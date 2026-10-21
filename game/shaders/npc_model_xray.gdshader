// A boss's 3D model seen through the blocks in front of it (its
// material_overlay): a flat tinted silhouette over everything, only where
// something nearer hides the model (see billboard.gdshaderinc, XRAY).
shader_type spatial;
render_mode unshaded, cull_back, depth_test_disabled, depth_draw_never, blend_mix;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 xray_color : source_color = vec4(1.0, 0.8, 0.35, 0.45);

void fragment() {
	// (Reverse Z: nearer is larger.)
	if (FRAGCOORD.z >= textureLod(depth_tex, SCREEN_UV, 0.0).r - 1e-6) {
		discard;
	}
	ALBEDO = xray_color.rgb;
	ALPHA = xray_color.a;
}
