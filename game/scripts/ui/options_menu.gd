class_name OptionsMenu
extends PanelContainer
## Settings screen shared by the title menu and the pause menu: General,
## Interface (UI scale), Audio and Controls (click a binding, press a key).

signal closed

var _listening := ""
var _bind_buttons := {}
var _ui_scale_label: Label


const PANEL_SIZE := Vector2(720, 580)


func _ready() -> void:
	_layout()
	get_parent().resized.connect(_layout)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.15, 0.35, 0.95)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	tabs.add_child(_general_tab())
	tabs.add_child(_interface_tab())
	tabs.add_child(_audio_tab())
	tabs.add_child(_controls_tab())

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(close)
	box.add_child(back)


## Centred, shrinking to fit when the UI scale leaves little room.
func _layout() -> void:
	var avail: Vector2 = get_parent().size - Vector2(24, 24)
	var s := Vector2(minf(PANEL_SIZE.x, avail.x), minf(PANEL_SIZE.y, avail.y))
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -s.x / 2.0
	offset_right = s.x / 2.0
	offset_top = -s.y / 2.0
	offset_bottom = s.y / 2.0


func close() -> void:
	_listening = ""
	closed.emit()
	queue_free()


# ------------------------------------------------------------------ tabs

func _page(name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = name
	page.add_theme_constant_override("separation", 12)
	return page


## A labelled slider row; `fmt` turns the value into display text.
func _slider(parent: Control, label: String, key: String, lo: float, hi: float, step: float, fmt: Callable, live := true) -> HSlider:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(240, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(260, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := Label.new()
	v.text = fmt.call(s.value)
	v.custom_minimum_size = Vector2(90, 0)
	row.add_child(v)
	s.value_changed.connect(func(x):
		v.text = fmt.call(x)
		if live:
			Settings.set_value(key, x))
	if not live:
		# Apply when the drag ends (UI scale would otherwise move the slider under the mouse).
		s.drag_ended.connect(func(_changed): Settings.set_value(key, s.value))
	parent.add_child(row)
	return s


func _checkbox(parent: Control, label: String, key: String) -> void:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = bool(Settings.get_value(key))
	c.toggled.connect(func(on): Settings.set_value(key, on))
	parent.add_child(c)


func _general_tab() -> Control:
	var page := _page("General")
	_slider(page, "Mouse sensitivity", "mouse_sensitivity", 0.0005, 0.008, 0.0001, func(x): return "%d%%" % roundi(x / 0.0025 * 100.0))
	_checkbox(page, "Invert mouse Y", "invert_y")
	_checkbox(page, "Autofire (hold to keep using every item)", "autofire")
	_slider(page, "Field of view", "fov", 60.0, 110.0, 1.0, func(x): return "%d°" % int(x))
	_slider(page, "View distance", "render_distance", 3.0, 12.0, 1.0, func(x): return "%d chunks" % int(x))
	_slider(page, "Far view", "far_distance", 0.0, 64.0, 4.0, func(x): return "Off" if int(x) == 0 else "%d chunks" % int(x))
	return page


func _interface_tab() -> Control:
	var page := _page("Interface")
	_slider(page, "UI scale", "ui_scale", Settings.UI_SCALE_MIN, Settings.UI_SCALE_MAX, 0.05, func(x): return "%d%%" % roundi(x * 100.0), false)
	var hint := Label.new()
	hint.text = "Scales the hotbar, inventory, health and all menus."
	hint.add_theme_font_size_override("font_size", 18)
	hint.modulate = Color(1, 1, 1, 0.7)
	page.add_child(hint)
	var reset := Button.new()
	reset.text = "Reset UI scale to 100%"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func():
		Settings.set_value("ui_scale", 1.0)
		# Reflect the reset in the slider without re-applying it.
		for row in page.get_children():
			for c in row.get_children():
				if c is HSlider:
					c.set_value_no_signal(1.0))
	page.add_child(reset)
	_checkbox(page, "Enemy health bars", "enemy_health_bars")
	return page


func _audio_tab() -> Control:
	var page := _page("Audio")
	_slider(page, "Music volume", "music_volume", 0.0, 1.0, 0.01, func(x): return "%d%%" % roundi(x * 100.0))
	_slider(page, "Sound volume", "sfx_volume", 0.0, 1.0, 0.01, func(x): return "%d%%" % roundi(x * 100.0))
	return page


func _controls_tab() -> Control:
	var page := _page("Controls")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for a in Controls.ACTIONS:
		var l := Label.new()
		l.text = a[1]
		l.custom_minimum_size = Vector2(260, 0)
		grid.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(240, 0)
		b.pressed.connect(_start_listening.bind(a[0]))
		grid.add_child(b)
		_bind_buttons[a[0]] = b
	var fixed := Label.new()
	fixed.text = "Escape always opens the pause menu. Mouse wheel cycles the hotbar."
	fixed.add_theme_font_size_override("font_size", 18)
	fixed.modulate = Color(1, 1, 1, 0.7)
	page.add_child(fixed)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func():
		Controls.reset_defaults()
		_refresh_bindings())
	page.add_child(reset)
	_refresh_bindings()
	return page


func _refresh_bindings() -> void:
	for action in _bind_buttons:
		_bind_buttons[action].text = "Press a key... (Esc cancels)" if action == _listening else Controls.label(action)


func _start_listening(action: String) -> void:
	_listening = action
	_refresh_bindings()


## While waiting for a binding, the next key or mouse button press is captured
## before anything else sees it.
func _input(event: InputEvent) -> void:
	if _listening == "":
		return
	if event is InputEventKey and event.pressed and (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE):
		_listening = ""
		_refresh_bindings()
		get_viewport().set_input_as_handled()
	elif Controls.bindable(event):
		Controls.rebind(_listening, event)
		_listening = ""
		_refresh_bindings()
		get_viewport().set_input_as_handled()
