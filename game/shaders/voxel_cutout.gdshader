shader_type spatial;
render_mode cull_disabled, specular_disabled;

#define SUN_FACES
#include "res://shaders/voxel_common.gdshaderinc"
#include "res://shaders/sun_shadow.gdshaderinc"

void fragment() {
	vec4 c = block_tex(UV, v_layer_ao.x);
	VOXEL_SHADED(c.rgb);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (SUN_SHADOWS_ON) {
		// (Plants and platforms: not all on the block grid.)
		LIGHT_VERTEX = sun_snap_uv(VERTEX, UV, vec2(layer_art_pixels()));
	}
}
