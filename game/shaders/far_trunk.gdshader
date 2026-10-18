// Far tree trunks (FarTrees): a strip of the trunk's sprite from its base
// (MODEL_MATRIX origin) up its axis (basis y, to the canopy) and as wide as
// basis x is long, turned about the axis to face the camera, the sprite
// repeated up it (one repeat every `tile` blocks). COLOR: the light there.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D sprite : source_color, filter_nearest, repeat_enable;
uniform float tile = 1.0;
uniform float sky_light = 1.0;
uniform vec3 sky_color : source_color = vec3(1.0);
// Hidden where the full-detail chunks draw the trunk's blocks (its column's
// level-1 far tile has its middle within `near_radius` chunks of
// `focus_chunk`'s middle: LodRenderer.is_near) and past `reach` blocks.
uniform vec2 focus_chunk = vec2(0.0);
uniform float near_radius = 0.0;
uniform float reach = 0.0;
varying vec4 v_light;
varying float v_len;

void vertex() {
	v_light = COLOR;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 p = origin + axis * VERTEX.y;
	vec3 side = cross(axis, CAMERA_POSITION_WORLD - p);
	side = length(side) > 0.0001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	v_len = length(axis);
	UV = vec2(UV.x, (1.0 - VERTEX.y) * v_len / tile);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p + side * VERTEX.x * w, 1.0);
	vec2 far_tile = floor(floor(origin.xz / 32.0) / 2.0);
	bool near = length(far_tile * 2.0 + 1.0 - (focus_chunk + 0.5)) < near_radius;
	bool far = distance(origin.xz, (focus_chunk + 0.5) * 32.0) > reach;
	if (near || far) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);  // not drawn
	}
}

void fragment() {
	vec4 c = texture(sprite, UV);
	if (c.a < 0.5) {
		discard;
	}
	vec3 l = max(v_light.rgb, vec3(v_light.a * sky_light) * sky_color);
	ALBEDO = c.rgb * l * l;
}
