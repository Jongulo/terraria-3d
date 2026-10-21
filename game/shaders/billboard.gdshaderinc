// Doom-style sprites (billboard.gdshader; billboard_rendered.gdshader with
// DEPTH_PUSH for pre-rendered NPCs; the _xray ones with XRAY: a boss seen
// through the blocks in front of it): see billboard.gdshader.
uniform sampler2D sprite : source_color, filter_nearest, repeat_disable;
uniform int frames = 1;
uniform int frame = 0;
// Fraction of each frame cut off at the bottom (sheets with guide lines).
uniform float trim_bottom = 0.0;
uniform bool flip = false;
uniform vec4 tint : source_color = vec4(1.0);
// Light at the entity (r, g, b, sun) and the global sun brightness.
uniform vec4 light = vec4(1.0);
uniform float sky_light = 1.0;
uniform vec3 sky_color : source_color = vec3(1.0);
uniform float flash = 0.0;
// Billboard fully toward the camera (projectiles, drops) instead of only around Y.
uniform bool spherical = false;
// Rotation in the view plane (radians); quads that rotate are centred on their origin.
uniform float rotation = 0.0;
// A world direction (zero: none): the quad's up lies along it, turned round it
// to face the camera, so it points that way in 3D (arrows along their flight,
// foreshortened end-on); `rotation` then turns the sprite within the quad.
uniform vec3 axis = vec3(0.0);
// Never seen quite end-on: at least this share of its length shows, pointing
// where its way goes on the screen (your own arrow, flying off toward the
// crosshair, stays in sight).
uniform float axis_min_side = 0.4;
// How much of it is still there (1: all): fading sprites (gore) drop out in a
// screen-door pattern, so they need no transparency sorting.
uniform float fade = 1.0;
// The part of the texture drawn (x, y, width, height in UV): one shot of a
// pre-rendered NPC's atlas (scripts/entities/rendered_sprite.gd).
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
// The texture's colour is premultiplied by its alpha (pre-rendered shots,
// shrunk with their edges part covered): divided back out.
uniform bool unpremultiply = false;
#ifdef DEPTH_PUSH
// Its depth is taken this share of its half width nearer the camera (never
// past half way): drawn where it is (so it doesn't slide as you move round
// it), but in front of what lies within its model (pre-rendered NPCs: seen
// from above, the ground they stand on doesn't cut them).
uniform float push = 0.0;
varying float v_push;
#endif
#ifdef XRAY
// Drawn over everything, but only where something nearer hides the sprite
// (the scene's depth there is in front of its own): Terraria draws NPCs in
// front of the tiles, so a boss in the blocks is never lost.
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 xray_color : source_color = vec4(1.0, 0.8, 0.35, 0.6);
#endif
#include "res://shaders/player_light.gdshaderinc"

void vertex() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = cam - origin;
	vec3 fwd = spherical ? normalize(to_cam) : normalize(vec3(to_cam.x, 0.0, to_cam.z));
	vec3 up = spherical ? INV_VIEW_MATRIX[1].xyz : vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, fwd));
	up = cross(fwd, right);
	if (dot(axis, axis) > 1e-8) {
		vec3 a = normalize(axis);
		vec3 v = normalize(to_cam);
		float along = dot(a, v);
		vec3 side = a - v * along;
		float s = length(side);
		if (s < axis_min_side) {
			vec3 dir = s > 1e-5 ? side / s : INV_VIEW_MATRIX[1].xyz;
			a = dir * axis_min_side + v * sign(along) * sqrt(1.0 - axis_min_side * axis_min_side);
		}
		up = a;
		right = normalize(cross(up, v));
	}
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	vec2 v = VERTEX.xy * scale.xy;
#ifdef DEPTH_PUSH
	v_push = min(push * scale.x * 0.5, length(to_cam) * 0.5);
#endif
	float cr = cos(rotation);
	float sr = sin(rotation);
	v = vec2(v.x * cr - v.y * sr, v.x * sr + v.y * cr);
	vec3 world = origin + right * v.x + up * v.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	float u = flip ? 1.0 - UV.x : UV.x;
	UV = vec2(u, (UV.y * (1.0 - trim_bottom) + float(frame)) / float(frames));
	UV = region.xy + UV * region.zw;
}

void fragment() {
	vec4 c = texture(sprite, UV);
	if (unpremultiply && c.a > 0.0) {
		c.rgb /= c.a;
	}
	c *= tint;
#ifdef XRAY
	if (c.a < 0.5) {
		discard;
	}
	float d = FRAGCOORD.z;
#ifdef DEPTH_PUSH
	vec4 pushed = PROJECTION_MATRIX * vec4(VERTEX + normalize(-VERTEX) * v_push, 1.0);
	d = pushed.z / pushed.w;
#endif
	// (Reverse Z: nearer is larger.)
	if (d >= textureLod(depth_tex, SCREEN_UV, 0.0).r - 1e-6) {
		discard;
	}
	ALBEDO = mix(c.rgb * 0.6, xray_color.rgb, 0.45);
	ALPHA = xray_color.a * fade;
}
#else
	vec3 sun = vec3(light.a * sky_light) * sky_color;
	vec3 l = max(max(light.rgb, sun), extra_light(NODE_POSITION_WORLD));
	l = max(l * l, vec3(0.04));
	ALBEDO = mix(c.rgb * l, vec3(1.0), flash);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (fade < 1.0 && fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453) > fade) {
		discard;
	}
#ifdef DEPTH_PUSH
	vec4 clip = PROJECTION_MATRIX * vec4(VERTEX + normalize(-VERTEX) * v_push, 1.0);
	DEPTH = clip.z / clip.w;
#endif
}
#endif
