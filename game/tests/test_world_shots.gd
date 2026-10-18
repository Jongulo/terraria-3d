extends Node
## Screenshots of the Test World (visual check). godot --path game res://tests/test_world_shots.tscn -- <dir>

var game: Game


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	Settings.persist = false
	Settings.set_value("render_distance", 5)
	game = Game.new()
	add_child(game)
	game.start({"mode": "test", "name": "Shots", "seed": 1, "path": "user://worlds/test_world_shots.twld"})
	while game.state != Game.State.PLAYING:
		await get_tree().process_frame
	var p := game.player
	p.flying = true
	var c := Vector3(TestWorld.SIZE.x / 2, TestWorld.GROUND + 1, TestWorld.SIZE.z / 2)
	var spawner: Vector3 = Vector3(game.test_world.spawners.values()[0].pos)
	game.test_world.use_spawner(Vector3i(spawner), false)
	var views := [
		["overview", c + Vector3(-34, 34, 40), c + Vector3(0, 0, 0)],
		["storage", c + Vector3(2, 2.5, -1), c + Vector3(0, 1, -9)],
		["arena", c + Vector3(16, 4, 10), c + Vector3(11, 1, -2)],
		["liquids", c + Vector3(-10, 8, 6), c + Vector3(-21, 2, -3)],
		["gallery", c + Vector3(0, 6, 4), c + Vector3(0, 1, 15)],
	]
	for v in views:
		p.global_position = v[1] - Vector3(0, Player.EYE_HEIGHT, 0)
		var dir: Vector3 = (v[2] - v[1]).normalized()
		p.look_at_yaw_pitch(atan2(-dir.x, -dir.z), asin(dir.y))
		for i in 150:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join("tw_%s.png" % v[0]))
	# Animation strip: a skeleton walking toward the player next to a dummy being hit.
	var spot := c + Vector3(6, 0, 3)
	p.global_position = spot + Vector3(0, 0, 4)
	p.look_at_yaw_pitch(0.0, -0.15)
	var skel := game.spawn_npc("Skeleton", spot + Vector3(-3, 0, 0))
	var dummies: Array = game.npcs().filter(func(n): return n.kind == "TargetDummy")
	for i in 6:
		for j in 9:
			await get_tree().process_frame
		if not dummies.is_empty() and i % 2 == 0:
			dummies[0].hit(20, 0.0, Vector3.FORWARD, 0.0)
		skel.velocity.x = 3.0
		get_viewport().get_texture().get_image().save_png(out.path_join("tw_anim_%d.png" % i))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://worlds/test_world_shots.twld"))
	print("RESULT: ok")
	get_tree().quit()
