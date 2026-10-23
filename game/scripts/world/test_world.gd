class_name TestWorld
extends Node3D
## A flat sandbox for trying everything: chests holding every item, NPC
## spawners in a walled arena, target dummies, a liquid lab (pool, waterfalls,
## hammer springs, lava pit), a block gallery, an ore wall, a fall-test tower and
## a dark room. Debug hotkeys: F1 help, F2 god mode, F3 fly, F4 day/night,
## F5 kill enemies, F6 clear drops, F7 natural spawns, F8 heal.
##
## Its kinds (KINDS): the whole thing ("all", the one the tests walk), or one
## theme of it - NPCs, wiring (a wiring lab of its own), biomes, building -
## each with the spawn plaza and the chests of every item.

const SIZE := Vector3i(256, 128, 256)
const GROUND := 64  # top grass block; you stand at GROUND + 1
## Kind -> its name in the menu and on the plaza.
const KINDS := {"all": "Test World", "npc": "NPC Test World", "wiring": "Wiring Test World",
		"biome": "Biome Test World", "building": "Building Test World"}
const SPAWNER_INTERVAL := 3.0
const SPAWNER_MAX_ALIVE := 3
const CATEGORIES := [
	["Weapons", ["melee", "ranged", "magic", "thrown"]],
	["Tools", ["tool", "bucket", "tool_use", "hook", "fishing_pole"]],
	["Ammo", ["ammo"]],
	["Potions & Summons", ["consumable", "summon"]],
	["Accessories", ["accessory"]],
	["Armor", ["armor"]],
	["Blocks", ["block"]],
	["Materials", ["material"]],
	["Coins & Misc", []],
]
## The F1 help: [the themes a line is for ("" every kind), the line].
const HELP := [
	["", "F1  this help"],
	["", "F2  god mode (no damage, endless air and mana)"],
	["", "F3  fly (Space up, Shift down)"],
	["", "F4  day / night"],
	["", "F5  kill all enemies      F6  clear dropped items"],
	["", "F7  natural enemy spawns on/off      F8  heal"],
	["", "North: every item in chests, crafting by spawn"],
	["npc", "Spawners: right-click spawns one, Shift+right-click toggles auto-spawn"],
	["npc", "East: enemy arena   East of it: the town - the Guide, Merchant, Nurse, Arms Dealer, Dryad,"],
	["npc", "  Demolitionist, Goblin Tinkerer and Angler (right-click to talk)"],
	["npc", "West of the gallery: the critter pen (a spawner for each critter; catch them with a Bug Net)"],
	["npc biome", "Far west: the Dungeon (the Old Man by its door)"],
	["building", "West: water, waterfalls, hammer springs, lava   South: blocks, ores, tower (rope and chain)"],
	["building", "North of the trees: forest plants, a pond and vines; east of them a furnished house and hammered blocks"],
	["building", "South-west: platforms   Hammer: reshapes blocks (half, ramp, upside-down ramp)"],
	["biome", "North-west of the plaza: the fishing pond (deep enough for full fishing power) with a dock"],
	["biome", "A fishing spot in every biome (signposted): Snow, Desert, Jungle (and honey), Corruption, Crimson,"],
	["biome", "  the ocean (far north), the Dungeon (west), lava, the mushroom cavern, underground, the sky"],
	["biome", "North: Snow (north-west), Desert, Jungle (north-east)   South-west / south-east: Corruption, Crimson"],
	["biome", "South-east, down the shaft: the Glowing Mushroom biome   Up (F3): floating islands"],
	["biome", "North-east, down the shaft in the Jungle: a bee hive (honey, honey blocks, the larva)"],
	["wiring", "South: the wiring lab - levers, pressure plates, actuators, timers, traps, teleporters,"],
	["wiring", "  a Junction Box, a Wire Bulb and a Pixel Box display (signposted). Hold a wrench to see the wires"],
]

var game: Game
## Which of KINDS this one is.
var kind := "all"
var natural_spawns := false
## "x,y,z" -> {pos: Vector3i, kind, auto, timer, alive: Array, sprite, label}
var spawners := {}
var _labels: Array = []  # [Vector3, text, font size]
var _dummies: Array = []  # Vector3i stand positions
var _blocks := PackedInt32Array()
var _liquids := PackedInt32Array()
var _shapes: Array = []  # [Vector3i, shape], applied once the blocks are in
var _status: Label
var _help: PanelContainer


# ------------------------------------------------------------------ building

func _id(name: String) -> int:
	return Data.block_id(name) if name != "" else 0


func _b(p: Vector3i, name: String) -> void:
	_blocks.append_array([p.x, p.y, p.z, _id(name)])


## A closed door (bottom cell `p`) facing Player.WALL_NORMALS[facing].
func _door(p: Vector3i, name: String, facing: int) -> void:
	_b(p, name)
	_b(p + Vector3i.UP, "door_top")
	game.block_rotations[Chests.key(p)] = facing


func _box(a: Vector3i, b: Vector3i, name: String) -> void:
	for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
				_b(Vector3i(x, y, z), name)


func _liquid_box(a: Vector3i, b: Vector3i, t: int) -> void:
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			for z in range(a.z, b.z + 1):
				_liquids.append_array([x, y, z, t, 63])


func _label(p: Vector3, text: String, size := 22) -> void:
	_labels.append([p, text, size])


## Builds the whole facility into a freshly generated flat world (before lighting
## and before the renderer starts). Chests and spawners are registered with the game.
func build() -> void:
	var w := game.world
	var c := Vector3i(SIZE.x / 2, GROUND + 1, SIZE.z / 2)
	w.set_spawn(c)
	var ground := GROUND

	# Spawn plaza with crafting stations and torches.
	_box(Vector3i(c.x - 5, ground, c.z - 5), Vector3i(c.x + 5, ground, c.z + 5), "gray_brick")
	for corner in [Vector3i(-5, 0, -5), Vector3i(5, 0, -5), Vector3i(-5, 0, 5), Vector3i(5, 0, 5)]:
		_b(c + corner, "torch")
	_b(c + Vector3i(-2, 0, -4), "work_bench")
	_b(c + Vector3i(0, 0, -4), "furnace")
	_b(c + Vector3i(2, 0, -4), "iron_anvil")
	_label(Vector3(c + Vector3i(0, 1, -4)) + Vector3(0.5, 0.6, 0.5), "Crafting stations")
	_label(Vector3(c) + Vector3(0.5, 3.2, 0.5), "%s - press F1 for help" % KINDS[kind], 26)

	_build_storage(c)
	if _has("npc"):
		_build_arena(c)
		_build_dummies(c)
		_build_critter_pen(c)
		_build_town(c)
	if _has("building"):
		_build_liquids(c)
		_build_gallery(c)
		_build_tower(c)
		_build_dark_room(c)
		_build_trees(c)
		_build_garden(c)
		_build_platforms(c)
		_build_house(c)
		_build_library(c)
		_build_hammered(c)
	if _has("biome"):
		_build_fishing(c)
		_build_fishing_rooms(c)
		_build_mushroom_cavern(c)
	if kind == "wiring":
		_build_wiring_lab(c)

	w.set_blocks_raw(_blocks)
	for sh in _shapes:
		w.set_shape(sh[0], sh[1])
	w.set_liquids_raw(_liquids)
	if _has("biome"):
		_build_islands(c)
		_build_evil(c)
		_build_biomes(c)
		_build_hive(c)
	if _has("biome") or _has("npc"):
		_build_dungeon(c)
	if _has("biome"):
		game.world.generate_mushroom_biome(c + MUSHROOM, 26, 41, false)
		_build_fishing_spots(c)
	w.relight_all()
	_blocks = PackedInt32Array()
	_liquids = PackedInt32Array()


## The wiring lab (the wiring test world), south of the plaza on a brick
## floor, each station signposted:
## - a lever wired to a door (red), torches (blue) and gemspark (green);
## - the seven pressure plates, each wired to a torch, with who sets it off;
## - a lever and a wall of stone with actuators;
## - timers: a 1 Second and a 1/4 Second one switched on, a 5 Second one off
##   (right-click to switch);
## - traps: a gray plate and a Dart Trap down a lane, an orange plate and a
##   boulder on actuated stone, a Geyser;
## - two Teleporters and the lever between them;
## - wires crossing at a Junction Box, each to its own torch;
## - a Wire Bulb on four levers, one a colour;
## - a 3 x 3 Pixel Box display: each of three levers is wired to a row (red)
##   and a column (blue), lighting the box where they cross;
## - a Projectile Pressure Pad wired to a torch.
func _build_wiring_lab(c: Vector3i) -> void:
	_box(c + Vector3i(-30, -1, 8), c + Vector3i(30, -1, 58), "gray_brick")
	var at := func(x: int, y: int, z: int) -> Vector3i: return c + Vector3i(x, y, z)
	var sign := func(x: float, z: float, text: String) -> void: _label(Vector3(c) + Vector3(x + 0.5, 3.0, z + 0.5), text, 18)
	# A lever: a door, torches, gemspark.
	_b(at.call(-28, 0, 12), "lever")
	_door(at.call(-20, 0, 12), "wooden_door", 0)
	for x in range(-26, -23):
		_b(at.call(x, 0, 14), "torch")
		_b(at.call(x, 0, 10), "ruby_gemspark_block")
	_wire(Wiring.RED, [at.call(-28, 0, 12), at.call(-20, 0, 12)])
	_wire(Wiring.BLUE, [at.call(-28, 0, 12), at.call(-28, 0, 14), at.call(-24, 0, 14)])
	_wire(Wiring.GREEN, [at.call(-28, 0, 12), at.call(-28, 0, 10), at.call(-24, 0, 10)])
	sign.call(-24, 12, "Lever: a door (red), torches (blue), gemspark (green)")
	# The pressure plates.
	var plates := [["red", "anyone"], ["green", "anyone"], ["gray", "you"], ["brown", "you"], ["blue", "you"], ["yellow", "not you"], ["orange", "you, once"]]
	for i in plates.size():
		var x := -28 + 4 * i
		_b(at.call(x, 0, 20), "%s_pressure_plate" % plates[i][0])
		_b(at.call(x, 0, 18), "torch")
		_wire(Wiring.RED, [at.call(x, 0, 20), at.call(x, 0, 18)])
		_label(Vector3(at.call(x, 0, 20)) + Vector3(0.5, 1.4, 0.5), "%s: %s" % [plates[i][0].capitalize(), plates[i][1]], 14)
	sign.call(-16, 19, "Pressure plates (each to a torch)")
	# Actuators.
	_b(at.call(0, 0, 22), "lever")
	for x in range(2, 7):
		for y in range(0, 3):
			_b(at.call(x, y, 20), "stone")
			_wire(Wiring.GREEN | Wiring.ACTUATOR, [at.call(x, y, 20)])
	_wire(Wiring.GREEN, [at.call(0, 0, 22), at.call(2, 0, 22), at.call(2, 0, 20)])
	sign.call(4, 22, "Actuators: the lever switches the wall")
	# Timers.
	_b(at.call(-28, 0, 28), "timer_1s_on")
	_b(at.call(-20, 0, 28), "timer_quarter_on")
	_b(at.call(-12, 0, 28), "timer_5s")
	for x in [-26, -25, -24, -18, -17, -16, -10, -9, -8]:
		_b(at.call(x, 0, 28), "torch")
	_wire(Wiring.RED, [at.call(-28, 0, 28), at.call(-24, 0, 28)])
	_wire(Wiring.RED, [at.call(-20, 0, 28), at.call(-16, 0, 28)])
	_wire(Wiring.RED, [at.call(-12, 0, 28), at.call(-8, 0, 28)])
	sign.call(-18, 28, "Timers: 1 s and 1/4 s on, 5 s off (right-click one)")
	# Traps.
	_b(at.call(-28, 0, 36), "gray_pressure_plate")
	_b(at.call(-14, 0, 36), "dart_trap")
	game.world.add_decoration("rotation", at.call(-14, 0, 36), 3)
	_wire(Wiring.YELLOW, [at.call(-28, 0, 36), at.call(-14, 0, 36)])
	_b(at.call(-8, 0, 36), "orange_pressure_plate")
	for y in [0, 1]:
		_b(at.call(-8, y, 39), "stone")
		_wire(Wiring.ACTUATOR, [at.call(-8, y, 39)])
	_b(at.call(-8, 2, 39), "boulder")
	_wire(Wiring.RED, [at.call(-8, 0, 36), at.call(-8, 0, 39), at.call(-8, 1, 39)])
	_b(at.call(-2, 0, 36), "geyser")
	sign.call(-20, 36, "Traps: a plate and a Dart Trap")
	sign.call(-6, 37, "a boulder on actuated stone; a Geyser (step on it)")
	# Teleporters.
	_b(at.call(4, 0, 36), "teleporter")
	_b(at.call(16, 0, 36), "teleporter")
	_b(at.call(10, 0, 38), "lever")
	_wire(Wiring.YELLOW, [at.call(10, 0, 38), at.call(4, 0, 38), at.call(4, 0, 36)])
	_wire(Wiring.YELLOW, [at.call(10, 0, 38), at.call(16, 0, 38), at.call(16, 0, 36)])
	sign.call(10, 36, "Teleporters: stand on one, flip the lever")
	# A Junction Box.
	_b(at.call(-22, 0, 44), "junction_box")
	_b(at.call(-28, 0, 44), "lever")
	_b(at.call(-22, 0, 50), "lever")
	_b(at.call(-16, 0, 44), "torch")
	_b(at.call(-22, 0, 40), "torch")
	_wire(Wiring.RED, [at.call(-28, 0, 44), at.call(-16, 0, 44)])
	_wire(Wiring.RED, [at.call(-22, 0, 50), at.call(-22, 0, 40)])
	sign.call(-22, 46, "Junction Box: crossing wires, each lever its own torch")
	# A Wire Bulb.
	_b(at.call(-4, 0, 44), "wire_bulb")
	var bulb_levers := [[-8, Wiring.RED], [-6, Wiring.BLUE], [-2, Wiring.GREEN], [0, Wiring.YELLOW]]
	for bl in bulb_levers:
		_b(at.call(bl[0], 0, 46), "lever")
		_wire(bl[1], [at.call(bl[0], 0, 46), at.call(bl[0], 0, 44) if bl[0] == -8 else at.call(-4, 0, 46), at.call(-4, 0, 44)])
	sign.call(-4, 45, "Wire Bulb: a lever for each colour")
	# The Pixel Box display (rows red, columns blue, crossing in the boxes).
	for x in range(14, 17):
		for y in range(1, 4):
			_b(at.call(x, y, 46), "pixel_box")
	_wire(Wiring.RED, [at.call(12, 1, 46), at.call(16, 1, 46)])
	_wire(Wiring.RED, [at.call(14, 2, 46), at.call(18, 2, 46)])
	_wire(Wiring.RED, [at.call(12, 3, 46), at.call(16, 3, 46)])
	_wire(Wiring.BLUE, [at.call(14, 0, 46), at.call(14, 3, 46)])
	_wire(Wiring.BLUE, [at.call(15, 1, 46), at.call(15, 4, 46)])
	_wire(Wiring.BLUE, [at.call(16, 0, 46), at.call(16, 3, 46)])
	_b(at.call(10, 0, 50), "lever")
	_b(at.call(20, 0, 50), "lever")
	_b(at.call(24, 0, 52), "lever")
	_wire(Wiring.RED, [at.call(10, 0, 50), at.call(10, 1, 50), at.call(12, 1, 50), at.call(12, 1, 46)])
	_wire(Wiring.BLUE, [at.call(10, 0, 50), at.call(14, 0, 50), at.call(14, 0, 46)])
	_wire(Wiring.RED, [at.call(20, 0, 50), at.call(20, 2, 50), at.call(18, 2, 50), at.call(18, 2, 46)])
	_wire(Wiring.BLUE, [at.call(20, 0, 50), at.call(20, 5, 50), at.call(15, 5, 50), at.call(15, 5, 46), at.call(15, 4, 46)])
	_wire(Wiring.RED, [at.call(24, 0, 52), at.call(24, 3, 52), at.call(12, 3, 52), at.call(12, 3, 46)])
	_wire(Wiring.BLUE, [at.call(24, 0, 52), at.call(16, 0, 52), at.call(16, 0, 46)])
	sign.call(15, 48, "Pixel Box display: each lever crosses a row and a column")
	# A Projectile Pressure Pad.
	_b(at.call(-28, 0, 54), "projectile_pressure_pad")
	_b(at.call(-28, 0, 52), "torch")
	_wire(Wiring.RED, [at.call(-28, 0, 54), at.call(-28, 0, 52)])
	sign.call(-26, 54, "Projectile Pressure Pad: shoot it")


## Wire of `bits` (colours, ACTUATOR) through `points`, straight from each to
## the next (as worldgen's: "wire" decorations the wiring loads).
func _wire(bits: int, points: Array) -> void:
	var p: Vector3i = points[0]
	var cells := [p]
	for q in points.slice(1):
		while p != q:
			for axis in 3:
				if p[axis] != q[axis]:
					p[axis] += signi(q[axis] - p[axis])
					break
			cells.append(p)
	for cell in cells:
		if bits & 15:
			game.world.add_decoration("wire", cell, bits & 15)
		if bits & Wiring.ACTUATOR:
			game.world.add_decoration("actuator", cell, 0)


## Whether this kind has the theme `theme` (the whole test world has all).
func _has(theme: String) -> bool:
	return kind == "all" or kind == theme


## Floating islands (the world generator's) above the plaza: a house island
## with a Skyware chest and a lake island, in the Space layer (harpies spawn
## there with natural spawns on). Fly up with F3.
const ISLAND_HOUSE := Vector3i(-14, 52, -16)
const ISLAND_LAKE := Vector3i(16, 56, -26)


func _build_islands(c: Vector3i) -> void:
	game.world.generate_island(c + ISLAND_HOUSE + Vector3i(0, -1, 0), 15, 1, 11)
	game.world.generate_island(c + ISLAND_LAKE + Vector3i(0, -1, 0), 10, 2, 12)
	_label(Vector3(c) + Vector3(0.5, 4.2, 0.5), "Floating islands above - F3 to fly", 22)


## A small Corruption and Crimson patch (the world generator's) south-west and
## south-east: chasms to Shadow Orbs, tunnels to a cavern of Crimson Hearts.
const CORRUPTION := Vector2i(-75, 70)
const CRIMSON := Vector2i(75, 70)


func _build_evil(c: Vector3i) -> void:
	game.world.generate_evil_patch(Vector2i(c.x, c.z) + CORRUPTION, 24, 1, 21)
	game.world.generate_evil_patch(Vector2i(c.x, c.z) + CRIMSON, 24, 2, 22)
	_label(Vector3(c.x + CORRUPTION.x * 0.6, GROUND + 3, c.z + CORRUPTION.y * 0.6), "Corruption", 26)
	_label(Vector3(c.x + CRIMSON.x * 0.6, GROUND + 3, c.z + CRIMSON.y * 0.6), "Crimson", 26)


## Small Snow, Desert and Jungle patches (the world generator's) north-west,
## north and north-east, with their blocks, trees, cacti and enemies.
const SNOW := Vector2i(-75, -70)
const DESERT := Vector2i(0, -90)
const JUNGLE := Vector2i(75, -70)
const BIOME_RADIUS := 22


func _build_biomes(c: Vector3i) -> void:
	for b in [[SNOW, 1, "Snow"], [DESERT, 2, "Desert"], [JUNGLE, 3, "Jungle"]]:
		var at: Vector2i = b[0]
		game.world.generate_biome_patch(Vector2i(c.x, c.z) + at, BIOME_RADIUS, b[1], 30 + b[1])
		_label(Vector3(c.x + at.x * 0.6, GROUND + 3, c.z + at.y * 0.6), b[2], 26)


## Under the Jungle patch: a bee hive (the world generator's, its balls 0.6
## the size), its honey and larva; a shaft with platforms down to the larva.
const HIVE := Vector3i(75, -26, -70)
## Where the hive's larva is (a fresh test world).
var hive_larva := Vector3i.ZERO


func _build_hive(c: Vector3i) -> void:
	var w := game.world
	hive_larva = w.generate_hive(c + HIVE, 51, 0.6)
	var s := hive_larva
	_blocks = PackedInt32Array()
	_liquids = PackedInt32Array()
	_box(Vector3i(s.x - 1, s.y + 3, s.z - 1), Vector3i(s.x + 1, GROUND, s.z + 1), "")
	for y in range(s.y + 3, GROUND + 1):
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				_liquids.append_array([s.x + dx, y, s.z + dz, 0, 0])
	for y in range(s.y + 6, GROUND, 4):
		_box(Vector3i(s.x - 1, y, s.z - 1), Vector3i(s.x + 1, y, s.z + 1), "wood_platform")
	_box(Vector3i(s.x - 2, GROUND, s.z - 2), Vector3i(s.x + 2, GROUND, s.z - 2), "rich_mahogany")
	w.set_blocks_raw(_blocks)
	w.set_liquids_raw(_liquids)
	_label(Vector3(s.x + 0.5, GROUND + 3, s.z + 0.5), "Bee hive below", 24)


func _build_storage(c: Vector3i) -> void:
	var z := c.z - 9
	_box(Vector3i(c.x - 16, GROUND, z - 2), Vector3i(c.x + 16, GROUND, z + 2), "gray_brick")
	_label(Vector3(c.x + 0.5, GROUND + 4.2, z + 0.5), "Every item", 28)
	var by_cat := {}
	for name in Data.items:
		var t: String = Data.item(name).get("type", "")
		var cat := "Coins & Misc"
		for cdef in CATEGORIES:
			if t in cdef[1]:
				cat = cdef[0]
		by_cat.get_or_add(cat, []).append(name)
	# Rows of eight chests (the arena starts east of them), going north.
	var n := 0
	for cdef in CATEGORIES:
		var names: Array = by_cat.get(cdef[0], [])
		names.sort()
		var chunk := 0
		while chunk * Chests.SIZE < names.size():
			var pos := Vector3i(c.x - 15 + (n % 8) * 3, GROUND + 1, z - (n / 8) * 4)
			if n % 8 == 0 and n > 0:
				_box(Vector3i(c.x - 16, GROUND, pos.z - 1), Vector3i(c.x + 7, GROUND, pos.z + 1), "gray_brick")
			_b(pos, "chest")
			game.chests.register_new(pos)
			var inv := game.chests.get_inventory(pos)
			for name in names.slice(chunk * Chests.SIZE, (chunk + 1) * Chests.SIZE):
				# (A full stack of coins would turn into the next coin up.)
				inv.add(name, inv.max_stack(name) - (1 if name in Inventory.COINS else 0))
			var count := ceili(names.size() / float(Chests.SIZE))
			_label(Vector3(pos) + Vector3(0.5, 1.7, 0.5), cdef[0] + ("" if count == 1 else " %d/%d" % [chunk + 1, count]))
			chunk += 1
			n += 1


## The arena's walls: higher than a zombie's best jump (Terraria's 8 px/tick,
## 4.4 blocks).
const ARENA_WALL := 5


func _build_arena(c: Vector3i) -> void:
	var x0 := c.x + 9
	var x1 := c.x + 44
	var z0 := c.z - 17
	var z1 := c.z + 17
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var edge := x == x0 or x == x1 or z == z0 or z == z1
			if x == x0 and z == c.z:
				# The gate: a wooden door, which walking enemies can't open.
				_door(Vector3i(x, GROUND + 1, z), "wooden_door", 3)
				_box(Vector3i(x, GROUND + 3, z), Vector3i(x, GROUND + ARENA_WALL, z), "gray_brick")
			elif edge:
				_box(Vector3i(x, GROUND + 1, z), Vector3i(x, GROUND + ARENA_WALL, z), "gray_brick")
				if (x + z) % 6 == 0:
					_b(Vector3i(x, GROUND + ARENA_WALL + 1, z), "torch")
	_label(Vector3(x0 - 1, GROUND + ARENA_WALL + 2, c.z + 0.5), "Enemy arena", 28)
	# (Critters have their pen: _build_critter_pen.)
	var kinds: Array = Data.npcs.keys().filter(func(k): return not Data.npcs[k].get("invulnerable", false) and Data.npcs[k].get("spawner", true) \
			and not Data.npcs[k].get("critter", false))
	kinds.sort_custom(func(a, b): return Data.npcs[a].get("boss", false) == false and Data.npcs[b].get("boss", false))
	# Columns of spawners down the arena's west side, 3 blocks apart.
	var per_column := (z1 - z0 - 2) / 3
	for i in kinds.size():
		var pos := Vector3i(x0 + 2 + (i / per_column) * 4, GROUND + 1, z0 + 2 + (i % per_column) * 3)
		_b(pos, "npc_spawner")
		spawners[_key(pos)] = {"pos": pos, "kind": kinds[i], "auto": false, "timer": 0.0, "alive": []}
	_label(Vector3(x0 + 2.5, GROUND + ARENA_WALL + 1.6, z0 + 0.5), "Right-click: spawn   Shift+right-click: auto", 18)


func _build_dummies(c: Vector3i) -> void:
	_box(Vector3i(c.x + 4, GROUND, c.z + 6), Vector3i(c.x + 8, GROUND, c.z + 8), "gray_brick")
	for dx in [5, 7]:
		_dummies.append(Vector3i(c.x + dx, GROUND + 1, c.z + 7))
	_label(Vector3(c.x + 6.5, GROUND + 3.6, c.z + 7.5), "Target dummies", 22)


## Mid-depth in the water pool (see _build_liquids), where swimmers spawn.
static func pool_spot() -> Vector3:
	return Vector3(SIZE.x / 2 - 21 + 0.5, GROUND - 4, SIZE.z / 2 - 3 + 0.5)


func _build_liquids(c: Vector3i) -> void:
	# Water pool, 6 deep, with a brick rim.
	var a := Vector3i(c.x - 26, GROUND - 5, c.z - 8)
	var b := Vector3i(c.x - 16, GROUND, c.z + 2)
	_box(Vector3i(a.x - 1, GROUND, a.z - 1), Vector3i(b.x + 1, GROUND, b.z + 1), "gray_brick")
	_box(a, b, "")
	_liquid_box(a, b, 1)
	_label(Vector3(c.x - 21, GROUND + 2.5, c.z - 3), "Water pool (6 deep)", 22)
	# Stone cliff in the pool with a natural spring pouring from it.
	_box(Vector3i(c.x - 26, GROUND - 5, c.z - 7), Vector3i(c.x - 25, GROUND + 12, c.z - 5), "stone")
	var mouth := Vector3i(c.x - 24, GROUND + 10, c.z - 6)
	game.world.add_decoration("waterfall", mouth, 1 * 10 + 0)
	_label(Vector3(mouth) + Vector3(0.5, 3.4, 0.5), "Natural waterfall", 20)
	# Hammer springs: a water tank (already hammered) and a lava tank to try.
	for i in 2:
		var tank := Vector3i(c.x - 20 + i * 3, GROUND + 6, c.z + 4)
		_box(tank - Vector3i(1, 1, 1), tank + Vector3i(1, 1, 1), "gray_brick")
		_b(tank, "")
		_liquids.append_array([tank.x, tank.y, tank.z, 1 if i == 0 else 2, 63])
		if i == 0:
			game.world.add_decoration("waterfall", tank + Vector3i(0, 0, -2), 1 * 10 + 3 + Waterfalls.NEEDS_LIQUID)
	_label(Vector3(c.x - 17.5, GROUND + 9, c.z + 4.5), "Hammer springs: hit a tank's front face with a hammer", 18)
	# Lava pit with a fence, and obsidian next to it.
	var la := Vector3i(c.x - 26, GROUND - 2, c.z + 8)
	var lb := Vector3i(c.x - 20, GROUND, c.z + 13)
	_box(la, lb, "")
	_liquid_box(la, lb, 2)
	for x in range(la.x - 1, lb.x + 2):
		for z in range(la.z - 1, lb.z + 2):
			if x == la.x - 1 or x == lb.x + 1 or z == la.z - 1 or z == lb.z + 1:
				_b(Vector3i(x, GROUND + 1, z), "gray_brick")
	_box(Vector3i(lb.x + 3, GROUND + 1, la.z), Vector3i(lb.x + 4, GROUND + 2, la.z + 1), "obsidian")
	_label(Vector3(c.x - 22.5, GROUND + 3, c.z + 10.5), "Lava pit", 22)


## The fishing pond: big enough for full fishing power (Fishing: 300 tiles
## of water, 134 cells in a slice; this one's 20 x 8 across), with a dock of
## platforms along its south side to cast from.
const FISHING := Vector3i(-48, 0, -26)
const FISHING_SIZE := Vector3i(20, 8, 12)


func _build_fishing(c: Vector3i) -> void:
	var a := Vector3i(c.x + FISHING.x, GROUND - FISHING_SIZE.y + 1, c.z + FISHING.z)
	var b := Vector3i(a.x + FISHING_SIZE.x - 1, GROUND, a.z + FISHING_SIZE.z - 1)
	_box(Vector3i(a.x - 1, a.y - 1, a.z - 1), Vector3i(b.x + 1, GROUND, b.z + 1), "sand")
	_box(a, b, "")
	_liquid_box(a, b, 1)
	for x in range(a.x, b.x + 1):
		_b(Vector3i(x, GROUND + 1, b.z), "wood_platform")
	for x in [a.x, a.x + 6, a.x + 12, b.x]:
		_box(Vector3i(x, a.y, b.z), Vector3i(x, GROUND, b.z), "wood")
	_label(Vector3((a.x + b.x) * 0.5 + 0.5, GROUND + 3.0, b.z + 0.5), "Fishing pond (full fishing power)", 22)


## The critter pen: a glass house on the grass west of the gallery, a
## spawner for each critter in rows down its west half, open grass in the
## middle and a pond in its east end (ducks swim, fish live in it), a door
## on its south side.
const CRITTER_PEN := Vector3i(-56, 0, 34)
const CRITTER_PEN_SIZE := Vector3i(34, 6, 22)


func _build_critter_pen(c: Vector3i) -> void:
	var a := Vector3i(c.x + CRITTER_PEN.x, GROUND, c.z + CRITTER_PEN.z)
	var sz := CRITTER_PEN_SIZE
	var b := a + Vector3i(sz.x - 1, sz.y, sz.z - 1)
	_box(Vector3i(a.x, GROUND + 1, a.z), b, "glass")
	_box(Vector3i(a.x + 1, GROUND + 1, a.z + 1), Vector3i(b.x - 1, b.y - 1, b.z - 1), "")
	_box(Vector3i(a.x, GROUND, a.z), Vector3i(b.x, GROUND, b.z), "grass")
	var door := Vector3i(a.x + 25, GROUND + 1, b.z)
	_door(door, "wooden_door", 0)
	# The pond: 5 x 16, 3 deep.
	var pa := Vector3i(b.x - 5, GROUND - 2, a.z + 3)
	var pb := Vector3i(b.x - 1, GROUND, a.z + 18)
	_box(Vector3i(pa.x - 1, pa.y - 1, pa.z - 1), Vector3i(pb.x + 1, GROUND - 1, pb.z + 1), "dirt")
	_box(pa, pb, "")
	_liquid_box(pa, pb, 1)
	var kinds: Array = Data.npcs.keys().filter(func(k): return Data.npcs[k].get("critter", false) and Data.npcs[k].get("spawner", true))
	for i in kinds.size():
		var pos := Vector3i(a.x + 2 + (i / 10) * 4, GROUND + 1, a.z + 2 + (i % 10) * 2)
		_b(pos, "npc_spawner")
		spawners[_key(pos)] = {"pos": pos, "kind": kinds[i], "auto": false, "timer": 0.0, "alive": []}
	_label(Vector3(a.x + sz.x * 0.5, GROUND + sz.y + 1.5, b.z + 0.5), "Critter pen: catch them with a Bug Net", 24)


## A fishing spot in every biome. Ponds in the world generator's patches
## are dug after them (FISHING_SPOTS: where, half size, depth, liquid, lining,
## cells of open air above; the biome counts round them as round the patch
## centre). The ocean is a long strip along the far north (TestWorld.in_ocean
## makes it the ocean: 80 x 14 cells across, more than Terraria's 1000 tiles).
## The Dungeon's spot is a blue brick hall (its catches need Skeletron
## beaten); the underground one a chamber down a shaft (north-east: the
## Dungeon's maze fills the west underground); the sky's a cloud
## basin above the islands, in the space layer.
const OCEAN := Vector3i(-40, 0, -125)
const OCEAN_SIZE := Vector3i(80, 14, 10)
const DUNGEON_HALL := Vector3i(-48, 0, 18)
const DUNGEON_HALL_SIZE := Vector3i(16, 7, 14)
const UNDERGROUND := Vector3i(22, -39, -46)
const UNDERGROUND_SIZE := Vector3i(18, 10, 14)
const UNDERGROUND_SHAFT := Vector3i(36, 0, -40)
const SKY_POND := Vector3i(16, 48, 0)
const FISHING_SPOTS := [
	# [name, centre of its surface (relative to the plaza, y from GROUND), half size, depth, liquid, lining, clear]
	["Snow", Vector3i(-75, 0, -70), Vector2i(8, 4), 8, 1, "ice_block", 25],
	["Desert", Vector3i(0, 0, -90), Vector2i(8, 4), 8, 1, "hardened_sand", 25],
	["Jungle", Vector3i(75, 0, -70), Vector2i(8, 4), 8, 1, "mud", 25],
	["Honey (Jungle)", Vector3i(75, 0, -84), Vector2i(4, 3), 10, 3, "hive", 25],
	["Corruption", Vector3i(-81, 0, 58), Vector2i(8, 4), 8, 1, "ebonstone", 25],
	["Crimson", Vector3i(69, 0, 58), Vector2i(8, 4), 8, 1, "crimstone", 25],
	["Lava", Vector3i(-42, 0, -33), Vector2i(7, 3), 9, 2, "gray_brick", 0],
	["Glowing Mushroom", Vector3i(56, -36, 18), Vector2i(8, 4), 8, 1, "mud", 0],
	["Underground", Vector3i(31, -38, -39), Vector2i(8, 4), 8, 1, "stone", 0],
	["Ocean", Vector3i(0, 0, -120), Vector2i(40, 4), 14, 1, "sand", 0],
	["Dungeon", Vector3i(-40, 0, 25), Vector2i(6, 4), 11, 1, "blue_brick", 0],
	["Sky", Vector3i(16, 48, 0), Vector2i(6, 4), 5, 1, "cloud", 0],
]


## What's built in the main pass for the spots: the Dungeon's hall, the
## underground chamber and its shaft, the ocean's beach.
func _build_fishing_rooms(c: Vector3i) -> void:
	# The Dungeon's hall: blue brick, a door gap on the east side.
	var h := c + DUNGEON_HALL
	var hs := DUNGEON_HALL_SIZE
	_box(Vector3i(h.x, GROUND, h.z), Vector3i(h.x + hs.x - 1, GROUND + hs.y, h.z + hs.z - 1), "blue_brick")
	_box(Vector3i(h.x + 1, GROUND + 1, h.z + 1), Vector3i(h.x + hs.x - 2, GROUND + hs.y - 1, h.z + hs.z - 2), "")
	_box(Vector3i(h.x + hs.x - 1, GROUND + 1, h.z + 6), Vector3i(h.x + hs.x - 1, GROUND + 2, h.z + 7), "")
	for corner in [Vector3i(1, 1, 1), Vector3i(hs.x - 2, 1, 1), Vector3i(1, 1, hs.z - 2), Vector3i(hs.x - 2, 1, hs.z - 2)]:
		_b(Vector3i(h.x, GROUND, h.z) + corner, "torch")
	# The underground chamber, lit, and a shaft with platforms down to it.
	var u := c + UNDERGROUND
	var us := UNDERGROUND_SIZE
	_box(Vector3i(u.x, u.y + 1, u.z), Vector3i(u.x + us.x - 1, u.y + us.y, u.z + us.z - 1), "")
	for corner in [Vector3i(0, 1, 0), Vector3i(us.x - 1, 1, 0), Vector3i(0, 1, us.z - 1), Vector3i(us.x - 1, 1, us.z - 1)]:
		_b(u + corner, "torch")
	var s := c + UNDERGROUND_SHAFT
	_box(Vector3i(s.x - 1, u.y + 1, s.z - 1), Vector3i(s.x + 1, GROUND, s.z + 1), "")
	for y in range(u.y + 4, GROUND, 4):
		_box(Vector3i(s.x - 1, y, s.z - 1), Vector3i(s.x + 1, y, s.z + 1), "wood_platform")
	_box(Vector3i(s.x - 2, GROUND, s.z - 2), Vector3i(s.x + 2, GROUND, s.z - 2), "gray_brick")
	_label(Vector3(s.x + 0.5, GROUND + 3, s.z + 0.5), "Underground fishing below", 22)
	# The beach round the ocean strip.
	var o := c + OCEAN
	_box(Vector3i(o.x - 3, GROUND, o.z - 2), Vector3i(o.x + OCEAN_SIZE.x + 2, GROUND, o.z + OCEAN_SIZE.z + 2), "sand")
	_label(Vector3(o.x + OCEAN_SIZE.x * 0.5, GROUND + 3, o.z + OCEAN_SIZE.z + 2.5), "The ocean (fishing, ocean music and enemies)", 24)


func _build_fishing_spots(c: Vector3i) -> void:
	# The sky pond's basin hangs in the air, a cloud walk round it.
	var sp := Vector3i(c.x + SKY_POND.x, GROUND + SKY_POND.y, c.z + SKY_POND.z)
	_blocks = PackedInt32Array()
	_box(sp + Vector3i(-9, 0, -7), sp + Vector3i(9, 0, 7), "cloud")
	game.world.set_blocks_raw(_blocks)
	for spot in FISHING_SPOTS:
		var at: Vector3i = spot[1]
		var top := Vector3i(c.x + at.x, GROUND + at.y, c.z + at.z)
		_dig_pond(top, spot[2], spot[3], spot[4], spot[5], spot[6])
		_label(Vector3(top) + Vector3(0.5, 2.6, spot[2].y + 2.5), "Fishing: " + spot[0], 20)
	_blocks = PackedInt32Array()
	_liquids = PackedInt32Array()


## A pond dug after the world generator's passes: `top` its surface's middle
## cell, `half` its half width (x) and length (z), `depth` deep, full of
## `liquid`, lined with `lining`; `clear` cells of air above it and its rim
## (trees, cacti and plants cleared off).
func _dig_pond(top: Vector3i, half: Vector2i, depth: int, liquid: int, lining: String, clear: int) -> void:
	_blocks = PackedInt32Array()
	_liquids = PackedInt32Array()
	var a := Vector3i(top.x - half.x, top.y - depth + 1, top.z - half.y)
	var b := Vector3i(top.x + half.x, top.y, top.z + half.y)
	_box(Vector3i(a.x - 1, a.y - 1, a.z - 1), Vector3i(b.x + 1, top.y, b.z + 1), lining)
	_box(a, b, "")
	if clear > 0:
		_box(Vector3i(a.x - 2, top.y + 1, a.z - 2), Vector3i(b.x + 2, top.y + clear, b.z + 2), "")
	_liquid_box(a, b, liquid)
	game.world.set_blocks_raw(_blocks)
	game.world.set_liquids_raw(_liquids)
	# Plants left over the water and its rim (a cave's mushrooms) go too.
	for x in range(a.x - 1, b.x + 2):
		for z in range(a.z - 1, b.z + 2):
			var above := Vector3i(x, top.y + 1, z)
			var id := game.world.get_block(above)
			if id != 0 and not Data.block(id).get("solid", true):
				game.world.set_block(above, 0)
			game.world.remove_decorations_at(above)
	if clear > 0:
		for x in range(a.x - 2, b.x + 3):
			for z in range(a.z - 2, b.z + 3):
				for y in range(top.y, top.y + clear + 1):
					game.world.remove_decorations_at(Vector3i(x, y, z))


## The test world's ocean (Game.in_ocean): the strip along the far north and its beach.
func in_ocean(pos: Vector3) -> bool:
	var c := Vector3i(SIZE.x / 2, GROUND + 1, SIZE.z / 2)
	var o := c + OCEAN
	return pos.x >= o.x - 3 and pos.x < o.x + OCEAN_SIZE.x + 3 and pos.z >= o.z - 2 and pos.z < o.z + OCEAN_SIZE.z + 3 \
			and pos.y > GROUND - OCEAN_SIZE.y - 4 and pos.y < GROUND + 30


## The block gallery: rows of GALLERY_ROW blocks, 2 apart, from GALLERY_Z
## south of the centre (south of the tower), 3 between rows; GALLERY_X east
## of it (clear of the critter pen to the west).
const GALLERY_Z := 31
const GALLERY_ROW := 22
const GALLERY_X := 4


static func gallery_pos(c: Vector3i, i: int) -> Vector3i:
	return Vector3i(c.x + GALLERY_X - GALLERY_ROW + (i % GALLERY_ROW) * 2, GROUND + 1, c.z + GALLERY_Z + (i / GALLERY_ROW) * 3)


## Whether `pos` is in the gallery (its herbs stay as shown: Herbs).
static func in_gallery(c: Vector3i, pos: Vector3i) -> bool:
	var rows := ceili(gallery_blocks().size() / float(GALLERY_ROW))
	return pos.x >= c.x + GALLERY_X - GALLERY_ROW - 2 and pos.x <= c.x + GALLERY_X + GALLERY_ROW + 2 and pos.z >= c.z + GALLERY_Z - 1 \
			and pos.z <= c.z + GALLERY_Z + rows * 3 - 1 and pos.y >= GROUND and pos.y <= GROUND + 4


static func gallery_blocks() -> Array:
	var names: Array = []
	for id in range(1, Data.blocks.size()):
		# (Not the Bast Statue: its buff would reach the whole test area.)
		if not Data.blocks[id].get("hidden", false) and not Data.blocks[id].has("near_buff"):
			names.append(Data.blocks[id].name)
	return names


func _build_gallery(c: Vector3i) -> void:
	var names := gallery_blocks()
	var rows := ceili(names.size() / float(GALLERY_ROW))
	_box(Vector3i(c.x + GALLERY_X - GALLERY_ROW - 2, GROUND, c.z + GALLERY_Z - 1), Vector3i(c.x + GALLERY_X + GALLERY_ROW + 2, GROUND, c.z + GALLERY_Z + rows * 3 - 1), "gray_brick")
	_label(Vector3(c.x + GALLERY_X + 0.5, GROUND + 3.5, c.z + GALLERY_Z - 1.5), "One of every block", 24)
	for i in names.size():
		var pos := gallery_pos(c, i)
		if Doors.is_door(Data.block(Data.block_id(names[i]))):
			_door(pos, names[i], 0)
			_label(Vector3(pos) + Vector3(0.5, 2.5, 0.5), names[i].replace("_", " "), 14)
			continue
		_b(pos, names[i])
		# Herbs and coral on what they grow on.
		var soils: Array = Data.block(Data.block_id(names[i])).get("grows_on", [])
		if not soils.is_empty():
			_b(pos + Vector3i.DOWN, soils[0])
		if Data.block(Data.block_id(names[i])).get("wall", false):
			_b(pos + Vector3i(0, 0, -1), "stone")  # something to hang on (it faces +z)
		if Data.block(Data.block_id(names[i])).get("interact") == "chest":
			game.chests.register_new(pos)
		if names[i] == "npc_spawner":
			spawners[_key(pos)] = {"pos": pos, "kind": "BlueSlime", "auto": false, "timer": 0.0, "alive": []}
		_label(Vector3(pos) + Vector3(0.5, 1.5, 0.5), names[i].replace("_", " "), 14)
	# Ore wall: 3 wide, 4 high per ore, with the pickaxe power each needs.
	var ores: Array = names.filter(func(n): return n.ends_with("_ore") or n in ["hellstone", "obsidian"])
	var x := c.x - 34
	for ore in ores:
		_box(Vector3i(x, GROUND + 1, c.z + 19), Vector3i(x + 2, GROUND + 4, c.z + 20), ore)
		var need := int(Data.block(Data.block_id(ore)).get("min_pick", 0))
		_label(Vector3(x + 1.5, GROUND + 5.6, c.z + 18.5), ore.replace("_", " ") + ("\n%d%% pick" % need if need > 0 else ""), 14)
		x += 4


func _build_tower(c: Vector3i) -> void:
	# A staircase up to a platform 25 blocks high, with a water landing pool on
	# one side and a rope and a chain up the other.
	var x0 := c.x + 14
	var z := c.z + 21
	for i in 25:
		_box(Vector3i(x0 + i, GROUND + 1, z), Vector3i(x0 + i, GROUND + 1 + i, z + 1), "gray_brick")
	var top := GROUND + 25
	_box(Vector3i(x0 + 25, top, z - 1), Vector3i(x0 + 28, top, z + 2), "gray_brick")
	_box(Vector3i(x0 + 25, GROUND + 1, z - 1), Vector3i(x0 + 28, top - 1, z - 1), "gray_brick")
	var pa := Vector3i(x0 + 25, GROUND - 4, z + 3)
	var pb := Vector3i(x0 + 28, GROUND, z + 6)
	_box(pa, pb, "")
	_liquid_box(pa, pb, 1)
	_label(Vector3(x0 + 27, top + 2.6, z + 1), "Fall test: water to the south, ground to the north", 18)
	# A rope and a chain down its north wall, from the top to the ground.
	for y in range(GROUND + 1, top + 1):
		_b(Vector3i(x0 + 26, y, z - 2), "rope")
		_b(Vector3i(x0 + 28, y, z - 2), "chain")
	_label(Vector3(x0 + 27.5, GROUND + 4.6, z - 1.5), "Rope and chain: Space climbs, Shift slides down,\nmove to let go, jump while moving leaps off", 16)


func _build_dark_room(c: Vector3i) -> void:
	var a := Vector3i(c.x - 26, GROUND + 1, c.z - 26)
	var b := Vector3i(c.x - 18, GROUND + 6, c.z - 18)
	_box(a, b, "stone")
	_box(a + Vector3i(1, 0, 1), b - Vector3i(1, 1, 1), "")
	# Bent entrance so no daylight reaches the inside.
	_box(Vector3i(c.x - 22, GROUND + 1, b.z), Vector3i(c.x - 22, GROUND + 2, b.z), "")
	_box(Vector3i(c.x - 24, GROUND + 1, b.z - 2), Vector3i(c.x - 20, GROUND + 4, b.z - 2), "stone")
	_label(Vector3(c.x - 21.5, GROUND + 8.5, b.z + 0.5), "Dark room (torches & lighting)", 20)


func _build_trees(c: Vector3i) -> void:
	for i in 4:
		var x := c.x - 8 + i * 4
		var z := c.z - 20
		_box(Vector3i(x, GROUND + 1, z), Vector3i(x, GROUND + 8, z), "tree_trunk")
		game.world.add_decoration("tree_top", Vector3i(x, GROUND + 9, z), i % 3)
	_label(Vector3(c.x - 1.5, GROUND + 3, c.z - 21), "Trees (axe)", 20)


## North of the trees: the forest's plants and debris as the world generator
## scatters them, a sunflower patch, a pond with lily pads and cattails, and a
## grassy ledge with vines hanging under it.
const GARDEN := Vector3i(0, 0, -36)
## The herb bed, from the garden: a row along x, south of the sunflowers.
const HERB_BED := Vector3i(-13, 0, -14)


func _build_garden(c: Vector3i) -> void:
	var g := c + GARDEN
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ground := ["tall_grass", "taller_grass", "flowers", "tall_flowers", "mushroom", "small_rocks", "twigs",
			"large_rocks", "fallen_log"]
	# The meadow: every ground piece at least twice, then grass and flowers.
	for x in range(-12, 13):
		for z in range(-8, 0):
			var i := (x + 12) + (z + 8) * 25
			var name: String = ground[i % ground.size()] if i < ground.size() * 2 else \
					["tall_grass", "tall_grass", "taller_grass", "flowers", "tall_flowers", ""][rng.randi() % 6]
			if name != "" and (i < ground.size() * 2 or rng.randf() < 0.6):
				_b(g + Vector3i(x, 0, z), name)
	for x in range(-3, 4):
		_b(g + Vector3i(x, 0, -10), "sunflower")
	# The pond: 2 deep, lily pads on it, cattails up through it.
	var pa := g + Vector3i(2, -2, 2)
	var pb := g + Vector3i(9, -1, 7)
	_box(pa, pb, "")
	_liquid_box(pa, pb, 1)
	for p in [Vector3i(3, 0, 3), Vector3i(6, 0, 5), Vector3i(8, 0, 3), Vector3i(4, 0, 6)]:
		_b(g + p, "lily_pad")
	for x in [2, 5, 9]:
		var q := g + Vector3i(x, 0, 7 if x != 5 else 2)
		_b(q + Vector3i(0, -2, 0), "cattail")
		_b(q + Vector3i(0, -1, 0), "cattail_stem")
		_b(q, "cattail_top")
	# A grassy ledge on two dirt pillars, vines and flowering vines under it.
	var la := g + Vector3i(-10, 3, 2)
	_box(la, la + Vector3i(7, 0, 3), "grass")
	_box(la + Vector3i(0, 1, 0), la + Vector3i(7, 1, 3), "grass")
	for x in [0, 7]:
		_box(la + Vector3i(x, -3, 0), la + Vector3i(x, -1, 0), "dirt")
	for x in range(1, 7):
		for z in range(0, 4):
			if rng.randf() < 0.6:
				var n := rng.randi_range(1, 3)
				for k in n:
					_b(la + Vector3i(x, -1 - k, z), "vine_flowers" if rng.randf() < 0.25 else "vines")
	_label(Vector3(g) + Vector3(0.5, 3.0, -4.0), "Forest plants", 24)
	# The herb bed: each herb as a sprout, grown and in bloom on its soil
	# (they grow and bloom here as anywhere: Herbs).
	for h in Herbs.STYLES.size():
		for stage in 3:
			var q := g + HERB_BED + Vector3i(h * 4 + stage, 0, 0)
			_b(q + Vector3i.DOWN, Data.block(Data.block_id(Herbs.STYLES[h])).grows_on[0])
			_b(q, Herbs.STYLES[h] + ["_sprout", "_mature", ""][stage])
		_label(Vector3(g + HERB_BED + Vector3i(h * 4 + 1, 0, 0)) + Vector3(0.5, 1.4, 0.5), Herbs.STYLES[h].capitalize(), 14)
	_label(Vector3(g + HERB_BED) + Vector3(13.5, 2.6, 0.5), "Herbs: sprout, grown, in bloom", 20)


## South-west of spawn: a stair of wooden platforms up to a floating platform
## floor (stand on it, jump up through it, Drop down to fall through).
const PLATFORMS := Vector3i(-12, 0, 14)


func _build_platforms(c: Vector3i) -> void:
	var a := c + PLATFORMS
	for i in 4:
		_b(a + Vector3i(i, i, 0), "wood_platform")
	for x in range(4, 10):
		for z in range(-1, 2):
			_b(a + Vector3i(x, 3, z), "wood_platform")
	_label(Vector3(a) + Vector3(6.5, 5.6, 0.5), "Platforms (Shift: drop through)", 18)


## East of the forest garden: a wooden house with a door, furnished like a
## Terraria NPC house: table with a candle, chair, bed (right-click: spawn
## point), grandfather clock (right-click: the time), barrel, a chandelier, and a
## sawmill and loom. Cobwebs hang in the dark room's corners.
const HOUSE := Vector3i(15, 0, -34)


func _build_house(c: Vector3i) -> void:
	var a := c + HOUSE  # north-west corner, at ground + 1
	var size := Vector3i(9, 5, 7)
	for x in size.x:
		for z in size.z:
			for y in size.y:
				var wall := x == 0 or z == 0 or x == size.x - 1 or z == size.z - 1
				if y == size.y - 1 or wall:
					_b(a + Vector3i(x, y, z), "wood")
	# Door in the south wall (facing spawn), with a lintel above it.
	var door := a + Vector3i(4, 0, size.z - 1)
	_b(door + Vector3i.UP * 2, "wood")
	_door(door, "wooden_door", 0)
	_b(a + Vector3i(2, 0, 1), "wooden_table")
	_b(a + Vector3i(2, 1, 1), "candle")
	_b(a + Vector3i(3, 0, 1), "wooden_chair")
	_b(a + Vector3i(6, 0, 1), "bed")
	_b(a + Vector3i(1, 0, 5), "grandfather_clock")
	_b(a + Vector3i(7, 0, 5), "barrel")
	game.chests.register_new(a + Vector3i(7, 0, 5))
	_b(a + Vector3i(1, 0, 3), "sawmill")
	_b(a + Vector3i(7, 0, 3), "loom")
	_b(a + Vector3i(4, size.y - 2, 3), "copper_chandelier")
	_label(Vector3(door) + Vector3(0.5, 4.8, 1.5), "House (furniture)", 20)
	# Cobwebs in the dark room's top corners (see _build_dark_room).
	var r0 := Vector3i(c.x - 25, GROUND + 5, c.z - 25)
	for corner in [Vector3i(0, 0, 0), Vector3i(6, 0, 0), Vector3i(0, 0, 6), Vector3i(6, 0, 6)]:
		for d in [Vector3i.ZERO, Vector3i(signi(3 - corner.x), 0, 0), Vector3i(0, 0, signi(3 - corner.z)), Vector3i(0, -1, 0)]:
			_b(r0 + corner + d, "cobweb")


## North of the house: a library - bookcases, piano, dresser with a
## candelabra on it, trash can, silver chandelier - with a lamp post outside;
## tiki torches and a sign (right-click to write, aim to read) by the house door.
const LIBRARY := Vector3i(15, 0, -44)
const HOUSE_SIGN := Vector3i(17, 0, -26)


func _build_library(c: Vector3i) -> void:
	var a := c + LIBRARY
	var size := Vector3i(9, 5, 7)
	for x in size.x:
		for z in size.z:
			for y in size.y:
				if y == size.y - 1 or x == 0 or z == 0 or x == size.x - 1 or z == size.z - 1:
					_b(a + Vector3i(x, y, z), "wood")
	var door := a + Vector3i(4, 0, size.z - 1)
	_b(door + Vector3i.UP * 2, "wood")
	_door(door, "wooden_door", 0)
	_b(a + Vector3i(2, 0, 1), "bookcase")
	_b(a + Vector3i(6, 0, 1), "bookcase")
	_b(a + Vector3i(4, 0, 1), "piano")
	_b(a + Vector3i(1, 0, 4), "dresser")
	_b(a + Vector3i(1, 1, 4), "candelabra")
	game.chests.register_new(a + Vector3i(1, 0, 4))
	_b(a + Vector3i(7, 0, 5), "trash_can")
	game.chests.register_new(a + Vector3i(7, 0, 5))
	_b(a + Vector3i(4, size.y - 2, 3), "silver_chandelier")
	_b(door + Vector3i(2, 0, 1), "lamp_post")
	_label(Vector3(door) + Vector3(0.5, 4.8, 1.5), "Library (furniture)", 20)
	# By the house door: tiki torches, and a sign.
	var house_door := c + HOUSE + Vector3i(4, 0, 6)
	_b(house_door + Vector3i(-1, 0, 1), "tiki_torch")
	_b(house_door + Vector3i(1, 0, 1), "tiki_torch")
	_b(c + HOUSE_SIGN, "sign")
	game.signs[Chests.key(c + HOUSE_SIGN)] = "Welcome! Right-click a sign to write on it."


## Far west: the Dungeon's entrance (the world generator's), its door facing
## spawn, the Old Man by it, and a small Dungeon under it (a few of the
## generator's layout steps).
const DUNGEON := Vector3i(-62, 0, 0)
const DUNGEON_STEPS := 0.25


func _build_dungeon(c: Vector3i) -> void:
	var at := Vector3i(c.x + DUNGEON.x, GROUND, c.z + DUNGEON.z)
	game.world.generate_dungeon_entrance(at, 1, "blue_brick")
	game.world.generate_dungeon(at, 1, "blue_brick", DUNGEON_STEPS, 7)
	_label(Vector3(c.x + DUNGEON.x + 9.5, GROUND + 9, c.z + 0.5), "Dungeon entrance", 26)


## South-east, under the ground past the tower: a mud cavern the world
## generator's Glowing Mushroom biome grows in (generate_mushroom_biome: its
## mushroom grass, giant and small glowing mushrooms, vines; not its patches,
## whose shape is chance), down a shaft with platforms every 4 blocks.
const MUSHROOM := Vector3i(56, -32, 18)
const MUSHROOM_SHAFT := Vector3i(56, 0, 6)


func _build_mushroom_cavern(c: Vector3i) -> void:
	var m := c + MUSHROOM
	# Hollow inside, a mud shell 4 blocks thick round it.
	for dx in range(-21, 22):
		for dz in range(-21, 22):
			for dy in range(-9, 18):
				var e := Vector3(dx / 16.0, dy / (12.0 if dy > 0 else 4.5), dz / 16.0)
				var shell := Vector3(dx / 20.0, dy / (16.0 if dy > 0 else 8.5), dz / 20.0)
				if e.length() < 1.0:
					_b(m + Vector3i(dx, dy, dz), "")
				elif shell.length() < 1.0 and m.y + dy < GROUND - 4:
					_b(m + Vector3i(dx, dy, dz), "mud")
	var s := c + MUSHROOM_SHAFT
	var bottom := m.y + 5
	_box(Vector3i(s.x - 1, bottom, s.z - 1), Vector3i(s.x + 1, GROUND, s.z + 1), "")
	for y in range(bottom + 2, GROUND, 4):
		_box(Vector3i(s.x - 1, y, s.z - 1), Vector3i(s.x + 1, y, s.z + 1), "wood_platform")
	_box(Vector3i(s.x - 2, GROUND, s.z - 2), Vector3i(s.x + 2, GROUND, s.z - 2), "gray_brick")
	_label(Vector3(s.x + 0.5, GROUND + 3, s.z + 0.5), "Glowing Mushroom biome below", 24)


## East of the house: blocks reshaped with a hammer - half blocks, a ramp
## staircase and an arch with upside-down ramps in its corners.
const HAMMERED := Vector3i(26, 0, -32)


func _build_hammered(c: Vector3i) -> void:
	var h := c + HAMMERED
	var shaped := func(p: Vector3i, shape: int) -> void:
		_b(p, "stone")
		_shapes.append([p, shape])
	shaped.call(h, Game.SHAPE_HALF)
	shaped.call(h + Vector3i(1, 0, 0), Game.SHAPE_HALF)
	# A staircase of ramps rising east (direction 1), three blocks up.
	for i in 3:
		for y in i:
			_b(h + Vector3i(3 + i, y, 0), "stone")
		shaped.call(h + Vector3i(3 + i, i, 0), Game.SHAPE_RAMP + 1)
	_box(h + Vector3i(6, 0, 0), h + Vector3i(6, 2, 0), "stone")
	# An arch: two pillars, a beam, upside-down ramps against the pillars.
	_box(h + Vector3i(8, 0, 0), h + Vector3i(8, 2, 0), "stone")
	_box(h + Vector3i(12, 0, 0), h + Vector3i(12, 2, 0), "stone")
	_box(h + Vector3i(8, 3, 0), h + Vector3i(12, 3, 0), "stone")
	shaped.call(h + Vector3i(9, 2, 0), Game.SHAPE_CEILING + 3)
	shaped.call(h + Vector3i(11, 2, 0), Game.SHAPE_CEILING + 1)
	# Grass ramps: the green edge runs up the steps.
	for i in 2:
		var g := h + Vector3i(14 + i, 0, 0)
		_b(g, "grass")
		_shapes.append([g, Game.SHAPE_RAMP + 1])
	_label(Vector3(h) + Vector3(6.5, 5.2, 0.5), "Hammered blocks (hit a block with a hammer)", 18)


## East of the arena: a row of houses for the town NPCs, each a valid home
## (door, light, table, chair), with a resident in each (see activate).
const TOWN := Vector3i(52, 0, -24)
const TOWN_HOUSES := 8
## Who lives in them (the Clothier comes once Skeletron is beaten, as in
## Terraria).
const TOWN_RESIDENTS := ["Guide", "Merchant", "Nurse", "ArmsDealer", "Dryad", "Demolitionist", "GoblinTinkerer", "Angler"]


## The north-west corner (at ground + 1) of town house `i`.
static func town_house(c: Vector3i, i: int) -> Vector3i:
	return c + TOWN + Vector3i(0, 0, i * 8)


func _build_town(c: Vector3i) -> void:
	var size := Vector3i(7, 5, 6)
	for i in TOWN_HOUSES:
		var a := town_house(c, i)
		for x in size.x:
			for z in size.z:
				for y in size.y:
					if y == size.y - 1 or x == 0 or z == 0 or x == size.x - 1 or z == size.z - 1:
						_b(a + Vector3i(x, y, z), "wood")
		# The door in the west wall (toward the arena), a lintel over it.
		var door := a + Vector3i(0, 0, 2)
		_b(door + Vector3i.UP * 2, "wood")
		_door(door, "wooden_door", 3)
		_b(a + Vector3i(4, 0, 1), "wooden_table")
		_b(a + Vector3i(4, 1, 1), "candle")
		_b(a + Vector3i(3, 0, 1), "wooden_chair")
	_label(Vector3(town_house(c, 3)) + Vector3(-1.5, 5.5, 3.0), "Town (NPC houses; Tab > Housing)", 22)


## Settles the town NPCs in the town's houses (a fresh test world).
func _settle_town() -> void:
	var c := Vector3i(SIZE.x / 2, GROUND + 1, SIZE.z / 2)
	for i in TOWN_RESIDENTS.size():
		var h := Housing.check(game.world, town_house(c, i) + Vector3i(3, 0, 3))
		if not h.ok:
			push_warning("test town house %d: %s" % [i, h.reason])
			continue
		var npc := game.town.move_in(TOWN_RESIDENTS[i], Vector3(h.spot) + Vector3(0.5, 0, 0.5))
		npc.home_key = h.key
		npc.home_spot = h.spot


## The player's starting kit in a test world.
func give_loadout(p: Player) -> void:
	p.inventory.slots.fill(null)
	var hotbar := ["PlatinumBroadsword", "PlatinumPickaxe", "PlatinumAxe", "PlatinumHammer", "DemonBow",
			"FlintlockPistol", "AmethystStaff", "Torch", "WaterBucket", "LesserHealingPotion"]
	for i in hotbar.size():
		p.inventory.slots[i] = Inventory.stack(hotbar[i], p.inventory.max_stack(hotbar[i]))
	for item in ["WoodenArrow", "UnholyArrow", "MusketBall", "EmptyBucket", "LavaBucket", "SuspiciousLookingEye", "DirtBlock", "StoneBlock", "Wood"]:
		p.inventory.add(item, p.inventory.max_stack(item))
	# Fishing gear (the fishing pond is north-west of the water pool) and a
	# Bug Net (the critter pen is west of the gallery).
	p.inventory.add("BugNet", 1)
	p.inventory.add("ReinforcedFishingPole", 1)
	p.inventory.add("MasterBait", 99)
	p.inventory.add_money(50 * 10000)  # 50 gold, for the town's shops
	if kind == "wiring":
		for item in ["Wrench", "BlueWrench", "GreenWrench", "YellowWrench", "WireCutter", "Wire", "Actuator"]:
			p.inventory.add(item, p.inventory.max_stack(item))
	p.accessories.slots.fill(null)
	for i in 3:
		p.accessories.slots[i] = Inventory.stack(["HermesBoots", "CloudinaBottle", "BandofRegeneration"][i], 1)
	for i in 3:
		p.armor.slots[i] = Inventory.stack(["PlatinumHelmet", "PlatinumChainmail", "PlatinumGreaves"][i], 1)
	p.life_max = Player.MAX_LIFE
	p.life = p.life_max
	p.mana_max = Player.MAX_MANA
	p.mana = p.mana_max
	p.inventory.changed.emit()


# ------------------------------------------------------------------ runtime

## Creates labels, spawner visuals, dummies and the overlay (new or loaded world).
func activate() -> void:
	for l in _labels:
		var lab := Label3D.new()
		lab.text = l[1]
		lab.font = Assets.font("Mouse_Text")
		lab.font_size = int(l[2])
		lab.pixel_size = 0.02
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		lab.outline_size = 0
		lab.modulate = Color(1, 1, 0.85)
		add_child(lab)
		lab.global_position = l[0]
	for sp in spawners.values():
		_make_spawner_visual(sp)
	for d in _dummies:
		game.spawn_npc("TargetDummy", Vector3(d) + Vector3(0.5, 0, 0.5))
	if game.town.residents.is_empty() and _has("npc"):
		_settle_town()
	game.spawner.process_mode = Node.PROCESS_MODE_INHERIT if natural_spawns else Node.PROCESS_MODE_DISABLED
	_build_overlay()


func _make_spawner_visual(sp: Dictionary) -> void:
	var def: Dictionary = Data.npcs[sp.kind]
	var s := EntitySprite.new()
	var tex := Assets.texture(NPC.image_path(sp.kind))
	var frame_h := float(tex.get_height()) / int(def.frames)
	var h := 0.9
	s.setup(tex, int(def.frames), Vector2(h * tex.get_width() / frame_h, h), true)
	if def.has("tint"):
		var t: Array = def.tint
		s.set_tint(Color(t[0], t[1], t[2], t[3]))
	if def.has("trim_bottom"):
		s.set_trim_bottom(float(def.trim_bottom), frame_h)
	add_child(s)
	s.global_position = Vector3(sp.pos) + Vector3(0.5, 1.6, 0.5)
	sp["sprite"] = s
	var lab := Label3D.new()
	lab.font = Assets.font("Mouse_Text")
	lab.font_size = 16
	lab.pixel_size = 0.02
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(lab)
	lab.global_position = Vector3(sp.pos) + Vector3(0.5, 2.7, 0.5)
	sp["label"] = lab
	_update_spawner_label(sp)


func _update_spawner_label(sp: Dictionary) -> void:
	sp.label.text = Assets.npc_name(sp.kind) + ("\n[AUTO]" if sp.auto else "")
	sp.label.modulate = Color(0.6, 1.0, 0.6) if sp.auto else Color(1, 1, 1)


static func _key(p: Vector3i) -> String:
	return "%d,%d,%d" % [p.x, p.y, p.z]


func is_spawner(p: Vector3i) -> bool:
	return spawners.has(_key(p))


## Right-click: spawn one; with Shift: toggle auto-spawning.
func use_spawner(p: Vector3i, toggle_auto: bool) -> void:
	var sp: Dictionary = spawners.get(_key(p), {})
	if sp.is_empty():
		return
	if toggle_auto:
		sp.auto = not sp.auto
		sp.timer = 0.0
		_update_spawner_label(sp)
		game.message("%s spawner: auto %s" % [Assets.npc_name(sp.kind), "on" if sp.auto else "off"], Color(0.7, 1.0, 0.7))
		Audio.play("Mech_0", 0.6)
	else:
		_spawn_from(sp)


func _spawn_from(sp: Dictionary) -> void:
	var def: Dictionary = Data.npcs[sp.kind]
	if def.get("boss", false):
		if game.boss_alive():
			game.message("A boss is already here", Color(0.8, 0.8, 0.8))
			return
		var npc := game.spawn_npc(sp.kind, Vector3(sp.pos) + Vector3(8.5, 10.0, 0.5))
		sp.alive.append(npc)
		Audio.play("Roar_0")
		game.message("%s has awoken!" % Assets.npc_name(sp.kind), Color(0.69, 0.29, 1.0))
		return
	# Swimmers (sharks, jellyfish) go in the water pool.
	var at := pool_spot() if def.ai == "swim" else spawn_spot(sp.pos, sp.kind)
	var npc := game.spawn_npc(sp.kind, at)
	sp.alive.append(npc)
	Audio.play_at("Mech_0", Vector3(sp.pos), 0.5)


## Where a spawner at `p` puts its enemy: the first spot east of it where the
## enemy's whole body is in the open (fliers 3 up, walkers on the floor), so
## it never lands inside the next spawner along or anything else.
func spawn_spot(p: Vector3i, kind: String) -> Vector3:
	var lk := NPC.look(kind)
	var flying: bool = lk.flying
	var size: Array = lk.hitbox
	var half := Vector3(float(size[0]) * 0.5, float(size[1]), float(size[0]) * 0.5)
	var lift := 3.0 if flying else 0.0
	for k in range(4, 40):
		var at := Vector3(p) + Vector3(0.5 + k * 0.5, lift, 0.5)
		if _clear(at, half) and (flying or game.world.is_solid(Vector3i((at + Vector3(0, -0.5, 0)).floor()))):
			return at
	return Vector3(p) + Vector3(0.5, 2.0 + lift, 0.5)


## No solid block in the box `half` (half width, full height) standing at `at`.
func _clear(at: Vector3, half: Vector3) -> bool:
	var lo := Vector3i((at - Vector3(half.x, 0, half.z)).floor())
	var hi := Vector3i((at + Vector3(half.x, half.y, half.z) - Vector3.ONE * 0.001).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				if game.world.is_solid(Vector3i(x, y, z)):
					return false
	return true


func remove_spawner(p: Vector3i) -> void:
	var sp: Dictionary = spawners.get(_key(p), {})
	if sp.is_empty():
		return
	for n in ["sprite", "label"]:
		if sp.has(n):
			sp[n].queue_free()
	spawners.erase(_key(p))


func _physics_process(delta: float) -> void:
	if game == null or game.state != Game.State.PLAYING:
		return
	for sp in spawners.values():
		sp.alive = sp.alive.filter(func(n): return is_instance_valid(n) and n.is_inside_tree())
		if sp.auto:
			sp.timer -= delta
			if sp.timer <= 0.0:
				sp.timer = SPAWNER_INTERVAL
				if sp.alive.size() < SPAWNER_MAX_ALIVE:
					_spawn_from(sp)


func _process(_delta: float) -> void:
	if game == null or game.state != Game.State.PLAYING:
		return
	for sp in spawners.values():
		if sp.has("sprite"):
			sp.sprite.update_light(game.world, game.sky, sp.sprite.global_position)
	if _status:
		var p := game.player
		var flags := []
		if p.god_mode:
			flags.append("GOD")
		if p.flying:
			flags.append("FLY")
		if natural_spawns:
			flags.append("SPAWNS ON")
		_status.text = KINDS[kind].to_upper() + "   F1 help" + ("   [" + "] [".join(flags) + "]" if not flags.is_empty() else "")


# ------------------------------------------------------------------ hotkeys

func _unhandled_input(event: InputEvent) -> void:
	if game == null or game.state != Game.State.PLAYING or game.hud.paused:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var p := game.player
	match event.keycode:
		KEY_F1:
			_help.visible = not _help.visible
		KEY_F2:
			p.god_mode = not p.god_mode
			game.message("God mode " + ("on" if p.god_mode else "off"), Color(1, 0.9, 0.5))
		KEY_F3:
			p.flying = not p.flying
			p.velocity = Vector3.ZERO
			game.message("Flying " + ("on (Space up, Shift down)" if p.flying else "off"), Color(1, 0.9, 0.5))
		KEY_F4:
			set_night(game.sky.is_day)
		KEY_F5:
			var n := 0
			for npc in game.npcs():
				if not npc.def.get("invulnerable", false):
					npc.queue_free()
					n += 1
			game.message("Removed %d enemies" % n, Color(1, 0.9, 0.5))
		KEY_F6:
			var n := 0
			for e in game.entities.get_children():
				if e is ItemDrop:
					e.queue_free()
					n += 1
			game.message("Cleared %d dropped items" % n, Color(1, 0.9, 0.5))
		KEY_F7:
			natural_spawns = not natural_spawns
			game.spawner.process_mode = Node.PROCESS_MODE_INHERIT if natural_spawns else Node.PROCESS_MODE_DISABLED
			game.message("Natural enemy spawns " + ("on" if natural_spawns else "off"), Color(1, 0.9, 0.5))
		KEY_F8:
			p.heal(p.life_max)
			p.mana = p.mana_max
			p.breath = Player.BREATH_MAX
			p.on_fire = 0.0
			p.potion_sickness = 0.0
			p.stats_changed.emit()
		_:
			return
	get_viewport().set_input_as_handled()


func set_night(night: bool) -> void:
	game.sky.is_day = not night
	game.sky.time = SkySystem.NIGHT_LENGTH * 0.25 if night else SkySystem.DAY_LENGTH * 0.45
	game.message("It is now " + ("night" if night else "day"), Color(1, 0.9, 0.5))


## This kind's help lines.
func help_lines() -> Array:
	var out := [KINDS[kind].to_upper()]
	for h in HELP:
		if h[0] == "" or Array(h[0].split(" ")).any(func(t): return _has(t)):
			out.append(h[1])
	return out


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 11
	add_child(layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = Assets.font("Mouse_Text")
	theme.default_font_size = 20
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.9))
	theme.set_constant("shadow_offset_x", "Label", 2)
	theme.set_constant("shadow_offset_y", "Label", 2)
	root.theme = theme
	layer.add_child(root)
	Settings.track_ui_scale(root)
	_status = Label.new()
	# Bottom centre, clear of the hotbar and hearts at any UI scale.
	_status.anchor_left = 0.5
	_status.anchor_right = 0.5
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_left = -300
	_status.offset_right = 300
	_status.offset_top = -34
	_status.offset_bottom = -8
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_status)
	_help = PanelContainer.new()
	_help.anchor_left = 0.5
	_help.anchor_right = 0.5
	_help.anchor_top = 0.5
	_help.anchor_bottom = 0.5
	_help.offset_left = -330
	_help.offset_right = 330
	_help.offset_top = -170
	_help.offset_bottom = 170
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.2, 0.85)
	sb.set_content_margin_all(14)
	sb.set_corner_radius_all(8)
	_help.add_theme_stylebox_override("panel", sb)
	var t := Label.new()
	t.text = "\n".join(help_lines())
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_child(t)
	_help.visible = false
	root.add_child(_help)


# ------------------------------------------------------------------ saving

func save_state() -> Dictionary:
	var sps := []
	for sp in spawners.values():
		sps.append([[sp.pos.x, sp.pos.y, sp.pos.z], sp.kind, sp.auto])
	var labels := []
	for l in _labels:
		labels.append([[l[0].x, l[0].y, l[0].z], l[1], l[2]])
	var dummies := []
	for d in _dummies:
		dummies.append([d.x, d.y, d.z])
	return {"kind": kind, "spawners": sps, "labels": labels, "dummies": dummies, "natural_spawns": natural_spawns}


func load_state(d: Dictionary) -> void:
	kind = d.get("kind", "all")
	spawners.clear()
	for s in d.get("spawners", []):
		var pos := Vector3i(int(s[0][0]), int(s[0][1]), int(s[0][2]))
		spawners[_key(pos)] = {"pos": pos, "kind": s[1], "auto": bool(s[2]), "timer": 0.0, "alive": []}
	_labels.clear()
	for l in d.get("labels", []):
		_labels.append([Vector3(l[0][0], l[0][1], l[0][2]), l[1], int(l[2])])
	_dummies.clear()
	for p in d.get("dummies", []):
		_dummies.append(Vector3i(int(p[0]), int(p[1]), int(p[2])))
	natural_spawns = bool(d.get("natural_spawns", false))
