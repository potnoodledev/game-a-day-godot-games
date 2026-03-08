extends RefCounted
## Static registry of all procedural scene definitions.
## Each scene is a dictionary of environment parameters.

# Defaults — any key omitted from a scene uses these values
const DEFAULTS := {
	# Sky
	"sky_top_color": Color(0.4, 0.6, 0.9),
	"sky_horizon_color": Color(0.7, 0.8, 0.95),
	"ground_bottom_color": Color(0.3, 0.25, 0.2),
	"ground_horizon_color": Color(0.6, 0.55, 0.5),

	# Lighting
	"key_light_color": Color(1.0, 0.95, 0.85),
	"key_light_energy": 2.5,
	"key_light_rotation": Vector3(-45, 30, 0),
	"fill_light_color": Color(0.7, 0.8, 1.0),
	"fill_light_energy": 0.8,
	"fill_light_rotation": Vector3(-20, -60, 0),
	"ambient_energy": 0.5,

	# Floor
	"floor_color": Color(0.3, 0.35, 0.3),
	"floor_roughness": 0.9,
	"floor_metallic": 0.0,

	# Post-processing
	"ssao_enabled": true,
	"glow_enabled": false,
	"glow_intensity": 0.3,
	"glow_threshold": 0.8,
	"glow_bloom": 0.0,
	"fog_enabled": false,
	"fog_density": 0.01,
	"fog_light_color": Color(0.5, 0.6, 0.7),
	"tonemap_mode": 0,  # Environment.TONE_MAP_LINEAR
	"adjustments_enabled": false,
	"adjustments_saturation": 1.0,

	# Particles
	"particles": [],
}

const SCENES := {
	"default_studio": {
		# Clean photography studio — the baseline
	},

	"sunset_rooftop": {
		"sky_top_color": Color(0.9, 0.4, 0.2),
		"sky_horizon_color": Color(1.0, 0.7, 0.4),
		"ground_bottom_color": Color(0.2, 0.1, 0.05),
		"ground_horizon_color": Color(0.5, 0.25, 0.1),
		"key_light_color": Color(1.0, 0.8, 0.5),
		"key_light_energy": 3.0,
		"key_light_rotation": Vector3(-15, 40, 0),
		"fill_light_color": Color(0.4, 0.3, 0.6),
		"fill_light_energy": 0.5,
		"fill_light_rotation": Vector3(-30, -50, 0),
		"ambient_energy": 0.4,
		"floor_color": Color(0.25, 0.22, 0.2),
		"floor_roughness": 0.8,
		"glow_enabled": true,
		"glow_intensity": 0.3,
		"glow_threshold": 0.8,
	},

	"moonlit_garden": {
		"sky_top_color": Color(0.05, 0.05, 0.15),
		"sky_horizon_color": Color(0.1, 0.1, 0.2),
		"ground_bottom_color": Color(0.02, 0.02, 0.05),
		"ground_horizon_color": Color(0.05, 0.05, 0.1),
		"key_light_color": Color(0.6, 0.7, 1.0),
		"key_light_energy": 1.5,
		"key_light_rotation": Vector3(-60, 20, 0),
		"fill_light_color": Color(0.2, 0.25, 0.4),
		"fill_light_energy": 0.3,
		"fill_light_rotation": Vector3(-10, -40, 0),
		"ambient_energy": 0.2,
		"floor_color": Color(0.08, 0.1, 0.08),
		"floor_roughness": 0.85,
		"fog_enabled": true,
		"fog_density": 0.02,
		"fog_light_color": Color(0.1, 0.1, 0.2),
		"particles": [
			{
				"type": "fireflies",
				"count": 20,
				"lifetime": 5.0,
				"emission_shape": "sphere",
				"emission_radius": 2.5,
				"emission_offset": Vector3(0, 0.8, 0),
				"direction": Vector3(0, 0.3, 0),
				"velocity_min": 0.05,
				"velocity_max": 0.15,
				"gravity": Vector3.ZERO,
				"color": Color(0.8, 1.0, 0.3, 0.8),
				"color_end": Color(0.8, 1.0, 0.3, 0.0),
				"scale_min": 0.02,
				"scale_max": 0.04,
			}
		],
	},

	"winter_wonderland": {
		"sky_top_color": Color(0.7, 0.75, 0.8),
		"sky_horizon_color": Color(0.85, 0.87, 0.9),
		"ground_bottom_color": Color(0.6, 0.62, 0.65),
		"ground_horizon_color": Color(0.75, 0.77, 0.8),
		"key_light_color": Color(0.9, 0.92, 1.0),
		"key_light_energy": 1.8,
		"key_light_rotation": Vector3(-40, 25, 0),
		"fill_light_color": Color(0.8, 0.85, 1.0),
		"fill_light_energy": 1.0,
		"fill_light_rotation": Vector3(-20, -50, 0),
		"ambient_energy": 0.7,
		"floor_color": Color(0.9, 0.92, 0.95),
		"floor_roughness": 0.95,
		"particles": [
			{
				"type": "snow",
				"count": 150,
				"lifetime": 4.0,
				"emission_shape": "box",
				"emission_extents": Vector3(3, 0.1, 3),
				"emission_offset": Vector3(0, 3, 0),
				"direction": Vector3(0, -1, 0),
				"velocity_min": 0.5,
				"velocity_max": 1.0,
				"gravity": Vector3(0, -0.5, 0),
				"color": Color(1, 1, 1, 0.8),
				"color_end": Color(1, 1, 1, 0.0),
				"scale_min": 0.015,
				"scale_max": 0.035,
			}
		],
	},

	"neon_city": {
		"sky_top_color": Color(0.05, 0.02, 0.1),
		"sky_horizon_color": Color(0.1, 0.05, 0.15),
		"ground_bottom_color": Color(0.03, 0.01, 0.05),
		"ground_horizon_color": Color(0.06, 0.03, 0.1),
		"key_light_color": Color(1.0, 0.2, 0.8),
		"key_light_energy": 3.0,
		"key_light_rotation": Vector3(-35, -50, 0),
		"fill_light_color": Color(0.2, 0.8, 1.0),
		"fill_light_energy": 2.5,
		"fill_light_rotation": Vector3(-25, 50, 0),
		"ambient_energy": 0.15,
		"floor_color": Color(0.1, 0.1, 0.12),
		"floor_roughness": 0.15,
		"floor_metallic": 0.3,
		"ssao_enabled": false,
		"glow_enabled": true,
		"glow_intensity": 0.8,
		"glow_threshold": 0.6,
		"glow_bloom": 0.3,
	},

	"cosmic_void": {
		"sky_top_color": Color(0.02, 0.0, 0.05),
		"sky_horizon_color": Color(0.1, 0.02, 0.15),
		"ground_bottom_color": Color(0.01, 0.0, 0.03),
		"ground_horizon_color": Color(0.05, 0.01, 0.08),
		"key_light_color": Color(0.8, 0.7, 1.0),
		"key_light_energy": 2.0,
		"key_light_rotation": Vector3(-80, 0, 0),
		"fill_light_color": Color(0.3, 0.2, 0.5),
		"fill_light_energy": 0.6,
		"fill_light_rotation": Vector3(-10, 180, 0),
		"ambient_energy": 0.15,
		"floor_color": Color(0.05, 0.03, 0.08),
		"floor_roughness": 0.05,
		"floor_metallic": 0.9,
		"glow_enabled": true,
		"glow_intensity": 0.4,
		"glow_threshold": 0.7,
		"particles": [
			{
				"type": "sparkles",
				"count": 60,
				"lifetime": 3.0,
				"emission_shape": "sphere",
				"emission_radius": 3.0,
				"emission_offset": Vector3(0, 1.0, 0),
				"direction": Vector3(0, 0, 0),
				"velocity_min": 0.02,
				"velocity_max": 0.08,
				"gravity": Vector3.ZERO,
				"color": Color(1, 1, 1, 0.9),
				"color_end": Color(1, 1, 1, 0.0),
				"scale_min": 0.01,
				"scale_max": 0.025,
			}
		],
	},

	"cozy_fireplace": {
		"sky_top_color": Color(0.15, 0.08, 0.04),
		"sky_horizon_color": Color(0.3, 0.15, 0.08),
		"ground_bottom_color": Color(0.1, 0.05, 0.02),
		"ground_horizon_color": Color(0.2, 0.1, 0.05),
		"key_light_color": Color(1.0, 0.7, 0.3),
		"key_light_energy": 3.5,
		"key_light_rotation": Vector3(-30, -45, 0),
		"fill_light_color": Color(0.5, 0.3, 0.15),
		"fill_light_energy": 0.4,
		"fill_light_rotation": Vector3(-15, 60, 0),
		"ambient_energy": 0.2,
		"floor_color": Color(0.35, 0.22, 0.12),
		"floor_roughness": 0.7,
		"glow_enabled": true,
		"glow_intensity": 0.2,
		"glow_threshold": 0.9,
		"particles": [
			{
				"type": "embers",
				"count": 30,
				"lifetime": 3.5,
				"emission_shape": "box",
				"emission_extents": Vector3(0.3, 0.1, 0.3),
				"emission_offset": Vector3(-1.5, 0.0, 0),
				"direction": Vector3(0.2, 1, 0),
				"velocity_min": 0.2,
				"velocity_max": 0.5,
				"gravity": Vector3(0, 0.3, 0),
				"color": Color(1.0, 0.5, 0.1, 0.9),
				"color_end": Color(1.0, 0.2, 0.0, 0.0),
				"scale_min": 0.01,
				"scale_max": 0.025,
			}
		],
	},

	"sakura_garden": {
		"sky_top_color": Color(0.6, 0.7, 0.9),
		"sky_horizon_color": Color(0.9, 0.75, 0.8),
		"ground_bottom_color": Color(0.35, 0.3, 0.25),
		"ground_horizon_color": Color(0.6, 0.5, 0.5),
		"key_light_color": Color(1.0, 0.95, 0.9),
		"key_light_energy": 2.0,
		"key_light_rotation": Vector3(-45, 35, 0),
		"fill_light_color": Color(0.8, 0.75, 0.85),
		"fill_light_energy": 0.8,
		"fill_light_rotation": Vector3(-20, -55, 0),
		"ambient_energy": 0.6,
		"floor_color": Color(0.5, 0.52, 0.48),
		"floor_roughness": 0.85,
		"particles": [
			{
				"type": "petals",
				"count": 80,
				"lifetime": 5.0,
				"emission_shape": "box",
				"emission_extents": Vector3(3, 0.1, 3),
				"emission_offset": Vector3(0, 3.5, 0),
				"direction": Vector3(0.3, -1, 0.1),
				"velocity_min": 0.3,
				"velocity_max": 0.7,
				"gravity": Vector3(0, -0.3, 0),
				"color": Color(1.0, 0.75, 0.8, 0.85),
				"color_end": Color(1.0, 0.8, 0.85, 0.0),
				"scale_min": 0.02,
				"scale_max": 0.04,
			}
		],
	},
}

static func get_scene(id: String) -> Dictionary:
	var base := DEFAULTS.duplicate(true)
	if SCENES.has(id):
		var scene: Dictionary = SCENES[id]
		for key in scene:
			base[key] = scene[key]
	return base

static func get_scene_ids() -> Array:
	return SCENES.keys()
