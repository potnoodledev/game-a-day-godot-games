extends CanvasLayer

var score_label: Label
var level_label: Label
var lives_label: Label
var center_label: Label
var feedback_label: Label
var controls_label: Label
var urgency_bar: ColorRect

func _ready():
	# Score
	score_label = Label.new()
	score_label.position = Vector2(20, 20)
	score_label.add_theme_font_size_override("font_size", 32)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	score_label.add_theme_constant_override("shadow_offset_x", 2)
	score_label.add_theme_constant_override("shadow_offset_y", 2)
	score_label.text = "Score: 0"
	add_child(score_label)

	# Level
	level_label = Label.new()
	level_label.add_theme_font_size_override("font_size", 24)
	level_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	level_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	level_label.add_theme_constant_override("shadow_offset_x", 2)
	level_label.add_theme_constant_override("shadow_offset_y", 2)
	level_label.text = "Level 1"
	add_child(level_label)

	# Lives (hearts)
	lives_label = Label.new()
	lives_label.add_theme_font_size_override("font_size", 28)
	lives_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	lives_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lives_label.add_theme_constant_override("shadow_offset_x", 2)
	lives_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(lives_label)

	# Center label
	center_label = Label.new()
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.add_theme_font_size_override("font_size", 40)
	center_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	center_label.add_theme_constant_override("shadow_offset_x", 3)
	center_label.add_theme_constant_override("shadow_offset_y", 3)
	add_child(center_label)

	# Feedback label
	feedback_label = Label.new()
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	feedback_label.add_theme_font_size_override("font_size", 52)
	feedback_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	feedback_label.add_theme_constant_override("shadow_offset_x", 3)
	feedback_label.add_theme_constant_override("shadow_offset_y", 3)
	feedback_label.visible = false
	add_child(feedback_label)

	# Urgency bar (bottom of screen, pulses red when wall is close)
	urgency_bar = ColorRect.new()
	urgency_bar.color = Color(1, 0.2, 0.1, 0)
	urgency_bar.size = Vector2(800, 4)
	urgency_bar.position = Vector2(0, 0)
	add_child(urgency_bar)

	# Controls hint (persistent during gameplay)
	controls_label = Label.new()
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.add_theme_font_size_override("font_size", 16)
	controls_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	controls_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	controls_label.add_theme_constant_override("shadow_offset_x", 1)
	controls_label.add_theme_constant_override("shadow_offset_y", 1)
	controls_label.text = "Tap: rotate  |  Swipe: flip"
	add_child(controls_label)

func _process(_delta):
	var vp_size = get_viewport().get_visible_rect().size
	level_label.position = Vector2(vp_size.x - 150, 20)
	lives_label.position = Vector2(vp_size.x - 150, 52)
	center_label.position = Vector2(0, vp_size.y * 0.2)
	center_label.size = Vector2(vp_size.x, vp_size.y * 0.6)
	feedback_label.position = Vector2(0, vp_size.y * 0.3)
	feedback_label.size = Vector2(vp_size.x, vp_size.y * 0.3)
	controls_label.position = Vector2(vp_size.x / 2 - 120, vp_size.y - 30)
	urgency_bar.size.x = vp_size.x
	urgency_bar.position.y = vp_size.y - 4

func update_score(value: int):
	score_label.text = "Score: %d" % value

func update_level(value: int):
	level_label.text = "Level %d" % value

func update_lives(value: int):
	var hearts = ""
	for i in range(value):
		hearts += "♥ "
	lives_label.text = hearts

func set_urgency(amount: float):
	urgency_bar.color = Color(1, 0.2, 0.1, amount * 0.6)

func show_start():
	center_label.text = "FIT THE BLOCK\n\nRotate the shape to\nfit through the wall!\n\nTap to rotate | Swipe to flip\n\nTap to Start"
	center_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	center_label.visible = true

func show_game_over(final_score: int, final_level: int):
	center_label.text = "GAME OVER\n\nScore: %d\nLevel: %d\n\nTap to retry" % [final_score, final_level]
	center_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	center_label.visible = true

func show_feedback(text: String, color: Color):
	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", color)
	feedback_label.visible = true
	get_tree().create_timer(0.8).timeout.connect(func(): feedback_label.visible = false)

func hide_center():
	center_label.visible = false
