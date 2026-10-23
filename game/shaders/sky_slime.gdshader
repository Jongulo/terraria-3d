// Slime Rain's background slimes (Terraria's SlimeSky): one frame of a
// 4-frame Sky_Slime sheet, tinted by the sky.
// INSTANCE_CUSTOM.x: frame. COLOR: tint.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_opaque;

uniform sampler2D sheet : source_color, filter_nearest, repeat_disable;
varying float v_frame;
varying vec4 v_tint;

void vertex() {
	v_frame = INSTANCE_CUSTOM.x;
	v_tint = COLOR;
}

void fragment() {
	vec4 c = texture(sheet, vec2(UV.x, (v_frame + UV.y) / 4.0));
	if (c.a < 0.4) {
		discard;
	}
	ALBEDO = c.rgb * v_tint.rgb;
}
