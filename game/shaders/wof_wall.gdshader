// The Wall of Flesh's wall (WallOfFlesh): its flesh lit as the blocks are
// (voxel_common.gdshaderinc's light model), with the voxel light read for
// each pixel from `wall_light`, the light of the cells along the wall's plane,
// refreshed as it goes (VoxelWorld.light_plane): dark where nothing lights
// it, glowing by the lava, orange in the Underworld's light. What stands out
// from it (the mouth, the eyes, the Hungry) shades the flesh round it, as
// ambient light is shut out near a thing on a wall.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D flesh : source_color, filter_nearest_mipmap, repeat_enable;
// Its colour till the flesh is made (WofTexture, off the main thread).
uniform vec3 flesh_color : source_color = vec3(0.4, 0.18, 0.26);
uniform bool has_flesh = false;
// How many times the flesh repeats across and up the wall.
uniform vec2 flesh_repeat = vec2(1.0);
// The cells' light (r, g, b, sun): a texel a block, x across the world from
// 0, y up from 0; blended between the cells' middles, as the blocks' corners
// blend theirs.
uniform sampler2D wall_light : filter_linear, repeat_disable;
uniform vec2 light_size = vec2(1.0);
uniform float sky_light = 1.0;
uniform vec3 sky_color : source_color = vec3(1.0);
uniform float min_light = 0.0;
// Those: (x, y, z, radius) each, the first `caster_count`.
uniform vec4 casters[16];
uniform int caster_count = 0;
// How much of the light is shut out right behind one.
uniform float shade = 0.55;
#include "res://shaders/player_light.gdshaderinc"
#include "res://shaders/sun_shadow.gdshaderinc"

varying vec3 v_world;

// The share of the light left at `p` on the wall: each caster shuts out the
// most behind its middle, fading out a little past its edge, and less the
// further it stands out from the wall.
float occlusion(vec3 p) {
	float lit = 1.0;
	for (int i = 0; i < caster_count; i++) {
		vec4 c = casters[i];
		float out_of = abs(c.z - p.z);
		float d = distance(c.xy, p.xy);
		float o = 1.0 - smoothstep(c.w * 0.4, c.w * 1.4 + out_of * 0.2, d);
		o *= clamp(1.0 - (out_of - c.w) / (c.w * 3.0), 0.0, 1.0);
		lit = min(lit, 1.0 - shade * o);
	}
	return lit;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = has_flesh ? texture(flesh, UV * flesh_repeat).rgb : flesh_color;
	vec4 l = texture(wall_light, v_world.xy / light_size);
	float lit = occlusion(v_world);
	vec3 sun = vec3(l.a * sky_light) * sky_color * lit;
	SUN_SHADOW_COLOUR(col, max(l.rgb, extra_light(v_world)) * lit, sun, min_light);
}
