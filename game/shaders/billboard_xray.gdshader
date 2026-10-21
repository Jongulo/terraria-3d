// A boss's billboard seen through the blocks in front of it (the sprite's
// material_overlay; see billboard.gdshaderinc, XRAY).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix;

#define XRAY
#include "res://shaders/billboard.gdshaderinc"
