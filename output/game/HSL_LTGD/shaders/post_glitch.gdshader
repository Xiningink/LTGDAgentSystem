shader_type canvas_item;

// CRT / interference post process used on the whole viewport.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float time_scale = 1.0;
uniform float vignette_strength : hint_range(0.0, 2.0) = 1.0;
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform float desat : hint_range(0.0, 1.0) = 0.2;
uniform float corruption : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

float hsh(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME * time_scale;
	float g = clamp(glitch, 0.0, 1.0);

	// horizontal displacement bands
	float band = floor(uv.y * 46.0);
	float pick = hsh(vec2(band, floor(t * 11.0)));
	float disp = (hsh(vec2(band, floor(t * 7.0))) - 0.5) * 0.05 * g * step(0.62, pick);
	uv.x += disp;

	// global micro jitter
	uv.x += (hsh(vec2(floor(t * 27.0), 1.0)) - 0.5) * 0.008 * g;
	uv.y += (hsh(vec2(floor(t * 27.0), 2.0)) - 0.5) * 0.006 * g;

	// chromatic aberration
	float ca = 0.0012 + 0.014 * g;
	vec4 c;
	c.r = texture(screen_tex, uv + vec2(ca, 0.0)).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - vec2(ca, 0.0)).b;
	c.a = texture(screen_tex, uv).a;

	// scanlines
	c.rgb *= 0.93 + 0.07 * sin(uv.y * 820.0);

	// rolling bright bar
	float roll = abs(fract(uv.y * 0.5 - t * 0.05) - 0.5);
	c.rgb += smoothstep(0.09, 0.0, roll) * 0.05 * (0.35 + g);

	// film grain
	float n = hsh(floor(uv * vec2(620.0, 340.0)) + floor(t * 38.0));
	c.rgb += (n - 0.5) * (0.045 + g * 0.16 + corruption * 0.10);

	// dead pixels / data blocks
	float blk = step(0.9975, hsh(floor(uv * vec2(58.0, 32.0)) + floor(t * 5.0)));
	c.rgb = mix(c.rgb, vec3(0.35, 0.95, 0.65) * hsh(vec2(t, uv.x)), blk * (0.15 + corruption * 0.6));

	// saturation
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, vec3(lum), clamp(desat, 0.0, 1.0));

	c.rgb *= tint.rgb;
	c.rgb *= brightness;

	// vignette
	vec2 v = uv - vec2(0.5);
	float vig = pow(clamp(1.0 - dot(v, v) * 1.85 * vignette_strength, 0.0, 1.0), 1.35);
	c.rgb *= mix(0.18, 1.0, vig);

	COLOR = vec4(c.rgb, 1.0);
}
