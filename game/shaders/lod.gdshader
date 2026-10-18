// Far terrain (rust/voxel_core/src/lod.rs): coarse cells in each block's
// average colour, lit like the near blocks (voxel_common's squared light).
// COLOR = (albedo rgb in sRGB, face shade baked in; sun), UV.x = block light.
shader_type spatial;
render_mode unshaded, cull_back;

uniform float sky_light = 1.0;
uniform vec3 sky_color : source_color = vec3(1.0);
varying vec4 v_color;
varying float v_block;

void vertex() {
	v_color = COLOR;
	v_block = UV.x;
}

void fragment() {
	vec3 albedo = pow(v_color.rgb, vec3(2.2));
	vec3 l = max(vec3(v_block), vec3(v_color.a * sky_light) * sky_color);
	ALBEDO = albedo * l * l;
}
