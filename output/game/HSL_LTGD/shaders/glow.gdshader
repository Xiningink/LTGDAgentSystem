shader_type canvas_item;
render_mode blend_add;

// Additive radial glow used for the radio lamp and console bounce light.

uniform vec2 uv_center = vec2(0.5, 0.5);
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float radius : hint_range(0.01, 2.0) = 0.4;
uniform vec4 glow_color : source_color = vec4(1.0, 0.62, 0.28, 1.0);
uniform float strength : hint_range(0.0, 3.0) = 1.0;
uniform float falloff : hint_range(0.5, 6.0) = 2.4;

void fragment() {
	vec2 p = (UV - uv_center) * uv_scale;
	float d = length(p) / max(radius, 0.0001);
	float f = pow(clamp(1.0 - d, 0.0, 1.0), falloff);
	COLOR = vec4(glow_color.rgb * f * strength, f * glow_color.a * clamp(strength, 0.0, 1.0));
}
