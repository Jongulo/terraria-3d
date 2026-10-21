// Optional real-time shadows from the sun and moon (Settings → Shaders, the
// game's SunShadows node). Included by the shaders that receive them, which
// are drawn "shaded" so Godot works out the sun's shadow map for them, though
// the light itself plays no part in their colour: their own light model
// (voxel light, sunlight, yours) stays as it was, with the sunlight cut to
// `sun_shade` of itself where something stands between it and the sun.
//
// The shadow is looked up once per texel of the surface's own texture (16 a
// block on the blocks), at the texel's middle (LIGHT_VERTEX), so a shadow's
// edge runs along the texture's pixels instead of across them.
//
// With shadows off they look exactly as before: their colour goes out as
// EMISSION, with no light to add to it.
//
// In fragment(): work out the surface's colour and lights as before, then
// SUN_SHADOW_COLOUR(colour, other light, sunlight, darkest) (lights 0..1,
// before they're squared; darkest: the floor after squaring), and snap the
// lookup with one of the SNAP_ helpers.
global uniform bool sun_shadows;
// How much of the sunlight is left in a shadow (0..1).
global uniform float sun_shade;
// Toward the sun (or moon), in the world.
global uniform vec3 sun_dir;

varying vec3 v_sh_other;
varying vec3 v_sh_sun;
varying float v_sh_floor;

#define SUN_SHADOW_COLOUR(col, other, sun, darkest) \
	if (sun_shadows) { \
		ALBEDO = (col); v_sh_other = (other); v_sh_sun = (sun); v_sh_floor = (darkest); \
	} else { \
		vec3 sh_l = max((other), (sun)); \
		EMISSION = (col) * max(sh_l * sh_l, vec3(darkest)); \
		ALBEDO = vec3(0.0); \
	}

// The middle of the world-space texel (`per_block` to a block) the fragment
// at `world` lies in, on a face whose world normal is `n`: snapped across the
// face, not along its normal.
vec3 sun_snap_grid(vec3 world, vec3 n, float per_block) {
	vec3 snapped = (floor(world * per_block) + 0.5) / per_block;
	return mix(snapped, world, step(vec3(0.5), abs(n)));
}

// The same for any textured surface: the view-space point at the middle of
// the texture texel (of a texture `texels` across) under `uv`, found from how
// the view position and UV change across the screen.
vec3 sun_snap_uv(vec3 view_pos, vec2 uv, vec2 texels) {
	vec3 dpx = dFdx(view_pos);
	vec3 dpy = dFdy(view_pos);
	vec2 dux = dFdx(uv);
	vec2 duy = dFdy(uv);
	float det = dux.x * duy.y - duy.x * dux.y;
	if (abs(det) < 1e-12) {
		return view_pos;
	}
	// Columns: how the position changes with u and with v.
	vec3 dpdu = (dpx * duy.y - dpy * dux.y) / det;
	vec3 dpdv = (dpy * dux.x - dpx * duy.x) / det;
	vec2 du = ((floor(uv * texels) + 0.5) / texels) - uv;
	return view_pos + dpdu * du.x + dpdv * du.y;
}

void light() {
	if (sun_shadows && LIGHT_IS_DIRECTIONAL) {
		float lit = ATTENUATION;
#ifdef SUN_FACES
		// Faces turned from the sun (or nearly edge on to it) are in their
		// own shadow: no depth test against themselves, so no shadow acne.
		lit *= step(0.05, dot(NORMAL, LIGHT));
#endif
		vec3 l = max(v_sh_other, v_sh_sun * mix(sun_shade, 1.0, lit));
		DIFFUSE_LIGHT = max(l * l, vec3(v_sh_floor));
	}
}
