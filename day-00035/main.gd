extends Node2D

# === CONSTANTS ===
const GAME_DURATION := 60.0
const BALL_RADIUS := 18.0
const GRAVITY := 800.0
const MAX_LAUNCH_SPEED := 900.0
const MIN_LAUNCH_SPEED := 200.0
const MAX_BLOCKS := 150
const MAX_DEBRIS := 60
const MAX_FLOATS := 12
const BOOM_MOVE_SPEED := 4.0  # how fast boom follows tap target
const CHAIN_SEGMENTS := 8

# === GAME STATE ===
var game_state := 0
var game_timer := 0.0
var score := 0
var best_score := 0
var state_timer := 0.0
var title_pulse := 0.0
var blocks_smashed := 0

# === SHOTS ===
var shots_left := 5
const SHOTS_PER_BUILDING := 5

# === COMBO ===
var combo_count := 0
var combo_timer := 0.0  # time since last hit
const COMBO_WINDOW := 2.0  # seconds to chain hits

# === SCREEN ===
var sw := 800.0
var sh := 600.0

# === CRANE ===
var crane_base_x := 0.0
var crane_base_y := 0.0
var boom_angle := -0.4
var boom_angle_target := -0.4
var boom_length := 0.0
var boom_length_target := 0.0
var boom_max_length := 0.0
var boom_tip := Vector2.ZERO

# === BALL ===
var ball_pos := Vector2.ZERO
var ball_vel := Vector2.ZERO
var ball_active := false
var ball_ready := true

# === CHAIN (visual sag points) ===
var chain_points: Array[Vector2] = []

# === POWER BAR ===
var power_bar_active := false
var power_bar_value := 0.0
var power_bar_speed := 2.5
var power_bar_dir := 1.0

# === TOUCH ===
var touching := false
var touch_pos := Vector2.ZERO

# === GROUND ===
var ground_y := 0.0

# === TOWER ===
var tower_x := 0.0
var building_style := 0  # current building color/shape style

# === BLOCKS ===
var b_x := PackedFloat32Array()
var b_y := PackedFloat32Array()
var b_vx := PackedFloat32Array()
var b_vy := PackedFloat32Array()
var b_rot := PackedFloat32Array()
var b_rotv := PackedFloat32Array()
var b_w := PackedFloat32Array()
var b_h := PackedFloat32Array()
var b_r := PackedFloat32Array()
var b_g := PackedFloat32Array()
var b_b := PackedFloat32Array()
var b_alive := []
var b_static := []
var b_hp := PackedFloat32Array()
var b_ground_time := PackedFloat32Array()
var b_star := []  # bool — gold star blocks worth 5x
var b_fixed := []  # bool — immovable reinforced blocks
var num_blocks := 0
var tower_settle_timer := 0.0  # grace period after building spawns

# === SHAKE ===
var shake := 0.0

# === DEBRIS ===
var d_x := PackedFloat32Array()
var d_y := PackedFloat32Array()
var d_vx := PackedFloat32Array()
var d_vy := PackedFloat32Array()
var d_age := PackedFloat32Array()
var d_col := PackedColorArray()
var d_next := 0

# === SCORE FLOATS ===
var f_x := PackedFloat32Array()
var f_y := PackedFloat32Array()
var f_age := PackedFloat32Array()
var f_val := PackedInt32Array()
var f_next := 0

func _ready() -> void:
	b_x.resize(MAX_BLOCKS); b_y.resize(MAX_BLOCKS)
	b_vx.resize(MAX_BLOCKS); b_vy.resize(MAX_BLOCKS)
	b_rot.resize(MAX_BLOCKS); b_rotv.resize(MAX_BLOCKS)
	b_w.resize(MAX_BLOCKS); b_h.resize(MAX_BLOCKS)
	b_r.resize(MAX_BLOCKS); b_g.resize(MAX_BLOCKS); b_b.resize(MAX_BLOCKS)
	b_hp.resize(MAX_BLOCKS); b_ground_time.resize(MAX_BLOCKS)
	b_alive.resize(MAX_BLOCKS); b_static.resize(MAX_BLOCKS)
	b_star.resize(MAX_BLOCKS); b_fixed.resize(MAX_BLOCKS)
	for i in MAX_BLOCKS: b_alive[i] = false; b_static[i] = false; b_ground_time[i] = 0; b_star[i] = false; b_fixed[i] = false

	d_x.resize(MAX_DEBRIS); d_y.resize(MAX_DEBRIS)
	d_vx.resize(MAX_DEBRIS); d_vy.resize(MAX_DEBRIS)
	d_age.resize(MAX_DEBRIS); d_col.resize(MAX_DEBRIS)
	for i in MAX_DEBRIS: d_age[i] = -1.0

	f_x.resize(MAX_FLOATS); f_y.resize(MAX_FLOATS)
	f_age.resize(MAX_FLOATS); f_val.resize(MAX_FLOATS)
	for i in MAX_FLOATS: f_age[i] = -1.0

	for i in CHAIN_SEGMENTS + 1:
		chain_points.append(Vector2.ZERO)

	Api.load_state(func(ok: bool, data) -> void:
		if ok and data and data.has("data"):
			best_score = data["data"].get("points", 0)
			score = best_score
	)

func _get_screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size

# Building style palettes: [base_r, base_g, base_b, variation]
var _styles := [
	[0.75, 0.35, 0.2],   # red brick
	[0.5, 0.55, 0.65],   # blue-grey concrete
	[0.8, 0.7, 0.45],    # sandstone
	[0.4, 0.5, 0.35],    # mossy stone
	[0.65, 0.4, 0.55],   # purple brick
	[0.85, 0.55, 0.2],   # orange clay
]

func _place_block(px: float, py: float, bw: float, bh: float, cr: float, cg: float, cb: float, is_star: bool = false, is_fixed: bool = false) -> void:
	var slot := -1
	for i in MAX_BLOCKS:
		if not b_alive[i]: slot = i; break
	if slot < 0: return
	b_x[slot] = px; b_y[slot] = py
	b_vx[slot] = 0; b_vy[slot] = 0; b_rot[slot] = 0; b_rotv[slot] = 0
	b_w[slot] = bw; b_h[slot] = bh; b_hp[slot] = 1.0
	b_r[slot] = cr; b_g[slot] = cg; b_b[slot] = cb; b_ground_time[slot] = 0
	b_star[slot] = is_star; b_fixed[slot] = is_fixed
	b_alive[slot] = true; b_static[slot] = true
	if slot >= num_blocks: num_blocks = slot + 1

func _build_tower() -> void:
	building_style = randi() % _styles.size()
	var palette: Array = _styles[building_style]
	var br: float = palette[0]; var bg: float = palette[1]; var bb: float = palette[2]
	var btype := randi() % 5  # no bridge (type 4)

	var bw := randf_range(38, 52)
	var bh := randf_range(18, 26)
	var cx := tower_x
	shots_left = SHOTS_PER_BUILDING
	tower_settle_timer = 0.5  # half second grace period

	match btype:
		0: _build_office(cx, bw, bh, br, bg, bb)
		1: _build_house(cx, bw, bh, br, bg, bb)
		2: _build_tower_shape(cx, bw, bh, br, bg, bb)
		3: _build_pyramid(cx, bw, bh, br, bg, bb)
		4: _build_skyscraper(cx, bw, bh, br, bg, bb)

	# Assign star blocks — pick 2-4 blocks, preferring higher rows
	var alive_slots: Array[int] = []
	for i in num_blocks:
		if b_alive[i] and b_static[i]: alive_slots.append(i)
	# Sort by Y ascending (highest first)
	alive_slots.sort_custom(func(a: int, b: int) -> bool: return b_y[a] < b_y[b])
	var star_count := mini(randi_range(2, 4), alive_slots.size())
	# Place stars in the top third of the building
	var top_third := maxi(1, alive_slots.size() / 3)
	for s in star_count:
		var idx := alive_slots[randi() % top_third]
		b_star[idx] = true
		# Gold color override
		b_r[idx] = 0.95; b_g[idx] = 0.8; b_b[idx] = 0.2

func _rc(base: float) -> float:
	return clampf(base + randf_range(-0.06, 0.06), 0, 1)

func _build_office(cx: float, bw: float, bh: float, br: float, bg: float, bb: float) -> void:
	var cols := randi_range(3, 5)
	var rows := randi_range(6, 10)
	for row in rows:
		for col in cols:
			var offset := bw * 0.5 if row % 2 == 1 else 0.0
			var px := cx + col * (bw + 2) - (cols * (bw + 2)) * 0.5 + offset
			var py := ground_y - row * (bh + 1) - bh * 0.5
			var t := float(row) / float(rows)
			# Bottom row is reinforced foundation
			var fixed := (row == 0)
			var cr := _rc(br + t * 0.1) if not fixed else 0.4
			var cg := _rc(bg + t * 0.08) if not fixed else 0.4
			var cb := _rc(bb + t * 0.04) if not fixed else 0.45
			_place_block(px, py, bw + randf_range(-2, 2), bh + randf_range(-1, 1),
				cr, cg, cb, false, fixed)

func _build_house(cx: float, bw: float, bh: float, br: float, bg: float, bb: float) -> void:
	var base_cols := 4
	var rows := randi_range(5, 8)
	for row in rows:
		var cols := base_cols
		if row >= rows - 2: cols = maxi(1, base_cols - (row - (rows - 3)))
		for col in cols:
			var row_w := cols * (bw + 2)
			var px := cx + col * (bw + 2) - row_w * 0.5
			var py := ground_y - row * (bh + 1) - bh * 0.5
			var t := float(row) / float(rows)
			# Corner pillars are fixed
			var fixed := (row < 3 and (col == 0 or col == cols - 1))
			var cr := _rc(br + t * 0.15) if not fixed else 0.4
			var cg := _rc(bg + t * 0.1) if not fixed else 0.4
			var cb := _rc(bb) if not fixed else 0.45
			_place_block(px, py, bw + randf_range(-2, 2), bh + randf_range(-1, 1),
				cr, cg, cb, false, fixed)

func _build_tower_shape(cx: float, bw: float, bh: float, br: float, bg: float, bb: float) -> void:
	var cols := 2
	var rows := randi_range(10, 15)
	for row in rows:
		for col in cols:
			var px := cx + col * (bw + 2) - (cols * (bw + 2)) * 0.5
			var py := ground_y - row * (bh + 1) - bh * 0.5
			var t := float(row) / float(rows)
			# Every 4th row is reinforced (steel beams)
			var fixed := (row % 4 == 0)
			var cr := _rc(br + t * 0.12) if not fixed else 0.35
			var cg := _rc(bg + t * 0.1) if not fixed else 0.38
			var cb := _rc(bb + t * 0.05) if not fixed else 0.45
			_place_block(px, py, bw + randf_range(-2, 2), bh + randf_range(-1, 1),
				cr, cg, cb, false, fixed)
	_place_block(cx, ground_y - rows * (bh + 1) - bh, bw * 0.3, bh * 2,
		_rc(br - 0.2), _rc(bg - 0.2), _rc(bb - 0.1))

func _build_pyramid(cx: float, bw: float, bh: float, br: float, bg: float, bb: float) -> void:
	# Wide base pyramid
	var base_cols := 6
	var rows := base_cols
	for row in rows:
		var cols := base_cols - row
		if cols < 1: break
		for col in cols:
			var row_w := cols * (bw + 2)
			var px := cx + col * (bw + 2) - row_w * 0.5
			var py := ground_y - row * (bh + 1) - bh * 0.5
			var t := float(row) / float(rows)
			_place_block(px, py, bw + randf_range(-2, 2), bh + randf_range(-1, 1),
				_rc(br + t * 0.2), _rc(bg + t * 0.15), _rc(bb + t * 0.05))

func _build_bridge(cx: float, bw: float, bh: float, br: float, bg: float, bb: float) -> void:
	var pillar_h := randi_range(4, 7)
	var span_w := 4
	# Pillars are fully reinforced
	for row in pillar_h:
		var px := cx - (span_w * 0.5) * (bw + 2) - bw * 0.5
		var py := ground_y - row * (bh + 1) - bh * 0.5
		_place_block(px, py, bw, bh, 0.4, 0.4, 0.45, false, true)
	for row in pillar_h:
		var px := cx + (span_w * 0.5) * (bw + 2) + bw * 0.5
		var py := ground_y - row * (bh + 1) - bh * 0.5
		_place_block(px, py, bw, bh, 0.4, 0.4, 0.45, false, true)
	# Span is destructible
	var span_y := ground_y - pillar_h * (bh + 1) - bh * 0.5
	for col in span_w + 2:
		var px := cx + col * (bw + 2) - ((span_w + 2) * (bw + 2)) * 0.5
		_place_block(px, span_y, bw + randf_range(-2, 2), bh,
			_rc(br + 0.1), _rc(bg + 0.1), _rc(bb + 0.05))
	for col in span_w:
		var px := cx + col * (bw + 2) - (span_w * (bw + 2)) * 0.5
		_place_block(px, span_y - bh - 1, bw, bh,
			_rc(br + 0.15), _rc(bg + 0.12), _rc(bb + 0.06))

func _build_skyscraper(cx: float, bw: float, bh: float, br: float, bg: float, bb: float) -> void:
	var tiers := [[4, 4], [3, 5], [2, 4]]
	var cur_y := ground_y
	for tier_idx in tiers.size():
		var tier: Array = tiers[tier_idx]
		var cols: int = tier[0]
		var rows: int = tier[1]
		for row in rows:
			for col in cols:
				var row_w := cols * (bw + 2)
				var px := cx + col * (bw + 2) - row_w * 0.5
				var py := cur_y - row * (bh + 1) - bh * 0.5
				var t := float(tier_idx) / 3.0
				# First row of each tier is a reinforced floor slab
				var fixed := (row == 0)
				var cr := _rc(br + t * 0.15) if not fixed else 0.38
				var cg := _rc(bg + t * 0.12) if not fixed else 0.4
				var cb := _rc(bb + t * 0.06) if not fixed else 0.47
				_place_block(px, py, bw + randf_range(-2, 2), bh + randf_range(-1, 1),
					cr, cg, cb, false, fixed)
			cur_y -= (bh + 1)

func _update_boom_tip() -> void:
	boom_tip = Vector2(
		crane_base_x + cos(boom_angle) * boom_length,
		crane_base_y + sin(boom_angle) * boom_length
	)

func _update_chain() -> void:
	# Chain from boom_tip to ball_pos with sag
	var start := boom_tip
	var end := ball_pos
	var chain_dir := (end - start)
	var chain_len := chain_dir.length()
	var perp := chain_dir.normalized().rotated(PI * 0.5) if chain_len > 1 else Vector2.DOWN
	for i in CHAIN_SEGMENTS + 1:
		var t := float(i) / float(CHAIN_SEGMENTS)
		var base_pt := start.lerp(end, t)
		# Sag: parabolic, max at middle
		var sag := sin(t * PI) * minf(chain_len * 0.08, 15.0)
		chain_points[i] = base_pt + perp * sag

func _start_game() -> void:
	game_state = 1; state_timer = 0; game_timer = GAME_DURATION
	blocks_smashed = 0; score = 0; shake = 0
	ball_active = false; ball_ready = true
	power_bar_active = false; touching = false
	combo_count = 0; combo_timer = 0; shots_left = SHOTS_PER_BUILDING
	boom_angle = -0.4; boom_angle_target = -0.4
	boom_length = boom_max_length * 0.5
	boom_length_target = boom_length

	for i in MAX_BLOCKS: b_alive[i] = false; b_static[i] = false; b_ground_time[i] = 0; b_star[i] = false; b_fixed[i] = false
	num_blocks = 0
	_build_tower()
	_update_boom_tip()
	ball_pos = boom_tip

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var pos: Vector2 = event.position
		if event.pressed:
			touching = true; touch_pos = pos

			if game_state == 0: _start_game(); return
			if game_state == 2 and state_timer > 1.0: game_state = 0; return

			if game_state == 1:
				if power_bar_active:
					# Lock in power and launch!
					var power := power_bar_value
					var spd: float = lerp(MIN_LAUNCH_SPEED, MAX_LAUNCH_SPEED, power)
					var launch_angle := boom_angle - 0.1
					ball_vel = Vector2(cos(launch_angle), sin(launch_angle)) * spd
					ball_active = true; ball_ready = false
					power_bar_active = false
					shots_left -= 1
					return

				# Check tap on ball
				if not ball_active and ball_ready:
					var dist_to_ball := pos.distance_to(ball_pos)
					if dist_to_ball < BALL_RADIUS * 4:
						power_bar_active = true
						power_bar_value = 0.0; power_bar_dir = 1.0
						return

				# Otherwise: set boom target toward tap position
				_set_boom_target(pos)
		else:
			touching = false

	if event is InputEventMouseMotion and touching and not power_bar_active:
		touch_pos = event.position
		if game_state == 1 and not ball_active:
			_set_boom_target(touch_pos)

func _set_boom_target(pos: Vector2) -> void:
	var dx := pos.x - crane_base_x
	var dy := pos.y - crane_base_y
	boom_angle_target = atan2(dy, maxf(dx, 10))
	boom_angle_target = clampf(boom_angle_target, -1.3, -0.05)
	var dist := sqrt(dx * dx + dy * dy)
	boom_length_target = clampf(dist, boom_max_length * 0.4, boom_max_length * 0.75)

func _process(delta: float) -> void:
	var vp := _get_screen_size()
	sw = vp.x; sh = vp.y
	ground_y = sh - 35
	crane_base_x = sw * 0.08
	crane_base_y = ground_y - 10
	boom_max_length = sw * 0.4
	tower_x = sw * 0.72

	_update_debris(delta); _update_floats(delta)
	shake *= 0.9

	match game_state:
		0: _process_title(delta)
		1: _process_playing(delta)
		2: _process_gameover(delta)

	queue_redraw()

func _process_title(delta: float) -> void:
	title_pulse += delta * 3.0; state_timer += delta
	boom_angle = -0.3 + sin(state_timer) * 0.15
	boom_length = boom_max_length * (0.5 + sin(state_timer * 0.7) * 0.1)
	_update_boom_tip(); ball_pos = boom_tip; _update_chain()

func _process_playing(delta: float) -> void:
	state_timer += delta; game_timer -= delta

	# Tower settle grace period
	if tower_settle_timer > 0:
		tower_settle_timer -= delta

	# Combo decay
	if combo_count > 0:
		combo_timer += delta
		if combo_timer > COMBO_WINDOW:
			combo_count = 0

	# Smooth boom movement toward target
	boom_angle = lerp(boom_angle, boom_angle_target, BOOM_MOVE_SPEED * delta)
	boom_length = lerp(boom_length, boom_length_target, BOOM_MOVE_SPEED * delta)
	_update_boom_tip()

	# Power bar
	if power_bar_active:
		power_bar_value += power_bar_dir * power_bar_speed * delta
		if power_bar_value >= 1.0: power_bar_value = 1.0; power_bar_dir = -1.0
		elif power_bar_value <= 0.0: power_bar_value = 0.0; power_bar_dir = 1.0

	# Ball
	if not ball_active:
		ball_pos = boom_tip
	else:
		ball_vel.y += GRAVITY * delta
		ball_pos += ball_vel * delta

		if ball_pos.y > ground_y - BALL_RADIUS:
			ball_pos.y = ground_y - BALL_RADIUS
			ball_vel.y *= -0.3; ball_vel.x *= 0.85; shake = maxf(shake, 0.5)
			if absf(ball_vel.y) < 15 and absf(ball_vel.x) < 10:
				ball_active = false; ball_ready = true
		if ball_pos.y < BALL_RADIUS:
			ball_pos.y = BALL_RADIUS; ball_vel.y = absf(ball_vel.y) * 0.3
		if ball_pos.x > sw - BALL_RADIUS:
			ball_pos.x = sw - BALL_RADIUS; ball_vel.x *= -0.5
		if ball_pos.x < BALL_RADIUS:
			ball_active = false; ball_ready = true
		if ball_pos.y > sh + 50:
			ball_active = false; ball_ready = true

	_update_chain()

	# Block collision
	if ball_active:
		var ball_speed := ball_vel.length()
		for i in num_blocks:
			if not b_alive[i]: continue
			var dx := ball_pos.x - b_x[i]; var dy := ball_pos.y - b_y[i]
			var dist := sqrt(dx * dx + dy * dy)
			var min_dist := BALL_RADIUS + maxf(b_w[i], b_h[i]) * 0.45
			if dist < min_dist and dist > 0:
				if ball_speed < 20 and b_static[i]: continue
				var nx := -dx / dist; var ny := -dy / dist

				if b_fixed[i]:
					# Bounce off fixed blocks — no damage, just deflect
					ball_vel = ball_vel.bounce(Vector2(nx, ny)) * 0.6
					shake = maxf(shake, 0.3)
					_spawn_debris(b_x[i], b_y[i], Color(0.5, 0.5, 0.55), 1)
				else:
					var impulse := clampf(ball_speed * 0.3, 40, 350)
					b_static[i] = false
					b_vx[i] += nx * impulse; b_vy[i] += ny * impulse
					b_rotv[i] += randf_range(-5, 5); b_hp[i] -= 0.5
					shake = clampf(ball_speed * 0.004, shake, 3.0)
					blocks_smashed += 1
					combo_count += 1; combo_timer = 0
					var multiplier := mini(combo_count, 10)
					var base_pts := 50 if b_star[i] else 10
					var pts := base_pts * multiplier
					score += pts
					f_x[f_next] = b_x[i]; f_y[f_next] = b_y[i]
					f_val[f_next] = pts; f_age[f_next] = 0.0
					f_next = (f_next + 1) % MAX_FLOATS
					_spawn_debris(b_x[i], b_y[i], Color(b_r[i], b_g[i], b_b[i]), 3)
					ball_vel = ball_vel.bounce(Vector2(nx, ny)) * 0.65

	# Block physics
	for i in num_blocks:
		if not b_alive[i]: continue

		if b_static[i]:
			if b_fixed[i]: continue
			# Skip support checks during settle period
			if tower_settle_timer > 0: continue
			# Check if block has support
			var has_support := false
			if b_y[i] + b_h[i] * 0.5 >= ground_y - 5:
				has_support = true
			else:
				for j in num_blocks:
					if j == i or not b_alive[j] or not b_static[j]: continue
					# Horizontal overlap check
					if absf(b_x[i] - b_x[j]) < (b_w[i] + b_w[j]) * 0.5:
						# Block j is below block i and close enough vertically
						if b_y[j] > b_y[i] and b_y[j] - b_y[i] < (b_h[i] + b_h[j]) * 0.5 + 8:
							has_support = true; break
			if not has_support:
				b_static[i] = false
				b_vy[i] = 10
			continue

		# Non-static physics
		b_vy[i] += 700 * delta
		b_x[i] += b_vx[i] * delta; b_y[i] += b_vy[i] * delta
		b_rot[i] += b_rotv[i] * delta
		b_vx[i] *= 0.99; b_rotv[i] *= 0.98

		if b_y[i] > ground_y - b_h[i] * 0.3:
			b_y[i] = ground_y - b_h[i] * 0.3
			b_vy[i] *= -0.15; b_vx[i] *= 0.6; b_rotv[i] *= 0.4
			if abs(b_vy[i]) < 5: b_vy[i] = 0
			if abs(b_vx[i]) < 3: b_vx[i] = 0

		# Auto-destroy blocks that have been sitting still on/near ground
		var ground_spd := absf(b_vx[i]) + absf(b_vy[i])
		if ground_spd < 10 and b_y[i] > ground_y - b_h[i] * 1.5:
			b_ground_time[i] += delta
			if b_ground_time[i] > 1.0:  # 1 second on ground = fade out
				b_alive[i] = false
				_spawn_debris(b_x[i], b_y[i], Color(b_r[i], b_g[i], b_b[i]), 2)
		else:
			b_ground_time[i] = 0

		# Block-on-block
		for j in num_blocks:
			if i == j or not b_alive[j]: continue
			var ddx := b_x[i] - b_x[j]; var ddy := b_y[i] - b_y[j]
			var dd := sqrt(ddx * ddx + ddy * ddy)
			var min_d := (b_w[i] + b_w[j]) * 0.35
			if dd < min_d and dd > 0:
				var nnx := ddx / dd; var nny := ddy / dd
				if b_static[j]:
					if b_fixed[j]: continue  # fixed blocks can't be knocked
					var spd := sqrt(b_vx[i] * b_vx[i] + b_vy[i] * b_vy[i])
					if spd > 20:
						b_static[j] = false
						var knock := clampf(spd * 0.2, 15, 120)
						b_vx[j] = nnx * knock; b_vy[j] = nny * knock - 15
						b_rotv[j] = randf_range(-3, 3)
						blocks_smashed += 1
						combo_count += 1; combo_timer = 0
						var c_mult := mini(combo_count, 10)
						var c_base := 50 if b_star[j] else 10
						var c_pts := c_base * c_mult
						score += c_pts
						f_x[f_next] = b_x[j]; f_y[f_next] = b_y[j]
						f_val[f_next] = c_pts; f_age[f_next] = 0.0
						f_next = (f_next + 1) % MAX_FLOATS
						_spawn_debris(b_x[j], b_y[j], Color(b_r[j], b_g[j], b_b[j]), 2)
				else:
					var overlap := min_d - dd
					b_x[i] += nnx * overlap * 0.5; b_y[i] += nny * overlap * 0.5
					b_x[j] -= nnx * overlap * 0.5; b_y[j] -= nny * overlap * 0.5

		if b_y[i] > sh + 50 or b_x[i] < -100 or b_x[i] > sw + 100:
			b_alive[i] = false
		if b_hp[i] <= 0:
			b_alive[i] = false
			_spawn_debris(b_x[i], b_y[i], Color(b_r[i], b_g[i], b_b[i]), 5)

	# Rebuild — only count breakable static blocks (not fixed)
	var breakable_static := 0; var moving_count := 0
	for i in num_blocks:
		if b_alive[i] and b_static[i] and not b_fixed[i]: breakable_static += 1
		if b_alive[i] and not b_static[i]:
			if absf(b_vx[i]) + absf(b_vy[i]) > 5: moving_count += 1
	if (breakable_static < 3 and moving_count == 0) or (shots_left <= 0 and not ball_active):
		for i in MAX_BLOCKS: b_alive[i] = false; b_static[i] = false; b_ground_time[i] = 0; b_star[i] = false; b_fixed[i] = false
		num_blocks = 0
		# Reset crane and ball
		ball_active = false; ball_ready = true; power_bar_active = false
		boom_angle = -0.4; boom_angle_target = -0.4
		boom_length = boom_max_length * 0.5; boom_length_target = boom_length
		combo_count = 0
		_build_tower()
		_update_boom_tip(); ball_pos = boom_tip

	if game_timer <= 0:
		game_state = 2; state_timer = 0
		best_score = maxi(best_score, score)
		Api.submit_score(score, func(_ok, _r): pass)
		Api.save_state(0, {"points": best_score}, func(_ok, _r): pass)

func _process_gameover(delta: float) -> void:
	state_timer += delta

func _spawn_debris(px: float, py: float, col: Color, count: int) -> void:
	for c in count:
		d_x[d_next] = px + randf_range(-8, 8); d_y[d_next] = py + randf_range(-4, 4)
		d_vx[d_next] = randf_range(-100, 100); d_vy[d_next] = randf_range(-150, -30)
		d_age[d_next] = 0.0; d_col[d_next] = col
		d_next = (d_next + 1) % MAX_DEBRIS

func _update_debris(delta: float) -> void:
	for i in MAX_DEBRIS:
		if d_age[i] < 0: continue
		d_x[i] += d_vx[i] * delta; d_y[i] += d_vy[i] * delta
		d_vy[i] += 400 * delta; d_age[i] += delta
		if d_age[i] > 1.5: d_age[i] = -1.0

func _update_floats(delta: float) -> void:
	for i in MAX_FLOATS:
		if f_age[i] < 0: continue
		f_y[i] -= 40 * delta; f_age[i] += delta
		if f_age[i] > 1.0: f_age[i] = -1.0

func _draw() -> void:
	var so := Vector2(randf_range(-shake, shake) * 8, randf_range(-shake, shake) * 8)

	# Sky
	draw_rect(Rect2(0, 0, sw, sh), Color(0.5, 0.7, 0.92))

	# Ground
	draw_rect(Rect2(so.x, ground_y + so.y, sw, sh - ground_y), Color(0.38, 0.28, 0.2))
	draw_line(Vector2(0, ground_y) + so, Vector2(sw, ground_y) + so, Color(0.48, 0.38, 0.28), 3)

	# Blocks
	for i in num_blocks:
		if not b_alive[i]: continue
		var bpos := Vector2(b_x[i], b_y[i]) + so
		var col := Color(b_r[i], b_g[i], b_b[i])
		if b_static[i]:
			var rect := Rect2(bpos.x - b_w[i] * 0.5, bpos.y - b_h[i] * 0.5, b_w[i], b_h[i])
			draw_rect(rect, col); draw_rect(rect, col.darkened(0.25), true, 1.5)
			# Fixed block: darker with cross-hatch lines
			if b_fixed[i]:
				draw_rect(rect, Color(0, 0, 0, 0.15))
				var lx := bpos.x - b_w[i] * 0.5; var ly := bpos.y - b_h[i] * 0.5
				var rx := bpos.x + b_w[i] * 0.5; var ry := bpos.y + b_h[i] * 0.5
				draw_line(Vector2(lx, ly), Vector2(rx, ry), Color(0.3, 0.3, 0.35, 0.4), 1)
				draw_line(Vector2(rx, ly), Vector2(lx, ry), Color(0.3, 0.3, 0.35, 0.4), 1)
			# Star block glow
			if b_star[i]:
				var glow_alpha := 0.3 + sin(state_timer * 5 + float(i)) * 0.15
				draw_rect(rect, Color(1, 0.9, 0.3, glow_alpha))
				_draw_text(bpos, "*", 14, Color(1, 1, 1, 0.8))
		else:
			var hw := b_w[i] * 0.5; var hh := b_h[i] * 0.5
			var ca := cos(b_rot[i]); var sa := sin(b_rot[i])
			var corners: Array[Vector2] = [
				bpos + Vector2(-hw * ca + hh * sa, -hw * sa - hh * ca),
				bpos + Vector2(hw * ca + hh * sa, hw * sa - hh * ca),
				bpos + Vector2(hw * ca - hh * sa, hw * sa + hh * ca),
				bpos + Vector2(-hw * ca - hh * sa, -hw * sa + hh * ca),
			]
			draw_colored_polygon(PackedVector2Array(corners), col)
			for c in 4:
				draw_line(corners[c], corners[(c + 1) % 4], col.darkened(0.25), 1.5)

	# Crane cab
	var cb := Vector2(crane_base_x, crane_base_y) + so
	draw_rect(Rect2(cb.x - 25, cb.y - 30, 50, 40), Color(0.85, 0.65, 0.1))
	draw_rect(Rect2(cb.x - 25, cb.y - 30, 50, 40), Color(0.7, 0.5, 0.05), true, 2)
	draw_rect(Rect2(cb.x - 15, cb.y - 25, 20, 12), Color(0.55, 0.78, 0.95))
	draw_circle(Vector2(cb.x - 15, cb.y + 12), 8, Color(0.2, 0.2, 0.2))
	draw_circle(Vector2(cb.x + 15, cb.y + 12), 8, Color(0.2, 0.2, 0.2))
	draw_circle(Vector2(cb.x - 15, cb.y + 12), 4, Color(0.35, 0.35, 0.35))
	draw_circle(Vector2(cb.x + 15, cb.y + 12), 4, Color(0.35, 0.35, 0.35))

	# Boom arm
	var boom_start := cb + Vector2(15, -15)
	var bt := boom_tip + so
	draw_line(boom_start, bt, Color(0.75, 0.58, 0.1), 6)
	draw_line(boom_start, bt, Color(0.88, 0.7, 0.2), 3)
	# Boom tip circle
	draw_circle(bt, 5, Color(0.6, 0.45, 0.1))

	# Chain (catenary-style with sag)
	var bp := ball_pos + so
	for s in CHAIN_SEGMENTS:
		var p0 := chain_points[s] + so
		var p1 := chain_points[s + 1] + so
		# Alternate link colors for chain look
		var link_col := Color(0.35, 0.35, 0.4) if s % 2 == 0 else Color(0.28, 0.28, 0.33)
		draw_line(p0, p1, link_col, 3)
		# Small circles at joints
		draw_circle(p0, 2.5, Color(0.4, 0.4, 0.45))
	draw_circle(chain_points[CHAIN_SEGMENTS] + so, 2.5, Color(0.4, 0.4, 0.45))

	# Ball
	draw_circle(bp, BALL_RADIUS + 2, Color(0.15, 0.15, 0.2))
	draw_circle(bp, BALL_RADIUS, Color(0.38, 0.38, 0.43))
	draw_circle(bp + Vector2(-3, -3), BALL_RADIUS * 0.3, Color(0.52, 0.52, 0.57, 0.5))

	# Trajectory preview
	if not ball_active and ball_ready and not power_bar_active and game_state == 1:
		var launch_angle := boom_angle - 0.1
		var mid_speed: float = (MIN_LAUNCH_SPEED + MAX_LAUNCH_SPEED) * 0.5
		var lv: Vector2 = Vector2(cos(launch_angle), sin(launch_angle)) * mid_speed
		var lp := ball_pos
		for dot in 10:
			lp += lv * 0.025; lv.y += GRAVITY * 0.025
			draw_circle(lp + so, 2.5, Color(1, 0.8, 0.3, (1.0 - float(dot) / 10.0) * 0.15))

	# Power bar
	if power_bar_active and game_state == 1:
		var bar_x := bp.x - 40; var bar_y := bp.y - 60
		var bar_w := 16.0; var bar_h := 80.0
		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.2, 0.8))
		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.4, 0.4, 0.45), true, 1.5)
		var fill_h := bar_h * power_bar_value
		var fill_col := Color(0.3, 1, 0.3).lerp(Color(1, 0.2, 0.1), power_bar_value)
		draw_rect(Rect2(bar_x + 2, bar_y + bar_h - fill_h, bar_w - 4, fill_h), fill_col)
		draw_line(Vector2(bar_x - 3, bar_y + bar_h - fill_h),
			Vector2(bar_x + bar_w + 3, bar_y + bar_h - fill_h), Color(1, 1, 1, 0.8), 2)
		_draw_text(Vector2(bp.x, bp.y + BALL_RADIUS + 18), "TAP!", 14,
			Color(1, 0.8, 0.3, 0.6 + sin(state_timer * 8) * 0.3))
		# Live trajectory
		var launch_angle := boom_angle - 0.1
		var spd: float = lerp(MIN_LAUNCH_SPEED, MAX_LAUNCH_SPEED, power_bar_value)
		var lv: Vector2 = Vector2(cos(launch_angle), sin(launch_angle)) * spd
		var lp := ball_pos
		for dot in 15:
			lp += lv * 0.025; lv.y += GRAVITY * 0.025
			draw_circle(lp + so, 3, Color(1, 0.6, 0.2, (1.0 - float(dot) / 15.0) * 0.4))

	# Tap hint on ball
	if ball_ready and not ball_active and not power_bar_active and game_state == 1:
		var hint_alpha := 0.25 + sin(state_timer * 4) * 0.15
		draw_arc(bp, BALL_RADIUS + 8, 0, TAU, 24, Color(1, 0.8, 0.3, hint_alpha), 2)

	# Debris
	for i in MAX_DEBRIS:
		if d_age[i] < 0: continue
		var alpha := 1.0 - d_age[i] / 1.5
		draw_rect(Rect2(d_x[i] + so.x - 3, d_y[i] + so.y - 3, 6, 6),
			Color(d_col[i].r, d_col[i].g, d_col[i].b, alpha))

	# Float text
	for i in MAX_FLOATS:
		if f_age[i] < 0: continue
		var alpha := 1.0 - f_age[i]
		_draw_text(Vector2(f_x[i], f_y[i]) + so, "+" + str(f_val[i]), 18,
			Color(1, 0.9, 0.3, alpha))

	match game_state:
		0: _draw_title()
		1: _draw_hud()
		2: _draw_gameover()

func _draw_title() -> void:
	var cx := sw * 0.5; var pulse := 0.7 + sin(title_pulse) * 0.3
	_draw_text(Vector2(cx, sh * 0.2), "WRECKING BALL", 36, Color(1, 1, 1, pulse))
	_draw_text(Vector2(cx, sh * 0.2 + 42), "demolition time", 18, Color(1, 1, 1, 0.5))
	_draw_text(Vector2(cx, sh * 0.42), "Tap to aim — tap ball to fire!", 14, Color(1, 1, 1, 0.45))
	_draw_text(Vector2(cx, sh * 0.42 + 22), "5 shots per building — aim smart!", 14, Color(1, 0.8, 0.3, 0.45))
	_draw_text(Vector2(cx, sh * 0.42 + 44), "Hit gold blocks for 5x points", 14, Color(0.95, 0.8, 0.2, 0.45))
	_draw_text(Vector2(cx, sh * 0.42 + 66), "Chain hits for combo multiplier!", 14, Color(1, 0.5, 0.1, 0.45))
	var tap_alpha := 0.4 + sin(title_pulse * 1.5) * 0.3
	_draw_text(Vector2(cx, sh * 0.68), "TAP TO BEGIN", 26, Color(1, 1, 1, tap_alpha))
	if best_score > 0:
		_draw_text(Vector2(cx, sh * 0.68 + 35), "BEST: " + str(best_score), 16, Color(1, 1, 1, 0.4))

func _draw_hud() -> void:
	var secs := ceili(maxf(game_timer, 0))
	var timer_col := Color(1, 0.3, 0.2) if secs <= 10 else Color(1, 1, 1, 0.8)
	_draw_text(Vector2(sw * 0.5, 8), str(secs) + "s", 22, timer_col)
	_draw_text(Vector2(sw * 0.5, 32), str(score) + " pts", 16, Color(1, 0.9, 0.3, 0.7))

	# Shots remaining (bottom right)
	for s in SHOTS_PER_BUILDING:
		var sx := sw - 20 - s * 18
		var sy := ground_y + 15
		var col := Color(0.9, 0.7, 0.2) if s < shots_left else Color(0.3, 0.3, 0.3, 0.4)
		draw_circle(Vector2(sx, sy), 6, col)

	# Combo display
	if combo_count > 1:
		var combo_alpha := 1.0 - combo_timer / COMBO_WINDOW
		_draw_text(Vector2(sw * 0.5, 52), "x" + str(mini(combo_count, 10)) + " COMBO!", 18,
			Color(1, 0.5, 0.1, combo_alpha))

	# Blocks remaining counter (top right)
	var remaining := 0
	for i in num_blocks:
		if b_alive[i] and b_static[i] and not b_fixed[i]: remaining += 1
	_draw_text(Vector2(sw - 55, 8), str(remaining) + " left", 14, Color(1, 1, 1, 0.5))

func _draw_gameover() -> void:
	var cx := sw * 0.5
	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, 0.4))
	_draw_text(Vector2(cx, sh * 0.3), "TIME'S UP!", 36, Color(1, 1, 1))
	_draw_text(Vector2(cx, sh * 0.43), str(score) + " points", 28, Color(1, 0.9, 0.3))
	_draw_text(Vector2(cx, sh * 0.43 + 35), str(blocks_smashed) + " blocks  |  best: " + str(best_score), 16, Color(1, 1, 1, 0.7))
	if score >= best_score and score > 0:
		_draw_text(Vector2(cx, sh * 0.57), "NEW BEST!", 22, Color(1, 0.85, 0.3))
	if state_timer > 1.0:
		var tap_alpha := 0.4 + sin(state_timer * 5) * 0.3
		_draw_text(Vector2(cx, sh * 0.72), "TAP TO RETRY", 22, Color(1, 1, 1, tap_alpha))

func _draw_text(pos: Vector2, text: String, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var str_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	font.draw_string(get_canvas_item(), pos + Vector2(-str_size.x * 0.5 + 1, size * 0.35 + 1),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.5))
	font.draw_string(get_canvas_item(), pos + Vector2(-str_size.x * 0.5, size * 0.35),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
