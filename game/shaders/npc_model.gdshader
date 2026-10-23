// Enemies and town NPCs drawn as 3D models (scripts/entities/npc_model.gd):
// the block model shader, lit by the `light` instance uniform, with a tint and
// a hit flash per enemy. See block_model.gdshaderinc.
shader_type spatial;
render_mode specular_disabled, cull_disabled;

#define NPC_MODEL
#include "res://shaders/block_model.gdshaderinc"
