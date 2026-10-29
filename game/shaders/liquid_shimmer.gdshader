// Shimmer, as Terraria's LiquidRenderer.DrawShimmer draws it: white liquid
// tinted by a slow violet wave across the world (GetShimmerBaseColor) at 0.75
// opacity, not lit (it glows), with a sparkle layer (Misc/water_14's middle
// column) in rainbow glitter that drifts with the wave
// (GetShimmerGlitterColor, GetShimmerGlitterOpacity). Coordinates are in
// Terraria tiles (1.5 a block); its timeForVisualEffects counts 60 a second.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Misc/water_14: 3 columns of 48 px, 17 frames of 80 px; the sparkles are the
// middle column, its full bottom rows (64-79) tile without edges.
uniform sampler2D sparkle_tex : source_color, filter_nearest, repeat_disable;
uniform float opacity = 0.75;

varying float v_face;
varying vec3 v_world;

void vertex() {
	v_face = UV2.x;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float ticks() {
	return TIME * 60.0;
}

float wave(vec2 t) {
	return sin(((t.x + t.y / 6.0) / 10.0 - ticks() / 360.0) * 6.28319);
}

vec3 base_color(vec2 t) {
	return mix(vec3(0.647059, 0.509804, 0.933333), vec3(0.803922, 0.803922, 1.0), 0.1 + wave(t) * 0.4);
}

// Main.hslToRgb(h, 1, 0.5): the pure hue.
vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

float noise(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453) * 10000.0;
}

float glitter_opacity(vec2 t) {
	vec2 cell = floor(t);
	float n = sin(noise(cell) / 10.0 + ticks() / 180.0);
	float a = clamp((wave(t) + 0.5) / 1.5 * 0.35, 0.0, 0.35);
	return clamp(a * n / 0.5, 0.0, 1.0);
}

vec3 sparkle(vec2 t) {
	vec2 cell = floor(t);
	float frame = mod(floor((cell.x + 0.5 + (cell.y + 0.5) / 6.0) / 10.0 - ticks() / 360.0), 16.0);
	vec2 px = vec2(48.0 + mod(floor(t.x * 16.0), 48.0), frame * 80.0 + 64.0 + mod(floor(t.y * 16.0), 16.0));
	float s = texture(sparkle_tex, (px + 0.5) / vec2(144.0, 1360.0)).r;
	vec3 glitter = hue(fract(((t.x + t.y / 6.0) + ticks() / 30.0) / 6.0));
	return s * glitter * glitter_opacity(t);
}

void fragment() {
	vec2 t;
	if (v_face > 0.5 && v_face < 2.5) {
		t = vec2(v_world.x + v_world.z, -v_world.y) * 1.5;
	} else {
		t = v_world.xz * 1.5;
	}
	vec3 c = base_color(t);
	if (v_face > 2.5) {
		// Falling shimmer: streaks running down.
		c *= 0.85 + 0.25 * step(0.7, fract(sin(floor(t.x * 4.0) * 91.7) * 43.1 + (v_world.y + TIME * 3.0) * 0.5));
	}
	ALBEDO = c + sparkle(t);
	ALPHA = opacity;
}
