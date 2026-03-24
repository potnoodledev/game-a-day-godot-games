extends Node2D

# DAY 41: KI BRAWL — Martial Arts Energy Battle
# Tap to charge ki energy. Release to fire blasts at enemies.
# Deflect incoming attacks by tapping them. Power up through waves.

# === CONSTANTS ===
const GAME_DURATION := 90.0
const CHARGE_RATE := 40.0
const MAX_KI := 100.0
const BLAST_SPEED := 350.0
const ENEMY_SPEED_BASE := 120.0
const SPAWN_INTERVAL_BASE := 2.0
const DEFLECT_RADIUS := 50.0

# === STATE ===
var game_state := 0  # 0=title, 1=playing, 2=gameover
var state_timer := 0.0
var score := 0
var best_score := 0
var game_timer := 0.0
var ki := 0.0
var charging := false
var power_level := 1
var combo := 0
var max_combo := 0
var enemies_defeated := 0
var wave := 1

# === SCREEN ===
var sw := 800.0
var sh := 600.0

# === PLAYER ===
var player_pos := Vector2.ZERO
var player_aura := 0.0
var shielding := false
var shield_radius := 35.0
const SHIELD_KI_COST := 15.0  # ki per second to maintain shield

# === BLASTS ===
# {p: Vector2, v: Vector2, power: float, radius: float, color: Color}
var blasts: Array[Dictionary] = []

# === ENEMIES ===
# {p: Vector2, v: Vector2, hp: float, sz: float, type: int, flash: float}
var enemies: Array[Dictionary] = []
var spawn_timer := 0.0

# === ENEMY PROJECTILES ===
# {p: Vector2, v: Vector2, sz: float}
var enemy_shots: Array[Dictionary] = []

# === PARTICLES ===
# {p: Vector2, color: Color, life: float, v: Vector2, sz: float}
var particles: Array[Dictionary] = []

# === AURA PARTICLES ===
var aura_timer := 0.0

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
	ki = 50.0
	charging = false
	power_level = 1
	combo = 0
	max_combo = 0
	enemies_defeated = 0
	wave = 1
	blasts.clear()
	enemies.clear()
	enemy_shots.clear()
	particles.clear()
	spawn_timer = 0.0
	player_pos = Vector2(sw * 0.5, sh * 0.75)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if game_state == 0 and event.pressed:
			_start_game()
			return
		if game_state == 2 and event.pressed and state_timer > 1.5:
			game_state = 0
			return
		if game_state == 1:
			if event.pressed:
				var tapped: Vector2 = event.position

				# Check if tapping near player — activate shield
				if tapped.distance_to(player_pos) < shield_radius + 20 and ki >= 5:
					shielding = true
					return

				# Check if tapping an enemy projectile to deflect
				var deflected := false
				var i := enemy_shots.size() - 1
				while i >= 0:
					var shot: Dictionary = enemy_shots[i]
					if tapped.distance_to(shot["p"]) < DEFLECT_RADIUS:
						var dir: Vector2 = (Vector2(shot["p"]) - player_pos).normalized()
						blasts.append({"p": Vector2(shot["p"]), "v": dir * BLAST_SPEED * 0.8, "power": 15.0, "radius": 6.0, "color": Color(0.3, 0.8, 1.0)})
						_spawn_burst(shot["p"], Color(0.3, 0.8, 1.0), 6)
						enemy_shots.remove_at(i)
						combo += 1
						max_combo = maxi(max_combo, combo)
						score += 5 * combo
						deflected = true
						break
					i -= 1
				if not deflected:
					charging = true
			else:
				# Release
				if shielding:
					shielding = false
				elif charging and ki >= 10:
					_fire_blast(event.position)
				charging = false

func _fire_blast(target: Vector2) -> void:
	var dir := (target - player_pos).normalized()
	var power := minf(ki, 50.0)
	var radius := 5.0 + power * 0.15
	var col := Color(1.0, 0.8, 0.2) if power_level < 3 else Color(0.2, 0.6, 1.0)
	if power_level >= 5:
		col = Color(1.0, 0.3, 0.3)

	blasts.append({"p": Vector2(player_pos), "v": dir * BLAST_SPEED, "power": power, "radius": radius, "color": col})
	ki -= minf(ki, power)
	_spawn_burst(player_pos, col, 4)

# ─────────────────────────── PROCESS ───────────────────────────

func _process(delta: float) -> void:
	var vp := _get_ss()
	sw = vp.x; sh = vp.y
	player_pos = Vector2(sw * 0.5, sh * 0.75)
	state_timer += delta

	if game_state == 1:
		_tick_game(delta)

	# Update particles
	var i := particles.size() - 1
	while i >= 0:
		var p: Dictionary = particles[i]
		p["life"] = float(p["life"]) - delta
		p["p"] = Vector2(p["p"]) + Vector2(p["v"]) * delta
		if float(p["life"]) <= 0:
			particles.remove_at(i)
		i -= 1

	queue_redraw()

func _tick_game(delta: float) -> void:
	game_timer -= delta
	wave = 1 + int((GAME_DURATION - game_timer) / 15.0)

	# Shield drains ki
	if shielding:
		ki -= SHIELD_KI_COST * delta
		if ki <= 0:
			ki = 0
			shielding = false

	# Charge ki (not while shielding)
	if charging and not shielding:
		ki = minf(ki + CHARGE_RATE * delta, MAX_KI)
		player_aura = minf(player_aura + delta * 3.0, 1.0)
	elif not shielding:
		# Passive regen
		ki = minf(ki + 5.0 * delta, MAX_KI)
		player_aura = maxf(player_aura - delta * 2.0, 0.0)

	# Aura particles when charging
	if charging:
		aura_timer += delta
		while aura_timer > 0.05:
			aura_timer -= 0.05
			var angle := randf() * TAU
			var dist := randf_range(20, 40 + player_aura * 20)
			var pp := player_pos + Vector2(cos(angle), sin(angle)) * dist
			var col := Color(1.0, 0.9, 0.3, 0.6) if power_level < 3 else Color(0.3, 0.6, 1.0, 0.6)
			particles.append({"p": pp, "color": col, "life": 0.4, "v": (player_pos - pp).normalized() * 60.0, "sz": 3.0})

	# Spawn enemies
	spawn_timer += delta
	var interval := SPAWN_INTERVAL_BASE / (1.0 + float(wave) * 0.3)
	while spawn_timer > interval:
		spawn_timer -= interval
		_spawn_enemy()

	# Update blasts
	var bi := blasts.size() - 1
	while bi >= 0:
		var b: Dictionary = blasts[bi]
		b["p"] = Vector2(b["p"]) + Vector2(b["v"]) * delta
		var bp: Vector2 = b["p"]
		if bp.x < -50 or bp.x > sw + 50 or bp.y < -50 or bp.y > sh + 50:
			blasts.remove_at(bi)
			bi -= 1
			continue

		# Check hits on enemies
		var ei := enemies.size() - 1
		while ei >= 0:
			var e: Dictionary = enemies[ei]
			var dist: float = bp.distance_to(e["p"])
			if dist < float(b["radius"]) + float(e["sz"]):
				e["hp"] = float(e["hp"]) - float(b["power"])
				e["flash"] = 0.15
				if float(e["hp"]) <= 0:
					var pts := 10 * wave
					score += pts
					enemies_defeated += 1
					combo += 1
					max_combo = maxi(max_combo, combo)
					_spawn_burst(e["p"], Color(1, 0.6, 0.2), 10)
					# Power up every 5 kills
					if enemies_defeated % 5 == 0:
						power_level += 1
						_spawn_burst(player_pos, Color(1, 1, 0.5), 15)
					enemies.remove_at(ei)
				blasts.remove_at(bi)
				break
			ei -= 1
		bi -= 1

	# Update enemies
	var eidx := enemies.size() - 1
	while eidx >= 0:
		var e: Dictionary = enemies[eidx]
		e["p"] = Vector2(e["p"]) + Vector2(e["v"]) * delta
		e["flash"] = maxf(float(e["flash"]) - delta, 0.0)
		var ep: Vector2 = e["p"]

		# Enemy shoots at player occasionally
		if randf() < 0.01 * float(wave):
			var dir := (player_pos - ep).normalized()
			enemy_shots.append({"p": Vector2(ep), "v": dir * (80.0 + float(wave) * 15.0), "sz": 4.0})

		# Remove if off screen bottom
		if ep.y > sh + 50:
			combo = 0
			enemies.remove_at(eidx)
		eidx -= 1

	# Update enemy shots
	var si := enemy_shots.size() - 1
	while si >= 0:
		var s: Dictionary = enemy_shots[si]
		s["p"] = Vector2(s["p"]) + Vector2(s["v"]) * delta
		var sp: Vector2 = s["p"]

		# Shield blocks shots
		if shielding and sp.distance_to(player_pos) < shield_radius:
			score += 3
			_spawn_burst(sp, Color(0.3, 0.9, 1.0), 4)
			enemy_shots.remove_at(si)
			si -= 1
			continue

		# Hit player (unshielded)
		if sp.distance_to(player_pos) < 20:
			game_timer -= 3.0
			combo = 0
			_spawn_burst(player_pos, Color(1, 0.2, 0.2), 8)
			enemy_shots.remove_at(si)
			si -= 1
			continue

		if sp.x < -20 or sp.x > sw + 20 or sp.y < -20 or sp.y > sh + 20:
			enemy_shots.remove_at(si)
		si -= 1

	# Game over
	if game_timer <= 0:
		game_timer = 0
		score += power_level * 20
		game_state = 2
		state_timer = 0.0
		best_score = maxi(best_score, score)
		Api.submit_score(score, func(_ok: bool, _r: Variant) -> void: pass)
		Api.save_state(0, {"points": best_score}, func(_ok: bool, _r: Variant) -> void: pass)

func _spawn_enemy() -> void:
	var x := randf_range(40, sw - 40)
	var type := randi() % mini(3, wave)
	var hp := 20.0 + float(type) * 15.0
	var sz := 12.0 + float(type) * 4.0
	var spd := ENEMY_SPEED_BASE + float(wave) * 10.0 - float(type) * 20.0

	enemies.append({
		"p": Vector2(x, -30),
		"v": Vector2(randf_range(-20, 20), spd),
		"hp": hp,
		"sz": sz,
		"type": type,
		"flash": 0.0,
	})

func _spawn_burst(pos: Vector2, col: Color, count: int) -> void:
	for k in count:
		var angle := randf() * TAU
		var spd := randf_range(40, 120)
		particles.append({
			"p": Vector2(pos),
			"color": Color(col.r, col.g, col.b, 0.8),
			"life": randf_range(0.3, 0.6),
			"v": Vector2(cos(angle), sin(angle)) * spd,
			"sz": randf_range(2, 5),
		})

# ─────────────────────────── DRAWING ───────────────────────────

func _draw() -> void:
	draw_rect(Rect2(0, 0, sw, sh), Color(0.03, 0.02, 0.08))

	match game_state:
		0: _draw_title()
		1: _draw_game()
		2: _draw_game(); _draw_gameover()

	# Particles
	for p in particles:
		var a: float = clampf(float(p["life"]) / 0.5, 0, 1)
		var col: Color = p["color"]
		col.a = a
		draw_circle(p["p"], float(p["sz"]) * a, col)

func _draw_game() -> void:
	# Ground line
	draw_line(Vector2(0, sh * 0.85), Vector2(sw, sh * 0.85), Color(0.15, 0.12, 0.25), 1.0)

	# Player
	var pcol := Color(1.0, 0.8, 0.2) if power_level < 3 else Color(0.3, 0.7, 1.0)
	if power_level >= 5:
		pcol = Color(1.0, 0.3, 0.3)

	# Aura glow
	if player_aura > 0.1:
		var aura_sz := 30.0 + player_aura * 25.0
		draw_circle(player_pos, aura_sz, Color(pcol.r, pcol.g, pcol.b, 0.08 + player_aura * 0.12))
		draw_circle(player_pos, aura_sz * 0.7, Color(pcol.r, pcol.g, pcol.b, 0.06 + player_aura * 0.08))

	# Shield
	if shielding:
		var shield_alpha := 0.15 + sin(state_timer * 8.0) * 0.05
		draw_arc(player_pos, shield_radius, 0, TAU, 32, Color(0.3, 0.9, 1.0, shield_alpha + 0.2), 2.5)
		draw_circle(player_pos, shield_radius, Color(0.3, 0.9, 1.0, shield_alpha))

	# Player body
	draw_circle(player_pos, 14, pcol)
	draw_circle(player_pos, 10, pcol.lightened(0.2))
	# Power level indicator
	if power_level > 1:
		for k in mini(power_level, 8):
			var angle := float(k) / float(mini(power_level, 8)) * TAU + state_timer * 2.0
			var orb_pos := player_pos + Vector2(cos(angle), sin(angle)) * 22
			draw_circle(orb_pos, 3, Color(pcol.r, pcol.g, pcol.b, 0.5))

	# Blasts
	for b in blasts:
		var col: Color = b["color"]
		var r: float = b["radius"]
		draw_circle(b["p"], r + 3, Color(col.r, col.g, col.b, 0.3))
		draw_circle(b["p"], r, col)
		draw_circle(b["p"], r * 0.5, col.lightened(0.4))

	# Enemies
	for e in enemies:
		var ep: Vector2 = e["p"]
		var sz: float = e["sz"]
		var type: int = e["type"]
		var flash: float = e["flash"]

		var ecol := Color(0.8, 0.2, 0.3) if type == 0 else Color(0.6, 0.2, 0.7) if type == 1 else Color(0.2, 0.3, 0.8)
		if flash > 0:
			ecol = Color(1, 1, 1)

		# Draw based on type
		if type == 0:
			draw_circle(ep, sz, ecol)
		elif type == 1:
			# Diamond
			var pts: PackedVector2Array = PackedVector2Array()
			pts.append(ep + Vector2(0, -sz))
			pts.append(ep + Vector2(sz * 0.7, 0))
			pts.append(ep + Vector2(0, sz))
			pts.append(ep + Vector2(-sz * 0.7, 0))
			var cols: PackedColorArray = PackedColorArray()
			for _k in 4: cols.append(ecol)
			draw_polygon(pts, cols)
		else:
			# Star
			var pts: PackedVector2Array = PackedVector2Array()
			for k in 8:
				var angle := float(k) / 8.0 * TAU
				var r := sz if k % 2 == 0 else sz * 0.5
				pts.append(ep + Vector2(cos(angle), sin(angle)) * r)
			var cols: PackedColorArray = PackedColorArray()
			for _k in 8: cols.append(ecol)
			draw_polygon(pts, cols)

		# HP bar
		var hp_pct := clampf(float(e["hp"]) / (20.0 + float(type) * 15.0), 0, 1)
		if hp_pct < 1.0:
			var bar_w := sz * 2
			draw_rect(Rect2(ep.x - bar_w * 0.5, ep.y - sz - 6, bar_w, 3), Color(0.3, 0.1, 0.1))
			draw_rect(Rect2(ep.x - bar_w * 0.5, ep.y - sz - 6, bar_w * hp_pct, 3), Color(0.2, 0.9, 0.3))

	# Enemy shots
	for s in enemy_shots:
		draw_circle(s["p"], float(s["sz"]), Color(1, 0.3, 0.5, 0.8))
		draw_circle(s["p"], float(s["sz"]) * 0.5, Color(1, 0.6, 0.7))

	# HUD
	_draw_hud()

func _draw_hud() -> void:
	var secs := ceili(maxf(game_timer, 0))
	var timer_col := Color(1, 0.3, 0.2) if secs <= 15 else Color(1, 1, 1, 0.7)
	_txt(Vector2(sw * 0.5, 14), str(secs) + "s", 18, timer_col)
	_txt(Vector2(sw * 0.5, 32), str(score) + " pts", 13, Color(0.8, 0.85, 0.9, 0.6))

	# Ki bar
	var bar_w := 100.0
	var bar_x := sw * 0.5 - bar_w * 0.5
	var bar_y := sh * 0.88
	draw_rect(Rect2(bar_x, bar_y, bar_w, 6), Color(0.15, 0.1, 0.2))
	var ki_col := Color(1.0, 0.8, 0.2) if power_level < 3 else Color(0.3, 0.7, 1.0)
	draw_rect(Rect2(bar_x, bar_y, bar_w * ki / MAX_KI, 6), ki_col)
	_txt(Vector2(sw * 0.5, bar_y + 16), "KI", 9, Color(0.6, 0.6, 0.55, 0.4))

	# Power level & combo
	_txt(Vector2(20, 14), "PWR " + str(power_level), 11, Color(1, 0.85, 0.2, 0.7))
	if combo > 1:
		_txt(Vector2(sw - 30, 14), "x" + str(combo), 16, Color(1, 0.85, 0.2, 0.8))

	# Wave
	_txt(Vector2(20, 30), "WAVE " + str(wave), 9, Color(0.6, 0.5, 0.7, 0.5))

	# Hints
	_txt(Vector2(sw * 0.5, sh * 0.94), "hold to charge \u00B7 release to fire \u00B7 hold near self to shield", 9, Color(0.5, 0.5, 0.45, 0.3))

func _draw_title() -> void:
	var pulse := 0.6 + sin(state_timer * 2.0) * 0.2
	_txt(Vector2(sw * 0.5, sh * 0.15), "KI BRAWL", 34, Color(1.0, 0.8, 0.2, pulse))
	_txt(Vector2(sw * 0.5, sh * 0.15 + 36), "energy battle", 15, Color(0.8, 0.7, 0.5, 0.45))

	_txt(Vector2(sw * 0.5, sh * 0.35), "Hold to charge ki energy", 14, Color(0.9, 0.85, 0.8, 0.5))
	_txt(Vector2(sw * 0.5, sh * 0.35 + 24), "Release to fire energy blasts", 14, Color(0.9, 0.85, 0.8, 0.45))
	_txt(Vector2(sw * 0.5, sh * 0.35 + 48), "Hold near yourself to activate shield", 14, Color(0.9, 0.85, 0.8, 0.4))
	_txt(Vector2(sw * 0.5, sh * 0.35 + 72), "Every 5 defeats = power up!", 13, Color(1, 0.85, 0.2, 0.4))

	# Animated energy orbs
	for k in 6:
		var angle := float(k) / 6.0 * TAU + state_timer * 1.5
		var r := 60.0 + sin(state_timer * 2 + float(k)) * 10
		var orb := Vector2(sw * 0.5, sh * 0.65) + Vector2(cos(angle), sin(angle)) * r
		draw_circle(orb, 6, Color(1.0, 0.8, 0.2, 0.3 + sin(state_timer * 3 + float(k)) * 0.15))

	var ta := 0.3 + sin(state_timer * 3.0) * 0.2
	_txt(Vector2(sw * 0.5, sh * 0.85), "TAP TO START", 22, Color(1.0, 0.8, 0.2, ta))
	if best_score > 0:
		_txt(Vector2(sw * 0.5, sh * 0.85 + 28), "best: " + str(best_score), 13, Color(0.7, 0.6, 0.5, 0.3))

func _draw_gameover() -> void:
	var a := minf(state_timer * 0.8, 1.0)
	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, 0.6 * a))
	var cx := sw * 0.5

	_txt(Vector2(cx, sh * 0.22), "BATTLE OVER", 30, Color(1.0, 0.8, 0.2, a))
	_txt(Vector2(cx, sh * 0.35), str(score) + " points", 26, Color(1, 0.9, 0.3, a * 0.85))
	_txt(Vector2(cx, sh * 0.35 + 30), str(enemies_defeated) + " defeated  |  power " + str(power_level) + "  |  combo x" + str(max_combo), 11, Color(0.7, 0.7, 0.65, a * 0.5))

	if score >= best_score and score > 0:
		_txt(Vector2(cx, sh * 0.52), "NEW BEST!", 20, Color(1, 0.85, 0.2, a))
	elif best_score > 0:
		_txt(Vector2(cx, sh * 0.52), "best: " + str(best_score), 14, Color(0.6, 0.6, 0.55, a * 0.4))

	if state_timer > 1.5:
		var ta := 0.3 + sin(state_timer * 3.0) * 0.2
		_txt(Vector2(cx, sh * 0.72), "TAP TO RETRY", 22, Color(1.0, 0.8, 0.2, ta))

# ─────────────────────────── TEXT HELPER ───────────────────────────

func _txt(pos: Vector2, text: String, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var ss := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5 + 1, size * 0.35 + 1),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.4))
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5, size * 0.35),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
