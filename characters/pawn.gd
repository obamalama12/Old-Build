class_name Pawn
extends Node3D
## Visual-only token. Never decides where it goes; it animates what the server says.

const HOP_TIME := 0.35

var pid := -1


func setup(p: int) -> void:
	pid = p
	var mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.2
	mesh.mesh = cap
	mesh.position.y = 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GameState.color_of(p)
	mat.roughness = 0.7
	mesh.material_override = mat
	add_child(mesh)


func hop_along(points: Array[Vector3]) -> Tween:
	var tw := create_tween()
	var from := position
	for to in points:
		tw.tween_method(_hop_step.bind(from, to), 0.0, 1.0, HOP_TIME)
		from = to
	return tw


func _hop_step(t: float, a: Vector3, b: Vector3) -> void:
	position = a.lerp(b, t) + Vector3(0, sin(t * PI) * 0.6, 0)
