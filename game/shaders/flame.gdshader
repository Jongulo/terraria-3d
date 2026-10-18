// Terraria's flickering flames (TileDrawing.DrawSingleTile_Flames): the flame
// sheet drawn `count` times on top of the torch, each at a random offset (a
// whole number of steps in [min, max), times pixels per step) that changes
// every tick, added on at `brightness` each. In 3D: a quad round the flame,
// turned to face the camera (or fixed: a held torch) and pulled toward it so
// the torch's own model doesn't hide it. INSTANCE_CUSTOM.x seeds each flame.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D flame : source_color, filter_nearest, repeat_disable;
uniform vec2 tex_size = vec2(16.0);
uniform int count = 7;
uniform float brightness = 0.392;
// [min, max) steps and pixels per step, sideways and down (Terraria's y).
uniform vec3 range_x = vec3(-10.0, 11.0, 0.15);
uniform vec3 range_y = vec3(-10.0, 1.0, 0.35);
uniform bool billboard = true;
uniform float toward = 0.25;
uniform float seed = 0.0;
uniform bool batched = true;
// A held torch: drawn in the viewmodel's depth range (viewmodel.gdshader).
uniform bool viewmodel = false;
varying float v_seed;

void vertex() {
	v_seed = batched ? INSTANCE_CUSTOM.x : seed;
	if (billboard) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		vec3 to_cam = CAMERA_POSITION_WORLD - origin;
		vec3 fwd = length(to_cam) > 0.001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
		vec3 side = cross(vec3(0.0, 1.0, 0.0), fwd);
		vec3 right = length(side) > 0.001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
		vec3 up = cross(fwd, right);
		float sx = length(MODEL_MATRIX[0].xyz);
		float sy = length(MODEL_MATRIX[1].xyz);
		vec3 world = origin + right * VERTEX.x * sx + up * VERTEX.y * sy + fwd * toward;
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	} else if (viewmodel) {
		POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		POSITION.z = POSITION.z * 0.01 + POSITION.w * 0.99;
	}
}

float rnd(float a, float b, float c) {
	return fract(sin(dot(vec3(a, b, c), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	float tick = floor(TIME * 60.0);
	vec3 sum = vec3(0.0);
	for (int k = 0; k < count; k++) {
		float ox = floor(mix(range_x.x, range_x.y, rnd(v_seed, tick, float(k)))) * range_x.z;
		float oy = floor(mix(range_y.x, range_y.y, rnd(v_seed + 7.13, tick, float(k)))) * range_y.z;
		vec4 c = texture(flame, UV - vec2(ox, oy) / tex_size);
		sum += c.rgb * c.a;
	}
	ALBEDO = sum * brightness;
}
