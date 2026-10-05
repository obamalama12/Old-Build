class_name Pawn
extends Node3D
## Visual-only token. Never decides where it goes; it animates what the server says.

const HOP_TIME := 0.35
const MODEL_SCALE := 1.7
const MODELS: Array[String] = [
	"res://assets/kenney_mini_characters/character-male-a.glb",
	"res://assets/kenney_mini_characters/character-female-b.glb",
	"res://assets/kenney_mini_characters/character-male-d.glb",
	"res://assets/kenney_mini_characters/character-female-e.glb",
]

var pid := -1
var _body: Node3D     # offset per player so pawns sharing a space don't overlap
var _model: Node3D    # rotates to face travel direction
var _anim: AnimationPlayer


func setup(p: int) -> void:
	pid = p
	_body = Node3D.new()
	var a := TAU * p / 4.0
	_body.position = Vector3(cos(a), 0.15, sin(a)) * 0.38
	add_child(_body)

	var ring := MeshInstance3D.new()  # player-colored base so you can always tell who is who
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.42
	cyl.height = 0.06
	ring.mesh = cyl
	ring.material_override = Toon.glossy(GameState.color_of(p), 0.4)
	ring.position.y = 0.02
	_body.add_child(ring)
	Toon.add_outline(ring, 0.03)

	_model = Toon.load_model(MODELS[p % MODELS.size()])
	_model.scale = Vector3.ONE * MODEL_SCALE
	_model.position.y = 0.04
	_body.add_child(_model)
	Toon.add_outline(_model, 0.03, MODEL_SCALE)
	_anim = _model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for n in ["idle", "walk", "sprint"]:
		_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR

	var tag := Toon.label3d(GameState.name_of(p), 40, GameState.color_of(p).lightened(0.25))
	tag.position.y = 1.9
	_body.add_child(tag)


func _ready() -> void:
	_anim.play("idle")


func hop_along(points: Array[Vector3]) -> Tween:
	var tw := create_tween()
	tw.tween_callback(_anim.play.bind("sprint"))
	var from := position
	for to in points:
		var dir := to - from
		tw.tween_callback(_face.bind(dir))
		tw.tween_method(_hop_step.bind(from, to), 0.0, 1.0, HOP_TIME)
		from = to
	tw.tween_callback(_anim.play.bind("idle"))
	return tw


func celebrate() -> void:
	_anim.play("emote-yes")
	await _anim.animation_finished
	_anim.play("idle")


func pop_text(text: String, color: Color) -> void:
	var l := Toon.label3d(text, 72, color)
	l.position = Vector3(0, 2.3, 0)
	_body.add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", 3.6, 1.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)


func _face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() > 0.01:
		create_tween().tween_property(_model, "rotation:y", atan2(dir.x, dir.z), 0.12)


func _hop_step(t: float, a: Vector3, b: Vector3) -> void:
	position = a.lerp(b, t) + Vector3(0, sin(t * PI) * 0.6, 0)
