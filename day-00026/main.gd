extends Node3D

# === GAME STATE ===
var game_state := 0  # 0=ready, 1=playing, 2=dead
var points := 0
var wave := 1
var enemies_this_wave := 3
var enemies_spawned := 0
var enemies_alive := 0
var wave_cooldown := 0.0
var combo := 0
var combo_timer := 0.0

# === PLAYER ===
var player_pos := Vector3.ZERO
var player_hp := 100.0
var player_max_hp := 100.0
var player_mesh: MeshInstance3D
var player_attack_timer := 0.0
var player_attack_dir := Vector3.ZERO
var player_invuln := 0.0
var player_stun := 0.0
var player_target_pos := Vector3.ZERO

# === ENEMIES ===
var enemies: Array = []

# === ARENA ===
var arena_radius := 7.0
var camera: Camera3D
var hud: Node

# === TOUCH ===
var touch_start := Vector2.ZERO
var touch_start_time := 0.0
var is_touching := false

# === VISUAL ===
var hit_effects: Array = []
var damage_numbers: Array = []
var screen_shake := 0.0

var _score_submitted := false

func _ready():
	# Camera - isometric-ish view
	camera = Camera3D.new()
	camera.position = Vector3(0, 14, 10)
	camera.rotation_degrees = Vector3(-50, 0, 0)
	add_child(camera)
	
	# Lights
	var dir_light = DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-40, -20, 0)
	dir_light.shadow_enabled = true
	dir_light.light_energy = 1.2
	add_child(dir_light)
	
	var env_node = WorldEnvironment.new()
	var environment = Environment.new()
	environment.ambient_light_color = Color(0.4, 0.35, 0.5)
	environment.ambient_light_energy = 0.6
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.06, 0.12)
	env_node.environment = environment
	add_child(env_node)
	
	# Arena floor - octagonal platform
	_build_arena()
	
	# Player
	_build_player()
	
	# HUD
	var hud_script = load("res://hud.gd")
	hud = CanvasLayer.new()
	hud.set_script(hud_script)
	add_child(hud)

	# Start
	game_state = 0
	player_target_pos = Vector3.ZERO
	hud.show_start()

func _build_arena():
	# Main floor
	var floor_mesh = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = arena_radius
	cylinder.bottom_radius = arena_radius + 0.3
	cylinder.height = 0.3
	cylinder.radial_segments = 8
	floor_mesh.mesh = cylinder
	floor_mesh.position = Vector3(0, -0.15, 0)
	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.25, 0.2, 0.3)
	floor_mesh.set_surface_override_material(0, floor_mat)
	add_child(floor_mesh)
	
	# Ring border
	var ring = MeshInstance3D.new()
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = arena_radius - 0.1
	ring_mesh.outer_radius = arena_radius + 0.2
	ring.mesh = ring_mesh
	ring.position = Vector3(0, 0.05, 0)
	var ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.6, 0.15, 0.15)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.4, 0.05, 0.05)
	ring_mat.emission_energy_multiplier = 0.3
	ring.set_surface_override_material(0, ring_mat)
	add_child(ring)
	
	# Corner pillars
	for i in range(8):
		var angle = i * TAU / 8.0
		var pos = Vector3(cos(angle) * (arena_radius + 0.5), 0, sin(angle) * (arena_radius + 0.5))
		var pillar = MeshInstance3D.new()
		var pbox = BoxMesh.new()
		pbox.size = Vector3(0.4, 1.5, 0.4)
		pillar.mesh = pbox
		pillar.position = pos + Vector3(0, 0.75, 0)
		var pmat = StandardMaterial3D.new()
		pmat.albedo_color = Color(0.5, 0.3, 0.15)
		pillar.set_surface_override_material(0, pmat)
		add_child(pillar)

func _build_player():
	player_mesh = MeshInstance3D.new()
	player_mesh.name = "Player"
	
	# Body - capsule
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.4
	player_mesh.mesh = capsule
	player_mesh.position = Vector3(0, 0.7, 0)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.2, 0.6)
	mat.emission_energy_multiplier = 0.3
	player_mesh.set_surface_override_material(0, mat)
	add_child(player_mesh)
	
	# Fists (positive Z = toward camera = visual "front")
	var fist_l = _make_fist(Color(0.9, 0.7, 0.5))
	fist_l.name = "FistL"
	fist_l.position = Vector3(-0.5, 0.6, 0.3)
	player_mesh.add_child(fist_l)

	var fist_r = _make_fist(Color(0.9, 0.7, 0.5))
	fist_r.name = "FistR"
	fist_r.position = Vector3(0.5, 0.6, 0.3)
	player_mesh.add_child(fist_r)

func _make_fist(color: Color) -> MeshInstance3D:
	var fist = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	fist.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	fist.set_surface_override_material(0, mat)
	return fist

func spawn_enemy():
	var angle = randf() * TAU
	var dist = arena_radius - 1.0
	var spawn_pos = Vector3(cos(angle) * dist, 0, sin(angle) * dist)
	
	var enemy = {
		"pos": spawn_pos,
		"hp": 30.0 + wave * 10.0,
		"max_hp": 30.0 + wave * 10.0,
		"speed": 1.5 + wave * 0.2,
		"attack_range": 1.5,
		"attack_timer": 0.0,
		"attack_cooldown": 1.5 - min(wave * 0.05, 0.5),
		"damage": 8.0 + wave * 2.0,
		"mesh": null,
		"hp_bar": null,
		"stun": 0.0,
		"flash": 0.0,
		"type": randi() % 3,  # 0=normal, 1=heavy, 2=fast
		"alive": true
	}
	
	# Vary by type
	if enemy.type == 1:  # Heavy
		enemy.hp *= 1.8
		enemy.max_hp = enemy.hp
		enemy.speed *= 0.6
		enemy.damage *= 1.5
		enemy.attack_cooldown *= 1.3
	elif enemy.type == 2:  # Fast
		enemy.hp *= 0.6
		enemy.max_hp = enemy.hp
		enemy.speed *= 1.6
		enemy.damage *= 0.7
		enemy.attack_cooldown *= 0.7
	
	# Build mesh
	var root = Node3D.new()
	root.position = spawn_pos + Vector3(0, 0.7, 0)
	
	var body = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	
	var colors = [Color(0.8, 0.2, 0.2), Color(0.6, 0.15, 0.5), Color(0.9, 0.5, 0.1)]
	var sizes = [0.35, 0.45, 0.28]
	
	capsule.radius = sizes[enemy.type]
	capsule.height = 1.4 if enemy.type != 1 else 1.6
	body.mesh = capsule
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = colors[enemy.type]
	body.set_surface_override_material(0, mat)
	root.add_child(body)
	
	# Enemy fists
	var fl = _make_fist(Color(0.7, 0.3, 0.3))
	fl.position = Vector3(-0.4, -0.1, -0.2)
	root.add_child(fl)
	var fr = _make_fist(Color(0.7, 0.3, 0.3))
	fr.position = Vector3(0.4, -0.1, -0.2)
	root.add_child(fr)
	
	# HP bar (small box above head)
	var hp_bg = MeshInstance3D.new()
	var hp_box = BoxMesh.new()
	hp_box.size = Vector3(0.8, 0.08, 0.08)
	hp_bg.mesh = hp_box
	hp_bg.position = Vector3(0, 0.9, 0)
	var hp_bg_mat = StandardMaterial3D.new()
	hp_bg_mat.albedo_color = Color(0.2, 0.2, 0.2)
	hp_bg.set_surface_override_material(0, hp_bg_mat)
	root.add_child(hp_bg)
	
	var hp_fill = MeshInstance3D.new()
	hp_fill.mesh = hp_box.duplicate()
	hp_fill.position = Vector3(0, 0.9, 0.02)
	var hp_fill_mat = StandardMaterial3D.new()
	hp_fill_mat.albedo_color = Color(0.1, 0.8, 0.1)
	hp_fill.set_surface_override_material(0, hp_fill_mat)
	root.add_child(hp_fill)
	
	add_child(root)
	enemy.mesh = root
	enemy.hp_bar = hp_fill
	enemies.append(enemy)
	enemies_spawned += 1
	enemies_alive += 1

func _process(delta):
	# Screen shake
	if screen_shake > 0:
		screen_shake -= delta * 8.0
		var shake_amount = screen_shake * 0.15
		camera.position = Vector3(randf_range(-shake_amount, shake_amount), 14 + randf_range(-shake_amount, shake_amount), 10)
	else:
		screen_shake = 0
		camera.position = Vector3(0, 14, 10)
	
	if game_state == 0:
		# Waiting to start - tap to begin
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			game_state = 1
			hud.hide_center()
			_start_wave()
		return
	
	if game_state == 2:
		return
	
	# === PLAYING ===
	
	# HUD updates
	hud.update_hp(player_hp, player_max_hp)
	hud.update_score(points)
	hud.update_wave(wave)
	hud.update_combo(combo)

	# Combo timer
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo = 0
	
	# Player attack animation
	if player_attack_timer > 0:
		player_attack_timer -= delta
		var punch_progress = 1.0 - (player_attack_timer / 0.3)
		var fist_extend = sin(punch_progress * PI) * 0.6
		var fist_node: MeshInstance3D
		if player_attack_timer > 0.15:
			fist_node = player_mesh.get_node("FistR")
		else:
			fist_node = player_mesh.get_node("FistL")
		# Animate fist forward (+Z = toward camera = visual front)
		fist_node.position.z = 0.3 + fist_extend
	else:
		# Reset fist positions
		player_mesh.get_node("FistL").position = Vector3(-0.5, 0.6, 0.3)
		player_mesh.get_node("FistR").position = Vector3(0.5, 0.6, 0.3)
	
	# Player invulnerability
	if player_invuln > 0:
		player_invuln -= delta
		player_mesh.visible = fmod(player_invuln * 10.0, 1.0) > 0.5
	else:
		player_mesh.visible = true
	
	# Player stun
	if player_stun > 0:
		player_stun -= delta
	
	# Move player toward target
	if player_stun <= 0:
		var move_dir = player_target_pos - player_pos
		if move_dir.length() > 0.1:
			var move_speed = 6.0 * delta
			player_pos += move_dir.normalized() * min(move_speed, move_dir.length())
			# Clamp to arena
			if player_pos.length() > arena_radius - 1.0:
				player_pos = player_pos.normalized() * (arena_radius - 1.0)
			player_target_pos = player_pos + move_dir.normalized() * max(0, move_dir.length() - move_speed)
		# Face direction of movement
		if move_dir.length() > 0.2:
			var look_angle = atan2(-move_dir.x, -move_dir.z)
			player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, look_angle, delta * 10.0)
	
	player_mesh.position = Vector3(player_pos.x, 0.7, player_pos.z)
	
	# === ENEMIES ===
	for enemy in enemies:
		if not enemy.alive:
			continue
		
		if enemy.stun > 0:
			enemy.stun -= delta
			if enemy.flash > 0:
				enemy.flash -= delta
				if enemy.mesh.get_child(0) is MeshInstance3D:
					var body_mesh: MeshInstance3D = enemy.mesh.get_child(0)
					var emat: StandardMaterial3D = body_mesh.get_surface_override_material(0)
					if emat:
						emat.emission_energy_multiplier = enemy.flash * 3.0
			continue
		
		var to_player = player_pos - enemy.pos
		var dist = to_player.length()
		
		if dist > enemy.attack_range:
			# Move toward player
			var move = to_player.normalized() * enemy.speed * delta
			enemy.pos += move
			# Clamp to arena
			if enemy.pos.length() > arena_radius - 0.5:
				enemy.pos = enemy.pos.normalized() * (arena_radius - 0.5)
		else:
			# Attack
			enemy.attack_timer -= delta
			if enemy.attack_timer <= 0:
				enemy.attack_timer = enemy.attack_cooldown
				_enemy_attack(enemy)
		
		# Face player
		var look_angle = atan2(-to_player.x, -to_player.z)
		enemy.mesh.position = Vector3(enemy.pos.x, 0.7, enemy.pos.z)
		enemy.mesh.rotation.y = look_angle
		
		# Update HP bar
		var hp_ratio = enemy.hp / enemy.max_hp
		if enemy.hp_bar and enemy.hp_bar.mesh:
			enemy.hp_bar.mesh.size.x = 0.8 * hp_ratio
			enemy.hp_bar.position.x = -0.4 * (1.0 - hp_ratio)
			var hp_mat: StandardMaterial3D = enemy.hp_bar.get_surface_override_material(0)
			if hp_mat:
				hp_mat.albedo_color = Color(1.0 - hp_ratio, hp_ratio, 0.1)
	
	# Update hit effects
	var effects_to_remove := []
	for fx in hit_effects:
		fx.life -= delta
		if fx.life <= 0:
			fx.mesh.queue_free()
			effects_to_remove.append(fx)
		else:
			fx.mesh.position += fx.vel * delta
			fx.mesh.scale *= 0.95
	for fx in effects_to_remove:
		hit_effects.erase(fx)
	
	# Update damage numbers
	var nums_to_remove := []
	for dn in damage_numbers:
		dn.life -= delta
		dn.mesh.position.y += delta * 2.0
		if dn.life <= 0:
			dn.mesh.queue_free()
			nums_to_remove.append(dn)
	for dn in nums_to_remove:
		damage_numbers.erase(dn)
	
	# Wave management
	if enemies_alive <= 0 and enemies_spawned >= enemies_this_wave:
		wave_cooldown -= delta
		if wave_cooldown <= 0:
			wave += 1
			_start_wave()
	
	# Spawn remaining enemies with delay
	if enemies_spawned < enemies_this_wave:
		wave_cooldown -= delta
		if wave_cooldown <= 0:
			spawn_enemy()
			wave_cooldown = 0.8

func _start_wave():
	enemies_this_wave = 2 + wave
	enemies_spawned = 0
	enemies_alive = 0
	wave_cooldown = 1.0
	spawn_enemy()

func _enemy_attack(enemy: Dictionary):
	if player_invuln > 0:
		return
	var dist = (player_pos - enemy.pos).length()
	if dist < enemy.attack_range + 0.5:
		player_hp -= enemy.damage
		player_stun = 0.3
		screen_shake = 1.5
		# Knockback
		var kb_dir = (player_pos - enemy.pos).normalized()
		player_pos += kb_dir * 1.0
		player_target_pos = player_pos
		if player_pos.length() > arena_radius - 1.0:
			player_pos = player_pos.normalized() * (arena_radius - 1.0)
			player_target_pos = player_pos
		
		_spawn_hit_effect(player_pos + Vector3(0, 0.7, 0), Color(1, 0.3, 0.1))
		
		if player_hp <= 0:
			player_hp = 0
			game_state = 2
			screen_shake = 3.0
			hud.show_game_over(points, wave)
			_submit_and_save()

func player_attack(direction: Vector3):
	if player_attack_timer > 0 or player_stun > 0:
		return
	
	player_attack_timer = 0.3
	player_attack_dir = direction
	
	# Face attack direction (negate so fists face toward target)
	if direction.length() > 0.1:
		player_mesh.rotation.y = atan2(-direction.x, -direction.z)
	
	# Check hit enemies
	var hit_any := false
	for enemy in enemies:
		if not enemy.alive:
			continue
		var to_enemy = enemy.pos - player_pos
		var dist = to_enemy.length()
		if dist < 2.0:
			# Check direction (generous cone)
			var dot = to_enemy.normalized().dot(direction.normalized()) if direction.length() > 0.1 else 1.0
			if dot > 0.3 or dist < 1.2:
				var damage = 15.0 + combo * 3.0
				enemy.hp -= damage
				enemy.stun = 0.4
				enemy.flash = 0.4
				
				# Knockback enemy
				var kb = to_enemy.normalized() * 1.5
				enemy.pos += kb
				if enemy.pos.length() > arena_radius - 0.5:
					enemy.pos = enemy.pos.normalized() * (arena_radius - 0.5)
				
				_spawn_hit_effect(enemy.pos + Vector3(0, 0.7, 0), Color(1, 1, 0.3))
				_spawn_damage_number(enemy.pos + Vector3(0, 1.5, 0), int(damage))
				screen_shake = 0.8
				hit_any = true
				
				if enemy.hp <= 0:
					_kill_enemy(enemy)
	
	if hit_any:
		combo += 1
		combo_timer = 2.0

func _kill_enemy(enemy: Dictionary):
	enemy.alive = false
	enemies_alive -= 1
	points += 10 * wave
	if combo > 1:
		points += combo * 5
	
	# Death burst effect
	for i in range(5):
		var vel = Vector3(randf_range(-2, 2), randf_range(1, 3), randf_range(-2, 2))
		_spawn_hit_effect(enemy.pos + Vector3(0, 0.7, 0), Color(1, 0.5, 0.1), vel)
	
	# Remove mesh after brief delay
	if enemy.mesh:
		var tween = create_tween()
		tween.tween_property(enemy.mesh, "scale", Vector3.ZERO, 0.3)
		tween.tween_callback(enemy.mesh.queue_free)
	
	# Clean up dead enemies from array
	var to_remove := []
	for e in enemies:
		if not e.alive and e != enemy:
			to_remove.append(e)
	for e in to_remove:
		enemies.erase(e)

func _spawn_hit_effect(pos: Vector3, color: Color, velocity := Vector3(0, 1, 0)):
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	mesh.mesh = sphere
	mesh.position = pos
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.set_surface_override_material(0, mat)
	add_child(mesh)
	hit_effects.append({"mesh": mesh, "vel": velocity, "life": 0.4})

func _spawn_damage_number(pos: Vector3, value: int):
	# Use a small box as placeholder for damage number
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	var size_factor = 0.1 + min(value, 50) * 0.005
	box.size = Vector3(size_factor * 3, size_factor, size_factor)
	mesh.mesh = box
	mesh.position = pos
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.YELLOW if value < 30 else Color.RED
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 2.0
	mesh.set_surface_override_material(0, mat)
	add_child(mesh)
	damage_numbers.append({"mesh": mesh, "life": 0.8})

func _input(event):
	if game_state == 2:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			_restart()
		return
	
	if game_state == 0:
		return
	
	# Mouse click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_touching = true
			touch_start = event.position
			touch_start_time = Time.get_ticks_msec() / 1000.0
		else:
			if is_touching:
				var swipe = event.position - touch_start
				var duration = Time.get_ticks_msec() / 1000.0 - touch_start_time
				_handle_input(touch_start, event.position, swipe, duration)
			is_touching = false
	
	# Touch
	if event is InputEventScreenTouch:
		if event.pressed:
			is_touching = true
			touch_start = event.position
			touch_start_time = Time.get_ticks_msec() / 1000.0
		else:
			if is_touching:
				var swipe = event.position - touch_start
				var duration = Time.get_ticks_msec() / 1000.0 - touch_start_time
				_handle_input(touch_start, event.position, swipe, duration)
			is_touching = false

func _handle_input(start_pos: Vector2, end_pos: Vector2, swipe: Vector2, duration: float):
	var swipe_len = swipe.length()
	
	if swipe_len > 50 and duration < 0.4:
		# Swipe = dodge roll
		var world_dir = _screen_to_world_dir(swipe)
		player_target_pos = player_pos + world_dir * 3.0
		if player_target_pos.length() > arena_radius - 1.0:
			player_target_pos = player_target_pos.normalized() * (arena_radius - 1.0)
		player_invuln = 0.4
	else:
		# Tap = attack toward tap position
		var world_pos = _screen_to_floor(end_pos)
		var attack_dir = (world_pos - player_pos).normalized()
		player_attack(attack_dir)
		# Also move slightly toward tap
		player_target_pos = player_pos + attack_dir * 1.0
		if player_target_pos.length() > arena_radius - 1.0:
			player_target_pos = player_target_pos.normalized() * (arena_radius - 1.0)

func _screen_to_floor(screen_pos: Vector2) -> Vector3:
	var from = camera.project_ray_origin(screen_pos)
	var dir = camera.project_ray_normal(screen_pos)
	if dir.y == 0:
		return Vector3.ZERO
	var t = -from.y / dir.y
	return from + dir * t

func _screen_to_world_dir(screen_dir: Vector2) -> Vector3:
	# Convert 2D swipe direction to 3D world direction on the floor plane
	# Account for camera angle
	var forward = -camera.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	var right = camera.global_transform.basis.x
	right.y = 0
	right = right.normalized()
	var normalized = screen_dir.normalized()
	return (right * normalized.x + forward * -normalized.y).normalized()

func _submit_and_save():
	if _score_submitted or points <= 0:
		return
	_score_submitted = true
	if Api:
		Api.submit_score(points, func(ok, _result): print("[api] score submit: ", ok))
		Api.save_state(wave, {"points": points, "wave": wave}, func(ok, _result): print("[api] state save: ", ok))

func _restart():
	game_state = 1
	hud.hide_center()
	_score_submitted = false
	points = 0
	wave = 1
	combo = 0
	combo_timer = 0.0
	player_hp = player_max_hp
	player_pos = Vector3.ZERO
	player_target_pos = Vector3.ZERO
	player_mesh.position = Vector3(0, 0.7, 0)
	player_invuln = 1.0
	player_stun = 0.0
	
	for enemy in enemies:
		if enemy.mesh and is_instance_valid(enemy.mesh):
			enemy.mesh.queue_free()
	enemies.clear()
	
	for fx in hit_effects:
		if is_instance_valid(fx.mesh):
			fx.mesh.queue_free()
	hit_effects.clear()
	
	for dn in damage_numbers:
		if is_instance_valid(dn.mesh):
			dn.mesh.queue_free()
	damage_numbers.clear()
	
	_start_wave()
