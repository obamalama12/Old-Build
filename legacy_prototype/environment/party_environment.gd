class_name PartyEnvironment
extends Node3D
## Sky, light, camera, island and scenery. Purely cosmetic and identical on every peer.

const KIT := "res://assets/kenney_platformer_kit/"
const DECOR: Array[String] = ["tree", "tree-pine", "tree", "tree-pine-small", "rocks", "flowers-tall", "flowers", "mushrooms", "plant", "stones"]


func _ready() -> void:
	_sky_and_light()
	_island()
	_decor()
	var cam := Camera3D.new()
	cam.fov = 38
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 21, 16), Vector3(0, 0, 1))


func _sky_and_light() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("2f86ff")
	sky_mat.sky_horizon_color = Color("bde8ff")
	sky_mat.ground_horizon_color = Color("bde8ff")
	sky_mat.ground_bottom_color = Color("7ec8ff")
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.25
	env.adjustment_contrast = 1.08
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff0d0")
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 60.0
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)


func _island() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	water.mesh = plane
	water.position.y = -1.4
	water.material_override = Toon.glossy(Color("37b6ff"), 0.15)
	add_child(water)
	Toon.add_outline(_cylinder(23.0, 1.0, Color("9a6a3c"), -0.9), 0.08)  # dirt cliff
	_cylinder(22.6, 0.5, Color("7fe04a"), -0.4)                           # grass top


func _cylinder(radius: float, height: float, color: Color, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 0.94
	cyl.height = height
	cyl.radial_segments = 64
	mi.mesh = cyl
	mi.material_override = Toon.glossy(color, 0.9)
	mi.position.y = y
	add_child(mi)
	return mi


func _decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # fixed so the scenery matches on every peer
	for i in 60:
		var a := rng.randf() * TAU
		var r := rng.randf_range(12.5, 21.0)
		var name: String = DECOR[rng.randi() % DECOR.size()]
		var n := Toon.load_model(KIT + name + ".glb")
		var s := rng.randf_range(2.4, 3.4) if name.begins_with("tree") else rng.randf_range(2.0, 3.0)
		n.scale = Vector3.ONE * s
		n.position = Vector3(cos(a) * r, -0.15, sin(a) * r)
		n.rotation.y = rng.randf() * TAU
		add_child(n)
		Toon.add_outline(n, 0.04, s)
