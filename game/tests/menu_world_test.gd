extends Node
## The title screen's pages, as Terraria's: Single Player, then the saved
## characters (newest first, deleting asks first, Cancel keeps it), New
## Character (the character creator), then a character's worlds (newest
## first, creating, deleting). Runs headless on throwaway save files; the
## player's own characters and worlds are left alone. ./run_tests.sh

const FILES := ["_menu_check_old.twld", "_menu_check_new.twld"]
const PLAYERS := ["_menu_check_old", "_menu_check_new"]

var failures: Array[String] = []
var _made := []


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	Settings.persist = false
	PlayerFile.use_trash = false
	_run()


func _press(main: Node, row_name: String, button: String) -> bool:
	var row := main.find_child(row_name, true, false)
	var b: Button = row.find_child(button, true, false) if row else null
	if b == null:
		return false
	b.pressed.emit()
	await frames(2)
	return true


func _button(main: Node, name: String) -> Button:
	return main.find_child(name, true, false) as Button


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(Game.SAVE_DIR)
	for i in FILES.size():
		var f := FileAccess.open(Game.SAVE_DIR + FILES[i], FileAccess.WRITE)
		f.store_string("not a real world")
		f.close()
		PlayerFile.write(PlayerFile.DIR + PLAYERS[i] + PlayerFile.EXT, PlayerFile.new_data(PLAYERS[i], i, PlayerLook.new()))
		if i == 0:
			OS.delay_msec(1100)  # modified times have 1 s resolution
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.use_trash = false
	add_child(main)
	await frames(3)
	check(_button(main, "SinglePlayer") != null and _button(main, "Settings") != null and _button(main, "Exit") != null,
			"the title: Single Player, Settings, Exit")
	_button(main, "SinglePlayer").pressed.emit()
	await frames(2)

	# Characters.
	check(main.find_child("PlayerList", true, false) != null, "Single Player lists your characters")
	var order: Array = PlayerFile.list().map(func(p): return p.get_file().get_basename())
	check(order.find(PLAYERS[1]) < order.find(PLAYERS[0]), "saved characters are listed last played first")
	var row := "Player__menu_check_old"
	check(main.find_child(row, true, false) != null, "each character has a row")
	var old_path := PlayerFile.DIR + PLAYERS[0] + PlayerFile.EXT
	check(await _press(main, row, "Delete") and main.find_child(row, true, false).find_child("Confirm", true, false) != null,
			"deleting a character asks first")
	check(await _press(main, row, "Cancel") and FileAccess.file_exists(old_path), "Cancel keeps it")
	await _press(main, row, "Delete")
	await _press(main, row, "Confirm")
	await frames(2)
	check(not FileAccess.file_exists(old_path) and main.find_child(row, true, false) == null, "Confirm deletes the character and its row")

	# A new character.
	_button(main, "NewCharacter").pressed.emit()
	await frames(2)
	var creator: CharacterCreator = main.find_child("CharacterCreator", true, false)
	check(creator != null and _button(main, "Create").disabled, "New Character: the creator, which wants a name first")
	var name_edit: LineEdit = main.find_child("NameEdit", true, false)
	name_edit.text = "_menu_check_made"
	name_edit.text_changed.emit(name_edit.text)
	var diff: OptionButton = main.find_child("DifficultyPick", true, false)
	check(diff.item_count == 3 and diff.get_item_text(2) == "Hardcore", "it offers Classic, Mediumcore and Hardcore")
	diff.select(1)
	diff.item_selected.emit(1)
	var hair0 := creator.look.hair
	_button(main, "HairNext").pressed.emit()
	check(creator.look.hair == PlayerLook.creation_hairs()[1] and hair0 == 0, "Hair steps through Terraria's starting hairstyles")
	_button(main, "StyleNext").pressed.emit()
	check(creator.look.style == PlayerLook.CLOTH_STYLES[1], "Clothing steps through its clothing styles")
	_button(main, "Random").pressed.emit()
	var shirt: ColorPickerButton = main.find_child("Colour_shirt", true, false)
	check(shirt.color == creator.look.colour("shirt"), "Random changes the look, and the colour pickers follow")
	shirt.color_changed.emit(Color8(1, 2, 3))
	var made_look := creator.look.to_data()
	check(not _button(main, "Create").disabled, "named, it can be created")
	_button(main, "Create").pressed.emit()
	await frames(2)
	var made := PlayerFile.DIR + "_menu_check_made" + PlayerFile.EXT
	_made.append(made)
	var d := PlayerFile.read(made)
	check(d.get("name") == "_menu_check_made" and int(d.get("difficulty", 0)) == 1 and PlayerLook.from_data(d.get("look", {})).to_data() == made_look
			and d.look.colours.shirt == Color8(1, 2, 3).to_html(false),
			"Create writes it, its name, difficulty and look")
	check(main.find_child("Player__menu_check_made", true, false) != null, "and it's in the list")

	# Its worlds.
	var made_row := main.find_child("Player__menu_check_made", true, false)
	(made_row.get_child(0) as Button).pressed.emit()
	await frames(2)
	var size_pick: OptionButton = main.find_child("SizePick", true, false)
	check(size_pick != null and size_pick.item_count == Game.WORLD_SIZES.size() and size_pick.get_item_text(0).begins_with("Small"),
			"picking a character goes to the worlds: Create World offers the world sizes")
	var mode_pick: OptionButton = main.find_child("ModePick", true, false)
	check(mode_pick != null and mode_pick.get_item_text(1) == "Creative", "Create World offers creative mode")
	check(main._player_path == made, "as that character")
	var worlds: Array = main._saved_worlds()
	check(worlds.find(FILES[1]) < worlds.find(FILES[0]), "saved worlds are listed newest first")
	row = "World__menu_check_old"
	check(main.find_child(row, true, false) != null, "each saved world has a row")
	check(await _press(main, row, "Delete") and main.find_child(row, true, false).find_child("Confirm", true, false) != null,
			"Delete asks for confirmation")
	check(FileAccess.file_exists(Game.SAVE_DIR + FILES[0]), "nothing deleted before confirming")
	check(await _press(main, row, "Cancel") and await _press(main, row, "Delete") and await _press(main, row, "Cancel"),
			"Cancel restores the row, and Delete still asks again")
	check(FileAccess.file_exists(Game.SAVE_DIR + FILES[0]), "Cancel keeps the world")
	await _press(main, row, "Delete")
	await _press(main, row, "Confirm")
	await frames(2)
	check(not FileAccess.file_exists(Game.SAVE_DIR + FILES[0]) and main.find_child(row, true, false) == null,
			"Confirm deletes the world and its row")
	check(FileAccess.file_exists(Game.SAVE_DIR + FILES[1]), "other worlds are kept")
	_button(main, "Back").pressed.emit()
	await frames(2)
	check(main.find_child("PlayerList", true, false) != null, "Back goes to the characters")

	for f in FILES:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_DIR + f))
	for p in PLAYERS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerFile.DIR + p + PlayerFile.EXT))
	for p in _made:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("RESULT: %d failures" % failures.size())
	get_tree().quit()
