class_name PlaceableRenders
## Pre-rendered shots of placeables (the placeable picker's "rendered" method),
## made as NPCRenders makes an NPC's, but only straight on: the block's model
## shot from YAWS directions round it at eye level (Doom's way; BlockModels
## stands them upright, turning round the vertical only), each shot shrunk to
## the art's pixels, every frame of an animated block. The model is the
## Extruded one if its rendered setting says so, else its tuned model, else
## Claude's, else its hull, with the block's offset, rotation and scale. BlockModels draws them (rendered_batched.gdshader) once they're made,
## and the block's billboard until then (or where nothing renders: headless).
## Cached in NPCRenders.dir as "block-<name>_...".

## Shots round the model (every 22.5 degrees), all at eye level.
const YAWS := 16
const PITCHES := [0.0]

## block id -> NPCRenders.bake_shots' result.
static var _done := {}
static var _baking := {}
static var _stale := {}


## The method whose model the shots are of.
static func source(block_id: int) -> String:
	var d := Data.block(block_id)
	var settings: String = d.get("settings", d.name)
	if Data.method_options(settings, "rendered").model == "extruded":
		return "extruded"
	if TunedModels.has(TunedModels.block_key(settings)):
		return "tuned"
	if Data.handmade_models.has(settings):
		return "claude"
	return "hull"


## Its shots, or {} while they're being made (or can't be).
static func renders(block_id: int) -> Dictionary:
	if _done.has(block_id):
		return _done[block_id]
	if not _baking.has(block_id) and NPCRenders.can_render():
		_baking[block_id] = true
		_bake.call_deferred(block_id)
	return {}


## Forgets a block's shots (all with -1), so they're made again: its model or
## settings changed. A bake under way is dropped.
static func forget(block_id := -1) -> void:
	for id in _baking:
		if block_id < 0 or id == block_id:
			_stale[id] = true
	if block_id < 0:
		_done.clear()
	else:
		_done.erase(block_id)


static func _bake(block_id: int) -> void:
	var d := Data.block(block_id)
	var src := source(block_id)
	var meshes: Array = []
	for f in Data.anim_frames(d):
		var m := BlockModels.model_mesh(block_id, src, 0, f)
		meshes.append({"mesh": m.mesh, "textured": m.textured})
	# One pixel per voxel: the art's pixels, at the block's scale.
	var apx: float = float(d.get("art_px", d.sprite_px)) * Data.block_transform(d).basis.get_scale().x
	var done := await NPCRenders.bake_shots("block-" + d.name, meshes,
			func(f: int, textured: bool): return BlockModels.material_for(block_id, textured, {}, f), apx, [src], YAWS, PITCHES,
			Data.method_options(d.get("settings", d.name), "rendered").outline)
	_baking.erase(block_id)
	if _stale.has(block_id):
		_stale.erase(block_id)
		return
	_done[block_id] = done
