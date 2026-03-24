extends Node2D

# DAY 42: PULSE FIRE — Top-Down Arena Shooter
# Tap anywhere to fire a pulse in that direction.
# Enemies swarm from the edges. Survive as long as you can.

# === CONSTANTS ===
const GAME_DURATION := 90.0
const BULLET_SPEED := 500.0
const BULLET_LIFE := 1.2
const ENEMY_SPEED_BASE := 60.0
const SPAWN_INTERVAL_BASE := 1.2
const PLAYER_RADIUS := 12.0

# === STATE ===
var game_state := 0  # 0=title, 1=playing, 2=gameover
var state_timer := 0.0
var score := 0
var best_score := 0
var game_timer := 0.0
var wave := 1
var kills := 0
var combo := 0
var max_combo := 0

# === SCREEN ===
var sw := 800.0
var sh := 600.0

# === PLAYER ===
var player_pos := Vector2.ZERO
var player_hit_flash := 0.0

# === BULLETS ===
# {p: Vector2, v: Vector2, life: float}
var bullets: Array[Dictionary] = []

# === ENEMIES ===
# {p: Vector2, hp: int, sz: float, spd: float, type: int, flash: float}
var enemies: Array[Dictionary] = []
var spawn_timer := 0.0

# === PARTICLES ===
# {p: Vector2, v: Vector2, life: float, color: Color, sz: float}
var particles: Array[Dictionary] = []

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
	wave = 1
	kills = 0
	combo = 0
	max_combo = 0
	player_hit_flash = 0.0
	bullets.clear()
	enemies.clear()
	particles.clear()
	spawn_timer = 0.0
	player_pos = Vector2(sw * 0.5, sh * 0.5)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if game_state == 0:
			_start_game()
			return
		if game_state == 2 and state_timer > 1.5:
			game_state = 0
			return
		if game_state == 1:
			_fire(event.position)

func _fire(target: Vector2) -> void:
	var dir: Vector2 = (target - player_pos).normalized()
	bullets.append({
		"p": Vector2(player_pos),
		"v": dir * BULLET_SPEED,
		"life": BULLET_LIFE,
	})
	# Muzzle flash particles
	for k in 3:
		var spread: Vector2 = dir.rotated(randf_range(-0.3, 0.3)) * randf_range(60, 120)
		particles.append({"p": Vector2(player_pos) + dir * 15, "v": spread, "life": 0.15, "color": Color(1, 0.8, 0.3, 0.8), "sz": 2.5})

# ─────────────────────────── PROCESS ───────────────────────────

func _process(delta: float) -> void:
	var vp := _get_ss()
	sw = vp.x; sh = vp.y
	player_pos = Vector2(sw * 0.5, sh * 0.5)
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

	queue_redraw()

func _tick_game(delta: float) -> void:
	game_timer -= delta
	wave = 1 + int((GAME_DURATION - game_timer) / 12.0)

	# Spawn enemies
	spawn_timer += delta
	var interval := SPAWN_INTERVAL_BASE / (1.0 + float(wave) * 0.25)
	while spawn_timer > interval:
		spawn_timer -= interval
		_spawn_enemy()

	# Update bullets
	var bi := bullets.size() - 1
	while bi >= 0:
		var b: Dictionary = bullets[bi]
		b["p"] = Vector2(b["p"]) + Vector2(b["v"]) * delta
		b["life"] = float(b["life"]) - delta
		if float(b["life"]) <= 0:
			bullets.remove_at(bi)
			bi -= 1
			continue

		# Hit enemies
		var bp: Vector2 = b["p"]
		var hit := false
		var ei := enemies.size() - 1
		while ei >= 0:
			var e: Dictionary = enemies[ei]
			if bp.distance_to(e["p"]) < float(e["sz"]) + 4:
				e["hp"] = int(e["hp"]) - 1
				e["flash"] = 0.1
				if int(e["hp"]) <= 0:
					kills += 1
					combo += 1
					max_combo = maxi(max_combo, combo)
					var pts := (5 + int(e["type"]) * 5) * mini(combo, 10)
					score += pts
					_spawn_burst(e["p"], Color(1, 0.5, 0.2), 8)
					enemies.remove_at(ei)
				hit = true
				break
			ei -= 1
		if hit:
			bullets.remove_at(bi)
		bi -= 1

	# Update enemies
	var eidx := enemies.size() - 1
	while eidx >= 0:
		var e: Dictionary = enemies[eidx]
		var dir: Vector2 = (player_pos - Vector2(e["p"])).normalized()
		e["p"] = Vector2(e["p"]) + dir * float(e["spd"]) * delta
		e["flash"] = maxf(float(e["flash"]) - delta, 0.0)

		# Hit player
		if Vector2(e["p"]).distance_to(player_pos) < float(e["sz"]) + PLAYER_RADIUS:
			game_timer -= 4.0
			combo = 0
			player_hit_flash = 0.3
			_spawn_burst(player_pos, Color(1, 0.2, 0.2), 10)
			enemies.remove_at(eidx)
		eidx -= 1

	player_hit_flash = maxf(player_hit_flash - delta, 0.0)

	# Game over
	if game_timer <= 0:
		game_timer = 0
		game_state = 2
		state_timer = 0.0
		best_score = maxi(best_score, score)
		Api.submit_score(score, func(_ok: bool, _r: Variant) -> void: pass)
		Api.save_state(0, {"points": best_score}, func(_ok: bool, _r: Variant) -> void: pass)

func _spawn_enemy() -> void:
	# Spawn from random edge
	var side := randi() % 4
	var pos := Vector2.ZERO
	match side:
		0: pos = Vector2(randf_range(0, sw), -20)  # top
		1: pos = Vector2(randf_range(0, sw), sh + 20)  # bottom
		2: pos = Vector2(-20, randf_range(0, sh))  # left
		3: pos = Vector2(sw + 20, randf_range(0, sh))  # right

	var type := 0
	var roll := randf()
	if wave >= 3 and roll > 0.7:
		type = 1  # medium
	if wave >= 5 and roll > 0.9:
		type = 2  # large

	var hp := 1 + type
	var sz := 8.0 + float(type) * 5.0
	var spd := ENEMY_SPEED_BASE + float(wave) * 8.0 - float(type) * 15.0

	enemies.append({"p": pos, "hp": hp, "sz": sz, "spd": spd, "type": type, "flash": 0.0})

func _spawn_burst(pos: Vector2, col: Color, count: int) -> void:
	for k in count:
		var angle := randf() * TAU
		var spd := randf_range(50, 150)
		particles.append({"p": Vector2(pos), "v": Vector2(cos(angle), sin(angle)) * spd, "life": randf_range(0.2, 0.5), "color": Color(col.r, col.g, col.b, 0.8), "sz": randf_range(2, 4)})

# ─────────────────────────── DRAWING ───────────────────────────

func _draw() -> void:
	draw_rect(Rect2(0, 0, sw, sh), Color(0.02, 0.02, 0.06))

	match game_state:
		0: _draw_title()
		1: _draw_game()
		2: _draw_game(); _draw_gameover()

	# Particles
	for p in particles:
		var a: float = clampf(float(p["life"]) / 0.4, 0, 1)
		var col: Color = p["color"]
		col.a = a
		draw_circle(p["p"], float(p["sz"]) * a, col)

func _draw_game() -> void:
	# Grid background
	var grid_col := Color(0.08, 0.08, 0.14)
	for gx in range(0, int(sw) + 40, 40):
		draw_line(Vector2(float(gx), 0), Vector2(float(gx), sh), grid_col, 1.0)
	for gy in range(0, int(sh) + 40, 40):
		draw_line(Vector2(0, float(gy)), Vector2(sw, float(gy)), grid_col, 1.0)

	# Enemies
	for e in enemies:
		var ep: Vector2 = e["p"]
		var sz: float = e["sz"]
		var type: int = e["type"]
		var ecol := Color(0.9, 0.25, 0.3) if type == 0 else Color(0.7, 0.2, 0.8) if type == 1 else Color(0.9, 0.6, 0.1)
		if float(e["flash"]) > 0:
			ecol = Color(1, 1, 1)
		draw_circle(ep, sz, ecol)
		draw_circle(ep, sz * 0.5, ecol.lightened(0.3))

	# Bullets
	for b in bullets:
		var bp: Vector2 = b["p"]
		var bv: Vector2 = b["v"]
		var trail: Vector2 = bp - bv.normalized() * 8
		draw_line(trail, bp, Color(1, 0.9, 0.4, 0.6), 2.0)
		draw_circle(bp, 3, Color(1, 0.95, 0.6))

	# Player
	var pcol := Color(0.3, 0.8, 1.0)
	if player_hit_flash > 0:
		pcol = Color(1, 0.3, 0.3)
	# Outer ring
	draw_arc(player_pos, PLAYER_RADIUS + 4, 0, TAU, 24, Color(pcol.r, pcol.g, pcol.b, 0.2), 2.0)
	draw_circle(player_pos, PLAYER_RADIUS, pcol)
	draw_circle(player_pos, PLAYER_RADIUS * 0.6, pcol.lightened(0.3))
	# Crosshair lines
	for k in 4:
		var angle := float(k) / 4.0 * TAU + state_timer * 0.5
		var inner := player_pos + Vector2(cos(angle), sin(angle)) * (PLAYER_RADIUS + 8)
		var outer := player_pos + Vector2(cos(angle), sin(angle)) * (PLAYER_RADIUS + 14)
		draw_line(inner, outer, Color(pcol.r, pcol.g, pcol.b, 0.3), 1.5)

	# HUD
	var secs := ceili(maxf(game_timer, 0))
	var timer_col := Color(1, 0.3, 0.2) if secs <= 15 else Color(1, 1, 1, 0.7)
	_txt(Vector2(sw * 0.5, 14), str(secs) + "s", 18, timer_col)
	_txt(Vector2(sw * 0.5, 32), str(score), 14, Color(0.8, 0.85, 0.9, 0.6))
	_txt(Vector2(20, 14), "WAVE " + str(wave), 11, Color(0.5, 0.7, 0.9, 0.5))
	if combo > 1:
		_txt(Vector2(sw - 30, 14), "x" + str(combo), 16, Color(1, 0.85, 0.2, 0.8))
	_txt(Vector2(sw * 0.5, sh - 12), "tap to shoot", 9, Color(0.4, 0.4, 0.4, 0.3))

func _draw_title() -> void:
	# Animated crosshair
	for k in 8:
		var angle := float(k) / 8.0 * TAU + state_timer * 0.8
		var r := 50.0 + sin(state_timer * 2 + float(k)) * 8
		var p := Vector2(sw * 0.5, sh * 0.6) + Vector2(cos(angle), sin(angle)) * r
		draw_circle(p, 4, Color(0.3, 0.8, 1.0, 0.2 + sin(state_timer * 3 + float(k)) * 0.1))

	var pulse := 0.6 + sin(state_timer * 2.0) * 0.2
	_txt(Vector2(sw * 0.5, sh * 0.15), "PULSE FIRE", 34, Color(0.3, 0.85, 1.0, pulse))
	_txt(Vector2(sw * 0.5, sh * 0.15 + 34), "arena shooter", 15, Color(0.5, 0.7, 0.85, 0.45))

	_txt(Vector2(sw * 0.5, sh * 0.35), "Tap anywhere to fire", 14, Color(0.8, 0.85, 0.9, 0.5))
	_txt(Vector2(sw * 0.5, sh * 0.35 + 24), "Enemies swarm from all sides", 14, Color(0.8, 0.85, 0.9, 0.45))
	_txt(Vector2(sw * 0.5, sh * 0.35 + 48), "Getting hit costs 4 seconds", 14, Color(0.9, 0.4, 0.3, 0.4))
	_txt(Vector2(sw * 0.5, sh * 0.35 + 72), "Chain kills for combo multiplier", 13, Color(1, 0.85, 0.2, 0.4))

	var ta := 0.3 + sin(state_timer * 3.0) * 0.2
	_txt(Vector2(sw * 0.5, sh * 0.85), "TAP TO START", 22, Color(0.3, 0.85, 1.0, ta))
	if best_score > 0:
		_txt(Vector2(sw * 0.5, sh * 0.85 + 28), "best: " + str(best_score), 13, Color(0.5, 0.6, 0.7, 0.3))

func _draw_gameover() -> void:
	var a := minf(state_timer * 0.8, 1.0)
	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, 0.6 * a))
	var cx := sw * 0.5

	_txt(Vector2(cx, sh * 0.22), "GAME OVER", 30, Color(0.3, 0.85, 1.0, a))
	_txt(Vector2(cx, sh * 0.35), str(score) + " points", 26, Color(1, 0.9, 0.3, a * 0.85))
	_txt(Vector2(cx, sh * 0.35 + 30), str(kills) + " kills  |  wave " + str(wave) + "  |  max combo x" + str(max_combo), 11, Color(0.7, 0.7, 0.65, a * 0.5))

	if score >= best_score and score > 0:
		_txt(Vector2(cx, sh * 0.52), "NEW BEST!", 20, Color(1, 0.85, 0.2, a))
	elif best_score > 0:
		_txt(Vector2(cx, sh * 0.52), "best: " + str(best_score), 14, Color(0.5, 0.6, 0.7, a * 0.4))

	if state_timer > 1.5:
		var ta := 0.3 + sin(state_timer * 3.0) * 0.2
		_txt(Vector2(cx, sh * 0.72), "TAP TO RETRY", 22, Color(0.3, 0.85, 1.0, ta))

# ─────────────────────────── TEXT HELPER ───────────────────────────

func _txt(pos: Vector2, text: String, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var ss := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5 + 1, size * 0.35 + 1),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.4))
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5, size * 0.35),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
