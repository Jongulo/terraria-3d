// Torch embers (Terraria's torch dust): a frame of the dust sheet, turned to
// the camera, glowing. INSTANCE_CUSTOM: frame corner (sheet pixels), alpha.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform sampler2D dust : source_color, filter_nearest, repeat_disable;
uniform vec2 sheet_size = vec2(1000.0, 120.0);
varying vec3 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM.xyw;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 fwd = normalize(CAMERA_POSITION_WORLD - origin);
	vec3 side = cross(vec3(0.0, 1.0, 0.0), fwd);
	vec3 right = length(side) > 0.001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	vec3 up = cross(fwd, right);
	float s = length(MODEL_MATRIX[0].xyz);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(origin + (right * VERTEX.x + up * VERTEX.y) * s, 1.0);
}

void fragment() {
	vec4 c = texture(dust, (v_custom.xy + UV * 8.0) / sheet_size);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ALPHA = c.a * v_custom.z;
}
