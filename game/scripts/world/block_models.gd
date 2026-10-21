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
## built again.

var world: VoxelWorld
var game: Game
var _by_chunk := {}  # Vector3i -> Array[Node3D]
## Each model block's instance: "x,y,z" -> {mesh, transform, light} (tests,
## and anything that needs to know how a block is drawn).
var _models := {}
var _models_by_chunk := {}  # Vector3i -> Array of _models keys
## Open doors in loaded chunks, for aiming at their panels (Doors.raycast):
## "x,y,z" -> bottom cell.
var open_doors := {}
var _doors_by_chunk := {}  # Vector3i -> Array of open_doors keys
var _sky_light := 1.0
var _sky_color := Color.WHITE
## Level of detail: in chunks more than DETAIL_CHUNKS from yours, placeables
## with a heavy 3D method (voxel models, extrusions) are drawn as their crossed
## sprite instead; they're rebuilt as you move (a few chunks a frame).
const DETAIL_CHUNKS := 2
const HEAVY_METHODS := ["hull", "hull_top", "lathe", "claude", "tuned", "extruded", "flat"]
const REBUILDS_PER_FRAME := 3
var _detail := {}  # Vector3i chunk -> whether it was built in full detail
var _player_chunk := Vector3i(1 << 20, 0, 0)
var _rebuild_queue: Array[Vector3i] = []
## Animated batches per chunk: Vector3i -> Array of {node, id, method,
## rotation, textured, billboard (variant, or -1), frame, blocks}.
var _animated := {}
## Blocks drawn as billboards while their rendered shots are being made.
var _waiting_renders := {}


func setup(voxel_world: VoxelWorld, g: Game) -> void:
	world = voxel_world
	game = g


func set_sky(light: float, color: Color) -> void:
	_sky_light = light
	_sky_color = color
	# Cacti and tree branches keep their own materials (CactusArt, TreeBranches).
	for m in _shared_materials.values() + Doors.materials() + CactusArt.materials() + TreeBranches.materials():
		m.set_shader_parameter("sky_light", light)
		m.set_shader_parameter("sky_color", color)


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
	return _models.get(Chests.key(pos), {})


func chunk_unloaded(c: Vector3i) -> void:
	_animated.erase(c)
	_detail.erase(c)
	for n in _by_chunk.get(c, []):
		n.queue_free()
	_by_chunk.erase(c)
	for k in _models_by_chunk.get(c, []):
		_models.erase(k)
	_models_by_chunk.erase(c)
	for k in _doors_by_chunk.get(c, []):
		open_doors.erase(k)
	_doors_by_chunk.erase(c)


func chunk_updated(c: Vector3i) -> void:
	chunk_unloaded(c)
	var data := world.get_model_blocks(c)
	if data.is_empty():
		return
	var nodes: Array = []
	var detailed := full_detail(c)
	_detail[c] = detailed
	var billboards := {}  # Vector2i(block id, variant) -> Array[Vector3i]
	var rendered := {}  # block id -> Array of [Vector3i, rotation]
	var batches := {}  # mesh key -> {id, mesh, textured, items: [[Transform3D, Vector3i]]}
	var keys: Array = []
	var cacti := []
	var palms := []
	var trunks := []
	var kinds := {}  # block id -> what this loop needs of it (looked up once)
	for i in range(0, data.size(), 4):
		var pos := Vector3i(data[i], data[i + 1], data[i + 2])
		var id := int(data[i + 3])
		if not kinds.has(id):
			var bd := Data.block(id)
			kinds[id] = {"trunk": bd.get("trunk", false) and not bd.get("palm", false), "palm": bd.get("palm", false),
					"cactus": bd.get("cactus", false), "door": Doors.is_part(bd), "method": bd.get("method", "panels"),
					"wall": bd.get("wall", false), "variants": bd.get("variants", 1), "scatter": float(bd.get("scatter", 0.0))}
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
				var door := Doors.make_node(id, game.block_rotation(pos), Chests.key(pos))
				add_child(door)
				door.global_position = Vector3(pos) + Vector3(0.5, 0.0, 0.5)
				Doors.set_light(door, world.get_light(Vector3(pos) + Vector3(0.5, 1.0, 0.5)))
				Doors.animate(door)
				nodes.append(door)
				if Doors.is_open(Data.block(id)):
					open_doors[Chests.key(pos)] = pos
					if not _doors_by_chunk.has(c):
						_doors_by_chunk[c] = []
					_doors_by_chunk[c].append(Chests.key(pos))
			continue
		var method: String = k.method
		if method == "rendered" and not k.wall:
			if not PlaceableRenders.renders(id).is_empty():
				if not rendered.has(id):
					rendered[id] = []
				rendered[id].append([pos, game.block_rotation(pos), scatter_at(pos, k.scatter)])
				continue
			_waiting_renders[id] = true
			method = "billboard"  # until its shots are made
		if method == "billboard" and not k.wall:
			var key := Vector2i(id, variant_at(pos, k.variants))
			if not billboards.has(key):
				billboards[key] = []
			billboards[key].append(pos)
			continue
		var rotation := game.block_rotation(pos)
		var frame := Data.anim_frame_now(Data.block(id))
		var shape := world.get_shape(pos) if Data.block(id).get("platform", false) else 0
		if shape >= Game.SHAPE_RAMP and shape < Game.SHAPE_CEILING:
			# A platform stair: its stair twin, turned to rise toward
			# WALL_NORMALS[shape - 2] (the art rises toward +x).
			id = Data.block_id(Data.block(id).name + "_stair")
			method = Data.block(id).get("method", "extruded")
			if method in ["billboard", "rendered"]:
				method = "extruded"
			rotation = (shape - Game.SHAPE_RAMP + 3) % 4
		if not detailed and method in HEAVY_METHODS:
			method = "cross"  # far off: its crossed sprite
		var model := model_mesh(id, method, rotation, frame)
		var mkey := "%d:%d" % [id, model.mesh.get_instance_id()]
		if not batches.has(mkey):
			batches[mkey] = {"id": id, "mesh": model.mesh, "textured": model.textured, "items": [],
					"method": method, "rotation": rotation, "frame": frame}
		var t := Transform3D(Basis(Vector3.UP, int(model.turn) * PI * 0.5), Vector3(pos) + Vector3(0.5, 0.0, 0.5))
		if k.scatter > 0.0:
			var sc := scatter_at(pos, k.scatter)
			t = Transform3D(sc.basis * t.basis, t.origin + sc.origin)
		# A stair's beam hangs below its block to meet the next stair down.
		t.origin.y -= float(Data.block(id).get("stair_drop", 0.0))
		batches[mkey].items.append([t, pos])
	var animated := []
	for b in batches.values():
		var node := _mesh_batch(b.id, b.mesh, b.textured, b.items, keys, b.frame)
		add_child(node)
		nodes.append(node)
		if Data.anim_frames(Data.block(b.id)) > 1:
			animated.append({"node": node, "id": b.id, "method": b.method, "rotation": b.rotation,
					"textured": b.textured, "billboard": -1, "frame": b.frame, "blocks": b.items.map(func(it): return it[1])})
	for key in billboards:
		var frame := Data.anim_frame_now(Data.block(key.x))
		var node := _billboard_batch(key.x, key.y, billboards[key], keys, frame)
		add_child(node)
		nodes.append(node)
		if Data.anim_frames(Data.block(key.x)) > 1:
			animated.append({"node": node, "id": key.x, "method": "billboard", "rotation": 0,
					"textured": true, "billboard": key.y, "frame": frame, "blocks": billboards[key]})
	for id in rendered:
		var frame := Data.anim_frame_now(Data.block(id))
		var node := _rendered_batch(id, rendered[id], keys, frame)
		add_child(node)
		nodes.append(node)
		if Data.anim_frames(Data.block(id)) > 1:
			animated.append({"node": node, "id": id, "method": "rendered", "rotation": 0,
					"textured": false, "billboard": -1, "frame": frame, "blocks": rendered[id].map(func(it): return it[0])})
	if not animated.is_empty():
		_animated[c] = animated
	for node in _branch_batches(trunks):
		add_child(node)
		nodes.append(node)
	for node in _palm_batches(palms, keys):
		add_child(node)
		nodes.append(node)
	for node in _cactus_batches(cacti, keys):
		add_child(node)
		nodes.append(node)
	for n in nodes:
		if n is MultiMeshInstance3D:
			# A material made just now hasn't had this frame's sky yet.
			n.material_override.set_shader_parameter("sky_light", _sky_light)
			n.material_override.set_shader_parameter("sky_color", _sky_color)
	_by_chunk[c] = nodes
	_models_by_chunk[c] = keys


## Whether chunk `c` is drawn in full detail (near your chunk), or without a
## player (the picker, tests without one) always.
func full_detail(c: Vector3i) -> bool:
	if game == null or game.player == null or _player_chunk.x == 1 << 20:
		return true
	var d := c - _player_chunk
	return maxi(absi(d.x), absi(d.z)) <= DETAIL_CHUNKS and absi(d.y) <= DETAIL_CHUNKS


## Rebuilds chunks whose level of detail changed since you moved.
func _update_detail() -> void:
	if game == null or game.player == null:
		return
	var p := game.player.global_position
	var pc := Vector3i(floori(p.x / 32.0), floori(p.y / 32.0), floori(p.z / 32.0))
	if pc != _player_chunk:
		_player_chunk = pc
		for c in _detail:
			if _detail[c] != full_detail(c) and not c in _rebuild_queue:
				_rebuild_queue.append(c)
	# A couple of milliseconds a frame (at least one chunk).
	var start := Time.get_ticks_usec()
	var n := 0
	while not _rebuild_queue.is_empty() and n < REBUILDS_PER_FRAME and (n == 0 or Time.get_ticks_usec() - start < 2000):
		var c: Vector3i = _rebuild_queue.pop_front()
		if _detail.has(c) and _detail[c] != full_detail(c):
			chunk_updated(c)
			n += 1


## Moves animated batches on to the frame their block is on now.
func _process(_delta: float) -> void:
	_update_detail()
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
			m.set_shader_parameter("sky_light", _sky_light)
			m.set_shader_parameter("sky_color", _sky_color)
			mi.material_override = m


## Once blocks waiting for their rendered shots have them, their chunks are
## built again with the shots.
func _check_renders() -> void:
	if _waiting_renders.is_empty():
		return
	var ready := _waiting_renders.keys().filter(func(id): return not PlaceableRenders.renders(id).is_empty())
	if ready.is_empty():
		return
	for id in ready:
		_waiting_renders.erase(id)
	refresh_all()


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


## Variant for a block at `pos`: stable, and different between neighbours.
static func variant_at(pos: Vector3i, variants: int) -> int:
	if variants <= 1:
		return 0
	return absi(hash(pos)) % variants


## One mesh drawn at `items` ([Transform3D, block position]), each instance
## lit by its block's light (custom data); records them in _models.
func _mesh_batch(block_id: int, mesh: ArrayMesh, textured: bool, items: Array, keys: Array, frame := 0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		var t: Transform3D = items[i][0]
		var pos: Vector3i = items[i][1]
		var light := world.get_light(Vector3(pos) + Vector3(0.5, 0.5, 0.5))
		mm.set_instance_transform(i, t)
		mm.set_instance_custom_data(i, light)
		_models[Chests.key(pos)] = {"mesh": mesh, "transform": t, "light": light}
		keys.append(Chests.key(pos))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = batched_material(block_id, textured, frame)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _billboard_batch(block_id: int, variant: int, positions: Array, keys: Array, frame := 0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BlockModelMesh.build(block_id, "billboard", frame).mesh
	mm.instance_count = positions.size()
	# The block's transform, once (billboard_instance per block).
	var bt := Data.block_transform(Data.block(block_id))
	var bscale := Basis.from_scale(Vector3.ONE * bt.basis.get_scale().x)
	var scatter := float(Data.block(block_id).get("scatter", 0.0))
	for i in positions.size():
		var pos: Vector3i = positions[i]
		var t := Transform3D(bscale, Vector3(pos) + Vector3(0.5, 0.0, 0.5) + bt.origin + scatter_at(pos, scatter).origin)
		var light := world.get_light(Vector3(pos) + Vector3(0.5, 0.5, 0.5))
		mm.set_instance_transform(i, t)
		mm.set_instance_custom_data(i, light)
		_models[Chests.key(pos)] = {"mesh": mm.mesh, "transform": t, "light": light}
		keys.append(Chests.key(pos))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = billboard_material(block_id, variant, frame)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


## Rendered placeables of one block: `items` [block position, rotation,
## scatter_at], each a quad turned to the camera in the shader, the instance
## turned the way the block was placed and scattered (the shots turn with it).
func _rendered_batch(block_id: int, items: Array, keys: Array, frame := 0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = rendered_quad()
	mm.instance_count = items.size()
	for i in items.size():
		var pos: Vector3i = items[i][0]
		var t := Transform3D(Basis(Vector3.UP, int(items[i][1]) * PI * 0.5), Vector3(pos) + Vector3(0.5, 0.0, 0.5))
		if items[i].size() > 2:
			var sc: Transform3D = items[i][2]
			t = Transform3D(sc.basis * t.basis, t.origin + sc.origin)
		var light := world.get_light(Vector3(pos) + Vector3(0.5, 0.5, 0.5))
		mm.set_instance_transform(i, t)
		mm.set_instance_custom_data(i, light)
		_models[Chests.key(pos)] = {"mesh": mm.mesh, "transform": t, "light": light}
		keys.append(Chests.key(pos))
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
		m.set_shader_parameter("yaws", r.yaws)
		m.set_shader_parameter("rows", r.pitches.size())
		m.set_shader_parameter("atlas", r.atlases[clampi(frame, 0, r.atlases.size() - 1)])
		m.set_shader_parameter("center", r.center)
		m.set_shader_parameter("size", r.n * r.px)
		m.set_shader_parameter("radius", r.radius)
	return m


## The branches on these trunk cells (TreeBranches): fixed cards, one batch
## per look. A trunk without its canopy (a stump) has none.
func _branch_batches(cells: Array) -> Array:
	var trees := {}  # base -> [height, branches, sheet] (a trunk can span chunks: each finds it)
	var groups := {}  # art -> [Transform3D, light] list
	var arts := {}
	for pos in cells:
		var tree: Array = []
		for base in trees:
			if base.x == pos.x and base.z == pos.z and pos.y >= base.y and pos.y < base.y + trees[base][0]:
				tree = trees[base]
		if tree.is_empty():
			var col := TreeBranches.column(world, pos)
			var top: Vector3i = col[0] + Vector3i.UP * col[1]
			var canopy: int = game.decorations.canopies.get(top, -1) if game != null else -1
			tree = [col[1], TreeBranches.branches(col[0], col[1]) if canopy >= 0 else [], TreeBranches.sheet_for(maxi(canopy, 0)), col[0]]
			trees[col[0]] = tree
		var base: Vector3i = tree[3]
		var trunk_sheet: String = Data.block(world.get_block(pos)).get("tex", {}).get("all", {}).get("sheet", "Tiles_5")
		for b in tree[1]:
			if b.cell != pos.y - base.y:
				continue
			var art := TreeBranches.get_art(tree[2], trunk_sheet, b)
			var k: int = art.material.get_instance_id()
			if not groups.has(k):
				groups[k] = []
				arts[k] = art
			var t := TreeBranches.transform(base, b)
			groups[k].append([t, world.get_light(t.origin + b.dir * 0.75)])
	var out := []
	for k in groups:
		var list: Array = groups[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = arts[k].mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_custom_data(i, list[i][1])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = arts[k].material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		out.append(mi)
	return out


## Palm trunk cells: each its segment's billboard (palm_trunk's variant),
## shifted along the palm's curve, one batch per segment frame.
func _palm_batches(cells: Array, keys: Array) -> Array:
	var shapes := {}  # base -> PalmArt shape (a palm can span chunks: each finds it)
	var groups := {}  # [id, frame] -> [[cell, offset], ...]
	for pos in cells:
		var s: Dictionary = {}
		for base in shapes:
			if base.x == pos.x and base.z == pos.z and pos.y >= base.y and pos.y < base.y + shapes[base].height:
				s = shapes[base]
		if s.is_empty():
			s = PalmArt.at(world, pos)
			if s.is_empty():
				continue
			shapes[s.base] = s
		var k: int = pos.y - s.base.y
		var key := Vector2i(world.get_block(pos), s.frames[k])
		if not groups.has(key):
			groups[key] = []
		groups[key].append([pos, PalmArt.segment_offset(s, k), PalmArt.segment_nudge(s, k)])
	var out := []
	for key in groups:
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = BlockModelMesh.build(key.x, "billboard").mesh
		mm.instance_count = list.size()
		for i in list.size():
			var pos: Vector3i = list[i][0]
			var t := billboard_instance(key.x, pos)
			t.origin += list[i][1]
			# The billboard shader reads a longer z axis as a nudge toward the camera.
			t.basis.z = t.basis.z.normalized() * (t.basis.get_scale().y + list[i][2])
			var light := world.get_light(Vector3(pos) + Vector3(0.5, 0.5, 0.5))
			mm.set_instance_transform(i, t)
			mm.set_instance_custom_data(i, light)
			_models[Chests.key(pos)] = {"mesh": mm.mesh, "transform": t, "light": light}
			keys.append(Chests.key(pos))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = billboard_material(key.x, key.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		out.append(mi)
	return out


## Cacti standing on these base cells, one batch per shape.
func _cactus_batches(bases: Array, keys: Array) -> Array:
	var groups := {}  # shape code -> [art, [base, ...]]
	for base in bases:
		var col := CactusArt.column(world, base)
		var s := CactusArt.shape(base, col[1], CactusArt.color_for(Data.block(world.get_block(base + Vector3i.DOWN))))
		var c := CactusArt.code(s)
		if not groups.has(c):
			groups[c] = [CactusArt.get_art(s), []]
		groups[c][1].append(base)
	var out := []
	for c in groups:
		var art: Dictionary = groups[c][0]
		var list: Array = groups[c][1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = art.mesh
		mm.instance_count = list.size()
		for i in list.size():
			var base: Vector3i = list[i]
			var t := Transform3D(Basis(), Vector3(base) + Vector3(0.5, 0.0, 0.5))
			var light := world.get_light(Vector3(base) + Vector3(0.5, 1.5, 0.5))
			mm.set_instance_transform(i, t)
			mm.set_instance_custom_data(i, light)
			_models[Chests.key(base)] = {"mesh": art.mesh, "transform": t, "light": light}
			keys.append(Chests.key(base))
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
	if not _meshes.has(key):
		_meshes[key] = BlockModelMesh.transformed(mesh, t)
	return _meshes[key]


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
