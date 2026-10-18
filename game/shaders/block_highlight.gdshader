// Outline of the targeted block: only fragments near the cube's edges are drawn.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 a = abs(local_pos) * 2.0;
	// On an edge when at least two coordinates are at the cube's surface.
	float near_edges = step(0.94, a.x) + step(0.94, a.y) + step(0.94, a.z);
	if (near_edges < 2.0) {
		discard;
	}
	ALBEDO = vec3(1.0, 0.95, 0.5);
	ALPHA = 0.85;
}
