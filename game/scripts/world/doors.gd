class_name Doors
## Terraria's doors in 3D: 1 block wide and 2 tall (the player is 2 blocks
## tall here, Terraria's 3). A door is two cells: the bottom holds the door's
## block (one per style, with a closed and an open twin: "door" names the open
## one, "door_closed" the closed one) and the top a shared door_top /
## door_top_open block. Closed doors are solid; open ones aren't.
##
## The door is drawn from the bottom cell as the open-door art (Terraria's
## Tiles_11, the door seen face on; frame 0 has its hinge on the left, frame 1
## on the right) pushed THICKNESS deep and stretched to 1 x 2 blocks, each of
## its voxels one colour (the voxel methods' "one colour per voxel" rule: no
## dark outline wrapping round its edges). Closed,
## it stands across the middle of its block; open, it has swung a quarter turn
## about its hinge, away from whoever opened it, into the next block.
##
## State lives in Game.block_rotations at the bottom cell:
##   bits 0-1  facing: quarter turns of the door's front (+z), toward the placer
##   bit 2     hinge: 0 on the left of the front, 1 on the right
##   bit 3     swing: 0 opens toward the front, 1 toward the back

const THICKNESS := 3.0 / 16.0
const HEIGHT := 2
const HINGE_BIT := 4
const SWING_BIT := 8
const SWING_TIME := 0.15

## Recent swings, so a rebuilt door model turns from where the old one was:
## "x,y,z" -> {from: angle, at: msec}
static var _swings := {}
static var _meshes := {}  # "id:hinge" -> ArrayMesh
static var _materials := {}  # "id:hinge" -> ShaderMaterial
static var _sprites := {}  # "id:hinge" -> Image


static func is_door(d: Dictionary) -> bool:
	return d.has("door") or d.has("door_closed")


static func is_part(d: Dictionary) -> bool:
	return is_door(d) or d.get("door_top", false)


static func is_open(d: Dictionary) -> bool:
	return d.has("door_closed")


## The bottom cell of the door at `p` (p itself unless it's a top half).
static func bottom(world: VoxelWorld, p: Vector3i) -> Vector3i:
	if Data.block(world.get_block(p)).get("door_top", false):
		return p + Vector3i.DOWN
	return p


static func facing(state: int) -> int:
	return state & 3


static func hinge(state: int) -> int:
	return 1 if state & HINGE_BIT else 0


static func swing(state: int) -> int:
	return 1 if state & SWING_BIT else 0


## The hinge's x in the door's own frame (block centre at 0, front +z): just
## inside the block's edge, so the open door stays clear of the wall beside it.
static func hinge_x(state: int) -> float:
	return (0.5 - THICKNESS * 0.5) * (1.0 if hinge(state) == 1 else -1.0)


## The door panel's turn about its hinge: none when closed; open, a quarter
## turn that sends the free edge toward the front (swing 0) or the back.
static func angle(state: int, open: bool) -> float:
	if not open:
		return 0.0
	var a := PI * 0.5 * (1.0 if hinge(state) == 1 else -1.0)
	return a if swing(state) == 0 else -a


## The panel's box in the door's own frame (block bottom centre at 0).
static func local_box(state: int, open: bool) -> AABB:
	var t := THICKNESS
	if not open:
		return AABB(Vector3(-0.5, 0, -t * 0.5), Vector3(1, HEIGHT, t))
	var hx := hinge_x(state)
	var z0 := -t * 0.5 if swing(state) == 0 else -(1.0 - t * 0.5)
	return AABB(Vector3(hx - t * 0.5, 0, z0), Vector3(t, HEIGHT, 1.0))


## The panel's box in the world for a door whose bottom cell is `p`.
static func world_box(p: Vector3i, state: int, open: bool) -> AABB:
	var b := local_box(state, open)
	var turn := Basis(Vector3.UP, facing(state) * PI * 0.5)
	var out := AABB(turn * b.position, Vector3.ZERO)
	for i in 8:
		out = out.expand(turn * b.get_endpoint(i))
	out.position += Vector3(p) + Vector3(0.5, 0, 0.5)
	return out


## The box the block highlight outlines at `cell`: a door's panel (both
## halves), else the cell.
static func outline(game: Game, cell: Vector3i) -> AABB:
	if not is_part(Data.block(game.world.get_block(cell))):
		return AABB(Vector3(cell), Vector3.ONE)
	var p := bottom(game.world, cell)
	return world_box(p, game.block_rotation(p), is_open(Data.block(game.world.get_block(p))))


## Where an open door reaches: the block beside its own on the swing side.
static func swing_cell(p: Vector3i, state: int) -> Vector3i:
	var front := Vector3(Player.WALL_NORMALS[facing(state)])
	var dir := front if swing(state) == 0 else -front
	return p + Vector3i(roundi(dir.x), 0, roundi(dir.z))


# ------------------------------------------------------------------ world

## Puts a door (closed, block `id`) at `p` and the top half above it.
static func place(game: Game, p: Vector3i, id: int, state: int) -> void:
	game.world.set_block(p, id)
	game.world.set_block(p + Vector3i.UP, Data.block_id("door_top"))
	game.block_rotations[Chests.key(p)] = state


## Places a door from the player's hotbar on the block face they aim at.
## Returns false if it doesn't fit: both cells must be free, the floor solid
## and nobody standing in the way.
static func place_from_player(game: Game, player: Player, p: Vector3i, id: int) -> bool:
	var w := game.world
	for q in [p, p + Vector3i.UP]:
		var b := w.get_block(q)
		if b != 0 and Data.kind_of(b) != "tall_grass":
			return false
		if player.overlaps_block(q) or game.any_npc_in_block(q):
			return false
	if not w.is_solid(p + Vector3i.DOWN):
		return false
	# Front toward the player; hinge on the side of the block they aimed at.
	var face := posmod(roundi(player.yaw() / (PI * 0.5)), 4)
	var aim := player.aim_point()
	var right := Basis(Vector3.UP, face * PI * 0.5) * Vector3.RIGHT
	var side := (aim - (Vector3(p) + Vector3(0.5, 0, 0.5))).dot(right)
	place(game, p, id, face | (HINGE_BIT if side > 0.0 else 0))
	return true


## Opens or closes the door at `p` (either half) for someone at `from`. An
## open door swings away from them; if that side is blocked it swings the other
## way. A door won't close on someone standing in it. Returns true if it moved.
static func toggle(game: Game, p: Vector3i, from: Vector3) -> bool:
	var w := game.world
	p = bottom(w, p)
	var d := Data.block(w.get_block(p))
	if not is_door(d):
		return false
	var key := Chests.key(p)
	var state := game.block_rotation(p)
	var c := Vector3(p) + Vector3(0.5, 0, 0.5)
	if is_open(d):
		for q in [p, p + Vector3i.UP]:
			if game.player.overlaps_block(q) or game.any_npc_in_block(q):
				return false
		_swings[key] = {"from": angle(state, true), "at": Time.get_ticks_msec()}
		w.set_block(p, Data.block_id(d.door_closed))
		w.set_block(p + Vector3i.UP, Data.block_id("door_top"))
		Audio.play_at("Door_Closed", c + Vector3(0, 1, 0))
		return true
	var front := Vector3(Player.WALL_NORMALS[facing(state)])
	var away := 1 if (from - c).dot(front) > 0.0 else 0
	for s in [away, 1 - away]:
		var opened := (state & ~SWING_BIT) | (SWING_BIT if s == 1 else 0)
		var q := swing_cell(p, opened)
		if w.is_solid(q) or w.is_solid(q + Vector3i.UP):
			continue
		_swings[key] = {"from": 0.0, "at": Time.get_ticks_msec()}
		game.block_rotations[key] = opened
		w.set_block(p, Data.block_id(d.door))
		w.set_block(p + Vector3i.UP, Data.block_id("door_top_open"))
		Audio.play_at("Door_Opened", c + Vector3(0, 1, 0))
		return true
	return false


## Like VoxelWorld.raycast, but open doors are hit only on their panel (half
## of which reaches into the next block): the rest of the doorway lets the ray
## through to what's behind. `open_doors` are the bottom cells of the open
## doors around (BlockModels.open_doors).
static func raycast(game: Game, origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var w := game.world
	dir = dir.normalized()
	# The nearest open door panel on the ray.
	var best := {}
	for p in game.block_models.open_doors.values():
		var d := Data.block(w.get_block(p))
		if not is_door(d) or not is_open(d) or (Vector3(p) - origin).length() > max_dist + 2.0:
			continue
		var r = _ray_box(origin, dir, world_box(p, game.block_rotation(p), true))
		if r != null and r[0] <= max_dist and (best.is_empty() or r[0] < best.distance):
			var at: Vector3 = origin + dir * r[0]
			var normal := Vector3i.ZERO
			normal[r[1]] = -1 if dir[r[1]] > 0.0 else 1
			best = {"block": p + (Vector3i.UP if at.y >= p.y + 1 else Vector3i.ZERO), "normal": normal,
					"id": w.get_block(p), "distance": r[0]}
	# The first block that isn't an open doorway.
	var travelled := 0.0
	var start := origin
	for _i in 8:
		var hit := w.raycast(start, dir, max_dist - travelled)
		if hit.is_empty():
			break
		hit.distance = float(hit.distance) + travelled
		var bottom_cell := bottom(w, hit.block)
		if not is_part(Data.block(int(hit.id))) or not is_open(Data.block(w.get_block(bottom_cell))):
			if best.is_empty() or hit.distance < best.distance:
				return hit
			break
		# An open doorway: carry on from where the ray leaves it.
		var out = _ray_exit(origin, dir, AABB(Vector3(hit.block), Vector3.ONE))
		if out == null:
			break
		travelled = float(out) + 0.001
		start = origin + dir * travelled
		if travelled >= max_dist:
			break
	return best


## [distance along the ray to where it enters `box`, axis it enters through],
## or null.
static func _ray_box(o: Vector3, d: Vector3, box: AABB):
	var t0 := 0.0
	var t1 := INF
	var axis := 0
	for i in 3:
		if absf(d[i]) < 1e-8:
			if o[i] < box.position[i] or o[i] > box.end[i]:
				return null
			continue
		var a := (box.position[i] - o[i]) / d[i]
		var b := (box.end[i] - o[i]) / d[i]
		if minf(a, b) > t0:
			t0 = minf(a, b)
			axis = i
		t1 = minf(t1, maxf(a, b))
	return [t0, axis] if t0 <= t1 else null


## Distance along the ray to where it leaves `box`, or null.
static func _ray_exit(o: Vector3, d: Vector3, box: AABB):
	var t1 := INF
	for i in 3:
		if absf(d[i]) < 1e-8:
			continue
		t1 = minf(t1, maxf((box.position[i] - o[i]) / d[i], (box.end[i] - o[i]) / d[i]))
	return t1 if t1 < INF else null


## Breaking either half takes both; the caller handles the bottom cell (and
## its drop). Returns the bottom cell.
static func break_top(game: Game, p: Vector3i) -> Vector3i:
	var b := bottom(game.world, p)
	if not is_door(Data.block(game.world.get_block(b))):
		return p  # a top half on its own
	var top := b + Vector3i.UP
	if Data.block(game.world.get_block(top)).get("door_top", false):
		game.world.set_block(top, 0)
	_swings.erase(Chests.key(b))
	return b


# ------------------------------------------------------------------ model

## The door's model at its bottom cell: a root turned to the door's facing,
## a pivot on the hinge and the panel mesh. Turns into place if it just moved.
static func make_node(block_id: int, state: int, key := "") -> Node3D:
	var open := is_open(Data.block(block_id))
	var root := Node3D.new()
	root.rotation.y = facing(state) * PI * 0.5
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position.x = hinge_x(state)
	pivot.rotation.y = angle(state, open)
	root.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.name = "Panel"
	mi.mesh = mesh(block_id, hinge(state))
	mi.material_override = material(block_id, hinge(state))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.x = -hinge_x(state)
	pivot.add_child(mi)
	if key != "" and _swings.has(key):
		var s: Dictionary = _swings[key]
		if Time.get_ticks_msec() - int(s.at) < 1000:
			root.set_meta("swing_from", float(s.from))
		_swings.erase(key)
	return root


## Starts the swing of a door model made by make_node (once it's in the tree).
static func animate(root: Node3D) -> void:
	if not root.has_meta("swing_from"):
		return
	var pivot: Node3D = root.get_node("Pivot")
	var to := pivot.rotation.y
	pivot.rotation.y = float(root.get_meta("swing_from"))
	root.remove_meta("swing_from")
	root.create_tween().tween_property(pivot, "rotation:y", to, SWING_TIME).set_trans(Tween.TRANS_SINE)


static func set_light(root: Node3D, light: Color) -> void:
	(root.get_node("Pivot/Panel") as MeshInstance3D).set_instance_shader_parameter("light", light)


## The art for a door block and hinge side, cropped to the door: Terraria's
## frames leave transparent columns beside it (where the door frame would be),
## which would show as a gap down the side of the doorway.
static func _sprite(block_id: int, hinge_side: int) -> Image:
	var key := "%d:%d" % [block_id, hinge_side]
	if not _sprites.has(key):
		var d := Data.block(block_id)
		var sprites: Array = d.get("sprites", [d.sprite])
		var img: Image = sprites[hinge_side % sprites.size()]
		_sprites[key] = img.get_region(img.get_used_rect())
	return _sprites[key]


## The panel: the door art pushed THICKNESS deep, stretched to 1 x HEIGHT,
## centred on x, bottom at 0, its middle on z = 0.
static func mesh(block_id: int, hinge_side: int) -> ArrayMesh:
	var key := "%d:%d" % [block_id, hinge_side]
	if not _meshes.has(key):
		var art := _art(block_id, hinge_side)
		var depth := _depth(art)
		var fit := Basis.from_scale(Vector3(1.0 / art.get_width(), float(HEIGHT) / art.get_height(), THICKNESS / depth))
		_meshes[key] = BlockModelMesh.transformed(panel(block_id, hinge_side), Transform3D(fit, Vector3.ZERO))
	return _meshes[key]


## The panel before it's fitted to the doorway: one unit per art pixel, the
## art pushed through, every voxel one colour.
static func panel(block_id: int, hinge_side: int) -> ArrayMesh:
	var art := _art(block_id, hinge_side)
	var o := {"depth": _depth(art), "noise": "none", "strength": 0.0, "seed": 0, "bevel": "none", "bevel_size": 1}
	return TunedModels.one_color_mesh(BlockModelMesh._extrude(art, 1.0, o), true, art, 1.0)


static func _art(block_id: int, hinge_side: int) -> Image:
	var img := _sprite(block_id, hinge_side)
	return PixelArt.downsample(img, PixelArt.detect_scale(img))


static func _depth(art: Image) -> int:
	return maxi(1, roundi(THICKNESS * art.get_width()))


static func material(block_id: int, hinge_side: int) -> ShaderMaterial:
	var key := "%d:%d" % [block_id, hinge_side]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/block_model.gdshader")
		# Voxel colours (one a voxel), not the sprite.
		m.set_shader_parameter("textured", false)
		_materials[key] = m
	return _materials[key]


## Every door material, for the sky light (BlockModels.set_sky).
static func materials() -> Array:
	return _materials.values()
