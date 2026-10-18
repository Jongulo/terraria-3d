class_name FallingLeaves
extends Node3D
## Terraria's falling leaves. Trees drop them (TileDrawing.EmitTreeLeaves):
## each tree near you rolls once a tick, 1 in Terraria's leaf frequency, which
## comes from the wind (UpdateLeafFrequency: 14000 in still air down to 70 in
## a gale; half for Hallow trees, three times for a leafy branch, 10000 where
## the wind doesn't reach). The leaf is the tree's (WorldGen.GetTreeLeaf:
## forest, jungle, Corruption, Crimson, palm, gem, Sakura, Willow; snow, ash and
## mushroom trees drop none). Living-tree leaf blocks drop them too, 4 times as
## often, below them and toward the wind (EmitLivingTreeLeaf).
## A leaf (Gore_UpdateLeaf) sways as it sinks: its swing angle goes up a degree
## a tick and it moves (-sin, |cos|) of it in pixels a tick, pushed along by
## the wind (4 px a tick at full wind) where it blows; it tumbles through 4
## frames of its sheet every 8 ticks and leans along its path. Landed it lies
## still (sliding with the wind), on water it floats, and after 10 seconds it
## fades. It drifts through tree trunks (Terraria's trees aren't solid tiles);
## a wall only stops it going sideways, so it slides down it. Wind here blows
## along x (Terraria's left and right).

## Canopy sheet (CanopyArt.SHEETS index) -> leaf gore (-1: none).
const SHEET_LEAVES := [910, 915, 916, -1, 914, 910, 910, 910, 910, 910, -1, -1, -1, -1, 914, 911,
		1249, 1250, 1251, 1252, 1253, 1254, 1255, 1248, 1257, -1, 914]
## Leaf blocks of living trees -> leaf gore.
const BLOCK_LEAVES := {"leaf_block": 910, "mahogany_leaves": 914}
const HALLOW_LEAVES := Vector2i(917, 925)
const SOURCE_RANGE := 40.0
const MAX_LEAVES := 400
const TICK := 1.0 / 60.0
const PX := 16.0
## Pixels a tick -> blocks a second.
const PX_TICK := 60.0 / PX
## How big a leaf's pixels are drawn (blocks): half a canopy pixel, like the
## placeable sprites' 32 to a block.
const LEAF_PX := 1.0 / 32.0
const LIFE := 10.0
const FADE := 2.0

var world: VoxelWorld
var game: Game
var _sources := []  # {at: Vector3, leaf: int, mult: float, block: bool}
var _rebuild := 0.0
var _leaves: Array = []
var _acc := 0.0
var _batches := {}  # leaf gore -> MultiMeshInstance3D
static var _quad: QuadMesh
static var _trunks := {}  # block ids leaves drift through


func setup(voxel_world: VoxelWorld, g: Game) -> void:
	world = voxel_world
	game = g


## Terraria's leaf frequency for a wind speed.
static func frequency(wind: float) -> int:
	var w := absf(wind)
	var f := 10
	for step in [[0.1, 2000], [0.2, 1000], [0.3, 450], [0.4, 300], [0.5, 200], [0.6, 130], [0.7, 75], [0.8, 50],
			[0.9, 40], [1.0, 30], [1.1, 20]]:
		if w <= step[0]:
			f = step[1]
			break
	return f * 7


## The leaf a canopy style drops (-1: none).
static func canopy_leaf(style: int) -> int:
	var sheet := style / 10
	return SHEET_LEAVES[sheet] if sheet >= 0 and sheet < SHEET_LEAVES.size() else -1


## Whether the wind blows here (Terraria: above the underground): open to
## the sky.
func wind_reaches(at: Vector3) -> bool:
	return world.get_light(at).a > 0.0


func leaf_count() -> int:
	return _leaves.size()


func source_count() -> int:
	return _sources.size()


## What drops leaves near you: every canopy (and its leafy branches) and
## the undersides of living-tree leaf blocks.
func rebuild_sources() -> void:
	_sources.clear()
	var eye := game.player.global_position
	for top in game.decorations.canopies:
		if Vector3(top).distance_squared_to(eye) > SOURCE_RANGE * SOURCE_RANGE:
			continue
		var style: int = game.decorations.canopies[top]
		var leaf := canopy_leaf(style)
		if leaf < 0:
			continue
		var d := Data.block(Data.block_id(CanopyArt.block_name(style)))
		var size := Vector2(d.sprite.get_size()) * float(d.sprite_px) if not d.is_empty() else Vector2(3, 3)
		var hallow := leaf >= HALLOW_LEAVES.x and leaf <= HALLOW_LEAVES.y
		_sources.append({"at": game.decorations.canopy_position(top, style), "size": size, "leaf": leaf,
				"mult": 0.5 if hallow else 1.0, "kind": "canopy"})
		# Leafy branches: three times as rare.
		var col := TreeBranches.column(world, top + Vector3i.DOWN)
		if col[1] > 0:
			for b in TreeBranches.branches(col[0], col[1]):
				if b.leafy:
					var t := TreeBranches.transform(col[0], b)
					_sources.append({"at": t.origin + b.dir * 1.2, "size": Vector2(1.5, 1.0), "leaf": leaf, "mult": 3.0, "kind": "branch"})
	var ids := PackedInt32Array()
	for n in BLOCK_LEAVES:
		ids.append(Data.block_id(n))
	var found := world.find_blocks(Vector3i(eye.floor()), Vector3i(32, 24, 32), ids, 6000)
	for i in range(0, found.size(), 3):
		var p := Vector3i(found[i], found[i + 1], found[i + 2])
		if world.is_solid(p + Vector3i.DOWN) and world.is_solid(p + Vector3i.RIGHT) and world.is_solid(p + Vector3i.LEFT):
			continue  # nowhere for a leaf to fall
		_sources.append({"cell": p, "leaf": BLOCK_LEAVES[Data.block(world.get_block(p)).name], "mult": 0.25, "kind": "block"})


func _physics_process(delta: float) -> void:
	if game == null or game.player == null or game.state != Game.State.PLAYING:
		return
	_rebuild -= delta
	if _rebuild <= 0.0:
		_rebuild = 2.0
		rebuild_sources()
	_acc += delta
	var steps := 0
	while _acc >= TICK and steps < 4:
		_acc -= TICK
		steps += 1
		_tick()
	_draw()


func _tick() -> void:
	var freq := float(frequency(game.sky.wind))
	for s in _sources:
		if _leaves.size() >= MAX_LEAVES:
			break
		var at: Vector3 = s.at if s.has("at") else Vector3(s.cell) + Vector3(0.5, 0.0, 0.5)
		var f: float = freq * float(s.mult)
		if not wind_reaches(at + Vector3.UP):
			f = 10000.0 * (3.0 if s.kind == "branch" else 1.0)
		if randf() * f >= 1.0:
			continue
		match s.kind:
			"block":
				_emit_from_block(s.cell, int(s.leaf))
			_:
				# Somewhere in the canopy's lower part, Terraria's random push.
				var size: Vector2 = s.size
				var p := at + Vector3(randf_range(-0.35, 0.35) * size.x, randf_range(0.1, 0.55) * size.y, randf_range(-0.35, 0.35) * size.x)
				if not blocks_leaf(Vector3i(p.floor())):
					# (Terraria's random velocity is replaced by the leaf's own.)
					spawn(p, int(s.leaf), Vector2.ZERO, 0.7 + randf() * 0.6)
	_step_leaves()


## A living-tree leaf block: a leaf from its underside, and half the time
## one from its side the wind blows to.
func _emit_from_block(cell: Vector3i, leaf: int) -> void:
	if not world.is_solid(cell + Vector3i.DOWN) and world.get_liquid(cell + Vector3i.DOWN).y == 0:
		spawn(Vector3(cell) + Vector3(randf(), -0.05, randf()), leaf, Vector2.ZERO, 1.0)
	if randi() % 2 == 0:
		var dir := 1 if game.sky.wind > 0.2 else (-1 if game.sky.wind < -0.2 else 0)
		var side := cell + Vector3i(dir, 0, 0)
		if not world.is_solid(side) and world.get_liquid(side).y == 0:
			spawn(Vector3(cell) + Vector3(0.5 + dir * 0.55, 0.5, randf()), leaf, Vector2.ZERO, 1.0)


## A leaf at `at`: Terraria's leaf gore starts with a random sideways speed
## (-0.5..0.5) and swing angle (0..2 pi); `push` adds an emitter's random
## velocity (pixels a tick, x and down).
func spawn(at: Vector3, leaf: int, push := Vector2.ZERO, scale := 1.0) -> void:
	if _leaves.size() >= MAX_LEAVES:
		return
	var axis := Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
	_leaves.append({"pos": at, "leaf": leaf, "axis": axis, "angle": randf() * TAU,
			"push": Vector3(push.x, -push.y, randf_range(-1.0, 1.0) * absf(push.x)) * PX_TICK, "scale": scale,
			"row": randi() % 8, "frame_t": 0, "landed": false, "age": 0.0, "spin": 0.0})


func _step_leaves() -> void:
	var wind: float = game.sky.wind
	var keep := []
	for l in _leaves:
		l.age += TICK
		if l.age > LIFE + FADE:
			continue
		var cell := Vector3i(l.pos.floor())
		var liquid: Vector2i = world.get_liquid(cell)
		var blows := wind_reaches(l.pos)
		if not l.landed:
			l.angle += PI / 180.0
			var swing := Vector2(-sin(l.angle), absf(cos(l.angle)))
			var step: Vector3 = l.axis * swing.x * PX_TICK - Vector3(0, swing.y * PX_TICK, 0)
			if blows:
				step.x += wind * 4.0 * PX_TICK
			step += l.push
			l.push *= 0.9
			if liquid.y > 0:
				l.landed = true  # floating
			else:
				# Sideways and down separately: a wall stops it going sideways,
				# only something under it stops it falling.
				var side: Vector3 = l.pos + Vector3(step.x, 0.0, step.z) * TICK
				if not blocks_leaf(Vector3i(side.floor())):
					l.pos = side
				var down: Vector3 = l.pos + Vector3(0.0, step.y * TICK, 0.0)
				if blocks_leaf(Vector3i(down.floor())):
					l.landed = true
				else:
					l.pos = down
				l.spin = atan2(step.y, Vector2(step.x, step.z).length() * signf(swing.x + 0.0001)) + PI * 0.5
			l.frame_t += 1
			if l.frame_t >= 8:
				l.frame_t = 0
				var group: int = l.row / 4
				l.row = group * 4 + (l.row % 4 + 1) % 4
		else:
			# Lying there: the wind slides it along; falls again off an edge.
			var below := Vector3i((l.pos + Vector3(0, -0.1, 0)).floor())
			if not blocks_leaf(below) and world.get_liquid(below).y == 0 and liquid.y == 0:
				l.landed = false
				l.angle = 0.0
			elif blows and liquid.y == 0:
				var to: Vector3 = l.pos + Vector3(wind * PX_TICK * TICK, 0, 0)
				if not blocks_leaf(Vector3i(to.floor())):
					l.pos = to
			l.spin = PI * 0.5
		keep.append(l)
	_leaves = keep


## Whether a cell stops a leaf: solid, but not a tree trunk.
func blocks_leaf(cell: Vector3i) -> bool:
	if not world.is_solid(cell):
		return false
	var id := world.get_block(cell)
	if not _trunks.has(id):
		_trunks[id] = Data.block(id).get("trunk", false)
	return not _trunks[id]


static func _unit_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(12.0, 14.0)
	return _quad


func _batch(leaf: int) -> MultiMeshInstance3D:
	if not _batches.has(leaf):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.use_colors = true
		mm.mesh = _unit_quad()
		mm.instance_count = MAX_LEAVES
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/leaf.gdshader")
		var tex := Assets.texture("Images/Gore_%d" % leaf)
		m.set_shader_parameter("sheet", tex)
		m.set_shader_parameter("sheet_size", Vector2(tex.get_width(), tex.get_height()))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16384.0
		add_child(mi)
		_batches[leaf] = mi
	return _batches[leaf]


func _draw() -> void:
	var by_leaf := {}
	for l in _leaves:
		if not by_leaf.has(l.leaf):
			by_leaf[l.leaf] = []
		by_leaf[l.leaf].append(l)
	for leaf in _batches:
		if not by_leaf.has(leaf):
			_batches[leaf].multimesh.visible_instance_count = 0
	for leaf in by_leaf:
		var mi := _batch(leaf)
		var m: ShaderMaterial = mi.material_override
		m.set_shader_parameter("sky_light", game.sky.sky_light)
		m.set_shader_parameter("sky_color", game.sky.sky_tint)
		var list: Array = by_leaf[leaf]
		var mm := mi.multimesh
		mm.visible_instance_count = list.size()
		for i in list.size():
			var l: Dictionary = list[i]
			var k: float = l.scale * LEAF_PX
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(k, k, k)), l.pos))
			var fade := clampf((LIFE + FADE - l.age) / FADE, 0.0, 1.0)
			mm.set_instance_custom_data(i, Color(0.0, l.row * 14.0, l.spin, fade))
			mm.set_instance_color(i, world.get_light(l.pos))
