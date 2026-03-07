shader_type spatial;

uniform sampler2D base_texture : source_color;
uniform vec3 iris_color : source_color = vec3(0.2, 0.5, 0.8);

// RGB to HSV
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// HSV to RGB
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 tex = texture(base_texture, UV);
	vec3 hsv = rgb2hsv(tex.rgb);

	// Saturation is our iris mask — iris is colorful, sclera/pupil/highlights are not
	float sat = hsv.y;
	float iris_mask = smoothstep(0.15, 0.4, sat);

	// Get target color in HSV
	vec3 target_hsv = rgb2hsv(iris_color);

	// Replace hue and saturation of the iris, keep original value (brightness)
	vec3 recolored_hsv = vec3(target_hsv.x, target_hsv.y * hsv.y / max(hsv.y, 0.01), hsv.z);
	vec3 recolored = hsv2rgb(recolored_hsv);

	ALBEDO = mix(tex.rgb, recolored, iris_mask);
	ALPHA = tex.a;
}
