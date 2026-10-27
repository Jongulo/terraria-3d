extends Node
## Title screen, as Terraria's menus go: Single Player, then pick (or
## create) a character (PlayerFile), then pick (or create) a world, then
## hand over to a Game session as that character.

var _menu: Control
var _game: Game
## Deleted worlds and characters go to the system trash (tests turn this off).
var use_trash := true
## The page shown under the logo, and the character picked for the worlds.
var _ui: Control
var _layout: VBoxContainer
var _logo: TextureRect
var _content: Control
var _player_path := ""


func _ready() -> void:
	if not Assets.available():
		_show_missing_assets()
		return
	_show_menu()


func _show_missing_assets() -> void:
	var l := Label.new()
	l.text = "Terraria assets not found.\n%s, then restart." % Assets.how_to_extract()
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-300, -30)
	add_child(l)


## The backdrop, the logo and the first page (`page`: "title", "players",
## "create" or "worlds").
func _show_menu(page := "title") -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.set_music("TitleClassic")
	# Full-screen art stays unscaled; the menu UI follows the UI scale setting.
	var backdrop := Control.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu = backdrop
	_ui = Control.new()
	var theme := Theme.new()
	theme.default_font = Assets.font("Mouse_Text")
	theme.default_font_size = 26
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.9))
	theme.set_constant("shadow_offset_x", "Label", 2)
	theme.set_constant("shadow_offset_y", "Label", 2)
	_ui.theme = theme
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_menu.add_child(_ui)
	Settings.track_ui_scale(_ui)
	# Layout: the logo on top (shrinking with the window), then the page.
	# Fits down to 640 x 360 at any UI scale.
	_layout = VBoxContainer.new()
	_layout.name = "Layout"
	_layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layout.offset_left = 16
	_layout.offset_right = -16
	_layout.offset_top = 8
	_layout.offset_bottom = -30  # the credit line
	_layout.add_theme_constant_override("separation", 8)
	_ui.add_child(_layout)
	_logo = TextureRect.new()
	_logo.texture = Assets.texture("Images/Logo")
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_layout.add_child(_logo)
	var sub := Label.new()
	sub.text = "3D"
	_logo.add_child(sub)
	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_child(_content)

	# The logo gets what height the page leaves (up to 30%), and the "3D"
	# sits on its lower right as the logo scales.
	var fit := func():
		var free := _ui.size.y - 54.0 - _content.get_combined_minimum_size().y
		var h := clampf(minf(_ui.size.y * 0.3, free), 48.0, 180.0)
		_logo.custom_minimum_size.y = h
		var k := minf(h / 142.0, maxf(_logo.size.x, 1.0) / 486.0)  # the logo's drawn scale
		sub.add_theme_font_size_override("font_size", maxi(int(48 * k), 12))
		sub.position = (_logo.size - Vector2(486, 142) * k) / 2.0 + Vector2(443, 110) * k
	_ui.resized.connect(fit)
	_logo.resized.connect(fit)
	_content.resized.connect(fit)

	var credit := Label.new()
	credit.text = "Fan project using assets from your own Terraria install. Terraria (c) Re-Logic."
	credit.add_theme_font_size_override("font_size", 18)
	credit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	credit.position = Vector2(12, -28)
	_ui.add_child(credit)
	show_page(page)
	fit.call()


## Swaps the page under the logo.
func show_page(page: String) -> void:
	for c in _content.get_children():
		c.queue_free()
	var node: Control
	match page:
		"players":
			node = _players_page()
		"create":
			var creator := CharacterCreator.new()
			creator.name = "CharacterCreator"
			creator.created.connect(func(path: String):
				_player_path = path
				show_page("players"))
			creator.cancelled.connect(show_page.bind("players"))
			node = creator
		"worlds":
			node = _worlds_page()
		_:
			node = _title_page()
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(node)


func _title_page() -> Control:
	var center := CenterContainer.new()
	center.name = "TitlePage"
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 300
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	for b in [["Single Player", show_page.bind("players")], ["Settings", _open_settings], ["Exit", func(): get_tree().quit()]]:
		var button := Button.new()
		button.name = b[0].replace(" ", "")
		button.text = b[0]
		button.pressed.connect(b[1])
		box.add_child(button)
	return center


func _open_settings() -> void:
	_layout.visible = false
	var menu := OptionsMenu.new()
	_ui.add_child(menu)
	menu.closed.connect(func(): _layout.visible = true)


## Your characters (last played first), New Character and Back.
func _players_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "PlayersPage"
	page.add_theme_constant_override("separation", 8)
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 460
	col.add_theme_constant_override("separation", 8)
	center.add_child(col)
	var title := Label.new()
	title.text = "Select Player"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.name = "PlayerList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	col.add_child(scroll)
	var players := PlayerFile.list()
	if players.is_empty():
		var none := Label.new()
		none.text = "No characters yet"
		none.modulate = Color(1, 1, 1, 0.7)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(none)
	for path in players:
		var d := PlayerFile.read(path)
		if not d.is_empty():
			list.add_child(_player_row(path, d))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(show_page.bind("title"))
	buttons.add_child(back)
	var new_char := Button.new()
	new_char.name = "NewCharacter"
	new_char.text = "New Character"
	new_char.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_char.pressed.connect(show_page.bind("create"))
	buttons.add_child(new_char)
	col.add_child(buttons)
	return page


## A character: its figure, its name (in its difficulty's colour; picks it),
## its life, mana and time played, and Delete (asking first, in the row).
func _player_row(path: String, d: Dictionary) -> HBoxContainer:
	var difficulty := clampi(int(d.get("difficulty", 0)), 0, PlayerFile.DIFFICULTIES.size() - 1)
	var st: Dictionary = d.get("state", {})
	var info := "%s   Life %d   Mana %d   %s" % [PlayerFile.DIFFICULTIES[difficulty], int(st.get("life_max", 100)),
			int(st.get("mana_max", 20)), PlayerFile.play_time_text(float(d.get("play_time", 0.0)))]
	return _confirm_row("Player_" + path.get_file().get_basename().validate_node_name(), str(d.name), func():
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 64
		b.tooltip_text = info
		b.pressed.connect(func():
			_player_path = path
			show_page("worlds"))
		var doll := PaperDoll.new()
		doll.look = PlayerLook.from_data(d.get("look", {}))
		doll.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		doll.size = PaperDoll.FRAME
		doll.position = Vector2(6, 4)
		doll.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(doll)
		var text := VBoxContainer.new()
		text.position = Vector2(56, 2)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := Label.new()
		n.text = str(d.name)
		n.add_theme_color_override("font_color", PlayerFile.DIFFICULTY_COLOURS[difficulty])
		text.add_child(n)
		var i := Label.new()
		i.text = info
		i.add_theme_font_size_override("font_size", 18)
		text.add_child(i)
		b.add_child(text)
		var forget := func():
			PlayerFile.use_trash = use_trash
			PlayerFile.delete(path)
			if _player_path == path:
				_player_path = ""
		return [b, forget])


## Pick a world for your character: create one (left), your saved worlds
## (right), and Back to the characters.
func _worlds_page() -> Control:
	var d := PlayerFile.read(_player_path)
	var page := VBoxContainer.new()
	page.name = "WorldsPage"
	page.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Select World  -  playing as %s" % str(d.get("name", "?"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)
	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	page.add_child(columns)
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
	new_btn.name = "CreateWorld"
	new_btn.text = "Create World"
	new_btn.pressed.connect(func():
		var seed_text := seed_edit.text.strip_edges()
		var seed := randi() % 2147483647 if seed_text == "" else (int(seed_text) if seed_text.is_valid_int() else seed_text.hash())
		_start({"mode": "new", "name": name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "World", "seed": seed,
				"evil": evil_pick.selected, "size": Game.WORLD_SIZES.keys()[size_pick.selected], "creative": mode_pick.selected == 1}))
	box.add_child(new_btn)
	# Test worlds: the whole sandbox, or one theme of it (TestWorld.KINDS),
	# with their own things on you (your character's are left as they are).
	var test_row := HBoxContainer.new()
	var test_pick := OptionButton.new()
	for k in TestWorld.KINDS:
		test_pick.add_item(TestWorld.KINDS[k])
	test_pick.tooltip_text = "Test World: everything at once. Or just NPCs (arena, town, critters), wiring (a wiring lab), biomes, or building (blocks, liquids, houses)"
	test_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_row.add_child(test_pick)
	var test_btn := Button.new()
	test_btn.text = "Create"
	test_btn.tooltip_text = "Flat sandbox with every item in chests, and what the picked kind is for.\nIt has its own items for you: your character's stay as they are."
	test_btn.pressed.connect(func():
		var k: String = TestWorld.KINDS.keys()[test_pick.selected]
		_start({"mode": "test", "test_kind": k, "name": _unique_name(TestWorld.KINDS[k]), "seed": 1}))
	test_row.add_child(test_btn)
	box.add_child(test_row)
	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	back.pressed.connect(show_page.bind("players"))
	box.add_child(back)

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
	# Columns up to 340 wide.
	var fit := func():
		var col_w := clampf((_ui.size.x - 56.0) / 2.0, 200.0, 340.0)
		left_scroll.custom_minimum_size.x = col_w
		right.custom_minimum_size.x = col_w
	fit.call()
	_ui.resized.connect(fit)
	page.tree_exiting.connect(func(): _ui.resized.disconnect(fit))
	return page


## A saved world: its name (loads it) and a Delete button, which asks first
## in the same row.
func _world_row(file: String) -> HBoxContainer:
	return _confirm_row("World_" + file.get_basename().validate_node_name(), file.get_basename(), func():
		var b := Button.new()
		b.text = file.get_basename()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _start({"mode": "load", "name": file.get_basename(), "path": Game.SAVE_DIR + file}))
		return [b, delete_world.bind(file)])


## A list row: what `make` gives ([its main button, what deleting does]),
## and a Delete button, which asks "Delete <what>?" in the same row first
## (Cancel puts the row back). The last row gone, the page is redrawn.
func _confirm_row(row_name: String, what: String, make: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	var on_delete := [Callable()]
	var show_normal := func():
		for c in row.get_children():
			c.queue_free()
		var made: Array = make.call()
		on_delete[0] = made[1]
		row.add_child(made[0])
		var del := Button.new()
		del.name = "Delete"
		del.text = "Delete"
		del.tooltip_text = "Delete %s (it goes to the trash)" % what
		row.add_child(del)
		return del
	var del: Button = show_normal.call()
	var ask := func(ask_self: Callable):
		for c in row.get_children():
			c.queue_free()
		var q := Label.new()
		q.text = "Delete %s?" % what
		q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		q.clip_text = true
		q.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
		row.add_child(q)
		var yes := Button.new()
		yes.name = "Confirm"
		yes.text = "Delete"
		yes.pressed.connect(func():
			on_delete[0].call()
			var list := row.get_parent()
			row.queue_free()
			if list.get_child_count() <= 1:
				show_page.call_deferred(_content.get_child(0).name.trim_suffix("Page").to_lower()))
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


## Plays `params` as the picked character.
func _start(params: Dictionary) -> void:
	params["player"] = _player_path
	_menu.queue_free()
	_game = Game.new()
	add_child(_game)
	_game.exit_to_menu.connect(_on_exit)
	_game.start(params)


## Back from a game: to the worlds, as your character (or, if it's gone, the
## characters).
func _on_exit() -> void:
	_game.queue_free()
	_game = null
	_show_menu.call_deferred("worlds" if FileAccess.file_exists(_player_path) else "players")
