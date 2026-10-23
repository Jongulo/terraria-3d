extends Node
## The test world's themed kinds (TestWorld.KINDS): each builds its own part,
## and the wiring one's lab works. Runs headless: ./run_tests.sh

const PATH := "user://worlds/test_world_kinds_check.twld"

var game: Game
var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	Settings.persist = false
	Settings.set_value("render_distance", 3)
	var c := Vector3i(TestWorld.SIZE.x / 2, TestWorld.GROUND + 1, TestWorld.SIZE.z / 2)
	for kind in ["npc", "wiring", "biome", "building"]:
		game = Game.new()
		add_child(game)
		game.start({"mode": "test", "test_kind": kind, "name": TestWorld.KINDS[kind], "seed": 1, "path": PATH})
		while game.state != Game.State.PLAYING:
			await get_tree().process_frame
		await frames(5)
		var w: VoxelWorld = game.world
		var tw: TestWorld = game.test_world
		var has_block := func(name: String, at: Vector3i, r: int) -> bool:
			return not Array(w.find_blocks(at, Vector3i(r, r, r), PackedInt32Array([Data.block_id(name)]), 1)).is_empty()
		var chests: bool = has_block.call("chest", c + Vector3i(0, 0, -12), 12)
		var spawners := tw.spawners.size()
		var town := game.town.residents.size()
		var snow: bool = has_block.call("snow_block", c + Vector3i(TestWorld.SNOW.x, -2, TestWorld.SNOW.y), 12)
		var gallery: bool = has_block.call("gold_ore", c + Vector3i(0, 0, TestWorld.GALLERY_Z), 20)
		var wired := game.wiring.cells.size()
		check(tw.kind == kind and chests, "%s: built, with the chests of every item" % TestWorld.KINDS[kind])
		match kind:
			"npc":
				check(spawners > 10 and town == TestWorld.TOWN_RESIDENTS.size() and not snow and not gallery,
						"NPCs: the arena's spawners (%d) and the town (%d), no biomes or block gallery" % [spawners, town])
			"biome":
				check(snow and spawners == 0 and town == 0 and not gallery, "biomes: the Snow patch, no spawners (%d), town (%d) or gallery" % [spawners, town])
			"building":
				# (One spawner: the water pool's, for swimmers.)
				check(gallery and spawners == 1 and town == 0 and not snow, "building: the block gallery, the pool's spawner (%d), no town or biomes" % spawners)
			"wiring":
				check(wired > 50 and spawners == 0 and town == 0 and not snow and not gallery, "wiring: the lab's wire (%d cells), nothing else" % wired)
				var p := game.player
				p.god_mode = true
				# The lever by the door opens it; the display's first lever lights
				# its corner box, and only that one.
				var door := c + Vector3i(-20, 0, 12)
				game.hit_switch(c + Vector3i(-28, 0, 12))
				await frames(2)
				check(Doors.is_open(Data.block(w.get_block(Doors.bottom(w, door)))) and Data.block(w.get_block(c + Vector3i(-25, 0, 14))).name == "torch_off",
						"the lab's lever opens its door and switches off its torches")
				game.hit_switch(c + Vector3i(10, 0, 50))
				await frames(2)
				var lit := []
				for x in range(14, 17):
					for y in range(1, 4):
						if Data.block(w.get_block(c + Vector3i(x, y, 46))).name == "pixel_box_on":
							lit.append(Vector2i(x - 14, y - 1))
				game.hit_switch(c + Vector3i(24, 0, 52))
				await frames(2)
				var lit2 := 0
				for x in range(14, 17):
					for y in range(1, 4):
						if Data.block(w.get_block(c + Vector3i(x, y, 46))).name == "pixel_box_on":
							lit2 += 1
				check(lit == [Vector2i(0, 0)] and lit2 == 2 and Data.block(w.get_block(c + Vector3i(16, 3, 46))).name == "pixel_box_on",
						"the Pixel Box display: a lever lights the box where its row and column cross (%s, then %d)" % [lit, lit2])
				p.global_position = Vector3(c + Vector3i(4, 0, 36)) + Vector3(0.5, 0.05, 0.5)
				p._fall_start = p.global_position.y
				await frames(2)
				game.hit_switch(c + Vector3i(10, 0, 38))
				await frames(2)
				check(p.global_position.distance_to(Vector3(c + Vector3i(16, 0, 36)) + Vector3(0.5, 0.05, 0.5)) < 0.6, "the lab's teleporters work")
				check(game.player.inventory.count_of("Wire") > 0 and game.player.inventory.count_of("Wrench") == 1, "you start with wrenches, wire and actuators")
		var help := "\n".join(tw.help_lines())
		check(help.begins_with(TestWorld.KINDS[kind].to_upper()) and (help.contains("wiring lab") == (kind == "wiring")), "%s: its own help" % TestWorld.KINDS[kind])
		game.queue_free()
		await frames(3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT: %d failures" % failures.size())
	for f in failures:
		print("  - " + f)
	get_tree().quit(1 if failures.size() > 0 else 0)
