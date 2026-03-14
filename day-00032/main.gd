extends Node2D

# ── Game States ──────────────────────────────────────────────────────────────
enum State { TITLE, PLAYING, PORTRAIT }

# ── Constants ────────────────────────────────────────────────────────────────
const MAX_SLOTS := 5
const WATER_MAX := 1.0
const WATER_DRAIN_BASE := 0.025
const GROWTH_RATE_TREE := 0.045
const GROWTH_RATE_FLOWER := 0.065
const FRUIT_RIPEN_TIME := 7.0
const FRUIT_RESPAWN_TIME := 10.0
const BLOOM_SCORE := 50
const FRUIT_SCORE := 30
const VISITOR_SCORE := 20
const PRUNE_BOOST_DURATION := 8.0  # seconds of boosted production after prune
const PRUNE_BOOST_MULT := 2.0     # fruit ripen / bloom 2x faster
const MAX_BRANCH_DEPTH_TREE := 4
const MAX_BRANCH_DEPTH_FLOWER := 2
const MAX_BRANCHES_PER_PLANT := 30
const TAP_RADIUS := 35.0
const PRUNE_RADIUS := 25.0
const SEASON_DURATION := 180.0

# Season boundaries (seconds)
const SPRING_END := 60.0
const SUMMER_END := 120.0

# ── Season Colors ────────────────────────────────────────────────────────────
# Background tints per season
const BG_SPRING := Color(0.90, 0.95, 0.88)
const BG_SUMMER := Color(0.95, 0.95, 0.85)
const BG_AUTUMN := Color(0.95, 0.90, 0.82)

# Leaf tint per season (blended onto leaf_color)
const LEAF_SPRING := Color(0.2, 0.6, 0.15)
const LEAF_SUMMER := Color(0.15, 0.5, 0.1)
const LEAF_AUTUMN := Color(0.8, 0.5, 0.15)

# Sky tint
const SKY_SPRING := Color(0.6, 0.8, 0.95)
const SKY_SUMMER := Color(0.55, 0.75, 0.95)
const SKY_AUTUMN := Color(0.85, 0.65, 0.5)

# ── Colors ───────────────────────────────────────────────────────────────────
const COL_FRAME := Color(0.35, 0.30, 0.25)
const COL_SOIL := Color(0.35, 0.22, 0.10)
const COL_SOIL_DRY := Color(0.50, 0.38, 0.25)
const COL_SOIL_WET := Color(0.25, 0.16, 0.08)
const COL_TRUNK := Color(0.45, 0.28, 0.12)
const COL_FRUIT_UNRIPE := Color(0.3, 0.55, 0.2)
const COL_FRUIT_RIPE := Color(0.9, 0.25, 0.15)
const COL_FLOWER_STEM := Color(0.25, 0.55, 0.18)
const COL_HUD_BG := Color(0.0, 0.0, 0.0, 0.45)
const COL_HUD_TEXT := Color(0.95, 0.95, 0.90)
const COL_WATER_BAR := Color(0.3, 0.6, 0.9)
const COL_WILT := Color(0.6, 0.5, 0.2, 0.7)

const PETAL_COLORS: Array = [
	Color(0.95, 0.3, 0.4),
	Color(0.95, 0.7, 0.2),
	Color(0.7, 0.3, 0.9),
	Color(0.95, 0.55, 0.7),
	Color(0.3, 0.6, 0.95),
	Color(0.95, 0.95, 0.9),
]

const BUTTERFLY_COLORS: Array = [
	Color(0.95, 0.6, 0.2),
	Color(0.3, 0.7, 0.95),
	Color(0.9, 0.3, 0.6),
	Color(0.95, 0.95, 0.4),
	Color(0.6, 0.3, 0.9),
]

# ── State ────────────────────────────────────────────────────────────────────
var game_state: int = State.TITLE
var points: int = 0
var sw: float = 800.0
var sh: float = 600.0
var game_time: float = 0.0
var title_timer: float = 0.0
var portrait_timer: float = 0.0

# Season: 0=spring, 1=summer, 2=autumn
var season: int = 0
var season_t: float = 0.0  # 0-1 blend within current season

# Plants
var plants: Array = []

# Water
var water_charges: int = 5
var water_max_charges: int = 5
var water_regen_timer: float = 0.0

# Layout
var ground_y: float = 0.0
var slot_width: float = 0.0
var slot_start_x: float = 0.0
var slots_per_row: int = MAX_SLOTS
var slot_rows: int = 1
var row_height: float = 0.0

# Plant chooser
var choosing_slot: int = -1  # which slot is showing tree/flower picker

# Bouquet — harvested flowers accumulate here
var bouquet: Array = []  # Array of Colors (petal colors)

# Visitors (butterflies & bees)
var visitors: Array = []
var visitor_spawn_timer: float = 0.0

# Particles
var water_drops: Array = []
var harvest_particles: Array = []
var pollen_particles: Array = []
var leaf_fall: Array = []  # autumn falling leaves

# Stats (for portrait)
var stat_fruits: int = 0
var stat_blooms: int = 0
var stat_visitors: int = 0
var stat_plants: int = 0
var stat_prunes: int = 0

# Audio
var plant_sfx: AudioStreamPlayer
var water_sfx: AudioStreamPlayer
var harvest_sfx: AudioStreamPlayer
var bloom_sfx: AudioStreamPlayer
var prune_sfx: AudioStreamPlayer
var ambient_player: AudioStreamPlayer

# API
var _score_submitted := false
var _best_score: int = 0


func _ready() -> void:
	_resize()
	_setup_audio()
	Api.load_state(func(ok: bool, data: Variant) -> void:
		if ok and data is Dictionary:
			_best_score = int(data.get("best", 0))
	)


func _resize() -> void:
	sw = float(get_viewport().get_visible_rect().size.x)
	sh = float(get_viewport().get_visible_rect().size.y)
	if sw < 1.0:
		sw = 800.0
	if sh < 1.0:
		sh = 600.0
	var is_portrait: bool = sh > sw * 0.9
	if is_portrait:
		ground_y = sh * 0.70
		slots_per_row = int(ceil(float(MAX_SLOTS) / 2.0))
		slot_rows = 2
		slot_width = sw / float(slots_per_row + 1)
		slot_start_x = slot_width * 0.5
		row_height = minf(60.0, sh * 0.10)
	else:
		ground_y = sh * 0.80
		slots_per_row = MAX_SLOTS
		slot_rows = 1
		slot_width = sw / float(MAX_SLOTS + 1)
		slot_start_x = slot_width * 0.5
		row_height = 0.0


# ── Input ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _is_press(event):
		return
	var pos: Vector2 = _event_pos(event)

	if game_state == State.TITLE:
		_start_game()
		return

	if game_state == State.PORTRAIT:
		if portrait_timer > 2.0:
			_go_title()
		return

	# PLAYING — check taps

	# If chooser is open, check if tapping tree/flower icon
	if choosing_slot >= 0:
		var croot: Vector2 = _slot_root(choosing_slot)
		var icon_y: float = croot.y - 40.0
		var icon_spacing: float = 30.0
		var tree_pos := Vector2(croot.x - icon_spacing, icon_y)
		var flower_pos := Vector2(croot.x + icon_spacing, icon_y)
		if pos.distance_to(tree_pos) < TAP_RADIUS:
			_plant_seed_type(choosing_slot, "tree")
			choosing_slot = -1
			return
		if pos.distance_to(flower_pos) < TAP_RADIUS:
			_plant_seed_type(choosing_slot, "flower")
			choosing_slot = -1
			return
		# Tapped elsewhere — dismiss chooser
		choosing_slot = -1

	# Ripe fruit
	var tapped := false
	for plant in plants:
		if bool(plant["dead"]) or plant["type"] != "tree":
			continue
		var root: Vector2 = _slot_root(int(plant["slot"]))
		for fruit in plant["fruits"]:
			if bool(fruit["harvested"]) or not bool(fruit["ripe"]):
				continue
			if pos.distance_to(root + Vector2(fruit["pos"])) < TAP_RADIUS:
				_harvest_fruit(plant, fruit)
				tapped = true
				break
		if tapped:
			break
	if tapped:
		return

	# Bloomed flowers
	for plant in plants:
		if bool(plant["dead"]) or plant["type"] != "flower":
			continue
		if int(plant["bloom_stage"]) < 4 or bool(plant["bloom_harvested"]):
			continue
		var root: Vector2 = _slot_root(int(plant["slot"]))
		var tip_y: float = -float(plant["height"]) * float(plant["growth"])
		if pos.distance_to(root + Vector2(0, tip_y)) < TAP_RADIUS:
			_harvest_bloom(plant)
			return

	# Pruning — tap on a leaf cluster to snip
	for plant in plants:
		if bool(plant["dead"]) or float(plant["growth"]) < 0.3:
			continue
		var root: Vector2 = _slot_root(int(plant["slot"]))
		var branches: Array = plant["branches"]
		for bi in range(branches.size()):
			var branch: Dictionary = branches[bi]
			if int(branch["depth"]) < 1 or not bool(branch["has_leaves"]):
				continue
			if float(branch["grow_t"]) < 0.8:
				continue
			if pos.distance_to(root + Vector2(branch["end"])) < PRUNE_RADIUS:
				_prune_branch(plant, bi)
				return

	# Soil slots
	for i in range(MAX_SLOTS):
		var rect: Rect2 = _slot_rect(i)
		if rect.has_point(pos):
			var existing: Dictionary = _plant_in_slot(i)
			if existing.is_empty():
				if water_charges > 0:
					choosing_slot = i  # open chooser
			elif not bool(existing["dead"]):
				if water_charges > 0 and float(existing["water"]) < 0.85:
					_water_plant(existing)
			else:
				if water_charges > 0:
					_remove_plant(i)
					choosing_slot = i  # open chooser for replant
			return


func _is_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventScreenTouch:
		return event.pressed
	return false


func _event_pos(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return event.position
	if event is InputEventScreenTouch:
		return event.position
	return Vector2.ZERO


# ── Game Loop ────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_resize()

	if game_state == State.TITLE:
		title_timer += delta
		queue_redraw()
		return

	if game_state == State.PORTRAIT:
		portrait_timer += delta
		_update_particles(delta)
		# Slow pollen drift in portrait
		if portrait_timer < 3.0 and randf() < delta * 3.0:
			var rx: float = randf_range(sw * 0.1, sw * 0.9)
			pollen_particles.append({
				"pos": Vector2(rx, ground_y - randf_range(30, 100)),
				"vel": Vector2(randf_range(-10, 10), randf_range(-15, -5)),
				"life": 2.0,
				"color": PETAL_COLORS[randi() % PETAL_COLORS.size()].lightened(0.3),
			})
		queue_redraw()
		return

	game_time += delta

	# Compute season
	if game_time < SPRING_END:
		season = 0
		season_t = game_time / SPRING_END
	elif game_time < SUMMER_END:
		season = 1
		season_t = (game_time - SPRING_END) / (SUMMER_END - SPRING_END)
	else:
		season = 2
		season_t = clampf((game_time - SUMMER_END) / (SEASON_DURATION - SUMMER_END), 0.0, 1.0)

	# Season ends naturally at 3 min
	if game_time >= SEASON_DURATION:
		_end_season()
		queue_redraw()
		return

	# Water regen — faster in spring, slower in autumn
	var regen_rate: float = 2.0 if season == 0 else (3.0 if season == 1 else 4.5)
	water_regen_timer += delta
	if water_regen_timer >= regen_rate and water_charges < water_max_charges:
		water_charges += 1
		water_regen_timer = 0.0

	# Water drain scales gently with season (not punishing)
	var drain_mult: float = 0.8 if season == 0 else (1.0 if season == 1 else 1.3)

	# Update plants
	var living_count: int = 0
	for plant in plants:
		if bool(plant["dead"]):
			continue
		_update_plant(plant, delta, drain_mult)
		if not bool(plant["dead"]):
			living_count += 1

	# Alive bonus (more in summer — thriving season)
	var alive_mult: float = 1.0 if season == 0 else (2.0 if season == 1 else 1.5)
	points += int(float(living_count) * alive_mult * delta)

	# Spawn visitors (more in summer)
	_update_visitors(delta)

	# Autumn: falling leaves
	if season == 2 and randf() < delta * 1.5:
		leaf_fall.append({
			"pos": Vector2(randf_range(0, sw), randf_range(ground_y * 0.15, ground_y * 0.5)),
			"vel": Vector2(randf_range(-15, 15), randf_range(15, 35)),
			"rot": randf() * TAU,
			"life": 3.0,
			"color": Color(
				randf_range(0.7, 0.95),
				randf_range(0.3, 0.6),
				randf_range(0.05, 0.2),
				0.5
			),
		})

	_update_particles(delta)
	queue_redraw()


func _update_plant(plant: Dictionary, delta: float, drain_mult: float) -> void:
	plant["age"] = float(plant["age"]) + delta

	var drain: float = WATER_DRAIN_BASE * drain_mult * delta
	plant["water"] = maxf(float(plant["water"]) - drain, 0.0)

	# Wilt — slower, more forgiving (12s to die)
	if float(plant["water"]) <= 0.0:
		plant["wilt_timer"] = float(plant["wilt_timer"]) + delta
		if float(plant["wilt_timer"]) > 12.0:
			plant["dead"] = true
			return
	else:
		plant["wilt_timer"] = maxf(float(plant["wilt_timer"]) - delta * 0.5, 0.0)

	# Growth — boosted in spring, normal summer, slow autumn
	if float(plant["water"]) > 0.1:
		var rate: float = GROWTH_RATE_TREE if plant["type"] == "tree" else GROWTH_RATE_FLOWER
		var season_mult: float = 1.3 if season == 0 else (1.0 if season == 1 else 0.6)
		var water_mult: float = clampf(float(plant["water"]) / 0.5, 0.2, 1.0)
		var prune_growth: float = PRUNE_BOOST_MULT if float(plant["prune_boost"]) > 0.0 else 1.0
		plant["growth"] = minf(float(plant["growth"]) + rate * season_mult * water_mult * prune_growth * delta, 1.0)

	# Decay prune boost
	if float(plant["prune_boost"]) > 0.0:
		plant["prune_boost"] = maxf(float(plant["prune_boost"]) - delta, 0.0)

	# Animate branches
	for branch in plant["branches"]:
		if float(branch["grow_t"]) < 1.0:
			branch["grow_t"] = minf(float(branch["grow_t"]) + delta * 1.5, 1.0)

	_try_grow_branches(plant)

	if plant["type"] == "flower":
		_update_flower(plant)
	if plant["type"] == "tree":
		_update_tree_fruit(plant, delta)


# ── Visitors ─────────────────────────────────────────────────────────────────

func _update_visitors(delta: float) -> void:
	# Spawn rate depends on season and bloomed plants
	var bloom_count: int = 0
	for plant in plants:
		if bool(plant["dead"]):
			continue
		if plant["type"] == "flower" and int(plant["bloom_stage"]) >= 4:
			bloom_count += 1
		if plant["type"] == "tree" and float(plant["growth"]) > 0.7:
			bloom_count += 1

	var spawn_rate: float = 0.0
	if season == 0:
		spawn_rate = 0.1 * float(bloom_count)
	elif season == 1:
		spawn_rate = 0.25 * float(bloom_count)  # summer = visitor paradise
	else:
		spawn_rate = 0.05 * float(bloom_count)

	visitor_spawn_timer += delta
	if visitor_spawn_timer > 1.0 and visitors.size() < 6 and bloom_count > 0:
		visitor_spawn_timer = 0.0
		if randf() < spawn_rate:
			_spawn_visitor()

	# Update each visitor
	var vi := 0
	while vi < visitors.size():
		var v: Dictionary = visitors[vi]
		v["wing_phase"] = float(v["wing_phase"]) + delta * 12.0
		v["life"] = float(v["life"]) - delta

		if float(v["life"]) <= 0.0:
			visitors.remove_at(vi)
			continue

		var target: Vector2 = Vector2(v["target"])
		var pos: Vector2 = Vector2(v["pos"])
		var dist: float = pos.distance_to(target)

		if dist < 5.0:
			# Lingering at flower
			v["linger"] = float(v["linger"]) - delta
			# Gentle bob
			v["pos"] = target + Vector2(sin(float(v["wing_phase"]) * 0.3) * 3, cos(float(v["wing_phase"]) * 0.2) * 2)
			if float(v["linger"]) <= 0.0:
				# Score and fly away
				points += VISITOR_SCORE
				stat_visitors += 1
				# Pollen burst
				for k in range(3):
					pollen_particles.append({
						"pos": pos,
						"vel": Vector2(randf_range(-20, 20), randf_range(-25, -5)),
						"life": 1.0,
						"color": Color(v["color"]).lightened(0.4),
					})
				visitors.remove_at(vi)
				continue
		else:
			# Fly toward target with gentle wave
			var dir: Vector2 = (target - pos).normalized()
			var wave: Vector2 = Vector2(-dir.y, dir.x) * sin(float(v["wing_phase"]) * 0.5) * 15.0
			v["pos"] = pos + (dir * 60.0 + wave) * delta

		vi += 1


func _spawn_visitor() -> void:
	# Pick a bloomed plant to visit
	var candidates: Array = []
	for plant in plants:
		if bool(plant["dead"]):
			continue
		if plant["type"] == "flower" and int(plant["bloom_stage"]) >= 4:
			candidates.append(plant)
		elif plant["type"] == "tree" and float(plant["growth"]) > 0.7:
			candidates.append(plant)
	if candidates.is_empty():
		return

	var target_plant: Dictionary = candidates[randi() % candidates.size()]
	var root: Vector2 = _slot_root(int(target_plant["slot"]))
	var target_pos: Vector2 = root + Vector2(0, -float(target_plant["height"]) * float(target_plant["growth"]) * 0.8)

	# Spawn from offscreen edge
	var side: float = -30.0 if randf() < 0.5 else sw + 30.0
	var start_y: float = randf_range(ground_y * 0.2, ground_y * 0.6)

	visitors.append({
		"pos": Vector2(side, start_y),
		"target": target_pos,
		"type": "butterfly" if randf() < 0.6 else "bee",
		"color": BUTTERFLY_COLORS[randi() % BUTTERFLY_COLORS.size()],
		"wing_phase": randf() * TAU,
		"linger": randf_range(1.5, 3.0),
		"plant_slot": int(target_plant["slot"]),
		"life": 12.0,
	})


# ── Plant Growth System ──────────────────────────────────────────────────────

func _plant_height(plant_type: String, rng: RandomNumberGenerator) -> float:
	var avail: float = ground_y - 60.0
	var max_h: float = avail * 0.65
	var min_h: float = avail * 0.3
	if plant_type == "tree":
		return rng.randf_range(minf(min_h, 80.0), minf(max_h, 180.0))
	else:
		return rng.randf_range(minf(min_h * 0.6, 50.0), minf(max_h * 0.6, 100.0))


func _plant_seed_type(slot: int, plant_type: String) -> void:
	water_charges -= 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var seed_val: int = rng.randi()

	var plant := {
		"type": plant_type,
		"slot": slot,
		"age": 0.0,
		"water": 0.8,
		"growth": 0.0,
		"branches": [] as Array,
		"fruits": [] as Array,
		"bloom_stage": 0,
		"bloom_scored": false,
		"bloom_harvested": false,
		"dead": false,
		"wilt_timer": 0.0,
		"rng_seed": seed_val,
		"height": _plant_height(plant_type, rng),
		"petal_color": PETAL_COLORS[rng.randi() % PETAL_COLORS.size()],
		"fruit_timer": 0.0,
		"max_fruits": rng.randi_range(3, 6) if plant_type == "tree" else 0,
		"prune_boost": 0.0,
	}

	var trunk_len: float = float(plant["height"]) * 0.4
	var trunk := {
		"start": Vector2.ZERO,
		"end": Vector2(0, -trunk_len),
		"thickness": 4.0 if plant_type == "tree" else 2.5,
		"depth": 0,
		"angle": -PI * 0.5,
		"length": trunk_len,
		"grow_t": 0.0,
		"has_leaves": false,
		"children": [] as Array,
		"leaf_color": Color(0.2 + randf() * 0.15, 0.5 + randf() * 0.2, 0.15 + randf() * 0.1),
		"branched": false,
	}
	plant["branches"].append(trunk)
	plants.append(plant)
	stat_plants += 1

	if plant_sfx:
		plant_sfx.play()

	var root: Vector2 = _slot_root(slot)
	for k in range(5):
		water_drops.append({
			"pos": root + Vector2(randf_range(-15, 15), -5),
			"vel": Vector2(randf_range(-20, 20), randf_range(-80, -40)),
			"life": 0.6,
		})


func _try_grow_branches(plant: Dictionary) -> void:
	var growth: float = float(plant["growth"])
	var branches: Array = plant["branches"]
	var max_depth: int = MAX_BRANCH_DEPTH_TREE if plant["type"] == "tree" else MAX_BRANCH_DEPTH_FLOWER
	var height: float = float(plant["height"])

	for bi in range(branches.size()):
		var branch: Dictionary = branches[bi]
		if float(branch["grow_t"]) < 0.95:
			continue
		if bool(branch["branched"]):
			continue
		if branches.size() >= MAX_BRANCHES_PER_PLANT:
			break

		var depth: int = int(branch["depth"])
		if depth >= max_depth:
			branch["has_leaves"] = true
			branch["branched"] = true
			continue

		var threshold: float = 0.15 + float(depth) * 0.2
		if growth < threshold:
			continue

		branch["branched"] = true

		var rng := RandomNumberGenerator.new()
		rng.seed = int(plant["rng_seed"]) + bi * 31 + depth * 97

		var count: int = rng.randi_range(2, 3) if depth < 2 else rng.randi_range(1, 2)
		if plant["type"] == "flower" and depth == 0:
			count = rng.randi_range(1, 2)

		var base_angle: float = float(branch["angle"])
		var spread: float = PI * 0.35
		var parent_end: Vector2 = Vector2(branch["end"])

		for ci in range(count):
			if branches.size() >= MAX_BRANCHES_PER_PLANT:
				break
			var angle_offset: float = (float(ci) - float(count - 1) * 0.5) * spread / maxf(float(count), 1.0)
			var child_angle: float = base_angle + angle_offset + rng.randf_range(-0.2, 0.2)
			var child_length: float = float(branch["length"]) * rng.randf_range(0.55, 0.75)
			child_length = minf(child_length, height * 0.3)
			var child_end: Vector2 = parent_end + Vector2(cos(child_angle), sin(child_angle)) * child_length

			var child := {
				"start": parent_end,
				"end": child_end,
				"thickness": float(branch["thickness"]) * 0.6,
				"depth": depth + 1,
				"angle": child_angle,
				"length": child_length,
				"grow_t": 0.0,
				"has_leaves": depth + 1 >= max_depth - 1,
				"children": [] as Array,
				"leaf_color": Color(
					rng.randf_range(0.15, 0.35),
					rng.randf_range(0.45, 0.7),
					rng.randf_range(0.08, 0.25)
				),
				"branched": false,
			}
			var new_idx: int = branches.size()
			branches.append(child)
			var ch: Array = branch["children"]
			ch.append(new_idx)


func _update_flower(plant: Dictionary) -> void:
	var growth: float = float(plant["growth"])

	if growth < 0.15:
		plant["bloom_stage"] = 0
	elif growth < 0.3:
		plant["bloom_stage"] = 1
	elif growth < 0.55:
		plant["bloom_stage"] = 2
	elif growth < 0.8:
		plant["bloom_stage"] = 3
	else:
		plant["bloom_stage"] = 4

	if int(plant["bloom_stage"]) == 4 and not bool(plant["bloom_scored"]):
		plant["bloom_scored"] = true
		points += BLOOM_SCORE
		stat_blooms += 1
		if bloom_sfx:
			bloom_sfx.play()
		var root: Vector2 = _slot_root(int(plant["slot"]))
		var tip_y: float = -float(plant["height"]) * growth
		for k in range(8):
			pollen_particles.append({
				"pos": root + Vector2(0, tip_y),
				"vel": Vector2(randf_range(-30, 30), randf_range(-40, -10)),
				"life": 1.5,
				"color": Color(plant["petal_color"]).lightened(0.3),
			})


func _update_tree_fruit(plant: Dictionary, delta: float) -> void:
	var growth: float = float(plant["growth"])
	if growth < 0.6:
		return

	var fruits: Array = plant["fruits"]
	var branches: Array = plant["branches"]

	for fruit in fruits:
		if bool(fruit["harvested"]):
			fruit["respawn_timer"] = float(fruit["respawn_timer"]) - delta
			if float(fruit["respawn_timer"]) <= 0.0:
				fruit["harvested"] = false
				fruit["ripe"] = false
				fruit["ripen_timer"] = FRUIT_RIPEN_TIME
				fruit["size"] = 0.0
			continue
		if not bool(fruit["ripe"]):
			# Bees speed up ripening
			var bee_bonus: float = 1.0
			for v in visitors:
				if v["type"] == "bee" and int(v["plant_slot"]) == int(plant["slot"]):
					bee_bonus = 1.5
					break
			var prune_mult: float = PRUNE_BOOST_MULT if float(plant["prune_boost"]) > 0.0 else 1.0
			fruit["ripen_timer"] = float(fruit["ripen_timer"]) - delta * bee_bonus * prune_mult
			fruit["size"] = minf(float(fruit["size"]) + delta * 1.2, 6.0)
			if float(fruit["ripen_timer"]) <= 0.0:
				fruit["ripe"] = true

	if fruits.size() < int(plant["max_fruits"]):
		plant["fruit_timer"] = float(plant["fruit_timer"]) + delta
		if float(plant["fruit_timer"]) > 4.0:
			plant["fruit_timer"] = 0.0
			for bi in range(branches.size()):
				var b: Dictionary = branches[bi]
				if not bool(b["has_leaves"]) or float(b["grow_t"]) < 0.8:
					continue
				var already := false
				for f in fruits:
					if int(f["branch_idx"]) == bi:
						already = true
						break
				if already:
					continue
				fruits.append({
					"branch_idx": bi,
					"pos": Vector2(b["end"]) + Vector2(0, 4),
					"ripe": false,
					"ripen_timer": FRUIT_RIPEN_TIME,
					"size": 1.0,
					"harvested": false,
					"respawn_timer": 0.0,
				})
				break


func _harvest_fruit(plant: Dictionary, fruit: Dictionary) -> void:
	fruit["harvested"] = true
	fruit["respawn_timer"] = FRUIT_RESPAWN_TIME
	points += FRUIT_SCORE
	stat_fruits += 1
	if harvest_sfx:
		harvest_sfx.play()
	var root: Vector2 = _slot_root(int(plant["slot"]))
	var fpos: Vector2 = root + Vector2(fruit["pos"])
	for k in range(6):
		harvest_particles.append({
			"pos": fpos,
			"vel": Vector2(randf_range(-40, 40), randf_range(-60, -20)),
			"life": 0.8,
			"color": COL_FRUIT_RIPE,
		})


func _harvest_bloom(plant: Dictionary) -> void:
	plant["bloom_harvested"] = true
	points += BLOOM_SCORE
	stat_blooms += 1
	# Add to bouquet
	bouquet.append(Color(plant["petal_color"]))
	if harvest_sfx:
		harvest_sfx.play()
	var root: Vector2 = _slot_root(int(plant["slot"]))
	var tip_y: float = -float(plant["height"]) * float(plant["growth"])
	for k in range(6):
		harvest_particles.append({
			"pos": root + Vector2(0, tip_y),
			"vel": Vector2(randf_range(-40, 40), randf_range(-60, -20)),
			"life": 0.8,
			"color": Color(plant["petal_color"]),
		})
	plant["bloom_stage"] = 2
	plant["bloom_scored"] = false
	plant["bloom_harvested"] = false
	plant["growth"] = 0.45


func _water_plant(plant: Dictionary) -> void:
	water_charges -= 1
	plant["water"] = minf(float(plant["water"]) + 0.4, WATER_MAX)
	if water_sfx:
		water_sfx.play()
	var root: Vector2 = _slot_root(int(plant["slot"]))
	for k in range(4):
		water_drops.append({
			"pos": root + Vector2(randf_range(-10, 10), randf_range(-30, -10)),
			"vel": Vector2(randf_range(-15, 15), randf_range(20, 50)),
			"life": 0.5,
		})


func _prune_branch(plant: Dictionary, branch_idx: int) -> void:
	var branches: Array = plant["branches"]
	var branch: Dictionary = branches[branch_idx]
	var root: Vector2 = _slot_root(int(plant["slot"]))
	var tip: Vector2 = root + Vector2(branch["end"])

	# Snip particles (green leaf bits)
	for k in range(5):
		harvest_particles.append({
			"pos": tip,
			"vel": Vector2(randf_range(-30, 30), randf_range(-40, 10)),
			"life": 0.6,
			"color": Color(branch["leaf_color"]).lightened(0.1),
		})

	# Remove any fruit on this branch
	if plant["type"] == "tree":
		var fruits: Array = plant["fruits"]
		var fi := 0
		while fi < fruits.size():
			if int(fruits[fi]["branch_idx"]) == branch_idx:
				fruits.remove_at(fi)
			else:
				fi += 1

	# Mark branch as pruned (hide it, remove leaves)
	branch["has_leaves"] = false
	branch["grow_t"] = 0.0
	branch["branched"] = true  # prevent regrowth

	# Also prune children recursively
	var children: Array = branch["children"]
	for child_idx in children:
		if child_idx < branches.size():
			var child: Dictionary = branches[child_idx]
			child["has_leaves"] = false
			child["grow_t"] = 0.0
			child["branched"] = true

	# Give plant a prune boost — redirected energy!
	plant["prune_boost"] = PRUNE_BOOST_DURATION

	stat_prunes += 1
	if prune_sfx:
		prune_sfx.play()


func _remove_plant(slot: int) -> void:
	for i in range(plants.size() - 1, -1, -1):
		if int(plants[i]["slot"]) == slot:
			plants.remove_at(i)
			break


func _plant_in_slot(slot: int) -> Dictionary:
	for plant in plants:
		if int(plant["slot"]) == slot:
			return plant
	return {}


# ── State Transitions ────────────────────────────────────────────────────────

func _start_game() -> void:
	game_state = State.PLAYING
	game_time = 0.0
	points = 0
	season = 0
	season_t = 0.0
	plants.clear()
	visitors.clear()
	bouquet.clear()
	choosing_slot = -1
	water_charges = water_max_charges
	water_regen_timer = 0.0
	visitor_spawn_timer = 0.0
	water_drops.clear()
	harvest_particles.clear()
	pollen_particles.clear()
	leaf_fall.clear()
	stat_fruits = 0
	stat_blooms = 0
	stat_visitors = 0
	stat_plants = 0
	stat_prunes = 0
	_score_submitted = false
	if ambient_player and not ambient_player.playing:
		ambient_player.play()


func _end_season() -> void:
	game_state = State.PORTRAIT
	portrait_timer = 0.0
	# Garden beauty bonus: living plants * 25
	var living: int = 0
	for plant in plants:
		if not bool(plant["dead"]):
			living += 1
	points += living * 25
	_submit_score()


func _go_title() -> void:
	game_state = State.TITLE
	title_timer = 0.0


func _submit_score() -> void:
	if _score_submitted:
		return
	_score_submitted = true
	if points > _best_score:
		_best_score = points
	Api.submit_score(points, func(_ok: bool, _result: Variant) -> void: pass)
	Api.save_state(1, {"best": _best_score}, func(_ok: bool, _result: Variant) -> void: pass)


# ── Particles ────────────────────────────────────────────────────────────────

func _update_particles(delta: float) -> void:
	var wi := 0
	while wi < water_drops.size():
		var d: Dictionary = water_drops[wi]
		d["pos"] = Vector2(d["pos"]) + Vector2(d["vel"]) * delta
		d["vel"] = Vector2(d["vel"]) + Vector2(0, 200) * delta
		d["life"] = float(d["life"]) - delta
		if float(d["life"]) <= 0.0:
			water_drops.remove_at(wi)
		else:
			wi += 1

	var hi := 0
	while hi < harvest_particles.size():
		var p: Dictionary = harvest_particles[hi]
		p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * delta
		p["vel"] = Vector2(p["vel"]) + Vector2(0, 100) * delta
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			harvest_particles.remove_at(hi)
		else:
			hi += 1

	var pi := 0
	while pi < pollen_particles.size():
		var p: Dictionary = pollen_particles[pi]
		p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * delta
		p["vel"] = Vector2(p["vel"]) * 0.97
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			pollen_particles.remove_at(pi)
		else:
			pi += 1

	var li := 0
	while li < leaf_fall.size():
		var lf: Dictionary = leaf_fall[li]
		lf["pos"] = Vector2(lf["pos"]) + Vector2(lf["vel"]) * delta
		lf["vel"] = Vector2(lf["vel"]) + Vector2(sin(game_time * 2.0 + float(li)) * 10.0, 5.0) * delta
		lf["rot"] = float(lf["rot"]) + delta * 1.5
		lf["life"] = float(lf["life"]) - delta
		if float(lf["life"]) <= 0.0 or Vector2(lf["pos"]).y > ground_y + 10:
			leaf_fall.remove_at(li)
		else:
			li += 1


# ── Drawing ──────────────────────────────────────────────────────────────────

func _season_bg_color() -> Color:
	if season == 0:
		return BG_SPRING.lerp(BG_SUMMER, season_t)
	elif season == 1:
		return BG_SUMMER.lerp(BG_AUTUMN, season_t)
	else:
		return BG_AUTUMN

func _season_sky_color() -> Color:
	if season == 0:
		return SKY_SPRING.lerp(SKY_SUMMER, season_t)
	elif season == 1:
		return SKY_SUMMER.lerp(SKY_AUTUMN, season_t)
	else:
		return SKY_AUTUMN

func _season_leaf_tint() -> Color:
	if season == 0:
		return LEAF_SPRING.lerp(LEAF_SUMMER, season_t)
	elif season == 1:
		return LEAF_SUMMER.lerp(LEAF_AUTUMN, season_t)
	else:
		return LEAF_AUTUMN

func _season_name() -> String:
	if season == 0:
		return "Spring"
	elif season == 1:
		return "Summer"
	else:
		return "Autumn"


func _draw() -> void:
	if game_state == State.TITLE:
		_draw_title()
		return

	_draw_greenhouse_bg()
	_draw_soil_slots()
	_draw_chooser()
	for plant in plants:
		_draw_plant(plant)
	_draw_visitors()
	_draw_particles()
	_draw_bouquet()
	_draw_hud()

	if game_state == State.PORTRAIT:
		_draw_portrait()


func _draw_greenhouse_bg() -> void:
	var bg_col: Color = _season_bg_color()
	draw_rect(Rect2(0, 0, sw, sh), bg_col)

	# Sky gradient
	var sky_col: Color = _season_sky_color()
	for i in range(8):
		var frac: float = float(i) / 8.0
		var sc := sky_col
		sc.a = 0.1 * (1.0 - frac)
		draw_rect(Rect2(0, frac * ground_y * 0.3, sw, ground_y * 0.3 / 8.0), sc)

	# Glass
	draw_rect(Rect2(0, 0, sw, ground_y), Color(0.7, 0.85, 0.95, 0.08))

	# Greenhouse frame
	var peak := Vector2(sw * 0.5, sh * 0.02)
	draw_line(Vector2(0, sh * 0.08), peak, COL_FRAME, 3.0)
	draw_line(peak, Vector2(sw, sh * 0.08), COL_FRAME, 3.0)
	draw_line(Vector2(0, sh * 0.08), Vector2(sw, sh * 0.08), COL_FRAME, 2.0)

	var strut_count: int = MAX_SLOTS + 2
	for i in range(strut_count):
		var x: float = float(i) * sw / float(strut_count - 1)
		draw_line(Vector2(x, sh * 0.08), Vector2(x, ground_y), COL_FRAME, 1.5)

	for i in range(strut_count - 1):
		var x1: float = float(i) * sw / float(strut_count - 1)
		var x2: float = float(i + 1) * sw / float(strut_count - 1)
		var mid_y: float = (sh * 0.08 + ground_y) * 0.5
		draw_line(Vector2(x1, sh * 0.08), Vector2(x2, mid_y), Color(COL_FRAME.r, COL_FRAME.g, COL_FRAME.b, 0.3), 1.0)
		draw_line(Vector2(x2, sh * 0.08), Vector2(x1, mid_y), Color(COL_FRAME.r, COL_FRAME.g, COL_FRAME.b, 0.3), 1.0)

	# Sunlight shaft in summer (warm diagonal glow)
	if season >= 1:
		var sun_a: float = 0.04 * (season_t if season == 1 else 1.0 - season_t * 0.5)
		var sun_points := PackedVector2Array([
			Vector2(sw * 0.6, 0),
			Vector2(sw * 0.9, 0),
			Vector2(sw * 0.5, ground_y),
			Vector2(sw * 0.3, ground_y),
		])
		draw_colored_polygon(sun_points, Color(1.0, 0.95, 0.7, sun_a))

	var shelf_bottom: float = ground_y + float(slot_rows - 1) * row_height + 55.0
	shelf_bottom = maxf(shelf_bottom, sh)
	draw_rect(Rect2(0, ground_y, sw, shelf_bottom - ground_y), COL_SOIL)
	draw_line(Vector2(0, ground_y), Vector2(sw, ground_y), Color(0.5, 0.35, 0.18), 3.0)


func _draw_soil_slots() -> void:
	for i in range(MAX_SLOTS):
		var rect: Rect2 = _slot_rect(i)
		var plant: Dictionary = _plant_in_slot(i)

		var soil_col := COL_SOIL_DRY
		if not plant.is_empty() and not bool(plant["dead"]):
			soil_col = COL_SOIL_DRY.lerp(COL_SOIL_WET, float(plant["water"]))

		var pot_top := rect.position.y
		var pot_bottom := rect.end.y
		var pot_cx: float = rect.position.x + rect.size.x * 0.5
		var pot_half_top: float = rect.size.x * 0.5
		var pot_half_bottom: float = rect.size.x * 0.35
		draw_colored_polygon(PackedVector2Array([
			Vector2(pot_cx - pot_half_top, pot_top),
			Vector2(pot_cx + pot_half_top, pot_top),
			Vector2(pot_cx + pot_half_bottom, pot_bottom),
			Vector2(pot_cx - pot_half_bottom, pot_bottom),
		]), Color(0.55, 0.32, 0.18))
		draw_colored_polygon(PackedVector2Array([
			Vector2(pot_cx - pot_half_top + 3, pot_top + 4),
			Vector2(pot_cx + pot_half_top - 3, pot_top + 4),
			Vector2(pot_cx + pot_half_bottom + 1, pot_bottom - 2),
			Vector2(pot_cx - pot_half_bottom - 1, pot_bottom - 2),
		]), soil_col)

		if not plant.is_empty() and not bool(plant["dead"]):
			var bar_w: float = rect.size.x * 0.8
			var bar_x: float = pot_cx - bar_w * 0.5
			var bar_y: float = pot_bottom + 4
			draw_rect(Rect2(bar_x, bar_y, bar_w, 4.0), Color(0.2, 0.2, 0.2, 0.4))
			var w: float = clampf(float(plant["water"]), 0.0, 1.0)
			var bar_col := COL_WATER_BAR
			if w < 0.25:
				bar_col = Color(0.9, 0.3, 0.1)
			elif w < 0.5:
				bar_col = Color(0.9, 0.7, 0.2)
			draw_rect(Rect2(bar_x, bar_y, bar_w * w, 4.0), bar_col)

		if plant.is_empty():
			var plus_col := Color(0.5, 0.4, 0.3, 0.3 + 0.1 * sin(game_time * 2.0 + float(i)))
			draw_line(Vector2(pot_cx - 8, pot_top - 15), Vector2(pot_cx + 8, pot_top - 15), plus_col, 2.0)
			draw_line(Vector2(pot_cx, pot_top - 23), Vector2(pot_cx, pot_top - 7), plus_col, 2.0)

		if not plant.is_empty() and bool(plant["dead"]):
			var x_col := Color(0.7, 0.3, 0.2, 0.6)
			draw_line(Vector2(pot_cx - 8, pot_top - 28), Vector2(pot_cx + 8, pot_top - 12), x_col, 2.5)
			draw_line(Vector2(pot_cx + 8, pot_top - 28), Vector2(pot_cx - 8, pot_top - 12), x_col, 2.5)


func _draw_plant(plant: Dictionary) -> void:
	if bool(plant["dead"]):
		_draw_dead_plant(plant)
		return
	var root: Vector2 = _slot_root(int(plant["slot"]))
	if plant["type"] == "tree":
		_draw_tree(plant, root)
	else:
		_draw_flower(plant, root)


func _draw_dead_plant(plant: Dictionary) -> void:
	var root: Vector2 = _slot_root(int(plant["slot"]))
	for branch in plant["branches"]:
		var gt: float = float(branch["grow_t"])
		if gt < 0.01:
			continue
		var start: Vector2 = root + Vector2(branch["start"])
		var end_pos: Vector2 = root + Vector2(branch["start"]).lerp(Vector2(branch["end"]), gt)
		end_pos.y += 5.0
		draw_line(start, end_pos, COL_WILT, maxf(float(branch["thickness"]) * gt, 0.5))


func _draw_tree(plant: Dictionary, root: Vector2) -> void:
	var branches: Array = plant["branches"]
	var wilt_amt: float = clampf(float(plant["wilt_timer"]) / 5.0, 0.0, 1.0)
	var leaf_tint: Color = _season_leaf_tint()
	var boosted: bool = float(plant["prune_boost"]) > 0.0

	# Prune boost glow at base
	if boosted:
		var glow_a: float = 0.12 + 0.06 * sin(game_time * 5.0)
		draw_circle(root, 12.0, Color(0.4, 0.9, 0.3, glow_a))

	for bi in range(branches.size()):
		var branch: Dictionary = branches[bi]
		var gt: float = float(branch["grow_t"])
		if gt < 0.01:
			continue
		var start: Vector2 = root + Vector2(branch["start"])
		var animated_end: Vector2 = root + Vector2(branch["start"]).lerp(Vector2(branch["end"]), gt)
		var thickness: float = maxf(float(branch["thickness"]) * gt, 0.8)
		var depth: int = int(branch["depth"])
		var trunk_col := Color(COL_TRUNK.r - float(depth) * 0.04, COL_TRUNK.g - float(depth) * 0.02, COL_TRUNK.b)
		trunk_col = trunk_col.lerp(COL_WILT, wilt_amt * 0.5)
		draw_line(start, animated_end, trunk_col, thickness)

		if bool(branch["has_leaves"]) and gt > 0.4:
			var leaf_a: float = (gt - 0.4) * 1.67
			var leaf_col: Color = Color(branch["leaf_color"]).lerp(leaf_tint, 0.4)
			leaf_col = leaf_col.lerp(Color(0.6, 0.5, 0.2), wilt_amt)
			leaf_col.a = leaf_a * 0.85
			var leaf_size: float = 5.0 + float(branch["length"]) * 0.06
			draw_circle(animated_end, leaf_size, leaf_col)
			draw_circle(animated_end + Vector2(-3, -2), leaf_size * 0.7, leaf_col)
			draw_circle(animated_end + Vector2(3, -1), leaf_size * 0.7, leaf_col)
			# Prunable hint — subtle pulsing outline on deep branches
			if int(branch["depth"]) >= 1 and gt > 0.8 and not boosted:
				var hint_a: float = 0.15 + 0.1 * sin(game_time * 3.0 + float(bi) * 0.7)
				draw_arc(animated_end, leaf_size + 2.0, 0, TAU, 12, Color(0.9, 0.95, 0.8, hint_a), 1.0)

	for fruit in plant["fruits"]:
		if bool(fruit["harvested"]):
			continue
		var fpos: Vector2 = root + Vector2(fruit["pos"])
		var size: float = float(fruit["size"])
		var ripen_progress: float = 1.0 - clampf(float(fruit["ripen_timer"]) / FRUIT_RIPEN_TIME, 0.0, 1.0)
		draw_circle(fpos, size, COL_FRUIT_UNRIPE.lerp(COL_FRUIT_RIPE, ripen_progress))
		var bi: int = int(fruit["branch_idx"])
		if bi < branches.size():
			draw_line(root + Vector2(branches[bi]["end"]), fpos, Color(0.3, 0.2, 0.05), 1.0)
		if bool(fruit["ripe"]):
			draw_circle(fpos, size + 4.0, Color(1.0, 0.9, 0.3, 0.15 + 0.1 * sin(game_time * 4.0)))


func _draw_flower(plant: Dictionary, root: Vector2) -> void:
	var growth: float = float(plant["growth"])
	var stage: int = int(plant["bloom_stage"])
	var height: float = float(plant["height"])
	var wilt_amt: float = clampf(float(plant["wilt_timer"]) / 5.0, 0.0, 1.0)

	if stage == 0:
		draw_circle(root + Vector2(0, -3), 3.0, Color(0.45, 0.3, 0.15))
		return

	var stem_h: float = height * minf(growth * 1.2, 1.0)
	var stem_top := root + Vector2(0, -stem_h)
	var stem_col: Color = COL_FLOWER_STEM.lerp(Color(0.5, 0.45, 0.2), wilt_amt)
	draw_line(root, stem_top, stem_col, 2.0 + growth)

	# Branches
	for branch in plant["branches"]:
		var gt: float = float(branch["grow_t"])
		if gt < 0.01 or int(branch["depth"]) == 0:
			continue
		var start: Vector2 = root + Vector2(branch["start"])
		var animated_end: Vector2 = root + Vector2(branch["start"]).lerp(Vector2(branch["end"]), gt)
		draw_line(start, animated_end, stem_col, maxf(float(branch["thickness"]) * gt, 0.5))
		if bool(branch["has_leaves"]) and gt > 0.5:
			var leaf_col := Color(branch["leaf_color"]).lerp(_season_leaf_tint(), 0.3)
			leaf_col.a = (gt - 0.5) * 2.0 * 0.7
			draw_circle(animated_end, 3.5, leaf_col)

	# Stem leaves
	if stage >= 2:
		var leaf_col := Color(0.2, 0.55, 0.15, 0.75).lerp(Color(0.5, 0.45, 0.2), wilt_amt)
		for li in range(2 + int(growth * 3.0)):
			var t: float = 0.3 + float(li) * 0.15
			if t > 0.9:
				break
			var side: float = -1.0 if li % 2 == 0 else 1.0
			var lpos := root + Vector2(side * (6.0 + growth * 4.0), -stem_h * t)
			draw_circle(lpos, 3.5 + growth * 1.5, leaf_col)
			draw_circle(lpos + Vector2(side * 2, -1), 2.5 + growth, leaf_col)

	if stage == 3:
		var bud_col := Color(plant["petal_color"]).darkened(0.3).lerp(Color(0.5, 0.45, 0.2), wilt_amt)
		draw_circle(stem_top, 5.0 + growth * 2.0, bud_col)

	if stage >= 4:
		var petal_col: Color = Color(plant["petal_color"]).lerp(Color(0.5, 0.45, 0.2), wilt_amt)
		var petal_r: float = 6.0 + growth * 5.0
		for petal_i in range(6):
			var angle: float = float(petal_i) * TAU / 6.0 + game_time * 0.1
			var ppos: Vector2 = stem_top + Vector2(cos(angle), sin(angle)) * petal_r * 0.6
			var col := petal_col
			col.a = 0.8
			draw_circle(ppos, petal_r * 0.55, col)
		for petal_i in range(6):
			var angle: float = float(petal_i) * TAU / 6.0 + PI / 6.0 + game_time * 0.1
			var ppos: Vector2 = stem_top + Vector2(cos(angle), sin(angle)) * petal_r * 0.3
			var col: Color = petal_col.lightened(0.3)
			col.a = 0.7
			draw_circle(ppos, petal_r * 0.4, col)
		draw_circle(stem_top, petal_r * 0.25, Color(0.95, 0.85, 0.2))
		if not bool(plant["bloom_harvested"]):
			draw_circle(stem_top, petal_r + 4.0, Color(1.0, 0.95, 0.6, 0.1 + 0.08 * sin(game_time * 3.0)))


func _draw_visitors() -> void:
	for v in visitors:
		var pos: Vector2 = Vector2(v["pos"])
		var col: Color = Color(v["color"])
		var wing: float = sin(float(v["wing_phase"])) * 0.5 + 0.5  # 0-1

		if v["type"] == "butterfly":
			# Body
			draw_circle(pos, 2.0, col.darkened(0.3))
			# Wings (two pairs, flapping)
			var wing_size: float = 5.0 + wing * 3.0
			var wcol := col
			wcol.a = 0.7
			draw_circle(pos + Vector2(-wing_size * 0.7, -wing * 2), wing_size, wcol)
			draw_circle(pos + Vector2(wing_size * 0.7, -wing * 2), wing_size, wcol)
			# Lower wings (smaller)
			var wcol2 := col.darkened(0.15)
			wcol2.a = 0.6
			draw_circle(pos + Vector2(-wing_size * 0.4, wing * 1.5), wing_size * 0.6, wcol2)
			draw_circle(pos + Vector2(wing_size * 0.4, wing * 1.5), wing_size * 0.6, wcol2)
		else:
			# Bee
			draw_circle(pos, 3.0, Color(0.95, 0.8, 0.1))
			draw_line(pos + Vector2(-2, -1), pos + Vector2(2, -1), Color(0.15, 0.1, 0.0), 1.5)
			draw_line(pos + Vector2(-2, 1), pos + Vector2(2, 1), Color(0.15, 0.1, 0.0), 1.5)
			# Wings
			var bw: float = 2.0 + wing * 2.0
			draw_circle(pos + Vector2(-2, -bw), 2.5, Color(0.9, 0.9, 1.0, 0.4))
			draw_circle(pos + Vector2(2, -bw), 2.5, Color(0.9, 0.9, 1.0, 0.4))


func _draw_particles() -> void:
	for d in water_drops:
		draw_circle(Vector2(d["pos"]), 2.5, Color(0.4, 0.65, 0.95, clampf(float(d["life"]) * 2.0, 0.0, 0.8)))
	for p in harvest_particles:
		var col: Color = Color(p["color"])
		col.a = clampf(float(p["life"]) * 1.5, 0.0, 1.0)
		draw_circle(Vector2(p["pos"]), 3.0, col)
	for p in pollen_particles:
		var col: Color = Color(p["color"])
		col.a = clampf(float(p["life"]) / 1.5, 0.0, 0.6)
		draw_circle(Vector2(p["pos"]), 2.0, col)
	for lf in leaf_fall:
		var col: Color = Color(lf["color"])
		col.a *= clampf(float(lf["life"]), 0.0, 1.0)
		var lpos: Vector2 = Vector2(lf["pos"])
		var r: float = float(lf["rot"])
		# Leaf shape: small diamond rotated
		var s := 4.0
		var pts := PackedVector2Array([
			lpos + Vector2(cos(r), sin(r)) * s,
			lpos + Vector2(cos(r + PI * 0.5), sin(r + PI * 0.5)) * s * 0.5,
			lpos + Vector2(cos(r + PI), sin(r + PI)) * s,
			lpos + Vector2(cos(r + PI * 1.5), sin(r + PI * 1.5)) * s * 0.5,
		])
		draw_colored_polygon(pts, col)


func _draw_chooser() -> void:
	if choosing_slot < 0 or game_state != State.PLAYING:
		return
	var root: Vector2 = _slot_root(choosing_slot)
	var icon_y: float = root.y - 40.0
	var spacing: float = 30.0
	var tree_pos := Vector2(root.x - spacing, icon_y)
	var flower_pos := Vector2(root.x + spacing, icon_y)

	# Background pill
	draw_rect(Rect2(root.x - spacing - 22, icon_y - 22, spacing * 2 + 44, 44), Color(0.0, 0.0, 0.0, 0.5), false, 0.0)
	draw_rect(Rect2(root.x - spacing - 20, icon_y - 20, spacing * 2 + 40, 40), Color(0.15, 0.12, 0.08, 0.85))

	# Tree icon — brown trunk + green canopy
	draw_line(tree_pos + Vector2(0, 8), tree_pos + Vector2(0, -4), Color(0.45, 0.28, 0.12), 3.0)
	draw_circle(tree_pos + Vector2(0, -8), 8.0, Color(0.2, 0.55, 0.15, 0.9))
	# Highlight ring
	draw_arc(tree_pos, 14.0, 0, TAU, 16, Color(0.9, 0.9, 0.8, 0.3 + 0.2 * sin(game_time * 4.0)), 1.5)

	# Flower icon — stem + colored petals
	draw_line(flower_pos + Vector2(0, 8), flower_pos + Vector2(0, -2), Color(0.25, 0.5, 0.15), 2.0)
	var fcol := Color(PETAL_COLORS[int(game_time * 0.5) % PETAL_COLORS.size()])
	for pi in range(5):
		var angle: float = float(pi) * TAU / 5.0 + game_time * 0.3
		draw_circle(flower_pos + Vector2(0, -6) + Vector2(cos(angle), sin(angle)) * 5, 3.5, fcol)
	draw_circle(flower_pos + Vector2(0, -6), 2.5, Color(0.95, 0.85, 0.2))
	draw_arc(flower_pos, 14.0, 0, TAU, 16, Color(0.9, 0.9, 0.8, 0.3 + 0.2 * sin(game_time * 4.0 + 1.0)), 1.5)

	# Arrow pointing down to pot
	draw_line(root + Vector2(0, -18), root + Vector2(0, -8), Color(0.9, 0.9, 0.8, 0.4), 1.5)


func _draw_bouquet() -> void:
	if bouquet.is_empty():
		return

	# Draw bouquet in bottom-right corner as a small vase with flowers
	var vase_x: float = sw - 50.0
	var vase_y: float = ground_y - 10.0
	var fs_tiny: int = _font_size(0.02)

	# Vase
	var vase_w := 20.0
	var vase_h := 25.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(vase_x - vase_w * 0.4, vase_y - vase_h),
		Vector2(vase_x + vase_w * 0.4, vase_y - vase_h),
		Vector2(vase_x + vase_w * 0.5, vase_y),
		Vector2(vase_x - vase_w * 0.5, vase_y),
	]), Color(0.5, 0.6, 0.7, 0.7))

	# Flowers in vase — arranged in a fan
	var count: int = bouquet.size()
	var max_show: int = mini(count, 12)
	for i in range(max_show):
		var frac: float = float(i) / maxf(float(max_show - 1), 1.0)
		var angle: float = lerpf(-0.6, 0.6, frac)
		var stem_len: float = 18.0 + float(i % 3) * 5.0
		var stem_base := Vector2(vase_x, vase_y - vase_h + 2)
		var stem_tip := stem_base + Vector2(sin(angle) * stem_len, -cos(angle) * stem_len)

		# Stem
		draw_line(stem_base, stem_tip, Color(0.25, 0.5, 0.15, 0.7), 1.5)

		# Flower head
		var col: Color = bouquet[count - max_show + i]
		for pi in range(5):
			var pa: float = float(pi) * TAU / 5.0
			draw_circle(stem_tip + Vector2(cos(pa), sin(pa)) * 2.5, 2.0, Color(col.r, col.g, col.b, 0.8))
		draw_circle(stem_tip, 1.5, Color(0.95, 0.85, 0.2, 0.8))

	# Count
	if count > 0:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(vase_x - 8, vase_y + 14), "%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_tiny, Color(0.7, 0.6, 0.5, 0.6))


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var fs: int = _font_size(0.035)
	var hud_h: float = float(fs) + 28.0
	draw_rect(Rect2(0, 0, sw, hud_h), COL_HUD_BG)
	var text_y: float = hud_h - 10.0

	# Season name + score
	var season_col := Color(0.6, 0.9, 0.5) if season == 0 else (Color(1.0, 0.9, 0.4) if season == 1 else Color(0.95, 0.65, 0.3))
	draw_string(font, Vector2(10, text_y), _season_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, season_col)
	draw_string(font, Vector2(10 + float(fs) * 4.5, text_y), "%d" % points, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_HUD_TEXT)

	# Timer
	var time_left: float = maxf(SEASON_DURATION - game_time, 0.0)
	var time_str: String = "%d:%02d" % [int(time_left) / 60, int(time_left) % 60]
	draw_string(font, Vector2(sw * 0.5 - float(fs) * 1.2, text_y), time_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_HUD_TEXT)

	# Water
	draw_string(font, Vector2(sw - float(fs) * 7.5, text_y), "Water: %d/%d" % [water_charges, water_max_charges], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_WATER_BAR)

	# Season progress bar
	var bar_y: float = hud_h - 2.0
	var bar_w: float = sw - 24.0
	draw_rect(Rect2(12, bar_y, bar_w, 2), Color(0.3, 0.3, 0.3, 0.3))
	var progress: float = clampf(game_time / SEASON_DURATION, 0.0, 1.0)
	# Three-color bar: green → gold → amber
	var bar_col := Color(0.4, 0.8, 0.3) if progress < 0.33 else (Color(0.9, 0.8, 0.2) if progress < 0.66 else Color(0.9, 0.5, 0.15))
	bar_col.a = 0.6
	draw_rect(Rect2(12, bar_y, bar_w * progress, 2), bar_col)

	if _best_score > 0:
		draw_string(font, Vector2(14, sh - 8), "Best: %d" % _best_score, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size(0.025), Color(0.6, 0.6, 0.5, 0.4))


func _draw_portrait() -> void:
	# Gentle fade — semi-transparent so garden shows through
	var a: float = clampf(portrait_timer * 0.5, 0.0, 0.55)
	draw_rect(Rect2(0, 0, sw, sh), Color(0.95, 0.92, 0.85, a))

	if portrait_timer < 0.8:
		return

	var font := ThemeDB.fallback_font
	var text_a: float = clampf((portrait_timer - 0.8) * 1.5, 0.0, 1.0)
	var fs_big: int = _font_size(0.06)
	var fs_med: int = _font_size(0.04)
	var fs_sm: int = _font_size(0.03)
	var cx: float = sw * 0.5

	var y: float = sh * 0.15
	# Title — warm, celebratory
	var title_str := "Your Garden"
	draw_string(font, Vector2(cx - float(fs_big) * 3, y), title_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_big, Color(0.35, 0.55, 0.2, text_a))

	y += float(fs_big) + 16
	draw_string(font, Vector2(cx - float(fs_med) * 3, y), "Score: %d" % points, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_med, Color(0.85, 0.75, 0.3, text_a))

	# Stats
	y += float(fs_med) + 20
	var stats_x: float = cx - float(fs_sm) * 5
	var line_h: float = float(fs_sm) + 10

	draw_string(font, Vector2(stats_x, y), "Plants grown: %d" % stat_plants, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sm, Color(0.45, 0.6, 0.3, text_a))
	y += line_h
	draw_string(font, Vector2(stats_x, y), "Flowers bloomed: %d" % stat_blooms, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sm, Color(0.8, 0.4, 0.6, text_a))
	y += line_h
	draw_string(font, Vector2(stats_x, y), "Fruit harvested: %d" % stat_fruits, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sm, Color(0.8, 0.3, 0.2, text_a))
	y += line_h
	draw_string(font, Vector2(stats_x, y), "Visitors attracted: %d" % stat_visitors, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sm, Color(0.6, 0.5, 0.8, text_a))
	y += line_h
	draw_string(font, Vector2(stats_x, y), "Branches pruned: %d" % stat_prunes, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sm, Color(0.5, 0.7, 0.4, text_a))
	y += line_h
	draw_string(font, Vector2(stats_x, y), "Bouquet: %d flowers" % bouquet.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sm, Color(0.85, 0.5, 0.65, text_a))

	y += line_h + 8
	if _best_score > 0:
		draw_string(font, Vector2(stats_x, y), "Best: %d" % _best_score, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_sm, Color(0.7, 0.6, 0.3, text_a * 0.7))

	if portrait_timer > 2.0:
		var tap_a: float = 0.4 + 0.4 * sin(portrait_timer * 2.5)
		var tap_fs: int = _font_size(0.03)
		draw_string(font, Vector2(cx - float(tap_fs) * 3, sh * 0.85), "Tap to continue", HORIZONTAL_ALIGNMENT_LEFT, -1, tap_fs, Color(0.5, 0.45, 0.35, tap_a))


func _draw_title() -> void:
	draw_rect(Rect2(0, 0, sw, sh), Color(0.88, 0.92, 0.84))
	var font := ThemeDB.fallback_font

	# Decorative background plants
	var deco_rng := RandomNumberGenerator.new()
	deco_rng.seed = 42
	for i in range(5):
		var x: float = sw * (0.1 + float(i) * 0.2)
		var base_y: float = sh * 0.75
		var trunk_col := Color(0.4, 0.25, 0.1, 0.3)
		var leaf_col := Color(0.2, 0.5, 0.15, 0.25)
		draw_line(Vector2(x, base_y), Vector2(x, base_y - 80 - deco_rng.randf() * 40), trunk_col, 3.0)
		draw_circle(Vector2(x - 5, base_y - 90 - deco_rng.randf() * 30), 15.0, leaf_col)
		draw_circle(Vector2(x + 8, base_y - 100 - deco_rng.randf() * 20), 12.0, leaf_col)
		draw_circle(Vector2(x, base_y - 110 - deco_rng.randf() * 25), 14.0, leaf_col)
		if i % 2 == 0:
			var fy: float = base_y - 30 - deco_rng.randf() * 20
			var fcol := Color(PETAL_COLORS[i % PETAL_COLORS.size()])
			fcol.a = 0.35
			for petal_i in range(5):
				var angle: float = float(petal_i) * TAU / 5.0 + title_timer * 0.2
				draw_circle(Vector2(x + 20, fy) + Vector2(cos(angle), sin(angle)) * 6, 4.0, fcol)
			draw_circle(Vector2(x + 20, fy), 3.0, Color(0.95, 0.85, 0.2, 0.4))

	draw_rect(Rect2(0, sh * 0.75, sw, sh * 0.25), Color(0.35, 0.22, 0.1, 0.4))

	var title_size: int = _font_size(0.06)
	var sub_size: int = _font_size(0.035)
	var inst_size: int = _font_size(0.03)
	var margin_x: float = sw * 0.12

	var title_y: float = sh * 0.28
	draw_string(font, Vector2(margin_x, title_y), "GREENHOUSE GARDEN", HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(0.25, 0.5, 0.15, 0.95))
	draw_string(font, Vector2(margin_x, title_y + float(title_size) + 8), "grow, water & harvest", HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, Color(0.45, 0.4, 0.3, 0.8))

	var inst_y: float = sh * 0.50
	var line_h: float = float(inst_size) + 8.0
	var inst_col := Color(0.4, 0.35, 0.25, 0.75)
	draw_string(font, Vector2(margin_x, inst_y), "Tap empty pot to plant a seed", HORIZONTAL_ALIGNMENT_LEFT, -1, inst_size, inst_col)
	draw_string(font, Vector2(margin_x, inst_y + line_h), "Tap a plant to water it", HORIZONTAL_ALIGNMENT_LEFT, -1, inst_size, inst_col)
	draw_string(font, Vector2(margin_x, inst_y + line_h * 2), "Tap ripe fruit or blooms to harvest", HORIZONTAL_ALIGNMENT_LEFT, -1, inst_size, inst_col)
	draw_string(font, Vector2(margin_x, inst_y + line_h * 3), "Tap leaf clusters to prune & boost", HORIZONTAL_ALIGNMENT_LEFT, -1, inst_size, Color(0.4, 0.65, 0.3, 0.75))
	draw_string(font, Vector2(margin_x, inst_y + line_h * 4), "Butterflies visit thriving gardens!", HORIZONTAL_ALIGNMENT_LEFT, -1, inst_size, Color(0.6, 0.4, 0.8, 0.75))

	if _best_score > 0:
		draw_string(font, Vector2(margin_x, sh * 0.82), "Best: %d" % _best_score, HORIZONTAL_ALIGNMENT_LEFT, -1, inst_size, Color(0.5, 0.45, 0.3, 0.6))

	var tap_size: int = _font_size(0.04)
	var tap_a: float = 0.5 + 0.5 * sin(title_timer * 2.5)
	draw_string(font, Vector2(sw * 0.5 - float(tap_size) * 3, sh * 0.90), "TAP TO START", HORIZONTAL_ALIGNMENT_LEFT, -1, tap_size, Color(0.3, 0.55, 0.2, tap_a))


# ── Audio ────────────────────────────────────────────────────────────────────

func _setup_audio() -> void:
	plant_sfx = AudioStreamPlayer.new()
	add_child(plant_sfx)
	plant_sfx.stream = _make_tone(0.15, 600.0, 900.0, 0.3)
	plant_sfx.volume_db = -12.0

	water_sfx = AudioStreamPlayer.new()
	add_child(water_sfx)
	water_sfx.stream = _make_noise(0.2, 0.4)
	water_sfx.volume_db = -14.0

	harvest_sfx = AudioStreamPlayer.new()
	add_child(harvest_sfx)
	harvest_sfx.stream = _make_tone(0.2, 400.0, 200.0, 0.5)
	harvest_sfx.volume_db = -10.0

	bloom_sfx = AudioStreamPlayer.new()
	add_child(bloom_sfx)
	bloom_sfx.stream = _make_chime(0.3, 520.0, 780.0, 0.4)
	bloom_sfx.volume_db = -10.0

	# Prune sound — short snip (high freq click)
	prune_sfx = AudioStreamPlayer.new()
	add_child(prune_sfx)
	prune_sfx.stream = _make_tone(0.08, 1200.0, 600.0, 0.8)
	prune_sfx.volume_db = -8.0

	ambient_player = AudioStreamPlayer.new()
	add_child(ambient_player)
	var amb_stream := AudioStreamWAV.new()
	amb_stream.format = AudioStreamWAV.FORMAT_16_BITS
	amb_stream.mix_rate = 22050
	amb_stream.stereo = false
	amb_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var amb_samples: int = 22050 * 2
	var amb_data := PackedByteArray()
	amb_data.resize(amb_samples * 2)
	for i in range(amb_samples):
		var t: float = float(i) / 22050.0
		var val := 0.0
		val += (randf() - 0.5) * 0.012 * (0.4 + 0.3 * sin(t * 0.15 * TAU))
		var chirp: float = maxf(0.0, sin(t * 3.0 * TAU)) * maxf(0.0, sin(t * 0.4 * TAU))
		val += sin(t * 3200.0 * TAU) * chirp * 0.03
		amb_data.encode_s16(i * 2, clampi(int(val * 32000.0), -32767, 32767))
	amb_stream.data = amb_data
	amb_stream.loop_end = amb_samples
	ambient_player.stream = amb_stream
	ambient_player.volume_db = -20.0


func _make_tone(duration: float, freq_start: float, freq_end: float, decay: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var samples: int = int(22050.0 * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t: float = float(i) / 22050.0
		var freq: float = lerpf(freq_start, freq_end, t / duration)
		var env: float = exp(-t * decay * 10.0)
		data.encode_s16(i * 2, clampi(int(sin(t * freq * TAU) * env * 0.6 * 32000.0), -32767, 32767))
	stream.data = data
	return stream


func _make_noise(duration: float, decay: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var samples: int = int(22050.0 * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t: float = float(i) / 22050.0
		var env: float = exp(-t * decay * 15.0)
		var val: float = (randf() - 0.5) * env * 0.5 * (sin(t * 800.0 * TAU) * 0.5 + 0.5)
		data.encode_s16(i * 2, clampi(int(val * 32000.0), -32767, 32767))
	stream.data = data
	return stream


func _make_chime(duration: float, freq1: float, freq2: float, decay: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var samples: int = int(22050.0 * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t: float = float(i) / 22050.0
		var frac: float = t / duration
		var env: float = exp(-t * decay * 8.0)
		var val: float = sin(t * freq1 * TAU) * env * 0.4
		if frac > 0.3:
			val += sin((t - duration * 0.3) * freq2 * TAU) * exp(-(t - duration * 0.3) * decay * 8.0) * 0.4
		data.encode_s16(i * 2, clampi(int(val * 32000.0), -32767, 32767))
	stream.data = data
	return stream


# ── Layout Helpers ───────────────────────────────────────────────────────────

func _font_size(scale: float) -> int:
	var base: float = minf(sw, sh)
	return int(clampf(base * scale, 11, 40))


func _slot_root(slot: int) -> Vector2:
	var row: int = slot / slots_per_row
	var col: int = slot % slots_per_row
	var items_in_row: int = slots_per_row if row == 0 else MAX_SLOTS - slots_per_row
	var row_start_x: float = (sw - float(items_in_row) * slot_width) * 0.5
	var x: float = row_start_x + float(col) * slot_width + slot_width * 0.5
	var y: float = ground_y + float(row) * row_height
	return Vector2(x, y)


func _slot_rect(slot: int) -> Rect2:
	var root: Vector2 = _slot_root(slot)
	var pot_w: float = minf(slot_width * 0.7, 70.0)
	var pot_h: float = minf(40.0, sh * 0.06)
	return Rect2(root.x - pot_w * 0.5, root.y + 2, pot_w, pot_h)
