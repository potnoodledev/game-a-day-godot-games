extends Node2D

# THIRD SPACE — A liminal experience v2
# Walk through empty spaces. Something isn't right.

# === CONSTANTS ===
const UNEASE_BASE := 0.008
const UNEASE_LINGER := 0.005
const UNEASE_RELIEF := 0.04
const ROOM_TYPES := 8
const PLAYER_SPEED := 0.45  # depth-units per second
const STEP_INTERVAL := 0.35

# === STATE ===
var game_state := 0  # 0=title, 1=playing, 2=transition, 3=gameover
var score := 0
var best_score := 0
var state_timer := 0.0

# === SCREEN ===
var sw := 800.0
var sh := 600.0

# === ROOM ===
var room_type := 0
var room_time := 0.0
var room_seed := 0
var rooms_visited := 0
var last_types: Array[int] = []
var type_counts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]

# === PLAYER ===
var player_depth := 0.15   # 0=near, 1=far
var player_lateral := 0.5  # 0=left, 1=right
var player_target_depth := 0.15
var player_target_lateral := 0.5
var player_moving := false
var target_door := -1

# === DOORS ===
var doors: Array = []
var entered_from := ""  # side player entered from
var door_fade: Array[float] = []  # per-door fade alpha (1=visible, 0=gone)
var door_will_vanish: Array[bool] = []  # pre-decided at room setup
var doors_vanishing := false  # triggered when player approaches any door

# === PERSPECTIVE ===
var btl := Vector2.ZERO
var btr := Vector2.ZERO
var bbl := Vector2.ZERO
var bbr := Vector2.ZERO
var stretch := 0.0  # corridor stretch amount

# === ATMOSPHERE ===
var unease := 0.0
var flicker_timer := 0.0
var flicker_on := true
var wobble := Vector2.ZERO
var breath := 0.0

# === AMBIENT EVENTS ===
var event_timer := 5.0
var event_type := -1  # -1=none, 0=shadow, 1=light_out, 2=handle_jiggle, 3=wall_breathe, 4=peripheral
var event_progress := 0.0
var event_data := Vector2.ZERO  # generic x,y for event positioning

# === ANOMALIES ===
var has_anomaly := false
var anomaly_type := 0  # 0=wrong_label, 1=upside_door, 2=same_numbers, 3=footprints, 4=impossible_window

# === CLOSING DOOR ===
var close_door_timer := 0.0

# === DEJA VU ===
var deja_vu_alpha := 0.0
var deja_vu_text := ""

# === WHISPERS ===
var wh_text := ""
var wh_alpha := 0.0
var wh_timer := 8.0
var wh_pos := Vector2.ZERO

const WHISPERS := [
	"have you been here before?",
	"the exit was here",
	"someone was just here",
	"this isn't right",
	"keep walking",
	"don't look back",
	"the lights are watching",
	"you can hear the hum",
	"which floor is this?",
	"the walls are warm",
	"there's no one here",
	"you've passed this door",
	"was that a shadow?",
	"the air tastes stale",
	"everything looks the same",
	"you should have turned left",
	"the floor is sticky",
	"where does that sound come from?",
	"the ceiling is lower here",
	"nobody works here anymore",
]

# === TRANSITION ===
var tr_alpha := 0.0
var tr_phase := 0
var tr_target := 0

# === FOOTPRINTS ===
# Each: {pos: Vector2, angle: float, is_left: bool, age: float}
var footprints: Array[Dictionary] = []
var footprint_timer := 0.0
var next_foot_left := true  # alternate left/right

# === ROOM CONFIGS: [depth, width_factor, ceiling_pct] ===
var _cfg := [
	[0.55, 0.32, 0.34],  # 0 HALLWAY
	[0.38, 0.52, 0.28],  # 1 POOL
	[0.44, 0.44, 0.36],  # 2 OFFICE
	[0.58, 0.28, 0.34],  # 3 HOTEL
	[0.34, 0.38, 0.30],  # 4 STAIRWELL
	[0.42, 0.60, 0.24],  # 5 MALL
	[0.48, 0.48, 0.40],  # 6 PARKING
	[0.32, 0.34, 0.34],  # 7 BATHROOM
]

# === PALETTES: [floor, wall, ceiling, back, accent] ===
var _pal := [
	[Color(0.72,0.68,0.55), Color(0.82,0.78,0.68), Color(0.78,0.75,0.66), Color(0.75,0.72,0.62), Color(0.60,0.55,0.42)],
	[Color(0.62,0.72,0.75), Color(0.78,0.80,0.76), Color(0.74,0.74,0.70), Color(0.65,0.70,0.72), Color(0.45,0.55,0.58)],
	[Color(0.52,0.52,0.50), Color(0.76,0.74,0.70), Color(0.68,0.68,0.65), Color(0.72,0.70,0.66), Color(0.45,0.48,0.42)],
	[Color(0.48,0.28,0.22), Color(0.72,0.65,0.55), Color(0.68,0.62,0.52), Color(0.65,0.58,0.48), Color(0.55,0.40,0.28)],
	[Color(0.58,0.56,0.52), Color(0.62,0.60,0.57), Color(0.60,0.58,0.55), Color(0.58,0.56,0.53), Color(0.48,0.46,0.42)],
	[Color(0.76,0.73,0.65), Color(0.83,0.80,0.73), Color(0.78,0.76,0.70), Color(0.80,0.77,0.70), Color(0.58,0.53,0.42)],
	[Color(0.38,0.38,0.40), Color(0.46,0.46,0.48), Color(0.42,0.42,0.44), Color(0.44,0.44,0.46), Color(0.32,0.32,0.34)],
	[Color(0.80,0.80,0.78), Color(0.86,0.86,0.84), Color(0.83,0.83,0.81), Color(0.84,0.84,0.82), Color(0.68,0.68,0.66)],
]

var _names := ["hallway", "pool room", "office", "hotel corridor", "stairwell", "mall atrium", "parking garage", "bathroom"]

# === AUDIO ===
var hum_player: AudioStreamPlayer
var step_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer
var step_stream: AudioStreamWAV
var drip_stream: AudioStreamWAV
var ding_stream: AudioStreamWAV
var ambient_timer := 12.0

# ─────────────────────────── LIFECYCLE ───────────────────────────

func _ready() -> void:
	_make_hum()
	_make_step_sound()
	_make_ambient_sounds()
	Api.load_state(func(ok: bool, data: Variant) -> void:
		if ok and data and data.has("data"):
			best_score = data["data"].get("points", 0)
			score = best_score
	)

func _get_ss() -> Vector2:
	return get_viewport().get_visible_rect().size

# ─────────────────────────── AUDIO GENERATION ───────────────────────────

func _make_hum() -> void:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 22050
	var d := PackedByteArray()
	d.resize(22050 * 2)
	for i in 22050:
		var t := float(i) / 22050.0
		var s := sin(t * 120.0 * TAU) * 0.2
		s += sin(t * 240.0 * TAU) * 0.1
		s += sin(t * 60.0 * TAU) * 0.06
		s += randf_range(-0.01, 0.01)
		var v := int(s * 2500)
		d[i * 2] = v & 0xFF
		d[i * 2 + 1] = (v >> 8) & 0xFF
	stream.data = d
	hum_player = AudioStreamPlayer.new()
	hum_player.stream = stream
	hum_player.volume_db = -24.0
	add_child(hum_player)

func _make_step_sound() -> void:
	step_stream = AudioStreamWAV.new()
	step_stream.format = AudioStreamWAV.FORMAT_16_BITS
	step_stream.mix_rate = 22050
	step_stream.stereo = false
	var samples := 1800  # ~80ms
	var d := PackedByteArray()
	d.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(samples)
		var env := (1.0 - t) * (1.0 - t)  # quick decay
		var s := sin(t * 180.0 * TAU) * 0.15 * env
		s += randf_range(-0.08, 0.08) * env  # noise component
		var v := int(s * 4000)
		d[i * 2] = v & 0xFF
		d[i * 2 + 1] = (v >> 8) & 0xFF
	step_stream.data = d
	step_player = AudioStreamPlayer.new()
	step_player.stream = step_stream
	step_player.volume_db = -14.0
	add_child(step_player)

func _make_ambient_sounds() -> void:
	# Water drip
	drip_stream = AudioStreamWAV.new()
	drip_stream.format = AudioStreamWAV.FORMAT_16_BITS
	drip_stream.mix_rate = 22050
	drip_stream.stereo = false
	var samples := 4000
	var d := PackedByteArray()
	d.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(samples)
		var env := exp(-t * 8.0)
		var s := sin(t * 800.0 * TAU * (1.0 - t * 0.3)) * 0.2 * env
		var v := int(s * 3000)
		d[i * 2] = v & 0xFF
		d[i * 2 + 1] = (v >> 8) & 0xFF
	drip_stream.data = d

	# Distant ding
	ding_stream = AudioStreamWAV.new()
	ding_stream.format = AudioStreamWAV.FORMAT_16_BITS
	ding_stream.mix_rate = 22050
	ding_stream.stereo = false
	samples = 11025  # 0.5s
	d = PackedByteArray()
	d.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(samples)
		var env := exp(-t * 3.0)
		var s := sin(t * 1200.0 * TAU) * 0.12 * env
		s += sin(t * 1800.0 * TAU) * 0.06 * env
		var v := int(s * 2000)
		d[i * 2] = v & 0xFF
		d[i * 2 + 1] = (v >> 8) & 0xFF
	ding_stream.data = d

	ambient_player = AudioStreamPlayer.new()
	ambient_player.volume_db = -18.0
	add_child(ambient_player)

func _play_ambient() -> void:
	if ambient_player.playing:
		return
	if randf() < 0.6:
		ambient_player.stream = drip_stream
		ambient_player.volume_db = lerpf(-22.0, -12.0, unease)
	else:
		ambient_player.stream = ding_stream
		ambient_player.volume_db = lerpf(-26.0, -16.0, unease)
	ambient_player.play()

# ─────────────────────────── FLOOR COORDINATE SYSTEM ───────────────────────────

func _floor_to_screen(depth: float, lateral: float) -> Vector2:
	var y := lerpf(sh, bbl.y, depth)
	var l := lerpf(0.0, bbl.x, depth)
	var r := lerpf(sw, bbr.x, depth)
	var x := lerpf(l, r, lateral)
	return Vector2(x, y)

func _screen_to_floor(pos: Vector2) -> Vector2:
	# Returns Vector2(depth, lateral)
	var depth := clampf((sh - pos.y) / maxf(sh - bbl.y, 1.0), 0.0, 1.0)
	var l := lerpf(0.0, bbl.x, depth)
	var r := lerpf(sw, bbr.x, depth)
	var lateral := clampf((pos.x - l) / maxf(r - l, 1.0), 0.0, 1.0)
	return Vector2(depth, lateral)

# ─────────────────────────── ROOM SETUP ───────────────────────────

func _setup_room(type: int) -> void:
	room_type = type
	room_time = 0.0
	room_seed = randi()
	stretch = 0.0
	footprints.clear()
	footprint_timer = 0.0
	next_foot_left = true
	door_fade.clear()
	door_will_vanish.clear()
	doors_vanishing = false

	# Player starts near entrance
	player_depth = 0.12
	player_lateral = 0.5
	player_target_depth = player_depth
	player_target_lateral = player_lateral
	player_moving = false
	target_door = -1

	# Anomaly check
	has_anomaly = unease > 0.4 and randf() < unease * 0.6
	anomaly_type = randi() % 5

	# Closing door animation
	close_door_timer = 1.2

	# Déjà vu check
	type_counts[type] += 1
	if type_counts[type] > 1:
		deja_vu_alpha = 1.0
		var msgs := ["haven't I been here before?", "this looks familiar...", "I remember this place.", "wait... again?", "déjà vu."]
		deja_vu_text = msgs[randi() % msgs.size()]
	else:
		deja_vu_alpha = 0.0

	# Reset event
	event_type = -1
	event_timer = randf_range(2.0, 5.0)

	_calc_perspective()
	_gen_doors()
	# Init door fade — all visible at start
	for i in doors.size():
		door_fade.append(1.0)
		door_will_vanish.append(false)
	# Pre-decide which doors vanish (at least one must survive)
	if unease > 0.1 and doors.size() > 1:
		# Pick one random door to be the safe one
		var safe_door := randi() % doors.size()
		for i in doors.size():
			if i == safe_door:
				continue
			# Higher unease = more doors vanish
			if randf() < 0.4 + unease * 0.4:
				door_will_vanish[i] = true

func _calc_perspective() -> void:
	var c: Array = _cfg[room_type]
	var depth: float = float(c[0]) + stretch
	var wf: float = float(c[1])
	var ceil_pct: float = float(c[2])

	var d := unease * 0.05
	depth += randf_range(-d, d) * 0.1  # tiny random per recalc
	wf += randf_range(-d * 0.2, d * 0.2) * 0.1

	var cx := sw * 0.5
	var cy := sh * ceil_pct
	var bw := sw * wf
	var bh := sh * (1.0 - depth) * 0.55

	btl = Vector2(cx - bw * 0.5, cy)
	btr = Vector2(cx + bw * 0.5, cy)
	bbl = Vector2(cx - bw * 0.5, cy + bh)
	bbr = Vector2(cx + bw * 0.5, cy + bh)

func _wall_point(side: String, depth_t: float, vert_t: float) -> Vector2:
	# Get a point on a wall surface. depth_t: 0=near, 1=far. vert_t: 0=top, 1=bottom.
	if side == "left":
		var x := lerpf(0.0, btl.x, depth_t)
		var yt := lerpf(0.0, btl.y, depth_t)
		var yb := lerpf(sh, bbl.y, depth_t)
		return Vector2(x, lerpf(yt, yb, vert_t))
	else:  # right
		var x := lerpf(sw, btr.x, depth_t)
		var yt := lerpf(0.0, btr.y, depth_t)
		var yb := lerpf(sh, bbr.y, depth_t)
		return Vector2(x, lerpf(yt, yb, vert_t))

func _gen_doors() -> void:
	doors.clear()
	var back_cx := (btl.x + btr.x) * 0.5
	var dw := (btr.x - btl.x) * 0.25
	var dh := (bbl.y - btl.y) * 0.6
	var dy := bbl.y - dh

	# Back door (always)
	doors.append({
		"rect": Rect2(back_cx - dw * 0.5, dy, dw, dh),
		"side": "back", "target": _pick_room(),
		"depth": 0.95, "lateral": 0.5,
		"quad": PackedVector2Array(),  # empty = use rect
	})

	var sides := randi_range(0, 2)
	if entered_from == "left":
		sides = mini(sides, 1)
	if entered_from == "right":
		sides = mini(sides, 1)

	if sides >= 1:
		var dp := randf_range(0.35, 0.6)
		var d_half := 0.08  # door width in depth-space
		var d_near := dp - d_half
		var d_far := dp + d_half
		var v_top := 0.35   # door occupies lower portion of wall
		var v_bot := 0.92
		# Compute perspective quad on left wall
		var q := PackedVector2Array([
			_wall_point("left", d_near, v_top),  # near-top
			_wall_point("left", d_far, v_top),   # far-top
			_wall_point("left", d_far, v_bot),   # far-bottom
			_wall_point("left", d_near, v_bot),  # near-bottom
		])
		# Hit rect = bounding box of quad
		var minx := minf(q[0].x, q[1].x)
		var maxx := maxf(q[3].x, q[2].x)
		var miny := minf(q[0].y, q[1].y)
		var maxy := maxf(q[2].y, q[3].y)
		doors.append({
			"rect": Rect2(minx, miny, maxx - minx, maxy - miny),
			"side": "left", "target": _pick_room(),
			"depth": dp, "lateral": 0.05,
			"quad": q,
		})
	if sides >= 2:
		var dp := randf_range(0.35, 0.6)
		var d_half := 0.08
		var d_near := dp - d_half
		var d_far := dp + d_half
		var v_top := 0.35
		var v_bot := 0.92
		var q := PackedVector2Array([
			_wall_point("right", d_near, v_top),
			_wall_point("right", d_far, v_top),
			_wall_point("right", d_far, v_bot),
			_wall_point("right", d_near, v_bot),
		])
		var minx := minf(q[0].x, q[1].x)
		var maxx := maxf(q[3].x, q[2].x)
		var miny := minf(q[0].y, q[1].y)
		var maxy := maxf(q[2].y, q[3].y)
		doors.append({
			"rect": Rect2(minx, miny, maxx - minx, maxy - miny),
			"side": "right", "target": _pick_room(),
			"depth": dp, "lateral": 0.95,
			"quad": q,
		})

func _pick_room() -> int:
	if unease > 0.4 and randf() < unease * 0.4 and last_types.size() > 0:
		return last_types[randi() % last_types.size()]
	var r := randi() % ROOM_TYPES
	if r == room_type and randf() > 0.2:
		r = (r + randi_range(1, ROOM_TYPES - 1)) % ROOM_TYPES
	return r

# ─────────────────────────── GAME FLOW ───────────────────────────

func _start_game() -> void:
	game_state = 1
	state_timer = 0.0
	score = 0
	unease = 0.0
	rooms_visited = 0
	last_types.clear()
	for i in ROOM_TYPES:
		type_counts[i] = 0
	flicker_on = true
	wh_alpha = 0.0
	wh_timer = randf_range(5, 10)
	wobble = Vector2.ZERO
	entered_from = ""
	_setup_room(randi() % ROOM_TYPES)
	if hum_player:
		hum_player.play()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var pos: Vector2 = event.position
		if game_state == 0:
			_start_game()
			return
		if game_state == 3 and state_timer > 1.5:
			game_state = 0
			return
		if game_state == 1:
			# Check door taps first
			for i in doors.size():
				# Skip vanished doors
				if i < door_fade.size() and door_fade[i] < 0.1:
					continue
				var r: Rect2 = doors[i]["rect"]
				if r.grow(20).has_point(pos):
					_walk_to_door(i)
					return
			# Otherwise walk to tapped floor position
			if pos.y > bbl.y * 0.8:  # on floor area
				var fl := _screen_to_floor(pos)
				player_target_depth = fl.x
				player_target_lateral = fl.y
				player_moving = true
				target_door = -1

func _walk_to_door(idx: int) -> void:
	var door: Dictionary = doors[idx]
	player_target_depth = float(door["depth"])
	player_target_lateral = float(door["lateral"])
	player_moving = true
	target_door = idx

func _enter_door(idx: int) -> void:
	var door: Dictionary = doors[idx]
	tr_target = int(door["target"])
	# Track which side we're entering FROM (opposite of door side)
	match String(door["side"]):
		"back": entered_from = "back"
		"left": entered_from = "right"
		"right": entered_from = "left"
		_: entered_from = ""
	tr_alpha = 0.0
	tr_phase = 0
	game_state = 2
	player_moving = false
	target_door = -1

# ─────────────────────────── PROCESS ───────────────────────────

func _process(delta: float) -> void:
	var vp := _get_ss()
	sw = vp.x; sh = vp.y
	state_timer += delta

	match game_state:
		0: breath += delta * 0.5
		1: _tick_playing(delta)
		2: _tick_transition(delta)
	queue_redraw()

func _tick_playing(delta: float) -> void:
	room_time += delta
	breath += delta * (0.5 + unease * 2.0)

	# === PLAYER MOVEMENT ===
	if player_moving:
		var dd := player_target_depth - player_depth
		var dl := player_target_lateral - player_lateral
		var dist := sqrt(dd * dd + dl * dl)
		if dist < 0.02:
			player_depth = player_target_depth
			player_lateral = player_target_lateral
			player_moving = false
			if target_door >= 0:
				_enter_door(target_door)
				return
		else:
			var spd := PLAYER_SPEED * delta
			var move := minf(spd, dist)
			player_depth += dd / dist * move
			player_lateral += dl / dist * move

			# Footstep sound + footprint
			footprint_timer -= delta
			if footprint_timer <= 0:
				footprint_timer = STEP_INTERVAL
				if step_player and not step_player.playing:
					step_player.pitch_scale = randf_range(0.85, 1.15)
					step_player.play()
				# Alternating left/right shoe prints
				var fp := _floor_to_screen(player_depth, player_lateral)
				var walk_angle := atan2(dd, dl)
				var side_offset := lerpf(6.0, 2.0, player_depth)  # smaller when further
				var perp := Vector2(-sin(walk_angle), cos(walk_angle)) * side_offset
				if next_foot_left:
					fp -= perp
				else:
					fp += perp
				footprints.append({"pos": fp, "angle": walk_angle, "is_left": next_foot_left, "age": 0.0})
				next_foot_left = not next_foot_left
				if footprints.size() > 30:
					footprints.remove_at(0)

	# === DOOR VANISHING ===
	# Trigger vanishing when player moves past a depth threshold (committed to walking)
	if not doors_vanishing and player_depth > 0.25:
		doors_vanishing = true

	# Fade doomed doors
	if doors_vanishing:
		for i in doors.size():
			if i >= door_fade.size() or i >= door_will_vanish.size():
				break
			if door_will_vanish[i]:
				door_fade[i] = maxf(door_fade[i] - delta * 1.5, 0.0)
			# Cancel walk toward vanished door
			if target_door == i and door_fade[i] < 0.1:
				target_door = -1
				player_moving = false

	# === CORRIDOR STRETCH ===
	if player_moving and target_door >= 0 and target_door < doors.size():
		var door: Dictionary = doors[target_door]
		if String(door["side"]) == "back" and player_depth > 0.3:
			stretch = minf(stretch + delta * 0.04, 0.12)
			_calc_perspective()
			# Update back door rect to match new perspective (don't regenerate all doors)
			var back_cx := (btl.x + btr.x) * 0.5
			var dw := (btr.x - btl.x) * 0.25
			var dh := (bbl.y - btl.y) * 0.6
			var dy := bbl.y - dh
			doors[0]["rect"] = Rect2(back_cx - dw * 0.5, dy, dw, dh)

	# === FOOTPRINT AGING ===
	for fp in footprints:
		fp["age"] += delta

	# === UNEASE ===
	var rate := UNEASE_BASE + room_time * UNEASE_LINGER
	if not player_moving:
		rate *= 1.5  # standing still = more unease
	unease = minf(unease + rate * delta, 1.0)

	# === FLICKER (subtle dim, not full on/off) ===
	flicker_timer -= delta
	if flicker_timer <= 0.0:
		if unease > 0.5:
			# Gentle dim — never goes below 0.7 brightness
			flicker_on = not flicker_on
			flicker_timer = randf_range(0.3, 0.8)
		else:
			flicker_on = true
			flicker_timer = randf_range(2.0, 5.0)

	# === WOBBLE ===
	if unease > 0.45:
		var i := (unease - 0.45) * 5.0
		wobble = Vector2(sin(state_timer * 7.3) * i, cos(state_timer * 5.1) * i * 0.6)
	else:
		wobble = Vector2.ZERO

	# === AMBIENT EVENTS ===
	event_timer -= delta
	if event_timer <= 0.0 and event_type < 0:
		event_type = randi() % 5
		event_progress = 0.0
		event_data = Vector2(randf_range(0.2, 0.8), randf_range(0.3, 0.7))
	if event_type >= 0:
		event_progress += delta
		var duration := 2.5 if event_type != 1 else 1.5
		if event_progress > duration:
			event_type = -1
			event_timer = randf_range(3.0, 8.0) / (1.0 + unease * 2.0)
			flicker_on = true  # restore light if event 1

	# === CLOSING DOOR ===
	if close_door_timer > 0:
		close_door_timer -= delta

	# === DEJA VU ===
	if deja_vu_alpha > 0:
		deja_vu_alpha = maxf(deja_vu_alpha - delta * 0.3, 0.0)

	# === WHISPERS ===
	wh_timer -= delta
	if wh_timer <= 0.0 and unease > 0.2:
		wh_text = WHISPERS[randi() % WHISPERS.size()]
		wh_alpha = 1.0
		wh_pos = Vector2(randf_range(sw * 0.15, sw * 0.85), randf_range(sh * 0.2, sh * 0.75))
		wh_timer = randf_range(3.0, 7.0) / (1.0 + unease * 2.0)
	if wh_alpha > 0.0:
		wh_alpha = maxf(wh_alpha - delta * 0.25, 0.0)

	# === AMBIENT SOUND ===
	ambient_timer -= delta
	if ambient_timer <= 0.0:
		_play_ambient()
		ambient_timer = randf_range(6.0, 15.0) / (1.0 + unease)

	# === HUM VOLUME ===
	if hum_player:
		hum_player.volume_db = lerpf(-24.0, -6.0, unease)

	# === GAME OVER ===
	if unease >= 1.0:
		game_state = 3
		state_timer = 0.0
		best_score = maxi(best_score, score)
		Api.submit_score(score, func(_ok: bool, _r: Variant) -> void: pass)
		Api.save_state(0, {"points": best_score}, func(_ok: bool, _r: Variant) -> void: pass)
		if hum_player:
			hum_player.stop()

func _tick_transition(delta: float) -> void:
	if tr_phase == 0:
		tr_alpha += delta * 3.0
		if tr_alpha >= 1.0:
			tr_alpha = 1.0
			tr_phase = 1
			last_types.append(room_type)
			if last_types.size() > 6:
				last_types.remove_at(0)
			_setup_room(tr_target)
			rooms_visited += 1
			score = rooms_visited
			unease = maxf(unease - UNEASE_RELIEF, 0.0)
	else:
		tr_alpha -= delta * 2.0
		if tr_alpha <= 0.0:
			tr_alpha = 0.0
			game_state = 1

# ─────────────────────────── DRAWING ───────────────────────────

func _draw() -> void:
	match game_state:
		0: _draw_title()
		1:
			_draw_room(wobble)
			_draw_details(wobble)
			_draw_anomaly(wobble)
			_draw_footprints(wobble)
			_draw_doors(wobble)
			_draw_player_shadow(wobble)
			_draw_events(wobble)
			_draw_close_door()
			_draw_fx()
			_draw_hud()
		2:
			_draw_room(wobble)
			_draw_details(wobble)
			_draw_doors(wobble)
			_draw_player_shadow(wobble)
			_draw_fx()
			_draw_hud()
			_draw_trans()
		3:
			_draw_room(Vector2.ZERO)
			_draw_fx()
			_draw_gameover()

# ---- Title ----

func _draw_title() -> void:
	var save_type := room_type
	room_type = 0
	var c: Array = _cfg[0]
	var cx := sw * 0.5
	var cy := sh * float(c[2])
	var bw := sw * float(c[1])
	var bh := sh * (1.0 - float(c[0])) * 0.55
	btl = Vector2(cx - bw * 0.5, cy)
	btr = Vector2(cx + bw * 0.5, cy)
	bbl = Vector2(cx - bw * 0.5, cy + bh)
	bbr = Vector2(cx + bw * 0.5, cy + bh)
	_draw_room(Vector2.ZERO)
	_draw_details(Vector2.ZERO)
	room_type = save_type

	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, 0.55))

	var ccx := sw * 0.5
	var pulse := 0.6 + sin(breath * 2.0) * 0.2
	_txt(Vector2(ccx, sh * 0.22), "THIRD SPACE", 34, Color(0.95, 0.92, 0.82, pulse))
	_txt(Vector2(ccx, sh * 0.22 + 38), "a liminal experience", 16, Color(0.8, 0.78, 0.72, 0.45))

	_txt(Vector2(ccx, sh * 0.44), "Tap to walk. Find doors to go deeper.", 14, Color(0.8, 0.8, 0.75, 0.4))
	_txt(Vector2(ccx, sh * 0.44 + 22), "Don't stay too long.", 14, Color(0.8, 0.8, 0.75, 0.3))

	var ta := 0.3 + sin(breath * 3.0) * 0.2
	_txt(Vector2(ccx, sh * 0.64), "TAP TO ENTER", 24, Color(0.95, 0.92, 0.82, ta))
	if best_score > 0:
		_txt(Vector2(ccx, sh * 0.64 + 30), "deepest: " + str(best_score) + " rooms", 14, Color(0.8, 0.8, 0.75, 0.3))

# ---- Room base geometry ----

func _shift_color(c: Color) -> Color:
	var s := unease * 0.35
	return Color(
		lerpf(c.r, c.r * 0.8 + 0.15, s),
		lerpf(c.g, c.g * 0.85 + 0.1, s),
		lerpf(c.b, c.b * 0.6, s),
		c.a
	)

func _draw_room(o: Vector2) -> void:
	var p: Array = _pal[room_type]
	var floor_c := _shift_color(p[0] as Color)
	var wall_c := _shift_color(p[1] as Color)
	var ceil_c := _shift_color(p[2] as Color)
	var back_c := _shift_color(p[3] as Color)

	var bright := 1.0 if flicker_on else randf_range(0.7, 0.85)
	floor_c = floor_c * bright
	wall_c = wall_c * bright
	ceil_c = ceil_c * bright
	back_c = back_c * bright

	# Wall breathing at high unease
	var breathe := Vector2.ZERO
	if event_type == 3 and event_progress < 2.5:
		var p2 := sin(event_progress * 4.0) * 3.0
		breathe = Vector2(p2, p2 * 0.5)

	var _btl := btl + breathe * Vector2(-1, -1)
	var _btr := btr + breathe * Vector2(1, -1)
	var _bbl := bbl + breathe * Vector2(-1, 1)
	var _bbr := bbr + breathe * Vector2(1, 1)

	draw_colored_polygon(PackedVector2Array([Vector2(0, 0) + o, Vector2(sw, 0) + o, _btr + o, _btl + o]), ceil_c)
	draw_colored_polygon(PackedVector2Array([Vector2(0, sh) + o, Vector2(sw, sh) + o, _bbr + o, _bbl + o]), floor_c)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0) + o, _btl + o, _bbl + o, Vector2(0, sh) + o]), wall_c)
	draw_colored_polygon(PackedVector2Array([Vector2(sw, 0) + o, _btr + o, _bbr + o, Vector2(sw, sh) + o]), wall_c)
	draw_colored_polygon(PackedVector2Array([_btl + o, _btr + o, _bbr + o, _bbl + o]), back_c)

	var edge_c := Color(0, 0, 0, 0.08)
	draw_line(_btl + o, Vector2(0, 0) + o, edge_c, 1.5)
	draw_line(_btr + o, Vector2(sw, 0) + o, edge_c, 1.5)
	draw_line(_bbl + o, Vector2(0, sh) + o, edge_c, 1.5)
	draw_line(_bbr + o, Vector2(sw, sh) + o, edge_c, 1.5)
	draw_line(_bbl + o, _bbr + o, Color(0, 0, 0, 0.12), 1.5)
	draw_line(_btl + o, _btr + o, Color(0, 0, 0, 0.06), 1.0)

# ---- Room details ----

func _draw_details(o: Vector2) -> void:
	var bright := 1.0 if flicker_on else randf_range(0.7, 0.85)
	_draw_ceiling_lights(o, bright)
	_draw_floor_pattern(o, bright)
	match room_type:
		0: _draw_hallway(o, bright)
		1: _draw_pool(o, bright)
		2: _draw_office(o, bright)
		3: _draw_hotel(o, bright)
		4: _draw_stairwell(o, bright)
		5: _draw_mall(o, bright)
		6: _draw_parking(o, bright)
		7: _draw_bathroom(o, bright)

func _draw_ceiling_lights(o: Vector2, bright: float) -> void:
	var cx := (btl.x + btr.x) * 0.5
	var bw := btr.x - btl.x
	for i in 3:
		var t := float(i + 1) / 4.0
		var lx := lerpf(sw * 0.5, cx, t)
		var ly := lerpf(0, (btl.y + btr.y) * 0.5, t)
		var lw := lerpf(sw * 0.12, bw * 0.3, t)
		var lh := lerpf(8.0, 3.0, t)

		# Event: light out (one light goes dark)
		var this_bright := bright
		if event_type == 1 and i == 1:
			this_bright *= maxf(0.0, 1.0 - event_progress * 3.0)

		var light_c := Color(0.95, 0.95, 0.88, 0.7 * this_bright)
		draw_rect(Rect2(lx - lw * 0.5 + o.x, ly - lh * 0.5 + o.y, lw, lh), light_c)
		if this_bright > 0.5:
			draw_rect(Rect2(lx - lw * 0.7 + o.x, ly - lh * 2 + o.y, lw * 1.4, lh * 5), Color(1, 0.98, 0.9, 0.06 * this_bright))

func _draw_floor_pattern(o: Vector2, bright: float) -> void:
	var line_c := Color(0, 0, 0, 0.04 * bright)
	for i in 6:
		var t := float(i + 1) / 7.0
		var lx := lerpf(0, bbl.x, t)
		var rx := lerpf(sw, bbr.x, t)
		var ly := lerpf(sh, bbl.y, t)
		draw_line(Vector2(lx, ly) + o, Vector2(rx, ly) + o, line_c, 1.0)
	for i in 5:
		var fx := sw * (float(i + 1) / 6.0)
		var bx := lerpf(bbl.x, bbr.x, float(i + 1) / 6.0)
		draw_line(Vector2(fx, sh) + o, Vector2(bx, bbl.y) + o, line_c, 1.0)

func _draw_hallway(o: Vector2, bright: float) -> void:
	var wh := (bbl.y - btl.y) * 0.65
	draw_line(Vector2(0, sh * 0.6) + o, btl + Vector2(0, wh) + o, Color(0, 0, 0, 0.06 * bright), 1.5)
	draw_line(Vector2(sw, sh * 0.6) + o, btr + Vector2(0, wh) + o, Color(0, 0, 0, 0.06 * bright), 1.5)
	var sign_x := (btl.x + btr.x) * 0.5
	var sign_y := btl.y + (bbl.y - btl.y) * 0.15
	draw_rect(Rect2(sign_x - 12 + o.x, sign_y - 4 + o.y, 24, 8), Color(0.2, 0.8, 0.3, 0.5 * bright))
	_txt(Vector2(sign_x + o.x, sign_y + o.y), "EXIT", 6, Color(1, 1, 1, 0.6 * bright))

func _draw_pool(o: Vector2, bright: float) -> void:
	var pl := lerpf(bbl.x, bbr.x, 0.2)
	var pr := lerpf(bbl.x, bbr.x, 0.8)
	var pt := lerpf(bbl.y, sh, 0.15)
	var pb := lerpf(bbl.y, sh, 0.75)
	draw_rect(Rect2(pl + o.x, pt + o.y, pr - pl, pb - pt), Color(0.4, 0.6, 0.65, 0.2 * bright))
	draw_rect(Rect2(pl + o.x, pt + o.y, pr - pl, pb - pt), Color(0.3, 0.5, 0.55, 0.15 * bright), true, 2)
	var tw := (btr.x - btl.x) / 8.0
	var th := (bbl.y - btl.y) / 5.0
	for i in 9:
		draw_line(Vector2(btl.x + i * tw, btl.y) + o, Vector2(btl.x + i * tw, bbl.y) + o, Color(0, 0, 0, 0.03 * bright), 0.5)
	for i in 6:
		draw_line(Vector2(btl.x, btl.y + i * th) + o, Vector2(btr.x, btl.y + i * th) + o, Color(0, 0, 0, 0.03 * bright), 0.5)

func _draw_office(o: Vector2, bright: float) -> void:
	var cc := Color(0.45, 0.45, 0.42, 0.12 * bright)
	for i in 3:
		var t := float(i + 1) / 4.0
		var top := bbl.lerp(btl, t * 0.5)
		var bot := Vector2(lerpf(0, bbl.x, t * 0.5), lerpf(sh, bbl.y, t * 0.5))
		var rtop := bbr.lerp(btr, t * 0.5)
		var rbot := Vector2(lerpf(sw, bbr.x, t * 0.5), lerpf(sh, bbr.y, t * 0.5))
		draw_line(top + o, bot + o, cc, 2)
		draw_line(rtop + o, rbot + o, cc, 2)
	for i in 5:
		var t := float(i + 1) / 6.0
		var lx := lerpf(0, btl.x, t)
		var rx := lerpf(sw, btr.x, t)
		var y := lerpf(0, btl.y, t)
		draw_line(Vector2(lx, y) + o, Vector2(rx, y) + o, Color(0, 0, 0, 0.03 * bright), 0.5)

func _draw_hotel(o: Vector2, bright: float) -> void:
	var dc := Color(0.45, 0.32, 0.2, 0.15 * bright)
	for i in 4:
		var t := float(i + 1) / 5.0
		var lx := lerpf(0.0, btl.x, t)
		var lb := lerpf(sh, bbl.y, t)
		var lt := lerpf(0.0, btl.y, t)
		var dh := (lb - lt) * 0.45
		var dw := dh * 0.35
		draw_rect(Rect2(lx + o.x, lb - dh + o.y, dw, dh), dc)
		# Room numbers — anomaly: all same number
		var num := str(100 + room_seed % 50 + i)
		if has_anomaly and anomaly_type == 2:
			num = str(100 + room_seed % 50)  # all same
		_txt(Vector2(lx + dw * 0.5 + o.x, lb - dh * 0.85 + o.y), num, 5 + int(t * 3), Color(0.8, 0.75, 0.6, 0.2 * bright))
		var rx := lerpf(sw, btr.x, t)
		var rb := lerpf(sh, bbr.y, t)
		dh = (rb - lerpf(0.0, btr.y, t)) * 0.45
		dw = dh * 0.35
		draw_rect(Rect2(rx - dw + o.x, rb - dh + o.y, dw, dh), dc)
	var sl := lerpf(bbl.x, bbr.x, 0.35)
	var sr := lerpf(bbl.x, bbr.x, 0.65)
	draw_colored_polygon(PackedVector2Array([Vector2(sw*0.35,sh)+o, Vector2(sw*0.65,sh)+o, Vector2(sr,bbl.y)+o, Vector2(sl,bbl.y)+o]), Color(0.55, 0.25, 0.18, 0.08 * bright))

func _draw_stairwell(o: Vector2, bright: float) -> void:
	for i in 6:
		var t := float(i) / 6.0
		var y := lerpf(bbl.y, btl.y, t)
		var indent := (btr.x - btl.x) * t * 0.1
		draw_line(Vector2(btl.x + indent, y) + o, Vector2(btr.x - indent, y) + o, Color(0, 0, 0, 0.08 * bright), 1.5)
	draw_line(Vector2((btl.x + btr.x) * 0.5, btl.y) + o, Vector2(sw * 0.5, sh * 0.5) + o, Color(0.5, 0.5, 0.48, 0.15 * bright), 2.5)
	draw_rect(Rect2(btl.x + 8 + o.x, btl.y + 8 + o.y, 6, 4), Color(0.9, 0.2, 0.1, 0.4 * bright))

func _draw_mall(o: Vector2, bright: float) -> void:
	for i in 4:
		var t := float(i + 1) / 5.0
		var lx := lerpf(sw * 0.15, lerpf(bbl.x, bbr.x, 0.15), t)
		var ly := lerpf(sh, bbl.y, t)
		var lt := lerpf(0, btl.y, t)
		var cw := lerpf(12, 5, t)
		draw_rect(Rect2(lx - cw * 0.5 + o.x, lt + o.y, cw, ly - lt), Color(0.7, 0.68, 0.6, 0.15 * bright))
		var rx := lerpf(sw * 0.85, lerpf(bbl.x, bbr.x, 0.85), t)
		draw_rect(Rect2(rx - cw * 0.5 + o.x, lt + o.y, cw, ly - lt), Color(0.7, 0.68, 0.6, 0.15 * bright))
	var sfw := (btr.x - btl.x) * 0.25
	var sfh := (bbl.y - btl.y) * 0.65
	draw_rect(Rect2(btl.x + 5 + o.x, btl.y + 5 + o.y, sfw, sfh), Color(0.15, 0.18, 0.2, 0.12 * bright))
	draw_rect(Rect2(btr.x - sfw - 5 + o.x, btl.y + 5 + o.y, sfw, sfh), Color(0.15, 0.18, 0.2, 0.12 * bright))

func _draw_parking(o: Vector2, bright: float) -> void:
	for i in 3:
		var t := float(i + 1) / 4.0
		var px := lerpf(sw * 0.25, lerpf(bbl.x, bbr.x, 0.25), t)
		var pt := lerpf(0, btl.y, t)
		var pb := lerpf(sh, bbl.y, t)
		var pw := lerpf(16, 6, t)
		draw_rect(Rect2(px - pw * 0.5 + o.x, pt + o.y, pw, pb - pt), Color(0.35, 0.35, 0.37, 0.2 * bright))
	for i in 4:
		var t := float(i + 1) / 5.0
		var fx := lerpf(sw * 0.6, lerpf(bbl.x, bbr.x, 0.6), t * 0.7)
		var fy := lerpf(sh, bbl.y, t * 0.7)
		draw_line(Vector2(fx, fy) + o, Vector2(fx + lerpf(30, 10, t), fy) + o, Color(1, 1, 1, 0.04 * bright), lerpf(3, 1, t))
	_txt(Vector2((btl.x+btr.x)*0.5+o.x, (btl.y+bbl.y)*0.5+o.y), "P" + str(room_seed % 5 + 1), 12, Color(0.8, 0.8, 0.2, 0.2 * bright))

func _draw_bathroom(o: Vector2, bright: float) -> void:
	var sw_back := btr.x - btl.x
	for i in 4:
		var t := float(i) / 3.0
		var x := btl.x + t * sw_back
		draw_line(Vector2(x, bbl.y) + o, Vector2(x, btl.y + (bbl.y - btl.y) * 0.15) + o, Color(0.6, 0.6, 0.58, 0.12 * bright), 2)
	var mw := sw_back * 0.6
	var mh := (bbl.y - btl.y) * 0.3
	var mx := (btl.x + btr.x) * 0.5 - mw * 0.5
	var my := btl.y + (bbl.y - btl.y) * 0.1
	draw_rect(Rect2(mx + o.x, my + o.y, mw, mh), Color(0.7, 0.75, 0.78, 0.15 * bright))

# ---- Anomalies ----

func _draw_anomaly(o: Vector2) -> void:
	if not has_anomaly:
		return
	var bright := 1.0 if flicker_on else 0.3
	match anomaly_type:
		0:  # Wrong label — handled in _draw_fx (room name display)
			pass
		1:  # Upside-down door on ceiling
			var cx := (btl.x + btr.x) * 0.5
			var cy := btl.y * 0.5
			var dw := (btr.x - btl.x) * 0.15
			var dh := btl.y * 0.3
			draw_rect(Rect2(cx - dw * 0.5 + o.x, cy - dh * 0.5 + o.y, dw, dh), Color(0.3, 0.25, 0.2, 0.25 * bright))
			draw_rect(Rect2(cx - dw * 0.5 + o.x, cy - dh * 0.5 + o.y, dw, dh), Color(0.2, 0.15, 0.1, 0.15), true, 1)
		2:  # Same numbers — handled in _draw_hotel
			pass
		3:  # Pre-existing footprints
			var seed_r := room_seed
			for i in 8:
				seed_r = (seed_r * 1103515245 + 12345) & 0x7FFFFFFF
				var fd := float(seed_r % 1000) / 1000.0 * 0.7 + 0.1
				seed_r = (seed_r * 1103515245 + 12345) & 0x7FFFFFFF
				var fl := float(seed_r % 1000) / 1000.0 * 0.6 + 0.2
				var fp := _floor_to_screen(fd, fl)
				var sz := lerpf(5.0, 2.0, fd)
				draw_circle(fp + o, sz, Color(0.15, 0.12, 0.1, 0.06))
		4:  # Impossible window on back wall showing another room
			var wcx := (btl.x + btr.x) * 0.5
			var wcy := (btl.y + bbl.y) * 0.35
			var ww := (btr.x - btl.x) * 0.3
			var wh := (bbl.y - btl.y) * 0.25
			draw_rect(Rect2(wcx - ww * 0.5 + o.x, wcy + o.y, ww, wh), Color(0.55, 0.65, 0.7, 0.15 * bright))
			draw_rect(Rect2(wcx - ww * 0.5 + o.x, wcy + o.y, ww, wh), Color(0.4, 0.4, 0.38, 0.2), true, 1.5)

# ---- Footprints ----

func _draw_footprints(o: Vector2) -> void:
	for fp in footprints:
		var pos: Vector2 = fp["pos"]
		var angle: float = fp["angle"]
		var is_left: bool = fp["is_left"]
		var age: float = fp["age"]
		var fade := clampf(1.0 - age / 8.0, 0.0, 1.0)  # fade over 8 seconds
		if fade < 0.01:
			continue
		var a := 0.1 * fade
		var col := Color(0.12, 0.10, 0.08, a)
		# Shoe shape: elongated oval (heel + toe)
		var sz := lerpf(5.0, 2.0, clampf(pos.y / sh, 0.0, 1.0))  # smaller when further away
		var fwd := Vector2(cos(angle), sin(angle))
		var side := Vector2(-fwd.y, fwd.x) * (0.3 if is_left else -0.3)
		# Toe
		draw_circle(pos + fwd * sz * 0.5 + side + o, sz * 0.45, col)
		# Heel
		draw_circle(pos - fwd * sz * 0.4 + side + o, sz * 0.35, col)

# ---- Player shadow ----

func _draw_player_shadow(o: Vector2) -> void:
	# Very subtle — just a faint shadow on the floor, you don't see "yourself"
	var pos := _floor_to_screen(player_depth, player_lateral)
	var sz := lerpf(8.0, 3.0, player_depth)
	draw_circle(pos + o, sz, Color(0, 0, 0, 0.06))

	# Subtle tap target indicator when moving
	if player_moving:
		var tgt := _floor_to_screen(player_target_depth, player_target_lateral)
		var pulse := 0.08 + sin(breath * 4.0) * 0.04
		draw_circle(tgt + o, 3.0, Color(1, 1, 1, pulse))

# ---- Doors ----

func _draw_doors(o: Vector2) -> void:
	var bright := 1.0 if flicker_on else randf_range(0.7, 0.85)
	for i in doors.size():
		# Check fade
		var fade := 1.0
		if i < door_fade.size():
			fade = door_fade[i]
		if fade < 0.01:
			continue  # fully vanished

		var door: Dictionary = doors[i]
		var r: Rect2 = door["rect"]
		var q: PackedVector2Array = door["quad"]
		var side: String = door["side"]

		# Proximity glow
		var ddepth := float(door["depth"])
		var dlat := float(door["lateral"])
		var dist := sqrt((player_depth - ddepth) * (player_depth - ddepth) + (player_lateral - dlat) * (player_lateral - dlat))
		var proximity_glow := clampf(1.0 - dist * 3.0, 0.0, 0.3)
		var pulse := proximity_glow + 0.1 + sin(breath * 2.0 + float(i) * 1.5) * 0.06

		# Apply fade to all alphas
		var f_bright := bright * fade
		var f_pulse := pulse * fade

		if q.size() == 4:
			# Perspective quad for side doors
			var oq := PackedVector2Array()
			for p in q:
				oq.append(p + o)
			# Frame
			draw_colored_polygon(oq, Color(0.35, 0.30, 0.25, 0.6 * f_bright))
			# Dark interior (inset quad)
			var center := (q[0] + q[1] + q[2] + q[3]) * 0.25
			var inner_q := PackedVector2Array()
			for p in q:
				inner_q.append(p.lerp(center, 0.1) + o)
			draw_colored_polygon(inner_q, Color(0.08, 0.07, 0.06, 0.8 * f_bright))
			# Outline glow
			for e in 4:
				draw_line(oq[e], oq[(e + 1) % 4], Color(1, 0.95, 0.8, f_pulse), 1.5)
			# Handle — on the inner side of the door
			var handle_pos: Vector2
			if side == "left":
				handle_pos = q[1].lerp(q[2], 0.55) + o
			else:
				handle_pos = q[0].lerp(q[3], 0.55) + o
			var hs := maxf(2.0, r.size.y * 0.03)
			var jiggle := Vector2.ZERO
			if event_type == 2 and i > 0 and event_progress < 1.5:
				jiggle = Vector2(sin(event_progress * 25.0) * 2.0, 0)
			draw_circle(handle_pos + jiggle, hs, Color(0.7, 0.65, 0.5, 0.4 * f_bright))
		else:
			# Back door — flat rect on back wall
			draw_rect(Rect2(r.position + o, r.size), Color(0.35, 0.30, 0.25, 0.6 * f_bright))
			var inner := r.grow(-3)
			draw_rect(Rect2(inner.position + o, inner.size), Color(0.08, 0.07, 0.06, 0.8 * f_bright))
			draw_rect(Rect2(r.position + o, r.size), Color(1, 0.95, 0.8, f_pulse), true, 1.5)
			# Handle
			var hx := r.position.x + r.size.x * 0.8
			var hy := r.position.y + r.size.y * 0.55
			var hs := maxf(2.0, r.size.x * 0.06)
			var jiggle := Vector2.ZERO
			if event_type == 2 and i == 0 and event_progress < 1.5:
				jiggle = Vector2(sin(event_progress * 25.0) * 2.0, 0)
			draw_circle(Vector2(hx, hy) + o + jiggle, hs, Color(0.7, 0.65, 0.5, 0.4 * f_bright))

# ---- Ambient events ----

func _draw_events(o: Vector2) -> void:
	if event_type < 0:
		return
	match event_type:
		0:  # Shadow crosses back wall
			if event_progress < 2.0:
				var t := event_progress / 2.0
				var sx := lerpf(btl.x, btr.x, t)
				var sy := (btl.y + bbl.y) * 0.5
				var sw2 := (btr.x - btl.x) * 0.15
				var sh2 := (bbl.y - btl.y) * 0.6
				var a := sin(t * PI) * 0.12
				draw_rect(Rect2(sx - sw2 * 0.5 + o.x, sy - sh2 * 0.5 + o.y, sw2, sh2), Color(0, 0, 0, a))
		4:  # Something in peripheral vision
			if event_progress < 1.0:
				var side := 1.0 if event_data.x > 0.5 else 0.0
				var px := lerpf(-20.0, 20.0, side) + lerpf(0.0, sw, side)
				var py := sh * event_data.y
				var a := sin(event_progress * PI) * 0.08
				draw_circle(Vector2(px, py) + o, 8, Color(0.1, 0.1, 0.1, a))

# ---- Closing door animation ----

func _draw_close_door() -> void:
	if close_door_timer <= 0:
		return
	var t := close_door_timer / 1.2  # 1.0 → 0.0
	var a := t * 0.6
	# Two dark panels closing from sides at bottom of screen
	var panel_w := sw * 0.5 * t
	draw_rect(Rect2(0, sh * 0.4, panel_w, sh * 0.6), Color(0.12, 0.10, 0.08, a))
	draw_rect(Rect2(sw - panel_w, sh * 0.4, panel_w, sh * 0.6), Color(0.12, 0.10, 0.08, a))

# ---- Atmosphere FX ----

func _draw_fx() -> void:
	# Vignette
	var vig := unease * 0.55
	if vig > 0.01:
		for i in 8:
			var t := float(i) / 8.0
			var a := vig * (1.0 - t) * 0.6
			draw_rect(Rect2(0, sh * t * 0.2, sw, sh * 0.025), Color(0, 0, 0, a))
			draw_rect(Rect2(0, sh - sh * t * 0.2, sw, sh * 0.025), Color(0, 0, 0, a))
			draw_rect(Rect2(sw * t * 0.15, 0, sw * 0.02, sh), Color(0, 0, 0, a * 0.7))
			draw_rect(Rect2(sw - sw * t * 0.15, 0, sw * 0.02, sh), Color(0, 0, 0, a * 0.7))

	# Whispers
	if wh_alpha > 0.01:
		_txt(wh_pos, wh_text, 16, Color(0.85, 0.82, 0.75, wh_alpha * 0.5))

	# Déjà vu text
	if deja_vu_alpha > 0.01:
		_txt(Vector2(sw * 0.5, sh * 0.5), deja_vu_text, 18, Color(0.9, 0.88, 0.8, deja_vu_alpha * 0.6))

	# Scan lines at high unease
	if unease > 0.7:
		var sl_a := (unease - 0.7) * 0.15
		var sl_offset := fmod(state_timer * 60.0, 4.0)
		var y := sl_offset
		while y < sh:
			draw_line(Vector2(0, y), Vector2(sw, y), Color(0, 0, 0, sl_a), 1)
			y += 4.0

	# Room name (with anomaly: wrong name)
	if room_time < 2.5 and game_state == 1:
		var na := 1.0 - room_time / 2.5
		var display_name: String = _names[room_type]
		if has_anomaly and anomaly_type == 0:
			var wrong := (room_type + room_seed % (ROOM_TYPES - 1) + 1) % ROOM_TYPES
			display_name = _names[wrong]
		_txt(Vector2(sw * 0.5, sh * 0.88), display_name, 12, Color(0.8, 0.78, 0.7, na * 0.35))

# ---- HUD ----

func _draw_hud() -> void:
	_txt(Vector2(sw * 0.5, 14), str(score) + " rooms", 14, Color(0.9, 0.88, 0.8, 0.5))
	var bar_w := sw * 0.3
	var bx := sw * 0.5 - bar_w * 0.5
	var by := 30.0
	draw_rect(Rect2(bx, by, bar_w, 4), Color(0.3, 0.3, 0.28, 0.3))
	draw_rect(Rect2(bx, by, bar_w * unease, 4), Color(0.7, 0.5, 0.2, 0.5).lerp(Color(0.9, 0.2, 0.1, 0.7), unease))

# ---- Transition ----

func _draw_trans() -> void:
	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, tr_alpha))

# ---- Game Over ----

func _draw_gameover() -> void:
	var a := minf(state_timer * 0.8, 1.0)
	draw_rect(Rect2(0, 0, sw, sh), Color(0, 0, 0, 0.7 * a))
	var cx := sw * 0.5
	_txt(Vector2(cx, sh * 0.28), "The space has you.", 28, Color(0.9, 0.88, 0.82, a))
	_txt(Vector2(cx, sh * 0.42), str(score) + " rooms", 22, Color(0.85, 0.80, 0.65, a * 0.8))
	if score >= best_score and score > 0:
		_txt(Vector2(cx, sh * 0.42 + 28), "new record", 14, Color(0.9, 0.8, 0.5, a * 0.6))
	elif best_score > 0:
		_txt(Vector2(cx, sh * 0.42 + 28), "deepest: " + str(best_score), 14, Color(0.8, 0.78, 0.7, a * 0.4))
	if state_timer > 1.5:
		var ta := 0.3 + sin(state_timer * 3) * 0.2
		_txt(Vector2(cx, sh * 0.62), "TAP TO TRY AGAIN", 20, Color(0.9, 0.88, 0.82, ta))

# ---- Text helper ----

func _txt(pos: Vector2, text: String, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var ss := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5 + 1, size * 0.35 + 1),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.35))
	font.draw_string(get_canvas_item(), pos + Vector2(-ss.x * 0.5, size * 0.35),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
