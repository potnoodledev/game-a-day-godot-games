extends Node2D

# DAY 47: SPIT TAKE — You're a camel at the zoo.
# TAP anywhere to spit in that direction. HOLD the camel to call fans.
# Spit annoying tourists (red/orange hats). Let fans reach you (green/blue hats).
# Spit passes through fans harmlessly — aim freely!

const GAME_DURATION := 45.0
const SPIT_SPEED := 300.0
const SPIT_GRAVITY := 350.0
const SPAWN_START := 1.6
const SPAWN_MIN := 0.5

const T_SELFIE := 0
const T_CAMERA := 1
const T_FAN := 2
const T_SUPERFAN := 3

var game_state := 0
var score := 0
var best_score := 0
var game_timer := 0.0
var combo := 0
var max_combo := 0
var hits_total := 0
var fans_greeted := 0
var lives := 3

var spits: Array[Dictionary] = []
var tourists: Array[Dictionary] = []
var spawn_timer := 0.0

var camel_x := 0.0
var camel_y := 0.0
var camel_spit_anim := 0.0
var camel_bob := 0.0
var camel_hit_flash := 0.0

# Call mechanic — tap camel to activate (cooldown-based, area effect)
var calling := false
var call_active_timer := 0.0  # how long call effect lasts (brief pulse)
var call_cooldown := 0.0  # time until next call
const CALL_DURATION := 0.8  # seconds the call lasts
const CALL_COOLDOWN := 3.0  # seconds between calls
const CALL_RADIUS_BASE := 3.0  # in u units
var call_pulse := 0.0
var fan_glow_phase := 0.0

# Spit
var spit_size_mult := 1.0
var spit_max := 2
const SPIT_RECHARGE_TIME := 1.4
var spit_charges := 2
var spit_recharge_timer := 0.0
var spit_explosive := false

# Call
var call_cd_mult := 1.0  # multiplier on cooldown (lower = faster)
var call_power_mult := 1.0  # multiplier on fan speed boost + radius

var milestone_msg := ""
var milestone_timer := 0.0
var particles: Array[Dictionary] = []
var pops: Array[Dictionary] = []
var screen_shake := 0.0

var sw := 800.0
var sh := 600.0
var u := 60.0
var ground_y := 0.0

func _ready() -> void:
	Api.load_state(func(ok: bool, data: Variant) -> void:
		if ok and data and data.has("data"):
			best_score = data["data"].get("points", 0)
	)

func _get_ss() -> Vector2:
	return get_viewport().get_visible_rect().size

func _is_annoying(type: int) -> bool:
	return type == T_SELFIE or type == T_CAMERA

func _show_milestone(msg: String) -> void:
	milestone_msg = msg
	milestone_timer = 2.0
	for i in range(8):
		particles.append({"p": Vector2(sw / 2.0, u * 1.5), "v": Vector2(randf_range(-100, 100), randf_range(-50, -100)), "life": 0.6, "max_life": 0.7, "color": Color(1.0, 0.85, 0.2), "size": 4.0})

# ─────────────────────────── GAME FLOW ───────────────────────────

func _start_game() -> void:
	game_state = 1
	score = 0; combo = 0; max_combo = 0; hits_total = 0; fans_greeted = 0; lives = 3
	game_timer = GAME_DURATION; spawn_timer = 0.8
	calling = false; call_active_timer = 0.0; call_cooldown = 0.0; call_pulse = 0.0
	spit_size_mult = 1.0; spit_max = 2; spit_charges = 2; spit_recharge_timer = 0.0; spit_explosive = false
	call_cd_mult = 1.0; call_power_mult = 1.0
	tourists.clear(); spits.clear(); particles.clear(); pops.clear()
	screen_shake = 0.0; camel_hit_flash = 0.0; milestone_msg = ""; milestone_timer = 0.0

func _end_game() -> void:
	game_state = 3
	if score > best_score: best_score = score
	Api.submit_score(score, func(_ok: bool, _r: Variant) -> void: pass)
	Api.save_state(0, {"points": score, "hits": hits_total, "fans": fans_greeted, "combo": max_combo}, func(_ok: bool, _r: Variant) -> void: pass)

# ─────────────────────────── TOURISTS ───────────────────────────

func _spawn_tourist() -> void:
	var elapsed: float = GAME_DURATION - game_timer
	var roll: float = randf()
	var fan_chance: float = clampf(0.3 + elapsed * 0.006, 0.3, 0.5)
	var type := T_SELFIE
	if roll < fan_chance:
		type = T_FAN if randf() < 0.75 else T_SUPERFAN
	else:
		type = T_SELFIE if randf() < 0.55 else T_CAMERA

	var speed: float; var size: float; var pts: int; var color: Color; var hat_color: Color; var n: String
	match type:
		T_SELFIE: speed = randf_range(35, 55); size = 1.0; pts = 100; color = Color(0.9, 0.7, 0.5); hat_color = Color(0.85, 0.25, 0.2); n = "Selfie"
		T_CAMERA: speed = randf_range(25, 45); size = 1.15; pts = 150; color = Color(0.85, 0.65, 0.5); hat_color = Color(0.9, 0.35, 0.15); n = "Camera"
		T_FAN: speed = randf_range(28, 45); size = 0.9; pts = 200; color = Color(0.7, 0.85, 0.7); hat_color = Color(0.2, 0.7, 0.3); n = "Fan"
		T_SUPERFAN: speed = randf_range(20, 38); size = 0.85; pts = 400; color = Color(0.7, 0.8, 0.95); hat_color = Color(0.2, 0.5, 0.9); n = "Superfan"

	speed *= (1.0 + elapsed * 0.015)
	# Last 10 seconds: tourists much faster
	if game_timer < 10.0:
		speed *= 1.0 + (10.0 - game_timer) * 0.08
	var t_h: float = u * 1.8 * size
	tourists.append({
		"type": type, "p": Vector2(sw + u, ground_y - t_h / 2.0),
		"base_speed": speed, "speed": speed, "size": size, "points": pts,
		"color": color, "hat_color": hat_color, "name": n,
		"alive": true, "hit_timer": 0.0, "greet_timer": 0.0,
		"slowed": false, "stunned": 0.0,
	})

# ─────────────────────────── SPIT ───────────────────────────

func _fire_spit(target: Vector2) -> void:
	if spit_charges <= 0: return
	spit_charges -= 1
	spit_recharge_timer = 0.0
	camel_spit_anim = 0.3
	var origin := Vector2(camel_x + u * 1.3, camel_y - u * 1.5)
	var dx: float = target.x - origin.x
	var dy: float = target.y - origin.y
	var t_f: float = maxf(abs(dx) / SPIT_SPEED, 0.2)
	var vx: float = dx / t_f
	var vy: float = (dy - 0.5 * SPIT_GRAVITY * t_f * t_f) / t_f
	spits.append({"p": origin, "v": Vector2(vx, vy), "alive": true, "trail": [] as Array[Vector2], "size": spit_size_mult, "explosive": spit_explosive})

func _check_spit_collisions() -> void:
	for s: Dictionary in spits:
		if not s["alive"]: continue
		var spit_r: float = u * 0.12 * s["size"]
		for t: Dictionary in tourists:
			if not t["alive"] or t["hit_timer"] > 0 or t["greet_timer"] > 0: continue
			# Spit hits ANYONE — be careful around fans!
			var t_h: float = u * 1.8 * t["size"]
			var t_w: float = u * 0.9 * t["size"]
			var t_rect := Rect2(t["p"].x - t_w / 2.0, t["p"].y - t_h / 2.0, t_w, t_h)
			if t_rect.has_point(s["p"]):
				if _is_annoying(t["type"]):
					# GOOD HIT — annoying tourist
					t["hit_timer"] = 0.8
					hits_total += 1; combo += 1
					if combo > max_combo: max_combo = combo
					var pts: int = t["points"]
					if combo >= 3: pts = int(pts * (1.0 + combo * 0.12))
					score += pts
					screen_shake = 0.12
					var spark_count: int = 10 + spit_max * 3
					for j in range(spark_count):
						var angle: float = randf() * TAU
						particles.append({"p": s["p"], "v": Vector2(cos(angle), sin(angle)) * randf_range(60, 180), "life": randf_range(0.3, 0.6), "max_life": 0.6, "color": Color(0.5, 0.85, 0.3, 0.9), "size": randf_range(3, 7)})
					var pop_text: String = "+%d" % pts
					if combo >= 3: pop_text += " x%d" % combo
					pops.append({"p": s["p"] + Vector2(0, -u * 0.3), "text": pop_text, "timer": 1.3, "color": Color(1.0, 0.9, 0.3)})
					# Explosive splash (only hits annoying tourists)
					if s["explosive"]:
						for t2: Dictionary in tourists:
							if t2 == t or not t2["alive"] or t2["hit_timer"] > 0: continue
							if not _is_annoying(t2["type"]): continue
							if t2["p"].distance_to(s["p"]) < u * 2.5:
								t2["hit_timer"] = 0.8; hits_total += 1
								var pts2: int = int(t2["points"] * 0.5)
								score += pts2
								pops.append({"p": t2["p"] + Vector2(0, -u * 0.2), "text": "+%d" % pts2, "timer": 1.0, "color": Color(1.0, 0.7, 0.2)})
						for j3 in range(12):
							var a3: float = j3 * TAU / 12.0
							particles.append({"p": s["p"], "v": Vector2(cos(a3), sin(a3)) * 120, "life": 0.3, "max_life": 0.4, "color": Color(1.0, 0.6, 0.1, 0.6), "size": 5.0})
					_check_spit_milestones()
				else:
					# BAD HIT — fan!
					t["hit_timer"] = 0.6
					combo = 0
					var penalty: int = t["points"]
					score = max(score - penalty, 0)
					screen_shake = 0.18
					for j in range(8):
						var angle: float = randf() * TAU
						particles.append({"p": s["p"], "v": Vector2(cos(angle), sin(angle)) * randf_range(40, 100), "life": 0.3, "max_life": 0.4, "color": Color(1.0, 0.3, 0.3, 0.8), "size": 4.0})
					pops.append({"p": s["p"] + Vector2(0, -u * 0.3), "text": "-%d FAN!" % penalty, "timer": 1.3, "color": Color(1.0, 0.2, 0.2)})
				s["alive"] = false
				break

func _check_spit_milestones() -> void:
	match hits_total:
		3:
			spit_max = 3; spit_size_mult = 1.2
			_show_milestone("3 Charges + Big Spit!")
		8:
			spit_max = 4; spit_size_mult = 1.4
			_show_milestone("4 Charges + Bigger Spit!")
		15:
			spit_max = 5; spit_explosive = true
			_show_milestone("5 Charges + EXPLOSIVE!")

# ─────────────────────────── CALL ───────────────────────────

func _activate_call() -> void:
	if call_cooldown > 0: return
	call_active_timer = CALL_DURATION
	call_cooldown = CALL_COOLDOWN * call_cd_mult
	call_pulse = 0.0
	calling = true
	var camel_pos := Vector2(camel_x + u * 0.5, camel_y - u)
	var slow_radius: float = (CALL_RADIUS_BASE + call_power_mult) * u
	for t: Dictionary in tourists:
		if not t["alive"] or t["hit_timer"] > 0 or t["greet_timer"] > 0: continue
		if not _is_annoying(t["type"]):
			# ALL fans on screen get speed boost (no range check)
			t["speed"] = t["base_speed"] * (1.5 + call_power_mult * 0.5)
			particles.append({"p": t["p"] + Vector2(0, -u * 0.5), "v": Vector2(randf_range(-20, 20), randf_range(-40, -20)), "life": 0.5, "max_life": 0.6, "color": Color(1.0, 0.4, 0.6, 0.7), "size": 3.0})
		else:
			# Annoying tourists: slow only within range, only if unlocked
			if call_power_mult >= 1.5:
				var d: float = t["p"].distance_to(camel_pos)
				if d <= slow_radius:
					t["speed"] = t["base_speed"] * maxf(0.3, 1.0 - call_power_mult * 0.15)
					t["slowed"] = true
	# Musical note particles
	for i in range(4):
		particles.append({"p": camel_pos + Vector2(u * 0.8, -u * 0.5), "v": Vector2(randf_range(10, 50), randf_range(-60, -90)), "life": 0.7, "max_life": 0.8, "color": Color(1.0, 0.85, 0.4, 0.8), "size": randf_range(3, 5)})

func _update_call(delta: float) -> void:
	if call_cooldown > 0: call_cooldown -= delta
	if call_active_timer > 0:
		call_active_timer -= delta
		call_pulse += delta * 6.0
		fan_glow_phase += delta * 8.0
		if call_active_timer <= 0:
			calling = false
			# Reset slowed tourists
			for t: Dictionary in tourists:
				if t["slowed"]:
					t["speed"] = t["base_speed"]
					t["slowed"] = false

# ─────────────────────────── PROCESS ───────────────────────────

func _process(delta: float) -> void:
	var s: Vector2 = _get_ss()
	sw = s.x; sh = s.y; u = min(sw, sh) / 10.0
	ground_y = sh * 0.82; camel_x = u * 1.5; camel_y = ground_y
	camel_bob = sin(Time.get_ticks_msec() * 0.003) * u * 0.05

	if game_state == 1:
		_update_call(delta)
		_process_playing(delta)

	for i in range(particles.size() - 1, -1, -1):
		particles[i]["p"] += particles[i]["v"] * delta
		particles[i]["v"] *= 0.93
		particles[i]["life"] -= delta
		if particles[i]["life"] <= 0: particles.remove_at(i)
	for i in range(pops.size() - 1, -1, -1):
		pops[i]["p"].y -= 35 * delta
		pops[i]["timer"] -= delta
		if pops[i]["timer"] <= 0: pops.remove_at(i)
	if camel_spit_anim > 0: camel_spit_anim -= delta
	if milestone_timer > 0: milestone_timer -= delta
	if screen_shake > 0: screen_shake -= delta
	if camel_hit_flash > 0: camel_hit_flash -= delta
	queue_redraw()

func _process_playing(delta: float) -> void:
	game_timer -= delta
	if game_timer <= 0: game_timer = 0; _end_game(); return

	# Spit recharge
	if spit_charges < spit_max:
		spit_recharge_timer += delta
		if spit_recharge_timer >= SPIT_RECHARGE_TIME:
			spit_charges += 1
			spit_recharge_timer = 0.0

	spawn_timer -= delta
	var elapsed: float = GAME_DURATION - game_timer
	# HARD RAMP: last 10 seconds = much faster spawning + faster tourists
	var endgame_mult: float = 1.0
	if game_timer < 10.0:
		endgame_mult = 1.0 + (10.0 - game_timer) * 0.15  # up to 2.5x at 0s
	var interval: float = lerpf(SPAWN_START, SPAWN_MIN, clampf(elapsed / GAME_DURATION, 0, 1)) / endgame_mult
	if spawn_timer <= 0:
		_spawn_tourist()
		spawn_timer = interval + randf_range(-0.2, 0.2)

	var camel_zone: float = camel_x + u * 2.0
	for t: Dictionary in tourists:
		if t["hit_timer"] > 0:
			t["hit_timer"] -= delta; t["p"].x += 120 * delta; t["p"].y -= 50 * delta
			if t["hit_timer"] <= 0: t["alive"] = false
			continue
		if t["greet_timer"] > 0:
			t["greet_timer"] -= delta
			if t["greet_timer"] <= 0: t["alive"] = false
			continue
		if t["stunned"] > 0:
			t["stunned"] -= delta
			continue
		t["p"].x -= t["speed"] * delta

		if t["p"].x <= camel_zone:
			if _is_annoying(t["type"]):
				lives -= 1; combo = 0; camel_hit_flash = 0.5; screen_shake = 0.25
				t["alive"] = false
				pops.append({"p": t["p"] + Vector2(0, -u * 0.5), "text": "OUCH!", "timer": 1.0, "color": Color(1.0, 0.2, 0.2)})
				for j in range(6):
					particles.append({"p": t["p"], "v": Vector2(randf_range(-60, 60), randf_range(-80, -20)), "life": 0.4, "max_life": 0.5, "color": Color(1.0, 0.3, 0.2, 0.8), "size": 4.0})
				if lives <= 0: _end_game(); return
			else:
				# FAN REACHED — celebration!
				t["greet_timer"] = 1.0
				fans_greeted += 1; combo += 1
				if combo > max_combo: max_combo = combo
				var pts: int = t["points"]
				if combo >= 3: pts = int(pts * (1.0 + combo * 0.1))
				score += pts
				# Big celebration particles — hearts + stars
				for j in range(12):
					var angle: float = randf() * TAU
					var pcol: Color = [Color(1.0, 0.3, 0.5), Color(1.0, 0.85, 0.2), Color(0.3, 0.9, 0.5)][j % 3]
					particles.append({"p": t["p"] + Vector2(0, -u * 0.3), "v": Vector2(cos(angle), sin(angle)) * randf_range(40, 120), "life": randf_range(0.5, 1.0), "max_life": 1.0, "color": pcol, "size": randf_range(3, 6)})
				pops.append({"p": t["p"] + Vector2(0, -u * 0.8), "text": "+%d" % pts, "timer": 1.5, "color": Color(0.3, 1.0, 0.5)})
				# Extra "WELCOME!" pop for superfans
				if t["type"] == T_SUPERFAN:
					pops.append({"p": t["p"] + Vector2(0, -u * 1.2), "text": "SUPER FAN!", "timer": 1.2, "color": Color(0.3, 0.6, 1.0)})
				# Check fan milestones
				match fans_greeted:
					3:
						call_cd_mult = 0.75; call_power_mult = 1.3
						_show_milestone("Popular! (faster call)")
					7:
						call_cd_mult = 0.5; call_power_mult = 1.8
						_show_milestone("Famous! (powerful call)")
					12:
						call_cd_mult = 0.3; call_power_mult = 2.5
						_show_milestone("LEGENDARY CAMEL!")

	for i in range(tourists.size() - 1, -1, -1):
		if not tourists[i]["alive"]: tourists.remove_at(i)

	# Spits
	for i in range(spits.size() - 1, -1, -1):
		var sp: Dictionary = spits[i]
		if not sp["alive"]: spits.remove_at(i); continue
		sp["v"].y += SPIT_GRAVITY * delta
		sp["p"] += sp["v"] * delta
		sp["trail"].append(Vector2(sp["p"]))
		if sp["trail"].size() > 14: sp["trail"].remove_at(0)
		if sp["p"].y > ground_y + u or sp["p"].x > sw + u * 2 or sp["p"].x < -u:
			sp["alive"] = false
			if sp["p"].y >= ground_y:
				for j in range(4):
					particles.append({"p": Vector2(sp["p"].x, ground_y), "v": Vector2(randf_range(-25, 25), randf_range(-30, -10)), "life": 0.3, "max_life": 0.4, "color": Color(0.4, 0.7, 0.2, 0.5), "size": 3.0})
	_check_spit_collisions()

# ─────────────────────────── INPUT ───────────────────────────

func _input(event: InputEvent) -> void:
	var pos := Vector2.ZERO

	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		pos = t.position
		if t.pressed:
			if game_state == 0 or game_state == 3:
				_start_game()
			elif game_state == 1:
				if _is_camel_area(pos):
					_activate_call()
				else:
					_fire_spit(pos)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			pos = mb.position
			if game_state == 0 or game_state == 3:
				_start_game()
			elif game_state == 1:
				if _is_camel_area(pos):
					_activate_call()
				else:
					_fire_spit(pos)

func _is_camel_area(pos: Vector2) -> bool:
	return pos.x < camel_x + u * 2.5 and pos.y > ground_y - u * 3.0

# ─────────────────────────── DRAW ───────────────────────────

func _draw() -> void:
	var shake := Vector2.ZERO
	if screen_shake > 0:
		shake = Vector2(randf_range(-3, 3), randf_range(-3, 3)) * (screen_shake / 0.2)

	# Sky
	draw_rect(Rect2(0, 0, sw, ground_y), Color(0.55, 0.78, 0.95))
	draw_circle(Vector2(sw * 0.85, u * 2) + shake, u * 0.8, Color(1.0, 0.95, 0.7, 0.4))
	# Ground
	draw_rect(Rect2(0, ground_y, sw, sh - ground_y), Color(0.85, 0.75, 0.55))
	# Cacti
	_draw_cactus(Vector2(sw * 0.55, ground_y) + shake)
	_draw_cactus(Vector2(sw * 0.82, ground_y) + shake)

	if camel_hit_flash > 0:
		draw_rect(Rect2(0, 0, sw, sh), Color(1.0, 0.15, 0.1, camel_hit_flash * 0.25))

	match game_state:
		0: _draw_title(shake)
		1: _draw_playing(shake)
		3: _draw_gameover(shake)

	# Particles
	for p: Dictionary in particles:
		var alpha: float = clampf(p["life"] / p["max_life"], 0, 1)
		draw_circle(p["p"] + shake, p["size"] * alpha, Color(p["color"], alpha))
	# Pops
	for pop: Dictionary in pops:
		var alpha: float = clampf(pop["timer"] / 1.0, 0, 1)
		var fs: float = u * 0.4 * (1.0 + (1.0 - alpha) * 0.2)
		draw_string(ThemeDB.fallback_font, pop["p"] + shake, pop["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, int(fs), Color(pop["color"], alpha))

func _draw_title(shake: Vector2) -> void:
	_draw_camel(shake)
	var cx: float = sw / 2.0
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 3, sh * 0.15) + shake, "SPIT TAKE", HORIZONTAL_ALIGNMENT_CENTER, int(u * 6), int(u * 0.8), Color(0.2, 0.5, 0.15))
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 3.5, sh * 0.15 + u * 1.0) + shake, "TAP anywhere to spit!", HORIZONTAL_ALIGNMENT_CENTER, int(u * 7), int(u * 0.28), Color(0.85, 0.3, 0.2))
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 3.5, sh * 0.15 + u * 1.35) + shake, "TAP the camel to call fans!", HORIZONTAL_ALIGNMENT_CENTER, int(u * 7), int(u * 0.28), Color(0.2, 0.7, 0.3))
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 3.5, sh * 0.15 + u * 1.7) + shake, "Don't hit fans with spit!", HORIZONTAL_ALIGNMENT_CENTER, int(u * 7), int(u * 0.22), Color(0.8, 0.35, 0.25))
	# Legend
	draw_rect(Rect2(cx - u * 2.5, sh * 0.52, u * 0.3, u * 0.2), Color(0.85, 0.25, 0.2))
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2.1, sh * 0.52 + u * 0.16) + shake, "= SPIT on them!", HORIZONTAL_ALIGNMENT_LEFT, int(u * 4), int(u * 0.22), Color(0.85, 0.25, 0.2))
	draw_rect(Rect2(cx - u * 2.5, sh * 0.52 + u * 0.35, u * 0.3, u * 0.2), Color(0.2, 0.7, 0.3))
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2.1, sh * 0.52 + u * 0.35 + u * 0.16) + shake, "= Let them through!", HORIZONTAL_ALIGNMENT_LEFT, int(u * 4), int(u * 0.22), Color(0.2, 0.7, 0.3))

	var blink: bool = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
	if blink:
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, sh * 0.78) + shake, "Tap to Start", HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.35), Color(0.3, 0.25, 0.15))
	if best_score > 0:
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, sh * 0.88) + shake, "Best: %d" % best_score, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.25), Color(0.5, 0.4, 0.3))

func _draw_playing(shake: Vector2) -> void:
	# Call visual
	if calling:
		var ring_alpha: float = 0.2 + sin(call_pulse) * 0.1
		var camel_center := Vector2(camel_x + u * 0.5, camel_y - u) + shake
		# Fan attract ring (golden, expanding)
		var ring_r: float = u * 2.0 + sin(call_pulse * 0.5) * u * 0.5
		draw_arc(camel_center, ring_r, 0, TAU, 24, Color(1.0, 0.7, 0.3, ring_alpha), 3.0)
		# Slow range ring (blue, only if unlocked)
		if call_power_mult >= 1.5:
			var slow_r: float = (CALL_RADIUS_BASE + call_power_mult) * u
			draw_arc(camel_center, slow_r, 0, TAU, 24, Color(0.3, 0.5, 1.0, ring_alpha * 0.7), 2.5)
			draw_string(ThemeDB.fallback_font, camel_center + Vector2(-u * 0.5, slow_r + u * 0.2), "SLOW ZONE", HORIZONTAL_ALIGNMENT_CENTER, int(u * 1.2), int(u * 0.13), Color(0.3, 0.5, 1.0, ring_alpha))

	# Tourists
	for t: Dictionary in tourists:
		_draw_tourist(t, shake)
	# Camel
	_draw_camel(shake)
	# Spits
	for s: Dictionary in spits:
		if not s["alive"]: continue
		for i in range(s["trail"].size()):
			var alpha: float = float(i) / float(max(s["trail"].size(), 1)) * 0.5
			draw_circle(s["trail"][i] + shake, u * 0.06 * s["size"], Color(0.5, 0.8, 0.2, alpha))
		var sr: float = u * 0.13 * s["size"]
		draw_circle(s["p"] + shake, sr, Color(0.45, 0.8, 0.2))
		draw_circle(s["p"] + shake, sr * 0.6, Color(0.55, 0.95, 0.3))
	# HUD
	_draw_hud(shake)
	# Milestone
	if milestone_timer > 0:
		var alpha: float = clampf(milestone_timer / 1.0, 0, 1)
		draw_rect(Rect2(0, sh * 0.15, sw, u * 0.7), Color(0.1, 0.3, 0.1, alpha * 0.3))
		draw_string(ThemeDB.fallback_font, Vector2(sw / 2.0 - u * 2.5, sh * 0.15 + u * 0.45) + shake, milestone_msg, HORIZONTAL_ALIGNMENT_CENTER, int(u * 5), int(u * 0.38), Color(1.0, 0.9, 0.3, alpha))

func _draw_hud(shake: Vector2) -> void:
	var pad: float = u * 0.3
	# Timer
	draw_rect(Rect2(pad + shake.x, pad + shake.y, sw - pad * 2, u * 0.1), Color(0.7, 0.65, 0.55))
	var frac: float = clampf(game_timer / GAME_DURATION, 0, 1)
	draw_rect(Rect2(pad + shake.x, pad + shake.y, (sw - pad * 2) * frac, u * 0.1), Color(0.3, 0.7, 0.2).lerp(Color(0.8, 0.2, 0.1), 1.0 - frac))
	draw_string(ThemeDB.fallback_font, Vector2(pad, pad + u * 0.25) + shake, "%ds" % ceili(game_timer), HORIZONTAL_ALIGNMENT_LEFT, -1, int(u * 0.25), Color(0.4, 0.35, 0.25))
	draw_string(ThemeDB.fallback_font, Vector2(sw - pad, pad + u * 0.25) + shake, "%d" % score, HORIZONTAL_ALIGNMENT_RIGHT, -1, int(u * 0.4), Color(0.2, 0.5, 0.15))
	if combo >= 2:
		var cc: Color = Color(0.3, 0.8, 0.2) if combo < 5 else Color(1.0, 0.5, 0.1)
		draw_string(ThemeDB.fallback_font, Vector2(sw / 2.0 - u, pad + u * 0.25) + shake, "x%d" % combo, HORIZONTAL_ALIGNMENT_CENTER, int(u * 2), int(u * 0.35), cc)
	# Lives (left side, red circles with X for lost)
	draw_string(ThemeDB.fallback_font, Vector2(pad, pad + u * 0.5) + shake, "Lives:", HORIZONTAL_ALIGNMENT_LEFT, -1, int(u * 0.15), Color(0.5, 0.4, 0.35))
	for i in range(3):
		var hx: float = pad + u * 0.7 + i * u * 0.35
		var hy: float = pad + u * 0.6
		if i < lives:
			draw_circle(Vector2(hx, hy) + shake, u * 0.1, Color(1.0, 0.3, 0.3))
		else:
			draw_circle(Vector2(hx, hy) + shake, u * 0.1, Color(0.3, 0.2, 0.2, 0.3))
	# Spit charges (right side, green circles that deplete)
	draw_string(ThemeDB.fallback_font, Vector2(sw - pad - spit_max * u * 0.35 - u * 0.6, pad + u * 0.5) + shake, "Spit:", HORIZONTAL_ALIGNMENT_LEFT, -1, int(u * 0.15), Color(0.4, 0.6, 0.3))
	for i in range(spit_max):
		var cx: float = sw - pad - u * 0.15 - (spit_max - 1 - i) * u * 0.35
		var cy: float = pad + u * 0.6
		if i < spit_charges:
			draw_circle(Vector2(cx, cy) + shake, u * 0.12, Color(0.4, 0.8, 0.2))
		else:
			draw_circle(Vector2(cx, cy) + shake, u * 0.12, Color(0.25, 0.2, 0.15, 0.3))
			if i == spit_charges:
				var fill: float = clampf(spit_recharge_timer / SPIT_RECHARGE_TIME, 0, 1)
				draw_arc(Vector2(cx, cy) + shake, u * 0.12, -PI / 2.0, -PI / 2.0 + fill * TAU, 10, Color(0.4, 0.8, 0.2, 0.6), 2.5)
	if spit_explosive:
		draw_string(ThemeDB.fallback_font, Vector2(sw - pad, pad + u * 0.85) + shake, "BOOM", HORIZONTAL_ALIGNMENT_RIGHT, -1, int(u * 0.16), Color(1.0, 0.6, 0.1))
	# Call cooldown indicator (near camel)
	if call_cooldown > 0:
		var cd_frac: float = clampf(call_cooldown / CALL_COOLDOWN, 0, 1)
		draw_arc(Vector2(camel_x + u * 0.5, ground_y - u * 2.8) + shake, u * 0.25, -PI / 2.0, -PI / 2.0 + (1.0 - cd_frac) * TAU, 12, Color(1.0, 0.7, 0.3, 0.4), 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(camel_x - u * 0.2, ground_y - u * 3.1) + shake, "CALL", HORIZONTAL_ALIGNMENT_CENTER, int(u * 1.5), int(u * 0.15), Color(0.6, 0.5, 0.3, 0.5))
	else:
		draw_string(ThemeDB.fallback_font, Vector2(camel_x - u * 0.2, ground_y - u * 3.1) + shake, "CALL", HORIZONTAL_ALIGNMENT_CENTER, int(u * 1.5), int(u * 0.15), Color(1.0, 0.8, 0.3))

func _draw_camel(shake: Vector2) -> void:
	var cx: float = camel_x + shake.x
	var cy: float = camel_y + camel_bob + shake.y
	var head_off: float = sin(camel_spit_anim * 20.0) * u * 0.15 if camel_spit_anim > 0 else 0.0
	var body_col := Color(0.75, 0.6, 0.35)
	if camel_hit_flash > 0: body_col = body_col.lerp(Color(1.0, 0.3, 0.2), camel_hit_flash)
	if calling: body_col = body_col.lerp(Color(0.9, 0.8, 0.4), 0.3)  # glow when calling
	var bw: float = u * 1.6; var bh: float = u * 1.0; var by: float = cy - bh - u * 0.4
	draw_rect(Rect2(cx - bw * 0.3, by, bw, bh), body_col)
	draw_circle(Vector2(cx + u * 0.3, by - u * 0.1), u * 0.4, body_col.darkened(0.05))
	for i in range(4):
		draw_rect(Rect2(cx - u * 0.1 + i * u * 0.35, cy - u * 0.4, u * 0.15, u * 0.4), body_col.darkened(0.1))
	var nb := Vector2(cx + u * 0.8, by + u * 0.1)
	var hp := Vector2(cx + u * 1.3 + head_off, by - u * 0.7)
	draw_line(nb, hp, body_col.darkened(0.05), u * 0.2)
	draw_circle(hp, u * 0.3, body_col)
	draw_circle(hp + Vector2(u * 0.12, -u * 0.05), u * 0.06, Color(0.1, 0.1, 0.1))
	if calling:
		draw_circle(hp + Vector2(u * 0.2, u * 0.06), u * 0.1, Color(0.4, 0.2, 0.2))  # open mouth
		# Musical notes
		var note_off: float = sin(call_pulse * 2.0) * u * 0.1
		draw_string(ThemeDB.fallback_font, hp + Vector2(u * 0.4, -u * 0.3 + note_off), "♪", HORIZONTAL_ALIGNMENT_LEFT, -1, int(u * 0.25), Color(1.0, 0.8, 0.3, 0.7))
	else:
		draw_line(hp + Vector2(u * 0.15, u * 0.08), hp + Vector2(u * 0.25, u * 0.04), Color(0.3, 0.2, 0.15), 2.0)
	if lives > 0:
		draw_rect(Rect2(hp.x + u * 0.02, hp.y - u * 0.12, u * 0.22, u * 0.1), Color(0.1, 0.1, 0.15, 0.8))

func _draw_tourist(t: Dictionary, shake: Vector2) -> void:
	var tx: float = t["p"].x + shake.x; var ty: float = t["p"].y + shake.y
	var sz: float = t["size"]; var h: float = u * 1.8 * sz; var w: float = u * 0.6 * sz
	if t["hit_timer"] > 0:
		tx += sin(t["hit_timer"] * 15.0) * u * 0.3; ty -= t["hit_timer"] * u * 0.5
	# Greet celebration — hearts float up
	if t["greet_timer"] > 0:
		var gy: float = ty - h * 0.5 - (1.0 - t["greet_timer"]) * u * 1.2
		var ga: float = t["greet_timer"]
		draw_string(ThemeDB.fallback_font, Vector2(tx - u * 0.15, gy), "♥", HORIZONTAL_ALIGNMENT_CENTER, -1, int(u * 0.4), Color(1.0, 0.3, 0.5, ga))
		draw_string(ThemeDB.fallback_font, Vector2(tx + u * 0.2, gy - u * 0.15), "♥", HORIZONTAL_ALIGNMENT_CENTER, -1, int(u * 0.25), Color(1.0, 0.5, 0.6, ga * 0.7))
	# Fan glow when call is active
	if calling and not _is_annoying(t["type"]) and t["hit_timer"] <= 0 and t["greet_timer"] <= 0:
		var glow_a: float = 0.2 + sin(fan_glow_phase + tx * 0.01) * 0.15
		draw_circle(Vector2(tx, ty), u * 0.9 * sz, Color(0.3, 1.0, 0.5, glow_a))
	# Slow/stun effect on annoying tourists
	if t["slowed"] and _is_annoying(t["type"]) and t["hit_timer"] <= 0:
		draw_circle(Vector2(tx, ty), u * 0.7 * sz, Color(0.3, 0.5, 1.0, 0.15))
	if t["stunned"] > 0:
		draw_string(ThemeDB.fallback_font, Vector2(tx - u * 0.15, ty - h * 0.5), "✦", HORIZONTAL_ALIGNMENT_CENTER, -1, int(u * 0.2), Color(0.8, 0.6, 1.0, 0.8))
	# Body
	draw_rect(Rect2(tx - w / 2.0, ty - h * 0.3, w, h * 0.5), t["color"])
	draw_circle(Vector2(tx, ty - h * 0.4), w * 0.5, t["color"].lightened(0.15))
	draw_rect(Rect2(tx - w * 0.55, ty - h * 0.58, w * 1.1, h * 0.12), t["hat_color"])
	draw_rect(Rect2(tx - w * 0.3, ty + h * 0.2, w * 0.2, h * 0.2), Color(0.3, 0.3, 0.35))
	draw_rect(Rect2(tx + w * 0.1, ty + h * 0.2, w * 0.2, h * 0.2), Color(0.3, 0.3, 0.35))
	if tx < sw * 0.85 and t["hit_timer"] <= 0 and t["greet_timer"] <= 0:
		draw_string(ThemeDB.fallback_font, Vector2(tx - u * 0.5, ty - h * 0.65), t["name"], HORIZONTAL_ALIGNMENT_CENTER, int(u * 1.2), int(u * 0.15), Color(t["hat_color"], 0.8))

func _draw_cactus(pos: Vector2) -> void:
	var h: float = u * 1.0
	draw_rect(Rect2(pos.x - u * 0.07, pos.y - h, u * 0.14, h), Color(0.3, 0.6, 0.25))
	draw_rect(Rect2(pos.x - u * 0.25, pos.y - h * 0.6, u * 0.18, u * 0.08), Color(0.3, 0.6, 0.25))
	draw_rect(Rect2(pos.x - u * 0.25, pos.y - h * 0.6, u * 0.08, u * 0.25), Color(0.3, 0.6, 0.25))
	draw_rect(Rect2(pos.x + u * 0.12, pos.y - h * 0.4, u * 0.18, u * 0.08), Color(0.3, 0.6, 0.25))
	draw_rect(Rect2(pos.x + u * 0.22, pos.y - h * 0.65, u * 0.08, u * 0.25), Color(0.3, 0.6, 0.25))

func _draw_gameover(shake: Vector2) -> void:
	draw_rect(Rect2(0, 0, sw, sh), Color(0.85, 0.75, 0.55, 0.85))
	_draw_camel(shake)
	var cx: float = sw / 2.0; var y: float = sh * 0.1
	var lost: bool = lives <= 0
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 3, y) + shake, "BUSTED!" if lost else "TIME'S UP!", HORIZONTAL_ALIGNMENT_CENTER, int(u * 6), int(u * 0.55), Color(0.2, 0.5, 0.15))
	y += u * 1.0
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y) + shake, "%d pts" % score, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.65), Color(0.15, 0.4, 0.1))
	y += u * 0.9
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y) + shake, "%d tourists spit" % hits_total, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.28), Color(0.4, 0.35, 0.25))
	y += u * 0.45
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y) + shake, "%d fans greeted" % fans_greeted, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.28), Color(0.3, 0.7, 0.3))
	y += u * 0.45
	if max_combo >= 2:
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y) + shake, "Best chain: x%d" % max_combo, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.25), Color(0.3, 0.7, 0.2))
	y += u * 0.45
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y) + shake, "Spit charges: %d" % spit_max, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.22), Color(0.5, 0.7, 0.3))
	y += u * 0.9
	var blink: bool = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
	if blink:
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y) + shake, "Tap to play again", HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.3), Color(0.3, 0.25, 0.15))
