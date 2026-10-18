// Block models drawn one node each (the placeable picker, doors, tree
// canopies): lit by the `light` instance uniform. See block_model.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/block_model.gdshaderinc"
