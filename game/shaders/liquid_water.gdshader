// Water: Terraria's animated Liquid_0 strip (17 frames, 16 px, 18 px stride).
// Sides show the bright surface band only near the top (UV.y = depth below the
// surface in blocks); tops get a gentle world-space shimmer. Lit like blocks.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D liquid_tex : source_color, filter_nearest, repeat_disable;
// Waterfall_0: 16 frames of 32x40; the falling stream is columns 10-19, rows 24-39.
uniform sampler2D fall_tex : source_color, filter_nearest, repeat_disable;
uniform float sky_light = 1.0;
uniform vec3 sky_color : source_color = vec3(1.0);
uniform float opacity = 0.62;

varying vec4 v_light;
#include "res://shaders/player_light.gdshaderinc"
varying float v_face;
varying vec3 v_world;

void vertex() {
	v_light = COLOR;
	v_face = UV2.x;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec4 strip(float frame, vec2 px) {
	return texture(liquid_tex, vec2((frame * 18.0 + clamp(px.x, 0.0, 15.0) + 0.5) / 306.0, (clamp(px.y, 0.0, 15.0) + 0.5) / 16.0));
}

// Scrolling stream texel; `world_y` in blocks (UV.y of stream faces).
vec4 stream(float u, float world_y) {
	float frame = floor(mod(TIME * 12.0, 16.0));
	float px = 10.0 + clamp(floor(fract(u) * 10.0), 0.0, 9.0);
	float row = 24.0 + mod(floor(-world_y * 16.0 - TIME * 48.0), 16.0);
	return texture(fall_tex, vec2((frame * 32.0 + px + 0.5) / 512.0, (row + 0.5) / 40.0));
}

void fragment() {
	float frame = floor(mod(TIME * 8.0, 17.0));
	vec4 c;
	float alpha = opacity;
	if (v_face > 2.5) {
		c = v_face > 3.5 ? strip(frame, vec2(8.0, 2.0)) : stream(UV.x, UV.y);
		alpha = 0.85;
	} else if (v_face > 0.5 && v_face < 1.5) {
		vec2 px = vec2(floor(fract(UV.x) * 16.0), floor(UV.y * 16.0));
		c = px.y < 8.0 ? strip(frame, px) : strip(frame, vec2(px.x, 12.0));
	} else {
		vec2 w = floor(v_world.xz * 16.0);
		c = strip(frame, vec2(mod(w.x, 16.0), 12.0));
		float shimmer = sin(w.x * 0.37 + TIME * 2.1) * sin(w.y * 0.31 - TIME * 1.6);
		c.rgb += vec3(0.05, 0.07, 0.09) * step(0.55, shimmer);
	}
	vec3 sun = vec3(v_light.a * sky_light) * sky_color;
	vec3 l = max(max(v_light.rgb, sun), extra_light(v_world));
	l = max(l * l, vec3(0.03));
	ALBEDO = c.rgb * l;
	ALPHA = alpha;
}
