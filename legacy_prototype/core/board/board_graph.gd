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


## Dotted trail between linked spaces.
func _draw_links() -> void:
	var dot := SphereMesh.new()
	dot.radius = 0.14
	dot.height = 0.28
	dot.radial_segments = 12
	dot.rings = 6
	dot.material = Toon.glossy(Color("fff6dc"), 0.5)
	var xforms: Array[Transform3D] = []
	for id: int in spaces:
		var a: Vector3 = spaces[id].position
		for n in spaces[id].next_ids:
			var b: Vector3 = spaces[n].position
			var len := a.distance_to(b)
			var count := maxi(int(len / 0.9) - 1, 1)
			for i in count:
				var t := (i + 1.0) / (count + 1.0)
				xforms.append(Transform3D(Basis.from_scale(Vector3(1, 0.35, 1)), a.lerp(b, t) + Vector3(0, 0.02, 0)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dot
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	add_child(inst)
