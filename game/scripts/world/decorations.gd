class_name Decorations
extends Node3D
## Tree canopies: CanopyArt's upscaled, warped Tree_Tops art, one MultiMesh per
## style, drawn with the method chosen for "tree_canopy" in the placeable picker
## (cross by default; billboards turn to the camera in the shader). Each is lit
## by the world's light where it stands (sunlit on the surface; a gem tree's in
## a cave as dark as the cave, or lit by your torch), updated when its chunk
## is rebuilt (relight).

## How far billboard canopies sit in front of the trunk, in blocks.
const CANOPY_FRONT := 0.08
## Level of detail: canopies within this many blocks of you are drawn with
## their chosen method; farther ones as a single camera-facing sprite (a
## voxel canopy's detail is lost at that distance anyway), and past
## `far_reach` not at all. The sprite batch holds every canopy, the shader
## hiding the near ones (lod_near) and the ones past the far reach, so moving
## only re-sorts the few near you (found by a grid), every PARTITION_STEP
## blocks.
const DETAIL_DISTANCE := 64.0
const PARTITION_STEP := 16.0

var world: VoxelWorld
## Where you are (the level of detail is measured from here), and how far
## canopies are drawn. Unset (INF): every canopy in full detail.
var focus := Vector3(INF, INF, INF)
var far_reach := INF
var _materials: Array[ShaderMaterial] = []
var _instances := {}  # style -> MultiMeshInstance3D (full detail)
var _far_instances := {}  # style -> MultiMeshInstance3D (sprites)
## Every canopy, by style: {pos (drawn at), turn, light_at, light, near (its
## index in the full-detail batch, or -1)}; its index here is its sprite's.
var _all := {}
var _grid := {}  # Vector2i (32-block cell) -> Array of [style, canopy]
var _by_chunk := {}  # Vector3i chunk (of its light point) -> Array of [style, canopy]
var _near := []  # [style, canopy] in the full-detail batches
var _parted_at := Vector3(INF, INF, INF)
## Every canopy: position -> style (tree branches match their tree's top).
var canopies := {}


func setup(voxel_world: VoxelWorld) -> void:
	world = voxel_world
	refresh()


## The MultiMesh for a canopy style, made the first time a tree has it (a
## world only uses a few of CanopyArt's styles). `far`: the sprite version.
func _instance(style: int, far := false) -> MultiMeshInstance3D:
	var store := _far_instances if far else _instances
	if not store.has(style):
		var id := Data.block_id(CanopyArt.block_name(style))
		var d := Data.block(id)
		var method: String = "billboard" if far else d.get("method", "cross")
		var built := BlockModelMesh.build(id, method)
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/block_model_batched.gdshader")
		mat.set_shader_parameter("sprite", ImageTexture.create_from_image(d.sprite))
		mat.set_shader_parameter("textured", built.textured)
		mat.set_shader_parameter("billboard", method == "billboard")
		# In front of the billboard trunk, whose top it overlaps (no z-fighting).
		mat.set_shader_parameter("billboard_offset", CANOPY_FRONT)
		_materials.append(mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true  # each canopy's light
		mm.mesh = built.mesh
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		store[style] = mi
		if _sky_light >= 0.0:
			mat.set_shader_parameter("sky_light", _sky_light)
			mat.set_shader_parameter("sky_color", _sky_color)
	return store[style]


var _sky_light := -1.0
var _sky_color := Color.WHITE


func set_sky(light: float, color: Color) -> void:
	_sky_light = light
	_sky_color = color
	for m in _materials:
		m.set_shader_parameter("sky_light", light)
		m.set_shader_parameter("sky_color", color)


## Where you are and how far canopies are drawn (the game, every frame).
func set_focus(at: Vector3, reach: float) -> void:
	focus = at
	if not _sprites_built:
		far_reach = reach
		_build_sprites()
		_partition()
	if reach != far_reach:
		far_reach = reach
		for mi in _far_instances.values():
			mi.material_override.set_shader_parameter("lod_far", far_reach)
	if Vector2(at.x - _parted_at.x, at.z - _parted_at.z).length() > PARTITION_STEP:
		_partition()


## Where a canopy decoration at `pos` is drawn (before the canopy's own
## transform): overlapping the trunk's top block; a palm's on the end of its
## curve, its bottom at the top segment's (Terraria's palm tops).
func canopy_position(pos: Vector3i, style: int) -> Vector3:
	if style / 10 == PalmArt.CANOPY_SHEET:
		var s := PalmArt.at(world, pos + Vector3i.DOWN)
		if not s.is_empty():
			return Vector3(pos) + Vector3(0.5, -1.0, 0.5) + PalmArt.top_offset(s)
	return Vector3(pos) + Vector3(0.5, -0.6, 0.5)


## Rebuilds the canopy list from the world's decorations (after trees are cut).
func refresh() -> void:
	_all = {}
	_grid = {}
	_by_chunk = {}
	_near = []
	canopies.clear()
	for d in world.get_decorations():
		if d.kind == "tree_top":
			var style := int(d.style)
			var pos := Vector3i(d.pos)
			canopies[pos] = style
			if not style in CanopyArt.STYLE_IDS:
				style = style % 3
			if not _all.has(style):
				_all[style] = []
			var at := canopy_position(pos, style)
			# Each tree's canopy turned its own way (the same every time).
			var turn := Basis(Vector3.UP, float(absi(hash(pos)) % 6283) / 1000.0)
			var e := {"pos": at, "turn": turn, "light_at": at + LIGHT_AT, "light": canopy_light(at + LIGHT_AT), "near": -1,
					"far": _all[style].size()}
			_all[style].append(e)
			var cell := Vector2i(floori(at.x / 32.0), floori(at.z / 32.0))
			if not _grid.has(cell):
				_grid[cell] = []
			_grid[cell].append([style, e])
			var lc := Vector3i((e.light_at / 32.0).floor())
			if not _by_chunk.has(lc):
				_by_chunk[lc] = []
			_by_chunk[lc].append([style, e])
	_sprites_built = false
	if focus.x != INF:
		_build_sprites()
	_partition()


var _sprites_built := false


## Every canopy's sprite (for the far view; the shader shows the right ones).
func _build_sprites() -> void:
	_sprites_built = true
	for style in _all.keys() + _far_instances.keys():
		var list: Array = _all.get(style, [])
		var mm: MultiMesh = _instance(style, true).multimesh
		var t := _transform(style)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, Transform3D(list[i].turn * t.basis, list[i].pos + t.origin))
			mm.set_instance_custom_data(i, list[i].light)
		var m: ShaderMaterial = _far_instances[style].material_override
		m.set_shader_parameter("lod_far", far_reach)


## The canopy's transform (placeable picker): offset in world axes, its
## rotation and scale under each tree's turn.
func _transform(style: int) -> Transform3D:
	return Data.block_transform(Data.block(Data.block_id(CanopyArt.block_name(style))))


## The canopies near you, in full detail (every one without a focus); the
## sprite batches hide those.
func _partition() -> void:
	_parted_at = focus
	for pair in _near:
		pair[1].near = -1
	_near = []
	if focus.x == INF:
		for style in _all:
			for e in _all[style]:
				_near.append([style, e])
	else:
		var r := int(ceil(DETAIL_DISTANCE / 32.0))
		var fc := Vector2i(floori(focus.x / 32.0), floori(focus.z / 32.0))
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				for pair in _grid.get(fc + Vector2i(dx, dz), []):
					var e: Dictionary = pair[1]
					if Vector2(e.pos.x - focus.x, e.pos.z - focus.z).length() <= DETAIL_DISTANCE:
						_near.append(pair)
	var per_style := {}
	for style in _instances:
		per_style[style] = []
	for pair in _near:
		if not per_style.has(pair[0]):
			per_style[pair[0]] = []
		pair[1].near = per_style[pair[0]].size()
		per_style[pair[0]].append(pair[1])
	for style in per_style:
		var list: Array = per_style[style]
		var mm: MultiMesh = _instance(style).multimesh
		var t := _transform(style)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, Transform3D(list[i].turn * t.basis, list[i].pos + t.origin))
			mm.set_instance_custom_data(i, list[i].light)
	for mi in _far_instances.values():
		var m: ShaderMaterial = mi.material_override
		m.set_shader_parameter("lod_center", Vector2(focus.x, focus.z))
		m.set_shader_parameter("lod_near", DETAIL_DISTANCE if focus.x != INF else -1.0)
		m.set_shader_parameter("lod_far", far_reach)


## How many canopies are drawn in full detail and as sprites (tests): the
## sprites are those beyond the full-detail ones within the far reach.
func tier_counts() -> Vector2i:
	var near := _near.size()
	var far := 0
	if focus.x != INF:
		for style in _all:
			for e in _all[style]:
				var d := Vector2(e.pos.x - focus.x, e.pos.z - focus.z).length()
				if d > DETAIL_DISTANCE and d <= far_reach:
					far += 1
	return Vector2i(near, far)


## Where a canopy's light is taken, from its bottom: inside the leaves.
const LIGHT_AT := Vector3(0, 1.5, 0)


## The light on a canopy round `p`: the brightest of a few points in and round
## its leaves that are open (a point inside a block reads as dark, and a
## canopy pressed against the ground or a wall shouldn't go black).
const LIGHT_PROBES := [Vector3.ZERO, Vector3(0, 1.5, 0), Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5), Vector3(0, 0, -1.5), Vector3(0, -1.0, 0)]


func canopy_light(p: Vector3) -> Color:
	var best := Color(0, 0, 0, 0)
	for o in LIGHT_PROBES:
		var q: Vector3 = p + o
		if world.is_solid(Vector3i(q.floor())):
			continue
		var l := world.get_light(q)
		if l.r + l.g + l.b + l.a > best.r + best.g + best.b + best.a:
			best = l
	return best


## Re-reads the light of the canopies in chunk `c` (its blocks or light changed).
func relight(c: Vector3i) -> void:
	for pair in _by_chunk.get(c, []):
		var style: int = pair[0]
		var e: Dictionary = pair[1]
		e.light = canopy_light(e.light_at)
		if _far_instances.has(style) and e.far < _far_instances[style].multimesh.instance_count:
			_far_instances[style].multimesh.set_instance_custom_data(e.far, e.light)
		if e.near >= 0 and _instances.has(style) and e.near < _instances[style].multimesh.instance_count:
			_instances[style].multimesh.set_instance_custom_data(e.near, e.light)
