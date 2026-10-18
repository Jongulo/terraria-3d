// First-person held item. Depth is squeezed into the nearest 1% of the
// (reversed-Z) depth range: the model always draws in front of the world, so it
// never clips into walls, while its own faces still depth-sort correctly.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D sprite : source_color, filter_nearest, repeat_disable;
// Voxel light at the player, already combined with sunlight.
uniform vec3 light = vec3(1.0);

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = POSITION.z * 0.01 + POSITION.w * 0.99;
}

void fragment() {
	vec4 c = texture(sprite, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * COLOR.rgb * light;
}
