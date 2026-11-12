shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Albedo is uploaded already linear. Do not mark these samplers source_color,
// and do not mark the normal hint_normal: NORMAL_MAP unpacks on its own.
uniform sampler2D albedo_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float metallic = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);

void fragment() {
	vec3 alb = texture(albedo_tex, UV).rgb * tint;
	float rough = clamp(texture(rough_tex, UV).r, 0.04, 1.0);
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metallic;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.35;
}
