// Decorative waterfall streams (scripts/world/waterfalls.gd), using Terraria's
// Waterfall_0 / Waterfall_1 strips: 16 frames of 32x40, stream in columns 10-19,
// rows 24-39, tiled down the fall. UV.y is world height so the texture scrolls
// continuously; water is lit by the world (per-instance light), lava glows.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D fall_tex : source_color, filter_nearest, repeat_disable;
uniform bool lava = false;
uniform float sky_light = 1.0;
uniform vec3 sky_color : source_color = vec3(1.0);
instance uniform vec4 light = vec4(1.0);
#include "res://shaders/player_light.gdshaderinc"

void fragment() {
	float speed = lava ? 24.0 : 48.0;
	float frame = floor(mod(TIME * (lava ? 8.0 : 12.0), 16.0));
	float px = 10.0 + clamp(floor(fract(UV.x) * 10.0), 0.0, 9.0);
	float row = 24.0 + mod(floor(-UV.y * 16.0 - TIME * speed), 16.0);
	vec4 c = texture(fall_tex, vec2((frame * 32.0 + px + 0.5) / 512.0, (row + 0.5) / 40.0));
	if (lava) {
		ALBEDO = c.rgb * 1.05;
	} else {
		vec3 l = max(max(light.rgb, vec3(light.a * sky_light) * sky_color), extra_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
		ALBEDO = c.rgb * max(l * l, vec3(0.03));
		ALPHA = 0.85;
	}
}
