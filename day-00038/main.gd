extends Node2D

# DAY 38: AUTONOMOUS AGENTS — Evolution Simulator
# Creatures with random traits compete, reproduce, and evolve.
# Tap to place food and guide natural selection.

# === CONSTANTS ===
const MAX_AGENTS := 150
const MAX_FOOD := 120
const INITIAL_AGENTS := 20
const FOOD_SPAWN_RATE := 2.0       # food per second
const ENERGY_DRAIN_BASE := 3.0     # per second base drain
const REPRODUCE_THRESHOLD := 80.0
const REPRODUCE_COST := 45.0
const MUTATION_RATE := 0.15        # max mutation per trait
const EAT_RANGE := 8.0
const ATTACK_RANGE := 10.0
const WANDER_FORCE := 40.0
const GAME_DURATION := 120.0       # 2 minutes

# === STATE ===
var game_state := 0  # 0=title, 1=playing, 2=gameover
var state_timer := 0.0
var score := 0
var best_score := 0
var game_timer := 0.0
var max_gen := 0
var total_born := 0
var food_timer := 0.0

# === SCREEN ===
var sw := 800.0
var sh := 600.0

# === AGENTS ===
# Each: {p: Vector2, v: Vector2, energy: float, sz: float, spd: float,
#         vis: float, agg: float, hue: float, age: float, gen: int, wander: float}
var agents: Array[Dictionary] = []

# === FOOD ===
# Each: {p: Vector2, energy: float, meat: bool}
var food: Array[Dictionary] = []

# === STATS ===
var pop_history: Array[int] = []
var gen_history: Array[int] = []
var stat_timer := 0.0

# === TOUCH ===
var touching := false

# ─────────────────────────── LIFECYCLE ───────────────────────────

func _ready() -> void:
	Api.load_state(func(ok: bool, data: Variant) -> void:
		if ok and data and data.has("data"):
			best_score = data["data"].get("points", 0)
	)

func _get_ss() -> Vector2:
	return get_viewport().get_visible_rect().size

# ─────────────────────────── AGENT CREATION ───────────────────────────

func _new_agent(pos: Vector2, gen: int, hue: float, sz: float, spd: float, vis: float, agg: float) -> Dictionary:
	return {
		"p": pos, "v": Vector2.ZERO,
		"energy": 50.0,
		"sz": clampf(sz, 0.4, 2.5),
		"spd": clampf(spd, 0.5, 4.0),
		"vis": clampf(vis, 40.0, 250.0),
		"agg": clampf(agg, 0.0, 1.0),
		"hue": fmod(hue + 1.0, 1.0),
		"age": 0.0,
		"gen": gen,
		"wander": randf() * TAU,
	}

func _random_agent(pos: Vector2) -> Dictionary:
	return _new_agent(pos, 1,
		randf(),                        # hue
		randf_range(0.6, 1.5),         # size
		randf_range(1.0, 3.0),         # speed
		randf_range(60.0, 160.0),      # vision
		randf_range(0.0, 0.8),         # aggression
	)

func _reproduce(parent: Dictionary) -> Dictionary:
	var m := MUTATION_RATE
	var child := _new_agent(
		parent["p"] + Vector2(randf_range(-15, 15), randf_range(-15, 15)),
		int(parent["gen"]) + 1,
		float(parent["hue"]) + randf_range(-0.05, 0.05),
		float(parent["sz"]) + randf_range(-m, m),
		float(parent["spd"]) + randf_range(-m * 2, m * 2),
		float(parent["vis"]) + randf_range(-m * 40, m * 40),
		float(parent["agg"]) + randf_range(-m, m),
	)
	child["energy"] = REPRODUCE_COST * 0.8
	return child

# ─────────────────────────── FOOD ───────────────────────────

func _spawn_food(pos: Vector2, meat := false) -> void:
	if food.size() >= MAX_FOOD:
		return
	food.append({"p": pos, "energy": 20.0 if not meat else 30.0, "meat": meat})

func _spawn_random_food() -> void:
	_spawn_food(Vector2(randf_range(20, sw - 20), randf_range(20, sh - 20)))

# ─────────────────────────── GAME FLOW ───────────────────────────

func _start_game() -> void:
	game_state = 1
	state_timer = 0.0
	game_timer = GAME_DURATION
	max_gen = 1
	total_born = 0
	food_timer = 0.0
	agents.clear()
	food.clear()
	pop_history.clear()
	gen_history.clear()
	stat_timer = 0.0

	# Spawn initial agents
	for i in INITIAL_AGENTS:
		var pos := Vector2(randf_range(50, sw - 50), randf_range(50, sh - 50))
		agents.append(_random_agent(pos))
		total_born += 1

	# Scatter initial food
	for i in 30:
		_spawn_random_food()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			if game_state == 0:
				_start_game()
				return
			if game_state == 2 and state_timer > 1.5:
				game_state = 0
				return
			if game_state == 1:
				touching = true
				_spawn_food(event.position)
		else:
			touching = false

	if event is InputEventMouseMotion and touching and game_state == 1:
		_spawn_food(event.position)

# ─────────────────────────── PROCESS ───────────────────────────

func _process(delta: float) -> void:
	var vp := _get_ss()
	sw = vp.x; sh = vp.y
	state_timer += delta

	if game_state == 1:
		_tick_sim(delta)

	queue_redraw()

func _tick_sim(delta: float) -> void:
	game_timer -= delta

	# Spawn food
	food_timer += delta
	var spawn_rate := FOOD_SPAWN_RATE + float(agents.size()) * 0.05
	while food_timer > 1.0 / spawn_rate:
		food_timer -= 1.0 / spawn_rate
		_spawn_random_food()

	# Stats snapshot
	stat_timer += delta
	if stat_timer > 1.0:
		stat_timer -= 1.0
		pop_history.append(agents.size())
		gen_history.append(max_gen)
		if pop_history.size() > 120:
			pop_history.remove_at(0)
			gen_history.remove_at(0)

	# Update agents
	var new_agents: Array[Dictionary] = []
	var dead_positions: Array[Vector2] = []

	var i := 0
	while i < agents.size():
		var a: Dictionary = agents[i]
		var p: Vector2 = a["p"]
		var v: Vector2 = a["v"]
		var sz: float = a["sz"]
		var spd: float = a["spd"]
		var vis: float = a["vis"]
		var agg: float = a["agg"]
		var energy: float = a["energy"]

		a["age"] = float(a["age"]) + delta

		# === FIND NEAREST FOOD ===
		var nearest_food := -1
		var nearest_food_dist := vis
		for fi in food.size():
			var fd: float = p.distance_to(food[fi]["p"])
			if fd < nearest_food_dist:
				nearest_food_dist = fd
				nearest_food = fi

		# === FIND NEAREST AGENT ===
		var nearest_agent := -1
		var nearest_agent_dist := vis
		var nearest_agent_sz := 0.0
		for ai in agents.size():
			if ai == i:
				continue
			var ad: float = p.distance_to(agents[ai]["p"])
			if ad < nearest_agent_dist:
				nearest_agent_dist = ad
				nearest_agent = ai
				nearest_agent_sz = float(agents[ai]["sz"])

		# === BEHAVIOR ===
		var accel := Vector2.ZERO

		# Flee from bigger agents
		if nearest_agent >= 0 and nearest_agent_sz > sz * 1.2 and nearest_agent_dist < vis * 0.6:
			var flee_dir: Vector2 = (p - agents[nearest_agent]["p"]).normalized()
			accel += flee_dir * spd * 80.0

		# Attack smaller agents if aggressive
		elif nearest_agent >= 0 and agg > 0.5 and nearest_agent_sz < sz * 0.8 and nearest_agent_dist < vis * 0.5:
			var chase_dir: Vector2 = (agents[nearest_agent]["p"] - p).normalized()
			accel += chase_dir * spd * 60.0 * agg

		# Seek food
		elif nearest_food >= 0:
			var food_dir: Vector2 = (food[nearest_food]["p"] - p).normalized()
			accel += food_dir * spd * 70.0

		# Wander
		else:
			a["wander"] = float(a["wander"]) + randf_range(-1.5, 1.5) * delta
			var w: float = a["wander"]
			accel += Vector2(cos(w), sin(w)) * WANDER_FORCE

		# Apply physics
		v += accel * delta
		var max_speed := spd * 50.0
		if v.length() > max_speed:
			v = v.normalized() * max_speed
		v *= 0.95  # friction
		p += v * delta

		# Wrap at edges
		if p.x < 5: p.x = 5; v.x = absf(v.x)
		if p.x > sw - 5: p.x = sw - 5; v.x = -absf(v.x)
		if p.y < 5: p.y = 5; v.y = absf(v.y)
		if p.y > sh - 5: p.y = sh - 5; v.y = -absf(v.y)

		a["p"] = p
		a["v"] = v

		# === EAT FOOD ===
		if nearest_food >= 0 and nearest_food_dist < EAT_RANGE + sz * 3:
			energy += float(food[nearest_food]["energy"])
			food.remove_at(nearest_food)

		# === ATTACK ===
		if nearest_agent >= 0 and agg > 0.5 and nearest_agent_dist < ATTACK_RANGE + sz * 3:
			if nearest_agent_sz < sz * 0.8:
				var stolen := minf(float(agents[nearest_agent]["energy"]) * 0.3, 15.0)
				energy += stolen
				agents[nearest_agent]["energy"] = float(agents[nearest_agent]["energy"]) - stolen * 2

		# === ENERGY DRAIN ===
		var drain := ENERGY_DRAIN_BASE * sz * (0.5 + spd * 0.3)
		energy -= drain * delta
		energy = minf(energy, 100.0)
		a["energy"] = energy

		# === REPRODUCE ===
		if energy > REPRODUCE_THRESHOLD and agents.size() + new_agents.size() < MAX_AGENTS:
			a["energy"] = energy - REPRODUCE_COST
			var child := _reproduce(a)
			new_agents.append(child)
			total_born += 1
			max_gen = maxi(max_gen, int(child["gen"]))

		# === DEATH ===
		if energy <= 0:
			dead_positions.append(p)
			agents.remove_at(i)
			continue

		i += 1

	# Add newborns
	for child in new_agents:
		agents.append(child)

	# Drop meat from dead agents
	for dp in dead_positions:
		_spawn_food(dp, true)

	# Game over: time up or extinction
	if game_timer <= 0 or agents.size() == 0:
		score = max_gen * 10 + total_born
		game_state = 2
		state_timer = 0.0
		best_score = maxi(best_score, score)
		Api.submit_score(score, func(_ok: bool, _r: Variant) -> void: pass)
		Api.save_state(0, {"points": best_score}, func(_ok: bool, _r: Variant) -> void: pass)

# ─────────────────────────── DRAWING ───────────────────────────

func _draw() -> void:
	# Background
	draw_rect(Rect2(0, 0, sw, sh), Color(0.06, 0.08, 0.1))

	match game_state:
		0: _draw_title()
		1: _draw_sim(); _draw_hud()
		2: _draw_sim(); _draw_gameover()

func _draw_sim() -> void:
	# Food
	for f in food:
		var fc: Color
		if f["meat"]:
			fc = Color(0.85, 0.25, 0.2, 0.7)
		else:
			fc = Color(0.3, 0.8, 0.3, 0.7)
		var fsz := 3.0 if not f["meat"] else 4.0
		draw_circle(f["p"], fsz, fc)

	# Agents
	for a in agents:
		var p: Vector2 = a["p"]
		var sz: float = a["sz"]
		var hue: float = a["hue"]
		var agg: float = a["agg"]
		var energy: float = a["energy"]
		var v: Vector2 = a["v"]

		var radius := 4.0 + sz * 4.0

		# Body color from hue
		var col := Color.from_hsv(hue, 0.7, 0.85)

		# Energy indicator: dimmer when low
		var energy_pct := clampf(energy / 100.0, 0.1, 1.0)
		col.a = 0.5 + energy_pct * 0.5

		# Body
		draw_circle(p, radius, col)

		# Dark outline
		draw_arc(p, radius, 0, TAU, 16, col.darkened(0.3), 1.5)

		# Aggression indicator: red ring for aggressive
		if agg > 0.5:
			draw_arc(p, radius + 2, 0, TAU, 12, Color(0.9, 0.2, 0.1, agg * 0.4), 1.5)

		# Direction indicator
		if v.length() > 5:
			var dir := v.normalized()
			draw_line(p, p + dir * (radius + 4), col.lightened(0.3), 1.5)

		# Generation badge (small number)
		var gen: int = a["gen"]
		if gen > 1:
			var font := ThemeDB.fallback_font
			var gen_str := str(gen)
			var gen_size := font.get_string_size(gen_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 8)
			font.draw_string(get_canvas_item(), p + Vector2(-gen_size.x * 0.5, 3),
				gen_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.6))

func _draw_hud() -> void:
	var secs := ceili(maxf(game_timer, 0))
	var timer_col := Color(1, 0.3, 0.2) if secs <= 15 else Color(1, 1, 1, 0.7)
	_txt(Vector2(sw * 0.5, 12), str(secs) + "s", 18, timer_col)

	_txt(Vector2(sw * 0.5, 32), "pop: " + str(agents.size()) + "  gen: " + str(max_gen), 13, Color(0.8, 0.8, 0.75, 0.5))

	# Trait averages
	if agents.size() > 0:
		var avg_sz := 0.0
		var avg_spd := 0.0
		var avg_agg := 0.0
		for a in agents:
			avg_sz += float(a["sz"])
			avg_spd += float(a["spd"])
			avg_agg += float(a["agg"])
		var n := float(agents.size())
		avg_sz /= n; avg_spd /= n; avg_agg /= n
		_txt(Vector2(sw * 0.5, 48), "avg size:%.1f spd:%.1f agg:%.0f%%" % [avg_sz, avg_spd, avg_agg * 100], 10, Color(0.7, 0.7, 0.65, 0.35))

	# Population graph (bottom left)
	if pop_history.size() > 2:
		var gx := 10.0
		var gy := sh - 50.0
		var gw := 120.0
		var gh := 40.0
		draw_rect(Rect2(gx, gy, gw, gh), Color(0.15, 0.15, 0.2, 0.5))
		var max_pop := 1
		for pp in pop_history:
			max_pop = maxi(max_pop, pp)
		for j in pop_history.size() - 1:
			var x1 := gx + float(j) / float(pop_history.size() - 1) * gw
			var x2 := gx + float(j + 1) / float(pop_history.size() - 1) * gw
			var y1 := gy + gh - float(pop_history[j]) / float(max_pop) * gh
			var y2 := gy + gh - float(pop_history[j + 1]) / float(max_pop) * gh
			draw_line(Vector2(x1, y1), Vector2(x2, y2), Color(0.3, 0.8, 0.4, 0.6), 1.5)
		_txt(Vector2(gx + gw * 0.5, gy - 4), "population", 8, Color(0.6, 0.6, 0.55, 0.35))

	# Touch hint
	_txt(Vector2(sw * 0.5, sh - 14), "tap to place food", 10, Color(0.6, 0.6, 0.55, 0.25))

func _draw_title() -> void:
	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, 0.5))
	var pulse := 0.6 + sin(state_timer * 2.0) * 0.2
	_txt(Vector2(sw * 0.5, sh * 0.15), "AUTONOMOUS AGENTS", 30, Color(0.4, 0.9, 0.5, pulse))
	_txt(Vector2(sw * 0.5, sh * 0.15 + 36), "evolution simulator", 16, Color(0.7, 0.8, 0.7, 0.45))

	_txt(Vector2(sw * 0.5, sh * 0.36), "Creatures evolve through natural selection", 14, Color(0.8, 0.85, 0.8, 0.5))
	_txt(Vector2(sw * 0.5, sh * 0.36 + 24), "Size, speed, vision, aggression — all mutate", 14, Color(0.8, 0.85, 0.8, 0.45))
	_txt(Vector2(sw * 0.5, sh * 0.36 + 48), "Tap to place food and guide evolution", 14, Color(0.8, 0.85, 0.8, 0.4))
	_txt(Vector2(sw * 0.5, sh * 0.36 + 72), "Red rings = aggressive hunters", 13, Color(0.9, 0.4, 0.3, 0.4))
	_txt(Vector2(sw * 0.5, sh * 0.36 + 92), "Numbers = generation count", 13, Color(0.7, 0.8, 0.7, 0.35))

	# Legend
	draw_circle(Vector2(sw * 0.35, sh * 0.72), 4, Color(0.3, 0.8, 0.3, 0.7))
	_txt(Vector2(sw * 0.35 + 12, sh * 0.72), "= plant food", 11, Color(0.7, 0.7, 0.65, 0.4))
	draw_circle(Vector2(sw * 0.35, sh * 0.72 + 18), 4, Color(0.85, 0.25, 0.2, 0.7))
	_txt(Vector2(sw * 0.35 + 12, sh * 0.72 + 18), "= meat (from dead agents)", 11, Color(0.7, 0.7, 0.65, 0.4))

	var ta := 0.3 + sin(state_timer * 3.0) * 0.2
	_txt(Vector2(sw * 0.5, sh * 0.88), "TAP TO START", 22, Color(0.4, 0.9, 0.5, ta))
	if best_score > 0:
		_txt(Vector2(sw * 0.5, sh * 0.88 + 28), "best: " + str(best_score), 13, Color(0.6, 0.7, 0.6, 0.3))

func _draw_gameover() -> void:
	var a := minf(state_timer * 0.8, 1.0)
	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, 0.55 * a))
	var cx := sw * 0.5
	if agents.size() == 0:
		_txt(Vector2(cx, sh * 0.25), "EXTINCTION", 32, Color(0.9, 0.3, 0.2, a))
	else:
		_txt(Vector2(cx, sh * 0.25), "TIME'S UP", 32, Color(0.9, 0.9, 0.8, a))

	_txt(Vector2(cx, sh * 0.38), str(score) + " points", 24, Color(0.4, 0.9, 0.5, a * 0.8))
	_txt(Vector2(cx, sh * 0.38 + 28), "gen " + str(max_gen) + "  |  " + str(total_born) + " born", 14, Color(0.7, 0.8, 0.7, a * 0.6))

	if agents.size() > 0:
		# Show evolved traits
		var avg_sz := 0.0; var avg_spd := 0.0; var avg_agg := 0.0; var avg_vis := 0.0
		for ag in agents:
			avg_sz += float(ag["sz"]); avg_spd += float(ag["spd"])
			avg_agg += float(ag["agg"]); avg_vis += float(ag["vis"])
		var n := float(agents.size())
		_txt(Vector2(cx, sh * 0.52), "Evolved traits:", 14, Color(0.8, 0.85, 0.8, a * 0.5))
		_txt(Vector2(cx, sh * 0.52 + 20), "size %.1f  speed %.1f  vision %.0f  aggression %.0f%%" % [avg_sz/n, avg_spd/n, avg_vis/n, avg_agg/n*100], 11, Color(0.7, 0.8, 0.7, a * 0.4))

	if score >= best_score and score > 0:
		_txt(Vector2(cx, sh * 0.64), "NEW BEST!", 18, Color(0.4, 0.9, 0.5, a))
	elif best_score > 0:
		_txt(Vector2(cx, sh * 0.64), "best: " + str(best_score), 13, Color(0.6, 0.7, 0.6, a * 0.4))

	if state_timer > 1.5:
		var ta := 0.3 + sin(state_timer * 3.0) * 0.2
		_txt(Vector2(cx, sh * 0.78), "TAP TO RETRY", 20, Color(0.4, 0.9, 0.5, ta))

# ─────────────────────────── TEXT HELPER ───────────────────────────

func _txt(pos: Vector2, text: String, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var ss := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5 + 1, size * 0.35 + 1),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.4))
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5, size * 0.35),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
