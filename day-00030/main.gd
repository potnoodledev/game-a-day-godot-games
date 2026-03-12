extends Node3D

# =============================================================================
# TERRAFORMING MARS — Day 30
# Engine-builder inspired by the board game.
# Horizontal card hand + icon action bar for mobile.
# =============================================================================

enum Phase { LOADING, INTRO, ACTIONS, WON, LOST }
var phase: int = Phase.LOADING
var points: int = 0

const MAX_TEMP_STEPS := 19
const MAX_OXY_STEPS := 14
const MAX_OCEAN_STEPS := 9
var temp_steps: int = 0
var oxy_steps: int = 0
var ocean_steps: int = 0
var display_temp: float = 0.0
var display_oxy: float = 0.0
var display_ocean: float = 0.0

var credits: int = 14
var tr: int = 14
var heat: int = 0
var plants: int = 0
var heat_prod: int = 0
var plant_prod: int = 0
var credit_prod: int = 0
var generation: int = 0
var cards_played: int = 0
var actions_this_turn: int = 0
const MAX_GENERATIONS := 20

var tags: Dictionary = {"space": 0, "science": 0, "building": 0, "plant": 0, "energy": 0, "microbe": 0}

var card_pool: Array = []
var draft_choices: Array = []
var played_blue_cards: Array = []

# 3D
var planet_mesh: MeshInstance3D
var atmosphere_mesh: MeshInstance3D
var camera: Camera3D
var camera_angle: float = 0.0
var flash_timer: float = 0.0
var flash_color: Color = Color.WHITE
var planet_patches: Array = []  # {mesh: MeshInstance3D, timer: float, max_time: float}

# UI references
var canvas: CanvasLayer
var top_bar: PanelContainer
var status_label: Label
var bars: Dictionary = {}
var resource_label: Label
var hand_container: HBoxContainer  # horizontal card hand
var action_bar: HBoxContainer      # fixed bottom action buttons
var bottom_control: Control
var message_label: Label
var message_timer: float = 0.0
var intro_panel: PanelContainer
var card_panels: Array = []
var end_game_panel: Control


func _ready() -> void:
	_build_card_pool()
	_setup_3d_scene()
	_setup_ui()
	Api.load_state(func(ok: bool, data) -> void:
		if ok and data is Dictionary and data.has("data") and data["data"] is Dictionary:
			var d: Dictionary = data["data"]
			temp_steps = d.get("temp_steps", 0)
			oxy_steps = d.get("oxy_steps", 0)
			ocean_steps = d.get("ocean_steps", 0)
			credits = d.get("credits", 14)
			tr = d.get("tr", 14)
			heat = d.get("heat", 0)
			plants = d.get("plants", 0)
			heat_prod = d.get("heat_prod", 0)
			plant_prod = d.get("plant_prod", 0)
			credit_prod = d.get("credit_prod", 0)
			generation = d.get("generation", 0)
			cards_played = d.get("cards_played", 0)
			points = d.get("points", 0)
			var saved_tags = d.get("tags", {})
			if saved_tags is Dictionary:
				for t_key in tags:
					tags[t_key] = saved_tags.get(t_key, 0)
			display_temp = float(temp_steps) / MAX_TEMP_STEPS
			display_oxy = float(oxy_steps) / MAX_OXY_STEPS
			display_ocean = float(ocean_steps) / MAX_OCEAN_STEPS
			if generation >= MAX_GENERATIONS or _is_terraformed():
				phase = Phase.WON if _is_terraformed() else Phase.LOST
				_update_planet_visuals()
				_update_top_bar()
				_show_end_screen()
				return
			_update_planet_visuals()
			_update_top_bar()
		_show_intro()
	)


func _process(delta: float) -> void:
	camera_angle += delta * 0.06
	var cam_dist := 11.0
	camera.position = Vector3(sin(camera_angle) * cam_dist, 1.5 + sin(camera_angle * 0.3) * 0.5, cos(camera_angle) * cam_dist)
	camera.look_at(Vector3(0, -0.2, 0), Vector3.UP)

	# Animate planet patches (fade out)
	var i := 0
	while i < planet_patches.size():
		var patch: Dictionary = planet_patches[i]
		var ptimer: float = float(patch["timer"]) - delta
		patch["timer"] = ptimer
		if ptimer <= 0:
			var m = patch["mesh"]
			if m is Node:
				m.queue_free()
			planet_patches.remove_at(i)
		else:
			var alpha: float = float(patch["timer"]) / float(patch["max_time"])
			var mesh_node = patch["mesh"]
			if mesh_node is MeshInstance3D:
				var mat = mesh_node.material_override
				if mat is StandardMaterial3D:
					mat.albedo_color.a = alpha * 0.85
					mat.emission_energy_multiplier = alpha * 3.0
			i += 1

	var target_t := float(temp_steps) / MAX_TEMP_STEPS
	var target_o := float(oxy_steps) / MAX_OXY_STEPS
	var target_w := float(ocean_steps) / MAX_OCEAN_STEPS
	display_temp = lerp(display_temp, target_t, delta * 3.0)
	display_oxy = lerp(display_oxy, target_o, delta * 3.0)
	display_ocean = lerp(display_ocean, target_w, delta * 3.0)
	_update_planet_shader()
	_update_bars()

	if flash_timer > 0:
		flash_timer -= delta
		var mat: ShaderMaterial = planet_mesh.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("flash_intensity", max(0.0, flash_timer / 0.8))
			mat.set_shader_parameter("flash_color", Vector3(flash_color.r, flash_color.g, flash_color.b))

	if message_timer > 0:
		message_timer -= delta
		if message_timer <= 0:
			message_label.text = ""
			message_label.visible = false

	_layout_ui()


# =============================================================================
# TURN FLOW
# =============================================================================

func _show_intro() -> void:
	phase = Phase.INTRO
	intro_panel.visible = true
	bottom_control.visible = false

func _on_start_pressed() -> void:
	intro_panel.visible = false
	bottom_control.visible = true
	_start_new_turn()

func _start_new_turn() -> void:
	generation += 1
	actions_this_turn = 0
	if generation > MAX_GENERATIONS:
		_end_game()
		return
	if generation > 1:
		credits += tr + credit_prod
		heat += heat_prod
		plants += plant_prod
	_deal_draft()
	phase = Phase.ACTIONS
	_rebuild_hand()
	_rebuild_action_bar()
	_update_top_bar()

func _deal_draft() -> void:
	draft_choices.clear()
	var available: Array = []
	for card in card_pool:
		var prereq: Dictionary = card.get("prereq", {})
		var ok := true
		if prereq.has("temp") and temp_steps < int(prereq["temp"]):
			ok = false
		if prereq.has("oxy") and oxy_steps < int(prereq["oxy"]):
			ok = false
		if prereq.has("ocean") and ocean_steps < int(prereq["ocean"]):
			ok = false
		if prereq.has("tag"):
			var tag_req: Dictionary = prereq["tag"]
			for t_key in tag_req:
				if tags.get(t_key, 0) < int(tag_req[t_key]):
					ok = false
		if ok:
			available.append(card)
	available.shuffle()
	var blues: Array = []
	var others: Array = []
	for c in available:
		if c["type"] == "blue":
			blues.append(c)
		else:
			others.append(c)
	if generation <= 6 and blues.size() > 0 and others.size() >= 2:
		draft_choices.append(blues[0])
		draft_choices.append(others[0])
		draft_choices.append(others[1])
	else:
		for i in range(min(3, available.size())):
			draft_choices.append(available[i])
	draft_choices.shuffle()


# =============================================================================
# ACTIONS
# =============================================================================

func _raise_temp() -> void:
	if temp_steps < MAX_TEMP_STEPS:
		temp_steps += 1
		tr += 1
		_flash_planet(Color(1.0, 0.4, 0.1))
		_spawn_planet_patches(Color(1.0, 0.35, 0.05), 3, randf_range(0.15, 0.3))
		_show_message("+1 Temp, +1 Income")
		_update_planet_visuals()
		_update_top_bar()
		_save_game()
		if _is_terraformed():
			_end_game()

func _raise_oxygen() -> void:
	if oxy_steps < MAX_OXY_STEPS:
		oxy_steps += 1
		tr += 1
		_flash_planet(Color(0.3, 0.9, 0.3))
		_spawn_planet_patches(Color(0.15, 0.7, 0.1), 4, randf_range(0.2, 0.4))
		if oxy_steps == 8 and temp_steps < MAX_TEMP_STEPS:
			temp_steps += 1
			tr += 1
			_spawn_planet_patches(Color(1.0, 0.35, 0.05), 2, 0.2)
			_show_message("+1 O2, +1 Temp bonus!")
		else:
			_show_message("+1 O2, +1 Income")
		_update_planet_visuals()
		_update_top_bar()
		_save_game()
		if _is_terraformed():
			_end_game()

func _raise_ocean() -> void:
	if ocean_steps < MAX_OCEAN_STEPS:
		ocean_steps += 1
		tr += 1
		_flash_planet(Color(0.2, 0.5, 1.0))
		_spawn_planet_patches(Color(0.1, 0.4, 1.0), 3, randf_range(0.2, 0.35))
		_show_message("+1 Ocean, +1 Income")
		_update_planet_visuals()
		_update_top_bar()
		_save_game()
		if _is_terraformed():
			_end_game()

func _on_convert_heat() -> void:
	if phase != Phase.ACTIONS or heat < 8 or temp_steps >= MAX_TEMP_STEPS:
		return
	heat -= 8
	_raise_temp()
	actions_this_turn += 1
	_rebuild_hand()
	_rebuild_action_bar()

func _on_convert_plants() -> void:
	if phase != Phase.ACTIONS or plants < 8 or oxy_steps >= MAX_OXY_STEPS:
		return
	plants -= 8
	_raise_oxygen()
	actions_this_turn += 1
	_rebuild_hand()
	_rebuild_action_bar()

func _on_std_asteroid() -> void:
	if phase != Phase.ACTIONS or credits < 14 or temp_steps >= MAX_TEMP_STEPS:
		return
	credits -= 14
	_raise_temp()
	actions_this_turn += 1
	_rebuild_hand()
	_rebuild_action_bar()

func _on_std_aquifer() -> void:
	if phase != Phase.ACTIONS or credits < 18 or ocean_steps >= MAX_OCEAN_STEPS:
		return
	credits -= 18
	_raise_ocean()
	actions_this_turn += 1
	_rebuild_hand()
	_rebuild_action_bar()

func _on_std_greenery() -> void:
	if phase != Phase.ACTIONS or credits < 23 or oxy_steps >= MAX_OXY_STEPS:
		return
	credits -= 23
	_raise_oxygen()
	actions_this_turn += 1
	_rebuild_hand()
	_rebuild_action_bar()

func _on_card_drafted(idx: int) -> void:
	if phase != Phase.ACTIONS or idx >= draft_choices.size():
		return
	var card: Dictionary = draft_choices[idx]
	var total_cost: int = int(card["cost"]) + 3
	var discount := 0
	var card_tags: Array = card.get("tags", [])
	for t in card_tags:
		discount += tags.get(t, 0)
	discount = min(discount, int(card["cost"]))
	total_cost -= discount

	if credits < total_cost:
		_show_message("Need %d cr!" % total_cost)
		return

	credits -= total_cost
	cards_played += 1
	actions_this_turn += 1
	for t in card_tags:
		tags[t] = tags.get(t, 0) + 1

	var effects: Dictionary = card["effects"]
	var parts: Array = []
	var temp_raise := int(effects.get("temp", 0))
	for _i in range(temp_raise):
		if temp_steps < MAX_TEMP_STEPS:
			temp_steps += 1
			tr += 1
	if temp_raise > 0:
		parts.append("+%d Temp" % temp_raise)
		_flash_planet(Color(1.0, 0.4, 0.1))
	var oxy_raise := int(effects.get("oxy", 0))
	for _i in range(oxy_raise):
		if oxy_steps < MAX_OXY_STEPS:
			oxy_steps += 1
			tr += 1
			if oxy_steps == 8 and temp_steps < MAX_TEMP_STEPS:
				temp_steps += 1
				tr += 1
	if oxy_raise > 0:
		parts.append("+%d O2" % oxy_raise)
		_flash_planet(Color(0.3, 0.9, 0.3))
	var ocean_raise := int(effects.get("ocean", 0))
	for _i in range(ocean_raise):
		if ocean_steps < MAX_OCEAN_STEPS:
			ocean_steps += 1
			tr += 1
	if ocean_raise > 0:
		parts.append("+%d Ocean" % ocean_raise)
		_flash_planet(Color(0.2, 0.5, 1.0))
	heat += int(effects.get("heat", 0))
	if int(effects.get("heat", 0)) > 0:
		parts.append("+%d Heat" % int(effects.get("heat", 0)))
	plants += int(effects.get("plants", 0))
	if int(effects.get("plants", 0)) > 0:
		parts.append("+%d Plants" % int(effects.get("plants", 0)))
	var cp := int(effects.get("credit_prod", 0))
	credit_prod += cp
	if cp > 0:
		parts.append("+%d Cr/gen" % cp)
	var hp := int(effects.get("heat_prod", 0))
	heat_prod += hp
	if hp > 0:
		parts.append("+%d Heat/gen" % hp)
	var pp := int(effects.get("plant_prod", 0))
	plant_prod += pp
	if pp > 0:
		parts.append("+%d Plant/gen" % pp)
	var tr_bonus := int(effects.get("tr", 0))
	tr += tr_bonus
	if tr_bonus > 0:
		parts.append("+%d TR" % tr_bonus)

	draft_choices.remove_at(idx)
	_show_message(str(card["name"]) + ": " + ", ".join(parts))
	_update_planet_visuals()
	_update_top_bar()
	_rebuild_hand()
	_rebuild_action_bar()
	_save_game()
	if _is_terraformed():
		_end_game()

func _on_end_turn() -> void:
	if phase != Phase.ACTIONS:
		return
	phase = Phase.LOADING
	_start_new_turn()


# =============================================================================
# END GAME
# =============================================================================

func _is_terraformed() -> bool:
	return temp_steps >= MAX_TEMP_STEPS and oxy_steps >= MAX_OXY_STEPS and ocean_steps >= MAX_OCEAN_STEPS

func _end_game() -> void:
	if _is_terraformed():
		phase = Phase.WON
		points = tr * 10 + cards_played * 5 + max(0, (MAX_GENERATIONS - generation) * 50)
	else:
		phase = Phase.LOST
		points = tr * 5
	Api.submit_score(points, func(_ok: bool, _result) -> void: pass)
	_save_game()
	_show_end_screen()

func _show_end_screen() -> void:
	# Hide hand and action bar, show end panel
	for child in hand_container.get_children():
		child.queue_free()
	for child in action_bar.get_children():
		child.queue_free()

	# Build end game card in the hand area
	var vp := get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.15, 0.08) if phase == Phase.WON else Color(0.2, 0.08, 0.05)
	s.corner_radius_top_left = 12
	s.corner_radius_top_right = 12
	s.corner_radius_bottom_left = 12
	s.corner_radius_bottom_right = 12
	s.border_width_top = 3
	s.border_width_bottom = 3
	s.border_width_left = 3
	s.border_width_right = 3
	s.border_color = Color(0.3, 1.0, 0.5) if phase == Phase.WON else Color(1.0, 0.3, 0.2)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", s)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "MARS LIVES!" if phase == Phase.WON else "TIME'S UP"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 1, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var score := Label.new()
	score.text = "Score: %d" % points
	score.add_theme_font_size_override("font_size", 20)
	score.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(score)

	var details := Label.new()
	if phase == Phase.WON:
		details.text = "Income %d  |  Gen %d  |  Cards %d" % [tr, generation, cards_played]
	else:
		details.text = "Income %d  |  T %d/%d  O2 %d/%d  W %d/%d" % [tr, temp_steps, MAX_TEMP_STEPS, oxy_steps, MAX_OXY_STEPS, ocean_steps, MAX_OCEAN_STEPS]
	details.add_theme_font_size_override("font_size", 14)
	details.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(details)

	hand_container.add_child(panel)

	# Play Again button in action bar
	var btn := Button.new()
	btn.text = "PLAY AGAIN"
	btn.add_theme_font_size_override("font_size", 16)
	btn.custom_minimum_size.y = 50
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_stylebox_override("normal", _make_action_btn_style(Color(0.15, 0.45, 0.15)))
	btn.add_theme_stylebox_override("hover", _make_action_btn_style(Color(0.2, 0.55, 0.2)))
	btn.pressed.connect(_on_restart)
	action_bar.add_child(btn)

func _on_restart() -> void:
	temp_steps = 0
	oxy_steps = 0
	ocean_steps = 0
	display_temp = 0.0
	display_oxy = 0.0
	display_ocean = 0.0
	credits = 14
	tr = 14
	heat = 0
	plants = 0
	heat_prod = 0
	plant_prod = 0
	credit_prod = 0
	generation = 0
	cards_played = 0
	actions_this_turn = 0
	points = 0
	for t_key in tags:
		tags[t_key] = 0
	played_blue_cards.clear()
	_update_planet_visuals()
	_update_top_bar()
	_show_intro()


# =============================================================================
# 3D SCENE
# =============================================================================

func _setup_3d_scene() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.5, 11.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.fov = 40
	add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -20, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	# Fill light from opposite side
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 160, 0)
	fill.light_energy = 0.4
	fill.shadow_enabled = false
	add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.17, 0.15)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	_create_planet()
	_create_atmosphere()
	_create_stars()

func _create_planet() -> void:
	planet_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 3.0
	sphere.height = 6.0
	sphere.radial_segments = 64
	sphere.rings = 32
	planet_mesh.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = _create_planet_shader()
	mat.set_shader_parameter("terraform_temp", 0.0)
	mat.set_shader_parameter("terraform_oxygen", 0.0)
	mat.set_shader_parameter("terraform_oceans", 0.0)
	mat.set_shader_parameter("flash_intensity", 0.0)
	mat.set_shader_parameter("flash_color", Vector3(1, 1, 1))
	planet_mesh.material_override = mat
	add_child(planet_mesh)

func _create_planet_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform float terraform_temp : hint_range(0.0, 1.0) = 0.0;
uniform float terraform_oxygen : hint_range(0.0, 1.0) = 0.0;
uniform float terraform_oceans : hint_range(0.0, 1.0) = 0.0;
uniform float flash_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color = vec3(1.0);
varying vec3 world_pos;
float hash(vec3 p) { p = fract(p * vec3(443.897, 441.423, 437.195)); p += dot(p, p.yzx + 19.19); return fract((p.x + p.y) * p.z); }
float noise3d(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = hash(i); float b = hash(i + vec3(1,0,0)); float c = hash(i + vec3(0,1,0)); float d = hash(i + vec3(1,1,0));
	float e = hash(i + vec3(0,0,1)); float ff = hash(i + vec3(1,0,1)); float g = hash(i + vec3(0,1,1)); float h = hash(i + vec3(1,1,1));
	return mix(mix(mix(a,b,f.x), mix(c,d,f.x), f.y), mix(mix(e,ff,f.x), mix(g,h,f.x), f.y), f.z);
}
float fbm(vec3 p) { float val = 0.0; float amp = 0.5; for (int i = 0; i < 5; i++) { val += amp * noise3d(p); p *= 2.1; amp *= 0.5; } return val; }
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; float h = fbm(normalize(VERTEX) * 4.0) * 0.3; VERTEX += NORMAL * h; }
void fragment() {
	vec3 n = normalize(world_pos); float h = fbm(n * 4.0); float pole = abs(n.y);
	vec3 mars_low = vec3(0.6, 0.25, 0.1); vec3 mars_high = vec3(0.85, 0.55, 0.3);
	vec3 col = mix(mars_low, mars_high, h);
	float ice = smoothstep(0.75, 0.85, pole); col = mix(col, vec3(0.9, 0.92, 0.95), ice * 0.7);
	float green_zone = 1.0 - pole; float green_noise = fbm(n * 8.0);
	float green_mask = smoothstep(0.3, 0.7, green_zone) * smoothstep(0.3, 0.6, green_noise);
	vec3 green_col = mix(vec3(0.12, 0.35, 0.08), vec3(0.2, 0.55, 0.15), green_noise);
	col = mix(col, green_col, green_mask * terraform_oxygen);
	float ocean_level = terraform_oceans * 0.45; float depth = ocean_level - h;
	if (depth > 0.0) { vec3 shallow = vec3(0.1, 0.4, 0.7); vec3 deep_water = vec3(0.04, 0.12, 0.35);
		vec3 water_col = mix(shallow, deep_water, clamp(depth * 5.0, 0.0, 1.0));
		col = mix(col, water_col, clamp(depth * 10.0, 0.0, 0.95)); }
	col = mix(col, flash_color, flash_intensity * 0.4);
	ALBEDO = col; float water_factor = clamp(depth * 10.0, 0.0, 1.0) * step(0.0, depth);
	ROUGHNESS = mix(0.9, 0.3, water_factor); METALLIC = water_factor * 0.15;
}
"""
	return shader

func _create_atmosphere() -> void:
	atmosphere_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 3.4
	sphere.height = 6.8
	sphere.radial_segments = 32
	sphere.rings = 16
	atmosphere_mesh.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """
shader_type spatial;
render_mode blend_add, cull_front, unshaded;
uniform float atmosphere_density : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	vec3 atmo_color = mix(vec3(0.8, 0.3, 0.1), vec3(0.4, 0.6, 1.0), atmosphere_density);
	ALBEDO = atmo_color; ALPHA = fresnel * atmosphere_density * 0.6;
}
"""
	mat.set_shader_parameter("atmosphere_density", 0.0)
	mat.render_priority = 1
	atmosphere_mesh.material_override = mat
	add_child(atmosphere_mesh)

func _create_stars() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var s := SphereMesh.new()
	s.radius = 0.03
	s.height = 0.06
	mm.mesh = s
	mm.instance_count = 400
	for i in range(400):
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var t := Transform3D()
		t.origin = dir * randf_range(25, 55)
		mm.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 0.9)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmi.material_override = mat
	add_child(mmi)

func _flash_planet(color: Color) -> void:
	flash_color = color
	flash_timer = 0.8

func _spawn_planet_patches(color: Color, count: int, patch_size: float) -> void:
	for _i in range(count):
		# Random point on visible hemisphere (facing camera)
		var cam_dir := -camera.global_transform.basis.z.normalized()
		var up := Vector3.UP
		var right := cam_dir.cross(up).normalized()
		up = right.cross(cam_dir).normalized()
		# Random offset within visible face
		var angle := randf() * TAU
		var radius := randf_range(0.1, 0.8)
		var offset := right * cos(angle) * radius + up * sin(angle) * radius
		var point := (cam_dir + offset).normalized() * 3.05  # slightly above planet surface

		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = patch_size
		sphere.height = patch_size * 2.0
		sphere.radial_segments = 12
		sphere.rings = 6
		mesh.mesh = sphere
		mesh.position = point

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mesh.material_override = mat
		add_child(mesh)

		var life := randf_range(4.0, 8.0)
		planet_patches.append({"mesh": mesh, "timer": life, "max_time": life})

func _update_planet_shader() -> void:
	var mat: ShaderMaterial = planet_mesh.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("terraform_temp", display_temp)
		mat.set_shader_parameter("terraform_oxygen", display_oxy)
		mat.set_shader_parameter("terraform_oceans", display_ocean)
	var atmo_mat: ShaderMaterial = atmosphere_mesh.material_override as ShaderMaterial
	if atmo_mat:
		atmo_mat.set_shader_parameter("atmosphere_density", (display_temp + display_oxy + display_ocean) / 3.0)

func _update_planet_visuals() -> void:
	_update_planet_shader()
	var world_env_node := get_node_or_null("WorldEnvironment")
	if world_env_node is WorldEnvironment:
		var env: Environment = world_env_node.environment
		var progress := (display_temp + display_oxy + display_ocean) / 3.0
		env.ambient_light_color = Color(0.2, 0.17, 0.15).lerp(Color(0.3, 0.35, 0.45), progress)
		env.ambient_light_energy = 0.6 + progress * 0.6


# =============================================================================
# UI SETUP
# =============================================================================

func _make_action_btn_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

func _make_card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right = 10
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_color = border
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _setup_ui() -> void:
	canvas = CanvasLayer.new()
	add_child(canvas)

	# --- TOP BAR ---
	top_bar = PanelContainer.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0, 0, 0, 0.8)
	ts.content_margin_left = 8
	ts.content_margin_right = 8
	ts.content_margin_top = 4
	ts.content_margin_bottom = 2
	top_bar.add_theme_stylebox_override("panel", ts)
	canvas.add_child(top_bar)

	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 1)
	top_bar.add_child(tv)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(status_label)

	# Bars in a row
	var bars_row := HBoxContainer.new()
	bars_row.add_theme_constant_override("separation", 6)
	tv.add_child(bars_row)
	for p in [["T", Color(1, 0.35, 0.1), "temp"],
			  ["O2", Color(0.3, 0.85, 0.3), "oxy"],
			  ["W", Color(0.25, 0.55, 1.0), "ocean"]]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 2)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bars_row.add_child(item)
		var lbl := Label.new()
		lbl.text = p[0]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", p[1])
		item.add_child(lbl)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = 100
		bar.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = p[1]
		fill.corner_radius_top_left = 2
		fill.corner_radius_top_right = 2
		fill.corner_radius_bottom_left = 2
		fill.corner_radius_bottom_right = 2
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.15, 0.15, 0.15)
		bg.corner_radius_top_left = 2
		bg.corner_radius_top_right = 2
		bg.corner_radius_bottom_left = 2
		bg.corner_radius_bottom_right = 2
		bar.add_theme_stylebox_override("background", bg)
		item.add_child(bar)
		bars[p[2]] = {"bar": bar}

	resource_label = Label.new()
	resource_label.add_theme_font_size_override("font_size", 11)
	resource_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.45))
	resource_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(resource_label)

	# --- MESSAGE (center overlay) ---
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 18)
	message_label.add_theme_color_override("font_color", Color(1, 1, 0.6))
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	message_label.visible = false
	canvas.add_child(message_label)

	# --- BOTTOM AREA: hand + action bar ---
	bottom_control = Control.new()
	canvas.add_child(bottom_control)

	var bottom_bg := PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0, 0, 0, 0.85)
	bs.content_margin_left = 6
	bs.content_margin_right = 6
	bs.content_margin_top = 6
	bs.content_margin_bottom = 6
	bottom_bg.add_theme_stylebox_override("panel", bs)
	bottom_control.add_child(bottom_bg)

	var bottom_vbox := VBoxContainer.new()
	bottom_vbox.add_theme_constant_override("separation", 6)
	bottom_bg.add_child(bottom_vbox)

	# Hand of cards (horizontal)
	hand_container = HBoxContainer.new()
	hand_container.add_theme_constant_override("separation", 6)
	hand_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_vbox.add_child(hand_container)

	# Action bar (fixed row of buttons at bottom)
	action_bar = HBoxContainer.new()
	action_bar.add_theme_constant_override("separation", 4)
	action_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_vbox.add_child(action_bar)

	# --- INTRO PANEL ---
	intro_panel = PanelContainer.new()
	var is2 := StyleBoxFlat.new()
	is2.bg_color = Color(0.05, 0.03, 0.1, 0.95)
	is2.corner_radius_top_left = 16
	is2.corner_radius_top_right = 16
	is2.corner_radius_bottom_left = 16
	is2.corner_radius_bottom_right = 16
	is2.border_width_bottom = 3
	is2.border_width_top = 3
	is2.border_width_left = 3
	is2.border_width_right = 3
	is2.border_color = Color(1, 0.6, 0.2, 0.5)
	is2.content_margin_left = 20
	is2.content_margin_right = 20
	is2.content_margin_top = 16
	is2.content_margin_bottom = 16
	intro_panel.add_theme_stylebox_override("panel", is2)
	intro_panel.visible = false
	canvas.add_child(intro_panel)

	var intro_scroll := ScrollContainer.new()
	intro_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	intro_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	intro_panel.add_child(intro_scroll)

	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 10)
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro_scroll.add_child(iv)

	var it := Label.new()
	it.text = "TERRAFORMING MARS"
	it.add_theme_font_size_override("font_size", 22)
	it.add_theme_color_override("font_color", Color(1, 0.7, 0.3))
	it.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	iv.add_child(it)

	var itx := Label.new()
	itx.text = "Terraform Mars in 20 generations!\n\nTap cards to play them. Every parameter step you raise earns +1 Income forever.\n\nGreen = one-time  |  Blue = ongoing  |  Red = event\n\nBuild production early, compound your income, raise Temp + O2 + Oceans to win!"
	itx.add_theme_font_size_override("font_size", 14)
	itx.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	itx.autowrap_mode = TextServer.AUTOWRAP_WORD
	iv.add_child(itx)

	var sb := Button.new()
	sb.text = "START"
	sb.add_theme_font_size_override("font_size", 20)
	sb.custom_minimum_size.y = 56
	sb.add_theme_stylebox_override("normal", _make_action_btn_style(Color(0.2, 0.5, 0.2)))
	sb.add_theme_stylebox_override("hover", _make_action_btn_style(Color(0.25, 0.6, 0.25)))
	sb.pressed.connect(_on_start_pressed)
	iv.add_child(sb)

	_update_top_bar()


# =============================================================================
# LAYOUT (per-frame responsive)
# =============================================================================

func _layout_ui() -> void:
	var vp := get_viewport().get_visible_rect().size

	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(vp.x, 0)

	# Bottom area: cards + action bar
	var bottom_h: float = min(vp.y * 0.48, 340.0)
	bottom_control.position = Vector2(0, vp.y - bottom_h)
	var bp: PanelContainer = bottom_control.get_child(0)
	bp.position = Vector2.ZERO
	bp.size = Vector2(vp.x, bottom_h)

	message_label.position = Vector2(10, vp.y * 0.28)
	message_label.size = Vector2(vp.x - 20, 60)

	var margin := vp.x * 0.05
	intro_panel.position = Vector2(margin, vp.y * 0.03)
	intro_panel.size = Vector2(vp.x - margin * 2, vp.y * 0.94)


# =============================================================================
# HAND OF CARDS (horizontal, like Hearthstone)
# =============================================================================

func _rebuild_hand() -> void:
	for child in hand_container.get_children():
		child.queue_free()
	card_panels.clear()

	if phase != Phase.ACTIONS:
		return

	for i in range(draft_choices.size()):
		var card: Dictionary = draft_choices[i]
		var panel := _build_hand_card(card, i)
		hand_container.add_child(panel)
		card_panels.append(panel)

	# If no draft cards left, show "No cards" message
	if draft_choices.size() == 0:
		var lbl := Label.new()
		lbl.text = "No cards - use actions below or End Turn"
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.45))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		hand_container.add_child(lbl)


func _build_hand_card(card: Dictionary, idx: int) -> PanelContainer:
	var card_cost: int = int(card["cost"])
	var card_tags: Array = card.get("tags", [])
	var discount := 0
	for t in card_tags:
		discount += tags.get(t, 0)
	discount = min(discount, card_cost)
	var total := card_cost + 3 - discount
	var affordable := credits >= total

	var bg_col: Color
	var border_col: Color
	var type_char: String  # single letter for compact display
	if card["type"] == "green":
		bg_col = Color(0.04, 0.14, 0.04)
		border_col = Color(0.3, 0.85, 0.3) if affordable else Color(0.12, 0.25, 0.12)
		type_char = "G"
	elif card["type"] == "blue":
		bg_col = Color(0.04, 0.08, 0.18)
		border_col = Color(0.4, 0.65, 1.0) if affordable else Color(0.12, 0.18, 0.3)
		type_char = "B"
	else:
		bg_col = Color(0.18, 0.04, 0.04)
		border_col = Color(1.0, 0.4, 0.35) if affordable else Color(0.3, 0.12, 0.1)
		type_char = "R"

	if not affordable:
		bg_col = bg_col.darkened(0.3)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_card_style(bg_col, border_col))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	# Cost badge (top right feel) — cost on top, big and clear
	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 4)
	vbox.add_child(cost_row)

	# Type indicator (colored dot)
	var type_lbl := Label.new()
	type_lbl.text = type_char
	type_lbl.add_theme_font_size_override("font_size", 12)
	type_lbl.add_theme_color_override("font_color", border_col)
	cost_row.add_child(type_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_row.add_child(spacer)

	var cost_lbl := Label.new()
	cost_lbl.text = "%d" % total
	cost_lbl.add_theme_font_size_override("font_size", 18)
	cost_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if affordable else Color(0.7, 0.3, 0.2))
	cost_row.add_child(cost_lbl)

	# Card name
	var name_lbl := Label.new()
	name_lbl.text = str(card["name"])
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 0.9) if affordable else Color(0.45, 0.45, 0.4))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(name_lbl)

	# Effect text (the most important info — big and clear)
	var effect_lbl := Label.new()
	effect_lbl.text = str(card["effect_text"])
	effect_lbl.add_theme_font_size_override("font_size", 14)
	effect_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.8) if affordable else Color(0.4, 0.4, 0.35))
	effect_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	effect_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(effect_lbl)

	# PLAY button at bottom of card
	if affordable:
		var btn := Button.new()
		btn.text = "PLAY"
		btn.add_theme_font_size_override("font_size", 15)
		btn.custom_minimum_size.y = 40
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn_bg: Color = border_col.darkened(0.4)
		btn.add_theme_stylebox_override("normal", _make_action_btn_style(btn_bg))
		btn.add_theme_stylebox_override("hover", _make_action_btn_style(btn_bg.lightened(0.15)))
		var card_idx := idx
		btn.pressed.connect(func() -> void: _on_card_drafted(card_idx))
		vbox.add_child(btn)
	else:
		var cant_lbl := Label.new()
		cant_lbl.text = "-%d cr" % (total - credits)
		cant_lbl.add_theme_font_size_override("font_size", 11)
		cant_lbl.add_theme_color_override("font_color", Color(0.5, 0.25, 0.2))
		cant_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(cant_lbl)

	return panel


# =============================================================================
# ACTION BAR (always visible, clear icons)
# =============================================================================

func _rebuild_action_bar() -> void:
	for child in action_bar.get_children():
		child.queue_free()

	if phase != Phase.ACTIONS:
		return

	# Heat conversion
	var can_heat := heat >= 8 and temp_steps < MAX_TEMP_STEPS
	if heat > 0 or heat_prod > 0:
		var btn := Button.new()
		btn.text = "HEAT\n%d/8" % heat
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = not can_heat
		var col := Color(0.4, 0.18, 0.05) if can_heat else Color(0.15, 0.1, 0.06)
		btn.add_theme_stylebox_override("normal", _make_action_btn_style(col))
		btn.add_theme_stylebox_override("disabled", _make_action_btn_style(Color(0.1, 0.08, 0.05)))
		btn.tooltip_text = "Spend 8 Heat to raise Temperature +1"
		btn.pressed.connect(_on_convert_heat)
		action_bar.add_child(btn)

	# Plant conversion
	var can_plants := plants >= 8 and oxy_steps < MAX_OXY_STEPS
	if plants > 0 or plant_prod > 0:
		var btn := Button.new()
		btn.text = "PLANT\n%d/8" % plants
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = not can_plants
		var col := Color(0.12, 0.3, 0.08) if can_plants else Color(0.08, 0.12, 0.06)
		btn.add_theme_stylebox_override("normal", _make_action_btn_style(col))
		btn.add_theme_stylebox_override("disabled", _make_action_btn_style(Color(0.06, 0.08, 0.04)))
		btn.tooltip_text = "Spend 8 Plants to raise Oxygen +1"
		btn.pressed.connect(_on_convert_plants)
		action_bar.add_child(btn)

	# Separator
	var sep := VSeparator.new()
	sep.custom_minimum_size.x = 2
	action_bar.add_child(sep)

	# Standard projects — compact with clear labels
	var std_items: Array = [
		["TEMP\n14cr", 14, credits >= 14 and temp_steps < MAX_TEMP_STEPS, Color(0.4, 0.15, 0.05), "_asteroid"],
		["WATER\n18cr", 18, credits >= 18 and ocean_steps < MAX_OCEAN_STEPS, Color(0.1, 0.2, 0.45), "_aquifer"],
		["O2\n23cr", 23, credits >= 23 and oxy_steps < MAX_OXY_STEPS, Color(0.08, 0.3, 0.08), "_greenery"],
	]
	for sd in std_items:
		var btn := Button.new()
		btn.text = sd[0]
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = not sd[2]
		var col: Color = sd[3] if sd[2] else Color(0.08, 0.08, 0.1)
		btn.add_theme_stylebox_override("normal", _make_action_btn_style(col))
		btn.add_theme_stylebox_override("disabled", _make_action_btn_style(Color(0.06, 0.06, 0.06)))
		if sd[4] == "_asteroid":
			btn.tooltip_text = "Standard Project: Asteroid (14 cr) - raise Temperature +1"
			btn.pressed.connect(_on_std_asteroid)
		elif sd[4] == "_aquifer":
			btn.tooltip_text = "Standard Project: Aquifer (18 cr) - place Ocean +1"
			btn.pressed.connect(_on_std_aquifer)
		else:
			btn.tooltip_text = "Standard Project: Greenery (23 cr) - raise Oxygen +1"
			btn.pressed.connect(_on_std_greenery)
		action_bar.add_child(btn)

	# Separator
	var sep2 := VSeparator.new()
	sep2.custom_minimum_size.x = 2
	action_bar.add_child(sep2)

	# End Turn — prominent green
	var end_btn := Button.new()
	end_btn.text = "END\nTURN"
	end_btn.add_theme_font_size_override("font_size", 13)
	end_btn.custom_minimum_size = Vector2(0, 44)
	end_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_btn.add_theme_stylebox_override("normal", _make_action_btn_style(Color(0.15, 0.4, 0.15)))
	end_btn.add_theme_stylebox_override("hover", _make_action_btn_style(Color(0.2, 0.55, 0.2)))
	end_btn.pressed.connect(_on_end_turn)
	action_bar.add_child(end_btn)


# =============================================================================
# UPDATE HELPERS
# =============================================================================

func _update_bars() -> void:
	bars["temp"]["bar"].value = display_temp * 100.0
	bars["oxy"]["bar"].value = display_oxy * 100.0
	bars["ocean"]["bar"].value = display_ocean * 100.0

func _update_top_bar() -> void:
	status_label.text = "Gen %d/%d   Income %d/turn   %d cr" % [generation, MAX_GENERATIONS, tr + credit_prod, credits]
	var parts: Array = []
	if heat > 0 or heat_prod > 0:
		var s := "Heat %d" % heat
		if heat_prod > 0:
			s += "(+%d)" % heat_prod
		parts.append(s)
	if plants > 0 or plant_prod > 0:
		var s := "Plant %d" % plants
		if plant_prod > 0:
			s += "(+%d)" % plant_prod
		parts.append(s)
	if credit_prod > 0:
		parts.append("+%d cr/gen" % credit_prod)
	resource_label.text = "  ".join(parts) if parts.size() > 0 else ""
	resource_label.visible = parts.size() > 0
	_update_bars()

func _show_message(msg: String) -> void:
	message_label.text = msg
	message_label.visible = true
	message_timer = 2.5


# =============================================================================
# CARD POOL
# =============================================================================

func _build_card_pool() -> void:
	card_pool = [
		{"name": "Asteroid Mining", "cost": 10, "type": "green", "tags": ["space"],
		 "effects": {"temp": 2, "heat": 4}, "effect_text": "+2 Temp\n+4 Heat", "prereq": {}},
		{"name": "Giant Ice Asteroid", "cost": 18, "type": "green", "tags": ["space"],
		 "effects": {"temp": 2, "ocean": 2}, "effect_text": "+2 Temp\n+2 Ocean", "prereq": {}},
		{"name": "Import Nitrogen", "cost": 14, "type": "green", "tags": ["space", "science"],
		 "effects": {"oxy": 1, "temp": 1, "plants": 4}, "effect_text": "+1 O2, +1 Temp\n+4 Plants", "prereq": {}},
		{"name": "Plantation", "cost": 12, "type": "green", "tags": ["plant"],
		 "effects": {"oxy": 2}, "effect_text": "+2 O2", "prereq": {"temp": 4}},
		{"name": "Lake Formation", "cost": 10, "type": "green", "tags": ["building"],
		 "effects": {"ocean": 2}, "effect_text": "+2 Ocean", "prereq": {}},
		{"name": "Greenhouse Gases", "cost": 7, "type": "green", "tags": ["science"],
		 "effects": {"temp": 3}, "effect_text": "+3 Temp", "prereq": {}},
		{"name": "Algae", "cost": 8, "type": "green", "tags": ["plant"],
		 "effects": {"oxy": 1, "plants": 6}, "effect_text": "+1 O2\n+6 Plants", "prereq": {"ocean": 2}},
		{"name": "Polar Melt", "cost": 16, "type": "green", "tags": ["space"],
		 "effects": {"ocean": 3, "temp": 1}, "effect_text": "+3 Ocean\n+1 Temp", "prereq": {"temp": 5}},
		{"name": "Microbes", "cost": 6, "type": "green", "tags": ["microbe", "science"],
		 "effects": {"oxy": 1, "plants": 3}, "effect_text": "+1 O2\n+3 Plants", "prereq": {}},
		{"name": "Deimos Down", "cost": 24, "type": "green", "tags": ["space"],
		 "effects": {"temp": 5}, "effect_text": "+5 Temp", "prereq": {}},
		{"name": "Nuclear Power", "cost": 8, "type": "green", "tags": ["energy", "building"],
		 "effects": {"temp": 2, "heat": 6}, "effect_text": "+2 Temp\n+6 Heat", "prereq": {}},
		{"name": "Moss", "cost": 5, "type": "green", "tags": ["plant"],
		 "effects": {"oxy": 1, "plants": 4}, "effect_text": "+1 O2\n+4 Plants", "prereq": {"temp": 3}},
		{"name": "Deep Wells", "cost": 12, "type": "green", "tags": ["building", "energy"],
		 "effects": {"ocean": 1, "heat": 8}, "effect_text": "+1 Ocean\n+8 Heat", "prereq": {}},
		{"name": "Imported GHG", "cost": 5, "type": "green", "tags": ["space", "science"],
		 "effects": {"temp": 2}, "effect_text": "+2 Temp", "prereq": {}},
		{"name": "Trees", "cost": 10, "type": "green", "tags": ["plant"],
		 "effects": {"oxy": 2, "plants": 2}, "effect_text": "+2 O2\n+2 Plants", "prereq": {"temp": 6}},
		{"name": "Water Import", "cost": 16, "type": "green", "tags": ["space"],
		 "effects": {"ocean": 2, "plants": 4}, "effect_text": "+2 Ocean\n+4 Plants", "prereq": {}},
		{"name": "Research", "cost": 8, "type": "green", "tags": ["science"],
		 "effects": {"tr": 1, "plants": 3, "heat": 3}, "effect_text": "+1 TR\n+3 Plants, +3 Heat", "prereq": {}},

		{"name": "Power Grid", "cost": 10, "type": "blue", "tags": ["energy", "building"],
		 "effects": {"credit_prod": 3}, "effect_text": "+3 Cr/gen", "prereq": {}},
		{"name": "Mining Rights", "cost": 14, "type": "blue", "tags": ["building"],
		 "effects": {"credit_prod": 5}, "effect_text": "+5 Cr/gen", "prereq": {}},
		{"name": "Heat Traps", "cost": 7, "type": "blue", "tags": ["energy"],
		 "effects": {"heat_prod": 4}, "effect_text": "+4 Heat/gen", "prereq": {}},
		{"name": "Forest Reserve", "cost": 10, "type": "blue", "tags": ["plant"],
		 "effects": {"plant_prod": 4}, "effect_text": "+4 Plants/gen", "prereq": {"temp": 4}},
		{"name": "Aquifer Pump", "cost": 12, "type": "blue", "tags": ["building"],
		 "effects": {"credit_prod": 2, "heat_prod": 2, "plant_prod": 1}, "effect_text": "+2 Cr, +2 Heat\n+1 Plant /gen", "prereq": {}},
		{"name": "Space Mirrors", "cost": 12, "type": "blue", "tags": ["space", "energy"],
		 "effects": {"heat_prod": 5}, "effect_text": "+5 Heat/gen", "prereq": {}},
		{"name": "Bio Labs", "cost": 14, "type": "blue", "tags": ["science", "plant"],
		 "effects": {"plant_prod": 5}, "effect_text": "+5 Plants/gen", "prereq": {"oxy": 3}},
		{"name": "Trade Routes", "cost": 18, "type": "blue", "tags": ["space"],
		 "effects": {"credit_prod": 7}, "effect_text": "+7 Cr/gen", "prereq": {"temp": 6}},
		{"name": "Solar Farms", "cost": 8, "type": "blue", "tags": ["energy"],
		 "effects": {"credit_prod": 2, "heat_prod": 2}, "effect_text": "+2 Cr\n+2 Heat /gen", "prereq": {}},
		{"name": "Fungus Colony", "cost": 9, "type": "blue", "tags": ["microbe", "plant"],
		 "effects": {"plant_prod": 3, "heat_prod": 1}, "effect_text": "+3 Plant\n+1 Heat /gen", "prereq": {}},
		{"name": "AI Central", "cost": 16, "type": "blue", "tags": ["science", "building"],
		 "effects": {"credit_prod": 4, "plant_prod": 2, "heat_prod": 2}, "effect_text": "+4 Cr, +2 Plant\n+2 Heat /gen", "prereq": {"tag": {"science": 3}}},

		{"name": "Comet", "cost": 18, "type": "red", "tags": ["space"],
		 "effects": {"temp": 3, "ocean": 2}, "effect_text": "+3 Temp\n+2 Ocean", "prereq": {}},
		{"name": "Viral Bloom", "cost": 6, "type": "red", "tags": ["microbe"],
		 "effects": {"oxy": 3}, "effect_text": "+3 O2", "prereq": {"ocean": 4}},
		{"name": "Solar Wind", "cost": 8, "type": "red", "tags": ["space", "science"],
		 "effects": {"temp": 2, "heat": 8}, "effect_text": "+2 Temp\n+8 Heat", "prereq": {}},
		{"name": "Tectonic Stress", "cost": 20, "type": "red", "tags": ["energy"],
		 "effects": {"temp": 2, "ocean": 2, "oxy": 1}, "effect_text": "+2 Temp, +2 Ocean\n+1 O2", "prereq": {"temp": 8}},
		{"name": "Gene Bomb", "cost": 14, "type": "red", "tags": ["science", "microbe"],
		 "effects": {"oxy": 3, "plants": 6}, "effect_text": "+3 O2\n+6 Plants", "prereq": {"temp": 6, "ocean": 3}},
		{"name": "Ice Moon", "cost": 22, "type": "red", "tags": ["space"],
		 "effects": {"ocean": 4}, "effect_text": "+4 Ocean", "prereq": {}},
		{"name": "Meteor Shower", "cost": 12, "type": "red", "tags": ["space"],
		 "effects": {"temp": 3, "heat": 4}, "effect_text": "+3 Temp\n+4 Heat", "prereq": {}},
		{"name": "Lightning Harvest", "cost": 9, "type": "red", "tags": ["energy", "science"],
		 "effects": {"credit_prod": 3, "heat": 6}, "effect_text": "+3 Cr/gen\n+6 Heat", "prereq": {"tag": {"science": 2}}},
	]


# =============================================================================
# SAVE / LOAD
# =============================================================================

func _save_game() -> void:
	var save_data := {
		"temp_steps": temp_steps, "oxy_steps": oxy_steps, "ocean_steps": ocean_steps,
		"credits": credits, "tr": tr, "heat": heat, "plants": plants,
		"heat_prod": heat_prod, "plant_prod": plant_prod, "credit_prod": credit_prod,
		"generation": generation, "cards_played": cards_played, "points": points,
		"tags": tags,
	}
	Api.save_state(generation, save_data, func(_ok: bool, _result) -> void: pass)
