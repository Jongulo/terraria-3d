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
	await _platform_checks(c)
	await _rope_checks(c)
	await _hook_checks(c)
	await _accessory_checks(c)
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
	_sword_shrine_checks(c)
	await _swim_checks(c)
	await _screenshot_checks()
	await _eater_checks(c)
	await _king_slime_checks(c)
	await _recipe_checks(c)
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
	check(town_after == town_before and town_after.size() == 6, "the town's residents come back with their names and homes (%s)" % [town_after])
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
	var floor_at := m + Vector3i(0, -3, 0)
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
	# No Old Man once it's beaten; until then, he's back at dawn.
	game._on_dawn()
	check(game.npcs().filter(func(n): return n.kind == "OldMan").is_empty(), "the Old Man doesn't come back once Skeletron is beaten")
	game.defeated_bosses.erase("SkeletronHead")
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

	# The arena's gate: a closed door facing west (toward spawn).
	var gate := c + Vector3i(9, 0, 0)
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
	for z in range(-8, -2):
		w.set_block(base + Vector3i(3, 0, z), id.call("tall_grass"))
		w.set_block(base + Vector3i(-3, 0, z), id.call("tall_grass"))
	game.spawn_projectile("WoodenArrowFriendly", Vector3(base) + Vector3(3.5, 0.5, -2.2), Vector3(0, 0, -20), 5, 0.0)
	game.spawn_projectile("WoodenArrowFriendly", Vector3(base) + Vector3(-2.5, 0.5, -2.2), Vector3(0, 0, -20), 5, 0.0, 0.0, 0.0, 0.5, false)
	for i in 30:
		await get_tree().physics_frame
	check(range(-8, -2).all(func(z): return w.get_block(base + Vector3i(3, 0, z)) == 0), "your arrow cuts the grass it flies through")
	check(range(-8, -2).all(func(z): return w.get_block(base + Vector3i(-3, 0, z)) == id.call("tall_grass")), "an enemy's doesn't")
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
## the ground: worked out by a transcription of them, in blocks).
const KNOCKBACK_TERRARIA := {
	"Zombie": [1.713, 4.052], "BlueSlime": [2.434, 4.24], "DemonEye": [1.108, 5.392],
	"EaterofSouls": [3.203, 8.25], "CaveBat": [6.581, 9.131],
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
	var want := ["tall_grass", "taller_grass", "flowers", "tall_flowers", "mushroom", "daybloom", "sunflower", "small_rocks",
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
	# Drops: a mushroom, Daybloom and sunflowers.
	var drops := func(name: String) -> int:
		return game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == name).size()
	for pair in [["mushroom", "Mushroom"], ["daybloom", "Daybloom"], ["sunflower", "Sunflower"]]:
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
	var surface_items := ["Spear", "WoodenBoomerang", "Aglet", "ClimbingClaws", "CordageGuide", "Radar"]
	var top := Vector3i(c.x + 3, TestWorld.GROUND + 1, c.z + 60)
	var all_surface := true
	for i in 12:
		game.chests._worldgen[Chests.key(top)] = "chest"
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
	var drops := game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "Rope")
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
				names[Data.block(w.get_block(a + Vector3i(x, y, z))).get("name", "")] = true
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
		var dropped: bool = Data.npcs.values().any(func(e): return e.get("drops", []).any(func(x): return x[0] == n) or n in e.get("drops_one_of", []) or e.get("drops_chain", []).any(func(x): return x[0] == n))
		var in_set: bool = Data.loot.values().any(func(t): return t is Dictionary and t.get("sets", []).any(func(e): return n in e[0]))
		var sources: bool = Data.recipes.any(func(r): return r.result == n) or Data.loot.chest.extras.any(func(e): return e[0] == n) or dropped or in_set
		if not d.get("slot") in Data.ARMOR_SLOTS or Assets.armor_texture(d.slot, n) == null or d.id == 0 or not sources:
			bad.append(n)
	check(armor_items.size() >= 50 and bad.is_empty(), "%d armor pieces, each with its equip sprite and a recipe, chest or enemy drop (bad: %s)" % [armor_items.size(), bad])
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

	# The test town: five residents, each at home.
	check(town.residents.size() == 6 and Town.ROSTER.all(func(k): return town.residents.has(k)), "the Guide, Merchant, Nurse, Arms Dealer, Dryad and Demolitionist live in the test town")
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
	var merchant: NPC = town.residents.Merchant
	town.residents.erase("Merchant")
	town.arrived.erase("Merchant")
	merchant.queue_free()
	await frames(2)
	p.global_position = Vector3(TestWorld.town_house(c, 1)) + Vector3(-4, 0, 3)
	var money := p.inventory.money()
	p.inventory.pay(money)
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
	var d0: float = ks.global_position.distance_to(p.global_position)
	var jumped := false
	for i in 300:
		await get_tree().physics_frame
		if ks.velocity.y > 15.0:
			jumped = true
	var d1: float = ks.global_position.distance_to(p.global_position)
	check(jumped and d1 < d0 - 5.0, "it hops at you (%.1f -> %.1f blocks)" % [d0, d1])
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
	game._collected_drops = {}
	game.break_block(q, true, true)
	var got: Dictionary = game._collected_drops
	game._collected_drops = null
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
	check(not p.viewmodel.item_node().visible and p.carried_light().r >= 0.8, "it's out of your hand and shines while you slash")
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
	var odd := Data.recipes.filter(func(r): return not r.get("terraria", false) and not r.has("stand_in"))
	var stand_ins: Array = Data.recipes.filter(func(r): return r.has("stand_in")).map(func(r): return r.result)
	check(odd.is_empty() and stand_ins == ["HellstoneBar"],
			"every recipe is Terraria's but one marked stand-in (%s)" % [stand_ins])
	check(find.call("MusketBall").is_empty() and find.call("Shuriken").is_empty(), "no recipes Terraria doesn't have (Musket Balls, Shurikens)")
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
	# A switch and the light it's wired to.
	var sw := Vector3i(-1, -1, -1)
	for k in game.wires:
		if (game.wires[k] - d).length() < 120:
			var parts: PackedStringArray = k.split(",")
			sw = Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
			break
	check(sw.y >= 0, "the Dungeon's lights have switches")
	if sw.y >= 0:
		var light: Vector3i = game.wires[Chests.key(sw)]
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
