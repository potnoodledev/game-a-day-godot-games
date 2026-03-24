extends Node2D

# DAY 40: RESEARCH LAB — Microscope Specimen Identification
# Organisms float in a petri dish. Tap to collect specimens.
# Match them to active research goals for bonus points.
# Wrong taps lose time. Increasing difficulty.

# === CONSTANTS ===
const GAME_DURATION := 90.0
const MAX_SPECIMENS := 12
const SPAWN_INTERVAL_BASE := 1.5
const SPECIMEN_SPEED := 30.0
const TAP_RADIUS := 40.0
const GOAL_DURATION := 12.0

# Specimen types: name, color, shape (0=circle, 1=triangle, 2=square, 3=diamond, 4=star)
const TYPES := [
	{"name": "Amoeba", "color": Color(0.3, 0.85, 0.4), "shape": 0, "sz": 18.0},
	{"name": "Paramecium", "color": Color(0.2, 0.7, 0.9), "shape": 1, "sz": 16.0},
	{"name": "Diatom", "color": Color(0.9, 0.8, 0.2), "shape": 2, "sz": 14.0},
	{"name": "Rotifer", "color": Color(0.9, 0.4, 0.3), "shape": 3, "sz": 15.0},
	{"name": "Tardigrade", "color": Color(0.8, 0.5, 0.9), "shape": 4, "sz": 20.0},
	{"name": "Euglena", "color": Color(0.4, 0.9, 0.7), "shape": 0, "sz": 12.0},
	{"name": "Volvox", "color": Color(0.2, 0.8, 0.3), "shape": 2, "sz": 22.0},
	{"name": "Stentor", "color": Color(0.9, 0.5, 0.6), "shape": 1, "sz": 19.0},
]

# === STATE ===
var game_state := 0  # 0=title, 1=playing, 2=gameover
var state_timer := 0.0
var score := 0
var best_score := 0
var game_timer := 0.0
var combo := 0
var max_combo := 0
var specimens_collected := 0

# === SCREEN ===
var sw := 800.0
var sh := 600.0

# === SPECIMENS ===
# {p: Vector2, v: Vector2, type_idx: int, age: float, wobble: float, alive: bool}
var specimens: Array[Dictionary] = []
var spawn_timer := 0.0
var difficulty := 1.0

# === RESEARCH GOAL ===
var goal_type := 0
var goal_timer := 0.0
var goal_count := 0
var goal_target := 3

# === PARTICLES ===
# {p: Vector2, color: Color, life: float, text: String, vy: float}
var particles: Array[Dictionary] = []

# === PETRI DISH ===
var dish_center := Vector2.ZERO
var dish_radius := 250.0

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
	combo = 0
	max_combo = 0
	specimens_collected = 0
	specimens.clear()
	particles.clear()
	spawn_timer = 0.0
	difficulty = 1.0
	_new_goal()

func _new_goal() -> void:
	goal_type = randi() % TYPES.size()
	goal_timer = GOAL_DURATION
	goal_count = 0
	goal_target = 3 + int(difficulty * 0.5)

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

func _handle_tap(pos: Vector2) -> void:
	var best_idx := -1
	var best_dist := TAP_RADIUS
	for i in specimens.size():
		var s: Dictionary = specimens[i]
		if not s["alive"]:
			continue
		var d: float = pos.distance_to(s["p"])
		var sz: float = TYPES[int(s["type_idx"])]["sz"]
		if d < best_dist + sz:
			best_dist = d
			best_idx = i

	if best_idx >= 0:
		var s: Dictionary = specimens[best_idx]
		var type_idx: int = s["type_idx"]
		var type_info: Dictionary = TYPES[type_idx]
		s["alive"] = false

		var pts := 10 + combo * 2
		var is_goal := type_idx == goal_type

		if is_goal:
			pts += 15
			goal_count += 1
			combo += 1
			max_combo = maxi(max_combo, combo)
		else:
			combo = 0

		score += pts
		specimens_collected += 1

		var col: Color = type_info["color"]
		_spawn_particle(s["p"], col, "+" + str(pts))
		if is_goal:
			_spawn_particle(s["p"] + Vector2(0, -20), Color(1, 0.9, 0.3), "MATCH!")

		if is_goal and goal_count >= goal_target:
			var bonus := goal_target * 20
			score += bonus
			_spawn_particle(Vector2(sw * 0.5, sh * 0.3), Color(1, 0.85, 0.2), "RESEARCH COMPLETE! +" + str(bonus))
			_new_goal()
	else:
		game_timer -= 2.0
		combo = 0
		_spawn_particle(pos, Color(0.9, 0.3, 0.2, 0.8), "-2s")

# ─────────────────────────── PROCESS ───────────────────────────

func _process(delta: float) -> void:
	var vp := _get_ss()
	sw = vp.x; sh = vp.y
	dish_center = Vector2(sw * 0.5, sh * 0.52)
	dish_radius = minf(sw, sh) * 0.4
	state_timer += delta

	if game_state == 1:
		_tick_game(delta)

	# Update particles
	var i := particles.size() - 1
	while i >= 0:
		particles[i]["life"] = float(particles[i]["life"]) - delta
		particles[i]["p"] = Vector2(particles[i]["p"]) + Vector2(0, float(particles[i]["vy"]) * delta)
		if float(particles[i]["life"]) <= 0:
			particles.remove_at(i)
		i -= 1

	queue_redraw()

func _tick_game(delta: float) -> void:
	game_timer -= delta
	difficulty = 1.0 + (GAME_DURATION - game_timer) / GAME_DURATION * 3.0

	spawn_timer += delta
	var interval := SPAWN_INTERVAL_BASE / difficulty
	while spawn_timer > interval and specimens.size() < MAX_SPECIMENS:
		spawn_timer -= interval
		_spawn_specimen()

	var idx := specimens.size() - 1
	while idx >= 0:
		var s: Dictionary = specimens[idx]
		if not s["alive"]:
			specimens.remove_at(idx)
			idx -= 1
			continue

		s["age"] = float(s["age"]) + delta
		s["wobble"] = float(s["wobble"]) + delta * 2.5

		var p: Vector2 = s["p"]
		var v: Vector2 = s["v"]

		v += Vector2(randf_range(-8, 8), randf_range(-8, 8)) * delta
		var spd := v.length()
		var max_spd := SPECIMEN_SPEED * difficulty * 0.7
		if spd > max_spd:
			v = v.normalized() * max_spd

		p += v * delta

		var to_center := dish_center - p
		var dist := to_center.length()
		if dist > dish_radius - 20:
			v += to_center.normalized() * 80.0 * delta
			if dist > dish_radius:
				p = dish_center + (p - dish_center).normalized() * (dish_radius - 5)
				v = v.reflect((dish_center - p).normalized()) * 0.5

		s["p"] = p
		s["v"] = v

		if float(s["age"]) > 15.0:
			specimens.remove_at(idx)

		idx -= 1

	goal_timer -= delta
	if goal_timer <= 0:
		_new_goal()

	if game_timer <= 0:
		game_timer = 0
		score += max_combo * 5
		game_state = 2
		state_timer = 0.0
		best_score = maxi(best_score, score)
		Api.submit_score(score, func(_ok: bool, _r: Variant) -> void: pass)
		Api.save_state(0, {"points": best_score}, func(_ok: bool, _r: Variant) -> void: pass)

func _spawn_specimen() -> void:
	var type_idx: int
	if randf() < 0.3:
		type_idx = goal_type
	else:
		type_idx = randi() % TYPES.size()

	var angle := randf() * TAU
	var edge := dish_center + Vector2(cos(angle), sin(angle)) * (dish_radius - 30)
	var drift_dir := (dish_center - edge).normalized().rotated(randf_range(-0.8, 0.8))

	specimens.append({
		"p": edge,
		"v": drift_dir * randf_range(15, 35),
		"type_idx": type_idx,
		"age": 0.0,
		"wobble": randf() * TAU,
		"alive": true,
	})

func _spawn_particle(pos: Vector2, col: Color, text: String) -> void:
	particles.append({"p": pos, "color": col, "life": 1.2, "text": text, "vy": -40.0})

# ─────────────────────────── DRAWING ───────────────────────────

func _draw() -> void:
	draw_rect(Rect2(0, 0, sw, sh), Color(0.04, 0.06, 0.1))

	match game_state:
		0: _draw_title()
		1: _draw_game()
		2: _draw_game(); _draw_gameover()

	for part in particles:
		var a: float = clampf(float(part["life"]) / 1.2, 0, 1)
		var col: Color = part["color"]
		col.a = a
		_txt(Vector2(part["p"]), part["text"], 16, col)

func _draw_game() -> void:
	draw_circle(dish_center, dish_radius + 4, Color(0.15, 0.18, 0.25, 0.6))
	draw_circle(dish_center, dish_radius, Color(0.08, 0.1, 0.16))
	draw_arc(dish_center, dish_radius, 0, TAU, 64, Color(0.3, 0.35, 0.45, 0.4), 2.0)

	var grid_alpha := 0.06
	for gx in range(int(dish_center.x - dish_radius), int(dish_center.x + dish_radius), 40):
		var fx := float(gx)
		draw_line(Vector2(fx, dish_center.y - dish_radius), Vector2(fx, dish_center.y + dish_radius), Color(0.3, 0.4, 0.5, grid_alpha), 1.0)
	for gy in range(int(dish_center.y - dish_radius), int(dish_center.y + dish_radius), 40):
		var fy := float(gy)
		draw_line(Vector2(dish_center.x - dish_radius, fy), Vector2(dish_center.x + dish_radius, fy), Color(0.3, 0.4, 0.5, grid_alpha), 1.0)

	for s in specimens:
		if not s["alive"]:
			continue
		var p: Vector2 = s["p"]
		var type_idx: int = s["type_idx"]
		var type_info: Dictionary = TYPES[type_idx]
		var col: Color = type_info["color"]
		var sz: float = type_info["sz"]
		var wobble: float = s["wobble"]
		var shape: int = type_info["shape"]
		var pulse := 1.0 + sin(wobble) * 0.12
		sz *= pulse

		if type_idx == goal_type:
			draw_circle(p, sz + 6, Color(1, 0.9, 0.3, 0.15 + sin(wobble * 1.5) * 0.08))

		_draw_specimen(p, sz, col, shape, wobble)

	_draw_hud()

func _draw_specimen(p: Vector2, sz: float, col: Color, shape: int, wobble: float) -> void:
	match shape:
		0:
			var pts: PackedVector2Array = PackedVector2Array()
			for k in 12:
				var angle := float(k) / 12.0 * TAU
				var r := sz + sin(angle * 3 + wobble) * sz * 0.2
				pts.append(p + Vector2(cos(angle), sin(angle)) * r)
			var cols: PackedColorArray = PackedColorArray()
			for _k in 12:
				cols.append(col)
			draw_polygon(pts, cols)
			draw_polyline(pts, col.darkened(0.2), 1.5)
		1:
			var pts: PackedVector2Array = PackedVector2Array()
			for k in 3:
				var angle := float(k) / 3.0 * TAU - PI * 0.5 + sin(wobble) * 0.1
				pts.append(p + Vector2(cos(angle), sin(angle)) * sz)
			var cols: PackedColorArray = PackedColorArray()
			for _k in 3:
				cols.append(col)
			draw_polygon(pts, cols)
			draw_polyline(pts, col.darkened(0.2), 1.5)
		2:
			var rot := wobble * 0.3
			var pts: PackedVector2Array = PackedVector2Array()
			for k in 4:
				var angle := float(k) / 4.0 * TAU + PI * 0.25 + rot
				pts.append(p + Vector2(cos(angle), sin(angle)) * sz)
			var cols: PackedColorArray = PackedColorArray()
			for _k in 4:
				cols.append(col)
			draw_polygon(pts, cols)
			draw_polyline(pts, col.darkened(0.2), 1.5)
		3:
			var pts: PackedVector2Array = PackedVector2Array()
			pts.append(p + Vector2(0, -sz * 1.3))
			pts.append(p + Vector2(sz * 0.7, 0))
			pts.append(p + Vector2(0, sz * 1.3))
			pts.append(p + Vector2(-sz * 0.7, 0))
			var cols: PackedColorArray = PackedColorArray()
			for _k in 4:
				cols.append(col)
			draw_polygon(pts, cols)
			draw_polyline(pts, col.darkened(0.2), 1.5)
		4:
			var pts: PackedVector2Array = PackedVector2Array()
			for k in 10:
				var angle := float(k) / 10.0 * TAU - PI * 0.5
				var r := sz if k % 2 == 0 else sz * 0.5
				pts.append(p + Vector2(cos(angle), sin(angle)) * r)
			var cols: PackedColorArray = PackedColorArray()
			for _k in 10:
				cols.append(col)
			draw_polygon(pts, cols)
			draw_polyline(pts, col.darkened(0.2), 1.5)

	draw_circle(p, sz * 0.25, col.lightened(0.3))

func _draw_hud() -> void:
	var secs := ceili(maxf(game_timer, 0))
	var timer_col := Color(1, 0.3, 0.2) if secs <= 15 else Color(1, 1, 1, 0.7)
	_txt(Vector2(sw * 0.5, 16), str(secs) + "s", 20, timer_col)
	_txt(Vector2(sw * 0.5, 38), str(score) + " pts", 14, Color(0.8, 0.85, 0.9, 0.6))

	if combo > 1:
		_txt(Vector2(sw - 60, 20), "x" + str(combo), 18, Color(1, 0.85, 0.2, 0.8))

	var goal_info: Dictionary = TYPES[goal_type]
	var panel_y := 10.0
	var panel_x := 10.0
	draw_rect(Rect2(panel_x, panel_y, 170, 50), Color(0.1, 0.12, 0.18, 0.8))
	draw_rect(Rect2(panel_x, panel_y, 170, 50), Color(0.3, 0.4, 0.5, 0.3), false, 1.0)
	_txt(Vector2(panel_x + 85, panel_y + 14), "RESEARCH GOAL", 9, Color(0.6, 0.65, 0.7, 0.5))
	_txt(Vector2(panel_x + 85, panel_y + 30), goal_info["name"], 13, goal_info["color"])

	var bar_w := 150.0
	var bar_h := 6.0
	var bar_x := panel_x + 10
	var bar_y := panel_y + 40
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.2, 0.2, 0.25))
	var pct := clampf(float(goal_count) / float(goal_target), 0, 1)
	draw_rect(Rect2(bar_x, bar_y, bar_w * pct, bar_h), goal_info["color"].lightened(0.2))
	_txt(Vector2(bar_x + bar_w + 12, bar_y + 3), str(goal_count) + "/" + str(goal_target), 9, Color(0.7, 0.7, 0.75, 0.5))

	var gt_pct := clampf(goal_timer / GOAL_DURATION, 0, 1)
	if gt_pct < 0.3:
		_txt(Vector2(panel_x + 85, panel_y + 55), "hurry!", 9, Color(1, 0.4, 0.3, 0.5 + sin(state_timer * 5) * 0.3))

func _draw_title() -> void:
	for k in 8:
		var ang := float(k) / 8.0 * TAU + state_timer * 0.2
		var r := dish_radius * 0.6
		var p := dish_center + Vector2(cos(ang), sin(ang)) * r
		var type_info: Dictionary = TYPES[k]
		_draw_specimen(p, type_info["sz"] * 0.8, type_info["color"].darkened(0.3), type_info["shape"], state_timer + float(k))

	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, 0.55))

	var pulse := 0.6 + sin(state_timer * 2.0) * 0.2
	_txt(Vector2(sw * 0.5, sh * 0.14), "RESEARCH LAB", 32, Color(0.3, 0.8, 0.95, pulse))
	_txt(Vector2(sw * 0.5, sh * 0.14 + 34), "microscope specimens", 15, Color(0.6, 0.75, 0.85, 0.45))

	_txt(Vector2(sw * 0.5, sh * 0.34), "Tap specimens to collect them", 14, Color(0.8, 0.85, 0.9, 0.55))
	_txt(Vector2(sw * 0.5, sh * 0.34 + 24), "Match the research goal for bonus points", 14, Color(0.8, 0.85, 0.9, 0.45))
	_txt(Vector2(sw * 0.5, sh * 0.34 + 48), "Build combos by collecting goal specimens", 14, Color(0.8, 0.85, 0.9, 0.4))
	_txt(Vector2(sw * 0.5, sh * 0.34 + 72), "Missed taps cost 2 seconds!", 13, Color(0.9, 0.4, 0.3, 0.4))

	var legend_y := sh * 0.58
	for k in TYPES.size():
		var row := k / 4
		var col_idx := k % 4
		var lx := sw * 0.18 + float(col_idx) * sw * 0.2
		var ly := legend_y + float(row) * 28.0
		var info: Dictionary = TYPES[k]
		_draw_specimen(Vector2(lx - 14, ly), 8, info["color"], info["shape"], state_timer + float(k))
		_txt(Vector2(lx + 8, ly), info["name"], 10, Color(0.7, 0.75, 0.8, 0.45))

	var ta := 0.3 + sin(state_timer * 3.0) * 0.2
	_txt(Vector2(sw * 0.5, sh * 0.86), "TAP TO START", 22, Color(0.3, 0.8, 0.95, ta))
	if best_score > 0:
		_txt(Vector2(sw * 0.5, sh * 0.86 + 28), "best: " + str(best_score), 13, Color(0.6, 0.7, 0.8, 0.3))

func _draw_gameover() -> void:
	var a := minf(state_timer * 0.8, 1.0)
	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, 0.6 * a))
	var cx := sw * 0.5

	_txt(Vector2(cx, sh * 0.22), "RESEARCH COMPLETE", 30, Color(0.3, 0.85, 0.95, a))
	_txt(Vector2(cx, sh * 0.35), str(score) + " points", 26, Color(1, 0.9, 0.3, a * 0.85))
	_txt(Vector2(cx, sh * 0.35 + 30), str(specimens_collected) + " specimens  |  max combo x" + str(max_combo), 13, Color(0.7, 0.8, 0.85, a * 0.5))

	if score >= best_score and score > 0:
		_txt(Vector2(cx, sh * 0.52), "NEW BEST!", 20, Color(1, 0.85, 0.2, a))
	elif best_score > 0:
		_txt(Vector2(cx, sh * 0.52), "best: " + str(best_score), 14, Color(0.6, 0.7, 0.8, a * 0.4))

	if state_timer > 1.5:
		var ta := 0.3 + sin(state_timer * 3.0) * 0.2
		_txt(Vector2(cx, sh * 0.72), "TAP TO RETRY", 22, Color(0.3, 0.8, 0.95, ta))

# ─────────────────────────── TEXT HELPER ───────────────────────────

func _txt(pos: Vector2, text: String, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var ss := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5 + 1, size * 0.35 + 1),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.4))
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5, size * 0.35),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
