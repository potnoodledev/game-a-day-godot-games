extends Node
## Bridge between HTML5 wrapper and the cat viewer.
## Registered as autoload "Bridge".
##
## Communication:
##   - Initial config: --cat-config JSON via OS.get_cmdline_args()
##   - Live updates: polls window._catCommands[] via JavaScriptBridge.eval()
##
## Wrapper API (JS):
##   window.catViewer.setAnimation("Cat_Walk")
##   window.catViewer.setColors([0.9,0.55,0.15], [0.4,0.15,0.05], [0.3,0.7,0.2])
##   window.catViewer.setBoneScale("head_size", 0.7)
##   window.catViewer.setCamera(2.5, 45, -10)
##   window.catViewer.setAutoRotate(true)

signal animation_changed(name: String)
signal primary_color_changed(color: Color)
signal stripe_color_changed(color: Color)
signal eye_color_changed(color: Color)
signal bone_scale_changed(name: String, value: float)
signal camera_changed(distance: float, angle_y: float, angle_x: float)
signal auto_rotate_changed(enabled: bool)
signal scene_changed(scene_id: String)
signal weapon_changed(weapon_id: String)
signal hat_changed(hat_id: String)
signal camera_target_changed(x: float, y: float, z: float)

var _poll_counter := 0
var _js_available := false
var _initial_config := {}

func _ready() -> void:
	_parse_args()
	if OS.has_feature("web"):
		_setup_js_bridge()

func _parse_args() -> void:
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--cat-config" and i + 1 < args.size():
			var json = JSON.parse_string(args[i + 1])
			if json is Dictionary:
				_initial_config = json
				print("[bridge] Config from args: ", _initial_config.keys())
				_apply_initial_config()
				return
	print("[bridge] No --cat-config arg, using defaults")

func _apply_initial_config() -> void:
	# Defer so main.gd has time to connect signals
	call_deferred("_emit_initial_config")

func _emit_initial_config() -> void:
	var cfg := _initial_config
	if cfg.has("animation"):
		animation_changed.emit(cfg["animation"])
	if cfg.has("primary_color"):
		var c = cfg["primary_color"]
		primary_color_changed.emit(Color(c[0], c[1], c[2]))
	if cfg.has("stripe_color"):
		var c = cfg["stripe_color"]
		stripe_color_changed.emit(Color(c[0], c[1], c[2]))
	if cfg.has("eye_color"):
		var c = cfg["eye_color"]
		eye_color_changed.emit(Color(c[0], c[1], c[2]))
	if cfg.has("bone_scales"):
		for key in cfg["bone_scales"]:
			bone_scale_changed.emit(key, cfg["bone_scales"][key])
	if cfg.has("camera"):
		var cam = cfg["camera"]
		camera_changed.emit(
			cam.get("distance", 2.5),
			cam.get("angle_y", 0.0),
			cam.get("angle_x", -10.0)
		)
	if cfg.has("auto_rotate"):
		auto_rotate_changed.emit(cfg["auto_rotate"])
	if cfg.has("scene"):
		scene_changed.emit(cfg["scene"])
	if cfg.has("weapon"):
		weapon_changed.emit(cfg["weapon"])
	if cfg.has("hat"):
		hat_changed.emit(cfg["hat"])

func _setup_js_bridge() -> void:
	# Install the catViewer API and command queue on the JS side
	var js_code := """
	(function() {
		if (window.catViewer) return 'already_installed';
		window._catCommands = [];
		window.catViewer = {
			setAnimation: function(name) { window._catCommands.push({cmd:'set_animation',value:name}); },
			setColors: function(primary, stripe, eye) { window._catCommands.push({cmd:'set_colors',primary:primary,stripe:stripe,eye:eye}); },
			setPrimaryColor: function(r,g,b) { window._catCommands.push({cmd:'set_primary_color',r:r,g:g,b:b}); },
			setStripeColor: function(r,g,b) { window._catCommands.push({cmd:'set_stripe_color',r:r,g:g,b:b}); },
			setEyeColor: function(r,g,b) { window._catCommands.push({cmd:'set_eye_color',r:r,g:g,b:b}); },
			setBoneScale: function(bone, value) { window._catCommands.push({cmd:'set_bone_scale',bone:bone,value:value}); },
			setCamera: function(distance, angleY, angleX) { window._catCommands.push({cmd:'set_camera',distance:distance,angle_y:angleY,angle_x:angleX}); },
			setAutoRotate: function(enabled) { window._catCommands.push({cmd:'set_auto_rotate',value:enabled}); },
			setScene: function(id) { window._catCommands.push({cmd:'set_scene',value:id}); },
			setWeapon: function(id) { window._catCommands.push({cmd:'set_weapon',value:id}); },
			setHat: function(id) { window._catCommands.push({cmd:'set_hat',value:id}); },
			getAnimations: function() { return window._catAnimations || []; },
			getScenes: function() { return window._catScenes || []; },
			getHats: function() { return window._catHats || []; },
			getConfig: function() { return window._catCurrentConfig || {}; },
		};
		return 'installed';
	})()
	"""
	var result = JavaScriptBridge.eval(js_code)
	if result != null:
		_js_available = true
		print("[bridge] JS bridge: ", result)
	else:
		print("[bridge] JavaScriptBridge.eval blocked (CSP?), using args-only mode")

func _process(_delta: float) -> void:
	if not _js_available:
		return
	# Poll every 3 frames (~20Hz at 60fps)
	_poll_counter += 1
	if _poll_counter % 3 != 0:
		return
	_poll_commands()

func _poll_commands() -> void:
	var result = JavaScriptBridge.eval("(function(){var q=window._catCommands||[];window._catCommands=[];return q.length>0?JSON.stringify(q):'[]';})()")
	if result == null or result == "[]":
		return
	var commands = JSON.parse_string(result)
	if not commands is Array:
		return
	for cmd in commands:
		_dispatch_command(cmd)

func _dispatch_command(cmd: Dictionary) -> void:
	match cmd.get("cmd", ""):
		"set_animation":
			animation_changed.emit(cmd["value"])
		"set_colors":
			if cmd.has("primary"):
				var c = cmd["primary"]
				primary_color_changed.emit(Color(c[0], c[1], c[2]))
			if cmd.has("stripe"):
				var c = cmd["stripe"]
				stripe_color_changed.emit(Color(c[0], c[1], c[2]))
			if cmd.has("eye"):
				var c = cmd["eye"]
				eye_color_changed.emit(Color(c[0], c[1], c[2]))
		"set_primary_color":
			primary_color_changed.emit(Color(cmd["r"], cmd["g"], cmd["b"]))
		"set_stripe_color":
			stripe_color_changed.emit(Color(cmd["r"], cmd["g"], cmd["b"]))
		"set_eye_color":
			eye_color_changed.emit(Color(cmd["r"], cmd["g"], cmd["b"]))
		"set_bone_scale":
			bone_scale_changed.emit(cmd["bone"], cmd["value"])
		"set_camera":
			camera_changed.emit(cmd["distance"], cmd["angle_y"], cmd["angle_x"])
		"set_auto_rotate":
			auto_rotate_changed.emit(cmd["value"])
		"set_scene":
			scene_changed.emit(cmd["value"])
		"set_weapon":
			weapon_changed.emit(cmd["value"])
		"set_hat":
			hat_changed.emit(cmd["value"])
		"set_camera_target":
			camera_target_changed.emit(cmd["x"], cmd["y"], cmd["z"])

## Called by main.gd to publish animation list back to JS
func publish_animations(names: Array) -> void:
	if not _js_available:
		return
	var json := JSON.stringify(names)
	JavaScriptBridge.eval("window._catAnimations=" + json)

## Called by main.gd to publish scene list back to JS
func publish_scenes(ids: Array) -> void:
	if not _js_available:
		return
	var json := JSON.stringify(ids)
	JavaScriptBridge.eval("window._catScenes=" + json)

## Called by main.gd to publish hat list back to JS
func publish_hats(ids: Array) -> void:
	if not _js_available:
		return
	var json := JSON.stringify(ids)
	JavaScriptBridge.eval("window._catHats=" + json)

## Called by main.gd to publish current config back to JS
func publish_config(config: Dictionary) -> void:
	if not _js_available:
		return
	var json := JSON.stringify(config)
	JavaScriptBridge.eval("window._catCurrentConfig=" + json)
