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
	# The Goblin Army near you: its goblins, up to 10 at once, a lot faster
	# than anything else (Terraria's invasion spawn rate).
	if game.invasion.near(player.global_position) and not game.boss_alive():
		if game.npcs().filter(func(n): return n.def.get("invasion", "") != "").size() < INVASION_CAP:
			var g := _pick(Invasion.SPAWNS)
			var at = _find_spot(game, player.global_position, false, false)
			if at != null:
				game.spawn_npc(g, at)
		return
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
	# Goblin Scouts by day on the outer sixths of the surface (here the outer
	# third of the island across): 1 in 15, 1 in 5 once an orb is smashed
	# and the army isn't beaten.
	if depth == "surface" and not night and game.biome == "" and _outer(game, player.global_position) \
			and randi() % (5 if game.orbs_broken > 0 and not game.invasion.downed else 15) == 0:
		kind = "GoblinScout"
	# Once the army is beaten, the Goblin Tinkerer, bound, deep in the caverns
	# (one at a time, till he's freed).
	if depth == "caverns" and game.invasion.downed and not game.town.arrived.has("GoblinTinkerer") and randi() % 20 == 0 \
			and not game.npcs().any(func(n): return n.kind == "BoundGoblin"):
		kind = "BoundGoblin"
	var flying: bool = Data.npcs[kind].ai in ["flyer", "bat", "harpy"]
	var pos = _find_water_spot(game, player.global_position, NPC.look(kind).hitbox) if Data.npcs[kind].ai == "swim" \
			else _find_spot(game, player.global_position, depth in ["underground", "caverns"], flying)
	if pos != null:
		game.spawn_npc(kind, pos)


const INVASION_CAP := 10


## Out in the world's outer third (Terraria's outer sixths of its width).
func _outer(game, p: Vector3) -> bool:
	var size: Vector3i = game.world.get_size()
	return absf(p.x - size.x * 0.5) > size.x / 3.0 or absf(p.z - size.z * 0.5) > size.z / 3.0


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
	var table: Array
	match depth:
		"space":
			return [["Harpy", 1]]
		"surface":
			return [["Zombie", 6], ["DemonEye", 4]] if night else [["GreenSlime", 6], ["BlueSlime", 3]]
		"underground":
			table = [["BlueSlime", 4], ["RedSlime", 2], ["CaveBat", 4], ["Skeleton", 1]]
		_:
			table = [["Skeleton", 4], ["CaveBat", 4], ["RedSlime", 2], ["YellowSlime", 2]]
	# The Glowing Mushroom biome: Terraria's Spore Skeletons and Spore Bats in
	# place of the Skeletons and bats (before Hardmode its own enemies are
	# only those; the rest come with Hardmode).
	if biome == "mushroom":
		table = table.map(func(e): return [{"Skeleton": "SporeSkeleton", "CaveBat": "SporeBat"}.get(e[0], e[0]), e[1]])
	return table


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
