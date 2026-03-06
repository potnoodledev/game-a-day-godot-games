extends CanvasLayer

var hp_bar_bg: ColorRect
var hp_bar_fill: ColorRect
var score_label: Label
var wave_label: Label
var combo_label: Label
var center_label: Label
var controls_label: Label

func _ready():
	# HP bar background
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.color = Color(0.2, 0.2, 0.2, 0.8)
	hp_bar_bg.size = Vector2(300, 24)
	hp_bar_bg.position = Vector2(20, 20)
	add_child(hp_bar_bg)
	
	# HP bar fill
	hp_bar_fill = ColorRect.new()
	hp_bar_fill.color = Color(0.2, 0.8, 0.2)
	hp_bar_fill.size = Vector2(300, 24)
	hp_bar_fill.position = Vector2(20, 20)
	add_child(hp_bar_fill)
	
	# Score
	score_label = Label.new()
	score_label.position = Vector2(20, 52)
	score_label.add_theme_font_size_override("font_size", 28)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	score_label.add_theme_constant_override("shadow_offset_x", 2)
	score_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(score_label)
	
	# Wave
	wave_label = Label.new()
	wave_label.add_theme_font_size_override("font_size", 22)
	wave_label.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	wave_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	wave_label.add_theme_constant_override("shadow_offset_x", 2)
	wave_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(wave_label)
	
	# Combo
	combo_label = Label.new()
	combo_label.add_theme_font_size_override("font_size", 36)
	combo_label.add_theme_color_override("font_color", Color(1, 0.4, 0.1))
	combo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	combo_label.add_theme_constant_override("shadow_offset_x", 2)
	combo_label.add_theme_constant_override("shadow_offset_y", 2)
	combo_label.visible = false
	add_child(combo_label)
	
	# Center label (start/game over)
	center_label = Label.new()
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.add_theme_font_size_override("font_size", 42)
	center_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	center_label.add_theme_constant_override("shadow_offset_x", 3)
	center_label.add_theme_constant_override("shadow_offset_y", 3)
	add_child(center_label)
	
	# Controls hint
	controls_label = Label.new()
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.add_theme_font_size_override("font_size", 18)
	controls_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	controls_label.text = "TAP to punch  |  SWIPE to dodge"
	add_child(controls_label)

func _process(_delta):
	var vp_size = get_viewport().get_visible_rect().size
	wave_label.position = Vector2(vp_size.x - 180, 20)
	center_label.position = Vector2(0, vp_size.y * 0.3)
	center_label.size = Vector2(vp_size.x, vp_size.y * 0.4)
	combo_label.position = Vector2(vp_size.x / 2 - 60, 90)
	controls_label.position = Vector2(vp_size.x / 2 - 140, vp_size.y - 40)

func update_hp(current: float, maximum: float):
	var ratio = current / maximum
	hp_bar_fill.size.x = 300.0 * ratio
	hp_bar_fill.color = Color(1.0 - ratio, ratio, 0.1)

func update_score(value: int):
	score_label.text = "Score: %d" % value

func update_wave(value: int):
	wave_label.text = "Wave %d" % value

func update_combo(value: int):
	if value > 1:
		combo_label.visible = true
		combo_label.text = "%dx COMBO!" % value
		combo_label.add_theme_font_size_override("font_size", 36 + value * 2)
	else:
		combo_label.visible = false

func show_start():
	center_label.text = "ARENA FIGHTER\n\nTap to Start"
	center_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	center_label.visible = true
	controls_label.visible = true

func show_game_over(final_score: int, final_wave: int):
	center_label.text = "K.O.!\n\nScore: %d\nWave: %d\n\nTap to retry" % [final_score, final_wave]
	center_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	center_label.visible = true

func hide_center():
	center_label.visible = false
	controls_label.visible = false
