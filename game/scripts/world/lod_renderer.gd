class_name LodRenderer
extends Node3D
## Far terrain (level of detail). Past the full-detail chunks (ChunkRenderer)
## the world is drawn in rings of coarser tiles (VoxelWorld.request_lod_mesh,
## rust/voxel_core/src/lod.rs): level k tiles are 2^k chunks across with cells
## of 2^k blocks, each ring twice as far out as the one inside it, out to the
## far view distance. The tiles are a quadtree: a tile is split into its four
## children while its middle is within the next finer level's radius (the
## full-detail chunks being level 0), so the levels meet without overlapping or
## leaving holes. A tile that's no longer wanted stays until what replaces it
## is drawn (its children, its parent, or the full-detail chunks), so nothing
## blinks out as you move. Far terrain is drawn in block colours with canopy
## blobs over the trees (lod.gdshader), lit like the near blocks; its water
## with the near water's material, see-through over the far sea floor.

const CHUNK := 32
## Coarsest level: tiles of 8 chunks (256 blocks), 8-block cells.
const MAX_LEVEL := 3
const MAX_IN_FLIGHT := 6

var world: VoxelWorld
var renderer: ChunkRenderer
## How far the far terrain reaches (chunks); 0: off.
var far_distance := 32:
	set(v):
		far_distance = v
		refocus()
var material := ShaderMaterial.new()

var _tiles := {}  # Vector3i(x, level, z) -> MeshInstance3D (or null: empty)
var _pending := {}
var _wanted := {}  # Vector3i -> true
var _queue: Array[Vector3i] = []
var _focus := Vector2i(1 << 20, 0)
var _chunk_count := Vector3i.ZERO


func setup(voxel_world: VoxelWorld, chunk_renderer: ChunkRenderer) -> void:
	world = voxel_world
	renderer = chunk_renderer
	_chunk_count = world.get_chunk_count()
	material.shader = preload("res://shaders/lod.gdshader")
	renderer.near_rule = is_near
	renderer.covered_rule = covers_column


func set_sky(light: float, color: Color) -> void:
	material.set_shader_parameter("sky_light", light)
	material.set_shader_parameter("sky_color", color)


func enabled() -> bool:
	return far_distance > 0


## Radius (chunks) of level k's ring: the full-detail chunks (level 0) are
## the render distance, each level twice the one inside.
func radius(level: int) -> float:
	return float(renderer.render_distance) * pow(2.0, level)


## Distance (chunks, across) from the focus chunk's middle to a tile's middle.
func tile_distance(level: int, tx: int, tz: int, focus := _focus) -> float:
	var size := float(1 << level)
	return Vector2((tx + 0.5) * size - (focus.x + 0.5), (tz + 0.5) * size - (focus.y + 0.5)).length()


## Whether a tile is split into finer ones.
func splits(level: int, tx: int, tz: int, focus := _focus) -> bool:
	return level > 0 and tile_distance(level, tx, tz, focus) < radius(level - 1)


## Whether a chunk column is drawn at full detail: its level-1 tile splits.
## (Without far terrain: within the render distance.)
func is_near(cx: int, cz: int, focus: Vector2i) -> bool:
	if not enabled():
		var dx := cx - focus.x
		var dz := cz - focus.y
		var r := renderer.render_distance + 1
		return dx * dx + dz * dz <= r * r + r
	return splits(1, cx >> 1, cz >> 1, focus)


func refocus() -> void:
	_focus = Vector2i(1 << 20, 0)


func _process(_delta: float) -> void:
	if world == null or world.is_busy():
		return
	var f := renderer._focus_chunk
	var fc := Vector2i(f.x, f.z)
	if fc != _focus:
		_focus = fc
		_select()
	# Finished tiles, as many as fit in a couple of milliseconds a frame.
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < 2500:
		var got := world.poll_lod_meshes(1)
		if got.is_empty():
			break
		var t: Vector3i = got[0][0]
		_pending.erase(t)
		if _wanted.has(t):
			_apply(t, got[0][1], got[0][2])
	while _pending.size() < MAX_IN_FLIGHT and not _queue.is_empty():
		var t: Vector3i = _queue.pop_front()
		if _wanted.has(t) and not _tiles.has(t) and not _pending.has(t):
			_pending[t] = true
			world.request_lod_mesh(t)
	_retire()


## The wanted tiles for the focus: the quadtree from the coarsest level down.
func _select() -> void:
	_wanted = {}
	if not enabled():
		_retire()
		return
	var top := 1 << MAX_LEVEL
	for tx in range(0, (_chunk_count.x + top - 1) / top):
		for tz in range(0, (_chunk_count.z + top - 1) / top):
			_want(MAX_LEVEL, tx, tz)
	_queue.clear()
	for t in _wanted:
		if not _tiles.has(t):
			_queue.append(t)
	# Nearest first.
	_queue.sort_custom(func(a, b): return tile_distance(a.y, a.x, a.z) < tile_distance(b.y, b.x, b.z))


func _want(level: int, tx: int, tz: int) -> void:
	var size := 1 << level
	if tile_distance(level, tx, tz) - size * 0.71 > far_distance:
		return
	if splits(level, tx, tz):
		if level > 1:
			for dz in 2:
				for dx in 2:
					_want(level - 1, tx * 2 + dx, tz * 2 + dz)
		return  # level 1 splits into full-detail chunks
	_wanted[Vector3i(tx, level, tz)] = true


## A finished tile: its terrain (lod.gdshader) and its water's surface, drawn
## with the near water's material so the far sea looks like the near one.
func _apply(t: Vector3i, arrays, water) -> void:
	if arrays == null and water == null:
		_tiles[t] = null
		return
	var mesh := ArrayMesh.new()
	for a in [[arrays, material], [water, renderer.water_material]]:
		if a[0] != null:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a[0])
			mesh.surface_set_material(mesh.get_surface_count() - 1, a[1])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(t.x * (CHUNK << t.y), 0, t.z * (CHUNK << t.y))
	add_child(mi)
	_tiles[t] = mi


## Frees tiles no longer wanted once their ground is drawn by something else.
func _retire() -> void:
	for t in _tiles.keys():
		if _wanted.has(t):
			continue
		if not enabled() or _region_covered(t):
			if _tiles[t]:
				_tiles[t].queue_free()
			_tiles.erase(t)


## Chunk-column bounds [x0, z0, x1, z1) of a tile.
static func _bounds(t: Vector3i) -> Rect2i:
	var size := 1 << t.y
	return Rect2i(t.x * size, t.z * size, size, size)


## Whether everything wanted over a tile's ground is drawn.
func _region_covered(t: Vector3i) -> bool:
	var r := _bounds(t)
	for w in _wanted:
		if _bounds(w).intersects(r) and not _tiles.has(w):
			return false
	for cx in range(r.position.x, r.end.x):
		for cz in range(r.position.y, r.end.y):
			if is_near(cx, cz, _focus) and not renderer.column_ready(cx, cz):
				return false
	return true


## Whether a chunk column the full-detail chunks are letting go of is drawn
## by far terrain (so they can let go). Without far terrain: always.
func covers_column(cx: int, cz: int) -> bool:
	if not enabled():
		return true
	for w in _wanted:
		if _bounds(w).has_point(Vector2i(cx, cz)):
			return _tiles.has(w)
	return true  # outside the far view: nothing to wait for


## How many far-terrain tiles are drawn, and wanted (tests).
func tile_count() -> int:
	return _tiles.size()


func wanted_count() -> int:
	return _wanted.size()
