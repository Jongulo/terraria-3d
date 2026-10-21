class_name RenderedPlaceable
extends Node3D
## One placeable drawn with its rendered shots (the placeable picker; the world
## batches them in BlockModels): the block's billboard until PlaceableRenders
## has made them (or where nothing renders: headless), then a one-instance
## batch with rendered_batched.gdshader, turned `rotation_index` quarter turns.

var block_id := 0
var rotation_index := 0
var frame := 0
var _shots: MultiMeshInstance3D
var _sprite: Node3D


func setup(id: int, rotation_idx := 0, f := 0) -> void:
	block_id = id
	rotation_index = rotation_idx
	frame = f
	_sprite = BlockModels.make_model(block_id, "billboard", 0, {}, frame)
	add_child(_sprite)
	_poll()


## Whether it shows the shots (not the stand-in billboard).
func showing_shots() -> bool:
	return _shots != null


func set_frame(f: int) -> void:
	frame = f
	if _shots != null:
		_shots.material_override = BlockModels.rendered_material(block_id, frame)
	elif _sprite != null:
		BlockModels.set_model_frame(_sprite, block_id, "billboard", frame)


func _process(_delta: float) -> void:
	if _shots == null:
		_poll()


func _poll() -> void:
	if PlaceableRenders.renders(block_id).is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BlockModels.rendered_quad()
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, rotation_index * PI * 0.5), Vector3.ZERO))
	mm.set_instance_custom_data(0, Color(1, 1, 1, 1))  # full light
	_shots = MultiMeshInstance3D.new()
	_shots.multimesh = mm
	_shots.material_override = BlockModels.rendered_material(block_id, frame)
	_shots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_shots.extra_cull_margin = 4.0
	add_child(_shots)
	_sprite.queue_free()
	_sprite = null
