shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/voxel_common.gdshaderinc"

void fragment() {
	vec4 c = texture(block_textures, vec3(UV, v_layer_ao.x));
	ALBEDO = c.rgb * voxel_light();
}
