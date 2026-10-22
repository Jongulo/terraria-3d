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
	spawn_tick()


## One spawn attempt near the player (once a second).
func spawn_tick() -> void:
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
	# Critters have their own spawns (spawn_critter) and don't count here.
	# (None in the Dungeon: Terraria's Dungeon spawns are its own.)
	if not game.boss_alive() and not game.invasion.near(player.global_position) and game.biome != "dungeon":
		spawn_critter(game, player, depth, night)
	var cap := 4
	if depth == "space":
		cap = 3
	elif depth == "surface" and night:
		cap = 8
	elif depth != "surface":
		cap = 7
	if game.boss_alive():
		cap = 2
	if game.npcs().filter(func(n): return n.def.ai != "town" and not n.is_critter()).size() >= cap:
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
	# The Sleeping Angler (Terraria's SpawnAnNPC): till he's woken, a spawn
	# in the ocean's water is him, asleep on the surface (one at a time).
	if game.biome == "ocean" and depth == "surface" and not game.town.arrived.has("Angler") \
			and not game.npcs().any(func(n): return n.kind == "SleepingAngler"):
		var spot = _find_water_spot(game, player.global_position, [1.0, 1.0])
		if spot != null:
			var top := Vector3i(spot.floor())
			while game.world.get_liquid(top + Vector3i.UP).y > 0:
				top.y += 1
			game.spawn_npc("SleepingAngler", Vector3(top) + Vector3(0.5, 0.95, 0.5))
			return
	var kind: String
	if depth == "underworld":
		kind = underworld_pick(game.npcs().any(func(n): return n.kind == "BoneSerpentHead"))
		if kind == "":
			return
	else:
		kind = _pick(_table(depth, night, game.biome))
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
			else _find_spot(game, player.global_position, depth in ["underground", "caverns", "underworld"], flying)
	if pos != null:
		game.spawn_npc(kind, pos)


const INVASION_CAP := 10
## Critters about you at most (they don't take enemies' places).
const CRITTER_CAP := 6
const CRITTER_RANGE := 60.0
## Terraria's goldCritterChance: 1 in 400 is gold.
const GOLD_CHANCE := 400
## The world's odds for butterflies and fireflies (Terraria's
## NPC.setFireFlyChance, rolled each dawn): fireflies 1 in fireFlyChance at
## night on grass, each with another 1 in fireFlyMultiple on each side;
## butterflies 1 in butterflyChance by day (some days none).
var firefly_chance := 20
var firefly_multiple := 10
var butterfly_chance := 10
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	roll_critter_odds()


## NPC.setFireFlyChance.
func roll_critter_odds() -> void:
	if _rng.randi_range(0, 8) == 0:
		firefly_chance = _rng.randi_range(5, 9)
		firefly_multiple = _rng.randi_range(3, 7)
	elif _rng.randi_range(0, 2) == 0:
		firefly_chance = 999999
		firefly_multiple = 999999
	else:
		firefly_chance = _rng.randi_range(10, 59)
		firefly_multiple = _rng.randi_range(6, 29)
	butterfly_chance = 999999 if _rng.randi_range(0, 2) == 0 else _rng.randi_range(1, 20)
	if _rng.randi_range(0, 4) == 0:
		butterfly_chance = 999999


func _one_in(n: int) -> bool:
	return _rng.randi_range(0, maxi(n, 1) - 1) == 0


## A gold one 1 in 400 (Terraria's RollLuck(goldCritterChance)).
func _gold(normal: String, gold: String) -> String:
	return gold if _one_in(GOLD_CHANCE) else normal


## Terraria's critter spawns (Spawner.SpawnAnNPC's): by day on the surface
## bunnies, squirrels, butterflies (on butterfly days), birds in the morning,
## penguins on snow, scorpions on sand, macaws and frogs in the Jungle; at
## night fireflies on grass; ducks (and turtles, grebes) on surface water,
## goldfish in it; worms, mice and snails underground; glowing snails on
## mushroom grass; the Underworld's Hell Butterflies, Lavaflies and Magma
## Snails. Gold ones 1 in 400.
func spawn_critter(game, player, depth: String, night: bool) -> void:
	var p: Vector3 = player.global_position
	var near := 0
	var birds := 0
	for n in game.npcs():
		if n.is_critter() and n.global_position.distance_to(p) < CRITTER_RANGE:
			near += 1
			if n.def.ai == "bird":
				birds += 1
	if near >= CRITTER_CAP:
		return
	var w: VoxelWorld = game.world
	if depth == "surface" and _one_in(4):
		var spot = _find_water_spot(game, p, [0.6, 0.6])
		if spot != null:
			var top := Vector3i(spot.floor())
			while w.get_liquid(top + Vector3i.UP).y > 0:
				top.y += 1
			var bottom := Vector3i(spot.floor())
			while bottom.y > 0 and not w.is_solid(bottom):
				bottom.y -= 1
			var under: String = Data.block(w.get_block(bottom)).get("name", "")
			if not night and not _one_in(3) and not game.in_ocean(spot):
				var kind := "Duck" if _one_in(2) else "DuckWhite"
				if under == "mud" or under == "jungle_grass":
					kind = "TurtleJungle"
				elif under == "sand":
					kind = "Grebe"
				elif _one_in(5):
					kind = "Turtle"
				game.spawn_npc(kind, Vector3(top) + Vector3(0.5, 0.75, 0.5))
			elif not game.in_ocean(spot):
				game.spawn_npc("Pupfish" if under == "sand" else _gold("Goldfish", "GoldGoldfish"), spot)
			return
	var under_ground: bool = depth in ["underground", "caverns", "underworld"]
	var at = _find_spot(game, p, under_ground, false)
	if at == null:
		return
	var ground: String = Data.block(w.get_block(Vector3i(at.floor()) + Vector3i.DOWN)).get("name", "")
	for c in pick_critters(game, at, ground, depth, night, birds):
		game.spawn_npc(c[0], c[1])


## Which critters come at `at`, on `ground` (a block name): [[kind, where], ...]
## (the rules of spawn_critter for a spot on land).
func pick_critters(game, at: Vector3, ground: String, depth: String, night: bool, birds := 0) -> Array:
	var out := []
	var biome: String = game.biome
	var grass: bool = ground in ["grass", "hallowed_grass"]
	if at.y < game.underworld_level:
		if _one_in(10):
			if _one_in(3):
				out.append(["MagmaSnail", at])
			elif not night:
				out.append(["HellButterfly", at + Vector3(0, 1.5, 0)])
			else:
				out.append_array(_group("Lavafly", at + Vector3(0, 1.5, 0), firefly_multiple))
		return out
	if ground == "mushroom_grass":
		if _one_in(6):
			out.append(["GlowingSnail", at])
		return out
	if depth in ["underground", "caverns"]:
		if biome in ["snow", "crimson", "corruption", "jungle"]:
			return out
		if _one_in(8):
			out.append([_gold("Worm", "GoldWorm"), at])
		elif _one_in(13):
			out.append([_gold("Mouse", "GoldMouse"), at])
		elif _one_in(13) and at.y > (game.cavern_level + game.underworld_level) * 0.5:
			out.append(["Snail", at])
		return out
	if depth != "surface":
		return out
	if night:
		if grass and _one_in(firefly_chance):
			out.append_array(_group("LightningBug" if ground == "hallowed_grass" else "Firefly", at + Vector3(0, 1.0, 0), firefly_multiple))
		return out
	if ground in ["snow_block", "ice_block"]:
		if _one_in(15):
			out.append(["Penguin" if _one_in(2) else "PenguinBlack", at])
	elif grass:
		if _one_in(15):
			if _one_in(butterfly_chance):
				out.append([_gold("Butterfly", "GoldButterfly"), at + Vector3(0, 1.0, 0)])
				for side in [-1, 1]:
					if _one_in(4):
						out.append(["Butterfly", at + Vector3(side * 0.67, 1.0, 0)])
			elif _one_in(GOLD_CHANCE):
				out.append(["GoldBunny", at])
			elif _one_in(GOLD_CHANCE):
				out.append(["SquirrelGold", at])
			elif _one_in(3):
				out.append(["Squirrel" if _one_in(2) else "SquirrelRed", at])
			else:
				out.append(["Bunny", at])
		elif game.sky.time < 18000.0 and _one_in(4) and birds < 6:
			out.append([_bird(), at])
	elif ground == "sand" and not game.in_ocean(at) and _one_in(12):
		out.append(["ScorpionBlack" if _one_in(2) else "Scorpion", at])
	elif ground == "jungle_grass" and _one_in(7):
		if game.sky.time < 43200.0 and not _one_in(3):
			out.append([["ScarletMacaw", "BlueMacaw", "Toucan", "YellowCockatiel", "GrayCockatiel"][_rng.randi_range(0, 4)], at])
		else:
			out.append([_gold("Frog", "GoldFrog"), at])
	return out


## Terraria's birds: gold 1 in 400, else a Blue Jay or a Cardinal 1 in 4 each, a Bird.
func _bird() -> String:
	var r := _rng.randi_range(0, 3)
	if _one_in(GOLD_CHANCE):
		return "GoldBird"
	return "BirdBlue" if r == 0 else "BirdRed" if r == 1 else "Bird"


## One, and another 1 in `multiple` on each side, above and below (fireflies).
func _group(kind: String, at: Vector3, multiple: int) -> Array:
	var out := [[kind, at]]
	for off in [Vector3(-0.67, 0, 0), Vector3(0.67, 0, 0), Vector3(0, 0.67, 0), Vector3(0, -0.67, 0)]:
		if _one_in(multiple):
			out.append([kind, at + off])
	return out


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
	if y < game.underworld_level:
		return "underworld"
	return "caverns"


## Terraria's Underworld spawns (Spawner.SpawnAnNPC below its last 190
## tiles, before Hardmode), in its order: 1 in 8 a lava critter (here
## spawn_critter's, so no enemy: ""), else 1 in 40 a Bone Serpent while
## there's none, 1 in 14 a Fire Imp, 1 in 7 a Demon (1 in 10 of those a
## Voodoo Demon), 1 in 3 a Lava Slime, else a Hellbat.
static func underworld_pick(serpent_alive: bool) -> String:
	if randi() % 8 == 0:
		return ""
	if randi() % 40 == 0 and not serpent_alive:
		return "BoneSerpentHead"
	if randi() % 14 == 0:
		return "FireImp"
	if randi() % 7 == 0:
		return "VoodooDemon" if randi() % 10 == 0 else "Demon"
	if randi() % 3 == 0:
		return "LavaSlime"
	return "Hellbat"


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
