// Swing auras (scripts/entities/sword_aura.gd: the Night's Edge's), drawn as
// Terraria's DrawProj_NightsEdge draws them, each layer over the last
// (premultiplied alpha, as its SpriteBatch): frame 0 of the 4-frame sheet
// turned back (back_turn) in Color(40, 20, 60) at 0.975 of the size, at 0.8 in
// Color(80, 30, 160) x 0.3, at 0.975 in Color(80, 40, 180) x 0.7, all of them
// times its light (lit) and its fade; then its edge, frame 3, white x 0.3,
// brighter in the dark (1 - 0.7 lit). In front of everything, like a held item.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_premul_alpha, depth_test_disabled, shadows_disabled;

uniform sampler2D sprite : source_color, filter_nearest, repeat_disable;
uniform float fade = 1.0;
uniform float lit = 1.0;
uniform float back_turn = 0.0;
uniform float edge_turn = 0.0;

// A layer: frame `f` of the 4, turned `turn` and drawn `scale` of the quad
// round its centre. (Terraria's y is down: the quad's v runs up its left.)
vec4 layer(vec2 uv, int f, float turn, float scale) {
	vec2 d = (uv - 0.5) / scale;
	float c = cos(-turn), s = sin(-turn);
	d = vec2(c * d.x - s * d.y, s * d.x + c * d.y) + 0.5;
	if (d.x < 0.0 || d.x > 1.0 || d.y < 0.0 || d.y > 1.0) {
		return vec4(0.0);
	}
	vec4 t = texture(sprite, vec2(d.x, (d.y + float(f)) / 4.0));
	return vec4(t.rgb * t.a, t.a);
}

vec4 over(vec4 dst, vec4 src) {
	return src + dst * (1.0 - src.a);
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	float k = lit * fade;
	vec4 c = layer(uv, 0, back_turn, 0.975) * vec4(vec3(40.0, 20.0, 60.0) / 255.0, 1.0) * k;
	c = over(c, layer(uv, 0, 0.0, 0.8) * vec4(vec3(80.0, 30.0, 160.0) / 255.0, 1.0) * k * 0.3);
	c = over(c, layer(uv, 0, 0.0, 0.975) * vec4(vec3(80.0, 40.0, 180.0) / 255.0, 1.0) * k * 0.7);
	c = over(c, layer(uv, 3, edge_turn, 1.0) * 0.3 * fade * (1.0 - lit * 0.7));
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
