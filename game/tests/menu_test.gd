extends Node
## Opens the title screen, its Settings menu (Controls tab) at 125% UI scale,
## and saves screenshots. godot --path game res://tests/menu_test.tscn -- <dir>


func _ready() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	Settings.persist = false
	Settings.set_value("ui_scale", 1.25)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("menu_title.png"))
	var settings_button: Button = null
	for b in main.find_children("*", "Button", true, false):
		if b.text == "Settings":
			settings_button = b
	settings_button.pressed.emit()
	await get_tree().process_frame
	var menu: OptionsMenu = main.find_children("*", "OptionsMenu", true, false)[0]
	var tabs: TabContainer = menu.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 3
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("menu_controls.png"))
	print("RESULT: ok")
	get_tree().quit()
