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
	_build_scenery()
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
	NetworkManager.notify_scene_ready()


## Runs on every peer when the server calls spawner.spawn(data).
func _spawn_pawn(data: Dictionary) -> Node:
	var pawn := Pawn.new()
	pawn.name = "Pawn_%d" % data["pid"]
	pawn.setup(data["pid"])
	pawn.position = board.space_position(data["space"])
	return pawn


func _build_scenery() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("3a8dff")
	sky_mat.sky_horizon_color = Color("bfe6ff")
	sky_mat.ground_horizon_color = Color("bfe6ff")
	sky_mat.ground_bottom_color = Color("6fbf5a")
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff2d6")
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 22, 17), Vector3.ZERO)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	ground.position.y = -0.15
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("7fd35a")
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)


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


func _on_game_over(order: PackedInt32Array) -> void:
	if _flag("--log"):
		print("[peer %d] GAME OVER order=%s coins=%s stars=%s" % [NetworkManager.local_id(), order, GameState.coins, GameState.stars])
	if _flag("--quit-on-end"):
		get_tree().quit()


func _flag(f: String) -> bool:
	return f in OS.get_cmdline_user_args()
