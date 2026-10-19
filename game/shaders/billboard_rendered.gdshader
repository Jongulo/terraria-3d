// Pre-rendered NPCs (RenderedSprite): the billboard, its depth pushed toward
// the camera (`push`) so the ground under its model doesn't cut it from
// above, while it's drawn where it is (it doesn't slide as you move round).
shader_type spatial;
render_mode unshaded, cull_disabled;

#define DEPTH_PUSH
#include "res://shaders/billboard.gdshaderinc"
