// A ring of Terraria background art around the viewer (scripts/world/sky.gd).
// Pixel art, cut out by alpha, lit by the sky; `fade` (0..1) dissolves it in
// a dither pattern so a biome's layer can cross-fade into another's while
// staying opaque (no sorting between the rings). `sea_mask` (one texel per
// direction round the viewer, angle from +x toward +z) hides it where the
// open sea reaches the horizon.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, fog_disabled;

uniform sampler2D art : source_color, filter_nearest, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float fade = 1.0;
// Fades the art into the sky colour (far layers look hazier, like Terraria's).
uniform vec3 haze_color : source_color = vec3(0.6, 0.78, 1.0);
uniform float haze = 0.0;
uniform sampler2D sea_mask : hint_default_white, filter_linear, repeat_enable;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec4 c = texture(art, UV);
	ivec2 p = ivec2(FRAGCOORD.xy) % 4;
	vec2 d = v_world.xz - NODE_POSITION_WORLD.xz;
	float shown = fade * texture(sea_mask, vec2(fract(atan(d.y, d.x) / TAU), 0.5)).r;
	if (c.a < 0.5 || shown <= (BAYER[p.y * 4 + p.x] + 0.5) / 16.0) {
		discard;
	}
	ALBEDO = mix(c.rgb * tint, haze_color, haze);
}
