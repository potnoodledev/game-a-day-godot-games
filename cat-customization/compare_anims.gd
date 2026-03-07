extends Node3D

## Side-by-side animation comparison viewer
## 3 cats with per-model animation dropdowns
## Controls: drag to rotate, scroll to zoom

var models: Array[Dictionary] = []
var camera: Camera3D
var cam_distance := 3.0
var cam_angle_y := 0.0
var cam_angle_x := -20.0
var cam_target := Vector3(0, 0.2, 0)
var ui_container: Control

# Model configs: [path, offset_x, scale_vec, rotation_y_deg, display_name]
var model_configs := [
	["res://cat.gltf", -1.6, Vector3(0.015, 0.015, 0.015), -90.0, "Our Cat"],
	["res://somali_cat.gltf", -0.8, Vector3(0.12, 0.12, 0.12), 180.0, "Somali Cat"],
	["res://black_cat.gltf", 0.0, Vector3(0.15, 0.10, 0.15), 0.0, "Black Cat"],
	["res://cartoon_cat.gltf", 0.8, Vector3(0.25, 0.25, 0.25), 0.0, "Cartoon Cat"],
	["res://little_cat.gltf", 1.6, Vector3(0.45, 0.45, 0.45), 0.0, "Little Cat"],
]

var _ground_snap_frame := 0

func _ready() -> void:
	_setup_environment()
	_setup_camera()
	_setup_floor()
	for cfg in model_configs:
		_load_model(cfg[0], cfg[1], cfg[2], cfg[3], cfg[4])
	_setup_ui()
	# Play a good starting animation for each model
	for m in models:
		if m["anim_names"].size() > 0:
			var start_idx := 0
			# Try to start on an idle animation
			for i in range(m["anim_names"].size()):
				var aname: String = m["anim_names"][i].to_lower()
				if aname.find("idle") >= 0:
					start_idx = i
					break
			m["current_anim"] = start_idx
			_play_model_anim(m, start_idx)
	# Remove non-skinned meshes immediately
	for m in models:
		_remove_non_skinned_meshes(m["instance"])

func _process(_delta: float) -> void:
	# Wait a few frames for animations to deform the skeleton, then snap
	if _ground_snap_frame >= 0:
		_ground_snap_frame += 1
		if _ground_snap_frame == 3:
			_ground_snap_frame = -1
			for m in models:
				_snap_to_ground(m)

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.7)
	sky_mat.sky_horizon_color = Color(0.5, 0.6, 0.75)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	light.light_energy = 2.5
	add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -60, 0)
	fill.light_energy = 0.8
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
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.33, 0.32)
	mat.roughness = 0.95
	floor_mesh.material_override = mat
	add_child(floor_mesh)

func _load_model(path: String, offset_x: float, scale_vec: Vector3, rot_y_deg: float, display_name: String) -> void:
	var scene = load(path)
	if not scene:
		print("[compare] Could not load ", path)
		return

	# Pivot node sits on the floor at the X offset
	# The model is a child — we shift it down so its feet touch Y=0 on the pivot
	var pivot := Node3D.new()
	pivot.name = display_name.replace(" ", "_") + "_Pivot"
	pivot.position = Vector3(offset_x, 0, 0)
	add_child(pivot)

	var instance: Node3D = scene.instantiate()
	instance.scale = scale_vec
	instance.rotation_degrees.y = rot_y_deg
	pivot.add_child(instance)

	# Apply a basic material to our cat so it's not white
	if display_name == "Our Cat":
		var mesh: MeshInstance3D = _find_node_by_class(instance, "MeshInstance3D")
		if mesh:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.9, 0.6, 0.25)
			mat.roughness = 0.8
			mesh.material_override = mat

	var ap: AnimationPlayer = _find_node_by_class(instance, "AnimationPlayer")
	var anim_names: Array = []
	if ap:
		anim_names = Array(ap.get_animation_list())
		for anim_name in anim_names:
			var anim := ap.get_animation(anim_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
		print("[compare] ", display_name, " animations: ", anim_names)

	models.append({
		"instance": instance,
		"pivot": pivot,
		"anim_player": ap,
		"anim_names": anim_names,
		"name": display_name,
		"current_anim": 0,
		"anim_label": null,  # set in _setup_ui
	})

func _snap_to_ground(m: Dictionary) -> void:
	var instance: Node3D = m["instance"]
	var pivot: Node3D = m["pivot"]
	# Use skeleton bone positions to find the lowest point (more accurate for skinned meshes)
	var skel: Skeleton3D = _find_node_by_class(instance, "Skeleton3D")
	if skel:
		var lowest_y := 9999.0
		for bone_idx in range(skel.get_bone_count()):
			var bone_global := skel.global_transform * skel.get_bone_global_pose(bone_idx)
			if bone_global.origin.y < lowest_y:
				lowest_y = bone_global.origin.y
		instance.position.y -= lowest_y - pivot.global_position.y
		print("[compare] ", m["name"], " ground snap via skeleton: lowest_bone_y=", lowest_y)
	else:
		# Fallback to AABB for non-skinned models
		var bottom_y := _get_world_bottom(instance)
		instance.position.y -= bottom_y - pivot.global_position.y
		print("[compare] ", m["name"], " ground snap via AABB: bottom_y=", bottom_y)

func _remove_non_skinned_meshes(node: Node) -> void:
	# Remove MeshInstance3D nodes that aren't children of a Skeleton3D
	# (these are usually embedded floor planes, pedestals, etc.)
	var to_remove: Array[Node] = []
	_find_non_skinned_meshes(node, to_remove)
	for n in to_remove:
		print("[compare] Removing non-skinned mesh: ", n.name)
		n.get_parent().remove_child(n)
		n.queue_free()

func _find_non_skinned_meshes(node: Node, out: Array[Node]) -> void:
	if node is MeshInstance3D and not (node.get_parent() is Skeleton3D):
		out.append(node)
		return  # don't recurse into removed nodes
	for child in node.get_children():
		_find_non_skinned_meshes(child, out)

func _get_world_bottom(node: Node) -> float:
	# Use array as a mutable container since GDScript passes floats by value
	var result := [9999.0]
	_find_lowest_point(node, result)
	return result[0]

func _find_lowest_point(node: Node, result: Array) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var aabb := mi.get_aabb()
		var gt := mi.global_transform
		# Transform all 8 AABB corners to world space, find lowest Y
		for ix in range(2):
			for iy in range(2):
				for iz in range(2):
					var corner := Vector3(
						aabb.position.x + aabb.size.x * ix,
						aabb.position.y + aabb.size.y * iy,
						aabb.position.z + aabb.size.z * iz
					)
					var world_pos := gt * corner
					if world_pos.y < result[0]:
						result[0] = world_pos.y
	for child in node.get_children():
		_find_lowest_point(child, result)

func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	if node.get_class() == class_name_str:
		return node
	for child in node.get_children():
		var result = _find_node_by_class(child, class_name_str)
		if result:
			return result
	return null

func _play_model_anim(m: Dictionary, idx: int) -> void:
	var ap: AnimationPlayer = m["anim_player"]
	if not ap or m["anim_names"].size() == 0:
		return
	idx = idx % m["anim_names"].size()
	m["current_anim"] = idx
	var anim_name: String = m["anim_names"][idx]
	ap.play(anim_name)
	ap.speed_scale = 1.0
	if m["anim_label"]:
		m["anim_label"].text = anim_name

func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	ui_container = Control.new()
	ui_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(ui_container)

	# Title
	var title := Label.new()
	title.text = "Animation Comparison"
	title.position = Vector2(20, 10)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color.WHITE)
	ui_container.add_child(title)

	# Bottom panel
	var panel := Panel.new()
	panel.position = Vector2(0, 550)
	panel.size = Vector2(1152, 98)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0, 0, 0, 0.7)
	panel.add_theme_stylebox_override("panel", ps)
	ui_container.add_child(panel)

	# Per-model animation controls
	var col_width := 1152.0 / models.size()
	for i in range(models.size()):
		var m = models[i]
		var x_base := col_width * i + 10

		# Model name
		var name_lbl := Label.new()
		name_lbl.text = m["name"]
		name_lbl.position = Vector2(x_base, 558)
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
		ui_container.add_child(name_lbl)

		# < > buttons
		var btn_prev := Button.new()
		btn_prev.text = "<"
		btn_prev.position = Vector2(x_base, 582)
		btn_prev.size = Vector2(30, 26)
		btn_prev.add_theme_font_size_override("font_size", 14)
		btn_prev.pressed.connect(_on_prev.bind(i))
		ui_container.add_child(btn_prev)

		var btn_next := Button.new()
		btn_next.text = ">"
		btn_next.position = Vector2(x_base + 34, 582)
		btn_next.size = Vector2(30, 26)
		btn_next.add_theme_font_size_override("font_size", 14)
		btn_next.pressed.connect(_on_next.bind(i))
		ui_container.add_child(btn_next)

		# Animation name label
		var anim_lbl := Label.new()
		var anim_text: String = m["anim_names"][0] if m["anim_names"].size() > 0 else "none"
		anim_lbl.text = anim_text
		anim_lbl.position = Vector2(x_base + 70, 584)
		anim_lbl.add_theme_font_size_override("font_size", 15)
		anim_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
		ui_container.add_child(anim_lbl)
		m["anim_label"] = anim_lbl

		# Count
		var count_lbl := Label.new()
		count_lbl.text = "(%d/%d)" % [1, m["anim_names"].size()]
		count_lbl.name = "Count_%d" % i
		count_lbl.position = Vector2(x_base + 70, 610)
		count_lbl.add_theme_font_size_override("font_size", 12)
		count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		ui_container.add_child(count_lbl)

	# Hint
	var hint := Label.new()
	hint.text = "LMB drag: rotate | RMB drag: pan | Scroll: zoom"
	hint.position = Vector2(20, 530)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	ui_container.add_child(hint)

func _on_next(model_idx: int) -> void:
	var m = models[model_idx]
	if m["anim_names"].size() == 0:
		return
	var next_idx: int = (m["current_anim"] + 1) % m["anim_names"].size()
	_play_model_anim(m, next_idx)
	_update_count(model_idx)

func _on_prev(model_idx: int) -> void:
	var m = models[model_idx]
	if m["anim_names"].size() == 0:
		return
	var prev_idx: int = (m["current_anim"] - 1 + m["anim_names"].size()) % m["anim_names"].size()
	_play_model_anim(m, prev_idx)
	_update_count(model_idx)

func _update_count(model_idx: int) -> void:
	var m = models[model_idx]
	var count_node = ui_container.get_node_or_null("Count_%d" % model_idx)
	if count_node:
		count_node.text = "(%d/%d)" % [m["current_anim"] + 1, m["anim_names"].size()]

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.position.y < 520:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			cam_angle_y += event.relative.x * 0.5
			cam_angle_x += event.relative.y * 0.3
			cam_angle_x = clamp(cam_angle_x, -80, 80)
			_update_camera()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			var right := camera.global_transform.basis.x
			var up := camera.global_transform.basis.y
			var pan_speed := cam_distance * 0.002
			cam_target -= right * event.relative.x * pan_speed
			cam_target -= up * event.relative.y * -pan_speed
			_update_camera()

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam_distance = max(0.3, cam_distance - 0.15)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_distance = min(6.0, cam_distance + 0.15)
			_update_camera()
