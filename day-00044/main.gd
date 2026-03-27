extends Node2D

# DAY 44: NINJA GARDEN — Zen Garden + Ninja Training
# Tend your garden (tap plots to plant) while slashing falling leaves.
# No penalties, no death — pure cozy score chasing.

# === CONSTANTS ===
const GAME_DURATION := 180.0
const GRID_COLS := 4
const GRID_ROWS := 3
const LEAF_SPAWN_BASE := 1.2
const LEAF_FALL_SPEED := 60.0
const KUNAI_SPEED := 200.0
const KUNAI_INTERVAL_BASE := 12.0
const GROW_TIME := 15.0  # seconds per growth stage
const SLASH_RADIUS := 35.0
const COMBO_DECAY := 1.5

# Plant types
const PLANT_BAMBOO := 0
const PLANT_BONSAI := 1
const PLANT_CHERRY := 2
const PLANT_ROCK := 3
const PLANT_NAMES := ["Bamboo", "Bonsai", "Cherry Blossom", "Rock Garden"]
const PLANT_BEAUTY := [3, 5, 8, 4]  # beauty per fully grown plant

# === STATE ===
var game_state := 0  # 0=title, 1=playing, 2=gameover
var state_timer := 0.0
var score := 0
var best_score := 0
var game_timer := 0.0
var beauty_score := 0
var slash_score := 0
var combo := 0
var combo_timer := 0.0
var max_combo := 0
var total_slashes := 0
var kunai_deflects := 0

# === SCREEN ===
var sw := 800.0
var sh := 600.0

# === GARDEN GRID ===
# Each cell: {"type": int (-1=empty), "stage": int (0-3), "grow_timer": float}
var garden: Array[Dictionary] = []
var garden_y_start := 0.0  # top of garden area
var cell_w := 0.0
var cell_h := 0.0
var plant_selector_visible := false
var plant_selector_cell := -1

# === FALLING OBJECTS ===
# Leaves: {"p": Vector2, "type": int (0=leaf, 1=petal, 2=kunai), "spd": float, "angle": float, "sway": float, "alive": bool}
var falling: Array[Dictionary] = []
var leaf_timer := 0.0
var kunai_timer := 0.0

# === PARTICLES ===
var particles: Array[Dictionary] = []

# === SLASH TRAIL ===
var slash_points: Array[Vector2] = []
var slash_timer := 0.0

# ─────────────────────────── LIFECYCLE ───────────────────────────

func _ready() -> void:
	Api.load_state(func(ok: bool, data: Variant) -> void:
		if ok and data and data.has("data"):
			best_score = data["data"].get("points", 0)
	)

func _get_ss() -> Vector2:
	return get_viewport().get_visible_rect().size

# ─────────────────────────── GAME FLOW ───────────────────────────

func _start_game() -> void:
	game_state = 1
	state_timer = 0.0
	game_timer = GAME_DURATION
	score = 0
	beauty_score = 0
	slash_score = 0
	combo = 0
	combo_timer = 0.0
	max_combo = 0
	total_slashes = 0
	kunai_deflects = 0
	falling.clear()
	particles.clear()
	slash_points.clear()
	plant_selector_visible = false
	leaf_timer = 0.0
	kunai_timer = 0.0

	# Init garden
	garden.clear()
	for i in GRID_COLS * GRID_ROWS:
		garden.append({"type": -1, "stage": 0, "grow_timer": 0.0})

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if game_state == 0:
			_start_game()
			return
		if game_state == 2 and state_timer > 1.5:
			game_state = 0
			return
		if game_state == 1:
			_handle_tap(event.position)

	if event is InputEventMouseMotion and game_state == 1:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_handle_drag(event.position)

func _handle_tap(pos: Vector2) -> void:
	# Check plant selector first
	if plant_selector_visible:
		var picked := _check_selector_tap(pos)
		if picked >= 0:
			garden[plant_selector_cell]["type"] = picked
			garden[plant_selector_cell]["stage"] = 0
			garden[plant_selector_cell]["grow_timer"] = 0.0
			plant_selector_visible = false
			# Plant particles
			var cp := _cell_center(plant_selector_cell)
			_spawn_burst(cp, Color(0.4, 0.8, 0.3), 6)
			return
		plant_selector_visible = false
		return

	# Check falling objects (slash)
	var slashed := false
	var fi := falling.size() - 1
	while fi >= 0:
		var f: Dictionary = falling[fi]
		if bool(f["alive"]) and Vector2(f["p"]).distance_to(pos) < SLASH_RADIUS:
			_slash_object(fi)
			slashed = true
		fi -= 1

	if slashed:
		return

	# Check garden grid tap
	if pos.y >= garden_y_start:
		var col := int((pos.x) / cell_w)
		var row := int((pos.y - garden_y_start) / cell_h)
		if col >= 0 and col < GRID_COLS and row >= 0 and row < GRID_ROWS:
			var idx := row * GRID_COLS + col
			if int(garden[idx]["type"]) == -1:
				# Show plant selector
				plant_selector_visible = true
				plant_selector_cell = idx
			return

func _handle_drag(pos: Vector2) -> void:
	# Slash trail
	slash_points.append(pos)
	if slash_points.size() > 12:
		slash_points.remove_at(0)
	slash_timer = 0.2

	# Check slash against falling objects
	var fi := falling.size() - 1
	while fi >= 0:
		var f: Dictionary = falling[fi]
		if bool(f["alive"]) and Vector2(f["p"]).distance_to(pos) < SLASH_RADIUS:
			_slash_object(fi)
		fi -= 1

func _slash_object(idx: int) -> void:
	var f: Dictionary = falling[idx]
	f["alive"] = false
	var pos: Vector2 = f["p"]
	var type: int = f["type"]

	combo += 1
	combo_timer = COMBO_DECAY
	max_combo = maxi(max_combo, combo)
	total_slashes += 1

	if type == 2:
		# Kunai deflect!
		kunai_deflects += 1
		var pts := 25 * mini(combo, 10)
		slash_score += pts
		_spawn_burst(pos, Color(1, 0.8, 0.2), 12)
		_spawn_burst(pos, Color(1, 0.4, 0.1), 8)
	else:
		# Leaf/petal
		var pts := 5 * mini(combo, 10)
		slash_score += pts
		var col := Color(0.3, 0.8, 0.2) if type == 0 else Color(1, 0.6, 0.8)
		_spawn_burst(pos, col, 6)

func _check_selector_tap(pos: Vector2) -> int:
	var cp := _cell_center(plant_selector_cell)
	var btn_w := 50.0
	var btn_h := 40.0
	var total := btn_w * 4.0 + 10.0 * 3.0
	var start_x: float = cp.x - total * 0.5
	var btn_y: float = cp.y - btn_h - 20.0

	for i in 4:
		var bx: float = start_x + float(i) * (btn_w + 10.0)
		if pos.x >= bx and pos.x <= bx + btn_w and pos.y >= btn_y and pos.y <= btn_y + btn_h:
			return i
	return -1

func _cell_center(idx: int) -> Vector2:
	var col := idx % GRID_COLS
	var row := idx / GRID_COLS
	return Vector2(float(col) * cell_w + cell_w * 0.5, garden_y_start + float(row) * cell_h + cell_h * 0.5)

# ─────────────────────────── PROCESS ───────────────────────────

func _process(delta: float) -> void:
	var vp := _get_ss()
	sw = vp.x; sh = vp.y
	garden_y_start = sh * 0.55
	cell_w = sw / float(GRID_COLS)
	cell_h = (sh - garden_y_start) / float(GRID_ROWS)
	state_timer += delta

	if game_state == 1:
		_tick_game(delta)

	# Update particles
	var pi := particles.size() - 1
	while pi >= 0:
		var p: Dictionary = particles[pi]
		p["life"] = float(p["life"]) - delta
		p["p"] = Vector2(p["p"]) + Vector2(p["v"]) * delta
		if float(p["life"]) <= 0:
			particles.remove_at(pi)
		pi -= 1

	# Slash trail fade
	if slash_timer > 0:
		slash_timer -= delta
	if slash_timer <= 0:
		slash_points.clear()

	queue_redraw()

func _tick_game(delta: float) -> void:
	game_timer -= delta

	# Combo decay
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo = 0

	# Grow plants
	for i in garden.size():
		var g: Dictionary = garden[i]
		if int(g["type"]) >= 0 and int(g["stage"]) < 3:
			g["grow_timer"] = float(g["grow_timer"]) + delta
			if float(g["grow_timer"]) >= GROW_TIME:
				g["grow_timer"] = 0.0
				g["stage"] = int(g["stage"]) + 1
				if int(g["stage"]) == 3:
					_spawn_burst(_cell_center(i), Color(1, 0.95, 0.5), 8)

	# Calculate beauty
	beauty_score = 0
	for g in garden:
		if int(g["type"]) >= 0:
			var type_idx: int = g["type"]
			var stage: int = g["stage"]
			beauty_score += PLANT_BEAUTY[type_idx] * (stage + 1)

	# Spawn leaves
	var elapsed: float = GAME_DURATION - game_timer
	var leaf_rate: float = LEAF_SPAWN_BASE / (1.0 + elapsed * 0.005)
	leaf_timer += delta
	while leaf_timer > leaf_rate:
		leaf_timer -= leaf_rate
		_spawn_leaf()

	# Spawn kunai
	var kunai_rate: float = KUNAI_INTERVAL_BASE / (1.0 + elapsed * 0.01)
	kunai_timer += delta
	if kunai_timer > kunai_rate:
		kunai_timer = 0.0
		_spawn_kunai()

	# Update falling objects
	var fi := falling.size() - 1
	while fi >= 0:
		var f: Dictionary = falling[fi]
		if not bool(f["alive"]):
			falling.remove_at(fi)
			fi -= 1
			continue
		var fp: Vector2 = f["p"]
		var ftype: int = f["type"]
		if ftype == 2:
			# Kunai — straight fast
			fp.y += KUNAI_SPEED * delta
		else:
			# Leaf/petal — gentle sway
			fp.y += float(f["spd"]) * delta
			fp.x += sin(state_timer * 2.0 + float(f["sway"])) * 30.0 * delta
			f["angle"] = float(f["angle"]) + delta * 1.5
		f["p"] = fp
		# Off screen
		if fp.y > sh + 20:
			falling.remove_at(fi)
		fi -= 1

	# Update score
	score = beauty_score * 10 + slash_score

	# Game over
	if game_timer <= 0:
		game_timer = 0
		game_state = 2
		state_timer = 0.0
		best_score = maxi(best_score, score)
		Api.submit_score(score, func(_ok: bool, _r: Variant) -> void: pass)
		Api.save_state(0, {"points": best_score}, func(_ok: bool, _r: Variant) -> void: pass)

func _spawn_leaf() -> void:
	var type := 0 if randf() > 0.4 else 1  # leaf or petal
	falling.append({
		"p": Vector2(randf_range(30, sw - 30), -20),
		"type": type,
		"spd": LEAF_FALL_SPEED + randf_range(-15, 15),
		"angle": randf() * TAU,
		"sway": randf() * TAU,
		"alive": true,
	})

func _spawn_kunai() -> void:
	falling.append({
		"p": Vector2(randf_range(50, sw - 50), -20),
		"type": 2,
		"spd": KUNAI_SPEED,
		"angle": 0.0,
		"sway": 0.0,
		"alive": true,
	})

func _spawn_burst(pos: Vector2, col: Color, count: int) -> void:
	for k in count:
		var angle := randf() * TAU
		var spd := randf_range(40, 120)
		particles.append({"p": Vector2(pos), "v": Vector2(cos(angle), sin(angle)) * spd, "life": randf_range(0.3, 0.6), "color": Color(col.r, col.g, col.b, 0.8), "sz": randf_range(2, 5)})

# ─────────────────────────── DRAWING ───────────────────────────

func _draw() -> void:
	match game_state:
		0: _draw_title()
		1: _draw_game()
		2: _draw_game(); _draw_gameover()

	# Particles (always)
	for p in particles:
		var a: float = clampf(float(p["life"]) / 0.5, 0, 1)
		var col: Color = p["color"]
		col.a = a
		draw_circle(p["p"], float(p["sz"]) * a, col)

func _draw_game() -> void:
	# Sky gradient
	var sky_top := Color(0.12, 0.15, 0.25)
	var sky_bot := Color(0.25, 0.35, 0.45)
	for row in 10:
		var frac := float(row) / 10.0
		var y0: float = frac * garden_y_start
		var y1: float = (frac + 0.1) * garden_y_start
		draw_rect(Rect2(0, y0, sw, y1 - y0 + 1), sky_top.lerp(sky_bot, frac))

	# Moon
	var moon_x := sw * 0.82
	var moon_y := sh * 0.1
	draw_circle(Vector2(moon_x, moon_y), 25, Color(0.95, 0.92, 0.8, 0.3))
	draw_circle(Vector2(moon_x, moon_y), 20, Color(0.95, 0.93, 0.85, 0.5))

	# Garden background
	draw_rect(Rect2(0, garden_y_start, sw, sh - garden_y_start), Color(0.15, 0.2, 0.1))

	# Garden grid
	for row in GRID_ROWS:
		for col in GRID_COLS:
			var idx := row * GRID_COLS + col
			var cx: float = float(col) * cell_w
			var cy: float = garden_y_start + float(row) * cell_h
			# Cell border
			draw_rect(Rect2(cx, cy, cell_w, cell_h), Color(0.2, 0.28, 0.15), false, 1.0)
			# Soil
			draw_rect(Rect2(cx + 4, cy + 4, cell_w - 8, cell_h - 8), Color(0.18, 0.22, 0.12))

			# Draw plant
			var g: Dictionary = garden[idx]
			if int(g["type"]) >= 0:
				_draw_plant(Vector2(cx + cell_w * 0.5, cy + cell_h * 0.5), int(g["type"]), int(g["stage"]))
			else:
				# Empty — subtle plus sign
				var center := Vector2(cx + cell_w * 0.5, cy + cell_h * 0.5)
				draw_line(center + Vector2(-8, 0), center + Vector2(8, 0), Color(0.3, 0.35, 0.2, 0.2), 1.0)
				draw_line(center + Vector2(0, -8), center + Vector2(0, 8), Color(0.3, 0.35, 0.2, 0.2), 1.0)

	# Garden border
	draw_line(Vector2(0, garden_y_start), Vector2(sw, garden_y_start), Color(0.3, 0.4, 0.2, 0.5), 2.0)

	# Falling objects
	for f in falling:
		if not bool(f["alive"]):
			continue
		_draw_falling(f)

	# Slash trail
	if slash_points.size() > 1:
		for i in range(1, slash_points.size()):
			var a: float = float(i) / float(slash_points.size())
			draw_line(slash_points[i - 1], slash_points[i], Color(1, 1, 1, a * 0.6 * (slash_timer / 0.2)), 2.0)

	# Plant selector popup
	if plant_selector_visible and plant_selector_cell >= 0:
		_draw_selector()

	# HUD
	_draw_hud()

func _draw_plant(center: Vector2, type: int, stage: int) -> void:
	var s: float = 0.4 + float(stage) * 0.2  # 0.4, 0.6, 0.8, 1.0
	match type:
		0:  # Bamboo — green vertical lines
			var count := 1 + stage
			for i in count:
				var ox: float = float(i - count / 2) * 6.0 * s
				var h: float = 20.0 * s + float(i) * 3.0
				draw_line(center + Vector2(ox, 10), center + Vector2(ox, -h), Color(0.3, 0.7, 0.25), 2.5 * s)
				# Leaves at top
				if stage >= 1:
					draw_line(center + Vector2(ox, -h), center + Vector2(ox - 8 * s, -h - 5), Color(0.4, 0.8, 0.3), 1.5)
					draw_line(center + Vector2(ox, -h), center + Vector2(ox + 8 * s, -h - 5), Color(0.4, 0.8, 0.3), 1.5)
		1:  # Bonsai — brown trunk + green canopy
			# Trunk
			draw_line(center + Vector2(0, 10), center + Vector2(-4 * s, -8 * s), Color(0.45, 0.3, 0.15), 3.0 * s)
			draw_line(center + Vector2(-4 * s, -8 * s), center + Vector2(6 * s, -14 * s), Color(0.45, 0.3, 0.15), 2.5 * s)
			# Canopy
			var canopy_r: float = 10.0 * s
			draw_circle(center + Vector2(2 * s, -16 * s), canopy_r, Color(0.2, 0.55, 0.2))
			if stage >= 2:
				draw_circle(center + Vector2(-8 * s, -10 * s), canopy_r * 0.7, Color(0.25, 0.6, 0.25))
		2:  # Cherry blossom — pink tree
			# Trunk
			draw_line(center + Vector2(0, 10), center + Vector2(0, -10 * s), Color(0.5, 0.3, 0.2), 2.5 * s)
			# Branches
			if stage >= 1:
				draw_line(center + Vector2(0, -8 * s), center + Vector2(-12 * s, -16 * s), Color(0.5, 0.3, 0.2), 1.5)
				draw_line(center + Vector2(0, -8 * s), center + Vector2(12 * s, -14 * s), Color(0.5, 0.3, 0.2), 1.5)
			# Blossoms
			var blossom_col := Color(1, 0.6, 0.75, 0.8)
			draw_circle(center + Vector2(0, -14 * s), 8.0 * s, blossom_col)
			if stage >= 1:
				draw_circle(center + Vector2(-12 * s, -18 * s), 6.0 * s, blossom_col)
				draw_circle(center + Vector2(10 * s, -16 * s), 6.0 * s, blossom_col)
			if stage >= 2:
				# Falling petals
				for k in 3:
					var px: float = center.x + sin(state_timer * 1.5 + float(k) * 2.0) * 15.0 * s
					var py: float = center.y - 5.0 + float(k) * 6.0
					draw_circle(Vector2(px, py), 2.0, Color(1, 0.7, 0.8, 0.5))
		3:  # Rock garden — grey stones + raked sand lines
			# Raked lines
			for i in 5:
				var ly: float = center.y - 8.0 + float(i) * 4.0
				draw_line(Vector2(center.x - 15 * s, ly), Vector2(center.x + 15 * s, ly), Color(0.35, 0.38, 0.3, 0.3), 1.0)
			# Stones
			draw_circle(center + Vector2(-5 * s, 2), 6.0 * s, Color(0.45, 0.45, 0.42))
			if stage >= 1:
				draw_circle(center + Vector2(8 * s, -3), 4.5 * s, Color(0.5, 0.5, 0.47))
			if stage >= 2:
				draw_circle(center + Vector2(-2 * s, -8 * s), 3.5 * s, Color(0.4, 0.42, 0.4))

func _draw_falling(f: Dictionary) -> void:
	var fp: Vector2 = f["p"]
	var type: int = f["type"]
	var angle: float = f["angle"]

	match type:
		0:  # Leaf — green diamond shape
			var pts: PackedVector2Array = PackedVector2Array()
			var leaf_s := 8.0
			pts.append(fp + Vector2(0, -leaf_s).rotated(angle))
			pts.append(fp + Vector2(leaf_s * 0.5, 0).rotated(angle))
			pts.append(fp + Vector2(0, leaf_s * 0.6).rotated(angle))
			pts.append(fp + Vector2(-leaf_s * 0.5, 0).rotated(angle))
			draw_colored_polygon(pts, Color(0.3, 0.7, 0.2, 0.8))
		1:  # Petal — pink circle
			draw_circle(fp, 5.0, Color(1, 0.65, 0.78, 0.7))
			draw_circle(fp + Vector2(3, -2).rotated(angle), 3.5, Color(1, 0.75, 0.85, 0.5))
		2:  # Kunai — grey dagger shape
			# Blade
			draw_line(fp + Vector2(0, -12), fp + Vector2(0, 8), Color(0.7, 0.7, 0.75), 2.5)
			# Point
			draw_line(fp + Vector2(0, -12), fp + Vector2(-3, -6), Color(0.8, 0.8, 0.85), 1.5)
			draw_line(fp + Vector2(0, -12), fp + Vector2(3, -6), Color(0.8, 0.8, 0.85), 1.5)
			# Handle wrap
			draw_line(fp + Vector2(-3, 4), fp + Vector2(3, 4), Color(0.6, 0.4, 0.3), 1.5)
			draw_line(fp + Vector2(-3, 7), fp + Vector2(3, 7), Color(0.6, 0.4, 0.3), 1.5)
			# Glint
			draw_circle(fp + Vector2(0, -8), 1.5, Color(1, 1, 1, 0.5 + sin(state_timer * 8) * 0.3))

func _draw_selector() -> void:
	var cp := _cell_center(plant_selector_cell)
	var btn_w := 50.0
	var btn_h := 40.0
	var total := btn_w * 4.0 + 10.0 * 3.0
	var start_x: float = cp.x - total * 0.5
	var btn_y: float = cp.y - btn_h - 25.0

	# Background
	draw_rect(Rect2(start_x - 8, btn_y - 8, total + 16, btn_h + 16), Color(0.08, 0.1, 0.06, 0.9))
	draw_rect(Rect2(start_x - 8, btn_y - 8, total + 16, btn_h + 16), Color(0.4, 0.5, 0.3, 0.5), false, 1.5)

	var icons := ["||", "}{", "**", "oo"]
	var colors: Array[Color] = [Color(0.3, 0.7, 0.25), Color(0.5, 0.3, 0.2), Color(1, 0.6, 0.75), Color(0.5, 0.5, 0.47)]

	for i in 4:
		var bx: float = start_x + float(i) * (btn_w + 10.0)
		draw_rect(Rect2(bx, btn_y, btn_w, btn_h), Color(0.12, 0.16, 0.08, 0.8))
		draw_rect(Rect2(bx, btn_y, btn_w, btn_h), colors[i] * Color(1, 1, 1, 0.4), false, 1.0)
		_txt(Vector2(bx + btn_w * 0.5, btn_y + 12), icons[i], 14, colors[i])
		_txt(Vector2(bx + btn_w * 0.5, btn_y + 28), PLANT_NAMES[i].substr(0, 6), 7, Color(0.6, 0.7, 0.5, 0.5))

func _draw_hud() -> void:
	# Timer
	var secs := ceili(maxf(game_timer, 0))
	var mins := secs / 60
	secs = secs % 60
	var timer_str := "%d:%02d" % [mins, secs]
	_txt(Vector2(sw * 0.5, 14), timer_str, 16, Color(0.8, 0.85, 0.9, 0.6))

	# Score
	_txt(Vector2(sw * 0.5, 32), str(score), 13, Color(0.8, 0.9, 0.7, 0.5))

	# Beauty
	_txt(Vector2(20, 14), "Garden: " + str(beauty_score), 10, Color(0.5, 0.8, 0.4, 0.5))

	# Combo
	if combo > 1:
		_txt(Vector2(sw - 30, 14), "x" + str(combo), 16, Color(1, 0.85, 0.2, 0.8))

	# Slashes
	_txt(Vector2(sw - 30, 32), str(total_slashes) + " cuts", 9, Color(0.6, 0.6, 0.5, 0.4))

	# Hint
	_txt(Vector2(sw * 0.5, garden_y_start - 10), "slash leaves  |  tap plots to plant", 8, Color(0.5, 0.6, 0.5, 0.25))

func _draw_title() -> void:
	# Night garden scene
	draw_rect(Rect2(0, 0, sw, sh), Color(0.06, 0.08, 0.14))

	# Stars
	for k in 40:
		var sx := fmod(float(k) * 137.5, sw)
		var sy := fmod(float(k) * 83.7, sh * 0.6)
		var twinkle := 0.12 + sin(state_timer * 2.0 + float(k) * 1.3) * 0.1
		draw_circle(Vector2(sx, sy), 1.0, Color(1, 1, 0.9, twinkle))

	# Moon
	draw_circle(Vector2(sw * 0.75, sh * 0.15), 30, Color(0.95, 0.92, 0.8, 0.25))
	draw_circle(Vector2(sw * 0.75, sh * 0.15), 24, Color(0.95, 0.93, 0.85, 0.4))

	# Garden silhouette at bottom
	var ground_y := sh * 0.7
	draw_rect(Rect2(0, ground_y, sw, sh - ground_y), Color(0.08, 0.12, 0.06))

	# Bamboo silhouettes
	for k in 7:
		var bx: float = sw * 0.1 + float(k) * sw * 0.12
		var bh: float = 40.0 + sin(float(k) * 2.3) * 20.0
		var sway: float = sin(state_timer * 0.8 + float(k)) * 3.0
		draw_line(Vector2(bx + sway, ground_y), Vector2(bx + sway * 0.5, ground_y - bh), Color(0.12, 0.22, 0.08, 0.5), 2.0)
		# Leaf
		draw_line(Vector2(bx + sway * 0.5, ground_y - bh), Vector2(bx + sway * 0.5 + 10, ground_y - bh - 5), Color(0.15, 0.25, 0.1, 0.4), 1.5)

	# Falling petals on title screen
	for k in 8:
		var px := fmod(state_timer * 20.0 + float(k) * 100.0, sw)
		var py := fmod(state_timer * 30.0 + float(k) * 80.0, ground_y)
		var pa := 0.15 + sin(state_timer + float(k)) * 0.08
		draw_circle(Vector2(px, py), 3.0, Color(1, 0.7, 0.85, pa))

	# Title
	_txt(Vector2(sw * 0.5, sh * 0.18), "NINJA", 36, Color(0.85, 0.85, 0.9, 0.85))
	_txt(Vector2(sw * 0.5, sh * 0.18 + 36), "GARDEN", 28, Color(0.5, 0.8, 0.4, 0.7))
	_txt(Vector2(sw * 0.5, sh * 0.18 + 64), "zen training grounds", 11, Color(0.5, 0.6, 0.5, 0.35))

	# Instructions
	_txt(Vector2(sw * 0.3, sh * 0.48), "tap plots", 12, Color(0.5, 0.8, 0.4, 0.4))
	_txt(Vector2(sw * 0.3, sh * 0.48 + 16), "to plant", 10, Color(0.5, 0.7, 0.5, 0.3))

	_txt(Vector2(sw * 0.7, sh * 0.48), "slash leaves", 12, Color(0.8, 0.8, 0.9, 0.4))
	_txt(Vector2(sw * 0.7, sh * 0.48 + 16), "for points", 10, Color(0.5, 0.7, 0.5, 0.3))

	# Kunai icon + text
	_txt(Vector2(sw * 0.5, sh * 0.58), "deflect kunai for bonus!", 11, Color(1, 0.8, 0.3, 0.35))

	var ta := 0.3 + sin(state_timer * 3.0) * 0.2
	_txt(Vector2(sw * 0.5, sh * 0.88), "TAP TO START", 20, Color(0.7, 0.9, 0.6, ta))
	if best_score > 0:
		_txt(Vector2(sw * 0.5, sh * 0.88 + 22), "best: " + str(best_score), 11, Color(0.4, 0.5, 0.4, 0.3))

func _draw_gameover() -> void:
	var a := minf(state_timer * 0.8, 1.0)
	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, 0.6 * a))
	var cx := sw * 0.5

	_txt(Vector2(cx, sh * 0.15), "SESSION COMPLETE", 26, Color(0.5, 0.85, 0.4, a))

	_txt(Vector2(cx, sh * 0.3), str(score) + " points", 24, Color(1, 0.9, 0.3, a * 0.85))

	# Breakdown
	_txt(Vector2(cx, sh * 0.42), "Garden beauty: " + str(beauty_score * 10), 12, Color(0.5, 0.8, 0.4, a * 0.6))
	_txt(Vector2(cx, sh * 0.42 + 18), "Slash score: " + str(slash_score), 12, Color(0.8, 0.8, 0.9, a * 0.6))
	_txt(Vector2(cx, sh * 0.42 + 36), str(total_slashes) + " cuts  |  " + str(kunai_deflects) + " deflects  |  max combo x" + str(max_combo), 10, Color(0.6, 0.6, 0.5, a * 0.4))

	# Plants grown count
	var plants_grown := 0
	var fully_grown := 0
	for g in garden:
		if int(g["type"]) >= 0:
			plants_grown += 1
			if int(g["stage"]) >= 3:
				fully_grown += 1
	_txt(Vector2(cx, sh * 0.55), str(plants_grown) + " planted  |  " + str(fully_grown) + " fully grown", 11, Color(0.5, 0.7, 0.4, a * 0.5))

	if score >= best_score and score > 0:
		_txt(Vector2(cx, sh * 0.65), "NEW BEST!", 18, Color(1, 0.85, 0.2, a))
	elif best_score > 0:
		_txt(Vector2(cx, sh * 0.65), "best: " + str(best_score), 12, Color(0.4, 0.5, 0.4, a * 0.4))

	if state_timer > 1.5:
		var ta := 0.3 + sin(state_timer * 3.0) * 0.2
		_txt(Vector2(cx, sh * 0.78), "TAP TO RETRY", 20, Color(0.5, 0.85, 0.4, ta))

# ─────────────────────────── TEXT HELPER ───────────────────────────

func _txt(pos: Vector2, text: String, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var ss := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5 + 1, size * 0.35 + 1),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.4))
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5, size * 0.35),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
