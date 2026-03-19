extends Node3D

# DAY 37: CLAWS — Claw machine with magnetic grab

enum { TITLE, POSITIONING, DROPPING, MAGNETIZING, RISING, SLIDING, RELEASING, GAMEOVER }

# === MACHINE ===
const MW := 3.0
const MD := 2.5
const MH := 3.5
const WALL := 0.08

# === MAGNET ===
const CLAW_REST_Y := 3.2
const CLAW_DROP_SPEED := 3.0
const CLAW_RISE_SPEED := 1.0
const CLAW_SLIDE_SPEED := 2.0
const CLAW_MOVE_SPEED := 4.0
const MIN_DROP_Y := 0.35
const MAGNET_RADIUS := 0.6      # attraction range for prizes
const MAGNET_FORCE := 18.0      # pull strength on prizes
const REPULSE_RADIUS := 0.5     # repulsion range for balls
const REPULSE_FORCE := 8.0      # push strength on balls
const GRAB_DIST := 0.3          # distance to lock on

# === GAME ===
const MAX_ATTEMPTS := 10
const BALL_COUNT := 600
const PRIZE_TOTAL := 8

# === STATE ===
var game_state := TITLE
var score := 0
var best_score := 0
var attempts := MAX_ATTEMPTS
var state_timer := 0.0
var title_pulse := 0.0

# === MAGNET NODES ===
var claw: Node3D
var cable_mesh: MeshInstance3D
var magnet_mesh: MeshInstance3D
var magnet_glow: MeshInstance3D
var magnet_body: AnimatableBody3D
var magnet_active := false

var claw_target := Vector2(0.0, 0.0)
var claw_y := CLAW_REST_Y

# === GRAB ===
var grabbed: RigidBody3D = null
var grab_offset := Vector3.ZERO

# === TOUCH ===
var dragging := false
var drag_start := Vector2.ZERO
var claw_drag_start := Vector2(0, 0)
var has_moved := false

# === CAMERA ===
var cam: Camera3D

# === BODIES ===
var all_bodies: Array[RigidBody3D] = []
var ball_bodies: Array[RigidBody3D] = []
var prize_bodies: Array[RigidBody3D] = []
var prize_values: Dictionary = {}
var prizes_won := 0

# === CHUTE ===
const CHUTE_X := -2.0

# === HUD ===
var hud: CanvasLayer
var hud_draw: Control
var drop_btn_rect := Rect2()

# Ball pit
const BALL_COLOR := Color(0.72, 0.80, 0.88)
const BALL_RADIUS := 0.09
const BALL_MASS := 0.1

# Prize defs: [mesh_type, size, mass, value, color]
var _prize_defs := [
	[1, 0.32, 0.6, 50, Color(0.95, 0.25, 0.25)],
	[1, 0.32, 0.6, 50, Color(0.25, 0.9, 0.35)],
	[2, 0.20, 0.5, 75, Color(0.85, 0.4, 0.9)],
	[2, 0.20, 0.5, 75, Color(0.95, 0.55, 0.15)],
	[0, 0.28, 0.4, 100, Color(0.95, 0.85, 0.2)],
	[0, 0.28, 0.4, 100, Color(0.95, 0.85, 0.2)],
	[1, 0.40, 0.8, 150, Color(0.2, 0.85, 0.95)],
	[1, 0.40, 0.8, 150, Color(0.95, 0.35, 0.55)],
]

# ─────────────────────────── LIFECYCLE ───────────────────────────

func _ready() -> void:
	_create_environment()
	_create_machine()
	_create_magnet()
	_create_balls_and_prizes()
	_create_hud()
	Api.load_state(func(ok: bool, data: Variant) -> void:
		if ok and data and data.has("data"):
			best_score = data["data"].get("points", 0)
	)

# ─────────────────────────── ENVIRONMENT ───────────────────────────

func _create_environment() -> void:
	cam = Camera3D.new()
	cam.position = Vector3(0, 1.75, 7.0)
	cam.look_at(Vector3(0, 1.75, 0))
	cam.fov = 38
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(cam)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.10, 0.15)
	e.ambient_light_color = Color(0.35, 0.32, 0.4)
	e.ambient_light_energy = 0.5
	env.environment = e
	add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 10, 0)
	light.light_color = Color(1.0, 0.95, 0.88)
	light.light_energy = 1.3
	light.shadow_enabled = true
	add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 120, 0)
	fill.light_color = Color(0.6, 0.7, 1.0)
	fill.light_energy = 0.3
	add_child(fill)

# ─────────────────────────── MACHINE ───────────────────────────

func _mat(color: Color, transparent := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 0.12
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _add_wall(pos: Vector3, size: Vector3, color: Color, transparent := false) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _mat(color, transparent)
	body.add_child(mesh)
	add_child(body)

func _create_machine() -> void:
	var frame_c := Color(0.25, 0.22, 0.35)
	var floor_c := Color(0.35, 0.5, 0.4)
	var glass_c := Color(0.5, 0.6, 0.7)

	_add_wall(Vector3(0, -WALL * 0.5, 0), Vector3(MW + WALL * 2, WALL, MD + WALL * 2), floor_c)
	_add_wall(Vector3(0, MH * 0.5, -MD * 0.5 - WALL * 0.5), Vector3(MW + WALL * 2, MH, WALL), frame_c)
	_add_wall(Vector3(-MW * 0.5 - WALL * 0.5, MH * 0.5, 0), Vector3(WALL, MH, MD), frame_c)
	_add_wall(Vector3(MW * 0.5 + WALL * 0.5, MH * 0.5, 0), Vector3(WALL, MH, MD), frame_c)
	_add_wall(Vector3(0, MH * 0.5, MD * 0.5 + WALL * 0.5), Vector3(MW + WALL * 2, MH, WALL), glass_c, true)

	for z_off in [-0.4, 0.4]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(MW, 0.06, 0.06)
		rail.mesh = rm
		rail.material_override = _mat(Color(0.6, 0.6, 0.65))
		rail.position = Vector3(0, CLAW_REST_Y + 0.2, z_off)
		add_child(rail)

	# Chute
	var chute := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.8, 0.6, 1.0)
	chute.mesh = cm
	chute.material_override = _mat(Color(0.3, 0.25, 0.4))
	chute.position = Vector3(CHUTE_X, 0.3, 0.8)
	add_child(chute)

	var label := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.6, 0.35, 0.02)
	label.mesh = lm
	label.material_override = _mat(Color(0.9, 0.8, 0.2))
	label.position = Vector3(CHUTE_X, 0.5, 1.31)
	add_child(label)

# ─────────────────────────── MAGNET ───────────────────────────

func _create_magnet() -> void:
	claw = Node3D.new()
	claw.position = Vector3(0, CLAW_REST_Y, 0)
	add_child(claw)

	# Cable
	cable_mesh = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.02
	cm.height = 0.5
	cable_mesh.mesh = cm
	cable_mesh.material_override = _mat(Color(0.4, 0.4, 0.45))
	cable_mesh.position = Vector3(0, 0.25, 0)
	claw.add_child(cable_mesh)

	# Magnet body — big red horseshoe-style (cylinder + bottom)
	var magnet_base := Node3D.new()
	claw.add_child(magnet_base)

	# Main cylinder body
	magnet_mesh = MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.18
	mm.bottom_radius = 0.22
	mm.height = 0.2
	magnet_mesh.mesh = mm
	var mag_mat := StandardMaterial3D.new()
	mag_mat.albedo_color = Color(0.85, 0.2, 0.15)
	mag_mat.metallic = 0.6
	mag_mat.roughness = 0.3
	magnet_mesh.material_override = mag_mat
	magnet_mesh.position = Vector3(0, -0.1, 0)
	magnet_base.add_child(magnet_mesh)

	# Silver bottom plate
	var plate := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.23
	pm.bottom_radius = 0.20
	pm.height = 0.06
	plate.mesh = pm
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.7, 0.72, 0.75)
	plate_mat.metallic = 0.8
	plate_mat.roughness = 0.2
	plate.material_override = plate_mat
	plate.position = Vector3(0, -0.23, 0)
	magnet_base.add_child(plate)

	# Glow ring (visible when active)
	magnet_glow = MeshInstance3D.new()
	var gm := TorusMesh.new()
	gm.inner_radius = 0.18
	gm.outer_radius = 0.28
	magnet_glow.mesh = gm
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.3, 0.6, 1.0, 0.0)
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.3, 0.5, 1.0)
	glow_mat.emission_energy_multiplier = 2.0
	magnet_glow.material_override = glow_mat
	magnet_glow.position = Vector3(0, -0.26, 0)
	magnet_glow.rotation_degrees.x = 90
	magnet_base.add_child(magnet_glow)

	# Physics body — pushes balls around
	magnet_body = AnimatableBody3D.new()
	magnet_body.sync_to_physics = true
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.23
	cs.height = 0.26
	col.shape = cs
	magnet_body.add_child(col)
	add_child(magnet_body)

# ─────────────────────────── BALLS & PRIZES ───────────────────────────

func _create_balls_and_prizes() -> void:
	for i in BALL_COUNT:
		_spawn_ball()
	for i in _prize_defs.size():
		_spawn_prize(i)

func _spawn_ball() -> void:
	var body := RigidBody3D.new()
	body.mass = BALL_MASS
	body.linear_damp = 1.2
	body.angular_damp = 1.5

	var col := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = BALL_RADIUS
	col.shape = ss
	body.add_child(col)

	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_RADIUS
	sm.height = BALL_RADIUS * 2
	mesh.mesh = sm
	var vary := randf_range(-0.03, 0.03)
	mesh.material_override = _mat(Color(BALL_COLOR.r + vary, BALL_COLOR.g + vary, BALL_COLOR.b + vary))
	body.add_child(mesh)

	body.position = Vector3(
		randf_range(-MW * 0.4, MW * 0.4),
		randf_range(0.15, 2.5),
		randf_range(-MD * 0.35, MD * 0.35)
	)
	add_child(body)
	all_bodies.append(body)
	ball_bodies.append(body)

func _spawn_prize(idx: int) -> void:
	var def: Array = _prize_defs[idx]
	var mesh_type: int = int(def[0])
	var sz: float = float(def[1])
	var mass_val: float = float(def[2])
	var value: int = int(def[3])
	var color: Color = def[4] as Color

	var body := RigidBody3D.new()
	body.mass = mass_val
	body.linear_damp = 0.8
	body.angular_damp = 1.0

	var col := CollisionShape3D.new()
	var mesh := MeshInstance3D.new()

	match mesh_type:
		0:
			var s := SphereShape3D.new()
			s.radius = sz
			col.shape = s
			var m := SphereMesh.new()
			m.radius = sz
			m.height = sz * 2
			mesh.mesh = m
		1:
			var s := BoxShape3D.new()
			s.size = Vector3(sz, sz, sz)
			col.shape = s
			var m := BoxMesh.new()
			m.size = Vector3(sz, sz, sz)
			mesh.mesh = m
		2:
			var s := CylinderShape3D.new()
			s.radius = sz
			s.height = sz * 2.5
			col.shape = s
			var m := CylinderMesh.new()
			m.top_radius = sz
			m.bottom_radius = sz
			m.height = sz * 2.5
			mesh.mesh = m

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.5
	mat.emission_energy_multiplier = 0.8
	mesh.material_override = mat

	body.add_child(col)
	body.add_child(mesh)

	body.position = Vector3(
		randf_range(-MW * 0.35, MW * 0.35),
		randf_range(0.3, 2.0),
		randf_range(-MD * 0.3, MD * 0.3)
	)
	body.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)

	add_child(body)
	all_bodies.append(body)
	prize_bodies.append(body)
	prize_values[body.get_instance_id()] = value

# ─────────────────────────── HUD ───────────────────────────

func _create_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	hud_draw = Control.new()
	hud_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud_draw)
	hud_draw.draw.connect(_draw_hud)

# ─────────────────────────── INPUT ───────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var pos: Vector2 = event.position
		if event.pressed:
			if game_state == TITLE:
				_start_game()
				return
			if game_state == GAMEOVER and state_timer > 1.5:
				game_state = TITLE
				return
			if game_state == POSITIONING:
				var btn_center := drop_btn_rect.get_center()
				var btn_r := drop_btn_rect.size.x * 0.5
				if btn_r > 0 and pos.distance_to(btn_center) < btn_r:
					_drop_claw()
					return
				dragging = true
				has_moved = true
				drag_start = pos
				claw_drag_start = Vector2(claw_target.x, claw_target.y)
		else:
			dragging = false

	if event is InputEventMouseMotion and dragging and game_state == POSITIONING:
		var delta_screen: Vector2 = event.position - drag_start
		var vp := get_viewport().get_visible_rect().size
		var sc := MW / vp.x * 2.5
		claw_target.x = clampf(claw_drag_start.x + delta_screen.x * sc, -MW * 0.42, MW * 0.42)
		claw_target.y = clampf(claw_drag_start.y - delta_screen.y * sc * 0.5, -MD * 0.35, MD * 0.35)

# ─────────────────────────── GAME FLOW ───────────────────────────

func _start_game() -> void:
	game_state = POSITIONING
	state_timer = 0.0
	score = 0
	attempts = MAX_ATTEMPTS
	prizes_won = 0
	claw_target = Vector2(0, 0)
	claw_y = CLAW_REST_Y
	has_moved = false
	grabbed = null
	magnet_active = false

	for p in all_bodies:
		if is_instance_valid(p):
			p.queue_free()
	all_bodies.clear()
	ball_bodies.clear()
	prize_bodies.clear()
	prize_values.clear()
	_create_balls_and_prizes()

func _drop_claw() -> void:
	if attempts <= 0:
		return
	game_state = DROPPING
	state_timer = 0.0
	attempts -= 1
	magnet_active = false

# ─────────────────────────── PROCESS ───────────────────────────

func _process(delta: float) -> void:
	state_timer += delta
	title_pulse += delta

	match game_state:
		TITLE: pass
		POSITIONING: _tick_position(delta)
		DROPPING: _tick_drop(delta)
		MAGNETIZING: _tick_magnetize(delta)
		RISING: _tick_rise(delta)
		SLIDING: _tick_slide(delta)
		RELEASING: _tick_release(delta)
		GAMEOVER: pass

	# Sync magnet physics body
	magnet_body.global_position = claw.position + Vector3(0, -0.15, 0)

	# Update cable length
	var cable_len := CLAW_REST_Y + 0.3 - claw.position.y
	if cable_len > 0.05:
		var cm2: CylinderMesh = cable_mesh.mesh as CylinderMesh
		cm2.height = cable_len
		cable_mesh.position.y = cable_len * 0.5

	# Magnet glow pulsing
	var gmat: StandardMaterial3D = magnet_glow.material_override as StandardMaterial3D
	if magnet_active:
		var pulse := 0.4 + sin(title_pulse * 8.0) * 0.2
		gmat.albedo_color.a = pulse
		gmat.emission_energy_multiplier = 2.0 + sin(title_pulse * 6.0) * 1.0
	else:
		gmat.albedo_color.a = 0.0

	hud_draw.queue_redraw()

func _physics_process(delta: float) -> void:
	if not magnet_active:
		return
	var mag_pos := claw.position + Vector3(0, -0.26, 0)

	# Attract prizes toward magnet
	if grabbed == null:
		for p in prize_bodies:
			if not is_instance_valid(p):
				continue
			var diff := mag_pos - p.global_position
			var dist := diff.length()
			if dist < MAGNET_RADIUS and dist > 0.01:
				var strength := MAGNET_FORCE * (1.0 - dist / MAGNET_RADIUS)
				p.apply_central_force(diff.normalized() * strength)
				# Lock on when close enough
				if dist < GRAB_DIST:
					grabbed = p
					grabbed.freeze = true
					grab_offset = grabbed.global_position - claw.position

	# Repulse balls away from magnet
	for b in ball_bodies:
		if not is_instance_valid(b):
			continue
		var diff := b.global_position - mag_pos
		var dist := diff.length()
		if dist < REPULSE_RADIUS and dist > 0.01:
			var strength := REPULSE_FORCE * (1.0 - dist / REPULSE_RADIUS)
			b.apply_central_force(diff.normalized() * strength)

func _tick_position(delta: float) -> void:
	claw.position.x = lerpf(claw.position.x, claw_target.x, CLAW_MOVE_SPEED * delta)
	claw.position.z = lerpf(claw.position.z, claw_target.y, CLAW_MOVE_SPEED * delta)
	claw.position.y = lerpf(claw.position.y, CLAW_REST_Y, 3.0 * delta)

func _tick_drop(delta: float) -> void:
	claw_y -= CLAW_DROP_SPEED * delta
	claw.position.y = claw_y
	if claw_y <= MIN_DROP_Y:
		claw_y = MIN_DROP_Y
		game_state = MAGNETIZING
		state_timer = 0.0
		magnet_active = true

func _tick_magnetize(delta: float) -> void:
	claw.position.y = claw_y
	# Stick grabbed prize to magnet
	if grabbed and is_instance_valid(grabbed):
		grabbed.global_position = claw.position + grab_offset
	# Wait a moment for magnetic pull, then rise
	if state_timer > 1.2 or (grabbed != null and state_timer > 0.4):
		game_state = RISING
		state_timer = 0.0

func _tick_rise(delta: float) -> void:
	claw_y += CLAW_RISE_SPEED * delta
	claw.position.y = claw_y
	if grabbed and is_instance_valid(grabbed):
		grabbed.global_position = claw.position + grab_offset
	if claw_y >= CLAW_REST_Y:
		claw_y = CLAW_REST_Y
		magnet_active = false
		game_state = SLIDING
		state_timer = 0.0

func _tick_slide(delta: float) -> void:
	claw.position.x = lerpf(claw.position.x, CHUTE_X, CLAW_SLIDE_SPEED * delta)
	claw.position.y = CLAW_REST_Y
	if grabbed and is_instance_valid(grabbed):
		grabbed.global_position = claw.position + grab_offset
	if absf(claw.position.x - CHUTE_X) < 0.15:
		game_state = RELEASING
		state_timer = 0.0

func _tick_release(delta: float) -> void:
	if state_timer > 0.3:
		if grabbed and is_instance_valid(grabbed):
			var val: int = prize_values.get(grabbed.get_instance_id(), 50)
			score += val
			prizes_won += 1
			prize_values.erase(grabbed.get_instance_id())
			prize_bodies.erase(grabbed)
			grabbed.freeze = false
			grabbed.linear_velocity = Vector3(0, -2, 2)
			grabbed = null
		_finish_attempt()

func _finish_attempt() -> void:
	magnet_active = false
	if attempts <= 0:
		game_state = GAMEOVER
		state_timer = 0.0
		best_score = maxi(best_score, score)
		Api.submit_score(score, func(_ok: bool, _r: Variant) -> void: pass)
		Api.save_state(0, {"points": best_score}, func(_ok: bool, _r: Variant) -> void: pass)
	else:
		game_state = POSITIONING
		state_timer = 0.0
		claw_target = Vector2(claw.position.x, claw.position.z)

# ─────────────────────────── HUD ───────────────────────────

func _draw_hud() -> void:
	var vp := hud_draw.get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var ci := hud_draw.get_canvas_item()

	match game_state:
		TITLE:
			hud_draw.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.5))
			_hud_text(ci, font, vp, Vector2(0.5, 0.12), "CLAWS", 38, Color(0.95, 0.85, 0.3))
			_hud_text(ci, font, vp, Vector2(0.5, 0.12 + 42.0 / vp.y), "magnetic claw machine", 16, Color(0.8, 0.75, 0.6, 0.5))
			_hud_text(ci, font, vp, Vector2(0.5, 0.36), "DRAG to move the magnet", 16, Color(0.9, 0.9, 0.85, 0.6))
			_hud_text(ci, font, vp, Vector2(0.5, 0.36 + 26.0 / vp.y), "Tap DROP to lower it", 16, Color(0.9, 0.9, 0.85, 0.6))
			_hud_text(ci, font, vp, Vector2(0.5, 0.36 + 52.0 / vp.y), "It attracts prizes, repels balls!", 16, Color(0.9, 0.9, 0.85, 0.5))
			_hud_text(ci, font, vp, Vector2(0.5, 0.36 + 82.0 / vp.y), "10 attempts — grab all 8 prizes!", 14, Color(0.95, 0.85, 0.3, 0.5))
			var ta := 0.4 + sin(title_pulse * 3.0) * 0.2
			_hud_text(ci, font, vp, Vector2(0.5, 0.72), "TAP TO PLAY", 24, Color(0.95, 0.9, 0.8, ta))
			if best_score > 0:
				_hud_text(ci, font, vp, Vector2(0.5, 0.72 + 30.0 / vp.y), "best: " + str(best_score), 14, Color(0.7, 0.7, 0.65, 0.4))

		POSITIONING, DROPPING, MAGNETIZING, RISING, SLIDING, RELEASING:
			_hud_text(ci, font, vp, Vector2(0.5, 0.03), str(score) + " pts", 18, Color(0.95, 0.85, 0.3, 0.8))
			_hud_text(ci, font, vp, Vector2(0.85, 0.03), str(attempts) + " left", 14, Color(0.8, 0.8, 0.75, 0.6))
			_hud_text(ci, font, vp, Vector2(0.15, 0.03), str(prizes_won) + "/" + str(PRIZE_TOTAL) + " prizes", 14, Color(0.3, 0.9, 0.4, 0.6))

			# DROP button
			if game_state == POSITIONING and has_moved and not dragging:
				var btn_r := minf(vp.x, vp.y) * 0.12
				var btn_center := vp * 0.5
				drop_btn_rect = Rect2(btn_center.x - btn_r, btn_center.y - btn_r, btn_r * 2, btn_r * 2)
				var bp := 0.6 + sin(title_pulse * 3.0) * 0.15
				hud_draw.draw_arc(btn_center, btn_r, 0, TAU, 48, Color(1, 0.9, 0.8, 0.35 * bp), 3.0)
				hud_draw.draw_arc(btn_center, btn_r - 5, 0, TAU, 48, Color(0.9, 0.3, 0.2, 0.12 * bp), 5.0)
				_hud_text(ci, font, vp, Vector2(0.5, 0.5), "DROP", 26, Color(1, 1, 1, 0.55 * bp))
			elif game_state == POSITIONING and not has_moved:
				_hud_text(ci, font, vp, Vector2(0.5, 0.5), "drag to move magnet", 16, Color(0.9, 0.9, 0.85, 0.4))
				drop_btn_rect = Rect2()
			elif game_state == POSITIONING:
				drop_btn_rect = Rect2()

			# Crosshair
			if game_state == POSITIONING:
				var ts := cam.unproject_position(Vector3(claw.position.x, 0.3, claw.position.z))
				var ch := Color(1, 0.9, 0.3, 0.3 + sin(title_pulse * 5.0) * 0.1)
				hud_draw.draw_line(ts + Vector2(-10, 0), ts + Vector2(10, 0), ch, 2)
				hud_draw.draw_line(ts + Vector2(0, -10), ts + Vector2(0, 10), ch, 2)

			match game_state:
				DROPPING:
					_hud_text(ci, font, vp, Vector2(0.5, 0.42), "lowering...", 14, Color(1, 1, 1, 0.35))
				MAGNETIZING:
					var ma := 0.5 + sin(title_pulse * 6.0) * 0.3
					_hud_text(ci, font, vp, Vector2(0.5, 0.42), "MAGNETIZING!", 18, Color(0.3, 0.6, 1.0, ma))
				RISING:
					if grabbed:
						_hud_text(ci, font, vp, Vector2(0.5, 0.42), "got one!", 16, Color(0.3, 0.9, 0.4, 0.6))
					else:
						_hud_text(ci, font, vp, Vector2(0.5, 0.42), "missed!", 16, Color(0.9, 0.3, 0.3, 0.5))
				SLIDING:
					_hud_text(ci, font, vp, Vector2(0.5, 0.42), "to the chute!", 14, Color(1, 0.8, 0.3, 0.4))

		GAMEOVER:
			var a := minf(state_timer * 0.8, 1.0)
			hud_draw.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.5 * a))
			_hud_text(ci, font, vp, Vector2(0.5, 0.25), "GAME OVER", 32, Color(0.95, 0.9, 0.8, a))
			_hud_text(ci, font, vp, Vector2(0.5, 0.38), str(score) + " points", 24, Color(0.95, 0.85, 0.3, a))
			_hud_text(ci, font, vp, Vector2(0.5, 0.38 + 28.0 / vp.y), str(prizes_won) + "/" + str(PRIZE_TOTAL) + " prizes", 16, Color(0.8, 0.8, 0.75, a * 0.6))
			if score >= best_score and score > 0:
				_hud_text(ci, font, vp, Vector2(0.5, 0.52), "NEW BEST!", 20, Color(0.95, 0.8, 0.3, a))
			elif best_score > 0:
				_hud_text(ci, font, vp, Vector2(0.5, 0.52), "best: " + str(best_score), 14, Color(0.7, 0.7, 0.65, a * 0.5))
			if state_timer > 1.5:
				var ta := 0.3 + sin(title_pulse * 3.0) * 0.2
				_hud_text(ci, font, vp, Vector2(0.5, 0.68), "TAP TO RETRY", 22, Color(0.95, 0.9, 0.8, ta))

func _hud_text(ci: RID, font: Font, vp: Vector2, pos_norm: Vector2, text: String, size: int, color: Color) -> void:
	var px := vp * pos_norm
	var ss := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	font.draw_string(ci, px + Vector2(-ss.x * 0.5 + 1, size * 0.35 + 1),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.4))
	font.draw_string(ci, px + Vector2(-ss.x * 0.5, size * 0.35),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
