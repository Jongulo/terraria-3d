class_name BlockModels
extends Node3D
## Draws placeable blocks whose method is a block model (billboard, flat,
## extruded, hull, lathe). Follows the chunk renderer: when a chunk's mesh is
## (re)applied its model blocks are rebuilt; when it unloads they are freed.
## Directional models face the way they were placed (Game.block_rotations).
## Everything is batched: one MultiMesh per chunk and mesh (block type, method
## and, for wall models, which wall), each block's light in its instance's
## custom data. Billboards batch per sprite variant too (each block picks a
## variant from its position) and turn to the camera in the shader, like the
## tree canopies. (One node per block, each with its own light as a shader
## instance uniform, ran out of Godot's instance uniform buffer in big worlds,
## and models rebuilt after that drew black; the batches use a shader with no
## instance uniform at all, block_model_batched.gdshader.) Doors stay nodes:
## they swing. Animated blocks (Terraria's animated tiles: furnaces,
## campfires...) have a mesh and material per frame; their batches are listed
## in _animated and swapped to the frame Data.anim_frame_now gives. Rendered
## placeables (PlaceableRenders' shots) batch per block: a camera-facing quad
## each that shows the shot for the view (rendered_batched.gdshader); until a
## block's shots are made it's drawn as its billboard, then its chunks are
## built again. Platforms that touch are drawn as one floor: each cell's mesh
## has no faces toward the platforms beside it (BlockModelMesh.platform),
## batched per block type and which sides link.

var world: VoxelWorld
var game: Game
var _by_chunk := {}  # Vector3i -> Array[Node3D]
## Each chunk's batches of model blocks: Vector3i -> Array of [MultiMesh,
## cells, instance buffer], instance i drawing cells[i] (model_at reads them
## back; the buffer is kept, as a headless renderer keeps none).
var _records := {}
## Chunks whose models are built (with or without any), and chunks the
## renderer has newly meshed whose models are still to build: nearest first,
## BUILD_BUDGET_USEC a frame (at least one chunk), so streaming in the world
## doesn't stall a frame. A chunk already built (an edit) is built again at
## once.
var _built := {}
var _build_queue := {}
const BUILD_BUDGET_USEC := 2500
## A sliced build waits for this (emitted each frame by _build_queued).
signal _slice
var _slice_start := 0
var _slicing := 0  # sliced builds under way
var _gen := {}  # chunk -> its latest build (an older one under way is dropped)
## Heavy models (HEAVY_METHODS), tree branch cards and cactus sprites a
## streamed-in chunk needs that aren't made yet are made on worker threads,
## ASYNC_BUILDS at a time (one can take tens of milliseconds): till then a
## model block is drawn as its crossed sprite (a branch or cactus not at all),
## and its chunk is built again once it's made. Models are keyed
## Vector4i(block id, rotation, frame, method hash), art by a String.
const ASYNC_BUILDS := 2
var _model_ready := {}  # key -> true once made
var _model_wanted := {}  # key -> Callable making it, waiting for a worker
var _model_tasks := {}  # WorkerThreadPool task id -> key
var _model_waiting := {}  # key -> {chunk: true} drawn without it
## Open doors in loaded chunks, for aiming at their panels (Doors.raycast):
## "x,y,z" -> bottom cell.
var open_doors := {}
var _doors_by_chunk := {}  # Vector3i -> Array of open_doors keys
var _sky_light := 1.0
var _sky_color := Color.WHITE
## Level of detail: in chunks more than DETAIL_CHUNKS from yours, placeables
## with a heavy 3D method (voxel models, extrusions) are drawn as their crossed
## sprite instead; they're rebuilt as you move (through the build queue).
const DETAIL_CHUNKS := 2
const HEAVY_METHODS := ["hull", "hull_top", "lathe", "claude", "tuned", "extruded", "flat"]
var _detail := {}  # Vector3i chunk with heavy models -> whether it was built in full detail
var _player_chunk := Vector3i(1 << 20, 0, 0)
## Animated batches per chunk: Vector3i -> Array of {node, id, method,
## rotation, textured, billboard (variant, or -1), frame, blocks}.
var _animated := {}
## Blocks drawn as billboards while their rendered shots are being made:
## block id -> {chunk: true} drawn so.
var _waiting_renders := {}


func setup(voxel_world: VoxelWorld, g: Game) -> void:
	world = voxel_world
	game = g
	# (Loaded here, not first on a worker: SpriteFx loads its settings lazily.)
	SpriteFx.options("tree_canopy")


## Changes in the sky's light smaller than this aren't passed on: every
## material told costs the renderer an update, and there are hundreds.
const SKY_STEP := 0.002


func set_sky(light: float, color: Color) -> void:
	if absf(light - _sky_light) < SKY_STEP and absf(color.r - _sky_color.r) < SKY_STEP \
			and absf(color.g - _sky_color.g) < SKY_STEP and absf(color.b - _sky_color.b) < SKY_STEP:
		return
	_sky_light = light
	_sky_color = color
	# Cacti and tree branches keep their own materials (CactusArt, TreeBranches).
	for m in _shared_materials.values() + Doors.materials() + CactusArt.materials() + TreeBranches.materials():
		m.set_shader_parameter("sky_light", light)
		m.set_shader_parameter("sky_color", color)


## Gives a material the sky's light, unless it has it (each change costs the
## renderer an update).
func _sky_to(m: ShaderMaterial) -> void:
	if m.get_shader_parameter("sky_light") != _sky_light or m.get_shader_parameter("sky_color") != _sky_color:
		m.set_shader_parameter("sky_light", _sky_light)
		m.set_shader_parameter("sky_color", _sky_color)


## How many blocks are drawn as models (batched instances and doors).
func count() -> int:
	var n := 0
	for a in _by_chunk.values():
		for node in a:
			n += node.multimesh.instance_count if node is MultiMeshInstance3D else 1
	return n


## How the model block at `pos` is drawn: {mesh, transform, light}, or {}
## (billboards: mesh and transform as batched; doors are nodes, not listed).
func model_at(pos: Vector3i) -> Dictionary:
	var c := Vector3i(floori(pos.x / 32.0), floori(pos.y / 32.0), floori(pos.z / 32.0))
	for r in _records.get(c, []):
		var i: int = r[1].find(pos)
		if i >= 0:
			var b: PackedFloat32Array = r[2]
			var o := i * 16
			var t := Transform3D(Basis(Vector3(b[o], b[o + 4], b[o + 8]), Vector3(b[o + 1], b[o + 5], b[o + 9]), Vector3(b[o + 2], b[o + 6], b[o + 10])),
					Vector3(b[o + 3], b[o + 7], b[o + 11]))
			return {"mesh": r[0].mesh, "transform": t, "light": Color(b[o + 12], b[o + 13], b[o + 14], b[o + 15])}
	return {}


func chunk_unloaded(c: Vector3i) -> void:
	_built.erase(c)
	_build_queue.erase(c)
	_gen[c] = _gen.get(c, 0) + 1  # (drops a build under way)
	_clear(c)


func _clear(c: Vector3i) -> void:
	_animated.erase(c)
	_detail.erase(c)
	for n in _by_chunk.get(c, []):
		n.queue_free()
	_by_chunk.erase(c)
	_records.erase(c)
	for k in _doors_by_chunk.get(c, []):
		open_doors.erase(k)
	_doors_by_chunk.erase(c)


## The renderer (re)meshed chunk `c`: its models are built again at once if
## they were built (an edit), else queued (a chunk streaming in; at once
## while the world is loading).
func chunk_meshed(c: Vector3i) -> void:
	if _built.has(c) or game == null or game.state != Game.State.PLAYING:
		chunk_updated(c)
	else:
		_build_queue[c] = true


## Builds chunk `c`'s models now; `streamed` (a chunk from the build queue):
## heavy models not made yet are drawn as crossed sprites meanwhile.
func chunk_updated(c: Vector3i, streamed := false) -> void:
	_build(c, streamed, false)


## Builds chunk `c`'s models (chunk_updated). `sliced` (the build queue's):
## spread over frames, waiting for the next _slice whenever this frame's
## BUILD_BUDGET_USEC is spent; its nodes stay hidden, and the models it
## replaces drawn, till it's done. Building the chunk again (or unloading it)
## meanwhile drops it.
func _build(c: Vector3i, streamed: bool, sliced: bool) -> void:
	var gen: int = _gen.get(c, 0) + 1
	_gen[c] = gen
	_build_queue.erase(c)
	_built[c] = true
	var data := world.get_model_blocks(c)
	if data.is_empty():
		_clear(c)
		return
	if sliced:
		_slicing += 1
	var nodes: Array = []
	var door_keys := []  # open doors' [key, bottom cell]
	var detailed := full_detail(c)
	var heavy := false
	# Each block type's model, looked up once a chunk: Vector4i(id, rotation,
	# frame, method hash) -> [model, batch key].
	var looked_up := {}
	var billboards := {}  # Vector2i(block id, variant) -> Array[Vector3i]
	var rendered := {}  # block id -> Array of [Vector3i, rotation]
	var batches := {}  # mesh key -> {id, mesh, textured, items: [[Transform3D, Vector3i]]}
	var records: Array = []
	var cacti := []
	var palms := []
	var trunks := []
	var kinds := {}  # block id -> what this loop needs of it (looked up once)
	for i in range(0, data.size(), 4):
		if sliced and i % 256 == 0 and _spent():
			await _slice
			if _gen.get(c, 0) != gen:
				_drop(nodes)
				return
		var pos := Vector3i(data[i], data[i + 1], data[i + 2])
		var id := int(data[i + 3])
		if not kinds.has(id):
			var bd := Data.block(id)
			kinds[id] = {"trunk": bd.get("trunk", false) and not bd.get("palm", false), "palm": bd.get("palm", false),
					"cactus": bd.get("cactus", false), "door": Doors.is_part(bd), "method": bd.get("method", "panels"),
					"wall": bd.get("wall", false), "variants": bd.get("variants", 1), "scatter": float(bd.get("scatter", 0.0)),
					"vary": bd.get("vary", false), "merge": merges(bd), "platform": bd.get("platform", false), "track": bd.get("track", false),
					"stair_drop": float(bd.get("stair_drop", 0.0)), "frame": Data.anim_frame_now(bd)}
		var k: Dictionary = kinds[id]
		if k.trunk:
			trunks.append(pos)  # and on with its own billboard below
		if k.palm:
			palms.append(pos)  # a curved trunk's segment (PalmArt)
			continue
		if k.cactus:
			# A cactus is drawn whole from its base cell (CactusArt).
			if not Data.block(world.get_block(pos + Vector3i.DOWN)).get("cactus", false):
				cacti.append(pos)
			continue
		if k.door:
			# Drawn from the bottom cell; the top half has no model of its own.
			if Doors.is_door(Data.block(id)):
				var state := game.block_rotation(pos)
				if streamed and not Doors.has_mesh(id, Doors.hinge(state)):
					var hinge := Doors.hinge(state)
					_want("door:%d:%d" % [id, hinge], func(): Doors.mesh(id, hinge), c)
					continue
				var door := Doors.make_node(id, state, Chests.key(pos))
				door.visible = false
				add_child(door)
				door.global_position = Vector3(pos) + Vector3(0.5, 0.0, 0.5)
				Doors.set_light(door, world.get_light(Vector3(pos) + Vector3(0.5, 1.0, 0.5)))
				Doors.animate(door)
				nodes.append(door)
				if Doors.is_open(Data.block(id)):
					door_keys.append([Chests.key(pos), pos])
			continue
		if k.track:
			# Minecart track: its shape from the track beside it (Tracks).
			# (A lone piece runs the way it was placed looking: Tracks.facing.)
			var sh := Tracks.shape(world, pos, Tracks.facing(game.block_rotation(pos)))
			var tkey := "%d:track:%d" % [id, sh]
			if not batches.has(tkey):
				batches[tkey] = {"id": id, "mesh": Tracks.mesh(sh), "textured": false, "items": [], "method": "track", "rotation": 0, "frame": 0,
						"material": batched_material(id, false)}
			batches[tkey].items.append([Transform3D(Basis(), Vector3(pos) + Vector3(0.5, 0.0, 0.5)), pos])
			continue
		var method: String = k.method
		if method == "rendered" and not k.wall:
			if not PlaceableRenders.renders(id).is_empty():
				if not rendered.has(id):
					rendered[id] = []
				var turns := game.block_rotation(pos) + (vary_turns(pos) if k.vary else 0)
				rendered[id].append([pos, turns, scatter_at(pos, k.scatter)])
				continue
			if not _waiting_renders.has(id):
				_waiting_renders[id] = {}
			_waiting_renders[id][c] = true
			method = "billboard"  # until its shots are made
		if method == "billboard" and not k.wall:
			var key := Vector2i(id, variant_at(pos, k.variants))
			if not billboards.has(key):
				billboards[key] = []
			billboards[key].append(pos)
			continue
		var rotation := game.block_rotation(pos)
		var frame: int = k.frame
		var shape := world.get_shape(pos) if k.platform else 0
		if k.merge and shape < Game.SHAPE_RAMP:
			# Platforms that touch are drawn as one floor (BlockModelMesh.platform).
			var links := platform_links(pos)
			if streamed and not BlockModelMesh.has_platform(id, links):
				_want("platform:%d:%d" % [id, links], func(): BlockModelMesh.platform(id, links), c)
				continue
			var pkey := "%d:platform:%d" % [id, links]
			if not batches.has(pkey):
				batches[pkey] = {"id": id, "mesh": BlockModelMesh.platform(id, links), "textured": false, "items": [],
						"method": "platform", "rotation": 0, "frame": 0, "material": platform_material(id)}
			batches[pkey].items.append([Transform3D(Basis(), Vector3(pos) + Vector3(0.5, 0.0, 0.5)), pos])
			continue
		var drop: float = k.stair_drop
		if shape >= Game.SHAPE_RAMP and shape < Game.SHAPE_CEILING:
			# A platform stair: its stair twin, turned to rise toward
			# WALL_NORMALS[shape - 2] (the art rises toward +x).
			id = Data.block_id(Data.block(id).name + "_stair")
			method = Data.block(id).get("method", "extruded")
			if method in ["billboard", "rendered"]:
				method = "extruded"
			rotation = (shape - Game.SHAPE_RAMP + 3) % 4
			drop = float(Data.block(id).get("stair_drop", 0.0))
		if method in HEAVY_METHODS:
			heavy = true
			if not detailed:
				method = "cross"  # far off: its crossed sprite
		var lkey := Vector4i(id, rotation, frame, method.hash())
		if method in HEAVY_METHODS and not _model_ready.has(lkey) and not looked_up.has(lkey):
			if streamed:
				var args := [id, method, rotation, frame]
				_want(lkey, func(): BlockModels.model_mesh(args[0], args[1], args[2], args[3]), c)
				method = "cross"
				lkey = Vector4i(id, rotation, frame, method.hash())
			else:
				_model_ready[lkey] = true
		if not looked_up.has(lkey):
			var m := model_mesh(id, method, rotation, frame)
			looked_up[lkey] = [m, "%d:%d" % [id, m.mesh.get_instance_id()]]
		var model: Dictionary = looked_up[lkey][0]
		var mkey: String = looked_up[lkey][1]
		if not batches.has(mkey):
			batches[mkey] = {"id": id, "mesh": model.mesh, "textured": model.textured, "items": [],
					"method": method, "rotation": rotation, "frame": frame}
		var t := Transform3D(Basis(Vector3.UP, int(model.turn) * PI * 0.5), Vector3(pos) + Vector3(0.5, 0.0, 0.5))
		if k.vary:
			t.basis = vary_at(pos) * t.basis
		if k.scatter > 0.0:
			var sc := scatter_at(pos, k.scatter)
			t = Transform3D(sc.basis * t.basis, t.origin + sc.origin)
		# A stair's beam hangs below its block to meet the next stair down.
		t.origin.y -= drop
		batches[mkey].items.append([t, pos])
	var animated := []
	for b in batches.values():
		if sliced and _spent():
			await _slice
			if _gen.get(c, 0) != gen:
				_drop(nodes)
				return
		var node := _mesh_batch(b.id, b.mesh, b.textured, b.items, records, b.frame, b.get("material"))
		node.visible = false
		add_child(node)
		nodes.append(node)
		if Data.anim_frames(Data.block(b.id)) > 1:
			animated.append({"node": node, "id": b.id, "method": b.method, "rotation": b.rotation,
					"textured": b.textured, "billboard": -1, "frame": b.frame, "blocks": b.items.map(func(it): return it[1])})
	for key in billboards:
		if sliced and _spent():
			await _slice
			if _gen.get(c, 0) != gen:
				_drop(nodes)
				return
		var frame := Data.anim_frame_now(Data.block(key.x))
		var node := _billboard_batch(key.x, key.y, billboards[key], records, frame)
		node.visible = false
		add_child(node)
		nodes.append(node)
		if Data.anim_frames(Data.block(key.x)) > 1:
			animated.append({"node": node, "id": key.x, "method": "billboard", "rotation": 0,
					"textured": true, "billboard": key.y, "frame": frame, "blocks": billboards[key]})
	for id in rendered:
		if sliced and _spent():
			await _slice
			if _gen.get(c, 0) != gen:
				_drop(nodes)
				return
		var frame := Data.anim_frame_now(Data.block(id))
		var node := _rendered_batch(id, rendered[id], records, frame)
		node.visible = false
		add_child(node)
		nodes.append(node)
		if Data.anim_frames(Data.block(id)) > 1:
			animated.append({"node": node, "id": id, "method": "rendered", "rotation": 0,
					"textured": false, "billboard": -1, "frame": frame, "blocks": rendered[id].map(func(it): return it[0])})
	if sliced and _spent():
		await _slice
		if _gen.get(c, 0) != gen:
			_drop(nodes)
			return
	for node in _branch_batches(trunks, c, streamed) + _palm_batches(palms, records) + _cactus_batches(cacti, records, c, streamed):
		node.visible = false
		add_child(node)
		nodes.append(node)
	# Done: these take the place of what was drawn.
	_clear(c)
	for n in nodes:
		n.visible = true
		if n is MultiMeshInstance3D:
			# A material made just now hasn't had the sky yet.
			_sky_to(n.material_override)
	for dk in door_keys:
		open_doors[dk[0]] = dk[1]
		if not _doors_by_chunk.has(c):
			_doors_by_chunk[c] = []
		_doors_by_chunk[c].append(dk[0])
	if not animated.is_empty():
		_animated[c] = animated
	_by_chunk[c] = nodes
	_records[c] = records
	if heavy:
		_detail[c] = detailed
	if sliced:
		_slicing -= 1


## Whether this frame's building time (BUILD_BUDGET_USEC) is spent.
func _spent() -> bool:
	return Time.get_ticks_usec() - _slice_start > BUILD_BUDGET_USEC


## Frees the nodes of a build that was dropped.
func _drop(nodes: Array) -> void:
	for n in nodes:
		n.queue_free()
	_slicing -= 1


## Whether a block is a platform drawn as part of one floor with the
## platforms it touches (BlockModelMesh.platform): Terraria's platforms (not
## tables and other furniture you can stand on), whose art spans one block.
## In every placeable method: the floor is what you see in the world (the
## placeable picker still shows the method's model).
static func merges(d: Dictionary) -> bool:
	return d.get("platform", false) and String(d.get("name", "")).ends_with("_platform") and d.has("art") \
			and is_equal_approx(d.art.get_width() * float(d.get("art_px", 0.0)), 1.0)


## Which sides of the flat platform at `pos` touch another flat platform (not
## a stair), as BlockModelMesh.PLATFORM_LINKS bits, then which diagonal cells
## are flat platforms (PLATFORM_DIAGONALS, bits 4-7).
func platform_links(pos: Vector3i) -> int:
	var links := 0
	var cells: Array = BlockModelMesh.PLATFORM_LINKS + BlockModelMesh.PLATFORM_DIAGONALS
	for i in cells.size():
		var q: Vector3i = pos + cells[i]
		if merges(Data.block(world.get_block(q))) and world.get_shape(q) < Game.SHAPE_RAMP:
			links |= 1 << i
	# A diagonal only counts next to a linked side (so fewer batches).
	for i in 4:
		var x_side := i / 2
		var z_side := 2 + i % 2
		if links & ((1 << x_side) | (1 << z_side)) == 0:
			links &= ~(1 << (4 + i))
	return links


## Whether chunk `c` is drawn in full detail (near your chunk), or without a
## player (the picker, tests without one) always.
func full_detail(c: Vector3i) -> bool:
	if game == null or game.player == null or _player_chunk.x == 1 << 20:
		return true
	var d := c - _player_chunk
	return maxi(absi(d.x), absi(d.z)) <= DETAIL_CHUNKS and absi(d.y) <= DETAIL_CHUNKS


## Queues chunks whose level of detail changed since you moved (their
## models stay as they are till they're built again).
func _update_detail() -> void:
	if game == null or game.player == null:
		return
	var p := game.player.global_position
	var pc := Vector3i(floori(p.x / 32.0), floori(p.y / 32.0), floori(p.z / 32.0))
	if pc != _player_chunk:
		_player_chunk = pc
		for c in _detail:
			if _detail[c] != full_detail(c):
				_build_queue[c] = true


## Builds queued chunks (chunk_meshed), nearest yours first, for
## BUILD_BUDGET_USEC a frame: builds under way go on first (_slice), then new
## ones start while there's time and none is waiting for the next frame.
func _build_queued() -> void:
	_slice_start = Time.get_ticks_usec()
	_slice.emit()
	while not _build_queue.is_empty() and _slicing == 0 and not _spent():
		var best := Vector3i.ZERO
		var best_d := 1 << 62
		for c in _build_queue:
			var d: Vector3i = c - _player_chunk
			var dist := d.x * d.x + d.y * d.y * 4 + d.z * d.z
			if dist < best_d:
				best_d = dist
				best = c
		_build(best, true, true)


## Chunk `c` drew without something not made yet (`key`): `make` makes it
## on a worker, and `c` is built again then.
func _want(key, make: Callable, c: Vector3i) -> void:
	if not _model_waiting.has(key):
		_model_waiting[key] = {}
	_model_waiting[key][c] = true
	if not _model_wanted.has(key) and not key in _model_tasks.values():
		_model_wanted[key] = make


## Finished worker models: their chunks queued to build again; and more
## started.
func _poll_models() -> void:
	for task in _model_tasks.keys():
		if not WorkerThreadPool.is_task_completed(task):
			continue
		WorkerThreadPool.wait_for_task_completion(task)
		var key = _model_tasks[task]
		_model_tasks.erase(task)
		_model_ready[key] = true
		for c in _model_waiting.get(key, {}):
			if _built.has(c):
				_build_queue[c] = true
		_model_waiting.erase(key)
	while _model_tasks.size() < ASYNC_BUILDS and not _model_wanted.is_empty():
		var key = _model_wanted.keys()[0]
		var make: Callable = _model_wanted[key]
		_model_wanted.erase(key)
		var task := WorkerThreadPool.add_task(make, false, "block model")
		_model_tasks[task] = key


## Waits for models still being made (a worker mustn't outlive the game).
func _exit_tree() -> void:
	for task in _model_tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	_model_tasks.clear()


## Whether models are still being made on workers (tests).
func models_pending() -> bool:
	return not _model_tasks.is_empty() or not _model_wanted.is_empty()


## Whether chunk `c`'s models are still to build (tests).
func queued(c: Vector3i) -> bool:
	return _build_queue.has(c)


## Moves animated batches on to the frame their block is on now.
func _process(_delta: float) -> void:
	_update_detail()
	_poll_models()
	_build_queued()
	_check_renders()
	for list in _animated.values():
		for a in list:
			var frame := Data.anim_frame_now(Data.block(a.id))
			if frame == a.frame:
				continue
			a.frame = frame
			var mi: MultiMeshInstance3D = a.node
			var m: ShaderMaterial
			if a.billboard >= 0:
				mi.multimesh.mesh = BlockModelMesh.build(a.id, "billboard", frame).mesh
				m = billboard_material(a.id, a.billboard, frame)
			elif a.method == "rendered":
				m = rendered_material(a.id, frame)
			else:
				mi.multimesh.mesh = model_mesh(a.id, a.method, a.rotation, frame).mesh
				m = batched_material(a.id, a.textured, frame)
			_sky_to(m)
			mi.material_override = m


## Once blocks waiting for their rendered shots have them, the chunks that
## drew them as billboards are queued to build again with the shots.
func _check_renders() -> void:
	if _waiting_renders.is_empty():
		return
	var ready := _waiting_renders.keys().filter(func(id): return not PlaceableRenders.renders(id).is_empty())
	if ready.is_empty():
		return
	for id in ready:
		for c in _waiting_renders[id]:
			if _built.has(c):
				_build_queue[c] = true
		_waiting_renders.erase(id)


## The frame an animated block is drawn on now (tests): -1 if it isn't drawn
## as an animated batch.
func anim_frame_at(pos: Vector3i) -> int:
	var c := Vector3i(floori(pos.x / 32.0), floori(pos.y / 32.0), floori(pos.z / 32.0))
	for a in _animated.get(c, []):
		if pos in a.blocks:
			return a.frame
	return -1


## A scattered plant's place in its cell ("scatter": how far it may sit off
## the middle, blocks): turned any way and moved off the middle, the same
## every time for its cell, so a field of them doesn't stand in a grid.
static func scatter_at(pos: Vector3i, scatter: float) -> Transform3D:
	if scatter <= 0.0:
		return Transform3D.IDENTITY
	var h := absi(hash(pos))
	var turn := float(h % 6283) / 1000.0
	var ox := (float((h / 6283) % 1000) / 999.0 * 2.0 - 1.0) * scatter
	var oz := (float(absi(hash(pos * 7 + Vector3i(3, 1, 5))) % 1000) / 999.0 * 2.0 - 1.0) * scatter
	return Transform3D(Basis(Vector3.UP, turn), Vector3(ox, 0.0, oz))


## Plants, rocks and debris on the ground ("vary"): turned a quarter, half
## or three quarters round or not at all, and mirrored or not, the same every
## time for their cell (a field of one plant doesn't look stamped out).
static func vary_at(pos: Vector3i) -> Basis:
	var b := Basis(Vector3.UP, vary_turns(pos) * PI * 0.5)
	return b * Basis.from_scale(Vector3(-1, 1, 1)) if vary_mirrored(pos) else b


## How many quarter turns `vary_at` gives the cell (0-3).
static func vary_turns(pos: Vector3i) -> int:
	return absi(hash(pos * 13 + Vector3i(7, 3, 11))) % 4


## Whether `vary_at` mirrors the cell.
static func vary_mirrored(pos: Vector3i) -> bool:
	return (absi(hash(pos * 13 + Vector3i(7, 3, 11))) / 4) % 2 == 1


## Variant for a block at `pos`: stable, and different between neighbours.
static func variant_at(pos: Vector3i, variants: int) -> int:
	if variants <= 1:
		return 0
	return absi(hash(pos)) % variants


## A batch's MultiMesh of `mesh` (3D transforms, each instance's light in
## its custom data).
static func _multimesh(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	return mm


## Sets a batch's instances in one go (VoxelWorld.instance_buffer): their
## transforms, each lit by the light at its point in `light_at`; `cells` (the
## block each instance draws) go in `records` for model_at, if given.
func _fill(mm: MultiMesh, transforms: Array[Transform3D], light_at: PackedVector3Array, cells: Array, records) -> void:
	mm.instance_count = transforms.size()
	var buffer := world.instance_buffer(transforms, light_at) if not transforms.is_empty() else PackedFloat32Array()
	if not transforms.is_empty():
		mm.buffer = buffer
	if records != null:
		records.append([mm, cells, buffer])


## One mesh drawn at `items` ([Transform3D, block position]), each instance
## lit by its block's light (custom data), recorded in `records`.
func _mesh_batch(block_id: int, mesh: ArrayMesh, textured: bool, items: Array, records: Array, frame := 0, material: ShaderMaterial = null) -> MultiMeshInstance3D:
	var mm := _multimesh(mesh)
	var ts: Array[Transform3D] = []
	var pts := PackedVector3Array()
	var cells := []
	for it in items:
		var pos: Vector3i = it[1]
		ts.append(it[0])
		pts.append(Vector3(pos) + Vector3(0.5, 0.5, 0.5))
		cells.append(pos)
	_fill(mm, ts, pts, cells, records)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = material if material != null else batched_material(block_id, textured, frame)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _billboard_batch(block_id: int, variant: int, positions: Array, records: Array, frame := 0) -> MultiMeshInstance3D:
	var mm := _multimesh(BlockModelMesh.build(block_id, "billboard", frame).mesh)
	var ts: Array[Transform3D] = []
	var pts := PackedVector3Array()
	# The block's transform, once (billboard_instance per block).
	var bt := Data.block_transform(Data.block(block_id))
	var bscale := Basis.from_scale(Vector3.ONE * bt.basis.get_scale().x)
	var scatter := float(Data.block(block_id).get("scatter", 0.0))
	var vary: bool = Data.block(block_id).get("vary", false)
	for pos in positions:
		# (A billboard turns to you; a mirrored one is drawn flipped, the shader
		# seeing its transform turned inside out.)
		var basis := bscale * Basis.from_scale(Vector3(-1, 1, 1)) if vary and vary_mirrored(pos) else bscale
		ts.append(Transform3D(basis, Vector3(pos) + Vector3(0.5, 0.0, 0.5) + bt.origin + scatter_at(pos, scatter).origin))
		pts.append(Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	_fill(mm, ts, pts, positions, records)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = billboard_material(block_id, variant, frame)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


## Rendered placeables of one block: `items` [block position, rotation,
## scatter_at], each a quad turned to the camera in the shader, the instance
## turned the way the block was placed and scattered (the shots turn with it).
func _rendered_batch(block_id: int, items: Array, records: Array, frame := 0) -> MultiMeshInstance3D:
	var mm := _multimesh(rendered_quad())
	var ts: Array[Transform3D] = []
	var pts := PackedVector3Array()
	var cells := []
	for it in items:
		var pos: Vector3i = it[0]
		var t := Transform3D(Basis(Vector3.UP, int(it[1]) * PI * 0.5), Vector3(pos) + Vector3(0.5, 0.0, 0.5))
		if it.size() > 2:
			var sc: Transform3D = it[2]
			t = Transform3D(sc.basis * t.basis, t.origin + sc.origin)
		ts.append(t)
		pts.append(Vector3(pos) + Vector3(0.5, 0.5, 0.5))
		cells.append(pos)
	_fill(mm, ts, pts, cells, records)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = rendered_material(block_id, frame)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# The quad is moved to the model's middle and grown in the shader.
	mi.extra_cull_margin = 4.0
	return mi


static var _rendered_quad: QuadMesh


## The unit quad rendered placeables are drawn on.
static func rendered_quad() -> QuadMesh:
	if _rendered_quad == null:
		_rendered_quad = QuadMesh.new()
		_rendered_quad.size = Vector2.ONE
	return _rendered_quad


## Shared material for a block's rendered shots (an animated block's frame).
## Made again when its shots are (PlaceableRenders.forget).
static func rendered_material(block_id: int, frame := 0) -> ShaderMaterial:
	var r := PlaceableRenders.renders(block_id)
	var key := "%d:rendered:%d" % [block_id, frame]
	var m: ShaderMaterial = _shared_materials.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = preload("res://shaders/rendered_batched.gdshader")
		_shared_materials[key] = m
	if not r.is_empty():
		_param(m, "yaws", r.yaws)
		_param(m, "rows", r.pitches.size())
		_param(m, "atlas", r.atlases[clampi(frame, 0, r.atlases.size() - 1)])
		_param(m, "center", r.center)
		_param(m, "size", r.n * r.px)
		_param(m, "radius", r.radius)
	return m


## Sets a shared material's parameter if it isn't that already: every change
## costs the renderer an update of the material (a texture's, of everything
## drawn with it), and these are asked for by every chunk built.
static func _param(m: ShaderMaterial, param: String, value) -> void:
	var now = m.get_shader_parameter(param)
	if now == null or typeof(now) != typeof(value) or now != value:
		m.set_shader_parameter(param, value)


## The branches on these trunk cells (TreeBranches): fixed cards, one batch
## per look. A trunk without its canopy (a stump) has none.
func _branch_batches(cells: Array, c := Vector3i.ZERO, streamed := false) -> Array:
	var trees := {}  # Vector2i column -> [[height, branches, sheet, base], ...] (a trunk can span chunks: each finds it)
	var groups := {}  # art -> [[Transform3D, ...], light points]
	var arts := {}
	var sheets := {}  # trunk block id -> its sheet
	for pos in cells:
		var tree: Array = []
		var column := Vector2i(pos.x, pos.z)
		for tr in trees.get(column, []):
			if pos.y >= tr[3].y and pos.y < tr[3].y + tr[0]:
				tree = tr
		if tree.is_empty():
			var col := TreeBranches.column(world, pos)
			var top: Vector3i = col[0] + Vector3i.UP * col[1]
			var canopy: int = game.decorations.canopies.get(top, -1) if game != null else -1
			tree = [col[1], TreeBranches.branches(col[0], col[1]) if canopy >= 0 else [], TreeBranches.sheet_for(maxi(canopy, 0)), col[0]]
			if not trees.has(column):
				trees[column] = []
			trees[column].append(tree)
		if tree[1].is_empty():
			continue
		var base: Vector3i = tree[3]
		var trunk_id := world.get_block(pos)
		if not sheets.has(trunk_id):
			sheets[trunk_id] = Data.block(trunk_id).get("tex", {}).get("all", {}).get("sheet", "Tiles_5")
		var trunk_sheet: String = sheets[trunk_id]
		for b in tree[1]:
			if b.cell != pos.y - base.y:
				continue
			if streamed and not TreeBranches.has_art(tree[2], trunk_sheet, b):
				var args := [tree[2], trunk_sheet, b]
				_want("branch:" + TreeBranches.art_key(tree[2], trunk_sheet, b), func(): TreeBranches.get_art(args[0], args[1], args[2]), c)
				continue
			var art := TreeBranches.get_art(tree[2], trunk_sheet, b)
			var k: int = art.material.get_instance_id()
			if not groups.has(k):
				var ts: Array[Transform3D] = []
				groups[k] = [ts, PackedVector3Array()]
				arts[k] = art
			var t := TreeBranches.transform(base, b)
			groups[k][0].append(t)
			groups[k][1].append(t.origin + b.dir * 0.75)
	var out := []
	for k in groups:
		var mm := _multimesh(arts[k].mesh)
		_fill(mm, groups[k][0], groups[k][1], [], null)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = arts[k].material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		out.append(mi)
	return out


## Palm trunk cells: each its segment's billboard (palm_trunk's variant),
## shifted along the palm's curve, one batch per segment frame.
func _palm_batches(cells: Array, records: Array) -> Array:
	var shapes := {}  # Vector2i column -> PalmArt shapes (a palm can span chunks: each finds it)
	var groups := {}  # [id, frame] -> [[cell, offset], ...]
	for pos in cells:
		var s: Dictionary = {}
		var column := Vector2i(pos.x, pos.z)
		for sh in shapes.get(column, []):
			if pos.y >= sh.base.y and pos.y < sh.base.y + sh.height:
				s = sh
		if s.is_empty():
			s = PalmArt.at(world, pos)
			if s.is_empty():
				continue
			if not shapes.has(column):
				shapes[column] = []
			shapes[column].append(s)
		var k: int = pos.y - s.base.y
		var key := Vector2i(world.get_block(pos), s.frames[k])
		if not groups.has(key):
			groups[key] = []
		groups[key].append([pos, PalmArt.segment_offset(s, k), PalmArt.segment_nudge(s, k)])
	var out := []
	for key in groups:
		var mm := _multimesh(BlockModelMesh.build(key.x, "billboard").mesh)
		var ts: Array[Transform3D] = []
		var pts := PackedVector3Array()
		var at := []
		for seg in groups[key]:
			var pos: Vector3i = seg[0]
			var t := billboard_instance(key.x, pos)
			t.origin += seg[1]
			# The billboard shader reads a longer z axis as a nudge toward the camera.
			t.basis.z = t.basis.z.normalized() * (t.basis.get_scale().y + seg[2])
			ts.append(t)
			pts.append(Vector3(pos) + Vector3(0.5, 0.5, 0.5))
			at.append(pos)
		_fill(mm, ts, pts, at, records)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = billboard_material(key.x, key.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		out.append(mi)
	return out


## Cacti standing on these base cells, one batch per shape.
func _cactus_batches(bases: Array, records: Array, chunk := Vector3i.ZERO, streamed := false) -> Array:
	var groups := {}  # shape code -> [art, [base, ...]]
	for base in bases:
		var col := CactusArt.column(world, base)
		var s := CactusArt.shape(base, col[1], CactusArt.color_for(Data.block(world.get_block(base + Vector3i.DOWN))))
		var c := CactusArt.code(s)
		if streamed and not CactusArt.has_art(s):
			_want("cactus:%d" % c, func(): CactusArt.get_art(s), chunk)
			continue
		if not groups.has(c):
			groups[c] = [CactusArt.get_art(s), []]
		groups[c][1].append(base)
	var out := []
	for c in groups:
		var art: Dictionary = groups[c][0]
		var list: Array = groups[c][1]
		var mm := _multimesh(art.mesh)
		var ts: Array[Transform3D] = []
		var pts := PackedVector3Array()
		for base in list:
			ts.append(Transform3D(Basis(), Vector3(base) + Vector3(0.5, 0.0, 0.5)))
			pts.append(Vector3(base) + Vector3(0.5, 1.5, 0.5))
		_fill(mm, ts, pts, list, records)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = art.material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		out.append(mi)
	return out


## A batched billboard's instance transform at block `pos`, with the block's
## offset and scale (it faces you, so rotation doesn't apply; the shader takes
## the scale from the instance).
static func billboard_instance(block_id: int, pos: Vector3i) -> Transform3D:
	var t := Data.block_transform(Data.block(block_id))
	return Transform3D(Basis.from_scale(Vector3.ONE * t.basis.get_scale().x), Vector3(pos) + Vector3(0.5, 0.0, 0.5) + t.origin)


## Shared material for batched billboards of one block variant (or an
## animated block's frame).
static func billboard_material(block_id: int, variant: int, frame := 0) -> ShaderMaterial:
	var key := "%d:billboard:%d:%d" % [block_id, variant, frame]
	if not _shared_materials.has(key):
		var d := Data.block(block_id)
		var sprites: Array = d.get("sprites", [d.sprite])
		if frame > 0:
			sprites = [d.anim_sprites[frame]]
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/block_model_batched.gdshader")
		m.set_shader_parameter("sprite", ImageTexture.create_from_image(sprites[variant % sprites.size()]))
		m.set_shader_parameter("art_scale", int(d.get("art_scale", 1)))
		m.set_shader_parameter("textured", true)
		m.set_shader_parameter("billboard", true)
		_shared_materials[key] = m
	return _shared_materials[key]


## Rebuilds everything (after a block's method changed).
func refresh_all() -> void:
	_model_ready.clear()
	for c in _by_chunk.keys():
		chunk_updated(c)


## A model node for a block (also used by the placeable picker). `rotation_index`
## turns it in quarter turns around the vertical axis. The block's transform
## (Data.block_transform) is baked into the mesh, so the node's own transform
## stays free; a billboard sprite takes its offset and scale on the node.
## `frame`: an animated block's frame (set_model_frame moves it on).
static func make_model(block_id: int, method: String, rotation_index := 0, materials := {}, frame := 0) -> Node3D:
	var d := Data.block(block_id)
	if d.get("wall", false):
		return _wall_model(block_id, method, rotation_index, materials, frame)
	if method == "rendered":
		var r := RenderedPlaceable.new()
		r.setup(block_id, rotation_index, frame)
		return r
	if method == "billboard":
		var s := EntitySprite.new()
		var img: Image = d.sprite
		s.setup(frame_texture(block_id, frame), 1, Vector2(img.get_width(), img.get_height()) * float(d.sprite_px))
		var t := Data.block_transform(d)
		s.position = t.origin
		s.scale = Vector3.ONE * t.basis.get_scale().x
		return s
	var model := model_mesh(block_id, method, rotation_index, frame)
	var mi := MeshInstance3D.new()
	mi.mesh = model.mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.material_override = material_for(block_id, model.textured, materials, frame)
	mi.rotation.y = int(model.turn) * PI * 0.5
	return mi


## Moves a node from make_model (same block, method and turn) on to another
## frame of its animation.
static func set_model_frame(node: Node3D, block_id: int, method: String, frame: int, rotation_index := 0, materials := {}) -> void:
	if node is EntitySprite:
		node.material_override.set_shader_parameter("sprite", frame_texture(block_id, frame))
		return
	if node is RenderedPlaceable:
		node.set_frame(frame)
		return
	var mi := node as MeshInstance3D
	var model := model_mesh(block_id, method, rotation_index, frame)
	mi.mesh = model.mesh
	mi.material_override = material_for(block_id, model.textured, materials, frame)


static var _frame_textures := {}


## A block's sprite (an animated block's frame) as a texture, shared.
static func frame_texture(block_id: int, frame := 0) -> ImageTexture:
	var d := Data.block(block_id)
	var img: Image = d.anim_sprites[frame] if frame > 0 else d.sprite
	# By image too: rebuilt sprites (SpriteFx settings) get new textures.
	var key := Vector3i(block_id, frame, img.get_instance_id())
	if not _frame_textures.has(key):
		_frame_textures[key] = ImageTexture.create_from_image(img)
	return _frame_textures[key]


## A block model's mesh (shared by every block of its kind and placement):
## {mesh, textured, turn: quarter turns to apply on the instance}. The block's
## transform is baked in; a wall model's lean out of its wall too (turn 0).
## Not for camera-facing billboards (BlockModels batches those itself).
static func model_mesh(block_id: int, method: String, rotation_index := 0, frame := 0) -> Dictionary:
	var d := Data.block(block_id)
	if d.get("wall", false):
		if d.get("side_view", false):
			# Side-view art in crossed or block-side planes would also lie flat
			# against the wall: one plane out from it instead.
			if method in ["billboard", "cross", "panels"]:
				method = "flat"
		elif method in ["billboard", "rendered"]:
			method = "cross"
		var wall_built := BlockModelMesh.build(block_id, method, frame)
		return {"mesh": _transformed_mesh(block_id, "%s:wall%d" % [method, rotation_index], wall_built.mesh,
				wall_transform(rotation_index, d) * Data.block_transform(d)), "textured": wall_built.textured, "turn": 0}
	if method == "rendered":
		method = PlaceableRenders.source(block_id)  # the model its shots are of
	var built := BlockModelMesh.build(block_id, method, frame)
	return {"mesh": _transformed_mesh(block_id, method, built.mesh, Data.block_transform(d)), "textured": built.textured,
			"turn": rotation_index}


## How far wall-hung models lean out of the wall, and where their base sits:
## against the wall (minus the stick's half thickness), a bit above the
## block's bottom - like Minecraft's wall torches.
const WALL_TILT := deg_to_rad(22.5)
const WALL_INSET := 0.07
const WALL_RAISE := 0.2
## Side-view wall models: how far the base sinks into the wall, and its height.
const SIDE_VIEW_INSET := 0.03
const SIDE_VIEW_RAISE := 0.0  # the art already sits mid-block, like Terraria's
static var _meshes := {}  # transformed meshes, by block, method, mesh and transform


## `mesh` moved by `t` (shared between blocks of a kind; `mesh` itself when
## `t` is the identity).
static func _transformed_mesh(block_id: int, tag: String, mesh: ArrayMesh, t: Transform3D) -> ArrayMesh:
	if t == Transform3D():
		return mesh
	var key := "%d:%s:%d:%s" % [block_id, tag, mesh.get_instance_id(), t]
	BlockModelMesh.lock.lock()
	var hit = _meshes.get(key)
	BlockModelMesh.lock.unlock()
	if hit != null:
		return hit
	var built := BlockModelMesh.transformed(mesh, t)
	BlockModelMesh.lock.lock()
	_meshes[key] = built
	BlockModelMesh.lock.unlock()
	return built


## A wall-hung block model (wall torch): its method's mesh (cross for
## billboards, which can't lean; flat for side-view art in planes), turned to
## face out of the wall along Player.WALL_NORMALS[rotation_index], tilted away
## from it with its base against the wall (model_mesh bakes that in).
static func _wall_model(block_id: int, method: String, rotation_index: int, materials: Dictionary, frame := 0) -> MeshInstance3D:
	var model := model_mesh(block_id, method, rotation_index, frame)
	var mi := MeshInstance3D.new()
	mi.mesh = model.mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.material_override = material_for(block_id, model.textured, materials, frame)
	return mi


## Per block: "wall_tilt" (degrees), "wall_inset", "wall_raise" (a banner hangs
## straight, flat against the wall). A "side_view" block (Terraria's wall
## torch frame, wall on the sprite's left) is turned so the sprite's +x points
## out of the wall, its left edge `wall_inset` into it; the art does the lean.
static func wall_transform(rotation_index: int, d := {}) -> Transform3D:
	var n := Vector3(Player.WALL_NORMALS[rotation_index % 4])
	if d.get("side_view", false):
		var half_width: float = d.sprite.get_width() * float(d.sprite_px) * 0.5
		var turn := Basis(Vector3.UP, atan2(-n.z, n.x))
		return Transform3D(turn, -n * (0.5 - half_width + float(d.get("wall_inset", SIDE_VIEW_INSET)))
				+ Vector3.UP * float(d.get("wall_raise", SIDE_VIEW_RAISE)))
	var yaw := Basis(Vector3.UP, rotation_index * PI * 0.5)
	# Turning about up x n tips the top toward n, away from the wall.
	var tilt := Basis(Vector3.UP.cross(n).normalized(), deg_to_rad(float(d.get("wall_tilt", rad_to_deg(WALL_TILT)))))
	var inset := float(d.get("wall_inset", WALL_INSET))
	var raise := float(d.get("wall_raise", WALL_RAISE))
	return Transform3D(tilt * yaw, -n * (0.5 - inset) + Vector3.UP * raise)


static var _shared_materials := {}


static func material_for(block_id: int, textured: bool, cache := {}, frame := 0) -> ShaderMaterial:
	var store: Dictionary = cache if not cache.is_empty() else _shared_materials
	var key := "%d:%s" % [block_id, textured] + (":%d" % frame if frame > 0 else "")
	if not store.has(key):
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/block_model.gdshader")
		m.set_shader_parameter("sprite", frame_texture(block_id, frame))
		m.set_shader_parameter("art_scale", int(Data.block(block_id).get("art_scale", 1)))
		m.set_shader_parameter("textured", textured)
		store[key] = m
	return store[key]


## Shared material for a block's merged platform floor (BlockModelMesh.platform),
## with the noise picked for its method in the placeable picker (Data's
## method_options), set again each time a chunk is built.
static func platform_material(block_id: int) -> ShaderMaterial:
	var key := "%d:platform" % block_id
	var m: ShaderMaterial = _shared_materials.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = preload("res://shaders/block_model_batched.gdshader")
		m.set_shader_parameter("textured", false)
		var palette := BlockModelMesh.platform_palette(block_id)
		m.set_shader_parameter("noise_palette", palette)
		m.set_shader_parameter("noise_palette_size", palette.size())
		_shared_materials[key] = m
	var d := Data.block(block_id)
	var o := BlockModelMesh.platform_options(block_id)
	_param(m, "voxel_noise", maxi(0, Data.EXTRUDE_NOISES.find(o.get("noise", "none"))))
	_param(m, "noise_strength", float(o.get("strength", 0.5)))
	_param(m, "noise_seed", int(o.get("seed", 0)))
	_param(m, "voxels_per_metre", 1.0 / float(d.get("art_px", 1.0 / 16.0)))
	return m


## Shared material for batched block models: lit per instance (custom data).
## `frame`: an animated block's frame (its sprite).
static func batched_material(block_id: int, textured: bool, frame := 0) -> ShaderMaterial:
	var key := "%d:%s:batched:%d" % [block_id, textured, frame]
	if not _shared_materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/block_model_batched.gdshader")
		var d := Data.block(block_id)
		m.set_shader_parameter("sprite", ImageTexture.create_from_image(d.anim_sprites[frame] if frame > 0 else d.sprite))
		m.set_shader_parameter("art_scale", int(d.get("art_scale", 1)))
		m.set_shader_parameter("textured", textured)
		_shared_materials[key] = m
	return _shared_materials[key]
