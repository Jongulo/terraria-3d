// Doom-style sprites: Y-axis billboard showing one frame of a vertical sprite
// sheet, lit by the voxel light sampled at the entity (set from script).
shader_type spatial;
render_mode specular_disabled, cull_disabled;

#include "res://shaders/billboard.gdshaderinc"
