// A pre-rendered boss seen through the blocks in front of it (see
// billboard.gdshaderinc, XRAY and DEPTH_PUSH).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix;

#define DEPTH_PUSH
#define XRAY
#include "res://shaders/billboard.gdshaderinc"
