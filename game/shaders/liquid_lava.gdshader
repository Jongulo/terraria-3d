// Lava: glows at full brightness (it lights the world itself), with slow
// flowing distortion on top and Terraria's bright band near the surface.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D liquid_tex : source_color, filter_nearest, repeat_disable;
// Waterfall_1 (lava): same layout as the water strip.
uniform sampler2D fall_tex : source_color, filter_nearest, repeat_disable;

varying float v_face;
varying vec3 v_world;

void vertex() {
	v_face = UV2.x;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec4 lava(vec2 px) {
	return texture(liquid_tex, (clamp(px, vec2(0.0), vec2(15.0)) + 0.5) / 16.0);
}

vec4 stream(float u, float world_y) {
	float frame = floor(mod(TIME * 8.0, 16.0));
	float px = 10.0 + clamp(floor(fract(u) * 10.0), 0.0, 9.0);
	float row = 24.0 + mod(floor(-world_y * 16.0 - TIME * 24.0), 16.0);
	return texture(fall_tex, vec2((frame * 32.0 + px + 0.5) / 512.0, (row + 0.5) / 40.0));
}

void fragment() {
	vec4 c;
	if (v_face > 2.5) {
		c = v_face > 3.5 ? lava(vec2(8.0, 1.0)) : stream(UV.x, UV.y);
	} else if (v_face > 0.5 && v_face < 1.5) {
		vec2 px = vec2(floor(fract(UV.x) * 16.0), floor(UV.y * 16.0));
		c = px.y < 6.0 ? lava(px) : lava(vec2(px.x, 10.0));
	} else {
		vec2 w = v_world.xz * 16.0;
		w += vec2(sin(TIME * 0.6 + v_world.z * 1.3), cos(TIME * 0.5 + v_world.x * 1.1)) * 3.0;
		float n = sin(floor(w.x) * 0.41 + TIME * 0.9) * sin(floor(w.y) * 0.37 - TIME * 0.7);
		c = mix(lava(vec2(8.0, 12.0)), lava(vec2(8.0, 1.0)), smoothstep(0.2, 0.9, n));
	}
	ALBEDO = c.rgb * 1.08;
}
