// Raindrops (Terraria's Rain sheet: a 2 x 40 frame at 4 px a drop type),
// each a streak along its fall turned to face the camera, lit by where it is
// at 0.85 (Main.DrawRain).
// MODEL_MATRIX: its place; its y axis its fall (length), x its width.
// INSTANCE_CUSTOM: x frame corner (sheet pixels).
// COLOR: the voxel light where it is (rgb block light, a sunlight).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D sheet : source_color, filter_nearest, repeat_disable;
uniform vec2 sheet_size = vec2(168.0, 42.0);
uniform vec2 frame_size = vec2(2.0, 40.0);
uniform float sky_light = 1.0;
uniform vec3 sky_color : source_color = vec3(1.0);
varying vec4 v_custom;
varying vec4 v_light;
varying vec3 v_world;
#include "res://shaders/player_light.gdshaderinc"

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_light = COLOR;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 along = MODEL_MATRIX[1].xyz;
	float wide = length(MODEL_MATRIX[0].xyz);
	vec3 axis = normalize(along);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - origin);
	vec3 side = cross(axis, to_cam);
	side = length(side) > 0.001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	v_world = origin + side * VERTEX.x * wide + along * VERTEX.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(v_world, 1.0);
}

void fragment() {
	vec4 c = texture(sheet, (v_custom.xy + vec2(UV.x, UV.y) * frame_size) / sheet_size);
	if (c.a < 0.02) {
		discard;
	}
	vec3 l = max(max(v_light.rgb, vec3(v_light.a * sky_light) * sky_color), extra_light(v_world));
	ALBEDO = c.rgb * l * 0.85;
	ALPHA = c.a;
}
