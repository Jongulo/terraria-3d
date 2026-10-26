class_name TorchFlames
extends Node3D
## Terraria's torch effects. Flames: torches, candles, candelabras,
## chandeliers, lamps and lanterns have a flame sheet (Flame_N, laid out like
## their tile sheet) drawn over them several times at random offsets that
## change every tick (TileDrawing.GetTileFlameData: the block's "flame"), so
## the flame flickers and glows; here a camera-facing quad round the flame
## (flame.gdshader), batched per chunk and block kind like BlockModels. Embers:
## a torch puffs its dust (its "ember": DustID) up from the flame 1 tick in 40
## (TileDrawing.DrawTiles_EmitParticles): most drift up slowing and shrinking,
## a third fall; drawn from the dust sheet, for torches near you. Pulsing
## lights: a block with a "pulse" (the Demon Torch) has its light set to the
## pulse's colour as it changes (VoxelWorld.set_block_emit relights it),
## within PULSE_RANGE of you (each change relights them and remeshes round
## them; farther off they keep the colour they had).

## Each tile sheet's flame sheet (Terraria's Main.tileFlame).
const FLAME_SHEETS := {"Tiles_4": "Flame_0", "Tiles_33": "Flame_1", "Tiles_100": "Flame_2", "Tiles_34": "Flame_3",
		"Tiles_93": "Flame_4", "Tiles_42": "Flame_13"}
const DEFAULT_FLAME := {"count": 7, "color": 100, "x": [-10, 11, 0.15], "y": [-10, 1, 0.35]}
## Embers only from torches this close (Terraria: on screen).
const EMBER_RANGE := 40.0
const EMBER_CHANCE := 1.0 / 40.0
const MAX_EMBERS := 400
const TICK := 1.0 / 60.0
## Terraria pixels a tick (velocity) per block a second.
const PX_TICK := 60.0 / 16.0
## Pulsing lights pulse this close to you (blocks), the list of them made
## again once you've moved PULSE_MOVE from where it was.
const PULSE_RANGE := 24.0
const PULSE_MOVE := 4.0

var world: VoxelWorld
var game: Game
var _by_chunk := {}  # Vector3i -> Array[MultiMeshInstance3D]
var _sources := {}  # Vector3i -> Array of [flame point, dust id, sprite px]
var _embers: Array = []  # {pos, vel, scale, gravity, frame: Vector2, px}
var _ember_mm := MultiMesh.new()
var _acc := 0.0
var _pulse := {}  # Vector3i chunk -> {block id: PackedInt32Array of x, y, z}
var _pulse_cells := {}  # block id -> PackedInt32Array (the chunks round you)
var _pulse_dirty := false
## The block kinds chunk_updated looks for (flames and pulsing ones), found
## once: every chunk that streams in asks.
var _ids := PackedInt32Array()
var _ids_found := false
var _pulse_center := Vector3(INF, INF, INF)
static var _info := {}  # block id -> flame info ({} if it has none)
static var _materials := {}
static var _quad: QuadMesh


func setup(voxel_world: VoxelWorld, g: Game) -> void:
	world = voxel_world
	game = g
	_ember_mm.transform_format = MultiMesh.TRANSFORM_3D
	_ember_mm.use_custom_data = true
	_ember_mm.mesh = _unit_quad()
	_ember_mm.instance_count = MAX_EMBERS
	_ember_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _ember_mm
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/ember.gdshader")
	var sheet := Assets.texture("Images/Dust")
	m.set_shader_parameter("dust", sheet)
	m.set_shader_parameter("sheet_size", Vector2(sheet.get_width(), sheet.get_height()))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)


static func _unit_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


## Every block kind whose light pulses.
static func pulse_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in range(1, Data.blocks.size()):
		if Data.blocks[id].has("pulse"):
			out.append(id)
	return out


## Every block kind with a flame.
static func flame_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in range(1, Data.blocks.size()):
		if Data.blocks[id].has("flame") and not info(id).is_empty():
			out.append(id)
	return out


## A block's flame: {texture, size (px), local: its middle in the block's
## sprite space (metres, before the block's transform), quad (metres),
## params}; {} if it has none.
static func info(id: int) -> Dictionary:
	if _info.has(id):
		return _info[id]
	var d := Data.block(id)
	var out := {}
	var face = d.get("tex", {}).get("all")
	if d.has("flame") and face != null and FLAME_SHEETS.has(face.sheet):
		var f: Dictionary = DEFAULT_FLAME.duplicate()
		f.merge(d.flame, true)
		var flame_face: Dictionary = face.duplicate()
		flame_face.sheet = FLAME_SHEETS[face.sheet]
		var img: Image = Data._stitch(flame_face, face.frames[0])
		var used := img.get_used_rect()
		if used.size.x > 0:
			# Room round it for the offsets.
			var pad := Vector2i(ceili(maxf(absf(f.x[0]), absf(f.x[1] - 1)) * f.x[2]) + 1,
					ceili(maxf(absf(f.y[0]), absf(f.y[1] - 1)) * f.y[2]) + 1)
			var crop := Image.create(used.size.x + pad.x * 2, used.size.y + pad.y * 2, false, Image.FORMAT_RGBA8)
			crop.blit_rect(img, used, pad)
			var sp: float = d.sprite_px
			var centre := Vector2(used.position) + Vector2(used.size) * 0.5
			out = {"texture": ImageTexture.create_from_image(crop), "size": Vector2(crop.get_size()),
					"local": Vector3((centre.x - img.get_width() * 0.5) * sp, (img.get_height() - centre.y) * sp, 0.0),
					"top": Vector3((centre.x - img.get_width() * 0.5) * sp, (img.get_height() - used.position.y) * sp, 0.0),
					"quad": Vector2(crop.get_size()) * sp, "params": f, "px": sp}
	_info[id] = out
	return out


static var _item_info := {}


## A held item's flame (Terraria's ItemFlame_N, drawn over a held torch the
## same way): {texture, size (px), centre (px from the sprite's bottom-left,
## y up), material}; {} if it has none.
static func item_flame(id: int) -> Dictionary:
	if _item_info.has(id):
		return _item_info[id]
	var out := {}
	if FileAccess.file_exists(Assets.disk_path("Images/ItemFlame_%d.png" % id)):
		var img := Assets.image("Images/ItemFlame_%d" % id)
		var used := img.get_used_rect()
		if used.size.x > 0:
			var f := DEFAULT_FLAME
			var pad := Vector2i(ceili(10.0 * f.x[2]) + 1, ceili(10.0 * f.y[2]) + 1)
			var crop := Image.create(used.size.x + pad.x * 2, used.size.y + pad.y * 2, false, Image.FORMAT_RGBA8)
			crop.blit_rect(img, used, pad)
			var m := ShaderMaterial.new()
			m.shader = preload("res://shaders/flame.gdshader")
			m.set_shader_parameter("flame", ImageTexture.create_from_image(crop))
			m.set_shader_parameter("tex_size", Vector2(crop.get_size()))
			m.set_shader_parameter("count", int(f["count"]))
			m.set_shader_parameter("brightness", float(f["color"]) / 255.0)
			m.set_shader_parameter("range_x", Vector3(f.x[0], f.x[1], f.x[2]))
			m.set_shader_parameter("range_y", Vector3(f.y[0], f.y[1], f.y[2]))
			m.set_shader_parameter("billboard", false)
			m.set_shader_parameter("batched", false)
			m.set_shader_parameter("viewmodel", true)
			var centre := Vector2(used.position) + Vector2(used.size) * 0.5
			out = {"size": Vector2(crop.get_size()), "centre": Vector2(centre.x, img.get_height() - centre.y),
					"top": Vector2(centre.x, img.get_height() - used.position.y), "material": m}
	_item_info[id] = out
	return out


## A torch's dust (DustID) for the item that places it, or -1.
static func item_ember(item: String) -> int:
	var place: String = Data.item(item).get("place", "")
	return int(Data.block(Data.block_id(place)).get("ember", -1)) if place != "" else -1


## Puffs an ember from `at` (a held torch).
func spawn_ember(at: Vector3, dust: int, px: float) -> void:
	if _embers.size() < MAX_EMBERS:
		_spawn_ember(at, dust, px)


static func material(id: int) -> ShaderMaterial:
	if not _materials.has(id):
		var fi := info(id)
		var f: Dictionary = fi.params
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/flame.gdshader")
		m.set_shader_parameter("flame", fi.texture)
		m.set_shader_parameter("tex_size", fi.size)
		m.set_shader_parameter("count", int(f["count"]))
		m.set_shader_parameter("brightness", float(f["color"]) / 255.0)
		m.set_shader_parameter("range_x", Vector3(f.x[0], f.x[1], f.x[2]))
		m.set_shader_parameter("range_y", Vector3(f.y[0], f.y[1], f.y[2]))
		_materials[id] = m
	return _materials[id]


## Where a block's flame point (`local`, sprite space) is in the world: the
## block's transform, its wall's for a wall model, its turn for other models.
func flame_point(id: int, pos: Vector3i, local: Vector3) -> Vector3:
	var d := Data.block(id)
	var t := Data.block_transform(d)
	if d.get("wall", false):
		t = BlockModels.wall_transform(game.block_rotation(pos), d) * t
	elif int(d.get("render_id", 0)) == 5 and d.get("method", "") != "billboard":
		t = Transform3D(Basis(Vector3.UP, game.block_rotation(pos) * PI * 0.5), Vector3.ZERO) * t
	return Vector3(pos) + Vector3(0.5, 0.0, 0.5) + t * local


func chunk_unloaded(c: Vector3i) -> void:
	for n in _by_chunk.get(c, []):
		n.queue_free()
	_by_chunk.erase(c)
	_sources.erase(c)
	if _pulse.has(c):
		_pulse.erase(c)
		_pulse_dirty = true


func chunk_updated(c: Vector3i) -> void:
	chunk_unloaded(c)
	if not _ids_found:
		_ids_found = true
		_ids = flame_ids()
		for id in pulse_ids():
			if not id in _ids:
				_ids.append(id)
	var ids := _ids
	if ids.is_empty():
		return
	var lo := c * ChunkRenderer.CHUNK
	var found := world.find_blocks(lo + Vector3i.ONE * (ChunkRenderer.CHUNK / 2), Vector3i.ONE * (ChunkRenderer.CHUNK / 2), ids, 100000)
	var groups := {}  # id -> [Vector3i]
	for i in range(0, found.size(), 3):
		var p := Vector3i(found[i], found[i + 1], found[i + 2])
		if p.x >= lo.x + ChunkRenderer.CHUNK or p.y >= lo.y + ChunkRenderer.CHUNK or p.z >= lo.z + ChunkRenderer.CHUNK:
			continue
		var id := world.get_block(p)
		if not groups.has(id):
			groups[id] = []
		groups[id].append(p)
	var nodes := []
	var sources := []
	var pulsing := {}
	for id in groups:
		if Data.block(id).has("pulse"):
			var cells := PackedInt32Array()
			for p in groups[id]:
				cells.append_array([p.x, p.y, p.z])
			pulsing[id] = cells
		var fi := info(id)
		if fi.is_empty():
			continue
		var list: Array = groups[id]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _unit_quad()
		mm.instance_count = list.size()
		var ember: int = int(Data.block(id).get("ember", -1))
		for i in list.size():
			var p: Vector3i = list[i]
			var at := flame_point(id, p, fi.local)
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(fi.quad.x, fi.quad.y, 1.0)), at))
			mm.set_instance_custom_data(i, Color(float(absi(hash(p)) % 10007), 0, 0, 0))
			if ember >= 0:
				sources.append([flame_point(id, p, fi.top), ember, fi.px])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = material(id)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		nodes.append(mi)
	_by_chunk[c] = nodes
	if not sources.is_empty():
		_sources[c] = sources
	if not pulsing.is_empty():
		_pulse[c] = pulsing
		_pulse_dirty = true


## How many flames are drawn (tests).
func count() -> int:
	var n := 0
	for list in _by_chunk.values():
		for mi in list:
			n += mi.multimesh.instance_count
	return n


func ember_count() -> int:
	return _embers.size()


func _physics_process(delta: float) -> void:
	if game == null or game.player == null:
		return
	_acc += delta
	var steps := 0
	while _acc >= TICK and steps < 4:
		_acc -= TICK
		steps += 1
		_tick()
	_draw_embers()
	_update_pulses()


## Pulsing lights: each kind's light set to its colour now (the world only
## relights when that moves to another of its 16 levels).
func _update_pulses() -> void:
	var at := game.player.global_position
	if at.distance_to(_pulse_center) >= PULSE_MOVE:
		_pulse_center = at
		_pulse_dirty = true
	if _pulse_dirty:
		_pulse_dirty = false
		_pulse_cells = {}
		var reach := PULSE_RANGE + ChunkRenderer.CHUNK
		for c in _pulse:
			var mid := (Vector3(c) + Vector3.ONE * 0.5) * ChunkRenderer.CHUNK
			if absf(mid.x - at.x) > reach or absf(mid.y - at.y) > reach or absf(mid.z - at.z) > reach:
				continue
			var per: Dictionary = _pulse[c]
			for id in per:
				var cells: PackedInt32Array = per[id]
				for i in range(0, cells.size(), 3):
					if Vector3(cells[i], cells[i + 1], cells[i + 2]).distance_to(at) <= PULSE_RANGE:
						if not _pulse_cells.has(id):
							_pulse_cells[id] = PackedInt32Array()
						_pulse_cells[id].append_array([cells[i], cells[i + 1], cells[i + 2]])
	for id in _pulse_cells:
		world.set_block_emit(id, Data.pulse_color(Data.block(id).pulse), _pulse_cells[id])


## The cells of a pulsing kind being kept up to date (tests).
func pulse_cells(id: int) -> PackedInt32Array:
	return _pulse_cells.get(id, PackedInt32Array())


## One tick: new embers from the torches near you, and the embers move.
func _tick() -> void:
	var eye := game.player.view().global_position
	for list in _sources.values():
		for s in list:
			if randf() >= EMBER_CHANCE or _embers.size() >= MAX_EMBERS:
				continue
			var at: Vector3 = s[0]
			if at.distance_squared_to(eye) > EMBER_RANGE * EMBER_RANGE:
				continue
			_spawn_ember(at, int(s[1]), float(s[2]))
	var keep := []
	for e in _embers:
		if e.gravity:
			e.vel.y -= 0.1 * PX_TICK
			e.scale -= 0.01
		else:
			e.vel *= 0.92
			e.scale -= 0.03
		e.pos += e.vel * TICK
		if e.scale > 0.1 and not (e.gravity and world.is_solid(Vector3i(e.pos.floor()))):
			keep.append(e)
	_embers = keep


## Terraria's torch dust: a 4 px box at the top of the flame, Dust.NewDust's
## random velocity (-2..2 px a tick each way) x 0.3, 1.5 px a tick upward, a
## third of them falling.
func _spawn_ember(at: Vector3, dust: int, px: float) -> void:
	var v := Vector3(randi_range(-20, 20), randi_range(-20, 20), randi_range(-20, 20)) * 0.1 * 0.3
	v.y = -v.y + 1.5  # Terraria's y is down
	_embers.append({"pos": at + Vector3(randf_range(-2, 2), randf_range(0, 4), randf_range(-2, 2)) * px,
			"vel": v * PX_TICK, "scale": 1.0 + randi_range(-20, 20) * 0.01, "gravity": randi() % 3 == 0,
			"frame": Vector2((dust % 100) * 10, (dust / 100) * 30 + (randi() % 3) * 10), "px": px})


func _draw_embers() -> void:
	_ember_mm.visible_instance_count = _embers.size()
	for i in _embers.size():
		var e: Dictionary = _embers[i]
		var size: float = 8.0 * e.px * e.scale
		_ember_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(size, size, size)), e.pos))
		_ember_mm.set_instance_custom_data(i, Color(e.frame.x, e.frame.y, 0.0, clampf(e.scale, 0.0, 1.0)))
