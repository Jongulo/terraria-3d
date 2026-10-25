class_name Spawner
extends Node
## Terraria-style enemy spawning: out of sight but nearby, capped, with
## tables by depth and time of day.

const INTERVAL := 1.0

var _timer := 0.0
var _slime_acc := 0.0


## Slime Rain's slimes (Terraria's Spawner.SlimeRainSpawns), a tick at a
## time: with you on the surface and fewer than 15 enemies about, 1 tick in
## 45 (more the more there are: 45 + 450 x a fifteenth of them) a slime
## starts high over you (0.75 to 1.5 of Terraria's screen heights up: 37 to
## 75 blocks; within 40 blocks across) where there's room and no roof: 1 in
## 200 a Pinky, else 1 in 10 a Purple Slime, 2 in 5 of the rest a Green
## Slime, else a Blue Slime.
func slime_rain_tick() -> void:
	var game := Game.current
	if game == null or game.state != Game.State.PLAYING or not game.sky.slime_rain:
		return
	var player: Player = game.player
	if not player.alive or player.global_position.y < game.surface_level - 12.0:
		return
	var near := game.npcs().filter(func(n): return n.def.ai != "town" and not n.is_critter() \
			and n.global_position.distance_to(player.global_position) < 60.0).size()
	if near > 15:
		return
	if randi() % (45 + int(450.0 * near / 15.0)) != 0:
		return
	var a := randf() * TAU
	var r := sqrt(randf()) * 40.0
	var at := player.global_position + Vector3(cos(a) * r, randf_range(37.0, 75.0), sin(a) * r)
	var size: Vector3i = game.world.get_size()
	if at.x < 10 or at.z < 10 or at.x > size.x - 10 or at.z > size.z - 10 or at.y > size.y - 4:
		return
	var cell := Vector3i(at.floor())
	if game.world.surface_y(cell.x, cell.z) >= cell.y:
		return
	for x in range(-2, 3):
		for z in range(-2, 3):
			for y in range(-3, 2):
				if game.world.is_solid(cell + Vector3i(x, y, z)):
					return
	var kind := "BlueSlime"
	if randi() % 200 == 0:
		kind = "Pinky"
	elif randi() % 10 == 0:
		kind = "PurpleSlime"
	elif randi() % 5 < 2:
		kind = "GreenSlime"
	game.spawn_npc(kind, at)


func _physics_process(delta: float) -> void:
	_slime_acc = minf(_slime_acc + delta, 0.25)
	while _slime_acc >= 1.0 / 60.0:
		_slime_acc -= 1.0 / 60.0
		slime_rain_tick()
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
	# The Dungeon: Terraria's spawn rate x0.3 (here always a try), its cap
	# x1.8.
	var dungeon: bool = game.biome == "dungeon"
	if dungeon:
		cap = int(round(cap * 1.8))
	# The Blood Moon (GetSpawnRate): x1.8 as many, at 0.3 the wait.
	var blood: bool = game.sky.blood_moon and night and depth == "surface"
	if blood:
		cap = int(round(cap * 1.8))
	if game.boss_alive():
		cap = 2
	# The Battle Potion: spawns twice as often, twice as many; the Calming
	# Potion: 1.3 times as seldom, 0.7 as many (spawnRate, maxSpawns).
	var rate := 1.0 if dungeon else (minf(1.0, 0.45 / 0.3) if blood else 0.45)
	if player.has_effect("battle"):
		cap *= 2
		rate *= 2.0
	if player.has_effect("calm"):
		cap = int(cap * 0.7)
		rate /= 1.3
	if game.npcs().filter(func(n): return n.def.ai != "town" and not n.is_critter()).size() >= cap:
		return
	if randf() > rate:
		return
	if dungeon:
		# Below the ground before Skeletron is beaten, the Dungeon Guardian
		# comes for you (Terraria's); after, the Dungeon's own.
		var p := player.global_position
		if not game.defeated_bosses.has("SkeletronHead"):
			if not game.boss_alive() and p.y < game.world.surface_y(floori(p.x), floori(p.z)) \
					and not game.npcs().any(func(n): return n.kind == "DungeonGuardian"):
				game.spawn_npc("DungeonGuardian", p + Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1)).normalized() * 40.0)
			return
		_spawn_dungeon(game, p)
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
		kind = surface_pick(game.biome, night, game.sky) if depth == "surface" else ""
		if kind == "":
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
	var flying: bool = Data.npcs[kind].ai in ["flyer", "bat", "harpy", "flying_fish", "hover", "granite_flyer"]
	var pos = _find_water_spot(game, player.global_position, NPC.look(kind).hitbox) if Data.npcs[kind].ai == "swim" \
			else _find_spot(game, player.global_position, depth in ["underground", "caverns", "underworld"], flying)
	# The mini-biomes' own, at a spot in a cave (cave_pick).
	if pos != null and depth in ["underground", "caverns"] and kind != "BoundGoblin":
		var own := cave_pick(game, pos, player.global_position)
		if own != "":
			kind = own
			if Data.npcs[kind].ai == "granite_flyer":
				pos += Vector3(0, 1.0, 0)
	# Any of Terraria's NPC 1 slimes spawning is a Pinky 1 time in 180
	# (Spawner.SpawnNPC).
	if kind in Game.SLIME_RAIN_SLIMES and randi() % 180 == 0:
		kind = "Pinky"
	if pos != null:
		game.spawn_npc(kind, pos)


## The Dungeon's spawns once Skeletron is beaten (Terraria's SpawnNPC with
## ZoneDungeon): a spot in the Dungeon, its wall there (Game.dungeon_wall: 0
## brick, 1 slab, 2 tiled; 1 time in 7 any of them) picking from the chain.
func _spawn_dungeon(game, p: Vector3) -> void:
	for attempt in 6:
		var at = _find_spot(game, p, true, false)
		if at == null or game.detect_biome(at + Vector3(0, 0.5, 0)) != "dungeon":
			continue
		var wall: int = game.dungeon_wall(at)
		if randi() % 7 == 0:
			wall = randi() % 3
		var spikes_near: bool = game.npcs().any(func(n): return n.kind == "SpikeBall" and absf(n._hang.x - at.x) < SPIKE_BALL_ROOM \
				and absf(n._hang.y - at.y) < SPIKE_BALL_ROOM and absf(n._hang.z - at.z) < SPIKE_BALL_ROOM)
		# The Bound Mechanic, 1 in 5 till she's freed (one at a time, not in
		# water, a fifth of the way from the surface down to the caverns).
		if bound_mechanic_here(game, at) and randi() % 5 == 0:
			game.spawn_npc("BoundMechanic", at)
			return
		var book = [null]
		var find_book := func() -> bool:
			book[0] = _book_near(game, at)
			return book[0] != null
		var kind := dungeon_pick(wall, spikes_near, find_book)
		if kind in ["WaterBoltMimic", "LibrarianSkeleton"]:
			# In front of the book (the Librarian on the floor under it).
			var b: Vector3i = book[0]
			var spot := Vector3(b) + Vector3(0.5, 0.5, 0.5)
			if kind == "LibrarianSkeleton":
				var cell: Vector3i = b
				while cell.y > b.y - 8 and not game.world.is_solid(cell + Vector3i.DOWN):
					cell += Vector3i.DOWN
				spot = Vector3(cell.x + 0.5, cell.y, cell.z + 0.5)
			game.spawn_npc(kind, spot)
			return
		if kind == "":
			return
		var flies: bool = Data.npcs[kind].ai in ["skull", "spike_ball", "wheel"]
		game.spawn_npc(kind, at + (Vector3(0, 1.0, 0) if flies else Vector3.ZERO))
		return


## Whether the Bound Mechanic can turn up at `at` (Terraria: savedMech not
## set, none about, no water there, below a fifth of the way from the surface
## to the rock layer).
static func bound_mechanic_here(game, at: Vector3) -> bool:
	if game.town.arrived.has("Mechanic") or game.npcs().any(func(n): return n.kind == "BoundMechanic"):
		return false
	if game.world.get_liquid(Vector3i(at.floor())).y > 0:
		return false
	var l: Dictionary = game.world.get_layers()
	return at.y < (float(l.surface) * 4.0 + float(l.cavern_top)) / 5.0


## A placed book within 16 blocks of `at` (Terraria's AI_FindNearbyBook over
## 32 x 32 tiles round the spawn spot), the nearest to it that's out of the
## player's sight (as the spawns are: 14 blocks off and not ahead of them).
static func _book_near(game, at: Vector3):
	var p = game.player
	var books: PackedInt32Array = game.world.find_blocks(Vector3i(at.floor()), Vector3i(16, 16, 16), NPC.book_ids(), 256)
	var best = null
	var best_d := INF
	for i in range(0, books.size(), 3):
		var b := Vector3i(books[i], books[i + 1], books[i + 2])
		var from_player: Vector3 = Vector3(b) + Vector3(0.5, 0.5, 0.5) - p.global_position
		if from_player.length() < 14.0 or from_player.normalized().dot(p.forward()) > 0.6:
			continue
		var d := at.distance_to(Vector3(b))
		if d < best_d:
			best_d = d
			best = b
	return best


## No Spike Ball within 300 px of another's anchor (Terraria's NearSpikeBall).
const SPIKE_BALL_ROOM := 300.0 / 24.0


## Terraria's Dungeon chain, roll by roll: 1 in 35 a Dungeon Slime; on slab
## walls 1 in 3 a Spike Ball (none near another), on tiled walls 1 in 5 a
## Blazing Wheel, on brick 1 in 7 a Cursed Skull; 1 in 7 a Dark Caster; then
## 1 in 8 a Water Bolt Mimic, else 1 in 10 a Librarian Skeleton, by a placed
## book that `book_near` finds (none: nothing spawns, ""); then Angry Bones:
## 1 in 5 each the three big ones, else 1 in 4 Big Boned, 1 in 5 Short
## Bones, else the plain one. (Not yet: the Bound Mechanic.)
static func dungeon_pick(wall: int, spikes_near: bool, book_near := Callable()) -> String:
	if randi() % 35 == 0:
		return "DungeonSlime"
	if wall == 1 and randi() % 3 == 0 and not spikes_near:
		return "SpikeBall"
	if wall == 2 and randi() % 5 == 0:
		return "BlazingWheel"
	if wall == 0 and randi() % 7 == 0:
		return "CursedSkull"
	if randi() % 7 == 0:
		return "DarkCaster"
	# 1.4.5's book dwellers, in front of a placed book (none: nothing spawns).
	var bookish := ""
	if randi() % 8 == 0:
		bookish = "WaterBoltMimic" if book_near.is_valid() and book_near.call() else "-"
	elif randi() % 10 == 0:
		bookish = "LibrarianSkeleton" if book_near.is_valid() and book_near.call() else "-"
	var r := randi() % 5
	if bookish != "":
		return "" if bookish == "-" else bookish
	if r < 3:
		return ["AngryBonesBig", "AngryBonesBigMuscle", "AngryBonesBigHelmet"][r]
	if randi() % 4 == 0:
		return "BigBoned"
	if randi() % 5 == 0:
		return "ShortBones"
	return "AngryBones"


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


## Terraria's mini-biome spawns underground (Spawner.SpawnAnNPC, before
## Hardmode), for a spot `at` in a cave with you at `you`: in a spider cave
## (its spider walls) a Wall Creeper; else (out of the big biomes, in half
## its cave spawns) near marble 3 in 4 a Hoplite, near granite 4 in 5 a
## Granite Elemental 5 in 6 while there's none, else a Granite Golem. Near:
## a block of it within 20 to 30 tiles of the spot or 30 to 60 of you
## (Terraria's nearMarble, nearGranite). "" for the usual spawns.
func cave_pick(game, at: Vector3, you: Vector3) -> String:
	if game.in_spider_cave(at):
		return "WallCreeper"
	if game.biome != "" or randi() % 2 != 0:
		return ""
	var stone := _stone_near(game, at, you)
	if stone == "marble" and randi() % 4 != 0:
		return "GreekSkeleton"
	if stone == "granite" and randi() % 5 != 0:
		if randi() % 6 != 0 and not game.npcs().any(func(n): return n.kind == "GraniteFlyer"):
			return "GraniteFlyer"
		return "GraniteGolem"
	return ""


## Marble or granite near a spawn (Terraria checks round the spot 20 to 30
## tiles, then round you 30 to 60; a tile is 2/3 of a block): marble if
## there's any, else granite, else "".
static func _stone_near(game, at: Vector3, you: Vector3) -> String:
	for look in [[at, randi_range(20, 30)], [you, randi_range(30, 60)]]:
		var r := int(round(float(look[1]) * 2.0 / 3.0))
		for stone in ["marble", "granite"]:
			var id: int = Data.block_id(stone)
			if id > 0 and game.world.find_blocks(Vector3i(look[0].floor()), Vector3i(r, r, r), PackedInt32Array([id]), 1).size() > 0:
				return stone
	return ""


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


## Terraria's surface spawns away from the special biomes (Spawner.
## SpawnAnNPC, before Hardmode), where rain and the Blood Moon come in; ""
## for the biome's table. By day in the rain: 1 in 4 a Flying Fish, else
## 1 in 2 an Umbrella Slime (not on the desert's sand: its antlions and
## vultures come first). At night in the forest: 1 in 6 a Demon Eye (1 in 2
## more at a new moon); under a Blood Moon (also in the snow and desert)
## 1 in 300 the Groom, then the Bride, then 2 in 5 a Blood Zombie or a
## Drippler; in the snow its Zombie Eskimos; in the rain 1 in 2 a Raincoat
## Zombie; else a Zombie (Terraria's Torch Zombies and zombie kinds not in
## this game are Zombies).
static func surface_pick(biome: String, night: bool, sky) -> String:
	if not biome in ["", "snow", "desert"]:
		return ""
	if not night:
		if biome == "desert" or not sky.raining:
			return ""
		if randi() % 4 == 0:
			return "FlyingFish"
		if randi() % 2 == 0:
			return "UmbrellaSlime"
		return ""
	if biome == "" and (randi() % 6 == 0 or (sky.moon_phase == 4 and randi() % 2 == 0)):
		return "DemonEye"
	if sky.blood_moon:
		if randi() % 300 == 0:
			return "TheGroom"
		if randi() % 300 == 0:
			return "TheBride"
		if randi() % 5 < 2:
			return "BloodZombie" if randi() % 2 == 0 else "Drippler"
	if biome == "snow":
		return ""
	if sky.raining and randi() % 2 == 0:
		return "ZombieRaincoat"
	return "Zombie" if biome == "" else ""


## Weighted spawn tables: [kind, weight].
func _table(depth: String, night: bool, biome := "") -> Array:
	# The ocean: crabs on the beach, jellyfish and sharks in the sea.
	if biome == "ocean" and depth == "surface":
		return [["Crab", 4], ["PinkJellyfish", 3], ["Shark", 2]]
	# Snow, Desert and Jungle: their own enemies on the surface and below.
	var under := depth in ["underground", "caverns"]
	if biome == "snow" and depth != "space":
		if under:
			return [["IceBat", 4], ["IceSlime", 2], ["SpikedIceSlime", 2], ["SnowFlinx", 2]]
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
