extends Node
## Title screen's saved-world list: newest first, and deleting a world (asks
## first, Cancel keeps it). Runs headless on two throwaway save files; the
## player's own worlds are left alone. ./run_tests.sh

const FILES := ["_menu_check_old.twld", "_menu_check_new.twld"]

var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	Settings.persist = false
	_run()


func _press(main: Node, row_name: String, button: String) -> bool:
	var row := main.find_child(row_name, true, false)
	var b: Button = row.find_child(button, true, false) if row else null
	if b == null:
		return false
	b.pressed.emit()
	await frames(2)
	return true


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(Game.SAVE_DIR)
	for i in FILES.size():
		var f := FileAccess.open(Game.SAVE_DIR + FILES[i], FileAccess.WRITE)
		f.store_string("not a real world")
		f.close()
		if i == 0:
			OS.delay_msec(1100)  # modified times have 1 s resolution
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.use_trash = false
	add_child(main)
	await frames(3)
	var size_pick: OptionButton = main.find_child("SizePick", true, false)
	check(size_pick != null and size_pick.item_count == Game.WORLD_SIZES.size() and size_pick.get_item_text(0).begins_with("Small"),
			"Create World offers the world sizes")
	var mode_pick: OptionButton = main.find_child("ModePick", true, false)
	check(mode_pick != null and mode_pick.get_item_text(1) == "Creative", "Create World offers creative mode")
	var order: Array = main._saved_worlds()
	check(order.find(FILES[1]) < order.find(FILES[0]), "saved worlds are listed newest first")
	var row := "World__menu_check_old"
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
	for f in FILES:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_DIR + f))
	print("RESULT: %d failures" % failures.size())
	get_tree().quit()
