shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 plume_color : source_color = vec3(1.0, 0.55, 0.18);
uniform float energy = 3.0;

void fragment() {
	float v = clamp(-UV.y, 0.0, 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.4);
	float a = pow(1.0 - v, 1.35) * mix(0.25, 1.0, fres);
	ALBEDO = plume_color;
	EMISSION = plume_color * energy * (1.0 - v * 0.65);
	ALPHA = a;
}
