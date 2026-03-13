extends Node2D

# ── Game States ──────────────────────────────────────────────────────────────
enum State { TITLE, PLAYING, SEARCHING, CAUGHT, ESCAPED }

# ── Map Constants ────────────────────────────────────────────────────────────
const MAP_W := 2400.0
const MAP_H := 2000.0
const CABIN_W := 100.0
const CABIN_H := 80.0
const TREE_RADIUS := 14.0
const PLAYER_RADIUS := 10.0
const JASON_RADIUS := 14.0
const LIGHT_RADIUS := 170.0
const CABIN_COUNT := 7
const TREE_COUNT := 55
const ITEM_COUNT := 5
const GAME_DURATION := 300.0   # 5 minutes real time = midnight to 6 AM
const SEARCH_TIME := 2.0
const SPRINT_SPEED := 220.0
const SPRINT_THRESHOLD := 200.0  # tap distance to trigger sprint
const BATTERY_DRAIN := 0.0028    # ~6 min to drain fully
const BATTERY_FLICKER_THRESHOLD := 0.3
const JASON_TELEPORT_INTERVAL := 25.0  # seconds between possible teleports

# ── Colors ───────────────────────────────────────────────────────────────────
const COL_GROUND := Color(0.015, 0.02, 0.01)
const COL_GROUND_LIT := Color(0.16, 0.22, 0.09)
const COL_CABIN := Color(0.38, 0.24, 0.12)
const COL_CABIN_ROOF := Color(0.28, 0.16, 0.08)
const COL_CABIN_DOOR := Color(0.55, 0.4, 0.18)
const COL_TREE_TRUNK := Color(0.3, 0.18, 0.08)
const COL_TREE_TOP := Color(0.1, 0.28, 0.08)
const COL_LAKE := Color(0.04, 0.1, 0.22)
const COL_LAKE_SHORE := Color(0.22, 0.2, 0.14)
const COL_PATH := Color(0.18, 0.14, 0.08)
const COL_PLAYER := Color(0.3, 0.55, 0.85)
const COL_PLAYER_SKIN := Color(0.85, 0.7, 0.55)
const COL_JASON_BODY := Color(0.2, 0.22, 0.2)
const COL_JASON_MASK := Color(0.85, 0.85, 0.8)
const COL_ITEM_GLOW := Color(1.0, 0.9, 0.2)
const COL_BLOOD := Color(0.7, 0.05, 0.05)
const COL_HUD_BG := Color(0.0, 0.0, 0.0, 0.7)
const COL_HUD_TEXT := Color(0.9, 0.9, 0.85)
const COL_WARNING := Color(0.8, 0.1, 0.1)

# ── State ────────────────────────────────────────────────────────────────────
var game_state: int = State.TITLE
var points: int = 0
var sw: float = 800.0
var sh: float = 600.0

# Player
var player_pos := Vector2(400.0, 1000.0)
var player_target := Vector2(400.0, 1000.0)
var player_speed := 140.0
var player_alive := true

# Jason
var jason_pos := Vector2(1200.0, 300.0)
var jason_speed := 45.0
var jason_base_speed := 45.0
var jason_hunt_speed := 70.0
var jason_state: int = 0  # 0=patrol, 1=hunting
var jason_patrol_target := Vector2.ZERO
var jason_patrol_wait := 0.0
var jason_awareness := 0.0
var jason_last_seen_pos := Vector2.ZERO
var jason_lost_timer := 0.0

# Map elements
var cabins: Array = []
var trees: Array = []
var lake_center := Vector2.ZERO
var lake_radius := 220.0
var paths: Array = []

# Items & searching
var items_found: int = 0
var found_items: Array = []
var item_names: Array = ["Car Keys", "Phone Battery", "Boat Fuel", "Fuse Box", "Radio Parts"]
var search_timer := 0.0
var searching_cabin: int = -1
var search_msg := ""
var search_msg_timer := 0.0

# Time & atmosphere
var game_time := 0.0
var heartbeat := 0.0  # 0-1 intensity
var pulse_timer := 0.0
var screen_flash := 0.0
var caught_timer := 0.0
var escaped_timer := 0.0
var title_timer := 0.0

# Camera
var cam := Vector2.ZERO

# Audio
var heartbeat_player: AudioStreamPlayer
var heartbeat_fast := false

# API
var _score_submitted := false
var _best_score: int = 0

# Sprint
var sprinting := false
var sprint_noise := 0.0  # 0-1, raises Jason detection range

# Flashlight battery
var flashlight_battery := 1.0
var flicker_offset := 0.0
var flicker_timer := 0.0

# Jason teleport
var jason_teleport_timer := 0.0

# Screen shake
var screen_shake := 0.0

# Ambient audio
var ambient_player: AudioStreamPlayer

# Footstep tracking
var _step_timer := 0.0
var footprints: Array = []  # {pos: Vector2, age: float}


func _ready() -> void:
	_resize()
	_generate_map()
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


# ── Map Generation ───────────────────────────────────────────────────────────

func _generate_map() -> void:
	cabins.clear()
	trees.clear()
	paths.clear()
	found_items.clear()
	items_found = 0

	# Lake in bottom-right area
	lake_center = Vector2(MAP_W * 0.72, MAP_H * 0.78)
	lake_radius = 220.0

	# Place cabins with rejection sampling
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var attempts := 0
	while cabins.size() < CABIN_COUNT and attempts < 500:
		attempts += 1
		var cx: float = rng.randf_range(150.0, MAP_W - 150.0)
		var cy: float = rng.randf_range(150.0, MAP_H - 150.0)
		var pos := Vector2(cx, cy)

		# Not in lake
		if pos.distance_to(lake_center) < lake_radius + 80.0:
			continue
		# Not too close to other cabins
		var too_close := false
		for c in cabins:
			if pos.distance_to(c["pos"]) < 280.0:
				too_close = true
				break
		if too_close:
			continue

		var cabin := {
			"pos": pos,
			"searched": false,
			"has_item": false,
			"item_idx": -1,
		}
		cabins.append(cabin)

	# Assign items to random cabins
	var item_indices: Array = []
	for i in range(cabins.size()):
		item_indices.append(i)
	item_indices.shuffle()
	for i in range(mini(ITEM_COUNT, cabins.size())):
		var ci: int = item_indices[i]
		cabins[ci]["has_item"] = true
		cabins[ci]["item_idx"] = i

	# Paths connecting nearby cabins
	for i in range(cabins.size()):
		var best_dist := 99999.0
		var best_j := -1
		for j in range(cabins.size()):
			if j == i:
				continue
			var d: float = Vector2(cabins[i]["pos"]).distance_to(Vector2(cabins[j]["pos"]))
			if d < best_dist:
				best_dist = d
				best_j = j
		if best_j >= 0:
			paths.append({"a": Vector2(cabins[i]["pos"]), "b": Vector2(cabins[best_j]["pos"])})

	# Place trees
	attempts = 0
	while trees.size() < TREE_COUNT and attempts < 800:
		attempts += 1
		var tx: float = rng.randf_range(40.0, MAP_W - 40.0)
		var ty: float = rng.randf_range(40.0, MAP_H - 40.0)
		var tp := Vector2(tx, ty)
		# Not in lake
		if tp.distance_to(lake_center) < lake_radius + 30.0:
			continue
		# Not in cabins
		var in_cabin := false
		for c in cabins:
			var r := Rect2(Vector2(c["pos"]) - Vector2(CABIN_W, CABIN_H) * 0.6, Vector2(CABIN_W, CABIN_H) * 1.2)
			if r.has_point(tp):
				in_cabin = true
				break
		if in_cabin:
			continue
		# Not too close to other trees
		var ok := true
		for t in trees:
			if tp.distance_to(Vector2(t["pos"])) < 30.0:
				ok = false
				break
		if not ok:
			continue
		trees.append({"pos": tp, "r": rng.randf_range(10.0, 18.0)})

	# Player starts at first cabin
	if cabins.size() > 0:
		player_pos = Vector2(cabins[0]["pos"]) + Vector2(0, CABIN_H * 0.5 + 20.0)
		player_target = player_pos
	# Jason starts at furthest cabin
	var max_dist := 0.0
	var jason_cabin := 0
	for i in range(cabins.size()):
		var d: float = Vector2(cabins[i]["pos"]).distance_to(player_pos)
		if d > max_dist:
			max_dist = d
			jason_cabin = i
	if cabins.size() > 1:
		jason_pos = Vector2(cabins[jason_cabin]["pos"])
	jason_patrol_target = jason_pos
	cam = player_pos


# ── Audio ────────────────────────────────────────────────────────────────────

func _setup_audio() -> void:
	heartbeat_player = AudioStreamPlayer.new()
	add_child(heartbeat_player)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	# Generate heartbeat: two thumps (lub-dub)
	var sample_count: int = 22050  # 1 second loop
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in range(sample_count):
		var t: float = float(i) / 22050.0
		var val := 0.0
		# First thump at t=0..0.08
		if t < 0.08:
			var env: float = sin(t / 0.08 * PI)
			val = sin(t * 55.0 * TAU) * env * 0.7
		# Second thump at t=0.15..0.22
		elif t > 0.15 and t < 0.22:
			var t2: float = t - 0.15
			var env2: float = sin(t2 / 0.07 * PI)
			val = sin(t2 * 65.0 * TAU) * env2 * 0.5
		var s: int = clampi(int(val * 32000.0), -32767, 32767)
		data.encode_s16(i * 2, s)
	stream.data = data
	stream.loop_end = sample_count
	heartbeat_player.stream = stream
	heartbeat_player.volume_db = -80.0  # start silent

	# Ambient cricket/wind loop
	ambient_player = AudioStreamPlayer.new()
	add_child(ambient_player)
	var amb_stream := AudioStreamWAV.new()
	amb_stream.format = AudioStreamWAV.FORMAT_16_BITS
	amb_stream.mix_rate = 22050
	amb_stream.stereo = false
	amb_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var amb_samples: int = 22050 * 3  # 3 second loop
	var amb_data := PackedByteArray()
	amb_data.resize(amb_samples * 2)
	for i in range(amb_samples):
		var t: float = float(i) / 22050.0
		var val := 0.0
		# Crickets: rapid chirps at ~4kHz modulated by slow envelope
		var chirp_env: float = max(0.0, sin(t * 7.0 * TAU)) * max(0.0, sin(t * 0.8 * TAU))
		val += sin(t * 4200.0 * TAU) * chirp_env * 0.08
		# Second cricket offset
		var chirp2: float = max(0.0, sin((t + 0.3) * 5.5 * TAU)) * max(0.0, sin((t + 0.3) * 0.6 * TAU))
		val += sin(t * 3800.0 * TAU) * chirp2 * 0.06
		# Wind: filtered noise
		val += (randf() - 0.5) * 0.015 * (0.5 + 0.5 * sin(t * 0.2 * TAU))
		var amb_s: int = clampi(int(val * 32000.0), -32767, 32767)
		amb_data.encode_s16(i * 2, amb_s)
	amb_stream.data = amb_data
	amb_stream.loop_end = amb_samples
	ambient_player.stream = amb_stream
	ambient_player.volume_db = -18.0


# ── Input ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if game_state == State.TITLE:
		if _is_press(event):
			_start_game()
		return

	if game_state == State.CAUGHT or game_state == State.ESCAPED:
		if _is_press(event):
			_go_title()
		return

	if game_state == State.PLAYING or game_state == State.SEARCHING:
		if not _is_press(event):
			return
		var pos: Vector2 = _event_pos(event)
		var world: Vector2 = pos + cam - Vector2(sw, sh) * 0.5

		# If searching, tap cancels
		if game_state == State.SEARCHING:
			searching_cabin = -1
			search_timer = 0.0
			game_state = State.PLAYING
			return

		# Check if tapping a nearby cabin
		for i in range(cabins.size()):
			var c: Dictionary = cabins[i]
			var cpos: Vector2 = Vector2(c["pos"])
			var rect := Rect2(cpos - Vector2(CABIN_W, CABIN_H) * 0.6, Vector2(CABIN_W, CABIN_H) * 1.2)
			if rect.has_point(world) and player_pos.distance_to(cpos) < CABIN_W + 30.0:
				if not bool(c["searched"]):
					_start_search(i)
					return
				else:
					# Already searched, show message
					search_msg = "Already searched"
					search_msg_timer = 1.0
					return

		# Move toward tap — far taps trigger sprint
		player_target = world
		player_target.x = clampf(player_target.x, 20.0, MAP_W - 20.0)
		player_target.y = clampf(player_target.y, 20.0, MAP_H - 20.0)
		var tap_dist: float = player_pos.distance_to(player_target)
		sprinting = tap_dist > SPRINT_THRESHOLD


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

	if game_state == State.CAUGHT:
		caught_timer += delta
		queue_redraw()
		return

	if game_state == State.ESCAPED:
		escaped_timer += delta
		queue_redraw()
		return

	# PLAYING or SEARCHING
	game_time += delta
	if search_msg_timer > 0.0:
		search_msg_timer -= delta

	# Player movement (not while searching)
	if game_state == State.PLAYING:
		_move_player(delta)

	# Search timer
	if game_state == State.SEARCHING:
		search_timer -= delta
		if search_timer <= 0.0:
			_finish_search()

	# Jason AI
	_update_jason(delta)

	# Check catch
	if player_pos.distance_to(jason_pos) < PLAYER_RADIUS + JASON_RADIUS + 4.0:
		_player_caught()

	# Check win by items
	if items_found >= ITEM_COUNT:
		_player_escaped()

	# Check win by time (survived till dawn)
	if game_time >= GAME_DURATION:
		_player_escaped()

	# Heartbeat proximity
	var jason_dist: float = player_pos.distance_to(jason_pos)
	var hb_range := 300.0
	if jason_dist < hb_range:
		heartbeat = 1.0 - jason_dist / hb_range
	else:
		heartbeat = 0.0
	pulse_timer += delta * (1.5 + heartbeat * 4.0)

	# Heartbeat audio
	if heartbeat > 0.05:
		if not heartbeat_player.playing:
			heartbeat_player.play()
		heartbeat_player.volume_db = lerpf(-40.0, -6.0, heartbeat)
		heartbeat_player.pitch_scale = lerpf(0.7, 1.8, heartbeat)
	else:
		if heartbeat_player.playing:
			heartbeat_player.stop()

	# Sprint noise (decays when not sprinting)
	if sprinting and player_pos.distance_to(player_target) > 5.0:
		sprint_noise = minf(sprint_noise + delta * 2.0, 1.0)
	else:
		sprint_noise = maxf(sprint_noise - delta * 1.5, 0.0)
		sprinting = false

	# Flashlight battery drain
	flashlight_battery -= BATTERY_DRAIN * delta
	if flashlight_battery < 0.0:
		flashlight_battery = 0.0
	# Flicker when low
	flicker_timer += delta
	if flashlight_battery < BATTERY_FLICKER_THRESHOLD:
		var flicker_chance: float = (1.0 - flashlight_battery / BATTERY_FLICKER_THRESHOLD) * 0.4
		if randf() < flicker_chance * delta * 10.0:
			flicker_offset = randf_range(-30.0, -60.0)  # sudden dim
		else:
			flicker_offset = lerpf(flicker_offset, 0.0, delta * 8.0)
	else:
		flicker_offset = lerpf(flicker_offset, 0.0, delta * 10.0)

	# Jason speed ramp (much scarier now)
	var minutes: float = game_time / 60.0
	jason_base_speed = 55.0 + minutes * 5.0
	jason_hunt_speed = 95.0 + minutes * 6.0

	# Jason teleport — when offscreen, occasionally warp to a nearby cabin
	jason_teleport_timer += delta
	if jason_teleport_timer > JASON_TELEPORT_INTERVAL and jason_state == 0:
		var dist_to_player: float = jason_pos.distance_to(player_pos)
		if dist_to_player > 400.0:  # only when far away
			_jason_teleport_near_player()
			jason_teleport_timer = 0.0

	# Screen shake decay
	if screen_shake > 0.0:
		screen_shake = maxf(screen_shake - delta * 4.0, 0.0)

	# Screen flash decay
	if screen_flash > 0.0:
		screen_flash -= delta * 2.0
		if screen_flash < 0.0:
			screen_flash = 0.0

	# Camera follow (with screen shake)
	var shake_offset := Vector2.ZERO
	if screen_shake > 0.0:
		shake_offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * screen_shake * 8.0
	cam = cam.lerp(player_pos, 5.0 * delta) + shake_offset
	cam.x = clampf(cam.x, sw * 0.5, MAP_W - sw * 0.5)
	cam.y = clampf(cam.y, sh * 0.5, MAP_H - sh * 0.5)

	# Ambient audio
	if not ambient_player.playing:
		ambient_player.play()

	# Footprints
	if player_pos.distance_to(player_target) > 5.0:
		_step_timer += delta
		var step_interval: float = 0.3 if sprinting else 0.5
		if _step_timer > step_interval:
			_step_timer = 0.0
			footprints.append({"pos": player_pos, "age": 0.0})
	# Age and remove old footprints
	var i := 0
	while i < footprints.size():
		footprints[i]["age"] = float(footprints[i]["age"]) + delta
		if float(footprints[i]["age"]) > 4.0:
			footprints.remove_at(i)
		else:
			i += 1

	# Points tick
	points = items_found * 200 + int(game_time) * 2

	queue_redraw()


# ── Player Movement ──────────────────────────────────────────────────────────

func _move_player(delta: float) -> void:
	var diff: Vector2 = player_target - player_pos
	if diff.length() < 3.0:
		sprinting = false
		return
	var speed: float = SPRINT_SPEED if sprinting else player_speed
	var vel: Vector2 = diff.normalized() * speed * delta
	if vel.length() > diff.length():
		vel = diff
	var new_pos: Vector2 = player_pos + vel

	# Collision with lake
	if new_pos.distance_to(lake_center) < lake_radius + 10.0:
		var away: Vector2 = (new_pos - lake_center).normalized()
		new_pos = lake_center + away * (lake_radius + 12.0)

	# Collision with trees
	for t in trees:
		var tpos: Vector2 = Vector2(t["pos"])
		var tr: float = float(t["r"])
		if new_pos.distance_to(tpos) < tr + PLAYER_RADIUS:
			var push: Vector2 = (new_pos - tpos).normalized()
			new_pos = tpos + push * (tr + PLAYER_RADIUS + 1.0)

	# Collision with cabin walls (but allow entering door side — south face)
	for c in cabins:
		var cpos: Vector2 = Vector2(c["pos"])
		var rect := Rect2(cpos - Vector2(CABIN_W, CABIN_H) * 0.5, Vector2(CABIN_W, CABIN_H))
		if rect.has_point(new_pos):
			# Push out to nearest edge
			var dx1: float = new_pos.x - rect.position.x
			var dx2: float = rect.end.x - new_pos.x
			var dy1: float = new_pos.y - rect.position.y
			var dy2: float = rect.end.y - new_pos.y
			var min_d: float = min(min(dx1, dx2), min(dy1, dy2))
			if min_d == dx1:
				new_pos.x = rect.position.x - 1.0
			elif min_d == dx2:
				new_pos.x = rect.end.x + 1.0
			elif min_d == dy1:
				new_pos.y = rect.position.y - 1.0
			else:
				new_pos.y = rect.end.y + 1.0

	new_pos.x = clampf(new_pos.x, 10.0, MAP_W - 10.0)
	new_pos.y = clampf(new_pos.y, 10.0, MAP_H - 10.0)
	player_pos = new_pos

	# Footstep tracking for audio feel
	_step_timer += delta


# ── Jason AI ─────────────────────────────────────────────────────────────────

func _update_jason(delta: float) -> void:
	var can_see_player := _jason_can_see_player()

	if jason_state == 0:  # Patrol
		# Move toward patrol target
		var to_target: Vector2 = jason_patrol_target - jason_pos
		if to_target.length() < 10.0:
			jason_patrol_wait -= delta
			if jason_patrol_wait <= 0.0:
				_jason_pick_patrol()
		else:
			var move_dir: Vector2 = to_target.normalized()
			jason_pos += move_dir * jason_base_speed * delta
			_jason_avoid_lake(delta)

		# Detect player
		if can_see_player:
			jason_state = 1
			jason_last_seen_pos = player_pos
			jason_awareness = 1.0
			screen_flash = 0.5
			screen_shake = 1.0  # camera shake on detection!

	elif jason_state == 1:  # Hunting
		if can_see_player:
			jason_last_seen_pos = player_pos
			jason_lost_timer = 0.0
		else:
			jason_lost_timer += delta

		var hunt_target: Vector2 = jason_last_seen_pos
		if can_see_player:
			hunt_target = player_pos
		var to_player: Vector2 = hunt_target - jason_pos
		if to_player.length() > 5.0:
			var move_dir: Vector2 = to_player.normalized()
			# Jason navigates around cabins
			var next_pos: Vector2 = jason_pos + move_dir * jason_hunt_speed * delta
			for c in cabins:
				var cpos: Vector2 = Vector2(c["pos"])
				var rect := Rect2(cpos - Vector2(CABIN_W, CABIN_H) * 0.55, Vector2(CABIN_W, CABIN_H) * 1.1)
				if rect.has_point(next_pos):
					# Steer around
					var side: Vector2 = Vector2(move_dir.y, -move_dir.x)
					next_pos = jason_pos + side * jason_hunt_speed * delta
					break
			jason_pos = next_pos
			_jason_avoid_lake(delta)

		# Lost player
		if jason_lost_timer > 5.0:
			jason_state = 0
			_jason_pick_patrol()

	jason_pos.x = clampf(jason_pos.x, 10.0, MAP_W - 10.0)
	jason_pos.y = clampf(jason_pos.y, 10.0, MAP_H - 10.0)


func _jason_can_see_player() -> bool:
	var dist: float = player_pos.distance_to(jason_pos)
	# Close range always detects
	if dist < 60.0:
		return true
	# Detection range expands when player is sprinting (noise!)
	var detect_range: float = 280.0 + sprint_noise * 250.0
	# Beyond detection range
	if dist > detect_range:
		return false
	# If player is searching (in cabin), harder to detect
	if game_state == State.SEARCHING and dist > 100.0:
		return false
	# Line of sight check — blocked by cabins
	for c in cabins:
		var cpos: Vector2 = Vector2(c["pos"])
		var rect := Rect2(cpos - Vector2(CABIN_W, CABIN_H) * 0.5, Vector2(CABIN_W, CABIN_H))
		if _line_intersects_rect(jason_pos, player_pos, rect):
			return false
	return true


func _line_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	# Simple AABB line intersection
	var dir: Vector2 = b - a
	var len_sq: float = dir.length_squared()
	if len_sq < 0.01:
		return rect.has_point(a)
	# Check if midpoints are inside (rough but fast)
	var mid: Vector2 = (a + b) * 0.5
	if rect.has_point(mid):
		return true
	var q1: Vector2 = (a + mid) * 0.5
	var q3: Vector2 = (mid + b) * 0.5
	if rect.has_point(q1) or rect.has_point(q3):
		return true
	return false


func _jason_pick_patrol() -> void:
	# Pick a random cabin to patrol toward
	if cabins.size() > 0:
		var idx: int = randi() % cabins.size()
		jason_patrol_target = Vector2(cabins[idx]["pos"]) + Vector2(randf_range(-50, 50), randf_range(-50, 50))
	else:
		jason_patrol_target = Vector2(randf_range(100, MAP_W - 100), randf_range(100, MAP_H - 100))
	jason_patrol_wait = randf_range(1.5, 4.0)


func _jason_teleport_near_player() -> void:
	# Teleport Jason to a cabin that's close-ish to the player but not visible
	var best_cabin := -1
	var best_score := -1.0
	for i in range(cabins.size()):
		var cpos: Vector2 = Vector2(cabins[i]["pos"])
		var d_to_player: float = cpos.distance_to(player_pos)
		# Must be outside player's light but not too far (sweet spot: 300-600px)
		if d_to_player < LIGHT_RADIUS * 2.0 or d_to_player > 700.0:
			continue
		# Prefer cabins the player hasn't searched (they'll go there)
		var score: float = 1.0 / (d_to_player + 1.0) * 1000.0
		if not bool(cabins[i]["searched"]):
			score *= 2.0
		if score > best_score:
			best_score = score
			best_cabin = i
	if best_cabin >= 0:
		jason_pos = Vector2(cabins[best_cabin]["pos"]) + Vector2(randf_range(-40, 40), randf_range(-40, 40))
		jason_patrol_target = jason_pos


func _jason_avoid_lake(delta: float) -> void:
	if jason_pos.distance_to(lake_center) < lake_radius + 20.0:
		var away: Vector2 = (jason_pos - lake_center).normalized()
		jason_pos = lake_center + away * (lake_radius + 22.0)


# ── Cabin Searching ──────────────────────────────────────────────────────────

func _start_search(idx: int) -> void:
	searching_cabin = idx
	search_timer = SEARCH_TIME
	game_state = State.SEARCHING
	# Move player to cabin center
	player_pos = Vector2(cabins[idx]["pos"])
	player_target = player_pos


func _finish_search() -> void:
	if searching_cabin >= 0 and searching_cabin < cabins.size():
		var c: Dictionary = cabins[searching_cabin]
		c["searched"] = true
		if bool(c["has_item"]):
			var idx: int = int(c["item_idx"])
			if idx >= 0 and idx < item_names.size():
				found_items.append(item_names[idx])
			else:
				found_items.append("???")
			items_found += 1
			search_msg = "Found: " + str(found_items[found_items.size() - 1]) + "!"
			screen_flash = 0.3
		else:
			search_msg = "Nothing here..."
		search_msg_timer = 2.0
		cabins[searching_cabin] = c
	searching_cabin = -1
	game_state = State.PLAYING


# ── State Transitions ────────────────────────────────────────────────────────

func _start_game() -> void:
	game_state = State.PLAYING
	game_time = 0.0
	points = 0
	player_alive = true
	caught_timer = 0.0
	escaped_timer = 0.0
	_score_submitted = false
	heartbeat = 0.0
	screen_flash = 0.0
	search_msg = ""
	search_msg_timer = 0.0
	jason_state = 0
	jason_lost_timer = 0.0
	jason_teleport_timer = 0.0
	sprinting = false
	sprint_noise = 0.0
	flashlight_battery = 1.0
	flicker_offset = 0.0
	screen_shake = 0.0
	footprints.clear()
	_generate_map()


func _player_caught() -> void:
	game_state = State.CAUGHT
	player_alive = false
	caught_timer = 0.0
	screen_flash = 1.0
	heartbeat_player.stop()
	_submit_score()


func _player_escaped() -> void:
	game_state = State.ESCAPED
	escaped_timer = 0.0
	points += 1000  # escape bonus
	if game_time >= GAME_DURATION:
		points += 500  # dawn survival bonus
	heartbeat_player.stop()
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


# ── Drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	if game_state == State.TITLE:
		_draw_title()
		return

	var offset: Vector2 = -cam + Vector2(sw, sh) * 0.5

	# Ground — dark
	draw_rect(Rect2(0, 0, sw, sh), COL_GROUND)

	# Effective light radius (battery + flicker)
	var eff_light: float = LIGHT_RADIUS * clampf(flashlight_battery * 1.1, 0.15, 1.0) + flicker_offset

	# Lit ground circle — smooth radial gradient from player position
	var pscreen: Vector2 = player_pos + offset
	var lit_steps := 32
	for i in range(lit_steps, 0, -1):
		var frac: float = float(i) / float(lit_steps)
		var r: float = eff_light * 1.2 * frac
		# Quadratic falloff for natural light feel
		var intensity: float = (1.0 - frac) * (1.0 - frac)
		var col: Color = COL_GROUND_LIT
		col.a = intensity * 0.9
		draw_circle(pscreen, r, col)

	# Draw map elements (only if near player for visibility)
	_draw_lake(offset)
	_draw_paths(offset)
	_draw_cabins(offset)
	_draw_trees(offset)
	_draw_items_in_cabins(offset)
	_draw_footprints(offset)
	_draw_jason(offset)
	_draw_player(offset)

	# No darkness overlay needed — _visibility() alpha + dark ground handles it

	# Heartbeat red pulse
	if heartbeat > 0.1:
		var pulse_a: float = heartbeat * 0.18 * (0.5 + 0.5 * sin(pulse_timer * TAU))
		draw_rect(Rect2(0, 0, sw, sh), Color(0.6, 0.0, 0.0, clampf(pulse_a, 0.0, 0.3)))

	# Screen flash (item found / jason spot)
	if screen_flash > 0.0:
		draw_rect(Rect2(0, 0, sw, sh), Color(1.0, 1.0, 1.0, screen_flash * 0.15))

	# HUD
	_draw_hud()

	# Search progress
	if game_state == State.SEARCHING:
		_draw_search_bar()

	# Search message
	if search_msg_timer > 0.0:
		_draw_search_msg()

	# Game over overlays
	if game_state == State.CAUGHT:
		_draw_caught()
	elif game_state == State.ESCAPED:
		_draw_escaped()


func _visibility(world_pos: Vector2) -> float:
	var eff: float = LIGHT_RADIUS * clampf(flashlight_battery * 1.1, 0.15, 1.0) + flicker_offset
	var d: float = player_pos.distance_to(world_pos)
	if d > eff * 1.4:
		return 0.0
	if d < eff * 0.5:
		return 1.0
	return 1.0 - (d - eff * 0.5) / (eff * 0.9)


func _draw_lake(offset: Vector2) -> void:
	var vis: float = _visibility(lake_center)
	if vis <= 0.0:
		return
	# Shore
	var shore_col := COL_LAKE_SHORE
	shore_col.a = vis * 0.6
	draw_circle(lake_center + offset, lake_radius + 15.0, shore_col)
	# Water
	var water_col := COL_LAKE
	water_col.a = vis * 0.8
	draw_circle(lake_center + offset, lake_radius, water_col)
	# Moonlight reflection
	var ref_col := Color(0.15, 0.2, 0.35, vis * 0.3)
	draw_circle(lake_center + offset + Vector2(-30, -40), lake_radius * 0.3, ref_col)


func _draw_paths(offset: Vector2) -> void:
	for p in paths:
		var a_pos: Vector2 = Vector2(p["a"])
		var b_pos: Vector2 = Vector2(p["b"])
		var mid: Vector2 = (a_pos + b_pos) * 0.5
		var vis: float = _visibility(mid)
		if vis <= 0.0:
			continue
		var col := COL_PATH
		col.a = vis * 0.5
		draw_line(a_pos + offset, b_pos + offset, col, 6.0)


func _draw_cabins(offset: Vector2) -> void:
	for i in range(cabins.size()):
		var c: Dictionary = cabins[i]
		var cpos: Vector2 = Vector2(c["pos"])
		var vis: float = _visibility(cpos)
		if vis <= 0.0:
			continue

		var rect := Rect2(cpos - Vector2(CABIN_W, CABIN_H) * 0.5 + offset, Vector2(CABIN_W, CABIN_H))

		# Shadow
		var shad := Color(0.0, 0.0, 0.0, vis * 0.3)
		draw_rect(Rect2(rect.position + Vector2(4, 4), rect.size), shad)

		# Cabin body
		var body_col := COL_CABIN
		body_col.a = vis
		draw_rect(rect, body_col)

		# Roof (darker top strip)
		var roof_col := COL_CABIN_ROOF
		roof_col.a = vis
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 14)), roof_col)

		# Door (bottom center)
		var door_col := COL_CABIN_DOOR
		door_col.a = vis
		var dw := 18.0
		var dh := 24.0
		draw_rect(Rect2(cpos.x - dw * 0.5 + offset.x, cpos.y + CABIN_H * 0.5 - dh + offset.y, dw, dh), door_col)

		# If searched, show checkmark or X
		if bool(c["searched"]):
			var mark_col := Color(0.5, 0.5, 0.5, vis * 0.7)
			if bool(c["has_item"]):
				# Was found — green check
				mark_col = Color(0.2, 0.8, 0.2, vis * 0.8)
			var mark_pos: Vector2 = cpos + offset + Vector2(0, -CABIN_H * 0.5 - 12)
			draw_circle(mark_pos, 8.0, mark_col)


func _draw_trees(offset: Vector2) -> void:
	for t in trees:
		var tpos: Vector2 = Vector2(t["pos"])
		var vis: float = _visibility(tpos)
		if vis <= 0.0:
			continue
		var tr: float = float(t["r"])

		# Trunk
		var trunk_col := COL_TREE_TRUNK
		trunk_col.a = vis
		draw_rect(Rect2(tpos.x - 3 + offset.x, tpos.y - 2 + offset.y, 6, tr * 0.8), trunk_col)

		# Canopy
		var top_col := COL_TREE_TOP
		top_col.a = vis
		draw_circle(tpos + offset + Vector2(0, -tr * 0.3), tr, top_col)


func _draw_items_in_cabins(offset: Vector2) -> void:
	for c in cabins:
		var cpos: Vector2 = Vector2(c["pos"])
		var searched: bool = bool(c["searched"])
		# Unsearched cabins: show a faint warm glow visible from further away
		if not searched:
			var dist: float = player_pos.distance_to(cpos)
			if dist < LIGHT_RADIUS * 3.0:
				var far_a: float = 0.08 * (1.0 - dist / (LIGHT_RADIUS * 3.0))
				var pulse: float = 0.7 + 0.3 * sin(game_time * 1.5 + cpos.x * 0.1)
				draw_circle(cpos + offset, 30.0, Color(0.8, 0.6, 0.2, far_a * pulse))
		if not bool(c["has_item"]) or searched:
			continue
		var vis: float = _visibility(cpos)
		if vis < 0.3:
			continue
		# Bright glow inside cabin when close
		var glow_col := COL_ITEM_GLOW
		glow_col.a = vis * 0.3 * (0.6 + 0.4 * sin(game_time * 3.0))
		draw_circle(cpos + offset, 22.0, glow_col)


func _draw_footprints(offset: Vector2) -> void:
	for fp in footprints:
		var fpos: Vector2 = Vector2(fp["pos"])
		var age: float = float(fp["age"])
		var vis: float = _visibility(fpos)
		if vis <= 0.0:
			continue
		var a: float = vis * (1.0 - age / 4.0) * 0.3
		draw_circle(fpos + offset, 3.0, Color(0.3, 0.25, 0.15, a))


func _draw_player(offset: Vector2) -> void:
	var ppos: Vector2 = player_pos + offset
	# Sprint aura
	if sprinting and sprint_noise > 0.2:
		var noise_a: float = sprint_noise * 0.15 * (0.6 + 0.4 * sin(game_time * 8.0))
		draw_circle(ppos, PLAYER_RADIUS * 3.0, Color(1.0, 0.7, 0.2, noise_a))
	# Body
	draw_circle(ppos, PLAYER_RADIUS, COL_PLAYER)
	# Head
	draw_circle(ppos + Vector2(0, -PLAYER_RADIUS * 0.6), PLAYER_RADIUS * 0.55, COL_PLAYER_SKIN)
	# Flashlight beam direction
	var dir: Vector2 = (player_target - player_pos)
	if dir.length() > 1.0:
		dir = dir.normalized()
	else:
		dir = Vector2(0, -1)
	var beam_end: Vector2 = ppos + dir * LIGHT_RADIUS * 0.8
	var beam_col := Color(1.0, 0.95, 0.7, 0.08)
	# Draw beam as a narrow triangle
	var perp: Vector2 = Vector2(-dir.y, dir.x) * 25.0
	var beam_points := PackedVector2Array([ppos + dir * 15.0, beam_end + perp, beam_end - perp])
	var beam_colors := PackedColorArray([beam_col, Color(1.0, 0.95, 0.7, 0.0), Color(1.0, 0.95, 0.7, 0.0)])
	draw_polygon(beam_points, beam_colors)


func _draw_jason(offset: Vector2) -> void:
	var vis: float = _visibility(jason_pos)
	if vis <= 0.0:
		return
	var jpos: Vector2 = jason_pos + offset

	# Body — dark figure
	var body_col := COL_JASON_BODY
	body_col.a = vis
	draw_circle(jpos, JASON_RADIUS, body_col)

	# Hockey mask
	var mask_col := COL_JASON_MASK
	mask_col.a = vis
	draw_circle(jpos + Vector2(0, -JASON_RADIUS * 0.4), JASON_RADIUS * 0.6, mask_col)

	# Eye holes
	var eye_col := Color(0.0, 0.0, 0.0, vis)
	draw_circle(jpos + Vector2(-3, -JASON_RADIUS * 0.5), 2.0, eye_col)
	draw_circle(jpos + Vector2(3, -JASON_RADIUS * 0.5), 2.0, eye_col)

	# Red glow when hunting
	if jason_state == 1:
		var glow := Color(0.8, 0.0, 0.0, vis * 0.3 * (0.5 + 0.5 * sin(game_time * 6.0)))
		draw_circle(jpos, JASON_RADIUS * 2.0, glow)


func _draw_darkness(player_screen: Vector2) -> void:
	# Draw dark rings OUTSIDE the light radius to darken the edge/corners
	# Use wide, overlapping arcs so the cumulative alpha creates smooth falloff
	# Objects already fade via _visibility(), this just ensures the background is dark
	var steps := 30
	for i in range(steps):
		var frac: float = float(i) / float(steps)
		var r: float = LIGHT_RADIUS * (1.2 + frac * 3.0)
		# Inner rings lighter, outer rings darker
		var a: float = minf(0.12 + frac * 0.25, 0.35)
		draw_arc(player_screen, r, 0, TAU, 48, Color(0.0, 0.0, 0.02, a), LIGHT_RADIUS * 0.25)


func _draw_hud() -> void:
	# Top bar background
	draw_rect(Rect2(0, 0, sw, 44), COL_HUD_BG)

	var font := ThemeDB.fallback_font
	var font_size := 18

	# Time display (midnight to 6 AM)
	var progress: float = clampf(game_time / GAME_DURATION, 0.0, 1.0)
	var total_minutes: float = progress * 360.0  # 6 hours = 360 minutes
	var hour: int = int(total_minutes / 60.0)
	var minute: int = int(total_minutes) % 60
	var time_str: String = "%d:%02d AM" % [12 if hour == 0 else hour, minute]
	draw_string(font, Vector2(12, 30), time_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_HUD_TEXT)

	# Items found
	var items_str: String = "ITEMS: %d/%d" % [items_found, ITEM_COUNT]
	var items_col := COL_HUD_TEXT
	if items_found >= ITEM_COUNT:
		items_col = COL_ITEM_GLOW
	draw_string(font, Vector2(sw * 0.5 - 50, 30), items_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, items_col)

	# Score
	draw_string(font, Vector2(sw - 120, 30), str(points), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COL_HUD_TEXT)

	# Dawn progress bar
	var bar_w: float = sw - 24.0
	var bar_h := 3.0
	var bar_y := 40.0
	draw_rect(Rect2(12, bar_y, bar_w, bar_h), Color(0.2, 0.2, 0.2, 0.5))
	var fill_col := Color(0.3, 0.3, 0.6, 0.7)
	if progress > 0.75:
		fill_col = Color(0.8, 0.6, 0.2, 0.8)  # Getting close to dawn
	draw_rect(Rect2(12, bar_y, bar_w * progress, bar_h), fill_col)

	# Found items display at bottom
	if found_items.size() > 0:
		var bottom_y: float = sh - 36.0
		draw_rect(Rect2(0, bottom_y - 4, sw, 40), COL_HUD_BG)
		var ix: float = 12.0
		for item_name in found_items:
			draw_string(font, Vector2(ix, bottom_y + 18), str(item_name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_ITEM_GLOW)
			ix += 110.0

	# Battery indicator (right side, below score)
	var bat_w := 60.0
	var bat_h := 6.0
	var bat_x: float = sw - bat_w - 12.0
	var bat_y := 34.0
	draw_rect(Rect2(bat_x, bat_y, bat_w, bat_h), Color(0.2, 0.2, 0.2, 0.6))
	var bat_col := Color(0.3, 0.8, 0.3, 0.8)
	if flashlight_battery < 0.3:
		bat_col = Color(0.9, 0.3, 0.1, 0.8)
	elif flashlight_battery < 0.5:
		bat_col = Color(0.9, 0.7, 0.2, 0.8)
	draw_rect(Rect2(bat_x, bat_y, bat_w * clampf(flashlight_battery, 0.0, 1.0), bat_h), bat_col)

	# Sprint noise indicator
	if sprint_noise > 0.1:
		var noise_col := Color(1.0, 0.7, 0.2, sprint_noise * 0.7)
		draw_string(font, Vector2(sw * 0.5 - 30, sh - 12), "RUNNING!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, noise_col)

	# Jason proximity warning
	if heartbeat > 0.5:
		var warn_a: float = (heartbeat - 0.5) * 2.0 * (0.5 + 0.5 * sin(pulse_timer * TAU * 2.0))
		var warn_col := COL_WARNING
		warn_col.a = clampf(warn_a * 0.6, 0.0, 0.5)
		# Red border
		draw_rect(Rect2(0, 0, sw, 4), warn_col)
		draw_rect(Rect2(0, sh - 4, sw, 4), warn_col)
		draw_rect(Rect2(0, 0, 4, sh), warn_col)
		draw_rect(Rect2(sw - 4, 0, 4, sh), warn_col)


func _draw_search_bar() -> void:
	var progress: float = 1.0 - search_timer / SEARCH_TIME
	var bar_w := 120.0
	var bar_h := 12.0
	var bx: float = sw * 0.5 - bar_w * 0.5
	var by: float = sh * 0.5 + 40.0

	draw_rect(Rect2(bx - 2, by - 2, bar_w + 4, bar_h + 4), Color(0.0, 0.0, 0.0, 0.7))
	draw_rect(Rect2(bx, by, bar_w * progress, bar_h), Color(0.9, 0.8, 0.3, 0.9))

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(bx, by - 8), "Searching...", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_HUD_TEXT)


func _draw_search_msg() -> void:
	var font := ThemeDB.fallback_font
	var a: float = clampf(search_msg_timer, 0.0, 1.0)
	var col := COL_ITEM_GLOW
	if search_msg.begins_with("Nothing") or search_msg.begins_with("Already"):
		col = Color(0.6, 0.6, 0.6)
	col.a = a
	var y_off: float = -20.0 * (1.0 - a)
	draw_string(font, Vector2(sw * 0.5 - 80, sh * 0.5 - 20 + y_off), search_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)


func _draw_caught() -> void:
	var a: float = clampf(caught_timer * 0.8, 0.0, 0.85)
	draw_rect(Rect2(0, 0, sw, sh), Color(0.3, 0.0, 0.0, a))

	if caught_timer > 0.5:
		var font := ThemeDB.fallback_font
		var text_a: float = clampf((caught_timer - 0.5) * 2.0, 0.0, 1.0)

		var y: float = sh * 0.35
		draw_string(font, Vector2(sw * 0.5 - 100, y), "YOU DIDN'T SURVIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.9, 0.1, 0.1, text_a))

		y += 50
		draw_string(font, Vector2(sw * 0.5 - 80, y), "Score: %d" % points, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.9, 0.9, text_a))

		y += 35
		draw_string(font, Vector2(sw * 0.5 - 80, y), "Items: %d/%d" % [items_found, ITEM_COUNT], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.8, 0.8, text_a))

		y += 35
		var time_survived: String = "%d:%02d" % [int(game_time) / 60, int(game_time) % 60]
		draw_string(font, Vector2(sw * 0.5 - 80, y), "Survived: " + time_survived, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.8, 0.8, text_a))

		if caught_timer > 2.0:
			var tap_a: float = 0.5 + 0.5 * sin(caught_timer * 3.0)
			draw_string(font, Vector2(sw * 0.5 - 60, sh * 0.75), "Tap to continue", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.7, tap_a))


func _draw_escaped() -> void:
	var a: float = clampf(escaped_timer * 0.6, 0.0, 0.8)
	draw_rect(Rect2(0, 0, sw, sh), Color(0.0, 0.05, 0.15, a))

	if escaped_timer > 0.5:
		var font := ThemeDB.fallback_font
		var text_a: float = clampf((escaped_timer - 0.5) * 2.0, 0.0, 1.0)

		var y: float = sh * 0.3
		var msg := "YOU ESCAPED!"
		if game_time >= GAME_DURATION and items_found < ITEM_COUNT:
			msg = "YOU SURVIVED TILL DAWN!"
		draw_string(font, Vector2(sw * 0.5 - 120, y), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.2, 0.9, 0.3, text_a))

		y += 50
		draw_string(font, Vector2(sw * 0.5 - 80, y), "Score: %d" % points, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.95, 0.5, text_a))

		y += 40
		draw_string(font, Vector2(sw * 0.5 - 80, y), "Items: %d/%d" % [items_found, ITEM_COUNT], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.8, 0.8, text_a))

		if escaped_timer > 2.0:
			var tap_a: float = 0.5 + 0.5 * sin(escaped_timer * 3.0)
			draw_string(font, Vector2(sw * 0.5 - 60, sh * 0.75), "Tap to continue", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.7, tap_a))


func _draw_title() -> void:
	# Dark background
	draw_rect(Rect2(0, 0, sw, sh), Color(0.02, 0.03, 0.02))

	var font := ThemeDB.fallback_font

	# Moon
	var moon_y: float = sh * 0.2 + sin(title_timer * 0.3) * 8.0
	draw_circle(Vector2(sw * 0.5, moon_y), 40.0, Color(0.9, 0.88, 0.7, 0.7))
	draw_circle(Vector2(sw * 0.5 + 8, moon_y - 5), 35.0, Color(0.02, 0.03, 0.02))  # Crescent

	# Trees silhouette
	for i in range(12):
		var tx: float = float(i) * sw / 11.0
		var th: float = 60.0 + sin(float(i) * 1.7) * 25.0
		var tree_col := Color(0.02, 0.06, 0.02)
		draw_rect(Rect2(tx - 3, sh * 0.55 - th, 6, th), tree_col)
		draw_circle(Vector2(tx, sh * 0.55 - th), 18.0 + sin(float(i) * 2.3) * 6.0, tree_col)

	# Title
	var title_y: float = sh * 0.42
	draw_string(font, Vector2(sw * 0.5 - 140, title_y), "SURVIVE TILL DAWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(0.9, 0.1, 0.1, 0.9))

	# Subtitle
	draw_string(font, Vector2(sw * 0.5 - 100, title_y + 35), "Camp Crystal Lake", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.5, 0.5, 0.5, 0.8))

	# Instructions
	var inst_y: float = sh * 0.62
	var inst_col := Color(0.7, 0.7, 0.7, 0.7)
	draw_string(font, Vector2(sw * 0.5 - 130, inst_y), "Tap nearby to sneak, far to sprint", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, inst_col)
	draw_string(font, Vector2(sw * 0.5 - 130, inst_y + 24), "Search cabins for 5 escape items", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, inst_col)
	draw_string(font, Vector2(sw * 0.5 - 130, inst_y + 48), "Sprinting makes noise — Jason hears!", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.7, 0.3, 0.7))
	draw_string(font, Vector2(sw * 0.5 - 130, inst_y + 72), "Your flashlight is dying...", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.7, 0.5, 0.7))
	draw_string(font, Vector2(sw * 0.5 - 130, inst_y + 96), "Don't let Jason catch you!", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.3, 0.3, 0.7))

	# Best score
	if _best_score > 0:
		draw_string(font, Vector2(sw * 0.5 - 60, sh * 0.85), "Best: %d" % _best_score, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.6, 0.4, 0.6))

	# Tap to start
	var tap_a: float = 0.5 + 0.5 * sin(title_timer * 2.5)
	draw_string(font, Vector2(sw * 0.5 - 50, sh * 0.92), "TAP TO START", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.9, 0.9, tap_a))
