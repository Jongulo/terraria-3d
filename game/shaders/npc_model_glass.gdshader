// A see-through NPC model (King Slime's hand-made body: the ninja inside shows
// through): npc_model.gdshader with `glass` opacity. Only the faces toward
// you are drawn (the voxel meshes wind the other way round from Godot's
// front faces, so the front is culled), so it's one layer of slime.
shader_type spatial;
render_mode specular_disabled, cull_front, depth_draw_always;

#define NPC_MODEL
#define NPC_GLASS
#include "res://shaders/block_model.gdshaderinc"
