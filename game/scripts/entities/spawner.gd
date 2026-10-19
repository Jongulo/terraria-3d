class_name Spawner
extends Node
## Terraria-style enemy spawning: out of sight but nearby, capped, with
## tables by depth and time of day.

const INTERVAL := 1.0

var _timer := 0.0


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL
	var game := Game.current
	var player: Player = game.player
	if not player.alive:
		return
	var depth := _depth(player.global_position.y, game)
	var night := not game.sky.is_day
	var cap := 4
	if depth == "space":
		cap = 3
	elif depth == "surface" and night:
		cap = 8
	elif depth != "surface":
		cap = 7
	if game.boss_alive():
		cap = 2
	if game.npcs().filter(func(n): return n.def.ai != "town").size() >= cap:
		return
	if randf() > 0.45:
		return
	if game.biome == "dungeon":
		# Below the ground before Skeletron is beaten, the Dungeon Guardian
		# comes for you (Terraria's); its other enemies aren't in yet.
		var p := player.global_position
		if not game.defeated_bosses.has("SkeletronHead") and not game.boss_alive() and p.y < game.world.surface_y(floori(p.x), floori(p.z)) \
				and not game.npcs().any(func(n): return n.kind == "DungeonGuardian"):
			game.spawn_npc("DungeonGuardian", p + Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1)).normalized() * 40.0)
		return
	var table := _table(depth, night, game.biome)
	var kind: String = _pick(table)
	var flying: bool = Data.npcs[kind].ai in ["flyer", "bat", "harpy"]
	var pos = _find_water_spot(game, player.global_position, NPC.look(kind).hitbox) if Data.npcs[kind].ai == "swim" \
			else _find_spot(game, player.global_position, depth in ["underground", "caverns"], flying)
	if pos != null:
		game.spawn_npc(kind, pos)


func _depth(y: float, game) -> String:
	if y > game.space_level():
		return "space"
	if y > game.surface_level - 12:
		return "surface"
	if y > game.cavern_level:
		return "underground"
	return "caverns"


## Weighted spawn tables: [kind, weight].
func _table(depth: String, night: bool, biome := "") -> Array:
	# The ocean: crabs on the beach, jellyfish and sharks in the sea.
	if biome == "ocean" and depth == "surface":
		return [["Crab", 4], ["PinkJellyfish", 3], ["Shark", 2]]
	# Snow, Desert and Jungle: their own enemies on the surface and below.
	var under := depth in ["underground", "caverns"]
	if biome == "snow" and depth != "space":
		if under:
			return [["IceBat", 4], ["IceSlime", 2], ["SpikedIceSlime", 2]]
		return [["ZombieEskimo", 5], ["IceSlime", 3]] if night else [["IceSlime", 6]]
	if biome == "desert" and depth != "space":
		if under:
			return [["WalkingAntlion", 4], ["Antlion", 2]]
		return [["Antlion", 4], ["Vulture", 2], ["Zombie", 3]] if night else [["Antlion", 4], ["Vulture", 3]]
	if biome == "jungle" and depth != "space":
		if under:
			return [["JungleBat", 4], ["Hornet", 3], ["ManEater", 2], ["JungleSlime", 2], ["Piranha", 1]]
		return [["JungleSlime", 5], ["Snatcher", 3]] + ([["DemonEye", 2]] if night else [])
	# The evil biomes bring their own enemies (not in Space or the Underworld).
	if biome == "corruption" and depth != "space":
		return [["EaterofSouls", 6], ["Zombie", 2]] if night and depth == "surface" else [["EaterofSouls", 6]]
	if biome == "crimson" and depth != "space":
		var t := [["Crimera", 5], ["FaceMonster", 4]]
		return t + [["Zombie", 2]] if night and depth == "surface" else t
	match depth:
		"space":
			return [["Harpy", 1]]
		"surface":
			return [["Zombie", 6], ["DemonEye", 4]] if night else [["GreenSlime", 6], ["BlueSlime", 3]]
		"underground":
			return [["BlueSlime", 4], ["RedSlime", 2], ["CaveBat", 4], ["Skeleton", 1]]
		_:
			return [["Skeleton", 4], ["CaveBat", 4], ["RedSlime", 2], ["YellowSlime", 2]]


func _pick(table: Array) -> String:
	var total := 0
	for e in table:
		total += int(e[1])
	var r := randi() % total
	for e in table:
		r -= int(e[1])
		if r < 0:
			return e[0]
	return table[0][0]


## Open water 15-40 blocks away, deep enough for a `size` swimmer: the sea
## (from sea level down), or wherever the player is swimming.
func _find_water_spot(game, origin: Vector3, size: Array):
	var world: VoxelWorld = game.world
	var need := ceili(float(size[1])) + 1
	for attempt in 12:
		var a := randf() * TAU
		var p := origin + Vector3(cos(a), 0, sin(a)) * randf_range(15.0, 40.0)
		var x := floori(p.x)
		var z := floori(p.z)
		var top := maxi(game.sea_level, floori(origin.y) + 4)
		var run := 0
		for y in range(top, top - 40, -1):
			var l := world.get_liquid(Vector3i(x, y, z))
			if l.x == 1 and l.y > 8:
				run += 1
				if run >= need:
					return Vector3(x + 0.5, y, z + 0.5)
			elif world.is_solid(Vector3i(x, y, z)):
				break
			else:
				run = 0
	return null


## A free spot 20-45 blocks away (closer in caves), behind the player's view if possible.
func _find_spot(game, origin: Vector3, underground: bool, flying: bool):
	var world: VoxelWorld = game.world
	var fwd: Vector3 = game.player.forward()
	for attempt in 12:
		var dist := randf_range(14.0, 30.0) if underground else randf_range(22.0, 45.0)
		var a := randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		if dir.dot(fwd) > 0.6 and attempt < 8:
			continue  # prefer off-screen spawns
		var p := origin + dir * dist
		var x := int(floor(p.x))
		var z := int(floor(p.z))
		if flying and not underground:
			var top := world.surface_y(x, z)
			if top >= 0:
				return Vector3(x + 0.5, maxf(top + 8.0, origin.y + 6.0), z + 0.5)
			continue
		# Search vertically near the player's height for floor with headroom.
		var y0 := int(origin.y)
		for dy in range(0, 24):
			for y in [y0 - dy, y0 + dy]:
				var c := Vector3i(x, y, z)
				if not world.is_solid(c) and not world.is_solid(c + Vector3i.UP) and world.is_solid(c + Vector3i.DOWN):
					# Surface spawns need sky access; cave spawns need darkness.
					var light := world.get_light(Vector3(c))
					if underground and light.a > 0.5:
						continue
					if not underground and light.a < 0.9:
						continue
					return Vector3(x + 0.5, y, z + 0.5)
	return null
