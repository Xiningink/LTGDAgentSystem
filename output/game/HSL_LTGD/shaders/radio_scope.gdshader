shader_type canvas_item;

// Static / carrier scope displayed on the radio faceplate.

uniform float noise_strength : hint_range(0.0, 2.0) = 1.0;
uniform float signal_strength : hint_range(0.0, 1.0) = 0.0;
uniform float jam_level : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform vec4 glow : source_color = vec4(0.42, 0.98, 0.62, 1.0);
uniform vec4 base_color : source_color = vec4(0.015, 0.03, 0.035, 1.0);

float hsh(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME + seed;

	float grains = hsh(floor(uv * vec2(200.0, 120.0)) + vec2(floor(t * 26.0), floor(t * 19.0)));
	float fine = hsh(floor(uv * vec2(90.0, 54.0)) + vec2(floor(t * 14.0), floor(t * 11.0)));
	float n = mix(grains, fine, 0.45);

	// horizontal tearing during jamming
	float tear_row = step(0.90, hsh(vec2(floor(uv.y * 40.0), floor(t * 9.0))));
	n = mix(n, hsh(vec2(floor(uv.y * 12.0), floor(t * 30.0))), tear_row * (0.25 + jam_level * 0.7));

	// carrier waveform
	float wave = 0.0;
	if (signal_strength > 0.001) {
		float w = sin(uv.x * 30.0 + t * 5.0) * 0.5 + 0.5;
		float w2 = sin(uv.x * 61.0 - t * 9.0) * 0.5 + 0.5;
		float shape = mix(w, w2, 0.35) * 0.62 + 0.19;
		float d = abs(uv.y - shape);
		wave = smoothstep(0.016, 0.0, d) * signal_strength;
	}

	vec3 col = base_color.rgb;
	col += glow.rgb * n * noise_strength * (1.0 - signal_strength * 0.72);
	col += glow.rgb * wave * 1.15;
	col += vec3(1.0, 0.35, 0.28) * jam_level * n * 0.55;

	// rolling scanline
	col *= 0.82 + 0.18 * (0.5 + 0.5 * sin(uv.y * 6.28318 * 3.0 - t * 1.6));

	// graticule
	float grid = max(step(0.972, fract(uv.x * 18.0)), step(0.955, fract(uv.y * 10.0)));
	col *= 1.0 - grid * 0.35;

	// edge falloff
	vec2 e = min(uv, 1.0 - uv);
	col *= smoothstep(0.0, 0.035, min(e.x, e.y));

	COLOR = vec4(col, 1.0);
}
