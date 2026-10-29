class_name ChunkRenderer
extends Node3D
## Streams chunk meshes around a focus point: requests meshes from the
## VoxelWorld worker pool nearest-first, applies finished ones, re-meshes chunks
## dirtied by edits, and frees chunks that fall out of range.

const CHUNK := 32

signal chunk_updated(c: Vector3i)
signal chunk_unloaded(c: Vector3i)

var world: VoxelWorld
## Horizontal render distance in chunks.
var render_distance := 7:
	set(v):
		render_distance = v
		_build_offsets()
var focus := Vector3.ZERO
## Which chunk columns are drawn here (cx, cz, focus chunk column) -> bool:
## the far terrain (LodRenderer) sets it so the two meet exactly. Default:
## within the render distance.
var near_rule: Callable = _near_default
## Whether a column leaving the near area may be freed yet (cx, cz) -> bool:
## the far terrain says no until it draws the ground there.
var covered_rule: Callable = func(_x, _z): return true
var _leaving := {}  # Vector3i chunk -> true: out of range, waiting to be covered

var opaque_material: ShaderMaterial
var cutout_material: ShaderMaterial
var water_material: ShaderMaterial
var lava_material: ShaderMaterial
var honey_material: ShaderMaterial
var shimmer_material: ShaderMaterial

var _chunks := {}  # Vector3i -> MeshInstance3D, or null for empty chunks
var _pending := {}  # Vector3i -> true while a mesh job is in flight
var _redo := {}  # chunks edited while their mesh job was in flight
var _offsets: Array[Vector3i] = []
var _scan_index := 0
var _focus_chunk := Vector3i(1 << 20, 0, 0)
var _chunk_count := Vector3i.ZERO
var _max_in_flight := 12
## Time per frame for applying finished meshes (microseconds).
const APPLY_BUDGET_USEC := 4000
## Chunks freed a frame at most: crossing into a new chunk leaves a whole
## slab of them behind, and freeing them (their meshes and models) at once
## stalls that frame.
const FREES_PER_FRAME := 12


func setup(voxel_world: VoxelWorld) -> void:
	world = voxel_world
	_chunk_count = world.get_chunk_count()
	opaque_material = ShaderMaterial.new()
	opaque_material.shader = load("res://shaders/voxel.gdshader")
	opaque_material.set_shader_parameter("block_textures", Data.block_textures)
	opaque_material.set_shader_parameter("block_textures_2", Data.block_textures_2)
	opaque_material.set_shader_parameter("layer_texels", Data.layer_texels)
	cutout_material = ShaderMaterial.new()
	cutout_material.shader = load("res://shaders/voxel_cutout.gdshader")
	cutout_material.set_shader_parameter("block_textures", Data.block_textures)
	cutout_material.set_shader_parameter("block_textures_2", Data.block_textures_2)
	cutout_material.set_shader_parameter("layer_texels", Data.layer_texels)
	water_material = ShaderMaterial.new()
	water_material.shader = load("res://shaders/liquid_water.gdshader")
	water_material.set_shader_parameter("liquid_tex", Assets.texture("Images/Liquid_0"))
	water_material.set_shader_parameter("fall_tex", Assets.texture("Images/Waterfall_0"))
	lava_material = ShaderMaterial.new()
	lava_material.shader = load("res://shaders/liquid_lava.gdshader")
	lava_material.set_shader_parameter("liquid_tex", Assets.texture("Images/Liquid_1"))
	lava_material.set_shader_parameter("fall_tex", Assets.texture("Images/Waterfall_1"))
	honey_material = ShaderMaterial.new()
	honey_material.shader = load("res://shaders/liquid_honey.gdshader")
	honey_material.set_shader_parameter("liquid_tex", Assets.texture("Images/Liquid_11"))
	honey_material.set_shader_parameter("fall_tex", Assets.texture("Images/Waterfall_14"))
	shimmer_material = ShaderMaterial.new()
	shimmer_material.shader = load("res://shaders/liquid_shimmer.gdshader")
	shimmer_material.set_shader_parameter("sparkle_tex", Assets.texture("Images/Misc/water_14"))
	_build_offsets()


func set_sky(light: float, color: Color) -> void:
	for m in [opaque_material, cutout_material, water_material, honey_material]:
		m.set_shader_parameter("sky_light", light)
		m.set_shader_parameter("sky_color", color)


## Number of chunks with a finished mesh (for the loading screen).
func loaded_count() -> int:
	return _chunks.size()


## Chunks with a mesh job in flight.
func pending_count() -> int:
	return _pending.size()


func _near_default(cx: int, cz: int, f: Vector2i) -> bool:
	var dx := cx - f.x
	var dz := cz - f.y
	var r := render_distance + 1
	return dx * dx + dz * dz <= r * r + r


func _build_offsets() -> void:
	_offsets.clear()
	var r := render_distance + 2
	for x in range(-r, r + 1):
		for z in range(-r, r + 1):
			if x * x + z * z > r * r + r:
				continue
			for y in range(-6, 7):
				_offsets.append(Vector3i(x, y, z))
	# Nearest first; vertical distance matters less (players see far horizontally).
	_offsets.sort_custom(func(a, b): return a.x * a.x + a.z * a.z + a.y * a.y * 0.5 < b.x * b.x + b.z * b.z + b.y * b.y * 0.5)
	_scan_index = 0


func _process(_delta: float) -> void:
	if world == null or world.is_busy():
		return
	# Finished meshes, as many as fit in this frame's time (applying one also
	# builds its block models etc.), so loading never stalls a frame.
	var start := Time.get_ticks_usec()
	var applied := 0
	while applied < 24 and (applied == 0 or Time.get_ticks_usec() - start < APPLY_BUDGET_USEC):
		var got := world.poll_meshes(1)
		if got.is_empty():
			break
		var item: Array = got[0]
		var c: Vector3i = item[0]
		_pending.erase(c)
		if _in_range(c):
			_apply(c, item.slice(1))
			applied += 1
		if _redo.has(c):
			# The job may have read the world before the edit; mesh again.
			_redo.erase(c)
			_pending[c] = true
			world.request_mesh(c)

	for c in world.take_dirty_chunks():
		if _pending.has(c):
			_redo[c] = true
		elif _chunks.has(c):
			_pending[c] = true
			world.request_mesh(c)

	var fc := Vector3i(floori(focus.x / CHUNK), floori(focus.y / CHUNK), floori(focus.z / CHUNK))
	if fc != _focus_chunk:
		_focus_chunk = fc
		_scan_index = 0
		_unload_far()
	_free_covered()
	_request_near()


## Forces the next frame to re-scan and unload around the focus (after a range change).
func refocus() -> void:
	_focus_chunk = Vector3i(1 << 20, 0, 0)


func _valid(c: Vector3i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < _chunk_count.x and c.y < _chunk_count.y and c.z < _chunk_count.z


func _in_range(c: Vector3i) -> bool:
	return near_rule.call(c.x, c.z, Vector2i(_focus_chunk.x, _focus_chunk.z))


## Whether a chunk column is all drawn (every chunk of it in vertical range
## has its mesh), for the far terrain to let go of the tile over it.
func column_ready(cx: int, cz: int) -> bool:
	for y in range(-6, 7):
		var c := Vector3i(cx, _focus_chunk.y + y, cz)
		if _valid(c) and not _chunks.has(c):
			return false
	return true


func _request_near() -> void:
	while _pending.size() < _max_in_flight and _scan_index < _offsets.size():
		var c := _focus_chunk + _offsets[_scan_index]
		_scan_index += 1
		if _valid(c) and not _chunks.has(c) and not _pending.has(c) and _in_range(c):
			_pending[c] = true
			world.request_mesh(c)


func _unload_far() -> void:
	for c in _chunks.keys():
		if not _in_range(c):
			_leaving[c] = true


## Frees chunks that left the range once the far terrain draws their ground
## (at once without far terrain), FREES_PER_FRAME a frame; ones back in range
## stay.
func _free_covered() -> void:
	var freed := 0
	for c in _leaving.keys():
		if _in_range(c) or not _chunks.has(c):
			_leaving.erase(c)
		elif covered_rule.call(c.x, c.z):
			var mi = _chunks[c]
			if mi:
				# (Empty chunks cost nothing to drop.)
				if freed >= FREES_PER_FRAME:
					continue
				freed += 1
				mi.queue_free()
			_leaving.erase(c)
			_chunks.erase(c)
			chunk_unloaded.emit(c)


## `surfaces` = [opaque, cutout, water, lava, honey, shimmer] surface arrays (or null).
func _apply(c: Vector3i, surfaces: Array) -> void:
	var mi: MeshInstance3D = _chunks.get(c)
	chunk_updated.emit(c)
	if surfaces.all(func(s): return s == null):
		if mi:
			mi.queue_free()
		_chunks[c] = null
		return
	var mesh := ArrayMesh.new()
	var materials := [opaque_material, cutout_material, water_material, lava_material, honey_material, shimmer_material]
	for i in surfaces.size():
		if surfaces[i] != null:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[i])
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[i])
	if mi == null:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.position = Vector3(c * CHUNK)
		add_child(mi)
		_chunks[c] = mi
	mi.mesh = mesh
