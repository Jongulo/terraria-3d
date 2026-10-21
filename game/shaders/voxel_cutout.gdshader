shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;

#define SUN_FACES
#include "res://shaders/voxel_common.gdshaderinc"
#include "res://shaders/sun_shadow.gdshaderinc"

void fragment() {
	vec4 c = texture(block_textures, vec3(UV, v_layer_ao.x));
	VOXEL_SHADED(c.rgb);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (sun_shadows) {
		// (Plants and platforms: not all on the block grid.)
		LIGHT_VERTEX = sun_snap_uv(VERTEX, UV, vec2(layer_art_pixels()));
	}
}
