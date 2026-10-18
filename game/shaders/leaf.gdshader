// Falling leaves (Terraria's leaf gores): a 12 x 14 frame of the leaf sheet,
// turned to the camera and spun in its plane, lit like the trees.
// INSTANCE_CUSTOM: frame corner (sheet pixels), spin (radians), alpha.
// COLOR: the voxel light where it is (rgb block light, a sunlight).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D sheet : source_color, filter_nearest, repeat_disable;
uniform vec2 sheet_size = vec2(384.0, 112.0);
uniform vec2 frame_size = vec2(12.0, 14.0);
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
	vec3 fwd = normalize(CAMERA_POSITION_WORLD - origin);
	vec3 side = cross(vec3(0.0, 1.0, 0.0), fwd);
	vec3 right = length(side) > 0.001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	vec3 up = cross(fwd, right);
	float c = cos(INSTANCE_CUSTOM.z);
	float s = sin(INSTANCE_CUSTOM.z);
	vec2 v = vec2(VERTEX.x * c - VERTEX.y * s, VERTEX.x * s + VERTEX.y * c);
	float k = length(MODEL_MATRIX[0].xyz);
	v_world = origin + (right * v.x + up * v.y) * k;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(v_world, 1.0);
}

void fragment() {
	vec4 c = texture(sheet, (v_custom.xy + UV * frame_size) / sheet_size);
	if (c.a < 0.5 || v_custom.w < 0.02) {
		discard;
	}
	vec3 l = max(max(v_light.rgb, vec3(v_light.a * sky_light) * sky_color), extra_light(v_world));
	ALBEDO = c.rgb * l * l;
	// Fading out: thinned away pixel by pixel (no sorting needed).
	if (fract(sin(dot(floor(UV * frame_size), vec2(12.9898, 78.233))) * 43758.5453) > v_custom.w) {
		discard;
	}
}
