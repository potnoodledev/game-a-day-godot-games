extends Node3D

# === GAME STATE ===
var game_state := 0  # 0=ready, 1=playing, 2=dead
var points := 0
var level := 1
var lives := 3
var wall_speed := 4.0
var wall_z_start := -25.0
var wall_z_end := 2.0

# === CURRENT SHAPE ===
var shape_blocks: Array = []  # Array of Vector3i — block positions in shape-local coords
var shape_node: Node3D
var solution_blocks: Array = []  # The correct rotation to match the hole

# === WALL ===
var wall_node: Node3D
var wall_z := 0.0
var wall_hole: Array = []  # 2D Vector2i positions that are open

# === CAMERA ===
var camera: Camera3D

# === TOUCH ===
var touch_start := Vector2.ZERO
var touch_start_time := 0.0
var is_touching := false
var round_active := false

# === ROTATION ANIMATION ===
var is_animating := false
var anim_from_rotation := Quaternion.IDENTITY
var anim_to_rotation := Quaternion.IDENTITY
var anim_progress := 0.0
var anim_duration := 0.2  # seconds per 90-degree snap
var pending_blocks: Array = []  # blocks after rotation (applied when anim finishes)

# === VISUAL ===
var hud: Node
var _score_submitted := false
var shape_color := Color.WHITE
var tunnel_markers: Array = []

# === SHAPE DEFINITIONS ===
var shape_defs: Array = []

var grid_size := 5
var block_size := 1.0

func _ready():
	camera = Camera3D.new()
	camera.position = Vector3(0, 3.5, 10)
	camera.rotation_degrees = Vector3(-12, 0, 0)
	add_child(camera)

	var dir_light = DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-40, 30, 0)
	dir_light.shadow_enabled = true
	dir_light.light_energy = 1.0
	add_child(dir_light)

	var env_node = WorldEnvironment.new()
	var environment = Environment.new()
	environment.ambient_light_color = Color(0.5, 0.6, 0.8)
	environment.ambient_light_energy = 0.5
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.06, 0.12)
	env_node.environment = environment
	add_child(env_node)

	_define_shapes()

	var hud_script = load("res://hud.gd")
	hud = CanvasLayer.new()
	hud.set_script(hud_script)
	add_child(hud)

	_build_tunnel()

	game_state = 0
	hud.show_start()

func _define_shapes():
	# Simple 2D shapes (levels 1-3)
	shape_defs.append([Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(0,1,0)])  # L small
	shape_defs.append([Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(2,0,0)])  # Line 3
	shape_defs.append([Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(0,1,0), Vector3i(1,1,0)])  # Square
	shape_defs.append([Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(2,0,0), Vector3i(1,1,0)])  # T
	shape_defs.append([Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(1,1,0), Vector3i(2,1,0)])  # S

	# 3D shapes (levels 4+)
	shape_defs.append([Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(0,1,0), Vector3i(0,0,1)])  # Corner 3D
	shape_defs.append([Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(2,0,0), Vector3i(0,0,1)])  # L 3D
	shape_defs.append([Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,0,1)])  # T 3D
	shape_defs.append([Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(1,1,0), Vector3i(1,1,1)])  # Z 3D
	shape_defs.append([Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0)])  # Plus
	shape_defs.append([Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(2,0,0), Vector3i(3,0,0), Vector3i(0,1,0)])  # Big L
	shape_defs.append([Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(1,1,0), Vector3i(2,1,0), Vector3i(2,2,0)])  # Stairs

func _build_tunnel():
	# Floor
	var floor_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(8, 0.2, 50)
	floor_mesh.mesh = box
	floor_mesh.position = Vector3(0, -3.2, -15)
	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.12, 0.12, 0.2)
	floor_mesh.set_surface_override_material(0, floor_mat)
	add_child(floor_mesh)

	# Side rails
	for side in [-1, 1]:
		var rail = MeshInstance3D.new()
		var rbox = BoxMesh.new()
		rbox.size = Vector3(0.15, 6.5, 50)
		rail.mesh = rbox
		rail.position = Vector3(side * 3.5, 0, -15)
		var rail_mat = StandardMaterial3D.new()
		rail_mat.albedo_color = Color(0.2, 0.15, 0.35)
		rail_mat.emission_enabled = true
		rail_mat.emission = Color(0.15, 0.08, 0.3)
		rail_mat.emission_energy_multiplier = 0.3
		rail.set_surface_override_material(0, rail_mat)
		add_child(rail)

	# Lane dashes
	for i in range(15):
		var marker = MeshInstance3D.new()
		var mbox = BoxMesh.new()
		mbox.size = Vector3(0.08, 0.03, 1.2)
		marker.mesh = mbox
		marker.position = Vector3(0, -3.05, -i * 3.0 + 3.0)
		var mmat = StandardMaterial3D.new()
		mmat.albedo_color = Color(0.25, 0.25, 0.4, 0.4)
		mmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		marker.set_surface_override_material(0, mmat)
		add_child(marker)
		tunnel_markers.append(marker)

func _spawn_round():
	round_active = false

	# Clean up previous
	if shape_node and is_instance_valid(shape_node):
		shape_node.queue_free()
		shape_node = null
	if wall_node and is_instance_valid(wall_node):
		wall_node.queue_free()
		wall_node = null

	# Pick shape based on level
	var max_index: int
	if level <= 3:
		max_index = 5
	elif level <= 6:
		max_index = 9
	else:
		max_index = shape_defs.size()
	var shape_idx = randi() % max_index
	solution_blocks = shape_defs[shape_idx].duplicate()
	solution_blocks = _center_blocks(solution_blocks)

	# The wall hole is the silhouette of the solution
	wall_hole = _project_silhouette(solution_blocks)

	# Scramble the shape — apply random rotations so player has to fix it
	shape_blocks = solution_blocks.duplicate()
	var scramble_count = 1
	if level >= 3:
		scramble_count = 2
	if level >= 6:
		scramble_count = 3
	for i in range(scramble_count):
		var axis = randi() % 3
		shape_blocks = _rotate_blocks(shape_blocks, axis)
	shape_blocks = _center_blocks(shape_blocks)

	# If scramble accidentally matches solution, rotate once more
	if _silhouettes_match(_project_silhouette(shape_blocks), wall_hole):
		shape_blocks = _rotate_blocks(shape_blocks, 0)
		shape_blocks = _center_blocks(shape_blocks)

	# Pick color
	var colors = [
		Color(0.2, 0.6, 1.0), Color(0.1, 0.85, 0.4), Color(1.0, 0.5, 0.1),
		Color(0.9, 0.2, 0.6), Color(0.6, 0.3, 1.0), Color(1.0, 0.85, 0.1),
	]
	shape_color = colors[randi() % colors.size()]

	_build_wall()
	_build_shape()

	wall_z = wall_z_start
	wall_node.position.z = wall_z
	wall_speed = 3.0 + level * 0.4
	round_active = true

func _project_silhouette(blocks: Array) -> Array:
	var silhouette: Array = []
	for b in blocks:
		var pos2d = Vector2i(b.x, b.y)
		if not silhouette.has(pos2d):
			silhouette.append(pos2d)
	return silhouette

func _silhouettes_match(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for cell in a:
		if not b.has(cell):
			return false
	return true

func _rotate_blocks(blocks: Array, axis: int) -> Array:
	var result: Array = []
	for b in blocks:
		var new_b: Vector3i
		if axis == 0:  # X axis: (x,y,z) -> (x,-z,y)
			new_b = Vector3i(b.x, -b.z, b.y)
		elif axis == 1:  # Y axis: (x,y,z) -> (z,y,-x)
			new_b = Vector3i(b.z, b.y, -b.x)
		else:  # Z axis: (x,y,z) -> (-y,x,z)
			new_b = Vector3i(-b.y, b.x, b.z)
		result.append(new_b)
	return result

func _center_blocks(blocks: Array) -> Array:
	var min_pos = Vector3i(999, 999, 999)
	var max_pos = Vector3i(-999, -999, -999)
	for b in blocks:
		min_pos.x = min(min_pos.x, b.x)
		min_pos.y = min(min_pos.y, b.y)
		min_pos.z = min(min_pos.z, b.z)
		max_pos.x = max(max_pos.x, b.x)
		max_pos.y = max(max_pos.y, b.y)
		max_pos.z = max(max_pos.z, b.z)
	var cx = int(floor((min_pos.x + max_pos.x) / 2.0))
	var cy = int(floor((min_pos.y + max_pos.y) / 2.0))
	var cz = int(floor((min_pos.z + max_pos.z) / 2.0))
	var result: Array = []
	for b in blocks:
		result.append(Vector3i(b.x - cx, b.y - cy, b.z - cz))
	return result

func _build_shape():
	shape_node = Node3D.new()
	shape_node.position = Vector3(0, 0.5, 4)

	for b in shape_blocks:
		var cube = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3.ONE * block_size * 0.88
		cube.mesh = box_mesh
		cube.position = Vector3(b.x, b.y, b.z) * block_size
		var mat = StandardMaterial3D.new()
		mat.albedo_color = shape_color
		mat.emission_enabled = true
		mat.emission = shape_color * 0.4
		mat.emission_energy_multiplier = 0.5
		cube.set_surface_override_material(0, mat)
		shape_node.add_child(cube)

	add_child(shape_node)

func _build_wall():
	wall_node = Node3D.new()
	wall_node.position = Vector3(0, 0.5, wall_z_start)

	var half = int(grid_size / 2)

	for gx in range(-half, half + 1):
		for gy in range(-half, half + 1):
			var is_hole = false
			for h in wall_hole:
				if h.x == gx and h.y == gy:
					is_hole = true
					break

			if not is_hole:
				var cube = MeshInstance3D.new()
				var box_mesh = BoxMesh.new()
				box_mesh.size = Vector3(block_size * 0.95, block_size * 0.95, block_size * 0.35)
				cube.mesh = box_mesh
				cube.position = Vector3(gx * block_size, gy * block_size, 0)
				var mat = StandardMaterial3D.new()
				mat.albedo_color = Color(0.35, 0.3, 0.45)
				mat.emission_enabled = true
				mat.emission = Color(0.15, 0.1, 0.25)
				mat.emission_energy_multiplier = 0.15
				cube.set_surface_override_material(0, mat)
				wall_node.add_child(cube)
			else:
				# Glowing hole outline
				var outline = MeshInstance3D.new()
				var obox = BoxMesh.new()
				obox.size = Vector3(block_size, block_size, block_size * 0.06)
				outline.mesh = obox
				outline.position = Vector3(gx * block_size, gy * block_size, 0)
				var omat = StandardMaterial3D.new()
				omat.albedo_color = Color(0.1, 0.7, 1.0, 0.25)
				omat.emission_enabled = true
				omat.emission = Color(0.05, 0.4, 0.7)
				omat.emission_energy_multiplier = 1.5
				omat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				outline.set_surface_override_material(0, omat)
				wall_node.add_child(outline)

	# Border frame
	var border = (grid_size + 1) * block_size
	var frame_data = [
		[Vector3(0, (half + 1) * block_size, 0), Vector3(border, block_size * 0.5, block_size * 0.5)],
		[Vector3(0, -(half + 1) * block_size, 0), Vector3(border, block_size * 0.5, block_size * 0.5)],
		[Vector3((half + 1) * block_size, 0, 0), Vector3(block_size * 0.5, border + block_size, block_size * 0.5)],
		[Vector3(-(half + 1) * block_size, 0, 0), Vector3(block_size * 0.5, border + block_size, block_size * 0.5)],
	]
	for fd in frame_data:
		var frame = MeshInstance3D.new()
		var fbox = BoxMesh.new()
		fbox.size = fd[1]
		frame.mesh = fbox
		frame.position = fd[0]
		var fmat = StandardMaterial3D.new()
		fmat.albedo_color = Color(0.5, 0.45, 0.6)
		frame.set_surface_override_material(0, fmat)
		wall_node.add_child(frame)

	add_child(wall_node)

func _process(delta):
	if game_state == 0 or game_state == 2:
		# Idle shape spin on title
		if shape_node and is_instance_valid(shape_node):
			shape_node.rotation.y += delta * 0.8
		return

	if not round_active:
		# Still tick animation even between rounds
		_tick_rotation_anim(delta)
		return

	# Rotation animation
	_tick_rotation_anim(delta)

	# Move wall
	wall_z += wall_speed * delta
	if wall_node:
		wall_node.position.z = wall_z

	# Wall reached shape position — check fit
	if wall_z >= wall_z_end:
		round_active = false
		_check_fit()

	hud.update_score(points)
	hud.update_level(level)
	hud.update_lives(lives)

	# Speed indicator — wall proximity warning
	var progress = (wall_z - wall_z_start) / (wall_z_end - wall_z_start)
	if progress > 0.7:
		var pulse = sin(Time.get_ticks_msec() / 100.0) * 0.5 + 0.5
		hud.set_urgency(pulse)
	else:
		hud.set_urgency(0.0)

func _check_fit():
	var current_sil = _project_silhouette(shape_blocks)
	var fits = _silhouettes_match(current_sil, wall_hole)

	if fits:
		points += 100 * level
		_spawn_pass_effect(true)
		hud.show_feedback("PERFECT!", Color(0.2, 1.0, 0.4))
		level += 1
		get_tree().create_timer(1.2).timeout.connect(_spawn_round)
	else:
		lives -= 1
		_spawn_pass_effect(false)
		hud.update_lives(lives)
		if lives <= 0:
			game_state = 2
			hud.show_game_over(points, level)
			_submit_and_save()
		else:
			hud.show_feedback("MISS!", Color(1.0, 0.3, 0.2))
			get_tree().create_timer(1.2).timeout.connect(_spawn_round)

func _spawn_pass_effect(success: bool):
	var flash = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(7, 7, 0.2)
	flash.mesh = box_mesh
	flash.position = Vector3(0, 0.5, wall_z_end)
	var mat = StandardMaterial3D.new()
	if success:
		mat.albedo_color = Color(0.2, 1.0, 0.4, 0.7)
	else:
		mat.albedo_color = Color(1.0, 0.2, 0.1, 0.7)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.set_surface_override_material(0, mat)
	add_child(flash)

	var tween = create_tween()
	tween.tween_property(flash, "scale", Vector3(2, 2, 2), 0.6)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tween.tween_callback(flash.queue_free)

	# Also animate shape through wall on success
	if success and shape_node and is_instance_valid(shape_node):
		var stween = create_tween()
		stween.tween_property(shape_node, "position:z", -5.0, 0.5)
		stween.parallel().tween_property(shape_node, "modulate", Color(1,1,1,0), 0.5)

func _input(event):
	if game_state == 2:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			_restart()
		return

	if game_state == 0:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			game_state = 1
			hud.hide_center()
			_spawn_round()
		return

	if not round_active:
		return

	# Touch/mouse for rotation
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_touching = true
			touch_start = event.position
			touch_start_time = Time.get_ticks_msec() / 1000.0
		else:
			if is_touching:
				_handle_swipe(event.position)
			is_touching = false

	if event is InputEventScreenTouch:
		if event.pressed:
			is_touching = true
			touch_start = event.position
			touch_start_time = Time.get_ticks_msec() / 1000.0
		else:
			if is_touching:
				_handle_swipe(event.position)
			is_touching = false

func _handle_swipe(end_pos: Vector2):
	var swipe = end_pos - touch_start
	var swipe_len = swipe.length()

	if swipe_len < 40:
		# Tap — rotate around Z axis (face rotation)
		_rotate_shape(2)
		return

	var abs_x = abs(swipe.x)
	var abs_y = abs(swipe.y)

	if abs_x > abs_y:
		# Horizontal swipe — rotate Y
		if swipe.x > 0:
			_rotate_shape(1)
		else:
			# Reverse Y rotation (3x = -90)
			_rotate_shape(1)
			_rotate_shape(1)
			_rotate_shape(1)
	else:
		# Vertical swipe — rotate X
		if swipe.y > 0:
			_rotate_shape(0)
		else:
			_rotate_shape(0)
			_rotate_shape(0)
			_rotate_shape(0)

func _rotate_shape(axis: int):
	if is_animating:
		return  # ignore input during animation

	# Compute new blocks (rotated + centered)
	shape_blocks = _rotate_blocks(shape_blocks, axis)
	shape_blocks = _center_blocks(shape_blocks)

	# Rebuild visual immediately with final block positions
	_rebuild_shape_visual()

	# Apply inverse rotation so it visually looks like before,
	# then animate from inverse back to identity
	var axis_vec := Vector3.ZERO
	if axis == 0:
		axis_vec = Vector3.RIGHT
	elif axis == 1:
		axis_vec = Vector3.UP
	else:
		axis_vec = Vector3.FORWARD
	anim_from_rotation = Quaternion(axis_vec, -PI / 2.0)
	anim_to_rotation = Quaternion.IDENTITY
	shape_node.quaternion = anim_from_rotation

	anim_progress = 0.0
	is_animating = true

func _tick_rotation_anim(delta: float):
	if not is_animating:
		return
	if not shape_node or not is_instance_valid(shape_node):
		is_animating = false
		return

	anim_progress += delta / anim_duration
	if anim_progress >= 1.0:
		is_animating = false
		shape_node.quaternion = Quaternion.IDENTITY
	else:
		shape_node.quaternion = anim_from_rotation.slerp(anim_to_rotation, anim_progress)

func _rebuild_shape_visual():
	if shape_node and is_instance_valid(shape_node):
		# Remove old cubes
		for child in shape_node.get_children():
			child.queue_free()

		# Add new cubes
		for b in shape_blocks:
			var cube = MeshInstance3D.new()
			var box_mesh = BoxMesh.new()
			box_mesh.size = Vector3.ONE * block_size * 0.88
			cube.mesh = box_mesh
			cube.position = Vector3(b.x, b.y, b.z) * block_size
			var mat = StandardMaterial3D.new()
			mat.albedo_color = shape_color
			mat.emission_enabled = true
			mat.emission = shape_color * 0.4
			mat.emission_energy_multiplier = 0.5
			cube.set_surface_override_material(0, mat)
			shape_node.add_child(cube)

		# Reset idle rotation so visual matches logic
		shape_node.rotation = Vector3.ZERO

func _submit_and_save():
	if _score_submitted or points <= 0:
		return
	_score_submitted = true
	if Api:
		Api.submit_score(points, func(ok, _result): print("[api] score submit: ", ok))
		Api.save_state(level, {"points": points, "level": level}, func(ok, _result): print("[api] state save: ", ok))

func _restart():
	game_state = 1
	hud.hide_center()
	_score_submitted = false
	points = 0
	level = 1
	lives = 3
	wall_speed = 4.0
	_spawn_round()
