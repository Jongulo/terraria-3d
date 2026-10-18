// Doom-style sprites: Y-axis billboard showing one frame of a vertical sprite
// sheet, lit by the voxel light sampled at the entity (set from script).
shader_type spatial;
render_mode unshaded, cull_disabled;

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
// How much of it is still there (1: all): fading sprites (gore) drop out in a
// screen-door pattern, so they need no transparency sorting.
uniform float fade = 1.0;
// The part of the texture drawn (x, y, width, height in UV): one shot of a
// pre-rendered NPC's atlas (scripts/entities/rendered_sprite.gd).
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
// The texture's colour is premultiplied by its alpha (pre-rendered shots,
// shrunk with their edges part covered): divided back out.
uniform bool unpremultiply = false;
#include "res://shaders/player_light.gdshaderinc"

void vertex() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = cam - origin;
	vec3 fwd = spherical ? normalize(to_cam) : normalize(vec3(to_cam.x, 0.0, to_cam.z));
	vec3 up = spherical ? INV_VIEW_MATRIX[1].xyz : vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, fwd));
	up = cross(fwd, right);
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	vec2 v = VERTEX.xy * scale.xy;
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
	vec3 sun = vec3(light.a * sky_light) * sky_color;
	vec3 l = max(max(light.rgb, sun), extra_light(NODE_POSITION_WORLD));
	l = max(l * l, vec3(0.04));
	ALBEDO = mix(c.rgb * l, vec3(1.0), flash);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (fade < 1.0 && fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453) > fade) {
		discard;
	}
}
