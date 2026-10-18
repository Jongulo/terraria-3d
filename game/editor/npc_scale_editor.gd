extends Node3D
## NPC scale editor: how big each enemy, boss and town NPC appears in the
## game. Shows the NPC as the game draws it (NPC.look), animated, on a grid of
## blocks next to the player (1.8 m) and a block for comparison, with its
## hitbox as a wire box. Saves data/npc_scales.json (Data.npc_scales), which
## the game reads at start-up. Run with ./npc_scale_editor.sh.
##
## Wheel: zoom · drag (LMB/MMB/RMB): orbit · F: frame · PageUp/PageDown:
## previous / next NPC · Space: pause the animation · Ctrl+S: save · F1: help.

const SCALE_MIN := 0.25
const SCALE_MAX := 4.0
const PLAYER_HEIGHT := 1.8
const SKY := Color(0.42, 0.61, 0.95)
const GRID_RADIUS := 8
const ANIM_FPS := 8.0

## Overridable before entering the tree (tests save elsewhere).
var save_path := Data.NPC_SCALES_PATH
var current := ""
var dirty := false
var animate := true

var _kinds: Array = []  # every NPC kind, sorted by name
var _shown: Array = []  # the kinds the list shows (search)
var _cam := Camera3D.new()
var _yaw := 0.6
var _pitch := -0.15
var _dist := 6.0
var _focus := Vector3(0, 1, 0)
var _dragging := false
var _npc := EntitySprite.new()
var _npc_node := Node3D.new()
var _hitbox := MeshInstance3D.new()
var _player := Sprite3D.new()
var _block := MeshInstance3D.new()
var _anim := 0.0
var _syncing := false

var _ui := Control.new()
var _left := PanelContainer.new()
var _right := PanelContainer.new()
var _search := LineEdit.new()
var _list := ItemList.new()
var _title := Label.new()
var _scale := HSlider.new()
var _scale_box := SpinBox.new()
var _hitbox_check := CheckBox.new()
var _info := Label.new()
var _status := Label.new()
var _help := PanelContainer.new()
var _message_time := 0.0


func _ready() -> void:
	get_tree().auto_accept_quit = false
	Data.load_npc_scales(save_path)
	_kinds = Data.npcs.keys()
	_kinds.sort_custom(func(a, b): return Assets.npc_name(a) < Assets.npc_name(b))
	_build_scene()
	_build_ui()
	_fill_list()
	select(_kinds[0] if not _kinds.has("Zombie") else "Zombie")


# ------------------------------------------------------------------ scene

func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_cam.fov = 50.0
	_cam.current = true
	add_child(_cam)
	# The ground: a grass floor with a line round every block.
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GRID_RADIUS * 2, GRID_RADIUS * 2)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(0.2, 0.55, 0.25)
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	var grid := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-GRID_RADIUS, GRID_RADIUS + 1):
		im.surface_add_vertex(Vector3(i, 0.002, -GRID_RADIUS))
		im.surface_add_vertex(Vector3(i, 0.002, GRID_RADIUS))
		im.surface_add_vertex(Vector3(-GRID_RADIUS, 0.002, i))
		im.surface_add_vertex(Vector3(GRID_RADIUS, 0.002, i))
	im.surface_end()
	grid.mesh = im
	grid.material_override = _line_material(Color(0.1, 0.35, 0.15))
	add_child(grid)
	# One block, for scale.
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_block.mesh = box
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_texture = _block_texture()
	bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_block.material_override = bm
	add_child(_block)
	# You, as Terraria draws you (PaperDoll), 1.8 m tall.
	_player.texture = _player_texture()
	_player.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_player.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_player.shaded = false
	_player.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	add_child(_player)
	add_child(_npc_node)
	_npc_node.add_child(_npc)
	_hitbox.material_override = _line_material(Color(1.0, 0.9, 0.3))
	_npc_node.add_child(_hitbox)


func _line_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


## A dirt block's face from Terraria's tiles.
func _block_texture() -> Texture2D:
	var sheet := Assets.image("Images/Tiles_0")
	var img := sheet.get_region(Rect2i(18, 18, 16, 16))
	return ImageTexture.create_from_image(img)


## The player standing, from Terraria's player sprites (PaperDoll), cropped to
## the figure; its pixel size makes it 1.8 m tall.
func _player_texture() -> Texture2D:
	_player.pixel_size = PaperDoll.player_pixel_size()
	return ImageTexture.create_from_image(PaperDoll.standing_image())


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var theme := Theme.new()
	theme.default_font = Assets.font("Mouse_Text")
	theme.default_font_size = 20
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.9))
	theme.set_constant("shadow_offset_x", "Label", 2)
	theme.set_constant("shadow_offset_y", "Label", 2)
	_ui.theme = theme
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	_fit_ui()
	get_viewport().size_changed.connect(_fit_ui)

	# Left: every NPC, searchable.
	var left := _panel(_left)
	left.offset_left = 12
	left.offset_top = 12
	left.offset_right = 300
	left.anchor_bottom = 1.0
	left.offset_bottom = -100
	_ui.add_child(left)
	var box := VBoxContainer.new()
	left.add_child(box)
	box.add_child(_label("NPCs"))
	_search.placeholder_text = "Search"
	_search.text_changed.connect(func(_t): _fill_list())
	box.add_child(_search)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i):
		select(_shown[i])
		get_viewport().gui_release_focus())
	box.add_child(_list)

	# Right: the selected NPC's size.
	var right := _panel(_right)
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -360
	right.offset_right = -12
	right.offset_top = 12
	_ui.add_child(right)
	var r := VBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	right.add_child(r)
	_title.add_theme_font_size_override("font_size", 24)
	r.add_child(_title)
	r.add_child(_section("Scale"))
	_scale.min_value = SCALE_MIN
	_scale.max_value = SCALE_MAX
	_scale.step = 0.01
	_scale.custom_minimum_size.x = 320
	_scale.value_changed.connect(func(v):
		if not _syncing:
			set_size_scale(v))
	r.add_child(_scale)
	var row := HBoxContainer.new()
	_scale_box.min_value = SCALE_MIN
	_scale_box.max_value = SCALE_MAX
	_scale_box.step = 0.01
	_scale_box.suffix = "x"
	_scale_box.value_changed.connect(func(v):
		if not _syncing:
			set_size_scale(v))
	row.add_child(_scale_box)
	for preset in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]:
		var b := Button.new()
		b.text = "%sx" % str(preset)
		b.pressed.connect(set_size_scale.bind(preset))
		row.add_child(b)
	r.add_child(row)
	_hitbox_check.text = "Hitbox scales too"
	_hitbox_check.tooltip_text = "On: it's hit (and touches you) where it looks. Off: only the sprite changes size."
	_hitbox_check.toggled.connect(func(on):
		if not _syncing:
			set_hitbox_scales(on))
	r.add_child(_hitbox_check)
	_info.add_theme_font_size_override("font_size", 17)
	r.add_child(_info)
	# Pixels the size of the player's, like Terraria's (everything on one grid).
	r.add_child(_section("Pixel size"))
	var match_row := HBoxContainer.new()
	var match_one := Button.new()
	match_one.text = "Match player pixels"
	match_one.tooltip_text = "Scale this NPC so one pixel of its sprite is as big as one of the player's"
	match_one.pressed.connect(func(): match_player_pixels(current))
	match_row.add_child(match_one)
	var match_all := Button.new()
	match_all.text = "Match all NPCs"
	match_all.tooltip_text = "Do that for every NPC (Revert to saved undoes it)"
	match_all.pressed.connect(match_all_player_pixels)
	match_row.add_child(match_all)
	r.add_child(match_row)
	var buttons := HBoxContainer.new()
	for b in [["Reset", func(): set_size_scale(1.0)], ["Revert to saved", _revert], ["Save (Ctrl+S)", save]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		buttons.add_child(btn)
	r.add_child(buttons)
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_status.add_theme_font_size_override("font_size", 16)
	r.add_child(_status)

	_help.anchor_left = 0.5
	_help.anchor_right = 0.5
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.offset_left = -330
	_help.offset_right = 330
	_help.offset_top = -80
	_help.offset_bottom = -12
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0, 0, 0, 0.6)
	hsb.set_content_margin_all(10)
	hsb.set_corner_radius_all(6)
	_help.add_theme_stylebox_override("panel", hsb)
	var ht := Label.new()
	ht.add_theme_font_size_override("font_size", 15)
	ht.text = "Drag: orbit   ·   Wheel: zoom   ·   F: frame   ·   PageUp/PageDown: NPC   ·   Space: pause\nYellow box: hitbox   ·   Beside it: you (1.8 m) and one block   ·   Ctrl+S: save   ·   F1: hide this"
	_help.add_child(ht)
	_ui.add_child(_help)


func _panel(p: PanelContainer) -> PanelContainer:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.16, 0.88)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	return p


## The UI at the player's UI scale, but no bigger than leaves room for the
## preview (like the sprite editor's).
func _fit_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var sc := clampf(float(Settings.get_value("ui_scale")), 0.5, maxf(0.5, vp.x / 1500.0))
	_ui.scale = Vector2(sc, sc)
	_ui.size = vp / sc
	_update_camera()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _section(text: String) -> Label:
	var l := _label(text)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	return l


## The list: NPCs matching the search, scaled ones marked with their scale.
func _fill_list() -> void:
	_list.clear()
	_shown.clear()
	var q := _search.text.strip_edges().to_lower()
	for k in _kinds:
		var label: String = "%s (%s)" % [Assets.npc_name(k), k] if Assets.npc_name(k) != k else k
		if q != "" and not q in label.to_lower():
			continue
		var s: float = Data.npc_scale(k).scale
		_list.add_item(label + ("   x%s" % str(snappedf(s, 0.01)) if not is_equal_approx(s, 1.0) else ""))
		_shown.append(k)
		if k == current:
			_list.select(_shown.size() - 1)


# ------------------------------------------------------------------ editing

## Shows an NPC (UI and tests).
func select(kind: String) -> void:
	if not Data.npcs.has(kind):
		return
	current = kind
	_anim = 0.0
	_rebuild()
	frame_view()
	var i := _shown.find(kind)
	if i >= 0:
		_list.select(i)
		_list.ensure_current_is_visible()


func set_size_scale(v: float) -> void:
	v = clampf(snappedf(v, 0.01), SCALE_MIN, SCALE_MAX)
	Data.set_npc_scale(current, v, Data.npc_scale(current).hitbox)
	_changed()


func set_hitbox_scales(on: bool) -> void:
	Data.set_npc_scale(current, Data.npc_scale(current).scale, on)
	_changed()


## The scale at which this NPC's sprite pixels are the player's size.
static func pixel_matched_scale(kind: String) -> float:
	var lk := NPC.look(kind)
	var shown_px: float = lk.frame_h - maxf(lk.trim, 0.0)
	var px: float = lk.sprite_size.y / shown_px
	return float(lk.scale) * PaperDoll.player_pixel_size() / px


## Scales an NPC so its pixels match the player's (UI and tests).
func match_player_pixels(kind: String) -> void:
	Data.set_npc_scale(kind, clampf(snappedf(pixel_matched_scale(kind), 0.01), SCALE_MIN, SCALE_MAX), Data.npc_scale(kind).hitbox)
	_changed()


func match_all_player_pixels() -> void:
	for k in _kinds:
		Data.set_npc_scale(k, clampf(snappedf(pixel_matched_scale(k), 0.01), SCALE_MIN, SCALE_MAX), Data.npc_scale(k).hitbox)
	_changed()
	_flash("Every NPC now has the player's pixel size (Revert to saved undoes it)")


func _changed() -> void:
	dirty = true
	_rebuild()
	_fill_list()


func _revert() -> void:
	Data.load_npc_scales(save_path)
	dirty = false
	_rebuild()
	_fill_list()


func save() -> void:
	if Data.save_npc_scales(save_path):
		dirty = false
		_flash("Saved %s (the game uses it next time it starts)" % save_path)
	else:
		_flash("Could not save " + save_path)


func _flash(text: String) -> void:
	_status.text = text
	_message_time = 4.0


## The preview and panel for the current NPC, as the game will draw it.
func _rebuild() -> void:
	var lk := NPC.look(current)
	NPC.apply_look(_npc, lk)
	var w: float = lk.hitbox[0]
	var h: float = lk.hitbox[1]
	_hitbox.mesh = _wire_box(Vector3(w, h, w))
	# You on its left, a block on its right, clear of it.
	var half_w: float = maxf(lk.sprite_size.x, w) * 0.5
	_player.position = Vector3(-half_w - 0.9, PLAYER_HEIGHT * 0.5, 0)
	_block.position = Vector3(half_w + 1.0, 0.5, 0)
	_syncing = true
	var sc := Data.npc_scale(current)
	_scale.value = sc.scale
	_scale_box.value = sc.scale
	_hitbox_check.button_pressed = sc.hitbox
	_syncing = false
	var d: Dictionary = Data.npcs[current]
	_title.text = "%s%s" % [Assets.npc_name(current), "  (boss)" if d.get("boss", false) else ""]
	var base: Array = d.size
	var px_ratio: float = (lk.sprite_size.y / (lk.frame_h - maxf(lk.trim, 0.0))) / PaperDoll.player_pixel_size()
	_info.text = "Sprite: %.2f x %.2f blocks\nHitbox: %.2f wide, %.2f tall%s\nIn npcs.json: %.2f x %.2f\n%s\nPixels: %.2fx the player's%s" % [
		lk.sprite_size.x, lk.sprite_size.y, w, h, "" if sc.hitbox else " (unscaled)", base[0], base[1],
		"Flies" if lk.flying else ("Town NPC" if d.ai == "town" else "Walks"),
		px_ratio, " (matched)" if absf(px_ratio - 1.0) < 0.01 else ""]


func _wire_box(s: Vector3) -> ImmediateMesh:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var x := s.x * 0.5
	var z := s.z * 0.5
	var corners := [Vector3(-x, 0, -z), Vector3(x, 0, -z), Vector3(x, 0, z), Vector3(-x, 0, z)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		for y in [0.01, s.y]:
			im.surface_add_vertex(a + Vector3(0, y, 0))
			im.surface_add_vertex(b + Vector3(0, y, 0))
		im.surface_add_vertex(a + Vector3(0, 0.01, 0))
		im.surface_add_vertex(a + Vector3(0, s.y, 0))
	im.surface_end()
	return im


## Points the camera at the NPC, far enough to see it, you and the block.
func frame_view() -> void:
	var lk := NPC.look(current)
	var tall: float = maxf(lk.top, PLAYER_HEIGHT)
	var wide: float = maxf(lk.sprite_size.x, lk.hitbox[0]) + 4.0
	_focus = Vector3(0, tall * 0.5, 0)
	_dist = maxf(tall * 1.6, wide * 1.1) + 1.5
	_update_camera()


func _update_camera() -> void:
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	_cam.position = _focus + dir * _dist
	_cam.look_at(_focus)
	# Centre the preview in the space between the side panels.
	var vp := get_viewport().get_visible_rect().size
	if _left.is_inside_tree() and vp.x > 0.0:
		var free_mid := (_left.get_global_rect().end.x + _right.get_global_rect().position.x) * 0.5
		var view_w := 2.0 * _dist * tan(deg_to_rad(_cam.fov) * 0.5) * vp.x / vp.y
		_cam.h_offset = (vp.x * 0.5 - free_mid) / vp.x * view_w


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_S when event.ctrl_pressed:
				save()
			KEY_F:
				frame_view()
			KEY_SPACE:
				animate = not animate
			KEY_F1:
				_help.visible = not _help.visible
			KEY_PAGEUP, KEY_PAGEDOWN:
				if not _shown.is_empty():
					var i := _shown.find(current) + (1 if event.keycode == KEY_PAGEDOWN else -1)
					select(_shown[wrapi(i, 0, _shown.size())])
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP when event.pressed:
				_dist = maxf(_dist / 1.12, 1.0)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN when event.pressed:
				_dist = minf(_dist * 1.12, 60.0)
				_update_camera()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.006, -1.4, 0.6)
		_update_camera()


func _process(delta: float) -> void:
	# The walk (or flap) cycle, like in the game.
	if animate and current != "":
		var d: Dictionary = Data.npcs[current]
		var wf: Array = d.get("walk_frames", d.get("fly_frames", [0, int(d.frames) - 1]))
		_anim += delta * ANIM_FPS
		var n := int(wf[1]) - int(wf[0]) + 1
		_npc.set_frame(int(wf[0]) + int(_anim) % maxi(n, 1))
	_message_time -= delta
	if _message_time <= 0.0:
		_status.text = "Unsaved changes" if dirty else ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not dirty:
			get_tree().quit()
			return
		var dlg := ConfirmationDialog.new()
		dlg.title = "Unsaved changes"
		dlg.dialog_text = "Save the NPC sizes before quitting?"
		dlg.ok_button_text = "Save and quit"
		dlg.add_button("Quit without saving", true, "discard")
		dlg.confirmed.connect(func():
			save()
			get_tree().quit())
		dlg.custom_action.connect(func(action):
			if action == "discard":
				get_tree().quit())
		_ui.add_child(dlg)
		dlg.popup_centered()
