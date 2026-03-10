extends Node2D

# === GAME CONFIG ===
const GRAVITY := 1800.0
const JUMP_FORCE := -650.0
const DOUBLE_JUMP_FORCE := -550.0
const RUN_SPEED := 200.0
const PLAYER_SIZE := Vector2(32, 40)
const COIN_RADIUS := 12.0
const GOOMBA_SIZE := Vector2(32, 28)
const PIPE_WIDTH := 48.0
const BLOCK_SIZE := 32.0
const TILE := 32.0  # base tile unit

# === COLORS (Mario palette) ===
const COL_SKY := Color(0.36, 0.68, 1.0)
const COL_GROUND := Color(0.76, 0.49, 0.24)
const COL_GROUND_TOP := Color(0.28, 0.72, 0.18)
const COL_PLAYER_RED := Color(0.9, 0.15, 0.1)
const COL_PLAYER_SKIN := Color(1.0, 0.82, 0.65)
const COL_PLAYER_BLUE := Color(0.15, 0.25, 0.85)
const COL_COIN := Color(1.0, 0.85, 0.0)
const COL_COIN_SHINE := Color(1.0, 0.95, 0.6)
const COL_GOOMBA := Color(0.55, 0.3, 0.1)
const COL_GOOMBA_FEET := Color(0.3, 0.15, 0.05)
const COL_PIPE_GREEN := Color(0.1, 0.65, 0.15)
const COL_PIPE_DARK := Color(0.05, 0.45, 0.1)
const COL_BLOCK_YELLOW := Color(0.85, 0.7, 0.2)
const COL_BLOCK_DARK := Color(0.6, 0.45, 0.1)
const COL_BRICK := Color(0.72, 0.35, 0.15)
const COL_BRICK_DARK := Color(0.55, 0.25, 0.1)
const COL_CLOUD := Color(1.0, 1.0, 1.0, 0.85)
const COL_HILL := Color(0.22, 0.62, 0.15)
const COL_HILL_DARK := Color(0.16, 0.5, 0.1)
const COL_BUSH := Color(0.18, 0.58, 0.12)
const COL_FLAG_GREEN := Color(0.1, 0.7, 0.2)
const COL_FLAG_POLE := Color(0.4, 0.4, 0.4)
const COL_CASTLE := Color(0.7, 0.55, 0.35)
const COL_CASTLE_DARK := Color(0.5, 0.4, 0.25)

# === GAME STATE ===
var game_state := 0  # 0=title, 1=playing, 2=dead, 3=win
var points := 0
var level_num := 1
var camera_x := 0.0
var ground_y := 400.0
var screen_w := 800.0
var screen_h := 600.0
var time_bonus := 300  # counts down, bonus for finishing fast
var time_timer := 0.0
var win_timer := 0.0

# === PLAYER ===
var player_x := 80.0
var player_y := 0.0
var player_vy := 0.0
var on_ground := true
var can_double_jump := true
var player_anim_frame := 0.0
var is_dead := false
var death_vy := 0.0
var player_on_flag := false
var flag_slide_target := 0.0

# === LEVEL DATA ===
# platforms: {x, y, width} — solid surfaces player can stand on
var platforms: Array = []
# ground_segments: {x, width} — ground-level terrain (y = ground_y)
var ground_segs: Array = []
var coins: Array = []       # {x, y, collected}
var goombas: Array = []     # {x, y, alive, vx, ground_left, ground_right}
var pipes: Array = []       # {x, height}
var qblocks: Array = []     # {x, y, hit, coin_y, coin_timer}
var bricks: Array = []      # {x, y}
var flag_x := 0.0           # flagpole x position
var flag_y_pos := 0.0       # flag sliding position (normalized 0-1)
var castle_x := 0.0
var level_end_x := 0.0

# === DECORATION ===
var clouds: Array = []
var hills: Array = []
var bushes: Array = []

# === SCORE DISPLAY ===
var score_popups: Array = []

# === AUDIO ===
var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer

# === API ===
var _score_submitted := false

func _ready() -> void:
	_resize()
	_setup_audio()

func _setup_audio() -> void:
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	var stream = _generate_theme()
	music_player.stream = stream
	music_player.volume_db = -3.0

	sfx_player = AudioStreamPlayer.new()
	add_child(sfx_player)
	sfx_player.stream = _generate_death_sound()
	sfx_player.volume_db = -3.0

func _generate_theme() -> AudioStreamWAV:
	var sr := 22050
	var amp := 0.35
	var bpm := 200.0
	var beat := 60.0 / bpm

	# Note frequencies
	var notes := {
		"R": 0.0,
		"C3": 130.81, "D3": 146.83, "E3": 164.81, "F3": 174.61, "G3": 196.00,
		"A3": 220.00, "B3": 246.94,
		"C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.00,
		"A4": 440.00, "Bb4": 466.16, "B4": 493.88,
		"C5": 523.25, "D5": 587.33, "E5": 659.25, "F5": 698.46, "G5": 783.99,
		"A5": 880.00, "B5": 987.77,
	}

	# Melody: [note, beats]
	var melody := [
		["E5", 0.5], ["E5", 0.5], ["R", 0.5], ["E5", 0.5],
		["R", 0.5], ["C5", 0.5], ["E5", 1.0],
		["G5", 1.0], ["R", 1.0], ["G4", 1.0], ["R", 1.0],
		["C5", 1.0], ["R", 0.5], ["G4", 1.0], ["R", 0.5],
		["E4", 1.0], ["R", 0.5], ["A4", 1.0], ["B4", 1.0],
		["Bb4", 0.5], ["A4", 1.0],
		["G4", 0.67], ["E5", 0.67], ["G5", 0.67],
		["A5", 1.0], ["F5", 0.5], ["G5", 0.5],
		["R", 0.5], ["E5", 1.0], ["C5", 0.5], ["D5", 0.5], ["B4", 1.0],
		["E5", 0.5], ["E5", 0.5], ["R", 0.5], ["E5", 0.5],
		["R", 0.5], ["C5", 0.5], ["E5", 1.0],
		["G5", 1.0], ["R", 1.0], ["G4", 1.0], ["R", 1.0],
	]

	# Bass: [note, beats]
	var bass := [
		["D3", 0.5], ["D3", 0.5], ["R", 0.5], ["D3", 0.5],
		["R", 0.5], ["D3", 0.5], ["G3", 1.0],
		["G3", 1.0], ["R", 1.0], ["G3", 1.0], ["R", 1.0],
		["G3", 1.0], ["R", 0.5], ["E3", 1.0], ["R", 0.5],
		["C3", 1.0], ["R", 0.5], ["F3", 1.0], ["G3", 1.0],
		["F3", 0.5], ["F3", 1.0],
		["C3", 0.67], ["G3", 0.67], ["E3", 0.67],
		["F3", 1.0], ["D3", 0.5], ["E3", 0.5],
		["R", 0.5], ["C3", 1.0], ["A3", 0.5], ["B3", 0.5], ["G3", 1.0],
		["D3", 0.5], ["D3", 0.5], ["R", 0.5], ["D3", 0.5],
		["R", 0.5], ["D3", 0.5], ["G3", 1.0],
		["G3", 1.0], ["R", 1.0], ["G3", 1.0], ["R", 1.0],
	]

	# Generate melody samples (square wave, 25% duty)
	var melody_samples := PackedFloat32Array()
	for entry in melody:
		var note_name: String = entry[0]
		var dur: float = entry[1] * beat
		var freq: float = notes[note_name]
		var n := int(sr * dur)
		for i in range(n):
			var t := float(i) / sr
			if freq == 0.0:
				melody_samples.append(0.0)
			else:
				var phase := fmod(t * freq, 1.0)
				melody_samples.append(amp * 0.7 if phase < 0.25 else -amp * 0.7)

	# Generate bass samples (triangle wave)
	var bass_samples := PackedFloat32Array()
	for entry in bass:
		var note_name: String = entry[0]
		var dur: float = entry[1] * beat
		var freq: float = notes[note_name]
		var n := int(sr * dur)
		for i in range(n):
			var t := float(i) / sr
			if freq == 0.0:
				bass_samples.append(0.0)
			else:
				var phase := fmod(t * freq, 1.0)
				bass_samples.append(amp * 0.5 * (4.0 * abs(phase - 0.5) - 1.0))

	# Mix into 16-bit PCM
	var max_len := maxi(melody_samples.size(), bass_samples.size())
	var pcm := PackedByteArray()
	pcm.resize(max_len * 2)  # 16-bit = 2 bytes per sample
	for i in range(max_len):
		var m := melody_samples[i] if i < melody_samples.size() else 0.0
		var b := bass_samples[i] if i < bass_samples.size() else 0.0
		var mixed := clampf(m + b, -1.0, 1.0)
		var val := int(mixed * 32767.0)
		pcm.encode_s16(i * 2, val)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sr
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = max_len
	stream.data = pcm
	return stream

func _generate_death_sound() -> AudioStreamWAV:
	var sr := 22050
	var amp := 0.4

	# Death jingle: Bb4 - pause - F4 - E4 - D4 - C4 (descending, getting slower)
	var sequence := [
		[466.16, 0.15],  # Bb4
		[0.0, 0.08],     # pause
		[349.23, 0.18],  # F4
		[0.0, 0.05],
		[329.63, 0.22],  # E4
		[0.0, 0.05],
		[293.66, 0.25],  # D4
		[0.0, 0.05],
		[261.63, 0.5],   # C4 (held longer)
		[0.0, 0.15],     # silence tail
	]

	var samples := PackedFloat32Array()
	for entry in sequence:
		var freq: float = entry[0]
		var dur: float = entry[1]
		var n := int(sr * dur)
		for i in range(n):
			var t := float(i) / sr
			var envelope := 1.0
			# Fade out last 20% of each note
			var progress := float(i) / float(n)
			if progress > 0.8:
				envelope = (1.0 - progress) / 0.2
			if freq == 0.0:
				samples.append(0.0)
			else:
				var phase := fmod(t * freq, 1.0)
				samples.append(amp * envelope * (1.0 if phase < 0.5 else -1.0))

	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in range(samples.size()):
		pcm.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sr
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream

func _resize() -> void:
	screen_w = get_viewport().get_visible_rect().size.x
	screen_h = get_viewport().get_visible_rect().size.y
	if screen_w <= 0:
		screen_w = 800.0
	if screen_h <= 0:
		screen_h = 600.0
	ground_y = screen_h * 0.78

func _build_level() -> void:
	platforms.clear()
	ground_segs.clear()
	coins.clear()
	goombas.clear()
	pipes.clear()
	qblocks.clear()
	bricks.clear()
	clouds.clear()
	hills.clear()
	bushes.clear()
	score_popups.clear()

	var cursor := 0.0  # x position cursor as we build the level
	var t := TILE
	var gy := ground_y
	var difficulty := mini(level_num, 5)

	# --- Section 1: Starting area (safe) ---
	ground_segs.append({"x": cursor, "width": t * 12})
	# Welcome coins
	for i in range(5):
		coins.append({"x": cursor + t * 3 + i * t, "y": gy - t * 3, "collected": false})
	cursor += t * 12

	# --- Section 2: First pipe + goomba ---
	ground_segs.append({"x": cursor, "width": t * 10})
	pipes.append({"x": cursor + t * 2, "height": t * 2})
	goombas.append({"x": cursor + t * 6, "y": gy - GOOMBA_SIZE.y, "alive": true, "vx": -40, "ground_left": cursor, "ground_right": cursor + t * 10})
	# Coins above pipe
	for i in range(3):
		coins.append({"x": cursor + t * 2 + i * t * 0.8, "y": gy - t * 4, "collected": false})
	cursor += t * 10

	# --- Section 3: Small pit with coins ---
	# gap
	cursor += t * 3
	# Coin arc over gap
	for i in range(3):
		var arc_h = sin(float(i) / 2.0 * PI) * t * 2
		coins.append({"x": cursor - t * 2.5 + i * t * 1.2, "y": gy - t * 2 - arc_h, "collected": false})
	# Landing
	ground_segs.append({"x": cursor, "width": t * 8})
	# Question blocks
	qblocks.append({"x": cursor + t * 2, "y": gy - t * 4, "hit": false, "coin_y": 0.0, "coin_timer": 0.0})
	qblocks.append({"x": cursor + t * 4, "y": gy - t * 4, "hit": false, "coin_y": 0.0, "coin_timer": 0.0})
	# Brick between question blocks
	bricks.append({"x": cursor + t * 3, "y": gy - t * 4})
	goombas.append({"x": cursor + t * 5, "y": gy - GOOMBA_SIZE.y, "alive": true, "vx": -35, "ground_left": cursor, "ground_right": cursor + t * 8})
	cursor += t * 8

	# --- Section 4: Elevated platforms ---
	ground_segs.append({"x": cursor, "width": t * 4})
	# Stepping platforms going up
	platforms.append({"x": cursor + t * 5, "y": gy - t * 2, "width": t * 3})
	platforms.append({"x": cursor + t * 9, "y": gy - t * 4, "width": t * 3})
	platforms.append({"x": cursor + t * 13, "y": gy - t * 3, "width": t * 3})
	# Coins on platforms
	coins.append({"x": cursor + t * 6, "y": gy - t * 3.5, "collected": false})
	coins.append({"x": cursor + t * 7, "y": gy - t * 3.5, "collected": false})
	coins.append({"x": cursor + t * 10, "y": gy - t * 5.5, "collected": false})
	coins.append({"x": cursor + t * 11, "y": gy - t * 5.5, "collected": false})
	coins.append({"x": cursor + t * 14, "y": gy - t * 4.5, "collected": false})
	# Ground resumes
	cursor += t * 16
	ground_segs.append({"x": cursor, "width": t * 8})
	# Two goombas patrolling
	goombas.append({"x": cursor + t * 2, "y": gy - GOOMBA_SIZE.y, "alive": true, "vx": -45, "ground_left": cursor, "ground_right": cursor + t * 8})
	goombas.append({"x": cursor + t * 5, "y": gy - GOOMBA_SIZE.y, "alive": true, "vx": -30, "ground_left": cursor, "ground_right": cursor + t * 8})
	cursor += t * 8

	# --- Section 5: Pipe valley ---
	ground_segs.append({"x": cursor, "width": t * 14})
	pipes.append({"x": cursor + t * 1, "height": t * 2})
	pipes.append({"x": cursor + t * 4, "height": t * 3})
	pipes.append({"x": cursor + t * 7, "height": t * 4})
	pipes.append({"x": cursor + t * 10, "height": t * 2.5})
	# Coins between pipes
	coins.append({"x": cursor + t * 3, "y": gy - t * 2, "collected": false})
	coins.append({"x": cursor + t * 6, "y": gy - t * 3.5, "collected": false})
	coins.append({"x": cursor + t * 9, "y": gy - t * 4.5, "collected": false})
	# Goomba between pipes
	goombas.append({"x": cursor + t * 3, "y": gy - GOOMBA_SIZE.y, "alive": true, "vx": -25, "ground_left": cursor + t * 2.5, "ground_right": cursor + t * 4})
	cursor += t * 14

	# --- Section 6: Big pit with floating platform ---
	# gap (wide)
	var gap_start = cursor
	cursor += t * 6
	# Floating platform in middle of gap
	platforms.append({"x": gap_start + t * 2, "y": gy - t * 1.5, "width": t * 2})
	# Coins above floating platform
	coins.append({"x": gap_start + t * 2.5, "y": gy - t * 3, "collected": false})
	coins.append({"x": gap_start + t * 3.5, "y": gy - t * 3, "collected": false})
	# Landing
	ground_segs.append({"x": cursor, "width": t * 6})
	# Question block row
	for i in range(4):
		qblocks.append({"x": cursor + t + i * t * 1.2, "y": gy - t * 4, "hit": false, "coin_y": 0.0, "coin_timer": 0.0})
	goombas.append({"x": cursor + t * 3, "y": gy - GOOMBA_SIZE.y, "alive": true, "vx": -50, "ground_left": cursor, "ground_right": cursor + t * 6})
	cursor += t * 6

	# --- Section 7: Brick bridge ---
	# gap underneath
	var bridge_x = cursor
	cursor += t * 1  # small gap before bridge
	# Brick bridge (floating)
	for i in range(6):
		bricks.append({"x": bridge_x + t * 1 + i * t, "y": gy - t * 2})
	# Put bricks as platforms
	platforms.append({"x": bridge_x + t, "y": gy - t * 2, "width": t * 6})
	# Coins above bridge
	for i in range(4):
		coins.append({"x": bridge_x + t * 2 + i * t, "y": gy - t * 4, "collected": false})
	# Goomba on bridge
	goombas.append({"x": bridge_x + t * 3, "y": gy - t * 2 - GOOMBA_SIZE.y, "alive": true, "vx": -30, "ground_left": bridge_x + t, "ground_right": bridge_x + t * 7})
	cursor = bridge_x + t * 8
	# Landing after bridge
	ground_segs.append({"x": cursor, "width": t * 6})
	cursor += t * 6

	# --- Section 8: Staircase challenge (harder sections based on level) ---
	ground_segs.append({"x": cursor, "width": t * 16})
	if difficulty >= 2:
		# More goombas
		goombas.append({"x": cursor + t * 2, "y": gy - GOOMBA_SIZE.y, "alive": true, "vx": -55, "ground_left": cursor, "ground_right": cursor + t * 16})
		goombas.append({"x": cursor + t * 5, "y": gy - GOOMBA_SIZE.y, "alive": true, "vx": -40, "ground_left": cursor, "ground_right": cursor + t * 16})
		goombas.append({"x": cursor + t * 9, "y": gy - GOOMBA_SIZE.y, "alive": true, "vx": -60, "ground_left": cursor, "ground_right": cursor + t * 16})
	# Pipe + question blocks
	pipes.append({"x": cursor + t * 3, "height": t * 3})
	qblocks.append({"x": cursor + t * 7, "y": gy - t * 4, "hit": false, "coin_y": 0.0, "coin_timer": 0.0})
	bricks.append({"x": cursor + t * 6, "y": gy - t * 4})
	bricks.append({"x": cursor + t * 8, "y": gy - t * 4})
	# Coin trail
	for i in range(6):
		coins.append({"x": cursor + t * 5 + i * t, "y": gy - t * 2, "collected": false})
	# Higher platform with coins
	platforms.append({"x": cursor + t * 11, "y": gy - t * 3, "width": t * 4})
	for i in range(3):
		coins.append({"x": cursor + t * 12 + i * t, "y": gy - t * 4.5, "collected": false})
	cursor += t * 16

	# --- Section 9: Gauntlet (more pits + enemies) ---
	# Pit
	cursor += t * 3
	for i in range(3):
		coins.append({"x": cursor - t * 2.5 + i * t, "y": gy - t * 3, "collected": false})
	ground_segs.append({"x": cursor, "width": t * 5})
	goombas.append({"x": cursor + t * 2, "y": gy - GOOMBA_SIZE.y, "alive": true, "vx": -45, "ground_left": cursor, "ground_right": cursor + t * 5})
	cursor += t * 5
	# Another pit
	cursor += t * 3
	for i in range(3):
		coins.append({"x": cursor - t * 2.5 + i * t, "y": gy - t * 2.5, "collected": false})
	ground_segs.append({"x": cursor, "width": t * 6})
	pipes.append({"x": cursor + t * 2, "height": t * 2.5})
	goombas.append({"x": cursor + t * 4, "y": gy - GOOMBA_SIZE.y, "alive": true, "vx": -35, "ground_left": cursor, "ground_right": cursor + t * 6})
	cursor += t * 6

	# --- Section 10: Final staircase + flag ---
	ground_segs.append({"x": cursor, "width": t * 20})
	# Staircase of bricks (ascending)
	for step in range(8):
		for col in range(8 - step):
			bricks.append({"x": cursor + t * 4 + col * t + step * t, "y": gy - (step + 1) * t})
	# The staircase acts as a ramp
	for step in range(8):
		platforms.append({"x": cursor + t * 4 + step * t, "y": gy - (step + 1) * t, "width": t * (8 - step)})

	# Flagpole
	flag_x = cursor + t * 14
	flag_y_pos = 0.0
	# Castle after flag
	castle_x = cursor + t * 17
	level_end_x = cursor + t * 20

	# --- Decorations ---
	var total_len = level_end_x
	var cx = 0.0
	while cx < total_len:
		clouds.append({"x": cx + randf_range(20, 100), "y": randf_range(20, ground_y * 0.35), "scale": randf_range(0.6, 1.3)})
		cx += randf_range(100, 250)
	var hx = 0.0
	while hx < total_len:
		hills.append({"x": hx, "width": randf_range(100, 250), "height": randf_range(30, 80)})
		hx += randf_range(250, 500)
	var bsx = 0.0
	while bsx < total_len:
		bushes.append({"x": bsx, "width": randf_range(40, 90)})
		bsx += randf_range(120, 300)

func _process(delta: float) -> void:
	_resize()

	if game_state == 1:
		_update_game(delta)
	elif game_state == 2:
		_update_death(delta)
	elif game_state == 3:
		_update_win(delta)

	queue_redraw()

func _update_game(delta: float) -> void:
	# Timer countdown
	time_timer += delta
	if time_timer >= 1.0:
		time_timer -= 1.0
		if time_bonus > 0:
			time_bonus -= 1

	# Auto-run right
	player_x += RUN_SPEED * delta
	player_anim_frame += delta * RUN_SPEED * 0.03

	# Camera follows player
	var target_cam = player_x - screen_w * 0.3
	if target_cam > camera_x:
		camera_x = target_cam
	if camera_x < 0:
		camera_x = 0

	# Player physics
	player_vy += GRAVITY * delta
	player_y += player_vy * delta

	# Collision with ground segments
	var standing := false
	for seg in ground_segs:
		standing = _check_ground_collision(seg.x, ground_y, seg.width) or standing

	# Collision with platforms
	for plat in platforms:
		standing = _check_ground_collision(plat.x, plat.y, plat.width) or standing

	# Collision with pipes (top landing + side death)
	for p in pipes:
		var pipe_top = ground_y - p.height
		var px1 = player_x + 4
		var py1 = player_y + 4
		var px2 = player_x + PLAYER_SIZE.x - 4
		var py2 = player_y + PLAYER_SIZE.y
		if px2 > p.x and px1 < p.x + PIPE_WIDTH:
			if py2 > pipe_top and py1 < ground_y:
				if player_vy > 0 and py1 < pipe_top + 4:
					player_y = pipe_top - PLAYER_SIZE.y
					player_vy = 0
					standing = true
					on_ground = true
					can_double_jump = true
				else:
					_die()
					return

	if not standing:
		on_ground = false

	# Fall to death
	if player_y > ground_y + screen_h * 0.5:
		_die()
		return

	# Coin collection
	var pcx = player_x + PLAYER_SIZE.x / 2.0
	var pcy = player_y + PLAYER_SIZE.y / 2.0
	for c in coins:
		if c.collected:
			continue
		var dx = pcx - c.x
		var dy = pcy - c.y
		if dx * dx + dy * dy < (COIN_RADIUS + 18) * (COIN_RADIUS + 18):
			c.collected = true
			points += 10
			_add_popup(c.x, c.y, "+10")

	# Question block collision (hit from below)
	for q in qblocks:
		if q.hit:
			continue
		if player_vy < 0:
			if player_x + PLAYER_SIZE.x - 4 > q.x and player_x + 4 < q.x + BLOCK_SIZE:
				if player_y > q.y and player_y < q.y + BLOCK_SIZE + 8:
					q.hit = true
					q.coin_y = q.y - 10
					q.coin_timer = 0.6
					points += 50
					player_vy = 0
					_add_popup(q.x + BLOCK_SIZE / 2, q.y - 20, "+50")

	# Question block animations
	for q in qblocks:
		if q.coin_timer > 0:
			q.coin_timer -= delta
			q.coin_y -= 120 * delta

	# Goomba logic
	for g in goombas:
		if not g.alive:
			continue
		g.x += g.vx * delta
		# Bounce off patrol bounds
		if g.x <= g.ground_left:
			g.vx = abs(g.vx)
		elif g.x + GOOMBA_SIZE.x >= g.ground_right:
			g.vx = -abs(g.vx)

		var gx1 = g.x
		var gy1 = g.y
		var gx2 = g.x + GOOMBA_SIZE.x
		var gy2 = g.y + GOOMBA_SIZE.y
		var px1 = player_x + 4
		var py1 = player_y + 4
		var px2 = player_x + PLAYER_SIZE.x - 4
		var py2 = player_y + PLAYER_SIZE.y

		if px2 > gx1 and px1 < gx2 and py2 > gy1 and py1 < gy2:
			if player_vy > 0 and pcy < gy1 + 10:
				g.alive = false
				player_vy = JUMP_FORCE * 0.5
				points += 25
				_add_popup(g.x + GOOMBA_SIZE.x / 2, g.y - 10, "+25")
			else:
				_die()
				return

	# Flag collision
	if not player_on_flag and player_x + PLAYER_SIZE.x > flag_x and player_x < flag_x + 16:
		player_on_flag = true
		# Calculate flag bonus based on height (higher = more points)
		var flag_top = ground_y - TILE * 9
		var flag_bottom = ground_y
		var height_ratio = clampf(1.0 - (player_y + PLAYER_SIZE.y - flag_top) / (flag_bottom - flag_top), 0, 1)
		var flag_bonus = int(height_ratio * 500) * 10
		if flag_bonus < 100:
			flag_bonus = 100
		points += flag_bonus
		_add_popup(flag_x, player_y, "+" + str(flag_bonus))
		flag_slide_target = ground_y - PLAYER_SIZE.y
		game_state = 3
		win_timer = 0.0

	# Score popups
	for pop in score_popups:
		pop.timer -= delta
		pop.y -= 40 * delta
	score_popups = score_popups.filter(func(p): return p.timer > 0)

func _check_ground_collision(surf_x: float, surf_y: float, surf_w: float) -> bool:
	var foot_y = player_y + PLAYER_SIZE.y
	if player_x + PLAYER_SIZE.x * 0.3 > surf_x and player_x + PLAYER_SIZE.x * 0.7 < surf_x + surf_w:
		if foot_y >= surf_y and foot_y < surf_y + 20 and player_vy >= 0:
			player_y = surf_y - PLAYER_SIZE.y
			player_vy = 0
			on_ground = true
			can_double_jump = true
			return true
	return false

func _update_death(delta: float) -> void:
	if is_dead:
		death_vy += GRAVITY * 0.6 * delta
		player_y += death_vy * delta
		if player_y > ground_y + screen_h:
			is_dead = false

func _update_win(delta: float) -> void:
	win_timer += delta
	# Slide down flagpole
	if player_y < flag_slide_target:
		player_y += 200 * delta
		flag_y_pos = clampf((player_y + PLAYER_SIZE.y - (ground_y - TILE * 9)) / (TILE * 9), 0, 1)
	elif win_timer < 3.0:
		# Walk to castle
		player_x += 100 * delta
		player_anim_frame += delta * 100 * 0.03
		camera_x = maxf(camera_x, player_x - screen_w * 0.3)
	elif win_timer < 4.5:
		# Time bonus counting
		if time_bonus > 0:
			var add = mini(time_bonus, 5)
			time_bonus -= add
			points += add * 10
	else:
		# Next level
		_submit_and_save()
		level_num += 1
		_start_level()

func _die() -> void:
	game_state = 2
	is_dead = true
	death_vy = JUMP_FORCE * 0.8
	if music_player and music_player.playing:
		music_player.stop()
	if sfx_player:
		sfx_player.play()
	_submit_and_save()

func _add_popup(px: float, py: float, text: String) -> void:
	score_popups.append({"x": px, "y": py, "text": text, "timer": 1.0})

func _input(event: InputEvent) -> void:
	if game_state == 0:
		if (event is InputEventMouseButton and event.pressed) or \
		   (event is InputEventScreenTouch and event.pressed):
			_start_game()
		return

	if game_state == 2 and not is_dead:
		if (event is InputEventMouseButton and event.pressed) or \
		   (event is InputEventScreenTouch and event.pressed):
			_restart_level()
		return

	if game_state == 1:
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or \
		   (event is InputEventScreenTouch and event.pressed):
			_jump()

func _jump() -> void:
	if on_ground:
		player_vy = JUMP_FORCE
		on_ground = false
	elif can_double_jump:
		player_vy = DOUBLE_JUMP_FORCE
		can_double_jump = false

func _start_game() -> void:
	level_num = 1
	points = 0
	_score_submitted = false
	_start_level()

	if Api:
		Api.load_state(func(ok: bool, data: Variant) -> void:
			if ok and data is Dictionary:
				var saved = data.get("data", {})
				if saved is Dictionary:
					points = int(saved.get("points", 0))
					level_num = int(saved.get("level", 1))
					_start_level()
		)

func _start_level() -> void:
	game_state = 1
	_build_level()
	if music_player and music_player.stream and not music_player.playing:
		print("[audio] Starting music playback")
		music_player.play()
	player_x = 80.0
	player_y = ground_y - PLAYER_SIZE.y
	player_vy = 0
	camera_x = 0.0
	on_ground = true
	can_double_jump = true
	is_dead = false
	player_on_flag = false
	time_bonus = 300
	time_timer = 0.0
	win_timer = 0.0
	_score_submitted = false

func _restart_level() -> void:
	_start_level()

func _submit_and_save() -> void:
	if _score_submitted or points <= 0:
		return
	_score_submitted = true
	if Api:
		Api.submit_score(points, func(_ok: bool, _r: Variant) -> void: pass)
		Api.save_state(level_num, {"points": points, "level": level_num}, func(_ok: bool, _r: Variant) -> void: pass)

# ==================== DRAWING ====================

func _draw() -> void:
	var cx = camera_x  # camera offset

	# Sky
	draw_rect(Rect2(0, 0, screen_w, screen_h), COL_SKY)

	# Hills (slow parallax)
	for h in hills:
		_draw_hill(h.x - cx * 0.3, h.width, h.height)

	# Clouds (slower parallax)
	for cl in clouds:
		_draw_cloud(cl.x - cx * 0.15, cl.y, cl.scale)

	# Bushes
	for b in bushes:
		_draw_bush(b.x - cx * 0.6, b.width)

	# Ground segments
	for seg in ground_segs:
		_draw_ground_segment(seg.x - cx, seg.width)

	# Platforms
	for plat in platforms:
		_draw_platform(plat.x - cx, plat.y, plat.width)

	# Bricks
	for br in bricks:
		_draw_brick(br.x - cx, br.y)

	# Pipes
	for p in pipes:
		_draw_pipe(p.x - cx, p.height)

	# Question blocks
	for q in qblocks:
		_draw_qblock(q, cx)

	# Coins
	for c in coins:
		if not c.collected:
			_draw_coin(c.x - cx, c.y)

	# Goombas
	for g in goombas:
		if g.alive:
			_draw_goomba(g.x - cx, g.y)
		else:
			draw_rect(Rect2(g.x - cx, g.y + GOOMBA_SIZE.y - 6, GOOMBA_SIZE.x, 6), COL_GOOMBA)

	# Flagpole
	_draw_flagpole(flag_x - cx)

	# Castle
	_draw_castle(castle_x - cx)

	# Player
	if game_state >= 1:
		_draw_player(player_x - cx, player_y)

	# Score popups (world space)
	for pop in score_popups:
		var alpha = clampf(pop.timer, 0, 1)
		draw_string(ThemeDB.fallback_font, Vector2(pop.x - cx, pop.y),
			pop.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16,
			Color(1, 1, 1, alpha))

	# HUD (screen space, drawn last)
	_draw_hud()

	# Title / Game Over / Win
	if game_state == 0:
		_draw_title()
	elif game_state == 2 and not is_dead:
		_draw_game_over()

func _draw_ground_segment(sx: float, sw: float) -> void:
	var gh = screen_h - ground_y
	draw_rect(Rect2(sx, ground_y + 4, sw, gh), COL_GROUND)
	draw_rect(Rect2(sx, ground_y, sw, 6), COL_GROUND_TOP)
	draw_rect(Rect2(sx, ground_y + 6, sw, 2), COL_GROUND_TOP.darkened(0.15))
	# Brick pattern in dirt
	var bx = sx
	while bx < sx + sw:
		var row = 0
		var by = ground_y + 10
		while by < screen_h:
			var offset = TILE * 0.5 if row % 2 == 1 else 0.0
			draw_rect(Rect2(bx + offset, by, TILE - 1, TILE * 0.5 - 1), COL_GROUND.darkened(0.08))
			by += TILE * 0.5
			row += 1
		bx += TILE

func _draw_platform(px: float, py: float, pw: float) -> void:
	# Brick-style platform
	draw_rect(Rect2(px, py, pw, TILE), COL_BRICK)
	draw_rect(Rect2(px, py, pw, 3), COL_BRICK.lightened(0.2))
	# Brick lines
	var bx = px
	while bx < px + pw:
		draw_rect(Rect2(bx, py, TILE - 1, TILE - 1), COL_BRICK)
		draw_rect(Rect2(bx + TILE - 1, py, 1, TILE), COL_BRICK_DARK)
		bx += TILE

func _draw_brick(bx: float, by: float) -> void:
	draw_rect(Rect2(bx, by, BLOCK_SIZE, BLOCK_SIZE), COL_BRICK)
	draw_rect(Rect2(bx, by, BLOCK_SIZE, 2), COL_BRICK.lightened(0.25))
	draw_rect(Rect2(bx, by, 2, BLOCK_SIZE), COL_BRICK.lightened(0.25))
	draw_rect(Rect2(bx + BLOCK_SIZE - 2, by, 2, BLOCK_SIZE), COL_BRICK_DARK)
	draw_rect(Rect2(bx, by + BLOCK_SIZE - 2, BLOCK_SIZE, 2), COL_BRICK_DARK)
	# Cross line
	draw_rect(Rect2(bx + BLOCK_SIZE / 2 - 0.5, by, 1, BLOCK_SIZE), COL_BRICK_DARK.lerp(COL_BRICK, 0.5))
	draw_rect(Rect2(bx, by + BLOCK_SIZE / 2 - 0.5, BLOCK_SIZE, 1), COL_BRICK_DARK.lerp(COL_BRICK, 0.5))

func _draw_pipe(px: float, pipe_h: float) -> void:
	var top_y = ground_y - pipe_h
	draw_rect(Rect2(px + 4, top_y + 16, PIPE_WIDTH - 8, pipe_h - 16), COL_PIPE_GREEN)
	draw_rect(Rect2(px, top_y, PIPE_WIDTH, 18), COL_PIPE_GREEN)
	draw_rect(Rect2(px + 4, top_y + 16, 6, pipe_h - 16), COL_PIPE_DARK)
	draw_rect(Rect2(px, top_y, 6, 18), COL_PIPE_DARK)
	draw_rect(Rect2(px + PIPE_WIDTH - 10, top_y + 16, 4, pipe_h - 16), Color(0.2, 0.8, 0.25))
	draw_rect(Rect2(px + PIPE_WIDTH - 6, top_y, 4, 18), Color(0.2, 0.8, 0.25))
	# Inner dark opening
	draw_rect(Rect2(px + 10, top_y + 2, PIPE_WIDTH - 20, 6), COL_PIPE_DARK.darkened(0.3))

func _draw_coin(coin_x: float, coin_y: float) -> void:
	var t = Time.get_ticks_msec() / 300.0 + coin_x * 0.1
	var squeeze = abs(sin(t))
	var w = COIN_RADIUS * squeeze
	if w < 2:
		w = 2
	draw_rect(Rect2(coin_x - w, coin_y - COIN_RADIUS, w * 2, COIN_RADIUS * 2), COL_COIN)
	if squeeze > 0.5:
		draw_rect(Rect2(coin_x - w * 0.3, coin_y - COIN_RADIUS * 0.6, w * 0.3, COIN_RADIUS * 1.2), COL_COIN_SHINE)

func _draw_goomba(gx: float, gy: float) -> void:
	var bw = GOOMBA_SIZE.x
	var bh = GOOMBA_SIZE.y
	draw_rect(Rect2(gx + 2, gy, bw - 4, bh * 0.55), COL_GOOMBA)
	draw_rect(Rect2(gx, gy + 2, bw, bh * 0.4), COL_GOOMBA)
	draw_rect(Rect2(gx + 4, gy + bh * 0.5, bw - 8, bh * 0.3), COL_PLAYER_SKIN.darkened(0.2))
	draw_rect(Rect2(gx + 7, gy + bh * 0.5 + 2, 5, 5), Color.WHITE)
	draw_rect(Rect2(gx + bw - 12, gy + bh * 0.5 + 2, 5, 5), Color.WHITE)
	draw_rect(Rect2(gx + 9, gy + bh * 0.5 + 3, 3, 3), Color.BLACK)
	draw_rect(Rect2(gx + bw - 10, gy + bh * 0.5 + 3, 3, 3), Color.BLACK)
	draw_rect(Rect2(gx + 3, gy + bh * 0.8, 8, bh * 0.2), COL_GOOMBA_FEET)
	draw_rect(Rect2(gx + bw - 11, gy + bh * 0.8, 8, bh * 0.2), COL_GOOMBA_FEET)

func _draw_qblock(q: Dictionary, cam_x: float) -> void:
	var bx = q.x - cam_x
	var by = q.y
	var col = COL_BLOCK_DARK if q.hit else COL_BLOCK_YELLOW
	draw_rect(Rect2(bx, by, BLOCK_SIZE, BLOCK_SIZE), col)
	draw_rect(Rect2(bx, by, BLOCK_SIZE, 2), col.lightened(0.3))
	draw_rect(Rect2(bx, by, 2, BLOCK_SIZE), col.lightened(0.3))
	draw_rect(Rect2(bx + BLOCK_SIZE - 2, by, 2, BLOCK_SIZE), col.darkened(0.3))
	draw_rect(Rect2(bx, by + BLOCK_SIZE - 2, BLOCK_SIZE, 2), col.darkened(0.3))
	if not q.hit:
		draw_string(ThemeDB.fallback_font, Vector2(bx + 8, by + BLOCK_SIZE - 8),
			"?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	if q.coin_timer > 0:
		_draw_coin(bx + BLOCK_SIZE / 2.0, q.coin_y)

func _draw_flagpole(fx: float) -> void:
	var t := TILE
	var pole_top = ground_y - t * 9
	var pole_bottom = ground_y
	# Pole
	draw_rect(Rect2(fx + 6, pole_top, 4, pole_bottom - pole_top), COL_FLAG_POLE)
	# Ball on top
	draw_rect(Rect2(fx + 2, pole_top - 6, 12, 8), COL_COIN)
	# Flag (slides down with player)
	var flag_draw_y = pole_top + 8 + flag_y_pos * (pole_bottom - pole_top - t * 2)
	draw_rect(Rect2(fx + 10, flag_draw_y, t * 1.5, t), COL_FLAG_GREEN)
	# Flag triangle shape
	draw_rect(Rect2(fx + 10, flag_draw_y, t, t * 0.4), COL_FLAG_GREEN.lightened(0.15))
	# Base block
	draw_rect(Rect2(fx - 4, pole_bottom - t, t + 8, t), COL_GROUND)

func _draw_castle(cx_pos: float) -> void:
	var t := TILE
	var base_y = ground_y
	# Castle body
	draw_rect(Rect2(cx_pos, base_y - t * 4, t * 4, t * 4), COL_CASTLE)
	# Battlements
	for i in range(5):
		draw_rect(Rect2(cx_pos + i * t * 0.9 - t * 0.1, base_y - t * 5, t * 0.7, t), COL_CASTLE)
	# Door
	draw_rect(Rect2(cx_pos + t * 1.2, base_y - t * 2, t * 1.6, t * 2), COL_CASTLE_DARK)
	# Door arch
	draw_rect(Rect2(cx_pos + t * 1.2, base_y - t * 2.3, t * 1.6, t * 0.5), COL_CASTLE_DARK)
	# Window
	draw_rect(Rect2(cx_pos + t * 1.5, base_y - t * 3.5, t, t * 0.7), COL_CASTLE_DARK)

func _draw_cloud(cloud_x: float, cloud_y: float, s: float) -> void:
	var r = 20.0 * s
	draw_rect(Rect2(cloud_x - r * 1.5, cloud_y - r * 0.3, r * 3, r * 1.2), COL_CLOUD)
	draw_rect(Rect2(cloud_x - r * 0.8, cloud_y - r * 0.8, r * 1.6, r * 1.2), COL_CLOUD)
	draw_rect(Rect2(cloud_x - r * 1.8, cloud_y, r * 0.8, r * 0.6), COL_CLOUD)
	draw_rect(Rect2(cloud_x + r, cloud_y, r * 0.8, r * 0.6), COL_CLOUD)

func _draw_hill(hx: float, hw: float, hh: float) -> void:
	var base_y = ground_y
	var steps = int(hh / 4)
	for i in range(steps):
		var frac = float(i) / float(steps)
		var w = hw * (1.0 - frac * 0.8)
		var x = hx + (hw - w) / 2.0
		var y = base_y - i * 4
		draw_rect(Rect2(x, y - 4, w, 5), COL_HILL.lerp(COL_HILL_DARK, frac * 0.5))

func _draw_bush(bx: float, bw: float) -> void:
	var by = ground_y - 8
	draw_rect(Rect2(bx, by - 6, bw, 14), COL_BUSH)
	draw_rect(Rect2(bx + 4, by - 12, bw - 8, 8), COL_BUSH)
	draw_rect(Rect2(bx + bw * 0.3, by - 16, bw * 0.4, 6), COL_BUSH)

func _draw_player(px: float, py: float) -> void:
	var w = PLAYER_SIZE.x
	var h = PLAYER_SIZE.y
	var leg_offset = 0.0
	if on_ground and (game_state == 1 or game_state == 3):
		leg_offset = sin(player_anim_frame * 2.0) * 4.0
	# Overalls
	draw_rect(Rect2(px + 4, py + h * 0.5, w - 8, h * 0.3), COL_PLAYER_BLUE)
	# Shirt
	draw_rect(Rect2(px + 4, py + h * 0.25, w - 8, h * 0.3), COL_PLAYER_RED)
	# Head
	draw_rect(Rect2(px + 6, py + h * 0.08, w - 12, h * 0.22), COL_PLAYER_SKIN)
	# Cap
	draw_rect(Rect2(px + 2, py, w - 2, h * 0.15), COL_PLAYER_RED)
	draw_rect(Rect2(px + w * 0.5, py + h * 0.1, w * 0.55, h * 0.06), COL_PLAYER_RED)
	# M emblem
	draw_rect(Rect2(px + 10, py + 2, 6, 4), Color.WHITE)
	# Mustache
	draw_rect(Rect2(px + w * 0.4, py + h * 0.22, w * 0.5, 3), COL_GOOMBA)
	# Eye
	draw_rect(Rect2(px + w * 0.55, py + h * 0.13, 4, 4), Color.WHITE)
	draw_rect(Rect2(px + w * 0.6, py + h * 0.14, 2, 3), Color.BLACK)
	# Legs
	var leg1_y = py + h * 0.78 + leg_offset
	var leg2_y = py + h * 0.78 - leg_offset
	draw_rect(Rect2(px + 6, leg1_y, 8, h * 0.22), COL_PLAYER_BLUE)
	draw_rect(Rect2(px + w - 14, leg2_y, 8, h * 0.22), COL_PLAYER_BLUE)
	# Shoes
	draw_rect(Rect2(px + 4, leg1_y + h * 0.16, 12, h * 0.08), COL_GOOMBA)
	draw_rect(Rect2(px + w - 16, leg2_y + h * 0.16, 12, h * 0.08), COL_GOOMBA)
	# Arms
	if not on_ground and game_state != 3:
		draw_rect(Rect2(px, py + h * 0.2, 6, h * 0.15), COL_PLAYER_RED)
		draw_rect(Rect2(px + w - 6, py + h * 0.2, 6, h * 0.15), COL_PLAYER_RED)
		draw_rect(Rect2(px, py + h * 0.15, 6, 5), COL_PLAYER_SKIN)
		draw_rect(Rect2(px + w - 6, py + h * 0.15, 6, 5), COL_PLAYER_SKIN)
	else:
		draw_rect(Rect2(px, py + h * 0.3 + abs(leg_offset) * 0.3, 6, h * 0.2), COL_PLAYER_RED)
		draw_rect(Rect2(px + w - 6, py + h * 0.3 + abs(leg_offset) * 0.3, 6, h * 0.2), COL_PLAYER_RED)

func _draw_hud() -> void:
	if game_state == 0:
		return
	# Semi-transparent HUD background
	draw_rect(Rect2(0, 0, screen_w, 36), Color(0, 0, 0, 0.3))
	# Score
	draw_string(ThemeDB.fallback_font, Vector2(12, 26), "SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	draw_string(ThemeDB.fallback_font, Vector2(12, 26), "\n%d" % points, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	# Level
	draw_string(ThemeDB.fallback_font, Vector2(screen_w / 2 - 30, 26), "WORLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	draw_string(ThemeDB.fallback_font, Vector2(screen_w / 2 - 30, 26), "\n1-%d" % level_num, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	# Time
	draw_string(ThemeDB.fallback_font, Vector2(screen_w - 80, 26), "TIME", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	var time_col = Color.WHITE if time_bonus > 50 else Color(1, 0.3, 0.2)
	draw_string(ThemeDB.fallback_font, Vector2(screen_w - 80, 26), "\n%d" % time_bonus, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, time_col)
	# Coin
	_draw_coin(screen_w * 0.3, 20)
	draw_string(ThemeDB.fallback_font, Vector2(screen_w * 0.3 + 16, 26), "x%d" % (points / 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_COIN)

func _draw_title() -> void:
	draw_rect(Rect2(0, 0, screen_w, screen_h), Color(0, 0, 0, 0.3))
	var mid_x = screen_w / 2.0
	var mid_y = screen_h / 2.0
	draw_string(ThemeDB.fallback_font, Vector2(mid_x - 150, mid_y - 60),
		"SUPER PLUMBER RUN", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(mid_x - 55, mid_y - 20),
		"It's-a me!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COL_PLAYER_RED)
	var alpha = sin(Time.get_ticks_msec() / 400.0) * 0.3 + 0.7
	draw_string(ThemeDB.fallback_font, Vector2(mid_x - 70, mid_y + 40),
		"TAP TO START", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, alpha))
	_draw_player(mid_x - PLAYER_SIZE.x / 2, mid_y + 60)

func _draw_game_over() -> void:
	draw_rect(Rect2(0, 0, screen_w, screen_h), Color(0, 0, 0, 0.5))
	var mid_x = screen_w / 2.0
	var mid_y = screen_h / 2.0
	draw_string(ThemeDB.fallback_font, Vector2(mid_x - 80, mid_y - 50),
		"GAME OVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, COL_PLAYER_RED)
	draw_string(ThemeDB.fallback_font, Vector2(mid_x - 60, mid_y),
		"Score: %d" % points, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	var alpha = sin(Time.get_ticks_msec() / 400.0) * 0.3 + 0.7
	draw_string(ThemeDB.fallback_font, Vector2(mid_x - 70, mid_y + 50),
		"TAP TO RETRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, alpha))
