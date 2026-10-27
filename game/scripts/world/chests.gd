class_name Chests
extends RefCounted
## Chest contents by block position. Worldgen chests roll their loot the first
## time they are opened; player-placed chests start empty.

const SIZE := 40
## Chests less than this far under the surface roll surface loot
## (Terraria's worldSurface + 25 tiles).
const SURFACE_DEPTH := 25.0 * 2.0 / 3.0

var _chests := {}  # "x,y,z" -> Inventory
var _worldgen := {}  # keys of unopened worldgen chests -> true
## Every worldgen chest's loot table by its key (from the world's chest
## decorations, saved with it), and those that hold a Shadow Key too.
var _tables := {}
var _shadow_keys := {}
## Which ore of each pair the world has (worldgen.rs: the "ores" decoration,
## bit k for the second of pair k): its chests' bars are the world's, as
## Terraria's are (GenVars.goldBar...).
var ores := 0
## Worldgen chests' loot tables by their decoration's style: 0 an underground
## chest, 1 a sky island's, 2 a living mahogany tree's Ivy Chest, 3 a cabin's
## (Gold or Rich Mahogany Chest), 4 an ice cabin's Frozen Chest, 5 and 6 a
## desert cabin's Sandstone Chest (the upper and the deeper desert), 7 to 14
## the Dungeon's chests in Terraria's order (dungeon.rs: DUNGEON_LOOT), 15 a
## mushroom cabin's Mushroom Chest, 16 to 20 the Underworld's Shadow Chests by
## their main item (hell.rs: SHADOW_LOOT), 21 to 26 the Dungeon's locked
## biome chests (dungeon.rs: BIOME_LOOT; their keys and Hardmode loot aren't
## in the game yet, so they stay locked), 27 a living tree's Living Wood
## Chest, 28 a spider cave's Web Covered Chest (spiders.rs: WEB_CHEST_LOOT), 29
## a Pyramid's Gold Chest (pyramids.rs).
## SHADOW_KEY added to a style: a Shadow Key in it too (the Dungeon's first
## chest, and 1 in 3 after it).
const LOOT := ["chest", "sky_chest", "ivy_chest", "chest", "frozen_chest", "sandstone_chest", "sandstone_chest_deep",
		"dungeon_Muramasa", "dungeon_CobaltShield", "dungeon_AquaScepter", "dungeon_BlueMoon", "dungeon_MagicMissile",
		"dungeon_Valor", "dungeon_GoldenKey", "dungeon_Handgun", "mushroom_chest",
		"shadow_DarkLance", "shadow_Sunfury", "shadow_FlowerofFire", "shadow_Flamelash", "shadow_HellwingBow",
		"biome_jungle", "biome_corruption", "biome_crimson", "biome_hallowed", "biome_frozen", "biome_desert", "living_chest", "web_chest", "pyramid"]
const SHADOW_KEY := 64
## The second ore of each pair's things, by the first's: what a world with it
## puts in its chests instead.
const WORLD_ORE := {"CopperBar": [0, "TinBar"], "IronBar": [1, "LeadBar"], "SilverBar": [2, "TungstenBar"],
		"SilverBullet": [2, "TungstenBullet"], "GoldBar": [3, "PlatinumBar"]}


static func key(p: Vector3i) -> String:
	return "%d,%d,%d" % [p.x, p.y, p.z]


func setup(world: VoxelWorld) -> void:
	for d in world.get_decorations():
		if d.kind == "chest":
			var k := key(d.pos)
			_tables[k] = LOOT[clampi(int(d.style) & (SHADOW_KEY - 1), 0, LOOT.size() - 1)]
			if int(d.style) & SHADOW_KEY:
				_shadow_keys[k] = true
			if not _chests.has(k):
				_worldgen[k] = true
		elif d.kind == "ores":
			ores = int(d.style)


## The world's own of an item that comes in a pair (a Platinum Bar for a Gold
## Bar in a world with Platinum).
func world_item(item: String) -> String:
	var pair: Array = WORLD_ORE.get(item, [])
	return pair[1] if not pair.is_empty() and ores & (1 << int(pair[0])) else item


func register_new(p: Vector3i) -> void:
	_chests[key(p)] = Inventory.new(SIZE)


func get_inventory(p: Vector3i) -> Inventory:
	var k := key(p)
	if not _chests.has(k):
		var inv := Inventory.new(SIZE)
		if _worldgen.has(k):
			var table: String = _tables.get(k, "chest")
			_worldgen.erase(k)
			var game := Game.current
			# By depth, like Terraria's AddBuriedChest: near the surface its
			# surface loot, below the lava line a chance of a Lava Charm.
			if game != null and p.y > game.surface_level - SURFACE_DEPTH and Data.loot.has(table + "_surface"):
				table += "_surface"
			var lava := game != null and p.y < game.lava_level()
			# Each with a prefix rolled, as Terraria's AddBuriedChest does.
			var drops := Game.roll_loot(table, lava)
			if _shadow_keys.has(k):
				drops.append(["ShadowKey", 1])
			for drop in drops:
				var item := world_item(drop[0])
				inv.add(item, drop[1], Prefixes.roll(Data.item(item)))
		_chests[k] = inv
	return _chests[k]


func is_empty(p: Vector3i) -> bool:
	var k := key(p)
	if _worldgen.has(k):
		return false
	return not _chests.has(k) or _chests[k].is_empty()


func remove(p: Vector3i) -> void:
	_chests.erase(key(p))
	_worldgen.erase(key(p))
	_tables.erase(key(p))
	_shadow_keys.erase(key(p))


func save_state() -> Dictionary:
	var out := {}
	for k in _chests:
		out[k] = _chests[k].to_data()
	return {"chests": out, "unopened": _worldgen.keys()}


func load_state(d: Dictionary) -> void:
	_chests.clear()
	_worldgen.clear()
	var chests: Dictionary = d.get("chests", {})
	for k in chests:
		var inv := Inventory.new(SIZE)
		inv.from_data(chests[k])
		_chests[k] = inv
	for k in d.get("unopened", []):
		_worldgen[k] = true
