// An enemy's health bar (scripts/entities/health_bar.gd): Terraria's
// HealthBar2 (the bar's dark track) with HealthBar1 filled over it up to
// `filled` pixels, both tinted green to red by the life left. It faces the
// camera and sits above the enemy's head; unshaded, so it reads in the dark.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D back_tex : source_color, filter_nearest, repeat_disable;
uniform sampler2D fill_tex : source_color, filter_nearest, repeat_disable;
// Filled width in art pixels (of 36).
uniform float filled = 36.0;
uniform vec4 color : source_color = vec4(0.0, 1.0, 0.0, 1.0);

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec3 world = origin + right * VERTEX.x * scale.x + up * VERTEX.y * scale.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 size = vec2(textureSize(back_tex, 0));
	float px = floor(UV.x * size.x);
	vec4 c = px < filled ? texture(fill_tex, UV) : texture(back_tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * color.rgb;
}
