extends Node3D

## Debug multi-angle viewer — 4 viewports: front, right side, back, top

var cat_instances: Array[Node3D] = []
var fur_materials: Array[ShaderMaterial] = []
var viewports: Array[SubViewport] = []

func _ready() -> void:
	# Create 4 sub-viewports in a 2x2 grid
	var canvas := CanvasLayer.new()
	add_child(canvas)
	
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(container)
	
	var half_w := 576
	var half_h := 324
	
	var angles := [
		{"name": "Eyes Extreme Close", "cam_pos": Vector3(0.38, 0.22, 0.08), "cam_rot": Vector3(-5, 75, 0)},
		{"name": "Face Close-up", "cam_pos": Vector3(0.5, 0.22, 0.15), "cam_rot": Vector3(-5, 70, 0)},
		{"name": "Front", "cam_pos": Vector3(0, 0.25, 0.7), "cam_rot": Vector3(-10, 0, 0)},
		{"name": "Left 3/4", "cam_pos": Vector3(0.4, 0.3, -0.5), "cam_rot": Vector3(-10, 140, 0)},
	]
	
	for i in range(4):
		var vp := SubViewport.new()
		vp.size = Vector2i(half_w, half_h)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.transparent_bg = false
		add_child(vp)
		viewports.append(vp)
		
		# Setup 3D scene in each viewport
		_setup_scene_in_viewport(vp, angles[i])
		
		# Display viewport on screen
		var rect := TextureRect.new()
		rect.texture = vp.get_texture()
		rect.position = Vector2((i % 2) * half_w, (i / 2) * half_h)
		rect.size = Vector2(half_w, half_h)
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		container.add_child(rect)
		
		# Label
		var label := Label.new()
		label.text = angles[i]["name"]
		label.position = Vector2((i % 2) * half_w + 10, (i / 2) * half_h + 5)
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color.YELLOW)
		container.add_child(label)
	
	# Grid lines
	var h_line := ColorRect.new()
	h_line.color = Color(1, 1, 1, 0.5)
	h_line.position = Vector2(0, half_h - 1)
	h_line.size = Vector2(1152, 2)
	container.add_child(h_line)
	
	var v_line := ColorRect.new()
	v_line.color = Color(1, 1, 1, 0.5)
	v_line.position = Vector2(half_w - 1, 0)
	v_line.size = Vector2(2, 648)
	container.add_child(v_line)

func _setup_scene_in_viewport(vp: SubViewport, angle: Dictionary) -> void:
	var root_3d := Node3D.new()
	vp.add_child(root_3d)
	
	# Environment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.25, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root_3d.add_child(we)
	
	# Light
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	light.light_energy = 2.0
	root_3d.add_child(light)
	
	# Camera
	var camera := Camera3D.new()
	camera.position = angle["cam_pos"]
	camera.rotation_degrees = angle["cam_rot"]
	camera.fov = 50.0
	camera.current = true
	root_3d.add_child(camera)
	
	# Floor
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3, 3)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.5)
	floor_mesh.material_override = mat
	root_3d.add_child(floor_mesh)
	
	# Cat
	var cat_scene = load("res://cat.gltf")
	if cat_scene:
		var cat = cat_scene.instantiate()
		cat.name = "Cat"
		cat.scale = Vector3(0.012, 0.012, 0.012)
		root_3d.add_child(cat)
		cat_instances.append(cat)
		
		# Stop animation — freeze in bind pose
		var anim = _find_node_by_class(cat, "AnimationPlayer")
		if anim:
			anim.stop()

		# Add 3D eye spheres
		var skeleton = _find_node_by_class(cat, "Skeleton3D")
		if skeleton:
			var head_idx := -1
			for bi in range(skeleton.get_bone_count()):
				if skeleton.get_bone_name(bi).begins_with("head"):
					head_idx = bi
					break
			if head_idx >= 0:
				var eye_mat := StandardMaterial3D.new()
				eye_mat.albedo_color = Color(1.0, 0.0, 0.0)  # bright red for debug
				eye_mat.roughness = 0.02
				eye_mat.metallic = 0.3
				var pupil_mat := StandardMaterial3D.new()
				pupil_mat.albedo_color = Color(0.02, 0.02, 0.02)
				pupil_mat.roughness = 0.05
				var eye_positions := [
					Vector3(-0.021, 0.055, -0.033),
					Vector3(0.021, 0.055, -0.033),
				]
				for ei in range(2):
					var attach := BoneAttachment3D.new()
					attach.bone_idx = head_idx
					skeleton.add_child(attach)
					var eye_m := MeshInstance3D.new()
					var sph := SphereMesh.new()
					sph.radius = 0.015
					sph.height = 0.03
					eye_m.mesh = sph
					eye_m.material_override = eye_mat
					eye_m.position = eye_positions[ei]
					attach.add_child(eye_m)
					var pupil := MeshInstance3D.new()
					var psph := SphereMesh.new()
					psph.radius = 0.007
					psph.height = 0.014
					pupil.mesh = psph
					pupil.material_override = pupil_mat
					pupil.position = eye_positions[ei] + Vector3(0.0, 0.01, 0.0)
					attach.add_child(pupil)

		# Apply fur shader
		var mesh = _find_node_by_class(cat, "MeshInstance3D")
		if mesh:
			var shader = load("res://cat_fur.gdshader")
			var fur_mat := ShaderMaterial.new()
			fur_mat.shader = shader
			# Orange tabby defaults
			fur_mat.set_shader_parameter("base_color", Vector3(0.9, 0.5, 0.2))
			fur_mat.set_shader_parameter("secondary_color", Vector3(0.3, 0.15, 0.05))
			fur_mat.set_shader_parameter("belly_color", Vector3(1.0, 0.92, 0.85))
			fur_mat.set_shader_parameter("paw_color", Vector3(1.0, 0.92, 0.85))
			fur_mat.set_shader_parameter("eye_color", Vector3(1.0, 0.0, 0.0))
			fur_mat.set_shader_parameter("ear_color", Vector3(0.95, 0.6, 0.6))
			fur_mat.set_shader_parameter("nose_color", Vector3(0.9, 0.55, 0.55))
			fur_mat.set_shader_parameter("pattern_type", 1) # tabby
			mesh.material_override = fur_mat
			fur_materials.append(fur_mat)

func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	if node.get_class() == class_name_str:
		return node
	for child in node.get_children():
		var result = _find_node_by_class(child, class_name_str)
		if result:
			return result
	return null
