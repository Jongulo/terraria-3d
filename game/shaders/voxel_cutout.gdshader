shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/voxel_common.gdshaderinc"

void fragment() {
	vec4 c = texture(block_textures, vec3(UV, v_layer_ao.x));
	ALBEDO = c.rgb * voxel_light();
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
