// Placeables drawn with their pre-rendered shots (BlockModels, the "rendered"
// method; PlaceableRenders bakes them as NPCRenders does for NPCs), batched in
// MultiMeshes. Each instance is a camera-facing quad at the model's middle
// showing the shot that looks at the model the way the camera does (its turn
// is the instance's: a placed chest's facing), rolled in the screen plane so
// the shot's up lies along the model's (RenderedSprite does the same on the
// CPU for one NPC). It's drawn where the model is, but its depth is taken
// the model's radius nearer the camera, so what lies within the model (the
// ground under it seen from above, a wall behind it) doesn't cut it, and it
// doesn't slide about as you move round it. The atlas is `yaws` x `rows`
// shots: columns round from the front (+z), rows from straight below to
// straight above. With one row (shots straight on only, as placeables have)
// it's Doom's way instead: the quad stands upright, turning round the model's
// vertical only. Lit like the other block models: each block's light in
// INSTANCE_CUSTOM. The sun's optional shadows (sun_shadow.gdshaderinc): in
// the shadow pass it shows the shot the sun sees; it takes its shade from one
// look-up beside it toward the sun (its shots don't line up with the shadow
// map's texel for texel).
shader_type spatial;
render_mode specular_disabled, cull_disabled;

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform int yaws = 16;
uniform int rows = 7;
// The shots' middle (the instance's space), size (metres square) and how far
// the model reaches from its middle.
uniform vec3 center = vec3(0.0);
uniform float size = 1.0;
uniform float radius = 0.0;
uniform float sky_light = 1.0;
uniform vec3 sky_color : source_color = vec3(1.0);
varying vec4 v_light;
varying vec3 v_world;
varying float v_push;
varying vec3 v_origin;
varying float v_reach;
#include "res://shaders/player_light.gdshaderinc"
#include "res://shaders/sun_shadow.gdshaderinc"

void vertex() {
	v_light = INSTANCE_CUSTOM;
	mat3 turn = mat3(MODEL_MATRIX);
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 origin = (MODEL_MATRIX * vec4(center, 1.0)).xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	if (PROJECTION_MATRIX[3][3] > 0.5) {
		to_cam = sun_dir * 1000.0;  // the sun's shadow pass
	}
	v_origin = origin;
	v_reach = radius * s;
	// The shot: the nearest row by pitch, column by yaw (model space).
	vec3 d = normalize(inverse(turn) * to_cam);
	bool upright = rows == 1;
	float step_deg = upright ? 180.0 : 180.0 / float(rows - 1);
	int row = upright ? 0 : clamp(int(round((degrees(asin(clamp(d.y, -1.0, 1.0))) + 90.0) / step_deg)), 0, rows - 1);
	float pitch = upright ? 0.0 : radians(-90.0 + float(row) * step_deg);
	int col = 0;
	bool pole = !upright && (row == 0 || row == rows - 1);
	if (!pole) {
		col = int(round(atan(d.x, d.z) / (6.28318530718 / float(yaws))));
		col = ((col % yaws) + yaws) % yaws;
	}
	// The shot's up (model space): the model's up, or its back / front from
	// straight above / below.
	float yaw = 6.28318530718 * float(col) / float(yaws);
	vec3 vd = normalize(vec3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)));
	vec3 up_m = pole ? (row == rows - 1 ? vec3(0.0, 0.0, -1.0) : vec3(0.0, 0.0, 1.0)) : vec3(0.0, 1.0, 0.0);
	up_m = normalize(up_m - vd * dot(up_m, vd));
	vec3 world_up = normalize(turn * up_m);
	// Facing the camera (upright: round the model's vertical only), rolled so
	// that up shows along the model's. Its depth goes the model's radius
	// toward the camera (never past half way): see fragment().
	vec3 flat_cam = upright ? to_cam - world_up * dot(to_cam, world_up) : to_cam;
	vec3 fwd = normalize(length(flat_cam) > 0.001 ? flat_cam : to_cam);
	v_push = min(radius * s, length(to_cam) * 0.5);
	vec3 up = upright ? world_up : INV_VIEW_MATRIX[1].xyz;
	vec3 right = normalize(cross(up, fwd));
	up = cross(fwd, right);
	float roll = upright ? 0.0 : atan(-dot(world_up, right), dot(world_up, up));
	vec2 v = VERTEX.xy * size * s;
	v = vec2(v.x * cos(roll) - v.y * sin(roll), v.x * sin(roll) + v.y * cos(roll));
	vec3 world = origin + right * v.x + up * v.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	v_world = world;
	UV = (vec2(float(col), float(row)) + UV) / vec2(float(yaws), float(rows));
}

void fragment() {
	vec4 c = texture(atlas, UV);
	if (c.a < 0.5) {
		discard;
	}
	// Premultiplied shots (crisp: their colour), lit as the block models are.
	SUN_SHADOW_COLOUR(c.rgb / c.a, max(v_light.rgb, extra_light(v_world)), vec3(v_light.a * sky_light) * sky_color, 0.0);
	if (SUN_SHADOWS_ON) {
		LIGHT_VERTEX = (VIEW_MATRIX * vec4(v_origin + sun_dir * (v_reach + 0.1), 1.0)).xyz;
	}
	vec4 clip = PROJECTION_MATRIX * vec4(VERTEX + normalize(-VERTEX) * v_push, 1.0);
	DEPTH = clip.z / clip.w;
}
