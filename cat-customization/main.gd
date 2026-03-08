extends Node3D

var cat_instance: Node3D
var cat_mesh: MeshInstance3D
var anim_player: AnimationPlayer
var fur_shader_mat: ShaderMaterial  # shared across all body meshes
var body_meshes: Array[MeshInstance3D] = []
var eye_mesh_node: MeshInstance3D  # the eye mesh from the model
var camera: Camera3D
var skeleton: Skeleton3D
var head_bone_idx := -1
var click_label: Label
var ref_models: Dictionary = {}  # anim_name -> {instance, anim_player}
var current_ref_name := ""

# Orbit camera
var cam_distance := 2.5
var cam_angle_y := 0.0
var cam_angle_x := -10.0
var cam_target := Vector3(0.8, 0.5, 0)

# Animation state
var current_anim := 0
var anim_names: Array = []  # populated from model
var anim_scrubber: HSlider
var anim_paused := false
var pause_check: CheckBox
var scrubbing := false

# Bone scaling customization
# Each entry: [slider_value (0-1 mapped to scale range), [bone_names], scale_axis_fn]
var bone_scale_values := {
	"head_size": 0.5,
	"eye_size": 0.5,
	"eye_spacing": 0.5,
	"body_width": 0.5,
	"tail_size": 0.5,
}
# Bone name -> custom Vector3 scale to apply each frame on top of animation
var bone_custom_scales := {}
var slider_labels := {}  # slider_name -> value Label

# Primary fur colors
var primary_colors := [
	Color(0.9, 0.55, 0.15),    # Orange
	Color(0.35, 0.35, 0.35),   # Gray
	Color(0.15, 0.15, 0.15),   # Black
	Color(0.85, 0.82, 0.78),   # White/Silver
	Color(0.95, 0.85, 0.7),    # Siamese
	Color(0.6, 0.35, 0.1),     # Brown
	Color(0.85, 0.65, 0.3),    # Ginger
	Color(0.3, 0.35, 0.5),     # Blue/Russian
]
var current_primary := 0

# Stripe/secondary fur colors
var stripe_colors := [
	Color(0.4, 0.15, 0.05),    # Dark brown
	Color(0.12, 0.12, 0.12),   # Near-black
	Color(0.05, 0.05, 0.05),   # Black
	Color(0.55, 0.5, 0.45),    # Warm gray
	Color(0.5, 0.25, 0.1),     # Siamese point
	Color(0.25, 0.1, 0.02),    # Dark brown
	Color(0.6, 0.3, 0.05),     # Deep ginger
	Color(0.1, 0.12, 0.2),     # Dark blue
]
var current_stripe := 0

var eye_colors := [
	Color(0.3, 0.7, 0.2),   # Green
	Color(0.7, 0.6, 0.1),   # Amber
	Color(0.2, 0.5, 0.8),   # Blue
	Color(0.5, 0.3, 0.15),  # Brown
	Color(0.6, 0.3, 0.7),   # Purple
	Color(0.1, 0.8, 0.8),   # Cyan
]
var current_eye := 0

# UI refs
var ui_container: Control
var eye_swatch_buttons: Array[Button] = []
var fur_swatch_buttons: Array[Button] = []
var sec_swatch_buttons: Array[Button] = []

func _ready() -> void:
	# Run _process after AnimationPlayer so bone scale overrides stick
	process_priority = 100
	_setup_environment()
	_setup_camera()
	_setup_floor()
	_load_cat()
	_load_reference_model()
	_setup_ui()
	_apply_primary(0)
	_apply_stripe(0)
	_update_bone_scales("head_size", 0.5)  # Initialize all bone scales

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

func _load_cat() -> void:
	var cat_scene = load("res://cartoon_cat.gltf")
	if not cat_scene:
		print("[ERROR] Could not load cartoon_cat.gltf")
		return

	cat_instance = cat_scene.instantiate()
	cat_instance.name = "Cat"
	cat_instance.scale = Vector3(0.25, 0.25, 0.25)
	# Sketchfab root matrix handles orientation — no rotation needed
	add_child(cat_instance)

	# Find skinned meshes and apply fur recolor shader to body parts
	_setup_fur_shader(cat_instance)

	# Remove non-skinned meshes (weapons, floor planes)
	_remove_non_skinned_meshes(cat_instance)

	# Find AnimationPlayer and populate anim list
	anim_player = _find_node_by_class(cat_instance, "AnimationPlayer")
	if anim_player:
		anim_names = Array(anim_player.get_animation_list())
		print("[cat] Found animations: ", anim_names)
		for anim_name in anim_names:
			var anim := anim_player.get_animation(anim_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
		# Start on Cat_Walk for easy testing of retargeted anims
		for i in range(anim_names.size()):
			if anim_names[i] == "Cat_Walk":
				current_anim = i
				break
		_apply_anim()
	# Find skeleton for bone scaling
	skeleton = _find_node_by_class(cat_instance, "Skeleton3D")
	if skeleton:
		print("[cat] Skeleton found: ", skeleton.get_bone_count(), " bones")
	# Find the eye mesh to enable color tinting
	_find_eye_mesh(cat_instance)
	print("[cat] Cat loaded successfully")

func _load_reference_model() -> void:
	var ref_fbxs := {
		"Cat_Walk": "res://mixamo_walk_ref.fbx",
		"Cat_HappyWalk": "res://ref_happy_walk.fbx",
		"Cat_SlowWalk": "res://ref_slow_walk.fbx",
		"Cat_CoolWalk": "res://ref_cool_walk.fbx",
		"Cat_Pacing": "res://ref_pacing.fbx",
	}
	for anim_name in ref_fbxs:
		var ref_scene = load(ref_fbxs[anim_name])
		if not ref_scene:
			print("[ref] Could not load ", ref_fbxs[anim_name])
			continue
		var inst: Node3D = ref_scene.instantiate()
		inst.name = "Ref_" + anim_name
		inst.position = Vector3(1.0, 0, 0)
		inst.scale = Vector3(0.5, 0.5, 0.5)
		inst.visible = false
		add_child(inst)
		var ap: AnimationPlayer = _find_node_by_class(inst, "AnimationPlayer")
		if ap:
			for a_name in ap.get_animation_list():
				var a := ap.get_animation(a_name)
				if a:
					a.loop_mode = Animation.LOOP_LINEAR
		ref_models[anim_name] = {"instance": inst, "anim_player": ap}
		print("[ref] Loaded reference: ", anim_name)
	_show_ref_for_anim(anim_names[current_anim] if anim_names.size() > 0 else "")

func _show_ref_for_anim(anim_name: String) -> void:
	# Hide all refs
	for key in ref_models:
		ref_models[key]["instance"].visible = false
		var ap: AnimationPlayer = ref_models[key]["anim_player"]
		if ap:
			ap.stop()
	current_ref_name = ""
	# Show matching ref if it exists
	if ref_models.has(anim_name):
		var data: Dictionary = ref_models[anim_name]
		data["instance"].visible = true
		current_ref_name = anim_name
		var ap: AnimationPlayer = data["anim_player"]
		if ap:
			var ref_anims := ap.get_animation_list()
			if ref_anims.size() > 0:
				ap.play(ref_anims[0])

func _setup_fur_shader(root: Node) -> void:
	# Create a shared fur recolor shader material
	var shader = load("res://cat_fur_recolor.gdshader")
	fur_shader_mat = ShaderMaterial.new()
	fur_shader_mat.shader = shader

	# Find all skinned meshes that use the Cat_Body material
	_collect_body_meshes(root)

	if body_meshes.size() > 0:
		# Get the base texture from the first body mesh
		var first_mat = body_meshes[0].get_active_material(0)
		if first_mat is StandardMaterial3D and first_mat.albedo_texture:
			fur_shader_mat.set_shader_parameter("base_texture", first_mat.albedo_texture)

		# Apply the shader to all body meshes
		for mesh in body_meshes:
			mesh.set_surface_override_material(0, fur_shader_mat)
		print("[cat] Fur recolor shader applied to ", body_meshes.size(), " body meshes")

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
		print("[cat] Removing non-skinned mesh: ", n.name)
		n.get_parent().remove_child(n)
		n.queue_free()

func _find_eye_mesh(node: Node) -> void:
	# The eye mesh is Object_70, which uses the Cat_Eye material
	# Search all skinned MeshInstance3D nodes and check material names
	if node is MeshInstance3D and node.get_parent() is Skeleton3D:
		var mat = node.get_active_material(0)
		if mat and mat.resource_name.contains("Cat_Eye"):
			eye_mesh_node = node
			# Replace with a shader material that recolors only the iris
			var shader = load("res://cat_eye_recolor.gdshader")
			var shader_mat := ShaderMaterial.new()
			shader_mat.shader = shader
			# Extract the base texture from the original material
			if mat is StandardMaterial3D:
				var base_tex = mat.albedo_texture
				if base_tex:
					shader_mat.set_shader_parameter("base_texture", base_tex)
			node.set_surface_override_material(0, shader_mat)
			print("[cat] Eye mesh found: ", node.name, " (iris recolor shader applied)")
			return
	for child in node.get_children():
		if eye_mesh_node:
			return
		_find_eye_mesh(child)

func _collect_non_skinned(node: Node, out: Array[Node]) -> void:
	if node is MeshInstance3D and not (node.get_parent() is Skeleton3D):
		out.append(node)
		return
	for child in node.get_children():
		_collect_non_skinned(child, out)


func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	if node.get_class() == class_name_str:
		return node
	for child in node.get_children():
		var result = _find_node_by_class(child, class_name_str)
		if result:
			return result
	return null

# --- UI ---

func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	ui_container = Control.new()
	ui_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(ui_container)

	# Title
	var title := Label.new()
	title.text = "Cat Customizer"
	title.position = Vector2(20, 15)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color.WHITE)
	ui_container.add_child(title)

	# Bottom panel background
	var panel := Panel.new()
	panel.position = Vector2(0, 420)
	panel.size = Vector2(1152, 228)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.6)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel.add_theme_stylebox_override("panel", panel_style)
	ui_container.add_child(panel)

	# Left side: Color swatches
	# Row 1: Primary fur color swatches
	var row1_y := 430.0
	_add_label("Primary:", Vector2(20, row1_y + 4), ui_container)
	for i in range(primary_colors.size()):
		var btn := _create_swatch(primary_colors[i], Vector2(110 + i * 50, row1_y), func(): _apply_primary(i))
		fur_swatch_buttons.append(btn)
		ui_container.add_child(btn)
	_update_fur_swatch_borders()

	# Row 2: Stripe color swatches
	var row2_y := 472.0
	_add_label("Stripes:", Vector2(20, row2_y + 4), ui_container)
	for i in range(stripe_colors.size()):
		var btn := _create_swatch(stripe_colors[i], Vector2(110 + i * 50, row2_y), func(): _apply_stripe(i))
		sec_swatch_buttons.append(btn)
		ui_container.add_child(btn)
	_update_sec_swatch_borders()

	# Row 3: Eye color swatches + Animation controls
	var row3_y := 514.0
	_add_label("Eyes:", Vector2(20, row3_y + 4), ui_container)
	for i in range(eye_colors.size()):
		var btn := _create_swatch(eye_colors[i], Vector2(110 + i * 50, row3_y), func(): _apply_eye_preset(i))
		eye_swatch_buttons.append(btn)
		ui_container.add_child(btn)
	_update_eye_swatch_borders()

	# Animation dropdown
	_add_label("Anim:", Vector2(430, row3_y + 4), ui_container)
	var anim_dropdown := OptionButton.new()
	anim_dropdown.position = Vector2(500, row3_y)
	anim_dropdown.size = Vector2(220, 30)
	anim_dropdown.add_theme_font_size_override("font_size", 14)
	for i in range(anim_names.size()):
		anim_dropdown.add_item(anim_names[i], i)
	anim_dropdown.selected = current_anim
	anim_dropdown.item_selected.connect(_on_anim_selected)
	ui_container.add_child(anim_dropdown)

	# Animation scrubber + pause (row below row3)
	var row4_y := row3_y + 38.0
	pause_check = CheckBox.new()
	pause_check.text = "Pause"
	pause_check.position = Vector2(430, row4_y)
	pause_check.add_theme_font_size_override("font_size", 14)
	pause_check.add_theme_color_override("font_color", Color.WHITE)
	pause_check.toggled.connect(_on_pause_toggled)
	ui_container.add_child(pause_check)

	anim_scrubber = HSlider.new()
	anim_scrubber.position = Vector2(530, row4_y + 4)
	anim_scrubber.size = Vector2(150, 22)
	anim_scrubber.min_value = 0.0
	anim_scrubber.max_value = 1.0
	anim_scrubber.step = 0.005
	anim_scrubber.value = 0.0
	anim_scrubber.drag_started.connect(_on_scrubber_drag_started)
	anim_scrubber.drag_ended.connect(_on_scrubber_drag_ended)
	anim_scrubber.value_changed.connect(_on_scrubber_changed)
	ui_container.add_child(anim_scrubber)

	# Right side: Body shape sliders
	var slider_x := 720.0
	var slider_w := 160.0
	var sliders_config := [
		["head_size", "Head:", 0.5],
		["eye_size", "Eyes:", 0.5],
		["eye_spacing", "Eye Gap:", 0.5],
		["body_width", "Body:", 0.5],
		["tail_size", "Tail:", 0.5],
	]
	for si in range(sliders_config.size()):
		var cfg = sliders_config[si]
		var sy := 430.0 + si * 34.0
		var lbl := _add_label(cfg[0] as String, Vector2(slider_x, sy + 2), ui_container)
		# Use display name
		lbl.text = cfg[1] as String
		lbl.add_theme_font_size_override("font_size", 15)
		var slider := HSlider.new()
		slider.position = Vector2(slider_x + 75, sy + 4)
		slider.size = Vector2(slider_w, 22)
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.02
		slider.value = cfg[2] as float
		var sname: String = cfg[0] as String
		slider.value_changed.connect(_on_bone_slider.bind(sname))
		ui_container.add_child(slider)
		# Value label
		var val_lbl := Label.new()
		val_lbl.text = "1.0"
		val_lbl.position = Vector2(slider_x + 75 + slider_w + 8, sy + 2)
		val_lbl.add_theme_font_size_override("font_size", 14)
		val_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		ui_container.add_child(val_lbl)
		slider_labels[sname] = val_lbl

	# Drag hint
	click_label = Label.new()
	click_label.text = "LMB: rotate | RMB: pan | Scroll: zoom"
	click_label.position = Vector2(20, 590)
	click_label.add_theme_font_size_override("font_size", 13)
	click_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	ui_container.add_child(click_label)

func _create_swatch(color: Color, pos: Vector2, callback: Callable) -> Button:
	var btn := Button.new()
	btn.position = pos
	btn.custom_minimum_size = Vector2(40, 36)
	btn.size = Vector2(40, 36)
	btn.text = ""
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(1, 1, 1, 0.3)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	var pressed_style := style.duplicate()
	pressed_style.border_color = Color(1, 1, 1, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.pressed.connect(callback)
	return btn

func _update_fur_swatch_borders() -> void:
	for i in range(fur_swatch_buttons.size()):
		var btn := fur_swatch_buttons[i]
		var style: StyleBoxFlat = btn.get_theme_stylebox("normal")
		style.border_color = Color(1, 1, 1, 1.0) if i == current_primary else Color(1, 1, 1, 0.3)

func _update_sec_swatch_borders() -> void:
	for i in range(sec_swatch_buttons.size()):
		var btn := sec_swatch_buttons[i]
		var style: StyleBoxFlat = btn.get_theme_stylebox("normal")
		style.border_color = Color(1, 1, 1, 1.0) if i == current_stripe else Color(1, 1, 1, 0.3)

func _update_eye_swatch_borders() -> void:
	for i in range(eye_swatch_buttons.size()):
		var btn := eye_swatch_buttons[i]
		var style: StyleBoxFlat = btn.get_theme_stylebox("normal")
		style.border_color = Color(1, 1, 1, 1.0) if i == current_eye else Color(1, 1, 1, 0.3)

func _add_label(text: String, pos: Vector2, parent: Control) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	parent.add_child(label)
	return label

func _add_button(text: String, pos: Vector2, sz: Vector2, parent: Control, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = sz
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

# --- Customization logic ---

func _color_to_vec3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)

func _apply_primary(idx: int) -> void:
	current_primary = idx
	if fur_shader_mat:
		fur_shader_mat.set_shader_parameter("primary_color", _color_to_vec3(primary_colors[idx]))
	_update_fur_swatch_borders()

func _apply_stripe(idx: int) -> void:
	current_stripe = idx
	if fur_shader_mat:
		fur_shader_mat.set_shader_parameter("secondary_color", _color_to_vec3(stripe_colors[idx]))
	_update_sec_swatch_borders()

func _apply_eye_preset(idx: int) -> void:
	current_eye = idx
	_apply_eyes()
	_update_eye_swatch_borders()

func _apply_eyes() -> void:
	if not eye_mesh_node:
		return
	var mat = eye_mesh_node.get_surface_override_material(0)
	if mat is ShaderMaterial:
		var ec = eye_colors[current_eye]
		mat.set_shader_parameter("iris_color", Vector3(ec.r, ec.g, ec.b))
		print("[cat] Iris color set to: ", ec)

func _on_anim_selected(idx: int) -> void:
	current_anim = idx
	_apply_anim()

func _apply_anim() -> void:
	if not anim_player or anim_names.size() == 0:
		return
	var anim_name: String = anim_names[current_anim]
	anim_player.play(anim_name)
	anim_player.speed_scale = 0.0 if anim_paused else 1.0
	_show_ref_for_anim(anim_name)

func _on_pause_toggled(pressed: bool) -> void:
	anim_paused = pressed
	if anim_player:
		anim_player.speed_scale = 0.0 if anim_paused else 1.0

func _on_scrubber_drag_started() -> void:
	scrubbing = true
	anim_paused = true
	if anim_player:
		anim_player.speed_scale = 0.0
	if pause_check:
		pause_check.set_pressed_no_signal(true)

func _on_scrubber_drag_ended(_value_changed: bool) -> void:
	scrubbing = false

func _on_scrubber_changed(value: float) -> void:
	if not scrubbing or not anim_player:
		return
	var anim_name: String = anim_player.current_animation
	if anim_name.is_empty():
		return
	var anim := anim_player.get_animation(anim_name)
	if anim:
		anim_player.seek(value * anim.length, true)

func _on_bone_slider(value: float, slider_name: String) -> void:
	_update_bone_scales(slider_name, value)

func _update_bone_scales(slider_name: String, value: float) -> void:
	bone_scale_values[slider_name] = value
	bone_custom_scales.clear()

	var head_v: float = bone_scale_values["head_size"]
	var eye_v: float = bone_scale_values["eye_size"]
	var spacing_v: float = bone_scale_values["eye_spacing"]
	var body_v: float = bone_scale_values["body_width"]
	var tail_v: float = bone_scale_values["tail_size"]

	# Head size: 0.75 - 1.25 (0.5 = 1.0)
	var head_s: float = lerp(0.75, 1.25, head_v)
	bone_custom_scales["Head_05"] = Vector3(head_s, head_s, head_s)

	# Eye size: 0.6 - 1.4 (0.5 = 1.0)
	var eye_s: float = lerp(0.6, 1.4, eye_v)
	bone_custom_scales["Aye_L_06"] = Vector3(eye_s, eye_s, eye_s)
	bone_custom_scales["Aye_R_021"] = Vector3(eye_s, eye_s, eye_s)

	# Body width: 0.7 - 1.3 (0.5 = 1.0) on X and Z
	var body_w: float = lerp(0.7, 1.3, body_v)
	bone_custom_scales["Bone2_02"] = Vector3(body_w, 1.0, body_w)
	bone_custom_scales["Bone3_03"] = Vector3(body_w, 1.0, body_w)

	# Tail size: 0.0 - 2.0 (0.5 = 1.0, 0 = no tail, 1 = max fluffy)
	# Only scale the root tail bone — child bones compound the parent's scale
	var tail_s: float = lerp(0.0, 2.0, tail_v)
	bone_custom_scales["Tail_B1_040"] = Vector3(tail_s, tail_s, tail_s)

	# Update label
	if slider_labels.has(slider_name):
		var display_val: float = 1.0
		match slider_name:
			"head_size": display_val = head_s
			"eye_size": display_val = eye_s
			"eye_spacing": display_val = lerp(0.8, 1.2, spacing_v)
			"body_width": display_val = body_w
			"tail_size": display_val = tail_s
		slider_labels[slider_name].text = "%.1f" % display_val

# --- Input ---

func _process(_delta: float) -> void:
	# Update scrubber position from animation playback
	if anim_scrubber and anim_player and not scrubbing:
		var anim_name := anim_player.current_animation
		if not anim_name.is_empty():
			var anim := anim_player.get_animation(anim_name)
			if anim and anim.length > 0:
				anim_scrubber.set_value_no_signal(anim_player.current_animation_position / anim.length)

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


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.position.y < 410:
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
			cam_distance = max(0.3, cam_distance - 0.1)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_distance = min(6.0, cam_distance + 0.1)
			_update_camera()


