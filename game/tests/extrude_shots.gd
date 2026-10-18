extends Node3D
## Visual check: extruded chests with each side noise, and at three depths.

func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.6, 0.98)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.6, 2.2, 4.8)
	cam.look_at(Vector3(0.6, 0.4, 0))
	var id := Data.block_id("chest")
	var x := -3.0
	var specs := [["none", 32, "none"], ["speckle", 32, "none"], ["grain", 32, "none"], ["palette", 32, "none"], ["grain", 16, "none"], ["grain", 6, "none"]]
	if OS.get_cmdline_user_args().has("--bevel"):
		specs = [["none", 32, "none"], ["none", 32, "chamfer"], ["none", 32, "round"], ["none", 32, "cove"], ["none", 32, "step"], ["palette", 32, "round"]]
	for spec in specs:
		Data.extrude_settings["chest"] = {"noise": spec[0], "depth": spec[1], "strength": 0.8, "seed": 3, "bevel": spec[2], "bevel_size": 5}
		var m := BlockModels.make_model(id, "extruded", 0)
		add_child(m)
		m.position = Vector3(x, 0, 0)
		m.rotation.y = -0.6
		var lab := Label3D.new()
		lab.text = "%s\n%s" % [spec[2], spec[0]] if OS.get_cmdline_user_args().has("--bevel") else "%s\ndepth %d" % [spec[0], spec[1]]
		lab.font_size = 28
		lab.pixel_size = 0.008
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(lab)
		lab.position = Vector3(x, 1.4, 0)
		x += 1.3
	if OS.get_cmdline_user_args().has("--voxel"):
		for c in get_children():
			if c is MeshInstance3D or c is Label3D:
				c.queue_free()
		x = -3.0
		var pot := Data.block_id("pot")
		for spec in [["hull", "none"], ["hull", "speckle"], ["hull", "palette"], ["lathe", "none"], ["lathe", "grain"], ["lathe", "palette"]]:
			Data.noise_settings[spec[0]]["pot"] = {"noise": spec[1], "strength": 1.0, "seed": 2}
			var m := BlockModels.make_model(pot, spec[0], 0)
			add_child(m)
			m.position = Vector3(x, 0, 0)
			m.rotation.y = -0.5
			var lab := Label3D.new()
			lab.text = "%s\n%s" % [spec[0], spec[1]]
			lab.font_size = 28
			lab.pixel_size = 0.008
			lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			add_child(lab)
			lab.position = Vector3(x, 1.2, 0)
			x += 1.3
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("extrude_noise.png"))
	print("RESULT: ok")
	get_tree().quit()
