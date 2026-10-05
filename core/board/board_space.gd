class_name BoardSpace
extends Node3D
## One node on the board graph. Ids are assigned by the board builder, so they are
## identical on server and clients; only ids ever cross the network.

enum Type { BLUE, RED, EVENT, STAR, START }

const TYPE_COLORS := {
	Type.BLUE: Color("2f7cff"),
	Type.RED: Color("ff3d4f"),
	Type.EVENT: Color("a855ff"),
	Type.STAR: Color("ffc61a"),
	Type.START: Color("22d36b"),
}
const KIT := "res://assets/kenney_platformer_kit/"

var id := -1
var type: Type = Type.BLUE
var next_ids := PackedInt32Array()
var _star: Node3D


func _ready() -> void:
	var base := TYPE_COLORS[type] as Color
	_disc(0.9, 0.3, base.darkened(0.25), 0.0)           # chunky rim
	_disc(0.68, 0.32, base.lightened(0.15), 0.0)         # glossy inner face
	Toon.add_outline(get_child(0), 0.04)
	match type:
		Type.BLUE:
			_label("+3", Color.WHITE)
		Type.RED:
			_label("-3", Color.WHITE)
		Type.EVENT:
			_label("?", Color.WHITE)
		Type.START:
			_prop("flag", 1.8, Vector3(0, 0.15, 0))
		Type.STAR:
			_star = _prop("star", 3.0, Vector3(0, 1.0, 0))


func _process(delta: float) -> void:
	if _star:
		_star.rotate_y(delta * 2.0)
		_star.position.y = 1.0 + sin(Time.get_ticks_msec() / 400.0) * 0.12


func set_highlight(on: bool) -> void:
	scale = Vector3.ONE * (1.35 if on else 1.0)


func _disc(radius: float, height: float, color: Color, y: float) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 32
	mi.mesh = cyl
	mi.material_override = Toon.glossy(color, 0.25)
	mi.position.y = y
	add_child(mi)


func _label(text: String, color: Color) -> void:
	var l := Toon.label3d(text, 72, color, true)
	l.position.y = 0.2
	add_child(l)


func _prop(model: String, s: float, pos: Vector3) -> Node3D:
	var n := Toon.load_model(KIT + model + ".glb")
	n.scale = Vector3.ONE * s
	n.position = pos
	add_child(n)
	Toon.add_outline(n, 0.035, s)
	return n
