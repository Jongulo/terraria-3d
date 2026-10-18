// The sky (scripts/world/sky.gd): a gradient from the horizon to the top, a
// warm glow around the sun low in the sky (sunrise, sunset), a soft halo
// around the sun or moon, and pixel stars that twinkle at night (and by day
// high in the Space layer).
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.33, 0.55, 0.98);
uniform vec3 horizon_color : source_color = vec3(0.6, 0.78, 1.0);
uniform vec3 below_color : source_color = vec3(0.2, 0.3, 0.5);
// Towards the sun (or moon).
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
// The glow around the sun near the horizon, and the halo right around it.
uniform vec3 glow_color : source_color = vec3(1.0, 0.55, 0.3);
uniform float glow = 0.0;
uniform vec3 halo_color : source_color = vec3(1.0, 0.95, 0.8);
uniform float halo = 0.4;
// 0 none .. 1 every star at full brightness.
uniform float stars = 0.0;
uniform float time_s = 0.0;
// 0 above ground .. 1 deep underground (all black).
uniform float under = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// A star field on a cube around the viewer: one cell in a few hundred holds a
// star, a small square (pixel-art), some brighter, tinted blue or gold.
vec3 star_field(vec3 d) {
	vec3 a = abs(d);
	vec2 uv;
	float face;
	if (a.x >= a.y && a.x >= a.z) {
		uv = d.zy / a.x;
		face = sign(d.x);
	} else if (a.y >= a.z) {
		uv = d.xz / a.y;
		face = 2.0 * sign(d.y);
	} else {
		uv = d.xy / a.z;
		face = 3.0 * sign(d.z);
	}
	const float CELLS = 150.0;
	vec2 g = uv * CELLS;
	vec2 cell = floor(g);
	float h = hash(vec3(cell, face));
	if (h < 0.975) {
		return vec3(0.0);
	}
	vec2 local = g - cell;
	vec2 at = vec2(hash(vec3(cell, face + 7.0)), hash(vec3(cell, face + 13.0))) * 0.6 + 0.2;
	float size = h > 0.995 ? 0.14 : 0.08;
	vec2 off = abs(local - at);
	if (max(off.x, off.y) > size) {
		return vec3(0.0);
	}
	float twinkle = 0.65 + 0.35 * sin(time_s * (1.5 + 3.0 * fract(h * 91.0)) + h * 400.0);
	vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.92, 0.75), fract(h * 37.0));
	return tint * twinkle * (h > 0.995 ? 1.2 : 0.8);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 col;
	if (y >= 0.0) {
		col = mix(horizon_color, top_color, pow(y, 0.55));
	} else {
		col = mix(horizon_color, below_color, clamp(-y * 4.0, 0.0, 1.0));
	}
	// Sunrise and sunset: warm light spreading along the horizon on the sun's side.
	float toward = max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(sun_dir.x, 0.0, sun_dir.z))), 0.0);
	float low = exp(-abs(y) * 4.0);
	col += glow_color * glow * pow(toward, 3.0) * low;
	// The halo right around the sun or moon.
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	col += halo_color * halo * (pow(s, 180.0) * 0.8 + pow(s, 18.0) * 0.25);
	// Stars, fading out towards the horizon.
	if (stars > 0.0 && y > -0.05) {
		col += star_field(d) * stars * smoothstep(-0.05, 0.25, y);
	}
	COLOR = mix(col, vec3(0.0), under);
}
