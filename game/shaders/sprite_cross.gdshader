// Crossed-quad sprites (tree canopies) lit by sunlight only.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D sprite : source_color, filter_nearest, repeat_disable;
uniform float sky_light = 1.0;
uniform vec3 sky_color : source_color = vec3(1.0);

void fragment() {
	vec4 c = texture(sprite, UV);
	float l = sky_light * sky_light;
	ALBEDO = c.rgb * l * sky_color;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
