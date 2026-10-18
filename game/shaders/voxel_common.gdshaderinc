// Shared by voxel.gdshader / voxel_cutout.gdshader. Vertex data comes from
// rust/voxel_core/src/mesher.rs: COLOR = (block r, g, b, sun), UV2 = (layer, ao).
uniform sampler2DArray block_textures : source_color, filter_nearest_mipmap, repeat_disable;
// Brightness and tint of sunlight (day/night), set by the sky every frame.
uniform float sky_light = 1.0;
uniform vec3 sky_color : source_color = vec3(1.0);
// Raised slightly when the player has a night-vision style effect; 0 = Terraria darkness.
uniform float min_light = 0.0;
#include "res://shaders/player_light.gdshaderinc"

varying vec4 v_light;
varying vec2 v_layer_ao;
varying vec3 v_world;

void vertex() {
	v_light = COLOR;
	v_layer_ao = UV2;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 voxel_light() {
	vec3 sun = vec3(v_light.a * sky_light) * sky_color;
	vec3 l = max(max(v_light.rgb, sun), extra_light(v_world));
	// 15 light levels fall off linearly; squaring gives Terraria's quick fade into darkness.
	l = l * l;
	return max(l, vec3(min_light)) * v_layer_ao.y;
}
