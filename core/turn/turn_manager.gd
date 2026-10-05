class_name TurnManager
extends Node
## Server-authoritative turn flow. Clients may only *request*; the server validates
## sender + state, rolls the dice, picks the path, and broadcasts the result.
## Clients never send a dice value or a destination.

enum State { WAITING_PLAYERS, AWAIT_ROLL, MOVING }

const DICE_MAX := 10
const SPAWN_SETTLE := 0.5  # lets spawn packets land before the first turn RPC

var state := State.WAITING_PLAYERS  # authoritative only on the server
var current_pid := -1
var _board: BoardGraph
var _spawner: MultiplayerSpawner
var _pawns_root: Node3D
var _rng := RandomNumberGenerator.new()


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


func _begin_turn(pid: int) -> void:
	var n := GameState.count()
	for i in n:  # skip players who dropped
		if GameState.is_connected_pid(pid):
			break
		pid = (pid + 1) % n
	current_pid = pid
	state = State.AWAIT_ROLL
	_net_turn_start.rpc(pid)


func _on_peer_left(peer_id: int) -> void:
	var pid := GameState.pid_of(peer_id)
	if pid == current_pid and state == State.AWAIT_ROLL:
		_begin_turn((pid + 1) % GameState.count())


# --- client -> server ---------------------------------------------------------

## Every peer calls `request_roll.rpc_id(1)`. Host runs it locally (call_local).
@rpc("any_peer", "call_local", "reliable")
func request_roll() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1  # local call on the host
	if state != State.AWAIT_ROLL or GameState.peer_of(current_pid) != sender:
		return  # not your turn / wrong phase: silently ignored
	state = State.MOVING
	var value := _rng.randi_range(1, DICE_MAX)
	var path := _board.walk(GameState.space_of[current_pid], value)
	var pid := current_pid
	_net_roll_and_move.rpc(pid, value, path)
	await get_tree().create_timer(path.size() * Pawn.HOP_TIME + 0.5).timeout
	_resolve_landing(pid, path[path.size() - 1])
	_begin_turn((pid + 1) % GameState.count())


func _resolve_landing(_pid: int, _space_id: int) -> void:
	pass  # Phase 3: SpaceEffect dispatch (coins, star, events)


# --- server -> everyone -------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _net_turn_start(pid: int) -> void:
	current_pid = pid
	EventBus.turn_started.emit(pid)


@rpc("authority", "call_local", "reliable")
func _net_roll_and_move(pid: int, value: int, path: PackedInt32Array) -> void:
	EventBus.dice_rolled.emit(pid, value)
	var pawn := _pawns_root.get_node_or_null("Pawn_%d" % pid) as Pawn
	var points: Array[Vector3] = []
	for id in path:
		points.append(_board.space_position(id))
	if pawn:
		pawn.hop_along(points)
	GameState.space_of[pid] = path[path.size() - 1]
	EventBus.pawn_moved.emit(pid, GameState.space_of[pid])
