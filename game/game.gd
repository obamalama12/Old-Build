extends Node3D
## Builds the same node tree on every peer (identical paths are required by
## MultiplayerSpawner and RPCs). Only the server decides; this scene just mirrors it.

const BOARDS := {"meadow": "res://boards/meadow/meadow_board.gd"}

var board: BoardGraph
var turns: TurnManager
var _pawns: Node3D
var _spawner: MultiplayerSpawner
var _turn_label: Label
var _dice_label: Label
var _roll_btn: Button


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

	_build_hud()
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.dice_rolled.connect(_on_dice_rolled)
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


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var box := VBoxContainer.new()
	box.position = Vector2(20, 16)
	layer.add_child(box)
	_turn_label = Label.new()
	_turn_label.text = "Waiting for players..."
	_dice_label = Label.new()
	_roll_btn = Button.new()
	_roll_btn.text = "Roll"
	_roll_btn.disabled = true
	_roll_btn.pressed.connect(_on_roll_pressed)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(func(): NetworkManager.leave())
	for c in [_turn_label, _dice_label, _roll_btn, leave]:
		box.add_child(c)


func _on_roll_pressed() -> void:
	_roll_btn.disabled = true
	turns.request_roll.rpc_id(1)


func _on_turn_started(pid: int) -> void:
	_turn_label.text = "%s's turn" % GameState.name_of(pid)
	_roll_btn.disabled = GameState.peer_of(pid) != NetworkManager.local_id()
	if "--autoroll" in OS.get_cmdline_user_args() and not _roll_btn.disabled:
		_on_roll_pressed()  # test flag: bots-by-flag for headless smoke tests


func _on_dice_rolled(pid: int, value: int) -> void:
	_dice_label.text = "%s rolled %d" % [GameState.name_of(pid), value]
	if "--log" in OS.get_cmdline_user_args():
		print("[peer %d] %s" % [NetworkManager.local_id(), _dice_label.text])
	_roll_btn.disabled = true
