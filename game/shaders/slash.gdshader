// Held slashes (scripts/entities/slash.gd: the Terragrim): one frame of a
// vertically stacked sheet, drawn as Terraria draws them (GetAlpha: the light
// lerped 85% to white, alpha 128 on premultiplied colour, so they glow over
// what's behind), in front of everything (like a held item).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_premul_alpha, depth_test_disabled, shadows_disabled;

uniform sampler2D sprite : source_color, filter_nearest, repeat_disable;
uniform int frames = 1;
uniform int frame = 0;
uniform vec3 light : source_color = vec3(1.0);

void fragment() {
	vec2 uv = vec2(UV.x, (UV.y + float(frame)) / float(frames));
	vec4 c = texture(sprite, uv);
	ALBEDO = c.rgb * light * c.a;
	ALPHA = c.a * (128.0 / 255.0);
}
