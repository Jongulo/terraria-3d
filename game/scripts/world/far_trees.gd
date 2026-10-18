class_name FarTrees
extends Node3D
## Tree trunks out in the far terrain (level of detail). Up close a trunk is
## its blocks (BlockModels), but only the full-detail chunks have blocks drawn,
## so a tree farther off gets a trunk sprite: a strip of its trunk's art from
## the bottom of the trunk up to its canopy (leaning to a palm's canopy),
## facing you (far_trunk.gdshader). Canopies are drawn everywhere already
## (Decorations, as sprites that far out). Every tree's trunk is batched once
## (per trunk kind; again when trees change), and the shader hides the ones in
## the full-detail chunks and past the far view, so walking costs nothing.

var world: VoxelWorld
var game: Game
var _trunks := {}  # tree top -> [base y, trunk block id] (cached)
var _batches := {}  # trunk id -> MultiMeshInstance3D
var _focus := Vector2i(1 << 20, 0)
var _reach := -1.0
var _dirty := true
var _sky_light := 1.0
var _sky_color := Color.WHITE
static var _mesh: ArrayMesh


func setup(voxel_world: VoxelWorld, g: Game) -> void:
	world = voxel_world
	game = g


## Trees were cut or grown (Decorations.refresh): their trunks again (the
## rest are kept).
func invalidate() -> void:
	for top in _trunks.keys():
		if not game.decorations.canopies.has(top):
			_trunks.erase(top)
	_trunks.erase(Vector3i.ZERO)
	_dirty = true


func set_sky(light: float, color: Color) -> void:
	_sky_light = light
	_sky_color = color
	for mi in _batches.values():
		mi.material_override.set_shader_parameter("sky_light", light)
		mi.material_override.set_shader_parameter("sky_color", color)


## A quad from x -0.5..0.5, y 0..1 (the shader stretches and turns it).
static func _unit_strip() -> ArrayMesh:
	if _mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var corners := [Vector2(-0.5, 0), Vector2(0.5, 0), Vector2(0.5, 1), Vector2(-0.5, 1)]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_uv(Vector2(corners[i].x + 0.5, 1.0 - corners[i].y))
			st.add_vertex(Vector3(corners[i].x, corners[i].y, 0))
		_mesh = st.commit()
		_mesh.custom_aabb = AABB(Vector3(-64, -64, -64), Vector3(128, 128, 128))
	return _mesh


## The trunk under a tree top: [base y, trunk id], or [] if there's none.
func _trunk(top: Vector3i) -> Array:
	if _trunks.has(top):
		return _trunks[top]
	var id := world.get_block(top + Vector3i.DOWN)
	var out := []
	if Data.block(id).get("trunk", false):
		var y := top.y - 1
		while y > 0 and world.get_block(Vector3i(top.x, y - 1, top.z)) == id:
			y -= 1
		out = [y, id]
	_trunks[top] = out
	return out


func _process(_delta: float) -> void:
	if game == null or game.state != Game.State.PLAYING:
		return
	if _dirty:
		_dirty = false
		rebuild()
	var f: Vector3i = game.renderer._focus_chunk
	var fc := Vector2i(f.x, f.z)
	var reach: float = game.lod.far_distance * 32.0 if game.lod.enabled() else 0.0
	if fc != _focus or reach != _reach:
		_focus = fc
		_reach = reach
		for mi in _batches.values():
			var m: ShaderMaterial = mi.material_override
			m.set_shader_parameter("focus_chunk", Vector2(fc))
			m.set_shader_parameter("near_radius", float(game.renderer.render_distance))
			m.set_shader_parameter("reach", reach)


## Trunk sprites for every tree (the shader shows the far ones).
func rebuild() -> void:
	var groups := {}  # trunk id -> [[base, top], ...]
	for top in game.decorations.canopies:
		var t := _trunk(top)
		if t.is_empty():
			continue
		var style: int = game.decorations.canopies[top]
		var crown := game.decorations.canopy_position(top, style) + Vector3(0, 0.6, 0)
		if not groups.has(t[1]):
			groups[t[1]] = []
		groups[t[1]].append([Vector3(top.x + 0.5, t[0], top.z + 0.5), crown])
	for id in _batches.keys():
		if not groups.has(id):
			_batches[id].queue_free()
			_batches.erase(id)
	for id in groups:
		var mi := _batch(id)
		var list: Array = groups[id]
		var d := Data.block(id)
		var width: float = d.sprite.get_width() * float(d.sprite_px)
		var mm := mi.multimesh
		mm.instance_count = list.size()
		for i in list.size():
			var base: Vector3 = list[i][0]
			var axis: Vector3 = list[i][1] - base
			mm.set_instance_transform(i, Transform3D(Basis(Vector3(width, 0, 0), axis, Vector3(0, 0, 1)), base))
			mm.set_instance_color(i, world.get_light(base + axis * 0.5))


func _batch(id: int) -> MultiMeshInstance3D:
	if not _batches.has(id):
		var d := Data.block(id)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _unit_strip()
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/far_trunk.gdshader")
		m.set_shader_parameter("sprite", ImageTexture.create_from_image(d.sprite))
		m.set_shader_parameter("tile", d.sprite.get_height() * float(d.sprite_px))
		m.set_shader_parameter("sky_light", _sky_light)
		m.set_shader_parameter("sky_color", _sky_color)
		m.set_shader_parameter("focus_chunk", Vector2(_focus))
		m.set_shader_parameter("near_radius", float(game.renderer.render_distance))
		m.set_shader_parameter("reach", maxf(_reach, 0.0))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_batches[id] = mi
	return _batches[id]


## How many far trunks are drawn (tests): the batched ones outside the
## full-detail chunks, within the far view (the shader's test).
func count() -> int:
	var n := 0
	if _reach <= 0.0:
		return 0
	var eye := Vector2((_focus.x + 0.5) * 32.0, (_focus.y + 0.5) * 32.0)
	for top in game.decorations.canopies:
		if _trunk(top).is_empty() or Vector2(top.x, top.z).distance_to(eye) > _reach:
			continue
		if not game.lod.splits(1, (top.x >> 5) >> 1, (top.z >> 5) >> 1, _focus):
			n += 1
	return n
