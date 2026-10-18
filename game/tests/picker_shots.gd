extends Node
## Screenshots of the placeable picker for a few blocks (visual check).

func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	Settings.persist = false
	Settings.set_value("ui_scale", 1.0)
	var picker: Node = load("res://editor/placeable_picker.tscn").instantiate()
	picker.save_path = "user://picker_shots.json"
	add_child(picker)
	await get_tree().process_frame
	picker._help.visible = false
	for name in ["chest", "pot", "furnace", "torch", "wall_torch", "work_bench", "life_crystal", "tree_canopy"]:
		picker._select_block(name)
		for i in 20:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join("pick_%s.png" % name))
	print("RESULT: ok")
	get_tree().quit()
