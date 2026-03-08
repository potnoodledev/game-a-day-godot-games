extends Node3D
## Cat Viewer — headless 3D cat renderer controlled externally via Bridge autoload.
## No UI or input handling — all customization comes from the HTML5 wrapper.

var cat_instance: Node3D
var anim_player: AnimationPlayer
var fur_shader_mat: ShaderMaterial
var body_meshes: Array[MeshInstance3D] = []
var eye_mesh_node: MeshInstance3D
var camera: Camera3D
var skeleton: Skeleton3D

# Orbit camera
var cam_distance := 1.8
var cam_angle_y := 0.0
var cam_angle_x := -5.0
var cam_target := Vector3(0.0, 0.55, 0)

# Auto-rotate turntable
var auto_rotate := false
var auto_rotate_speed := 20.0  # degrees per second

# Animation state
var anim_names: Array = []

# Bone scaling
var bone_scale_values := {
	"head_size": 0.5,
	"eye_size": 0.5,
	"eye_spacing": 0.5,
	"body_width": 0.5,
	"tail_size": 0.5,
}
var bone_custom_scales := {}

func _ready() -> void:
	process_priority = 100
	_setup_environment()
	_setup_camera()
	_setup_floor()
	_load_cat()
	_connect_bridge()
	# Apply defaults
	_apply_primary_color(Color(0.9, 0.55, 0.15))
	_apply_stripe_color(Color(0.4, 0.15, 0.05))
	_update_bone_scales("head_size", 0.5)

func _connect_bridge() -> void:
	if not Engine.has_singleton("Bridge") and not has_node("/root/Bridge"):
		print("[cat] No Bridge autoload found, running standalone")
		return
	var bridge = get_node("/root/Bridge")
	bridge.animation_changed.connect(_on_set_animation)
	bridge.primary_color_changed.connect(_apply_primary_color)
	bridge.stripe_color_changed.connect(_apply_stripe_color)
	bridge.eye_color_changed.connect(_apply_eye_color)
	bridge.bone_scale_changed.connect(_update_bone_scales)
	bridge.camera_changed.connect(_on_set_camera)
	bridge.auto_rotate_changed.connect(_on_set_auto_rotate)
	# Publish animation list to JS
	bridge.publish_animations(anim_names)
	print("[cat] Bridge connected")

# --- Environment ---

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.4, 0.6, 0.9)
	sky_mat.sky_horizon_color = Color(0.7, 0.8, 0.95)
	sky_mat.ground_bottom_color = Color(0.3, 0.25, 0.2)
	sky_mat.ground_horizon_color = Color(0.6, 0.55, 0.5)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	light.light_energy = 2.5
	light.light_color = Color(1.0, 0.95, 0.85)
	add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -60, 0)
	fill.light_energy = 0.8
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	_update_camera()

func _update_camera() -> void:
	if not camera:
		return
	var rad_y = deg_to_rad(cam_angle_y)
	var rad_x = deg_to_rad(cam_angle_x)
	var pos := Vector3(
		sin(rad_y) * cos(rad_x) * cam_distance,
		-sin(rad_x) * cam_distance,
		cos(rad_y) * cos(rad_x) * cam_distance
	)
	camera.position = cam_target + pos
	camera.look_at(cam_target)

func _setup_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(5, 5)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.3)
	mat.roughness = 0.9
	floor_mesh.material_override = mat
	add_child(floor_mesh)

# --- Cat Loading ---

func _load_cat() -> void:
	var cat_scene = load("res://cartoon_cat.gltf")
	if not cat_scene:
		print("[ERROR] Could not load cartoon_cat.gltf")
		return

	cat_instance = cat_scene.instantiate()
	cat_instance.name = "Cat"
	cat_instance.scale = Vector3(0.25, 0.25, 0.25)
	add_child(cat_instance)

	_setup_fur_shader(cat_instance)
	_remove_non_skinned_meshes(cat_instance)

	anim_player = _find_node_by_class(cat_instance, "AnimationPlayer")
	if anim_player:
		anim_names = Array(anim_player.get_animation_list())
		print("[cat] Found animations: ", anim_names)
		for anim_name in anim_names:
			var anim := anim_player.get_animation(anim_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
		# Default to first Cat_ animation or first available
		var start_anim := ""
		for n in anim_names:
			if n.begins_with("Cat_"):
				start_anim = n
				break
		if start_anim.is_empty() and anim_names.size() > 0:
			start_anim = anim_names[0]
		if not start_anim.is_empty():
			anim_player.play(start_anim)

	skeleton = _find_node_by_class(cat_instance, "Skeleton3D")
	if skeleton:
		print("[cat] Skeleton: ", skeleton.get_bone_count(), " bones")
	_find_eye_mesh(cat_instance)
	print("[cat] Cat loaded")

func _setup_fur_shader(root: Node) -> void:
	var shader = load("res://cat_fur_recolor.gdshader")
	fur_shader_mat = ShaderMaterial.new()
	fur_shader_mat.shader = shader
	_collect_body_meshes(root)
	if body_meshes.size() > 0:
		var first_mat = body_meshes[0].get_active_material(0)
		if first_mat is StandardMaterial3D and first_mat.albedo_texture:
			fur_shader_mat.set_shader_parameter("base_texture", first_mat.albedo_texture)
		for mesh in body_meshes:
			mesh.set_surface_override_material(0, fur_shader_mat)

func _collect_body_meshes(node: Node) -> void:
	if node is MeshInstance3D and node.get_parent() is Skeleton3D:
		var mat = node.get_active_material(0)
		if mat and mat.resource_name.contains("Cat_Body"):
			body_meshes.append(node)
	for child in node.get_children():
		_collect_body_meshes(child)

func _remove_non_skinned_meshes(node: Node) -> void:
	var to_remove: Array[Node] = []
	_collect_non_skinned(node, to_remove)
	for n in to_remove:
		n.get_parent().remove_child(n)
		n.queue_free()

func _collect_non_skinned(node: Node, out: Array[Node]) -> void:
	if node is MeshInstance3D and not (node.get_parent() is Skeleton3D):
		out.append(node)
		return
	for child in node.get_children():
		_collect_non_skinned(child, out)

func _find_eye_mesh(node: Node) -> void:
	if node is MeshInstance3D and node.get_parent() is Skeleton3D:
		var mat = node.get_active_material(0)
		if mat and mat.resource_name.contains("Cat_Eye"):
			eye_mesh_node = node
			var shader = load("res://cat_eye_recolor.gdshader")
			var shader_mat := ShaderMaterial.new()
			shader_mat.shader = shader
			if mat is StandardMaterial3D:
				var base_tex = mat.albedo_texture
				if base_tex:
					shader_mat.set_shader_parameter("base_texture", base_tex)
			node.set_surface_override_material(0, shader_mat)
			return
	for child in node.get_children():
		if eye_mesh_node:
			return
		_find_eye_mesh(child)

func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	if node.get_class() == class_name_str:
		return node
	for child in node.get_children():
		var result = _find_node_by_class(child, class_name_str)
		if result:
			return result
	return null

# --- External Commands ---

func _on_set_animation(anim_name: String) -> void:
	if not anim_player:
		return
	if anim_names.has(anim_name):
		anim_player.play(anim_name)
		print("[cat] Animation: ", anim_name)
	else:
		print("[cat] Unknown animation: ", anim_name)

func _apply_primary_color(color: Color) -> void:
	if fur_shader_mat:
		fur_shader_mat.set_shader_parameter("primary_color", Vector3(color.r, color.g, color.b))

func _apply_stripe_color(color: Color) -> void:
	if fur_shader_mat:
		fur_shader_mat.set_shader_parameter("secondary_color", Vector3(color.r, color.g, color.b))

func _apply_eye_color(color: Color) -> void:
	if not eye_mesh_node:
		return
	var mat = eye_mesh_node.get_surface_override_material(0)
	if mat is ShaderMaterial:
		mat.set_shader_parameter("iris_color", Vector3(color.r, color.g, color.b))

func _on_set_camera(distance: float, angle_y: float, angle_x: float) -> void:
	cam_distance = distance
	cam_angle_y = angle_y
	cam_angle_x = angle_x
	auto_rotate = false
	_update_camera()

func _on_set_auto_rotate(enabled: bool) -> void:
	auto_rotate = enabled

func _update_bone_scales(slider_name: String, value: float) -> void:
	bone_scale_values[slider_name] = value
	bone_custom_scales.clear()

	var head_v: float = bone_scale_values["head_size"]
	var eye_v: float = bone_scale_values["eye_size"]
	var body_v: float = bone_scale_values["body_width"]
	var tail_v: float = bone_scale_values["tail_size"]

	var head_s: float = lerp(0.75, 1.25, head_v)
	bone_custom_scales["Head_05"] = Vector3(head_s, head_s, head_s)

	var eye_s: float = lerp(0.6, 1.4, eye_v)
	bone_custom_scales["Aye_L_06"] = Vector3(eye_s, eye_s, eye_s)
	bone_custom_scales["Aye_R_021"] = Vector3(eye_s, eye_s, eye_s)

	var body_w: float = lerp(0.7, 1.3, body_v)
	bone_custom_scales["Bone2_02"] = Vector3(body_w, 1.0, body_w)
	bone_custom_scales["Bone3_03"] = Vector3(body_w, 1.0, body_w)

	var tail_s: float = lerp(0.0, 2.0, tail_v)
	bone_custom_scales["Tail_B1_040"] = Vector3(tail_s, tail_s, tail_s)

# --- Process ---

func _process(delta: float) -> void:
	# Auto-rotate turntable
	if auto_rotate:
		cam_angle_y += auto_rotate_speed * delta
		_update_camera()

	# Apply bone scale overrides on top of animation
	if not skeleton or bone_custom_scales.is_empty():
		return
	for bone_name in bone_custom_scales:
		var custom: Vector3 = bone_custom_scales[bone_name]
		if custom.is_equal_approx(Vector3.ONE):
			continue
		var idx := skeleton.find_bone(bone_name)
		if idx >= 0:
			var anim_scale := skeleton.get_bone_pose_scale(idx)
			skeleton.set_bone_pose_scale(idx, anim_scale * custom)

	var spacing_v: float = bone_scale_values["eye_spacing"]
	var spacing: float = lerp(0.8, 1.2, spacing_v)
	if not is_equal_approx(spacing, 1.0):
		for eye_bone in ["Aye_L_06", "Aye_R_021"]:
			var idx := skeleton.find_bone(eye_bone)
			if idx >= 0:
				var pos := skeleton.get_bone_pose_position(idx)
				pos.x *= spacing
				skeleton.set_bone_pose_position(idx, pos)
