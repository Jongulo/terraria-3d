extends Node
## Builds the Test World and checks its contents, spawners, dummies, liquids,
## hotkeys and save/load. Runs headless: ./run_tests.sh

const PATH := "user://worlds/test_world_check.twld"

var game: Game
var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await frames(1)


func start(mode: String) -> void:
	game = Game.new()
	add_child(game)
	game.start({"mode": mode, "name": "TestWorldCheck", "seed": 1, "path": PATH})
	while game.state != Game.State.PLAYING:
		await frames(1)
	await frames(10)


func orbs_count_before(game) -> int:
	return game.orbs_broken


func _ready() -> void:
	Settings.persist = false
	Settings.set_value("render_distance", 4)
	_run()


func _run() -> void:
	await start("test")
	var p := game.player
	var w := game.world
	var c := Vector3i(TestWorld.SIZE.x / 2, TestWorld.GROUND + 1, TestWorld.SIZE.z / 2)
	check(absf(p.global_position.y - (TestWorld.GROUND + 1)) < 0.6, "player starts on the flat ground (y %.1f)" % p.global_position.y)
	check(p.inventory.slots[0] != null and p.inventory.slots[0].item == "PlatinumBroadsword" and p.life_max == Player.MAX_LIFE, "test loadout: best gear, max life")

	# Every item is stocked in a chest.
	var stocked := {}
	for inv in game.chests._chests.values():
		for s in inv.slots:
			if s != null:
				stocked[s.item] = true
	var missing := Data.items.keys().filter(func(n): return not stocked.has(n))
	check(missing.is_empty(), "every item is in a chest (%d items, missing %s)" % [Data.items.size(), missing])

	# Spawners: one per enemy type (plus the gallery's), each spawns its NPC.
	var tw := game.test_world
	var kinds := {}
	for sp in tw.spawners.values():
		kinds[sp.kind] = true
	# (A worm's body and tail come with its head.)
	var enemies := Data.npcs.keys().filter(func(k): return not Data.npcs[k].get("invulnerable", false) and Data.npcs[k].get("spawner", true))
	check(enemies.all(func(k): return kinds.has(k)), "a spawner for every enemy type (missing %s)" % [enemies.filter(func(k): return not kinds.has(k))])
	var slime_sp: Dictionary = tw.spawners.values().filter(func(s): return s.kind == "Zombie")[0]
	var before := game.npcs().size()
	tw.use_spawner(slime_sp.pos, false)
	await frames(2)
	check(game.npcs().size() == before + 1 and game.npcs().any(func(n): return n.kind == "Zombie"), "right-click spawns a Zombie")
	# Every spawner puts its enemy in the open, not in the next spawner along.
	var inside := []
	for sp in tw.spawners.values():
		if Data.npcs[sp.kind].get("boss", false) or Data.npcs[sp.kind].ai == "swim":
			continue
		var lk := NPC.look(sp.kind)
		var h := Vector3(float(lk.hitbox[0]) * 0.5, float(lk.hitbox[1]), float(lk.hitbox[0]) * 0.5)
		if not tw._clear(tw.spawn_spot(sp.pos, sp.kind), h):
			inside.append(sp.kind)
	check(inside.is_empty(), "every spawner's enemy appears in the open (inside a block: %s)" % [inside])
	tw.use_spawner(slime_sp.pos, true)
	await frames(60 * 8)
	check(slime_sp.alive.size() == TestWorld.SPAWNER_MAX_ALIVE, "auto-spawn keeps %d alive (%d)" % [TestWorld.SPAWNER_MAX_ALIVE, slime_sp.alive.size()])
	tw.use_spawner(slime_sp.pos, true)
	check(game.sky.is_day, "it is daytime")
	var zombie: NPC = slime_sp.alive[0]
	await frames(60)
	check(is_instance_valid(zombie) and not zombie._flees_day(game),
			"test-world zombies don't flee at daytime")

	var boss_sp: Dictionary = tw.spawners.values().filter(func(s): return s.kind == "EyeofCthulhu")[0]
	tw.use_spawner(boss_sp.pos, false)
	await frames(120)
	var boss := game.boss()
	check(boss != null and boss.global_position.y < c.y + 40.0, "Eye of Cthulhu spawns and stays in daytime")

	# F5 clears enemies (dummies stay).
	await key(KEY_F5)
	await frames(2)
	var left := game.npcs().filter(func(n): return n.def.ai != "town")
	check(left.size() == 2 and left.all(func(n): return n.kind == "TargetDummy"), "F5 removes enemies, keeps the 2 dummies (and the Old Man)")
	check(game.npcs().any(func(n): return n.kind == "OldMan"), "the Old Man stays")

	# Target dummy: never dies, reports DPS.
	var dummy: NPC = left[0]
	for i in 5:
		dummy.hit(40, 0.0, Vector3.FORWARD, 0.0)
	check(is_instance_valid(dummy) and dummy.life == dummy.life_max and dummy.dps() > 30.0, "dummy survives and shows DPS (%.0f)" % dummy.dps())

	# Liquid lab and waterfalls.
	check(w.get_liquid(c + Vector3i(-20, -3, -3)).x == 1, "water pool")
	check(w.get_liquid(c + Vector3i(-23, -1, 10)).x == 2, "lava pit")
	var natural := Vector3i(c.x - 24, TestWorld.GROUND + 10, c.z - 6)
	var hammered := Vector3i(c.x - 20, TestWorld.GROUND + 6, c.z + 2)
	await get_tree().create_timer(1.0).timeout
	check(game.waterfalls.stream_length(natural) > 5.0, "natural waterfall pours into the pool (%.1f m)" % game.waterfalls.stream_length(natural))
	check(game.waterfalls.stream_length(hammered) > 3.0, "hammer spring tank pours (%.1f m)" % game.waterfalls.stream_length(hammered))

	# Galleries.
	var gallery_ok := true
	var gallery_missing := []
	var shown := TestWorld.gallery_blocks()
	for i in shown.size():
		var id: int = Data.block_id(shown[i])
		var pos := TestWorld.gallery_pos(c, i)
		if w.get_block(pos) != id:
			gallery_ok = false
			gallery_missing.append("%s (found %s)" % [Data.blocks[id].name, Data.block(w.get_block(pos)).get("name", "air")])
	check(gallery_ok, "block gallery has one of every block %s" % [gallery_missing])

	# Floating islands: clouds, a Sunplate house with a Skyware chest of sky loot, a lake.
	var counts := {}
	for name in ["cloud", "sunplate", "sunplate_trim", "disc_wall", "glass", "skyware_lantern", "world_banner", "grass", "skyware_chest"]:
		counts[name] = 0
	var house: Vector3i = c + TestWorld.ISLAND_HOUSE
	for x in range(house.x - 20, house.x + 21, 1):
		for z in range(house.z - 20, house.z + 21, 1):
			for y in range(house.y - 16, house.y + 8):
				var n: String = Data.block(w.get_block(Vector3i(x, y, z))).get("name", "")
				if counts.has(n):
					counts[n] += 1
	check(counts.cloud > 150 and counts.grass > 100 and counts.skyware_chest == 1,
			"house island: clouds, grass and one Skyware chest (%s)" % counts)
	check(counts.sunplate > 80 and counts.sunplate_trim > 40 and counts.disc_wall > 80 and counts.glass == 16
			and counts.skyware_lantern == 2 and counts.world_banner == 1,
			"Skyware house: Sunplate shell with gold trim, Disc Wall lining, 4 glass windows, 2 lanterns, a banner (%s)" % counts)
	var sky_chest := Vector3i(-1, -1, -1)
	for d in w.get_decorations():
		if d.kind == "chest" and int(d.style) == 1:
			sky_chest = d.pos
	check(sky_chest != Vector3i(-1, -1, -1) and Data.block(w.get_block(sky_chest)).name == "skyware_chest", "the Skyware chest is a worldgen chest")
	var sky_items: Array = game.chests.get_inventory(sky_chest).slots.filter(func(st): return st != null).map(func(st): return st.item)
	check(sky_items.any(func(i): return i in ["Starfury", "LuckyHorseshoe", "ShinyRedBalloon"]), "it holds sky loot (%s)" % [sky_items])
	var banner_pos := Vector3i(-1, -1, -1)
	for d in w.get_decorations():
		if d.kind == "rotation" and Data.block(w.get_block(d.pos)).get("name", "") == "world_banner":
			banner_pos = d.pos
	var bn: Vector3i = Player.WALL_NORMALS[game.block_rotation(banner_pos)]
	check(banner_pos.x >= 0 and w.is_solid(banner_pos - bn), "the banner hangs on a wall, facing into the room")
	var cn: Vector3i = Player.WALL_NORMALS[game.block_rotation(sky_chest)]
	check(w.is_solid(sky_chest - cn) and not w.is_solid(sky_chest + cn), "the chest stands against a wall, facing into the room")
	var lake: Vector3i = c + TestWorld.ISLAND_LAKE
	var water := 0
	for x in range(lake.x - 8, lake.x + 9):
		for z in range(lake.z - 8, lake.z + 9):
			for y in range(lake.y - 6, lake.y + 1):
				if w.get_liquid(Vector3i(x, y, z)).x == 1:
					water += 1
	check(water > 20, "the lake island holds a sky lake (%d water cells)" % water)
	check(game.spawner._depth(house.y + 2.0, game) == "space" and game.spawner._depth(c.y + 2.0, game) == "surface", "islands are in the Space layer")

	# The world evil: a Corruption and a Crimson patch with their stone, orbs /
	# hearts and altars; biome detection, music, enemies; smashing an orb.
	var find_blocks := func(center: Vector2i, names: Array) -> Dictionary:
		var found := {}
		for n in names:
			found[n] = []
		for x in range(center.x - 32, center.x + 33):
			for z in range(center.y - 32, center.y + 33):
				for y in range(8, TestWorld.GROUND + 3):
					var n: String = Data.block(w.get_block(Vector3i(x, y, z))).get("name", "")
					if found.has(n):
						found[n].append(Vector3i(x, y, z))
		return found
	var cor := Vector2i(c.x, c.z) + TestWorld.CORRUPTION
	var cri := Vector2i(c.x, c.z) + TestWorld.CRIMSON
	var cf: Dictionary = find_blocks.call(cor, ["ebonstone", "corrupt_grass", "shadow_orb", "demon_altar"])
	var rf: Dictionary = find_blocks.call(cri, ["crimstone", "crimson_grass", "crimson_heart", "crimson_altar"])
	check(cf.ebonstone.size() > 1500 and cf.corrupt_grass.size() > 500 and cf.shadow_orb.size() >= 2 and cf.demon_altar.size() >= 1,
			"Corruption patch: ebonstone, corrupt grass, Shadow Orbs, a demon altar (%s)" % [cf.keys().map(func(k): return "%s %d" % [k, cf[k].size()])])
	check(rf.crimstone.size() > 1500 and rf.crimson_grass.size() > 500 and rf.crimson_heart.size() >= 2 and rf.crimson_altar.size() >= 1,
			"Crimson patch: crimstone, crimson grass, Crimson Hearts, a crimson altar (%s)" % [rf.keys().map(func(k): return "%s %d" % [k, rf[k].size()])])
	var top_of := func(v: Vector2i) -> Vector3: return Vector3(v.x + 0.5, w.surface_y(v.x, v.y) + 1.5, v.y + 0.5)
	check(game.detect_biome(top_of.call(cor)) == "corruption" and game.detect_biome(top_of.call(cri)) == "crimson"
			and game.detect_biome(Vector3(c) + Vector3(0.5, 1, 0.5)) == "", "biome detection: Corruption, Crimson, and neither at the plaza")
	# Stand on the patches' grass at ground level (the centres can be chasms).
	var on_grass := func(cells: Array) -> Vector3:
		var g: Vector3i = cells.filter(func(q): return q.y == TestWorld.GROUND)[0]
		return Vector3(g) + Vector3(0.5, 1.05, 0.5)
	p.global_position = on_grass.call(cf.corrupt_grass)
	await frames(90)
	check(game.biome == "corruption" and Audio._current_track == "Corruption" and game.sky.evil_amount > 0.2,
			"in the Corruption: its music and purple sky (%s, %.2f)" % [Audio._current_track, game.sky.evil_amount])
	p.global_position = on_grass.call(rf.crimson_grass)
	await frames(90)
	check(game.biome == "crimson" and Audio._current_track == "Crimson", "in the Crimson: its music (%s)" % Audio._current_track)
	check(game.spawner._table("surface", false, "corruption")[0][0] == "EaterofSouls"
			and game.spawner._table("underground", false, "crimson").map(func(e): return e[0]) == ["Crimera", "FaceMonster"],
			"the evil biomes spawn their own enemies")
	var orb: Vector3i = cf.shadow_orb[0]
	p.target = {"block": orb, "normal": Vector3i.UP, "id": w.get_block(orb), "distance": 2.0}
	var smashed_at := orbs_count_before(game)
	for i in 4:
		p._mine(Data.item("WoodenHammer"))
	await frames(3)
	var loot := game.entities.get_children().filter(func(e): return e is ItemDrop and e.item in ["Musket", "Vilethorn", "BallOHurt", "BandofStarpower"])
	check(w.get_block(orb) == 0 and loot.size() == 1 and game.orbs_broken == smashed_at + 1, "a hammer smashes a Shadow Orb: one of its items, counted")
	# The world's first orb always gives the Musket (Terraria's CheckOrb).
	var broken := game.orbs_broken
	var orb_spot := Vector3(orb) + Vector3(0.5, 40.5, 0.5)
	var firsts := []
	for i in 6:
		game.orbs_broken = 0
		game._orb_smashed(orb_spot, {"loot": "shadow_orb"})
	await frames(2)
	for e in game.entities.get_children():
		if e is ItemDrop and e.global_position.distance_to(orb_spot) < 3.0 and e.item != "MusketBall":
			firsts.append(e.item)
			e.queue_free()
	game.orbs_broken = broken
	check(firsts.size() == 6 and firsts.all(func(n): return n == "Musket"), "the first orb smashed always gives the Musket (%s)" % [firsts])
	var altar: Vector3i = cf.demon_altar[0]
	p.target = {"block": altar, "normal": Vector3i.UP, "id": w.get_block(altar), "distance": 2.0}
	for i in 6:
		p._mine(Data.item("PlatinumPickaxe"))
	check(Data.block(w.get_block(altar)).get("name", "") == "demon_altar", "demon altars can't be broken yet")
	check(Data.block(Data.block_id("tree_canopy@10")).has("sprite") and Data.block(Data.block_id("tree_canopy@21")).has("sprite"),
			"Corruption and Crimson canopy styles exist")
	p.global_position = Vector3(c) + Vector3(0.5, 1, 0.5)

	# Snow, Desert and Jungle patches: their blocks above and below ground,
	# trees and cacti, biome detection, music and enemies.
	var snow_at := Vector2i(c.x, c.z) + TestWorld.SNOW
	var desert_at := Vector2i(c.x, c.z) + TestWorld.DESERT
	var jungle_at := Vector2i(c.x, c.z) + TestWorld.JUNGLE
	var sf: Dictionary = find_blocks.call(snow_at, ["snow_block", "ice_block", "boreal_trunk"])
	var df: Dictionary = find_blocks.call(desert_at, ["sand", "hardened_sand", "sandstone", "cactus"])
	var jf: Dictionary = find_blocks.call(jungle_at, ["mud", "jungle_grass", "mahogany_trunk"])
	var sizes := func(f: Dictionary) -> String: return str(f.keys().map(func(k): return "%s %d" % [k, f[k].size()]))
	check(sf.snow_block.size() > 1000 and sf.ice_block.size() > 300 and sf.boreal_trunk.size() >= 2, "Snow patch: snow, ice below, boreal trees %s" % sizes.call(sf))
	check(df.sand.size() > 1000 and df.hardened_sand.size() + df.sandstone.size() > 500 and df.cactus.size() > 3, "Desert patch: sand over hardened sand and sandstone, cacti %s" % sizes.call(df))
	check(jf.mud.size() > 3000 and jf.jungle_grass.size() > 500 and jf.mahogany_trunk.size() > 30, "Jungle patch: mud, jungle grass, mahogany trees %s" % sizes.call(jf))
	var styles := w.get_decorations().filter(func(d): return d.kind == "tree_top").map(func(d): return int(d.style))
	# (Each world has its own snow and jungle tree tops: sheets 3, 10-13 / 4, 14.)
	check(styles.any(func(s): return s / 10 in [3, 10, 11, 12, 13]) and styles.any(func(s): return s / 10 in [4, 14])
			and Data.block(Data.block_id("tree_canopy@30")).has("sprite") and Data.block(Data.block_id("tree_canopy@41")).has("sprite"),
			"snowy pine and jungle canopies grow there")
	check(Data.block(Data.block_id("tree_canopy@40")).sprite.get_width() > Data.block(Data.block_id("tree_canopy@30")).sprite.get_width(),
			"jungle canopies are bigger, like Terraria's")
	var biome_of := func(at: Vector2i) -> String: return game.detect_biome(top_of.call(at))
	check(biome_of.call(snow_at) == "snow" and biome_of.call(desert_at) == "desert" and biome_of.call(jungle_at) == "jungle",
			"biome detection: snow, desert, jungle (%s, %s, %s)" % [biome_of.call(snow_at), biome_of.call(desert_at), biome_of.call(jungle_at)])
	check(jf.mud.any(func(q): return q.y < TestWorld.GROUND - 35), "the jungle's mud goes deep underground")
	check(game.biome_music("snow", false) == "Snow" and game.biome_music("snow", true) == "Ice" and game.biome_music("desert", true) == "UndergroundDesert"
			and game.biome_music("jungle", true) == "UndergroundJungle", "biome music, surface and underground")
	var kinds_of := func(depth: String, night: bool, b: String) -> Array: return game.spawner._table(depth, night, b).map(func(e): return e[0])
	check("IceSlime" in kinds_of.call("surface", false, "snow") and "ZombieEskimo" in kinds_of.call("surface", true, "snow") and "IceBat" in kinds_of.call("caverns", false, "snow"),
			"snow enemies: ice slimes, Zombie Eskimos at night, ice bats below")
	check("Antlion" in kinds_of.call("surface", false, "desert") and "Vulture" in kinds_of.call("surface", false, "desert") and "WalkingAntlion" in kinds_of.call("underground", false, "desert"),
			"desert enemies: antlions, vultures, walking antlions below")
	check("JungleSlime" in kinds_of.call("surface", false, "jungle") and "Snatcher" in kinds_of.call("surface", false, "jungle") and "Hornet" in kinds_of.call("caverns", false, "jungle"),
			"jungle enemies: jungle slimes, snatchers, hornets below")
	# Antlions stay put and throw sand; hornets shoot stingers; snatchers lunge
	# only as far as their vine.
	var shots_before := game.entities.get_children().filter(func(e): return e is Projectile and not e.friendly).size()
	var ant := game.spawn_npc("Antlion", p.global_position + Vector3(8, 0, 0))
	var hornet := game.spawn_npc("Hornet", p.global_position + Vector3(-6, 3, 0))
	var snatch := game.spawn_npc("Snatcher", p.global_position + Vector3(0, 0, 14))
	var ant_pos := ant.global_position
	ant._shot_timer = 0.0
	hornet._shot_timer = 0.0
	await frames(3)  # (before the shots reach the player)
	var shots := game.entities.get_children().filter(func(e): return e is Projectile and not e.friendly).size() - shots_before
	check(shots >= 2, "antlions and hornets shoot at the player (%d shots)" % shots)
	await frames(40)
	check(Vector2(ant.global_position.x - ant_pos.x, ant.global_position.z - ant_pos.z).length() < 0.05, "the antlion stays put")
	await frames(90)
	check(snatch._anchor != null and snatch.center().distance_to(snatch._anchor) < float(Data.npcs.Snatcher.tether) + 1.0
			and snatch.center().distance_to(p.global_position) < 14.0, "a snatcher lunges at the player but its vine holds it")
	check(snatch._vine != null and snatch._vine.visible, "it hangs on a vine")
	for n in game.npcs():
		if not n.def.get("persistent", false):
			n.queue_free()
	# Ice is slippery.
	var ice_spot := Vector3i(c.x - 30, TestWorld.GROUND, c.z - 30)
	for dx in range(-3, 15):
		for dz in range(-2, 3):
			w.set_block(ice_spot + Vector3i(dx, 0, dz), Data.block_id("ice_block"))
	p.global_position = Vector3(ice_spot) + Vector3(0.5, 1.05, 0.5)
	p.velocity = Vector3(5.2, 0, 0)
	await frames(2)
	var slide_from := p.global_position.x
	p.input_enabled = false
	await frames(20)
	var slid := p.global_position.x - slide_from
	p.input_enabled = true
	check(slid > 1.0, "you slide on ice (%.1f blocks after letting go)" % slid)
	# Cactus gear and any wood.
	var cactus_sword: Dictionary = Data.recipes.filter(func(r): return r.result == "CactusSword")[0]
	check(cactus_sword.ingredients.has("Cactus"), "cactus makes a Cactus Sword")
	# Terraria's "any wood" recipes (the Torch) take any wood; the Work Bench,
	# like Terraria's, plain Wood (each wood has its own bench there).
	var torch: Dictionary = Data.recipes.filter(func(r): return r.result == "Torch")[0]
	var bench: Dictionary = Data.recipes.filter(func(r): return r.result == "WorkBench")[0]
	check(torch.ingredients.has(Data.ANY_WOOD) and "BorealWood" in Data.ANY_WOOD and "RichMahogany" in Data.ANY_WOOD and bench.ingredients.has("Wood"),
			"Terraria's any-wood recipes take any wood; plain-Wood ones plain Wood")
	p.global_position = Vector3(c) + Vector3(0.5, 1, 0.5)

	# Sky gear: clouds and the Lucky Horseshoe stop fall damage, the Shiny Red
	# Balloon jumps higher, Starfury calls stars, harpies throw feathers.
	var drop_test := func(floor_block: String, accessory: String, jump_near_ground: bool) -> int:
		var spot := c + Vector3i(30, 0, 30)
		w.set_block(spot + Vector3i(0, -1, 0), Data.block_id(floor_block))
		p.accessories.slots[0] = Inventory.stack(accessory, 1) if accessory != "" else null
		p.life = p.life_max
		p._immune = 0.0
		p.poisoned = 0.0  # (a hornet's stinger, earlier, may have poisoned you)
		p.velocity = Vector3.ZERO
		p.global_position = Vector3(spot) + Vector3(0.5, 20.0, 0.5)
		p._fall_start = p.global_position.y
		p.on_floor = false
		var jumped := false
		for i in 150:
			await frames(1)
			if jump_near_ground and not jumped and p.global_position.y < spot.y + 2.5:
				jumped = true
				Input.action_press("jump")
				await frames(2)
				Input.action_release("jump")
			if i > 5 and p.on_floor:
				break
		await frames(2)
		return p.life_max - p.life
	var god: bool = p.god_mode
	p.god_mode = false
	p.flying = false
	var hurt_stone: int = await drop_test.call("stone", "", false)
	var hurt_cloud: int = await drop_test.call("cloud", "", false)
	var hurt_shoe: int = await drop_test.call("stone", "LuckyHorseshoe", false)
	# Terraria: 10 damage for each tile beyond 25; 20 blocks is 30 tiles
	# (less half your defense).
	check(hurt_stone >= 25 and hurt_stone <= 50 and hurt_cloud == 0 and hurt_shoe == 0,
			"a 20 block (30 tile) fall hurts like Terraria's (%d), but not onto a cloud (%d) or with a Lucky Horseshoe (%d)" % [hurt_stone, hurt_cloud, hurt_shoe])
	var hurt_bottle: int = await drop_test.call("stone", "CloudinaBottle", false)
	var hurt_saved: int = await drop_test.call("stone", "CloudinaBottle", true)
	check(hurt_bottle > 0 and hurt_saved == 0,
			"a double jump just above the ground cancels fall damage (%d without it, %d with)" % [hurt_bottle, hurt_saved])
	var jump_height := func(accessory: String) -> float:
		p.accessories.slots[0] = Inventory.stack(accessory, 1) if accessory != "" else null
		var y0: float = p.global_position.y
		var top := y0
		Input.action_press("jump")
		for i in 50:
			await frames(1)
			top = maxf(top, p.global_position.y)
		Input.action_release("jump")
		for i in 60:
			await frames(1)
		return top - y0
	var plain_jump: float = await jump_height.call("")
	var balloon_jump: float = await jump_height.call("ShinyRedBalloon")
	check(balloon_jump > plain_jump * 1.2, "the Shiny Red Balloon jumps higher (%.2f vs %.2f)" % [balloon_jump, plain_jump])
	# Terraria's jump: 98 px, 6.1 tiles; the Balloon's 10.7 tiles.
	check(absf(plain_jump - 4.09) < 0.1 and absf(balloon_jump - 7.17) < 0.15,
			"jumps go as high as Terraria's (%.2f blocks, the Balloon %.2f)" % [plain_jump, balloon_jump])
	p.accessories.slots[0] = null
	await _run_checks(p)
	var proj_count := func(friendly: bool) -> int:
		return game.entities.get_children().filter(func(e): return e is Projectile and e.friendly == friendly).size()
	var before_stars: int = proj_count.call(true)
	p._call_star(Data.item("Starfury"))
	check(proj_count.call(true) == before_stars + 1, "Starfury calls down a star")
	p.god_mode = true
	var harpy := game.spawn_npc("Harpy", p.global_position + Vector3(4, 4, 0))
	var feathers := false
	for i in 300:
		await frames(1)
		if proj_count.call(false) > 0:
			feathers = true
			break
	check(harpy.flying and feathers, "a harpy hovers and throws feathers")
	harpy.queue_free()
	p.god_mode = god

	await _prop_batch_checks(c)
	await _vary_checks(c)
	await _platform_checks(c)
	await _rope_checks(c)
	await _hook_checks(c)
	await _accessory_checks(c)
	await _goblin_checks(c)
	await _prefix_checks(c)
	await _hive_checks(c)
	await _queen_bee_checks(c)
	await _brain_checks(c)
	await _fishing_checks(c)
	await _fishing_spot_checks(c)
	await _angler_checks(c)
	await _critter_checks(c)
	await _furniture_checks(c)
	await _hammer_checks(c)
	await _furniture2_checks(c)
	await _sky_checks()
	await _dungeon_checks(c)
	await _skeletron_checks(c)
	await _mushroom_checks(c)
	await _door_checks(c)
	await _flora_checks(c)
	await _cut_checks(c)
	await _cabin_loot_checks(c)
	await _sand_checks(c)
	await _dust_checks(c)
	await _knockback_checks(c)
	await _gore_checks(c)
	await _armor_checks(c)
	await _health_bar_checks()
	await _town_checks(c)
	await _explosive_checks(c)
	await _tool_checks(c)
	await _cactus_checks(c)
	await _yoyo_checks(c)
	await _flail_checks(c)
	await _terragrim_checks(c)
	await _sword_shrine_checks(c)
	await _swim_checks(c)
	await _screenshot_checks()
	await _eater_checks(c)
	await _king_slime_checks(c)
	await _recipe_checks(c)
	await _underworld_checks(c)
	await _shadow_chest_checks(c)
	await _hellstone_checks(c)
	await _dungeon_enemy_checks(c)
	await _trap_checks(c)
	await _wiring_checks(c)
	await _wiring_more_checks(c)
	await _boulder_kind_checks(c)
	await _alchemy_checks(c)
	await _potion_checks(c)
	await _summon_checks(c)
	await _bee_loot_checks(c)
	await _weather_checks(c)
	await _slime_rain_checks(c)
	await _mini_biome_checks(c)
	# A natural spring on a tree trunk (worlds from before the fix) is dropped
	# when the waterfalls load; ones from the ground stay.
	var trunk_fall := Vector3i(c.x - 7, TestWorld.GROUND + 6, c.z - 20)
	var natural_before := game.world.get_decorations().filter(func(d): return d.kind == "waterfall").size()
	game.world.add_decoration("waterfall", trunk_fall, 10)  # water, pouring +x off the first test tree
	var wf := Waterfalls.new()
	wf.setup(game.world)
	var falls_left := game.world.get_decorations().filter(func(d): return d.kind == "waterfall")
	check(Data.block(game.world.get_block(trunk_fall - Vector3i(1, 0, 0))).get("trunk", false)
			and not falls_left.any(func(d): return d.pos == trunk_fall) and falls_left.size() == natural_before,
			"a spring on a tree trunk is dropped on loading; the others stay (%d)" % falls_left.size())
	wf.free()

	# Hotkeys.
	await key(KEY_F2)
	check(p.god_mode, "F2 god mode on")
	var life := p.life
	p._immune = 0.0
	p.hurt(500, Vector3.ZERO)
	check(p.life == life, "god mode blocks damage")
	await key(KEY_F2)
	await key(KEY_F3)
	var y0 := p.global_position.y
	Input.action_press("jump")
	await frames(60)
	Input.action_release("jump")
	check(p.flying and p.global_position.y > y0 + 3.0, "F3 fly: Space rises (%.1f -> %.1f)" % [y0, p.global_position.y])
	await key(KEY_F3)
	await key(KEY_F4)
	check(not game.sky.is_day, "F4 makes it night")
	await key(KEY_F4)
	check(game.sky.is_day, "F4 again makes it day")
	game.spawn_item("Wood", 5, p.global_position + Vector3(6, 1, 6))
	await key(KEY_F6)
	await frames(2)
	check(not game.entities.get_children().any(func(e): return e is ItemDrop), "F6 clears dropped items")
	await key(KEY_F7)
	check(tw.natural_spawns and game.spawner.process_mode == Node.PROCESS_MODE_INHERIT, "F7 turns natural spawns on")

	# Save, reload: spawners, labels, dummies and chests come back.
	var town_before := {}
	for kind in game.town.residents:
		town_before[kind] = [game.town.residents[kind].display_name, game.town.residents[kind].home_key]
	var n_spawners := tw.spawners.size()
	var n_labels := tw._labels.size()
	check(game.save_world(), "test world saves")
	game.queue_free()
	await frames(5)
	await start("load")
	tw = game.test_world
	check(tw != null and tw.spawners.size() == n_spawners and tw._labels.size() == n_labels, "reloaded as a test world with its spawners and signs")
	check(game.npcs().filter(func(n): return n.kind == "TargetDummy").size() == 2, "dummies are back")
	var stocked2 := 0
	for inv in game.chests._chests.values():
		for s in inv.slots:
			if s != null:
				stocked2 += 1
	check(stocked2 >= Data.items.size(), "chests still stocked")
	check(tw.natural_spawns, "test-world settings saved")
	var town_after := {}
	for kind in game.town.residents:
		town_after[kind] = [game.town.residents[kind].display_name, game.town.residents[kind].home_key]
	check(town_after == town_before and town_after.size() == 8, "the town's residents come back with their names and homes (%s)" % [town_after])
	check(game.sign_text(c + TestWorld.HOUSE_SIGN) == "Signs keep what you write.", "signs keep their text after loading (%s)" % game.sign_text(c + TestWorld.HOUSE_SIGN))
	var shaped_after := c + Vector3i(-4, 0, 12)
	check(game.world.get_shape(shaped_after) == Game.SHAPE_HALF, "hammered shapes come back after loading (%d)" % game.world.get_shape(shaped_after))
	var gate_after := c + Vector3i(9, 0, 0)
	check(Data.block(game.world.get_block(gate_after)).name == "wooden_door" and Doors.facing(game.block_rotation(gate_after)) == 3,
			"the arena door comes back closed, facing the same way")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT: %d failures" % failures.size())
	for f in failures:
		print("  - " + f)
	get_tree().quit(1 if failures.size() > 0 else 0)


## Skeletron: the Old Man's Curse (only at night) brings it with its two
## hands; its hover, spin and enraged day; a hand's attacks; killing the head
## takes the hands and drops its loot; the Old Man back at dawn until it's
## beaten; and the Dungeon Guardian before then.
## Granite, Marble and spider caves: their spawns (Terraria's nearMarble,
## nearGranite and spider walls), the Granite Golem curling up, the Granite
## Elemental homing in, the Web Covered Chest's loot and the Web Slinger.
func _mini_biome_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var god := p.god_mode
	p.god_mode = true
	# A stone floor up in the air, nothing round it.
	var base := c + Vector3i(40, 40, -60)
	for x in range(-12, 13):
		for z in range(-12, 13):
			w.set_block(base + Vector3i(x, -1, z), Data.block_id("stone"))
			for y in range(0, 12):
				w.set_block(base + Vector3i(x, y, z), 0)
	var at := Vector3(base) + Vector3(0.5, 0, 0.5)
	var biome := game.biome
	game.biome = ""
	var share := func(kind: String) -> float:
		var n := 0
		for i in 4000:
			if game.spawner.cave_pick(game, at, at) == kind:
				n += 1
		return n / 4000.0
	check(share.call("") == 1.0, "no granite, marble or webs about: the usual cave spawns")
	var stone := base + Vector3i(6, 0, 0)
	w.set_block(stone, Data.block_id("marble"))
	var hoplite: float = share.call("GreekSkeleton")
	check(absf(hoplite - 0.375) < 0.03, "by marble, half the cave spawns 3 in 4 a Hoplite (%.3f)" % hoplite)
	w.set_block(stone, Data.block_id("granite"))
	var flyer: float = share.call("GraniteFlyer")
	var golem: float = share.call("GraniteGolem")
	check(absf(flyer - 0.333) < 0.03 and absf(golem - 0.0667) < 0.015,
			"by granite, half the cave spawns 4 in 5 a Granite Elemental 5 in 6, else a Granite Golem (%.3f, %.3f)" % [flyer, golem])
	w.set_block(stone, 0)
	w.add_decoration("spider_cave", base, 8)
	game._spider_caves = []
	check(share.call("WallCreeper") == 1.0 and not game.in_spider_cave(at + Vector3(9, 0, 0)), "in a spider cave's webs, Wall Creepers")
	w.remove_decorations_at(base)
	game._spider_caves = []
	game.biome = biome
	# The Granite Golem curls up on the ground every 300 ticks for 120, not to
	# be hurt.
	p.global_position = at + Vector3(8, 0, 0)
	p.velocity = Vector3.ZERO
	var golem_npc := game.spawn_npc("GraniteGolem", at)
	golem_npc._curl_t = 290.0
	var curled := false
	for i in 60:
		await get_tree().physics_frame
		if golem_npc.dont_take_damage:
			curled = true
			break
	var life := golem_npc.life
	golem_npc.hit(50, 0.0, Vector3.RIGHT, 0.0)
	check(curled and golem_npc.life == life, "the Granite Golem curls up and can't be hurt")
	var t := 0
	while golem_npc.dont_take_damage and t < 300:
		await get_tree().physics_frame
		t += 1
	check(t > 100 and t < 140, "it uncurls after 120 ticks (%d)" % t)
	golem_npc.hit(50, 0.0, Vector3.RIGHT, 0.0)
	check(golem_npc.life < life, "then it can be hurt")
	golem_npc.queue_free()
	# The Granite Elemental, seeing you, homes in.
	var flyer_npc := game.spawn_npc("GraniteFlyer", at + Vector3(0, 3, 0))
	var d0: float = flyer_npc.center().distance_to(p.center())
	for i in 90:
		await get_tree().physics_frame
	var d1: float = flyer_npc.center().distance_to(p.center())
	check(flyer_npc._gf_state == 1 and d1 < d0 - 1.5, "the Granite Elemental homes in on you (%.1f to %.1f blocks)" % [d0, d1])
	flyer_npc.queue_free()
	check(Chests.LOOT[28] == "web_chest" and Data.loot.web_chest.pick_one[0][0] == "WebSlinger", "a spider cave's Web Covered Chest holds a Web Slinger")
	check(int(Data.items.WebSlinger.hook.latched) == 8 and int(Data.items.WebSlinger.hook.fly) == 8, "the Web Slinger: up to 8 webs out")
	p.god_mode = god
	await frames(1)


func _mushroom_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var m := c + TestWorld.MUSHROOM
	var was_selected := p.selected
	var id := func(n: String) -> int: return Data.block_id(n)
	var counts := {}
	for n in ["mushroom_grass", "glowing_mushroom", "mushroom_trunk", "mushroom_vines"]:
		counts[n] = 0
	var on_grass := true
	var styles := {}
	for dx in range(-24, 25):
		for dz in range(-24, 25):
			for dy in range(-12, 18):
				var q := m + Vector3i(dx, dy, dz)
				var n: String = Data.block(w.get_block(q)).get("name", "")
				if n.begins_with("glowing_mushroom"):
					styles[n] = true
					n = "glowing_mushroom"
					if w.get_block(q + Vector3i.DOWN) != id.call("mushroom_grass"):
						on_grass = false
				if counts.has(n):
					counts[n] += 1
	var caps := w.get_decorations().filter(func(d): return d.kind == "tree_top" and int(d.style) >= 270 and int(d.style) < 273)
	check(counts.mushroom_grass > 500 and counts.glowing_mushroom > 100 and counts.mushroom_vines > 20 and on_grass,
			"the test world's Glowing Mushroom cavern: mushroom grass, glowing mushrooms on it, vines (%s)" % [counts])
	check(styles.size() == 5 and counts.glowing_mushroom < counts.mushroom_grass / 2, "all five styles of glowing mushroom, in clumps (%s)" % [styles.keys()])
	# Each stands somewhere of its own in its block, turned its own way.
	var a := BlockModels.scatter_at(m, 0.3)
	var b := BlockModels.scatter_at(m + Vector3i(1, 0, 0), 0.3)
	check(a.origin != b.origin and absf(a.origin.x) <= 0.3 and absf(a.origin.z) <= 0.3 and not a.basis.is_equal_approx(b.basis) and a.is_equal_approx(BlockModels.scatter_at(m, 0.3)),
			"glowing mushrooms are scattered off their blocks' middles and turned, the same each time")
	check(caps.size() >= 1 and counts.mushroom_trunk >= 3, "giant glowing mushrooms: stems under their caps (%d)" % caps.size())
	# It glows blue, it's the biome you're in (its music), its enemies.
	# (Off the fishing spot's pond in its middle.)
	var floor_at := m + Vector3i(0, -3, 8)
	while not w.is_solid(floor_at + Vector3i.DOWN) and floor_at.y > m.y - 10:
		floor_at += Vector3i.DOWN
	var light: Color = w.get_light(Vector3(floor_at) + Vector3(0.5, 0.5, 0.5))
	check(light.b > 0.5 and light.b > light.r * 2.0, "it glows blue (%s)" % light)
	check(game.detect_biome(Vector3(floor_at) + Vector3(0.5, 0.5, 0.5)) == "mushroom" and game.biome_music("mushroom", true) == "Mushroom",
			"it's the Glowing Mushroom biome, with its music")
	var table: Array = game.spawner._table("caverns", false, "mushroom")
	var kinds := table.map(func(e): return e[0])
	check(kinds.has("SporeSkeleton") and kinds.has("SporeBat") and not kinds.has("Skeleton") and not kinds.has("CaveBat"),
			"Spore Skeletons and Spore Bats in place of Skeletons and bats (%s)" % [kinds])
	check(Data.npcs.SporeBat.drops.any(func(e): return e[0] == "Shroomerang" and is_equal_approx(float(e[3]), 0.025)), "a Spore Bat drops the Shroomerang 1 in 40")
	# Terraria's drops: a glowing mushroom (small or giant) 1 in 40 Mushroom Grass
	# Seeds, else half the time a Glowing Mushroom; mushroom grass: mud.
	var got := {}
	for i in 4000:
		var item: String = game.block_drop(Data.block(id.call("glowing_mushroom")))
		got[item] = got.get(item, 0) + 1
	check(absf(got.get("GlowingMushroom", 0) / 4000.0 - 0.4875) < 0.04 and absf(got.get("MushroomGrassSeeds", 0) / 4000.0 - 0.025) < 0.012,
			"a glowing mushroom drops a Glowing Mushroom half the time, Mushroom Grass Seeds 1 in 40 (%s)" % [got])
	check(Data.block(id.call("mushroom_grass")).drop == "MudBlock" and Data.block(id.call("mushroom_block")).drop == "GlowingMushroom", "mushroom grass drops mud, a Mushroom Block a Glowing Mushroom")
	# Seeds plant mushroom grass on mud; a Glowing Mushroom places a Mushroom Block.
	var mud_at := floor_at + Vector3i(2, -1, 0)
	for k in 3:
		w.set_block(mud_at + Vector3i(0, k + 1, 0), 0)
	w.set_block(mud_at, id.call("mud"))
	p.inventory.slots[9] = Inventory.stack("MushroomGrassSeeds", 2)
	p.select(9)
	p.target = {"block": mud_at, "normal": Vector3i.UP, "id": w.get_block(mud_at), "distance": 3.0}
	check(p._place(Data.item("MushroomGrassSeeds")) and w.get_block(mud_at) == id.call("mushroom_grass") and p.inventory.count_of("MushroomGrassSeeds") == 1,
			"Mushroom Grass Seeds turn mud to mushroom grass")
	p.target = {"block": mud_at, "normal": Vector3i.UP, "id": w.get_block(mud_at), "distance": 3.0}
	check(not p._place(Data.item("MushroomGrassSeeds")), "not on anything else")
	check(Data.item("GlowingMushroom").place == "mushroom_block", "a Glowing Mushroom places a Mushroom Block")
	p.inventory.slots[9] = null
	p.select(was_selected)
	# The Mushroom Chest: a cabin chest's loot, half the time the Mushroom set.
	var sets := 0
	var split := 0
	for i in 400:
		var loot: Array = Game.roll_loot("mushroom_chest")
		var items := loot.map(func(e): return e[0])
		var n := ["MushroomHat", "MushroomVest", "MushroomPants"].filter(func(x): return items.has(x)).size()
		sets += int(n == 3)
		split += int(n != 0 and n != 3)
	check(absf(sets / 400.0 - 0.5) < 0.1 and split == 0 and Chests.LOOT[15] == "mushroom_chest", "a Mushroom Chest holds the Mushroom Hat, Vest and Pants half the time (%d of 400)" % sets)


func _skeletron_checks(c: Vector3i) -> void:
	var p := game.player
	var hud := game.hud
	var d := Vector3i(c.x + TestWorld.DUNGEON.x, TestWorld.GROUND, c.z + TestWorld.DUNGEON.z)
	var was_day: bool = game.sky.is_day
	var was_time: float = game.sky.time
	var god := p.god_mode
	p.god_mode = true
	# Its furniture is down in it, none out on the grass by the entrance.
	var outside := []
	var w: VoxelWorld = game.world
	for x in range(-45, 46):
		for z in range(-45, 46):
			var q := d + Vector3i(x, 1, z)
			var n: String = Data.block(w.get_block(q)).get("name", "")
			if (n.begins_with("gothic_") or n.contains("_dungeon_") or n in ["alchemy_table", "bewitching_table"]) and not n.contains("door"):
				outside.append(n)
	check(outside.is_empty(), "no Dungeon furniture on the ground outside it (%s)" % [outside])
	var old_men := game.npcs().filter(func(n): return n.kind == "OldMan")
	check(old_men.size() == 1, "the Old Man is at the Dungeon")
	if old_men.size() != 1:
		return
	var om: NPC = old_men[0]
	var buttons := func() -> Array:
		hud.open_chat(om)
		var names := hud._chat_buttons.get_children().filter(func(b): return not b.is_queued_for_deletion()).map(func(b): return b.text)
		return names
	game.sky.is_day = true
	game.sky.time = 27000.0
	check(not buttons.call().has("Curse"), "by day the Old Man has no Curse to offer")
	hud.close_chat()
	game.sky.is_day = false
	game.sky.time = 0.0
	check(buttons.call().has("Curse"), "at night he does")
	p.global_position = om.global_position + Vector3(6, 0, 0)
	# (As a 3D model, to see it face you.)
	var old_method := NPCModels.method("SkeletronHead")
	var old_arm := NPCModels.method("SkeletronArm")
	NPCModels.set_method("SkeletronHead", "claude")
	NPCModels.set_method("SkeletronArm", "hull")
	hud.chat_button("Curse")
	await frames(3)
	var heads := game.npcs().filter(func(n): return n.kind == "SkeletronHead")
	var hands := game.npcs().filter(func(n): return n.kind == "SkeletronHand")
	check(not is_instance_valid(om) or om.is_queued_for_deletion(), "cursing him: the Old Man dies")
	check(heads.size() == 1 and hands.size() == 2 and game.boss_alive() and last_message() == "Skeletron has awoken!",
			"and Skeletron rises with its two hands (%d heads, %d hands)" % [heads.size(), hands.size()])
	if heads.size() != 1 or hands.size() != 2:
		return
	var head: NPC = heads[0]
	check(head.life_max == 4400 and head.damage == 32 and head.defense == 10 and hands[0].life_max == 600 and hands[0].defense == 14,
			"Terraria's numbers: a 4400-life head (32 damage, 10 defense), 600-life hands (14 defense)")
	check(hands[0]._side != hands[1]._side and hands[0]._head == head, "a hand on each side")
	# Hovering, it climbs to keep 250 px over your head.
	head.global_position = p.global_position + Vector3(0, 2, 0)
	head.velocity = Vector3.ZERO
	await frames(30)
	check(head.ai_state == 0 and head.velocity.y > 0.0, "hovering, it rises over you (%.2f)" % head.velocity.y)
	var facing := func() -> Vector3:
		return head.sprite._mi.basis.z if head.sprite is NPCModel else Vector3.ZERO
	var toward := func() -> Vector3:
		var f: Vector3 = p.camera.global_position - head.center()
		return Vector3(f.x, 0, f.z).normalized()
	head.global_position = p.global_position + Vector3(10, 4, 0)
	head.velocity = Vector3.ZERO
	head._model_facing = Vector3.ZERO
	await frames(2)
	var fz: Vector3 = facing.call()
	check(Vector3(fz.x, 0, fz.z).normalized().dot(toward.call()) > 0.95 and absf(fz.y) < sin(NPC.SK_TILT_MAX) + 0.01,
			"its model's face looks your way, not its bottom, tipped only a little (%s)" % fz)
	# Step round it: it turns after you slowly, so you see its side.
	var round_it: Vector3 = head.global_position + (p.global_position - head.global_position).rotated(Vector3.UP, PI * 0.5)
	p.global_position = Vector3(round_it.x, p.global_position.y, round_it.z)
	await frames(10)
	fz = facing.call()
	check(Vector3(fz.x, 0, fz.z).normalized().dot(toward.call()) < 0.5, "step round it and you see its side for a while (%.2f)" % Vector3(fz.x, 0, fz.z).normalized().dot(toward.call()))
	NPCModels.set_method("SkeletronHead", old_method)
	# Every 800 ticks it spins at you for 400, its defense 10 lower.
	head._sk_timer = 799.5
	await frames(3)
	check(head.ai_state == 1 and head.defense == 0, "after 800 ticks it spins (defense %d)" % head.defense)
	await frames(2)
	var to_you: Vector3 = (p.center() - head.center()).normalized()
	check(head.velocity.normalized().dot(to_you) > 0.95 and absf(head.velocity.length() - 1.5 * NPC.PX_TICK) < 0.05,
			"spinning, it comes at you at 1.5 px a tick (%.2f blocks/s)" % head.velocity.length())
	head._sk_timer = 399.5
	await frames(3)
	check(head.ai_state == 0, "and goes back to hovering after 400")
	# A hand, every 300 ticks: up over the head, then down at you.
	var hand: NPC = hands[0]
	hand.ai_state = 0
	hand.ai_timer = 299.5
	hand.velocity = Vector3.ZERO
	for i in 3:
		await get_tree().physics_frame
	check(hand.ai_state == 1 and hand.velocity.y > 0.0, "a hand rises to strike (state %d, %.2f up)" % [hand.ai_state, hand.velocity.y])
	hand.global_position = head.center() + Vector3(0, 9.0, 0)
	await frames(3)
	check(hand.ai_state == 2 and hand.velocity.length() > 17.0 * NPC.PX_TICK * 0.95, "then slams down at you (%.1f blocks/s)" % hand.velocity.length())
	check(hand.get_child_count() >= 3, "its arm: two bones")
	var bone: Node3D = hand._bones[0]
	var bone_ok: bool = bone.get_child_count() == 1 and bone.get_child(0) is NPCModel and bone.get_child(0).kind == "SkeletronArm"
	check(bone_ok, "its bones take the NPC picker's look for the Skeletron Arm (a hull model)")
	if bone_ok:
		var model: NPCModel = bone.get_child(0)
		var mid: Vector3 = model._mi.global_transform * (model._mi.mesh.get_aabb().get_center())
		var down: Vector3 = -model._mi.global_basis.y.normalized()
		var to_elbow: Vector3 = hand._bones[1].get_child(0)._mi.global_transform * (model._mi.mesh.get_aabb().get_center()) - mid
		check(down.dot(to_elbow.normalized()) > 0.0 and mid.distance_to(hand.center()) < 6.0,
				"lying along the arm, the art's bottom toward the elbow (%.2f)" % down.dot(to_elbow.normalized()))
	NPCModels.set_method("SkeletronArm", old_arm)
	# Enraged by day.
	game.sky.is_day = true
	game.sky.time = 100.0
	await frames(3)
	check(head.ai_state == 2 and head.damage == 9999 and head.defense == 9999, "by day it's enraged: 9999 damage and defense")
	game.sky.is_day = false
	game.sky.time = 0.0
	head.ai_state = 0
	await frames(2)
	# Killing the head: the hands go too, its loot drops, Skeletron is beaten.
	game._collected_drops = {}
	var guard := 0
	while is_instance_valid(head) and head.life > 0 and guard < 200:
		head.ai_state = 0
		head.defense = 0
		head.hit(1000, 0.0, Vector3.FORWARD, 0.0)
		guard += 1
	var drops: Dictionary = game._collected_drops
	game._collected_drops = null
	for i in 10:
		await get_tree().physics_frame
	check(game.defeated_bosses.has("SkeletronHead") and last_message() == "Skeletron has been defeated!", "killing the head beats Skeletron")
	check(game.npcs().filter(func(n): return n.kind == "SkeletronHand").is_empty(), "and its hands go with it")
	check(drops.get("HealingPotion", 0) >= 5 and drops.get("HealingPotion", 0) <= 15 and drops.has("GoldCoin"), "it drops 5-15 Healing Potions and gold (%s)" % [drops])
	# A Hellforge if the world has none (Terraria's NPCLoot_DropHellforge);
	# Chippy's Couch 1 in 7.
	var forge := Data.block_id("hellforge")
	check(drops.has("Hellforge") != game.world.has_block(forge), "Skeletron drops a Hellforge only into a world without one (%s, has one: %s)" % [drops.has("Hellforge"), game.world.has_block(forge)])
	check(Data.npcs.SkeletronHead.drops.any(func(e): return e[0] == "ChippysCouch" and absf(e[3] - 1.0 / 7.0) < 0.001), "Chippy's Couch: 1 in 7")
	# The Clothier comes once it's beaten: Terraria's lines and his shop.
	check(game.town.wants_to_come("Clothier"), "the Clothier wants to move in once Skeletron is beaten")
	var clothier := game.town.move_in("Clothier", p.global_position + Vector3(3, 0, 0))
	var line := clothier.talk_line()
	check(clothier.title().ends_with("the Clothier") and line != "..." and line != "", "the Clothier: his name and Terraria's lines (%s: %s)" % [clothier.title(), line])
	game.sky.moon_phase = 0
	check(Hud.shop_condition("moon0_night") and not Hud.shop_condition("moon1") and not Hud.shop_condition("day") and not Hud.shop_condition("snow"),
			"his shop by the moon: the White Tuxedo on a full moon's night, not the Doctor's clothes")
	clothier.queue_free()
	game.town.residents.erase("Clothier")
	game.town.arrived.erase("Clothier")
	# No Old Man once it's beaten; until then, he's back at dawn.
	game._on_dawn()
	check(game.npcs().filter(func(n): return n.kind == "OldMan").is_empty(), "the Old Man doesn't come back once Skeletron is beaten")
	game.defeated_bosses.erase("SkeletronHead")
	check(not game.town.wants_to_come("Clothier"), "not before")
	game._on_dawn()
	check(game.npcs().filter(func(n): return n.kind == "OldMan").size() == 1, "before then he's back at dawn")
	# The Dungeon Guardian: below the ground in the Dungeon before Skeletron
	# is beaten.
	var deep := Vector3.INF
	for x in range(-12, 13):
		for z in range(-12, 13):
			for y in range(d.y - 30, d.y - 3):
				var q := d + Vector3i(x, y - d.y, z)
				if not game.world.is_solid(q) and not game.world.is_solid(q + Vector3i.UP) and game.detect_biome(Vector3(q) + Vector3(0.5, 0.5, 0.5)) == "dungeon":
					deep = Vector3(q) + Vector3(0.5, 0, 0.5)
	check(deep != Vector3.INF, "somewhere below the ground in the Dungeon")
	if deep != Vector3.INF:
		p.global_position = deep
		game.biome = "dungeon"
		game._biome_timer = 1000.0
		game.spawner.process_mode = Node.PROCESS_MODE_INHERIT
		for i in 40:
			game.spawner._timer = 0.0
			game.spawner._physics_process(0.016)
		game.spawner.process_mode = Node.PROCESS_MODE_DISABLED
		var guardians := game.npcs().filter(func(n): return n.kind == "DungeonGuardian")
		check(guardians.size() == 1, "the Dungeon Guardian comes for you (%d)" % guardians.size())
		if guardians.size() == 1:
			var g: NPC = guardians[0]
			await frames(3)
			check(g.ai_state == 2 and g.damage == 9999 and g.velocity.length() > 19.0, "always enraged, at 8 px a tick")
			g.queue_free()
		game.biome = ""
		game._biome_timer = 0.0
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	game.sky.is_day = was_day
	game.sky.time = was_time
	p.god_mode = god
	await frames(3)


## Doors: the gallery and arena doors, opening away from you (or the other way
## when blocked), seeing past an open door, not closing on you, placing,
## breaking either half, and the floor going.
func _door_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var top_id := Data.block_id("door_top")
	var doors := TestWorld.gallery_blocks().filter(func(n): return Doors.is_door(Data.block(Data.block_id(n))))
	check(doors.size() >= 6, "door styles in the gallery: %s" % [doors])
	var gallery_ok := true
	for i in TestWorld.gallery_blocks().size():
		var name: String = TestWorld.gallery_blocks()[i]
		if name in doors:
			var pos := TestWorld.gallery_pos(c, i)
			gallery_ok = gallery_ok and w.get_block(pos + Vector3i.UP) == top_id and w.is_solid(pos + Vector3i.UP)
	check(gallery_ok, "gallery doors stand 2 blocks tall")
	var gaps := []
	for n in doors:
		for h in 2:
			var art := Doors._sprite(Data.block_id(n), h)
			if art.get_used_rect().size != art.get_size():
				gaps.append("%s hinge %d" % [n, h])
	check(gaps.is_empty(), "door art fills the doorway edge to edge (gaps: %s)" % [gaps])
	# Every voxel of a door one colour (its faces don't change colour round
	# the edge, as an outline would).
	var mixed := []
	for n in doors:
		var vx := TunedModels.voxelize(Doors.panel(Data.block_id(n), 0).surface_get_arrays(0), false, null, 1.0)
		for cell in vx.cells:
			var first := Color(0, 0, 0, 0)
			for col: Color in vx.cells[cell]:
				if col.a < 0.5:
					continue
				var lin := col.srgb_to_linear()
				if first.a < 0.5:
					first = lin
				elif absf(lin.r - first.r) + absf(lin.g - first.g) + absf(lin.b - first.b) > 0.04:
					mixed.append(n)
					break
			if n in mixed:
				break
	check(mixed.is_empty() and not Doors.material(Data.block_id(doors[0]), 0).get_shader_parameter("textured"),
			"doors keep one colour per voxel (mixed: %s)" % [mixed])
	check(Data.item("WoodenDoor").get("place") == "wooden_door" and Data.recipes.any(func(r): return r.result == "WoodenDoor" and r.ingredients.has("Wood")),
			"a Wooden Door takes plain Wood at a work bench")
	check(Data.recipes.any(func(r): return r.result == "BorealWoodDoor" and r.ingredients.has("BorealWood")), "Boreal Wood Door recipe")

	# The arena's gate: a closed door facing west (toward spawn). (The town
	# NPCs open doors walking through: they wait meanwhile, any by the gate
	# go home, and one left half through it is undone.)
	var gate := c + Vector3i(9, 0, 0)
	for n in game.town.residents.values():
		n.process_mode = Node.PROCESS_MODE_DISABLED
		if n.global_position.distance_to(Vector3(gate)) < 4.0:
			n.global_position = Vector3(n.home_spot) + Vector3(0.5, 0, 0.5) if n.home_key != "" else Vector3(c) + Vector3(-6.5, 0, 0.5)
	if Doors.is_open(Data.block(w.get_block(gate))):
		Doors.toggle(game, gate, Vector3(gate) + Vector3(-2.5, 0, 0.5))
	check(Data.block(w.get_block(gate)).name == "wooden_door" and w.is_solid(gate) and w.is_solid(gate + Vector3i.UP), "the arena gate is a closed wooden door")
	var model_found := false
	for nodes in game.block_models._by_chunk.values():
		for n in nodes:
			if n.has_node("Pivot") and n.global_position.distance_to(Vector3(gate) + Vector3(0.5, 0, 0.5)) < 0.01:
				model_found = true
	check(model_found, "the door has a hinged model")

	# Open it from the west: it swings east, away from the player.
	var west := Vector3(gate) + Vector3(-2.5, 0, 0.5)
	p.global_position = west
	check(Doors.toggle(game, gate + Vector3i.UP, west), "right-clicking the top half opens the door")
	var state := game.block_rotation(gate)
	var box := Doors.world_box(gate, state, true)
	check(Data.block(w.get_block(gate)).name == "wooden_door_open" and not w.is_solid(gate) and not w.is_solid(gate + Vector3i.UP),
			"an open door can be walked through")
	check(box.get_center().x > gate.x + 0.5 and box.size.y == 2.0, "it swings away from the player (panel x %.2f)" % box.get_center().x)
	await frames(20)  # (its model rebuilt and swung open)
	await get_tree().create_timer(Doors.SWING_TIME * 2.0).timeout  # (the swing runs on the clock)
	await frames(2)
	var drawn := AABB()
	for nodes in game.block_models._by_chunk.values():
		for n in nodes:
			if n.has_node("Pivot") and n.global_position.distance_to(Vector3(gate) + Vector3(0.5, 0, 0.5)) < 0.01:
				var panel: MeshInstance3D = n.get_node("Pivot/Panel")
				drawn = panel.global_transform * panel.mesh.get_aabb()
	check(drawn.position.distance_to(box.position) < 0.02 and drawn.size.distance_to(box.size) < 0.02,
			"the open model fills its panel box (%s vs %s)" % [drawn, box])
	# Seeing past it: the crosshair through the middle of the doorway hits what's beyond.
	var eye := Vector3(gate) + Vector3(-1.5, 1.0, 0.5)
	var beyond := gate + Vector3i(3, 1, 0)
	w.set_block(beyond, Data.block_id("stone"))
	var through := Doors.raycast(game, eye, Vector3.RIGHT, 6.0)
	check(through.get("block") == beyond, "aiming through an open doorway reaches past it (%s)" % [through.get("block")])
	w.set_block(beyond, 0)
	# The panel itself, both the half in the doorway and the half beyond it.
	for x in [0.75, 1.3]:
		var aim := Vector3(gate.x + x, gate.y + 1.0, box.get_center().z)
		var at_panel := Doors.raycast(game, eye, aim - eye, 6.0)
		var on := eye + (aim - eye).normalized() * float(at_panel.get("distance", 0.0))
		check(not at_panel.is_empty() and at_panel.block == gate + Vector3i.UP and box.grow(0.01).has_point(on),
				"the open panel can be aimed at (%.2f blocks in: %s)" % [x, at_panel])
	# It won't close on someone standing in the doorway.
	p.global_position = Vector3(gate) + Vector3(0.5, 0, 0.5)
	check(not Doors.toggle(game, gate, west) and not w.is_solid(gate), "a door won't close on the player")
	p.global_position = west
	check(Doors.toggle(game, gate, west) and w.is_solid(gate) and w.get_block(gate + Vector3i.UP) == top_id, "and closes once they step out")

	# A spot in the open to build test doors on.
	var spot := Vector3i(c.x - 6, TestWorld.GROUND + 1, c.z - 12)
	for dx in range(-1, 2):
		for dz in range(-2, 3):
			for dy in 3:
				w.set_block(spot + Vector3i(dx, dy, dz), 0)
	check(w.is_solid(spot + Vector3i.DOWN), "door test spot has a floor")
	# Blocked on the side away from the player: it swings toward them instead.
	var wood_door := Data.block_id("wooden_door")
	Doors.place(game, spot, wood_door, 0)  # front +z
	w.set_block(spot + Vector3i(0, 0, 1), Data.block_id("stone"))
	var back := Vector3(spot) + Vector3(0.5, 0, -2.0)
	check(Doors.toggle(game, spot, back) and Doors.swing(game.block_rotation(spot)) == 1, "blocked one way, a door swings the other")
	Doors.toggle(game, spot, back)
	w.set_block(spot + Vector3i(0, 1, -1), Data.block_id("stone"))
	check(not Doors.toggle(game, spot, back) and w.is_solid(spot), "blocked both ways, it stays shut")
	w.set_block(spot + Vector3i(0, 0, 1), 0)
	w.set_block(spot + Vector3i(0, 1, -1), 0)

	# Breaking the top half takes the whole door and drops one.
	var drops_before := game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "WoodenDoor").size()
	game.break_block(spot + Vector3i.UP)
	var drops := game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "WoodenDoor").size()
	check(w.get_block(spot) == 0 and w.get_block(spot + Vector3i.UP) == 0 and drops == drops_before + 1, "breaking the top half breaks the door, one drop")

	# Placing from the hotbar: on the floor, front toward the player.
	var held = p.inventory.slots[p.selected]
	p.inventory.slots[p.selected] = Inventory.stack("WoodenDoor", 3)
	p.global_position = Vector3(spot) + Vector3(0.5, 0, 3.5)
	p._yaw = 0.0  # looking north (-z): the door's front turns back toward +z
	p.target = {"block": spot + Vector3i.DOWN, "normal": Vector3i.UP, "id": w.get_block(spot + Vector3i.DOWN), "distance": 3.0}
	check(p._place(Data.item("WoodenDoor")) and w.get_block(spot) == wood_door and w.get_block(spot + Vector3i.UP) == top_id
			and p.inventory.slots[p.selected].count == 2, "placing a Wooden Door stands it on the floor")
	check(Doors.facing(game.block_rotation(spot)) == 0, "it faces the player")
	var beside := spot + Vector3i(1, 0, 0)
	p.target = {"block": beside + Vector3i.DOWN, "normal": Vector3i.UP, "id": w.get_block(beside + Vector3i.DOWN), "distance": 3.0}
	w.set_block(beside + Vector3i.UP, Data.block_id("stone"))
	check(not p._place(Data.item("WoodenDoor")) and w.get_block(beside) == 0, "a door needs two free blocks over a floor")
	w.set_block(beside + Vector3i.UP, 0)
	# Mining the floor under it breaks it.
	game.break_block(spot + Vector3i.DOWN)
	check(w.get_block(spot) == 0 and w.get_block(spot + Vector3i.UP) == 0, "a door falls when its floor goes")
	w.set_block(spot + Vector3i.DOWN, Data.block_id("dirt"))
	p.inventory.slots[p.selected] = held
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	for n in game.town.residents.values():
		n.process_mode = Node.PROCESS_MODE_INHERIT
	await frames(5)


## The forest garden: every plant and bit of debris, pond plants in the pond,
## vines that fall with the grass they hang from, drops.
## Terraria's tile cutting: a swung weapon or tool cuts grass, cobwebs, vines
## and pots in its swing (not through a wall, not a plant in a pot), and the
## player's projectiles cut what they fly through.
func _cut_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var id := func(n: String) -> int: return Data.block_id(n)
	check(["tall_grass", "flowers", "cobweb", "vines", "pot", "jungle_plants", "cattail", "lily_pad", "daybloom"].all(func(n): return Data.block(id.call(n)).get("cut", false))
			and not ["sunflower", "life_crystal", "small_rocks", "torch", "stone"].any(func(n): return Data.block(id.call(n)).get("cut", false)),
			"Terraria's cuttable tiles (grass, cobwebs, vines, pots... not sunflowers, rocks or life crystals)")
	var base := c + Vector3i(-40, 0, 60)
	for x in range(-4, 5):
		for z in range(-9, 3):
			w.set_block(base + Vector3i(x, -1, z), id.call("grass"))
			for y in range(0, 5):
				w.set_block(base + Vector3i(x, y, z), 0)
	# In front: grass, a cobweb, a pot, a vine under a block; a plant in a clay pot.
	w.set_block(base + Vector3i(0, 0, -2), id.call("tall_grass"))
	w.set_block(base + Vector3i(-1, 0, -2), id.call("pot"))
	w.set_block(base + Vector3i(1, 1, -2), id.call("cobweb"))
	w.set_block(base + Vector3i(-1, 3, -2), id.call("stone"))
	w.set_block(base + Vector3i(-1, 2, -2), id.call("vines"))
	w.set_block(base + Vector3i(1, 0, -1), id.call("clay_pot"))
	w.set_block(base + Vector3i(1, 1, -1), id.call("tall_grass"))
	var held := p.selected
	p.inventory.slots[9] = Inventory.stack("WoodenSword", 1)
	p.select(9)
	p.global_position = Vector3(base) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	p.look_at_yaw_pitch(0.0, -0.45)
	await frames(3)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	await frames(2)
	var gone := func(o: Vector3i) -> bool: return w.get_block(base + o) == 0
	check(gone.call(Vector3i(0, 0, -2)) and gone.call(Vector3i(-1, 0, -2)) and gone.call(Vector3i(1, 1, -2)) and gone.call(Vector3i(-1, 2, -2)),
			"a sword swing cuts the grass, pot, cobweb and vine in front")
	check(w.get_block(base + Vector3i(1, 1, -1)) == id.call("tall_grass"), "but not a plant in a clay pot")
	# Behind a wall it isn't cut.
	w.set_block(base + Vector3i(0, 0, -1), id.call("stone"))
	w.set_block(base + Vector3i(0, 1, -1), id.call("stone"))
	w.set_block(base + Vector3i(0, 0, -2), id.call("tall_grass"))
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	await frames(2)
	check(w.get_block(base + Vector3i(0, 0, -2)) == id.call("tall_grass"), "grass behind a wall isn't cut")
	# Projectiles: the player's arrow cuts the grass it flies through, an
	# enemy's doesn't.
	# (A critter or enemy in the way would stop the arrow, as in Terraria, so
	# clear them and hold the spawner off while it flies.)
	for n in game.npcs():
		if n.is_critter() or (n.def.ai != "town" and n.def.get("damage", 0) > 0 and n.global_position.distance_to(Vector3(base)) < 16.0):
			n.queue_free()
	var spawner_mode := game.spawner.process_mode
	game.spawner.process_mode = Node.PROCESS_MODE_DISABLED
	for z in range(-8, -2):
		w.set_block(base + Vector3i(3, 0, z), id.call("tall_grass"))
		w.set_block(base + Vector3i(-3, 0, z), id.call("tall_grass"))
	game.spawn_projectile("WoodenArrowFriendly", Vector3(base) + Vector3(3.5, 0.5, -2.2), Vector3(0, 0, -20), 5, 0.0)
	game.spawn_projectile("WoodenArrowFriendly", Vector3(base) + Vector3(-2.5, 0.5, -2.2), Vector3(0, 0, -20), 5, 0.0, 0.0, 0.0, 0.5, false)
	# Until the arrow has flown past it all (frame timing varies headless).
	for i in 120:
		await get_tree().physics_frame
		if range(-8, -2).all(func(z): return w.get_block(base + Vector3i(3, 0, z)) == 0):
			break
	check(range(-8, -2).all(func(z): return w.get_block(base + Vector3i(3, 0, z)) == 0), "your arrow cuts the grass it flies through (left at z %s; about: %s)" % [range(-8, -2).filter(func(z): return w.get_block(base + Vector3i(3, 0, z)) != 0), game.npcs().filter(func(n): return n.global_position.distance_to(Vector3(base)) < 12.0).map(func(n): return n.kind)])
	check(range(-8, -2).all(func(z): return w.get_block(base + Vector3i(-3, 0, z)) == id.call("tall_grass")), "an enemy's doesn't")
	game.spawner.process_mode = spawner_mode
	p.inventory.slots[9] = null
	p.select(held)
	# What the pot and plants dropped (the pot's coins would count as money).
	for e in game.entities.get_children():
		if e is ItemDrop:
			e.free()
	await frames(1)


## The biome cabins' chests and what they hold: the loot tables, the new
## weapons, accessories and furniture.
## Terraria's run: 0.625 s to its 3 px/tick (7.5 blocks/s); boots speed on
## to 6 (15 blocks/s), on the ground only; letting go slows you by 0.2 px/tick
## a tick (30 blocks/s a second).
func _run_checks(p: Player) -> void:
	var run := func(ticks: int, dir: Vector3, acc_run: float, floor: bool) -> float:
		p.on_floor = floor
		for i in ticks:
			p._run(1.0 / 60.0, dir, Player.RUN_SPEED, acc_run, Player.RUN_ACCEL, Player.RUN_SLOWDOWN)
		return Vector2(p.velocity.x, p.velocity.z).length()
	var saved := p.velocity
	p.velocity = Vector3.ZERO
	var early: float = run.call(30, Vector3.RIGHT, Player.RUN_SPEED, true)
	var top: float = run.call(30, Vector3.RIGHT, Player.RUN_SPEED, true)
	# (At the top it wobbles, like Terraria's: speeding up below it, slowing above.)
	check(early < 6.5 and top > 6.9 and top < 7.7, "running reaches Terraria's speed in about 0.6 s (%.2f after 0.5 s, %.2f after 1 s)" % [early, top])
	var air_boots: float = run.call(120, Vector3.RIGHT, 15.0, false)
	var boots: float = run.call(240, Vector3.RIGHT, 15.0, true)
	check(air_boots < 7.7 and boots > 14.5 and boots < 15.3, "boots speed up to 15 blocks/s on the ground only (%.2f in the air, %.2f on the ground)" % [air_boots, boots])
	run.call(20, Vector3.ZERO, Player.RUN_SPEED, true)
	var stopped: float = Vector2(p.velocity.x, p.velocity.z).length()
	check(stopped < 7.0, "letting go slows you by 30 blocks/s a second (%.2f a third of a second after 15)" % stopped)
	p.velocity = saved


func _cabin_loot_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var id := func(n: String) -> int: return Data.block_id(n)
	check(Chests.LOOT[4] == "frozen_chest" and Chests.LOOT[5] == "sandstone_chest" and Chests.LOOT[6] == "sandstone_chest_deep", "cabin chest styles name their loot")
	for t in ["frozen_chest", "sandstone_chest", "sandstone_chest_deep"]:
		var entries: Array = Data.loot[t].pick_one + Data.loot[t].get("instead", [])
		check(entries.all(func(e): return Data.items.has(e[0])), "every %s item is in the game" % t)
	for b in ["frozen_chest", "sandstone_chest", "rich_mahogany_chest", "boreal_wood_wall", "sandstone_column", "sandstone_door", "icicle", "jungle_vines", "bast_statue", "extractinator", "sharpening_station"]:
		check(id.call(b) > 0, "block " + b)
	check(Data.block(id.call("jungle_vines")).get("cut", false) and not Data.block(id.call("icicle")).get("cut", false), "jungle vines are cut by a swing, icicles aren't")
	check(Data.recipes.any(func(r): return r.result == "SandstoneDoor") and Data.recipes.any(func(r): return r.result == "Snowball"), "Terraria's recipes for the new furniture and snowballs")
	# Double jumps: the Cloud's, then the Blizzard's (higher).
	p.accessories.slots[0] = Inventory.stack("BlizzardinaBottle", 1)
	p.accessories.slots[1] = Inventory.stack("CloudinaBottle", 1)
	var jumps := p.extra_jumps()
	check(jumps.size() == 2 and jumps[0] < jumps[1], "Cloud then Blizzard in a Bottle: two jumps in the air, the Blizzard's higher (%s)" % [jumps])
	p.accessories.slots[0] = Inventory.stack("SandBoots", 1)
	p.accessories.slots[1] = Inventory.stack("AncientChisel", 1)
	check(p.stat("sand_run") == 1.75 and p.has_effect("run_speed") and p.stat("mining_speed") == 25, "Dunerider Boots run faster on sand; the Ancient Chisel mines 25% faster")
	p.accessories.slots[0] = null
	p.accessories.slots[1] = null
	# A clear spot.
	var base := c + Vector3i(-40, 0, 80)
	for x in range(-6, 7):
		for z in range(-6, 7):
			w.set_block(base + Vector3i(x, -1, z), id.call("grass"))
			for y in range(0, 8):
				w.set_block(base + Vector3i(x, y, z), 0)
	p.global_position = Vector3(base) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	p.look_at_yaw_pitch(0.0, -0.6)
	# The Sharpening Station: Sharpened, melee pierces 12 armor.
	w.set_block(base + Vector3i(0, 0, -2), id.call("sharpening_station"))
	await frames(3)
	p._interact()
	check(p.sharpened and p.armor_penetration({"type": "melee"}) == 12 and p.armor_penetration({"type": "magic"}) == 0, "the Sharpening Station sharpens melee weapons (12 armor penetration)")
	check(p.buffs().any(func(b): return b[1] == "Sharpened"), "the Sharpened buff shows")
	p.sharpened = false
	w.set_block(base + Vector3i(0, 0, -2), 0)
	# A Bast Statue near: +5 defense.
	var before := p.defense()
	w.set_block(base + Vector3i(4, 0, 4), id.call("bast_statue"))
	p._bast_check = 0.0
	await frames(2)
	check(p.bast_near and p.defense() == before + 5, "a Bast Statue nearby: The Bast Defense, +5 defense (%d -> %d)" % [before, p.defense()])
	w.set_block(base + Vector3i(4, 0, 4), 0)
	p._bast_check = 0.0
	await frames(2)
	check(not p.bast_near and p.defense() == before, "gone when it is")
	var held := p.selected
	var shots := func(kind: String) -> Array:
		return game.entities.get_children().filter(func(e): return e is Projectile and e.kind == kind and not e.is_queued_for_deletion())
	# The Ice Blade: an icy bolt with a swing, then not again for 55 ticks.
	p.inventory.slots[9] = Inventory.stack("IceBlade", 1)
	p.select(9)
	p.look_at_yaw_pitch(0.0, 0.0)
	p._swing_shot_cd = 0.0
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	p._use_timer = 0.0
	p.use_item()
	check(shots.call("IceBolt").size() == 1, "the Ice Blade shoots an icy bolt, at most every 55 ticks")
	# The Enchanted Sword: an Enchanted Beam with a swing (useTime 45 over a
	# 21-tick swing), 9.5 px a tick, glowing, trailing dust.
	p.inventory.slots[9] = Inventory.stack("EnchantedSword", 1)
	p._swing_shot_cd = 0.0
	p._use_timer = 0.0
	p.use_item()
	p._use_timer = 0.0
	p.use_item()
	var beams: Array = shots.call("EnchantedBeam")
	check(beams.size() == 1 and absf(beams[0].velocity.length() - 9.5 * 60.0 / 16.0) < 0.01 and beams[0].glow != Color.BLACK
			and not beams[0]._trail.is_empty() and Assets.ids.ItemID.get("EnchantedSword") == 989,
			"the Enchanted Sword (item 989) shoots one glowing Enchanted Beam a swing, at most every 45 ticks")
	# The Snowball Cannon: snowballs, lobbed.
	p.inventory.slots[9] = Inventory.stack("SnowballCannon", 1)
	p.inventory.slots[8] = Inventory.stack("Snowball", 20)
	p._use_timer = 0.0
	p.use_item()
	var balls: Array = shots.call("SnowBallFriendly")
	check(balls.size() == 1 and balls[0].gravity_delay > 0.0 and p.inventory.count_of("Snowball") == 19, "the Snowball Cannon fires snowballs (aiStyle 2: they drop after a moment)")
	# The Glacier Fang: hold to charge; at full charge the icicle flies by
	# itself, 400% damage, piercing 2.
	p.inventory.slots[9] = Inventory.stack("GlacierFang", 1)
	p.inventory.slots[8] = null
	var mana_max := p.mana_max
	p.mana_max = 100
	p.mana = p.mana_cap()
	var mana_before := p.mana
	p.hold_use = true
	p._use_timer = 0.0
	p.use_item()
	check(not p.charging.is_empty(), "the Glacier Fang charges while held")
	var t := 0.0
	while not p.charging.is_empty() and t < 2.0:
		p._use_timer = 1.0  # (no mana coming back meanwhile)
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	p.hold_use = false
	var icicles: Array = shots.call("GlacierFangShot")
	check(icicles.size() == 1 and icicles[0].penetrate == 3 and icicles[0].damage >= 40, "a full charge: one icicle, 400%% damage, piercing 2 (%s)" % [icicles.map(func(i): return [i.damage, i.penetrate])])
	check(mana_before - p.mana == 30 and t < 1.2, "10 mana to start, 10 more at a third and two thirds (%d) over a second (%.2f)" % [mana_before - p.mana, t])
	p.mana_max = mana_max
	p.mana = mini(p.mana, p.mana_cap())
	# The Snake Charmer's Flute: a rope snake up into the open sky, climbable.
	p.inventory.slots[9] = Inventory.stack("MysticCoilSnake", 1)
	p.target = {}
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	var snakes := get_tree().get_nodes_in_group("rope_snakes")
	check(snakes.size() == 1, "the flute summons a rope snake")
	for i in 90:
		await get_tree().physics_frame
	if snakes.size() == 1:
		var snake = snakes[0]
		check(snake.length > 20.0, "it rises into the sky (%.1f blocks)" % snake.length)
		var y0 := p.global_position.y
		Input.action_press("jump")
		for i in 40:
			await get_tree().physics_frame
		Input.action_release("jump")
		check(p.climbing == snake and p.global_position.y > y0 + 2.0, "jumping onto it climbs it (%.1f up)" % (p.global_position.y - y0))
		for i in 20:
			await get_tree().physics_frame
		check(p.climbing == snake and absf(p.velocity.y) < 0.01, "and you hang on")
		snake.queue_free()
		p.climbing = null
	# The Magic Conch: the test world has no sea, so it goes nowhere.
	check(game.far_beach(p.global_position) == null or not game.has_ocean, "no ocean, no beach")
	p.inventory.slots[9] = null
	p.select(held)
	for e in game.entities.get_children():
		if e is Projectile:
			e.queue_free()
	p.global_position = Vector3(base) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(2)


## Falling sand (and silt and slush), burying, and the Extractinator.
func _sand_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var id := func(n: String) -> int: return Data.block_id(n)
	var sand: int = id.call("sand")
	check(id.call("silt") > 0 and id.call("slush") > 0 and ["sand", "ebonsand", "crimsand", "silt", "slush"].all(func(n): return Data.block(Data.block_id(n)).get("falls", false)),
			"sand, ebonsand, crimsand, silt and slush fall")
	check(Data.item("SiltBlock").get("extractinator", false) and Data.item("SlushBlock").get("extractinator", false), "silt and slush go in the Extractinator")
	var base := c + Vector3i(-40, 0, 100)
	for x in range(-6, 7):
		for z in range(-6, 7):
			w.set_block(base + Vector3i(x, -1, z), id.call("grass"))
			for y in range(0, 12):
				w.set_block(base + Vector3i(x, y, z), 0)
	p.global_position = Vector3(base) + Vector3(5.5, 0, 5.5)
	p.velocity = Vector3.ZERO
	var falling := func() -> int: return game.entities.get_children().filter(func(e): return e is FallingBlock).size()
	# Three sand on a stone pillar: take the pillar's top and they fall onto
	# what's left.
	var col := base + Vector3i(-3, 0, -3)
	for y in 4:
		w.set_block(col + Vector3i(0, y, 0), id.call("stone"))
	for y in range(4, 7):
		w.set_block(col + Vector3i(0, y, 0), sand)
	game.break_block(col + Vector3i(0, 3, 0), false)
	check(falling.call() == 3 and w.get_block(col + Vector3i(0, 4, 0)) == 0, "taking the block under sand drops the whole column (%d falling)" % falling.call())
	await frames(60)
	check(falling.call() == 0 and w.get_block(col + Vector3i(0, 3, 0)) == sand and w.get_block(col + Vector3i(0, 5, 0)) == sand and w.get_block(col + Vector3i(0, 6, 0)) == 0,
			"and it settles on the pillar")
	# Silt set over a gap falls to the ground; sand onto a torch drops as an item.
	w.set_block(col + Vector3i(2, 6, 0), id.call("silt"))
	game.settle_falling(col + Vector3i(2, 6, 0))
	w.set_block(col + Vector3i(4, 0, 0), id.call("torch"))
	w.set_block(col + Vector3i(4, 5, 0), sand)
	game.settle_falling(col + Vector3i(4, 5, 0))
	await frames(60)
	var drops := game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "SandBlock")
	check(w.get_block(col + Vector3i(2, 0, 0)) == id.call("silt") and w.get_block(col + Vector3i(4, 0, 0)) == id.call("torch") and drops.size() == 1,
			"silt over a gap falls to the ground; sand landing on a torch drops as an item")
	for d in drops:
		d.queue_free()
	# Falling sand hurts (10) and buries you: Suffocation.
	var god := p.god_mode
	p.god_mode = false
	p.global_position = Vector3(base) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(5)
	p.life = p.life_max
	p._immune = 0.0
	w.set_block(base + Vector3i(0, 8, 0), sand)
	game.settle_falling(base + Vector3i(0, 8, 0))
	await frames(50)
	var hit := p.life_max - p.life
	check(hit > 0 and w.get_block(base) == sand and p.suffocating and p.buffs().any(func(b): return b[1] == "Suffocation"),
			"falling sand hurts (%d) and buries you: Suffocation" % hit)
	var stuck_at := p.global_position
	var life := p.life
	await get_tree().create_timer(0.5).timeout
	check(p.global_position == stuck_at and stuck_at.y < base.y + 1.0, "you're stuck in it (y %.2f)" % p.global_position.y)
	check(life - p.life >= 7 and life - p.life <= 13, "suffocating takes 20 life a second (%d in half a second)" % (life - p.life))
	w.set_block(base, 0)
	await frames(2)
	check(not p.suffocating, "dug out, you breathe again")
	p.god_mode = god
	p.life = p.life_max
	# The Extractinator's roll (Terraria's, for silt and slush).
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var kinds := {"coin": 0, "ore": 0, "gem": 0, "Amber": 0, "other": 0}
	var all_known := true
	var n := 30000
	for i in n:
		var r := Extractinator.roll(rng)
		all_known = all_known and Data.items.has(r[0]) and int(r[1]) >= 1
		var k: String = "coin" if r[0].ends_with("Coin") else ("ore" if r[0].ends_with("Ore") else ("gem" if r[0] in Extractinator.GEMS else ("Amber" if r[0] == "Amber" else "other")))
		kinds[k] += 1
	var share := func(k: String) -> float: return float(kinds[k]) / n
	check(all_known and absf(share.call("coin") - 0.657) < 0.015 and absf(share.call("ore") - 0.314) < 0.015 and absf(share.call("gem") - 0.02) < 0.005 and absf(share.call("Amber") - 0.0096) < 0.004,
			"the Extractinator's odds: %.1f%% coins, %.1f%% ore, %.1f%% gems, %.1f%% Amber" % [share.call("coin") * 100, share.call("ore") * 100, share.call("gem") * 100, share.call("Amber") * 100])
	# Silt into an Extractinator: one block a use, something drops.
	w.set_block(base + Vector3i(0, 0, -2), id.call("extractinator"))
	p.global_position = Vector3(base) + Vector3(0.5, 0, 0.5)
	p.look_at_yaw_pitch(0.0, -0.6)
	var held := p.selected
	p.inventory.slots[9] = Inventory.stack("SiltBlock", 5)
	p.select(9)
	await frames(3)
	var before := game.entities.get_children().filter(func(e): return e is ItemDrop).size()
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	var after := game.entities.get_children().filter(func(e): return e is ItemDrop).size()
	check(p.inventory.slots[9] != null and p.inventory.slots[9].count == 4 and after == before + 1 and w.get_block(base + Vector3i(0, 0, -2)) == id.call("extractinator"),
			"silt goes into the Extractinator one block a use, and something drops out")
	check(is_equal_approx(p._use_timer, Player.EXTRACT_TIME), "one block every 10 ticks")
	for e in game.entities.get_children():
		if e is ItemDrop:
			e.queue_free()
	p.inventory.slots[9] = null
	p.select(held)
	w.set_block(base + Vector3i(0, 0, -2), 0)


## Terraria's tile dust: each block's own dust type, 10 when it breaks, 3 on
## a hit; specks that fall, shrink and go.
func _dust_checks(c: Vector3i) -> void:
	var w := game.world
	var d := game.dust
	var id := func(n: String) -> int: return Data.block_id(n)
	check(not Data.tile_dust.is_empty(), "Terraria's tile dust is loaded (tools/terraria_dust.py)")
	check(Data.tile_dust.tall_grass.dust[0][0] == 3 and Data.tile_dust.stone.dust[0][0] == 1 and Data.tile_dust.wood.dust[0][0] == 7 \
			and Data.tile_dust.pot.dust[0][0] == 22 and Data.tile_dust.blue_torch.dust[0][0] == 59,
			"each block's own dust: grass 3, stone 1, wood 7, pots 22, a blue torch 59")
	var undusted := []
	for i in range(1, Data.blocks.size()):
		if Data.blocks[i].has("tile_id") and not Data.tile_dust.has(Data.blocks[i].name):
			undusted.append(Data.blocks[i].name)
	check(undusted.is_empty(), "every block drawn from a Terraria tile has its dust (missing: rerun tools/terraria_dust.py after adding blocks) %s" % [undusted.slice(0, 10)])
	var base := c + Vector3i(-40, 0, 100)
	var types := func() -> Array:
		var out := []
		for t in d._type:
			if not t in out:
				out.append(t)
		return out
	await frames(200)  # the earlier dust gone
	var before := d.count()
	w.set_block(base + Vector3i(2, 0, 2), id.call("tall_grass"))
	game.break_block(base + Vector3i(2, 0, 2))
	check(d.count() == before + 10 and types.call() == [3], "breaking tall grass throws 10 grass dust (%d, %s)" % [d.count() - before, types.call()])
	before = d.count()
	game.block_hit_effects(base + Vector3i(0, -1, 0), id.call("stone"))
	check(d.count() == before + 3, "a hit on a block throws 3 (%d)" % (d.count() - before))
	before = d.count()
	w.set_block(base + Vector3i(4, 0, 2), id.call("wooden_table"))
	game.break_block(base + Vector3i(4, 0, 2))
	check(d.count() == before, "a table makes none, like Terraria's")
	await frames(20)
	check(d.count() > 0 and d._scale.size() == d.count(), "dust lingers a moment")
	await frames(130)
	check(d.count() == 0, "and is gone within a couple of seconds (%d left)" % d.count())
	for e in game.entities.get_children():
		if e is ItemDrop:
			e.queue_free()


## Knockback, as far as Terraria's: each enemy hit (knockback 5 for ~12
## damage, then 8 for ~20) flies back as far at its farthest as Terraria's
## own tick-by-tick rules carry it (StrikeNPC_Inner, then its AI, gravity and
## the ground: worked out by a transcription of them, in blocks; aiStyle
## 14 steers a bat twice a tick).
const KNOCKBACK_TERRARIA := {
	"Zombie": [1.713, 4.052], "BlueSlime": [2.434, 4.24], "DemonEye": [1.108, 5.392],
	"EaterofSouls": [3.203, 8.25], "CaveBat": [3.25, 4.5],
}


func _knockback_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var god := p.god_mode
	p.god_mode = true
	# A long stone floor up in the air, nothing round it.
	var base := c + Vector3i(-20, 30, 60)
	for x in range(-8, 26):
		for z in range(-3, 4):
			w.set_block(base + Vector3i(x, -1, z), Data.block_id("stone"))
			for y in range(0, 10):
				w.set_block(base + Vector3i(x, y, z), 0)
	for kind in KNOCKBACK_TERRARIA:
		for k in 2:
			var kb: float = [5.0, 8.0][k]
			var dmg: int = [12, 20][k]
			p.global_position = Vector3(base) + Vector3(-5.5, 0, 0.5)
			p.velocity = Vector3.ZERO
			var npc := game.spawn_npc(kind, Vector3(base) + Vector3(0.5, 0, 0.5))
			var flier: bool = npc.flying
			if flier:
				# At the height it flies at (the player's middle), hovering.
				npc.global_position.y = maxf(npc.global_position.y + p.global_position.y + 1.0 - npc.center().y, float(base.y) + 0.05)
			npc.velocity = Vector3.ZERO
			if kind == "Zombie":
				npc.velocity = Vector3(-float(npc.def.speed), 0, 0)  # walking at you
			npc.ai_timer = 100.0 if kind == "CaveBat" else -100.0  # no hops or wandering
			npc._wander = Vector3.ZERO
			await frames(2) if flier else await frames(10)
			if kind == "Zombie":
				npc.velocity = Vector3(-float(npc.def.speed), 0, 0)
			var x0: float = npc.global_position.x
			# The damage it takes: what's asked of hit() before its roll and defense.
			var life := npc.life
			npc.life = 9999
			npc.hit(int(round((dmg + int(npc.def.get("defense", 0)) * 0.5) / 1.0)), kb, Vector3.RIGHT, 0.0)
			var far := 0.0
			for i in 240:
				await get_tree().physics_frame
				far = maxf(far, npc.global_position.x - x0)
				if npc.global_position.x - x0 < far - 0.1:
					break
			var want: float = KNOCKBACK_TERRARIA[kind][k]
			check(absf(far - want) < maxf(0.2, want * 0.12), "%s, knockback %d: flies back %.2f blocks (Terraria %.2f)" % [kind, int(kb), far, want])
			npc.queue_free()
			await frames(1)
	p.god_mode = god


## Gibbing: a zombie dies into Terraria's gores for it (head, two arms, two
## legs: Gore 3, 4, 5) and 50 blood dust; they fall, come to rest on the
## ground and fade away. A slime leaves no gore, just its own dust.
func _gore_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	# A wide floor up in the air: gores slide a long way (x0.97 a tick).
	var base := c + Vector3i(0, 45, 0)
	for x in range(-30, 31):
		for z in range(-30, 31):
			w.set_block(base + Vector3i(x, -1, z), Data.block_id("stone"))
			for y in range(0, 4):
				w.set_block(base + Vector3i(x, y, z), 0)
	var god := p.god_mode
	p.god_mode = true
	p.global_position = Vector3(base) + Vector3(-5.5, 0, 0.5)
	p._fall_start = p.global_position.y
	await frames(30)
	var gores := func() -> Array: return game.entities.get_children().filter(func(e): return e is Gore)
	var g: Dictionary = Data.npc_gore.get("Zombie", {})
	check(not g.is_empty() and g.gores[0].map(func(x): return int(x[0])) == [3, 4, 4, 5, 5],
			"a zombie's gores, as Terraria's: head, two arms, two legs (%s)" % [g.get("gores", [[]])[0].map(func(x): return int(x[0]))])
	var zombie := game.spawn_npc("Zombie", Vector3(base) + Vector3(0.5, 0, 0.5))
	await frames(5)
	var dust_before := game.dust.count()
	zombie.hit(9999, 5.0, Vector3.RIGHT, 0.0)
	var pieces: Array = gores.call()
	check(pieces.size() == 5 and game.dust.count() - dust_before >= 45, "it bursts into 5 pieces and blood (%d pieces, %d dust)" % [pieces.size(), game.dust.count() - dust_before])
	await frames(420)
	var resting := pieces.filter(func(x): return is_instance_valid(x) and x.velocity.length() < 0.05 and absf(x.global_position.y - base.y) < 0.05)
	check(resting.size() == 5, "the pieces fall and come to rest on the ground (%d of 5)" % resting.size())
	for x in pieces:
		x._ticks = Gore.LIFE + Gore.FADE - 3
	await frames(10)
	check(gores.call().is_empty(), "and fade away (Terraria: after 10 s, over 4 more)")
	var slime := game.spawn_npc("BlueSlime", Vector3(base) + Vector3(0.5, 0, 0.5))
	await frames(5)
	dust_before = game.dust.count()
	slime.hit(9999, 5.0, Vector3.RIGHT, 0.0)
	check(gores.call().is_empty() and game.dust.count() - dust_before >= 45 and game.dust._tint[game.dust.count() - 1] != Color.WHITE,
			"a slime leaves no gore, just dust of its own colour")
	# Take the floor down again (it shades the plaza) and come back down.
	for x in range(-30, 31):
		for z in range(-30, 31):
			w.set_block(base + Vector3i(x, -1, z), 0)
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p._fall_start = p.global_position.y
	p.velocity = Vector3.ZERO
	await frames(30)
	p.god_mode = god


func _flora_checks(c: Vector3i) -> void:
	var w := game.world
	var g := c + TestWorld.GARDEN
	var found := {}
	for x in range(-12, 13):
		for z in range(-11, 9):
			for y in range(-3, 5):
				found[Data.block(w.get_block(g + Vector3i(x, y, z))).get("name", "air")] = true
	var want := ["tall_grass", "taller_grass", "flowers", "tall_flowers", "mushroom", "sunflower", "small_rocks",
			"twigs", "large_rocks", "fallen_log", "vines", "vine_flowers", "lily_pad", "cattail", "cattail_stem", "cattail_top"]
	check(want.all(func(n): return found.has(n)), "the forest garden has every plant (missing %s)" % [want.filter(func(n): return not found.has(n))])
	check(want.all(func(n): return not Data.block(Data.block_id(n)).get("solid", true)),
			"forest plants and debris can be walked through")
	# Pond plants: lily pads float on the water, cattails stand in it.
	var lily := g + Vector3i(3, 0, 3)
	var cattail := g + Vector3i(2, -2, 7)
	check(Data.block(w.get_block(lily)).get("name", "") == "lily_pad" and w.get_liquid(lily + Vector3i.DOWN).x == 1, "a lily pad floats on the pond")
	check(Data.block(w.get_block(cattail)).get("name", "") == "cattail" and w.get_liquid(cattail).x == 1
			and Data.block(w.get_block(cattail + Vector3i(0, 2, 0))).get("name", "") == "cattail_top" and w.get_liquid(cattail + Vector3i(0, 2, 0)).y == 0,
			"a cattail grows up through the water, its head above it")
	# Breaking a cattail's base takes the rest of it.
	game.break_block(cattail, false)
	check(w.get_block(cattail + Vector3i.UP) == 0 and w.get_block(cattail + Vector3i(0, 2, 0)) == 0, "a cattail falls when its base goes")
	# Vines hang from the ledge's grass and fall with it.
	var vine := Vector3i(-1, -1, -1)
	for x in range(-9, -3):
		for z in range(2, 6):
			var q := g + Vector3i(x, 2, z)
			if vine.x < 0 and Data.block(w.get_block(q)).get("name", "") in ["vines", "vine_flowers"]:
				vine = q
	check(vine.x >= 0 and Data.block(w.get_block(vine + Vector3i.UP)).get("name", "") == "grass", "vines hang under the ledge's grass")
	if vine.x >= 0:
		var below := vine
		while Data.block(w.get_block(below + Vector3i.DOWN)).get("name", "") in ["vines", "vine_flowers"]:
			below += Vector3i.DOWN
		game.break_block(vine + Vector3i.UP, false)
		check(w.get_block(vine) == 0 and w.get_block(below) == 0, "vines fall when the grass above them is mined")
	# The herb bed: all seven, each as a sprout, grown and in bloom, on its soil.
	var bed := []
	for h in Herbs.STYLES.size():
		for stage in 3:
			var q := g + TestWorld.HERB_BED + Vector3i(h * 4 + stage, 0, 0)
			var b := Data.block(w.get_block(q))
			if b.has("herb") and int(b.herb) == h and Data.block(w.get_block(q + Vector3i.DOWN)).get("name", "") in b.grows_on:
				bed.append(b.name)
	check(bed.size() == 21, "the herb bed has all seven herbs on their soils (%d of 21)" % bed.size())
	# Drops: a mushroom and sunflowers.
	var drops := func(name: String) -> int:
		return game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == name).size()
	for pair in [["mushroom", "Mushroom"], ["sunflower", "Sunflower"]]:
		var at := Vector3i(-1, -1, -1)
		for x in range(-12, 13):
			for z in range(-11, 0):
				if at.x < 0 and Data.block(w.get_block(g + Vector3i(x, 0, z))).get("name", "") == pair[0]:
					at = g + Vector3i(x, 0, z)
		var before: int = drops.call(pair[1])
		game.break_block(at)
		check(drops.call(pair[1]) == before + 1, "breaking %s drops %s" % [pair[0], pair[1]])
	await frames(2)


## Props (block models) are drawn in batches with each block's light in the
## instance data, not one node each with a shader instance uniform: those ran
## out in big worlds, and props rebuilt after breaking one drew black.
## Plants, rocks and debris on the ground ("vary") turn and mirror by cell.
func _vary_checks(c: Vector3i) -> void:
	var w: VoxelWorld = game.world
	var bm := game.block_models
	var o := c + Vector3i(-20, 45, 40)
	for x in range(0, 24):
		w.set_block(o + Vector3i(x, -1, 0), Data.block_id("stone"))
		w.set_block(o + Vector3i(x, 0, 0), Data.block_id("small_rocks"))
	await frames(12)
	var looks := {}
	var drawn := 0
	var first := []
	for x in range(0, 24):
		var m: Dictionary = bm.model_at(o + Vector3i(x, 0, 0))
		if m.is_empty():
			continue
		drawn += 1
		var b: Basis = m.transform.basis
		looks[[roundi(b.x.x), roundi(b.x.z), signf(b.determinant())]] = true
		first.append(m.transform)
	check(Data.block(Data.block_id("small_rocks")).get("vary", false) and drawn == 24 and looks.size() >= 4,
			"small rocks lie turned and mirrored every which way (%d looks in %d)" % [looks.size(), drawn])
	# The same every time for their cell.
	var chunk := Vector3i(floori(o.x / 32.0), floori(o.y / 32.0), floori(o.z / 32.0))
	bm.chunk_updated(chunk)
	var again := []
	for x in range(0, 24):
		var m: Dictionary = bm.model_at(o + Vector3i(x, 0, 0))
		if not m.is_empty():
			again.append(m.transform)
	check(again == first, "and the same each time they're drawn")
	for x in range(0, 24):
		w.set_block(o + Vector3i(x, 0, 0), 0)
		w.set_block(o + Vector3i(x, -1, 0), 0)


func _prop_batch_checks(c: Vector3i) -> void:
	var bm := game.block_models
	var loose := []
	for nodes in bm._by_chunk.values():
		for n in nodes:
			if not (n is MultiMeshInstance3D or n.has_node("Pivot")):
				loose.append(n)
	check(loose.is_empty() and bm.count() > bm._by_chunk.values().reduce(func(a, b): return a + b.size(), 0),
			"props are batched per chunk, not one node each (%d props, %d loose nodes)" % [bm.count(), loose.size()])
	var names := TestWorld.gallery_blocks()
	var pot := TestWorld.gallery_pos(c, names.find("pot"))
	var others := [TestWorld.gallery_pos(c, names.find("chest")), TestWorld.gallery_pos(c, names.find("life_crystal"))]
	game.break_block(pot)
	await frames(10)
	var lit := true
	for q in others:
		var m: Dictionary = bm.model_at(q)
		lit = lit and not m.is_empty() and m.light == game.world.get_light(Vector3(q) + Vector3(0.5, 0.5, 0.5)) and m.light.a > 0.5
	check(bm.model_at(pot).is_empty() and lit, "breaking a prop leaves the props around it lit")
	game.world.set_block(pot, Data.block_id("pot"))
	await frames(5)


## The Goblin Army and the Goblin Tinkerer: the Battle Standard summons the
## army from a world edge, it marches in, its goblins come while you're near
## and each kill counts down to its defeat; then the Tinkerer, found bound,
## is freed into the town with his shop, and his Tinkerer's Workshop makes
## the combinations. His Rocket Boots, the Spiky Ball, the Harpoon and the
## combinations' effects too.
func _goblin_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var inv: Invasion = game.invasion
	# (The goblins killed here drop things you'd pick up: the inventory is put
	# back as it was at the end.)
	var kept_slots := p.inventory.slots.duplicate(true)
	var recipe := func(result: String) -> Dictionary:
		for r in Data.recipes:
			if r.result == result:
				return r
		return {}
	check(recipe.call("GoblinBattleStandard").get("ingredients", {}).get("TatteredCloth") == 10 and recipe.call("GoblinBattleStandard").get("station") == "loom",
			"the Goblin Battle Standard: 10 Tattered Cloth and 5 Wood at a Loom")
	check(Data.npcs.GoblinScout.drops.any(func(d): return d[0] == "TatteredCloth" and d[3] == 1.0)
			and ["GoblinPeon", "GoblinThief", "GoblinWarrior", "GoblinSorcerer", "GoblinArcher"].all(func(k): return Data.npcs[k].drops.any(func(d): return d[0] == "SpikyBall") and Data.npcs[k].drops.any(func(d): return d[0] == "Harpoon")),
			"Goblin Scouts drop Tattered Cloth; the army's goblins Spiky Balls and Harpoons")
	var combos := ["CloudinaBalloon", "BlueHorseshoeBalloon", "ObsidianShield", "ManaRegenerationBand", "MagicCuffs", "TigerClimbingGear", "SpectreBoots", "LightningBoots", "FrostsparkBoots", "GPS", "LavaSkull", "FairyBoots"]
	check(combos.all(func(n): return recipe.call(n).get("station") == "tinkerers_workshop"), "the combinations are made at the Tinkerer's Workshop (%s)" % [combos.filter(func(n): return recipe.call(n).get("station") != "tinkerers_workshop")])
	# The army: summoned, marching in from an edge, arriving.
	var held := p.selected
	var god := p.god_mode
	p.god_mode = true
	p.inventory.slots[p.selected] = Inventory.stack("GoblinBattleStandard", 1)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	check(inv.active and inv.size == Invasion.SIZE and last_message().begins_with("A goblin army is approaching from the"), "the Battle Standard summons the Goblin Army (%s)" % last_message())
	check(p.inventory.slots[p.selected] == null and not inv.start(), "it's used up, and there's only one army at a time")
	var edge0 := inv.army_x
	inv.update(1.0)
	check(absf(inv.army_x - edge0) > 39.0 and absf(inv.army_x - edge0) < 41.0, "it marches in a tile a tick (%.1f blocks in a second)" % absf(inv.army_x - edge0))
	for i in 20:
		inv.update(1.0)
	check(inv.arrived and last_message() == "A goblin army has arrived!", "it arrives at the spawn point")
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	await frames(5)
	check(inv.near(p.global_position) and Audio._current_track == "GoblinArmy" and game.hud._invasion.visible, "near it: its music and progress bar")
	# Its goblins spawn round you.
	for i in 12:
		game.spawner._timer = 0.0
		game.spawner._physics_process(0.1)
	var goblins := game.npcs().filter(func(n): return n.def.get("invasion", "") == "goblin")
	check(goblins.size() >= 6 and goblins.size() <= Spawner.INVASION_CAP, "its goblins come (%d: %s)" % [goblins.size(), goblins.map(func(n): return n.kind)])
	# Killing them counts down.
	var left := inv.size
	for g in goblins.slice(0, 3):
		g.hit(9999, 0.0, Vector3.ZERO, 0.0)
	await frames(2)
	# (Any other that's died meanwhile, in the lava pond or such, counts too.)
	var now := inv.size
	check(now <= left - 3 and now >= left - 6 and absf(game.hud._invasion_bar.value - inv.progress() * 100.0) < 0.01, "each kill brings it closer to defeat (%d left)" % inv.size)
	var saved := inv.save_state()
	inv.load_state({})
	inv.load_state(saved)
	check(inv.active and inv.size == now, "it's saved with the world, part beaten")
	inv.size = 1
	var last := game.spawn_npc("GoblinWarrior", p.global_position + Vector3(4, 0, 0))
	last.hit(9999, 0.0, Vector3.ZERO, 0.0)
	await frames(2)
	check(not inv.active and inv.downed and last_message() == "A goblin army has been defeated!", "the last kill beats it (%s)" % last_message())
	for n in game.npcs():
		if n.def.get("invasion", "") != "":
			n.queue_free()
	await frames(2)

	# A Goblin Sorcerer teleports near you, then casts Chaos Balls.
	var sorc := game.spawn_npc("GoblinSorcerer", p.global_position + Vector3(8, 0, 8))
	var at0 := sorc.global_position
	await frames(160)
	var moved := sorc.global_position.distance_to(at0) > 0.5
	# (Watched each frame: one cast close by can reach you and be gone.)
	var balls := []
	for i in 110:
		await frames(1)
		for e in game.entities.get_children():
			if e is Projectile and e.kind == "ChaosBall" and not e.friendly and not balls.has(e):
				balls.append(e)
	# (Anywhere within 13.3 blocks each way and 8 up or down: 21 at most.)
	check(moved and sorc.global_position.distance_to(p.global_position) < 21.5,
			"the Goblin Sorcerer teleports near you after 150 ticks (%.1f blocks off; life %d, cast timer %.0f)" % [sorc.global_position.distance_to(p.global_position), sorc.life, sorc._cast_t])
	check(balls.size() >= 1, "then casts a Chaos Ball at you (%d)" % balls.size())
	sorc.queue_free()
	for b in balls:
		if is_instance_valid(b):
			b.queue_free()

	# The Tinkerer, bound in the caverns: freed, he joins the town. (The test
	# town's own Tinkerer steps aside meanwhile.)
	var resident: NPC = game.town.residents.get("GoblinTinkerer")
	game.town.residents.erase("GoblinTinkerer")
	var bound := game.spawn_npc("BoundGoblin", p.global_position + Vector3(2, 0, 0))
	await frames(2)
	var tinkerer: NPC = game.town.free_goblin(bound)
	game.hud.open_chat(tinkerer, NPC.dialog(NPC.FREED_LINE))
	await frames(2)
	check(game.town.residents.has("GoblinTinkerer") and game.hud._chat_text.text.begins_with("Thank you for freeing me"), "freed, the Bound Goblin is the Goblin Tinkerer (%s)" % game.hud._chat_text.text.left(40))
	check(Data.npcs.GoblinTinkerer.town.shop == ["RocketBoots", "Ruler", "TinkerersWorkshop", "GrapplingHook", "Toolbelt", "SpikyBall"], "his shop: Rocket Boots, Ruler, Tinkerer's Workshop, Grappling Hook, Toolbelt, Spiky Ball")
	game.hud.close_chat()
	# His workshop is a crafting station.
	var bench := Vector3i(p.global_position.floor()) + Vector3i(2, 0, 0)
	w.set_block(bench, Data.block_id("tinkerers_workshop"))
	check(game.nearby_stations().has("tinkerers_workshop"), "the Tinkerer's Workshop is a crafting station")
	w.set_block(bench, 0)

	# Rocket Boots: let go of jump in the air and hold it again to fly.
	p.global_position = Vector3(c.x + 0.5, TestWorld.GROUND + 1, c.z + 30.5)
	p.velocity = Vector3.ZERO
	await frames(10)
	var rise := func() -> float:
		var start := p.global_position.y
		var best := start
		Input.action_press("jump")
		await frames(15)
		Input.action_release("jump")
		await frames(3)
		Input.action_press("jump")
		for i in 90:
			await frames(1)
			best = maxf(best, p.global_position.y)
		Input.action_release("jump")
		for i in 240:
			await frames(1)
			if p.on_floor:
				break
		await frames(2)
		return best - start
	var plain: float = await rise.call()
	p.accessories.slots[0] = Inventory.stack("RocketBoots", 1)
	var rocketed: float = await rise.call()
	check(rocketed > plain + 1.0 and p._rocket_time == Player.ROCKET_TIME, "Rocket Boots fly you up (%.1f blocks, %.1f without), and refill on the ground" % [rocketed, plain])
	# The combinations' effects.
	p.accessories.slots[0] = Inventory.stack("MagicCuffs", 1)
	p.god_mode = false
	p.mana = 0
	p._immune = 0.0
	p.hurt(30, Vector3.ZERO)
	check(p.mana > 0 and p.mana_cap() == p.mana_max + 40, "Magic Cuffs: +40 mana, and taking damage gives mana back (%d)" % p.mana)
	p.god_mode = true
	p.life = p.life_max
	p.accessories.slots[0] = Inventory.stack("Toolbelt", 1)
	p.inventory.slots[p.selected] = Inventory.stack("DirtBlock", 10)
	check(is_equal_approx(p.reach(), Player.REACH + 2.0 / 3.0), "the Toolbelt: a tile more reach placing blocks")
	p.accessories.slots[0] = Inventory.stack("GPS", 1)
	await frames(2)
	check(game.hud._clock.text != "" and game.hud.info_text().split("\n").size() == 2, "the GPS: the time, the depth and the position")
	p.accessories.slots[0] = Inventory.stack("ManaRegenerationBand", 1)
	var mrb := Data.item("ManaRegenerationBand")
	check(p.stat("mana_regen_bonus") == 60.0 and mrb.regen == 2 and mrb.mana_bonus == 40 and Data.item("BandofStarpower").mana_bonus == 40, "the Mana Regeneration Band (+40 mana, regeneration); the Band of Starpower is +40 now, as in 1.4.5")
	p.accessories.slots[0] = null
	# The Spiky Ball: thrown, it rolls to a stop and hurts what touches it.
	var dummy := game.spawn_npc("GoblinWarrior", p.global_position + Vector3(0, 0, -3))
	dummy.untouchable = false
	var life0 := dummy.life
	var ball := game.spawn_projectile("SpikyBall", dummy.center(), Vector3.ZERO, 16, 1.0, 20.0, 18.0, 0.45, true, 0.0)
	ball.explosive = Data.item("SpikyBall").explosive
	ball.life = 80.0
	ball.penetrate = 7
	await frames(5)
	check(dummy.life < life0 and is_instance_valid(ball) and ball.penetrate == 6, "a Spiky Ball hurts an enemy that touches it, and stays (%d left)" % ball.penetrate)
	dummy.queue_free()
	if is_instance_valid(ball):
		ball.queue_free()
	# The Harpoon: out on its chain, back when you let go.
	p.inventory.slots[p.selected] = Inventory.stack("Harpoon", 1)
	p.look_at_yaw_pitch(0.0, 0.0)
	p._use_timer = 0.0
	p._use_released = true
	p.hold_use = true
	p.use_item()
	await frames(8)
	var hp := get_tree().get_nodes_in_group("harpoons")
	check(hp.size() == 1 and not hp[0].returning and hp[0].global_position.distance_to(p.center()) > 3.0, "the Harpoon flies out on its chain")
	p.hold_use = false
	await frames(60)
	check(get_tree().get_nodes_in_group("harpoons").filter(func(h): return is_instance_valid(h) and not h.is_queued_for_deletion()).is_empty(), "let go, it's reeled back in")
	p.inventory.slots[p.selected] = null
	p.select(held)
	p.god_mode = god
	inv.downed = false
	for e in game.entities.get_children():
		if e is ItemDrop:
			e.queue_free()
	p.inventory.slots = kept_slots
	p.inventory.changed.emit()
	tinkerer.queue_free()
	if resident:
		game.town.residents.GoblinTinkerer = resident
	else:
		game.town.residents.erase("GoblinTinkerer")
		game.town.arrived.erase("GoblinTinkerer")
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	await frames(5)


## The Queen Bee (Terraria's aiStyle 43): what brings her, her charges, bees
## and stingers (and their poison), her fury out of the Jungle, her music,
## leaving when you die, and what she drops.
func _queen_bee_checks(c: Vector3i) -> void:
	var p := game.player
	var god := p.god_mode
	var kept_slots := p.inventory.slots.duplicate(true)
	var held := p.selected
	p.god_mode = true
	var qd: Dictionary = Data.npcs.QueenBee
	check(int(qd.life) == 3400 and int(qd.damage) == 30 and int(qd.defense) == 8 and qd.boss and Data.npcs.Bee.life == 20 and Data.npcs.BeeSmall.life == 10,
			"the Queen Bee: Terraria's 3400 life, 30 damage, 8 defense; her bees 20 and 10 life")
	var recipe: Array = Data.recipes.filter(func(r): return r.result == "Abeemination")
	check(recipe.size() == 1 and recipe[0].ingredients == {"HoneyBlock": 5, "Stinger": 1, "Hive": 5, "BottledHoney": 1},
			"the Abeemination: 5 Honey Blocks, a Stinger, 5 Hive and a Bottled Honey (%s)" % [recipe[0].ingredients if recipe.size() > 0 else null])
	check(Data.block_id("hive") in Data.biome_blocks.jungle, "hive blocks count as the Jungle (Terraria's JungleTileCount)")
	var clear := func() -> void:
		for n in game.npcs():
			if n.boss or n.def.ai == "bee":
				n.queue_free()
		for e in game.entities.get_children():
			if e is Projectile or e is Gore or e is ItemDrop:
				e.queue_free()
		await frames(2)
	var use := func() -> void:
		p._use_timer = 0.0
		p._use_released = true
		p.use_item()
		await frames(2)
	var plaza := Vector3(c) + Vector3(0.5, 0, 12.5)
	p.global_position = plaza
	p.velocity = Vector3.ZERO
	await frames(20)
	p.inventory.slots[9] = Inventory.stack("Abeemination", 2)
	p.select(9)
	await use.call()
	check(not game.boss_alive() and p.inventory.slots[9].count == 2, "out of the Jungle the Abeemination does nothing")
	var spot: Array = TestWorld.FISHING_SPOTS.filter(func(x): return x[0] == "Jungle")[0]
	var jungle := Vector3(c.x + spot[1].x + 0.5, TestWorld.GROUND + 1, c.z + spot[1].z + spot[2].y + 2.5)
	p.global_position = jungle
	await frames(30)
	game.biome = game.detect_biome(jungle)
	await use.call()
	var qb: NPC = game.boss()
	check(game.biome == "jungle" and qb != null and qb.kind == "QueenBee" and p.inventory.slots[9].count == 1 and last_message() == "Queen Bee has awoken!",
			"in the Jungle it brings the Queen Bee (%s, %s)" % [game.biome, last_message()])
	await frames(5)
	check(Audio._current_track == "QueenBee", "her own music plays (%s)" % Audio._current_track)
	# Seen through the blocks in front of her (Terraria draws NPCs in front of
	# the tiles), with her bees and stingers; out of view, her head icon at
	# the edge of the screen points to her.
	var bee_look := NPC.make_look("Bee", NPC.look("Bee"))
	check(qb != null and qb.sprite.get("material_overlay") != null or (qb.sprite is NPCModel and qb.sprite._mi.material_overlay != null),
			"she's seen through blocks")
	check(bee_look is NPCModel or bee_look.material_overlay != null, "and so are her bees")
	bee_look.free()
	if qb != null:
		qb.process_mode = Node.PROCESS_MODE_DISABLED
		qb.global_position = p.camera.global_position - p.forward() * 10.0
		await get_tree().process_frame
		await get_tree().process_frame
		var marks: Array = game.hud.boss_markers.marks
		check(marks.size() == 1 and qb.head_icon() == 14 and absf(marks[0][2] - PI / 2.0) < 0.3,
				"behind you, her head icon (NPC_Head_Boss_14) points to her from the bottom of the screen (%s)" % [marks])
		qb.global_position = p.camera.global_position + p.forward() * 10.0
		await get_tree().process_frame
		await get_tree().process_frame
		check(game.hud.boss_markers.marks.is_empty(), "in view, no marker")
		qb.process_mode = Node.PROCESS_MODE_INHERIT
	# Her dash: at the Jungle's surface (fury 1: out of the underground) 19
	# px a tick; in the plaza (fury 2: out of the Jungle too) 26.
	var dash_speed := func(at: Vector3) -> float:
		qb._qb = [0.0, 0.0, 0.0]
		qb.global_position = at + Vector3(-14, 0.0, -4)
		qb.velocity = Vector3.ZERO
		for i in 240:
			await frames(1)
			if qb._qb[1] == 1.0:
				break
		return qb.velocity.length() / NPC.PX_TICK
	if qb != null:
		var jungle_dash: float = await dash_speed.call(jungle)
		p.global_position = plaza
		await frames(20)
		game.biome = game.detect_biome(plaza)
		var plaza_dash: float = await dash_speed.call(plaza)
		check(absf(jungle_dash - 19.0) < 0.1 and absf(plaza_dash - 26.0) < 0.1 and qb._qb_dash and qb._qb_frame < 4,
				"she lines up level with you and dashes: 19 px a tick at the Jungle's surface, 26 out of it (%.1f, %.1f), in her charging frames" % [jungle_dash, plaza_dash])
		var passed := 0.0
		for i in 240:
			await frames(1)
			if qb._qb[2] == 1.0:
				var off: Vector3 = qb.center() - p.center()
				passed = Vector2(off.x, off.z).length() * NPC.QB_PX
				break
		check(passed > 400.0 and passed < 700.0, "and goes on till she's 400 px past you (fury 2: 600 less 100 a fury) (%.0f)" % passed)
		# Bees: a bee (or small bee) every 4 ticks at fury 2 (40 less 18 a fury), 6 of them.
		await clear.call()
		qb = null
		game.summon_boss("QueenBee")
		qb = game.boss()
		qb._qb = [1.0, 0.0, 0.0]
		qb.global_position = p.global_position + Vector3(0, 4, -4)
		qb.velocity = Vector3.ZERO
		for i in 120:
			await frames(1)
			if qb._qb[0] != 1.0:
				break
		var bees := game.npcs().filter(func(n): return n.def.ai == "bee")
		check(bees.size() == 6 and qb._qb[0] != 1.0, "she sends out 6 bees, then moves on (%d)" % bees.size())
		for n in game.npcs():
			if n.def.ai == "bee":
				n.queue_free()
		# (Launched at you at 5 px a tick, as she sends them: its pull starts
		# out backwards, (age - 60) / 60, slowing it, then grows.)
		var bee: NPC = game.spawn_npc("Bee", p.center() + Vector3(-4, 6, 6))
		bee.velocity = (p.center() - bee.center()).normalized() * 5.0 * NPC.PX_TICK
		await frames(240)
		check(is_instance_valid(bee) and bee.center().distance_to(p.center()) < 4.0, "a bee homes in on you (%.1f blocks off)" % (bee.center().distance_to(p.center()) if is_instance_valid(bee) else -1.0))
		# Stingers from above: one every 30 ticks at fury 2, 22 px a tick, 22 damage.
		await clear.call()
		game.summon_boss("QueenBee")
		qb = game.boss()
		qb._qb = [3.0, 0.0, 0.0]
		qb.global_position = p.global_position + Vector3(0, 11, -3)
		qb.velocity = Vector3.ZERO
		var stinger: Projectile = null
		for i in 60:
			await frames(1)
			for e in game.entities.get_children():
				if e is Projectile and e.kind == "QueenBeeStinger":
					stinger = e
			if stinger != null:
				break
		check(stinger != null and not stinger.friendly and stinger.damage == 22 and absf(stinger.velocity.length() / NPC.PX_TICK - 22.0) < 0.1 and stinger._axial
				and stinger.sprite.material_overlay != null,
				"from over your head she shoots stingers at you (22 damage, 22 px a tick), pointing along their flight, seen through blocks")
		# Poisoned: 2 life a second, no healing.
		await clear.call()
		p.god_mode = false
		var life0 := p.life
		p.poison(10.0)
		await frames(61)
		var lost := life0 - p.life
		check(p.buffs().any(func(b): return b[1] == "Poisoned") and lost >= 1 and lost <= 3 and "QueenBeeStinger" in Projectile.POISONS,
				"her stingers poison you: 2 life a second (%d lost)" % lost)
		p.poisoned = 0.0
		p.life = life0
		p.god_mode = true
		# You die: she flies off and is gone.
		game.summon_boss("QueenBee")
		qb = game.boss()
		p.alive = false
		await frames(200)
		check(not is_instance_valid(qb) or qb.is_queued_for_deletion(), "with you dead she leaves")
		p.alive = true
		await clear.call()
		# Killed: her gores, Bottled Honey, Bee Wax and money.
		game.summon_boss("QueenBee")
		qb = game.boss()
		qb.global_position = p.global_position + Vector3(0, 2, -5)
		await frames(2)
		qb.hit(99999, 0.0, Vector3.FORWARD, 0.0)
		await frames(2)
		var drops := {}
		for e in game.entities.get_children():
			if e is ItemDrop:
				drops[e.item] = int(drops.get(e.item, 0)) + e.count
		var gores := game.entities.get_children().filter(func(e): return e is Gore).size()
		check(gores == 6 and drops.get("BottledHoney", 0) >= 5 and drops.get("BeeWax", 0) >= 17 and game.defeated_bosses.has("QueenBee")
				and last_message() == "Queen Bee has been defeated!", "killed she breaks in 6 and drops Bottled Honey, Bee Wax and more (%s)" % [drops])
		game.defeated_bosses.erase("QueenBee")
	await clear.call()
	p.god_mode = god
	p.inventory.slots = kept_slots
	p.inventory.changed.emit()
	p.select(held)
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	game.biome = ""
	await frames(5)


## The Brain of Cthulhu: the Bloody Spine and the third Crimson Heart, its
## Creepers (its shield, the boss bar), its teleports, shedding its outer
## brain, its second form, leaving out of the Crimson and far off, its loot.
func _brain_checks(c: Vector3i) -> void:
	var p := game.player
	var god := p.god_mode
	var kept_slots := p.inventory.slots.duplicate(true)
	var held := p.selected
	p.god_mode = true
	var bd: Dictionary = Data.npcs.BrainofCthulhu
	var cd: Dictionary = Data.npcs.Creeper
	check(int(bd.life) == 1250 and int(bd.damage) == 30 and int(bd.defense) == 14 and bd.boss and int(cd.life) == 100 and int(cd.damage) == 20
			and int(cd.defense) == 10, "the Brain of Cthulhu: Terraria's 1250 life, 30 damage, 14 defense; its Creepers 100 life, 20 damage, 10 defense")
	var recipe: Array = Data.recipes.filter(func(r): return r.result == "BloodySpine")
	check(recipe.size() == 1 and recipe[0].ingredients == {"ViciousPowder": 30, "Vertebrae": 15},
			"the Bloody Spine: 30 Vicious Powder and 15 Vertebrae (%s)" % [recipe[0].ingredients if recipe.size() > 0 else null])
	var clear := func() -> void:
		for n in game.npcs():
			if n.boss or n.kind == "Creeper":
				n.queue_free()
		for e in game.entities.get_children():
			if e is Projectile or e is Gore or e is ItemDrop:
				e.queue_free()
		await frames(2)
	var creepers := func() -> Array:
		return game.npcs().filter(func(n): return n.kind == "Creeper" and not n.is_queued_for_deletion())
	var plaza := Vector3(c) + Vector3(0.5, 0, 12.5)
	p.global_position = plaza
	p.velocity = Vector3.ZERO
	await frames(20)
	game.biome = game.detect_biome(plaza)
	p.inventory.slots[9] = Inventory.stack("BloodySpine", 2)
	p.select(9)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	await frames(2)
	check(not game.boss_alive() and p.inventory.slots[9].count == 2, "out of the Crimson the Bloody Spine does nothing")
	var spot: Array = TestWorld.FISHING_SPOTS.filter(func(x): return x[0] == "Crimson")[0]
	var crimson := Vector3(c.x + spot[1].x + 0.5, TestWorld.GROUND + 1, c.z + spot[1].z + spot[2].y + 2.5)
	p.global_position = crimson
	await frames(30)
	game.biome = game.detect_biome(crimson)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	await frames(2)
	var b: NPC = game.boss()
	check(game.biome == "crimson" and b != null and b.kind == "BrainofCthulhu" and p.inventory.slots[9].count == 1
			and last_message() == "Brain of Cthulhu has awoken!", "in the Crimson it brings the Brain of Cthulhu (%s, %s)" % [game.biome, last_message()])
	await frames(5)
	check(Audio._current_track == "Boss3", "with Terraria's Boss 3 music (%s)" % Audio._current_track)
	if b == null:
		await clear.call()
		return
	var bar: Dictionary = game.boss_status()
	check(creepers.call().size() == 20 and bar.life == 3250 and bar.max == 3250,
			"it brings 20 Creepers, and the boss bar counts their life with its own (%d, %s)" % [creepers.call().size(), bar])
	check(b.head_icon() == 23 and (b.sprite.get("material_overlay") != null or (b.sprite is NPCModel and b.sprite._mi.material_overlay != null)),
			"its head icon is NPC_Head_Boss_23, and it's seen through blocks")
	var life0 := b.life
	b.hit(500, 0.0, Vector3.FORWARD, 0.0)
	check(b.dont_take_damage and b.life == life0 and b._br_frame < 4, "while it has Creepers it can't be hurt, in its outer brain")
	# Its first form drifts at you at 1 px a tick; now and then it fades out
	# (5 a tick), comes back 12-40 tiles off you on each axis and fades in.
	b.global_position = p.global_position + Vector3(0, 4, 12)
	await frames(30)
	var drift: float = b.velocity.length() / NPC.PX_TICK
	b._br_count = 9999.0
	await frames(2)
	var fading: bool = b._br == 1.0 and b._br_alpha > 0.0 and b._br_alpha <= 10.0
	var from := b.center()
	for i in 80:
		await frames(1)
		if b._br == 2.0:
			break
	var off: Vector3 = (b.center() - p.center()) * NPC.BR_PX
	var tiles := Vector2(Vector2(off.x, off.z).length(), absf(off.y)) / 16.0
	check(absf(drift - 1.0) < 0.05 and fading and b._br == 2.0 and b.center().distance_to(from) > 3.0 and tiles.x > 11.0 and tiles.x < 41.0
			and tiles.y > 11.0 and tiles.y < 41.0 and not game.world.is_solid(Vector3i(b.center().floor())),
			"it drifts at you (%.2f px a tick), fades out and comes back 12-40 tiles off you across and up or down (%.1f, %.1f)" % [drift, tiles.x, tiles.y])
	# Creepers circle it, and now and then charge at you (8 px a tick) till hit.
	var cr: NPC = creepers.call()[0]
	b.global_position = p.global_position + Vector3(0, 4, 12)
	b._br = 0.0
	b._br_alpha = 0.0
	await frames(120)
	var near: int = creepers.call().filter(func(n): return n.center().distance_to(b.center()) < 300.0 / NPC.BR_PX).size()
	cr.ai_state = 1
	cr.velocity = (p.center() - cr.center()).normalized() * 8.0 * NPC.PX_TICK
	await frames(3)
	var charge: float = cr.velocity.length() / NPC.PX_TICK
	var charging: bool = cr.ai_state == 1
	cr.hit(1, 0.0, Vector3.FORWARD, 0.0)
	await frames(2)
	check(near >= 10 and charging and absf(charge - 8.0) < 0.1 and cr.ai_state == 0,
			"its Creepers circle it (%d near), charge at you at 8 px a tick and go back when hit" % near)
	# Its Creepers killed: tissue and ore, its outer brain bursts off, and
	# it comes at you; now it can be hurt.
	await frames(2)
	for e in game.entities.get_children():
		if e is ItemDrop:
			e.queue_free()
	b.global_position = p.global_position + Vector3(0, 4, 14)
	for n in creepers.call():
		n.hit(99999, 0.0, Vector3.FORWARD, 0.0)
	await frames(2)
	var drops := {}
	for e in game.entities.get_children():
		if e is ItemDrop:
			drops[e.item] = int(drops.get(e.item, 0)) + e.count
	check(drops.get("TissueSample", 0) >= 10 and drops.get("CrimtaneOre", 0) >= 25 and game.boss_status().life == 1250 and game.boss_status().max == 3250,
			"killed, Creepers drop Tissue Samples and Crimtane Ore (2 in 3 each), and the bar falls (%s)" % [drops])
	b._br = 0.0
	b._br_alpha = 0.0
	await frames(3)
	var gores: Array = game.entities.get_children().filter(func(e): return e is Gore and e.gore_id >= 392 and e.gore_id <= 395)
	check(b._br_shed and b._br < 0.0 and not b.dont_take_damage and gores.size() == 4,
			"with its Creepers gone it sheds its outer brain (Terraria's gores 392-395) and can be hurt")
	await frames(10)
	check(b._br_frame >= 4 and b._br_frame <= 7, "in its second form's frames (%d)" % b._br_frame)
	life0 = b.life
	b.hit(100, 0.0, Vector3.FORWARD, 0.0)
	check(b.life < life0, "now it's hurt (%d -> %d)" % [life0, b.life])
	# Its second form: easing toward 8 px a tick at you; fading out and in
	# fast (25 a tick) to 10-12 tiles off you.
	b._br = -1.0
	b._br_count = -9999.0
	b.global_position = p.global_position + Vector3(0, 40, -90)
	b.velocity = Vector3.ZERO
	await frames(150)
	var dash: float = b.velocity.length() / NPC.PX_TICK
	b._br_count = 9999.0
	await frames(2)
	var fast: bool = b._br == -2.0 and b._br_alpha >= 25.0 and b._br_alpha <= 50.0
	for i in 30:
		await frames(1)
		if b._br == -3.0:
			break
	off = (b.center() - p.center()) * NPC.BR_PX
	tiles = Vector2(Vector2(off.x, off.z).length(), absf(off.y)) / 16.0
	check(dash > 7.0 and dash <= 8.0 and fast and b._br == -3.0 and tiles.x > 9.5 and tiles.x < 12.5 and tiles.y > 9.5 and tiles.y < 12.5,
			"then it comes at you (%.2f px a tick, toward 8) and blinks to 10-12 tiles off you, fading 25 a tick (%.1f, %.1f)" % [dash, tiles.x, tiles.y])
	# Out of the Crimson it stops and sinks away, faster after a second.
	b.process_mode = Node.PROCESS_MODE_DISABLED
	b.velocity = Vector3.ZERO
	for i in 60:
		b._brain_tick(game, p, false)
	var sink0: float = b.velocity.y / NPC.PX_TICK
	for i in 30:
		b._brain_tick(game, p, false)
	var sink1: float = b.velocity.y / NPC.PX_TICK
	check(b._br == 2.0 and sink0 >= -1.01 and sink1 < -5.0 and b._br_away == 90.0,
			"out of the Crimson it stops and, after a second, sinks away ever faster (%.1f, %.1f px a tick)" % [sink0, sink1])
	b._br_away = 0.0
	b.process_mode = Node.PROCESS_MODE_INHERIT
	# Far off (6000 px across plus up and down) it's gone.
	b.global_position = p.global_position + Vector3(6100.0 / NPC.BR_PX, 0, 0)
	await frames(2)
	check(not is_instance_valid(b) or b.is_queued_for_deletion(), "6000 px off it's gone (%s)" % last_message())
	await clear.call()
	# The third Crimson Heart smashed wakes it.
	var orbs := game.orbs_broken
	game.orbs_broken = 2
	game._orb_smashed(p.global_position + Vector3(0, 1, -3), Data.block(Data.block_id("crimson_heart")))
	await frames(2)
	b = game.boss()
	check(b != null and b.kind == "BrainofCthulhu", "the third Crimson Heart smashed wakes it")
	game.orbs_broken = orbs
	if b != null:
		# Killed: its gores, Crimtane Ore, potions and money.
		for e in game.entities.get_children():
			if e is ItemDrop:
				e.queue_free()
		for n in creepers.call():
			n.queue_free()
		await frames(2)
		b._br = -1.0
		b.dont_take_damage = false
		b.global_position = p.global_position + Vector3(0, 2, -8)
		await frames(1)
		b.hit(99999, 0.0, Vector3.FORWARD, 0.0)
		await frames(2)
		drops = {}
		for e in game.entities.get_children():
			if e is ItemDrop:
				drops[e.item] = int(drops.get(e.item, 0)) + e.count
		var pieces := game.entities.get_children().filter(func(e): return e is Gore and e.gore_id >= 396 and e.gore_id <= 401).size()
		check(pieces == 6 and drops.get("CrimtaneOre", 0) >= 40 and drops.get("LesserHealingPotion", 0) >= 5 and game.defeated_bosses.has("BrainofCthulhu")
				and last_message() == "Brain of Cthulhu has been defeated!", "killed it breaks in 6 and drops 40-90 Crimtane Ore, potions and more (%s)" % [drops])
		game.defeated_bosses.erase("BrainofCthulhu")
	await clear.call()
	# What Crimtane and Tissue Samples make: Terraria's recipes and stats; the
	# Crimson set (3% damage a piece; its bonus, faster natural healing).
	var has_recipe := func(result: String, want: Dictionary) -> bool:
		return Data.recipes.any(func(r): return r.result == result and r.ingredients == want and r.station == "iron_anvil")
	check(has_recipe.call("DeathbringerPickaxe", {"CrimtaneBar": 12, "TissueSample": 6}) and has_recipe.call("BloodButcherer", {"CrimtaneBar": 10})
			and has_recipe.call("TendonBow", {"CrimtaneBar": 8}) and has_recipe.call("FleshGrinder", {"CrimtaneBar": 10, "TissueSample": 5})
			and has_recipe.call("CrimsonHelmet", {"CrimtaneBar": 15, "TissueSample": 10}) and has_recipe.call("CrimsonScalemail", {"CrimtaneBar": 25, "TissueSample": 20})
			and has_recipe.call("CrimsonGreaves", {"CrimtaneBar": 20, "TissueSample": 15}),
			"the Deathbringer Pickaxe, Blood Butcherer, Tendon Bow, Flesh Grinder and Crimson armor have Terraria's recipes")
	check(int(Data.item("DeathbringerPickaxe").pick) == 70 and int(Data.item("BloodButcherer").damage) == 22 and int(Data.item("TendonBow").damage) == 19
			and int(Data.item("FleshGrinder").hammer) == 55, "the Deathbringer Pickaxe mines at 70% (Dungeon bricks need 65), the Blood Butcherer hits for 22, the Tendon Bow 19")
	var kept_armor := p.armor.slots.duplicate(true)
	var kept_acc := p.accessories.slots.duplicate(true)
	for i in p.accessories.slots.size():
		p.accessories.slots[i] = null
	p.armor.slots = [Inventory.stack("CrimsonHelmet", 1), Inventory.stack("CrimsonScalemail", 1), Inventory.stack("CrimsonGreaves", 1)]
	var worn: Dictionary = p.armor_set()
	check(p.defense() == 19 and worn.get("text", "") == "Crimson" and Assets.set_bonus_text("Crimson") == "Greatly increased life regen"
			and p.weapon_damage(Data.item("BloodButcherer")) == 24, "Crimson armor: 19 defense, 9% more damage, its set bonus \"Greatly increased life regen\"")
	var healed := func(seconds: int) -> int:
		p.life = 100
		p._regen_acc = 0.0
		p._since_hurt = 30.0
		for i in seconds:
			p._regen(1.0)
		return p.life - 100
	var with_set: int = healed.call(4)
	p._since_hurt = 0.0
	p._regen(4.5)
	var ramp_set: float = p._since_hurt
	p.armor.slots = [null, null, null]
	var without: int = healed.call(4)
	p._since_hurt = 0.0
	p._regen(4.5)
	var ramp: float = p._since_hurt
	check(with_set == 9 and without == 6 and absf(ramp_set - 9.0) < 0.01 and absf(ramp - 4.5) < 0.01,
			"its set bonus: natural healing builds twice as fast and heals half again as much (%d vs %d life in 4 s)" % [with_set, without])
	p.armor.slots = kept_armor
	p.accessories.slots = kept_acc
	p.life = p.life_max
	p.god_mode = god
	p.inventory.slots = kept_slots
	p.inventory.changed.emit()
	p.select(held)
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	game.biome = ""
	await frames(5)


## Bee hives: the test world's (its larva, hive blocks and honey), the
## honey recipes, honey (its slow fall, the Honey buff and its healing, the
## bucket, Bottled Honey), honey meeting water and lava, the sticky honey
## block, the Extractinator's Honey Block and breaking the larva.
func _hive_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var hud := game.hud
	var kept_slots := p.inventory.slots.duplicate(true)
	var held := p.selected
	var id := func(n: String) -> int: return Data.block_id(n)
	var larva: Vector3i = game.test_world.hive_larva
	var floor_ok := true
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if w.get_block(larva + Vector3i(dx, -1, dz)) != id.call("hive"):
				floor_ok = false
	check(w.get_block(larva) == id.call("larva") and floor_ok, "the test world's hive: its larva on a 3 x 3 hive floor (%s)" % larva)
	var near := w.count_blocks(larva, 24)
	var honey_cells := 0
	for x in range(larva.x - 24, larva.x + 25):
		for y in range(maxi(1, larva.y - 24), larva.y + 25):
			for z in range(larva.z - 24, larva.z + 25):
				if w.get_liquid(Vector3i(x, y, z)).x == Player.LIQ_HONEY:
					honey_cells += 1
	check(near[id.call("hive")] > 1000 and honey_cells > 100, "hive blocks round it (%d) and honey (%d cells)" % [near[id.call("hive")], honey_cells])
	var recipe := func(result: String) -> Dictionary:
		for r in Data.recipes:
			if r.result == result:
				return r
		return {}
	check(recipe.call("BottledHoney").get("station") == "honey" and recipe.call("BottledHoney").ingredients == {"Bottle": 1}
			and recipe.call("CrispyHoneyBlock").get("station") == "furnace" and recipe.call("HoneyBucket").get("station") == "campfire"
			and recipe.call("HiveWall").get("count") == 4 and recipe.call("HiveWall").ingredients == {"Hive": 1},
			"Terraria's honey recipes: Bottled Honey by honey, Crispy Honey at a Furnace, the Honey Bucket at a Campfire, 4 Hive Walls a Hive")

	# A tank of honey, glass round it, up in the air.
	var tank := c + Vector3i(-40, 30, -40)
	var glass: int = id.call("glass")
	for x in range(-2, 3):
		for z in range(-2, 3):
			w.set_block(tank + Vector3i(x, -1, z), glass)
			for y in range(0, 9):
				if absi(x) == 2 or absi(z) == 2:
					w.set_block(tank + Vector3i(x, y, z), glass)
	for x in range(-1, 2):
		for z in range(-1, 2):
			for y in range(0, 7):
				w.set_liquid(tank + Vector3i(x, y, z), Player.LIQ_HONEY, 63)
	p.honey_time = 0.0
	p.global_position = Vector3(tank) + Vector3(0.5, 8.5, 0.5)
	p.velocity = Vector3(0, -20.0, 0)
	await frames(40)
	check(p.in_liquid == Player.LIQ_HONEY and p.velocity.y >= -Player.HONEY_MAX_FALL - 0.01, "in honey you sink slowly (%.2f, at most %.1f)" % [p.velocity.y, Player.HONEY_MAX_FALL])
	check(is_equal_approx(p.honey_time, Player.HONEY_TIME) and p.buffs().any(func(b): return b[0] == 48 and b[1] == "Honey"), "and you're Honey for 30 s (Terraria's buff 48)")
	await frames(20)
	var tint: Color = hud._liquid_tint.color
	check(p.head_liquid == Player.LIQ_HONEY and tint.r > 0.9 and tint.g > 0.6 and tint.b < 0.2 and tint.a > 0.4, "under honey the screen goes yellow (%s)" % tint)
	# Its healing: a life a second more, and natural healing three times as fast.
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(5)
	var heal_over := func(honey: bool) -> int:
		p.honey_time = Player.HONEY_TIME if honey else 0.0
		p.life = p.life_max - 50
		p._since_hurt = 0.0
		p._regen_acc = 0.0
		await frames(120)
		return p.life - (p.life_max - 50)
	var plain: int = await heal_over.call(false)
	var honeyed: int = await heal_over.call(true)
	check(plain == 0 and honeyed >= 2 and honeyed <= 3, "Honey heals a life a second where you'd heal none yet (%d vs %d in 2 s)" % [honeyed, plain])
	p.honey_time = 0.0
	p.life = p.life_max

	# Buckets: scooped, honey fills a Honey Bucket; poured, it's honey.
	p.global_position = Vector3(tank) + Vector3(0.5, 7.2, 0.5)
	p.velocity = Vector3.ZERO
	p.look_at_yaw_pitch(0.0, -PI / 2.0 + 0.01)
	p.inventory.slots[9] = Inventory.stack("EmptyBucket", 1)
	p.select(9)
	await frames(2)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	check(p.inventory.slots[9] != null and p.inventory.slots[9].item == "HoneyBucket", "an empty bucket scoops up a Honey Bucket")
	# (Poured from low in the tank, the glass floor in reach.)
	p.global_position = Vector3(tank) + Vector3(0.5, 2.0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(2)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	check(p.inventory.slots[9] != null and p.inventory.slots[9].item == "EmptyBucket", "and pours it out again")
	# Bottled Honey: a Bottle by honey (the honey counts as a crafting station).
	hud._open_inventory()
	check(hud._stations.has("honey"), "by honey, honey counts for crafting")
	p.inventory.add("Bottle", 1)
	hud._cursor_stack = null
	hud.craft(recipe.call("BottledHoney"))
	check(hud._cursor_stack != null and hud._cursor_stack.item == "BottledHoney", "a Bottle by honey makes Bottled Honey")
	hud._cursor_stack = null
	hud.close_inventory()
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	await frames(5)
	p.inventory.slots[9] = Inventory.stack("BottledHoney", 1)
	p.life = p.life_max - 100
	p.potion_sickness = 0.0
	p.honey_time = 0.0
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	check(p.life == p.life_max - 20 and is_equal_approx(p.honey_time, 15.0) and p.potion_sickness > 0.0, "Bottled Honey heals 80 and makes you Honey for 15 s")
	p.life = p.life_max
	p.potion_sickness = 0.0

	# Honey meeting water makes a honey block (where the honey was); meeting
	# lava, crispy honey (where the lava was).
	# (Lava first: water would meet the lava and make obsidian.)
	w.set_liquid(tank + Vector3i(1, 7, 1), 2, 63)
	await frames(30)
	var crispy: String = Data.block(w.get_block(tank + Vector3i(1, 7, 1))).get("name", "")
	w.set_liquid(tank + Vector3i(-1, 7, -1), 1, 63)
	await frames(30)
	var block: String = Data.block(w.get_block(tank + Vector3i(-1, 6, -1))).get("name", "")
	check(crispy == "crispy_honey_block" and block == "honey_block", "honey and lava make crispy honey (where the lava was), honey and water a honey block (where the honey was): %s, %s" % [crispy, block])

	# A honey block's side: you stick to it, sliding slowly down.
	var pillar := c + Vector3i(-50, 30, -40)
	for y in range(0, 8):
		w.set_block(pillar + Vector3i(0, y, 0), id.call("honey_block"))
	p.global_position = Vector3(pillar) + Vector3(1.0 + p.half.x + 0.01, 6.0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(30)
	check(p.honey_stuck and p.velocity.y >= -Player.HONEY_STICK_FALL - 0.01 and p.global_position.y > pillar.y + 4.0,
			"against a honey block you stick, sliding slowly down (%.2f a second, %.1f fallen)" % [p.velocity.y, pillar.y + 6.0 - p.global_position.y])
	for y in range(0, 8):
		w.set_block(pillar + Vector3i(0, y, 0), 0)

	# The Extractinator: a Hive gives a Honey Block.
	var ex := c + Vector3i(-50, 0, -48)
	w.set_block(ex + Vector3i(0, 0, -2), id.call("extractinator"))
	p.global_position = Vector3(ex) + Vector3(0.5, 0, 0.5)
	p.look_at_yaw_pitch(0.0, -0.6)
	p.inventory.slots[9] = Inventory.stack("Hive", 3)
	p.select(9)
	await frames(3)
	for e in game.entities.get_children():
		if e is ItemDrop:
			e.queue_free()
	await frames(1)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	var out := game.entities.get_children().filter(func(e): return e is ItemDrop and not e.is_queued_for_deletion())
	check(out.size() == 1 and out[0].item == "HoneyBlock" and p.inventory.slots[9].count == 2, "a Hive in the Extractinator gives a Honey Block")
	w.set_block(ex + Vector3i(0, 0, -2), 0)

	# Breaking the larva: the Queen Bee comes for you.
	game.break_block(larva)
	check(w.get_block(larva) == 0 and game.boss() != null and game.boss().kind == "QueenBee" and last_message() == "Queen Bee has awoken!",
			"breaking the larva brings the Queen Bee (%s)" % last_message())
	for n in game.npcs():
		if n.boss:
			n.queue_free()

	for x in range(-2, 3):
		for z in range(-2, 3):
			for y in range(-1, 9):
				w.set_block(tank + Vector3i(x, y, z), 0)
				w.set_liquid(tank + Vector3i(x, y, z), 0, 0)
	for e in game.entities.get_children():
		if e is ItemDrop:
			e.queue_free()
	p.inventory.slots = kept_slots
	p.inventory.changed.emit()
	p.select(held)
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(5)


## Item prefixes (Terraria's modifiers): which items can have which, their
## names and stats rounded as Terraria rounds them, what they add to you, the
## tooltip lines, rolling on crafting, drops and in chests, keeping them
## through the inventory, drops and saves, and the Goblin Tinkerer's reforge.
func _fishing_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var hud := game.hud
	var kept_slots := p.inventory.slots.duplicate(true)
	var kept_acc := p.accessories.slots.duplicate(true)
	var held := p.selected
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var recipe := func(result: String) -> Dictionary:
		for r in Data.recipes:
			if r.result == result:
				return r
		return {}
	check(Fishing.rules().size() > 150 and Fishing.rules()[-1].items == ["Bass"], "Terraria's catch table is loaded (%d rules, Bass last)" % Fishing.rules().size())
	check(recipe.call("WoodFishingPole").get("station") == "work_bench" and recipe.call("WoodFishingPole").ingredients.values() == [8]
			and recipe.call("ReinforcedFishingPole").ingredients.has("IronBar|LeadBar") and recipe.call("FisherofSouls").ingredients == {"DemoniteBar": 8}
			and recipe.call("AnglerTackleBag").get("station") == "tinkerers_workshop",
			"fishing recipes are Terraria's (Wooden Fishing Pole: 8 wood at a work bench, ...)")

	# Fishing power: pole + bait + skill, times the hour and the moon.
	check(is_equal_approx(Fishing.power_multiplier(true, 3000.0, 0), Fishing.f32(Fishing.f32(1.3) * Fishing.f32(1.1)))
			and is_equal_approx(Fishing.power_multiplier(true, 27000.0, 4), Fishing.f32(Fishing.f32(0.8) * Fishing.f32(0.9)))
			and Fishing.power_multiplier(true, 10000.0, 2) == 1.0, "fishing power is up at dawn and full moon, down at noon and new moon")
	p.inventory.slots.fill(null)
	p.inventory.slots[0] = Inventory.stack("ReinforcedFishingPole", 1)
	p.inventory.slots[5] = Inventory.stack("MasterBait", 20)
	p.inventory.slots[6] = Inventory.stack("Worm", 5)
	p.accessories.slots.fill(null)
	p.accessories.slots[0] = Inventory.stack("AnglerEarring", 1)
	p.accessories.slots[1] = Inventory.stack("HighTestFishingLine", 1)
	p.select(0)
	var sky := game.sky
	var kept_sky := [sky.is_day, sky.time, sky.moon_phase]
	sky.is_day = true
	sky.time = 10000.0
	sky.moon_phase = 2
	var cond := Fishing.conditions(p, sky)
	check(cond.pole == "ReinforcedFishingPole" and cond.bait == "MasterBait" and cond.level == 15 + 50 + 10,
			"fishing power: Reinforced Fishing Pole 15 + Master Bait 50 + Angler Earring 10 = %d" % cond.level)
	check(Hud.item_tooltip(Data.item("ReinforcedFishingPole")).contains("15% fishing power")
			and Hud.item_tooltip(Data.item("MasterBait")).contains("50% bait power"), "tooltips show fishing and bait power")

	# The ponds: the fishing pond is big enough, the water pool isn't quite.
	var fa := Vector3i(c.x + TestWorld.FISHING.x, TestWorld.GROUND, c.z + TestWorld.FISHING.z)
	var mid := Vector3(fa.x + 10.5, TestWorld.GROUND + 0.9, fa.z + 5.5)
	var pond := Fishing.pond(w, mid)
	var pool := Fishing.pond(w, Vector3(c.x - 21.5, TestWorld.GROUND + 0.9, c.z - 3.5))
	check(pond.tiles == 360 and not pond.lava and not pond.honey, "the fishing pond: 20 x 8 cells across, 360 tiles of water (%d)" % pond.tiles)
	check(pool.tiles == int(66 * 2.25), "the water pool: 11 x 6 cells, %d tiles (less than 300: less power)" % pool.tiles)
	var r := Fishing.check(game, p, Vector3(c.x - 21.5, TestWorld.GROUND + 0.9, c.z - 3.5), rng)
	check(r.info == "%d (-51%%) Fishing Power" % r.level and r.level == int(75 * 148 / 300.0), "in the small pool: %s" % r.info)
	r = Fishing.check(game, p, mid, rng)
	check(r.info == "75 Fishing Power" and r.level == 75, "in the fishing pond: %s" % r.info)
	# A puddle: not enough water.
	var puddle := c + Vector3i(-40, 20, 40)
	for x in range(-1, 2):
		for z in range(-1, 2):
			w.set_block(puddle + Vector3i(x, -1, z), Data.block_id("glass"))
			w.set_liquid(puddle + Vector3i(x, 0, z), Player.LIQ_WATER, 63)
	r = Fishing.check(game, p, Vector3(puddle) + Vector3(0.5, 0.9, 0.5), rng)
	check(r.catch == "" and r.info == "Not Enough Water!", "a puddle: %s" % r.info)

	# What bites in the forest pond: mostly Bass, crates now and then. (The
	# Angler's fish aside: his quest is off for this.)
	game.biome = ""
	var kept_done := game.town.angler_done
	game.town.angler_done = true
	var counts := {}
	for i in 3000:
		r = Fishing.check(game, p, mid, rng)
		counts[r.catch] = int(counts.get(r.catch, 0)) + 1
	var crates := 0
	for k in counts:
		if k.ends_with("Crate"):
			crates += counts[k]
	var allowed := ["", "Bass", "WoodenCrate", "IronCrate", "GoldenCrate", "FrogLeg", "BalloonPufferfish", "ZephyrFish", "BombFish"]
	check(counts.keys().all(func(k): return k in allowed) and counts.get("Bass", 0) > 1000 and crates > 100 and crates < 500 and counts.get("", 0) > 300,
			"surface pond catches: %s" % [counts])
	# The jungle, the snow, the corruption: their own fish.
	for biome in [["jungle", ["NeonTetra", "DoubleCod"]], ["snow", ["AtlanticCod", "FrostMinnow"]], ["corruption", ["Ebonkoi"]], ["crimson", ["CrimsonTigerfish", "Hemopiranha"]]]:
		game.biome = biome[0]
		var seen := {}
		for i in 600:
			r = Fishing.check(game, p, mid, rng)
			seen[r.catch] = true
		check(biome[1].all(func(f): return seen.has(f)), "fishing in the %s: %s" % [biome[0], seen.keys()])
	game.biome = ""
	game.town.angler_done = kept_done
	# Rules straight from the table: the ocean, honey, lava (with lava gear), junk.
	var ctx := func(extra: Dictionary) -> Dictionary:
		var d := {"EarlyMode": true, "Height1": true, "HeightUnder2": true, "HeightAboveAnd1": true, "Height1And2": true, "DidNotUseCombatBook": true,
				"common": true, "uncommon": false, "rare": false, "veryrare": false, "legendary": false, "crate": false}
		d.merge(extra, true)
		return d
	var seen_in := func(extra: Dictionary) -> Dictionary:
		var seen := {}
		for i in 400:
			seen[Fishing.roll_catch(ctx.call(extra), rng)] = true
		return seen
	check(seen_in.call({"Ocean": true, "Beach": true}).has("Tuna") and seen_in.call({"Ocean": true, "Beach": true, "Crate": true, "rare": true}).has("OceanCrate"),
			"the ocean: Tuna, Ocean Crates...")
	check(seen_in.call({"InHoney": true, "uncommon": true}).keys().all(func(k): return k in ["Honeyfin", ""]), "honey: only Honeyfin")
	check(seen_in.call({"InLava": true}).keys() == [""] and seen_in.call({"InLava": true, "CanFishInLava": true, "rare": true}).has("Obsidifish"),
			"lava: nothing without lava gear, Obsidifish with it")
	check(seen_in.call({"Junk": true}).keys().all(func(k): return k in ["OldShoe", "FishingSeaweed", "TinCan", "JojaCola"]), "junk: Old Shoes, Seaweed, Tin Cans")
	# Stacks of Bomb Fish and Frost Daggerfish.
	var bombs := Fishing.catch_count("BombFish", 75, rng)
	var daggers := Fishing.catch_count("FrostDaggerfish", 75, rng)
	check(bombs >= 3 and bombs <= 10 and daggers >= 16 and daggers <= 54, "Bomb Fish come %d at a time, Frost Daggerfish %d" % [bombs, daggers])
	# Bait: Master Bait is used up 1 time in 1 + 50/6 (less with a Tackle Box), junk never uses it.
	var used := 0
	var used_box := 0
	for i in 20000:
		used += int(Fishing.bait_used("MasterBait", "Bass", false, rng))
		used_box += int(Fishing.bait_used("MasterBait", "Bass", true, rng))
	check(absf(used / 20000.0 - 6.0 / 56.0) < 0.01 and used_box < used and not Fishing.bait_used("Worm", "OldShoe", false, rng),
			"Master Bait is used up %.3f of the time (%.3f with a Tackle Box); junk never uses bait" % [used / 20000.0, used_box / 20000.0])

	# Casting from the dock: the bobber flies out and floats on the pond.
	p.global_position = Vector3(fa.x + 10.5, TestWorld.GROUND + 2.0, fa.z + 11.5)
	p.velocity = Vector3.ZERO
	p.look_at_yaw_pitch(0.0, -0.35)
	await frames(5)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	check(p.bobbers().size() == 1, "using a fishing pole casts its bobber")
	var bob: Bobber = p.bobbers()[0] if p.bobbers().size() > 0 else null
	# (Rising back up, its speed passes 0 for a tick: settled for good takes a while.)
	var floated := false
	for i in 240:
		await frames(1)
		if bob != null and bob.settled and absf(bob.velocity.y) < 0.001 and bob.global_position.y > TestWorld.GROUND + 0.9:
			floated = true
			break
	check(floated and bob.wet and absf(bob.global_position.y - (TestWorld.GROUND + 0.94)) < 0.1 and bob.global_position.z < fa.z + 11.0,
			"it lands in the pond and floats at the surface (%s)" % (bob.global_position if bob else null))
	# A bite: reeling in brings the fish home.
	var bass_before := p.inventory.count_of("Bass")
	var bait_before := p.inventory.count_of("MasterBait")
	bob.timer = 0.0
	bob.catch_item = "Bass"
	bob.catch_bait = "MasterBait"
	bob.catch_level = 75
	bob.bite = -200.0
	var lowest := bob.global_position.y
	var dips := 0
	var was_down := false
	for i in 120:
		await frames(1)
		lowest = minf(lowest, bob.global_position.y)
		var down := bob.global_position.y < TestWorld.GROUND + 0.94 - 0.05
		if down and not was_down:
			dips += 1
		was_down = down
	check(lowest < TestWorld.GROUND + 0.94 - 0.1 and dips >= 2, "a bite pulls the bobber under, again and again (%d dips, down to %.2f)" % [dips, lowest])
	# (Two seconds of it: the fish has got away; another bites.)
	bob.catch_item = "Bass"
	bob.catch_bait = "MasterBait"
	bob.bite = -200.0
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	for i in 120:
		await frames(1)
		if not is_instance_valid(bob) and p.inventory.count_of("Bass") > bass_before:
			break
	check(not is_instance_valid(bob) and p.inventory.count_of("Bass") == bass_before + 1 and p.inventory.count_of("MasterBait") >= bait_before - 1,
			"reeled in during a bite, the bobber comes back with a Bass (%d)" % p.inventory.count_of("Bass"))
	# Switching away from the pole takes the bobber in.
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	await frames(10)
	p.select(5)
	await frames(3)
	check(p.bobbers().is_empty(), "switching items takes the bobber in")
	p.select(0)
	# A real wait: a bite comes in time (the dawn's power, a full moon).
	sky.time = 1000.0
	sky.moon_phase = 0
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	var bit := false
	for i in 60 * 40:
		await frames(1)
		var b: Array = p.bobbers()
		if not b.is_empty() and b[0].bite < 0.0:
			bit = true
			break
	check(bit, "left in the pond, something bites (%s)" % p.fishing_info)
	p.accessories.slots[2] = Inventory.stack("FishermansGuide", 1)
	check(hud.info_text().contains("Fishing Power"), "the Fisherman's Pocket Guide shows it: %s" % hud.info_text())
	p.select(5)
	await frames(3)
	sky.is_day = kept_sky[0]
	sky.time = kept_sky[1]
	sky.moon_phase = kept_sky[2]

	# Crates and oysters: right click to open.
	var loot_of := func(crate: String, n: int) -> Dictionary:
		var got := {}
		for i in n:
			for l in Crates.open(crate, rng):
				got[l[0]] = int(got.get(l[0], 0)) + l[1]
		return got
	var wooden: Dictionary = loot_of.call("WoodenCrate", 300)
	check(wooden.has("ApprenticeBait") and wooden.has("CopperOre") and (wooden.has("SilverCoin") or wooden.has("GoldCoin")) and wooden.has("LesserHealingPotion"),
			"Wooden Crates: bait, ore, coins, potions (%s)" % [wooden.keys()])
	var golden: Dictionary = loot_of.call("GoldenCrate", 200)
	check(golden.has("LifeCrystal") and golden.get("MasterBait", 0) > 300, "Golden Crates: Life Crystals, Master Bait (%d)" % golden.get("MasterBait", 0))
	var jungle: Dictionary = loot_of.call("JungleFishingCrate", 200)
	check(["AnkletoftheWind", "Boomstick", "FeralClaws", "StaffofRegrowth", "FiberglassFishingPole"].all(func(k): return jungle.has(k)),
			"Jungle Crates: the Ivy Chest's treasures (%s)" % [jungle.keys()])
	var oysters: Dictionary = loot_of.call("Oyster", 400)
	var pearls: int = oysters.get("WhitePearl", 0) + oysters.get("BlackPearl", 0) + oysters.get("PinkPearl", 0)
	check(oysters.get("ShuckedOyster", 0) == 400 and pearls > 60 and pearls < 140, "an oyster: a Shucked Oyster, a pearl 1 time in 4 (%d)" % pearls)
	p.inventory.slots.fill(null)
	p.inventory.slots[20] = Inventory.stack("IronCrate", 10)
	hud._open_inventory()
	hud._cursor_stack = null
	# (Its rarest finds aren't in this game: now and then one has nothing in it.)
	var clicks := 0
	var items_now := []
	while clicks < 9 and items_now.size() < 2:
		hud.slot_clicked(hud._slots[20], MOUSE_BUTTON_RIGHT)
		clicks += 1
		items_now = p.inventory.slots.filter(func(s): return s != null)
	check(p.inventory.slots[20] != null and p.inventory.slots[20].count == 10 - clicks and items_now.size() >= 2,
			"right-clicking an Iron Crate opens one (%s)" % [items_now.map(func(s): return s.item)])
	hud.close_inventory()

	# The Frog Leg: a faster jump.
	p.accessories.slots.fill(null)
	p.accessories.slots[0] = Inventory.stack("FrogLeg", 1)
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(10)
	Input.action_press("jump")
	await frames(2)
	var vy := p.velocity.y
	Input.action_release("jump")
	await frames(30)
	# (A tick of gravity in: 1 block a second off.)
	check(vy > Player.JUMP_SPEED + 4.0 - 1.1, "the Frog Leg jumps faster: 1.6 px a tick more (%.2f vs %.2f)" % [vy, Player.JUMP_SPEED])

	p.inventory.slots = kept_slots
	p.accessories.slots = kept_acc
	p.inventory.changed.emit()
	p.accessories.changed.emit()
	p.select(held)


## The test world's fishing spots: each in its biome (and height), deep
## enough for full power, with its biome's fish biting.
func _fishing_spot_checks(c: Vector3i) -> void:
	var p := game.player
	var kept_slots := p.inventory.slots.duplicate(true)
	var kept_pos := p.global_position
	var held := p.selected
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	p.inventory.slots.fill(null)
	p.inventory.slots[0] = Inventory.stack("HotlineFishingHook", 1)
	p.inventory.slots[1] = Inventory.stack("MasterBait", 99)
	p.select(0)
	var kept_bosses := game.defeated_bosses.duplicate()
	game.defeated_bosses["SkeletronHead"] = true
	var kept_quest := game.town.angler_quest
	game.town.angler_quest = ""
	var expect := {
		"Snow": ["snow", 1, "AtlanticCod"], "Desert": ["desert", 1, "Flounder"], "Jungle": ["jungle", 1, "NeonTetra"],
		"Honey (Jungle)": ["jungle", 1, "Honeyfin"], "Corruption": ["corruption", 1, "Ebonkoi"], "Crimson": ["crimson", 1, "CrimsonTigerfish"],
		"Lava": ["", 1, "Obsidifish"], "Glowing Mushroom": ["mushroom", 2, "ArmoredCavefish"], "Underground": ["", 2, "ArmoredCavefish"],
		"Ocean": ["ocean", 1, "Tuna"], "Dungeon": ["dungeon", 1, "DungeonFishingCrate"], "Sky": ["", 0, "Damselfish"],
	}
	check(TestWorld.FISHING_SPOTS.size() == expect.size(), "a fishing spot in every biome: %s" % [TestWorld.FISHING_SPOTS.map(func(s): return s[0])])
	for spot in TestWorld.FISHING_SPOTS:
		var at: Vector3i = spot[1]
		var top := Vector3(c.x + at.x + 0.5, TestWorld.GROUND + at.y + 0.9, c.z + at.z + 0.5)
		var rim := Vector3(top.x, top.y + 0.2, top.z + spot[2].y + 1.5)
		p.global_position = rim
		game.biome = game.detect_biome(rim)
		var pond := Fishing.pond(game.world, top)
		var r := Fishing.check(game, p, top, rng)
		var seen := {}
		for i in 600:
			seen[Fishing.check(game, p, top, rng).catch] = true
		var e: Array = expect.get(spot[0], ["?", -1, "?"])
		check(game.biome == e[0] and Fishing.height_level(game, top.y) == e[1] and not r.info.contains("%") and seen.has(e[2]),
				"fishing spot %s: %s, height %d, %d tiles (%s), %s bites (%s)" % [spot[0], game.biome, Fishing.height_level(game, top.y), pond.tiles, r.info, e[2], seen.keys()])
	check(game.in_ocean(Vector3(c.x + 0.5, TestWorld.GROUND + 1, c.z - 119.5)) and not game.in_ocean(Vector3(c.x, TestWorld.GROUND + 1, c.z)),
			"the test world's ocean strip is the ocean (and the plaza isn't)")
	game.defeated_bosses = kept_bosses
	game.town.angler_quest = kept_quest
	game.biome = ""
	p.inventory.slots = kept_slots
	p.inventory.changed.emit()
	p.select(held)
	p.global_position = kept_pos


## The Angler: in the test town; his quests (today's fish, handing it in,
## the rewards, a new one at dawn), his chat; the Sleeping Angler at the
## ocean, woken; the potions, buckets and info accessories he gives.
func _angler_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var hud := game.hud
	var town := game.town
	var kept_slots := p.inventory.slots.duplicate(true)
	var kept_acc := p.accessories.slots.duplicate(true)
	var kept_pos := p.global_position
	var kept_quests := p.angler_quests
	var held := p.selected
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var angler: NPC = town.residents.get("Angler")
	check(angler != null and angler.home_key != "" and angler.title().ends_with(" the Angler") and angler.display_name in Assets.ids.names.town.AnglerNames,
			"the Angler lives in the test town (%s)" % (angler.title() if angler else "none"))
	check(town.angler_quest in AnglerQuests.FISH and not town.angler_quest in AnglerQuests.HARDMODE_FISH, "he wants a fish today: %s" % town.angler_quest)
	var picks := {}
	for i in 2000:
		picks[AnglerQuests.pick(false, false, rng)] = true
	check(picks.size() >= 25 and not picks.keys().any(func(f): return f in AnglerQuests.HARDMODE_FISH or f in AnglerQuests.SKY_FISH or f == "BloodyManowar"),
			"his fish: %d kinds before Hardmode in a Corruption world with no boss beaten (no Hardmode, sky or Crimson fish)" % picks.size())
	check(AnglerQuests.pick(true, true, rng) != "EaterofPlankton" and _fish_fit_crimson(), "fish fit the world (no Corruption fish in a Crimson world)")
	# Talking: his lines, and the Quest button (by him: walk off and the chat closes).
	p.global_position = angler.global_position + Vector3(1.0, 0.2, 0.0)
	p.velocity = Vector3.ZERO
	hud.open_chat(angler)
	await frames(2)
	check(hud._chat_text.text != "" and hud._chat_text.text != "..." and hud._chat_buttons.get_children().any(func(b): return b.text == "Quest"),
			"he talks (%s) and has a Quest button" % hud._chat_text.text.left(50))
	town.angler_quest = "Mudfish"
	town.angler_done = false
	p.inventory.slots.fill(null)
	hud.chat_button("Quest")
	var quest_text: String = Assets.ids.names.town.AnglerQuestText.Quest_Mudfish
	check(hud._chat_text.text == quest_text and hud._chat_item.visible, "Quest: what he wants, his fish in the corner (%s)" % hud._chat_text.text.left(60))
	# The quest fish bites (in the Jungle), once, and only while it's his fish.
	var spot: Array = TestWorld.FISHING_SPOTS.filter(func(s): return s[0] == "Jungle")[0]
	var top := Vector3(c.x + spot[1].x + 0.5, TestWorld.GROUND + 0.9, c.z + spot[1].z + 0.5)
	game.biome = "jungle"
	p.inventory.slots[0] = Inventory.stack("GoldenFishingRod", 1)
	p.inventory.slots[1] = Inventory.stack("MasterBait", 99)
	p.select(0)
	var caught := 0
	for i in 1000:
		if Fishing.check(game, p, top, rng).catch == "Mudfish":
			caught += 1
	check(caught > 20, "today's fish bites where Terraria has it: %d Mudfish in 1000 jungle bites" % caught)
	p.inventory.add("Mudfish", 1)
	caught = 0
	for i in 1000:
		if Fishing.check(game, p, top, rng).catch == "Mudfish":
			caught += 1
	check(caught == 0, "not once you've one")
	check(Hud.item_tooltip(Data.item("Mudfish")).contains("Quest Item") and Hud.item_tooltip(Data.item("Mudfish")).contains("Caught in Jungle"), "a quest fish's tooltip says where it's caught")
	town.angler_quest = "Batfish"
	p.inventory.slots[2] = null
	caught = 0
	for i in 1000:
		if Fishing.check(game, p, top, rng).catch == "Mudfish":
			caught += 1
	check(caught == 0, "and not when it isn't his fish today")
	# Handing it in: his rewards; done for the day.
	town.angler_quest = "Mudfish"
	p.inventory.add("Mudfish", 1)
	p.angler_quests = 9
	var money := p.inventory.money()
	hud.chat_button("Quest")
	check(p.inventory.count_of("Mudfish") == 0 and p.angler_quests == 10 and town.angler_done and p.inventory.count_of("AnglerHat") == 1
			and p.inventory.money() > money and hud._chat_text.text in Assets.ids.names.town.AnglerQuestText.values() and not hud._chat_item.visible,
			"handed in, the 10th quest: the Angler Hat and money (%s)" % hud._chat_text.text.left(40))
	hud.chat_button("Quest")
	var no_quest: Array = Assets.ids.names.town.AnglerQuestText.keys().filter(func(k): return k.begins_with("NoQuest_")).map(func(k): return NPC.fill(Assets.ids.names.town.AnglerQuestText[k]))
	check(hud._chat_text.text in no_quest, "then nothing more today (%s)" % hud._chat_text.text.left(40))
	hud.close_chat()
	# His rewards: milestones, else an accessory you haven't got, or potions.
	var got := {}
	for i in 400:
		for r in AnglerQuests.rewards(3, "Batfish", [], rng):
			got[r[0]] = true
	check(got.has("FishingPotion") and got.has("HighTestFishingLine") and (got.has("SilverCoin") or got.has("GoldCoin")) and got.has("ApprenticeBait"),
			"rewards: potions, the fishing accessories, money and bait (%s)" % [got.keys()])
	var owned := AnglerQuests.ACCESSORIES.filter(func(a): return a != "Sextant")
	var accs := {}
	for i in 600:
		for r in AnglerQuests.rewards(3, "Batfish", owned + ["AnglerTackleBag"], rng):
			if r[0] in AnglerQuests.ACCESSORIES:
				accs[r[0]] = true
	check(accs.keys() == ["Sextant"], "while you lack some of his accessories, only those (%s)" % [accs.keys()])
	check(AnglerQuests.rewards(30, "Batfish", [], rng)[0][0] == "GoldenFishingRod", "the 30th quest: the Golden Fishing Rod")
	# A new day, a new fish.
	game.sky.dawn.emit()
	check(not town.angler_done and town.angler_quest in AnglerQuests.FISH, "at dawn he wants a new fish (%s)" % town.angler_quest)

	# The Sleeping Angler: afloat at the ocean; woken, he's the Angler.
	town.residents.erase("Angler")
	town.arrived.erase("Angler")
	var ocean_top := Vector3(c.x + 0.5, TestWorld.GROUND + 0.95, c.z - 119.5)
	p.global_position = ocean_top + Vector3(0, 3, 6)
	p.velocity = Vector3.ZERO
	game.biome = "ocean"
	# The spawner: a spawn in the ocean's water is him. (Enemies about would
	# fill its cap.)
	for n in game.npcs():
		if not n.def.ai in ["town", "dummy"]:
			n.queue_free()
	await frames(1)
	for i in 40:
		game.spawner.spawn_tick()
		if game.npcs().any(func(n): return n.kind == "SleepingAngler"):
			break
		# (A tick that finds no spot for him spawns an enemy; those would fill the cap.)
		for n in game.npcs():
			if not n.def.ai in ["town", "dummy"] and not n.is_queued_for_deletion():
				n.queue_free()
		await frames(1)
	var sleeping: Array = game.npcs().filter(func(n): return n.kind == "SleepingAngler")
	check(sleeping.size() == 1, "in the ocean the Sleeping Angler turns up, asleep on the water")
	var sl: NPC = sleeping[0] if not sleeping.is_empty() else game.spawn_npc("SleepingAngler", ocean_top)
	sl.global_position = ocean_top + Vector3(0, -1.5, 0)
	await frames(90)
	var surf := TestWorld.GROUND + 0.94
	check(absf(sl.global_position.y - surf) < 0.5, "he floats at the surface (%.2f, surface %.2f)" % [sl.global_position.y, surf])
	var woke: NPC = town.wake_angler(sl)
	hud.open_chat(woke, NPC.dialog(353))
	await frames(2)
	check(town.residents.has("Angler") and town.arrived.has("Angler") and hud._chat_text.text.begins_with("Thanks, I guess"), "woken, he's the Angler: \"%s\"" % hud._chat_text.text.left(40))
	hud.close_chat()
	woke.queue_free()
	town.residents["Angler"] = angler
	game.biome = ""

	# His potions: the Fishing Potion's 15 power, the Crate Potion's crates.
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.inventory.slots.fill(null)
	p.inventory.slots[0] = Inventory.stack("ReinforcedFishingPole", 1)
	p.inventory.slots[1] = Inventory.stack("MasterBait", 9)
	p.inventory.slots[2] = Inventory.stack("FishingPotion", 1)
	p.select(0)
	var before: int = Fishing.conditions(p, game.sky).skill
	p.select(2)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	p.select(0)
	check(p.has_buff("Fishing") and Fishing.conditions(p, game.sky).skill == before + 15 and p.buffs().any(func(b): return b[1] == "Fishing"),
			"the Fishing Potion: +15 fishing power for 8 minutes")
	var crates := [0, 0]
	for i in 4000:
		crates[0] += int(Fishing.roll_rarity(50, false, rng).crate)
		crates[1] += int(Fishing.roll_rarity(50, true, rng).crate)
	check(absf(crates[0] / 4000.0 - 0.1) < 0.02 and absf(crates[1] / 4000.0 - 0.25) < 0.03, "crates 1 in 10, 1 in 4 with a Crate Potion (%d, %d of 4000)" % crates)
	p.timed_buffs.clear()
	# Bottomless buckets and sponges.
	var pit := c + Vector3i(40, 30, 40)
	for x in range(-2, 3):
		for z in range(-2, 3):
			w.set_block(pit + Vector3i(x, -1, z), Data.block_id("glass"))
	p.global_position = Vector3(pit) + Vector3(0.5, 3.0, 0.5)
	p.velocity = Vector3.ZERO
	p.look_at_yaw_pitch(0.0, -PI / 2.0 + 0.01)
	p.god_mode = true
	await frames(30)
	p.inventory.slots[3] = Inventory.stack("BottomlessBucket", 1)
	p.select(3)
	await frames(2)
	p._use_timer = 0.0
	p.use_item()
	var poured := w.get_liquid(pit).x == Player.LIQ_WATER
	check(poured and p.inventory.slots[3] != null and p.inventory.slots[3].item == "BottomlessBucket", "the Bottomless Bucket pours water and stays full")
	p.inventory.slots[3] = Inventory.stack("SuperAbsorbantSponge", 1)
	await frames(2)
	p._use_timer = 0.0
	p.use_item()
	check(w.get_liquid(pit).y == 0 and p.inventory.slots[3].item == "SuperAbsorbantSponge", "the Super Absorbant Sponge soaks it up and stays a sponge")
	p.god_mode = false
	# The Sextant and Weather Radio.
	p.accessories.slots.fill(null)
	p.accessories.slots[0] = Inventory.stack("Sextant", 1)
	p.accessories.slots[1] = Inventory.stack("WeatherRadio", 1)
	game.sky.moon_phase = 0
	var info := hud.info_text()
	check(info.contains("Full Moon") and (info.contains("Clear") or info.contains("Cloudy")), "the Sextant and Weather Radio: %s" % info.replace("\n", " / "))
	check(Data.item("FishHook").get("type") == "hook" and Data.item("FishHook").hook.latched == 2, "the Fish Hook is a grappling hook (two hooks)")

	p.angler_quests = kept_quests
	p.inventory.slots = kept_slots
	p.accessories.slots = kept_acc
	p.inventory.changed.emit()
	p.accessories.changed.emit()
	p.select(held)
	p.global_position = kept_pos


func _fish_fit_crimson() -> bool:
	for i in 300:
		var f := AnglerQuests.pick(true, false, RandomNumberGenerator.new())
		if f in ["EaterofPlankton", "InfectedScabbardfish"]:
			return false
	return true


## Critters: the pen's spawners, their AIs (walking, flying off, drifting,
## crawling, swimming), the Bug Net and letting them go, plants letting out
## bait, the spawner's critter rules.
func _critter_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var tw := game.test_world
	var kept_slots := p.inventory.slots.duplicate(true)
	var kept_pos := p.global_position
	var held := p.selected
	var god := p.god_mode
	p.god_mode = true
	var critters: Array = Data.npcs.keys().filter(func(k): return Data.npcs[k].get("critter", false))
	var pen_kinds := {}
	for sp in tw.spawners.values():
		if Data.npcs[sp.kind].get("critter", false):
			pen_kinds[sp.kind] = true
	check(critters.size() >= 45 and critters.all(func(k): return pen_kinds.has(k) and Data.items.has(Data.npcs[k].catch)),
			"%d critters, each with a spawner in the pen and an item to catch" % critters.size())
	check(Data.npcs.Merchant.town.shop.has("BugNet"), "the Merchant sells the Bug Net")
	var a := Vector3(c.x + TestWorld.CRITTER_PEN.x, TestWorld.GROUND + 1, c.z + TestWorld.CRITTER_PEN.z)
	var spot := a + Vector3(8.5, 0, 11.5)
	var clear := func() -> void:
		for n in game.npcs():
			if n.is_critter():
				n.queue_free()
		await frames(1)
	await clear.call()
	p.global_position = a + Vector3(20.5, 0, 3.5)
	p.velocity = Vector3.ZERO
	await frames(10)
	# A bunny potters about on the ground.
	var bunny: NPC = game.spawn_npc("Bunny", spot)
	bunny._crit_state = 1
	bunny._crit_dir = Vector3.RIGHT  # (else its first tick picks a heading and a new timer)
	bunny._crit_timer = 300
	# (How far it walks, not where it ends: it turns at the pen's walls.)
	var walked := 0.0
	var last := bunny.global_position
	for i in 240:
		await frames(1)
		if is_instance_valid(bunny):
			walked += Vector2(bunny.global_position.x - last.x, bunny.global_position.z - last.z).length()
			last = bunny.global_position
	check(is_instance_valid(bunny) and bunny.on_floor and walked > 3.0, "a bunny walks about (%.1f blocks in 4 s)" % walked)
	# A bird sits, and flies off when you come near.
	var bird: NPC = game.spawn_npc("Bird", spot + Vector3(-4, 0, 0))
	await frames(30)
	var sat := bird._crit_state == 0 and bird.on_floor
	p.global_position = bird.global_position + Vector3(2.0, 0, 0)
	await frames(60)
	check(sat and bird._crit_state == 1 and bird.global_position.y > spot.y + 0.5 and bird.global_position.x < spot.x - 4.0,
			"a bird sits till you come near, then flies off away from you (%s)" % bird.global_position)
	# Butterflies flutter; each is one of eight colours, caught as its own item.
	var fly: NPC = game.spawn_npc("Butterfly", spot + Vector3(0, 1.5, 0))
	await frames(2)
	var fly_scale := fly.sprite.scale
	await frames(120)
	check(is_instance_valid(fly) and fly.sprite.scale.is_equal_approx(fly_scale) and fly_scale.x > 0.3,
			"it keeps the size it's born with (%s, then %s)" % [fly_scale, fly.sprite.scale if is_instance_valid(fly) else null])
	check(is_instance_valid(fly) and fly.variant >= 0 and fly.variant < 8 and fly.catch_item() == NPC.BUTTERFLIES[fly.variant]
			and fly.global_position.y > spot.y + 0.3, "a butterfly flutters about (%s, %.1f up)" % [fly.catch_item(), fly.global_position.y - spot.y])
	var colours := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	for i in 4000:
		var v := NPC.roll_butterfly(rng)
		colours[v] = int(colours.get(v, 0)) + 1
	check(absf(colours[0] / 4000.0 - 0.25) < 0.03 and absf(colours[5] / 4000.0 - 0.01) < 0.01, "Terraria's odds of colours: Monarch 25%%, Tree Nymph 1%% (%s)" % [colours])
	# A worm crawls (0.2 px a tick: half a block a second).
	# (Out by the door, clear of the spawners.)
	var worm: NPC = game.spawn_npc("Worm", a + Vector3(19.5, 0, 2.5))
	worm._crit_dir = Vector3.RIGHT
	worm._crit_state = 1
	worm._crit_timer = 999
	await frames(60)
	var ws := worm.global_position
	await frames(120)
	var crawled := worm.global_position.distance_to(ws)
	check(crawled > 0.7 and crawled < 1.3, "a worm crawls 0.2 px a tick (%.2f blocks in 2 s)" % crawled)
	# A duck on the pond paddles at the surface, and flies off when you come near.
	var pond := Vector3(a.x + TestWorld.CRITTER_PEN_SIZE.x - 3.5, TestWorld.GROUND + 0.8, a.z + 10.5)
	p.global_position = a + Vector3(10.5, 0, 18.5)
	var duck: NPC = game.spawn_npc("Duck", pond)
	await frames(120)
	var surf := TestWorld.GROUND + 0.94
	check(is_instance_valid(duck) and duck._crit_state != 2 and absf(duck.global_position.y - (surf - 0.25)) < 0.4, "a duck paddles on the pond (%.2f, surface %.2f)" % [duck.global_position.y, surf])
	p.global_position = duck.global_position + Vector3(-2.0, 0.2, 0)
	await frames(30)
	check(duck._crit_state == 2 and duck.global_position.y > surf + 0.3, "and flies off when you come near (%.2f)" % duck.global_position.y)
	var fish: NPC = game.spawn_npc("Goldfish", pond + Vector3(0, -1.5, 4))
	await frames(180)
	check(is_instance_valid(fish) and fish.in_water(fish.center()), "a goldfish swims in the pond")
	# Catching: the Bug Net's swing catches the critter it sweeps through.
	await clear.call()
	p.global_position = a + Vector3(12.5, 0, 14.5)
	p.look_at_yaw_pitch(0.0, -0.4)
	await frames(5)
	var target := game.spawn_npc("Bunny", p.global_position + p.forward().slide(Vector3.UP).normalized() * 1.6)
	target._crit_state = 0
	target._crit_timer = 999
	p.inventory.slots.fill(null)
	p.inventory.slots[0] = Inventory.stack("BugNet", 1)
	p.select(0)
	await frames(2)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	await frames(90)
	check(not is_instance_valid(target) and p.inventory.count_of("Bunny") == 1, "the Bug Net catches the bunny: a Bunny in your inventory")
	# Letting it go: used, the Bunny is back where you aim.
	var slot := -1
	for i in p.inventory.slots.size():
		if p.inventory.slots[i] != null and p.inventory.slots[i].item == "Bunny":
			slot = i
	p.select(slot)
	await frames(3)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	await frames(5)
	check(p.inventory.count_of("Bunny") == 0 and game.npcs().any(func(n): return n.kind == "Bunny" and n.released), "used, the Bunny goes free where you aim")
	# The Underworld's critters burn a plain Bug Net's owner; the Golden one is fine.
	await clear.call()
	p.god_mode = false
	var hp := p.life
	var snail := game.spawn_npc("MagmaSnail", p.global_position + p.forward().slide(Vector3.UP).normalized() * 1.4)
	p.select(0)
	p._immune = 0.0
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	await frames(3)
	check(is_instance_valid(snail) and p.on_fire > 0.0 and p.life < hp, "a plain Bug Net can't hold a Magma Snail: it burns you")
	p.on_fire = 0.0
	p.god_mode = true
	p.inventory.slots[0] = Inventory.stack("GoldenBugNet", 1)
	await frames(30)
	# (It crawls on: back in front of you.)
	snail.global_position = p.global_position + p.forward().slide(Vector3.UP).normalized() * 1.4
	snail.velocity = Vector3.ZERO
	await frames(1)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	await frames(90)
	check(not is_instance_valid(snail) and p.inventory.count_of("MagmaSnail") == 1 and p.on_fire == 0.0, "the Golden Bug Net catches it safely")
	check(int(Data.item("Worm").bait) == 25 and int(Data.item("TreeNymphButterfly").bait) == 50 and int(Data.item("GoldWorm").bait) == 50,
			"critters are bait (Worm 25, Tree Nymph 50, Gold Worm 50)")
	# Broken grass now and then lets out a worm or a grasshopper; jungle plants grubs.
	await clear.call()
	var grass_def := Data.block(Data.block_id("tall_grass"))
	var jungle_def := Data.block(Data.block_id("jungle_plants"))
	var out := {}
	var at := Vector3i(a + Vector3(6, 0, 6))
	for i in 6000:
		game._drop_bait(at, grass_def)
		game._drop_bait(at, jungle_def)
		for n in game.npcs():
			if n.is_critter() and not n.is_queued_for_deletion():
				out[n.kind] = int(out.get(n.kind, 0)) + 1
				n.free()
	var worms: int = out.get("Worm", 0) + out.get("GoldWorm", 0)
	var hoppers: int = out.get("Grasshopper", 0) + out.get("GoldGrasshopper", 0)
	var grubs: int = out.get("Grubby", 0) + out.get("Sluggy", 0) + out.get("Buggy", 0)
	check(int(grass_def.tile_id) == 3 and worms > 5 and worms < 35 and hoppers > 35 and hoppers < 90 and grubs > 35 and grubs < 90,
			"broken plants let out bait: %d worms, %d grasshoppers (6000 grass), %d grubs (6000 jungle plants)" % [worms, hoppers, grubs])
	# The spawner's critters (its rules for a spot on land): by day on grass
	# (at noon: the mornings are the birds'), at night, underground, on snow.
	var sp := game.spawner
	var picks := func(ground: String, depth: String, night: bool, tries: int, y := 0.0) -> Dictionary:
		var got := {}
		var where := Vector3(c.x, TestWorld.GROUND + 1 + y, c.z)
		for i in tries:
			for k in sp.pick_critters(game, where, ground, depth, night):
				got[k[0]] = int(got.get(k[0], 0)) + 1
		return got
	game.biome = ""
	var kept_time := game.sky.time
	game.sky.time = 30000.0
	var kept_bf: int = sp.butterfly_chance
	sp.butterfly_chance = 999999
	var day: Dictionary = picks.call("grass", "surface", false, 3000)
	check(day.get("Bunny", 0) > 80 and day.get("Squirrel", 0) + day.get("SquirrelRed", 0) > 30 and not day.has("Worm") and not day.has("Bird"),
			"by day on grass: bunnies, squirrels (%s)" % [day])
	game.sky.time = 6000.0
	var morning: Dictionary = picks.call("grass", "surface", false, 3000)
	check(morning.get("Bird", 0) + morning.get("BirdBlue", 0) + morning.get("BirdRed", 0) > 300, "in the morning birds (%s)" % [morning])
	sp.butterfly_chance = 1
	game.sky.time = 30000.0
	var bf: Dictionary = picks.call("grass", "surface", false, 600)
	check(bf.get("Butterfly", 0) > 30 and not bf.has("Bunny"), "on a butterfly day: butterflies (%s)" % [bf])
	sp.butterfly_chance = kept_bf
	game.sky.time = kept_time
	var kept_ff: int = sp.firefly_chance
	sp.firefly_chance = 1
	var night: Dictionary = picks.call("grass", "surface", true, 200)
	sp.firefly_chance = kept_ff
	check(night.has("Firefly") and not night.has("Bunny"), "at night: fireflies (%s)" % [night])
	var deep: Dictionary = picks.call("stone", "underground", false, 2000, -30.0)
	check(deep.has("Worm") and deep.has("Mouse") and not deep.has("Bunny"), "underground: worms, mice (%s)" % [deep])
	var snowy: Dictionary = picks.call("snow_block", "surface", false, 3000)
	check(snowy.has("Penguin") and snowy.has("PenguinBlack") and not snowy.has("Bunny"), "on snow: penguins (%s)" % [snowy.keys()])
	check(picks.call("mushroom_grass", "underground", false, 600, -30.0).has("GlowingSnail"), "on mushroom grass: glowing snails")
	check(game.npcs().filter(func(n): return n.def.ai != "town" and not n.is_critter()).size() <= game.npcs().size(), "critters don't count toward the enemy cap")
	await clear.call()
	# Killed, they break up as in Terraria's HitEffect: a bunny into its two
	# pieces and blood, a butterfly into its own dust, gold ones into gold.
	var gores := func() -> Array: return game.entities.get_children().filter(func(e): return e is Gore)
	for e in gores.call():
		e.queue_free()
	await frames(1)
	var deaths := {"Bunny": [[76, 77], [5]], "Butterfly": [[], [199]], "GoldBunny": [[], [232, 233]]}
	for k in deaths:
		var critter: NPC = game.spawn_npc(k, spot)
		await frames(2)
		var dust_from := game.dust.count()
		critter.hit(9999, 0.0, Vector3.RIGHT, 0.0)
		var made: Array = gores.call().map(func(e): return e.gore_id)
		made.sort()
		var kinds := {}
		for i in range(dust_from, game.dust.count()):
			kinds[game.dust._type[i]] = true
		check(made == deaths[k][0] and game.dust.count() - dust_from >= 6 and kinds.keys().all(func(t): return t in deaths[k][1]),
				"a killed %s leaves gores %s and dust %s" % [k, made, kinds.keys()])
		for e in gores.call():
			e.queue_free()
		await frames(1)

	p.god_mode = god
	p.inventory.slots = kept_slots
	p.inventory.changed.emit()
	p.select(held)
	p.global_position = kept_pos


func _prefix_checks(c: Vector3i) -> void:
	var p := game.player
	var hud := game.hud
	var kept_slots := p.inventory.slots.duplicate(true)
	var kept_acc := p.accessories.slots.duplicate(true)
	var d := Prefixes.data()
	var list := func(item: String) -> Array: return Prefixes.rollable(Data.item(item))
	check(list.call("PlatinumBroadsword") == d.rollable.swords and list.call("PlatinumPickaxe") == d.rollable.swords and list.call("Spear") == d.rollable.spears
			and list.call("WoodenBow") == d.rollable.guns_bows and list.call("AmethystStaff") == d.rollable.magic and list.call("WoodenBoomerang") == d.rollable.boomerangs
			and list.call("WoodYoyo") == d.rollable.boomerangs and list.call("HermesBoots") == d.rollable.accessories,
			"swords and tools, spears, bows and guns, magic, boomerangs and yoyos, accessories: each their own prefixes")
	check(["GrapplingHook", "Shuriken", "DirtBlock", "PlatinumHelmet", "LesserHealingPotion", "WoodenArrow"].all(func(n): return list.call(n).is_empty()),
			"hooks, thrown weapons, blocks, armor, potions and ammo have none")
	check(d.rollable.swords.size() == 40 and d.rollable.accessories.size() == 19 and d.rollable.guns_bows.size() == 35 and d.rollable.magic.size() == 36,
			"40 prefixes for swords, 35 for guns and bows, 36 for magic, 19 for accessories")
	check(Prefixes.prefix_name(81) == "Legendary" and Prefixes.prefix_name(82) == "Unreal" and Prefixes.prefix_name(83) == "Mythical"
			and Prefixes.prefix_name(65) == "Warding" and Prefixes.prefix_name(72) == "Menacing" and Prefixes.prefix_name(Assets.ids.PrefixID.Deadly2) == "Deadly",
			"Terraria's names: Legendary, Unreal, Mythical, Warding, Menacing (and the second Deadly)")
	# Terraria's sums: 32-bit floats, halves rounded to even.
	check(Prefixes._scaled(10, 1.05) == 10 and Prefixes._scaled(30, 1.15) == 34 and Prefixes.round_even(2.5) == 2.0 and Prefixes.round_even(3.5) == 4.0,
			"rounded as Terraria rounds (10 x 1.05 is 10, 30 x 1.15 is 34)")
	# A Legendary Platinum Broadsword.
	var base := Data.item("PlatinumBroadsword")
	var leg := Data.item_of(Inventory.stack("PlatinumBroadsword", 1, 81))
	check(leg.name == "Legendary Platinum Broadsword", "its name: %s" % leg.name)
	check(leg.damage == Prefixes._scaled(base.damage, 1.15) and leg.use_time == Prefixes._scaled(base.use_time, 0.9) and is_equal_approx(leg.knockback, base.knockback * 1.15)
			and leg.crit == int(base.get("crit", 0)) + 5 and is_equal_approx(leg.scale, 1.1),
			"Legendary: +15%% damage, +10%% speed, +5%% crit, +10%% size, +15%% knockback (%d dmg, %d ticks)" % [leg.damage, leg.use_time])
	var lv := Prefixes.f32(1.15 * 1.1 * 1.1 * 1.15 * 1.1)
	check(absf(leg.value - Data.value("PlatinumBroadsword") * lv * lv) <= 2.0 and Hud.sell_price("PlatinumBroadsword", 81) == int(leg.value) / 5,
			"worth the square of its value multiplier more (%d copper), sold for a fifth" % leg.value)
	var tips := Prefixes.tooltip_lines(leg)
	var texts := tips.map(func(t): return t[0])
	check(tips.all(func(t): return t[1]) and texts.has("+5% critical strike chance") and texts.has("+10% size") and texts.has("+15% knockback")
			and texts.any(func(t): return t.ends_with("% damage") and t.begins_with("+")) and texts.any(func(t): return t.ends_with("% speed") and t.begins_with("+")),
			"its tooltip lines, all good: %s" % [texts])
	var broken := Prefixes.tooltip_lines(Data.item_of(Inventory.stack("PlatinumBroadsword", 1, Assets.ids.PrefixID.Broken)))
	check(broken.size() == 2 and broken.all(func(t): return not t[1]) and broken[0][0].begins_with("-") and broken[1][0] == "-20% knockback",
			"a Broken one's are bad: %s" % [broken.map(func(t): return t[0])])
	check(Prefixes.multipliers(Data.item("WoodenBow"), Assets.ids.PrefixID.Intimidating).is_empty() and float(Data.item("WoodenBow").knockback) == 0.0,
			"a weapon without knockback can't get more of it (no Intimidating Wooden Bow)")
	# Rolling: a quarter of crafted or found ones have none (more with the
	# reduced ones), reforging always gives one.
	var none := 0
	var ok := true
	for i in 4000:
		var r := Prefixes.roll(base)
		if r == 0:
			none += 1
		elif not r in d.rollable.swords:
			ok = false
	check(ok and none > 4000 * 0.3 and none < 4000 * 0.43, "rolled naturally, a sword has none %.0f%% of the time" % (none * 100.0 / 4000))
	var forged := []
	for i in 500:
		forged.append(Prefixes.roll(base, Prefixes.REFORGE))
	check(forged.all(func(r): return r in d.rollable.swords), "reforged it always gets one")
	check(Prefixes.roll(Data.item("DirtBlock")) == 0 and Prefixes.roll(Data.item("GrapplingHook"), Prefixes.REFORGE) == 0, "something that can't have one never does")
	# In your hands: its damage and speed.
	var held := p.selected
	p.inventory.slots[p.selected] = Inventory.stack("PlatinumBroadsword", 1, 81)
	check(p.held().name == "Legendary Platinum Broadsword" and p.weapon_damage(p.held()) >= p.weapon_damage(base) and is_equal_approx(p.crit_chance(p.held()) - p.crit_chance(base), 0.05),
			"held, it hits harder and crits more often")
	await frames(3)
	var big := p.viewmodel.item_node().transform.basis.get_scale().x
	p.inventory.slots[p.selected] = Inventory.stack("PlatinumBroadsword", 1)
	await frames(3)
	var plain := p.viewmodel.item_node().transform.basis.get_scale().x
	check(absf(big / plain - 1.1) < 0.01, "and looks 10%% bigger in your hand (%.3f)" % (big / plain))
	# An accessory's prefix: Warding adds 4 defense, Menacing 4% damage, Arcane 20 mana.
	var def0 := p.defense()
	var dmg0 := p.stat("damage")
	var mana0 := p.mana_cap()
	p.accessories.slots[0] = Inventory.stack("HermesBoots", 1, 65)
	p.accessories.slots[1] = Inventory.stack("CloudinaBottle", 1, 72)
	p.accessories.slots[2] = Inventory.stack("BandofRegeneration", 1, 66)
	check(p.defense() == def0 + 4 and is_equal_approx(p.stat("damage"), dmg0 + 4.0) and p.mana_cap() == mana0 + 20,
			"worn: Warding +4 defense, Menacing +4%% damage, Arcane +20 mana (%d, %.0f, %d)" % [p.defense() - def0, p.stat("damage") - dmg0, p.mana_cap() - mana0])
	var warding := Data.item_of(p.accessories.slots[0])
	check(warding.name == "Warding Hermes Boots" and Prefixes.tooltip_lines(warding) == [["+4 defense", true]]
			and Prefixes.tooltip_lines(Data.item_of(p.accessories.slots[2])) == [["+20 mana", true]],
			"its tooltip line: +4 defense (Arcane: +20 mana)")
	check(Prefixes.value("HermesBoots", 65) == int(Prefixes.f32(Data.value("HermesBoots") * Prefixes.f32(Prefixes.f32(1.2) * Prefixes.f32(1.2)))),
			"a Warding accessory is worth 1.44 times as much")
	p.accessories.slots = kept_acc.duplicate(true)
	# Kept: a prefixed item doesn't stack, and stays itself in a save, a drop and back.
	p.inventory.slots.fill(null)
	p.inventory.add("PlatinumBroadsword", 1, 81)
	p.inventory.add("PlatinumBroadsword", 1)
	var data := p.inventory.to_data()
	p.inventory.from_data(JSON.parse_string(JSON.stringify(data)))
	check(int(p.inventory.slots[0].get("prefix", 0)) == 81 and not p.inventory.slots[1].has("prefix"), "a prefixed item keeps its own slot and its prefix through a save")
	p.selected = 0
	p.throw_held()
	await frames(2)
	var drops := game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "PlatinumBroadsword")
	check(drops.size() == 1 and drops[0].prefix == 81, "thrown away, it's still Legendary on the ground")
	drops[0].age = 1.0
	drops[0].global_position = p.global_position + Vector3(0, 0.9, 0)
	await frames(5)
	check(p.inventory.slots.any(func(s): return s != null and int(s.get("prefix", 0)) == 81), "and when you pick it up")
	# Dropped by enemies (and found in chests) they come with one.
	p.inventory.slots.fill(null)
	for i in 40:
		game.spawn_item("PlatinumBroadsword", 1, Vector3(c) + Vector3(0.5, 30, 0.5), Vector3.ZERO, 0.0, Prefixes.NATURAL)
	var natural := game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "PlatinumBroadsword").map(func(e): return e.prefix)
	check(natural.size() == 40 and natural.any(func(x): return x != 0) and natural.all(func(x): return x == 0 or x in d.rollable.swords),
			"an enemy's drop rolls a prefix (%d of 40 got one)" % natural.filter(func(x): return x != 0).size())
	for e in game.entities.get_children():
		if e is ItemDrop:
			e.queue_free()
	var found := 0
	for i in 30:
		var at := Vector3i(5, 3, 5 + i)
		game.chests._worldgen[Chests.key(at)] = true
		game.chests._tables[Chests.key(at)] = "chest"
		for s in game.chests.get_inventory(at).slots:
			if s != null and s.has("prefix"):
				found += 1
		game.chests.remove(at)
	check(found > 0, "chests' weapons and accessories come with prefixes (%d in 30 chests)" % found)
	# Crafted one at a time, they roll one too.
	hud._open_inventory()
	hud._stations = {"work_bench": true}
	p.inventory.add("Wood", 200)
	var sword := {}
	for r in Data.recipes:
		if r.result == "WoodenSword":
			sword = r
	var crafted := []
	for i in 20:
		hud.craft(sword)
		if hud._cursor_stack != null:
			crafted.append(int(hud._cursor_stack.get("prefix", 0)))
		hud._cursor_stack = null
	check(crafted.size() == 20 and crafted.any(func(x): return x != 0) and crafted.all(func(x): return x == 0 or x in d.rollable.swords),
			"crafted Wooden Swords roll prefixes (%d of 20)" % crafted.filter(func(x): return x != 0).size())
	hud.close_inventory()
	# The Goblin Tinkerer reforges: a third of the item's value, a new prefix.
	var tinkerer: NPC = game.town.residents.get("GoblinTinkerer")
	check(tinkerer != null, "the test town's Goblin Tinkerer")
	if tinkerer != null:
		p.global_position = tinkerer.global_position + Vector3(1, 0, 0)
		hud.open_chat(tinkerer)
		check(hud._chat_buttons.get_children().any(func(b): return b.text == "Reforge"), "he has a Reforge button")
		hud.chat_button("Reforge")
		check(hud.reforge_open and hud.inventory_open and hud._reforge_panel.visible, "it opens the reforge slot with your inventory")
		check(not Hud.slot_accepts("reforge", "DirtBlock") and Hud.slot_accepts("reforge", "HermesBoots"), "only things that can have a prefix go in it")
		p.inventory.slots.fill(null)
		p.inventory.slots[12] = Inventory.stack("PlatinumBroadsword", 1)
		p.inventory.add_money(5 * 10000)
		hud._quick_move(hud._slots[12])
		check(hud._reforge_inv.slots[0] != null and p.inventory.slots[12] == null, "Shift-click puts the item in the reforge slot")
		var cost := hud.reforge_cost()
		check(cost == maxi(1, Data.value("PlatinumBroadsword") / 3), "reforging costs a third of its value (%s)" % Inventory.money_text(cost))
		var money := p.inventory.money()
		check(hud.reforge() and int(hud._reforge_inv.slots[0].get("prefix", 0)) in d.rollable.swords and p.inventory.money() == money - cost,
				"reforged: paid, and a new prefix (%s)" % Data.item_of(hud._reforge_inv.slots[0]).name)
		var poor := p.inventory.money()
		p.inventory.pay(poor)
		check(not hud.reforge(), "without the money, nothing happens")
		var pre := int(hud._reforge_inv.slots[0].prefix)
		hud.close_inventory()
		check(not hud.reforge_open and hud.chat_npc == null and p.inventory.slots.any(func(s): return s != null and s.item == "PlatinumBroadsword" and int(s.get("prefix", 0)) == pre),
				"closing, the item comes back to your inventory")
	# Saving with something on the cursor (or in the reforge slot) keeps it.
	hud._open_inventory()
	p.inventory.slots.fill(null)
	hud._cursor_stack = Inventory.stack("HermesBoots", 1, 65)
	hud._reforge_inv.slots[0] = Inventory.stack("Spear", 1, 59)
	hud.stow_temporary_items()
	check(hud._cursor_stack == null and hud._reforge_inv.slots[0] == null and p.inventory.count_of("HermesBoots") == 1 and p.inventory.count_of("Spear") == 1,
			"saving, what's on the cursor or in the reforge slot goes into your inventory")
	hud.close_inventory()
	p.inventory.slots = kept_slots
	p.inventory.changed.emit()
	p.select(held)
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	await frames(5)


## The accessories added after the first ones: where they come from (drops,
## chests by depth), the informational ones in your inventory, wall sliding
## and jumping, wings, the Lava Charm, the Diving Helmet, the Jellyfish
## Necklace's light and the Guide to Plant Fiber Cordage.
func _accessory_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var added := ["Aglet", "ClimbingClaws", "ShoeSpikes", "LavaCharm", "Shackle", "JellyfishNecklace", "CordageGuide", "Magiluminescence", "CreativeWings",
			"CopperWatch", "TinWatch", "SilverWatch", "TungstenWatch", "GoldWatch", "PlatinumWatch", "DepthMeter", "Compass", "Radar", "DivingHelmet"]
	check(added.all(func(n): return not Data.item(n).is_empty()), "the new accessories are items")
	var drops := func(npc: String, item: String) -> bool: return Data.npcs[npc].drops.any(func(d): return d[0] == item)
	check(drops.call("CaveBat", "DepthMeter") and drops.call("Piranha", "Compass") and drops.call("Zombie", "Shackle") and drops.call("Shark", "DivingHelmet") and drops.call("PinkJellyfish", "JellyfishNecklace"),
			"drops: bats the Depth Meter, Piranhas the Compass, Zombies the Shackle, Sharks the Diving Helmet, Jellyfish the Jellyfish Necklace")
	check(Data.recipes.any(func(r): return r.result == "CopperWatch" and r.ingredients.get("CopperBar") == 10 and r.ingredients.get("Chain") == 1)
			and Data.recipes.any(func(r): return r.result == "Magiluminescence" and r.ingredients.get("Topaz") == 5), "recipes: watches (10 bars and a Chain), Magiluminescence")
	# Chests by depth: near the surface Terraria's surface loot.
	var surface_items := ["Spear", "WoodenBoomerang", "Aglet", "ClimbingClaws", "Umbrella", "CordageGuide", "Radar"]
	var top := Vector3i(c.x + 3, TestWorld.GROUND + 1, c.z + 60)
	var all_surface := true
	for i in 12:
		game.chests._worldgen[Chests.key(top)] = true
		game.chests._tables[Chests.key(top)] = "chest"
		game.chests._chests.erase(Chests.key(top))
		all_surface = all_surface and game.chests.get_inventory(top).slots.any(func(s): return s != null and s.item in surface_items)
	game.chests._chests.erase(Chests.key(top))
	check(all_surface, "a chest near the surface rolls Terraria's surface loot (Aglet, Climbing Claws, Radar...)")
	var lava_charms := [0, 0]
	for i in 600:
		for k in 2:
			if Game.roll_loot("chest", k == 1).any(func(d): return d[0] == "LavaCharm"):
				lava_charms[k] += 1
	check(lava_charms[0] == 0 and lava_charms[1] > 10, "Lava Charms only in chests below the lava line (%s of 600)" % [lava_charms])
	check(Data.loot.chest.pick_one.any(func(e): return e[0] == "ShoeSpikes") and Data.loot.sky_chest.extras.any(func(e): return e[0] == "CreativeWings"),
			"Shoe Spikes in underground chests, Fledgling Wings in sky chests")

	# Informational accessories: anywhere in the inventory.
	var held := p.selected
	var free_slot := 30
	check(game.hud._clock.text == "" and game.hud.info_text() == "", "no watch, no Depth Meter: no time or depth")
	p.inventory.slots[free_slot] = Inventory.stack("CopperWatch", 1)
	await frames(2)
	check(game.hud._clock.text.ends_with("M") and game.hud._clock.text.contains(":00 "), "a Copper Watch tells the hour (%s)" % game.hud._clock.text)
	p.inventory.slots[free_slot] = Inventory.stack("GoldWatch", 1)
	await frames(2)
	check(game.hud._clock.text == game.sky.clock_text(3), "a Gold Watch, to the minute (%s)" % game.hud._clock.text)
	p.inventory.slots[free_slot] = Inventory.stack("DepthMeter", 1)
	p.inventory.slots[free_slot + 1] = Inventory.stack("Compass", 1)
	p.inventory.slots[free_slot + 2] = Inventory.stack("Radar", 1)
	await frames(2)
	var lines := game.hud.info_text().split("\n")
	check(lines.size() == 3 and (lines[0].ends_with(" Surface") or lines[0].ends_with(" Underground")) and (lines[1].contains("East") or lines[1].contains("West") or lines[1] == "Center")
			and lines[2].contains("nearby"), "Depth Meter, Compass and Radar, Terraria's way (%s)" % [lines])
	for k in 3:
		p.inventory.slots[free_slot + k] = null
	p.accessories.slots[0] = Inventory.stack("Aglet", 1)
	check(is_equal_approx(p.stat("move_speed"), 5.0), "the Aglet: 5% movement speed")

	# Wall sliding on the arena's south wall (from inside), facing it.
	var god := p.god_mode
	p.god_mode = true
	var wall_z := c.z + 17
	var x := c.x + 37
	p.accessories.slots[0] = Inventory.stack("ClimbingClaws", 1)
	p.look_at_yaw_pitch(PI, 0.0)
	p.global_position = Vector3(x + 0.5, TestWorld.GROUND + 4.5, wall_z - 0.31)
	p.velocity = Vector3(0, -6, 0)
	Input.action_press("move_forward")
	await frames(6)
	check(p.sliding and is_equal_approx(p.velocity.y, -Player.WALL_SLIDE), "Climbing Claws: pressing into a wall in the air slides down it slowly (%.2f)" % p.velocity.y)
	p.accessories.slots[1] = Inventory.stack("ShoeSpikes", 1)
	var y0 := p.global_position.y
	await frames(20)
	check(p.sliding and absf(p.global_position.y - y0) < 0.05, "with Shoe Spikes too, you stick (moved %.2f)" % (p.global_position.y - y0))
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	Input.action_release("move_forward")
	check(p.velocity.y > 5.0 and p.velocity.z < -3.0, "jumping off the wall: up and away from it (%s)" % p.velocity)
	await frames(90)
	p.accessories.slots[0] = null
	p.accessories.slots[1] = null

	# Fledgling Wings: flight after the jump, then a slow glide.
	p.global_position = Vector3(c.x + 0.5, TestWorld.GROUND + 1, c.z + 30.5)
	p.velocity = Vector3.ZERO
	await frames(10)
	var climb := func() -> float:
		var start := p.global_position.y
		var best := start
		Input.action_press("jump")
		for i in 60:
			await frames(1)
			best = maxf(best, p.global_position.y)
		Input.action_release("jump")
		await frames(90)
		return best - start
	var plain: float = await climb.call()
	p.accessories.slots[0] = Inventory.stack("CreativeWings", 1)
	var winged: float = await climb.call()
	check(winged > plain + 0.5, "Fledgling Wings fly you higher (%.1f blocks, %.1f without)" % [winged, plain])
	p.global_position = Vector3(c.x + 0.5, TestWorld.GROUND + 30, c.z + 30.5)
	p.velocity = Vector3.ZERO
	await frames(3)
	p._wing_time = 0.0
	Input.action_press("jump")
	await frames(60)
	check(absf(p.velocity.y + Player.MAX_FALL / 3.0) < 0.01, "out of flight, holding jump glides down at a third of the fall speed (%.2f)" % p.velocity.y)
	Input.action_release("jump")
	p.accessories.slots[0] = null
	await frames(90)

	# The Lava Charm: 7 s of lava immunity, its flames on the breath meter.
	p.god_mode = false
	p.accessories.slots[0] = Inventory.stack("LavaCharm", 1)
	p.lava_time = 0.0
	await frames(60)
	check(absf(p.lava_time - 1.0) < 0.1, "out of lava it fills a second a second (%.2f)" % p.lava_time)
	p.lava_time = 7.0
	var life0 := p.life
	p.global_position = Vector3(c + Vector3i(-23, -1, 10)) + Vector3(0.5, 0.1, 0.5)
	p.velocity = Vector3.ZERO
	await frames(120)
	check(p.in_liquid == Player.LIQ_LAVA and p.life == life0 and p.lava_time < 5.5 and p.lava_time > 4.5, "in lava it doesn't hurt while the charm lasts (life %d, %.1f s left)" % [p.life, p.lava_time])
	check(game.hud._bubbles.get_child_count() > 0 and game.hud._bubbles.get_child(0).texture == Assets.texture("Images/Flame"), "its flames show on the breath meter")
	p.god_mode = true
	p.on_fire = 0.0
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(30)
	p.life = p.life_max

	# Diving Helmet: six times the breath. Jellyfish Necklace: light, more under water.
	p.accessories.slots[0] = Inventory.stack("JellyfishNecklace", 1)
	var dry := p.carried_light()
	p.armor.slots[0] = Inventory.stack("DivingHelmet", 1)
	p.god_mode = false
	p.global_position = Vector3(c + Vector3i(-20, -6, -3)) + Vector3(0.5, 0.1, 0.5)
	p.velocity = Vector3.ZERO
	p.breath = Player.BREATH_MAX
	await frames(120)
	var used := Player.BREATH_MAX - p.breath
	check(p.head_liquid == Player.LIQ_WATER and absf(used - 2.0 / 6.0) < 0.05, "the Diving Helmet: breath goes six times slower (%.2f s in 2 s)" % used)
	check(dry.r > 0.0 and p.carried_light().r > dry.r, "the Jellyfish Necklace glows, brighter under water")
	p.god_mode = true
	p.armor.slots[0] = null
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(30)

	# The Guide to Plant Fiber Cordage: vines drop Vine Rope half the time.
	p.accessories.slots[0] = Inventory.stack("CordageGuide", 1)
	var ledge := Vector3i(c.x + 4, TestWorld.GROUND + 8, c.z + 30)
	w.set_block(ledge, Data.block_id("stone"))
	for i in 40:
		w.set_block(ledge + Vector3i.DOWN, Data.block_id("vines"))
		game.break_block(ledge + Vector3i.DOWN)
	var ropes := 0
	for e in game.entities.get_children():
		if e is ItemDrop and e.item == "VineRope":
			ropes += e.count
			e.queue_free()
	check(ropes > 8 and ropes < 32, "with the Guide to Plant Fiber Cordage, vines drop Vine Rope about half the time (%d of 40)" % ropes)
	w.set_block(ledge, 0)
	p.accessories.slots[0] = Inventory.stack("Magiluminescence", 1)
	check(p.carried_light().r > 0.8 and p.has_effect("magiluminescence"), "Magiluminescence shines")
	# The tooltip over the equipment (at the window's right edge) stays in the
	# window, at UI scale 1 and 2.
	var hud := game.hud
	var scale0 = Settings.get_value("ui_scale")
	var inside := true
	hud._open_inventory()
	for ui in [1.0, 2.0]:
		Settings.set_value("ui_scale", ui)
		await frames(2)
		for slot in [hud._accessory_slots[4], hud._armor_slots[0], hud._hook_slot]:
			hud.show_tooltip(Inventory.stack("Magiluminescence", 1), slot)
			await frames(1)
			# A 1600 x 900 window (headless runs have a tiny one): the slot's
			# place from the right edge, the mouse on it, in the HUD's units.
			var area: Vector2 = Vector2(1600, 900) / float(ui)
			var mouse := Vector2(area.x + slot.offset_left + slot.size.x * 0.5, slot.offset_top + slot.size.y * 0.5)
			var r := Rect2(Hud.tooltip_position(mouse, hud._tooltip.size, area), hud._tooltip.size)
			inside = inside and r.position.x >= 0.0 and r.end.x <= area.x + 0.5 and r.end.y <= area.y + 0.5 and r.size.x > 100.0 and not r.has_point(mouse)
	hud.hide_tooltip()
	hud.close_inventory()
	Settings.set_value("ui_scale", scale0)
	check(inside, "the tooltip over equipped items and armor stays inside the window (UI scale 1 and 2)")
	check(Hud.tooltip_position(Vector2(1580, 100), Vector2(300, 120), Vector2(1600, 900)).x == 1580 - 300 - 10, "near the right edge it flips to the left of the mouse")
	p.accessories.slots[0] = null
	p.select(held)
	p.god_mode = god
	await frames(5)


## Grappling hooks, at the arena's south wall (from inside): where they come from, latching
## on and pulling you over, hanging, jumping off, single hooks letting go of
## the last, the Ivy Whip's three (a fourth drops the oldest), coming back
## when nothing's in reach, and the Grapple key.
func _hook_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	check(Data.recipes.any(func(r): return r.result == "GrapplingHook" and r.ingredients.get("Hook") == 1 and r.ingredients.get("Chain") == 3)
			and Data.recipes.any(func(r): return r.result == "DiamondHook" and r.ingredients.get("Diamond") == 15)
			and Data.recipes.any(func(r): return r.result == "IvyWhip" and r.ingredients.get("JungleSpores") == 12 and r.ingredients.get("Vine") == 3),
			"recipes: a Hook and 3 Chain make a Grappling Hook, 15 gems a gem hook, 12 Jungle Spores and 3 Vines an Ivy Whip")
	check(Data.npcs.Skeleton.drops.any(func(d): return d[0] == "Hook" and is_equal_approx(d[3], 0.04)) and Data.npcs.KingSlime.drops.any(func(d): return d[0] == "SlimeHook")
			and Data.npcs.SkeletronHead.drops_chain.any(func(d): return d[0] == "SkeletronHand") and not Data.item("SkeletronHand").is_empty(),
			"Skeletons drop Hooks (1 in 25), King Slime the Slime Hook, Skeletron his Hand")
	var god := p.god_mode
	p.god_mode = true
	var held := p.selected
	var wall_z := c.z + 17
	var x := c.x + 37
	var fire := func(item: String, yaw: float, pitch: float) -> void:
		p.inventory.slots[p.selected] = Inventory.stack(item, 1)
		p.look_at_yaw_pitch(yaw, pitch)
		p.fire_hook(Data.item(item))
	var mine := func() -> Array: return p.hooks()
	p.global_position = Vector3(x + 0.5, TestWorld.GROUND + 1, c.z + 11.5)
	p.velocity = Vector3.ZERO
	await frames(10)
	fire.call("GrapplingHook", PI, 0.3)
	await frames(15)
	check(mine.call().size() == 1 and mine.call()[0].latched() and mine.call()[0].cell.z == wall_z, "the Grappling Hook flies to the wall and latches on")
	await frames(45)
	check(p.global_position.z > wall_z - 1.0 and p.global_position.y > TestWorld.GROUND + 2.5 and not p.on_floor,
			"it pulls you over to it, off the ground (feet %.1f up, %.2f from the wall)" % [p.global_position.y - TestWorld.GROUND - 1, wall_z - p.global_position.z])
	await frames(30)
	var y0 := p.global_position.y
	check(absf(p.global_position.y - y0) < 0.01 and p.velocity.length() < Player.GRAPPLE_STILL, "and you hang there")
	# Single hooks: throwing again lets go of the first.
	var first: GrappleHook = mine.call()[0]
	fire.call("GrapplingHook", PI + 0.5, 0.2)
	await frames(2)
	check(not is_instance_valid(first) or first.is_queued_for_deletion(), "throwing a single hook again lets go of the last one")
	await frames(30)
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	check(mine.call().is_empty() and p.velocity.y > 5.0, "jump lets go, with a jump")
	await frames(60)

	# The Ivy Whip: three latched at once; a fourth drops the oldest.
	p.global_position = Vector3(x + 0.5, TestWorld.GROUND + 1, c.z + 11.5)
	p.velocity = Vector3.ZERO
	await frames(5)
	for yaw in [PI - 0.15, PI, PI + 0.15]:
		fire.call("IvyWhip", yaw, 0.35)
		await frames(3)
	await frames(20)
	check(mine.call().size() == 3 and mine.call().all(func(h): return h.latched()), "the Ivy Whip holds on with three hooks (%d)" % mine.call().size())
	var oldest: GrappleHook = mine.call()[0]
	for h in mine.call():
		if h.born < oldest.born:
			oldest = h
	p.look_at_yaw_pitch(PI, 0.6)
	p.fire_hook(Data.item("IvyWhip"))
	await frames(20)
	check(mine.call().size() == 3 and (not is_instance_valid(oldest) or oldest.is_queued_for_deletion()), "a fourth latching lets go of the oldest")
	for h in mine.call():
		h.queue_free()
	await frames(30)
	p.global_position = Vector3(x + 0.5, TestWorld.GROUND + 1, c.z + 6.5)
	p.velocity = Vector3.ZERO
	await frames(30)

	# Out of reach (straight up into the sky), it comes back and goes.
	fire.call("AmethystHook", 0.0, 1.5)
	await frames(10)
	var h: GrappleHook = mine.call()[0] if not mine.call().is_empty() else null
	check(h != null and h.state == GrappleHook.FLYING, "a hook flies up")
	await frames(30)
	check(h != null and (not is_instance_valid(h) or h.state == GrappleHook.RETRACTING), "past its reach (12.5 blocks) it comes back")
	await frames(90)
	check(mine.call().is_empty(), "and goes once it's back")
	# The Grapple key, no hook slot: the first hook in the inventory, whatever you hold.
	p.inventory.slots[p.selected] = Inventory.stack("PlatinumBroadsword", 1)
	p.inventory.slots[25] = Inventory.stack("SkeletronHand", 1)
	p.look_at_yaw_pitch(PI, 0.3)
	p.global_position = Vector3(x + 0.5, TestWorld.GROUND + 1, c.z + 11.5)
	await key(KEY_E)
	check(mine.call().size() == 1 and mine.call()[0].def.projectile == 256, "the Grapple key (E) throws the first hook in the inventory")
	await frames(20)
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(60)
	# The hook slot: right-click puts a hook there; it takes only hooks, the
	# Grapple key throws it before any in the inventory, and it's saved.
	var hud := game.hud
	hud._open_inventory()
	await frames(2)
	check(hud._hook_slot.visible and hud._hook_slot.inventory == p.hook_slot, "the inventory shows the hook slot")
	p.inventory.slots[26] = Inventory.stack("RubyHook", 1)
	hud.slot_clicked(hud._slots[26], MOUSE_BUTTON_RIGHT)
	check(p.hook_slot.slots[0] != null and p.hook_slot.slots[0].item == "RubyHook" and p.inventory.slots[26] == null, "right-clicking a hook puts it in the hook slot")
	check(Hud.slot_accepts("hook", "IvyWhip") and not Hud.slot_accepts("hook", "HermesBoots") and not Hud.slot_accepts("accessory", "IvyWhip"), "the hook slot takes only hooks")
	hud.close_inventory()
	await key(KEY_E)
	check(mine.call().size() == 1 and mine.call()[0].def.projectile == 234, "the Grapple key throws the hook in the hook slot first (the Ruby Hook, not the Skeletron Hand)")
	for k in mine.call():
		k.queue_free()
	var saved: Dictionary = p.save_state()
	p.hook_slot.slots[0] = null
	p.load_state(saved)
	check(p.hook_slot.slots[0] != null and p.hook_slot.slots[0].item == "RubyHook", "the hook slot is saved with you")
	p.hook_slot.slots[0] = null
	await frames(30)
	p.inventory.slots[25] = null
	p.select(held)
	p.god_mode = god
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(10)


## Ropes and chains (the tower's north wall): where they come from, climbing
## up, hanging on, sliding down, letting go, leaping off at the top,
## placing more on a rope and throwing Rope Coils.
func _rope_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var has_recipe := func(result: String, count: int, ingredient: String) -> bool:
		return Data.recipes.any(func(r): return r.result == result and r.count == count and r.ingredients.keys().any(func(k): return ingredient in k.split("|")))
	check(has_recipe.call("RopeCoil", 1, "Rope") and has_recipe.call("WebRope", 3, "Cobweb") and has_recipe.call("SilkRope", 30, "Silk") and has_recipe.call("Chain", 15, "IronBar"),
			"recipes: 10 Rope make a Rope Coil, a Cobweb 3 Web Rope, a Silk 30 Silk Rope, an Iron Bar 15 Chain")
	check("Rope" in Data.npcs.Merchant.town.shop and Data.item("Rope").value == 10, "the Merchant sells Rope for 10 copper")
	check(Data.loot.pot.pick_one.any(func(e): return e[0] == "Rope") and Data.loot.chest.extras.any(func(e): return e[0] == "Rope" and e[1] == 50 and e[2] == 100),
			"pots give 20-40 Rope, chests 50-100")
	var x0 := c.x + 14
	var col := Vector3i(x0 + 26, 0, c.z + 19)  # the rope (the chain is 2 east)
	var top := TestWorld.GROUND + 25
	check(Data.block(w.get_block(Vector3i(col.x, top, col.z))).get("rope", false) and Data.block(w.get_block(Vector3i(col.x + 2, top - 10, col.z))).get("name") == "chain",
			"a rope and a chain hang down the tower")
	var god := p.god_mode
	p.god_mode = true
	p.look_at_yaw_pitch(PI, 0.0)  # facing south, at the wall
	p.global_position = Vector3(col.x + 0.5, TestWorld.GROUND + 1, col.z + 0.2)
	p.velocity = Vector3.ZERO
	await frames(10)
	Input.action_press("jump")
	await frames(30)
	check(p.on_rope and p.global_position.y > TestWorld.GROUND + 2.0 and p.velocity.y > 5.0, "jump grabs the rope and climbs it (%.1f up, %.1f blocks/s)" % [p.global_position.y - TestWorld.GROUND - 1, p.velocity.y])
	await frames(240)
	# The hand stops a tile under the top of the rope: feet 1.47 under its top cell.
	check(p.on_rope and absf(p.global_position.y - (top - 1.47)) < 0.1 and p.velocity.y == 0.0, "up to the top of it, no further (feet %.2f, top %d)" % [p.global_position.y, top])
	check(absf(Vector2(p.global_position.x - col.x - 0.5, p.global_position.z - col.z - 0.5).length() - Player.ROPE_HANG) < 0.05, "hanging just beside it")
	Input.action_release("jump")
	await frames(20)
	var y0 := p.global_position.y
	check(p.on_rope and p.velocity.y == 0.0, "let go of jump: you hang on")
	Input.action_press("drop_down")
	await frames(30)
	Input.action_release("drop_down")
	check(p.on_rope and p.global_position.y < y0 - 2.0, "Drop down slides down it (%.1f down)" % (y0 - p.global_position.y))
	await frames(20)
	# Leaping off at the top onto the tower's platform: hold jump, move south.
	Input.action_press("jump")
	await frames(120)
	Input.action_press("move_forward")
	await frames(2)
	check(not p.on_rope and p.velocity.y > 5.0, "moving while you climb leaps off")
	for i in 90:
		await frames(1)
		if p.on_floor:
			break
	Input.action_release("move_forward")
	Input.action_release("jump")
	await frames(30)
	check(p.on_floor and absf(p.global_position.y - (top + 1)) < 0.05, "onto the platform at the top (y %.2f)" % p.global_position.y)
	# Tapping sideways lets go.
	p.global_position = Vector3(col.x + 0.5, TestWorld.GROUND + 8, col.z + 0.2)
	p.velocity = Vector3.ZERO
	Input.action_press("drop_down")
	await frames(3)
	Input.action_release("drop_down")
	await frames(5)
	check(p.on_rope, "Drop down grabs it too")
	Input.action_press("move_left")
	await frames(2)
	Input.action_release("move_left")
	await frames(20)
	check(not p.on_rope and p.global_position.y < TestWorld.GROUND + 7.5, "a tap sideways lets go (y %.1f)" % p.global_position.y)
	await frames(60)

	# Placing: on a wall in mid-air, then more on it go under its bottom.
	var wall := Vector3i(x0 + 27, TestWorld.GROUND + 12, c.z + 20)
	var hang := wall + Vector3i(0, 0, -1)
	p.global_position = Vector3(hang.x + 0.5, TestWorld.GROUND + 1, hang.z - 2.5)
	p.inventory.slots[p.selected] = Inventory.stack("Rope", 10)
	p.target = {"block": wall, "normal": Vector3i(0, 0, -1), "id": w.get_block(wall), "distance": 3.0}
	check(p._place(Data.item("Rope")) and Data.block(w.get_block(hang)).get("name") == "rope", "Rope goes on the side of a block")
	for i in 3:
		p.target = {"block": hang, "normal": Vector3i(0, 0, -1), "id": w.get_block(hang), "distance": 3.0}
		p._place(Data.item("Rope"))
	var line := range(4).all(func(k): return Data.block(w.get_block(hang - Vector3i(0, k, 0))).get("name") == "rope")
	check(line and p.inventory.slots[p.selected].count == 6, "placing on it adds to the bottom (4 down, 6 left)")
	for k in 4:
		w.set_block(hang - Vector3i(0, k, 0), 0)

	# Rope Coils: thrown up under the tower's platform, each lays 10 down from
	# where it hit (past rope already there); the last one runs out of room.
	var under := Vector3i(x0 + 26, 0, c.z + 21)
	var coil_at := func(y: float) -> void:
		var rc := RopeCoil.new()
		rc.setup("RopeCoil", Data.item("RopeCoil").rope_coil)
		rc.velocity = Vector3(0, RopeCoil.SPEED, 0)
		game.entities.add_child(rc)
		rc.global_position = Vector3(under.x + 0.5, y, under.z + 0.5)
	var ropes_under := func() -> int:
		var n := 0
		for y in range(TestWorld.GROUND + 1, top):
			if Data.block(w.get_block(Vector3i(under.x, y, under.z))).get("name") == "rope":
				n += 1
		return n
	coil_at.call(TestWorld.GROUND + 15.5)
	await frames(30)
	check(ropes_under.call() == 10 and Data.block(w.get_block(Vector3i(under.x, top - 1, under.z))).get("rope", false), "a Rope Coil hits the ceiling and lays 10 rope down from it")
	coil_at.call(TestWorld.GROUND + 10.5)
	await frames(90)
	check(ropes_under.call() == 20, "the next goes on below the first (%d)" % ropes_under.call())
	coil_at.call(TestWorld.GROUND + 10.5)
	await frames(90)
	# (Only the ones by the tower: a pot broken earlier may have left Rope about.)
	var near_tower := func(e) -> bool: return e is ItemDrop and e.item == "Rope" and Vector2(e.global_position.x - under.x, e.global_position.z - under.z).length() < 6.0
	var drops := game.entities.get_children().filter(near_tower)
	check(ropes_under.call() == 24 and drops.size() == 1 and drops[0].count == 6, "the third has room for 4: the other 6 drop as Rope (%d, %s)" % [ropes_under.call(), drops.map(func(d): return d.count)])
	coil_at.call(TestWorld.GROUND + 10.5)
	await frames(90)
	check(game.entities.get_children().any(func(e): return e is ItemDrop and e.item == "RopeCoil"), "with no room at all it drops back as a coil")
	for e in game.entities.get_children():
		if e is ItemDrop:
			e.queue_free()
	for y in range(TestWorld.GROUND + 1, top):
		w.set_block(Vector3i(under.x, y, under.z), 0)
	# Throwing one.
	p.inventory.slots[p.selected] = Inventory.stack("RopeCoil", 2)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	check(game.entities.get_children().any(func(e): return e is RopeCoil) and p.inventory.slots[p.selected].count == 1, "using a Rope Coil throws it")
	for e in game.entities.get_children():
		if e is RopeCoil:
			e.queue_free()
	p.inventory.slots[p.selected] = null
	p.god_mode = god
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(10)


## Platforms: stand on them, drop through with Drop down, climb a platform
## stair, place them off another platform in mid-air, craft them.
func _platform_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var a := c + TestWorld.PLATFORMS
	var floor_cell := a + Vector3i(6, 3, 0)
	check(Data.block(w.get_block(floor_cell)).get("name", "") == "wood_platform" and not w.is_solid(floor_cell), "the platform floor is there, and not solid")
	check(Data.recipes.any(func(r): return r.result == "WoodPlatform" and r.count == 2 and r.ingredients.has("Wood")), "1 Wood makes 2 Wood Platforms")
	var god := p.god_mode
	p.god_mode = true
	p.velocity = Vector3.ZERO
	p.global_position = Vector3(floor_cell) + Vector3(0.5, 2.5, 0.5)
	await frames(60)
	check(absf(p.global_position.y - (floor_cell.y + 1)) < 0.05 and p.on_floor, "you land and stand on a platform (y %.2f)" % p.global_position.y)
	Input.action_press("drop_down")
	await frames(45)
	Input.action_release("drop_down")
	check(p.global_position.y < floor_cell.y - 1.5, "Drop down falls through it (y %.2f)" % p.global_position.y)
	# Jumping from under one (the stair's second step, 2 up) goes up through it
	# and lands on top.
	var step := a + Vector3i(1, 1, 0)
	p.global_position = Vector3(step.x + 0.5, a.y, step.z + 0.5)
	p.velocity = Vector3.ZERO
	await frames(10)
	Input.action_press("jump")
	await frames(30)
	Input.action_release("jump")
	await frames(60)
	check(absf(p.global_position.y - (step.y + 1)) < 0.05, "jumping up through a platform lands on top (y %.2f, top %d)" % [p.global_position.y, step.y + 1])
	# Walking up the platform stair.
	p.global_position = Vector3(a) + Vector3(-1.5, 0.0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(10)
	var climbed := 0.0
	for i in 120:
		p.velocity.x = 3.0
		await frames(1)
		climbed = maxf(climbed, p.global_position.y - a.y)
	check(climbed >= 3.9, "walking up a platform stair climbs it (%.1f blocks)" % climbed)
	# Placing one off the side of another, in mid-air.
	var edge := a + Vector3i(10, 3, 0)
	p.inventory.slots[p.selected] = Inventory.stack("WoodPlatform", 10)
	p.target = {"block": edge - Vector3i(1, 0, 0), "normal": Vector3i(1, 0, 0), "id": w.get_block(edge - Vector3i(1, 0, 0)), "distance": 3.0}
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	check(p._place(Data.item("WoodPlatform")) and Data.block(w.get_block(edge)).get("name", "") == "wood_platform", "a platform goes off the side of another in mid-air")
	# A torch stands on a platform; breaking the block under a platform leaves it.
	p.inventory.slots[p.selected] = Inventory.stack("Torch", 10)
	p.target = {"block": edge, "normal": Vector3i.UP, "id": w.get_block(edge), "distance": 3.0}
	check(p._place(Data.item("Torch")) and Data.block(w.get_block(edge + Vector3i.UP)).get("name", "") == "torch", "a torch stands on a platform")
	var low := a + Vector3i(1, 1, 0)
	w.set_block(low + Vector3i.DOWN, Data.block_id("dirt"))
	game.break_block(low + Vector3i.DOWN, false)
	check(Data.block(w.get_block(low)).get("name", "") == "wood_platform", "a platform stays when the block under it is mined")
	p.god_mode = god
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	await frames(5)


func last_message() -> String:
	var box: Node = game.hud._messages
	return box.get_child(box.get_child_count() - 1).text if box.get_child_count() > 0 else ""


## Furniture: the house's pieces, the bed's spawn point, the clock, the barrel,
## standing on a table, cobwebs, and the Sawmill -> Loom -> Silk -> Bed chain.
func _furniture_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var a := c + TestWorld.HOUSE
	var names := {}
	for x in 9:
		for z in 7:
			for y in 5:
				var d := Data.block(w.get_block(a + Vector3i(x, y, z)))
				# A town NPC may be walking out through the door: open, it's still the door.
				names[d.door_closed if Doors.is_open(d) else d.get("name", "")] = true
	var want := ["wooden_table", "candle", "wooden_chair", "bed", "grandfather_clock", "barrel", "sawmill", "loom", "copper_chandelier", "wooden_door"]
	check(want.all(func(n): return names.has(n)), "the house has its furniture (missing %s)" % [want.filter(func(n): return not names.has(n))])
	check(w.get_light(Vector3(a) + Vector3(4.5, 2.5, 3.5)).r > 0.4, "the chandelier and candle light the house (%s)" % w.get_light(Vector3(a) + Vector3(4.5, 2.5, 3.5)))
	# The bed: right-click sets the spawn point, again clears it; you come back there.
	var bed := a + Vector3i(6, 0, 1)
	p.target = {"block": bed, "normal": Vector3i.UP, "id": w.get_block(bed), "distance": 2.0}
	p._interact()
	check(p.bed == bed and last_message() == "Spawn point set!", "right-clicking a bed sets your spawn point")
	check(p.respawn_point().distance_to(Vector3(bed) + Vector3(0.5, 0, 0.5)) < 0.01, "you respawn at your bed")
	check(p.save_state().bed == [bed.x, bed.y, bed.z], "the bed is saved with the player")
	p._interact()
	check(p.bed == Player.NO_BED and last_message() == "Spawn point removed!", "right-clicking it again clears it")
	p._interact()
	game.break_block(bed, false)
	check(p.respawn_point() == p.spawn_point and p.bed == Player.NO_BED and last_message() == "Your bed has been destroyed.",
			"with the bed gone you respawn at the world spawn")
	w.set_block(bed, Data.block_id("bed"))
	# The clock tells the time.
	var clock := a + Vector3i(1, 0, 5)
	p.target = {"block": clock, "normal": Vector3i.UP, "id": w.get_block(clock), "distance": 2.0}
	p._interact()
	check(last_message() == "Current time: " + game.sky.clock_text(), "the grandfather clock tells the time (%s)" % last_message())
	# The barrel is a container.
	var barrel := a + Vector3i(7, 0, 5)
	p.target = {"block": barrel, "normal": Vector3i.UP, "id": w.get_block(barrel), "distance": 2.0}
	p._interact()
	await frames(2)
	check(game.hud._chest_panel.visible and game.hud._chest == game.chests.get_inventory(barrel), "a barrel opens like a chest")
	game.hud.close_inventory()
	# Standing on the table (solid on top, like Terraria's).
	var god := p.god_mode
	p.god_mode = true
	var table := a + Vector3i(2, 0, 1)
	w.set_block(table + Vector3i.UP, 0)
	p.global_position = Vector3(table) + Vector3(0.5, 2.0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(40)
	check(absf(p.global_position.y - (table.y + 1)) < 0.05, "you can stand on a table (y %.2f)" % p.global_position.y)
	w.set_block(table + Vector3i.UP, Data.block_id("candle"))
	# Cobwebs slow you down, and drop Cobweb.
	var web := Vector3i(c.x, TestWorld.GROUND + 1, c.z + 4)
	p.global_position = Vector3(c) + Vector3(0.5, 0, 6.5)
	await frames(5)
	for k in 2:
		w.set_block(web + Vector3i(0, k, 0), Data.block_id("cobweb"))
	p.global_position = Vector3(web) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	var start := p.global_position
	for i in 30:
		p.velocity.x = 0.0
		Input.action_press("move_right")
		await frames(1)
	Input.action_release("move_right")
	var crawled := p.global_position.distance_to(start)
	check(p.touching("sticky") or crawled < 1.0, "a cobweb slows you to a crawl (%.2f m in half a second)" % crawled)
	p.global_position = Vector3(web) + Vector3(0.5, 0, 12.5)  # (out of pickup reach)
	await frames(2)
	var drops := game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "Cobweb").size()
	game.break_block(web)
	check(game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "Cobweb").size() == drops + 1, "cobwebs drop Cobweb")
	check(Data.block(w.get_block(web + Vector3i.UP)).get("name", "") == "cobweb", "a cobweb stays when the one under it goes")
	game.break_block(web + Vector3i.UP, false)
	check(Data.block(w.get_block(c + Vector3i(-25, 4, -25))).get("name", "") == "cobweb", "cobwebs hang in the dark room's corners")
	p.god_mode = god
	# The crafting chain: Sawmill (work bench), Loom (sawmill), Silk (loom), Bed (sawmill).
	var chain := {"Sawmill": "work_bench", "Loom": "sawmill", "Silk": "loom", "Bed": "sawmill", "Barrel": "sawmill", "GrandfatherClock": "sawmill", "Glass": "furnace"}
	var ok := true
	for item in chain:
		ok = ok and Data.recipes.any(func(r): return r.result == item and r.get("station", "") == chain[item])
	check(ok and Data.recipes.any(func(r): return r.result == "Bed" and r.ingredients.get("Silk", 0) == 5), "the Sawmill -> Loom -> Silk -> Bed recipes")
	check(Data.block(Data.block_id("sawmill")).get("station", false) and Data.block(Data.block_id("loom")).get("station", false), "the sawmill and loom are crafting stations")
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	await frames(5)


## The hammer reshapes blocks like Terraria's: half block, ramp (rising away
## from you), upside-down ramp, whole again. You stand on and walk up them.
func _hammer_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var stone := Data.block_id("stone")
	var b := c + Vector3i(-4, 0, 12)  # on the ground south-west of spawn
	for x in range(-1, 4):
		for y in range(0, 3):
			w.set_block(b + Vector3i(x, y, 0), 0)
	w.set_block(b, stone)
	var held = p.inventory.slots[p.selected]
	p.inventory.slots[p.selected] = Inventory.stack("PlatinumHammer", 1)
	# Facing +x (east): ramps rise toward +x (direction 1).
	p.global_position = Vector3(b) + Vector3(-1.5, 0, 0.5)
	p.look_at_yaw_pitch(-PI * 0.5, -0.4)
	check(p.facing_dir() == 1, "facing east (%d)" % p.facing_dir())
	var seq := []
	for i in 4:
		p.target = {"block": b, "normal": Vector3i(-1, 0, 0), "id": stone, "distance": 1.5}
		p._hammer(Data.item("PlatinumHammer"))
		seq.append(w.get_shape(b))
	check(seq == [Game.SHAPE_HALF, Game.SHAPE_RAMP + 1, Game.SHAPE_CEILING + 1, Game.SHAPE_FULL],
			"hammering cycles half block -> ramp -> upside-down ramp -> whole (%s)" % [seq])
	# Stand on a half block.
	var god := p.god_mode
	p.god_mode = true
	p.target = {"block": b, "normal": Vector3i.UP, "id": stone, "distance": 1.5}
	p._hammer(Data.item("PlatinumHammer"))
	await frames(3)
	p.global_position = Vector3(b) + Vector3(0.5, 2.0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(40)
	check(absf(p.global_position.y - (b.y + 0.5)) < 0.01, "you stand on a half block (y %.3f)" % p.global_position.y)
	# Walk up a ramp onto a block behind it.
	var r := b + Vector3i(2, 0, 0)
	w.set_block(r, stone)
	w.set_block(r + Vector3i(1, 0, 0), stone)
	check(w.set_shape(r, Game.SHAPE_RAMP + 1), "a ramp rising east")
	p.global_position = Vector3(r) + Vector3(-0.6, 0.0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(5)
	p.look_at_yaw_pitch(-PI * 0.5, 0.0)  # facing east, up the ramp
	var top := 0.0
	var biggest_step := 0.0
	var last := p.global_position.y
	for i in 36:
		Input.action_press("move_forward")
		await frames(1)
		top = maxf(top, p.global_position.y - r.y)
		biggest_step = maxf(biggest_step, p.global_position.y - last)
		last = p.global_position.y
	Input.action_release("move_forward")
	check(top > 0.99 and biggest_step < 0.15, "walking up the ramp climbs smoothly onto the block behind it (top %.2f, biggest step %.2f)" % [top, biggest_step])
	# Breaking a shaped block and placing one back: whole again.
	game.break_block(r, false)
	w.set_block(r, stone)
	check(w.get_shape(r) == Game.SHAPE_FULL, "a block put back where a shaped one was is whole")
	# Things that can't be shaped.
	check(not game.hammer_shape(c + Vector3i(0, 5, 0), 1), "air can't be shaped")
	w.set_block(r + Vector3i(0, 1, 0), Data.block_id("torch"))
	check(not game.hammer_shape(r + Vector3i(0, 1, 0), 1), "nor a torch")
	w.set_block(r + Vector3i(0, 1, 0), 0)
	w.set_block(r, 0)
	w.set_block(r + Vector3i(1, 0, 0), 0)
	p.god_mode = god
	p.inventory.slots[p.selected] = held
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	await frames(5)


## The second furniture batch: the library (bookcases, piano, dresser,
## candelabra, trash can, silver chandelier, lamp post), tiki torches and the
## sign you can write on.
func _furniture2_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var a := c + TestWorld.LIBRARY
	var names := {}
	for x in range(0, 10):
		for z in range(0, 9):
			for y in 5:
				names[Data.block(w.get_block(a + Vector3i(x, y, z))).get("name", "")] = true
	var want := ["bookcase", "piano", "dresser", "candelabra", "trash_can", "silver_chandelier", "lamp_post"]
	check(want.all(func(n): return names.has(n)), "the library has its furniture (missing %s)" % [want.filter(func(n): return not names.has(n))])
	check(w.get_light(Vector3(a) + Vector3(4.5, 2.5, 3.5)).r > 0.4, "the library is lit")
	var house_door := c + TestWorld.HOUSE + Vector3i(4, 0, 6)
	check(Data.block(w.get_block(house_door + Vector3i(-1, 0, 1))).get("name", "") == "tiki_torch", "tiki torches by the house door")
	# The dresser and trash can are containers.
	for q in [a + Vector3i(1, 0, 4), a + Vector3i(7, 0, 5)]:
		p.target = {"block": q, "normal": Vector3i.UP, "id": w.get_block(q), "distance": 2.0}
		p._interact()
		await frames(2)
		check(game.hud._chest_panel.visible and game.hud._chest == game.chests.get_inventory(q), "a %s opens like a chest" % Data.block(w.get_block(q)).name)
		game.hud.close_inventory()
	# The sign: reading it, writing on it, cancelling.
	var sign := c + TestWorld.HOUSE_SIGN
	check(game.sign_text(sign).begins_with("Welcome!"), "the house sign has a message")
	p.global_position = Vector3(sign) + Vector3(0.5, 0, 2.5)
	p.look_at_yaw_pitch(0.0, -0.35)
	await frames(5)
	var aimed: bool = not p.target.is_empty() and p.target.block == sign
	check(aimed and game.hud._sign_read.visible and game.hud._sign_read_label.text.begins_with("Welcome!"), "aiming at a sign shows what it says (aimed %s)" % aimed)
	p.target = {"block": sign, "normal": Vector3i.UP, "id": w.get_block(sign), "distance": 2.0}
	p._interact()
	await frames(2)
	check(game.hud.sign_open and game.hud._sign_edit.text.begins_with("Welcome!") and not p.input_enabled, "right-clicking it opens the editor")
	game.hud._sign_edit.text = "Something else"
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	game._unhandled_input(esc)
	check(not game.hud.sign_open and game.sign_text(sign).begins_with("Welcome!") and p.input_enabled, "Escape closes it without changing the sign")
	p.target = {"block": sign, "normal": Vector3i.UP, "id": w.get_block(sign), "distance": 2.0}
	p._interact()
	game.hud._sign_edit.text = "Signs keep what you write."
	game.hud.close_sign(true)
	check(game.sign_text(sign) == "Signs keep what you write.", "Save writes on the sign")
	# Breaking a sign takes its text with it.
	var spare := sign + Vector3i(2, 0, 0)
	w.set_block(spare, Data.block_id("sign"))
	game.set_sign_text(spare, "temporary")
	game.break_block(spare, false)
	w.set_block(spare, Data.block_id("sign"))
	check(game.sign_text(spare) == "", "a broken sign's text goes with it")
	game.break_block(spare, false)
	# Recipes, and where their Books and Bones come from.
	var ok := true
	for item in ["Bookcase", "Piano", "Dresser", "Sign", "LampPost", "TikiTorch", "TrashCan", "SilverChandelier", "GoldChandelier", "Candelabra"]:
		ok = ok and Data.recipes.any(func(r): return r.result == item)
	check(ok, "every new piece has a recipe")
	check(Data.loot.chest.extras.any(func(e): return e[0] == "Book") and Data.npcs.Skeleton.drops.any(func(e): return e[0] == "Bone"),
			"Books turn up in underground chests and Skeletons drop Bones")
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	await frames(5)


## The sky: backdrop layers per biome (cross-fading), distant things beyond
## the view distance, clouds following the day's cloudiness, stars at night
## and in Space.
## Armor: every piece has its equip sprite and a way to get it; defense
## (sets included) cuts damage; the bonuses (damage, crit, mana, light, fire
## immunity, thorns) work; the HUD's slots take only their piece; it saves.
func _armor_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var hud := game.hud
	var god := p.god_mode
	var saved_armor := p.armor.slots.duplicate()
	var saved_acc := p.accessories.slots.duplicate()
	p.accessories.slots.fill(null)
	var wear := func(pieces: Array) -> void:
		for i in 3:
			p.armor.slots[i] = null if i >= pieces.size() or pieces[i] == "" else Inventory.stack(pieces[i], 1)
		p.armor.changed.emit()

	var bad := []
	var armor_items := Data.items.keys().filter(func(n): return Data.item(n).get("type") == "armor")
	for n in armor_items:
		var d := Data.item(n)
		var dropped: bool = Data.npcs.values().any(func(e): return e.get("drops", []).any(func(x): return x[0] == n) or n in e.get("drops_one_of", []) or e.get("drops_chain", []).any(func(x): return x[0] == n if x[0] is String else n in x[0]))
		var in_set: bool = Data.loot.values().any(func(t): return t is Dictionary and t.get("sets", []).any(func(e): return n in e[0]))
		# (The Angler's armor: his rewards for the 10th, 15th and 20th quests.)
		var sold: bool = Data.npcs.values().any(func(e): return e.get("town", {}).get("shop", []).any(func(x): return (x if x is String else x[0]) == n))
		var sources: bool = Data.recipes.any(func(r): return r.result == n) or Data.loot.chest.extras.any(func(e): return e[0] == n) or dropped or in_set \
				or sold or n in AnglerQuests.MILESTONES.values()
		if not d.get("slot") in Data.ARMOR_SLOTS or (Assets.armor_texture(d.slot, n) == null and not d.get("own_look", false)) or d.id == 0 or not sources:
			bad.append(n)
	check(armor_items.size() >= 50 and bad.is_empty(), "%d armor pieces, each with its equip sprite and a recipe, chest, enemy drop, shop or Angler reward (bad: %s)" % [armor_items.size(), bad])
	var sets_ok := Data.armor_sets.all(func(a): return Data.item(a.head).get("slot") == "head" and Data.item(a.body).get("slot") == "body" \
			and Data.item(a.legs).get("slot") == "legs" and Hud.set_bonus_text(a) != "")
	check(Data.armor_sets.size() >= 18 and sets_ok, "%d armor sets, each one head, body and legs, with Terraria's set bonus text" % Data.armor_sets.size())

	# Defense: the pieces plus the set's bonus; it takes half off damage.
	wear.call([])
	check(p.defense() == 0 and p.armor_set().is_empty(), "no armor: no defense")
	wear.call(["CopperHelmet", "CopperChainmail", "CopperGreaves"])
	check(p.defense() == 1 + 2 + 1 + 2 and Hud.set_bonus_text(p.armor_set()) == "2 defense", "Copper armor: 4 defense and a 2 defense set bonus (%d)" % p.defense())
	wear.call(["CopperHelmet", "IronChainmail", "CopperGreaves"])
	check(p.defense() == 1 + 3 + 1 and p.armor_set().is_empty(), "mixed pieces: no set bonus")
	wear.call(["PlatinumHelmet", "PlatinumChainmail", "PlatinumGreaves"])
	p.god_mode = false
	p.life = p.life_max
	p._immune = 0.0
	p.hurt(40, Vector3.ZERO)
	check(p.life_max - p.life == 40 - 22 / 2, "22 defense takes 11 off a 40 damage hit (took %d)" % (p.life_max - p.life))
	p.life = p.life_max

	# Molten: melee damage, crit and speed; immune to fire blocks.
	var sword := Data.item("PlatinumBroadsword")
	wear.call([])
	var plain_damage := p.weapon_damage(sword)
	var plain_crit := p.crit_chance(sword)
	wear.call(["MoltenHelmet", "MoltenBreastplate", "MoltenGreaves"])
	check(p.defense() == 25 and p.weapon_damage(sword) == int(round(sword.damage * 1.17)) and plain_damage == int(sword.damage),
			"Molten armor: 25 defense, 17%% more melee damage (%d -> %d)" % [plain_damage, p.weapon_damage(sword)])
	check(is_equal_approx(p.crit_chance(sword), plain_crit + 0.07) and is_equal_approx(p.stat("melee_speed"), 7.0)
			and p.weapon_damage(Data.item("AmethystStaff")) == int(Data.item("AmethystStaff").damage), "Molten: +7% melee crit and speed, magic untouched")
	# Hellstone under your feet sets you on fire, unless you're immune.
	var spot := Vector3i(c.x + 30, TestWorld.GROUND, c.z + 30)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			w.set_block(spot + Vector3i(dx, 0, dz), Data.block_id("hellstone"))
			for dy in range(1, 4):
				w.set_block(spot + Vector3i(dx, dy, dz), 0)
	p.velocity = Vector3.ZERO
	p.global_position = Vector3(spot) + Vector3(0.5, 1.0, 0.5)
	p.on_fire = 0.0
	await frames(10)
	check(p.on_fire == 0.0, "the Molten set keeps you from burning on Hellstone")
	wear.call([])
	await frames(10)
	check(p.on_fire > 0.0, "without it, Hellstone sets you on fire")
	p.on_fire = 0.0
	p.accessories.slots[0] = Inventory.stack("ObsidianSkull", 1)
	await frames(10)
	check(p.on_fire == 0.0 and p.defense() == 1, "the Obsidian Skull: immune to fire blocks, 1 defense")
	p.accessories.slots[0] = null
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			w.set_block(spot + Vector3i(dx, 0, dz), Data.block_id("grass"))
	p.on_fire = 0.0
	p.life = p.life_max

	# Jungle: mana and cheaper spells.
	var staff := Data.item("AmethystStaff")
	var cap := p.mana_cap()
	wear.call(["JungleHat", "JungleShirt", "JunglePants"])
	check(p.mana_cap() == cap + 80 and p.mana_cost(staff) == int(round(staff.mana * 0.84)), "Jungle armor: +80 mana, 16%% cheaper spells (%d mana)" % p.mana_cost(staff))
	# Necro: ranged damage and crit.
	var bow := Data.item("DemonBow")
	wear.call(["NecroHelmet", "NecroBreastplate", "NecroGreaves"])
	check(p.weapon_damage(bow) == int(round(bow.damage * 1.15)) and is_equal_approx(p.crit_chance(bow), 0.14), "Necro armor: 15% ranged damage, 10% ranged crit")

	# Cactus: whatever touches you takes the spines' damage.
	wear.call(["CactusHelmet", "CactusBreastplate", "CactusLeggings"])
	var slime := game.spawn_npc("GreenSlime", p.global_position + Vector3(3, 0, 0))
	var slime_life := slime.life
	p._immune = 0.0
	p.hurt(5, slime.center(), false, slime)
	# (15 damage, give or take Terraria's 15% variance.)
	check(slime_life - slime.life >= 12 and p.defense() == 1 + 2 + 1, "Cactus armor's spines hurt attackers (%d -> %d)" % [slime_life, slime.life])
	if is_instance_valid(slime):
		slime.queue_free()
	p.life = p.life_max

	# Light: a Mining Helmet, or a torch in your hand.
	wear.call([])
	var held := p.selected
	p.select(1)  # the pickaxe
	check(p.carried_light() == Color.BLACK, "no light without a helmet or torch")
	wear.call(["MiningHelmet", "", ""])
	check(p.carried_light().r > 0.5, "the Mining Helmet gives light")
	wear.call([])
	p.select(p.inventory.slots.find(p.inventory.slots.filter(func(s): return s != null and s.item == "Torch")[0]))
	check(p.carried_light().r > 0.5, "so does a torch in your hand")
	p.select(held)
	p.update_carried_light()

	# The slots: each takes only its piece; right-click and Shift-click put armor on.
	check(Hud.slot_accepts("head", "IronHelmet") and not Hud.slot_accepts("head", "IronChainmail")
			and not Hud.slot_accepts("legs", "Wood") and not Hud.slot_accepts("accessory", "IronHelmet")
			and Hud.slot_accepts("accessory", "HermesBoots") and Hud.slot_accepts("", "IronHelmet"), "armor slots take only their piece")
	hud.toggle_inventory()
	var free := p.inventory.slots.find(null)
	p.inventory.slots[free] = Inventory.stack("GoldChainmail", 1)
	wear.call(["", "SilverChainmail", ""])
	var slot: Hud.ItemSlot = hud._slots[free]
	hud.slot_clicked(slot, MOUSE_BUTTON_RIGHT)
	check(p.armor.slots[1] != null and p.armor.slots[1].item == "GoldChainmail" and p.inventory.slots[free].item == "SilverChainmail",
			"right-click puts armor on, swapping what you wore")
	hud._quick_move(slot)
	check(p.armor.slots[1].item == "SilverChainmail" and p.inventory.slots[free].item == "GoldChainmail", "Shift-click swaps it back")
	p.inventory.slots[free] = null
	# The cursor can't drop a helmet in the legs slot.
	hud._cursor_stack = Inventory.stack("IronHelmet", 1)
	hud.slot_clicked(hud._armor_slots[2], MOUSE_BUTTON_LEFT)
	check(p.armor.slots[2] == null and hud._cursor_stack != null, "a helmet won't go in the legs slot")
	hud.slot_clicked(hud._armor_slots[0], MOUSE_BUTTON_LEFT)
	check(p.armor.slots[0] != null and p.armor.slots[0].item == "IronHelmet", "but goes in the head slot")
	hud._cursor_stack = null
	hud.close_inventory()
	var tip := Hud.item_tooltip(Data.item("MoltenHelmet"))
	check("8 defense" in tip and "7% increased melee critical strike chance" in tip, "armor tooltips: defense and Terraria's text")

	# Saved with the player.
	wear.call(["GoldHelmet", "GoldChainmail", "GoldGreaves"])
	var data := p.save_state()
	wear.call([])
	p.load_state(data)
	check(p.armor.slots[2] != null and p.armor.slots[2].item == "GoldGreaves" and p.armor_set().get("text") == "MetalTier2", "armor is saved and loaded")

	p.armor.slots = saved_armor
	p.accessories.slots = saved_acc
	p.armor.changed.emit()
	p.god_mode = god
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(5)


## Enemy health bars: over the head once hurt, green to red; none for town
## NPCs or dummies; the setting hides them.
func _health_bar_checks() -> void:
	var p := game.player
	var zombie := game.spawn_npc("Zombie", p.global_position + Vector3(0, 0, -6))
	zombie.process_mode = Node.PROCESS_MODE_DISABLED
	zombie._update_sprite(0.0, game)
	check(zombie.health_bar != null and not zombie.health_bar.visible, "an unhurt enemy shows no health bar")
	zombie.hit(10, 0.0, Vector3.FORWARD, 0.0)
	zombie._update_sprite(0.0, game)
	var bar := zombie.health_bar
	check(bar.visible and bar.position.y > zombie.half.y, "a hurt one shows it above its head (%.2f m)" % bar.position.y)
	var filled: float = bar.material_override.get_shader_parameter("filled")
	check(absf(filled - int(36.0 * zombie.life / zombie.life_max)) <= 1.0, "filled to its life (%d of 36 pixels)" % int(filled))
	var high := HealthBar.bar_color(0.95)
	var low := HealthBar.bar_color(0.1)
	check(high.g > 0.9 and high.r < 0.3 and low.r > 0.9 and low.g < 0.1, "green when healthy, red when nearly dead")
	Settings.set_value("enemy_health_bars", false)
	await frames(2)
	zombie._update_sprite(0.0, game)
	check(not bar.visible, "the setting turns health bars off")
	Settings.set_value("enemy_health_bars", true)
	await frames(2)
	zombie._update_sprite(0.0, game)
	check(bar.visible, "and back on")
	zombie.queue_free()
	var old := game.spawn_npc("OldMan", p.global_position + Vector3(3, 0, -6))
	var dummy := game.spawn_npc("TargetDummy", p.global_position + Vector3(-3, 0, -6))
	check(old.health_bar == null and (dummy == null or dummy.health_bar == null), "no health bar on town NPCs or target dummies")
	old.queue_free()
	if dummy != null:
		dummy.queue_free()
	await frames(2)


## The town: houses and the housing check, residents with Terraria's names,
## going home at night, doors, arrivals, chat (Help), shops (buying and
## selling), the Nurse, the Dryad, chat lines, money.
func _town_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var town := game.town
	var hud := game.hud
	var god := p.god_mode
	# Money: coins join up; paying makes change.
	var purse := Inventory.new(10)
	purse.add("CopperCoin", 150)
	check(purse.money() == 150 and purse.count_of("SilverCoin") == 1 and purse.count_of("CopperCoin") == 50, "100 copper coins become a silver")
	check(purse.pay(75) and purse.money() == 75 and not purse.pay(100), "paying takes coins and gives change, but not more than you have")
	check(Inventory.money_text(12345) == "1 gold 23 silver 45 copper", "money in Terraria's words (%s)" % Inventory.money_text(12345))
	check(Data.value("Torch") == 50 and Data.value("CopperPickaxe") > 0, "items have values (Copper Pickaxe from its bars: %d)" % Data.value("CopperPickaxe"))

	# The test town: eight residents, each at home.
	check(town.residents.size() == 8 and ["Guide", "Merchant", "Nurse", "ArmsDealer", "Dryad", "Demolitionist", "GoblinTinkerer", "Angler"].all(func(k): return town.residents.has(k)), "the Guide, Merchant, Nurse, Arms Dealer, Dryad, Demolitionist, Goblin Tinkerer and Angler live in the test town")
	var guide: NPC = town.residents.Guide
	var names: Array = Assets.ids.names.town.GuideNames
	check(guide.display_name in names and guide.title() == guide.display_name + " the Guide", "named from Terraria's list: %s" % guide.title())
	check(town.residents.values().all(func(n): return n.home_key != ""), "each has a home")
	var house := TestWorld.town_house(c, 0)
	var h := Housing.check(w, house + Vector3i(3, 0, 3))
	check(h.ok and h.key == guide.home_key, "a town house is a valid home: %s" % h.reason)
	check(not Housing.check(w, c + Vector3i(0, 0, 30)).ok and "wall" in Housing.check(w, c + Vector3i(0, 0, 30)).reason, "open ground isn't (%s)" % Housing.check(w, c + Vector3i(0, 0, 30)).reason)
	check("solid" in Housing.check(w, house).reason, "a check started in a wall says so")
	var candle := house + Vector3i(4, 1, 1)
	w.set_block(candle, 0)
	check("light source" in Housing.check(w, house + Vector3i(3, 0, 3)).reason, "without its candle: %s" % Housing.check(w, house + Vector3i(3, 0, 3)).reason)
	w.set_block(candle, Data.block_id("candle"))
	var chair := house + Vector3i(3, 0, 1)
	w.set_block(chair, 0)
	check("chair" in Housing.check(w, house + Vector3i(3, 0, 3)).reason, "without its chair: %s" % Housing.check(w, house + Vector3i(3, 0, 3)).reason)
	w.set_block(chair, Data.block_id("wooden_chair"))
	var hole := house + Vector3i(3, 4, 3)
	w.set_block(hole, 0)
	check("wall" in Housing.check(w, house + Vector3i(3, 0, 3)).reason, "a hole in the roof: %s" % Housing.check(w, house + Vector3i(3, 0, 3)).reason)
	town.update_housing()
	check(guide.home_key != h.key, "the Guide leaves a home with a hole in it (for a free one: %s)" % guide.home_key)
	w.set_block(hole, Data.block_id("wood"))
	check(Housing.check(w, house + Vector3i(3, 0, 3)).ok, "mended, it's a home again")
	guide.home_key = h.key
	guide.home_spot = h.spot

	# At night they go home; out of your sight a long way off, they're just there.
	var day := game.sky.is_day
	game.test_world.set_night(true)
	guide.global_position = Vector3(house) + Vector3(-30, 0, 0.5)
	p.global_position = Vector3(house) + Vector3(-30, 0, 60)
	await frames(5)
	check(guide.global_position.distance_to(Vector3(guide.home_spot) + Vector3(0.5, 0, 0.5)) < 1.0, "at night, far off and unseen, the Guide is back home")
	game.test_world.set_night(not day)
	# By day they walk out of the house, opening the door and shutting it behind them.
	var door := house + Vector3i(0, 0, 2)
	guide.global_position = Vector3(guide.home_spot) + Vector3(0.5, 0, 0.5)
	guide.ai_timer = 30.0
	check(guide.walk_to(Vector3(door) + Vector3(-3.0, 0, 0.5)), "the Guide finds his way out")
	p.global_position = Vector3(door) + Vector3(-6, 0, 6)
	var got_out := false
	for i in 600:
		await get_tree().physics_frame
		guide.ai_timer = 30.0
		if guide.global_position.x < door.x - 1.5:
			got_out = true
			break
	await frames(40)
	check(got_out, "a resident walks out through the door (at %s)" % guide.global_position)
	check(Data.block(w.get_block(door)).name == "wooden_door", "and shuts it behind them")
	# Somewhere behind the house: round its walls, not stuck against them.
	guide.global_position = Vector3(guide.home_spot) + Vector3(0.5, 0, 0.5)
	await frames(2)
	var behind := Vector3(house) + Vector3(9.5, 0, 3.5)
	guide.walk_to(behind)
	var hugged := 0.0
	var arrived := false
	for i in 1500:
		await get_tree().physics_frame
		guide.ai_timer = 30.0
		hugged += 1.0 / 60.0 if guide._stuck > 0.0 else 0.0
		if Vector2(guide.global_position.x - behind.x, guide.global_position.z - behind.z).length() < 0.5:
			arrived = true
			break
	check(arrived and hugged < 0.5, "a resident walks round to the back of the house (at %s, %.1f s against walls)" % [guide.global_position, hugged])
	# Wandering from home: every spot it heads for, it gets to.
	guide.global_position = Vector3(guide.home_spot) + Vector3(0.5, 0, 0.5)
	await frames(2)
	var reached := 0
	for k in 6:
		guide.wander(game, Vector3(guide.home_spot))
		var goal = guide._waypoints.back() if not guide._waypoints.is_empty() else null
		for i in 1200:
			await get_tree().physics_frame
			guide.ai_timer = 30.0
			if guide._waypoints.is_empty():
				break
		if goal != null and Vector2(guide.global_position.x - goal.x, guide.global_position.z - goal.z).length() < 0.5:
			reached += 1
	check(reached == 6, "wandering, the Guide reaches every spot he sets off for (%d of 6)" % reached)
	await frames(40)

	# Arrivals: with the Merchant gone and his house free, 50 silver brings him back.
	# (The money goes first: the town checks its homes now and then, and with
	# 50 silver on you he'd be straight back.)
	var money := p.inventory.money()
	p.inventory.pay(money)
	var merchant: NPC = town.residents.Merchant
	town.residents.erase("Merchant")
	town.arrived.erase("Merchant")
	merchant.queue_free()
	await frames(2)
	p.global_position = Vector3(TestWorld.town_house(c, 1)) + Vector3(-4, 0, 3)
	town.update_housing()
	check(not town.residents.has("Merchant"), "no money, no Merchant")
	p.inventory.add_money(money)
	town.update_housing()
	check(town.residents.has("Merchant") and town.residents.Merchant.home_key != "" and "has arrived" in last_message(), "with 50 silver he moves into the free house: %s" % last_message())
	merchant = town.residents.Merchant

	# Chat: the Guide's Help gives Terraria's tips.
	hud.open_chat(guide)
	check(hud.chat_npc == guide and guide.talking and hud._chat_title.text == guide.title() and hud._chat_text.text != "...", "talking to the Guide: %s" % hud._chat_text.text)
	var buttons := hud._chat_buttons.get_children().map(func(b): return b.text)
	check("Help" in buttons and "Close" in buttons and not "Shop" in buttons, "his buttons: %s" % [buttons])
	hud.chat_button("Help")
	var tip := hud._chat_text.text
	hud.chat_button("Help")
	check(tip != "..." and hud._chat_text.text != tip and not "{" in tip, "Help: a tip, then another (%s)" % tip)
	hud.close_chat()
	check(hud.chat_npc == null and not guide.talking, "Close ends the chat")
	# Chat lines name the NPCs who live here, and skip lines about those who don't.
	check(NPC.dialog(13) == "" and guide.display_name in NPC.dialog(35), "chat lines fill in names (%s)" % NPC.dialog(35))

	# The Merchant's shop: buying and selling.
	hud.open_chat(merchant)
	hud.chat_button("Shop")
	check(hud.shop_open and hud.inventory_open and hud._shop_inv.slots[0] != null and hud._shop_inv.slots[0].item == "Torch", "the Merchant's shop opens with the inventory")
	money = p.inventory.money()
	var torches := p.inventory.count_of("Torch")
	check(hud.buy("Torch", true) and p.inventory.money() == money - 50 and p.inventory.count_of("Torch") == torches + 1, "buying a Torch costs 50 copper")
	var free := p.inventory.slots.find(null)
	p.inventory.slots[free] = Inventory.stack("LesserHealingPotion", 5)
	money = p.inventory.money()
	hud._quick_move(hud._slots[free])
	check(p.inventory.slots[free] == null and p.inventory.money() == money + 5 * 60, "Shift-click sells 5 potions for a fifth of their price (%s)" % Inventory.money_text(p.inventory.money() - money))
	hud.close_inventory()
	check(not hud.shop_open and hud.chat_npc == null, "closing the inventory ends the shopping")

	# The Nurse heals for a price; the Dryad tells how corrupt the world is.
	p.god_mode = false
	p.life = p.life_max - 40
	money = p.inventory.money()
	var said := town.nurse_heal()
	check(p.life == p.life_max and p.inventory.money() == money - 40 * (1 + game.defeated_bosses.size()) and said != "", "the Nurse heals you for a price: %s" % said)
	check(town.nurse_heal() != "" and p.inventory.money() == money - 40 * (1 + game.defeated_bosses.size()), "at full life she won't charge")
	p.god_mode = god
	var status := town.dryad_status()
	check(game.world_name in status and ("%" in status or "pure" in status), "the Dryad's Status: %s" % status)
	var share := town.evil_share()
	check(share.corruption > 0.0 and share.crimson > 0.0, "the test world has both evils (%.1f%% / %.1f%%)" % [share.corruption, share.crimson])
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	await frames(5)


## Explosives: bombs blow a sphere of blocks away (not blastproof ones), one
## pile of drops; they hurt enemies and you (grenades only enemies); thrown
## bombs bounce and go off on their fuse, sticky ones stick; the
## Demolitionist comes for them and sells them.
func _explosive_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var god := p.god_mode
	var bomb := Data.item("Bomb")
	check(["Bomb", "StickyBomb", "Dynamite", "StickyDynamite", "Grenade"].all(func(n): return Data.item(n).has("explosive") and Data.item(n).id > 0),
			"Bombs, Sticky Bombs, Dynamite, Sticky Dynamite and Grenades")
	check(Data.recipes.any(func(r): return r.result == "StickyBomb" and r.ingredients.has("Gel")), "Sticky Bombs: a Bomb and Gel")
	# A block of stone with a chest, dungeon brick and Hellstone in it.
	var o := c + Vector3i(32, 0, 42)
	for x in range(-4, 5):
		for y in range(0, 7):
			for z in range(-4, 5):
				w.set_block(o + Vector3i(x, y, z), Data.block_id("stone"))
	var proof := {o + Vector3i(1, 3, 0): "blue_brick", o + Vector3i(-1, 3, 0): "hellstone", o + Vector3i(0, 3, 1): "chest"}
	for q in proof:
		w.set_block(q, Data.block_id(proof[q]))
	game.chests.register_new(o + Vector3i(0, 3, 1))
	var center := Vector3(o) + Vector3(0.5, 3.5, 0.5)
	for e in game.entities.get_children():
		if e is ItemDrop:
			e.queue_free()
	await frames(2)
	p.global_position = Vector3(o) + Vector3(0.5, 8, 12.5)
	var broken := game.blast_blocks(center, float(bomb.explosive.radius))
	var inner := w.get_block(o + Vector3i(0, 3, 0)) == 0 and w.get_block(o + Vector3i(2, 3, 0)) == 0 and w.get_block(o + Vector3i(0, 5, 0)) == 0
	var outer := w.get_block(o + Vector3i(4, 3, 0)) != 0 and w.get_block(o + Vector3i(0, 3, 4)) != 0
	check(broken > 100 and inner and outer, "a bomb blows a sphere of blocks away (%d), leaving what's beyond it" % broken)
	check(proof.keys().all(func(q): return Data.block(w.get_block(q)).name == proof[q]), "but not dungeon brick, Hellstone or a chest")
	await frames(2)
	var piles := game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "StoneBlock")
	check(piles.size() == 1 and piles[0].count == broken, "the stone drops as one pile (%s)" % [piles.map(func(e): return e.count)])
	for e in piles:
		e.queue_free()
	# Damage: enemies in reach, you too (not with a grenade).
	p.god_mode = false
	p.life = p.life_max
	p._immune = 0.0
	var zombie := game.spawn_npc("Zombie", center + Vector3(1.5, -1.0, 0))
	zombie.process_mode = Node.PROCESS_MODE_DISABLED
	var zl := zombie.life
	p.global_position = center + Vector3(0, -1.0, -1.5)
	game.explode(center, 60, 8.0, Data.item("Grenade").explosive)
	check(zombie.life < zl and p.life == p.life_max, "a grenade hurts the zombie (%d -> %d), not you" % [zl, zombie.life])
	game.explode(center, 70, 8.0, {"radius": 3.5, "tiles": false})
	check(p.life < p.life_max, "your own bomb hurts you (%d)" % (p.life_max - p.life))
	if is_instance_valid(zombie):
		zombie.queue_free()
	p.life = p.life_max
	p.god_mode = true
	# Throwing: a bomb lands, rolls to a stop, goes off on its fuse.
	for x in range(-4, 5):
		for z in range(-4, 5):
			for y in range(1, 7):
				w.set_block(o + Vector3i(x, y, z), 0)
	p.global_position = Vector3(o) + Vector3(0.5, 1, 0.5)
	p.velocity = Vector3.ZERO
	p.look_at_yaw_pitch(0.0, 0.3)
	var held := p.selected
	p.inventory.slots[9] = Inventory.stack("Bomb", 5)
	p.select(9)
	p._use_timer = 0.0
	p.use_item()
	var thrown := game.entities.get_children().filter(func(e): return e is Projectile and not e.explosive.is_empty())
	check(thrown.size() == 1 and p.inventory.slots[9].count == 4, "throwing a Bomb lights one")
	var pr: Projectile = thrown[0]
	await frames(150)
	check(is_instance_valid(pr) and pr.global_position.y < Vector3(o).y + 1.6 and pr.velocity.length() < 1.0, "it lands and rolls to a stop")
	await frames(60)
	check(not is_instance_valid(pr), "and goes off when its fuse burns down")
	# A sticky bomb sticks to a wall.
	w.set_block(o + Vector3i(0, 3, -3), Data.block_id("stone"))
	var sticky := game.spawn_projectile("StickyBomb", Vector3(o) + Vector3(0.5, 3.5, 0.5), Vector3(0, 0, -8), 70, 8.0, 0.0, 10.0, 0.45)
	sticky.explosive = Data.item("StickyBomb").explosive
	sticky.life = 10.0
	sticky.gravity = 20.0
	await frames(30)
	var at := sticky.global_position
	await frames(30)
	check(sticky._stuck and sticky.global_position == at, "a Sticky Bomb sticks where it hits")
	sticky.queue_free()
	p.inventory.slots[9] = null
	p.select(held)
	# The Demolitionist comes when you carry an explosive, and sells them.
	var town := game.town
	var demo: NPC = town.residents.Demolitionist
	check(demo.def.town.shop == ["Grenade", "Bomb", "Dynamite"], "the Demolitionist sells Grenades, Bombs and Dynamite")
	town.residents.erase("Demolitionist")
	town.arrived.erase("Demolitionist")
	demo.queue_free()
	await frames(2)
	p.global_position = Vector3(TestWorld.town_house(c, 5)) + Vector3(-4, 0, 3)
	var stash := []
	for i in p.inventory.slots.size():
		var s = p.inventory.slots[i]
		if s != null and Data.item(s.item).has("explosive"):
			stash.append([i, s])
			p.inventory.slots[i] = null
	town.update_housing()
	check(not town.residents.has("Demolitionist"), "no explosives, no Demolitionist")
	p.inventory.add("Bomb", 1)
	town.update_housing()
	check(town.residents.has("Demolitionist") and "Demolitionist has arrived" in last_message(), "carrying a Bomb brings him: %s" % last_message())
	p.inventory.remove("Bomb", 1)
	for e in stash:
		p.inventory.slots[e[0]] = e[1]
	check(NPC.dialog(93).contains("stone"), "his chat names the world's evil stone: %s" % NPC.dialog(93))
	p.god_mode = god
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	await frames(5)


## Terraria's mining and chopping: hits = block hit points / power a hit.
## Axes do axe power x 0.24 a hit to 100 hit points a tree tile (Copper Axe:
## 13 hits); pickaxes their power, blocks 50% (dirt) to 200% (ebonstone);
## grass takes one hit more (it turns into dirt first).
func _tool_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var spot := c + Vector3i(-30, 0, 30)
	var hits := func(item: String, block: String) -> int:
		w.set_block(spot, Data.block_id(block))
		p._mine_pos = Vector3i(-1, -1, -1)
		var def := Data.item(item)
		for i in 60:
			if w.get_block(spot) == 0:
				return i
			p.target = {"block": spot, "id": w.get_block(spot), "normal": Vector3i.UP, "distance": 2.0}
			p._mine(def)
		return -1
	var expect := [["CopperAxe", "tree_trunk", 13], ["PlatinumAxe", "tree_trunk", 8], ["LeadAxe", "tree_trunk", 9],
			["CopperPickaxe", "stone", 3], ["CopperPickaxe", "dirt", 2], ["CopperPickaxe", "grass", 3],
			["GoldPickaxe", "stone", 2], ["NightmarePickaxe", "ebonstone", 4], ["CopperAxe", "cactus", 5], ["CopperPickaxe", "cactus", 3]]
	var wrong := []
	for e in expect:
		var n: int = hits.call(e[0], e[1])
		if n != e[2]:
			wrong.append("%s on %s: %d hits, not %d" % [e[0], e[1], n, e[2]])
	check(wrong.is_empty(), "Terraria's hit counts (Copper Axe fells a tree in 13) %s" % [wrong])
	check(Data.item("CopperAxe").use_time == 21 and Data.item("CopperPickaxe").use_time == 15 and Data.item("PlatinumAxe").use_time == 17,
			"and tool speeds (Copper Axe 21 ticks a chop, Copper Pickaxe 15)")
	w.set_block(spot, Data.block_id("grass"))
	await frames(2)


## Cacti: a column of walk-through cells drawn whole from the base as one
## sprite with arms (CactusArt), the same shape every time; chopping any cell
## brings the whole cactus down, a Cactus per piece.
func _cactus_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var d := Vector3i(c.x + TestWorld.DESERT.x, c.y, c.z + TestWorld.DESERT.y)
	var found := w.find_blocks(d, Vector3i(22, 12, 22), PackedInt32Array([Data.block_id("cactus")]), 400)
	var bases := []
	for i in range(0, found.size(), 3):
		var q := Vector3i(found[i], found[i + 1], found[i + 2])
		if CactusArt.column(w, q)[0] == q:
			bases.append(q)
	check(bases.size() >= 3, "the desert has cacti (%d)" % bases.size())
	bases.sort_custom(func(a, b): return CactusArt.column(w, a)[1] > CactusArt.column(w, b)[1])
	var base: Vector3i = bases[0]
	var h: int = CactusArt.column(w, base)[1]
	p.global_position = Vector3(base) + Vector3(0.5, 0, 4.5)
	await frames(20)
	check(not w.is_solid(base) and Data.item("Cactus").get("type") == "material", "cacti are walk-through; the Cactus item is a material")
	check(not game.block_models.model_at(base).is_empty() and game.block_models.model_at(base + Vector3i.UP).is_empty(),
			"a cactus is drawn once, from its base")
	var s := CactusArt.shape(base, h)
	check(CactusArt.code(s) == CactusArt.code(CactusArt.shape(base, h)) and s.height == h, "its shape is the same every time (%s)" % [s])
	var arms_ok := true
	for side in ["left", "right"]:
		if not s[side].is_empty():
			arms_ok = arms_ok and s[side][0] >= 1 and s[side][1] > s[side][0] and s[side][1] <= h - 1
	check(arms_ok, "arms rise from the trunk and end at or below its top")
	var art := CactusArt.compose(CactusArt.shape(base, 5, 0).merged({"left": [1, 2], "right": [2, 4]}, true))
	check(art.get_size() == Vector2i(24, 40) and art.get_pixel(4, 26).a > 0.5 and art.get_pixel(12, 2).a > 0.5,
			"composed from Tiles_80: 3 tiles wide, an arm out to the left, a trunk to the top")
	# Every arm meets the trunk: the trunk has its joint stub beside each elbow
	# (art x 8 / 15, the trunk tile's edges), whatever row the elbow is on.
	var joints_ok := true
	for elbow in range(1, 6):
		var j := CactusArt.compose({"height": 7, "left": [elbow, elbow + 1], "right": [elbow, elbow + 1], "color": 0})
		var y := (7 - 1 - elbow) * CactusArt.ART + 5
		joints_ok = joints_ok and j.get_pixel(8, y).a > 0.5 and j.get_pixel(15, y).a > 0.5
	check(joints_ok, "every arm joins the trunk, whichever row its elbow is on")
	for e in game.entities.get_children():
		if e is ItemDrop:
			e.queue_free()
	await frames(2)
	game.break_block(base + Vector3i.UP * (h / 2))
	var gone := true
	for y in h:
		gone = gone and w.get_block(base + Vector3i.UP * y) == 0
	await frames(2)
	var got := 0
	for e in game.entities.get_children():
		if e is ItemDrop and e.item == "Cactus":
			got += e.count
	check(gone and got == CactusArt.pieces(s), "chopping it brings it all down: %d Cactus for %d pieces" % [got, CactusArt.pieces(s)])
	await frames(5)


## King Slime (Terraria's AI_015_KingSlime): the Slime Crown summons it any
## time; it hops at you, shrinks as it's hurt and spits out Blue Slimes,
## teleports next to you when it can't reach you, and drops the Solidifier,
## a Ninja armor piece and healing potions.
func _king_slime_checks(c: Vector3i) -> void:
	var p := game.player
	check(Data.recipes.any(func(r): return r.result == "SlimeCrown" and r.ingredients.get("Gel") == 20 and r.ingredients.get("GoldCrown") == 1)
			and Data.recipes.any(func(r): return r.result == "GoldCrown" and r.ingredients.get("Ruby") == 1),
			"the Slime Crown: 20 Gel and a Gold Crown (5 Gold Bars and a Ruby) at a Demon Altar")
	var was_god := p.god_mode
	p.god_mode = true
	p.flying = false
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	var held := p.selected
	p.inventory.slots[9] = Inventory.stack("SlimeCrown", 1)
	p.select(9)
	p._use_timer = 0.0
	p.hold_use = true
	p.use_item()
	p.hold_use = false
	await frames(2)
	var ks: NPC = game.boss()
	check(ks != null and ks.kind == "KingSlime" and p.inventory.slots[9] == null, "the Slime Crown summons King Slime, by day too")
	p.select(held)
	# Its summon spot varies (sometimes a ledge or a chest top, where it can
	# glide in on air control without ever winding up a hop), so the hop check
	# starts it on the plaza's flat grass, in sight.
	ks.global_position = Vector3(c) + Vector3(4.5, 0, 23.0)
	ks.velocity = Vector3.ZERO
	var d0: float = ks.global_position.distance_to(p.global_position)
	var jumped := false
	var states := {}
	var landed := -1
	var top_vy := -INF
	var grounded := 0
	# (Up to 10 s: it may still teleport first.)
	for i in 600:
		await get_tree().physics_frame
		states[ks._ks_state] = true
		top_vy = maxf(top_vy, ks.velocity.y)
		if ks.on_floor:
			grounded += 1
		if ks.on_floor and landed < 0:
			landed = i
		if ks.velocity.y > 15.0:
			jumped = true
		if jumped and i >= 300 and ks.global_position.distance_to(p.global_position) < d0 - 5.0:
			break
	var d1: float = ks.global_position.distance_to(p.global_position)
	check(jumped and d1 < d0 - 5.0, "it hops at you (%.1f -> %.1f blocks; states %s, landed at tick %d, on the floor %d ticks, fastest rise %.1f, at %s, jump timer %.0f, paused %s)" % [d0, d1, states.keys(), landed, grounded, top_vy, ks.global_position - Vector3(c), ks._ks_jump, get_tree().paused])
	var full: Vector3 = ks.half
	var slimes_before := game.npcs().filter(func(n): return n.kind == "BlueSlime").size()
	ks.hit(260, 0.0, Vector3.FORWARD, 0.0)
	await frames(3)
	var slimes_after := game.npcs().filter(func(n): return n.kind == "BlueSlime").size()
	check(slimes_after > slimes_before and slimes_after <= slimes_before + 3, "hurt, out pop Blue Slimes (%d)" % (slimes_after - slimes_before))
	check(ks.half.x < full.x * 0.97, "and it shrinks (%.2f -> %.2f wide)" % [full.x * 2.0, ks.half.x * 2.0])
	# Can't reach you for 5 seconds: it teleports next to you.
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	while not ks.on_floor:
		await get_tree().physics_frame
	ks._ks_stuck = 300
	var stages := {}
	for i in 200:
		await get_tree().physics_frame
		stages[ks._ks_state] = true
		if stages.has(6) and ks._ks_state == 0:
			break
	check(stages.has(5) and stages.has(6) and ks._ks_state == 0 and ks.global_position.distance_to(p.global_position) < 16.0,
			"stuck, it shrinks away and grows back beside you (%.1f blocks off)" % ks.global_position.distance_to(p.global_position))
	game._collected_drops = {}
	while is_instance_valid(ks) and ks.life > 0:
		ks.untouchable = false
		ks.hit(5000, 0.0, Vector3.FORWARD, 0.0)
		await get_tree().physics_frame
	var drops: Dictionary = game._collected_drops
	game._collected_drops = null
	check(game.defeated_bosses.has("KingSlime") and drops.has("Solidifier") and int(drops.get("LesserHealingPotion", 0)) >= 5
			and ["NinjaHood", "NinjaShirt", "NinjaPants"].filter(func(n): return drops.has(n)).size() == 1,
			"King Slime drops the Solidifier, a Ninja armor piece and potions (%s)" % [drops])
	for n in game.npcs():
		if n.kind == "BlueSlime":
			n.queue_free()
	p.god_mode = was_god
	await frames(2)


## The Eater of Worlds (Terraria's worm AI): 67 segments of 150 life, one
## boss bar; it steers at you through the ground, its segments trailing at
## 38 px; killing a middle segment splits it; the last segment drops the
## boss's loot. Worm Food (Corruption only), Shadow Scales and what they make.
func _eater_checks(c: Vector3i) -> void:
	var p := game.player
	var has_recipe := func(result: String, ing: String, n: int) -> bool:
		return Data.recipes.any(func(r): return r.result == result and r.ingredients.get(ing) == n)
	check(has_recipe.call("WormFood", "VilePowder", 30) and has_recipe.call("WormFood", "RottenChunk", 15)
			and has_recipe.call("ShadowScalemail", "ShadowScale", 20) and has_recipe.call("NightmarePickaxe", "ShadowScale", 6)
			and has_recipe.call("TheBreaker", "ShadowScale", 5), "Worm Food, Shadow armor, the Nightmare Pickaxe and The Breaker have Terraria's recipes")
	# Worm Food does nothing outside the Corruption.
	p.inventory.slots[9] = Inventory.stack("WormFood", 1)
	var held := p.selected
	p.select(9)
	p._use_timer = 0.0
	p.hold_use = true
	p.use_item()
	p.hold_use = false
	check(not game.boss_alive() and p.inventory.slots[9] != null, "Worm Food does nothing outside the Corruption")
	p.inventory.slots[9] = null
	p.select(held)
	var was_god := p.god_mode
	p.god_mode = true
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	game.summon_boss("EaterofWorldsHead")
	await frames(3)
	var segs: Array = game.npcs().filter(func(n): return n.def.get("boss_group", "") == "EaterofWorldsHead")
	var heads := segs.filter(func(n): return n.worm_role() == "head")
	check(segs.size() == 67 and heads.size() == 1 and segs.filter(func(n): return n.worm_role() == "tail").size() == 1,
			"the Eater of Worlds: a head, 65 body segments and a tail (%d)" % segs.size())
	var st: Dictionary = game.boss_status()
	check(st.get("name") == "Eater of Worlds" and st.get("max") == 10050 and st.get("life") == 10050, "one boss bar for all of it: 10,050 life (%s)" % [st])
	var head: NPC = heads[0]
	var d0: float = head.center().distance_to(p.center())
	for i in 120:
		await get_tree().physics_frame
	var spaced := true
	var seg: NPC = head
	while seg.behind != null:
		if absf(seg.center().distance_to(seg.behind.center()) - 38.0 / 24.0) > 0.02:
			spaced = false
		seg = seg.behind
	check(head.center().distance_to(p.center()) < d0 - 5.0, "it comes at you through the ground (%.1f -> %.1f blocks)" % [d0, head.center().distance_to(p.center())])
	check(spaced, "its segments trail 38 px apart")
	# Split: kill the 30th segment.
	var mid: NPC = head
	for i in 30:
		mid = mid.behind
	var before: NPC = mid.ahead
	var after: NPC = mid.behind
	while mid.life > 0:
		mid.hit(1000, 0.0, Vector3.FORWARD, 0.0)
	await frames(2)
	check(is_instance_valid(after) and after.worm_role() == "head" and after.kind == "EaterofWorldsHead"
			and is_instance_valid(before) and before.worm_role() == "tail" and before.kind == "EaterofWorldsTail",
			"killing a middle segment splits it: the one behind becomes a head, the one ahead a tail")
	check(game.npcs().filter(func(n): return n.def.get("boss_group", "") == "EaterofWorldsHead" and n.worm_role() == "head").size() == 2, "two worms now")
	# Kill the rest: each segment its loot, the last the boss's.
	game._collected_drops = {}
	var guard := 0
	while guard < 500:
		var left: Array = game.npcs().filter(func(n): return n.def.get("boss_group", "") == "EaterofWorldsHead" and n.life > 0 and not n.is_queued_for_deletion())
		if left.is_empty():
			break
		left[0].hit(1000, 0.0, Vector3.FORWARD, 0.0)
		await get_tree().physics_frame
		guard += 1
	var drops: Dictionary = game._collected_drops
	game._collected_drops = null
	check(game.defeated_bosses.has("EaterofWorldsHead") and not game.boss_alive(), "the Eater of Worlds is defeated")
	check(int(drops.get("DemoniteOre", 0)) >= 20 + 20 and int(drops.get("ShadowScale", 0)) > 15,
			"its segments drop Shadow Scales and Demonite Ore, the last 20-60 more ore (%s)" % [drops])
	# Digging away: the whole worm goes.
	game.defeated_bosses.erase("EaterofWorldsHead")
	game.summon_boss("EaterofWorldsHead")
	await frames(3)
	var h2: NPC = game.npcs().filter(func(n): return n.kind == "EaterofWorldsHead")[0]
	h2._worm_despawn(game)
	await frames(2)
	check(not game.boss_alive(), "when it digs away, all of it goes")
	p.god_mode = was_god
	await frames(2)


## The screenshot key (F12): the HUD, the test world's panel and the block
## outline are hidden for the frame it takes, then come back.
func _screenshot_checks() -> void:
	check(InputMap.has_action("screenshot") and InputMap.action_get_events("screenshot").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_F12),
			"F12 takes a screenshot (rebindable under Controls)")
	var hud_was: bool = game.hud.visible
	# What the frame it takes is drawn with (headless: the frame it waits for).
	var seen := []
	get_tree().process_frame.connect(func():
		seen.append(not game.hud.visible and not game.player._highlight.visible and game.taking_screenshot
				and get_tree().root.find_children("*", "CanvasLayer", true, false).all(func(l): return not l.visible)), CONNECT_ONE_SHOT)
	var path: String = await game.take_screenshot()
	check(seen == [true], "taking it hides the HUD, every overlay and the block outline for its frame")
	check(game.hud.visible == hud_was and not game.taking_screenshot, "and puts them back after the frame")
	if path != "":
		check(FileAccess.file_exists(path), "it's saved (%s)" % path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Water, Terraria style: you can't swim. You sink, and jump only off the
## bottom, half as far (about 2.9 blocks: Terraria's 4.3 tiles); pressing
## jump again mid-water does nothing.
func _swim_checks(c: Vector3i) -> void:
	var p := game.player
	var was_flying := p.flying
	var was_god := p.god_mode
	p.flying = false
	p.god_mode = true
	var bottom := Vector3(c.x - 20 + 0.5, TestWorld.GROUND - 5, c.z - 3 + 0.5)
	p.global_position = bottom + Vector3(0, 0.5, 0)
	p.velocity = Vector3.ZERO
	for i in 60:
		await get_tree().physics_frame
		if p.on_floor:
			break
	check(p.on_floor and p.in_liquid == 1 and absf(p.global_position.y - bottom.y) < 0.05, "you sink to the bottom of the pool")
	var start := p.global_position.y
	var top := start
	Input.action_press("jump")
	var fell_back := false
	for i in 150:
		await get_tree().physics_frame
		top = maxf(top, p.global_position.y)
		if i > 20 and p.velocity.y < -1.0:
			fell_back = true
			break
	check(fell_back and top - start > 2.3 and top - start < 3.4 and top + Player.EYE_HEIGHT < TestWorld.GROUND + 1,
			"held jump in water: up %.2f blocks off the bottom, then you sink (Terraria: 4.3 tiles)" % (top - start))
	Input.action_release("jump")
	await get_tree().physics_frame
	Input.action_press("jump")
	var rose := false
	for i in 20:
		await get_tree().physics_frame
		if not p.on_floor and p.velocity.y > 0.0:
			rose = true
	Input.action_release("jump")
	check(not rose, "pressing jump again mid-water does nothing: no swimming")
	p.flying = was_flying
	p.god_mode = was_god
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(3)


## Flails (Terraria's AI_015_Flails): held, one spins round you and hits what's
## near you; let go and it flies at your aim, then comes back; click while
## it's out and it drops, staying while you hold the button; a block sends a
## throw into a ricochet. Damage x1.2 spinning, x2 thrown; the Sunfury and the
## Flaming Mace set enemies on fire.
func _flail_checks(c: Vector3i) -> void:
	var p := game.player
	var flails := ["Mace", "FlamingMace", "BallOHurt", "TheMeatball", "BlueMoon", "Sunfury"]
	var looks := func(n: String) -> bool:
		var d := Data.item(n)
		return d.has("flail") and int(Assets.ids.ProjectileID.get(d.projectile, 0)) > 0 and Assets.texture("Images/" + str(d.flail.chain[0])) != null
	check(flails.all(looks), "six flails, each with its Terraria head and chain sprites")
	check(Data.loot.chest.pick_one.any(func(e): return e[0] == "Mace") and Data.loot.shadow_orb.pick_one.any(func(e): return e[0] == "BallOHurt")
			and Data.recipes.any(func(r): return r.result == "FlamingMace" and r.ingredients.get("Mace") == 1 and r.ingredients.get("Torch") == 99)
			and Data.recipes.any(func(r): return r.result == "TheMeatball" and r.ingredients.get("TissueSample") == 5),
			"the Mace in chests, the Ball O' Hurt from Shadow Orbs, the Flaming Mace and The Meatball crafted")
	check("18 melee damage" in Hud.item_tooltip(Data.item("Mace")) and "64 melee damage" in Hud.item_tooltip(Data.item("Sunfury")),
			"tooltips show a flail's thrown damage, twice its base (Mace 18, Sunfury 64)")
	var held := p.selected
	p.inventory.slots[9] = Inventory.stack("Mace", 1)
	p.select(9)
	p.god_mode = true
	var dummies: Array = game.npcs().filter(func(n): return n.kind == "TargetDummy")
	var dummy: NPC = dummies.reduce(func(a, b): return a if absf(a.global_position.x - (c.x + 6.0)) < absf(b.global_position.x - (c.x + 6.0)) else b)
	# 1. Spinning, right next to a dummy: it circles over you and hits it.
	p.global_position = dummy.global_position + Vector3(1.6, 0, 0)
	p.velocity = Vector3.ZERO
	p.look_at_yaw_pitch(PI * 0.5, 0.0)
	p.hold_use = false
	await get_tree().physics_frame
	dummy._hits.clear()
	p.hold_use = true
	p._use_timer = 0.0
	p.use_item()
	check(p.flail_out() and p.flail.state == Flail.State.SPIN, "using a flail spins it")
	var radius_ok := true
	var early_hit := false
	for i in 40:
		await get_tree().physics_frame
		if i < 10 and not dummy._hits.is_empty():
			early_hit = true
		var off: Vector3 = p.flail.global_position - p.center()
		if absf(Vector2(off.x, off.z).length() - 30.0 / 16.0) > 0.01 or absf(off.y - Flail.SPIN_HEIGHT) > 0.01:
			radius_ok = false
	var base := p.weapon_damage(Data.item("Mace"))
	var spin_hits: Array = dummy._hits.duplicate()
	check(radius_ok and not p.viewmodel.item_node().visible, "it whirls round over your head, 30 px out, out of your hand")
	var spin_dmg := func(h: Array) -> bool: return h[1] >= floor(base * 1.2 * 0.85) and h[1] <= ceil(base * 1.2 * 1.15) * 2
	check(not early_hit and spin_hits.size() >= 1 and spin_hits.size() <= 3 and spin_hits.all(spin_dmg),
			"after 12 ticks it hits a dummy beside you, every 15 ticks, for 1.2x (%s)" % [spin_hits])
	# 2. Let go: thrown along your aim (at nothing), out and back.
	p.global_position = Vector3(c.x + 6.0, c.y, c.z + 1.0)
	p.look_at_yaw_pitch(0.0, 0.35)
	await get_tree().physics_frame
	p.hold_use = false
	var far := 0.0
	var ticks := 0
	var start: Vector3 = p.center()
	var states := {}
	while p.flail_out() and ticks < 240:
		await get_tree().physics_frame
		ticks += 1
		if p.flail_out():
			far = maxf(far, p.flail.global_position.distance_to(start))
			states[p.flail.state] = true
	# Terraria's Mace: 12 px a tick for 13 ticks, then x0.3 and back.
	check(states.has(Flail.State.LAUNCH) and states.has(Flail.State.RETRACT) and far > 8.5 and far < 12.0 and not p.flail_out(),
			"let go, it flies out (%.1f blocks) and comes back to you (%.1f s)" % [far, ticks / 60.0])
	check(not states.has(Flail.State.DROP), "untouched, it never drops")
	# 3. Thrown at the dummy: twice the damage.
	p.global_position = dummy.global_position + Vector3(0, 0, 5.0)  # (the dummies stand in a row along x)
	var aim: Vector3 = (dummy.center() - p.camera.global_position).normalized()
	p.look_at_yaw_pitch(atan2(-aim.x, -aim.z), asin(aim.y))
	await get_tree().physics_frame
	p.hold_use = true
	p._use_timer = 0.0
	p.use_item()
	await get_tree().physics_frame
	dummy._hits.clear()
	p.hold_use = false
	for i in 120:
		await get_tree().physics_frame
		if not p.flail_out():
			break
	check(not dummy._hits.is_empty() and dummy._hits.any(func(h): return h[1] >= floor(base * 2 * 0.85)),
			"thrown, it hits for twice its damage (%s, base %d)" % [dummy._hits, base])
	# 4. Click while it's out: it drops and stays while you hold; let go, it's pulled back.
	p.global_position = Vector3(c.x + 6.0, c.y, c.z + 1.0)
	p.look_at_yaw_pitch(0.0, 0.0)
	p.hold_use = true
	p._use_timer = 0.0
	p.use_item()
	await get_tree().physics_frame
	p.hold_use = false
	for i in 6:
		await get_tree().physics_frame
	p.hold_use = true
	await get_tree().physics_frame
	check(p.flail_out() and p.flail.state == Flail.State.DROP, "clicking while it's out drops it")
	for i in 60:
		await get_tree().physics_frame
	var rest: Vector3 = p.flail.global_position
	for i in 20:
		await get_tree().physics_frame
	# (On the ground it slides to a stop, x0.95 a tick.)
	var ground := p.flail.global_position.y - p.flail._half
	check(p.flail_out() and p.flail.state == Flail.State.DROP and absf(ground - roundf(ground)) < 0.02 and absf(p.flail.velocity.y) < 0.01
			and p.flail.global_position.distance_to(rest) < 0.2, "it lands and stays on the ground while you hold (bottom at %.2f)" % ground)
	p.hold_use = false
	var back_ticks := 0
	var forced := false
	while p.flail_out() and back_ticks < 120:
		await get_tree().physics_frame
		back_ticks += 1
		forced = forced or (p.flail_out() and p.flail.state == Flail.State.FORCED)
	check(forced and not p.flail_out(), "let go, it's pulled back to you (%.2f s)" % (back_ticks / 60.0))
	# 5. Thrown into the ground: a ricochet.
	p.look_at_yaw_pitch(0.0, -1.3)
	p.hold_use = true
	p._use_timer = 0.0
	p.use_item()
	await get_tree().physics_frame
	p.hold_use = false
	var ricochet := false
	for i in 120:
		await get_tree().physics_frame
		ricochet = ricochet or (p.flail_out() and p.flail.state == Flail.State.RICOCHET)
		if not p.flail_out():
			break
	check(ricochet and not p.flail_out(), "thrown into a block it ricochets, then comes back")
	# 6. Putting it away mid-spin takes it back.
	p.hold_use = true
	p._use_timer = 0.0
	p.use_item()
	await get_tree().physics_frame
	p.select(held)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not p.flail_out(), "switching items puts the flail away")
	p.hold_use = false
	# 7. On fire: 4 life a second, 1 at a time; the Sunfury sets it 1 hit in 2.
	var zombie: NPC = game.spawn_npc("Zombie", Vector3(c.x + 0.5, c.y, c.z + 6.5))
	zombie.set_physics_process(false)
	var life0 := zombie.life
	zombie.ignite(1.0)
	for i in 60:
		zombie._burn_tick(1.0 / 60.0, game)
	check(life0 - zombie.life == 4 and zombie.on_fire <= 0.0001, "On Fire!: 4 life a second (%d)" % (life0 - zombie.life))
	var lit := 0
	zombie.life_max = 100000  # (thrown, the Sunfury would kill it)
	zombie.life = zombie.life_max
	p.inventory.slots[9] = Inventory.stack("Sunfury", 1)
	p.select(9)
	for i in 40:
		zombie.on_fire = 0.0
		p.flail = null
		var f := Flail.new()
		f.setup(p, Data.item("Sunfury"))
		game.entities.add_child(f)
		f.state = Flail.State.RETRACT
		f.global_position = zombie.center()
		f._check_hits(game)
		lit += int(zombie.on_fire > 0.0)
		zombie.life = zombie.life_max
		f.free()
	check(lit > 8 and lit < 32 and is_equal_approx(Data.item("Sunfury").on_fire[1] / 60.0, 5.0), "the Sunfury sets enemies on fire half the time, for 5 s (%d of 40)" % lit)
	zombie.queue_free()
	p.inventory.slots[9] = null
	p.select(held)
	p.god_mode = false
	await frames(2)


## The Terragrim (Slash, projectile AI 75): held, it slashes on toward your
## aim; its hitbox is centred on you (68 x 64 Terraria px), so it reaches a
## little behind you; each enemy is hit at most every 5 ticks (12 a second).
## An Enchanted Sword Shrine's sword in stone (LargePiles2 style 17): mined
## with a pickaxe, it gives the Enchanted Sword, or 1 time in 30 the Terragrim.
func _sword_shrine_checks(c: Vector3i) -> void:
	var id := Data.block_id("sword_in_stone")
	var b := Data.block(id)
	check(id != 0 and b.get("tool") == "pickaxe" and b.tex.all.sheet == "Tiles_187" and int(b.tex.all.frames[0][0]) == 918,
			"the sword in stone: Terraria's LargePiles2 style 17, mined with a pickaxe")
	var q := c + Vector3i(0, 1, -8)
	game.world.set_block(q, id)
	for e in game.entities.get_children():
		if e is ItemDrop:
			e.queue_free()
	await frames(1)
	game._collected_drops = {}
	game.break_block(q, true, true)
	var got: Dictionary = game._collected_drops
	game._collected_drops = null
	# (A sword that rolled a prefix drops on its own, not collected.)
	for e in game.entities.get_children():
		if e is ItemDrop and not e.is_queued_for_deletion() and e.item in ["EnchantedSword", "Terragrim"]:
			got[e.item] = int(got.get(e.item, 0)) + 1
			e.queue_free()
	check(game.world.get_block(q) == 0 and got.size() == 1 and (got.has("EnchantedSword") or got.has("Terragrim")),
			"breaking it drops the sword (%s)" % str(got))
	var rare := 0
	for i in 6000:
		if game.block_drop(b) == "Terragrim":
			rare += 1
	check(rare > 140 and rare < 260, "the Terragrim 1 time in 30, else the Enchanted Sword (%d in 6000)" % rare)


func _terragrim_checks(c: Vector3i) -> void:
	var p := game.player
	var d := Data.item("Terragrim")
	var tex := Assets.texture("Images/Projectile_%d" % int(Assets.ids.ProjectileID.get("Terragrim", 0)))
	check(d.get("slash") is Dictionary and tex != null and tex.get_height() == 64 * int(d.slash.frames) and Assets.ids.ItemID.get("Terragrim") == 4144,
			"the Terragrim (item 4144): its 28-frame slash sheet, Terraria's numbers (%d damage, %s knockback)" % [d.damage, d.knockback])
	var held := p.selected
	p.inventory.slots[9] = Inventory.stack("Terragrim", 1)
	p.select(9)
	p.god_mode = true
	var dummies: Array = game.npcs().filter(func(n): return n.kind == "TargetDummy")
	var dummy: NPC = dummies.reduce(func(a, b): return a if absf(a.global_position.x - (c.x + 6.0)) < absf(b.global_position.x - (c.x + 6.0)) else b)
	p.global_position = dummy.global_position + Vector3(1.5, 0, 0)
	p.velocity = Vector3.ZERO
	p.look_at_yaw_pitch(PI * 0.5, 0.0)  # facing the dummy (-x)
	p.hold_use = false
	await get_tree().physics_frame
	dummy._hits.clear()
	p.hold_use = true
	p._use_timer = 0.0
	p.use_item()
	check(p.slash_out(), "using the Terragrim starts slashing")
	await frames(3)
	# (The viewmodel hides it in its _process, which runs after process_frame.)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not p.viewmodel.item_node().visible and p.carried_light().r >= 0.8, "it's out of your hand and shines while you slash (shown %s, light %s, slashing %s)" % [p.viewmodel.item_node().visible, p.carried_light(), p.slash_out()])
	dummy._hits.clear()
	for i in 60:
		await get_tree().physics_frame
	var base := p.weapon_damage(d)
	var hits: Array = dummy._hits.duplicate()
	var dmg_ok := hits.all(func(h): return h[1] >= floor(base * 0.85) and h[1] <= ceil(base * 1.15) * 2)
	check(hits.size() >= 11 and hits.size() <= 13 and dmg_ok, "held beside a dummy it hits 12 times a second at the item's damage (%d hits)" % hits.size())
	# Facing away: the hitbox is centred on you, so it still reaches.
	p.look_at_yaw_pitch(-PI * 0.5, 0.0)
	dummy._hits.clear()
	for i in 30:
		await get_tree().physics_frame
	check(dummy._hits.size() >= 5, "it reaches a little behind you, as in Terraria (%d hits)" % dummy._hits.size())
	# Out of its reach (68 px across: 2 blocks or so to each side).
	p.global_position = dummy.global_position + Vector3(4.0, 0, 0)
	p.look_at_yaw_pitch(PI * 0.5, 0.0)
	await get_tree().physics_frame
	dummy._hits.clear()
	for i in 30:
		await get_tree().physics_frame
	check(dummy._hits.is_empty(), "4 blocks away it doesn't reach")
	p.hold_use = false
	await frames(2)
	check(not p.slash_out() and p.carried_light() == Color.BLACK, "let go, and it stops")
	p.inventory.slots[9] = null
	p.select(held)
	p.god_mode = false
	await frames(2)


## Yoyos: thrown while the use button is held, they chase what you aim at
## (an enemy in your sights) within their reach, tethered by a string, hit it
## several times a second, and come back when you let go or the spin ends.
func _yoyo_checks(c: Vector3i) -> void:
	var p := game.player
	var yoyos := ["WoodYoyo", "Rally", "CorruptYoyo", "CrimsonYoyo", "JungleYoyo", "Code1"]
	var sourced := yoyos.all(func(n): return Data.recipes.any(func(r): return r.result == n) \
			or Data.loot.chest.pick_one.any(func(e): return e[0] == n))
	check(yoyos.all(func(n): return Data.item(n).has("yoyo") and int(Assets.ids.ProjectileID.get(Data.item(n).projectile, 0)) > 0) and sourced,
			"six yoyos, each with its Terraria sprite and a recipe or chest")
	var held := p.selected
	p.inventory.slots[9] = Inventory.stack("Code1", 1)
	p.select(9)
	# Facing the target dummies from 6 blocks away.
	p.global_position = Vector3(c.x + 6.0, c.y, c.z + 1.0)
	p.velocity = Vector3.ZERO
	p.look_at_yaw_pitch(PI, -0.05)
	# (The one in your sights: the crosshair is half a block from its middle.)
	var dummy: NPC = game.npcs().filter(func(n): return n.kind == "TargetDummy").reduce(func(a, b): return a if absf(a.global_position.x - (c.x + 6.0)) < absf(b.global_position.x - (c.x + 6.0)) else b)
	dummy._hits.clear()
	p.hold_use = true
	p._use_timer = 0.0
	p.use_item()
	check(p.yoyo_out(), "using a yoyo throws it")
	var first := p.yoyo
	p._use_timer = 0.0
	p.use_item()
	check(p.yoyo == first and game.entities.get_children().filter(func(e): return e is Yoyo).size() == 1, "one out at a time")
	var too_far := false
	for i in 120:
		await get_tree().physics_frame
		if p.yoyo_out() and p.yoyo.global_position.distance_to(p.camera.global_position) > p.yoyo.reach() + 0.01:
			too_far = true
	check(dummy._hits.size() >= 5 and p.yoyo_out() and not p.viewmodel.item_node().visible,
			"held out, it hits the dummy in your sights again and again (%d hits in 2 s), out of your hand" % dummy._hits.size())
	check(not too_far, "never farther than its reach (%.1f blocks)" % p.yoyo.reach())
	p.hold_use = false
	for i in 60:
		await get_tree().physics_frame
		if not p.yoyo_out():
			break
	check(not p.yoyo_out(), "let go, it comes back")
	# Its spin runs out: the Wooden Yoyo's 3 seconds.
	p.inventory.slots[9] = Inventory.stack("WoodYoyo", 1)
	p.look_at_yaw_pitch(0.0, 0.3)  # at nothing
	p.hold_use = true
	p._use_timer = 0.0
	p.use_item()
	# (Counted in physics frames: headless tests run faster than real time.)
	var ticks := 0
	while p.yoyo_out() and ticks < 360:
		await get_tree().physics_frame
		ticks += 1
	var secs := ticks / 60.0
	check(not p.yoyo_out() and secs > 2.8 and secs < 4.5, "the Wooden Yoyo spins for its 3 seconds, then comes back (%.1f s)" % secs)
	# Like Terraria's (no auto reuse), holding the button as it comes back
	# doesn't throw it again: it takes a fresh click.
	await frames(5)
	p._use_timer = 0.0
	p.use_item()
	check(not p.yoyo_out(), "holding the button as it comes back doesn't throw it again")
	p.hold_use = false
	await get_tree().physics_frame
	p.hold_use = true
	p._use_timer = 0.0
	p.use_item()
	check(p.yoyo_out(), "a fresh click does")
	# The same for every weapon (Terraria's autoReuse is off for all of them):
	# held down, a sword swings once; a pickaxe keeps going (tools do), and with
	# the Autofire setting on, so does the sword.
	p.hold_use = false
	while p.yoyo_out():
		await get_tree().physics_frame
	var swings := func(item: String) -> int:
		p.inventory.slots[9] = Inventory.stack(item, 1)
		p.hold_use = false
		await get_tree().physics_frame
		p.hold_use = true
		var n := 0
		for i in 90:
			p._use_timer = 0.0
			p.use_item()
			if p._use_timer > 0.0:
				n += 1
			await get_tree().physics_frame
		p.hold_use = false
		await get_tree().physics_frame
		return n
	var sword_n: int = await swings.call("PlatinumBroadsword")
	var pick_n: int = await swings.call("CopperPickaxe")
	Settings.set_value("autofire", true)
	var auto_n: int = await swings.call("PlatinumBroadsword")
	Settings.set_value("autofire", false)
	check(sword_n == 1 and pick_n > 30 and auto_n > 30 and not Data.item("FlintlockPistol").auto_reuse and Data.item("DirtBlock").auto_reuse and not Data.item("WoodenDoor").auto_reuse,
			"held down, a sword swings once (%d), a pickaxe keeps going (%d), Autofire swings on (%d)" % [sword_n, pick_n, auto_n])
	p.inventory.slots[9] = Inventory.stack("WoodYoyo", 1)
	p.hold_use = true
	p._use_timer = 0.0
	await get_tree().physics_frame
	p.hold_use = false
	await get_tree().physics_frame
	p.hold_use = true
	p.use_item()
	# Reach: a White String adds a quarter and 1.875 blocks.
	var base: float = p.yoyo.reach()
	var acc0 = p.accessories.slots[4]
	p.accessories.slots[4] = Inventory.stack("WhiteString", 1)
	check(is_equal_approx(p.yoyo.reach(), base * 1.25 + 1.875) and is_equal_approx(base, 8.125 * (1.0 + p.stat("melee_speed") / 100.0)),
			"a White String reaches farther (%.2f -> %.2f blocks)" % [base, p.yoyo.reach()])
	p.accessories.slots[4] = acc0
	p.hold_use = false
	while p.yoyo_out():
		await get_tree().physics_frame
	p.inventory.slots[9] = null
	p.select(held)
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	await frames(3)


## Recipes are Terraria's own, read from Terraria.exe (tools/terraria_recipes.py),
## except marked stand-ins for things this game can't make Terraria's way yet.
## The Underworld's enemies: Terraria's spawn chain, the bats' and demons'
## aiStyle 14, the Fire Imp's spell, the Bone Serpent's shared life, lava.
func _underworld_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var was_god := p.god_mode
	p.god_mode = true
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	var clear_npcs := func() -> void:
		for n in game.npcs():
			if not n.def.get("persistent", false) and n.def.ai != "town" and n.def.ai != "dummy":
				n.queue_free()
		for e in game.entities.get_children():
			if e is Projectile:
				e.queue_free()
	clear_npcs.call()
	await frames(2)
	# Terraria's chain: 1 in 8 a critter, 1 in 40 a Bone Serpent, 1 in 14 a
	# Fire Imp, 1 in 7 a Demon (1 in 10 of them Voodoo), 1 in 3 a Lava Slime,
	# else a Hellbat.
	var counts := {}
	for i in 20000:
		var k := Spawner.underworld_pick(false)
		counts[k] = int(counts.get(k, 0)) + 1
	var share := func(k: String) -> float: return float(counts.get(k, 0)) / 20000.0
	check(absf(share.call("Hellbat") - 0.452) < 0.02 and absf(share.call("LavaSlime") - 0.226) < 0.015 and absf(share.call("Demon") - 0.102) < 0.012
			and absf(share.call("") - 0.125) < 0.012 and absf(share.call("FireImp") - 0.061) < 0.01 and absf(share.call("BoneSerpentHead") - 0.022) < 0.006
			and absf(share.call("VoodooDemon") - 0.0113) < 0.004, "the Underworld's spawns are Terraria's chain (%s)" % [counts])
	var serpents := 0
	for i in 4000:
		if Spawner.underworld_pick(true) == "BoneSerpentHead":
			serpents += 1
	check(serpents == 0 and game.spawner._depth(game.underworld_level - 1.0, game) == "underworld", "one Bone Serpent at a time; below the Underworld's top is the Underworld")

	# A Hellbat comes at you (aiStyle 14: steered twice a tick), up in the
	# open air.
	var sky := c + Vector3i(0, 40, 0)
	for x in range(-14, 6):
		for y in range(-3, 6):
			for z in range(-4, 5):
				w.set_block(sky + Vector3i(x, y, z), Data.block_id("stone") if y == -1 and absi(x + 4) <= 1 and absi(z) <= 1 else 0)
	p.global_position = Vector3(sky) + Vector3(-3.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	await frames(2)
	var bat := game.spawn_npc("Hellbat", p.center() + Vector3(-10, 1, 0))
	var d0 := bat.center().distance_to(p.center())
	await frames(90)
	check(bat.center().distance_to(p.center()) < d0 - 4.0, "a Hellbat flies at you (%.1f -> %.1f blocks)" % [d0, bat.center().distance_to(p.center())])
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	# Lava doesn't hurt it; it does a Cave Bat: 50 and 7 s of On Fire!
	var lava := c + Vector3i(-23, -1, 10)
	var cave := game.spawn_npc("CaveBat", Vector3(lava) + Vector3(0.5, 0.2, 0.5))
	bat.global_position = Vector3(lava) + Vector3(0.5, 0.2, 0.5)
	bat.velocity = Vector3.ZERO
	cave.velocity = Vector3.ZERO
	var cave_life := cave.life
	await frames(3)
	check(bat.life == bat.life_max and bat.on_fire == 0.0, "lava doesn't hurt a Hellbat (%d of %d)" % [bat.life, bat.life_max])
	check(not is_instance_valid(cave) or cave.life < cave_life, "it does a Cave Bat")
	clear_npcs.call()
	await frames(2)

	# A Demon's scythes: four, 20 ticks apart, slow then fast.
	var demon := game.spawn_npc("Demon", p.center() + Vector3(7, 3, 0))
	var scythes := []
	var fastest := 0.0
	for i in 110:
		await frames(1)
		for e in game.entities.get_children():
			if e is Projectile and e.kind == "DemonSickle" and not e.friendly:
				if not scythes.has(e):
					scythes.append(e)
				fastest = maxf(fastest, e.velocity.length())
	check(scythes.size() == 4, "a Demon throws four Demon Scythes (%d)" % scythes.size())
	check(fastest > 10.0, "speeding up as they fly (%.1f blocks/s)" % fastest)
	clear_npcs.call()
	await frames(2)

	# A Voodoo Demon always drops the Guide Voodoo Doll.
	var vd := game.spawn_npc("VoodooDemon", p.center() + Vector3(4, 3, 0))
	await frames(2)
	var drop_at := vd.center()
	vd.hit(9999, 0.0, Vector3.RIGHT)
	await frames(2)
	var dolls := game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "GuideVoodooDoll" and e.global_position.distance_to(drop_at) < 4.0)
	check(dolls.size() == 1, "a Voodoo Demon drops the Guide Voodoo Doll")
	for e in dolls:
		e.queue_free()

	# A Fire Imp teleports near you and casts Burning Spheres.
	var imp := game.spawn_npc("FireImp", p.global_position + Vector3(8, 0, 8))
	var spheres := []
	for i in 330:
		await frames(1)
		for e in game.entities.get_children():
			if e is Projectile and e.kind == "BurningSphere" and not spheres.has(e):
				spheres.append(e)
	check(spheres.size() >= 1 and imp.global_position.distance_to(p.global_position) < 21.5, "a Fire Imp teleports near you and casts a Burning Sphere (%d)" % spheres.size())
	clear_npcs.call()
	await frames(2)

	# A Bone Serpent: 14-22 bodies and a tail, one life for all of it.
	var head := game.spawn_npc("BoneSerpentHead", p.center() + Vector3(0, -6, 12))
	await frames(3)
	var segs: Array = game.npcs().filter(func(n): return n.kind.begins_with("BoneSerpent"))
	check(segs.size() >= 16 and segs.size() <= 24 and segs.filter(func(n): return n.worm_role() == "tail").size() == 1,
			"a Bone Serpent: a head, 14-22 bodies and a tail (%d)" % segs.size())
	var body: NPC = head.behind.behind
	body.hit(60, 0.0, Vector3.RIGHT, 0.0)
	check(head.life < head.life_max and body.life == head.life, "a hit anywhere comes off its one life (%d of %d)" % [head.life, head.life_max])
	body.hit(9999, 0.0, Vector3.RIGHT, 0.0)
	await frames(2)
	var left := game.npcs().filter(func(n): return n.kind.begins_with("BoneSerpent"))
	check(left.is_empty(), "and it dies all at once (%s)" % [left.map(func(n): return "%s %d %s" % [n.kind, n.life, n._dying])])
	clear_npcs.call()
	await frames(2)

	# A Lava Slime glows.
	var slime := game.spawn_npc("LavaSlime", p.global_position + Vector3(5, 0, 0))
	check(slime.glowing(), "a Lava Slime glows")
	clear_npcs.call()

	# The Magma Stone: melee hits set enemies on Hellfire (15 a second), not
	# the Underworld's.
	p.accessories.slots[0] = Inventory.stack("MagmaStone", 1)
	var zombie := game.spawn_npc("Zombie", p.global_position + Vector3(6, 0, 0))
	var hellbat := game.spawn_npc("Hellbat", p.global_position + Vector3(-6, 3, 0))
	p.on_melee_hit(zombie, {})
	p.on_melee_hit(hellbat, {})
	var z_life := zombie.life
	check(zombie.hellfire >= 2.0 and hellbat.hellfire == 0.0, "the Magma Stone's Hellfire takes, but not on a Hellbat")
	await frames(62)
	check(z_life - zombie.life >= 10, "Hellfire burns 15 a second, 5 at a time (%d)" % (z_life - zombie.life))
	# The Obsidian Rose: lava does 45 less.
	p.accessories.slots[0] = Inventory.stack("ObsidianRose", 1)
	p.god_mode = false
	p.life = p.life_max
	p._immune = 0.0
	p.on_fire = 0.0
	var life0 := p.life
	p.global_position = Vector3(lava) + Vector3(0.5, 0.1, 0.5)
	p.velocity = Vector3.ZERO
	await frames(3)
	var expect := maxi(1, Player.LAVA_DAMAGE - Player.LAVA_ROSE_DAMAGE - p.defense() / 2)
	check(p.in_liquid == Player.LIQ_LAVA and life0 - p.life == expect, "with an Obsidian Rose lava hurts %d (took %d)" % [expect, life0 - p.life])
	p.god_mode = true
	p.on_fire = 0.0
	p.accessories.slots[0] = null
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	p.god_mode = was_god
	clear_npcs.call()
	await frames(30)
	p.life = p.life_max


func _shadow_chest_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var was_god := p.god_mode
	p.god_mode = true
	var ores_was := game.chests.ores
	var clear := func() -> void:
		for n in game.npcs():
			if not n.def.get("persistent", false) and n.def.ai != "town" and n.def.ai != "dummy":
				n.queue_free()
		for e in game.entities.get_children():
			if e is Projectile or e is ItemDrop:
				e.queue_free()
	# A Locked Shadow Chest (worldgen's, hell.rs) holding a Flamelash.
	var spot := c + Vector3i(-4, 40, 0)
	w.set_block(spot + Vector3i.DOWN, Data.block_id("stone"))
	w.set_block(spot, Data.block_id("locked_shadow_chest"))
	w.add_decoration("chest", spot, 16 + 3)
	# One left unopened through a save and reload; a Dungeon chest with a
	# Shadow Key in it.
	var later := spot + Vector3i(2, 0, 0)
	var keyed := spot + Vector3i(-2, 0, 0)
	w.add_decoration("chest", later, 16)
	w.add_decoration("chest", keyed, 7 + Chests.SHADOW_KEY)
	game.chests.setup(w)
	game.chests.ores = 8
	p.inventory.remove("ShadowKey", p.inventory.count_of("ShadowKey"))
	check(not game.unlock_chest(spot) and last_message() == "It's locked", "a Locked Shadow Chest stays locked without a Shadow Key")
	p.inventory.add("ShadowKey", 1)
	check(game.unlock_chest(spot) and Data.block(w.get_block(spot)).get("name", "") == "shadow_chest" and p.inventory.count_of("ShadowKey") == 1,
			"a Shadow Key opens it for good, and isn't used up")
	check(game.chests.get_inventory(spot).count_of("Flamelash") == 1, "its main item inside")
	game.hud.close_inventory()
	game.chests.load_state(game.chests.save_state())
	check(game.chests.get_inventory(later).count_of("DarkLance") == 1, "a worldgen chest left unopened rolls its loot after a save and reload")
	var dungeon := game.chests.get_inventory(keyed)
	check(dungeon.count_of("Muramasa") == 1 and dungeon.count_of("ShadowKey") == 1, "a Dungeon chest with a Shadow Key")
	# The loot: Terraria's odds, the world's bars.
	var seen := {}
	for i in 1000:
		for drop in Game.roll_loot("shadow_HellwingBow", true):
			seen[drop[0]] = int(seen.get(drop[0], 0)) + 1
	var n := func(k: String) -> int: return int(seen.get(k, 0))
	check(n.call("HellwingBow") == 1000 and absi(n.call("TreasureMagnet") - 200) < 50 and absi(n.call("MeteoriteBar") + n.call("GoldBar") - 500) < 60
			and n.call("MeteoriteBar") > 150 and absi(n.call("HellfireArrow") + n.call("SilverBullet") - 500) < 60 and absi(n.call("RestorationPotion") - 500) < 60,
			"a Shadow Chest's loot (%s)" % [seen])
	check(game.chests.world_item("GoldBar") == "PlatinumBar" and game.chests.world_item("SilverBullet") == "SilverBullet" and game.chests.world_item("IronBar") == "IronBar",
			"a Platinum world's chests hold Platinum Bars")
	game.chests.ores = 4
	check(game.chests.world_item("SilverBullet") == "TungstenBullet" and game.chests.world_item("GoldBar") == "GoldBar", "a Tungsten world's, Tungsten Bullets")
	game.chests.ores = ores_was
	for q in [spot, later, keyed]:
		w.set_block(q, 0)
		w.remove_decorations_at(q)
		game.chests.remove(q)
	w.set_block(spot + Vector3i.DOWN, 0)

	# The Flower of Fire's Ball of Fire: straight for 20 ticks, then falling;
	# in a box it bounces 5 times and goes out on the 6th.
	var box := c + Vector3i(0, 52, 0)
	for x in range(-2, 3):
		for y in range(-2, 3):
			for z in range(-2, 3):
				w.set_block(box + Vector3i(x, y, z), Data.block_id("stone") if maxi(absi(x), maxi(absi(y), absi(z))) == 2 else 0)
	var open := c + Vector3i(0, 64, 0)
	var ball := game.spawn_projectile("BallofFire", Vector3(open) + Vector3(0.5, 0.5, 0.5), Vector3(28.125, 0, 0), 48, 5.5)
	await frames(15)
	var vy15 := ball.velocity.y
	await frames(25)
	check(vy15 == 0.0 and ball.velocity.y < -5.0, "a Ball of Fire flies straight, then falls (%.1f, %.1f)" % [vy15, ball.velocity.y])
	ball.queue_free()
	ball = game.spawn_projectile("BallofFire", Vector3(box) + Vector3(0.5, 0.5, 0.5), Vector3(20, 6, 9), 48, 5.5)
	var bounced := false
	for i in 120:
		await frames(1)
		if not is_instance_valid(ball):
			break
		bounced = bounced or ball.bounces < 5
	check(bounced and not is_instance_valid(ball), "it bounces round a box and goes out")
	# It sets enemies on fire 1 time in 2.
	var target := game.spawn_npc("Zombie", Vector3(open) + Vector3(3.5, 0, 0.5))
	target.life_max = 100000
	target.life = 100000
	target.velocity = Vector3.ZERO
	var lit := 0
	for i in 12:
		target.on_fire = 0.0
		target.global_position = Vector3(open) + Vector3(3.5, -0.5, 0.5)
		game.spawn_projectile("BallofFire", target.center() - Vector3(1.0, 0, 0), Vector3(28.125, 0, 0), 48, 0.0)
		await frames(3)
		if target.on_fire > 0.0:
			lit += 1
	check(lit >= 1 and lit <= 11, "a Ball of Fire sets enemies on fire, some of the time (%d of 12)" % lit)
	clear.call()
	for x in range(-2, 3):
		for y in range(-2, 3):
			for z in range(-2, 3):
				w.set_block(box + Vector3i(x, y, z), 0)
	await frames(2)

	# The Hellwing Bow: Wooden Arrows become Hellwings, flying straight on
	# with no drop; other arrows stay arrows.
	var bow := Data.item("HellwingBow")
	p.global_position = Vector3(open) + Vector3(0.5, -1.5, 0.5)
	p.velocity = Vector3.ZERO
	p.look_at_yaw_pitch(0.0, 0.0)
	p.inventory.remove("WoodenArrow", p.inventory.count_of("WoodenArrow"))
	p.inventory.remove("HellfireArrow", p.inventory.count_of("HellfireArrow"))
	p.inventory.add("WoodenArrow", 5)
	p._shoot_ranged(bow)
	var wing: Projectile = null
	for e in game.entities.get_children():
		if e is Projectile and e.kind == "Hellwing":
			wing = e
	var fwd := p.forward()
	await frames(30)
	check(wing != null and is_instance_valid(wing) and wing.gravity == 0.0 and wing.velocity.normalized().dot(fwd) > 0.97,
			"the Hellwing Bow turns a Wooden Arrow into a Hellwing, flying on with no drop")
	p.inventory.remove("WoodenArrow", p.inventory.count_of("WoodenArrow"))
	p.inventory.add("HellfireArrow", 5)
	p._shoot_ranged(bow)
	var arrows := game.entities.get_children().filter(func(e): return e is Projectile and e.kind == "HellfireArrow")
	check(arrows.size() == 1 and arrows[0].gravity > 0.0, "other arrows stay arrows")
	p.inventory.remove("HellfireArrow", p.inventory.count_of("HellfireArrow"))
	clear.call()
	await frames(2)
	# A Hellfire Arrow blows up on what it hits, hurting what's beside it too.
	var a := game.spawn_npc("Zombie", Vector3(open) + Vector3(4.5, -1.5, 0.5))
	var b := game.spawn_npc("Zombie", Vector3(open) + Vector3(4.5, -1.5, 1.6))
	for z in [a, b]:
		z.life_max = 100000
		z.life = 100000
		z.velocity = Vector3.ZERO
	game.spawn_projectile("HellfireArrow", a.center() - Vector3(1.2, 0, 0), Vector3(30, 0, 0), 13, 0.0)
	await frames(4)
	check(a.life < a.life_max and b.life < b.life_max, "a Hellfire Arrow's blast hurts the one beside it (%d, %d)" % [a.life_max - a.life, b.life_max - b.life])
	clear.call()
	await frames(2)

	# The Treasure Magnet: items come from further off.
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	p._fall_start = p.global_position.y  # (moved down, not fallen)
	await frames(2)
	game.spawn_item("Gel", 1, p.global_position + Vector3(0, 0.9, 0) + Vector3(7.0, 0, 0))
	await frames(50)
	var gel: Array = game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "Gel")
	var far: bool = gel.size() == 1 and gel[0].global_position.distance_to(p.global_position) > 6.0
	p.accessories.slots[0] = Inventory.stack("TreasureMagnet", 1)
	await frames(50)
	check(far and (gel.is_empty() or not is_instance_valid(gel[0]) or gel[0].global_position.distance_to(p.global_position) < 4.0),
			"with a Treasure Magnet items 7 blocks off come to you")
	p.accessories.slots[0] = null
	clear.call()
	# The Restoration Potion: 90 life, 45 s of potion sickness.
	p.life = 100
	p.potion_sickness = 0.0
	p._consume(Data.item("RestorationPotion"))
	check(p.life == 190 and is_equal_approx(p.potion_sickness, 45.0), "a Restoration Potion heals 90, 45 s of sickness (%d, %.0f)" % [p.life, p.potion_sickness])
	p.potion_sickness = 0.0
	p.life = p.life_max
	p.god_mode = was_god
	await frames(2)


func _hellstone_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var was_god := p.god_mode
	p.god_mode = true
	var find := func(item: String) -> Dictionary:
		var r: Array = Data.recipes.filter(func(x): return x.result == item)
		return r[0] if not r.is_empty() else {}
	check(find.call("MoltenPickaxe").get("ingredients") == {"HellstoneBar": 20} and find.call("MoltenHamaxe").get("ingredients") == {"HellstoneBar": 15}
			and find.call("FieryGreatsword").get("ingredients") == {"HellstoneBar": 20} and find.call("MoltenFury").get("ingredients") == {"HellstoneBar": 15}
			and find.call("PhoenixBlaster").get("ingredients") == {"HellstoneBar": 10, "Handgun": 1} and find.call("MoltenPickaxe").get("station") == "iron_anvil",
			"the Hellstone gear has Terraria's recipes, at an anvil")
	var open := c + Vector3i(0, 40, 0)
	p.global_position = Vector3(open) + Vector3(0.5, -1.5, 0.5)
	p.velocity = Vector3.ZERO
	p.look_at_yaw_pitch(0.0, 0.0)
	# The Fiery Greatsword: the first enemy a swing hits erupts, hurting and
	# burning up to 3 round it.
	var sword := Data.item("FieryGreatsword")
	var zs := []
	for i in 4:
		var z := game.spawn_npc("Zombie", Vector3(open) + Vector3(0.5 + i * 1.2, -1.5, -4.5))
		z.life_max = 100000
		z.life = 100000
		z.velocity = Vector3.ZERO
		zs.append(z)
	var swing := {}
	p.on_melee_hit(zs[0], sword, swing)
	var volcanoes := game.entities.get_children().filter(func(e): return e is Projectile and e.kind == "Volcano")
	await frames(14)
	var hurt: Array = zs.filter(func(z): return z.life < z.life_max)
	check(volcanoes.size() == 1 and hurt.size() == 3 and hurt.all(func(z): return z.on_fire > 0.0),
			"a Fiery Greatsword swing's first hit erupts: 3 enemies hurt and burning (%d volcanoes, %d hurt)" % [volcanoes.size(), hurt.size()])
	p.on_melee_hit(zs[1], sword, swing)
	var again := game.entities.get_children().filter(func(e): return e is Projectile and e.kind == "Volcano" and not volcanoes.has(e))
	check(again.is_empty(), "once a swing")
	for z in zs:
		z.queue_free()
	# Molten Fury: Wooden Arrows become Flaming Arrows.
	p.inventory.remove("WoodenArrow", p.inventory.count_of("WoodenArrow"))
	var added := p.inventory.add("WoodenArrow", 3)
	var shot := p._shoot_ranged(Data.item("MoltenFury"))
	var fire := game.entities.get_children().filter(func(e): return e is Projectile and e.kind == "FireArrow")
	check(added == 0 and shot and fire.size() == 1 and fire[0].gravity > 0.0, "Molten Fury turns Wooden Arrows into Flaming Arrows")
	p.inventory.remove("WoodenArrow", p.inventory.count_of("WoodenArrow"))
	for e in game.entities.get_children():
		if e is Projectile:
			e.queue_free()
	# The Molten Hamaxe chops trees and hammers the rest.
	var trunk := open + Vector3i(0, -1, -3)
	w.set_block(trunk, Data.block_id("tree_trunk"))
	var held = p.inventory.slots[p.selected]
	p.inventory.slots[p.selected] = Inventory.stack("MoltenHamaxe", 1)
	p._use_timer = 0.0
	p._mine_damage = 0.0
	p.target = {"block": trunk, "normal": Vector3i.BACK, "id": w.get_block(trunk), "distance": 3.0}
	p.use_item()
	check(p._mine_pos == trunk and p._mine_damage > 0.0, "the Molten Hamaxe chops a tree (%.0f)" % p._mine_damage)
	w.set_block(trunk, 0)
	p.inventory.slots[p.selected] = held
	p._use_timer = 0.0
	# The Molten set: +10% melee damage, fire blocks don't burn, nor can
	# anything set you on fire; the Obsidian Skull only keeps fire blocks off.
	for i in 3:
		p.armor.slots[i] = Inventory.stack(["MoltenHelmet", "MoltenBreastplate", "MoltenGreaves"][i], 1)
	p.on_fire = 0.0
	p.god_mode = false
	p.ignite(5.0)
	check(p.on_fire == 0.0 and p.has_effect("fire_walk") and p.stat("melee_damage") >= 17.0, "the Molten set: no On Fire!, fire blocks harmless, melee damage up")
	for i in 3:
		p.armor.slots[i] = null
	p.accessories.slots[0] = Inventory.stack("ObsidianSkull", 1)
	p.ignite(5.0)
	check(p.on_fire > 0.0 and p.has_effect("fire_walk"), "an Obsidian Skull keeps fire blocks off, not On Fire!")
	p.on_fire = 0.0
	p.accessories.slots[0] = null
	p.god_mode = was_god
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	p._fall_start = p.global_position.y  # (moved down, not fallen)
	await frames(2)


## The Bound Mechanic: where she can turn up, and freed, the Mechanic.
func _bound_mechanic_checks(c: Vector3i) -> void:
	var p := game.player
	var l: Dictionary = game.world.get_layers()
	var deep := Vector3(c.x + 0.5, (float(l.surface) * 4.0 + float(l.cavern_top)) / 5.0 - 2.0, c.z + 0.5)
	var shallow := Vector3(c.x + 0.5, float(l.surface) - 1.0, c.z + 0.5)
	check(Spawner.bound_mechanic_here(game, deep) and not Spawner.bound_mechanic_here(game, shallow),
			"the Bound Mechanic turns up in the Dungeon below a fifth of the way to the caverns")
	var bound := game.spawn_npc("BoundMechanic", p.global_position + Vector3(2, 0, 0))
	await frames(2)
	check(not Spawner.bound_mechanic_here(game, deep), "one at a time")
	var mechanic: NPC = game.town.free_mechanic(bound)
	game.hud.open_chat(mechanic, NPC.dialog(NPC.MECHANIC_FREED_LINE))
	await frames(2)
	check(game.town.residents.has("Mechanic") and game.hud._chat_text.text.begins_with("Thanks!") and not Spawner.bound_mechanic_here(game, deep),
			"freed, she's the Mechanic, and no more Bound Mechanics (%s)" % game.hud._chat_text.text.left(30))
	check(mechanic.talk_line() != "" and mechanic.talk_line() != "...", "she talks (%s)" % mechanic.talk_line().left(40))
	var shop: Array = Data.npcs.Mechanic.town.shop
	check(shop.all(func(e): return Data.items.has(e if e is String else e[0])), "her shop's items all exist (%d)" % shop.size())
	game.hud.close_chat()
	mechanic.queue_free()
	game.town.residents.erase("Mechanic")
	game.town.arrived.erase("Mechanic")


## The Librarian Skeleton's books and the Water Bolt Mimic, on a stone floor
## high over the test world with a book on it.
func _book_dweller_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var o := c + Vector3i(40, 50, 30)
	var stone := Data.block_id("stone")
	for x in range(-10, 11):
		for z in range(-10, 11):
			w.set_block(o + Vector3i(x, -1, z), stone)
			for y in range(0, 6):
				w.set_block(o + Vector3i(x, y, z), 0)
	var book := o + Vector3i(6, 0, 0)
	w.set_block(book, Data.block_id("book"))
	p.global_position = Vector3(o) + Vector3(-5.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	p._fall_start = p.global_position.y
	p.look_at_yaw_pitch(PI / 2.0, 0.0)
	# The Librarian Skeleton casts off the book: it rises, harmless, then
	# flies at you.
	var lib: NPC = game.spawn_npc("LibrarianSkeleton", Vector3(o) + Vector3(3.5, 0, 0.5))
	lib._cast_t = 98.0
	var books: Array = []
	for i in 10:
		await frames(1)
		books = game.entities.get_children().filter(func(e): return e is Projectile and e.kind == "LibrarianSkeletonBook")
		if not books.is_empty():
			break
	check(books.size() == 1 and books[0].global_position.distance_to(Vector3(book) + Vector3(0.5, 0.5, 0.5)) < 0.6 and books[0].velocity.y > 0.0,
			"a Librarian Skeleton's book rises off the placed book")
	if books.size() == 1:
		var b: Projectile = books[0]
		var life := p.life
		p.god_mode = false
		await frames(20)
		check(is_instance_valid(b) and not b._launched and p.life == life, "hurting nothing while it rises")
		await frames(40)
		var to_you: Vector3 = p.global_position + Vector3(0, 0.9, 0) - b.global_position
		check(is_instance_valid(b) and b._launched and b.velocity.normalized().dot(to_you.normalized()) > 0.8 and b.velocity.length() > 30.0,
				"then it flies at you (%.1f blocks/s)" % (b.velocity.length() if is_instance_valid(b) else 0.0))
		p.god_mode = true
		if is_instance_valid(b):
			b.queue_free()
	lib.queue_free()
	# The Water Bolt Mimic sits as a book till it's hurt.
	var mimic: NPC = game.spawn_npc("WaterBoltMimic", Vector3(book) + Vector3(0.5, 0.5, 0.5))
	var at := mimic.global_position
	p.global_position = Vector3(book) + Vector3(-1.5, 0, 0.5)
	await frames(60)
	check(mimic.global_position.distance_to(at) < 0.01 and mimic._mimic == 3 and mimic._mimic_f == 0, "a Water Bolt Mimic sits still as a book, even with you by it")
	mimic.hit(1, 0.0, Vector3.RIGHT, 0.0)
	await frames(10)
	check(mimic._mimic == 4 and mimic.global_position.distance_to(at) < 0.01, "hurt, it wakes")
	p.global_position = Vector3(o) + Vector3(-9.5, 0, 0.5)
	await frames(110)
	check(mimic._mimic != 3 and mimic._mimic != 4 and mimic.global_position.distance_to(at) > 0.3, "and comes after you (%.1f blocks)" % mimic.global_position.distance_to(at))
	mimic.queue_free()
	for x in range(-10, 11):
		for z in range(-10, 11):
			for y in range(-1, 6):
				w.set_block(o + Vector3i(x, y, z), 0)
	for e in game.entities.get_children():
		if e is Projectile:
			e.queue_free()


func _dungeon_enemy_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var was_god := p.god_mode
	p.god_mode = true
	var clear := func() -> void:
		for n in game.npcs():
			if not n.def.get("persistent", false) and n.def.ai != "town" and n.def.ai != "dummy":
				n.queue_free()
		for e in game.entities.get_children():
			if e is Projectile or e is ItemDrop:
				e.queue_free()
	clear.call()
	# Terraria's Dungeon chain.
	var share := func(wall: int, near: bool, kind: String) -> float:
		var n := 0
		for i in 20000:
			if Spawner.dungeon_pick(wall, near) == kind:
				n += 1
		return n / 20000.0
	var skull: float = share.call(0, false, "CursedSkull")
	var spike: float = share.call(1, false, "SpikeBall")
	var wheel: float = share.call(2, false, "BlazingWheel")
	var caster: float = share.call(2, false, "DarkCaster")
	var slime: float = share.call(0, false, "DungeonSlime")
	check(absf(skull - 0.139) < 0.012 and absf(spike - 0.324) < 0.015 and absf(wheel - 0.194) < 0.013 and absf(caster - 0.111) < 0.01 and absf(slime - 0.0286) < 0.006
			and share.call(1, true, "SpikeBall") == 0.0, "the Dungeon's spawns are Terraria's chain (skull %.3f, spike %.3f, wheel %.3f, caster %.3f, slime %.3f)" % [skull, spike, wheel, caster, slime])
	# By a placed book (1.4.5): 1 in 8 a Water Bolt Mimic, else 1 in 10 a
	# Librarian Skeleton; with no book, nothing.
	var by_book := func(kind: String, found: bool) -> float:
		var n := 0
		for i in 20000:
			if Spawner.dungeon_pick(2, false, func() -> bool: return found) == kind:
				n += 1
		return n / 20000.0
	var mimic: float = by_book.call("WaterBoltMimic", true)
	var librarian: float = by_book.call("LibrarianSkeleton", true)
	var no_book: float = by_book.call("", false)
	check(absf(mimic - 0.0833) < 0.008 and absf(librarian - 0.0583) < 0.007 and absf(no_book - 0.1416) < 0.01 and by_book.call("WaterBoltMimic", false) == 0.0,
			"by a book, Water Bolt Mimics (%.3f) and Librarian Skeletons (%.3f); no book, no spawn (%.3f)" % [mimic, librarian, no_book])
	await _book_dweller_checks(c)
	await _bound_mechanic_checks(c)
	# Its walls by worldgen's parts: the last blob a spot is in.
	w.add_decoration("dungeon_part", Vector3i(5000, 0, 5000), 1 + 4 * 300)
	w.add_decoration("dungeon_part", Vector3i(5010, 0, 5000), 2 + 4 * 100)
	game._dungeon_parts.clear()
	check(game.dungeon_wall(Vector3(5000, 0, 5000)) == 1 and game.dungeon_wall(Vector3(5012, 0, 5000)) == 2 and game.dungeon_wall(Vector3(6000, 0, 6000)) == 0,
			"its walls: brick, slab or tiled by worldgen's blobs")
	w.remove_decorations_at(Vector3i(5000, 0, 5000))
	w.remove_decorations_at(Vector3i(5010, 0, 5000))
	game._dungeon_parts.clear()
	# A floor up in the air to try them on, a stone pillar in the middle.
	var o := c + Vector3i(30, 45, 0)
	for x in range(-12, 13):
		for z in range(-12, 13):
			for y in range(-1, 8):
				var pillar := y >= 0 and absi(x) <= 1 and absi(z - 4) <= 1
				w.set_block(o + Vector3i(x, y, z), Data.block_id("stone") if y == -1 or pillar else 0)
	p.global_position = Vector3(o) + Vector3(0.5, 0, 8.5)
	p.velocity = Vector3.ZERO
	await frames(3)
	# Angry Bones walk at you.
	var bones := game.spawn_npc("AngryBones", Vector3(o) + Vector3(-8.5, 0, 8.5))
	var d0 := bones.global_position.distance_to(p.global_position)
	await frames(90)
	check(bones.global_position.distance_to(p.global_position) < d0 - 2.5, "Angry Bones walk at you (%.1f -> %.1f)" % [d0, bones.global_position.distance_to(p.global_position)])
	# Their chain: a Bone Wand, Tally Counter or Golden Key now and then, else
	# 1-3 Bones.
	var bone_drops := 0
	for i in 5:
		var b := game.spawn_npc("AngryBones", Vector3(o) + Vector3(-6.5, 0, -6.5))
		var at := b.center()
		b.hit(9999, 0.0, Vector3.RIGHT, 0.0)
		await frames(1)
		for e in game.entities.get_children():
			if e is ItemDrop and e.global_position.distance_to(at) < 3.0 and e.item in ["Bone", "BoneWand", "TallyCounter", "GoldenKey"]:
				bone_drops += 1
				e.queue_free()
	check(bone_drops == 5, "each Angry Bones drops one of its chain: Bones mostly (%d of 5)" % bone_drops)
	clear.call()
	await frames(2)
	# A Cursed Skull comes through the stone at you.
	var sk := game.spawn_npc("CursedSkull", Vector3(o) + Vector3(0.5, 1.5, -2.5))
	var s0 := sk.center().distance_to(p.center())
	await frames(120)
	check(is_instance_valid(sk) and sk.center().distance_to(p.center()) < s0 - 1.5, "a Cursed Skull flies through the stone at you (%.1f -> %.1f)" % [s0, sk.center().distance_to(p.center())])
	clear.call()
	await frames(2)
	# A Spike Ball swings round where it hangs; it can't be hurt.
	var ball := game.spawn_npc("SpikeBall", Vector3(o) + Vector3(-6.5, 4.0, -6.5))
	await frames(2)
	var hang: Vector3 = ball._hang
	var far := 0.0
	for i in 120:
		await frames(1)
		far = maxf(far, ball.center().distance_to(hang))
	ball.hit(500, 0.0, Vector3.RIGHT, 0.0)
	check(far > 1.0 and far < 14.0 and ball.life == ball.life_max and ball._chain.size() > 1, "a Spike Ball swings on its chain (out to %.1f blocks), unhurt" % far)
	clear.call()
	# A Blazing Wheel rolls along the floor and up the pillar's side; it can't
	# be hurt either.
	var wh := game.spawn_npc("BlazingWheel", Vector3(o) + Vector3(-6.5, 0.0, 4.5))
	var w0 := wh.global_position
	var touching := 0
	for i in 90:
		await frames(1)
		var cell := Vector3i(wh.center().floor())
		for dd in [Vector3i.DOWN, Vector3i.UP, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			if w.is_solid(cell + dd * 2) or w.is_solid(cell + dd):
				touching += 1
				break
	wh.hit(500, 0.0, Vector3.RIGHT, 0.0)
	check(wh.global_position.distance_to(w0) > 2.0 and touching > 65 and wh.life == wh.life_max, "a Blazing Wheel rolls along the blocks (%d of 90 ticks by one), unhurt" % touching)
	clear.call()
	await frames(2)
	# A Dark Caster casts Water Spheres at you.
	var dc := game.spawn_npc("DarkCaster", Vector3(o) + Vector3(-8.5, 0, -8.5))
	var spheres := []
	for i in 330:
		await frames(1)
		for e in game.entities.get_children():
			if e is Projectile and e.kind == "WaterSphere" and not spheres.has(e):
				spheres.append(e)
	check(spheres.size() >= 1 and is_instance_valid(dc), "a Dark Caster casts Water Spheres (%d)" % spheres.size())
	clear.call()
	await frames(2)
	# A Dungeon Slime always has a Golden Key in it.
	var ds := game.spawn_npc("DungeonSlime", Vector3(o) + Vector3(6.5, 0, -6.5))
	var ds_at := ds.center()
	ds.hit(9999, 0.0, Vector3.RIGHT, 0.0)
	await frames(1)
	check(game.entities.get_children().any(func(e): return e is ItemDrop and e.item == "GoldenKey" and e.global_position.distance_to(ds_at) < 3.0), "a Dungeon Slime drops a Golden Key")
	clear.call()
	# The Tally Counter: the last creature you hit and how many you've killed.
	game.kill_counts.erase("AngryBones")
	p.last_creature_hit = ""
	p.inventory.add("TallyCounter", 1)
	check("Kill count unavailable" in game.hud.info_text(), "the Tally Counter, before you've hit anything: %s" % game.hud.info_text())
	for k in ["AngryBones", "AngryBonesBig"]:
		var e := game.spawn_npc(k, Vector3(o) + Vector3(6.5, 0, 6.5))
		e.hit(9999, 0.0, Vector3.RIGHT, 0.0)
	await frames(1)
	check("Angry Bones: 2" in game.hud.info_text(), "then the Angry Bones killed, every kind of them: %s" % game.hud.info_text())
	p.inventory.remove("TallyCounter", 1)
	clear.call()
	# Cracked brick: landing hard on it shatters it under you; firm ground
	# doesn't; explosions break it, not the other dungeon brick.
	var cb := Data.block_id("cracked_blue_brick")
	for x in range(-2, 3):
		for z in range(-2, 3):
			w.set_block(o + Vector3i(x, -1, z) + Vector3i(0, 0, -8), cb)
			w.set_block(o + Vector3i(x, -2, z) + Vector3i(0, 0, -8), cb)
	# (At most 10 px a tick, Terraria's fall: it beats the random 2-11 8 times
	# in 10, so a few tries.)
	var shattered := false
	for attempt in 5:
		p.global_position = Vector3(o) + Vector3(0.5, 2.5, -7.5)
		p.velocity = Vector3(0, -30.0, 0)
		await frames(6)
		if w.get_block(o + Vector3i(0, -1, -8)) == 0:
			shattered = true
			break
	check(shattered, "landing hard on cracked brick shatters it")
	p.global_position = Vector3(o) + Vector3(0.5, 0, 8.5)
	p.velocity = Vector3.ZERO
	p._fall_start = p.global_position.y
	check(Game.blastproof(Data.block(Data.block_id("blue_brick"))) and not Game.blastproof(Data.block(cb)), "explosions break cracked brick, not the rest")
	for x in range(-2, 3):
		for z in range(-2, 3):
			for y in [-1, -2]:
				w.set_block(o + Vector3i(x, y, z - 8), Data.block_id("stone") if y == -1 else 0)
	# The Bone Wand: places Bone Blocks, using up Bones.
	var held = p.inventory.slots[p.selected]
	p.inventory.slots[p.selected] = Inventory.stack("BoneWand", 1)
	p.inventory.remove("Bone", p.inventory.count_of("Bone"))
	var floor_at := o + Vector3i(5, -1, 0)
	p.target = {"block": floor_at, "normal": Vector3i.UP, "id": w.get_block(floor_at), "distance": 3.0}
	var none := p._place(Data.item("BoneWand"))
	p.inventory.add("Bone", 2)
	var placed := p._place(Data.item("BoneWand"))
	check(not none and placed and Data.block(w.get_block(floor_at + Vector3i.UP)).get("name", "") == "bone_block" and p.inventory.count_of("Bone") == 1
			and p.inventory.slots[p.selected] != null, "the Bone Wand places a Bone Block for a Bone (none without)")
	p.inventory.slots[p.selected] = held
	p.inventory.remove("Bone", p.inventory.count_of("Bone"))
	for x in range(-12, 13):
		for z in range(-12, 13):
			for y in range(-1, 8):
				w.set_block(o + Vector3i(x, y, z), 0)
	p.god_mode = was_god
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	p._fall_start = p.global_position.y  # (moved down, not fallen)
	await frames(2)


## Terraria's boulder kinds (AI 25's variants), rolled down a tunnel along x
## toward its +x end.
func _boulder_kind_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var was_god := p.god_mode
	p.god_mode = true
	var o := c + Vector3i(-30, 45, 0)
	var stone := Data.block_id("stone")
	for x in range(-12, 13):
		for z in range(-3, 4):
			for y in range(-4, 12):
				var open := z == 0 and y >= 0 and y < 4 and absi(x) < 12
				w.set_block(o + Vector3i(x, y, z), 0 if open else stone)
	for e in game.entities.get_children():
		if e is Projectile:
			e.queue_free()
	p.global_position = Vector3(o) + Vector3(-10.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	p._fall_start = p.global_position.y
	p.look_at_yaw_pitch(-PI / 2.0, 0.0)
	var roll := func(kind: String, from_x: float, speed: float) -> Projectile:
		var b: Projectile = game.spawn_projectile(kind, Vector3(o) + Vector3(from_x, 0.5, 0.5), Vector3(speed, 0, 0), 100 if kind == "RainbowBoulder" else 70, 10.0, 0.0, 0.0, 1.0, false)
		b.boulder = true
		b._roll = Vector3.RIGHT
		return b
	# Lava Boulder: into the end wall it breaks, and lava fills round it.
	var lava: Projectile = roll.call("LavaBoulder", 6.5, 15.0)
	for i in 60:
		await frames(1)
		if not is_instance_valid(lava):
			break
	var pooled := 0
	for x in range(6, 12):
		for y in range(0, 4):
			if w.get_liquid(o + Vector3i(x, y, 0)) == Vector2i(Player.LIQ_LAVA, 63):
				pooled += 1
	check(not is_instance_valid(lava) and pooled >= 3, "a Lava Boulder breaks on a wall and leaves lava round it (%d cells)" % pooled)
	for x in range(-12, 13):
		for y in range(0, 4):
			w.set_liquid(o + Vector3i(x, y, 0), 0, 0)
	# Bouncy Boulder: the wall bounces it back.
	var bouncy: Projectile = roll.call("BouncyBoulder", 6.5, 15.0)
	var back := false
	for i in 60:
		await frames(1)
		if is_instance_valid(bouncy) and bouncy.velocity.x < -5.0:
			back = true
			break
	check(back, "a Bouncy Boulder bounces off the wall")
	if is_instance_valid(bouncy):
		bouncy.queue_free()
	# Ghoulder: the wall turns it into a ghost, which comes through the rock
	# at you while you look away and stops while you look at it.
	p.look_at_yaw_pitch(PI / 2.0, 0.0)
	var ghoulder: Projectile = roll.call("Ghoulder", 6.5, 15.0)
	for i in 60:
		await frames(1)
		if not is_instance_valid(ghoulder) or ghoulder._ghost:
			break
	check(is_instance_valid(ghoulder) and ghoulder._ghost, "a Ghoulder turns into a ghost on hitting a wall")
	if is_instance_valid(ghoulder):
		var d0 := ghoulder.global_position.distance_to(p.global_position)
		await frames(40)
		var d1 := ghoulder.global_position.distance_to(p.global_position)
		check(d1 < d0 - 1.0 and ghoulder.frame > 0, "it flies at you while you look away (%.1f -> %.1f blocks)" % [d0, d1])
		p.look_at_yaw_pitch(-PI / 2.0, 0.0)
		await frames(40)
		var flat := Vector2(ghoulder.velocity.x, ghoulder.velocity.z).length()
		check(flat < 2.0, "and stops while you look at it (%.1f blocks/s)" % flat)
		ghoulder.queue_free()
	# The pet boulder breaks landing hard.
	var pet: Projectile = game.spawn_projectile("BoulderThatSpawnsPet", Vector3(o) + Vector3(0.5, 2.5, 0.5), Vector3(0, -25.0, 0), 70, 10.0, 0.0, 0.0, 1.0, false)
	pet.boulder = true
	await frames(10)
	check(not is_instance_valid(pet), "the pet boulder breaks on a hard landing")
	# Rainbow Boulder: friendly - it never hurts you - and it leaps at you.
	p.god_mode = false
	p.life = p.life_max
	p.global_position = Vector3(o) + Vector3(-6.5, 0, 0.5)
	var rainbow: Projectile = roll.call("RainbowBoulder", 4.5, 0.0)
	var d_start := rainbow.global_position.distance_to(p.global_position)
	var nearest := d_start
	for i in 120:
		await frames(1)
		if not is_instance_valid(rainbow):
			break
		nearest = minf(nearest, rainbow.global_position.distance_to(p.global_position))
	check(nearest < d_start - 3.0, "a Rainbow Boulder leaps at you (%.1f -> %.1f blocks)" % [d_start, nearest])
	check(p.life == p.life_max, "without hurting you (%d)" % p.life)
	if is_instance_valid(rainbow):
		rainbow.queue_free()
	for x in range(-14, 15):
		for z in range(-5, 6):
			for y in range(-6, 14):
				w.set_block(o + Vector3i(x, y, z), 0)
	p.god_mode = was_god


## Junction Boxes, Wire Bulbs, Teleporters, Pixel Boxes, the Projectile
## Pressure Pad, the Laser Ruler.
func _wiring_more_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var wr: Wiring = game.wiring
	var was_god := p.god_mode
	p.god_mode = true
	var o := c + Vector3i(-30, 45, -30)
	var stone := Data.block_id("stone")
	for x in range(-10, 11):
		for z in range(-10, 11):
			w.set_block(o + Vector3i(x, -1, z), stone)
			for y in range(0, 8):
				w.set_block(o + Vector3i(x, y, z), 0)
	p.global_position = Vector3(o) + Vector3(-8.5, 0, -8.5)
	p._fall_start = p.global_position.y
	var lamp_on := func(at: Vector3i) -> bool: return Data.block(w.get_block(at)).name == "brass_lantern"
	# Two red wires crossing at a Junction Box don't join.
	var lever := o + Vector3i(-5, 0, 0)
	w.set_block(lever, Data.block_id("lever"))
	var lamp_a := o + Vector3i(5, 0, 0)
	var lamp_b := o + Vector3i(0, 0, 5)
	for l in [lamp_a, lamp_b]:
		w.set_block(l, Data.block_id("brass_lantern"))
	wr.lay(lever, lamp_a, Wiring.RED)
	wr.lay(o + Vector3i(0, 0, -5), lamp_b, Wiring.RED)
	var box := o
	w.set_block(box, Data.block_id("junction_box"))
	game.hit_switch(lever)
	await frames(2)
	check(not lamp_on.call(lamp_a) and lamp_on.call(lamp_b), "wires crossing at a Junction Box: the signal goes straight on, not round the corner")
	w.set_block(box, 0)
	game.hit_switch(lever)
	await frames(2)
	check(lamp_on.call(lamp_a) and not lamp_on.call(lamp_b), "without it they join")
	for x in range(-10, 11):
		for z in range(-10, 11):
			wr.remove(o + Vector3i(x, 0, z), 31)
	# A Wire Bulb lights a light for each colour that reaches it.
	var bulb := o + Vector3i(0, 0, 3)
	w.set_block(bulb, Data.block_id("wire_bulb"))
	wr.lay(lever, bulb, Wiring.RED)
	wr.lay(lever, bulb, Wiring.BLUE)
	game.hit_switch(lever)
	await frames(2)
	check(Data.block(w.get_block(bulb)).name == "wire_bulb_5", "a Wire Bulb on red and blue wire lights both (%s)" % Data.block(w.get_block(bulb)).name)
	wr.remove(bulb, 31)
	# Two Teleporters on a wire swap whoever stands on them.
	var t1 := o + Vector3i(-3, 0, -6)
	var t2 := o + Vector3i(6, 0, -6)
	for t in [t1, t2]:
		w.set_block(t, Data.block_id("teleporter"))
	for x in range(-10, 11):
		for z in range(-10, 11):
			wr.remove(o + Vector3i(x, 0, z), 31)
	wr.lay(lever, t1, Wiring.GREEN)
	wr.lay(t1, t2, Wiring.GREEN)
	p.global_position = Vector3(t1) + Vector3(0.5, 0.05, 0.5)
	p._fall_start = p.global_position.y
	await frames(2)
	game.hit_switch(lever)
	await frames(2)
	check(p.global_position.distance_to(Vector3(t2) + Vector3(0.5, 0.05, 0.5)) < 0.5, "a signal takes you from one Teleporter to the other")
	p.global_position = Vector3(o) + Vector3(-8.5, 0, -8.5)
	for x in range(-10, 11):
		for z in range(-10, 11):
			for y in range(0, 6):
				wr.remove(o + Vector3i(x, y, z), 31)
	# A Pixel Box switches only when a signal reaches it across and up or down
	# at once.
	var px := o + Vector3i(2, 2, 2)
	w.set_block(px, Data.block_id("pixel_box"))
	wr.lay(lever, px + Vector3i(-1, 0, 0), Wiring.RED)
	wr.add(px, Wiring.RED)
	game.hit_switch(lever)
	await frames(2)
	var across_only: String = Data.block(w.get_block(px)).name
	wr.lay(lever, px + Vector3i(0, 3, 0), Wiring.BLUE)
	wr.lay(px + Vector3i(0, 3, 0), px, Wiring.BLUE)
	game.hit_switch(lever)
	await frames(2)
	check(across_only == "pixel_box" and Data.block(w.get_block(px)).name == "pixel_box_on", "a Pixel Box lights when signals cross in it, not from one way (%s)" % across_only)
	for x in range(-10, 11):
		for z in range(-10, 11):
			for y in range(0, 8):
				wr.remove(o + Vector3i(x, y, z), 31)
	# The Projectile Pressure Pad: an arrow sets it off.
	var pad := o + Vector3i(0, 0, -3)
	w.set_block(pad, Data.block_id("projectile_pressure_pad"))
	w.set_block(lamp_a, Data.block_id("brass_lantern"))
	wr.lay(pad, lamp_a, Wiring.RED)
	p.global_position = Vector3(pad) + Vector3(0.5, 0.05, 0.5)
	await frames(3)
	check(lamp_on.call(lamp_a), "standing on the Projectile Pressure Pad does nothing")
	p.global_position = Vector3(o) + Vector3(-8.5, 0, -8.5)
	game.spawn_projectile("WoodenArrowFriendly", Vector3(pad) + Vector3(0.5, 0.4, -2.5), Vector3(0, 0, 20), 5, 0.0)
	for i in 40:
		await frames(1)
		if not lamp_on.call(lamp_a):
			break
	check(not lamp_on.call(lamp_a), "an arrow through it sets it off")
	# The Laser Ruler draws its lines through what you aim at.
	var acc_was = p.accessories.slots[0]
	p.accessories.slots[0] = Inventory.stack("LaserRuler", 1)
	p.look_at_yaw_pitch(0.0, -PI / 2.0 + 0.01)
	await frames(3)
	check(game.laser_ruler.visible, "the Laser Ruler shows its lines")
	p.accessories.slots[0] = acc_was
	await frames(2)
	check(not game.laser_ruler.visible, "and not once it's off")
	for e in game.entities.get_children():
		if e is Projectile or e is ItemDrop:
			e.queue_free()
	for x in range(-10, 11):
		for z in range(-10, 11):
			for y in range(-1, 8):
				w.set_block(o + Vector3i(x, y, z), 0)
				wr.remove(o + Vector3i(x, y, z), 31)
	p.god_mode = was_god


## Terraria's wiring: wrenches, levers, plates, actuators, timers, geysers.
func _wiring_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var wr: Wiring = game.wiring
	var was_god := p.god_mode
	p.god_mode = true
	var o := c + Vector3i(30, 45, -30)
	var stone := Data.block_id("stone")
	for x in range(-10, 11):
		for z in range(-10, 11):
			w.set_block(o + Vector3i(x, -1, z), stone)
			for y in range(0, 8):
				w.set_block(o + Vector3i(x, y, z), 0)
	for e in game.entities.get_children():
		if e is Projectile or e is ItemDrop:
			e.queue_free()
	p.global_position = Vector3(o) + Vector3(-6.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	p._fall_start = p.global_position.y
	await frames(2)
	# A wrench lays red wire on what you aim at, a Wire each.
	p.inventory.slots[9] = Inventory.stack("Wrench", 1)
	p.inventory.add("Wire", 5)
	p.select(9)
	p.look_at_yaw_pitch(0.0, -PI / 2.0 + 0.01)
	await frames(3)
	var aimed: Vector3i = p.target.get("block", Vector3i.ZERO)
	var wires_before := p.inventory.count_of("Wire")
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	check(wr.mask(aimed) & Wiring.RED and p.inventory.count_of("Wire") == wires_before - 1, "a Wrench lays red wire on the block you aim at, using up a Wire")
	check(WireView.showing(p) and game.wire_view.visible, "holding it, you see the wiring")
	p.inventory.slots[9] = Inventory.stack("WireCutter", 1)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	await frames(2)
	var back := game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "Wire")
	check(wr.mask(aimed) == 0 and back.size() == 1, "the Wire Cutter takes it back (and the Wire)")
	for e in back:
		e.queue_free()
	p.inventory.slots[9] = null
	p.inventory.remove("Wire", p.inventory.count_of("Wire"))
	p.select(0)
	await frames(2)
	check(not game.wire_view.visible, "without anything mechanical in hand you don't")
	# A lever wired to a door, a lantern and an actuated block.
	var lever := o + Vector3i(-4, 0, 0)
	w.set_block(lever, Data.block_id("lever"))
	var door := o + Vector3i(4, 0, 0)
	w.set_block(door, Data.block_id("wooden_door"))
	w.set_block(door + Vector3i.UP, Data.block_id("door_top"))
	var lamp := o + Vector3i(0, 4, 0)
	w.set_block(lamp, Data.block_id("brass_lantern"))
	var gate := o + Vector3i(0, 0, 3)
	w.set_block(gate, stone)
	wr.lay(lever, door, Wiring.RED)
	wr.lay(lever, lamp, Wiring.BLUE)
	wr.lay(lever, gate, Wiring.GREEN)
	wr.add(gate, Wiring.ACTUATOR)
	game.hit_switch(lever)
	await frames(2)
	check(Data.block(w.get_block(lever)).name == "lever_on", "a lever flips")
	check(Doors.is_open(Data.block(w.get_block(Doors.bottom(w, door)))), "its signal opens the door on its red wire")
	check(Data.block(w.get_block(lamp)).name == "brass_lantern_off", "switches off the lantern on its blue wire")
	check(w.is_inactive(gate) and not w.is_solid(gate), "and actuates the block on its green wire: it isn't solid")
	# Torches, candles, chandeliers, gemspark... switch too (Terraria's
	# Toggle* in HitWireSingle: their off looks).
	var torch := o + Vector3i(-4, 0, 2)
	w.set_block(torch, Data.block_id("torch"))
	var gem := o + Vector3i(-3, 0, 2)
	w.set_block(gem, Data.block_id("ruby_gemspark_block"))
	wr.lay(lever, torch, Wiring.YELLOW)
	wr.add(gem, Wiring.YELLOW)
	await frames(2)
	var lit_torch := w.get_light(Vector3(torch) + Vector3(0.5, 0.5, 0.5))
	game.hit_switch(lever)
	await frames(2)
	check(not w.is_inactive(gate) and w.is_solid(gate) and Data.block(w.get_block(lamp)).name == "brass_lantern"
			and not Doors.is_open(Data.block(w.get_block(Doors.bottom(w, door)))), "flipped back, all back as they were")
	check(Data.block(w.get_block(torch)).name == "torch_off" and Data.block(w.get_block(gem)).name == "ruby_gemspark_block_off"
			and w.get_light(Vector3(torch) + Vector3(0.5, 0.5, 0.5)).r < lit_torch.r, "a torch and a gemspark block on the wire switch off (and the torch's light goes)")
	game.hit_switch(lever)
	await frames(2)
	check(Data.block(w.get_block(torch)).name == "torch", "and on again")
	game.hit_switch(lever)
	await frames(2)
	var saved := wr.save_state()
	wr.load_state(game, saved)
	check(wr.mask(lever) == Wiring.RED | Wiring.BLUE | Wiring.GREEN | Wiring.YELLOW and wr.mask(gate) & Wiring.ACTUATOR, "the wiring saves and loads")
	# Plates: red by anyone, blue only by you, yellow by anything but you;
	# orange by you, breaking.
	var plate := func(kind: String, by_npc: bool) -> bool:
		var at := o + Vector3i(-2, 0, -4)
		w.set_block(at, Data.block_id(kind))
		wr.lay(at, gate, Wiring.YELLOW)
		var was_off := w.is_inactive(gate)
		var npc: NPC = null
		if by_npc:
			p.global_position = Vector3(o) + Vector3(-8.5, 0, -8.5)
			npc = game.spawn_npc("BlueSlime", Vector3(at) + Vector3(0.5, 0.05, 0.5))
			npc.velocity = Vector3.ZERO
		else:
			p.global_position = Vector3(at) + Vector3(0.5, 0.05, 0.5)
		await frames(3)
		var fired := w.is_inactive(gate) != was_off
		if npc != null:
			npc.queue_free()
		p.global_position = Vector3(o) + Vector3(-8.5, 0, -8.5)
		await frames(2)
		wr.remove(at, 31)
		return fired
	var red_you: bool = await plate.call("red_pressure_plate", false)
	var red_npc: bool = await plate.call("red_pressure_plate", true)
	var blue_you: bool = await plate.call("blue_pressure_plate", false)
	var blue_npc: bool = await plate.call("blue_pressure_plate", true)
	var yellow_you: bool = await plate.call("yellow_pressure_plate", false)
	var yellow_npc: bool = await plate.call("yellow_pressure_plate", true)
	check(red_you and red_npc and blue_you and not blue_npc and not yellow_you and yellow_npc,
			"pressure plates: red by anyone, blue by you alone, yellow by anything but you (%s)" % [[red_you, red_npc, blue_you, blue_npc, yellow_you, yellow_npc]])
	var orange_at := o + Vector3i(-2, 0, -4)
	var orange: bool = await plate.call("orange_pressure_plate", false)
	check(orange and w.get_block(orange_at) == 0, "an orange plate goes off once and breaks")
	w.set_inactive(gate, false)
	# A timer that's on signals every second: the lantern blinks.
	var timer := o + Vector3i(2, 1, -2)
	w.set_block(timer, Data.block_id("timer_1s"))
	wr.lay(timer, lamp, Wiring.RED)
	game.wiring.toggle_timer(game, timer)
	var flips := 0
	var last := w.get_block(lamp)
	# Game time, not the wall clock: under --fixed-fps a fast machine runs
	# several game seconds per real one.
	var t := 0.0
	while t < 2.5:
		await frames(1)
		t += 1.0 / Engine.physics_ticks_per_second
		if w.get_block(lamp) != last:
			flips += 1
			last = w.get_block(lamp)
	check(Data.block(w.get_block(timer)).name == "timer_1s_on" and flips == 2, "a 1 Second Timer switched on signals each second (%d in 2.5 s)" % flips)
	game.wiring.toggle_timer(game, timer)
	# A Geyser spouts when you step on it.
	var gey := o + Vector3i(6, 0, -6)
	w.set_block(gey, Data.block_id("geyser"))
	p.global_position = Vector3(gey) + Vector3(0.5, 0.05, 0.5)
	await frames(3)
	check(game.entities.get_children().any(func(e): return e is Projectile and e.geyser), "a Geyser spouts fire when you step on it")
	# A boulder whose ground is dug out rolls.
	var rock := o + Vector3i(6, 0, 6)
	w.set_block(rock, Data.block_id("boulder"))
	w.set_block(rock + Vector3i.DOWN, 0)
	game.settle_falling(rock)
	check(w.get_block(rock) == 0 and game.entities.get_children().any(func(e): return e is Projectile and e.boulder), "a boulder with nothing under it falls")
	for e in game.entities.get_children():
		if e is Projectile or e is ItemDrop:
			e.queue_free()
	for x in range(-10, 11):
		for z in range(-10, 11):
			for y in range(-1, 8):
				w.set_block(o + Vector3i(x, y, z), 0)
				wr.remove(o + Vector3i(x, y, z), 31)
	p.god_mode = was_god


func _trap_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var was_god := p.god_mode
	p.god_mode = true
	var o := c + Vector3i(-30, 45, 0)
	var stone := Data.block_id("stone")
	# A tunnel along x (4 tall, 1 wide), rock round it.
	for x in range(-12, 13):
		for z in range(-3, 4):
			for y in range(-4, 12):
				var open := z == 0 and y >= 0 and y < 4 and absi(x) < 12
				w.set_block(o + Vector3i(x, y, z), 0 if open else stone)
	var plate := o
	w.set_block(plate, Data.block_id("gray_pressure_plate"))
	# A dart trap in the tunnel's end, facing back down it (-x: FACING 3).
	var dart := o + Vector3i(12, 1, 0)
	w.set_block(dart, Data.block_id("dart_trap"))
	game.block_rotations[Chests.key(dart)] = 3
	# Explosives under the floor, and a boulder over a shaft.
	var bomb := o + Vector3i(-6, -3, 0)
	w.set_block(bomb, Data.block_id("explosives"))
	var shaft_x := o + Vector3i(-3, 0, 0)
	for y in range(4, 9):
		w.set_block(shaft_x + Vector3i(0, y, 0), 0)
	var boulder := shaft_x + Vector3i(0, 9, 0)
	w.set_block(boulder, Data.block_id("boulder"))
	# It rests on two blocks of stone with actuators (as worldgen leaves them).
	for k in [1, 2]:
		w.set_block(boulder + Vector3i.DOWN * k, stone)
		game.wiring.add(boulder + Vector3i.DOWN * k, Wiring.ACTUATOR)
	game.wiring.lay(plate, dart, Wiring.RED)
	game.wiring.lay(plate, boulder + Vector3i.DOWN, Wiring.RED)
	var bomb_plate := o + Vector3i(-9, 0, 0)
	w.set_block(bomb_plate, Data.block_id("brown_pressure_plate"))
	game.wiring.lay(bomb_plate, bomb, Wiring.YELLOW)
	for e in game.entities.get_children():
		if e is Projectile:
			e.queue_free()
	p.global_position = Vector3(o) + Vector3(2.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	p._fall_start = p.global_position.y
	await frames(3)
	# Stepping onto the plate: a Poison Dart out of the trap, the boulder down.
	p.global_position = Vector3(plate) + Vector3(0.5, 0.05, 0.5)
	await frames(2)
	var darts := game.entities.get_children().filter(func(e): return e is Projectile and e.kind == "PoisonDart")
	var rocks := game.entities.get_children().filter(func(e): return e is Projectile and e.kind == "Boulder")
	check(darts.size() == 1 and darts[0].velocity.x < -40.0 and not darts[0].friendly, "a pressure plate fires its dart trap: a Poison Dart down the tunnel (%d)" % darts.size())
	check(rocks.size() == 1 and w.get_block(boulder) == 0 and w.is_inactive(boulder + Vector3i.DOWN) and w.is_inactive(boulder + Vector3i.DOWN * 2),
			"and its actuators switch off the stone under the boulder: it drops")
	p.global_position = Vector3(o) + Vector3(-11.5, 0, 0.5)
	await frames(1)
	if rocks.size() == 1:
		var rock: Projectile = rocks[0]
		var fastest := 0.0
		for i in 90:
			await frames(1)
			if not is_instance_valid(rock):
				break
			fastest = maxf(fastest, Vector2(rock.velocity.x, rock.velocity.z).length())
		check(fastest > 5.0, "the boulder lands and rolls (%.1f blocks/s)" % fastest)
	# Off and on again soon after: the dart trap is still cooling down.
	p.global_position = Vector3(o) + Vector3(2.5, 0, 0.5)
	await frames(1)
	p.global_position = Vector3(plate) + Vector3(0.5, 0.05, 0.5)
	await frames(1)
	check(game.entities.get_children().filter(func(e): return e is Projectile and e.kind == "PoisonDart").size() <= 1, "200 ticks between darts")
	# Explosives: the blast takes the rock round them.
	var round_bomb := w.get_block(bomb + Vector3i(1, 0, 0))
	p.global_position = Vector3(bomb_plate) + Vector3(0.5, 0.05, 0.5)
	await frames(2)
	check(w.get_block(bomb) == 0 and w.get_block(bomb + Vector3i(1, 0, 0)) == 0 and round_bomb != 0, "a plate sets off its explosives, blasting the rock")
	for e in game.entities.get_children():
		if e is Projectile or e is ItemDrop:
			e.queue_free()
	for x in range(-14, 15):
		for z in range(-5, 6):
			for y in range(-6, 14):
				w.set_block(o + Vector3i(x, y, z), 0)
	for x in range(-14, 15):
		for z in range(-5, 6):
			for y in range(-6, 14):
				game.wiring.remove(o + Vector3i(x, y, z), 31)
	p.god_mode = was_god
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p.velocity = Vector3.ZERO
	p._fall_start = p.global_position.y  # (moved down, not fallen)
	p.life = p.life_max
	p.poisoned = 0.0
	await frames(2)


func _recipe_checks(c: Vector3i) -> void:
	var find := func(item: String) -> Array: return Data.recipes.filter(func(r): return r.result == item)
	var f := FileAccess.open(Data.TERRARIA_RECIPES, FileAccess.READ)
	var all: Array = JSON.parse_string(f.get_as_text())
	check(all.size() > 3000, "Terraria's recipes read from Terraria.exe (%d)" % all.size())
	var pick: Dictionary = find.call("CopperPickaxe")[0]
	check(pick.ingredients == {"CopperBar": 8, Data.ANY_WOOD: 4} and pick.station == "iron_anvil", "Copper Pickaxe: 8 Copper Bars, 4 of any wood, at an anvil (%s)" % pick.ingredients)
	var yoyo: Dictionary = find.call("WoodYoyo")[0]
	check(yoyo.ingredients == {Data.ANY_WOOD: 10, "Cobweb": 20} and yoyo.station == "work_bench", "Wooden Yoyo: 10 wood, 20 Cobwebs")
	var potion: Dictionary = find.call("LesserHealingPotion")[0]
	check(potion.count == 2 and potion.ingredients == {"Mushroom": 1, "Gel": 2, "Bottle": 2} and potion.station == "bottles",
			"Lesser Healing Potions: 2 from a Mushroom, 2 Gel and 2 Bottles at a placed Bottle")
	var odd := Data.recipes.filter(func(r): return not r.get("terraria", false))
	check(odd.is_empty(), "every recipe is Terraria's (%s)" % [odd.map(func(r): return r.result)])
	var bar: Dictionary = find.call("HellstoneBar")[0]
	check(bar.ingredients == {"Hellstone": 3, "Obsidian": 1} and bar.station == "hellforge", "Hellstone Bars: 3 Hellstone and an Obsidian at a Hellforge (%s)" % bar)
	check(find.call("MusketBall").is_empty() and find.call("Shuriken").is_empty(), "no recipes Terraria doesn't have (Musket Balls, Shurikens)")
	# Terraria's paintings (tiles 240-246, trophies and racks too): a block
	# each (the Catacomb's and Strange Growth's other styles too) dropping
	# its item.
	var paintings := Data.blocks.filter(func(b): return b.get("painting", false))
	var placing := Data.items.keys().filter(func(k): return Data.block(Data.block_id(Data.items[k].get("place", "air"))).get("painting", false))
	check(paintings.size() == 254 and placing.size() == 243 and paintings.all(func(b): return Data.items.has(b.drop)),
			"Terraria's 243 paintings, trophies and racks (%d blocks, %d items)" % [paintings.size(), placing.size()])
	check(Data.npcs.EyeofCthulhu.drops.any(func(d): return d[0] == "EyeofCthulhuTrophy" and is_equal_approx(float(d[3]), 0.1)), "a boss drops its trophy 1 time in 10")
	# A placed Bottle is where potions are made; a Lead Anvil counts as an anvil.
	var p := game.player
	var spot := c + Vector3i(-30, 0, 34)
	game.world.set_block(spot, Data.block_id("bottle"))
	game.world.set_block(spot + Vector3i(1, 0, 0), Data.block_id("lead_anvil"))
	p.global_position = Vector3(spot) + Vector3(0.5, 0, 2.5)
	await frames(2)
	var st: Dictionary = game.nearby_stations()
	check(st.has("bottles") and st.has("iron_anvil"), "a placed Bottle brews potions, a Lead Anvil is an anvil (%s)" % [st.keys()])
	game.world.set_block(spot, 0)
	game.world.set_block(spot + Vector3i(1, 0, 0), 0)
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	await frames(2)


func _sky_checks() -> void:
	var sky := game.sky
	var shown := func() -> Array:
		return sky._rings.map(func(r): return r.shown).filter(func(id): return id >= 0)
	await frames(5)
	check(shown.call() == SkySystem.BACKDROPS[game.biome], "the backdrop shows the current biome's layers (%s)" % [shown.call()])
	var was: String = game.biome
	game._biome_timer = 1000.0  # (hold the biome detection off)
	game.biome = "snow"
	await frames(3)
	check(shown.call() == SkySystem.BACKDROPS.snow, "in the snow, the snow backdrop (%s)" % [shown.call()])
	var ring: Dictionary = sky._rings[0]
	check(ring.meshes.size() == 2 and ring.fades[35] < 1.0, "it dissolves in over the old one")
	await frames(150)
	check(sky._rings[0].meshes.size() == 1 and sky._rings[0].fades[35] == 1.0, "and the old layer goes once it's faded")
	game.biome = was
	game._biome_timer = 0.0
	check(sky.ring_radius(0) > sky.env.fog_depth_end and sky.cloud_distance() > sky.ring_radius(2)
			and sky.body_distance() < game.player.camera.far,
			"rings, then clouds, then the sun lie beyond the view distance and within the camera's reach")
	sky.cloudiness = 0.3
	sky.load_state(sky.save_state())
	var active := sky._clouds.filter(func(c): return c.active).size()
	check(absi(active - roundi(0.3 * SkySystem.CLOUD_SLOTS)) <= 1, "cloudiness sets how many clouds there are (%d)" % active)
	var day: bool = sky.is_day
	var t: float = sky.time
	sky.is_day = false
	sky.time = 16000.0
	await frames(2)
	check(float(sky._sky_mat.get_shader_parameter("stars")) > 0.9, "stars come out at night")
	sky.is_day = true
	sky.time = 27000.0
	sky.space_factor = 1.0
	sky._update_visuals(0.0)
	check(float(sky._sky_mat.get_shader_parameter("stars")) > 0.9, "and by day in Space")
	sky.is_day = day
	sky.time = t
	await frames(2)


## The Dungeon: the keep, its arched door, a way from the plaza down the
## entrance hallway into the Dungeon under it, hard bricks, the dungeon biome
## inside (its music, no spawns), the Old Man, a Locked Gold Chest a Golden
## Key opens, a switch that switches its light, and spikes that hurt.
func _dungeon_checks(c: Vector3i) -> void:
	var p := game.player
	var w := game.world
	var d := Vector3i(c.x + TestWorld.DUNGEON.x, TestWorld.GROUND, c.z + TestWorld.DUNGEON.z)
	check(game.dungeon_entrance == d, "the game knows where the Dungeon's entrance is (%s)" % game.dungeon_entrance)
	check(Data.block(w.get_block(d + Vector3i(7, 3, 6))).get("name", "") == "blue_brick" and w.get_block(d + Vector3i(7, 3, 0)) == 0,
			"a keep of blue dungeon brick with an open doorway facing spawn")
	check(w.get_shape(d + Vector3i(7, 6, -2)) >= Game.SHAPE_CEILING and w.get_shape(d + Vector3i(7, 6, 2)) >= Game.SHAPE_CEILING,
			"the doorway is arched (upside-down ramps)")
	# Walk it: standing cells (open feet and head, something solid under the
	# feet) joined by steps of at most one block up, or a drop down.
	var start := d + Vector3i(27, 0, 0)  # the plaza past the porch's end
	var stands := func(q: Vector3i) -> bool:
		return not w.is_solid(q) and not w.is_solid(q + Vector3i.UP) and w.is_solid(q + Vector3i.DOWN)
	var seen := {start: true}
	var queue: Array[Vector3i] = [start]
	var deepest := start.y
	while not queue.is_empty() and seen.size() < 40000:
		var q: Vector3i = queue.pop_front()
		deepest = mini(deepest, q.y)
		for n in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			for dy in [0, 1, -1]:
				var r: Vector3i = q + n + Vector3i(0, dy, 0)
				# Stepping up needs headroom over where you are too.
				if dy == 1 and w.is_solid(q + Vector3i(0, 2, 0)):
					continue
				# Off an edge: fall to the floor below.
				if dy == -1 and not w.is_solid(r) and not w.is_solid(r + Vector3i.UP):
					while not w.is_solid(r + Vector3i.DOWN) and r.y > 2:
						r.y -= 1
				if seen.has(r) or (r - d).length() > 120:
					continue
				if stands.call(r):
					seen[r] = true
					queue.append(r)
	check(deepest <= d.y - 20, "you can walk from the plaza through the door and down the hallway into the Dungeon (down to %d below)" % (d.y - deepest))
	check(w.get_block(d + Vector3i(-2, 0, 0)) == 0, "the back of the hall floor opens into the hallway")
	# Dungeon brick needs a strong pickaxe (65%, like Terraria's).
	p.target = {"block": d + Vector3i(7, 3, 6), "normal": Vector3i(1, 0, 0), "id": w.get_block(d + Vector3i(7, 3, 6)), "distance": 2.0}
	p._mine(Data.item("PlatinumPickaxe"))
	check(w.get_block(d + Vector3i(7, 3, 6)) != 0 and last_message() == "This block is too hard for your pickaxe", "dungeon brick is too hard for a platinum pickaxe")
	check(int(Data.block(Data.block_id("blue_brick")).get("min_pick", 0)) == 65, "it needs 65% pickaxe power")
	# Inside: the dungeon biome and its music; outside: the forest.
	check(game.detect_biome(Vector3(d) + Vector3(0.5, 1, 3.5)) == "dungeon", "inside the keep is the Dungeon")
	check(game.detect_biome(Vector3(d) + Vector3(28.5, 1, 0.5)) == "", "the plaza outside isn't")
	check(game.biome_music("dungeon", false) == "Dungeon", "the Dungeon plays its music")
	game._biome_timer = 1000.0
	game.biome = "dungeon"
	var before := game.npcs().size()
	game.spawner.process_mode = Node.PROCESS_MODE_INHERIT
	for i in 40:
		game.spawner._timer = 0.0
		game.spawner._physics_process(0.016)
	check(game.npcs().size() == before, "nothing spawns in the Dungeon yet")
	game.spawner.process_mode = Node.PROCESS_MODE_DISABLED
	game.biome = ""
	game._biome_timer = 0.0
	# The Old Man by the door; he talks.
	var old_men := game.npcs().filter(func(n): return n.kind == "OldMan")
	check(old_men.size() == 1 and old_men[0].global_position.distance_to(Vector3(d) + Vector3(11.5, 1, 3.5)) < 1.5, "the Old Man stands under the porch")
	if old_men.size() == 1:
		var om: NPC = old_men[0]
		# Drawn the player's height: his figure (not his sprite frame's empty
		# margins) stands 1.8 m, feet on the ground.
		var tex := Assets.texture("Images/NPC_%d" % int(om.def.sprite))
		var frame_h := float(tex.get_height()) / int(om.def.frames)
		var rows := NPC.art_rows(tex, frame_h)
		var shown := frame_h - (frame_h - 1.0 - rows.y)
		var figure: float = om.sprite.scale.y * (rows.y - rows.x + 1) / shown
		# (Unless npc_scales.json resizes him: then by that much.)
		var sc := float(Data.npc_scale("OldMan").scale)
		check(absf(figure - p.half.y * sc) < 0.02, "the Old Man is as tall as the player x%.2f (%.2f m vs %.2f m)" % [sc, figure, p.half.y * sc])
		p.global_position = om.global_position + Vector3(2.5, 0, 0)
		p.look_at_yaw_pitch(-PI * 0.5 + PI, -0.15)
		var to: Vector3 = om.center() - p.camera.global_position
		p.look_at_yaw_pitch(atan2(-to.x, -to.z), asin(to.normalized().y))
		await frames(3)
		check(p.talk_target() == om, "aiming at the Old Man picks him to talk to")
		p._interact()
		check(game.hud.chat_npc == om and game.hud._chat_text.text != "" and game.hud._chat_title.text == "Old Man",
				"right-clicking him: he speaks (%s)" % game.hud._chat_text.text)
		game.hud.close_chat()
		om.hit(500, 0.0, Vector3.FORWARD, 0.0)
		check(is_instance_valid(om) and om.life == om.life_max, "he can't be hurt")
	# A Locked Gold Chest: locked without a key, a Golden Key opens it for
	# good (used up), its loot inside.
	var locked := Vector3i(-1, -1, -1)
	for dd in w.get_decorations():
		if dd.kind == "chest" and int(dd.style) >= 7 and Data.block(w.get_block(Vector3i(dd.pos))).get("name", "") == "locked_gold_chest":
			locked = Vector3i(dd.pos)
			break
	check(locked.y >= 0, "the Dungeon has a Locked Gold Chest")
	if locked.y >= 0:
		p.inventory.remove("GoldenKey", p.inventory.count_of("GoldenKey"))
		check(not game.unlock_chest(locked) and last_message() == "It's locked", "without a Golden Key it stays locked")
		p.inventory.add("GoldenKey", 2)
		check(game.unlock_chest(locked) and Data.block(w.get_block(locked)).get("name", "") == "gold_chest" and p.inventory.count_of("GoldenKey") == 1,
				"a Golden Key opens it for good: a Gold Chest now, the key used up")
		check(not game.chests.get_inventory(locked).is_empty(), "its loot is inside")
		game.hud.close_inventory()
		p.inventory.remove("GoldenKey", 1)
	# A switch and the light it's wired to (red wire, worldgen's).
	var sw := Vector3i(-1, -1, -1)
	var light := Vector3i(-1, -1, -1)
	for k in game.wiring.cells:
		if Vector3(k - d).length() < 120 and Data.block(w.get_block(k)).get("interact", "") == "switch":
			sw = k
			break
	if sw.y >= 0:
		var reached := {sw: true}
		var wire_todo: Array = [sw]
		while not wire_todo.is_empty() and light.y < 0:
			var wc: Vector3i = wire_todo.pop_back()
			for dd in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
				var n: Vector3i = wc + dd
				if not reached.has(n) and game.wiring.mask(n) & Wiring.RED:
					reached[n] = true
					wire_todo.append(n)
					var nb := Data.block(w.get_block(n))
					if nb.has("off") or nb.has("lit"):
						light = n
	check(sw.y >= 0 and light.y >= 0, "the Dungeon's lights have switches, wired to them")
	if sw.y >= 0 and light.y >= 0:
		var before_light := w.get_block(light)
		var lb := Data.block(before_light)
		game.hit_switch(sw)
		var twin: String = lb.get("off", lb.get("lit", ""))
		check(twin != "" and w.get_block(light) == Data.block_id(twin), "hitting the switch switches its light (%s -> %s)" % [lb.get("name", ""), twin])
		game.hit_switch(sw)
		check(w.get_block(light) == before_light, "and back")
	# Spikes hurt (Terraria's 60, give or take 15%).
	var spot := start + Vector3i(0, 0, 3)
	var under := w.get_block(spot + Vector3i.DOWN)
	w.set_block(spot + Vector3i.DOWN, Data.block_id("spike"))
	p.global_position = Vector3(spot) + Vector3(0.5, 0.0, 0.5)
	var god: bool = p.god_mode
	p.god_mode = false
	p._immune = 0.0
	var life_before: int = p.life
	p._liquid_effects(0.016)
	p.god_mode = god
	var lost := life_before - p.life
	check(lost >= int(60 * 0.85) - p.defense() / 2 - 1 and lost <= int(60 * 1.15) - p.defense() / 2 + 1, "standing on spikes hurts (%d)" % lost)
	w.set_block(spot + Vector3i.DOWN, under)
	p.life = p.life_max
	# The Cobalt Shield: no knockback.
	var saved_acc := p.accessories.slots.duplicate()
	p.accessories.slots.fill(null)
	p.accessories.slots[0] = Inventory.stack("CobaltShield", 1)
	p.god_mode = false
	p._immune = 0.0
	p.velocity = Vector3.ZERO
	p.hurt(10, p.global_position + Vector3(2, 0, 0))
	check(p.velocity.length() < 0.01 and p.defense() >= 1, "the Cobalt Shield: no knockback (and 1 defense)")
	p.accessories.slots = saved_acc
	p.god_mode = god
	p.life = p.life_max
	# The dungeon's spells: the Water Bolt bounces off blocks; the Aqua
	# Scepter's two streams a use cost its mana once; the Magic Missile flies
	# toward your crosshair while you hold the button.
	var bolt := game.spawn_projectile("WaterBolt", Vector3(spot) + Vector3(0.5, 1.5, 0.5), Vector3(0, -20, 0), 19, 5.0)
	for i in 20:
		await get_tree().physics_frame
	check(is_instance_valid(bolt) and bolt.velocity.y > 0.0 and bolt.bounces == 9, "a Water Bolt bounces off the floor")
	if is_instance_valid(bolt):
		bolt.queue_free()
	var scepter := Data.item("AquaScepter")
	p.mana = p.mana_max
	p._free_shots = 0
	p._cast(scepter)
	p._cast(scepter)
	check(p.mana == p.mana_max - p.mana_cost(scepter), "the Aqua Scepter's two streams cost %d mana once (%d left of %d)" % [p.mana_cost(scepter), p.mana, p.mana_max])
	var missile_def := Data.item("MagicMissile")
	p.mana = p.mana_max
	p.global_position = Vector3(start) + Vector3(0.5, 0, 0.5)
	p.look_at_yaw_pitch(0.0, 0.0)
	p.hold_use = true
	p._cast(missile_def)
	var missile: Projectile = p.channelled
	check(missile != null and not p._cast(missile_def), "one Magic Missile at a time")
	p.look_at_yaw_pitch(PI * 0.5, 0.0)
	for i in 20:
		await get_tree().physics_frame
	var to_aim := (p.aim_point() - missile.global_position).normalized() if is_instance_valid(missile) else Vector3.ZERO
	# (It set off straight away from where it's now steered.)
	check(is_instance_valid(missile) and missile.velocity.normalized().dot(to_aim) > 0.5, "the Magic Missile turns toward the crosshair")
	p.hold_use = false
	if is_instance_valid(missile):
		missile.queue_free()
	for n in game.entities.get_children():
		if n is Projectile:
			n.queue_free()
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	await frames(5)


## What breaking `at` drops: {item: count}.
func _drops_of(at: Vector3i) -> Dictionary:
	game._collected_drops = {}
	game.break_block(at)
	var d: Dictionary = game._collected_drops
	game._collected_drops = null
	return d


func _alchemy_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var herbs: Herbs = game.herbs
	var o := c + Vector3i(30, 45, -30)
	var grass := Data.block_id("grass")
	for x in range(-6, 7):
		for z in range(-6, 7):
			w.set_block(o + Vector3i(x, -1, z), grass)
			for y in range(0, 4):
				w.set_block(o + Vector3i(x, y, z), 0)
	var name_at := func(at: Vector3i) -> String: return Data.block(w.get_block(at)).get("name", "")
	# Seeds go in on their soil only.
	var held := p.selected
	p.inventory.slots[9] = Inventory.stack("DaybloomSeeds", 5)
	p.select(9)
	p._use_timer = 0.0
	p._use_released = true
	p.target = {"block": o + Vector3i.DOWN, "normal": Vector3i.UP, "id": grass, "distance": 3.0}
	p.use_item()
	check(name_at.call(o) == "daybloom_sprout" and p.inventory.count_of("DaybloomSeeds") == 4, "Daybloom Seeds plant a Daybloom sprout on grass")
	var stone_at := o + Vector3i(2, -1, 0)
	w.set_block(stone_at, Data.block_id("stone"))
	p._use_timer = 0.0
	p.target = {"block": stone_at, "normal": Vector3i.UP, "id": w.get_block(stone_at), "distance": 3.0}
	p.use_item()
	check(w.get_block(stone_at + Vector3i.UP) == 0 and p.inventory.count_of("DaybloomSeeds") == 4, "but not on stone")
	w.set_block(stone_at, grass)
	p.inventory.slots[9] = null
	p.select(held)
	# A sprout breaks for nothing, and grows (1 in 50 an update, another 1 in
	# 50 by day for Daybloom).
	check(_drops_of(o).is_empty(), "a sprout gives nothing")
	w.set_block(o, Data.block_id("daybloom_sprout"))
	game.sky.is_day = true
	var updates := 0
	while name_at.call(o) == "daybloom_sprout" and updates < 2000:
		herbs.grow(o)
		updates += 1
	check(name_at.call(o) in ["daybloom_mature", "daybloom"] and updates < 2000, "the sprout grows up (%d updates)" % updates)
	herbs.grow(o)
	check(name_at.call(o) == "daybloom", "Daybloom blooms by day")
	game.sky.is_day = false
	herbs.grow(o)
	check(name_at.call(o) == "daybloom_mature", "and closes at night")
	var d := _drops_of(o)
	check(d.get("Daybloom", 0) == 1 and not d.has("DaybloomSeeds"), "grown, it gives the herb, no seeds")
	game.sky.is_day = true
	var seeds := {}
	for i in 40:
		w.set_block(o, Data.block_id("daybloom"))
		d = _drops_of(o)
		if d.get("Daybloom", 0) != 1:
			seeds[-1] = true
		seeds[d.get("DaybloomSeeds", 0)] = true
	check(seeds.keys().all(func(k): return k >= 1 and k <= 3) and seeds.size() >= 2, "in bloom: the herb and 1-3 seeds %s" % [seeds.keys()])
	# The Staff of Regrowth cuts only herbs in bloom, for more.
	game.regrowth = true
	w.set_block(o, Data.block_id("daybloom_mature"))
	game.sky.is_day = false
	check(not game.cut_tile(o) and name_at.call(o) == "daybloom_mature", "the Staff of Regrowth leaves herbs not ready")
	game.sky.is_day = true
	var most := [0, 0]
	for i in 60:
		w.set_block(o, Data.block_id("daybloom"))
		game._collected_drops = {}
		game.cut_tile(o)
		d = game._collected_drops
		game._collected_drops = null
		most = [maxi(most[0], d.get("Daybloom", 0)), maxi(most[1], d.get("DaybloomSeeds", 0))]
	game.regrowth = false
	check(most[0] == 2 and most[1] >= 4 and most[1] <= 5, "and harvests them for 1-2 herbs and 1-5 seeds (most %s)" % [most])
	# Planting on a herb in bloom harvests and replants it.
	w.set_block(o, Data.block_id("daybloom"))
	p.inventory.slots[9] = Inventory.stack("DaybloomSeeds", 1)
	p.select(9)
	p._use_timer = 0.0
	p.target = {"block": o, "normal": Vector3i.UP, "id": w.get_block(o), "distance": 3.0}
	var drops_before := game.entities.get_children().filter(func(e): return e is ItemDrop).size()
	p.use_item()
	check(name_at.call(o) == "daybloom_sprout" and game.entities.get_children().filter(func(e): return e is ItemDrop).size() > drops_before,
			"seeds on a herb in bloom harvest it and go in its place")
	p.inventory.slots[9] = null
	p.select(held)
	# Liquid: water kills Daybloom, not Moonglow.
	w.set_block(o, Data.block_id("daybloom_mature"))
	var moon := o + Vector3i(2, 0, 0)
	w.set_block(moon + Vector3i.DOWN, Data.block_id("jungle_grass"))
	w.set_block(moon, Data.block_id("moonglow_mature"))
	w.set_liquid(o, Player.LIQ_WATER, 63)
	w.set_liquid(moon, Player.LIQ_WATER, 63)
	herbs.grow(o)
	herbs.grow(moon)
	check(w.get_block(o) == 0 and name_at.call(moon).begins_with("moonglow"), "water drowns Daybloom; Moonglow grows in it")
	w.set_liquid(o, 0, 0)
	w.set_liquid(moon, 0, 0)
	# Off its soil it dies.
	w.set_block(moon + Vector3i.DOWN, grass)
	herbs.grow(moon)
	check(w.get_block(moon) == 0, "a herb off its soil dies")
	# Blinkroot flickers; Shiverthorn blooms and stays.
	var blink := o + Vector3i(0, 0, 2)
	w.set_block(blink + Vector3i.DOWN, Data.block_id("dirt"))
	w.set_block(blink, Data.block_id("blinkroot_mature"))
	var seen := {}
	for i in 60:
		herbs.grow(blink)
		seen[name_at.call(blink)] = true
	check(seen.has("blinkroot") and seen.has("blinkroot_mature"), "Blinkroot flickers in and out of bloom")
	# Fireblossom: from 3:45 PM (40500 ticks) to dusk.
	var fire := o + Vector3i(0, 0, -2)
	w.set_block(fire + Vector3i.DOWN, Data.block_id("ash"))
	w.set_block(fire, Data.block_id("fireblossom_mature"))
	var t0: float = game.sky.time
	game.sky.time = 30000.0
	herbs.grow(fire)
	var before_bloom: String = name_at.call(fire)
	game.sky.time = 41000.0
	herbs.grow(fire)
	check(before_bloom == "fireblossom_mature" and name_at.call(fire) == "fireblossom", "Fireblossom blooms late in the day")
	game.sky.time = t0
	# Deathweed: on full-moon nights.
	var death := o + Vector3i(-2, 0, 0)
	w.set_block(death + Vector3i.DOWN, Data.block_id("ebonstone"))
	w.set_block(death, Data.block_id("deathweed_mature"))
	var phase: int = game.sky.moon_phase
	game.sky.is_day = false
	game.sky.moon_phase = 3
	herbs.grow(death)
	var waning: String = name_at.call(death)
	game.sky.moon_phase = 0
	herbs.grow(death)
	check(waning == "deathweed_mature" and name_at.call(death) == "deathweed", "Deathweed blooms under a full moon")
	game.sky.moon_phase = phase
	game.sky.is_day = true
	# Planter Boxes: any herb grows in any of them, and swinging doesn't cut it.
	var pb := o + Vector3i(4, 0, 4)
	w.set_block(pb + Vector3i.DOWN, Data.block_id("fireblossom_planter_box"))
	w.set_block(pb, Data.block_id("moonglow_mature"))
	herbs.grow(pb)
	check(name_at.call(pb).begins_with("moonglow") and not game.cut_tile(pb) and name_at.call(pb).begins_with("moonglow"),
			"Moonglow grows in a Fireblossom Planter Box, and a swing doesn't cut it")
	w.set_block(pb, 0)
	w.set_block(pb + Vector3i.DOWN, grass)
	# Planter Boxes are solid-looking cubes: their top fills the block and no
	# face can be seen through; their sides are the planter's soil over
	# dark-stained wood, like grass over dirt.
	var see_through := []
	for n in ["planter_box", "moonglow_planter_box", "corrupt_planter_box", "crimson_planter_box",
			"blinkroot_planter_box", "waterleaf_planter_box", "shiverthorn_planter_box", "fireblossom_planter_box"]:
		var pd := Data.block(Data.block_id(n))
		var faces_opaque := int(pd.render_id) == Data.RENDER.cube
		# (The faces' pictures are rebuilt: headless, the texture array has no data.)
		for f in ["top", "side", "bottom"]:
			faces_opaque = faces_opaque and Data._cube_layer(pd.tex[f], 0).detect_alpha() == Image.ALPHA_NONE
		if not faces_opaque:
			see_through.append(n)
	check(see_through.is_empty(), "Planter Boxes are full cubes with no see-through faces %s" % [see_through])
	# Coral drops Coral; it goes on sand only.
	check(Data.block(Data.block_id("coral_4")).get("drop") == "Coral" and Data.item("Coral").place == "coral", "Coral, from the sea floor")
	for q in [o, blink, fire, death, moon]:
		w.set_block(q, 0)


func _potion_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var held := p.selected
	var was_god := p.god_mode
	p.god_mode = false
	p.timed_buffs.clear()
	var drink := func(item: String) -> void:
		p.inventory.slots[9] = Inventory.stack(item, 1)
		p.select(9)
		p._use_timer = 0.0
		p._use_released = true
		p.use_item()
	var def0 := p.defense()
	drink.call("IronskinPotion")
	check(p.has_buff("Ironskin") and absf(p.timed_buffs.Ironskin - 480.0) < 0.1 and p.defense() == def0 + 8, "the Ironskin Potion: 8 defense for 8 minutes")
	var speed0 := p.stat("move_speed")
	drink.call("SwiftnessPotion")
	check(p.stat("move_speed") == speed0 + 25.0, "Swiftness: 25 percent faster")
	drink.call("LifeforcePotion")
	check(p.life_cap() == p.life_max + p.life_max / 5 / 20 * 20, "Lifeforce: a fifth more life (%d of %d)" % [p.life_cap(), p.life_max])
	drink.call("EndurancePotion")
	p.life = p.life_cap()
	p._immune = 0.0
	var life0 := p.life
	p.hurt(100 + p.defense() / 2, Vector3.ZERO, true)
	check(life0 - p.life == 90, "Endurance: 10%% less damage (%d of 100)" % [life0 - p.life])
	p.life = p.life_cap()
	# Obsidian Skin: lava doesn't hurt.
	drink.call("ObsidianSkinPotion")
	p.in_liquid = Player.LIQ_LAVA
	p.lava_time = 0.0
	p._immune = 0.0
	life0 = p.life
	p._liquid_effects(0.1)
	check(p.life == life0, "Obsidian Skin: lava doesn't hurt")
	p.in_liquid = 0
	p.on_fire = 0.0
	# Gills: no breath lost under water.
	drink.call("GillsPotion")
	p.head_liquid = Player.LIQ_WATER
	p.breath = 5.0
	p._liquid_effects(1.0)
	check(p.breath >= 5.0, "Gills: you breathe under water")
	p.head_liquid = 0
	# Flippers: jump swims you up in water.
	p.accessories.slots[0] = Inventory.stack("Flipper", 1)
	check(p.has_effect("flipper") and not p.has_effect("ignore_water"), "Flippers let you swim (still slowed by the water)")
	p.accessories.slots[0] = null
	drink.call("FlipperPotion")
	check(p.has_effect("flipper") and p.has_effect("ignore_water"), "the Flipper Potion: swimming, not slowed by water")
	# Titan: knockback half again.
	var sword := Data.item("WoodenSword")
	var kb0 := p.weapon_knockback(sword)
	drink.call("TitanPotion")
	check(absf(p.weapon_knockback(sword) - kb0 * 1.5) < 0.001, "Titan: knockback x1.5")
	# The buffs save and load.
	var saved := p.save_state()
	p.timed_buffs.clear()
	p.load_state(saved)
	check(p.has_buff("Ironskin") and p.has_buff("Titan"), "buffs keep across saving")
	p.timed_buffs.clear()
	p.life = mini(p.life, p.life_cap())
	# Food: Well Fed, and the stronger kinds in its place.
	var d0 := p.defense()
	drink.call("CookedFish")
	check(p.has_buff("WellFed") and p.defense() == d0 + 2 and absf(p.timed_buffs.WellFed - 480.0) < 0.1, "Cooked Fish: Well Fed, 2 defense for 8 minutes")
	drink.call("GoldenDelight")
	check(p.has_buff("WellFed3") and not p.has_buff("WellFed") and p.defense() == d0 + 4, "a Golden Delight: Exquisitely Stuffed in its place")
	p.timed_buffs.clear()
	var has_recipe := func(result: String, ing: String, station: String) -> bool:
		return Data.recipes.any(func(r): return r.result == result and r.ingredients.has(ing) and r.get("station", "") == station)
	check(has_recipe.call("RoastedDuck", "Duck", "cooking_pot") and has_recipe.call("CookedFish", "Bass", "cooking_pot")
			and has_recipe.call("IronskinPotion", "Daybloom", "bottles") and has_recipe.call("GillsPotion", "Coral", "bottles"),
			"recipes: critters and fish cooked at a Cooking Pot, potions at a bottle")
	# The Alchemy Table: each ingredient saved 1 in 3.
	var lab := c + Vector3i(-30, 60, -30)
	for x in range(-3, 4):
		for z in range(-3, 4):
			w.set_block(lab + Vector3i(x, -1, z), Data.block_id("stone"))
			for y in range(0, 4):
				w.set_block(lab + Vector3i(x, y, z), 0)
	w.set_block(lab + Vector3i(2, 0, 0), Data.block_id("alchemy_table"))
	p.global_position = Vector3(lab) + Vector3(0.5, 0, 0.5)
	p._fall_start = p.global_position.y
	await frames(2)
	var hud: Hud = game.hud
	hud._open_inventory()
	for item in ["BottledWater", "Daybloom", "IronOre"]:
		p.inventory.add(item, 60)
	var ironskin: Dictionary = Data.recipes.filter(func(r): return r.result == "IronskinPotion")[0]
	for i in 60:
		hud._cursor_stack = null
		hud.craft(ironskin)
	hud._cursor_stack = null
	hud.close_inventory()
	var used := 60 - p.inventory.count_of("BottledWater")
	check(used > 25 and used < 55, "by an Alchemy Table a potion's ingredients are often saved (%d of 60 Bottled Water used)" % used)
	for item in ["BottledWater", "Daybloom", "IronOre"]:
		p.inventory.remove(item, p.inventory.count_of(item))
	w.set_block(lab + Vector3i(2, 0, 0), 0)
	# The Piggy Bank and Safe: your own 40 slots, the same in every one; their
	# coins spend in shops.
	var bank_at := lab + Vector3i(-2, 0, 0)
	w.set_block(bank_at, Data.block_id("piggy_bank"))
	p.target = {"block": bank_at, "normal": Vector3i.UP, "id": w.get_block(bank_at), "distance": 2.0}
	p._interact()
	check(hud._chest == p.piggy_bank and p.piggy_bank.slots.size() == 40, "a Piggy Bank opens your own 40 slots")
	hud.close_inventory()
	w.set_block(bank_at, Data.block_id("safe"))
	p.target = {"block": bank_at, "normal": Vector3i.UP, "id": w.get_block(bank_at), "distance": 2.0}
	p._interact()
	check(hud._chest == p.safe and p.safe != p.piggy_bank, "a Safe its own")
	hud.close_inventory()
	w.set_block(bank_at, 0)
	p.piggy_bank.add("GoldCoin", 2)
	var carried := p.inventory.money()
	check(p.money() == carried + 20000 and p.pay(carried + 15000) and p.inventory.money() == 0 and p.piggy_bank.money() == 5000,
			"coins in the Piggy Bank spend in shops, after what you carry")
	var banked := p.save_state()
	p.piggy_bank.slots.fill(null)
	p.load_state(banked)
	check(p.piggy_bank.money() == 5000, "and stay in it across saving")
	p.piggy_bank.slots.fill(null)
	p.inventory.add_money(carried)
	# Recall Potion, Magic Mirror: home.
	var home := p.respawn_point()
	p.global_position = home + Vector3(30, 5, 30)
	p._fall_start = p.global_position.y
	drink.call("RecallPotion")
	check(p.global_position.distance_to(home) < 0.1, "the Recall Potion takes you home")
	p.global_position = home + Vector3(30, 5, 30)
	p._fall_start = p.global_position.y
	p.inventory.slots[9] = Inventory.stack("MagicMirror", 1)
	p.select(9)
	p._use_timer = 0.0
	p.use_item()
	check(p.global_position.distance_to(home) > 10.0, "the Magic Mirror: not at once")
	var t := 0.0
	while p.global_position.distance_to(home) > 0.1 and t < 2.0:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	check(p.global_position.distance_to(home) < 0.1 and absf(t - 0.75) < 0.1, "but home halfway through its use (%.2f s)" % t)
	# The Teleportation Potion's spot: on a floor, clear above.
	var o := c + Vector3i(-30, 60, 30)
	for y in range(-3, 6):
		w.set_block(o + Vector3i(0, y, 0), 0)
	w.set_block(o + Vector3i(0, -3, 0), Data.block_id("stone"))
	var spot = Player.random_spot(w, o + Vector3i(0, 2, 0))
	check(spot != null and absf(spot.y - (o.y - 2)) < 0.01, "the Teleportation Potion lands you on a floor")
	w.set_block(o + Vector3i(0, -3, 0), Data.block_id("spike"))
	check(Player.random_spot(w, o + Vector3i(0, 2, 0)) == null, "not on spikes")
	w.set_block(o + Vector3i(0, -3, 0), 0)
	# Hearts and Stars: picked up, they heal and give mana, not kept.
	p.life = p.life_cap() - 50
	var heart := ItemDrop.new()
	heart.setup("Heart", 1)
	game.entities.add_child(heart)
	heart.global_position = p.global_position + Vector3(0, 0.9, 0)
	heart.age = 10.0
	var life1 := p.life
	await frames(3)
	check(p.life == life1 + 20 and p.inventory.count_of("Heart") == 0 and not is_instance_valid(heart), "a Heart heals 20 and isn't kept")
	# Heartreach pulls them from further.
	var h2 := ItemDrop.new()
	h2.setup("Heart", 1)
	game.entities.add_child(h2)
	var r0 := h2.grab_range(p)
	p.timed_buffs["Heartreach"] = 60.0
	check(absf(h2.grab_range(p) - r0 - 250.0 / 24.0) < 0.01, "Heartreach: Hearts come from 250 px further")
	h2.queue_free()
	p.timed_buffs.clear()
	p.mana = 0
	var star := ItemDrop.new()
	star.setup("Star", 1)
	game.entities.add_child(star)
	star.global_position = p.global_position + Vector3(0, 0.9, 0)
	star.age = 10.0
	await frames(3)
	check(p.mana == mini(100, p.mana_cap()) and p.inventory.count_of("Star") == 0, "a Star gives 100 mana")
	# Chests: potions and Recall Potions; the Magic Mirror among the finds.
	var found := {}
	for i in 300:
		for dd in Game.roll_loot("chest"):
			found[dd[0]] = true
	check(found.has("MagicMirror") and found.has("RecallPotion") and found.has("TrapsightPotion") and not found.has("GravitationPotion"),
			"underground chests: Magic Mirrors, Recall and buff potions (no Gravitation, not in the game)")
	# Spelunker shows ore through the walls; Hunter shows creatures.
	var ore_at := o + Vector3i(3, 0, 0)
	w.set_block(ore_at, Data.block_id("gold_ore"))
	p.global_position = Vector3(o) + Vector3(0.5, 0, 0.5)
	p._fall_start = p.global_position.y
	p.timed_buffs["Spelunker"] = 60.0
	game.senses._scan_t = 0.0
	await frames(2)
	var ores: PackedInt32Array = game.senses._treasure
	var shown := false
	for i in range(0, ores.size(), 3):
		shown = shown or Vector3i(ores[i], ores[i + 1], ores[i + 2]) == ore_at
	check(shown and game.senses.visible, "Spelunker: ore shows")
	p.timed_buffs.clear()
	await frames(2)
	check(not game.senses.visible, "and not without it")
	w.set_block(ore_at, 0)
	var slime := game.spawn_npc("GreenSlime", Vector3(o) + Vector3(4, 0, 0))
	p.timed_buffs["Hunter"] = 60.0
	await frames(2)
	check(slime._hunted == 1, "Hunter: creatures show through the walls, enemies red")
	p.timed_buffs.clear()
	await frames(2)
	check(slime._hunted == 0, "and stop when it wears off")
	slime.queue_free()
	p.inventory.slots[9] = null
	p.select(held)
	p.god_mode = was_god
	p.life = p.life_cap()



## Waits up to `limit` seconds for `cond` to hold; true if it did.
func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while not cond.call() and t < limit:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	return cond.call()


## The Queen Bee's loot (Terraria's ItemDropDatabase.RegisterBoss_QueenBee and
## each item's SetDefaults): every drop is an item here; the bees (AI 36:
## homing, water kills them); the Bee Gun's, the Bee's Knees' Bee Arrows',
## the Beekeeper's (and its Confused), the Beenade's and the Honey Comb's
## bees; the Hive Wand; the Nectar's Baby Hornet; the Honeyed Goggles' Bee.
func _bee_loot_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var held := p.selected
	var was_god := p.god_mode
	var kept_slots := p.inventory.slots.duplicate(true)
	var kept_acc := p.accessories.slots.duplicate()
	p.god_mode = true
	var undefined := []
	for k in ["QueenBee", "Bee", "BeeSmall"]:
		var e: Dictionary = Data.npcs[k]
		var names := []
		for d in e.get("drops", []) + e.get("boss_drops", []):
			names.append(d[0])
		names.append_array(e.get("drops_one_of", []))
		for d in e.get("drops_chain", []):
			names.append_array(d[0] if d[0] is Array else [d[0]])
		for n in names:
			if not Data.items.has(n) and not n in undefined:
				undefined.append(n)
	check(undefined.is_empty(), "the Queen Bee's drops are all items in the game (undefined: %s)" % [undefined])
	var qb: Dictionary = Data.npcs.QueenBee
	check(qb.drops_one_of == ["BeeGun", "BeeKeeper", "BeesKnees"] and qb.drops.any(func(d): return d[0] == "BeeWax" and int(d[1]) == 17 and int(d[2]) == 30 and float(d[3]) == 1.0)
			and qb.drops.any(func(d): return d[0] == "Beenade" and d[1] == 10 and d[2] == 30 and is_equal_approx(d[3], 0.75)),
			"the Queen Bee drops one of the Bee Gun, Beekeeper and Bee's Knees, 17-30 Bee Wax, 3 in 4 10-30 Beenades")
	var gun := Data.item("BeeGun")
	var keeper := Data.item("BeeKeeper")
	var knees := Data.item("BeesKnees")
	check(int(gun.damage) == 9 and int(gun.mana) == 5 and int(gun.use_time) == 12 and gun.type == "magic"
			and int(keeper.damage) == 30 and int(keeper.use_time) == 20 and is_equal_approx(float(keeper.knockback), 5.3) and keeper.type == "melee"
			and int(knees.damage) == 23 and int(knees.use_time) == 23 and knees.type == "ranged",
			"Terraria's stats: the Bee Gun 9 magic, 5 mana, 12 ticks; the Beekeeper 30 melee, 20 ticks; the Bee's Knees 23 ranged, 23 ticks")
	check(int(Data.item("Beenade").damage) == 12 and Data.item("HiveWand").wand_ammo == "Hive" and Data.item("Nectar").pet == "BabyHornet"
			and Data.item("HoneyedGoggles").mount == "bee" and ["BeeHat", "BeeShirt", "BeePants"].all(func(i): return Data.item(i).get("vanity", false)),
			"the Beenade (12), Hive Wand (uses Hive), Nectar (Baby Hornet), Honeyed Goggles (the Bee) and the Bee vanity set")

	var arena := c + Vector3i(-30, 40, 30)
	for x in range(-14, 15):
		for z in range(-14, 15):
			w.set_block(arena + Vector3i(x, -1, z), Data.block_id("stone"))
			for y in range(0, 14):
				w.set_block(arena + Vector3i(x, y, z), 0)
				w.set_liquid(arena + Vector3i(x, y, z), 0, 0)
	for npc in game.npcs():
		if npc.def.ai != "town" and npc.global_position.distance_to(Vector3(arena)) < 60.0:
			npc.queue_free()
	var stand := func() -> void:
		p.global_position = Vector3(arena) + Vector3(0.5, 0, 0.5)
		p._fall_start = p.global_position.y
		p.velocity = Vector3.ZERO
		p.look_at_yaw_pitch(0.0, 0.0)
	var bees := func() -> Array:
		return game.entities.get_children().filter(func(e): return e is Projectile and e.kind == "Bee" and not e.is_queued_for_deletion())
	var clear := func() -> void:
		for b in bees.call():
			b.queue_free()
		for e in game.entities.get_children():
			if e is Projectile or e is ItemDrop:
				e.queue_free()
	var use := func(item: String) -> void:
		if p.inventory.slots[9] == null or p.inventory.slots[9].item != item:
			p.inventory.slots[9] = Inventory.stack(item, 1)
		p.select(9)
		p._use_timer = 0.0
		p._use_released = true
		p.use_item()
	var enemy := func(at: Vector3i, kind := "BlueSlime") -> NPC:
		var n := game.spawn_npc(kind, Vector3(arena + at) + Vector3(0.5, 0, 0.5))
		n.damage = 0
		return n
	stand.call()
	await frames(2)

	# The Bee Gun: 1 to 5 bees, each 9 or 10, that home in on an enemy.
	var counts := {}
	for i in 12:
		p.mana = p.mana_cap()
		use.call("BeeGun")
		counts[bees.call().size()] = true
		await clear.call()
		await frames(1)
	check(counts.keys().all(func(n): return n >= 1 and n <= 5) and counts.size() >= 2, "the Bee Gun shoots 1 to 5 bees (%s)" % [counts.keys()])
	p.mana = p.mana_cap()
	use.call("BeeGun")
	var shot: Array = bees.call()
	check(shot.all(func(b): return b.damage == p.weapon_damage(gun) or b.damage == p.weapon_damage(gun) + 1) and shot.all(func(b): return b.penetrate == 3),
			"its bees do its damage (1 in 2 one more) through 3 hits or bounces")
	await clear.call()
	# Homing: fired straight up, they find an enemy off to the side.
	var foe: NPC = enemy.call(Vector3i(7, 0, 0))
	var life0 := foe.life
	p.look_at_yaw_pitch(0.0, 1.4)
	p.mana = p.mana_cap()
	use.call("BeeGun")
	var stung := await _until(func(): return not is_instance_valid(foe) or foe.life < life0, 4.0)
	check(stung, "fired upward, its bees turn and sting an enemy off to the side")
	if is_instance_valid(foe):
		foe.queue_free()
	await clear.call()
	# Water kills a bee; honey doesn't.
	stand.call()
	var pool := arena + Vector3i(0, 0, -6)
	w.set_liquid(pool, Player.LIQ_WATER, 63)
	var wet: Array = Projectile.release_bees(game, 1, Vector3(pool) + Vector3(0.5, 0.5, 0.5), Vector3.ZERO, 5, 0.0)
	w.set_liquid(pool + Vector3i(2, 0, 0), Player.LIQ_HONEY, 63)
	var sticky: Array = Projectile.release_bees(game, 1, Vector3(pool + Vector3i(2, 0, 0)) + Vector3(0.5, 0.5, 0.5), Vector3.ZERO, 5, 0.0)
	await frames(3)
	check(not is_instance_valid(wet[0]) and is_instance_valid(sticky[0]), "a bee dies in water, not in honey")
	w.set_liquid(pool, 0, 0)
	w.set_liquid(pool + Vector3i(2, 0, 0), 0, 0)
	await clear.call()

	# The Bee's Knees: Wooden Arrows become Bee Arrows, breaking into bees.
	stand.call()
	await frames(1)
	p.inventory.slots[10] = Inventory.stack("WoodenArrow", 50)
	w.set_block(arena + Vector3i(0, 1, -5), Data.block_id("stone"))
	use.call("BeesKnees")
	var arrows := game.entities.get_children().filter(func(e): return e is Projectile and e.kind == "BeeArrow")
	check(arrows.size() == 1 and arrows[0].gravity == 0.0, "the Bee's Knees turns a Wooden Arrow into a Bee Arrow (no drop)")
	var dmg_arrow: int = arrows[0].damage if arrows.size() > 0 else 0
	var broke := await _until(func(): return bees.call().size() >= 3, 2.0)
	var kb: Array = bees.call()
	check(broke and kb.size() <= 6 and kb.all(func(b): return b.penetrate <= 2 and (b.damage == dmg_arrow / 3 or b.damage == dmg_arrow / 3 + 1)),
			"hitting a block it breaks into 3 to 6 bees, a third of its damage each, through 2 hits (%d bees)" % kb.size())
	w.set_block(arena + Vector3i(0, 1, -5), 0)
	p.inventory.slots[10] = null
	await clear.call()

	# The Beekeeper: bees from each hit, and the enemy Confused for 2 s.
	stand.call()
	foe = enemy.call(Vector3i(0, 0, -1))
	foe.life_max = 9999
	foe.life = 9999
	await frames(2)
	use.call("BeeKeeper")
	var kept: Array = bees.call()
	check(kept.size() >= 1 and kept.size() <= 3 and foe.confused > 1.9, "a Beekeeper hit lets loose 1 to 3 bees and Confuses the enemy (%d bees, %.1f s)" % [kept.size(), foe.confused])
	var keeper_dmg := p.weapon_damage(keeper) / 3
	check(kept.all(func(b): return b.damage == keeper_dmg or b.damage == keeper_dmg + 1), "the bees have a third of its damage")
	# Confused, a fighter walks away from you.
	foe.queue_free()
	var zombie: NPC = enemy.call(Vector3i(0, 0, -6), "Zombie")
	zombie.confuse(5.0)
	var z0 := zombie.global_position.distance_to(p.global_position)
	await frames(60)
	check(zombie.global_position.distance_to(p.global_position) > z0, "Confused, a Zombie walks away from you")
	zombie.queue_free()
	var boss := NPC.new()
	boss.boss = true
	boss.confuse(2.0)
	check(boss.confused == 0.0, "bosses shrug off Confused")
	boss.free()
	await clear.call()

	# The Beenade: thrown, it goes off into 15 to 24 bees, no blast.
	stand.call()
	p.look_at_yaw_pitch(0.0, 0.3)
	p.inventory.slots[9] = Inventory.stack("Beenade", 5)
	use.call("Beenade")
	check(p.inventory.slots[9].count == 4, "a Beenade is used up")
	var swarm := await _until(func(): return bees.call().size() >= 15, 4.0)
	var nb: Array = bees.call()
	check(swarm and nb.size() <= 24 and nb.all(func(b): return b.damage == 12 or b.damage == 13), "it bursts into 15 to 24 bees of 12 or 13 (%d)" % nb.size())
	await clear.call()
	await frames(1)

	# The Honey Comb: hurt by an enemy, bees and Honey; by lava, not.
	stand.call()
	p.accessories.slots[0] = Inventory.stack("HoneyComb", 1)
	p.god_mode = false
	p.life = p.life_cap()
	p._immune = 0.0
	foe = enemy.call(Vector3i(3, 0, 3))
	p.hurt(10, foe.center(), false, foe)
	var comb: Array = bees.call()
	check(comb.size() >= 1 and comb.size() <= 3 and comb.all(func(b): return b.damage == 13 or b.damage == 14) and p.honey_time >= 4.9,
			"the Honey Comb: hurt by an enemy, 1 to 3 bees of 13 and 5 s of Honey (%d)" % comb.size())
	await clear.call()
	p._immune = 0.0
	p.honey_time = 0.0
	p.hurt(10, Vector3.ZERO)
	check(bees.call().is_empty() and p.honey_time == 0.0, "but not from what isn't an enemy or a fall")
	foe.queue_free()
	p.accessories.slots[0] = null
	p.god_mode = true
	p.life = p.life_cap()
	await clear.call()

	# The Hive Wand places Hive, using up a Hive block each.
	stand.call()
	p.look_at_yaw_pitch(0.0, -0.6)
	await frames(2)
	p.inventory.slots[10] = Inventory.stack("Hive", 3)
	var hive_cells := func() -> Array:
		var out := []
		for x in range(-5, 6):
			for y in range(0, 6):
				for z in range(-5, 6):
					if w.get_block(arena + Vector3i(x, y, z)) == Data.block_id("hive"):
						out.append(arena + Vector3i(x, y, z))
		return out
	use.call("HiveWand")
	await frames(2)
	var hives: Array = hive_cells.call()
	check(hives.size() == 1 and p.inventory.count_of("Hive") == 2, "the Hive Wand places a Hive, using one up (%d)" % hives.size())
	p.inventory.slots[10] = null
	for q in hives:
		w.set_block(q, 0)

	# The Nectar: a Baby Hornet over your shoulder.
	stand.call()
	use.call("Nectar")
	check(p.pet != null and p.pet.kind == "BabyHornet" and p.buffs().any(func(b): return b[0] == 51), "the Nectar: a Baby Hornet (its buff)")
	var hornet: Minion = p.pet
	hornet.global_position = p.global_position + Vector3(10, 3, 0)
	var flew := await _until(func(): return hornet.center().distance_to(p.center()) < 4.0, 4.0)
	check(flew, "it flies after you")
	use.call("Nectar")
	await frames(1)
	check(p.pet == null, "used again, it goes")

	# The Honeyed Goggles: the Bee, 16 px higher; it hovers, climbs while you
	# hold jump, tires, and rests on the ground.
	stand.call()
	await frames(5)
	use.call("HoneyedGoggles")
	check(p.mount == "bee" and p.buffs().any(func(b): return b[0] == 132), "the Honeyed Goggles: you ride the Bee")
	await frames(3)
	Input.action_press("jump")
	await frames(40)
	var climb := p.velocity.y
	var high := p.global_position.y - arena.y
	Input.action_release("jump")
	check(high > 2.0 and climb > 15.0, "holding jump it climbs, up to 8 px a tick fresh (%.1f blocks up, %.1f blocks/s)" % [high, climb])
	await frames(70)
	check(absf(p.velocity.y) < 0.5 and p._fly_time > 0.0, "let go, it hangs in the air while its flight lasts (%.2f)" % p.velocity.y)
	p._fly_time = 0.0
	p._fatigue = 320.0
	await frames(30)
	check(p.velocity.y < -5.0, "worn out, it sinks (%.1f)" % p.velocity.y)
	await _until(func(): return p.on_floor, 4.0)
	await frames(10)
	check(p.on_floor and p.life == p.life_cap() and p._fly_time == 320.0 and p._fatigue < 320.0 - 15.0,
			"it lands unhurt, its flight back and resting off its fatigue (%.0f)" % p._fatigue)
	use.call("HoneyedGoggles")
	check(p.mount == "", "and again: off")

	await clear.call()
	p.inventory.slots = kept_slots
	p.inventory.changed.emit()
	p.accessories.slots = kept_acc
	p.accessories.changed.emit()
	p.select(held)
	p.god_mode = was_god
	p.life = p.life_cap()
	stand.call()
	p.global_position = Vector3(c) + Vector3(0.5, 0, 0.5)
	p._fall_start = p.global_position.y
	await frames(5)


## The summoner: minion staffs (slots, summon damage, each minion's AI), pets
## and the Shadow Orb, the Bee armor, where they come from.
func _summon_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var held := p.selected
	var was_god := p.god_mode
	var worn: Array = p.armor.slots.duplicate()
	p.god_mode = true
	var arena := c + Vector3i(30, 60, 30)
	for x in range(-18, 19):
		for z in range(-18, 19):
			w.set_block(arena + Vector3i(x, -1, z), Data.block_id("stone"))
			for y in range(0, 10):
				w.set_block(arena + Vector3i(x, y, z), 0)
	for npc in game.npcs():
		if npc.def.ai != "town" and npc.global_position.distance_to(Vector3(arena)) < 60.0:
			npc.queue_free()
	var stand := func() -> void:
		p.global_position = Vector3(arena) + Vector3(0.5, 0, 0.5)
		p._fall_start = p.global_position.y
		p.velocity = Vector3.ZERO
	stand.call()
	await frames(2)
	var use := func(item: String) -> void:
		p.inventory.slots[9] = Inventory.stack(item, 1)
		p.select(9)
		p._use_timer = 0.0
		p._use_released = true
		p.use_item()
	var enemy := func(at: Vector3i) -> NPC:
		var n := game.spawn_npc("BlueSlime", Vector3(arena + at) + Vector3(0.5, 0, 0.5))
		n.damage = 0
		return n
	# The Slime Staff: a Baby Slime, a minion slot, its buff.
	use.call("SlimeStaff")
	check(p.minions.size() == 1 and p.minions[0].kind == "BabySlime" and p.buffs().any(func(b): return b[0] == 64 and is_inf(b[2])),
			"the Slime Staff summons a Baby Slime (its buff shown, no time on it)")
	var first: Minion = p.minions[0]
	use.call("SlimeStaff")
	await frames(1)
	check(p.minions.size() == 1 and p.minions[0] != first and not is_instance_valid(first), "one minion slot: another sends the first off")
	# The Bee armor: two more slots, and with its set 23% summon damage.
	p.armor.slots = ["BeeHeadgear", "BeeBreastplate", "BeeGreaves"].map(func(i): return Inventory.stack(i, 1))
	check(p.max_minions() == 3 and p.weapon_damage(Data.item("SlimeStaff")) == roundi(8 * 1.23) and p.stat("summon_damage") == 23.0,
			"the Bee armor: 3 minion slots and 23%% summon damage (%d)" % p.weapon_damage(Data.item("SlimeStaff")))
	use.call("SlimeStaff")
	use.call("SlimeStaff")
	use.call("SlimeStaff")
	await frames(1)
	check(p.minions.size() == 3 and p.minions.map(func(m): return m.index) == [0, 1, 2], "three Baby Slimes, in line")
	p.armor.slots = worn.duplicate()
	p.cancel_buff("BabySlime")
	await frames(1)
	check(p.minions.is_empty() and p.companion_buffs().is_empty(), "cancelling the buff sends them off")
	# A Baby Slime hops after you, and flies back when you're far.
	use.call("SlimeStaff")
	var slime: Minion = p.minions[0]
	slime.global_position = Vector3(arena) + Vector3(9.5, 0, 0.5)
	var came := await _until(func(): return Vector2(slime.global_position.x - p.global_position.x, slime.global_position.z - p.global_position.z).length() < 3.0, 6.0)
	check(came and slime.ai0 == 0, "a Baby Slime hops after you")
	var fwd := p.forward()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var beside := await _until(func():
		var off := slime.global_position - p.global_position
		return absf(off.dot(fwd)) < 0.6 and off.dot(side) > 1.2, 4.0)
	check(beside, "and stands beside you, on your right (Terraria's line behind you, turned for first person)")
	slime.global_position = Vector3(arena) + Vector3(0.5, 0, 40.5)
	await frames(2)
	check(slime.ai0 == 1, "more than 500 px off it flies")
	came = await _until(func(): return slime.ai0 == 0 and slime.global_position.distance_to(p.global_position) < 6.0, 8.0)
	check(came, "back to you, landing near you")
	# It fights: an enemy it can see, hurt by touching it.
	var foe: NPC = enemy.call(Vector3i(5, 0, 3))
	var life0 := foe.life
	var hurt := await _until(func(): return not is_instance_valid(foe) or foe.life < life0, 6.0)
	check(hurt, "the Baby Slime goes for an enemy and hurts it")
	if is_instance_valid(foe):
		foe.queue_free()
	p.cancel_buff("BabySlime")
	await frames(1)
	# The Hornet: over you, stinging enemies (Poisoned).
	use.call("HornetStaff")
	var hornet: Minion = p.minions[0]
	var hovers := await _until(func(): return hornet.center().distance_to(p.center() + Vector3(0, 2.5, 0)) < 2.5, 4.0)
	check(hovers, "the Hornet hovers over you")
	foe = enemy.call(Vector3i(6, 0, -4))
	var stung := await _until(func(): return not is_instance_valid(foe) or foe.poisoned > 0.0, 6.0)
	check(stung, "and stings enemies, poisoning them")
	if is_instance_valid(foe):
		foe.queue_free()
	p.cancel_buff("HornetMinion")
	await frames(1)
	# The Imp: fireballs (On Fire!).
	use.call("ImpStaff")
	foe = enemy.call(Vector3i(-6, 0, 5))
	var burnt := await _until(func(): return not is_instance_valid(foe) or foe.on_fire > 0.0, 6.0)
	check(burnt, "the Imp's fireballs set enemies on fire")
	if is_instance_valid(foe):
		foe.queue_free()
	p.cancel_buff("ImpMinion")
	await frames(1)
	# The Finch: sits on your head, pecks enemies.
	use.call("BabyBirdStaff")
	var bird: Minion = p.minions[0]
	var sits := await _until(func(): return bird.frame == 4 and bird.vel == Vector3.ZERO, 5.0)
	check(sits and bird.center().y > p.center().y + 0.8, "the Finch sits on your head")
	foe = enemy.call(Vector3i(4, 0, 4))
	life0 = foe.life
	hurt = await _until(func(): return not is_instance_valid(foe) or foe.life < life0, 6.0)
	check(hurt, "and pecks enemies")
	if is_instance_valid(foe):
		foe.queue_free()
	p.cancel_buff("BabyBird")
	await frames(1)
	# Pets: one at a time, the item again sends it off; the Shadow Orb shines.
	use.call("EatersBone")
	check(p.pet != null and p.pet.kind == "BabyEater" and p.buffs().any(func(b): return b[0] == 45), "the Eater's Bone: a Baby Eater")
	use.call("EatersBone")
	await frames(1)
	check(p.pet == null, "used again, it goes")
	use.call("AmberMosquito")
	var dino := p.pet
	dino.global_position = Vector3(arena) + Vector3(8.5, 0, 0.5)
	came = await _until(func(): return Vector2(dino.global_position.x - p.global_position.x, dino.global_position.z - p.global_position.z).length() < 5.0, 6.0)
	check(came and dino.on_floor, "the Baby Dinosaur walks after you")
	use.call("BoneKey")
	await frames(1)
	check(p.pet != null and p.pet.kind == "BabySkeletronHead" and not is_instance_valid(dino), "another pet sends the first off")
	use.call("ShadowOrb")
	await frames(2)
	var shine := p.carried_light()
	check(p.light_pet != null and p.pet != null and shine.b > 0.89 and shine.r > 0.5, "the Shadow Orb: a light pet beside your pet, shining purple")
	var saved := p.save_state()
	p.load_state(saved)
	await frames(1)
	check(p.pet != null and p.pet.kind == "BabySkeletronHead" and p.light_pet != null and p.light_pet.kind == "ShadowOrb", "pets come back after saving")
	# Dying: minions go, pets stay.
	use.call("SlimeStaff")
	var coins := p.inventory.money()
	p.inventory.pay(coins)
	var at := p.global_position
	p._die()
	check(p.minions.is_empty() and p.pet != null and is_instance_valid(p.pet), "when you die your minions go, your pets stay")
	p._respawn()
	p.global_position = at
	p._fall_start = at.y
	p.inventory.add_money(coins)
	p.cancel_buff("BabySkeletronHead")
	p.cancel_buff("ShadowOrb")
	await frames(1)
	check(p.pet == null and p.light_pet == null, "pets' buffs cancel too")
	# The Slimy Saddle: riding a slime 20 px higher; its run (4 px/tick), its
	# jump (8.25 px/tick), and it stomps enemies it lands on.
	stand.call()
	var eye0 := p.camera.position.y
	use.call("SlimySaddle")
	check(p.mount == "slime" and absf(p.camera.position.y - eye0 - 20.0 / 24.0) < 0.01 and absf(p.half.y - 1.8 - 20.0 / 24.0) < 0.01
			and p.buffs().any(func(b): return b[0] == 130), "the Slimy Saddle: you ride a slime, 20 px higher")
	await frames(3)
	Input.action_press("move_forward")
	await frames(60)
	var run := Vector2(p.velocity.x, p.velocity.z).length()
	Input.action_release("move_forward")
	check(absf(run - 10.0) < 0.3, "riding, you run at the slime's 4 px a tick (%.2f blocks/s)" % run)
	stand.call()
	await frames(10)
	Input.action_press("jump")
	await frames(2)
	var rise := p.velocity.y
	var hops := await _until(func(): return p.on_floor, 3.0)
	await frames(3)
	var again := p.velocity.y > 0.0 or not p.on_floor
	Input.action_release("jump")
	check(absf(rise - (8.25 * 2.5 - Player.GRAVITY / 60.0)) < 0.3 and hops and again, "its jump is 8.25 px a tick, and holding jump keeps it hopping (%.1f)" % rise)
	await _until(func(): return p.on_floor, 3.0)
	foe = enemy.call(Vector3i(3, 0, 3))
	await frames(2)
	life0 = foe.life
	p.global_position = foe.global_position + Vector3(0, foe.half.y + 0.4, 0)
	p._fall_start = p.global_position.y
	p.velocity = Vector3(0, -8.0, 0)
	var stomped := await _until(func(): return not is_instance_valid(foe) or foe.life < life0, 1.0)
	check(stomped and p.velocity.y > 0.0, "landing on an enemy hurts it and bounces you up")
	if is_instance_valid(foe):
		foe.queue_free()
	use.call("SlimySaddle")
	check(p.mount == "" and absf(p.half.y - 1.8) < 0.01 and absf(p.camera.position.y - eye0) < 0.01, "and again: off")
	stand.call()
	await frames(5)
	var made := func(item: String) -> bool:
		return Data.recipes.any(func(r): return r.result == item)
	# AI_067: the Flinx bowls into enemies, the Vampire Frog leaps at them.
	use.call("FlinxStaff")
	foe = enemy.call(Vector3i(5, 0, -3))
	life0 = foe.life
	hurt = await _until(func(): return not is_instance_valid(foe) or foe.life < life0, 6.0)
	check(hurt and p.minions[0].kind == "FlinxMinion", "the Flinx Staff: a Flinx runs into enemies")
	if is_instance_valid(foe):
		foe.queue_free()
	p.cancel_buff("FlinxMinion")
	await frames(1)
	use.call("VampireFrogStaff")
	var frog: Minion = p.minions[0]
	foe = enemy.call(Vector3i(-5, 0, -3))
	life0 = foe.life
	var leapt := false
	var t_frog := 0.0
	while t_frog < 6.0 and is_instance_valid(foe) and foe.life >= life0:
		leapt = leapt or frog.attack_left > 0.0
		await get_tree().physics_frame
		t_frog += 1.0 / Engine.physics_ticks_per_second
	check(leapt and (not is_instance_valid(foe) or foe.life < life0), "the Vampire Frog leaps at enemies and hurts them")
	if is_instance_valid(foe):
		foe.queue_free()
	p.cancel_buff("VampireFrog")
	await frames(1)
	# Setting minions on an enemy: right-click it with a staff in hand.
	p.inventory.slots[9] = Inventory.stack("HornetStaff", 1)
	p.select(9)
	var near_foe: NPC = enemy.call(Vector3i(3, 0, 0))
	var far_foe: NPC = enemy.call(Vector3i(-12, 0, 0))
	await frames(2)
	# Held still, so neither strays into the other's stingers.
	near_foe.set_physics_process(false)
	far_foe.set_physics_process(false)
	var aim := far_foe.center() - p.camera.global_position
	p.look_at_yaw_pitch(atan2(-aim.x, -aim.z), atan2(aim.y, Vector2(aim.x, aim.z).length()))
	await frames(1)
	p._interact()
	await frames(2)
	check(p.minion_target == far_foe and p._target_marker != null and p._target_marker.visible, "right-clicking an enemy with a summon staff sets your minions on it (marked)")
	# (Summoned after, so it doesn't sting the nearer one before.)
	use.call("HornetStaff")
	var on_far := await _until(func(): return not is_instance_valid(far_foe) or far_foe.poisoned > 0.0, 6.0)
	check(on_far and is_instance_valid(near_foe) and near_foe.poisoned == 0.0, "the Hornet goes for it, not the nearer enemy")
	if is_instance_valid(far_foe):
		p._interact()
		check(p.minion_target == null, "and right-clicking it again lets it go")
		far_foe.queue_free()
	near_foe.queue_free()
	p.minion_target = null
	p.cancel_buff("HornetMinion")
	await frames(1)
	# The Crimson Heart and the Friendly Boulder.
	use.call("CrimsonHeart")
	await frames(2)
	var heart_light := p.carried_light()
	check(p.light_pet != null and p.light_pet.kind == "CrimsonHeart" and heart_light.r > 0.89 and heart_light.b < 0.35,
			"the Crimson Heart: a light pet shining red")
	p.cancel_buff("CrimsonHeart")
	use.call("BoulderPet")
	var rock := p.pet
	rock.global_position = Vector3(arena) + Vector3(-8.5, 0, 0.5)
	came = await _until(func(): return Vector2(rock.global_position.x - p.global_position.x, rock.global_position.z - p.global_position.z).length() < 4.0, 6.0)
	check(came and rock.kind == "BoulderPet", "the Friendly Boulder rolls after you")
	p.cancel_buff("BoulderPet")
	await frames(1)
	var pet_boulder := game.spawn_projectile("BoulderThatSpawnsPet", Vector3(arena) + Vector3(-4.5, 1.5, 4.5), Vector3.ZERO, 70, 7.0)
	pet_boulder.boulder = true
	pet_boulder._boulder_break(game)
	await frames(2)
	var dropped := game.entities.get_children().any(func(e): return e is ItemDrop and e.item == "BoulderPet")
	check(dropped, "the boulder that leaves a pet leaves a Friendly Boulder")
	for e in game.entities.get_children():
		if e is ItemDrop and e.item == "BoulderPet":
			e.queue_free()
	# The Snow Flinx: Flinx Fur for the Flinx Staff and Coat.
	check(Data.npcs.has("SnowFlinx") and Data.npcs.SnowFlinx.drops[0][0] == "FlinxFur" and made.call("FlinxStaff") and made.call("FlinxFurCoat"),
			"Snow Flinxes drop Flinx Fur, for the Flinx Staff and Flinx Fur Coat")
	# Whips: a crack hits what it passes, tags it for your minions.
	stand.call()
	await frames(3)
	foe = enemy.call(Vector3i(3, 0, 0))
	foe.set_physics_process(false)
	foe.life_max = 1000
	foe.life = 1000
	await frames(1)
	var to_foe := foe.center() - p.camera.global_position
	p.look_at_yaw_pitch(atan2(-to_foe.x, -to_foe.z), atan2(to_foe.y, Vector2(to_foe.x, to_foe.z).length()))
	await frames(1)
	life0 = foe.life
	use.call("BlandWhip")
	var whip_hit := await _until(func(): return not is_instance_valid(foe) or foe.life < life0, 1.5)
	check(whip_hit and is_instance_valid(foe) and foe.tag().get("damage", 0) == 4 and p.minion_target == foe,
			"the Leather Whip hits an enemy, tags it (4 tag damage) and sets your minions on it")
	var tagged_life := foe.life
	Minion.strike(game, foe, 10, 0.0, Vector3.FORWARD)
	check(tagged_life - foe.life >= 11, "a minion's hit on it does the tag's damage more (%d)" % [tagged_life - foe.life])
	await _until(func(): return p._use_timer <= 0.0, 2.0)
	await frames(2)
	use.call("ThornWhip")
	await _until(func(): return p.has_buff("ThornWhipPlayerBuff"), 1.5)
	check(p.has_buff("ThornWhipPlayerBuff") and p.stat("whip_speed") == 12.0, "the Snapthorn: Jungle's Fury, 12% whip speed")
	await _until(func(): return p._use_timer <= 0.0, 2.0)
	await frames(2)
	use.call("MeteorWhip")
	await _until(func(): return foe.tag().get("proc", "") == "meteor", 1.5)
	var meteors := func() -> int:
		return game.entities.get_children().filter(func(e): return e is Projectile and e.kind == "MeteorWhipMeteor").size()
	var m0: int = meteors.call()
	Minion.strike(game, foe, 10, 0.0, Vector3.FORWARD)
	check(meteors.call() == m0 + 1 and foe.tag().get("proc", "") == "", "the Meteor Whip: your minion's next hit brings down a meteor")
	foe.life_max = 1
	foe.queue_free()
	p.timed_buffs.clear()
	p.minion_target = null
	await _until(func(): return p._use_timer <= 0.0, 2.0)
	check(["SlimeWhip", "CobWhip", "CorruptWhip", "CrimsonWhip", "MeteorWhip", "ThornWhip", "BoneWhip"].all(func(w): return made.call(w)),
			"the whips are crafted (Terraria's recipes)")
	# The Spiked Ice Slime: near you, it sits and shoots Ice Spikes.
	stand.call()
	var spiky := game.spawn_npc("SpikedIceSlime", Vector3(arena) + Vector3(5.5, 0, 0.5))
	var spikes := func() -> Array:
		return game.entities.get_children().filter(func(e): return e is Projectile and e.kind == "IceSpike" and not e.friendly)
	var shot := await _until(func(): return not spikes.call().is_empty(), 4.0)
	var falls := false
	if shot:
		var sp: Projectile = spikes.call()[0]
		var vy0 := sp.velocity.y
		await frames(20)
		falls = is_instance_valid(sp) and sp.velocity.y < vy0
	var at0 := spiky.global_position
	await frames(60)
	check(shot and falls and Vector2(spiky.global_position.x - at0.x, spiky.global_position.z - at0.z).length() < 0.3,
			"the Spiked Ice Slime sits and shoots Ice Spikes at you, which fall")
	spiky.queue_free()
	for e in spikes.call():
		e.queue_free()
	# Debuffs: Chilled slows you a quarter, Frozen holds you, Cursed stops
	# items, Frostburn burns 8 a second; Warmth cuts the cold ones.
	stand.call()
	await frames(5)
	var run_speed := func() -> float:
		stand.call()
		await frames(3)
		# (Still speeding up: 0.08 px/tick², a quarter less chilled.)
		Input.action_press("move_forward")
		await frames(20)
		var v := Vector2(p.velocity.x, p.velocity.z).length()
		Input.action_release("move_forward")
		await frames(10)
		return v
	p.timed_buffs.clear()
	var free_run: float = await run_speed.call()
	p.debuff("Chilled", 10.0)
	var cold_run: float = await run_speed.call()
	check(p.has_buff("Chilled") and absf(cold_run / free_run - 0.75) < 0.03, "Chilled: a quarter slower (%.2f of %.2f)" % [cold_run, free_run])
	p.timed_buffs.clear()
	p.timed_buffs["Warmth"] = 60.0
	p.debuff("Chilled", 20.0)
	p.debuff("Frozen", 2.0)
	check(absf(p.timed_buffs.Chilled - 5.0) < 0.01 and absf(p.timed_buffs.Frozen - 1.0) < 0.01, "Warmth: Chilled a quarter as long, Frozen half")
	p.timed_buffs.clear()
	p.debuff("Frozen", 1.0)
	p.inventory.slots[9] = Inventory.stack("WoodenSword", 1)
	p.select(9)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	check(not p.can_act() and p._use_timer == 0.0, "Frozen: you can't move or use anything")
	p.timed_buffs.clear()
	p.debuff("Cursed", 1.0)
	p.use_item()
	check(p.can_act() and p._use_timer == 0.0 and "Cursed" in Player.DEBUFFS, "Cursed: no using items (and debuffs can't be right-clicked off)")
	p.timed_buffs.clear()
	p.god_mode = false
	p.life = p.life_cap()
	p._immune = 0.0
	p.debuff("Frostburn", 1.0)
	var burn0 := p.life
	await _until(func(): return not p.has_buff("Frostburn"), 2.0)
	check(burn0 - p.life >= 7 and burn0 - p.life <= 9, "Frostburn: 8 life a second (%d)" % [burn0 - p.life])
	# What enemies put on you: the Spiked Ice Slime's touch and its spikes.
	var cold_slime := game.spawn_npc("SpikedIceSlime", Vector3(arena) + Vector3(2.5, 0, 0.5))
	cold_slime.set_physics_process(false)
	p.life = p.life_cap()
	p._immune = 0.0
	p.hurt(cold_slime.damage, cold_slime.center(), false, cold_slime)
	check(p.has_buff("Chilled") and p.timed_buffs.Chilled > 19.0, "a Spiked Ice Slime's touch: Chilled for 20 s")
	p.timed_buffs.clear()
	stand.call()
	await frames(2)
	p._immune = 0.0
	var spike_shot := game.spawn_projectile("IceSpike", p.center() + Vector3(0, 0, 1.5), Vector3(0, 0, -10), 18, 0.0, 0.0, 0.0, 0.5, false)
	await _until(func(): return not is_instance_valid(spike_shot), 1.0)
	check(p.has_buff("Chilled"), "its Ice Spikes chill you too")
	p.timed_buffs.clear()
	# A slime's carried stone: Stoned.
	cold_slime.carry("StoneBlock")
	p._immune = 0.0
	p.hurt(cold_slime.damage, cold_slime.center(), false, cold_slime)
	check(p.has_buff("Stoned") and not p.can_act(), "a slime carrying stone: Stoned")
	p.timed_buffs.clear()
	cold_slime.queue_free()
	p.god_mode = true
	p.life = p.life_cap()
	# Slimes carry items, dropped when they die.
	var carrier := game.spawn_npc("BlueSlime", Vector3(arena) + Vector3(-3.5, 0, 0.5))
	carrier.carry("Torch")
	check(carrier.carried == "Torch" and carrier._carry_sprite != null, "a slime can carry an item, seen inside it")
	carrier.hit(1000, 0.0, Vector3.FORWARD, 0.0)
	await frames(2)
	var torches := game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "Torch")
	check(torches.size() >= 1 and torches[0].count >= 5 and torches[0].count <= 10, "and drops it when it dies (5 to 10 torches)")
	for e in torches:
		e.queue_free()
	var roller := game.spawn_npc("BlueSlime", Vector3(arena) + Vector3(-5.5, 0, 0.5))
	roller.set_physics_process(false)
	var carried_counts := {}
	var rolls := 0
	for i in 800:
		roller._roll_carried(game)
		if roller.carried != "":
			rolls += 1
			carried_counts[roller.carried] = carried_counts.get(roller.carried, 0) + 1
	roller.carry("")
	roller.queue_free()
	check(rolls > 30 and rolls < 95 and carried_counts.has("Cloud"), "surface slimes: about 1 in 13 carry something, a Cloud among them (%d of 800: %s)" % [rolls, carried_counts])
	# The Vulture: perched till you come near, then it flies.
	stand.call()
	var vulture := game.spawn_npc("Vulture", Vector3(arena) + Vector3(10.5, 0, 0.5))
	await frames(60)
	var perched := vulture.ai_state == 0 and not vulture.flying
	vulture.global_position = p.global_position + Vector3(2.0, 0, 0)
	vulture.velocity = Vector3.ZERO
	var flew := await _until(func(): return vulture.ai_state == 1 and vulture.flying, 1.0)
	await frames(30)
	check(perched and flew and vulture.global_position.y > p.global_position.y + 0.5, "the Vulture sits till you come near, then flies up at you")
	vulture.queue_free()
	# Poisoned enemies: 6 life a second.
	foe = enemy.call(Vector3i(8, 0, -8))
	foe.life = 100
	foe.life_max = 100
	foe.poison(1.0)
	await _until(func(): return foe.poisoned <= 0.0, 2.0)
	check(foe.life >= 92 and foe.life <= 95, "Poisoned: 6 life a second (%d left of 100)" % foe.life)
	foe.queue_free()
	# Where they come from.
	check(made.call("HornetStaff") and made.call("ImpStaff") and made.call("BeeHeadgear"),
			"the Hornet and Imp Staffs, the Bee armor are crafted (Terraria's recipes)")
	var finds := {}
	var paired := true
	for i in 120:
		var got := Game.roll_loot("living_chest").map(func(dd): return dd[0])
		for g in got:
			finds[g] = true
		paired = paired and (got.has("LivingWoodWand") == got.has("LeafWand")) and not (got.has("LivingWoodWand") and got.has("BabyBirdStaff"))
	check(finds.has("BabyBirdStaff") and finds.has("LivingWoodWand") and paired and Chests.LOOT[27] == "living_chest",
			"a living tree's chest: a Living Wood and a Leaf Wand, or a Finch Staff")
	var orb := {}
	for i in 200:
		for dd in Game.roll_loot("shadow_orb"):
			orb[dd[0]] = true
	check(orb.has("ShadowOrb") and orb.has("Vilethorn"), "a Shadow Orb can hold the Shadow Orb pet")
	check(Data.npcs.GreenSlime.drops.any(func(dd): return dd[0] == "SlimeStaff" and is_equal_approx(dd[3], 0.0001)),
			"slimes drop the Slime Staff, 1 in 10000")
	check(Data.block_textures.get_layers() <= Data.MAX_LAYERS, "block textures fit the GPU (%d layers)" % Data.block_textures.get_layers())
	p.armor.slots = worn
	p.inventory.slots[9] = null
	p.select(held)
	p.god_mode = was_god
	p.life = p.life_cap()


## Rain, storms and the Blood Moon (Phase 4), their enemies and drops.
func _weather_checks(c: Vector3i) -> void:
	var p := game.player
	var w: VoxelWorld = game.world
	var sky: SkySystem = game.sky
	var held := p.selected
	var was_god := p.god_mode
	p.god_mode = true
	var saved := sky.save_state()
	var arena := c + Vector3i(-30, 60, 30)
	for x in range(-14, 15):
		for z in range(-14, 15):
			w.set_block(arena + Vector3i(x, -1, z), Data.block_id("stone"))
			for y in range(0, 24):
				w.set_block(arena + Vector3i(x, y, z), 0)
	for npc in game.npcs():
		if npc.def.ai != "town":
			npc.queue_free()
	var stand := func() -> void:
		p.global_position = Vector3(arena) + Vector3(0.5, 0, 0.5)
		p._fall_start = p.global_position.y
		p.velocity = Vector3.ZERO
	stand.call()
	game.spawner.set_physics_process(false)
	await frames(2)
	# Rain's timing and strength (StartRain, ChangeRain).
	var shortest := 1 << 30
	var longest := 0
	var weakest := 1.0
	var strongest := 0.0
	sky.cloudiness = 0.3
	for i in 300:
		sky.start_rain()
		shortest = mini(shortest, sky.rain_time)
		longest = maxi(longest, sky.rain_time)
		weakest = minf(weakest, sky.max_raining)
		strongest = maxf(strongest, sky.max_raining)
	check(sky.raining and shortest >= 8 * 3600 and longest <= int((86400 + 17 * 3600) * 1.5) and longest > 86400,
			"rain lasts 8 to 24 game hours, often more (%d to %d ticks)" % [shortest, longest])
	check(weakest >= 0.05 and strongest <= 0.4 and strongest > 0.3, "under few clouds it rains 5 to 40%% hard (%.2f to %.2f)" % [weakest, strongest])
	sky.cloudiness = 0.95
	strongest = 0.0
	weakest = 1.0
	for i in 300:
		sky.change_rain()
		weakest = minf(weakest, sky.max_raining)
		strongest = maxf(strongest, sky.max_raining)
	check(weakest >= 0.2 and strongest <= 0.9 and strongest > 0.8, "overcast, 20 to 90%% (%.2f to %.2f)" % [weakest, strongest])
	# It comes in slowly (0.0005 a tick) and darkens the day.
	sky.is_day = true
	sky.time = 30000.0
	sky.max_raining = 0.6
	sky.cloud_alpha = 0.0
	sky.wind_target = 0.0
	for i in 100:
		sky.rain_tick()
	check(is_equal_approx(sky.cloud_alpha, 0.05), "the rain comes in 0.0005 a tick (%.4f after 100)" % sky.cloud_alpha)
	sky.cloud_alpha = 0.6
	sky._update_visuals(0.0)
	var wet_light := sky.sky_light
	sky.cloud_alpha = 0.0
	sky._update_visuals(0.0)
	var dry_light := sky.sky_light
	sky.raining = true
	sky.cloud_alpha = 0.6
	check(absf(wet_light - dry_light * (1.0 - 0.6 * 0.9)) < 0.03, "rain darkens the day by 0.9 x how wet it is (%.2f vs %.2f)" % [wet_light, dry_light])
	# Storms: wet and windy enough, with lightning and thunder.
	sky.wind_target = 0.5
	sky.rain_tick()
	check(sky.storm, "60% rain and 0.5 wind: a storm")
	sky.wind_target = 0.36
	sky.rain_tick()
	check(sky.storm, "it stays a storm down to 0.34 wind")
	sky.wind_target = 0.3
	sky.rain_tick()
	check(not sky.storm, "and ends below it")
	sky.wind_target = 0.5
	sky.rain_tick()
	var thunder := [0]
	var on_thunder := func(_d): thunder[0] += 1
	sky.thunder.connect(on_thunder)
	sky.new_lightning()
	var flashed := false
	for i in 120:
		sky.rain_tick()
		flashed = flashed or sky.lightning > 0.9
	sky.thunder.disconnect(on_thunder)
	check(flashed and thunder[0] == 1, "lightning flashes, and its thunder follows")
	check(game.surface_music() == "Storm", "a storm has its music (%s)" % game.surface_music())
	sky.storm = false
	sky.wind_target = 0.0
	sky.time = 5000.0
	check(game.surface_music() == "MorningRain", "rain in the morning: Morning Rain")
	sky.time = 30000.0
	check(game.surface_music() == "Rain", "rain later in the day: Rain")
	# Raindrops fall round you on the surface, splashing where they land.
	# (The rain ticks above may have changed how wet it gets; the cap follows
	# how wet it is, so check against the wettest it got.)
	var wettest := sky.cloud_alpha
	for i in 60:
		await frames(1)
		wettest = maxf(wettest, sky.cloud_alpha)
	var drops: int = game.rain._drops.size()
	var sheet := Assets.texture("Images/Rain")
	check(drops > 50 and drops <= int(RainFall.MAX_RAIN * wettest) and sheet != null, "raindrops fall round you (%d, at most 750 x %d%%)" % [drops, roundi(wettest * 100.0)])
	check(game.herbs.raining(), "the herbs know it's raining (Waterleaf blooms)")
	# Rain's enemies: by day Flying Fish and Umbrella Slimes, by night Raincoat Zombies.
	var counts := {}
	for i in 4000:
		var k := Spawner.surface_pick("", false, sky)
		counts[k] = counts.get(k, 0) + 1
	check(absf(counts.get("FlyingFish", 0) / 4000.0 - 0.25) < 0.03 and absf(counts.get("UmbrellaSlime", 0) / 4000.0 - 0.375) < 0.03,
			"a rainy day: 1 in 4 a Flying Fish, then 1 in 2 an Umbrella Slime (%s)" % counts)
	counts = {}
	sky.is_day = false
	sky.moon_phase = 0
	for i in 4000:
		var k := Spawner.surface_pick("", true, sky)
		counts[k] = counts.get(k, 0) + 1
	check(absf(counts.get("ZombieRaincoat", 0) / 4000.0 - 5.0 / 12.0) < 0.03 and absf(counts.get("DemonEye", 0) / 4000.0 - 1.0 / 6.0) < 0.03,
			"a rainy night: 1 in 6 a Demon Eye, else half Raincoat Zombies (%s)" % counts)
	# Underground, no rain.
	sky.stop_rain()
	sky.cloud_alpha = 0.0
	check(not sky.raining and not game.herbs.raining(), "the rain stops")
	# The Blood Moon: rolled at dusk, red, its music, its enemies, over at dawn.
	game.start_blood_moon()
	check(sky.blood_moon and game.surface_music() == "Eerie", "a Blood Moon rises, with Eerie music")
	await frames(2)
	check(sky.sky_tint.r > sky.sky_tint.g * 2.0, "the Blood Moon's night is red (%s)" % sky.sky_tint)
	counts = {}
	for i in 30000:
		var k := Spawner.surface_pick("", true, sky)
		counts[k] = counts.get(k, 0) + 1
	var bz: float = counts.get("BloodZombie", 0) / 30000.0
	var dr: float = counts.get("Drippler", 0) / 30000.0
	check(absf(bz - 1.0 / 6.0) < 0.015 and absf(dr - 1.0 / 6.0) < 0.015 and counts.has("TheGroom") and counts.has("TheBride"),
			"under a Blood Moon: Blood Zombies and Dripplers (each 1 in 6 of spawns), rarely the Groom and the Bride (%s)" % counts)
	# (The Eye of Cthulhu, when it comes at dusk, comes instead.)
	var eye_beaten: bool = game.defeated_bosses.has("EyeofCthulhu")
	game.defeated_bosses["EyeofCthulhu"] = true
	var rolls := 0
	for i in 2700:
		sky.blood_moon = false
		game._on_dusk()
		if sky.blood_moon:
			rolls += 1
	check(rolls > 230 and rolls < 375, "at dusk, 1 night in 9 a Blood Moon (%d of 2700)" % rolls)
	sky.moon_phase = 4
	rolls = 0
	for i in 900:
		sky.blood_moon = false
		game._on_dusk()
		rolls += 1 if sky.blood_moon else 0
	check(rolls == 0, "never at a new moon")
	if not eye_beaten:
		game.defeated_bosses.erase("EyeofCthulhu")
	sky.moon_phase = 0
	sky.blood_moon = true
	var bs := sky.save_state()
	check(bs.blood_moon and bs.has("raining") and bs.has("rain_time"), "the weather and the Blood Moon are saved")
	sky.time = sky.NIGHT_LENGTH - 1.0
	await _until(func(): return sky.is_day, 1.0)
	check(sky.is_day and not sky.blood_moon, "the Blood Moon is over at dawn")
	# The Bloody Tear: a Blood Moon at night only, used up only then.
	var use := func(item: String) -> void:
		p.inventory.slots[9] = Inventory.stack(item, 1)
		p.select(9)
		p._use_timer = 0.0
		p._use_released = true
		p.use_item()
	use.call("BloodMoonStarter")
	await frames(2)
	check(not sky.blood_moon and p.inventory.slots[9] != null, "the Bloody Tear does nothing by day (not used up)")
	sky.is_day = false
	sky.time = 1000.0
	sky.moon_phase = 4
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	await frames(2)
	check(sky.blood_moon and p.inventory.slots[9] == null and sky.moon_phase == 5, "at night it brings the Blood Moon (a new moon turns waxing crescent)")
	# The new enemies move as Terraria's do.
	var px := 60.0 / 24.0
	# (Its top speed: (2.5 - 0.0025 x px away) x 0.8: 1.38 px/tick 13 blocks
	# off, nearly 2 close.)
	var zed := game.spawn_npc("BloodZombie", Vector3(arena) + Vector3(13.5, 0, 0.5))
	zed.damage = 0
	await frames(30)
	var far_speed := Vector2(zed.velocity.x, zed.velocity.z).length() / px
	zed.global_position = Vector3(arena) + Vector3(7.5, 0, 0.5)
	zed.velocity = Vector3.ZERO
	var near_speed := 0.0
	for i in 120:
		await frames(1)
		if Vector2(zed.global_position.x - p.global_position.x, zed.global_position.z - p.global_position.z).length() < 1.5:
			break
		near_speed = maxf(near_speed, Vector2(zed.velocity.x, zed.velocity.z).length() / px)
	check(far_speed > 1.2 and far_speed < 1.5 and near_speed > 1.75 and near_speed <= 2.01,
			"the Blood Zombie quickens as it nears you (%.2f px/tick 13 blocks off, up to %.2f close)" % [far_speed, near_speed])
	zed.queue_free()
	var fish := game.spawn_npc("FlyingFish", Vector3(arena) + Vector3(12.5, 4, 0.5))
	fish.damage = 0
	var fast := 0.0
	var climb := 0.0
	for i in 150:
		await frames(1)
		if not is_instance_valid(fish):
			break
		fast = maxf(fast, Vector2(fish.velocity.x, fish.velocity.z).length() / px)
		climb = maxf(climb, absf(fish.velocity.y) / px)
	check(fast > 2.0 and fast <= 3.05 and climb <= 1.05, "the Flying Fish: up to 3 px/tick across, 1 up or down (%.2f, %.2f)" % [fast, climb])
	if is_instance_valid(fish):
		fish.queue_free()
	var drip := game.spawn_npc("Drippler", Vector3(arena) + Vector3(10.5, 3, 0.5))
	drip.damage = 0
	var drift := 0.0
	var lowest := 100.0
	for i in 200:
		await frames(1)
		drift = maxf(drift, Vector2(drip.velocity.x, drip.velocity.z).length() / px)
		lowest = minf(lowest, drip.global_position.y - arena.y)
	check(drift > 1.0 and drift <= 1.55 and lowest > 0.3, "the Drippler drifts at you (up to 1.5 px/tick), hovering off the ground (lowest %.1f)" % lowest)
	drip.queue_free()
	# Their drops (Terraria's ItemDropDatabase).
	var has_drop := func(kind: String, item: String, chance: float) -> bool:
		return Data.npcs[kind].drops.any(func(dd): return dd[0] == item and absf(float(dd[3]) - chance) < 0.0001)
	check(has_drop.call("BloodZombie", "SharkToothNecklace", 1.0 / 150.0) and has_drop.call("Drippler", "MoneyTrough", 0.005)
			and has_drop.call("TheGroom", "TopHat", 1.0) and has_drop.call("FlyingFish", "Fries", 0.02),
			"the Blood Moon's and rain's enemies drop Terraria's items")
	var hats := 0
	var gel := 0
	var slime := game.spawn_npc("UmbrellaSlime", Vector3(arena) + Vector3(5.5, 0, 0.5))
	slime.set_physics_process(false)
	for i in 450:
		for dd in Data.npcs.UmbrellaSlime.drops_chain:
			if randf() < float(dd[1]):
				if dd[0] == "UmbrellaHat":
					hats += 1
				else:
					gel += 1
				break
	slime.queue_free()
	check(hats > 2 and hats < 25 and hats + gel == 450, "the Umbrella Slime: its hat 1 in 45, else gel (%d hats)" % hats)
	# The Shark Tooth Necklace: 5 armor penetration.
	var pen := p.armor_penetration(Data.item("WoodenSword"))
	p.accessories.slots[0] = Inventory.stack("SharkToothNecklace", 1)
	check(p.armor_penetration(Data.item("WoodenSword")) == pen + 5, "the Shark Tooth Necklace: 5 armor penetration")
	p.accessories.slots[0] = null
	# The Umbrella: held, you fall at most 2 px/tick.
	p.inventory.slots[9] = Inventory.stack("Umbrella", 1)
	p.select(9)
	p.global_position = Vector3(arena) + Vector3(0.5, 20, 0.5)
	p._fall_start = p.global_position.y
	p.velocity = Vector3.ZERO
	await frames(60)
	var fall := -p.velocity.y / px
	await _until(func(): return p.on_floor, 3.0)
	check(fall > 1.9 and fall < 2.05 and p.life == p.life_cap(), "holding the Umbrella you fall at 2 px/tick, unhurt (%.2f)" % fall)
	# The Money Trough: the Flying Piggy Bank, your Piggy Bank in it.
	stand.call()
	p.look_at_yaw_pitch(0.0, 0.0)
	use.call("MoneyTrough")
	await frames(90)
	var pigs := game.entities.get_children().filter(func(e): return e is FlyingPiggyBank)
	check(pigs.size() == 1 and p.inventory.slots[9] != null and pigs[0]._settled, "the Money Trough throws out the Flying Piggy Bank (not used up); it stops and bobs")
	if pigs.size() == 1:
		p.look_at_yaw_pitch(0.0, 0.0)
		var to: Vector3 = pigs[0].global_position - p.camera.global_position
		p.look_at_yaw_pitch(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
		await frames(2)
		p._interact()
		check(game.hud._chest == p.piggy_bank, "right-click it: your Piggy Bank")
		game.hud.close_inventory()
		use.call("MoneyTrough")
		await frames(2)
		check(game.entities.get_children().filter(func(e): return e is FlyingPiggyBank and not e.is_queued_for_deletion()).size() == 1, "one at a time")
		for e in game.entities.get_children():
			if e is FlyingPiggyBank:
				e.queue_free()
	check(Data.loot.chest_surface.pick_one.any(func(dd): return dd[0] == "Umbrella"), "surface chests can hold the Umbrella")
	sky.load_state(saved)
	sky.blood_moon = false
	sky.stop_rain()
	sky.cloud_alpha = 0.0
	game.spawner.set_physics_process(true)
	p.inventory.slots[9] = null
	p.select(held)
	p.god_mode = was_god
	p.life = p.life_cap()


## Slime Rain: its timing, its falling slimes, King Slime after enough kills.
func _slime_rain_checks(c: Vector3i) -> void:
	var p := game.player
	var sky: SkySystem = game.sky
	var saved := sky.save_state()
	var was_god := p.god_mode
	p.god_mode = true
	# (On the open ground west of the middle: room overhead for the slimes.)
	var arena := c + Vector3i(-90, 0, 0)
	for npc in game.npcs():
		if npc.def.ai != "town":
			npc.queue_free()
	p.global_position = Vector3(arena) + Vector3(0.5, 0, 0.5)
	p._fall_start = p.global_position.y
	p.velocity = Vector3.ZERO
	game.spawner.set_physics_process(false)
	await frames(2)
	sky.stop_rain()
	sky.cloud_alpha = 0.0
	sky.is_day = true
	sky.time = 5000.0
	# Its length and the wait after it.
	var shortest := 1e9
	var longest := 0.0
	var wait_short := 1e9
	var wait_long := 0.0
	for i in 200:
		sky.slime_rain = false
		sky.slime_rain_time = 0.0
		sky.start_slime_rain()
		shortest = minf(shortest, sky.slime_rain_time)
		longest = maxf(longest, sky.slime_rain_time)
		sky.stop_slime_rain()
		wait_short = minf(wait_short, -sky.slime_rain_time)
		wait_long = maxf(wait_long, -sky.slime_rain_time)
	check(shortest >= 32400 and longest < 54000 and wait_short >= 302400 and wait_long < 604800,
			"Slime Rain lasts 9 to 15 minutes (%d to %d ticks), then 3.5 to 7 days pass before another" % [shortest, longest])
	# No new one while the wait lasts; not in the rain.
	sky.slime_rain_time = -100.0
	sky.strongest_life = 400
	sky.strongest_defense = 20
	for i in 99:
		sky.slime_rain_tick()
	check(not sky.slime_rain and sky.slime_rain_time == -1.0, "the wait counts down a tick at a time, and none comes meanwhile")
	sky.raining = true
	sky.start_slime_rain()
	check(not sky.slime_rain, "never in the rain")
	sky.raining = false
	# It starts: its message after 420 ticks, its music.
	var news := []
	var on_news := func(started): news.append(started)
	sky.slime_rain_news.connect(on_news)
	sky.slime_rain_time = 0.0
	sky.start_slime_rain()
	for i in 420:
		sky.slime_rain_tick()
	check(sky.slime_rain and news == [true], "Slime is falling from the sky! (420 ticks after it starts)")
	sky.slime_rain_news.disconnect(on_news)
	game._update_music(p.global_position)
	check(game.surface_music() != "" and Audio._current_track == "SlimeRain", "its music plays on the surface (%s)" % Audio._current_track)
	game._update_playing(0.016)
	await frames(3)
	var shown := 0
	for b in sky._slime_sky._batches:
		shown += b.multimesh.visible_instance_count
	check(sky._slime_sky.active and shown > 20, "slimes fall far off in the sky (%d in view)" % shown)
	# Slimes fall from high over you.
	var spawned := []
	for i in 6000:
		game.spawner.slime_rain_tick()
		for npc in game.npcs():
			if npc.def.ai == "slime" and not npc in spawned:
				spawned.append(npc)
		if spawned.size() >= 8:
			break
	var high := spawned.all(func(npc): return npc.global_position.y - p.global_position.y > 30.0 and npc.kind in Game.SLIME_RAIN_SLIMES)
	check(spawned.size() >= 8 and high, "slimes start 37 to 75 blocks over you (%d: %s)" % [spawned.size(), spawned.map(func(npc): return npc.kind)])
	for npc in spawned:
		npc.queue_free()
	await frames(1)
	# (Terraria's picks: 1 in 200 Pinky, 1 in 10 Purple, 2 in 5 Green, else Blue.)
	check(Data.npcs.has("PurpleSlime") and Data.npcs.has("Pinky") and Data.npcs.Pinky.drops.any(func(dd): return dd[0] == "PinkGel" and dd[1] == 25 and dd[2] == 50),
			"Purple Slimes and Pinkies (25 to 50 Pink Gel)")
	# 150 slimes killed: King Slime.
	var slime := game.spawn_npc("GreenSlime", Vector3(arena) + Vector3(5.5, 0, 0.5))
	slime.set_physics_process(false)
	var beaten: bool = game.defeated_bosses.has("KingSlime")
	game.defeated_bosses.erase("KingSlime")
	sky.slime_rain_kills = 0
	for i in 149:
		game.advance_slime_rain(slime)
	var before := game.npcs().any(func(npc): return npc.kind == "KingSlime")
	game.advance_slime_rain(slime)
	var king := game.npcs().filter(func(npc): return npc.kind == "KingSlime")
	check(not before and king.size() == 1 and sky.slime_rain_kills == -75, "150 slimes killed in it: King Slime comes (the count starts again at -75)")
	slime.queue_free()
	if king.size() == 1:
		king[0].hit(100000, 0.0, Vector3.FORWARD, 0.0)
		await frames(3)
	check(not sky.slime_rain, "beating King Slime ends the Slime Rain")
	if not beaten:
		game.defeated_bosses.erase("KingSlime")
	var bs := sky.save_state()
	check(bs.has("slime_rain") and bs.has("slime_rain_time") and bs.has("slime_rain_kills"), "Slime Rain is saved with the world")
	for e in game.entities.get_children():
		if e is ItemDrop:
			e.queue_free()
	sky.load_state(saved)
	sky.slime_rain = false
	sky.slime_rain_time = -1000.0
	game.spawner.set_physics_process(true)
	p.god_mode = was_god
	p.life = p.life_cap()
