extends Node3D
## Builds the same node tree on every peer (identical paths are required by
## MultiplayerSpawner and RPCs). Only the server decides; this scene just mirrors it.

const BOARDS := {"meadow": "res://boards/meadow/meadow_board.gd"}

var board: BoardGraph
var turns: TurnManager
var _pawns: Node3D
var _spawner: MultiplayerSpawner
var _hud: Hud
var _highlighted := PackedInt32Array()
var _corrupted := false


func _ready() -> void:
	add_child(PartyEnvironment.new())
	board = (load(BOARDS[NetworkManager.board_id]) as GDScript).new()
	board.name = "Board"
	add_child(board)
	GameState.build_from_lobby(board.start_id)

	_pawns = Node3D.new()
	_pawns.name = "Pawns"
	add_child(_pawns)
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "PawnSpawner"
	add_child(_spawner)
	_spawner.spawn_path = _spawner.get_path_to(_pawns)
	_spawner.spawn_function = _spawn_pawn

	turns = TurnManager.new()
	turns.name = "TurnManager"
	add_child(turns)
	turns.setup(board, _spawner, _pawns)

	_hud = Hud.new()
	add_child(_hud)
	_hud.roll_pressed.connect(func(): turns.request_roll.rpc_id(1))
	_hud.choice_picked.connect(func(v): turns.request_choice.rpc_id(1, v))
	EventBus.prompt.connect(_on_prompt)
	EventBus.pawn_moved.connect(func(_p, _s): _clear_highlights())
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.game_over.connect(_on_game_over)
	EventBus.stat_delta.connect(_on_stat_delta)
	NetworkManager.notify_scene_ready()


## Runs on every peer when the server calls spawner.spawn(data).
func _spawn_pawn(data: Dictionary) -> Node:
	var pawn := Pawn.new()
	pawn.name = "Pawn_%d" % data["pid"]
	pawn.setup(data["pid"])
	pawn.position = board.space_position(data["space"])
	return pawn


func _on_prompt(pid: int, kind: int, options: PackedInt32Array) -> void:
	_clear_highlights()
	if kind == TurnManager.Prompt.BRANCH:
		_highlighted = options
		for id in options:
			board.get_space(id).set_highlight(true)
	if _flag("--autoroll") and GameState.peer_of(pid) == NetworkManager.local_id():
		turns.request_choice.rpc_id(1, options[0])  # test flag: always the first option


func _clear_highlights() -> void:
	for id in _highlighted:
		board.get_space(id).set_highlight(false)
	_highlighted = PackedInt32Array()


func _on_turn_started(pid: int, round_no: int, _max: int) -> void:
	if _flag("--autoroll") and GameState.peer_of(pid) == NetworkManager.local_id():
		turns.request_roll.rpc_id(1)
	# Test flag: corrupt a client's local inventory once to prove desync detection heals it.
	if _flag("--corrupt") and round_no == 2 and not _corrupted and not multiplayer.is_server():
		_corrupted = true
		GameState.coins[0] += 7


func _pawn(pid: int) -> Pawn:
	return _pawns.get_node_or_null("Pawn_%d" % pid) as Pawn


func _on_stat_delta(pid: int, d_coins: int, d_stars: int) -> void:
	var pawn := _pawn(pid)
	if pawn == null:
		return
	if d_stars > 0:
		pawn.pop_text("+%d STAR" % d_stars, Color("ffd23d"))
		pawn.celebrate()
	elif d_coins != 0:
		pawn.pop_text("%+d" % d_coins, Color("ffd23d") if d_coins > 0 else Color("ff5d6c"))


func _on_game_over(order: PackedInt32Array) -> void:
	if _pawn(order[0]):
		_pawn(order[0]).celebrate()
	if _flag("--log"):
		print("[peer %d] GAME OVER order=%s coins=%s stars=%s" % [NetworkManager.local_id(), order, GameState.coins, GameState.stars])
	if _flag("--quit-on-end"):
		get_tree().quit()


func _flag(f: String) -> bool:
	return f in OS.get_cmdline_user_args()
