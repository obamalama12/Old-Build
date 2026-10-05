class_name BoardSpace
extends Node3D
## One node on the board graph. Ids are assigned by the board builder, so they are
## identical on server and clients; only ids ever cross the network.

enum Type { BLUE, RED, EVENT, STAR, START }

const TYPE_COLORS := {
	Type.BLUE: Color("3d7bff"),
	Type.RED: Color("ff4b4b"),
	Type.EVENT: Color("b45cff"),
	Type.STAR: Color("ffd22e"),
	Type.START: Color("4be37a"),
}

var id := -1
var type: Type = Type.BLUE
var next_ids := PackedInt32Array()


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.8
	cyl.bottom_radius = 0.8
	cyl.height = 0.2
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TYPE_COLORS[type]
	mat.roughness = 0.8
	mesh.material_override = mat
	add_child(mesh)


func set_highlight(on: bool) -> void:
	scale = Vector3.ONE * (1.45 if on else 1.0)
