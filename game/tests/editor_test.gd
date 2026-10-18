extends Node
## Drives the viewmodel editor with synthetic input and checks the results.
## godot --path game res://tests/editor_test.tscn -- <screenshot dir>

const CONFIG := "user://editor_test_viewmodel.json"

var ed: Node3D
var out_dir := "user://"
var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures.append(what)


func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func key(code: Key, ctrl := false, shift := false, alt := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.alt_pressed = alt
		Input.parse_input_event(e)
		await frames(1)


func type_text(text: String) -> void:
	for c in text:
		match c:
			".": await key(KEY_PERIOD)
			"-": await key(KEY_MINUS)
			_: await key(KEY_0 + int(c))


func move_mouse(to: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = to
	e.global_position = to
	e.relative = to - ed.mouse
	Input.parse_input_event(e)
	await frames(1)


func mouse_button(b: MouseButton, pressed: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = pressed
	e.shift_pressed = shift
	e.position = ed.mouse
	e.global_position = ed.mouse
	Input.parse_input_event(e)
	await frames(1)


func grip() -> Dictionary:
	return Viewmodel.grip_for(ed.current_item)


func shot(name: String) -> void:
	# Headless runs (the default, see run_tests.sh) have nothing to capture.
	if DisplayServer.get_name() == "headless":
		return
	await frames(3)
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("editor_%s.png" % name))


func _ready() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out_dir = OS.get_cmdline_user_args()[0]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))
	Settings.persist = false
	Settings.set_value("ui_scale", 2.0)  # the editor must stay usable at large UI scales
	ed = load("res://editor/viewmodel_editor.tscn").instantiate()
	ed.config_path = CONFIG
	add_child(ed)
	_run()


func _run() -> void:
	await frames(5)
	var center := get_viewport().get_visible_rect().size * 0.5
	await move_mouse(center)
	await shot("start")

	# Grab: moving the mouse right moves the item right (camera +X).
	var x0: float = grip().position[0]
	await key(KEY_G)
	check(ed.mode == ed.Mode.GRAB, "G starts grab")
	await move_mouse(center + Vector2(120, 0))
	await key(KEY_ENTER)
	check(ed.mode == ed.Mode.IDLE, "Enter confirms")
	check(grip().position[0] > x0 + 0.01, "mouse right moved the item right (%.3f -> %.3f)" % [x0, grip().position[0]])
	check(ed.dirty, "edit marks the file unsaved")

	await key(KEY_Z, true)
	check(absf(grip().position[0] - x0) < 1e-5, "Ctrl+Z undoes the grab")
	await key(KEY_Z, true, true)
	check(grip().position[0] > x0 + 0.01, "Ctrl+Shift+Z redoes it")

	# Rotate about X by exactly 90 degrees via numeric input.
	var r0 := Basis.from_euler(Viewmodel.vec(grip().rotation) * (PI / 180.0))
	await key(KEY_R)
	await key(KEY_X)
	await type_text("90")
	await key(KEY_ENTER)
	var r1 := Basis.from_euler(Viewmodel.vec(grip().rotation) * (PI / 180.0))
	var expected := Basis(Vector3.RIGHT, deg_to_rad(90.0)) * r0
	check(r1.is_equal_approx(expected) or (r1.x - expected.x).length() + (r1.y - expected.y).length() < 1e-3, "R X 90 rotates 90° about camera X")

	# Typed scale, then a cancelled grab leaves things alone.
	await key(KEY_S)
	await type_text("1.5")
	await key(KEY_ENTER)
	check(absf(float(grip().scale) - 1.5) < 1e-4, "S 1.5 sets scale (%s)" % grip().scale)
	var before: Array = grip().position.duplicate()
	await key(KEY_G)
	await move_mouse(center + Vector2(-200, 80))
	await mouse_button(MOUSE_BUTTON_RIGHT, true)
	await mouse_button(MOUSE_BUTTON_RIGHT, false)
	check(grip().position == before and ed.mode == ed.Mode.IDLE, "RMB cancels a grab")

	# Axis constraint: G Z with typed distance moves only along camera Z.
	await key(KEY_G)
	await key(KEY_Z)
	await type_text("-0.1")
	await shot("grab_z")
	await key(KEY_ENTER)
	check(absf(grip().position[2] - (before[2] - 0.1)) < 1e-4 and absf(grip().position[0] - before[0]) < 1e-5, "G Z -0.1 moves 10 cm forward only")

	# Hand target.
	await key(KEY_TAB)
	check(ed.target == "hand", "Tab switches to the hand")
	var hy := Viewmodel.hand_position().y
	await key(KEY_G)
	await key(KEY_Y)
	await type_text("0.05")
	await key(KEY_ENTER)
	check(absf(Viewmodel.hand_position().y - (hy + 0.05)) < 1e-4, "hand moved up 5 cm")
	await key(KEY_TAB)

	# Alt+R resets the rotation to the default.
	await key(KEY_R, false, false, true)
	var d := Viewmodel.default_grip(Viewmodel.kind_of(Data.item(ed.current_item)))
	check(Viewmodel.vec(grip().rotation).is_equal_approx(Viewmodel.vec(d.rotation)), "Alt+R resets rotation")

	# Per-item override.
	ed._override.button_pressed = true
	await frames(2)
	check(Viewmodel.config.items.has(ed.current_item), "override created for this item")
	ed._override.button_pressed = false
	await frames(2)
	check(not Viewmodel.config.items.has(ed.current_item), "override removed")

	# Save, then reload from disk.
	await key(KEY_S, true)
	check(not ed.dirty and FileAccess.file_exists(CONFIG), "Ctrl+S saved the file")
	var saved_pos: Array = grip().position.duplicate()
	Viewmodel.load_config(CONFIG)
	check(Viewmodel.vec(grip().position).is_equal_approx(Viewmodel.vec(saved_pos)), "reloaded pose matches")
	check(absf(Viewmodel.hand_position().y - (hy + 0.05)) < 1e-4, "reloaded hand matches")

	# Orbit view with MMB, back with Numpad 0; the animation preview runs.
	await mouse_button(MOUSE_BUTTON_MIDDLE, true)
	await move_mouse(center + Vector2(-260, -60))
	await mouse_button(MOUSE_BUTTON_MIDDLE, false)
	check(not ed.camera_view, "MMB drag orbits")
	await key(KEY_G)
	await key(KEY_X)
	await shot("orbit_grab_x")
	await key(KEY_ESCAPE)
	await key(KEY_KP_0)
	check(ed.camera_view, "Numpad 0 returns to the camera view")
	await key(KEY_SPACE)
	await frames(4)
	check(player_animating(), "Space previews the swing")
	await key(KEY_PAGEDOWN)
	check(ed.current_item != "CopperBroadsword", "PageDown selects the next item (%s)" % ed.current_item)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))
	print("RESULT: %d failures" % failures.size())
	for f in failures:
		print("  - " + f)
	get_tree().quit(1 if failures.size() > 0 else 0)


func player_animating() -> bool:
	return ed.player.viewmodel._t < 1.0
