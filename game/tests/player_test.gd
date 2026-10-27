extends Node
## Characters apart from worlds (PlayerFile): a character takes its things
## from world to world, a world keeps none of them, your bed is kept per
## world, a test world leaves your character alone, and what a death costs
## each difficulty. On throwaway files (user://_player_test/ for the worlds,
## "_player_test" characters); the player's own are left alone.
## godot --headless --path game res://tests/player_test.tscn

const WORLD_DIR := "user://_player_test/"

var failures: Array[String] = []
var game: Game
var _paths: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	Settings.persist = false
	Settings.set_value("render_distance", 4)
	Settings.set_value("far_distance", 0)
	PlayerFile.use_trash = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORLD_DIR))
	await _run()
	for p in _paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var dir := DirAccess.open(WORLD_DIR)
	if dir:
		for f in dir.get_files():
			dir.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WORLD_DIR))
	print("RESULT: %d failures" % failures.size())
	get_tree().quit()


func _character(name: String, difficulty: int, look := PlayerLook.new()) -> String:
	var path := PlayerFile.path_for("_player_test " + name)
	_paths.append(path)
	PlayerFile.write(path, PlayerFile.new_data(name, difficulty, look))
	return path


## Plays `params` till it's going.
func _play(params: Dictionary) -> void:
	game = Game.new()
	add_child(game)
	game.start(params)
	while game.state != Game.State.PLAYING:
		await frames(1)
	game.spawner.process_mode = Node.PROCESS_MODE_DISABLED
	await frames(5)


func _leave() -> void:
	game.queue_free()
	game = null
	await frames(3)


func _run() -> void:
	var look := PlayerLook.new()
	look.hair = 41
	look.style = 7
	look.colours.shirt = Color8(20, 200, 90)
	var ana := _character("Ana", PlayerFile.CLASSIC, look)
	var bo := _character("Bo", PlayerFile.CLASSIC)
	var world := WORLD_DIR + "World.twld"

	# A new world, as Ana: her name and look, a new character's tools.
	await _play({"mode": "new", "name": "_player_test", "seed": 7, "path": world, "size": Vector3i(512, 256, 512), "player": ana})
	var p := game.player
	check(p.player_name == "Ana" and p.look.hair == 41 and p.look.style == 7 and p.look.colour("shirt") == Color8(20, 200, 90),
			"you play as your character: its name and look (%s, hair %d, style %d)" % [p.player_name, p.look.hair, p.look.style])
	check(p.inventory.count_of("CopperShortsword") == 1 and p.inventory.count_of("CopperPickaxe") == 1 and p.inventory.count_of("CopperAxe") == 1,
			"a new character starts with Terraria's copper tools")
	check(p.global_position.distance_to(p.spawn_point) < 1.0, "and at the world's spawn")
	check(NPC.fill("Hello, {PlayerName}!") == "Hello, Ana!", "town NPCs can say your name")
	# Her things and a bed in this world.
	p.inventory.add("DirtBlock", 37)
	p.life_max = 140
	var bed := Vector3i(p.spawn_point.floor()) + Vector3i(6, 0, 0)
	game.world.set_block(bed + Vector3i.DOWN, Data.block_id("stone"))
	game.world.set_block(bed, Data.block_id("bed"))
	p.bed = bed
	var wid := game.world_id
	check(game.save_world(), "saving the world saves your character too")
	var d := PlayerFile.read(ana)
	check(not d.get("fresh", false) and int(d.state.get("life_max", 0)) == 140
			and d.state.inventory.any(func(s): return s != null and s.item == "DirtBlock" and int(s.count) == 37),
			"her things are in her file (life %s)" % d.state.get("life_max"))
	check(d.spawns.get(str(wid), []).map(func(v): return int(v)) == [bed.x, bed.y, bed.z] and not d.state.has("pos") and not d.state.has("bed"),
			"her bed is kept by this world's number, not where she stood (%s)" % [d.spawns])
	check(float(d.play_time) > 0.0, "and how long she's played (%.2f s)" % float(d.play_time))
	await _leave()

	# The same world as Bo: none of her things are in it.
	await _play({"mode": "load", "name": "_player_test", "path": world, "player": bo})
	p = game.player
	check(game.world_id == wid, "the world keeps its number")
	check(p.player_name == "Bo" and p.inventory.count_of("DirtBlock") == 0 and p.life_max == 100 and p.inventory.count_of("CopperPickaxe") == 1,
			"another character brings only its own things: a world keeps none")
	check(p.bed == Player.NO_BED and p.global_position.distance_to(p.spawn_point) < 1.0, "and her bed isn't his: he starts at the spawn")
	await _leave()

	# Ana again: her things, and at her bed.
	await _play({"mode": "load", "name": "_player_test", "path": world, "player": ana})
	p = game.player
	check(p.inventory.count_of("DirtBlock") == 37 and p.life_max == 140 and p.inventory.count_of("CopperPickaxe") == 1,
			"back as Ana, with her things")
	check(p.bed == bed and p.global_position.distance_to(Vector3(bed) + Vector3(0.5, 0, 0.5)) < 0.6,
			"starting at her bed in this world (%s)" % p.global_position)

	# Deaths: Classic drops half your coins; Mediumcore everything but the
	# copper tools (lost).
	p.inventory.add("GoldCoin", 10)
	p._die()
	check(p.inventory.count_of("GoldCoin") == 5 and p.inventory.count_of("DirtBlock") == 37, "a Classic character drops half its coins")
	p._respawn()
	await frames(2)
	p.difficulty = PlayerFile.MEDIUMCORE
	p.armor.slots[0] = Inventory.stack("WoodHelmet", 1)
	var drops_before := _drops()
	p._die()
	await frames(2)
	var dropped := _drops().filter(func(n): return not n in drops_before)
	var kinds := dropped.map(func(n): return n.item)
	check(p.inventory.is_empty() and p.armor.slots[0] == null, "a Mediumcore character drops everything it carries and wears")
	check("DirtBlock" in kinds and "WoodHelmet" in kinds and "GoldCoin" in kinds and not "CopperPickaxe" in kinds,
			"where it died, but not the starting copper tools (%s)" % [kinds])
	p._respawn()
	await _leave()

	# Hardcore: dead for good, its file gone, back to the menu.
	var cy := _character("Cy", PlayerFile.HARDCORE)
	await _play({"mode": "load", "name": "_player_test", "path": world, "player": cy})
	p = game.player
	check(p.difficulty == PlayerFile.HARDCORE, "a Hardcore character")
	var left := [false]
	game.exit_to_menu.connect(func(): left[0] = true)
	p._die()
	check(not FileAccess.file_exists(cy), "dies for good: its file is deleted")
	await get_tree().create_timer(5.5).timeout
	check(p.gone and not p.alive and left[0], "never comes back, and you're taken back to the menu")
	await _leave()

	# A test world: its own things on you; your character is left as it was.
	var before := FileAccess.get_file_as_string(bo)
	await _play({"mode": "test", "test_kind": "npc", "name": "_player_test_sandbox", "seed": 1, "path": WORLD_DIR + "Sandbox.twld", "player": bo})
	p = game.player
	check(p.player_name == "Bo" and p.inventory.count_of("PlatinumPickaxe") > 0, "a test world: you as yourself, with its loadout")
	game.save_world()
	check(FileAccess.get_file_as_string(bo) == before, "and your character's file untouched")
	await _leave()


func _drops() -> Array:
	return game.entities.get_children().filter(func(n): return n is ItemDrop)
