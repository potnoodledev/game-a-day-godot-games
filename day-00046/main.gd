extends Node2D

# DAY 46: SIGNATURE FORGE — Trace signatures for accuracy
# Procedurally generated cursive signatures. Trace with your finger.
# Scored on accuracy + completion. 45 seconds, chain combos.

# === CONSTANTS ===
const GAME_DURATION := 45.0
const PATH_SAMPLE_DIST := 6.0  # pixels between path sample points
const ACCURACY_RADIUS := 25.0  # pixels — max distance to count as "on path"
const MIN_POINTS := 5
const MAX_POINTS := 8

# === STATE ===
var game_state := 0  # 0=title, 1=playing, 2=grading, 3=gameover
var score := 0
var best_score := 0
var game_timer := 0.0
var combo := 0
var max_combo := 0
var sigs_completed := 0
var total_grade_pts := 0

# Current signature
var sig_path: PackedVector2Array = PackedVector2Array()  # sampled points of target
var sig_control_points: Array[Vector2] = []  # bezier control points
var player_path: PackedVector2Array = PackedVector2Array()  # what player drew
var is_drawing := false
var sig_progress := 0.0  # 0-1 how much of sig covered
var sig_accuracy := 0.0  # average distance score
var path_hits: Array[bool] = []  # which sig_path points were "hit"
var sig_offset := Vector2.ZERO  # centering offset
var sig_scale := 1.0

# Grading animation
var grade_text := ""
var grade_color := Color.WHITE
var grade_timer := 0.0
var grade_pts := 0
var grade_stamp_scale := 3.0  # starts big, shrinks to 1

# Screen
var sw := 800.0
var sh := 600.0
var u := 60.0

# Tier
var tier := 0
var tier_names := ["Intern", "Clerk", "Manager", "Executive", "CEO"]
var tier_thresholds := [0, 500, 1500, 3000, 5000]
var tier_colors: Array[Color] = [Color(0.5, 0.5, 0.5), Color(0.4, 0.6, 0.8), Color(0.3, 0.8, 0.4), Color(0.9, 0.7, 0.2), Color(1.0, 0.4, 0.2)]

# Particles (ink splatter)
var particles: Array[Dictionary] = []

# Score pops
var pops: Array[Dictionary] = []

# Difficulty
var sig_count_total := 0  # increases difficulty

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
	score = 0
	combo = 0
	max_combo = 0
	sigs_completed = 0
	total_grade_pts = 0
	sig_count_total = 0
	game_timer = GAME_DURATION
	tier = 0
	particles.clear()
	pops.clear()
	_generate_signature()

func _end_game() -> void:
	game_state = 3
	if score > best_score:
		best_score = score
	Api.submit_score(score, func(_ok: bool, _r: Variant) -> void: pass)
	Api.save_state(0, {"points": score, "sigs": sigs_completed, "combo": max_combo, "tier": tier}, func(_ok: bool, _r: Variant) -> void: pass)

func _submit_signature() -> void:
	# Calculate grade
	var hit_count := 0
	for h: bool in path_hits:
		if h:
			hit_count += 1
	var completion: float = float(hit_count) / float(max(path_hits.size(), 1))

	# Average accuracy of player points that were near the path
	var avg_acc := 0.0
	if player_path.size() > 0:
		var total_acc := 0.0
		var acc_count := 0
		for pp: Vector2 in player_path:
			var min_dist := 99999.0
			for sp: Vector2 in sig_path:
				var d: float = pp.distance_to(sp)
				if d < min_dist:
					min_dist = d
			if min_dist < ACCURACY_RADIUS * 2:
				total_acc += clampf(1.0 - min_dist / ACCURACY_RADIUS, 0, 1)
				acc_count += 1
		if acc_count > 0:
			avg_acc = total_acc / float(acc_count)

	var final_score: float = (completion * 0.6 + avg_acc * 0.4) * 100.0

	# Grade
	var pts := 0
	if final_score >= 90:
		grade_text = "S"
		grade_color = Color(1.0, 0.85, 0.2)
		pts = 500
		combo += 1
	elif final_score >= 75:
		grade_text = "A"
		grade_color = Color(0.3, 0.9, 0.4)
		pts = 300
		combo += 1
	elif final_score >= 60:
		grade_text = "B"
		grade_color = Color(0.4, 0.7, 1.0)
		pts = 150
		combo = 0
	else:
		grade_text = "C"
		grade_color = Color(0.6, 0.4, 0.4)
		pts = 50
		combo = 0

	if combo > max_combo:
		max_combo = combo
	if combo >= 3:
		pts = int(pts * (1.0 + combo * 0.15))

	# Speed bonus — time left on this sig as fraction of total
	var time_bonus: float = clampf(game_timer / GAME_DURATION, 0.1, 1.0)
	pts = int(pts * (1.0 + time_bonus * 0.3))

	score += pts
	sigs_completed += 1
	sig_count_total += 1
	total_grade_pts += int(final_score)
	grade_pts = pts
	grade_timer = 0.8
	grade_stamp_scale = 2.5

	# Update tier
	for i in range(tier_thresholds.size() - 1, -1, -1):
		if score >= tier_thresholds[i]:
			tier = i
			break

	# Ink splatter
	var cx: float = sw / 2.0
	var cy: float = sh * 0.45
	for i in range(8):
		var angle: float = randf() * TAU
		var spd: float = randf_range(40, 120)
		particles.append({
			"p": Vector2(cx + randf_range(-u, u), cy + randf_range(-u * 0.5, u * 0.5)),
			"v": Vector2(cos(angle), sin(angle)) * spd,
			"life": randf_range(0.3, 0.6),
			"max_life": 0.6,
			"size": randf_range(2, 6),
			"color": Color(0.1, 0.08, 0.15, 0.8),
		})

	pops.append({"p": Vector2(cx, cy - u * 1.5), "text": "+%d" % pts, "timer": 1.2, "color": grade_color})

	# Brief grade display, then next sig
	game_state = 2

# ─────────────────────────── SIGNATURE GENERATION ───────────────────────────

func _generate_signature() -> void:
	sig_path.clear()
	sig_control_points.clear()
	player_path.clear()
	path_hits.clear()
	is_drawing = false

	# Complexity ramps significantly with each signature
	var complexity: int = sig_count_total  # 0, 1, 2, 3...
	var num_points: int = clampi(5 + complexity, 5, 20)
	var loop_chance: float = clampf(0.15 + complexity * 0.08, 0.15, 0.7)
	var curve_intensity: float = clampf(0.5 + complexity * 0.15, 0.5, 2.0)
	var y_amplitude: float = clampf(0.25 + complexity * 0.05, 0.25, 0.6)
	var num_flourishes: int = clampi(1 + complexity / 3, 1, 4)

	var margin: float = u * 1.5
	var area_w: float = sw - margin * 2
	var area_h: float = sh * 0.3
	var base_y: float = sh * 0.45

	sig_control_points.clear()

	for i in range(num_points):
		var t: float = float(i) / float(num_points - 1)
		var x: float = margin + t * area_w

		# Multi-frequency vertical variation for natural cursive feel
		var y_off := 0.0
		y_off += sin(t * PI * randf_range(1.5, 3.0)) * area_h * y_amplitude
		y_off += sin(t * PI * randf_range(3.0, 6.0)) * area_h * y_amplitude * 0.4

		# Loops: insert a vertical excursion (up then back)
		if randf() < loop_chance and i > 0 and i < num_points - 1:
			y_off += sin(t * PI * randf_range(4.0, 8.0)) * area_h * 0.4

		# Crossbacks at high complexity: x backtracks slightly
		if complexity >= 4 and randf() < 0.2 and i > 1 and i < num_points - 1:
			x -= area_w * randf_range(0.03, 0.08)

		sig_control_points.append(Vector2(x, base_y + y_off))

	# Flourishes at the end (underlines, loops, swoops)
	var last: Vector2 = sig_control_points[sig_control_points.size() - 1]
	for f in range(num_flourishes):
		var fx: float = last.x - area_w * randf_range(0.05, 0.2) * (f + 1)
		var fy: float = last.y + u * randf_range(0.2, 0.6)
		if f % 2 == 1:
			fy = last.y - u * randf_range(0.2, 0.5)  # upward flourish
		sig_control_points.append(Vector2(fx, fy))
		last = Vector2(fx, fy)

	# Sample the bezier path with curviness scaling
	sig_path.clear()
	for i in range(sig_control_points.size() - 1):
		var p0: Vector2 = sig_control_points[i]
		var p1: Vector2 = sig_control_points[i + 1]
		var mid: Vector2 = (p0 + p1) / 2.0
		if i > 0:
			var dir: Vector2 = (p1 - p0).normalized()
			var perp: Vector2 = Vector2(-dir.y, dir.x)
			mid += perp * randf_range(-u * curve_intensity, u * curve_intensity)

		var steps: int = max(10, int(p0.distance_to(p1) / PATH_SAMPLE_DIST))
		for s in range(steps):
			var t: float = float(s) / float(steps)
			var point: Vector2 = (1 - t) * (1 - t) * p0 + 2 * (1 - t) * t * mid + t * t * p1
			sig_path.append(point)

	sig_path.append(sig_control_points[sig_control_points.size() - 1])

	path_hits.resize(sig_path.size())
	path_hits.fill(false)

# ─────────────────────────── INPUT ───────────────────────────

func _input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var is_press := false
	var is_release := false
	var is_move := false

	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		pos = t.position
		is_press = t.pressed
		is_release = not t.pressed
	elif event is InputEventScreenDrag:
		pos = (event as InputEventScreenDrag).position
		is_move = true
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pos = mb.position
			is_press = mb.pressed
			is_release = not mb.pressed
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		pos = (event as InputEventMouseMotion).position
		is_move = true

	if game_state == 0 and is_press:
		_start_game()
		return

	if game_state == 3 and is_press:
		_start_game()
		return

	if game_state != 1:
		return

	if is_press:
		is_drawing = true
		player_path.clear()
		player_path.append(pos)
		_update_hits(pos)

	if is_move and is_drawing:
		player_path.append(pos)
		_update_hits(pos)

	if is_release and is_drawing:
		is_drawing = false
		player_path.append(pos)
		_update_hits(pos)
		_submit_signature()

func _update_hits(pos: Vector2) -> void:
	for i in range(sig_path.size()):
		if not path_hits[i]:
			if pos.distance_to(sig_path[i]) < ACCURACY_RADIUS:
				path_hits[i] = true

# ─────────────────────────── PROCESS ───────────────────────────

func _process(delta: float) -> void:
	var s: Vector2 = _get_ss()
	sw = s.x
	sh = s.y
	u = min(sw, sh) / 10.0

	if game_state == 1:
		game_timer -= delta
		if game_timer <= 0:
			game_timer = 0
			_end_game()

	if game_state == 2:
		grade_timer -= delta
		grade_stamp_scale = lerpf(grade_stamp_scale, 1.0, 0.15)
		if grade_timer <= 0:
			game_state = 1
			_generate_signature()

	# Particles
	for i in range(particles.size() - 1, -1, -1):
		particles[i]["p"] += particles[i]["v"] * delta
		particles[i]["v"] *= 0.92
		particles[i]["life"] -= delta
		if particles[i]["life"] <= 0:
			particles.remove_at(i)

	# Pops
	for i in range(pops.size() - 1, -1, -1):
		pops[i]["p"].y -= 35 * delta
		pops[i]["timer"] -= delta
		if pops[i]["timer"] <= 0:
			pops.remove_at(i)

	queue_redraw()

# ─────────────────────────── DRAW ───────────────────────────

func _draw() -> void:
	# Paper background
	draw_rect(Rect2(0, 0, sw, sh), Color(0.95, 0.93, 0.88))

	# Subtle grid lines (lined paper feel)
	var line_spacing: float = u * 0.6
	var line_y: float = u * 2.0
	while line_y < sh - u:
		draw_line(Vector2(u * 0.5, line_y), Vector2(sw - u * 0.5, line_y), Color(0.85, 0.82, 0.78), 1.0)
		line_y += line_spacing

	# Left margin line
	draw_line(Vector2(u * 1.2, 0), Vector2(u * 1.2, sh), Color(0.9, 0.6, 0.6, 0.3), 1.5)

	match game_state:
		0: _draw_title()
		1: _draw_playing()
		2: _draw_grading()
		3: _draw_gameover()

	# Particles
	for p: Dictionary in particles:
		var alpha: float = clampf(p["life"] / p["max_life"], 0, 1)
		var sz: float = p["size"] * alpha
		draw_circle(p["p"], sz, Color(p["color"], alpha))

	# Pops
	for pop: Dictionary in pops:
		var alpha: float = clampf(pop["timer"] / 1.0, 0, 1)
		var fs: float = u * 0.45
		draw_string(ThemeDB.fallback_font, pop["p"], pop["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, int(fs), Color(pop["color"], alpha))

func _draw_title() -> void:
	var cx: float = sw / 2.0

	# Title in "handwritten" style
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 3, sh * 0.25), "SIGNATURE", HORIZONTAL_ALIGNMENT_CENTER, int(u * 6), int(u * 0.8), Color(0.15, 0.1, 0.2))
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 3, sh * 0.25 + u * 0.9), "FORGE", HORIZONTAL_ALIGNMENT_CENTER, int(u * 6), int(u * 0.8), Color(0.15, 0.1, 0.2))

	# Decorative line
	draw_line(Vector2(cx - u * 2, sh * 0.25 + u * 1.5), Vector2(cx + u * 2, sh * 0.25 + u * 1.5), Color(0.3, 0.25, 0.35, 0.5), 2.0)

	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 3, sh * 0.55), "Trace the signature as\naccurately as you can", HORIZONTAL_ALIGNMENT_CENTER, int(u * 6), int(u * 0.28), Color(0.4, 0.35, 0.45))

	var blink: bool = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
	if blink:
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, sh * 0.75), "Tap to Start", HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.35), Color(0.3, 0.25, 0.4))

	if best_score > 0:
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, sh * 0.88), "Best: %d pts" % best_score, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.25), Color(0.5, 0.45, 0.5))

func _draw_playing() -> void:
	_draw_hud()
	_draw_signature_target()
	_draw_player_trace()
	_draw_live_accuracy()

func _draw_grading() -> void:
	_draw_hud()
	_draw_signature_target()
	_draw_player_trace()

	# Grade stamp — centered in screen
	var cx: float = sw / 2.0
	var cy: float = sh * 0.45
	var stamp_fs: float = u * 1.5 * grade_stamp_scale
	var stamp_r: float = stamp_fs * 0.5
	draw_circle(Vector2(cx, cy), stamp_r, Color(grade_color, 0.15))
	draw_arc(Vector2(cx, cy), stamp_r, 0, TAU, 32, Color(grade_color, 0.5), 3.0)
	# Center the letter: offset by half the font ascent
	var letter_fs: int = int(stamp_fs * 0.8)
	draw_string(ThemeDB.fallback_font, Vector2(cx - stamp_r, cy + float(letter_fs) * 0.35), grade_text, HORIZONTAL_ALIGNMENT_CENTER, int(stamp_r * 2), letter_fs, grade_color)

func _draw_gameover() -> void:
	# Dim overlay
	draw_rect(Rect2(0, 0, sw, sh), Color(0.95, 0.93, 0.88, 0.9))

	var cx: float = sw / 2.0
	var y: float = sh * 0.15

	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 3, y), "SESSION COMPLETE", HORIZONTAL_ALIGNMENT_CENTER, int(u * 6), int(u * 0.5), Color(0.15, 0.1, 0.2))

	y += u * 1.2
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y), "%d pts" % score, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.65), Color(0.2, 0.15, 0.25))

	y += u * 1.0
	# Tier badge
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y), "Rank: %s" % tier_names[tier], HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.35), tier_colors[tier])

	y += u * 0.7
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y), "%d signatures traced" % sigs_completed, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.28), Color(0.4, 0.35, 0.45))

	if sigs_completed > 0:
		y += u * 0.5
		var avg: int = total_grade_pts / max(sigs_completed, 1)
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y), "Avg accuracy: %d%%" % avg, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.25), Color(0.4, 0.35, 0.45))

	y += u * 0.5
	if max_combo >= 2:
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y), "Best chain: x%d" % max_combo, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.25), Color(0.3, 0.7, 0.4))

	y += u * 1.2
	var blink: bool = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
	if blink:
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y), "Tap to play again", HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.3), Color(0.4, 0.35, 0.45))

func _draw_hud() -> void:
	var bar_pad: float = u * 0.4
	var bar_y: float = u * 0.25
	var fs_sm: float = u * 0.25
	var fs_med: float = u * 0.35

	# Timer bar
	var bar_w: float = sw - bar_pad * 2
	draw_rect(Rect2(bar_pad, bar_y, bar_w, u * 0.1), Color(0.85, 0.82, 0.78))
	var frac: float = clampf(game_timer / GAME_DURATION, 0, 1)
	var tcol: Color = Color(0.3, 0.25, 0.4).lerp(Color(0.8, 0.2, 0.2), 1.0 - frac)
	if frac > 0:
		draw_rect(Rect2(bar_pad, bar_y, bar_w * frac, u * 0.1), tcol)

	# Timer + score
	draw_string(ThemeDB.fallback_font, Vector2(bar_pad, bar_y + u * 0.25), "%ds" % ceili(game_timer), HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs_sm), Color(0.5, 0.45, 0.5))
	draw_string(ThemeDB.fallback_font, Vector2(sw - bar_pad, bar_y + u * 0.25), "%d pts" % score, HORIZONTAL_ALIGNMENT_RIGHT, -1, int(fs_med), Color(0.2, 0.15, 0.25))

	# Tier
	draw_string(ThemeDB.fallback_font, Vector2(sw / 2.0 - u, bar_y + u * 0.25), tier_names[tier], HORIZONTAL_ALIGNMENT_CENTER, int(u * 2), int(fs_sm), tier_colors[tier])

	# Combo
	if combo >= 2:
		var cc: Color = Color(0.3, 0.7, 0.4) if combo < 5 else Color(0.9, 0.5, 0.2)
		draw_string(ThemeDB.fallback_font, Vector2(sw / 2.0 - u, bar_y + u * 0.55), "x%d chain!" % combo, HORIZONTAL_ALIGNMENT_CENTER, int(u * 2), int(fs_sm), cc)

	# Sig count
	draw_string(ThemeDB.fallback_font, Vector2(bar_pad, bar_y + u * 0.55), "#%d" % (sigs_completed + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs_sm), Color(0.6, 0.55, 0.6))

func _draw_signature_target() -> void:
	if sig_path.size() < 2:
		return

	# Draw target signature path
	for i in range(sig_path.size() - 1):
		var hit_a: bool = path_hits[i] if i < path_hits.size() else false
		var hit_b: bool = path_hits[i + 1] if (i + 1) < path_hits.size() else false
		var col: Color
		if hit_a and hit_b:
			col = Color(0.6, 0.8, 0.5, 0.3)  # hit — faded green
		else:
			col = Color(0.7, 0.65, 0.55, 0.5)  # target — gold/tan
		draw_line(sig_path[i], sig_path[i + 1], col, 3.0)

	# Start dot
	draw_circle(sig_path[0], u * 0.15, Color(0.3, 0.7, 0.4, 0.6))
	draw_string(ThemeDB.fallback_font, sig_path[0] + Vector2(-u * 0.3, -u * 0.2), "start", HORIZONTAL_ALIGNMENT_CENTER, int(u * 0.8), int(u * 0.15), Color(0.3, 0.6, 0.35))

func _draw_player_trace() -> void:
	if player_path.size() < 2:
		return
	# Draw player's ink trace
	for i in range(player_path.size() - 1):
		# Vary thickness slightly for ink feel
		var thickness: float = 2.0 + sin(float(i) * 0.1) * 0.8
		draw_line(player_path[i], player_path[i + 1], Color(0.1, 0.05, 0.15, 0.9), thickness)

func _draw_live_accuracy() -> void:
	if not is_drawing or player_path.size() < 5:
		return
	# Show live completion %
	var hit_count := 0
	for h: bool in path_hits:
		if h:
			hit_count += 1
	var pct: int = int(float(hit_count) / float(max(path_hits.size(), 1)) * 100)
	var col: Color = Color(0.3, 0.7, 0.4) if pct > 60 else Color(0.8, 0.5, 0.2) if pct > 30 else Color(0.6, 0.3, 0.3)
	draw_string(ThemeDB.fallback_font, Vector2(sw - u * 1.5, sh - u * 0.8), "%d%%" % pct, HORIZONTAL_ALIGNMENT_RIGHT, -1, int(u * 0.4), col)
