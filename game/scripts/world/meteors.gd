class_name Meteors
extends RefCounted
## Terraria's meteorite landings (WorldGen.dropMeteor and WorldGen.meteor,
## Main.HandleMeteorFall). Beating the Eater of Worlds or the Brain of
## Cthulhu sends one for sure the first time and 1 time in 2 after that; once
## either is beaten, every dusk has a 1 in 50 chance too. It lands at midnight
## (at once if that's past), somewhere out of sight on solid ground away from
## the spawn point, and carves a crater of Meteorite: a ball of it with a bowl
## hollowed out of its top, and odd bits scattered round it.
##
## The crater is Terraria's, its sizes times SCALE: Terraria's own sizes in 3D
## would be a ball of some 4000 Meteorite, against the 400 to 600 of its 2D
## crater. At 0.4 a crater holds about 800.

## Terraria's crater sizes (tiles) to blocks.
const SCALE := 0.4
## Night ticks to midnight (Terraria's 16200 of 32400).
const MIDNIGHT := 16200.0
## Terraria's first Meteorite count limit: past 400 above the surface on a
## small world (4200 tiles wide, more on wider ones) no more land. That's about
## 0.8 of its craters; here 0.8 of ours, on a 768 block wide world.
const ORE_CAP := 670
## Terraria counts Meteorite above its surface line, under the hills; here the
## surface base, less a crater's depth.
const CAP_DEPTH := 10
## Terraria's edge margin (150 tiles of 4200) and spawn clearance (8% of the
## world's width), as shares of the width.
const EDGE := 150.0 / 4200.0
const SPAWN_CLEAR := 0.08
## Its 30 x 30 tile ground check, and the 600 of its 900 tiles that must be
## solid at first (half a tile less each spot that isn't); it gives up below
## 100. Here a cube, the score taken as a share of Terraria's 900.
const GROUND_HALF := 6
const GROUND_START := 600.0
const GROUND_STEP := 0.5
const GROUND_MIN := 100.0
## The box round the spot that must hold no NPC, chest, altar, Dungeon brick...
## (Terraria's 35 tiles).
const CLEAR_HALF := 14
## Spot tries per frame and Meteorite-count layers per frame (a search can
## take thousands of tries; Terraria's runs them all in one tick).
const TRIES_PER_FRAME := 32
const COUNT_CELLS_PER_FRAME := 6000000
const NO_SPOT := Vector3i(-1, -1, -1)
## Blocks that keep a meteorite away (Terraria's WorldGen.meteor: chests,
## Dungeon brick, altars, Lihzahrd brick, mannequins, hat racks, fallen logs,
## pylons). Chests (and dressers and trash cans, which hold things too) and
## the Dungeon are found by their kind, these by name.
const KEEP_AWAY := ["demon_altar", "crimson_altar", "fallen_log", "lihzahrd_brick", "mannequin", "womannequin", "hat_rack"]

var game
## A meteorite is coming tonight (Terraria's WorldGen.spawnMeteor).
var pending := false
## The landing under way: {phase: "count" | "search", ...}.
var _drop := {}
## Where the last landing came down (NO_SPOT if it couldn't).
var _drop_result := NO_SPOT
var _keep_away := PackedInt32Array()
## Per block id: 1 solid ground, -99 cloud or Sunplate (Terraria's: +1 and
## -100), 0 the rest.
var _ground_weight := PackedInt32Array()


func _init(g) -> void:
	game = g


## The Eater of Worlds or the Brain of Cthulhu beaten (NPC.DoDeathEvents):
## the first time a meteorite for sure, after that 1 time in 2.
## `beaten_before`: either had been beaten before this one.
func boss_beaten(beaten_before: bool) -> void:
	if not _natural():
		return
	if not beaten_before or randi() % 2 == 0:
		pending = true


## Dusk (Main.UpdateTime_StartNight): 1 night in 50 once either is beaten.
func dusk() -> void:
	if _natural() and randi() % 50 == 0 and boss2_beaten():
		pending = true


## Terraria's NPC.downedBoss2: the Eater of Worlds or the Brain of Cthulhu.
func boss2_beaten() -> bool:
	return game.defeated_bosses.has("EaterofWorldsHead") or game.defeated_bosses.has("BrainofCthulhu")


## Not in the test world, unless its natural spawns are on (F7).
func _natural() -> bool:
	return game.test_world == null or game.test_world.natural_spawns


## Each frame: past midnight with one coming, it starts on its way down; a
## landing under way goes on.
func update(_delta: float) -> void:
	if _drop.is_empty():
		if pending and not game.sky.is_day and game.sky.time > MIDNIGHT:
			pending = false
			start_drop()
		return
	step(TRIES_PER_FRAME)


## Starts a landing (Terraria's dropMeteor): first the Meteorite count, then
## the search for a spot.
func start_drop() -> void:
	_drop = {"phase": "count", "y": game.surface_level - CAP_DEPTH, "found": 0, "tries": 0,
			"threshold": GROUND_START}


## Lands one now, the whole search at once: where (NO_SPOT if none).
func drop_now() -> Vector3i:
	start_drop()
	while not step(1 << 30):
		pass
	return _drop_result


## Goes on with the landing, up to `tries` spots; true once it's over.
func step(tries: int) -> bool:
	if _drop.is_empty():
		return true
	var size: Vector3i = game.world.get_size()
	if _drop.phase == "count":
		if not _count_step(size, tries >= 1 << 30):
			return false
		var cap := int(ORE_CAP * size.x / float(Game.WORLD_SIZES.small.x))
		if int(_drop.found) > cap:
			return _finish(NO_SPOT)
		_drop.phase = "search"
	for i in tries:
		var at := _try_spot(size)
		if at != NO_SPOT:
			return _finish(at)
		if float(_drop.threshold) < GROUND_MIN or int(_drop.tries) >= 5 * size.x:
			return _finish(NO_SPOT)
	return false


func _finish(at: Vector3i) -> bool:
	_drop = {}
	_drop_result = at
	return true


## Counts the Meteorite above the surface a few layers at a time (all at once
## with `all`); true when it's done or past the cap.
func _count_step(size: Vector3i, all: bool) -> bool:
	var id := PackedInt32Array([Data.block_id("meteorite")])
	var cap := int(ORE_CAP * size.x / float(Game.WORLD_SIZES.small.x))
	# Odd slabs: find_blocks takes a box as its centre and a half-size each way.
	var half_y := maxi(0, (COUNT_CELLS_PER_FRAME / maxi(size.x * size.z, 1) - 1) / 2)
	while int(_drop.y) < size.y:
		var center := Vector3i(size.x / 2, maxi(int(_drop.y), 0) + half_y, size.z / 2)
		var found: PackedInt32Array = game.world.find_blocks(center, Vector3i(size.x / 2, half_y, size.z / 2), id, cap + 2 - int(_drop.found))
		_drop.found = int(_drop.found) + found.size() / 3
		_drop.y = center.y + half_y + 1
		if int(_drop.found) > cap:
			return true
		if not all:
			return int(_drop.y) >= size.y
	return true


## One of Terraria's tries: a random column clear of the edges and the spawn
## point, its ground, how solid the ground round it is against the threshold
## (which comes down a little each time it isn't), then WorldGen.meteor's
## checks. The landing spot, or NO_SPOT.
func _try_spot(size: Vector3i) -> Vector3i:
	_drop.tries = int(_drop.tries) + 1
	var margin := maxi(int(size.x * EDGE), CLEAR_HALF + 2)
	var spawn: Vector3i = game.world.get_spawn()
	var x := 0
	var z := 0
	for i in 100:
		x = randi_range(margin, size.x - 1 - margin)
		z = randi_range(margin, size.z - 1 - margin)
		if Vector2(x - spawn.x, z - spawn.z).length() >= SPAWN_CLEAR * size.x:
			break
	if Vector2(x - spawn.x, z - spawn.z).length() < SPAWN_CLEAR * size.x:
		return NO_SPOT
	var y := ground_y(x, z)
	if y < 0:
		return NO_SPOT
	var at := Vector3i(x, y, z)
	if ground_score(at) < float(_drop.threshold):
		_drop.threshold = float(_drop.threshold) - GROUND_STEP
		return NO_SPOT
	if not can_land(at):
		return NO_SPOT
	land(at)
	return at


## The top of the ground in a column: the highest solid block that isn't part
## of a tree (Terraria's trees aren't solid); -1 if none.
func ground_y(x: int, z: int) -> int:
	var y: int = game.world.surface_y(x, z)
	while y >= 0:
		var b := Data.block(game.world.get_block(Vector3i(x, y, z)))
		if not b.get("trunk", false) and not b.get("sun_through", false) and game.world.is_solid(Vector3i(x, y, z)):
			return y
		y -= 1
	return -1


## Terraria's ground score round `at`, scaled to its 30 x 30: +1 a solid
## block, -1 a cell of liquid, -99 a cloud or Sunplate block (no landing on
## floating islands).
func ground_score(at: Vector3i) -> float:
	if _ground_weight.is_empty():
		_ground_weight.resize(Data.blocks.size())
		for id in range(1, Data.blocks.size()):
			var b: Dictionary = Data.blocks[id]
			if not b.get("solid", true):
				continue
			var tile := int(b.get("tile_id", -1))
			# Terraria's TileID.Sets.Clouds (cloud, rain cloud, snow cloud) and Sunplate.
			_ground_weight[id] = -99 if tile in [189, 196, 460, 202] else 1
	var counts: PackedInt32Array = game.world.count_blocks(at, GROUND_HALF)
	var score := 0
	for id in mini(counts.size(), _ground_weight.size()):
		if counts[id] != 0:
			score += counts[id] * _ground_weight[id]
	# Liquid, every other cell each way (8 cells each).
	for dx in range(-GROUND_HALF, GROUND_HALF + 1, 2):
		for dy in range(-GROUND_HALF, GROUND_HALF + 1, 2):
			for dz in range(-GROUND_HALF, GROUND_HALF + 1, 2):
				var q := at + Vector3i(dx, dy, dz)
				if game.world.get_liquid(q).y > 0 and not game.world.is_solid(q):
					score -= 8
	var side := 2 * GROUND_HALF + 1
	return score * 900.0 / float(side * side * side)


## WorldGen.meteor's checks: inside the world, out of sight of the player (past
## what's drawn), no NPC near (critters and town NPCs too), and no chest,
## Dungeon brick, altar... in the box round it.
func can_land(at: Vector3i) -> bool:
	var size: Vector3i = game.world.get_size()
	if at.x < CLEAR_HALF or at.z < CLEAR_HALF or at.x >= size.x - CLEAR_HALF or at.z >= size.z - CLEAR_HALF \
			or at.y < CLEAR_HALF or at.y >= size.y - CLEAR_HALF:
		return false
	var p: Vector3 = game.player.global_position
	var sight: float = game.renderer.render_distance * ChunkRenderer.CHUNK + CLEAR_HALF
	if Vector2(p.x - at.x, p.z - at.z).length() < sight:
		return false
	var box := AABB(Vector3(at - Vector3i.ONE * CLEAR_HALF), Vector3.ONE * (2 * CLEAR_HALF + 1))
	for npc in game.npcs():
		if box.has_point(npc.global_position):
			return false
	return not game.world.any_block_near(at, Vector3i.ONE * CLEAR_HALF, _keep_away_ids())


func _keep_away_ids() -> PackedInt32Array:
	if _keep_away.is_empty():
		for id in range(1, Data.blocks.size()):
			var b: Dictionary = Data.blocks[id]
			var n: String = b.name
			if b.get("biome") == "dungeon" or n in KEEP_AWAY or n.contains("pylon") or b.get("interact") in ["chest", "locked_chest"]:
				_keep_away.append(id)
	return _keep_away


## WorldGen.meteor's crater round `at` (the top of the ground), each of its
## sizes times SCALE, its upward cut-offs counted the other way (its y grows
## downward): a ball of Meteorite (any other block in it goes), a bowl
## hollowed out of it, trees and liquid cleared round it, lone bits taken
## away, then two wider sprinklings of Meteorite. Nothing drops.
func land(at: Vector3i) -> void:
	var w: VoxelWorld = game.world
	var ore := Data.block_id("meteorite")
	# The ball.
	var r := randi_range(17, 22) * SCALE
	for q in _cells(at, r):
		var d := Vector3(q - at)
		if d.y < (5 - randi_range(-2, 2)) * SCALE and d.length() < 0.9 * r + randi_range(-4, 4) * SCALE:
			var id := w.get_block(q)
			if id == 0:
				continue
			var b := Data.block(id)
			if Game.blastproof(b):
				continue
			if b.get("trunk", false):
				_fell(q)
			elif w.is_solid(q) and b.get("render", "cube") == "cube":
				_place(q, ore)
			else:
				_clear(q)
	# The bowl.
	r = randi_range(8, 13) * SCALE
	for q in _cells(at, r):
		var d := Vector3(q - at)
		if d.y < (4 - randi_range(-2, 2)) * SCALE and d.length() < 0.8 * r + randi_range(-3, 3) * SCALE \
				and w.get_block(q) == ore:
			_clear(q)
	# Trees and liquid round it, then Meteorite with nothing solid beside it.
	r = randi_range(25, 34) * SCALE
	var cells := _cells(at, r)
	for q in cells:
		if Vector3(q - at).length() < 0.7 * r:
			var b := Data.block(w.get_block(q))
			if b.get("trunk", false):
				_fell(q)
			elif b.get("on_break") == "cactus":
				game.break_block(q, false, true)
			if w.get_liquid(q).y > 0:
				w.set_liquid(q, 0, 0)
	for q in cells:
		if w.get_block(q) == ore and not _held(q):
			_clear(q)
	# The sprinklings: 1 in 10 of the ground a little wider, 1 in 20 wider still.
	r = randi_range(23, 31) * SCALE
	for q in _cells(at, r):
		var d := Vector3(q - at)
		if d.y < (3 - randi_range(-3, 3)) * SCALE and randi() % 10 == 0 and d.length() < 0.8 * r:
			_sprinkle(q, ore)
	r = randi_range(30, 37) * SCALE
	for q in _cells(at, r):
		var d := Vector3(q - at)
		if d.y < -randi_range(-2, 2) * SCALE and randi() % 20 == 0 and d.length() < 0.85 * r:
			_sprinkle(q, ore)
	game.decorations.refresh()
	game.far_trees.invalidate()
	game.message("A meteorite has landed!", Game.WORLD_COLOR)


## The cells of the cube of `r` round `at`, top down.
static func _cells(at: Vector3i, r: float) -> Array[Vector3i]:
	var n := ceili(r)
	var out: Array[Vector3i] = []
	for y in range(n, -n - 1, -1):
		for z in range(-n, n + 1):
			for x in range(-n, n + 1):
				out.append(at + Vector3i(x, y, z))
	return out


func _sprinkle(q: Vector3i, ore: int) -> void:
	var id: int = game.world.get_block(q)
	var b := Data.block(id)
	if id != 0 and game.world.is_solid(q) and b.get("render", "cube") == "cube" and not Game.blastproof(b) \
			and not b.get("trunk", false):
		_place(q, ore)


## Meteorite in place of the block at `q`, its hammered shape, actuation and
## any liquid gone.
func _place(q: Vector3i, id: int) -> void:
	var w: VoxelWorld = game.world
	w.set_block(q, id)
	if w.get_liquid(q).y > 0:
		w.set_liquid(q, 0, 0)
	if w.get_shape(q) != 0:
		w.set_shape(q, 0)
	if w.is_inactive(q):
		w.set_inactive(q, false)


func _clear(q: Vector3i) -> void:
	game.world.set_block(q, 0)
	game.world.set_inactive(q, false)
	game.block_rotations.erase(Chests.key(q))
	game.signs.erase(Chests.key(q))


## A tree in the way comes down whole, with nothing dropped.
func _fell(q: Vector3i) -> void:
	game.break_block(q, false, true)


## Something solid beside it (Terraria's: left, right, above or below).
func _held(q: Vector3i) -> bool:
	for n in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
		if game.world.is_solid(q + n):
			return true
	return false


func save_state() -> Dictionary:
	return {"pending": pending}


func load_state(d: Dictionary) -> void:
	pending = d.get("pending", false)
