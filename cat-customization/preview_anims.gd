extends Node3D

## Preview animations from a source model
## Cycles through animations with < > buttons

var model_instance: Node3D
var anim_player: AnimationPlayer
var anim_names: Array = []
var current_anim := 0
var anim_label: Label
var model_path := "res://somali_cat.gltf"

func _ready() -> void:
	_setup_environment()
	_setup_camera()
	_setup_floor()
	_load_model()
	_setup_ui()

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.4, 0.6, 0.9)
	sky_mat.sky_horizon_color = Color(0.7, 0.8, 0.95)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
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
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.3, 0.8)
	camera.rotation_degrees = Vector3(-10, 0, 0)
	camera.fov = 50.0
	add_child(camera)

func _setup_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(5, 5)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.82, 0.78)
	mat.roughness = 0.9
	floor_mesh.material_override = mat
	add_child(floor_mesh)

func _load_model() -> void:
	var scene = load(model_path)
	if not scene:
		print("[ERROR] Could not load ", model_path)
		return
	model_instance = scene.instantiate()
	model_instance.name = "PreviewModel"
	add_child(model_instance)

	# Find AnimationPlayer
	anim_player = _find_node_by_class(model_instance, "AnimationPlayer")
	if anim_player:
		anim_names = Array(anim_player.get_animation_list())
		print("[preview] Found animations: ", anim_names)
		for anim_name in anim_names:
			var anim := anim_player.get_animation(anim_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
		if anim_names.size() > 0:
			anim_player.play(anim_names[0])
	else:
		print("[preview] No AnimationPlayer found")

	# Fixed scale — adjust per model
	model_instance.scale = Vector3(0.12, 0.12, 0.12)

	print("[preview] Model loaded: ", model_path)

func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	if node.get_class() == class_name_str:
		return node
	for child in node.get_children():
		var result = _find_node_by_class(child, class_name_str)
		if result:
			return result
	return null

func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(container)

	# Title
	var title := Label.new()
	title.text = "Animation Preview: " + model_path.get_file()
	title.position = Vector2(20, 15)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color.WHITE)
	container.add_child(title)

	# Bottom panel
	var panel := Panel.new()
	panel.position = Vector2(0, 580)
	panel.size = Vector2(1152, 68)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0, 0, 0, 0.6)
	panel.add_theme_stylebox_override("panel", ps)
	container.add_child(panel)

	# Anim label and buttons
	var lbl := Label.new()
	lbl.text = "Anim:"
	lbl.position = Vector2(20, 596)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	container.add_child(lbl)

	anim_label = Label.new()
	anim_label.text = anim_names[current_anim] if anim_names.size() > 0 else "none"
	anim_label.position = Vector2(180, 596)
	anim_label.add_theme_font_size_override("font_size", 20)
	anim_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	container.add_child(anim_label)

	var btn_prev := Button.new()
	btn_prev.text = "<"
	btn_prev.position = Vector2(100, 592)
	btn_prev.size = Vector2(36, 30)
	btn_prev.add_theme_font_size_override("font_size", 18)
	btn_prev.pressed.connect(_prev_anim)
	container.add_child(btn_prev)

	var btn_next := Button.new()
	btn_next.text = ">"
	btn_next.position = Vector2(140, 592)
	btn_next.size = Vector2(36, 30)
	btn_next.add_theme_font_size_override("font_size", 18)
	btn_next.pressed.connect(_next_anim)
	container.add_child(btn_next)

	# Counter
	var counter := Label.new()
	counter.name = "Counter"
	counter.text = "(%d/%d)" % [current_anim + 1, anim_names.size()]
	counter.position = Vector2(700, 596)
	counter.add_theme_font_size_override("font_size", 18)
	counter.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	container.add_child(counter)

func _next_anim() -> void:
	if anim_names.size() == 0:
		return
	current_anim = (current_anim + 1) % anim_names.size()
	_play_current()

func _prev_anim() -> void:
	if anim_names.size() == 0:
		return
	current_anim = (current_anim - 1 + anim_names.size()) % anim_names.size()
	_play_current()

func _play_current() -> void:
	var anim_name: String = anim_names[current_anim]
	anim_player.play(anim_name)
	anim_label.text = anim_name
	# Update counter
	var counter = anim_label.get_parent().get_node_or_null("Counter")
	if counter:
		counter.text = "(%d/%d)" % [current_anim + 1, anim_names.size()]

func _process(_delta: float) -> void:
	if model_instance:
		model_instance.rotation.y += 0.3 * _delta

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if event.position.y < 580 and model_instance:
			model_instance.rotation.y += event.relative.x * 0.01
