shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform vec3 deep_color : source_color = vec3(0.02, 0.07, 0.09);
uniform vec3 shallow_color : source_color = vec3(0.05, 0.22, 0.24);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = sin(world_pos.x * 0.028 + TIME * 0.35) * cos(world_pos.z * 0.022 - TIME * 0.22);
	float n2 = sin((world_pos.x + world_pos.z) * 0.06 - TIME * 0.45);
	vec3 col = mix(deep_color, shallow_color, clamp(n * 0.35 + n2 * 0.15 + 0.45, 0.0, 1.0));
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 4.0);
	col = mix(col, vec3(0.42, 0.52, 0.56), fres * 0.62);
	ALBEDO = col;
	ROUGHNESS = mix(0.045, 0.2, 1.0 - fres);
	METALLIC = 0.12;
	SPECULAR = 0.55;
}
