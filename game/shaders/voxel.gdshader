shader_type spatial;
render_mode cull_back, specular_disabled;

#define SUN_FACES
#include "res://shaders/voxel_common.gdshaderinc"
#include "res://shaders/sun_shadow.gdshaderinc"

void fragment() {
	vec4 c = texture(block_textures, vec3(UV, v_layer_ao.x));
	VOXEL_SHADED(c.rgb);
	if (SUN_SHADOWS_ON) {
		// The shadow looked up at the middle of each of the texture's art pixels.
		vec3 n = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
		LIGHT_VERTEX = (VIEW_MATRIX * vec4(sun_snap_grid(v_world, n, layer_art_pixels()), 1.0)).xyz;
	}
}
