// Shared by voxel.gdshader / voxel_cutout.gdshader. Vertex data comes from
// rust/voxel_core/src/mesher.rs: COLOR = (block r, g, b, sun), UV2 = (layer, ao).
uniform sampler2DArray block_textures : source_color, filter_nearest_mipmap, repeat_disable;
// Each layer's art pixels across a block (Data.layer_texels): the sun's
// shadow is looked up once per art pixel.
uniform sampler2D layer_texels : filter_nearest, repeat_disable;
// Brightness and tint of sunlight (day/night), set by the sky every frame.
uniform float sky_light = 1.0;
uniform vec3 sky_color : source_color = vec3(1.0);
// Raised slightly when the player has a night-vision style effect; 0 = Terraria darkness.
uniform float min_light = 0.0;
#include "res://shaders/player_light.gdshaderinc"

varying vec4 v_light;
varying vec2 v_layer_ao;
varying vec3 v_world;

float layer_art_pixels() {
	int layer = int(v_layer_ao.x + 0.5);
	int w = textureSize(layer_texels, 0).x;
	return max(1.0, texelFetch(layer_texels, ivec2(layer % w, layer / w), 0).r);
}

void vertex() {
	v_light = COLOR;
	v_layer_ao = UV2;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Colours the fragment with the voxel light (see voxel_light), through
// sun_shadow.gdshaderinc so the sun's shadows can cut its sunlight.
#define VOXEL_SHADED(col) { \
	vec3 vs_sun = vec3(v_light.a * sky_light) * sky_color; \
	vec3 vs_other = max(v_light.rgb, extra_light(v_world)); \
	SUN_SHADOW_COLOUR((col) * v_layer_ao.y, vs_other, vs_sun, min_light); \
}

vec3 voxel_light() {
	vec3 sun = vec3(v_light.a * sky_light) * sky_color;
	vec3 l = max(max(v_light.rgb, sun), extra_light(v_world));
	// 15 light levels fall off linearly; squaring gives Terraria's quick fade into darkness.
	l = l * l;
	return max(l, vec3(min_light)) * v_layer_ao.y;
}
