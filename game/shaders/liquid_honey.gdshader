// Honey: Terraria's Liquid_11 (one 16 px frame), nearly opaque (its
// LiquidRenderer opacity 0.95), a slow ooze across the top; lit like blocks.
// Falling honey streams use Waterfall_14, Terraria's honeyfall.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D liquid_tex : source_color, filter_nearest, repeat_disable;
// Waterfall_14: 16 frames of 32x40; the falling stream is columns 10-19, rows 24-39.
uniform sampler2D fall_tex : source_color, filter_nearest, repeat_disable;
uniform float sky_light = 1.0;
uniform vec3 sky_color : source_color = vec3(1.0);
uniform float opacity = 0.95;

varying vec4 v_light;
#include "res://shaders/player_light.gdshaderinc"
varying float v_face;
varying vec3 v_world;

void vertex() {
	v_light = COLOR;
	v_face = UV2.x;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec4 honey(vec2 px) {
	return texture(liquid_tex, (clamp(px, vec2(0.0), vec2(15.0)) + 0.5) / 16.0);
}

// Scrolling stream texel (slow, like honey); `world_y` in blocks.
vec4 stream(float u, float world_y) {
	float frame = floor(mod(TIME * 6.0, 16.0));
	float px = 10.0 + clamp(floor(fract(u) * 10.0), 0.0, 9.0);
	float row = 24.0 + mod(floor(-world_y * 16.0 - TIME * 12.0), 16.0);
	return texture(fall_tex, vec2((frame * 32.0 + px + 0.5) / 512.0, (row + 0.5) / 40.0));
}

void fragment() {
	vec4 c;
	if (v_face > 2.5) {
		c = v_face > 3.5 ? honey(vec2(8.0, 2.0)) : stream(UV.x, UV.y);
	} else if (v_face > 0.5 && v_face < 1.5) {
		vec2 px = vec2(floor(fract(UV.x) * 16.0), floor(UV.y * 16.0));
		c = px.y < 6.0 ? honey(px) : honey(vec2(px.x, 12.0));
	} else {
		vec2 w = floor(v_world.xz * 16.0);
		w += floor(vec2(sin(TIME * 0.3 + v_world.z * 1.1), cos(TIME * 0.25 + v_world.x * 0.9)) * 2.0);
		c = honey(vec2(mod(w.x, 16.0), 8.0 + mod(w.y, 8.0)));
	}
	vec3 sun = vec3(v_light.a * sky_light) * sky_color;
	vec3 l = max(max(v_light.rgb, sun), extra_light(v_world));
	l = max(l * l, vec3(0.03));
	ALBEDO = c.rgb * l;
	ALPHA = opacity;
}
