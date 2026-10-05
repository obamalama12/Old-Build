class_name BoardGraph
extends Node3D
## Base class for boards. Subclasses override `_build()` and call `add_space()`.
## Built deterministically in _ready() on every peer (never replicated node-by-node).

var spaces: Dictionary = {}  # int -> BoardSpace
var start_id := 0


func _ready() -> void:
	_build()
	var problems := validate()
	for p in problems:
		push_error("Board '%s': %s" % [name, p])
	_draw_links()


func _build() -> void:
	pass


func add_space(id: int, pos: Vector3, type: BoardSpace.Type, next: Array[int]) -> BoardSpace:
	var s := BoardSpace.new()
	s.id = id
	s.type = type
	s.next_ids = PackedInt32Array(next)
	s.name = "Space_%d" % id
	s.position = pos
	spaces[id] = s
	add_child(s)
	return s


func get_space(id: int) -> BoardSpace:
	return spaces[id]


func space_position(id: int) -> Vector3:
	return spaces[id].position


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if not spaces.has(start_id):
		out.append("start_id %d missing" % start_id)
	for id: int in spaces:
		var s: BoardSpace = spaces[id]
		if s.next_ids.is_empty():
			out.append("space %d has no exits" % id)
		for n in s.next_ids:
			if not spaces.has(n):
				out.append("space %d links to missing %d" % [id, n])
	return out


func _draw_links() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("f4efe2")
	for id: int in spaces:
		var a: Vector3 = spaces[id].position
		for n in spaces[id].next_ids:
			var b: Vector3 = spaces[n].position
			if a.is_equal_approx(b):
				continue
			var box := BoxMesh.new()
			box.size = Vector3(0.25, 0.05, a.distance_to(b))
			var m := MeshInstance3D.new()
			m.mesh = box
			m.material_override = mat
			add_child(m)
			m.look_at_from_position((a + b) / 2.0 - Vector3(0, 0.08, 0), b - Vector3(0, 0.08, 0), Vector3.UP)
