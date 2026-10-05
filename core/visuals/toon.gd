class_name Toon
extends RefCounted
## Shared look helpers: outline overlay and model loading.

const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")
const FONT_PATH := "res://assets/kenney_ui/Font/Kenney Future.ttf"
const INK := Color("1b1340")

static var _outline_cache: Dictionary = {}


## `width` is in the mesh's local units; divide by the node's scale to get a world-size edge.
static func outline_material(width: float) -> ShaderMaterial:
	var key := snappedf(width, 0.0001)
	if not _outline_cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = OUTLINE_SHADER
		m.set_shader_parameter("width", width)
		_outline_cache[key] = m
	return _outline_cache[key]


static func add_outline(root: Node, world_width: float = 0.035, node_scale: float = 1.0) -> void:
	var mat := outline_material(world_width / maxf(node_scale, 0.001))
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = mat


static func load_model(path: String) -> Node3D:
	return (load(path) as PackedScene).instantiate() as Node3D


static func font() -> Font:
	return load(FONT_PATH) as Font


static func glossy(color: Color, roughness: float = 0.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic_specular = 0.7
	return m


static func label3d(text: String, size: int, color: Color, flat: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font()
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_modulate = INK
	l.outline_size = size / 3
	if flat:
		l.rotation_degrees.x = -90
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
	return l
