shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 paint_color : source_color = vec3(0.86, 0.83, 0.76);
uniform vec3 skirt_color : source_color = vec3(0.18, 0.18, 0.19);
uniform vec3 band_color : source_color = vec3(0.73, 0.40, 0.22);
uniform float skirt_end = 1.1;
uniform float band_0 = 2.4;
uniform float band_1 = 2.75;
uniform float band_2 = -1.0;
uniform float band_3 = -1.0;
uniform float frost = 0.0;
uniform float soot = 0.0;
uniform float window_0 = -1.0;
uniform float window_1 = -1.0;

void fragment() {
	float y = UV.y;
	float around = UV.x;
	vec3 col = paint_color;
	float rough = 0.42;
	float metal = 0.12;

	if (y < skirt_end) {
		col = skirt_color;
		rough = 0.58;
		metal = 0.45;
	}
	if (y >= band_0 && y <= band_1) {
		col = band_color;
		rough = 0.28;
		metal = 0.62;
	}
	if (band_2 >= 0.0 && y >= band_2 && y <= band_3) {
		col = band_color * vec3(0.85);
		rough = 0.30;
		metal = 0.55;
	}
	if (window_1 > window_0 && y >= window_0 && y <= window_1) {
		col = vec3(0.012, 0.016, 0.02);
		rough = 0.05;
		metal = 0.88;
	}

	float along = abs(fract(y * 1.15) - 0.5);
	float line = smoothstep(0.47, 0.5, along);
	float seam = min(fract(around * 8.0), 1.0 - fract(around * 8.0));
	float seam_line = smoothstep(0.018, 0.0, seam);
	col *= 1.0 - 0.46 * max(line, seam_line);

	float rivet_y = abs(fract(y * 2.4) - 0.5);
	float rivet = smoothstep(0.045, 0.0, length(vec2(seam, rivet_y * 0.12)));
	col *= 1.0 - 0.35 * rivet;

	float frost_mask = smoothstep(skirt_end + 0.2, skirt_end + 2.5, y) * frost;
	col = mix(col, vec3(0.62, 0.72, 0.78), frost_mask * 0.7);
	rough = mix(rough, 0.16, frost_mask);

	float soot_mask = (1.0 - smoothstep(skirt_end, skirt_end + 4.5, y)) * soot;
	col = mix(col, vec3(0.035, 0.03, 0.028), soot_mask * 0.75);
	rough = mix(rough, 0.8, soot_mask);

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = metal;
	EMISSION = vec3(0.22, 0.12, 0.06) * rim * 0.16;
}
