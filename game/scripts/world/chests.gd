class_name Chests
extends RefCounted
## Chest contents by block position. Worldgen chests roll their loot the first
## time they are opened; player-placed chests start empty.

const SIZE := 40

var _chests := {}  # "x,y,z" -> Inventory
var _worldgen := {}  # keys of unopened worldgen chests -> loot table
## Worldgen chests' loot tables by their decoration's style: 0 an underground
## chest, 1 a sky island's, 2 a living mahogany tree's Ivy Chest, 3 a cabin's
## (Gold or Rich Mahogany Chest), 4 an ice cabin's Frozen Chest, 5 and 6 a
## desert cabin's Sandstone Chest (the upper and the deeper desert), 7 to 14
## the Dungeon's chests in Terraria's order (dungeon.rs: DUNGEON_LOOT), 15 a
## mushroom cabin's Mushroom Chest.
const LOOT := ["chest", "sky_chest", "ivy_chest", "chest", "frozen_chest", "sandstone_chest", "sandstone_chest_deep",
		"dungeon_Muramasa", "dungeon_CobaltShield", "dungeon_AquaScepter", "dungeon_BlueMoon", "dungeon_MagicMissile",
		"dungeon_Valor", "dungeon_GoldenKey", "dungeon_Handgun", "mushroom_chest"]


static func key(p: Vector3i) -> String:
	return "%d,%d,%d" % [p.x, p.y, p.z]


func setup(world: VoxelWorld) -> void:
	for d in world.get_decorations():
		if d.kind == "chest":
			var k := key(d.pos)
			if not _chests.has(k):
				_worldgen[k] = LOOT[clampi(int(d.style), 0, LOOT.size() - 1)]


func register_new(p: Vector3i) -> void:
	_chests[key(p)] = Inventory.new(SIZE)


func get_inventory(p: Vector3i) -> Inventory:
	var k := key(p)
	if not _chests.has(k):
		var inv := Inventory.new(SIZE)
		if _worldgen.has(k):
			var table: String = _worldgen[k]
			_worldgen.erase(k)
			for drop in Game.roll_loot(table):
				inv.add(drop[0], drop[1])
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
