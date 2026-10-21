// Block models batched in MultiMeshes (BlockModels): lit by each instance's
// custom data, with no instance uniform. See block_model.gdshaderinc.
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled, cull_disabled;

#define BATCHED
#include "res://shaders/block_model.gdshaderinc"
