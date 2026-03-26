extends Node2D

# DAY 43: DINO SURVIVORS — Bullet Heaven / Survivors-like
# Move your dinosaur by tapping/dragging. Auto-attacks fire at nearest enemy.
# Collect XP orbs, pick upgrades every level-up. Survive 3 minutes!

# === CONSTANTS ===
const GAME_DURATION := 180.0
const PLAYER_SPEED := 180.0
const PLAYER_MAX_HP := 5
const ATTACK_COOLDOWN_BASE := 0.5
const ATTACK_RANGE := 300.0
const BULLET_SPEED := 350.0
const BULLET_LIFE := 0.8
const ENEMY_SPEED_BASE := 45.0
const SPAWN_INTERVAL_BASE := 1.0
const XP_MAGNET_RANGE := 60.0
const XP_PER_LEVEL := 8
const IFRAME_DURATION := 0.5
const ARENA_MARGIN := 40.0

# === STATE ===
var game_state := 0  # 0=title, 1=playing, 2=upgrade, 3=gameover
var state_timer := 0.0
var score := 0
var best_score := 0
var game_timer := 0.0
var kills := 0
var total_kills := 0

# === SCREEN ===
var sw := 800.0
var sh := 600.0

# === PLAYER ===
var player_pos := Vector2.ZERO
var player_hp := PLAYER_MAX_HP
var player_max_hp := PLAYER_MAX_HP
var player_iframe := 0.0
var player_level := 1
var player_xp := 0
var player_xp_needed := XP_PER_LEVEL
var move_target := Vector2(-1, -1)
var is_dragging := false

# === EVOLUTION ===
# 0=raptor, 1=big raptor, 2=triceratops, 3=t-rex
var evo_stage := 0
var evo_thresholds := [0, 20, 60, 120]
var evo_names := ["Raptor", "Alpha Raptor", "Triceratops", "T-Rex"]
var evo_colors: Array[Color] = [Color(0.2, 0.8, 0.3), Color(0.3, 0.9, 0.2), Color(0.6, 0.5, 0.2), Color(0.8, 0.2, 0.1)]
var evo_sizes: Array[float] = [10.0, 13.0, 16.0, 20.0]

# === UPGRADES ===
var atk_cooldown_mult := 1.0
var atk_damage := 1
var atk_count := 1  # multi-shot
var move_speed_mult := 1.0
var area_blast := false
var hp_regen_timer := 0.0
var hp_regen_rate := 0.0  # HP per second
var upgrade_choices: Array[Dictionary] = []

# === ATTACK ===
var attack_timer := 0.0

# === BULLETS ===
var bullets: Array[Dictionary] = []

# === ENEMIES ===
var enemies: Array[Dictionary] = []
var spawn_timer := 0.0
var wave := 1

# === XP ORBS ===
var xp_orbs: Array[Dictionary] = []

# === PARTICLES ===
var particles: Array[Dictionary] = []

# === DAMAGE NUMBERS ===
var dmg_numbers: Array[Dictionary] = []

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
	kills = 0
	total_kills = 0
	wave = 1
	player_hp = PLAYER_MAX_HP
	player_max_hp = PLAYER_MAX_HP
	player_level = 1
	player_xp = 0
	player_xp_needed = XP_PER_LEVEL
	player_iframe = 0.0
	evo_stage = 0
	atk_cooldown_mult = 1.0
	atk_damage = 1
	atk_count = 1
	move_speed_mult = 1.0
	area_blast = false
	hp_regen_rate = 0.0
	hp_regen_timer = 0.0
	magnet_mult = 1.0
	attack_timer = 0.0
	bullets.clear()
	enemies.clear()
	xp_orbs.clear()
	particles.clear()
	dmg_numbers.clear()
	spawn_timer = 0.0
	move_target = Vector2(-1, -1)
	is_dragging = false
	player_pos = Vector2(sw * 0.5, sh * 0.5)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			if game_state == 0:
				_start_game()
				return
			if game_state == 3 and state_timer > 1.5:
				game_state = 0
				return
			if game_state == 2:
				_handle_upgrade_tap(event.position)
				return
			if game_state == 1:
				is_dragging = true
				move_target = event.position
		else:
			is_dragging = false
			move_target = Vector2(-1, -1)

	if event is InputEventMouseMotion and is_dragging and game_state == 1:
		move_target = event.position

func _handle_upgrade_tap(pos: Vector2) -> void:
	var card_w := minf(sw * 0.28, 160.0)
	var card_h := 180.0
	var gap := 20.0
	var total_w: float = card_w * 3.0 + gap * 2.0
	var start_x: float = (sw - total_w) * 0.5
	var card_y: float = sh * 0.35

	for i in 3:
		if i >= upgrade_choices.size():
			break
		var cx: float = start_x + float(i) * (card_w + gap)
		if pos.x >= cx and pos.x <= cx + card_w and pos.y >= card_y and pos.y <= card_y + card_h:
			_apply_upgrade(upgrade_choices[i])
			game_state = 1
			return

# ─────────────────────────── UPGRADES ───────────────────────────

func _get_all_upgrades() -> Array[Dictionary]:
	var ups: Array[Dictionary] = []
	ups.append({"id": "fire_rate", "name": "Rapid Fire", "desc": "Attack 20% faster", "icon": ">>", "color": Color(1, 0.7, 0.2)})
	ups.append({"id": "damage", "name": "Sharp Claws", "desc": "+1 damage per hit", "icon": "!!", "color": Color(1, 0.3, 0.3)})
	ups.append({"id": "speed", "name": "Swift Legs", "desc": "Move 25% faster", "icon": "~~", "color": Color(0.3, 0.9, 1)})
	ups.append({"id": "hp_up", "name": "Thick Hide", "desc": "+2 max HP, heal full", "icon": "++", "color": Color(0.3, 1, 0.4)})
	ups.append({"id": "multi", "name": "Multi Fang", "desc": "+1 projectile", "icon": "**", "color": Color(0.9, 0.4, 1)})
	ups.append({"id": "regen", "name": "Regen", "desc": "Heal 0.5 HP/sec", "icon": "<3", "color": Color(1, 0.5, 0.7)})
	if not area_blast:
		ups.append({"id": "blast", "name": "Tail Slam", "desc": "Kills explode nearby", "icon": "()", "color": Color(1, 0.6, 0.1)})
	ups.append({"id": "magnet", "name": "XP Magnet", "desc": "Double pickup range", "icon": "@", "color": Color(0.5, 1, 0.8)})
	return ups

func _show_upgrade_screen() -> void:
	game_state = 2
	var all := _get_all_upgrades()
	# Pick 3 random
	upgrade_choices.clear()
	var indices: Array[int] = []
	for i in all.size():
		indices.append(i)
	# Shuffle
	for i in range(indices.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp := indices[i]
		indices[i] = indices[j]
		indices[j] = tmp
	for i in mini(3, indices.size()):
		upgrade_choices.append(all[indices[i]])

func _apply_upgrade(up: Dictionary) -> void:
	var id: String = up["id"]
	match id:
		"fire_rate": atk_cooldown_mult *= 0.8
		"damage": atk_damage += 1
		"speed": move_speed_mult *= 1.25
		"hp_up":
			player_max_hp += 2
			player_hp = player_max_hp
		"multi": atk_count += 1
		"regen": hp_regen_rate += 0.5
		"blast": area_blast = true
		"magnet": magnet_mult *= 2.0
	# Flash effect
	for k in 12:
		var angle := randf() * TAU
		var spd := randf_range(80, 180)
		particles.append({"p": Vector2(player_pos), "v": Vector2(cos(angle), sin(angle)) * spd, "life": 0.6, "color": Color(up["color"]), "sz": randf_range(3, 6)})

# ─────────────────────────── PROCESS ───────────────────────────

func _process(delta: float) -> void:
	var vp := _get_ss()
	sw = vp.x; sh = vp.y
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

	# Update damage numbers
	var di := dmg_numbers.size() - 1
	while di >= 0:
		var d: Dictionary = dmg_numbers[di]
		d["life"] = float(d["life"]) - delta
		d["p"] = Vector2(d["p"]) + Vector2(0, -40) * delta
		if float(d["life"]) <= 0:
			dmg_numbers.remove_at(di)
		di -= 1

	queue_redraw()

func _tick_game(delta: float) -> void:
	game_timer -= delta
	wave = 1 + int((GAME_DURATION - game_timer) / 20.0)

	# Move player
	if move_target.x >= 0:
		var dir: Vector2 = move_target - player_pos
		if dir.length() > 5:
			player_pos += dir.normalized() * PLAYER_SPEED * move_speed_mult * delta
		# Clamp to screen
		player_pos.x = clampf(player_pos.x, ARENA_MARGIN, sw - ARENA_MARGIN)
		player_pos.y = clampf(player_pos.y, ARENA_MARGIN, sh - ARENA_MARGIN)

	# iframes
	if player_iframe > 0:
		player_iframe -= delta

	# HP regen
	if hp_regen_rate > 0:
		hp_regen_timer += delta
		if hp_regen_timer >= 1.0 / hp_regen_rate:
			hp_regen_timer = 0.0
			if player_hp < player_max_hp:
				player_hp += 1

	# Auto attack
	attack_timer += delta
	var cooldown: float = ATTACK_COOLDOWN_BASE * atk_cooldown_mult
	if attack_timer >= cooldown:
		attack_timer -= cooldown
		_auto_attack()

	# Spawn enemies
	spawn_timer += delta
	var interval := SPAWN_INTERVAL_BASE / (1.0 + float(wave) * 0.2)
	interval = maxf(interval, 0.15)
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
			if bp.distance_to(e["p"]) < float(e["sz"]) + 5:
				e["hp"] = int(e["hp"]) - atk_damage
				e["flash"] = 0.12
				dmg_numbers.append({"p": Vector2(e["p"]) + Vector2(randf_range(-10, 10), -10), "text": str(atk_damage), "life": 0.6, "color": Color(1, 1, 0.5)})
				if int(e["hp"]) <= 0:
					_kill_enemy(ei)
				hit = true
				break
			ei -= 1
		if hit:
			bullets.remove_at(bi)
		bi -= 1

	# Update enemies + collision with player
	var eidx := enemies.size() - 1
	while eidx >= 0:
		var e: Dictionary = enemies[eidx]
		var dir: Vector2 = (player_pos - Vector2(e["p"])).normalized()
		e["p"] = Vector2(e["p"]) + dir * float(e["spd"]) * delta
		e["flash"] = maxf(float(e["flash"]) - delta, 0.0)

		# Hit player
		var psize: float = evo_sizes[evo_stage]
		if Vector2(e["p"]).distance_to(player_pos) < float(e["sz"]) + psize and player_iframe <= 0:
			player_hp -= 1
			player_iframe = IFRAME_DURATION
			_spawn_burst(player_pos, Color(1, 0.2, 0.2), 8)
			enemies.remove_at(eidx)
			if player_hp <= 0:
				_game_over()
				return
		eidx -= 1

	# Collect XP orbs
	var magnet_range := XP_MAGNET_RANGE * magnet_mult
	var xi := xp_orbs.size() - 1
	while xi >= 0:
		var orb: Dictionary = xp_orbs[xi]
		var op: Vector2 = orb["p"]
		var dist := op.distance_to(player_pos)
		if dist < magnet_range:
			# Move toward player
			var dir: Vector2 = (player_pos - op).normalized()
			var speed := 300.0 if dist < magnet_range * 0.5 else 150.0
			orb["p"] = op + dir * speed * delta
			if dist < 12:
				player_xp += int(orb["val"])
				xp_orbs.remove_at(xi)
				# Level up?
				if player_xp >= player_xp_needed:
					player_xp -= player_xp_needed
					player_level += 1
					player_xp_needed = XP_PER_LEVEL + player_level * 3
					_show_upgrade_screen()
		orb["life"] = float(orb["life"]) - delta
		if float(orb["life"]) <= 0:
			xp_orbs.remove_at(xi)
		xi -= 1

	# Evolution check
	for i in range(evo_thresholds.size() - 1, -1, -1):
		if total_kills >= evo_thresholds[i]:
			if evo_stage < i:
				evo_stage = i
				_spawn_burst(player_pos, evo_colors[evo_stage], 20)
			break

	# Update score
	score = total_kills * 10

	# Time up = win
	if game_timer <= 0:
		game_timer = 0
		_game_over()

var magnet_mult := 1.0

func _game_over() -> void:
	game_state = 3
	state_timer = 0.0
	# Bonus for surviving
	if game_timer <= 0:
		score += player_level * 50  # survival bonus
	best_score = maxi(best_score, score)
	Api.submit_score(score, func(_ok: bool, _r: Variant) -> void: pass)
	Api.save_state(0, {"points": best_score}, func(_ok: bool, _r: Variant) -> void: pass)

func _auto_attack() -> void:
	# Find nearest enemy
	var nearest_dist := ATTACK_RANGE
	var nearest_idx := -1
	for i in enemies.size():
		var d: float = Vector2(enemies[i]["p"]).distance_to(player_pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest_idx = i

	if nearest_idx < 0:
		return

	var target_pos: Vector2 = enemies[nearest_idx]["p"]
	var base_dir: Vector2 = (target_pos - player_pos).normalized()

	for i in atk_count:
		var spread := 0.0
		if atk_count > 1:
			spread = (float(i) - float(atk_count - 1) * 0.5) * 0.2
		var dir: Vector2 = base_dir.rotated(spread)
		bullets.append({
			"p": Vector2(player_pos) + dir * evo_sizes[evo_stage],
			"v": dir * BULLET_SPEED,
			"life": BULLET_LIFE,
		})
	# Muzzle particles
	for k in 2:
		var spread: Vector2 = base_dir.rotated(randf_range(-0.4, 0.4)) * randf_range(40, 80)
		particles.append({"p": Vector2(player_pos) + base_dir * 12, "v": spread, "life": 0.12, "color": Color(1, 0.9, 0.3, 0.7), "sz": 2.0})

func _kill_enemy(idx: int) -> void:
	var e: Dictionary = enemies[idx]
	var pos: Vector2 = e["p"]
	kills += 1
	total_kills += 1
	_spawn_burst(pos, Color(1, 0.5, 0.2), 6)

	# Drop XP orb
	xp_orbs.append({"p": Vector2(pos), "val": 1 + int(e["type"]), "life": 12.0})

	# Area blast
	if area_blast:
		var blast_range := 50.0
		var bi := enemies.size() - 1
		while bi >= 0:
			if bi != idx and bi < enemies.size():
				var other: Dictionary = enemies[bi]
				if Vector2(other["p"]).distance_to(pos) < blast_range:
					other["hp"] = int(other["hp"]) - 1
					other["flash"] = 0.12
					if int(other["hp"]) <= 0:
						var opos: Vector2 = other["p"]
						total_kills += 1
						_spawn_burst(opos, Color(1, 0.6, 0.1), 4)
						xp_orbs.append({"p": Vector2(opos), "val": 1, "life": 12.0})
						enemies.remove_at(bi)
						if bi < idx:
							idx -= 1
			bi -= 1

	if idx < enemies.size():
		enemies.remove_at(idx)

func _spawn_enemy() -> void:
	var side := randi() % 4
	var pos := Vector2.ZERO
	match side:
		0: pos = Vector2(randf_range(0, sw), -20)
		1: pos = Vector2(randf_range(0, sw), sh + 20)
		2: pos = Vector2(-20, randf_range(0, sh))
		3: pos = Vector2(sw + 20, randf_range(0, sh))

	var type := 0
	var roll := randf()
	if wave >= 3 and roll > 0.7:
		type = 1  # pterodactyl
	if wave >= 5 and roll > 0.9:
		type = 2  # big dino

	var hp := (1 + type * 2) + int(float(wave) * 0.3)
	var sz := 8.0 + float(type) * 5.0
	var spd := ENEMY_SPEED_BASE + float(wave) * 5.0 - float(type) * 10.0
	spd = maxf(spd, 25.0)

	enemies.append({"p": pos, "hp": hp, "max_hp": hp, "sz": sz, "spd": spd, "type": type, "flash": 0.0})

func _spawn_burst(pos: Vector2, col: Color, count: int) -> void:
	for k in count:
		var angle := randf() * TAU
		var spd := randf_range(50, 150)
		particles.append({"p": Vector2(pos), "v": Vector2(cos(angle), sin(angle)) * spd, "life": randf_range(0.2, 0.5), "color": Color(col.r, col.g, col.b, 0.8), "sz": randf_range(2, 5)})

# ─────────────────────────── DRAWING ───────────────────────────

func _draw() -> void:
	# Background — dark jungle green
	draw_rect(Rect2(0, 0, sw, sh), Color(0.04, 0.08, 0.04))

	match game_state:
		0: _draw_title()
		1: _draw_game()
		2: _draw_game(); _draw_upgrade_screen()
		3: _draw_game(); _draw_gameover()

	# Particles (always)
	for p in particles:
		var a: float = clampf(float(p["life"]) / 0.4, 0, 1)
		var col: Color = p["color"]
		col.a = a
		draw_circle(p["p"], float(p["sz"]) * a, col)

	# Damage numbers (always)
	for d in dmg_numbers:
		var a: float = clampf(float(d["life"]) / 0.5, 0, 1)
		_txt(d["p"], d["text"], 12, Color(d["color"].r, d["color"].g, d["color"].b, a))

func _draw_game() -> void:
	# Subtle ground pattern
	var grid_col := Color(0.06, 0.12, 0.06)
	for gx in range(0, int(sw) + 50, 50):
		draw_line(Vector2(float(gx), 0), Vector2(float(gx), sh), grid_col, 1.0)
	for gy in range(0, int(sh) + 50, 50):
		draw_line(Vector2(0, float(gy)), Vector2(sw, float(gy)), grid_col, 1.0)

	# XP orbs
	for orb in xp_orbs:
		var op: Vector2 = orb["p"]
		var val: int = orb["val"]
		var orb_col := Color(0.3, 1.0, 0.5, 0.8) if val == 1 else Color(0.4, 0.7, 1.0, 0.9)
		var orb_sz := 3.0 + float(val) * 1.5
		var pulse := 0.8 + sin(state_timer * 5.0 + op.x * 0.1) * 0.2
		draw_circle(op, orb_sz * pulse, orb_col)

	# Enemies
	for e in enemies:
		_draw_enemy(e)

	# Bullets
	for b in bullets:
		var bp: Vector2 = b["p"]
		var bv: Vector2 = b["v"]
		var trail: Vector2 = bp - bv.normalized() * 6
		draw_line(trail, bp, Color(1, 0.85, 0.3, 0.5), 2.0)
		draw_circle(bp, 3, Color(1, 0.95, 0.5))

	# Player
	_draw_player()

	# HUD
	_draw_hud()

func _draw_enemy(e: Dictionary) -> void:
	var ep: Vector2 = e["p"]
	var sz: float = e["sz"]
	var type: int = e["type"]
	var flash: float = e["flash"]

	# Enemy colors by type: caveman=brown, pterodactyl=purple, big dino=dark red
	var ecol: Color
	match type:
		0: ecol = Color(0.6, 0.4, 0.25)  # caveman brown
		1: ecol = Color(0.5, 0.2, 0.6)   # pterodactyl purple
		2: ecol = Color(0.6, 0.15, 0.1)  # big dino dark red
		_: ecol = Color(0.6, 0.4, 0.25)
	if flash > 0:
		ecol = Color(1, 1, 1)

	# Body
	draw_circle(ep, sz, ecol)

	# Type details
	match type:
		0:
			# Caveman — small circle head + legs
			draw_circle(ep + Vector2(0, -sz * 0.8), sz * 0.45, ecol.lightened(0.2))
			# Club
			draw_line(ep + Vector2(sz * 0.5, -sz * 0.3), ep + Vector2(sz * 1.2, -sz * 0.8), ecol.darkened(0.3), 2.0)
		1:
			# Pterodactyl — wings
			var wing_spread := sz * 1.5
			draw_line(ep + Vector2(-wing_spread, -sz * 0.3), ep, ecol.lightened(0.15), 2.5)
			draw_line(ep + Vector2(wing_spread, -sz * 0.3), ep, ecol.lightened(0.15), 2.5)
			# Beak
			draw_line(ep, ep + Vector2(0, -sz * 0.9), ecol.lightened(0.3), 2.0)
		2:
			# Big dino — spikes
			for k in 3:
				var angle: float = -PI * 0.5 + float(k - 1) * 0.5
				var spike_end: Vector2 = ep + Vector2(cos(angle), sin(angle)) * sz * 1.4
				draw_line(ep + Vector2(cos(angle), sin(angle)) * sz * 0.7, spike_end, ecol.lightened(0.15), 2.0)

	# HP bar (if damaged)
	if int(e["hp"]) < int(e["max_hp"]):
		var bar_w := sz * 2.0
		var bar_h := 3.0
		var hp_frac: float = float(e["hp"]) / float(e["max_hp"])
		var bar_pos := ep + Vector2(-bar_w * 0.5, -sz - 6)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.2, 0.2, 0.2, 0.6))
		draw_rect(Rect2(bar_pos, Vector2(bar_w * hp_frac, bar_h)), Color(1, 0.3, 0.2, 0.8))

func _draw_player() -> void:
	var sz: float = evo_sizes[evo_stage]
	var col: Color = evo_colors[evo_stage]

	# Iframe flash
	if player_iframe > 0 and fmod(player_iframe, 0.15) > 0.075:
		col = Color(1, 1, 1, 0.5)

	match evo_stage:
		0:
			# Raptor — small agile shape
			draw_circle(player_pos, sz, col)
			# Head
			draw_circle(player_pos + Vector2(0, -sz * 0.7), sz * 0.5, col.lightened(0.2))
			# Tail
			draw_line(player_pos + Vector2(0, sz * 0.5), player_pos + Vector2(0, sz * 1.5), col.darkened(0.2), 2.0)
		1:
			# Alpha raptor — bigger, crest
			draw_circle(player_pos, sz, col)
			draw_circle(player_pos + Vector2(0, -sz * 0.65), sz * 0.5, col.lightened(0.2))
			# Crest
			draw_line(player_pos + Vector2(0, -sz), player_pos + Vector2(-sz * 0.4, -sz * 1.5), col.lightened(0.3), 2.0)
			draw_line(player_pos + Vector2(0, -sz), player_pos + Vector2(sz * 0.4, -sz * 1.5), col.lightened(0.3), 2.0)
			draw_line(player_pos + Vector2(0, sz * 0.5), player_pos + Vector2(0, sz * 1.8), col.darkened(0.2), 2.5)
		2:
			# Triceratops — bulky, horns
			draw_circle(player_pos, sz, col)
			# Frill
			draw_arc(player_pos + Vector2(0, -sz * 0.3), sz * 1.1, PI * 0.8, PI * 1.2 + TAU, 12, col.lightened(0.15), 3.0)
			# Horns
			draw_line(player_pos + Vector2(-sz * 0.4, -sz * 0.7), player_pos + Vector2(-sz * 0.7, -sz * 1.6), Color(0.9, 0.85, 0.7), 2.5)
			draw_line(player_pos + Vector2(sz * 0.4, -sz * 0.7), player_pos + Vector2(sz * 0.7, -sz * 1.6), Color(0.9, 0.85, 0.7), 2.5)
			draw_line(player_pos + Vector2(0, -sz * 0.9), player_pos + Vector2(0, -sz * 1.5), Color(0.9, 0.85, 0.7), 2.0)
		3:
			# T-Rex — massive
			draw_circle(player_pos, sz, col)
			# Big head
			draw_circle(player_pos + Vector2(0, -sz * 0.6), sz * 0.7, col.lightened(0.15))
			# Jaw
			draw_line(player_pos + Vector2(-sz * 0.5, -sz * 0.3), player_pos + Vector2(sz * 0.5, -sz * 0.3), col.darkened(0.1), 3.0)
			# Teeth
			for k in 5:
				var tx: float = player_pos.x - sz * 0.4 + float(k) * sz * 0.2
				draw_line(Vector2(tx, player_pos.y - sz * 0.3), Vector2(tx, player_pos.y - sz * 0.1), Color(1, 1, 0.9, 0.7), 1.5)
			# Tiny arms
			draw_line(player_pos + Vector2(-sz * 0.6, 0), player_pos + Vector2(-sz * 0.9, sz * 0.3), col.darkened(0.15), 2.0)
			draw_line(player_pos + Vector2(sz * 0.6, 0), player_pos + Vector2(sz * 0.9, sz * 0.3), col.darkened(0.15), 2.0)
			# Tail
			draw_line(player_pos + Vector2(0, sz * 0.6), player_pos + Vector2(0, sz * 2.2), col.darkened(0.2), 3.0)

	# Aura ring
	var aura_a := 0.1 + sin(state_timer * 3.0) * 0.05
	draw_arc(player_pos, sz + 6, 0, TAU, 20, Color(col.r, col.g, col.b, aura_a), 1.5)

func _draw_hud() -> void:
	# Timer
	var secs := ceili(maxf(game_timer, 0))
	var mins := secs / 60
	secs = secs % 60
	var timer_str := "%d:%02d" % [mins, secs]
	var timer_col := Color(1, 0.3, 0.2) if game_timer < 30 else Color(0.8, 0.9, 0.8, 0.7)
	_txt(Vector2(sw * 0.5, 14), timer_str, 18, timer_col)

	# Score
	_txt(Vector2(sw * 0.5, 34), str(score), 13, Color(0.7, 0.8, 0.7, 0.5))

	# Evo name
	_txt(Vector2(20, 14), evo_names[evo_stage], 10, evo_colors[evo_stage] * Color(1, 1, 1, 0.6))

	# Level
	_txt(Vector2(20, 28), "Lv." + str(player_level), 10, Color(0.5, 0.8, 0.5, 0.5))

	# HP bar
	var hp_bar_w := 80.0
	var hp_bar_h := 6.0
	var hp_x := sw * 0.5 - hp_bar_w * 0.5
	var hp_y := sh - 20.0
	draw_rect(Rect2(hp_x, hp_y, hp_bar_w, hp_bar_h), Color(0.15, 0.15, 0.15, 0.6))
	var hp_frac: float = float(player_hp) / float(player_max_hp)
	var hp_col := Color(0.2, 0.9, 0.3) if hp_frac > 0.5 else Color(1, 0.8, 0.2) if hp_frac > 0.25 else Color(1, 0.2, 0.2)
	draw_rect(Rect2(hp_x, hp_y, hp_bar_w * hp_frac, hp_bar_h), hp_col)
	_txt(Vector2(sw * 0.5, hp_y - 4), "HP " + str(player_hp) + "/" + str(player_max_hp), 9, Color(0.7, 0.8, 0.7, 0.4))

	# XP bar
	var xp_bar_w := 60.0
	var xp_bar_h := 4.0
	var xp_x := sw * 0.5 - xp_bar_w * 0.5
	var xp_y := hp_y - 16
	draw_rect(Rect2(xp_x, xp_y, xp_bar_w, xp_bar_h), Color(0.1, 0.1, 0.1, 0.4))
	var xp_frac := clampf(float(player_xp) / float(player_xp_needed), 0, 1)
	draw_rect(Rect2(xp_x, xp_y, xp_bar_w * xp_frac, xp_bar_h), Color(0.3, 0.7, 1, 0.7))

	# Kill counter
	_txt(Vector2(sw - 30, 14), str(total_kills) + " kills", 10, Color(0.7, 0.6, 0.5, 0.4))

	# Wave
	_txt(Vector2(sw - 30, 28), "Wave " + str(wave), 10, Color(0.5, 0.6, 0.5, 0.4))

	# Controls hint
	_txt(Vector2(sw * 0.5, sh - 6), "tap & drag to move", 8, Color(0.3, 0.4, 0.3, 0.25))

func _draw_upgrade_screen() -> void:
	# Dim overlay
	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, 0.7))

	_txt(Vector2(sw * 0.5, sh * 0.12), "LEVEL UP!", 28, Color(0.3, 1, 0.5, 0.9))
	_txt(Vector2(sw * 0.5, sh * 0.12 + 30), "Choose an upgrade", 13, Color(0.6, 0.8, 0.6, 0.5))

	var card_w := minf(sw * 0.28, 160.0)
	var card_h := 180.0
	var gap := 20.0
	var total_w: float = card_w * 3.0 + gap * 2.0
	var start_x: float = (sw - total_w) * 0.5
	var card_y: float = sh * 0.35

	for i in mini(3, upgrade_choices.size()):
		var up: Dictionary = upgrade_choices[i]
		var cx: float = start_x + float(i) * (card_w + gap)

		# Card bg
		draw_rect(Rect2(cx, card_y, card_w, card_h), Color(0.1, 0.15, 0.1, 0.9))
		draw_rect(Rect2(cx, card_y, card_w, card_h), Color(up["color"].r, up["color"].g, up["color"].b, 0.3), false, 2.0)

		# Icon
		_txt(Vector2(cx + card_w * 0.5, card_y + 35), up["icon"], 26, up["color"])

		# Name
		_txt(Vector2(cx + card_w * 0.5, card_y + 80), up["name"], 13, Color(0.9, 0.95, 0.9))

		# Description
		_txt(Vector2(cx + card_w * 0.5, card_y + 110), up["desc"], 10, Color(0.6, 0.7, 0.6, 0.7))

func _draw_title() -> void:
	# === SKY: gradient from dark blue to burnt orange at horizon ===
	var horizon_y := sh * 0.65
	for row in 20:
		var frac := float(row) / 20.0
		var y0 := frac * horizon_y
		var y1 := (frac + 1.0 / 20.0) * horizon_y
		var sky_col := Color(0.02, 0.02, 0.08).lerp(Color(0.35, 0.12, 0.04), frac * frac)
		draw_rect(Rect2(0, y0, sw, y1 - y0 + 1), sky_col)
	# Ground
	draw_rect(Rect2(0, horizon_y, sw, sh - horizon_y), Color(0.06, 0.1, 0.04))
	# Ground line
	draw_line(Vector2(0, horizon_y), Vector2(sw, horizon_y), Color(0.12, 0.2, 0.08), 2.0)

	# === METEOR streaking across the sky ===
	var meteor_t := fmod(state_timer * 0.15, 1.0)
	var meteor_start := Vector2(sw * 0.8, sh * 0.05)
	var meteor_end := Vector2(sw * 0.15, horizon_y * 0.7)
	var meteor_pos := meteor_start.lerp(meteor_end, meteor_t)
	var meteor_a: float = 1.0 - abs(meteor_t - 0.5) * 2.0  # fade in/out
	# Tail
	for t in 8:
		var trail_frac := float(t) / 8.0
		var tp := meteor_pos.lerp(meteor_start, trail_frac * 0.25)
		var ta2: float = meteor_a * (1.0 - trail_frac) * 0.5
		draw_circle(tp, 3.0 - trail_frac * 2.0, Color(1, 0.6, 0.2, ta2))
	draw_circle(meteor_pos, 4.0, Color(1, 0.8, 0.3, meteor_a * 0.8))

	# === STARS twinkling ===
	for k in 30:
		var sx := fmod(float(k) * 137.5, sw)
		var sy := fmod(float(k) * 97.3, horizon_y * 0.8)
		var twinkle := 0.15 + sin(state_timer * 2.5 + float(k) * 1.7) * 0.12
		draw_circle(Vector2(sx, sy), 1.0, Color(1, 1, 0.9, twinkle))

	# === RUNNING DINOS silhouettes across the ground ===
	for k in 5:
		var dino_speed := 30.0 + float(k) * 12.0
		var dino_x := fmod(state_timer * dino_speed + float(k) * sw * 0.25, sw + 60.0) - 30.0
		var dino_y := horizon_y + 10 + float(k) * 18.0
		var dino_sz := 5.0 + float(k) * 2.5
		var depth_a := 0.35 - float(k) * 0.05
		var dino_col := Color(0.1, 0.18, 0.08, depth_a)
		# Body
		draw_circle(Vector2(dino_x, dino_y), dino_sz, dino_col)
		# Head (bobbing)
		var bob := sin(state_timer * 8.0 + float(k) * 2.0) * 2.0
		draw_circle(Vector2(dino_x + dino_sz * 0.9, dino_y - dino_sz * 0.6 + bob), dino_sz * 0.4, dino_col)
		# Tail
		draw_line(Vector2(dino_x - dino_sz * 0.5, dino_y), Vector2(dino_x - dino_sz * 1.8, dino_y - dino_sz * 0.3 + bob * 0.5), dino_col, 2.0)
		# Legs (animated)
		var leg_phase := state_timer * 10.0 + float(k) * 3.0
		draw_line(Vector2(dino_x - 3, dino_y + dino_sz * 0.5), Vector2(dino_x - 3 + sin(leg_phase) * 4, dino_y + dino_sz * 1.3), dino_col, 1.5)
		draw_line(Vector2(dino_x + 3, dino_y + dino_sz * 0.5), Vector2(dino_x + 3 + sin(leg_phase + PI) * 4, dino_y + dino_sz * 1.3), dino_col, 1.5)

	# === TITLE TEXT — big, centered, with glow ===
	var title_y := sh * 0.2
	# Glow behind title
	var glow_a := 0.06 + sin(state_timer * 1.5) * 0.03
	draw_circle(Vector2(sw * 0.5, title_y + 8), 90, Color(0.3, 0.9, 0.2, glow_a))
	_txt(Vector2(sw * 0.5, title_y), "DINO", 40, Color(0.3, 0.95, 0.3, 0.9))
	_txt(Vector2(sw * 0.5, title_y + 38), "SURVIVORS", 28, Color(0.9, 0.85, 0.3, 0.75))

	# === HOW TO PLAY — compact row of icons ===
	var info_y := sh * 0.52
	# Move icon (finger drag)
	_txt(Vector2(sw * 0.22, info_y), "~", 20, Color(0.5, 0.8, 0.5, 0.4))
	_txt(Vector2(sw * 0.22, info_y + 18), "drag to move", 9, Color(0.5, 0.7, 0.5, 0.35))
	# Auto attack icon
	_txt(Vector2(sw * 0.5, info_y), ">>", 20, Color(1, 0.8, 0.3, 0.4))
	_txt(Vector2(sw * 0.5, info_y + 18), "auto-attack", 9, Color(0.5, 0.7, 0.5, 0.35))
	# Level up icon
	_txt(Vector2(sw * 0.78, info_y), "UP", 20, Color(0.4, 0.7, 1, 0.4))
	_txt(Vector2(sw * 0.78, info_y + 18), "evolve & upgrade", 9, Color(0.5, 0.7, 0.5, 0.35))

	# === TAP TO START ===
	var tap_a := 0.4 + sin(state_timer * 3.0) * 0.25
	_txt(Vector2(sw * 0.5, sh * 0.85), "TAP TO START", 20, Color(0.3, 0.95, 0.3, tap_a))
	if best_score > 0:
		_txt(Vector2(sw * 0.5, sh * 0.85 + 24), "best: " + str(best_score), 11, Color(0.4, 0.5, 0.4, 0.3))

func _draw_gameover() -> void:
	var a := minf(state_timer * 0.8, 1.0)
	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, 0.65 * a))
	var cx := sw * 0.5

	var survived := game_timer <= 0
	if survived:
		_txt(Vector2(cx, sh * 0.18), "YOU SURVIVED!", 30, Color(0.3, 1, 0.4, a))
	else:
		_txt(Vector2(cx, sh * 0.18), "EXTINCT", 30, Color(1, 0.3, 0.2, a))

	_txt(Vector2(cx, sh * 0.32), str(score) + " points", 26, Color(1, 0.9, 0.3, a * 0.85))
	_txt(Vector2(cx, sh * 0.32 + 28), str(total_kills) + " kills  |  " + evo_names[evo_stage] + "  |  Lv." + str(player_level), 11, Color(0.6, 0.7, 0.6, a * 0.5))

	if score >= best_score and score > 0:
		_txt(Vector2(cx, sh * 0.48), "NEW BEST!", 20, Color(1, 0.85, 0.2, a))
	elif best_score > 0:
		_txt(Vector2(cx, sh * 0.48), "best: " + str(best_score), 13, Color(0.4, 0.5, 0.4, a * 0.4))

	if state_timer > 1.5:
		var ta := 0.3 + sin(state_timer * 3.0) * 0.2
		_txt(Vector2(cx, sh * 0.68), "TAP TO RETRY", 22, Color(0.2, 0.85, 0.3, ta))

# ─────────────────────────── TEXT HELPER ───────────────────────────

func _txt(pos: Vector2, text: String, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var ss := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5 + 1, size * 0.35 + 1),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.4))
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5, size * 0.35),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
