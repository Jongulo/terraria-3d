extends Node
## Rebindable input actions. Each action has one binding (a key or mouse button);
## changes are stored in Settings under "bindings". Escape is reserved for menus.

## [action, label, default] where default is {"key": physical keycode} or {"mouse": button}.
const ACTIONS := [
	["move_forward", "Move forward", {"key": KEY_W}],
	["move_back", "Move back", {"key": KEY_S}],
	["move_left", "Move left", {"key": KEY_A}],
	["move_right", "Move right", {"key": KEY_D}],
	["jump", "Jump", {"key": KEY_SPACE}],
	["drop_down", "Drop through platforms", {"key": KEY_SHIFT}],
	["use_item", "Use item", {"mouse": MOUSE_BUTTON_LEFT}],
	["interact", "Interact", {"mouse": MOUSE_BUTTON_RIGHT}],
	["inventory", "Inventory", {"key": KEY_TAB}],
	["quick_heal", "Quick heal", {"key": KEY_H}],
	["throw_item", "Throw item", {"key": KEY_T}],
	["grapple", "Grapple", {"key": KEY_E}],
	["screenshot", "Screenshot", {"key": KEY_F12}],
	["pick_block", "Pick block (creative)", {"mouse": MOUSE_BUTTON_MIDDLE}],
	["hotbar_1", "Hotbar 1", {"key": KEY_1}],
	["hotbar_2", "Hotbar 2", {"key": KEY_2}],
	["hotbar_3", "Hotbar 3", {"key": KEY_3}],
	["hotbar_4", "Hotbar 4", {"key": KEY_4}],
	["hotbar_5", "Hotbar 5", {"key": KEY_5}],
	["hotbar_6", "Hotbar 6", {"key": KEY_6}],
	["hotbar_7", "Hotbar 7", {"key": KEY_7}],
	["hotbar_8", "Hotbar 8", {"key": KEY_8}],
	["hotbar_9", "Hotbar 9", {"key": KEY_9}],
	["hotbar_10", "Hotbar 10", {"key": KEY_0}],
]
const PAUSE := "pause"


func _ready() -> void:
	_ensure_action(PAUSE)
	InputMap.action_erase_events(PAUSE)
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	InputMap.action_add_event(PAUSE, esc)
	var saved: Dictionary = Settings.get_value("bindings")
	for a in ACTIONS:
		_ensure_action(a[0])
		_set_event(a[0], _event_from(saved.get(a[0], a[2])))


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _set_event(action: String, ev: InputEvent) -> void:
	InputMap.action_erase_events(action)
	if ev:
		InputMap.action_add_event(action, ev)


func _event_from(d: Dictionary) -> InputEvent:
	if d.has("key"):
		var k := InputEventKey.new()
		k.physical_keycode = int(d.key)
		return k
	if d.has("mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = int(d.mouse)
		return m
	return null


func _to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"key": ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode}
	if ev is InputEventMouseButton:
		return {"mouse": ev.button_index}
	return {}


func binding(action: String) -> Dictionary:
	var events := InputMap.action_get_events(action)
	return {} if events.is_empty() else _to_dict(events[0])


## True for events that can be bound (keys other than Escape, mouse buttons except the wheel).
func bindable(ev: InputEvent) -> bool:
	if ev is InputEventKey:
		return ev.pressed and not ev.echo and ev.physical_keycode != KEY_ESCAPE and ev.keycode != KEY_ESCAPE
	if ev is InputEventMouseButton:
		return ev.pressed and ev.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
	return false


## Binds `ev` to `action`. If another action already uses it, the two swap bindings.
func rebind(action: String, ev: InputEvent) -> void:
	var new_binding := _to_dict(ev)
	var old_binding := binding(action)
	for a in ACTIONS:
		if a[0] != action and binding(a[0]) == new_binding:
			_set_event(a[0], _event_from(old_binding))
	_set_event(action, _event_from(new_binding))
	_save()


func reset_defaults() -> void:
	for a in ACTIONS:
		_set_event(a[0], _event_from(a[2]))
	_save()


func _save() -> void:
	var out := {}
	for a in ACTIONS:
		out[a[0]] = binding(a[0])
	Settings.set_value("bindings", out)


## Human-readable binding, e.g. "W", "Space", "Left Mouse".
func label(action: String) -> String:
	var b := binding(action)
	if b.has("key"):
		var keycode := DisplayServer.keyboard_get_keycode_from_physical(int(b.key))
		return OS.get_keycode_string(keycode if keycode != KEY_NONE else int(b.key))
	if b.has("mouse"):
		match int(b.mouse):
			MOUSE_BUTTON_LEFT: return "Left Mouse"
			MOUSE_BUTTON_RIGHT: return "Right Mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
			_: return "Mouse %d" % int(b.mouse)
	return "Unbound"
