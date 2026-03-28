extends Node2D

# DAY 45: FORGE QUEST — Blacksmith crafting game
# Drag materials to the anvil to forge weapons. Fill orders for gold.
# Every 3 orders, pick an upgrade. 90 seconds, one round, pure forging.

# === CONSTANTS ===
const GAME_DURATION := 45.0
const MAX_ORDERS := 3
const ORDER_EXPIRE_BASE := 18.0
const UPGRADE_EVERY := 3  # orders between upgrade picks

# Material types
const MAT_IRON := 0
const MAT_WOOD := 1
const MAT_GEM := 2
const MAT_LEATHER := 3
const MAT_BRONZE := 4
const MAT_SILVER := 5
const MAT_GOLD := 6
const MAT_NAMES := ["Iron", "Wood", "Gem", "Leather", "Bronze", "Silver", "Gold"]
const MAT_COLORS: Array[Color] = [
	Color(0.6, 0.65, 0.7),    # Iron
	Color(0.55, 0.35, 0.15),  # Wood
	Color(0.3, 0.8, 1.0),     # Gem
	Color(0.5, 0.3, 0.15),    # Leather
	Color(0.8, 0.55, 0.25),   # Bronze
	Color(0.78, 0.78, 0.82),  # Silver
	Color(1.0, 0.85, 0.25),   # Gold
]
const MAT_SYMBOLS := ["Fe", "W", "◆", "L", "Br", "Ag", "Au"]

var recipes := {}

# === STATE ===
var game_state := 0  # 0=title, 1=playing, 3=gameover
var score := 0
var best_score := 0
var gold := 0
var game_timer := 0.0
var combo := 0
var max_combo := 0
var orders_filled := 0
var best_item := ""
var difficulty := 0
var milestone_msg := ""
var milestone_timer := 0.0

# Screen
var sw := 800.0
var sh := 600.0
var u := 60.0

# Materials
var materials: Array[int] = []
const MAT_SLOTS := 6
var mat_rects: Array[Rect2] = []
var mat_cooldown: Array[float] = []  # refill cooldown per slot

# Anvil
var anvil_rect := Rect2()
var anvil_slots: Array[int] = []
var anvil_slot_rects: Array[Rect2] = []

# Orders
var orders: Array[Dictionary] = []

# Input (tap to add, no dragging)

# Forge animation
var forge_flash := 0.0
var forge_result := ""
var forge_result_timer := 0.0
var forge_result_gold := 0
var forge_success := false
var screen_shake := 0.0

# Particles
var sparks: Array[Dictionary] = []
var embers: Array[Dictionary] = []

# Pops
var pops: Array[Dictionary] = []

# Upgrades (auto-granted at milestones)
var forge_tier := 0  # 0=base, 1=bronze, 2=silver, 3=gold
var bonus_gold_pct := 0
var rerolls := 0  # reroll charges
var reroll_rect := Rect2()

# ─────────────────────────── LIFECYCLE ───────────────────────────

func _ready() -> void:
	_init_recipes()
	# Spawn initial embers
	for i in range(15):
		_spawn_ember()
	Api.load_state(func(ok: bool, data: Variant) -> void:
		if ok and data and data.has("data"):
			best_score = data["data"].get("points", 0)
	)

func _get_ss() -> Vector2:
	return get_viewport().get_visible_rect().size

func _init_recipes() -> void:
	recipes[_rk(MAT_IRON, MAT_WOOD)] = {"name": "Sword", "gold": 100, "color": Color(0.7, 0.7, 0.8)}
	recipes[_rk(MAT_IRON, MAT_IRON)] = {"name": "Shield", "gold": 120, "color": Color(0.6, 0.65, 0.7)}
	recipes[_rk(MAT_IRON, MAT_GEM)] = {"name": "Magic Blade", "gold": 250, "color": Color(0.4, 0.7, 1.0)}
	recipes[_rk(MAT_WOOD, MAT_LEATHER)] = {"name": "Bow", "gold": 100, "color": Color(0.55, 0.4, 0.2)}
	recipes[_rk(MAT_WOOD, MAT_WOOD)] = {"name": "Staff", "gold": 80, "color": Color(0.5, 0.35, 0.15)}
	recipes[_rk(MAT_LEATHER, MAT_LEATHER)] = {"name": "Armor", "gold": 130, "color": Color(0.45, 0.3, 0.15)}
	recipes[_rk(MAT_IRON, MAT_LEATHER)] = {"name": "Axe", "gold": 140, "color": Color(0.6, 0.5, 0.4)}
	recipes[_rk(MAT_GEM, MAT_GEM)] = {"name": "Amulet", "gold": 300, "color": Color(0.3, 0.9, 0.9)}
	recipes[_rk(MAT_GEM, MAT_LEATHER)] = {"name": "Enchanted Cape", "gold": 200, "color": Color(0.6, 0.3, 0.8)}
	recipes[_rk(MAT_GEM, MAT_WOOD)] = {"name": "Wand", "gold": 220, "color": Color(0.5, 0.8, 0.5)}
	# Bronze tier
	recipes[_rk(MAT_BRONZE, MAT_WOOD)] = {"name": "Bronze Spear", "gold": 200, "color": Color(0.8, 0.55, 0.25), "tier": 1}
	recipes[_rk(MAT_BRONZE, MAT_IRON)] = {"name": "Bronze Shield", "gold": 220, "color": Color(0.75, 0.5, 0.2), "tier": 1}
	recipes[_rk(MAT_BRONZE, MAT_GEM)] = {"name": "Enchanted Helm", "gold": 350, "color": Color(0.6, 0.8, 0.9), "tier": 1}
	recipes[_rk(MAT_BRONZE, MAT_LEATHER)] = {"name": "Bronze Armor", "gold": 250, "color": Color(0.7, 0.45, 0.2), "tier": 1}
	recipes[_rk(MAT_BRONZE, MAT_BRONZE)] = {"name": "Bronze Golem", "gold": 400, "color": Color(0.85, 0.6, 0.2), "tier": 1}
	# Silver tier
	recipes[_rk(MAT_SILVER, MAT_WOOD)] = {"name": "Silver Bow", "gold": 350, "color": Color(0.8, 0.8, 0.85), "tier": 2}
	recipes[_rk(MAT_SILVER, MAT_IRON)] = {"name": "Moonblade", "gold": 400, "color": Color(0.7, 0.75, 0.9), "tier": 2}
	recipes[_rk(MAT_SILVER, MAT_GEM)] = {"name": "Crystal Staff", "gold": 500, "color": Color(0.6, 0.85, 1.0), "tier": 2}
	recipes[_rk(MAT_SILVER, MAT_LEATHER)] = {"name": "Shadow Cloak", "gold": 380, "color": Color(0.5, 0.5, 0.65), "tier": 2}
	recipes[_rk(MAT_SILVER, MAT_BRONZE)] = {"name": "Paladin Armor", "gold": 450, "color": Color(0.8, 0.7, 0.5), "tier": 2}
	recipes[_rk(MAT_SILVER, MAT_SILVER)] = {"name": "Silver Dragon", "gold": 600, "color": Color(0.85, 0.85, 0.95), "tier": 2}
	# Gold tier
	recipes[_rk(MAT_GOLD, MAT_WOOD)] = {"name": "Phoenix Staff", "gold": 500, "color": Color(1.0, 0.6, 0.2), "tier": 3}
	recipes[_rk(MAT_GOLD, MAT_IRON)] = {"name": "Excalibur", "gold": 600, "color": Color(1.0, 0.9, 0.5), "tier": 3}
	recipes[_rk(MAT_GOLD, MAT_GEM)] = {"name": "Crown of Ages", "gold": 800, "color": Color(0.4, 1.0, 1.0), "tier": 3}
	recipes[_rk(MAT_GOLD, MAT_LEATHER)] = {"name": "Dragon Hide", "gold": 550, "color": Color(0.9, 0.7, 0.3), "tier": 3}
	recipes[_rk(MAT_GOLD, MAT_BRONZE)] = {"name": "Titan Hammer", "gold": 700, "color": Color(0.9, 0.65, 0.15), "tier": 3}
	recipes[_rk(MAT_GOLD, MAT_SILVER)] = {"name": "Celestial Blade", "gold": 900, "color": Color(1.0, 0.95, 0.8), "tier": 3}
	recipes[_rk(MAT_GOLD, MAT_GOLD)] = {"name": "Godforge Crown", "gold": 1200, "color": Color(1.0, 0.85, 0.0), "tier": 3}

func _rk(a: int, b: int) -> String:
	return "%d,%d" % [mini(a, b), maxi(a, b)]

# ─────────────────────────── GAME FLOW ───────────────────────────

func _start_game() -> void:
	game_state = 1
	score = 0
	gold = 0
	combo = 0
	max_combo = 0
	orders_filled = 0
	best_item = ""
	forge_tier = 0
	bonus_gold_pct = 0
	rerolls = 0
	difficulty = 0
	milestone_msg = ""
	milestone_timer = 0.0
	game_timer = GAME_DURATION
	orders.clear()
	anvil_slots.clear()
	sparks.clear()
	pops.clear()
	mat_cooldown.clear()
	for i in range(MAT_SLOTS):
		mat_cooldown.append(0.0)
	_refill_materials()
	_spawn_order()
	_spawn_order()

func _end_game() -> void:
	game_state = 3
	score = gold
	if score > best_score:
		best_score = score
	Api.submit_score(score, func(_ok: bool, _r: Variant) -> void: pass)
	Api.save_state(0, {"points": score, "orders": orders_filled, "best_item": best_item, "combo": max_combo}, func(_ok: bool, _r: Variant) -> void: pass)

func _check_milestones() -> void:
	match orders_filled:
		2:
			rerolls += 1
			_show_milestone("Reroll earned! (tap button)")
		4:
			forge_tier = 1
			rerolls += 1
			_show_milestone("BRONZE Tier Unlocked!")
		7:
			game_timer += 10.0
			rerolls += 1
			_show_milestone("+10s & Reroll!")
		10:
			forge_tier = 2
			rerolls += 1
			_show_milestone("SILVER Tier Unlocked!")
		14:
			game_timer += 10.0
			bonus_gold_pct += 20
			rerolls += 1
			_show_milestone("+10s & +20% Gold!")
		18:
			forge_tier = 3
			rerolls += 2
			_show_milestone("GOLD Tier Unlocked!")

func _show_milestone(msg: String) -> void:
	milestone_msg = msg
	milestone_timer = 2.0
	# Celebratory sparks
	for i in range(10):
		var angle: float = randf() * TAU
		var spd: float = randf_range(60, 150)
		sparks.append({
			"p": Vector2(sw / 2.0, sh * 0.15),
			"v": Vector2(cos(angle), sin(angle)) * spd,
			"life": randf_range(0.4, 0.8),
			"max_life": 0.8,
			"color": Color(1.0, 0.85, 0.3),
			"size": randf_range(0.06, 0.1),
		})

# ─────────────────────────── MATERIALS ───────────────────────────

func _get_available_mats() -> Array[int]:
	var available: Array[int] = [MAT_IRON, MAT_WOOD, MAT_GEM, MAT_LEATHER]
	if forge_tier >= 1:
		available.append(MAT_BRONZE)
	if forge_tier >= 2:
		available.append(MAT_SILVER)
	if forge_tier >= 3:
		available.append(MAT_GOLD)
	return available

func _refill_materials() -> void:
	materials.clear()
	var available: Array[int] = _get_available_mats()
	for i in range(MAT_SLOTS):
		materials.append(available[randi() % available.size()])

func _refill_slot(idx: int) -> void:
	var available: Array[int] = _get_available_mats()

	# Bias toward materials needed by current orders (70% chance)
	if orders.size() > 0 and randf() < 0.7:
		var needed: Array[int] = []
		for o: Dictionary in orders:
			needed.append(int(o["mat1"]))
			needed.append(int(o["mat2"]))
		var on_board: Array[int] = []
		for m: int in materials:
			if m >= 0:
				on_board.append(m)
		for m: int in anvil_slots:
			on_board.append(m)
		var still_needed: Array[int] = []
		var board_copy: Array[int] = on_board.duplicate()
		for n: int in needed:
			var found := false
			for j in range(board_copy.size()):
				if board_copy[j] == n:
					board_copy.remove_at(j)
					found = true
					break
			if not found:
				still_needed.append(n)
		if still_needed.size() > 0:
			materials[idx] = still_needed[randi() % still_needed.size()]
			mat_cooldown[idx] = 0.0
			return

	materials[idx] = available[randi() % available.size()]
	mat_cooldown[idx] = 0.0

func _do_reroll() -> void:
	if rerolls <= 0:
		return
	rerolls -= 1
	anvil_slots.clear()
	for i in range(MAT_SLOTS):
		materials[i] = -1
		mat_cooldown[i] = 0.0
	_refill_materials()
	_show_milestone("Rerolled!")
	# Sparks effect
	for i in range(MAT_SLOTS):
		var r: Rect2 = mat_rects[i] if i < mat_rects.size() else Rect2()
		if r.size.x > 0:
			for j in range(4):
				sparks.append({
					"p": r.get_center(),
					"v": Vector2(randf_range(-60, 60), randf_range(-80, -20)),
					"life": 0.4, "max_life": 0.5,
					"color": Color(0.3, 0.8, 1.0), "size": 0.06,
				})

# ─────────────────────────── ORDERS ───────────────────────────

func _spawn_order() -> void:
	if orders.size() >= MAX_ORDERS:
		return
	var keys: Array = recipes.keys()
	var valid_keys: Array[String] = []
	for k: String in keys:
		var parts: PackedStringArray = k.split(",")
		var m1: int = int(parts[0])
		var m2: int = int(parts[1])
		# Check if materials are available at current tier
		var max_mat: int = MAT_LEATHER
		if forge_tier >= 1: max_mat = MAT_BRONZE
		if forge_tier >= 2: max_mat = MAT_SILVER
		if forge_tier >= 3: max_mat = MAT_GOLD
		if m1 > max_mat or m2 > max_mat:
			continue
		valid_keys.append(k)
	if valid_keys.is_empty():
		return
	var key: String = valid_keys[randi() % valid_keys.size()]
	var recipe: Dictionary = recipes[key]
	var parts: PackedStringArray = key.split(",")
	var expire: float = maxf(ORDER_EXPIRE_BASE - difficulty * 1.5, 8.0)
	orders.append({
		"name": recipe["name"],
		"mat1": int(parts[0]),
		"mat2": int(parts[1]),
		"gold": int(recipe["gold"]),
		"timer": expire,
		"max_timer": expire,
		"color": recipe["color"],
	})

# ─────────────────────────── FORGING ───────────────────────────

func _try_forge() -> void:
	if anvil_slots.size() != 2:
		return
	var key: String = _rk(anvil_slots[0], anvil_slots[1])

	if not recipes.has(key):
		# Failed — materials lost, red flash, shake
		forge_flash = 0.4
		forge_result = "FAILED!"
		forge_result_timer = 1.0
		forge_result_gold = 0
		forge_success = false
		screen_shake = 0.2
		combo = 0
		# Red sparks
		_spawn_forge_sparks(Color(0.8, 0.2, 0.1))
		pops.append({"p": Vector2(anvil_rect.get_center().x, anvil_rect.position.y - u * 0.3), "text": "No recipe!", "timer": 1.0, "color": Color(0.8, 0.3, 0.2)})
		anvil_slots.clear()
		return

	var recipe: Dictionary = recipes[key]
	var item_name: String = recipe["name"]
	var item_gold: int = int(recipe["gold"])

	# Check orders
	var matched_order := -1
	for i in range(orders.size()):
		if orders[i]["name"] == item_name:
			matched_order = i
			break

	var earned: int = item_gold
	if matched_order >= 0:
		var time_frac: float = orders[matched_order]["timer"] / orders[matched_order]["max_timer"]
		var speed_bonus: int = int(item_gold * time_frac * 0.5)
		earned += speed_bonus
		combo += 1
		if combo > max_combo:
			max_combo = combo
		if combo >= 3:
			earned = int(earned * (1.0 + combo * 0.15))
		orders.remove_at(matched_order)
		orders_filled += 1
		_spawn_order()
	else:
		earned = int(earned * 0.3)
		combo = 0

	# Apply bonus gold
	if bonus_gold_pct > 0:
		earned = int(earned * (1.0 + bonus_gold_pct / 100.0))

	gold += earned
	if earned > forge_result_gold or best_item == "":
		best_item = item_name

	forge_flash = 0.6
	forge_result = item_name
	forge_result_timer = 1.5
	forge_result_gold = earned
	forge_success = true
	screen_shake = 0.15

	# Gold sparks
	var spark_col: Color = Color(1.0, 0.85, 0.3) if matched_order >= 0 else Color(0.5, 0.5, 0.4)
	_spawn_forge_sparks(spark_col)

	# Pop
	var pop_text: String = "+%d" % earned
	if combo >= 3:
		pop_text += " x%d!" % combo
	var pop_col: Color = Color(1.0, 0.85, 0.3) if matched_order >= 0 else Color(0.5, 0.5, 0.5)
	pops.append({"p": Vector2(anvil_rect.get_center().x, anvil_rect.position.y - u * 0.5), "text": pop_text, "timer": 1.5, "color": pop_col})

	anvil_slots.clear()
	_check_milestones()

func _spawn_forge_sparks(col: Color) -> void:
	var cx: float = anvil_rect.get_center().x
	var cy: float = anvil_rect.get_center().y
	for i in range(20):
		var angle: float = randf() * TAU
		var spd: float = randf_range(100, 300)
		sparks.append({
			"p": Vector2(cx + randf_range(-u * 0.3, u * 0.3), cy + randf_range(-u * 0.2, u * 0.2)),
			"v": Vector2(cos(angle), sin(angle)) * spd,
			"life": randf_range(0.3, 0.8),
			"max_life": 0.8,
			"color": Color(col.r + randf_range(-0.1, 0.1), col.g + randf_range(-0.1, 0.1), col.b + randf_range(-0.05, 0.05)),
			"size": randf_range(0.05, 0.12),
		})

func _spawn_ember() -> void:
	embers.append({
		"p": Vector2(randf_range(0, sw), randf_range(sh * 0.5, sh)),
		"v": Vector2(randf_range(-8, 8), randf_range(-20, -40)),
		"life": randf_range(2.0, 5.0),
		"max_life": 5.0,
		"size": randf_range(1.5, 3.0),
	})

# ─────────────────────────── PROCESS ───────────────────────────

func _process(delta: float) -> void:
	var s: Vector2 = _get_ss()
	sw = s.x
	sh = s.y
	u = min(sw, sh) / 10.0
	_update_layout()

	if game_state == 1:
		_process_playing(delta)

	# Sparks
	for i in range(sparks.size() - 1, -1, -1):
		sparks[i]["p"] += sparks[i]["v"] * delta
		sparks[i]["v"] *= 0.94
		sparks[i]["v"].y += 250 * delta
		sparks[i]["life"] -= delta
		if sparks[i]["life"] <= 0:
			sparks.remove_at(i)

	# Embers (background atmosphere)
	for i in range(embers.size() - 1, -1, -1):
		embers[i]["p"] += embers[i]["v"] * delta
		embers[i]["p"].x += sin(Time.get_ticks_msec() * 0.001 + float(i)) * 3.0 * delta
		embers[i]["life"] -= delta
		if embers[i]["life"] <= 0:
			embers.remove_at(i)
			_spawn_ember()

	# Pops
	for i in range(pops.size() - 1, -1, -1):
		pops[i]["p"].y -= 40 * delta
		pops[i]["timer"] -= delta
		if pops[i]["timer"] <= 0:
			pops.remove_at(i)

	if forge_flash > 0:
		forge_flash -= delta * 2.0
	if forge_result_timer > 0:
		forge_result_timer -= delta
	if screen_shake > 0:
		screen_shake -= delta

	# Difficulty ramps over time
	if game_state == 1:
		difficulty = int(orders_filled / 4)

	queue_redraw()

func _process_playing(delta: float) -> void:
	game_timer -= delta
	if game_timer <= 0:
		game_timer = 0
		_end_game()
		return

	# Order timers
	for i in range(orders.size() - 1, -1, -1):
		orders[i]["timer"] -= delta
		if orders[i]["timer"] <= 0:
			orders.remove_at(i)
			combo = 0
			_spawn_order()

	while orders.size() < MAX_ORDERS:
		_spawn_order()

	# Material cooldowns
	for i in range(materials.size()):
		if materials[i] == -1:
			mat_cooldown[i] += delta
			if mat_cooldown[i] >= 0.6:
				_refill_slot(i)

	# Milestone timer
	if milestone_timer > 0:
		milestone_timer -= delta

# ─────────────────────────── LAYOUT ───────────────────────────

func _update_layout() -> void:
	var mat_w: float = u * 1.4
	var mat_gap: float = u * 0.2
	var total_mat_w: float = MAT_SLOTS * mat_w + (MAT_SLOTS - 1) * mat_gap
	var mat_x0: float = (sw - total_mat_w) / 2.0
	var mat_y: float = sh - u * 2.2
	mat_rects.clear()
	for i in range(MAT_SLOTS):
		mat_rects.append(Rect2(mat_x0 + i * (mat_w + mat_gap), mat_y, mat_w, mat_w))

	var anvil_w: float = u * 4.5
	var anvil_h: float = u * 2.2
	anvil_rect = Rect2((sw - anvil_w) / 2.0, sh * 0.45, anvil_w, anvil_h)

	anvil_slot_rects.clear()
	var slot_size: float = u * 1.3
	var slot_y: float = anvil_rect.position.y + (anvil_rect.size.y - slot_size) / 2.0
	anvil_slot_rects.append(Rect2(anvil_rect.position.x + u * 0.5, slot_y, slot_size, slot_size))
	anvil_slot_rects.append(Rect2(anvil_rect.position.x + anvil_rect.size.x - u * 0.5 - slot_size, slot_y, slot_size, slot_size))

	# Reroll button — below materials, centered
	var reroll_w: float = u * 2.5
	var reroll_h: float = u * 0.7
	reroll_rect = Rect2((sw - reroll_w) / 2.0, sh - u * 0.7, reroll_w, reroll_h)


# ─────────────────────────── INPUT ───────────────────────────

func _input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var tapped := false
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			pos = touch.position
			tapped = true
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			pos = mb.position
			tapped = true

	if not tapped:
		return

	if game_state == 0 or game_state == 3:
		_start_game()
		return
	if game_state != 1:
		return

	# Tap reroll button
	if rerolls > 0 and reroll_rect.has_point(pos):
		_do_reroll()
		return

	# Tap material → add to anvil
	for i in range(mat_rects.size()):
		if mat_rects[i].has_point(pos) and i < materials.size() and materials[i] >= 0:
			if anvil_slots.size() < 2:
				anvil_slots.append(materials[i])
				materials[i] = -1
				mat_cooldown[i] = 0.0
				if anvil_slots.size() == 2:
					_try_forge()
			return

	# Tap anvil slot → remove back to grid
	for i in range(anvil_slots.size()):
		if i < anvil_slot_rects.size() and anvil_slot_rects[i].has_point(pos):
			var mat_type: int = anvil_slots[i]
			anvil_slots.remove_at(i)
			for j in range(materials.size()):
				if materials[j] == -1:
					materials[j] = mat_type
					mat_cooldown[j] = 0.0
					break
			return

# ─────────────────────────── DRAW ───────────────────────────

func _draw() -> void:
	var shake_off := Vector2.ZERO
	if screen_shake > 0:
		shake_off = Vector2(randf_range(-3, 3), randf_range(-3, 3)) * (screen_shake / 0.2)

	# Background
	draw_rect(Rect2(0, 0, sw, sh), Color(0.07, 0.05, 0.03))

	# Warm glow at bottom
	for i in range(8):
		var f: float = float(i) / 8.0
		var gy: float = sh * (0.6 + f * 0.4)
		draw_rect(Rect2(0, gy, sw, sh * 0.05), Color(0.2, 0.08, 0.02, 0.08 * f))

	# Embers (background)
	for e: Dictionary in embers:
		var alpha: float = clampf(e["life"] / e["max_life"], 0, 1) * 0.4
		var sz: float = e["size"]
		draw_rect(Rect2(e["p"] - Vector2(sz, sz), Vector2(sz * 2, sz * 2)), Color(1.0, 0.5, 0.15, alpha))

	match game_state:
		0: _draw_title()
		1: _draw_playing(shake_off)
		3: _draw_gameover()

	# Forge flash overlay
	if forge_flash > 0:
		var flash_col: Color = Color(1.0, 0.7, 0.2, forge_flash * 0.3) if forge_success else Color(1.0, 0.15, 0.05, forge_flash * 0.25)
		draw_rect(Rect2(0, 0, sw, sh), flash_col)

	# Sparks (on top)
	for sp: Dictionary in sparks:
		var alpha: float = clampf(sp["life"] / sp["max_life"], 0, 1)
		var sz: float = u * sp["size"] * alpha
		draw_rect(Rect2(sp["p"] + shake_off - Vector2(sz, sz), Vector2(sz * 2, sz * 2)), Color(sp["color"], alpha))

	# Pops (on top of everything)
	for pop: Dictionary in pops:
		var alpha: float = clampf(pop["timer"] / 1.0, 0, 1)
		var fs: float = u * 0.45 * (1.0 + (1.0 - alpha) * 0.3)
		draw_string(ThemeDB.fallback_font, pop["p"] + shake_off, pop["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, int(fs), Color(pop["color"], alpha))

func _draw_title() -> void:
	var cx: float = sw / 2.0
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 3, sh * 0.28), "FORGE QUEST", HORIZONTAL_ALIGNMENT_CENTER, int(u * 6), int(u * 0.75), Color(1.0, 0.8, 0.3))
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 3.5, sh * 0.28 + u * 1.0), "Tap materials to forge weapons", HORIZONTAL_ALIGNMENT_CENTER, int(u * 7), int(u * 0.3), Color(0.6, 0.5, 0.4))
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 3.5, sh * 0.28 + u * 1.4), "Fill orders to earn gold!", HORIZONTAL_ALIGNMENT_CENTER, int(u * 7), int(u * 0.3), Color(0.6, 0.5, 0.4))
	var blink: bool = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
	if blink:
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, sh * 0.65), "Tap to Start", HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.38), Color(0.8, 0.7, 0.5))
	if best_score > 0:
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, sh * 0.8), "Best: %d gold" % best_score, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.28), Color(0.5, 0.45, 0.35))

func _draw_playing(shake: Vector2) -> void:
	var bar_y: float = u * 0.2
	var bar_pad: float = u * 0.4
	var fs_sm: float = u * 0.28
	var fs_med: float = u * 0.38

	# Timer bar
	var bar_w: float = sw - bar_pad * 2
	draw_rect(Rect2(bar_pad + shake.x, bar_y + shake.y, bar_w, u * 0.12), Color(0.2, 0.15, 0.1))
	var frac: float = clampf(game_timer / GAME_DURATION, 0, 1)
	var tcol: Color = Color(1.0, 0.7, 0.2).lerp(Color(1.0, 0.2, 0.1), 1.0 - frac)
	if frac > 0:
		draw_rect(Rect2(bar_pad + shake.x, bar_y + shake.y, bar_w * frac, u * 0.12), tcol)

	# Timer + Gold
	draw_string(ThemeDB.fallback_font, Vector2(bar_pad, bar_y + u * 0.3) + shake, "%ds" % ceili(game_timer), HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs_sm), Color(0.7, 0.6, 0.5))
	draw_string(ThemeDB.fallback_font, Vector2(sw - bar_pad, bar_y + u * 0.3) + shake, "%d gold" % gold, HORIZONTAL_ALIGNMENT_RIGHT, -1, int(fs_med), Color(1.0, 0.85, 0.3))

	# Forge tier label
	var tier_names := ["Iron", "Bronze", "Silver", "Gold"]
	var tier_colors := [Color(0.5, 0.5, 0.55), Color(0.8, 0.55, 0.25), Color(0.78, 0.78, 0.85), Color(1.0, 0.85, 0.25)]
	draw_string(ThemeDB.fallback_font, Vector2(sw / 2.0 - u, bar_y + u * 0.3) + shake, tier_names[forge_tier] + " Forge", HORIZONTAL_ALIGNMENT_CENTER, int(u * 2), int(fs_sm), tier_colors[forge_tier])

	# Combo (prominent!)
	if combo >= 2:
		var cc: Color = Color(0.3, 1.0, 0.5) if combo < 5 else Color(1.0, 0.5, 1.0)
		var combo_fs: float = u * 0.35 + combo * u * 0.02
		draw_string(ThemeDB.fallback_font, Vector2(sw / 2.0 - u, bar_y + u * 0.3) + shake, "x%d CHAIN" % combo, HORIZONTAL_ALIGNMENT_CENTER, int(u * 2), int(combo_fs), cc)

	# Orders
	_draw_orders(shake)
	# Anvil
	_draw_anvil(shake)
	# Materials
	_draw_materials(shake)
	# Reroll button
	_draw_reroll(shake)

	# Forge result text
	if forge_result_timer > 0:
		var alpha: float = clampf(forge_result_timer / 1.0, 0, 1)
		var fs_res: float = u * 0.45
		var rc: Color = Color(1.0, 0.85, 0.3, alpha) if forge_success else Color(0.7, 0.25, 0.2, alpha)
		draw_string(ThemeDB.fallback_font, Vector2(sw / 2.0 - u * 2, anvil_rect.position.y - u * 0.4) + shake, forge_result, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(fs_res), rc)

	# Milestone banner
	if milestone_timer > 0:
		var alpha: float = clampf(milestone_timer / 1.0, 0, 1)
		var banner_y: float = sh * 0.18
		draw_rect(Rect2(0, banner_y - u * 0.3, sw, u * 0.7), Color(1.0, 0.7, 0.1, alpha * 0.15))
		draw_string(ThemeDB.fallback_font, Vector2(sw / 2.0 - u * 2, banner_y) + shake, milestone_msg, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.4), Color(1.0, 0.85, 0.3, alpha))


func _draw_orders(shake: Vector2) -> void:
	var order_y: float = u * 0.9
	var order_h: float = u * 1.6
	var order_gap: float = u * 0.15
	var order_w: float = (sw - u * 0.8 - order_gap * float(MAX_ORDERS - 1)) / float(MAX_ORDERS)
	var fs_name: float = u * 0.26
	var fs_sm: float = u * 0.2

	for i in range(orders.size()):
		var o: Dictionary = orders[i]
		var ox: float = u * 0.4 + i * (order_w + order_gap) + shake.x
		var oy: float = order_y + shake.y

		draw_rect(Rect2(ox, oy, order_w, order_h), Color(0.12, 0.1, 0.07))
		draw_rect(Rect2(ox, oy, order_w, order_h), Color(0.2, 0.17, 0.12), false, 1.0)

		# Timer bar at bottom
		var tfrac: float = clampf(o["timer"] / o["max_timer"], 0, 1)
		var tc: Color = Color(0.3, 0.8, 0.3).lerp(Color(0.9, 0.2, 0.1), 1.0 - tfrac)
		draw_rect(Rect2(ox, oy + order_h - u * 0.08, order_w * tfrac, u * 0.08), tc)

		# Item name
		draw_string(ThemeDB.fallback_font, Vector2(ox + u * 0.15, oy + u * 0.28), str(o["name"]), HORIZONTAL_ALIGNMENT_LEFT, int(order_w - u * 0.3), int(fs_name), Color(o["color"]))

		# Gold
		draw_string(ThemeDB.fallback_font, Vector2(ox + order_w - u * 0.15, oy + u * 0.28), "%dg" % o["gold"], HORIZONTAL_ALIGNMENT_RIGHT, -1, int(fs_sm), Color(1.0, 0.85, 0.3, 0.7))

		# Recipe materials (bigger, clearer)
		var icon_sz: float = u * 0.55
		var icon_y: float = oy + u * 0.7
		var icons_x: float = ox + (order_w - icon_sz * 2 - u * 0.4) / 2.0
		_draw_material_tile(Vector2(icons_x, icon_y), icon_sz, int(o["mat1"]), 0.9)
		draw_string(ThemeDB.fallback_font, Vector2(icons_x + icon_sz + u * 0.08, icon_y + icon_sz * 0.55), "+", HORIZONTAL_ALIGNMENT_CENTER, int(u * 0.3), int(u * 0.3), Color(0.5, 0.4, 0.3))
		_draw_material_tile(Vector2(icons_x + icon_sz + u * 0.4, icon_y), icon_sz, int(o["mat2"]), 0.9)

func _draw_anvil(shake: Vector2) -> void:
	var r: Rect2 = Rect2(anvil_rect.position + shake, anvil_rect.size)
	var glow: float = maxf(forge_flash, 0.0)
	var ac: Color = Color(0.15, 0.12, 0.08).lerp(Color(1.0, 0.5, 0.15), glow * 0.5)
	# Anvil shape (trapezoid-ish with draw_rect for simplicity + top highlight)
	draw_rect(r, ac)
	draw_rect(Rect2(r.position.x - u * 0.15, r.position.y, r.size.x + u * 0.3, u * 0.2), Color(ac.lightened(0.15)))
	draw_rect(r, Color(0.3, 0.25, 0.18), false, 2.0)

	# Label
	draw_string(ThemeDB.fallback_font, Vector2(r.get_center().x - u, r.position.y - u * 0.12) + shake, "ANVIL", HORIZONTAL_ALIGNMENT_CENTER, int(u * 2), int(u * 0.22), Color(0.45, 0.38, 0.28))

	# Slots
	for i in range(2):
		var sr: Rect2 = Rect2(anvil_slot_rects[i].position + shake, anvil_slot_rects[i].size)
		if i < anvil_slots.size():
			_draw_material_tile(sr.position, sr.size.x, anvil_slots[i], 1.0)
			# Tap hint
			draw_string(ThemeDB.fallback_font, Vector2(sr.position.x + sr.size.x * 0.5 - u * 0.3, sr.position.y - u * 0.08), "tap to remove", HORIZONTAL_ALIGNMENT_CENTER, int(u * 1.2), int(u * 0.13), Color(0.4, 0.35, 0.25))
		else:
			draw_rect(sr, Color(0.22, 0.18, 0.12))
			draw_rect(sr, Color(0.32, 0.27, 0.2), false, 1.5)
			draw_string(ThemeDB.fallback_font, sr.position + Vector2(sr.size.x * 0.5 - u * 0.3, sr.size.y * 0.6), "drop", HORIZONTAL_ALIGNMENT_CENTER, int(sr.size.x), int(u * 0.22), Color(0.35, 0.3, 0.22))

	# Plus between
	var mid: Vector2 = Vector2(
		(anvil_slot_rects[0].get_center().x + anvil_slot_rects[1].get_center().x) / 2.0,
		anvil_slot_rects[0].get_center().y
	) + shake
	draw_string(ThemeDB.fallback_font, mid + Vector2(-u * 0.15, u * 0.12), "+", HORIZONTAL_ALIGNMENT_CENTER, int(u * 0.5), int(u * 0.4), Color(0.5, 0.4, 0.3))

func _draw_materials(shake: Vector2) -> void:
	for i in range(mat_rects.size()):
		var r: Rect2 = Rect2(mat_rects[i].position + shake, mat_rects[i].size)
		if i < materials.size() and materials[i] >= 0:
			_draw_material_tile(r.position, r.size.x, materials[i], 1.0)
		elif i < mat_cooldown.size() and mat_cooldown[i] < 0.6:
			# Cooldown shimmer
			var pct: float = mat_cooldown[i] / 0.6
			draw_rect(r, Color(0.08, 0.06, 0.04))
			draw_rect(Rect2(r.position.x, r.position.y + r.size.y * (1.0 - pct), r.size.x, r.size.y * pct), Color(0.15, 0.1, 0.06))
		else:
			draw_rect(r, Color(0.08, 0.06, 0.04))

func _draw_reroll(shake: Vector2) -> void:
	if rerolls <= 0:
		return
	var r: Rect2 = Rect2(reroll_rect.position + shake, reroll_rect.size)
	draw_rect(r, Color(0.15, 0.25, 0.35))
	draw_rect(r, Color(0.3, 0.5, 0.7), false, 1.5)
	var fs: float = u * 0.24
	draw_string(ThemeDB.fallback_font, r.position + Vector2(r.size.x * 0.5 - u * 0.8, r.size.y * 0.6), "Reroll (%d)" % rerolls, HORIZONTAL_ALIGNMENT_CENTER, int(u * 2), int(fs), Color(0.5, 0.8, 1.0))

func _draw_material_tile(pos: Vector2, size: float, mat_type: int, alpha: float) -> void:
	var col: Color = MAT_COLORS[mat_type]
	draw_rect(Rect2(pos, Vector2(size, size)), Color(col, alpha * 0.85))
	draw_rect(Rect2(pos, Vector2(size, size)), Color(col.lightened(0.3), alpha), false, 2.0)
	var fs: float = size * 0.4
	draw_string(ThemeDB.fallback_font, pos + Vector2(size * 0.15, size * 0.55), MAT_SYMBOLS[mat_type], HORIZONTAL_ALIGNMENT_CENTER, int(size * 0.7), int(fs), Color(1, 1, 1, alpha))
	var fs2: float = size * 0.18
	draw_string(ThemeDB.fallback_font, pos + Vector2(size * 0.1, size * 0.85), MAT_NAMES[mat_type], HORIZONTAL_ALIGNMENT_CENTER, int(size * 0.8), int(fs2), Color(1, 1, 1, alpha * 0.5))

func _draw_gameover() -> void:
	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, 0.6))
	var cx: float = sw / 2.0
	var y: float = sh * 0.18

	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 3, y), "FORGE COMPLETE", HORIZONTAL_ALIGNMENT_CENTER, int(u * 6), int(u * 0.55), Color(1.0, 0.8, 0.3))
	y += u * 1.2
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y), "%d gold" % gold, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.65), Color(1.0, 0.85, 0.3))
	y += u * 1.0
	draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y), "%d orders filled" % orders_filled, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.32), Color(0.7, 0.65, 0.55))
	y += u * 0.6
	if best_item != "":
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y), "Best: %s" % best_item, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.28), Color(0.6, 0.5, 0.4))
	y += u * 0.6
	if max_combo >= 2:
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y), "Max chain: x%d" % max_combo, HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.28), Color(0.3, 0.8, 0.5))
	y += u * 1.2
	var blink: bool = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
	if blink:
		draw_string(ThemeDB.fallback_font, Vector2(cx - u * 2, y), "Tap to play again", HORIZONTAL_ALIGNMENT_CENTER, int(u * 4), int(u * 0.32), Color(0.6, 0.5, 0.4))
