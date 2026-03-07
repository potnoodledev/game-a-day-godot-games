shader_type spatial;

uniform sampler2D base_texture : source_color;
uniform vec3 primary_color : source_color = vec3(0.9, 0.55, 0.15);
uniform vec3 secondary_color : source_color = vec3(0.4, 0.15, 0.05);

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 tex = texture(base_texture, UV);
	vec3 hsv = rgb2hsv(tex.rgb);

	// Saturation mask: only recolor colored areas (skip white belly, black bg)
	float sat_mask = smoothstep(0.15, 0.35, hsv.y);

	// Brightness split: bright = primary fur, dark = stripes
	// The original: primary ~0.85 value, stripes ~0.35 value
	float stripe_blend = 1.0 - smoothstep(0.35, 0.65, hsv.z);

	// Get target HSVs
	vec3 pri_hsv = rgb2hsv(primary_color);
	vec3 sec_hsv = rgb2hsv(secondary_color);

	// Blend between primary and secondary based on brightness
	vec3 target_hsv = mix(pri_hsv, sec_hsv, stripe_blend);

	// Apply: replace hue and saturation, scale value relative to original
	// This preserves the shading/lighting baked into the texture
	float value_ratio = hsv.z / max(mix(0.85, 0.35, stripe_blend), 0.01);
	vec3 recolored_hsv = vec3(target_hsv.x, target_hsv.y, clamp(target_hsv.z * value_ratio, 0.0, 1.0));
	vec3 recolored = hsv2rgb(recolored_hsv);

	ALBEDO = mix(tex.rgb, recolored, sat_mask);
}
