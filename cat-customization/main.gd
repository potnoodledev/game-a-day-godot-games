extends Node3D
## Cat Viewer — headless 3D cat renderer controlled externally via Bridge autoload.
## No UI or input handling — all customization comes from the HTML5 wrapper.

const SceneRegistryScript = preload("res://scenes/scene_registry.gd")
const SceneManagerScript = preload("res://scenes/scene_manager.gd")

var cat_instance: Node3D
var anim_player: AnimationPlayer
var fur_shader_mat: ShaderMaterial
var body_meshes: Array[MeshInstance3D] = []
var eye_mesh_node: MeshInstance3D
var camera: Camera3D
var skeleton: Skeleton3D

# Weapons
var sword_node: Node3D  # Parent Node3D containing the sword mesh
var gun_node: Node3D    # Parent Node3D containing the gun mesh
var current_weapon: String = "none"  # "none", "sword", "gun"

# Hats
var hat_attachment: BoneAttachment3D
var current_hat_node: Node3D
var current_hat: String = "none"
var hat_registry: Dictionary = {}
var hat_ids: Array = []

# Environment nodes (stored for SceneManager)
var world_env_node: WorldEnvironment
var key_light_node: DirectionalLight3D
var fill_light_node: DirectionalLight3D
var floor_mesh_node: MeshInstance3D
var scene_manager: Node  # SceneManager instance

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
	_setup_scene_manager()
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
	bridge.scene_changed.connect(_on_set_scene)
	bridge.weapon_changed.connect(_on_set_weapon)
	bridge.hat_changed.connect(_on_set_hat)
	bridge.camera_target_changed.connect(_on_set_camera_target)
	bridge.hat_transform_changed.connect(_on_set_hat_transform)
	# Publish lists to JS
	bridge.publish_animations(anim_names)
	bridge.publish_scenes(SceneRegistryScript.get_scene_ids())
	bridge.publish_hats(hat_ids)
	print("[cat] Bridge connected")

# --- Environment ---

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_env_node = WorldEnvironment.new()
	world_env_node.environment = env
	add_child(world_env_node)

	key_light_node = DirectionalLight3D.new()
	key_light_node.shadow_enabled = true
	add_child(key_light_node)

	fill_light_node = DirectionalLight3D.new()
	add_child(fill_light_node)

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
	floor_mesh_node = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(5, 5)
	floor_mesh_node.mesh = plane
	add_child(floor_mesh_node)

func _setup_scene_manager() -> void:
	scene_manager = SceneManagerScript.new()
	scene_manager.name = "SceneManager"
	add_child(scene_manager)
	scene_manager.setup(world_env_node, key_light_node, fill_light_node, floor_mesh_node)
	scene_manager.apply_scene("default_studio", false)

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
	_find_weapon_nodes(cat_instance)
	_remove_non_skinned_meshes(cat_instance)
	_load_hat_registry()

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
		_setup_hat_attachment()
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

func _find_weapon_nodes(root: Node) -> void:
	sword_node = _find_node_by_name(root, "Weapon_Sword")
	gun_node = _find_node_by_name(root, "Weapon_LapaGun")
	if sword_node:
		sword_node.visible = false
		print("[cat] Found sword: ", sword_node.get_path())
	if gun_node:
		gun_node.visible = false
		print("[cat] Found gun: ", gun_node.get_path())

func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var result = _find_node_by_name(child, target_name)
		if result:
			return result
	return null

func _remove_non_skinned_meshes(node: Node) -> void:
	var to_remove: Array[Node] = []
	_collect_non_skinned(node, to_remove)
	for n in to_remove:
		n.get_parent().remove_child(n)
		n.queue_free()

func _is_under_bone_attachment(node: Node) -> bool:
	var current = node.get_parent()
	while current:
		if current is BoneAttachment3D:
			return true
		if current is Skeleton3D:
			return false
		current = current.get_parent()
	return false

func _collect_non_skinned(node: Node, out: Array[Node]) -> void:
	if node is MeshInstance3D and not (node.get_parent() is Skeleton3D):
		if not _is_under_bone_attachment(node):
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

# --- Hats ---

func _load_hat_registry() -> void:
	var path := "res://hats/hat_registry.json"
	if not FileAccess.file_exists(path):
		print("[cat] No hat registry found")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.parse_string(file.get_as_text())
	if json is Dictionary:
		hat_registry = json
		hat_ids = ["none"] + Array(hat_registry.keys())
		print("[cat] Loaded ", hat_registry.size(), " hats")

func _setup_hat_attachment() -> void:
	if not skeleton:
		return
	var head_idx := skeleton.find_bone("Head_05")
	if head_idx < 0:
		print("[cat] Head_05 bone not found")
		return
	hat_attachment = BoneAttachment3D.new()
	hat_attachment.bone_name = "Head_05"
	skeleton.add_child(hat_attachment)
	print("[cat] Hat attachment ready on Head_05")

func _on_set_hat(hat_id: String) -> void:
	if hat_id == current_hat:
		return
	# Remove current hat
	if current_hat_node:
		current_hat_node.queue_free()
		current_hat_node = null
	current_hat = hat_id

	if hat_id == "none" or not hat_registry.has(hat_id):
		if hat_id != "none":
			print("[cat] Unknown hat: ", hat_id)
		return

	var info: Dictionary = hat_registry[hat_id]
	var glb_path = "res://hats/" + str(info["file"])
	var scene = load(glb_path)
	if not scene:
		print("[cat] Could not load hat: ", glb_path)
		return

	current_hat_node = scene.instantiate()

	# Apply offset
	var offset = info.get("offset", [0, 0, 0])
	current_hat_node.position = Vector3(offset[0], offset[1], offset[2])

	# Apply rotation (degrees)
	var rot = info.get("rotation", [0, 0, 0])
	current_hat_node.rotation_degrees = Vector3(rot[0], rot[1], rot[2])

	# Apply scale
	var scl = info.get("scale", [1, 1, 1])
	current_hat_node.scale = Vector3(scl[0], scl[1], scl[2])

	if not hat_attachment:
		print("[cat] No hat attachment point")
		current_hat_node.queue_free()
		current_hat_node = null
		return
	hat_attachment.add_child(current_hat_node)
	print("[cat] Hat: ", hat_id)

# --- External Commands ---

func _on_set_animation(anim_name: String) -> void:
	if not anim_player:
		return
	if anim_names.has(anim_name):
		anim_player.play(anim_name)
		_auto_weapon_for_animation(anim_name)
		print("[cat] Animation: ", anim_name)
	else:
		print("[cat] Unknown animation: ", anim_name)

func _auto_weapon_for_animation(anim_name: String) -> void:
	if anim_name.begins_with("Sword_"):
		_apply_weapon("sword")
	elif anim_name.begins_with("Pistol_"):
		_apply_weapon("gun")
	elif anim_name.begins_with("Arm_"):
		_apply_weapon("none")
	# Cat_* and Idle_* animations: don't change weapon (let manual setting persist)

func _on_set_weapon(weapon_id: String) -> void:
	_apply_weapon(weapon_id)
	print("[cat] Weapon: ", weapon_id)

func _apply_weapon(weapon_id: String) -> void:
	current_weapon = weapon_id
	if sword_node:
		sword_node.visible = (weapon_id == "sword")
	if gun_node:
		gun_node.visible = (weapon_id == "gun")

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

func _on_set_scene(scene_id: String) -> void:
	if scene_manager:
		scene_manager.apply_scene(scene_id)
		print("[cat] Scene: ", scene_id)

func _on_set_camera(distance: float, angle_y: float, angle_x: float) -> void:
	cam_distance = distance
	cam_angle_y = angle_y
	cam_angle_x = angle_x
	auto_rotate = false
	_update_camera()

func _on_set_hat_transform(offset_y: float, offset_z: float, rotation_y: float, hat_scale: float) -> void:
	if not current_hat_node:
		return
	current_hat_node.position = Vector3(0.0, offset_y, offset_z)
	current_hat_node.rotation_degrees = Vector3(0.0, rotation_y, 0.0)
	current_hat_node.scale = Vector3(hat_scale, hat_scale, hat_scale)
	print("[hat] offset_y=", offset_y, " offset_z=", offset_z, " rot_y=", rotation_y, " scale=", hat_scale)

func _on_set_camera_target(x: float, y: float, z: float) -> void:
	cam_target = Vector3(x, y, z)
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
