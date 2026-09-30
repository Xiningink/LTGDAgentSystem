shader_type canvas_item;

// Night view through the station window. Something moves out there.

uniform float darkness : hint_range(0.0, 1.0) = 1.0;
uniform float shape_presence : hint_range(0.0, 1.0) = 0.0;
uniform float shape_seed = 0.0;
uniform float light_bleed : hint_range(0.0, 1.0) = 0.5;
uniform vec4 sky_top : source_color = vec4(0.020, 0.035, 0.062, 1.0);
uniform vec4 sky_bottom : source_color = vec4(0.055, 0.075, 0.105, 1.0);
uniform vec4 sea_color : source_color = vec4(0.010, 0.020, 0.030, 1.0);

float hsh(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hsh(i);
	float b = hsh(i + vec2(1.0, 0.0));
	float c = hsh(i + vec2(0.0, 1.0));
	float d = hsh(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float horizon = 0.63;
	vec3 col;

	if (uv.y < horizon) {
		float k = uv.y / horizon;
		col = mix(sky_top.rgb, sky_bottom.rgb, k);
		float s = hsh(floor(uv * vec2(110.0, 60.0)));
		float tw = 0.45 + 0.55 * sin(TIME * 1.7 + s * 41.0);
		col += vec3(0.55, 0.66, 0.80) * step(0.977, s) * tw * 0.75;
		// slow cloud band
		float cl = vnoise(vec2(uv.x * 4.0 + TIME * 0.02, uv.y * 7.0));
		col += vec3(0.02, 0.028, 0.038) * smoothstep(0.5, 0.95, cl);
	} else {
		float depth = (uv.y - horizon) / (1.0 - horizon);
		col = mix(vec3(0.030, 0.048, 0.062), sea_color.rgb, depth);
		float w = vnoise(vec2(uv.x * 26.0, uv.y * 46.0 - TIME * 0.22));
		float w2 = vnoise(vec2(uv.x * 60.0 - 3.0, uv.y * 90.0 - TIME * 0.4));
		col += vec3(0.05, 0.075, 0.09) * smoothstep(0.52, 1.0, w) * (0.55 + darkness * 0.35);
		col += vec3(0.07, 0.10, 0.11) * smoothstep(0.86, 1.0, w2) * 0.5;
	}

	// the shape beyond the glass
	float t = TIME * 0.22 + shape_seed;
	float drift = sin(t * 0.61) * 0.33;
	vec2 c = vec2(0.5 + drift, horizon - 0.16 + sin(t * 1.31) * 0.05);
	vec2 rel = (uv - c) * vec2(1.0, 1.35);
	float body = smoothstep(0.26, 0.07, length(rel));
	float pillar = smoothstep(0.55, 0.05, abs(rel.x) * 14.0) * smoothstep(0.62, 0.05, rel.y + 0.18);
	float tendril = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float off = sin(t * (1.1 + fi * 0.4) + fi * 2.1) * 0.16;
		float d = length((uv - vec2(c.x + off, horizon - 0.02 - fi * 0.03)) * vec2(1.0, 0.9));
		tendril = max(tendril, smoothstep(0.10 - fi * 0.02, 0.0, d));
	}
	float shape = clamp(max(body, max(pillar * 0.9, tendril)) * shape_presence, 0.0, 1.0);
	col = mix(col, vec3(0.0, 0.0, 0.0), shape * 0.96);

	// two dim lights far out on the water when the shape is near
	if (shape_presence > 0.2) {
		vec2 eye = vec2(c.x + 0.055, c.y + 0.015);
		float e = smoothstep(0.012, 0.0, length((uv - eye) * vec2(1.0, 1.0)));
		col = mix(col, vec3(0.9, 0.18, 0.12), e * shape_presence);
	}

	// faint reflection of the console light on the glass
	float sq = smoothstep(0.75, 0.1, abs(uv.x - 0.30) + abs(uv.y - 0.95) * 2.2);
	col += vec3(0.10, 0.14, 0.09) * sq * light_bleed;

	// glass streaks
	float streak = vnoise(vec2(uv.x * 3.0, uv.y * 22.0 + TIME * 0.05));
	col += vec3(0.012) * smoothstep(0.72, 1.0, streak);

	col *= mix(0.55, 1.0, darkness);

	// window frame vignette
	vec2 e2 = min(uv, 1.0 - uv);
	col *= smoothstep(0.0, 0.02, min(e2.x, e2.y));

	COLOR = vec4(col, 1.0);
}
