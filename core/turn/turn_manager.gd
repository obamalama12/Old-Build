class_name TurnManager
extends Node
## Server-authoritative turn flow. Clients may only *request*; the server validates
## sender + state, rolls the dice, walks the board, and broadcasts the results.
## Clients never send a dice value or a destination, only a branch pick that must be
## one of the exits the server offered.

enum State { WAITING_PLAYERS, AWAIT_ROLL, MOVING, AWAIT_BRANCH, OVER }

const DICE_MAX := 10
const SPAWN_SETTLE := 0.5   # lets spawn packets land before the first turn RPC
const DICE_TIME := 0.8      # let clients show the roll before the pawn moves
const BOT_DELAY := 0.7
const BRANCH_TIMEOUT := 15.0

var state := State.WAITING_PLAYERS  # authoritative only on the server
var current_pid := -1
var round_no := 1
var _board: BoardGraph
var _spawner: MultiplayerSpawner
var _pawns_root: Node3D
var _rng := RandomNumberGenerator.new()
var _options := PackedInt32Array()
var _prompt_serial := 0
var _chosen := -1  # set by _resolve_branch; covers a pick made before we start awaiting

signal _branch_resolved(space_id: int)


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
		_net_game_over.rpc()
		return
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
	elif state == State.AWAIT_BRANCH:
		_resolve_branch(_options[0])


# --- client -> server ---------------------------------------------------------

## Every peer calls `request_roll.rpc_id(1)`. The host runs it locally (call_local).
@rpc("any_peer", "call_local", "reliable")
func request_roll() -> void:
	if _valid_request(State.AWAIT_ROLL):
		_do_roll()


@rpc("any_peer", "call_local", "reliable")
func request_branch(space_id: int) -> void:
	if _valid_request(State.AWAIT_BRANCH):
		_resolve_branch(space_id)


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
			nxt = await _await_branch(pid, exits)
		seg.append(nxt)
		cur = nxt
		left -= 1
	await _send_segment(pid, seg)
	_resolve_landing(pid, cur)
	_advance(pid)


func _send_segment(pid: int, seg: PackedInt32Array) -> void:
	_net_move.rpc(pid, seg)
	await get_tree().create_timer(seg.size() * Pawn.HOP_TIME + 0.2).timeout


func _await_branch(pid: int, exits: PackedInt32Array) -> int:
	state = State.AWAIT_BRANCH
	_options = exits
	_prompt_serial += 1
	_chosen = -1
	var serial := _prompt_serial
	_net_branch_prompt.rpc(pid, exits)
	var auto_pick: int = exits[_rng.randi() % exits.size()] if GameState.is_bot(pid) else exits[0]
	var wait := BOT_DELAY if GameState.is_bot(pid) else BRANCH_TIMEOUT
	get_tree().create_timer(wait).timeout.connect(func():
		if serial == _prompt_serial:  # ignore timers from earlier prompts
			_resolve_branch(auto_pick))
	if _chosen < 0:
		await _branch_resolved
	return _chosen


func _resolve_branch(space_id: int) -> void:
	if state != State.AWAIT_BRANCH or not _options.has(space_id):
		return
	state = State.MOVING
	_chosen = space_id
	_branch_resolved.emit(space_id)


func _resolve_landing(_pid: int, _space_id: int) -> void:
	pass  # Phase 3: SpaceEffect dispatch (coins, star, events)


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
func _net_branch_prompt(pid: int, options: PackedInt32Array) -> void:
	EventBus.branch_prompt.emit(pid, options)


@rpc("authority", "call_local", "reliable")
func _net_game_over() -> void:
	EventBus.game_over.emit()
