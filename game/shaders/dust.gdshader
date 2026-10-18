shader_type spatial;
// Terraria's dust (DustParticles): camera-facing quads, one per MultiMesh
// instance, each showing its 8x8 frame of Images/Dust (INSTANCE_CUSTOM.xy: the
// frame's top-left pixel), tinted by its light and colour (instance COLOR).
render_mode unshaded, cull_disabled;

uniform sampler2D atlas : filter_nearest, source_color;
uniform vec2 atlas_size = vec2(1000.0, 120.0);

varying vec2 v_frame;
varying vec4 v_color;

void vertex() {
	// Billboard, keeping the instance's scale (its size).
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = center + (right * VERTEX.x + up * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	v_frame = INSTANCE_CUSTOM.xy;
	v_color = COLOR;
}

void fragment() {
	vec4 t = texture(atlas, (v_frame + UV * 8.0) / atlas_size);
	if (t.a < 0.5) {
		discard;
	}
	ALBEDO = t.rgb * v_color.rgb;
}
