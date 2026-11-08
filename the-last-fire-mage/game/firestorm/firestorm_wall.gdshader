shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D rune_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform float circumference = 100.0;
uniform float stage_energy = 1.0;

void fragment() {
	float height = 1.0 - UV.y;
	float arc = UV.x * circumference;
	float rise = TIME * 2.4;
	float tongues = 0.48 + 0.18 * sin(arc * 0.67 + rise + height * 5.0)
		+ 0.14 * sin(arc * 1.71 - rise * 0.7 + height * 12.0);
	float fire = (1.0 - smoothstep(tongues - 0.23, tongues + 0.18, height))
		* smoothstep(0.18, 0.8, 0.55 + 0.45 * sin(arc * 1.1 + height * 19.0 - rise * 3.0));
	float tiles = max(1.0, round(circumference / 23.0));
	vec2 rune_uv = vec2(UV.x * tiles, UV.y + TIME * (0.10 + 0.025 * stage_energy));
	vec3 rune = texture(rune_texture, rune_uv).rgb;
	float glyph = smoothstep(0.1, 0.8, rune.r) * (1.0 - smoothstep(0.2, 1.0, height));
	float heat = max(fire, glyph);
	vec3 flame_color = mix(vec3(1.0, 0.065, 0.008), vec3(1.0, 0.61, 0.10), fire);
	vec3 rune_color = mix(vec3(1.0, 0.18, 0.015), vec3(1.0, 0.72, 0.24), rune.g);
	ALBEDO = mix(flame_color, rune_color, glyph);
	EMISSION = (flame_color * fire * 1.4 + rune_color * glyph * 3.0) * stage_energy;
	ALPHA = clamp(heat * 0.82 + (1.0 - height) * 0.10, 0.0, 0.92);
}
