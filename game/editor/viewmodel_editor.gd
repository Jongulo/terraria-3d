extends Node3D
## Viewmodel editor: position held items in first person with Blender-style
## controls. Edits data/viewmodel.json (per item kind, optional per-item
## overrides, the hand position and swing settings). Run with ./viewmodel_editor.sh.
##
## Controls (mouse over the 3D view):
##   G / R / S        grab / rotate / scale (Tab switches target Item <-> Hand)
##   X / Y / Z        constrain axis (again: local axis, again: none)
##   type numbers     exact value, e.g. R X 90 Enter; - flips sign, Backspace edits
##   Ctrl / Shift     snap / precision while transforming
##   LMB / Enter      confirm         RMB / Esc   cancel
##   Alt+G/R/S        reset position / rotation / scale to the default
##   Ctrl+Z, Ctrl+Shift+Z   undo, redo        Ctrl+S   save
##   Space            preview the use animation (Shift+Space: slow motion)
##   MMB drag         orbit (Shift: pan), wheel zoom
##   Numpad 0 or `    first-person camera view;  Numpad 1/3/7 front/right/top (Ctrl: opposite),
##   Numpad 5         perspective/orthographic,  Numpad .  frame the item
##   PageUp/PageDown  previous / next item       F1   toggle help
##   T / N            toggle the item list / sidebar (like Blender's toolbar and N panel)

enum Mode { IDLE, GRAB, ROTATE, SCALE }

const SNAP_MOVE := 0.005
const SNAP_ROT := 5.0
const SNAP_SCALE := 0.05
const AXIS_COLORS := [Color(1.0, 0.25, 0.3), Color(0.45, 0.9, 0.2), Color(0.25, 0.5, 1.0)]
const AXIS_NAMES := ["X", "Y", "Z"]

## Overridable before the scene enters the tree (tests save elsewhere).
var config_path := Viewmodel.CONFIG_PATH

var player := Player.new()
var orbit_cam := Camera3D.new()
var camera_view := true
var mode := Mode.IDLE
var target := "item"  # "item" or "hand"
var axis := -1
var axis_local := false
var numeric := ""
var current_item := "CopperBroadsword"
var dirty := false
var mouse := Vector2.ZERO

var _start_mouse := Vector2.ZERO
var _start_grip := {}
var _start_hand := Vector3.ZERO
var _start_had_hand := false
var _start_pivot := Vector3.ZERO
var _start_item_basis := Basis()
var _undo: Array = []
var _redo: Array = []
var _orbit_target := Vector3.ZERO
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _orbit_dist := 1.0
var _orbiting := false
var _panning := false
var _gizmo := MeshInstance3D.new()
var _gizmo_mesh := ImmediateMesh.new()
var _gizmo_mat := StandardMaterial3D.new()

# UI
var _ui := Control.new()
var _header := Label.new()
var _status := Label.new()
var _help := PanelContainer.new()
var _search := LineEdit.new()
var _list := ItemList.new()
var _list_items: Array[String] = []
var _target_button := OptionButton.new()
var _override := CheckBox.new()
var _fields := {}
var _crosshair := Control.new()
var _left_panel: PanelContainer
var _right_panel: PanelContainer
var _message := ""
var _message_time := 0.0


func _ready() -> void:
	Viewmodel.editing = true
	Viewmodel.load_config(config_path)
	get_tree().auto_accept_quit = false
	_build_scene()
	_build_ui()
	_select_item(current_item)


# ------------------------------------------------------------------ scene

func _tile_texture(sheet: String, x: int, y: int) -> Texture2D:
	var img := Assets.image("Images/" + sheet).get_region(Rect2i(x, y, 16, 16))
	return ImageTexture.create_from_image(img)


func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.6, 0.98)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Grass ground and a few stone blocks for a sense of scale.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_texture = _tile_texture("Tiles_2", 144, 234)
	gm.uv1_scale = Vector3(40, 40, 1)
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ground.material_override = gm
	add_child(ground)
	var stone := StandardMaterial3D.new()
	stone.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stone.albedo_texture = _tile_texture("Tiles_1", 18, 18)
	stone.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	for p in [Vector3(-1.5, 0.5, -3.5), Vector3(-0.5, 0.5, -3.5), Vector3(-0.5, 1.5, -3.5), Vector3(1.5, 0.5, -4.5)]:
		var b := MeshInstance3D.new()
		b.mesh = BoxMesh.new()
		b.material_override = stone
		b.position = p
		add_child(b)

	add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.camera.make_current()
	player.viewmodel.set_light_rgb(Vector3.ONE)
	add_child(orbit_cam)
	orbit_cam.near = 0.01
	orbit_cam.far = 200.0

	_gizmo.mesh = _gizmo_mesh
	_gizmo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gizmo_mat.vertex_color_use_as_albedo = true
	_gizmo_mat.no_depth_test = true
	_gizmo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_gizmo_mat.render_priority = 100
	_gizmo.material_override = _gizmo_mat
	_gizmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_gizmo)


func _active_camera() -> Camera3D:
	return player.camera if camera_view else orbit_cam


# ------------------------------------------------------------------ UI

func _panel(rect: Rect2, anchor_right := false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.16, 0.88)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	if anchor_right:
		p.anchor_left = 1.0
		p.anchor_right = 1.0
		p.offset_left = -rect.size.x - rect.position.x
		p.offset_right = -rect.position.x
	else:
		p.offset_left = rect.position.x
		p.offset_right = rect.position.x + rect.size.x
	p.anchor_bottom = 1.0
	p.offset_top = rect.position.y
	p.offset_bottom = -12.0
	_ui.add_child(p)
	return p


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = Assets.font("Mouse_Text")
	theme.default_font_size = 20
	_ui.theme = theme
	layer.add_child(_ui)
	_fit_ui()
	get_viewport().size_changed.connect(_fit_ui)
	Settings.changed.connect(func(k):
		if k == "ui_scale":
			_fit_ui())

	_header.position = Vector2(300, 8)
	_header.add_theme_font_size_override("font_size", 22)
	_ui.add_child(_header)
	_status.position = Vector2(300, 36)
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_ui.add_child(_status)

	# Left: item list.
	var left := _panel(Rect2(12, 12, 270, 0))
	_left_panel = left
	var lbox := VBoxContainer.new()
	left.add_child(lbox)
	_search.placeholder_text = "Search items..."
	_search.text_changed.connect(func(_t): _fill_list())
	lbox.add_child(_search)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(24, 24)
	_list.item_selected.connect(func(i):
		_select_item(_list_items[i])
		get_viewport().gui_release_focus())
	lbox.add_child(_list)
	_fill_list()

	# Right: target, override, numeric fields, actions.
	var right := _panel(Rect2(12, 12, 300, 0), true)
	_right_panel = right
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 6)
	right.add_child(rbox)
	_target_button.add_item("Target: Item grip")
	_target_button.add_item("Target: Hand position")
	_target_button.item_selected.connect(func(i):
		_set_target("hand" if i == 1 else "item")
		get_viewport().gui_release_focus())
	rbox.add_child(_target_button)
	_override.text = "Override for this item only"
	_override.toggled.connect(_on_override_toggled)
	rbox.add_child(_override)
	for group in [["Position", ["px", "py", "pz"], 0.001, -2.0, 2.0], ["Rotation", ["rx", "ry", "rz"], 0.1, -360.0, 360.0]]:
		var l := Label.new()
		l.text = group[0]
		rbox.add_child(l)
		var row := HBoxContainer.new()
		for i in 3:
			row.add_child(_field(group[1][i], AXIS_NAMES[i], group[2], group[3], group[4]))
		rbox.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_child(_field("scale", "Scale", 0.01, 0.05, 5.0))
	row2.add_child(_field("swing", "Swing°", 1.0, -360.0, 360.0))
	rbox.add_child(row2)
	for b in [
			["Swing axis from current pose", _swing_axis_from_pose],
			["Flip swing direction", _flip_swing],
			["Preview animation (Space)", func(): _preview(false)],
			["Reset to default", _reset_all],
			["Revert to saved", _revert],
			["Save (Ctrl+S)", _save]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(func():
			b[1].call()
			get_viewport().gui_release_focus())
		rbox.add_child(btn)

	# Crosshair (camera view only).
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in [Rect2(-9, -1, 18, 2), Rect2(-1, -9, 2, 18)]:
		var bar := ColorRect.new()
		bar.color = Color(1, 1, 1, 0.8)
		bar.position = r.position
		bar.size = r.size
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crosshair.add_child(bar)
	_ui.add_child(_crosshair)

	# Help overlay.
	_help.anchor_left = 0.5
	_help.anchor_right = 0.5
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.offset_left = -260
	_help.offset_right = 260
	_help.offset_top = -262
	_help.offset_bottom = -12
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0, 0, 0, 0.65)
	hsb.set_content_margin_all(12)
	hsb.set_corner_radius_all(6)
	_help.add_theme_stylebox_override("panel", hsb)
	var ht := Label.new()
	ht.add_theme_font_size_override("font_size", 14)
	ht.text = "\n".join([
		"G grab   R rotate   S scale        Tab  target item / hand",
		"X Y Z  constrain axis (again = local, again = off)",
		"Type numbers for exact values (R X 90 Enter)   - flips sign",
		"Ctrl snap   Shift precision   LMB/Enter confirm   RMB/Esc cancel",
		"Alt+G / Alt+R / Alt+S  reset position / rotation / scale",
		"Ctrl+Z undo   Ctrl+Shift+Z redo   Ctrl+S save",
		"Space preview animation (Shift+Space slow motion)",
		"MMB orbit   Shift+MMB pan   wheel zoom",
		"Numpad 0 / `  camera view   Numpad 1 3 7  views   5 ortho   .  frame",
		"PageUp / PageDown  previous / next item",
		"T item list   N sidebar   F1 hide this help",
	])
	_help.add_child(ht)
	_ui.add_child(_help)


func _field(key: String, label: String, step: float, lo: float, hi: float) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 16)
	box.add_child(l)
	var sb := SpinBox.new()
	sb.step = step
	sb.min_value = lo
	sb.max_value = hi
	sb.allow_greater = true
	sb.allow_lesser = true
	sb.custom_arrow_step = step * 10.0
	sb.value_changed.connect(_on_field_changed.bind(key))
	box.add_child(sb)
	_fields[key] = sb
	return box


func _fill_list() -> void:
	_list.clear()
	_list_items.clear()
	var filter := _search.text.strip_edges().to_lower()
	var names: Array = Data.items.keys()
	names.sort_custom(func(a, b):
		var ka := Viewmodel.KINDS.find(Viewmodel.kind_of(Data.item(a)))
		var kb := Viewmodel.KINDS.find(Viewmodel.kind_of(Data.item(b)))
		return ka < kb if ka != kb else Data.item(a).name < Data.item(b).name)
	for n in names:
		var def := Data.item(n)
		if filter != "" and not def.name.to_lower().contains(filter):
			continue
		var idx := _list.add_item("%s  (%s)" % [def.name, Viewmodel.kind_of(def)], Assets.item_texture(def.id))
		_list.set_item_metadata(idx, n)
		_list_items.append(n)
		if n == current_item:
			_list.select(idx)


## Follows the game's UI scale, capped so the side panels never take more than
## about 40% of the window.
func _fit_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := clampf(float(Settings.get_value("ui_scale")), 0.5, maxf(0.5, vp.x / 1450.0))
	_ui.position = Vector2.ZERO
	_ui.scale = Vector2(s, s)
	_ui.size = vp / s


# ------------------------------------------------------------------ editing model

func _kind() -> String:
	return Viewmodel.kind_of(Data.item(current_item))


## The grip Dictionary the current item uses, inside Viewmodel.config (created
## from the defaults on first edit).
func _grip_ref() -> Dictionary:
	if Viewmodel.config.items.has(current_item):
		return Viewmodel.config.items[current_item]
	var kind := _kind()
	if not Viewmodel.config.kinds.has(kind):
		Viewmodel.config.kinds[kind] = Viewmodel.default_grip(kind)
	return Viewmodel.config.kinds[kind]


func _set_hand(p: Vector3) -> void:
	Viewmodel.config["hand"] = Viewmodel.round_vec(p, 0.0001)


func _snapshot() -> void:
	_undo.append(Viewmodel.config.duplicate(true))
	if _undo.size() > 200:
		_undo.pop_front()
	_redo.clear()


func _changed() -> void:
	dirty = true
	player.viewmodel.refresh_pose()
	_sync_fields()


func _undo_step() -> void:
	if _undo.is_empty():
		return
	_redo.append(Viewmodel.config.duplicate(true))
	Viewmodel.config = _undo.pop_back()
	_changed()
	_flash("Undo")


func _redo_step() -> void:
	if _redo.is_empty():
		return
	_undo.append(Viewmodel.config.duplicate(true))
	Viewmodel.config = _redo.pop_back()
	_changed()
	_flash("Redo")


func _select_item(item: String) -> void:
	if mode != Mode.IDLE:
		_cancel()
	current_item = item
	player.inventory.slots[0] = Inventory.stack(item, 1)
	player.selected = 0
	_sync_fields()


func _set_target(t: String) -> void:
	target = t
	_target_button.select(1 if t == "hand" else 0)


func _sync_fields() -> void:
	var g := Viewmodel.grip_for(current_item)
	var pos: Array = g.position
	var rot: Array = g.rotation
	var vals := {"px": pos[0], "py": pos[1], "pz": pos[2], "rx": rot[0], "ry": rot[1], "rz": rot[2],
			"scale": g.get("scale", 1.0), "swing": g.get("swing_angle", -60.0)}
	for k in vals:
		_fields[k].set_value_no_signal(float(vals[k]))
	_override.set_pressed_no_signal(Viewmodel.config.items.has(current_item))


func _on_field_changed(value: float, key: String) -> void:
	_snapshot()
	var g := _grip_ref()
	match key:
		"px", "py", "pz":
			g.position[["px", "py", "pz"].find(key)] = value
		"rx", "ry", "rz":
			g.rotation[["rx", "ry", "rz"].find(key)] = value
		"scale":
			g.scale = value
		"swing":
			g.swing_angle = value
	_changed()


func _on_override_toggled(on: bool) -> void:
	_snapshot()
	if on:
		Viewmodel.config.items[current_item] = Viewmodel.grip_for(current_item).duplicate(true)
		_flash("Editing an override for %s only" % Data.item(current_item).name)
	else:
		Viewmodel.config.items.erase(current_item)
		_flash("%s uses the %s pose again" % [Data.item(current_item).name, _kind()])
	_changed()


func _swing_axis_from_pose() -> void:
	_snapshot()
	var g := _grip_ref()
	var z := Basis.from_euler(Viewmodel.vec(g.rotation) * (PI / 180.0)).z.normalized()
	g.swing_axis = Viewmodel.round_vec(z, 0.0001)
	_changed()
	_flash("Swing axis set to the item's face normal")


func _flip_swing() -> void:
	_snapshot()
	var g := _grip_ref()
	g.swing_angle = -float(g.get("swing_angle", 0.0))
	_changed()


func _reset_all() -> void:
	_snapshot()
	if target == "hand":
		Viewmodel.config.erase("hand")
	else:
		var d := Viewmodel.default_grip(_kind())
		var g := _grip_ref()
		for k in d:
			g[k] = d[k]
	_changed()
	_flash("Reset to default")


func _reset_part(part: String) -> void:
	_snapshot()
	if target == "hand":
		if part == "position":
			Viewmodel.config.erase("hand")
	else:
		var d := Viewmodel.default_grip(_kind())
		var g := _grip_ref()
		match part:
			"position": g.position = d.position
			"rotation": g.rotation = d.rotation
			"scale": g.scale = 1.0
	_changed()
	_flash("Cleared " + part)


func _revert() -> void:
	Viewmodel.load_config(config_path)
	_undo.clear()
	_redo.clear()
	dirty = false
	_changed()
	dirty = false
	_flash("Reverted to the saved file")


func _save() -> void:
	if Viewmodel.save_config(config_path):
		dirty = false
		_flash("Saved " + config_path)
	else:
		_flash("Could not save " + config_path)


func _preview(slow: bool) -> void:
	var def := Data.item(current_item)
	var duration := float(def.get("use_time", 20)) / 60.0
	player.viewmodel.play(Viewmodel.use_style(def), duration * (4.0 if slow else 1.0))


func _flash(text: String) -> void:
	_message = text
	_message_time = 3.0


# ------------------------------------------------------------------ transforms

func _pivot_world() -> Vector3:
	var node: Node3D = player.viewmodel.hand_node() if target == "hand" else player.viewmodel.item_node()
	return node.global_position


## Constraint axis in world space: global = first-person camera axes, local =
## the item's own axes.
func _axis_world(i: int) -> Vector3:
	if axis_local and target == "item":
		return _start_item_basis[i].normalized()
	return player.camera.global_transform.basis[i].normalized()


func _begin(m: Mode) -> void:
	if target == "hand" and m != Mode.GRAB:
		_flash("The hand only has a position; use G")
		return
	player.viewmodel.stop_animation()
	player.viewmodel._process(0.0)
	_snapshot()
	mode = m
	axis = -1
	axis_local = false
	numeric = ""
	_start_mouse = mouse
	_start_grip = _grip_ref().duplicate(true)
	_start_hand = Viewmodel.hand_position()
	_start_had_hand = Viewmodel.config.has("hand")
	_start_pivot = _pivot_world()
	_start_item_basis = player.viewmodel.item_node().global_transform.basis.orthonormalized()


## Puts the edited values back to where the current transform started.
func _restore_start() -> void:
	var g := _grip_ref()
	for k in _start_grip:
		g[k] = _start_grip[k].duplicate(true) if _start_grip[k] is Array else _start_grip[k]
	if target == "hand":
		if _start_had_hand:
			_set_hand(_start_hand)
		else:
			Viewmodel.config.erase("hand")


func _confirm() -> void:
	mode = Mode.IDLE
	axis = -1
	numeric = ""
	_changed()


func _cancel() -> void:
	_restore_start()
	if not _undo.is_empty():
		_undo.pop_back()
	mode = Mode.IDLE
	axis = -1
	numeric = ""
	player.viewmodel.refresh_pose()
	_sync_fields()


func _numeric_value() -> float:
	var t := numeric
	if t == "" or t == "-" or t == "." or t == "-.":
		return 0.0
	return float(t)


func _update_transform() -> void:
	if mode == Mode.IDLE:
		return
	var cam := _active_camera()
	var precise := Input.is_key_pressed(KEY_SHIFT)
	var snap := Input.is_key_pressed(KEY_CTRL)
	var cam_basis_inv := player.camera.global_transform.basis.orthonormalized().inverse()
	var pivot_screen := cam.unproject_position(_start_pivot)
	var m := (mouse - _start_mouse) * (0.1 if precise else 1.0)
	_restore_start()
	var g := _grip_ref()
	match mode:
		Mode.GRAB:
			var d := Vector3.ZERO
			if numeric != "":
				d = _axis_world(maxi(axis, 0)) * _numeric_value()
			elif axis >= 0:
				var a := _axis_world(axis)
				var s := cam.unproject_position(_start_pivot + a) - pivot_screen
				d = a * (m.dot(s) / maxf(s.length_squared(), 1.0))
			else:
				var cb := cam.global_transform.basis
				var upp: float
				if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
					upp = cam.size / get_viewport().get_visible_rect().size.y
				else:
					var depth := maxf(0.05, -(cb.inverse() * (_start_pivot - cam.global_position)).z)
					upp = 2.0 * depth * tan(deg_to_rad(cam.fov) * 0.5) / get_viewport().get_visible_rect().size.y
				d = (cb.x * m.x - cb.y * m.y) * upp
			var local := cam_basis_inv * d
			if target == "hand":
				var hp := _start_hand + local
				if snap:
					hp = hp.snappedf(SNAP_MOVE)
				_set_hand(hp)
			else:
				var p := Viewmodel.vec(_start_grip.position) + local
				if snap:
					p = p.snappedf(SNAP_MOVE)
				g.position = Viewmodel.round_vec(p, 0.0001)
		Mode.ROTATE:
			var angle: float
			var a: Vector3
			if axis >= 0:
				a = _axis_world(axis)
			else:
				a = cam.global_transform.basis.z  # view axis, toward the viewer
			if numeric != "":
				angle = deg_to_rad(_numeric_value())
			else:
				var v0 := _start_mouse - pivot_screen
				var v1 := mouse - pivot_screen
				# Screen y points down; measure counter-clockwise angles.
				angle = atan2(-v1.y, v1.x) - atan2(-v0.y, v0.x)
				angle = wrapf(angle, -PI, PI) * (0.1 if precise else 1.0)
				# Counter-clockwise on screen matches the axis pointing at the viewer.
				if a.dot(cam.global_transform.basis.z) < 0.0:
					angle = -angle
			if snap:
				angle = deg_to_rad(snappedf(rad_to_deg(angle), SNAP_ROT))
			var r := Basis.from_euler(Viewmodel.vec(_start_grip.rotation) * (PI / 180.0))
			var a_local := (cam_basis_inv * a).normalized()
			var e := (Basis(a_local, angle) * r).orthonormalized().get_euler()
			g.rotation = Viewmodel.round_vec(e * (180.0 / PI), 0.001)
		Mode.SCALE:
			var f: float
			if numeric != "":
				f = _numeric_value()
			else:
				var d0 := maxf((_start_mouse - pivot_screen).length(), 1.0)
				f = (mouse - pivot_screen).length() / d0
				if precise:
					f = 1.0 + (f - 1.0) * 0.1
			var sc := float(_start_grip.get("scale", 1.0)) * f
			if snap:
				sc = snappedf(sc, SNAP_SCALE)
			g.scale = snappedf(maxf(sc, 0.01), 0.0001)
	player.viewmodel.refresh_pose()
	_sync_fields()


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	# Track the cursor everywhere (transforms keep following it over the panels).
	if event is InputEventMouse:
		mouse = event.position
		if mode != Mode.IDLE and event is InputEventMouseMotion:
			_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event)
	elif event is InputEventKey and event.pressed:
		if mode != Mode.IDLE:
			_transform_key(event)
		else:
			_idle_key(event)


func _on_mouse_button(e: InputEventMouseButton) -> void:
	if e.pressed:
		get_viewport().gui_release_focus()
	if mode != Mode.IDLE:
		if e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_confirm()
		elif e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			_cancel()
		return
	match e.button_index:
		MOUSE_BUTTON_MIDDLE:
			if e.pressed and camera_view:
				_enter_orbit()
			_orbiting = e.pressed and not e.shift_pressed
			_panning = e.pressed and e.shift_pressed
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				_zoom(0.88)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_zoom(1.0 / 0.88)


func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	if _orbiting:
		_orbit_yaw -= e.relative.x * 0.008
		_orbit_pitch = clampf(_orbit_pitch - e.relative.y * 0.008, -1.5, 1.5)
		_update_orbit()
	elif _panning:
		var b := orbit_cam.global_transform.basis
		var k := _orbit_dist * 0.0016
		_orbit_target += (-b.x * e.relative.x + b.y * e.relative.y) * k
		_update_orbit()


func _transform_key(e: InputEventKey) -> void:
	var k := e.keycode
	match k:
		KEY_ESCAPE:
			_cancel()
			return
		KEY_ENTER, KEY_KP_ENTER:
			_confirm()
			return
		KEY_X, KEY_Y, KEY_Z:
			var i := [KEY_X, KEY_Y, KEY_Z].find(k)
			if axis == i and not axis_local and target == "item":
				axis_local = true
			elif axis == i:
				axis = -1
				axis_local = false
			else:
				axis = i
				axis_local = false
		KEY_G, KEY_R, KEY_S:
			# Switch transform type mid-way, like Blender.
			var m: Mode = {KEY_G: Mode.GRAB, KEY_R: Mode.ROTATE, KEY_S: Mode.SCALE}[k]
			if m != mode and not (target == "hand" and m != Mode.GRAB):
				_restore_start()
				mode = m
				numeric = ""
		KEY_BACKSPACE:
			numeric = numeric.substr(0, numeric.length() - 1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			numeric = numeric.substr(1) if numeric.begins_with("-") else "-" + numeric
		KEY_PERIOD, KEY_KP_PERIOD:
			if not numeric.contains("."):
				numeric += "."
		_:
			var digit := -1
			if k >= KEY_0 and k <= KEY_9:
				digit = k - KEY_0
			elif k >= KEY_KP_0 and k <= KEY_KP_9:
				digit = k - KEY_KP_0
			if digit >= 0:
				numeric += str(digit)
	_update_transform()
	get_viewport().set_input_as_handled()


func _idle_key(e: InputEventKey) -> void:
	var k := e.keycode
	if e.ctrl_pressed:
		match k:
			KEY_Z:
				_redo_step() if e.shift_pressed else _undo_step()
			KEY_Y:
				_redo_step()
			KEY_S:
				_save()
		return
	if e.alt_pressed:
		match k:
			KEY_G: _reset_part("position")
			KEY_R: _reset_part("rotation")
			KEY_S: _reset_part("scale")
		return
	match k:
		KEY_G: _begin(Mode.GRAB)
		KEY_R: _begin(Mode.ROTATE)
		KEY_S: _begin(Mode.SCALE)
		KEY_TAB: _set_target("item" if target == "hand" else "hand")
		KEY_SPACE: _preview(e.shift_pressed)
		KEY_F1: _help.visible = not _help.visible
		KEY_T: _left_panel.visible = not _left_panel.visible
		KEY_N: _right_panel.visible = not _right_panel.visible
		KEY_QUOTELEFT, KEY_KP_0: _set_camera_view(true)
		KEY_KP_1: _view_preset(Vector2(0.0, 0.0), e.ctrl_pressed)
		KEY_KP_3: _view_preset(Vector2(PI / 2.0, 0.0), e.ctrl_pressed)
		KEY_KP_7: _view_preset(Vector2(0.0, PI / 2.0 - 0.001), e.ctrl_pressed)
		KEY_KP_5:
			orbit_cam.projection = Camera3D.PROJECTION_PERSPECTIVE if orbit_cam.projection == Camera3D.PROJECTION_ORTHOGONAL else Camera3D.PROJECTION_ORTHOGONAL
			_update_orbit()
		KEY_KP_PERIOD:
			_orbit_target = _pivot_world()
			_update_orbit()
		KEY_PAGEUP: _step_item(-1)
		KEY_PAGEDOWN: _step_item(1)
		_:
			return
	get_viewport().set_input_as_handled()


func _step_item(d: int) -> void:
	if _list_items.is_empty():
		return
	var i := wrapi(_list_items.find(current_item) + d, 0, _list_items.size())
	_list.select(i)
	_list.ensure_current_is_visible()
	_select_item(_list_items[i])


# ------------------------------------------------------------------ views

func _set_camera_view(on: bool) -> void:
	camera_view = on
	_active_camera().make_current()


func _enter_orbit() -> void:
	# Start from the first-person viewpoint, orbiting around the item.
	_orbit_target = _pivot_world()
	var from := player.camera.global_position - _orbit_target
	_orbit_dist = maxf(from.length(), 0.3)
	_orbit_yaw = atan2(from.x, from.z)
	_orbit_pitch = asin(clampf(from.y / _orbit_dist, -1.0, 1.0))
	_update_orbit()
	_set_camera_view(false)


func _view_preset(yaw_pitch: Vector2, opposite: bool) -> void:
	if camera_view:
		_enter_orbit()
	_orbit_yaw = yaw_pitch.x + (PI if opposite else 0.0)
	_orbit_pitch = -yaw_pitch.y if opposite and yaw_pitch.y != 0.0 else yaw_pitch.y
	_update_orbit()


func _zoom(f: float) -> void:
	if camera_view:
		return
	_orbit_dist = clampf(_orbit_dist * f, 0.1, 20.0)
	_update_orbit()


func _update_orbit() -> void:
	var dir := Vector3(sin(_orbit_yaw) * cos(_orbit_pitch), sin(_orbit_pitch), cos(_orbit_yaw) * cos(_orbit_pitch))
	orbit_cam.global_position = _orbit_target + dir * _orbit_dist
	var up := Vector3.UP if absf(_orbit_pitch) < 1.49 else Vector3.FORWARD
	orbit_cam.look_at(_orbit_target, up)
	orbit_cam.size = _orbit_dist * 1.2


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	_message_time -= delta
	_crosshair.visible = camera_view
	_draw_gizmo()
	_header.text = "%s  ·  %s pose%s  ·  target: %s  ·  %s view%s" % [
		Data.item(current_item).name, _kind(),
		" (item override)" if Viewmodel.config.items.has(current_item) else "",
		"hand" if target == "hand" else "item grip",
		"camera" if camera_view else ("ortho" if orbit_cam.projection == Camera3D.PROJECTION_ORTHOGONAL else "orbit"),
		"   ●  unsaved" if dirty else ""]
	_status.text = _status_text()


func _status_text() -> String:
	if mode == Mode.IDLE:
		return _message if _message_time > 0.0 else "G grab · R rotate · S scale · Tab target · Space preview · F1 help"
	var name: String = {Mode.GRAB: "Grab", Mode.ROTATE: "Rotate", Mode.SCALE: "Scale"}[mode]
	var parts: Array[String] = [name]
	if axis >= 0:
		parts.append("along %s%s" % [AXIS_NAMES[axis], " (local)" if axis_local else ""])
	var g := _grip_ref()
	match mode:
		Mode.GRAB:
			var p := Viewmodel.hand_position() if target == "hand" else Viewmodel.vec(g.position)
			var s := p - (_start_hand if target == "hand" else Viewmodel.vec(_start_grip.position))
			parts.append("Δ %.3f %.3f %.3f m" % [s.x, s.y, s.z])
		Mode.ROTATE:
			parts.append("rotation %.1f° %.1f° %.1f°" % [g.rotation[0], g.rotation[1], g.rotation[2]])
		Mode.SCALE:
			parts.append("scale %.3f" % g.scale)
	if numeric != "":
		parts.append("[%s]" % numeric)
	parts.append("Ctrl snap · Shift precise · LMB/Enter ok · RMB/Esc cancel")
	return "   ".join(parts)


func _draw_gizmo() -> void:
	_gizmo_mesh.clear_surfaces()
	var lines: Array = []  # [from, to, color]
	var pivot := _pivot_world() if mode == Mode.IDLE else _start_pivot
	if mode != Mode.IDLE and axis >= 0:
		var a := _axis_world(axis)
		var c: Color = AXIS_COLORS[axis]
		if axis_local:
			c = c.lightened(0.4)
		lines.append([pivot - a * 4.0, pivot + a * 4.0, c])
	# Pivot marker.
	var k := 0.015 if camera_view else _orbit_dist * 0.02
	for i in 3:
		var a := player.camera.global_transform.basis[i]
		var c: Color = AXIS_COLORS[i]
		lines.append([pivot - a * k, pivot + a * k, Color(c, 0.9)])
	if not camera_view:
		# The first-person camera: a small frustum.
		var cam := player.camera
		var b := cam.global_transform.basis
		var o := cam.global_position
		var depth := 0.25
		var hy := tan(deg_to_rad(cam.fov) * 0.5) * depth
		var vp := get_viewport().get_visible_rect().size
		var hx := hy * vp.x / vp.y
		var corners := []
		for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			corners.append(o - b.z * depth + b.x * hx * s.x + b.y * hy * s.y)
		var fc := Color(1, 1, 1, 0.7)
		for i in 4:
			lines.append([o, corners[i], fc])
			lines.append([corners[i], corners[(i + 1) % 4], fc])
	if lines.is_empty():
		return
	_gizmo_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for l in lines:
		_gizmo_mesh.surface_set_color(l[2])
		_gizmo_mesh.surface_add_vertex(l[0])
		_gizmo_mesh.surface_set_color(l[2])
		_gizmo_mesh.surface_add_vertex(l[1])
	_gizmo_mesh.surface_end()


# ------------------------------------------------------------------ quitting

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not dirty:
			get_tree().quit()
			return
		var dlg := ConfirmationDialog.new()
		dlg.title = "Unsaved changes"
		dlg.dialog_text = "Save the viewmodel poses before quitting?"
		dlg.ok_button_text = "Save and quit"
		dlg.add_button("Quit without saving", true, "discard")
		dlg.confirmed.connect(func():
			_save()
			get_tree().quit())
		dlg.custom_action.connect(func(action):
			if action == "discard":
				get_tree().quit())
		add_child(dlg)
		dlg.popup_centered()
