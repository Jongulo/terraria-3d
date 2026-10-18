extends Node
## Title screen: create or load a world, then hand over to a Game session.

var _menu: Control
var _game: Game
## Deleted worlds go to the system trash (tests turn this off).
var use_trash := true


func _ready() -> void:
	if not Assets.available():
		_show_missing_assets()
		return
	_show_menu()


func _show_missing_assets() -> void:
	var l := Label.new()
	l.text = "Terraria assets not found.\nRun ./extract_assets.sh (needs a local Terraria install), then restart."
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-300, -30)
	add_child(l)


func _show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.set_music("TitleClassic")
	# Full-screen art stays unscaled; the menu UI follows the UI scale setting.
	var backdrop := Control.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu = backdrop
	var ui := Control.new()
	var theme := Theme.new()
	theme.default_font = Assets.font("Mouse_Text")
	theme.default_font_size = 26
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.9))
	theme.set_constant("shadow_offset_x", "Label", 2)
	theme.set_constant("shadow_offset_y", "Label", 2)
	ui.theme = theme
	add_child(_menu)

	var bg := TextureRect.new()
	bg.texture = Assets.texture("Images/Background_0")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)
	var hills := TextureRect.new()
	hills.texture = Assets.texture("Images/Background_7")
	hills.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hills.stretch_mode = TextureRect.STRETCH_TILE
	hills.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hills.position.y = -435
	hills.size.y = 435
	_menu.add_child(hills)
	_menu.add_child(ui)
	Settings.track_ui_scale(ui)
	# Layout: the logo on top (shrinking with the window), then two columns:
	# creating worlds and settings on the left, the saved worlds on the right
	# (scrolling to fill the height). Fits down to 640 x 360 at any UI scale.
	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 16
	layout.offset_right = -16
	layout.offset_top = 8
	layout.offset_bottom = -30  # the credit line
	layout.add_theme_constant_override("separation", 8)
	ui.add_child(layout)
	var logo := TextureRect.new()
	logo.texture = Assets.texture("Images/Logo")
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layout.add_child(logo)
	var sub := Label.new()
	sub.text = "3D"
	logo.add_child(sub)

	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	layout.add_child(columns)
	# Scrolls only when the window is too short for it.
	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(left_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	left_scroll.add_child(box)

	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "World name"
	name_edit.text = "My World"
	box.add_child(name_edit)
	var seed_edit := LineEdit.new()
	seed_edit.placeholder_text = "Seed (blank = random)"
	box.add_child(seed_edit)
	var size_row := HBoxContainer.new()
	var size_label := Label.new()
	size_label.text = "World size"
	size_row.add_child(size_label)
	var size_pick := OptionButton.new()
	size_pick.name = "SizePick"
	for k in Game.WORLD_SIZES:
		var v: Vector3i = Game.WORLD_SIZES[k]
		size_pick.add_item("%s  %d x %d" % [k.capitalize(), v.x, v.z])
	size_pick.tooltip_text = "Terraria's world sizes in proportion (an island in the ocean).\nLarger worlds take longer to make: about 10 s, 25 s, 1 min."
	size_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(size_pick)
	box.add_child(size_row)
	var mode_row := HBoxContainer.new()
	var mode_label := Label.new()
	mode_label.text = "Game mode"
	mode_row.add_child(mode_label)
	var mode_pick := OptionButton.new()
	mode_pick.name = "ModePick"
	mode_pick.add_item("Survival")
	mode_pick.add_item("Creative")
	mode_pick.tooltip_text = "Creative: no damage, fly (double-tap jump), break blocks at once,\nevery item in the inventory, nothing used up. Switch any time from the pause menu."
	mode_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(mode_pick)
	box.add_child(mode_row)
	var evil_row := HBoxContainer.new()
	var evil_label := Label.new()
	evil_label.text = "World evil"
	evil_row.add_child(evil_label)
	var evil_pick := OptionButton.new()
	for e in ["Random", "Corruption", "Crimson"]:
		evil_pick.add_item(e)
	evil_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	evil_row.add_child(evil_pick)
	box.add_child(evil_row)
	var new_btn := Button.new()
	new_btn.text = "Create World"
	new_btn.pressed.connect(func():
		var seed_text := seed_edit.text.strip_edges()
		var seed := randi() % 2147483647 if seed_text == "" else (int(seed_text) if seed_text.is_valid_int() else seed_text.hash())
		_start({"mode": "new", "name": name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "World", "seed": seed,
				"evil": evil_pick.selected, "size": Game.WORLD_SIZES.keys()[size_pick.selected], "creative": mode_pick.selected == 1}))
	box.add_child(new_btn)
	var test_btn := Button.new()
	test_btn.text = "Create Test World"
	test_btn.tooltip_text = "Flat sandbox with every item, enemy spawners, dummies and liquids"
	test_btn.pressed.connect(func(): _start({"mode": "test", "name": _unique_name("Test World"), "seed": 1}))
	box.add_child(test_btn)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	box.add_child(bottom)
	var options := Button.new()
	options.text = "Settings"
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.pressed.connect(func():
		layout.visible = false
		var menu := OptionsMenu.new()
		ui.add_child(menu)
		menu.closed.connect(func(): layout.visible = true))
	bottom.add_child(options)
	var quit := Button.new()
	quit.text = "Exit"
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(func(): get_tree().quit())
	bottom.add_child(quit)

	var right := VBoxContainer.new()
	var worlds := _saved_worlds()
	if not worlds.is_empty():
		columns.add_child(right)
		var l := Label.new()
		l.text = "Saved worlds"
		right.add_child(l)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var list := VBoxContainer.new()
		list.name = "WorldList"
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		scroll.add_child(list)
		right.add_child(scroll)
		for w in worlds:
			list.add_child(_world_row(w))

	# Columns up to 340 wide; the logo gets what height the left column leaves
	# (up to 30%), and the "3D" sits on its lower right as the logo scales.
	var fit := func():
		var col_w := clampf((ui.size.x - 56.0) / 2.0, 200.0, 340.0)
		left_scroll.custom_minimum_size.x = col_w
		right.custom_minimum_size.x = col_w
		var free := ui.size.y - 54.0 - box.get_combined_minimum_size().y
		var h := clampf(minf(ui.size.y * 0.3, free), 48.0, 180.0)
		logo.custom_minimum_size.y = h
		var k := minf(h / 142.0, maxf(logo.size.x, 1.0) / 486.0)  # the logo's drawn scale
		sub.add_theme_font_size_override("font_size", maxi(int(48 * k), 12))
		sub.position = (logo.size - Vector2(486, 142) * k) / 2.0 + Vector2(443, 110) * k
	fit.call()
	ui.resized.connect(fit)
	logo.resized.connect(fit)

	var credit := Label.new()
	credit.text = "Fan project using assets from your own Terraria install. Terraria (c) Re-Logic."
	credit.add_theme_font_size_override("font_size", 18)
	credit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	credit.position = Vector2(12, -28)
	ui.add_child(credit)

## A saved world: its name (loads it) and a Delete button, which asks first
## in the same row.
func _world_row(file: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "World_" + file.get_basename().validate_node_name()
	var show_normal := func():
		for c in row.get_children():
			c.queue_free()
		var b := Button.new()
		b.text = file.get_basename()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _start({"mode": "load", "name": file.get_basename(), "path": Game.SAVE_DIR + file}))
		row.add_child(b)
		var del := Button.new()
		del.name = "Delete"
		del.text = "Delete"
		del.tooltip_text = "Delete this world (it goes to the trash)"
		row.add_child(del)
		return del
	var del: Button = show_normal.call()
	var ask := func(ask_self: Callable):
		for c in row.get_children():
			c.queue_free()
		var q := Label.new()
		q.text = "Delete %s?" % file.get_basename()
		q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		q.clip_text = true
		q.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
		row.add_child(q)
		var yes := Button.new()
		yes.name = "Confirm"
		yes.text = "Delete"
		yes.pressed.connect(func():
			delete_world(file)
			row.queue_free()
			if row.get_parent().get_child_count() <= 1:
				_menu.queue_free()
				_show_menu.call_deferred())  # last one gone: drop the list
		row.add_child(yes)
		var no := Button.new()
		no.name = "Cancel"
		no.text = "Cancel"
		no.pressed.connect(func():
			var d: Button = show_normal.call()
			d.pressed.connect(ask_self.bind(ask_self)))
		row.add_child(no)
	del.pressed.connect(ask.bind(ask))
	return row


## Deletes a saved world file: to the system trash if there is one (so a
## mistake can be undone), otherwise removed.
func delete_world(file: String) -> void:
	var path := ProjectSettings.globalize_path(Game.SAVE_DIR + file)
	if not (use_trash and OS.move_to_trash(path) == OK):
		DirAccess.remove_absolute(path)


## "Test World", or "Test World 2", 3... if saves with those names exist.
func _unique_name(base: String) -> String:
	var taken := _saved_worlds().map(func(f): return f.get_basename())
	var name := base
	var n := 2
	while name in taken:
		name = "%s %d" % [base, n]
		n += 1
	return name


func _saved_worlds() -> Array:
	var out := []
	var dir := DirAccess.open(Game.SAVE_DIR)
	if dir:
		for f in dir.get_files():
			if f.ends_with(".twld"):
				out.append(f)
	# Newest first.
	var age := func(f: String) -> int: return FileAccess.get_modified_time(Game.SAVE_DIR + f)
	out.sort_custom(func(a, b): return age.call(a) > age.call(b))
	return out


func _start(params: Dictionary) -> void:
	_menu.queue_free()
	_game = Game.new()
	add_child(_game)
	_game.exit_to_menu.connect(_on_exit)
	_game.start(params)


func _on_exit() -> void:
	_game.queue_free()
	_game = null
	_show_menu.call_deferred()
