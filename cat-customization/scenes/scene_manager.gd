extends Node
## Applies scene definitions to live environment nodes with smooth transitions.

const SceneRegistry = preload("res://scenes/scene_registry.gd")

var world_env: WorldEnvironment
var environment: Environment
var sky_material: ProceduralSkyMaterial
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var floor_mesh: MeshInstance3D
var particles_container: Node3D

var current_scene_id: String = ""
var _tween: Tween

# Cached procedural textures (generated once)
var _tex_soft_circle: ImageTexture
var _tex_star: ImageTexture
var _tex_petal: ImageTexture

const TRANSITION_DURATION := 0.8
const TEX_SIZE := 64

func setup(we: WorldEnvironment, key: DirectionalLight3D,
		fill: DirectionalLight3D, floor_node: MeshInstance3D) -> void:
	world_env = we
	environment = we.environment
	sky_material = environment.sky.sky_material as ProceduralSkyMaterial
	key_light = key
	fill_light = fill
	floor_mesh = floor_node
	particles_container = Node3D.new()
	particles_container.name = "Particles"
	get_parent().add_child(particles_container)
	_generate_textures()

# --- Procedural texture generation ---

func _generate_textures() -> void:
	_tex_soft_circle = _make_soft_circle()
	_tex_star = _make_star()
	_tex_petal = _make_petal()

func _make_soft_circle() -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(TEX_SIZE * 0.5, TEX_SIZE * 0.5)
	var radius := TEX_SIZE * 0.5
	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var t := clampf(1.0 - dist / radius, 0.0, 1.0)
			# Smooth falloff: pow gives a soft glow
			var alpha := t * t
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(img)

func _make_star() -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(TEX_SIZE * 0.5, TEX_SIZE * 0.5)
	var radius := TEX_SIZE * 0.5
	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var pos := Vector2(x + 0.5, y + 0.5) - center
			var dist := pos.length()
			if dist < 0.01:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
				continue
			# 4-point star: use min of horizontal and vertical distances
			var norm := pos / dist
			# Cross-shaped brightness: bright along axes, dim diagonally
			var ax := absf(norm.x)
			var ay := absf(norm.y)
			var cross := maxf(ax, ay)  # 1.0 on axes, ~0.7 diagonal
			var star_factor := cross * cross * cross  # sharpen the star shape
			var radial := clampf(1.0 - dist / radius, 0.0, 1.0)
			var alpha := radial * radial * star_factor
			# Add a soft core
			var core := clampf(1.0 - dist / (radius * 0.3), 0.0, 1.0)
			alpha = maxf(alpha, core * core)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(alpha, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _make_petal() -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(TEX_SIZE * 0.5, TEX_SIZE * 0.5)
	# Elongated ellipse: wider on X, narrower on Y
	var rx := TEX_SIZE * 0.5
	var ry := TEX_SIZE * 0.35
	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var dx := (x + 0.5 - center.x) / rx
			var dy := (y + 0.5 - center.y) / ry
			var dist := sqrt(dx * dx + dy * dy)
			var t := clampf(1.0 - dist, 0.0, 1.0)
			# Slightly asymmetric: shift brightness off-center
			var shift := clampf(1.0 - absf(dx - 0.15) * 1.5, 0.3, 1.0)
			var alpha := t * t * shift
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(img)

func _get_texture_for_type(particle_type: String) -> ImageTexture:
	match particle_type:
		"sparkles":
			return _tex_star
		"petals":
			return _tex_petal
		_:
			# snow, fireflies, embers all use soft circle
			return _tex_soft_circle

# --- Scene application ---

func apply_scene(scene_id: String, animate: bool = true) -> void:
	var data := SceneRegistry.get_scene(scene_id)
	current_scene_id = scene_id

	if _tween and _tween.is_valid():
		_tween.kill()

	var dur := TRANSITION_DURATION if animate else 0.0
	_apply_sky(data, dur)
	_apply_lighting(data, dur)
	_apply_floor(data)
	_apply_post_processing(data, dur)
	_apply_particles(data)

func _apply_sky(data: Dictionary, dur: float) -> void:
	if dur <= 0:
		sky_material.sky_top_color = data["sky_top_color"]
		sky_material.sky_horizon_color = data["sky_horizon_color"]
		sky_material.ground_bottom_color = data["ground_bottom_color"]
		sky_material.ground_horizon_color = data["ground_horizon_color"]
		return
	_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(sky_material, "sky_top_color", data["sky_top_color"], dur)
	_tween.tween_property(sky_material, "sky_horizon_color", data["sky_horizon_color"], dur)
	_tween.tween_property(sky_material, "ground_bottom_color", data["ground_bottom_color"], dur)
	_tween.tween_property(sky_material, "ground_horizon_color", data["ground_horizon_color"], dur)

func _apply_lighting(data: Dictionary, dur: float) -> void:
	if dur <= 0:
		key_light.light_color = data["key_light_color"]
		key_light.light_energy = data["key_light_energy"]
		key_light.rotation_degrees = data["key_light_rotation"]
		fill_light.light_color = data["fill_light_color"]
		fill_light.light_energy = data["fill_light_energy"]
		fill_light.rotation_degrees = data["fill_light_rotation"]
		environment.ambient_light_energy = data["ambient_energy"]
		return
	_tween.tween_property(key_light, "light_color", data["key_light_color"], dur)
	_tween.tween_property(key_light, "light_energy", data["key_light_energy"], dur)
	_tween.tween_property(key_light, "rotation_degrees", data["key_light_rotation"], dur)
	_tween.tween_property(fill_light, "light_color", data["fill_light_color"], dur)
	_tween.tween_property(fill_light, "light_energy", data["fill_light_energy"], dur)
	_tween.tween_property(fill_light, "rotation_degrees", data["fill_light_rotation"], dur)
	_tween.tween_property(environment, "ambient_light_energy", data["ambient_energy"], dur)

func _apply_floor(data: Dictionary) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data["floor_color"]
	mat.roughness = data["floor_roughness"]
	mat.metallic = data["floor_metallic"]
	floor_mesh.material_override = mat

func _apply_post_processing(data: Dictionary, dur: float) -> void:
	environment.ssao_enabled = data["ssao_enabled"]
	environment.glow_enabled = data["glow_enabled"]
	environment.fog_enabled = data["fog_enabled"]
	environment.tonemap_mode = data["tonemap_mode"] as Environment.ToneMapper
	environment.adjustment_enabled = data["adjustments_enabled"]
	environment.adjustment_saturation = data["adjustments_saturation"]

	if data["glow_enabled"]:
		environment.glow_intensity = data["glow_intensity"]
		environment.glow_hdr_threshold = data["glow_threshold"]
		environment.glow_bloom = data["glow_bloom"]

	if data["fog_enabled"]:
		environment.fog_light_color = data["fog_light_color"]
		if dur <= 0:
			environment.fog_density = data["fog_density"]
		else:
			_tween.tween_property(environment, "fog_density", data["fog_density"], dur)
	else:
		environment.fog_density = 0.0

func _apply_particles(data: Dictionary) -> void:
	for child in particles_container.get_children():
		child.queue_free()

	var configs: Array = data["particles"]
	for cfg in configs:
		_spawn_particles(cfg)

func _spawn_particles(cfg: Dictionary) -> void:
	var p := CPUParticles3D.new()
	p.emitting = true
	p.amount = cfg.get("count", 50)
	p.lifetime = cfg.get("lifetime", 3.0)
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.5

	# Position
	p.position = cfg.get("emission_offset", Vector3.ZERO)

	# Emission shape
	var shape: String = cfg.get("emission_shape", "sphere")
	match shape:
		"sphere":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = cfg.get("emission_radius", 2.0)
		"box":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = cfg.get("emission_extents", Vector3(1, 1, 1))
		"point":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT

	# Direction and velocity
	p.direction = cfg.get("direction", Vector3(0, -1, 0))
	p.spread = cfg.get("spread", 30.0)
	p.initial_velocity_min = cfg.get("velocity_min", 0.5)
	p.initial_velocity_max = cfg.get("velocity_max", 1.0)
	p.gravity = cfg.get("gravity", Vector3(0, -1, 0))

	# Color ramp
	var color_start: Color = cfg.get("color", Color.WHITE)
	var color_end: Color = cfg.get("color_end", Color(1, 1, 1, 0))
	var gradient := Gradient.new()
	gradient.set_color(0, color_start)
	gradient.set_color(1, color_end)
	p.color_ramp = gradient

	# Scale
	p.scale_amount_min = cfg.get("scale_min", 0.02)
	p.scale_amount_max = cfg.get("scale_max", 0.04)

	# Textured billboard quad
	var particle_type: String = cfg.get("type", "")
	var tex := _get_texture_for_type(particle_type)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.1, 0.1)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.albedo_texture = tex
	mesh.material = mat
	p.mesh = mesh

	particles_container.add_child(p)
