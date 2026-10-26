extends Node
## Scripted end-to-end session: creates a world, then exercises digging,
## pickups, building, crafting, combat, chests, the boss and save/load.
## godot --path game res://tests/game_test.tscn -- <screenshot dir>

var game: Game
var out_dir := "user://"
var failures: Array[String] = []
var _step := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	_run()


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures.append(what)


## Waits `n` physics ticks (headless, drawn frames can come several to a tick).
func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func shot(name: String) -> void:
	# Headless runs (the default, see run_tests.sh) have nothing to capture.
	if DisplayServer.get_name() == "headless":
		return
	await frames(3)
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("game_%s.png" % name))


func aim(pitch: float, yaw := 0.0) -> void:
	game.player.look_at_yaw_pitch(yaw, pitch)
	await get_tree().physics_frame
	await get_tree().physics_frame


func use(times: int) -> void:
	for i in times:
		game.player._use_timer = 0.0
		game.player.use_item()
		await get_tree().physics_frame


func _run() -> void:
	game = Game.new()
	add_child(game)
	Settings.persist = false
	Settings.set_value("render_distance", 5)
	# Far terrain off for the older checks (the far-terrain check turns it on).
	Settings.set_value("far_distance", 0)
	# An island like the real sizes', smaller so it generates quickly.
	game.start({"mode": "new", "name": "TestWorld", "seed": 42, "path": "user://worlds/test_world.twld", "size": Vector3i(512, 256, 512)})
	while game.state != Game.State.PLAYING:
		await frames(1)
	var p := game.player
	# Random spawns would make the scripted checks flaky; enabled only for the spawner check.
	game.spawner.process_mode = Node.PROCESS_MODE_DISABLED
	await frames(30)
	check(p.on_floor or p.velocity.y <= 0.0, "player spawned on the ground")
	check(p.inventory.count_of("CopperPickaxe") == 1, "starting items given")
	# Plants take their styles (blocks.json variant_of): the grass round spawn
	# is many of tall grass's, all tall grass to everything else.
	var grass_styles := {}
	var sp := Vector3i(p.global_position.floor())
	for dx in range(-40, 41):
		for dz in range(-40, 41):
			for dy in range(-12, 13):
				var b := game.world.get_block(sp + Vector3i(dx, dy, dz))
				if b != 0 and Data.kind_of(b) == "tall_grass":
					grass_styles[b] = true
	check(grass_styles.size() >= 4 and Data.kind_of(Data.block_id("tall_grass_3")) == "tall_grass" and Data.block(Data.block_id("tall_grass_3")).get("sound") == Data.block(Data.block_id("tall_grass")).get("sound"),
			"the grass round spawn in its different styles, each still tall grass (%d)" % grass_styles.size())
	# At the beach the horizon's mountains and trees aren't drawn over the sea,
	# only over the land.
	var home := p.global_position
	var size := game.world.get_size()
	var bx := size.x / 2
	var bz := size.z / 2
	while bx < size.x - 1 and game.world.coast_inland(bx, bz) > game.ocean_width + game.beach_width + 6:
		bx += 1
	p.global_position = Vector3(bx + 0.5, game.world.surface_y(bx, bz) + 1, bz + 0.5)
	await frames(5)
	check(game.has_ocean and game.sky.sea_mask_at(0.0) < 0.1 and game.sky.sea_mask_at(PI) > 0.9,
			"at the beach, no backdrop over the sea (toward it %.2f, inland %.2f)" % [game.sky.sea_mask_at(0.0), game.sky.sea_mask_at(PI)])
	p.global_position = home
	await frames(5)
	var guide = game.town.residents.get("Guide")
	check(guide != null and guide.global_position.distance_to(p.global_position) < 12.0 and guide.home_key == "",
			"a new world starts with the Guide by the spawn point, homeless")
	var half_size := Vector3i(size.x / 2, size.y / 2, size.z / 2)
	# Herbs (Terraria's Herbs pass): sprouts of several kinds, each on its soil.
	var sprout_ids := PackedInt32Array()
	for h in Herbs.STYLES:
		sprout_ids.append(Data.block_id(h + "_sprout"))
	var sprouts := game.world.find_blocks(half_size, half_size, sprout_ids, 4000)
	var herb_kinds := {}
	var on_soil := true
	for i in range(0, sprouts.size(), 3):
		var at := Vector3i(sprouts[i], sprouts[i + 1], sprouts[i + 2])
		var hb := Data.block(game.world.get_block(at))
		herb_kinds[hb.herb] = true
		on_soil = on_soil and Data.block(game.world.get_block(at + Vector3i.DOWN)).get("name", "") in hb.grows_on
	check(sprouts.size() / 3 > 100 and herb_kinds.size() >= 5 and on_soil,
			"worldgen plants herbs on their soils (%d sprouts, %d kinds)" % [sprouts.size() / 3, herb_kinds.size()])
	# Bee hives in the Jungle (Terraria's Hives pass): each larva on a hive floor.
	var larvae := game.world.find_blocks(half_size, half_size, PackedInt32Array([Data.block_id("larva")]), 100)
	var on_hive := true
	for i in range(0, larvae.size(), 3):
		if game.world.get_block(Vector3i(larvae[i], larvae[i + 1] - 1, larvae[i + 2])) != Data.block_id("hive"):
			on_hive = false
	check(larvae.size() >= 3 and on_hive, "the world has bee hives in its Jungle, each larva on hive (%d)" % (larvae.size() / 3))
	# Grass block sides: their grass is the top's texture (several of its
	# colours across the band, not Terraria's flat edge colour), at square pixels.
	for name in ["grass", "jungle_grass", "corrupt_grass", "crimson_grass"]:
		var spec: Dictionary = {}
		for b in Data._read_json("res://data/blocks.json").blocks:
			if b.name == name:
				spec = b.tex.side.duplicate()
				spec["fill"] = b.tex.top
		var side := Data._cube_layer(spec, 0)
		var ramp: Array = spec.fill.recolor.map(func(h): return Color(h).to_rgba32())
		var band := {}
		for x in side.get_width():
			var c := side.get_pixel(x, 2)
			if c.to_rgba32() in ramp:
				band[c.to_rgba32()] = true
		check(band.size() >= 3, "%s side's grass uses the top's texture (%d of its colours in the band)" % [name, band.size()])
	# NPC sheets: the frame count splits each sheet between its sprites (a wrong
	# count cuts sprites in half: the sheet rows either side of a frame boundary
	# both hold pixels). Sheets with guide lines (trim_bottom) are skipped.
	var cut := []
	for kind in Data.npcs:
		var def: Dictionary = Data.npcs[kind]
		if def.has("trim_bottom"):
			continue
		var img := Assets.image(NPC.image_path(kind))
		var row_used := func(y: int) -> bool:
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.0:
					return true
			return false
		var fh := float(img.get_height()) / int(def.frames)
		for i in range(1, int(def.frames)):
			if row_used.call(int(i * fh)) and row_used.call(int(i * fh) - 1):
				cut.append(kind)
				break
	check(cut.is_empty(), "NPC frame counts match their sheets (cut: %s)" % [cut])
	await shot("spawn")
	# Viewmodel poses: shortsword mid-thrust and a gun held out.
	p.select(0)
	p.viewmodel.play("thrust", 1.0)
	await frames(30)
	await shot("thrust")
	p.inventory.slots[9] = Inventory.stack("FlintlockPistol", 1)
	p.select(9)
	await frames(5)
	await shot("hold")
	p.inventory.slots[9] = null
	await frames(240)
	print("PERF fps=%d draw_calls=%d" % [Engine.get_frames_per_second(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])

	# Settings: UI scale and key rebinding.
	Settings.set_value("ui_scale", 1.5)
	await frames(2)
	check(is_equal_approx(game.hud._root.scale.x, 1.5), "UI scale applied to the HUD")
	var vp := get_viewport().get_visible_rect().size
	check(game.hud._root.size.is_equal_approx(vp / 1.5), "scaled HUD still spans the screen")
	game.hud.toggle_pause()
	game.hud.open_options()
	await frames(5)
	check(game.hud._options != null and not game.hud._pause.visible, "options open from the pause menu")
	await shot("options_150")
	Settings.set_value("ui_scale", 2.0)
	await shot("options_200")
	game.hud._options.close()
	await frames(2)
	await shot("pause_200")
	check(game.hud._pause.visible, "closing options returns to the pause menu")
	game.hud.toggle_pause()
	Settings.set_value("ui_scale", 0.75)
	await shot("hud_75")
	Settings.set_value("ui_scale", 1.0)
	var j := InputEventKey.new()
	j.physical_keycode = KEY_J
	j.pressed = true
	Controls.rebind("jump", j)
	check(Controls.binding("jump") == {"key": KEY_J}, "jump rebound to the J key")
	var w := InputEventKey.new()
	w.physical_keycode = KEY_W
	w.pressed = true
	Controls.rebind("jump", w)
	check(Controls.binding("jump") == {"key": KEY_W} and Controls.binding("move_forward") == {"key": KEY_J}, "conflicting binding swapped")
	Controls.reset_defaults()
	check(Controls.binding("jump") == {"key": KEY_SPACE} and Controls.binding("move_forward") == {"key": KEY_W}, "bindings reset to defaults")
	print("  layout labels: forward=%s back=%s left=%s right=%s" % [Controls.label("move_forward"), Controls.label("move_back"), Controls.label("move_left"), Controls.label("move_right")])
	Input.action_press("move_forward")
	await frames(20)
	Input.action_release("move_forward")
	check(Vector2(p.velocity.x, p.velocity.z).length() > 1.0 or p.global_position.distance_to(Vector3(game.world.get_spawn())) > 0.5, "movement driven by input actions")

	# Dig straight down with the pickaxe (after the walk test has come to rest).
	await frames(45)
	p.global_position = Vector3(floor(p.global_position.x) + 0.5, p.global_position.y, floor(p.global_position.z) + 0.5)
	await frames(2)
	p.select(1)
	await aim(-1.5)
	var below: Vector3i = p.target.get("block", Vector3i(-1, -1, -1))
	var id := game.world.get_block(below)
	check(id != 0, "targeting the block underfoot (%s)" % Data.block(id).get("name"))
	await use(12)
	check(game.world.get_block(below) == 0 or Data.block(game.world.get_block(below)).is_empty(), "block was mined")
	await frames(60)
	var drop := Data.block_drop(id)
	check(drop == "" or p.inventory.count_of(drop) > 0, "mined block was picked up (%s)" % drop)

	# Climb out of the hole, then build: place a dirt block in front.
	p.global_position = Vector3(game.world.get_spawn()) + Vector3(3.5, 0, 0.5)
	p.global_position.y = game.world.surface_y(int(p.global_position.x), int(p.global_position.z)) + 1.0
	await frames(10)
	p.inventory.add("DirtBlock", 10)
	var slot := -1
	for i in 10:
		var s = p.inventory.slots[i]
		if s != null and s.item == "DirtBlock":
			slot = i
	if slot < 0:
		p.inventory.slots[5] = Inventory.stack("DirtBlock", 10)
		slot = 5
	p.select(slot)
	# (A critter where it goes would stop it, as in Terraria.)
	for n in game.npcs():
		if n.is_critter():
			n.queue_free()
	await aim(-0.6)
	# (Nor anyone else: the Guide or a slime wandering into the spot.)
	var place_at: Vector3i = p.target.get("block", Vector3i(-1, -1, -1)) + p.target.get("normal", Vector3i.ZERO)
	for n in game.npcs():
		if n.overlaps_box(Vector3(place_at) + Vector3(0.5, 0, 0.5), Vector3(0.5, 1.0, 0.5)):
			n.global_position += Vector3(8, 0, 8)
	var before := p.inventory.count_of("DirtBlock")
	await use(1)
	var aimed: Dictionary = p.target
	var at: Vector3i = aimed.get("block", Vector3i(-1, -1, -1)) + aimed.get("normal", Vector3i.ZERO)
	check(p.inventory.count_of("DirtBlock") == before - 1, "placed a block (aimed at %s, the spot holds %s, an NPC there: %s)"
			% [Data.block(game.world.get_block(aimed.get("block", Vector3i(-1, -1, -1)))).get("name", "?"), Data.block(game.world.get_block(at)).get("name", "air"), game.any_npc_in_block(at)])

	# Crafting: wood -> work bench (by hand).
	p.inventory.add("Wood", 30)
	p.inventory.add("Gel", 5)
	game.hud.toggle_inventory()
	await frames(5)
	var bench_recipe := {}
	for r in Data.recipes:
		if r.result == "WorkBench":
			bench_recipe = r
	game.hud.craft(bench_recipe)
	check(game.hud._cursor_stack != null and game.hud._cursor_stack.item == "WorkBench", "crafted a work bench onto the cursor")
	await shot("inventory")
	game.hud.close_inventory()
	check(p.inventory.count_of("WorkBench") == 1, "cursor item returned to inventory on close")

	# Combat: spawn a slime in front and stab it.
	p.select(0)
	await aim(-0.2)
	var slime := game.spawn_npc("BlueSlime", p.global_position + p.forward() * 1.6)
	await frames(2)
	var life := slime.life
	await use(1)
	check(slime.life < life, "shortsword damaged the slime (%d -> %d)" % [life, slime.life])
	for i in 30:
		if not is_instance_valid(slime):
			break
		slime.global_position = p.global_position + p.forward() * 1.4
		await use(1)
		await frames(12)
	check(not is_instance_valid(slime), "slime died")
	await frames(150)
	check(p.inventory.count_of("Gel") > 5, "slime dropped gel that was picked up")

	# Spears: Terraria's reach (Spear: 5.05 blocks out, 2.5 back; Storm Spear:
	# 6.74), a slime 4 blocks off is hit, and the Storm Spear throws its bolt.
	p.inventory.add("Spear", 1)
	p.select(p.inventory.slots.find(p.inventory.slots.filter(func(s): return s != null and s.item == "Spear")[0]))
	await aim(-0.1)
	var cam0 := p.camera.global_position
	for d in range(1, 6):
		for up in [0.0, -0.5, 0.5]:
			game.world.set_block(Vector3i((cam0 + p.forward() * d + Vector3(0, up, 0)).floor()), 0)
	var far_slime := game.spawn_npc("BlueSlime", cam0 + p.forward() * 4.0 - Vector3(0, 0.3, 0))
	far_slime.process_mode = Node.PROCESS_MODE_DISABLED
	await frames(2)
	var far_life := far_slime.life
	await use(1)
	check(p.spear_thrusting(), "a spear is thrust")
	check(absf(p.spear.reach_at(21.0 / 60.0) - 80.845 / 16.0) < 0.02 and absf(p.spear.reach_at(31.0 / 60.0) - 40.145 / 16.0) < 0.02,
			"the Spear reaches as far as Terraria's (%.2f, then %.2f)" % [p.spear.reach_at(21.0 / 60.0), p.spear.reach_at(31.0 / 60.0)])
	await frames(40)
	check(far_slime.life < far_life, "speared a slime 4 blocks off (%d -> %d)" % [far_life, far_slime.life])
	check(not p.spear_thrusting() and p.spear_out(), "the thrust ends, the spear still in your hand (thrusting %s, out %s, time %s)" % [p.spear_thrusting(), p.spear_out(), game.sky.time])
	far_slime.queue_free()
	p.inventory.add("ThunderSpear", 1)
	p.select(p.inventory.slots.find(p.inventory.slots.filter(func(s): return s != null and s.item == "ThunderSpear")[0]))
	await frames(2)
	var bolts := func(): return game.entities.get_children().filter(func(n): return n is Projectile and not n.is_queued_for_deletion()).size()
	var before_bolts: int = bolts.call()
	await use(1)
	await get_tree().physics_frame
	check(bolts.call() == before_bolts + 1 and absf(p.spear.reach_at(19.0 / 60.0) - 6.7375) < 0.02,
			"the Storm Spear reaches 6.74 blocks and throws a bolt (%.2f; projectiles %d -> %d)" % [p.spear.reach_at(19.0 / 60.0), before_bolts, bolts.call()])
	await frames(40)
	p.select(0)
	await frames(2)
	check(not p.spear_out(), "putting the spear away takes it out of the world")

	# Boomerangs: out for Terraria's 30 ticks, back to be caught, one at a time
	# (three Trimarangs); the craftable ones have Terraria's recipes.
	p.inventory.add("WoodenBoomerang", 1)
	p.select(p.inventory.slots.find(p.inventory.slots.filter(func(s): return s != null and s.item == "WoodenBoomerang")[0]))
	await aim(0.3)
	await use(1)
	check(p.boomerangs_out(Data.item("WoodenBoomerang")) == 1, "a boomerang is thrown")
	var boom: Boomerang = p.boomerangs.back()
	await use(1)
	check(p.boomerangs_out(Data.item("WoodenBoomerang")) == 1, "only one at a time")
	var turned := -1
	for i in 240:
		await get_tree().physics_frame
		if not is_instance_valid(boom) or boom.is_queued_for_deletion():
			break
		if boom.returning and turned < 0:
			turned = boom.ticks
	check(turned > 0 and turned <= 30, "it turns round by Terraria's 30 ticks (%d)" % turned)
	check(not is_instance_valid(boom) or boom.is_queued_for_deletion(), "and comes back to be caught")
	var made := {}
	for r in Data.recipes:
		if r.result in ["ThornChakram", "Flamarang", "Trimarang"]:
			made[r.result] = r.ingredients
	check(made.get("ThornChakram", {}).get("JungleSpores") == 6 and made.get("ThornChakram", {}).get("Stinger") == 9
			and made.get("Flamarang", {}).get("HellstoneBar") == 10 and made.has("Trimarang"),
			"Thorn Chakram, Flamarang and Trimarang have Terraria's recipes (%s)" % made)
	p.select(0)

	# The sky fades through the day: no jumps, not even as day turns to night.
	var worst := 0.0
	var worst_at := 0.0
	var prev := SkySystem.sky_at(0.0)
	for step in range(1, 24 * 60 + 1):
		var now := SkySystem.sky_at(step / 60.0)
		var jump := absf(now.light - prev.light) * 3.0
		for key in ["top", "horizon", "tint", "glow_color", "halo_color"]:
			var c0: Color = prev[key]
			var c1: Color = now[key]
			jump = maxf(jump, absf(c1.r - c0.r) + absf(c1.g - c0.g) + absf(c1.b - c0.b))
		jump = maxf(jump, maxf(absf(now.glow - prev.glow), absf(now.stars - prev.stars)))
		if jump > worst:
			worst = jump
			worst_at = step / 60.0
		prev = now
	check(worst < 0.05, "the sky changes smoothly minute by minute through the day (largest step %.3f at %.2f h)" % [worst, worst_at])
	var dusk_was: Array = [game.sky.is_day, game.sky.time]
	game.sky.is_day = true
	game.sky.time = SkySystem.DAY_LENGTH - 1.0
	var before_night := SkySystem.sky_at(game.sky.hours())
	game.sky.is_day = false
	game.sky.time = 0.0
	var after_dusk := SkySystem.sky_at(game.sky.hours())
	check(absf(before_night.light - after_dusk.light) < 0.001 and (before_night.top as Color).is_equal_approx(after_dusk.top),
			"the last moment of day and the first of night look the same (%.3f / %.3f)" % [before_night.light, after_dusk.light])
	check(SkySystem.sky_at(12.0).light == 1.0 and SkySystem.sky_at(0.0).light < 0.25 and SkySystem.sky_at(6.0).light > 0.5 and SkySystem.sky_at(6.0).light < 0.9,
			"full light at noon, dark at midnight, half-way through the morning fade at 6 AM")
	game.sky.is_day = dusk_was[0]
	game.sky.time = dusk_was[1]

	# Fallen Stars: Terraria's rate, a lucky star lands near you as a Fallen
	# Star, which fades at sunrise; Mana Crystals take 5.
	var was_day: bool = game.sky.is_day
	var was_time: float = game.sky.time
	game.starfall.boost = 1.0
	check(absf(game.starfall.chance() / game.starfall.world_scale() - 10.0 / 8000.0) < 1e-9, "stars fall at Terraria's rate")
	# Early night (a day's time past the night's length would roll straight
	# over to morning).
	game.sky.is_day = false
	game.sky.time = 0.0
	game.starfall.process_mode = Node.PROCESS_MODE_DISABLED
	for n in game.entities.get_children():
		if n is FallingStar:
			n.free()  # any already on their way
	# (A lucky star drifts your way: it may land close enough to be picked up.)
	var lying_before := game.entities.get_children().filter(func(n): return n is ItemDrop and n.item == "FallenStar").size() + p.inventory.count_of("FallenStar")
	# (Straight down onto the ground beside you: a random one may drift off
	# the edge of this small island.)
	var star := FallingStar.new()
	var drop_at := Vector3i(p.global_position.floor()) + Vector3i(3, 0, 0)
	star.velocity = Vector3.DOWN * Starfall.STAR_SPEED
	star.delay = 0.0
	game.entities.add_child(star)
	star.global_position = Vector3(drop_at.x + 0.5, game.world.surface_y(drop_at.x, drop_at.z) + 40.0, drop_at.z + 0.5)
	for i in 900:
		await get_tree().physics_frame
		if not is_instance_valid(star):
			break
	await frames(5)
	var lying := game.entities.get_children().filter(func(n): return n is ItemDrop and n.item == "FallenStar")
	var stars_now := lying.size() + p.inventory.count_of("FallenStar")
	check(not is_instance_valid(star) and stars_now == lying_before + 1, "a falling star lands as a Fallen Star (%d -> %d)" % [lying_before, stars_now])
	game.sky.is_day = true
	await frames(3)
	check(game.entities.get_children().filter(func(n): return n is ItemDrop and n.item == "FallenStar" and not n.is_queued_for_deletion()).is_empty(),
			"it fades at sunrise")
	game.sky.is_day = was_day
	game.sky.time = was_time
	game.starfall.process_mode = Node.PROCESS_MODE_INHERIT

	# Meteorites (Meteors): beating the Eater of Worlds or the Brain of
	# Cthulhu sends one for sure the first time, then 1 time in 2; every dusk
	# 1 in 50 once either is beaten; it lands at midnight, out of sight and away
	# from spawn, as a crater of Meteorite with a bowl in it.
	var met := game.meteors
	var ore := Data.block_id("meteorite")
	check(ore > 0 and int(Data.block(ore).get("min_pick", 0)) == 50 and Data.item("Meteorite").get("place") == "meteorite",
			"Meteorite: a block that takes a pickaxe of 50 power, mined as the Meteorite item")
	var bar := Data.recipes.filter(func(r): return r.result == "MeteoriteBar")
	check(not bar.is_empty() and bar[0].ingredients.get("Meteorite") == 3 and bar[0].get("station") == "furnace",
			"a Meteorite Bar takes 3 Meteorite at a furnace")
	var bosses_was := game.defeated_bosses.duplicate()
	met.pending = false
	met.boss_beaten(false)
	check(met.pending, "the first Eater of Worlds or Brain of Cthulhu win always sends a meteorite")
	var sent := 0
	for i in 400:
		met.pending = false
		met.boss_beaten(true)
		sent += int(met.pending)
	check(sent > 150 and sent < 250, "later wins send one 1 time in 2 (%d of 400)" % sent)
	game.defeated_bosses.erase("EaterofWorldsHead")
	game.defeated_bosses.erase("BrainofCthulhu")
	sent = 0
	for i in 2000:
		met.pending = false
		met.dusk()
		sent += int(met.pending)
	check(sent == 0, "no nightly meteorites before either is beaten")
	game.defeated_bosses["BrainofCthulhu"] = true
	for i in 5000:
		met.pending = false
		met.dusk()
		sent += int(met.pending)
	check(sent > 50 and sent < 160, "after, 1 dusk in 50 (%d of 5000)" % sent)
	# Past midnight it starts down, a few spots a frame.
	met.pending = true
	game.sky.is_day = false
	game.sky.time = Meteors.MIDNIGHT - 100.0
	met.update(0.016)
	check(met.pending and met._drop.is_empty(), "before midnight it waits")
	game.sky.time = Meteors.MIDNIGHT + 1.0
	met.update(0.016)
	check(not met.pending and not met._drop.is_empty(), "at midnight it's on its way")
	met._drop = {}
	# Out of sight: what's drawn here, cut down so the island has room for it.
	Settings.set_value("render_distance", 2)
	var landed := met.drop_now()
	var spawn_at := game.world.get_spawn()
	var counts := game.world.count_blocks(landed, 16) if landed != Meteors.NO_SPOT else PackedInt32Array()
	var landed_ore := counts[ore] if counts.size() > ore else 0
	check(landed != Meteors.NO_SPOT and Vector2(landed.x - p.global_position.x, landed.z - p.global_position.z).length() > 64.0
			and Vector2(landed.x - spawn_at.x, landed.z - spawn_at.z).length() >= Meteors.SPAWN_CLEAR * size.x,
			"a meteorite lands out of sight and away from the spawn point (%s)" % landed)
	check(landed_ore > 200 and landed_ore < 2000, "its crater holds a few hundred Meteorite (%d)" % landed_ore)
	var under := range(2, 10).any(func(k): return game.world.get_block(landed + Vector3i.DOWN * k) == ore)
	check(landed != Meteors.NO_SPOT and game.world.get_block(landed) == 0 and under, "a bowl hollowed out of its top, Meteorite under it")
	await shot("meteorite")
	# Past Terraria's cap of Meteorite about (scaled: ~450 on this world) no
	# more land: while that crater's still there, the next one doesn't.
	check(met.drop_now() == Meteors.NO_SPOT, "no meteorite while there's too much Meteorite about")
	Settings.set_value("render_distance", 5)
	game.defeated_bosses = bosses_was
	game.sky.is_day = was_day
	game.sky.time = was_time
	# Optional sun shadows (Settings → Shaders): off by default, no light; on,
	# a shadowed directional light along the sun, the shaders told, with the
	# blocks and models casting; voxel models' faces carry UVs for the
	# per-voxel look-up.
	var ss := game.sun_shadows
	Settings.set_value("shadows", false)
	await frames(2)
	check(not bool(Settings.DEFAULTS.shadows) and ss._light == null and not ss.active,
			"sun shadows are off by default, and off there's no light (no shadow pass)")
	Settings.set_value("shadows", true)
	Settings.set_value("shadow_distance", 96.0)
	await frames(2)
	var sl := ss._light
	var chunk_casts := game.renderer._chunks.values().any(func(m): return m != null and m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	check(sl != null and sl.shadow_enabled and is_equal_approx(sl.directional_shadow_max_distance, 96.0) and ss.active
			and (-sl.global_basis.z).dot(-game.sky.sun_direction()) > 0.99999 - SunShadows.SUN_STEP and chunk_casts,
			"turned on: a shadowed light shining from the sun, the shaders told, the terrain casting (%s, %s, %s)"
			% [sl != null, ss.active, chunk_casts])
	var texels: Image = Data.layer_texels.get_image()
	var grass := int(Data.block(Data.block_id("grass")).tex_top)
	check(is_equal_approx(texels.get_pixel(grass % Data.LAYER_TEXELS_WIDTH, grass / Data.LAYER_TEXELS_WIDTH).r, 16.0),
			"looked up per art pixel: a grass top is 16 art pixels across (%.1f)" % texels.get_pixel(grass % Data.LAYER_TEXELS_WIDTH, grass / Data.LAYER_TEXELS_WIDTH).r)
	var voxel_arrays: Array = BlockModelMesh.voxel_arrays({Vector3i(0, 0, 0): Color.RED}, Image.create(1, 1, false, Image.FORMAT_RGBA8), 0.1)
	var uvs: PackedVector2Array = voxel_arrays[Mesh.ARRAY_TEX_UV]
	check(uvs.size() == 36 and uvs[0] == Vector2(0, 0) and uvs[2] == Vector2(1, 1), "a voxel model's faces carry 0-1 UVs (for the shadow's per-voxel look-up)")
	Settings.set_value("shadows", false)
	await frames(2)
	check(not is_instance_valid(sl) or sl.is_queued_for_deletion(), "turned off again, the light is gone")
	check(not ss.active, "and the shaders draw as before")
	Settings.set_value("shadow_distance", 64.0)
	# Optional global illumination: off by default; the environment's ambient
	# black either way; each mode turns on Godot's SDFGI and/or SSIL and tells
	# the shaders; the shadows' light then carries the sky's sunlight to it.
	var gi := game.global_illumination
	var env: Environment = game.sky.env
	# (Your own settings may have it on: off, as the defaults have it.)
	Settings.set_value("gi", Settings.DEFAULTS.gi)
	await frames(1)
	check(int(Settings.DEFAULTS.gi) == GlobalIllumination.OFF and not env.sdfgi_enabled and not env.ssil_enabled
			and env.ambient_light_energy == 0.0 and env.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED,
			"global illumination is off by default, the environment adding no light of its own (%s)"
			% [[Settings.DEFAULTS.gi, env.sdfgi_enabled, env.ssil_enabled, env.ambient_light_energy, env.ambient_light_source, env.reflected_light_source]])
	var modes := []
	for m in [GlobalIllumination.SSIL, GlobalIllumination.SDFGI, GlobalIllumination.BOTH]:
		Settings.set_value("gi", m)
		await frames(1)
		modes.append([env.ssil_enabled, env.sdfgi_enabled, gi.mode != GlobalIllumination.OFF])
	check(modes == [[true, false, true], [false, true, true], [true, true, true]], "its modes: screen space, SDFGI, both (%s)" % [modes])
	Settings.set_value("shadows", true)
	Settings.set_value("gi_strength", 1.5)
	await frames(2)
	var gl := ss._light
	check(gl != null and gl.light_color == game.sky.sky_tint and is_equal_approx(gl.light_indirect_energy, game.sky.sky_light)
			and is_equal_approx(env.sdfgi_energy, 1.5) and is_equal_approx(env.ssil_intensity, 1.5),
			"with shadows, their light carries the sky's sunlight into the GI; the strength sets both")
	Settings.set_value("shadows", false)
	Settings.set_value("gi", GlobalIllumination.OFF)
	Settings.set_value("gi_strength", 1.0)
	await frames(2)
	check(not env.sdfgi_enabled and not env.ssil_enabled and gi.mode == GlobalIllumination.OFF, "turned off again")
	# Far terrain (LOD): every chunk column within the far view is drawn once,
	# by the full-detail chunks or exactly one far tile, and the tiles load.
	var lod := game.lod
	Settings.set_value("far_distance", 32)
	await frames(5)
	var counts := game.world.get_chunk_count()
	var fc := Vector2i(game.renderer._focus_chunk.x, game.renderer._focus_chunk.z)
	var once := true
	var near_n := 0
	for cx in counts.x:
		for cz in counts.z:
			var n := 1 if lod.is_near(cx, cz, fc) else 0
			near_n += n
			for t in lod._wanted:
				if LodRenderer._bounds(t).has_point(Vector2i(cx, cz)):
					n += 1
			var far_enough := Vector2(cx - fc.x, cz - fc.y).length() > lod.far_distance + 8
			if n != 1 and not (n == 0 and far_enough):
				once = false
	check(once and near_n > 0 and lod.wanted_count() > 0, "every column is drawn once: near (%d) or by one far tile (%d)" % [near_n, lod.wanted_count()])
	var t_lod := Time.get_ticks_msec()
	while lod.tile_count() < lod.wanted_count() and Time.get_ticks_msec() - t_lod < 20000:
		await frames(5)
	check(lod.tile_count() >= lod.wanted_count(), "the far tiles load (%d of %d)" % [lod.tile_count(), lod.wanted_count()])
	# Trees' level of detail: canopies near you in full detail, farther ones
	# as sprites; trees out past the full-detail chunks get trunk sprites.
	await frames(10)
	var tiers: Vector2i = game.decorations.tier_counts()
	check(tiers.x > 0 and tiers.y > 0, "canopies near you in full detail (%d), farther ones as sprites (%d)" % [tiers.x, tiers.y])
	check(game.far_trees.count() > 0, "trees past the full-detail chunks have trunk sprites (%d)" % game.far_trees.count())
	# Rendered canopies: billboards until their style's shots are made (never,
	# headless), then the shots, with each tree's turn only (the canopy's
	# transform is in the shots).
	var canopy_methods := {}
	for st in CanopyArt.STYLE_IDS:
		var cn := CanopyArt.block_name(st)
		canopy_methods[cn] = Data.block(Data.block_id(cn)).method
		Data.set_block_method(cn, "rendered")
	var deco := Decorations.new()
	game.add_child(deco)
	deco.setup(game.world)
	var style: int = deco._instances.keys()[0] if not deco._instances.is_empty() else -1
	var style_id := Data.block_id(CanopyArt.block_name(style)) if style >= 0 else 0
	check(style >= 0 and deco._waiting.has(style) and deco._rendered.is_empty()
			and deco._instances[style].multimesh.mesh == BlockModelMesh.build(style_id, "billboard").mesh,
			"rendered canopies are billboards while their shots are being made")
	var fake := {"n": 8, "px": 0.1, "center": Vector3(0, 0.4, 0), "radius": 0.5, "yaws": 16, "pitches": [0.0],
			"atlases": [ImageTexture.create_from_image(Image.create(128, 8, false, Image.FORMAT_RGBA8))]}
	for st in deco._waiting:
		PlaceableRenders._done[deco._waiting[st]] = fake
	await frames(2)
	var first: Dictionary = deco._all[style][0]
	var shown: Transform3D = deco.near_transform(style, first)
	check(deco._waiting.is_empty() and deco._rendered.has(style) and deco._instances[style].multimesh.mesh == BlockModels.rendered_quad()
			and (shown.basis.x - first.turn.x).length() < 0.001 and (shown.basis.z - first.turn.z).length() < 0.001
			and shown.origin.distance_to(first.pos) < 0.001,
			"once made they show the shots, turned each tree's way (the canopy's transform is in the shots)")
	for st in deco._rendered:
		PlaceableRenders._done.erase(Data.block_id(CanopyArt.block_name(st)))
	deco.queue_free()
	for cn in canopy_methods:
		Data.set_block_method(cn, canopy_methods[cn])
	var crystal := Data.recipes.filter(func(r): return r.result == "ManaCrystal")
	check(not crystal.is_empty() and crystal[0].ingredients.get("FallenStar") == 5, "a Mana Crystal takes 5 Fallen Stars")

	# Chests: place one, store an item, reopen.
	var cpos := Vector3i(p.global_position.floor()) + Vector3i(2, 0, 0)
	game.world.set_block(cpos, Data.block_id("chest"))
	game.chests.register_new(cpos)
	game.open_chest(cpos)
	game.chests.get_inventory(cpos).add("Torch", 7)
	game.hud.close_inventory()
	check(game.chests.get_inventory(cpos).count_of("Torch") == 7, "chest keeps its contents")
	game.break_block(cpos)
	check(game.world.get_block(cpos) != 0, "a non-empty chest can't be broken")

	# Liquids. Clear stray enemies, then dig a sealed pit next to the player.
	for npc in game.npcs():
		npc.queue_free()
	var lw := game.world
	var pit := Vector3i(p.global_position.floor()) + Vector3i(5, -1, 0)
	# Stone shell (walls up to the rim, floor below), hollow inside: a sealed basin.
	var stone := Data.block_id("stone")
	for x in range(-1, 4):
		for y in range(-4, 1):
			for z in range(-1, 4):
				var inside := x >= 0 and x < 3 and z >= 0 and z < 3 and y > -4
				lw.set_block(pit + Vector3i(x, y, z), 0 if inside else stone)
	for x in range(-1, 4):
		for z in range(-1, 4):
			for y in range(1, 30):
				lw.set_block(pit + Vector3i(x, y, z), 0)  # clear the drop above
	p.global_position = Vector3(pit) + Vector3(1.5, 1.0, 1.5)
	p.velocity = Vector3.ZERO
	await frames(20)
	p.inventory.slots[8] = Inventory.stack("WaterBucket", 1)
	p.select(8)
	await aim(-1.5)
	await frames(5)
	var poured: Vector3i = p.target.get("block", Vector3i.ZERO) + p.target.get("normal", Vector3i.ZERO)
	await use(1)
	check(lw.get_liquid(poured).x == 1, "water bucket poured water (%s)" % [lw.get_liquid(poured)])
	check(p.inventory.slots[8] != null and p.inventory.slots[8].item == "EmptyBucket", "bucket is empty afterwards")
	await use(1)
	var left := 0
	for x in 3:
		for z in 3:
			left += lw.get_liquid(pit + Vector3i(x, -3, z)).y
	check(p.inventory.slots[8].item == "WaterBucket" and left <= 4, "empty bucket scooped the spread-out water back up (%d left)" % left)
	p.inventory.slots[8] = null

	# Fill the pit and jump in from high up: water breaks the fall.
	for x in 3:
		for y in range(1, 4):
			for z in 3:
				lw.set_liquid(pit + Vector3i(x, -y, z), 1, 63)
	var life_before := p.life
	p.global_position = Vector3(pit) + Vector3(1.5, 22.0, 1.5)
	p.velocity = Vector3.ZERO
	p._fall_start = p.global_position.y
	for i in 240:
		await get_tree().physics_frame
		if p.in_liquid == 1 and p.on_floor:
			break
	check(p.in_liquid == 1, "player is in the water")
	check(p.life >= life_before, "a long fall into water does no damage (%d -> %d)" % [life_before, p.life])
	await frames(10)
	check(p.head_liquid == 1, "head is underwater at the bottom of the pit")
	var air := p.breath
	await get_tree().create_timer(1.0).timeout
	check(p.breath < air, "breath runs down underwater (%.1f -> %.1f)" % [air, p.breath])
	await frames(5)
	await shot("underwater")
	p.global_position = Vector3(pit) + Vector3(1.5, 1.2, 4.5)
	await frames(30)
	check(p.in_liquid == 0 and p.breath > air - 1.5, "breath recovers out of the water")

	# Lava burns, sets the player on fire and destroys dropped items.
	var lava_cell := Vector3i(p.global_position.floor())
	p.life = p.life_max
	p._immune = 0.0
	life_before = p.life
	lw.set_liquid(lava_cell, 2, 63)
	await frames(6)
	check(p.life < life_before and p.on_fire > 0.0, "lava burns and sets the player On Fire! (%d -> %d)" % [life_before, p.life])
	check(p.buffs().any(func(b): return b[0] == 24), "On Fire! shows as a buff")
	game.spawn_item("Wood", 3, Vector3(lava_cell) + Vector3(0.5, 0.4, 0.5), Vector3(0, -1, 0), 99.0)
	await frames(10)
	var wood_left := game.entities.get_children().filter(func(e): return e is ItemDrop and e.item == "Wood" and e.global_position.distance_to(Vector3(lava_cell)) < 2.0)
	check(wood_left.is_empty(), "items burn up in lava")
	# Water next to lava hardens it into obsidian. Use an enclosed 2-cell trough
	# so the lava can't thin out by spreading before the water reaches it.
	var trough := Vector3i(p.global_position.floor()) + Vector3i(-4, 6, -4)
	for dx in range(-1, 3):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				lw.set_block(trough + Vector3i(dx, dy, dz), Data.block_id("stone"))
	lw.set_block(trough, 0)
	lw.set_block(trough + Vector3i(1, 0, 0), 0)
	lw.set_liquid(trough, 2, 63)
	lw.set_liquid(trough + Vector3i(1, 0, 0), 1, 63)
	for i in 10:
		lw.step_liquids(10000)
	var obsidian_found: bool = Data.block(lw.get_block(trough)).get("name") == "obsidian"
	check(obsidian_found, "water turned the lava into obsidian")
	p.on_fire = 0.0
	p.global_position = Vector3(lava_cell) + Vector3(0.5, 2.0, -2.5)
	await frames(5)
	p.life = p.life_max
	var liquid_cell := pit + Vector3i(0, -3, 0)

	# Decorative waterfall: a spring on a wall pours down to the ground and
	# re-measures when something is built underneath.
	var wbase := Vector3i(p.global_position.floor()) + Vector3i(-8, 0, -8)
	for x in range(-1, 2):
		for y in range(-1, 9):
			lw.set_block(wbase + Vector3i(x, y, 0), Data.block_id("stone"))
			for z in range(1, 3):
				if y >= 0:
					lw.set_block(wbase + Vector3i(x, y, z), 0)
	var mouth := wbase + Vector3i(0, 7, 1)
	game.waterfalls.add_fall(mouth, 1, 2)
	await get_tree().create_timer(0.8).timeout
	var full := game.waterfalls.stream_length(mouth)
	check(full > 6.0, "spring pours a stream down the wall (%.1f m)" % full)
	lw.set_block(mouth + Vector3i(0, -4, 0), Data.block_id("stone"))
	await get_tree().create_timer(0.8).timeout
	var short := game.waterfalls.stream_length(mouth)
	check(short > 0.5 and short < full - 2.0, "stream stops on a block placed under it (%.1f m)" % short)
	lw.set_block(wbase + Vector3i(0, 7, 0), 0)
	await get_tree().create_timer(0.8).timeout
	check(game.waterfalls.stream_length(mouth) == 0.0, "stream vanishes when its spring wall is dug out")

	# Hammer-made springs: a sealed one-cell tank of water high up; hammering the
	# tank's front block opens a waterfall that runs only while the water is there.
	var tank := Vector3i(p.global_position.floor()) + Vector3i(6, 9, -6)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				lw.set_block(tank + Vector3i(dx, dy, dz), Data.block_id("stone"))
	lw.set_block(tank, 0)
	var front := tank + Vector3i(0, 0, 1)
	for dy in range(-12, 2):
		lw.set_block(front + Vector3i(0, dy, 1), 0)  # open air in front, all the way down
	p.inventory.slots[7] = Inventory.stack("CopperHammer", 1)
	p.select(7)
	p.target = {"block": front, "normal": Vector3i(0, 0, 1), "id": lw.get_block(front), "distance": 2.0}
	p._hammer()
	var spring := front + Vector3i(0, 0, 1)
	check(not game.waterfalls.has_fall(spring, 2), "no spring without liquid behind the block")
	lw.set_liquid(tank, 1, 63)
	p.target = {"block": front, "normal": Vector3i(0, 0, 1), "id": lw.get_block(front), "distance": 2.0}
	p._hammer()
	check(game.waterfalls.has_fall(spring, 2), "hammering a block with water behind it makes a spring")
	await get_tree().create_timer(0.8).timeout
	check(game.waterfalls.stream_length(spring) > 4.0, "the spring pours down (%.1f m)" % game.waterfalls.stream_length(spring))
	lw.set_liquid(tank, 0, 0)
	await get_tree().create_timer(0.8).timeout
	check(game.waterfalls.stream_length(spring) == 0.0, "draining the tank stops it")
	lw.set_liquid(tank, 1, 63)
	await get_tree().create_timer(0.8).timeout
	check(game.waterfalls.stream_length(spring) > 4.0, "refilling starts it again")
	p.target = {"block": front, "normal": Vector3i(0, 0, 1), "id": lw.get_block(front), "distance": 2.0}
	p._hammer()
	check(not game.waterfalls.has_fall(spring, 2), "hammering again closes the spring")
	lw.set_liquid(tank, 2, 63)
	p.target = {"block": front, "normal": Vector3i(0, 0, 1), "id": lw.get_block(front), "distance": 2.0}
	p._hammer()
	check(game.waterfalls.has_fall(spring, 2) and game.waterfalls._falls.any(func(f): return f.pos == spring and f.type == 2), "lava behind makes a lavafall")
	game.break_block(front)
	check(not game.waterfalls.has_fall(spring, 2), "breaking the block removes its spring")
	lw.set_liquid(tank, 0, 0)

	# Night, torches and the Eye of Cthulhu. (No stars falling: one does 1000
	# damage, which would end the Eye's second phase early.)
	game.sky.is_day = false
	game.sky.time = 9000.0
	game.starfall.process_mode = Node.PROCESS_MODE_DISABLED
	for n in game.entities.get_children():
		if n is FallingStar:
			n.free()
	p.inventory.add("Torch", 5)
	game.world.set_block(Vector3i(p.global_position.floor()) + Vector3i(0, 0, -2), Data.block_id("torch"))
	p.inventory.slots[9] = Inventory.stack("SuspiciousLookingEye", 1)
	p.select(9)
	await use(1)
	await frames(5)
	check(game.boss_alive(), "Suspicious Looking Eye summoned the Eye of Cthulhu")
	var eoc := game.boss()
	if eoc:
		eoc.global_position = p.global_position + Vector3(0, 6, -9)
		p._immune = 999.0
		await aim(0.35, 0.0)
		await frames(40)
		var to_p: Vector3 = (p.center() - eoc.center()).normalized()
		check(eoc.look_dir.length() > 0.0 and (eoc.ai_state != 0 or eoc.look_dir.normalized().dot(to_p) > 0.9),
				"the Eye tells a 3D model where to look: at you while it hovers (state %d)" % eoc.ai_state)
		check(eoc.turn_rate >= 0.0, "and it turns there at Terraria's rate, not at once (%.2f rad/s)" % eoc.turn_rate)
		await shot("boss")
		eoc.hit(2000, 0.0, Vector3.FORWARD, 0.0)  # no crit: must leave it in phase 2
		await frames(150)
		check(is_instance_valid(eoc) and (eoc.ai_state >= 10 or eoc.ai_state == 5), "boss entered its second phase (state %d)" % (eoc.ai_state if is_instance_valid(eoc) else -1))
		await shot("boss_phase2")
		if is_instance_valid(eoc):
			eoc.hit(5000, 0.0, Vector3.FORWARD)
		await frames(5)
		check(game.defeated_bosses.has("EyeofCthulhu"), "boss defeat recorded")
		await frames(5)
		var demonite := p.inventory.count_of("DemoniteOre")
		for e in game.entities.get_children():
			if e is ItemDrop and e.item == "DemoniteOre":
				demonite += e.count
		check(demonite >= 30, "boss dropped Demonite Ore (%d)" % demonite)
	game.starfall.process_mode = Node.PROCESS_MODE_INHERIT

	# Spawner gets some enemies going at night.
	game.spawner.process_mode = Node.PROCESS_MODE_INHERIT
	game.sky.time = 15000.0
	await frames(600)
	check(game.npcs().size() > 0, "spawner produced enemies at night (%d)" % game.npcs().size())
	await shot("night")
	game.spawner.process_mode = Node.PROCESS_MODE_DISABLED
	for n in game.npcs():
		n.queue_free()

	# The ocean on every side: swimming in the sea is the ocean biome, with its
	# music; sharks chase swimmers, jellyfish drift, crabs walk the beach.
	var lw2 := game.world
	var layers2 := lw2.get_layers()
	check(game.has_ocean and game.underworld_level == int(layers2.underworld_top) and game.sea_level == int(layers2.sea_level),
			"new worlds have an ocean; levels come from the generator (underworld %d, sea %d)" % [game.underworld_level, game.sea_level])
	var sea_cell := Vector3i(6, game.sea_level, 256)
	check(lw2.get_liquid(sea_cell).x == 1 and lw2.get_liquid(Vector3i(256, game.sea_level, 6)).x == 1, "the sea reaches the world's edges")
	var land_pos := p.global_position
	check(game.detect_biome(land_pos) != "ocean", "inland is not the ocean")
	p.flying = false
	p.global_position = Vector3(6.5, game.sea_level - 1.5, 256.5)
	p.velocity = Vector3.ZERO
	await frames(45)
	check(p.in_liquid == 1 and game.biome == "ocean", "swimming in the sea is the ocean biome (%s)" % game.biome)
	check(Audio._current_track == ("OceanDay" if game.sky.is_day else "OceanNight"), "ocean music plays (%s)" % Audio._current_track)
	var depth: String = game.hud.depth_text()
	check(depth.ends_with(" Surface") or depth.ends_with(" Underground"), "the Depth Meter reads like Terraria's in the sea (%s)" % depth)
	var table: Array = game.spawner._table("surface", false, "ocean").map(func(e): return e[0])
	check("Crab" in table and "Shark" in table and "PinkJellyfish" in table, "ocean spawns: %s" % [table])
	var spot = game.spawner._find_water_spot(game, p.global_position, Data.npcs.Shark.size)
	check(spot != null and lw2.get_liquid(Vector3i(spot.floor())).x == 1, "sharks spawn in open water (%s)" % [spot])
	var shark := game.spawn_npc("Shark", p.global_position + Vector3(10, -1, 0))
	var jelly := game.spawn_npc("PinkJellyfish", p.global_position + Vector3(5, -1, 4))
	var d0: float = shark.center().distance_to(p.global_position)
	await frames(60)
	check(is_instance_valid(shark) and shark.in_water(shark.center()) and shark.center().distance_to(p.global_position) < d0 - 1.0,
			"the shark swims at the player (%.1f -> %.1f)" % [d0, shark.center().distance_to(p.global_position)])
	check(is_instance_valid(jelly) and jelly.in_water(jelly.center()), "the jellyfish stays in the water")
	var beach := Vector3i(-1, -1, -1)
	for x in range(0, 120):
		var top := lw2.surface_y(x, 256)
		if top > game.sea_level and Data.block(lw2.get_block(Vector3i(x, top, 256))).get("name", "") == "sand":
			beach = Vector3i(x, top + 1, 256)
			break
	check(beach.x > 0, "a sand beach above the sea (%s)" % beach)
	var crab := game.spawn_npc("Crab", Vector3(beach) + Vector3(0.5, 0.2, 0.5))
	await frames(40)
	check(is_instance_valid(crab) and crab.on_floor, "a crab walks the beach")
	await shot("ocean")
	for n in game.npcs():
		n.queue_free()
	p.global_position = land_pos
	p.velocity = Vector3.ZERO
	await frames(10)

	# Save, reload into a fresh session, compare. (By day, so tonight's
	# meteorite waits.)
	game.sky.is_day = true
	game.meteors.pending = true
	var pos := p.global_position
	var wood := p.inventory.count_of("Wood")
	check(game.save_world(), "world saved")
	game.queue_free()
	await frames(5)
	game = Game.new()
	add_child(game)
	game.start({"mode": "load", "name": "TestWorld", "path": "user://worlds/test_world.twld"})
	while game.state != Game.State.PLAYING:
		await frames(1)
	check(game.player.global_position.distance_to(pos) < 1.0, "player position restored")
	check(game.player.inventory.count_of("Wood") == wood, "inventory restored")
	check(game.chests.get_inventory(cpos).count_of("Torch") == 7, "chest contents restored")
	check(game.defeated_bosses.has("EyeofCthulhu"), "boss progress restored")
	check(game.world.get_liquid(liquid_cell).x == 1, "pit water saved and restored")
	check(game.waterfalls._falls.any(func(f): return f.pos == mouth), "waterfalls saved and restored")
	check(game.has_ocean, "the ocean flag is saved")
	check(game.meteors.pending, "a meteorite on its way is saved")

	# Don't leave the test world in the player's saved-worlds list.
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://worlds/test_world.twld"))
	print("RESULT: %d failures" % failures.size())
	for f in failures:
		print("  - " + f)
	get_tree().quit(1 if failures.size() > 0 else 0)
