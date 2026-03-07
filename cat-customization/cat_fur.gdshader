shader_type spatial;

// Body part colors
uniform vec3 base_color : source_color = vec3(0.9, 0.5, 0.2);
uniform vec3 secondary_color : source_color = vec3(0.3, 0.15, 0.05);
uniform vec3 belly_color : source_color = vec3(1.0, 0.95, 0.9);
uniform vec3 ear_color : source_color = vec3(0.95, 0.6, 0.6);
uniform vec3 nose_color : source_color = vec3(0.9, 0.55, 0.55);
uniform vec3 eye_color : source_color = vec3(0.3, 0.7, 0.2);
uniform vec3 paw_color : source_color = vec3(0.95, 0.85, 0.78);

// Pattern controls
uniform int pattern_type : hint_range(0, 5) = 0;
uniform float pattern_scale : hint_range(1.0, 30.0) = 10.0;
uniform float pattern_intensity : hint_range(0.0, 1.0) = 0.7;

uniform float roughness_base : hint_range(0.0, 1.0) = 0.75;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

// All 14 known UV values as region IDs
// Large body regions (safe to snap from boundary triangles):
//   0: (1,0) body_lower    1: (1,1) back_upper    2: (0,0) legs
//   3: (1,0.697) body_upper  4: (1,0.3244) sides
//   5: (0,0.3244) tail_mid  6: (0,1) tail_top  7: (0,0.697) tail_base
//   8: (1,0.9123) ear_outer  9: (1,0.8979) ear_inner
// Small face features (only on low-gradient triangles):
//   10: (1,0.7055) eye  11: (1,0.7012) face  12: (1,0.5273) nose  13: (1,0.4426) mouth

// Known UV coordinates
const int NUM_UVS = 14;
const vec2 KNOWN_UVS[14] = vec2[14](
	vec2(1.0, 0.0),     // 0: body_lower
	vec2(1.0, 1.0),     // 1: back_upper
	vec2(0.0, 0.0),     // 2: legs
	vec2(1.0, 0.697),   // 3: body_upper
	vec2(1.0, 0.3244),  // 4: sides
	vec2(0.0, 0.3244),  // 5: tail_mid
	vec2(0.0, 1.0),     // 6: tail_top
	vec2(0.0, 0.697),   // 7: tail_base
	vec2(1.0, 0.9123),  // 8: ear_outer
	vec2(1.0, 0.8979),  // 9: ear_inner
	vec2(1.0, 0.7055),  // 10: eye
	vec2(1.0, 0.7012),  // 11: face
	vec2(1.0, 0.5273),  // 12: nose
	vec2(1.0, 0.4426)   // 13: mouth
);

int classify_uv_internal(vec2 uv, bool allow_small) {
	// 1. Find nearest large body region (indices 0-9)
	float best_large_dist = 999.0;
	int best_large = 0;
	for (int i = 0; i < 10; i++) {
		float d = distance(uv, KNOWN_UVS[i]);
		if (d < best_large_dist) {
			best_large_dist = d;
			best_large = i;
		}
	}

	if (!allow_small) return best_large;

	// 2. Check if any small face feature (indices 10-13) is much closer
	for (int i = 10; i < NUM_UVS; i++) {
		float d = distance(uv, KNOWN_UVS[i]);
		if (d < best_large_dist * 0.5 && d < 0.01) {
			return i;
		}
	}

	return best_large;
}

// Noise functions
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amp * noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return value;
}

// Region ID helpers
bool is_tail(int region) { return region >= 5 && region <= 7; }
bool is_body(int region) { return region == 0 || region == 1 || region == 3 || region == 4; }

// Pattern generators
vec3 pat_tabby(vec3 base, vec3 dark, vec3 pos) {
	float stripe_coord = pos.x * pattern_scale * 2.5;
	float noise_warp = fbm(pos.xy * pattern_scale * 0.8) * 2.5;
	float stripes = sin(stripe_coord + noise_warp);
	stripes = smoothstep(-0.1, 0.4, stripes);
	stripes *= 0.6 + 0.4 * fbm(pos.xy * pattern_scale * 1.5);
	return mix(base, dark, stripes * pattern_intensity);
}

vec3 pat_tuxedo(vec3 dark, vec3 white, int region) {
	float white_mask = 0.0;
	if (region == 0) white_mask = 0.7;  // body_lower
	if (region == 2) white_mask = 0.6;  // legs
	return mix(dark, white, white_mask * pattern_intensity);
}

vec3 pat_calico(vec3 base, vec3 dark, vec3 pos) {
	float n1 = fbm(pos.xy * pattern_scale * 0.4);
	float n2 = fbm(pos.xy * pattern_scale * 0.4 + vec2(50.0));
	vec3 col = base;
	if (n1 > 0.5) col = dark;
	if (n2 > 0.55) col = vec3(1.0, 0.98, 0.95);
	return mix(base, col, pattern_intensity);
}

vec3 pat_siamese(vec3 light, vec3 dark, int region) {
	float dark_mask = 0.0;
	if (region == 10 || region == 11 || region == 12 || region == 13) dark_mask = 1.0; // face features
	if (region == 8 || region == 9) dark_mask = 1.0;  // ears
	if (region == 2) dark_mask = 0.8;                  // legs
	if (is_tail(region)) dark_mask = 1.0;              // tail
	if (region == 1) dark_mask = 0.15;                 // back_upper
	return mix(light, dark, dark_mask * pattern_intensity);
}

vec3 pat_spotted(vec3 base, vec3 dark, vec3 pos) {
	vec2 p = pos.xy * pattern_scale;
	vec2 grid_cell = floor(p);
	vec2 frac_p = fract(p);
	float spots = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 center = vec2(hash(grid_cell + neighbor), hash(grid_cell + neighbor + vec2(17.0, 31.0)));
			float d = length(frac_p - neighbor - center);
			spots = max(spots, smoothstep(0.38, 0.15, d));
		}
	}
	return mix(base, dark, spots * pattern_intensity);
}

void fragment() {
	// High UV gradient = boundary between distant regions → large regions only
	float uv_grad = length(dFdx(UV)) + length(dFdy(UV));
	bool allow_small = uv_grad < 0.003;
	int region = classify_uv_internal(UV, allow_small);
	vec3 pos = obj_pos;

	vec3 col = base_color;
	float final_roughness = roughness_base;
	float final_metallic = 0.0;
	float final_specular = 0.5;
	bool is_eye = (region == 10 || region == 11); // merge eye + face-around-eyes

	// Region-based coloring
	if (is_eye) {
		// Eyes — shiny, reflective (merged eye + face region for visibility)
		col = eye_color;
		final_roughness = 0.02;
		final_metallic = 0.4;
		final_specular = 1.0;
	} else if (region == 12) {
		// Nose
		col = nose_color;
	} else if (region == 13) {
		// Mouth area
		col = mix(base_color, nose_color, 0.15);
	} else if (region == 9) {
		// Ear inner
		col = ear_color;
	} else if (region == 8) {
		// Ear outer
		col = mix(base_color, ear_color, 0.25);
	} else if (region == 2) {
		// Legs/paws
		col = mix(base_color, paw_color, 0.35);
	} else if (is_tail(region)) {
		// Tail — base color, patterns applied below
		col = base_color;
	} else {
		// Main body — apply patterns
		if (pattern_type == 1) {
			col = pat_tabby(base_color, secondary_color, pos);
		} else if (pattern_type == 2) {
			col = pat_tuxedo(base_color, belly_color, region);
		} else if (pattern_type == 3) {
			col = pat_calico(base_color, secondary_color, pos);
		} else if (pattern_type == 5) {
			col = pat_spotted(base_color, secondary_color, pos);
		}
	}

	// Siamese overrides everything except eyes
	if (pattern_type == 4 && !is_eye) {
		if (region == 9) {
			col = mix(ear_color, secondary_color, 0.5);
		} else {
			col = pat_siamese(belly_color, base_color, region);
			if (region == 12) col = mix(col, nose_color, 0.4);
		}
	}

	// Tail gets pattern too
	if (is_tail(region) && pattern_type != 4) {
		if (pattern_type == 1) col = pat_tabby(base_color, secondary_color, pos);
		else if (pattern_type == 3) col = pat_calico(base_color, secondary_color, pos);
		else if (pattern_type == 5) col = pat_spotted(base_color, secondary_color, pos);
	}

	// Fur noise (skip for eyes)
	if (!is_eye) {
		float fur_noise = fbm(pos.xy * 40.0);
		col *= 0.93 + 0.07 * fur_noise;
		final_roughness += 0.04 * fur_noise;
	}

	ALBEDO = col;
	ROUGHNESS = final_roughness;
	METALLIC = final_metallic;
	SPECULAR = final_specular;
}
