class_name TurnManager
extends Node
## Server-authoritative turn flow. Clients may only *request*; the server validates
## sender + state, rolls the dice, walks the board, and broadcasts the results.
## Clients never send a dice value or a destination, only a branch pick that must be
## one of the exits the server offered.

enum State { WAITING_PLAYERS, AWAIT_ROLL, MOVING, AWAIT_CHOICE, OVER }
enum Prompt { BRANCH, STAR }

const DICE_MAX := 10
const SPAWN_SETTLE := 0.5   # lets spawn packets land before the first turn RPC
const DICE_TIME := 0.8      # let clients show the roll before the pawn moves
const BOT_DELAY := 0.7
const CHOICE_TIMEOUT := 15.0
const EFFECT_TIME := 0.7

var state := State.WAITING_PLAYERS  # authoritative only on the server
var current_pid := -1
var round_no := 1
var _board: BoardGraph
var _spawner: MultiplayerSpawner
var _pawns_root: Node3D
var _rng := RandomNumberGenerator.new()
var _options := PackedInt32Array()
var _prompt_serial := 0
var _chosen := -1       # set by _resolve_choice; covers a pick made before we start awaiting
var _default_pick := 0  # used if the player drops while a prompt is open

signal _choice_resolved(value: int)


func setup(board: BoardGraph, spawner: MultiplayerSpawner, pawns_root: Node3D) -> void:
	_board = board
	_spawner = spawner
	_pawns_root = pawns_root
	if multiplayer.is_server():
		_rng.randomize()
		NetworkManager.peer_ready.connect(func(_id): _try_begin())
		NetworkManager.peer_left.connect(_on_peer_left)


func _try_begin() -> void:
	if state == State.WAITING_PLAYERS and NetworkManager.all_ready():
		state = State.MOVING  # block re-entry while spawning
		for pid in GameState.count():
			_spawner.spawn({"pid": pid, "space": _board.start_id})
		await get_tree().create_timer(SPAWN_SETTLE).timeout
		_begin_turn(0)


func _advance(from_pid: int) -> void:
	var n := GameState.count()
	var pid := from_pid
	for i in n:
		pid = (pid + 1) % n
		if pid == 0:
			round_no += 1
		if GameState.is_connected_pid(pid):
			break
	if round_no > NetworkManager.max_rounds:
		state = State.OVER
		_net_checksum.rpc(GameState.stats_checksum())
		_net_game_over.rpc(GameState.standings())
		return
	_net_checksum.rpc(GameState.stats_checksum())
	_begin_turn(pid)


func _begin_turn(pid: int) -> void:
	current_pid = pid
	state = State.AWAIT_ROLL
	_net_turn_start.rpc(pid, round_no, NetworkManager.max_rounds)
	if GameState.is_bot(pid):
		await get_tree().create_timer(BOT_DELAY).timeout
		if state == State.AWAIT_ROLL and current_pid == pid:
			_do_roll()


func _on_peer_left(peer_id: int) -> void:
	var pid := GameState.pid_of(peer_id)
	if pid != current_pid:
		return
	if state == State.AWAIT_ROLL:
		_advance(pid)
	elif state == State.AWAIT_CHOICE:
		_resolve_choice(_default_pick)


# --- client -> server ---------------------------------------------------------

## Every peer calls `request_roll.rpc_id(1)`. The host runs it locally (call_local).
@rpc("any_peer", "call_local", "reliable")
func request_roll() -> void:
	if _valid_request(State.AWAIT_ROLL):
		_do_roll()


## Answer to the open prompt (branch exit id, or 1/0 for buy/skip the star).
@rpc("any_peer", "call_local", "reliable")
func request_choice(value: int) -> void:
	if _valid_request(State.AWAIT_CHOICE):
		_resolve_choice(value)


## A client whose inventory checksum drifted asks for the full state.
@rpc("any_peer", "reliable")
func request_resync() -> void:
	if multiplayer.is_server() and state != State.WAITING_PLAYERS:
		_net_stats.rpc_id(multiplayer.get_remote_sender_id(), GameState.coins, GameState.stars)


## True only on the server, for the current player's own peer, in the expected state.
func _valid_request(expected: State) -> bool:
	if not multiplayer.is_server():
		return false
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1  # local call on the host
	return state == expected and GameState.peer_of(current_pid) == sender


# --- server logic -------------------------------------------------------------

func _do_roll() -> void:
	state = State.MOVING
	var pid := current_pid
	var value := _rng.randi_range(1, DICE_MAX)
	_net_dice.rpc(pid, value)
	await get_tree().create_timer(DICE_TIME).timeout

	var cur: int = GameState.space_of[pid]
	var seg := PackedInt32Array()
	var left := value
	while left > 0:
		var exits := _board.get_space(cur).next_ids
		var nxt := exits[0]
		if exits.size() > 1:
			if not seg.is_empty():  # walk up to the fork first, then ask
				await _send_segment(pid, seg)
				seg = PackedInt32Array()
			var bot_pick: int = exits[_rng.randi() % exits.size()]
			nxt = await _await_choice(pid, Prompt.BRANCH, exits, bot_pick, exits[0])
		seg.append(nxt)
		cur = nxt
		left -= 1
		# Passing or landing on the star space offers a purchase.
		if _board.get_space(cur).type == BoardSpace.Type.STAR and GameState.coins[pid] >= SpaceEffects.STAR_COST:
			await _send_segment(pid, seg)
			seg = PackedInt32Array()
			var buy := await _await_choice(pid, Prompt.STAR, PackedInt32Array([1, 0]), 1, 0)
			if buy == 1:
				_apply([SpaceEffects.star_purchase(pid)])
				await get_tree().create_timer(EFFECT_TIME).timeout
	if not seg.is_empty():
		await _send_segment(pid, seg)
	await _resolve_landing(pid, cur)
	_advance(pid)


func _send_segment(pid: int, seg: PackedInt32Array) -> void:
	_net_move.rpc(pid, seg)
	await get_tree().create_timer(seg.size() * Pawn.HOP_TIME + 0.2).timeout


func _await_choice(pid: int, kind: Prompt, options: PackedInt32Array, bot_pick: int, timeout_pick: int) -> int:
	state = State.AWAIT_CHOICE
	_options = options
	_prompt_serial += 1
	_chosen = -1
	var serial := _prompt_serial
	var bot := GameState.is_bot(pid)
	_default_pick = bot_pick if bot else timeout_pick
	_net_prompt.rpc(pid, kind, options)
	var auto_pick := _default_pick
	get_tree().create_timer(BOT_DELAY if bot else CHOICE_TIMEOUT).timeout.connect(func():
		if serial == _prompt_serial:  # ignore timers from earlier prompts
			_resolve_choice(auto_pick))
	if _chosen < 0:
		await _choice_resolved
	return _chosen


func _resolve_choice(value: int) -> void:
	if state != State.AWAIT_CHOICE or not _options.has(value):
		return
	state = State.MOVING
	_chosen = value
	_choice_resolved.emit(value)


func _resolve_landing(pid: int, space_id: int) -> void:
	var changes := SpaceEffects.resolve(_board.get_space(space_id).type, pid, _rng)
	if changes.is_empty():
		return
	_apply(changes)
	await get_tree().create_timer(EFFECT_TIME).timeout


## Server only: clamp so coins never go negative, then replicate each change.
func _apply(changes: Array[Dictionary]) -> void:
	for c in changes:
		var pid: int = c["pid"]
		var dc: int = maxi(c["dc"], -GameState.coins[pid])
		_net_delta.rpc(pid, dc, c["ds"], c["msg"])


# --- server -> everyone -------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _net_turn_start(pid: int, round_number: int, max_rounds: int) -> void:
	current_pid = pid
	EventBus.turn_started.emit(pid, round_number, max_rounds)


@rpc("authority", "call_local", "reliable")
func _net_dice(pid: int, value: int) -> void:
	EventBus.dice_rolled.emit(pid, value)


@rpc("authority", "call_local", "reliable")
func _net_move(pid: int, path: PackedInt32Array) -> void:
	var pawn := _pawns_root.get_node_or_null("Pawn_%d" % pid) as Pawn
	var points: Array[Vector3] = []
	for id in path:
		points.append(_board.space_position(id))
	if pawn:
		pawn.hop_along(points)
	GameState.space_of[pid] = path[path.size() - 1]
	EventBus.pawn_moved.emit(pid, GameState.space_of[pid])


@rpc("authority", "call_local", "reliable")
func _net_prompt(pid: int, kind: int, options: PackedInt32Array) -> void:
	EventBus.prompt.emit(pid, kind, options)


## Incremental inventory change; applied identically on every peer.
@rpc("authority", "call_local", "reliable")
func _net_delta(pid: int, d_coins: int, d_stars: int, msg: String) -> void:
	GameState.apply_delta(pid, d_coins, d_stars)
	if msg != "":
		EventBus.log_message.emit(msg)
	EventBus.stats_changed.emit()


## Full inventory snapshot, sent only to heal a detected desync.
@rpc("authority", "reliable")
func _net_stats(new_coins: PackedInt32Array, new_stars: PackedInt32Array) -> void:
	GameState.coins = new_coins
	GameState.stars = new_stars
	EventBus.stats_changed.emit()


## Inventory validation: clients compare the server's checksum with their own state.
@rpc("authority", "reliable")
func _net_checksum(server_sum: int) -> void:
	if server_sum != GameState.stats_checksum():
		push_warning("DESYNC on peer %d: inventory mismatch, requesting resync" % multiplayer.get_unique_id())
		request_resync.rpc_id(1)


@rpc("authority", "call_local", "reliable")
func _net_game_over(order: PackedInt32Array) -> void:
	EventBus.game_over.emit(order)
