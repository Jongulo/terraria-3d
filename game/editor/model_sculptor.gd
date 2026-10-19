extends Node3D
## Model sculptor: hand-tunes voxel models for the "tuned" method of the NPC
## picker and the placeable picker (TunedModels, saved in data/tuned/). A model
## starts as a copy of any voxel method's (flat, extruded, hull, hull top,
## lathe, Claude's) or an empty grid, then is sculpted voxel by voxel, frame by
## frame (or a range of frames at once). Run with ./model_sculptor.sh.
##
## Tools (left click): A add (onto the face you point at; drag to lay a layer),
## X remove, P paint (F: just the face you point at), C smart paint (each voxel
## copies one sampled from the surface nearby, so a patch takes on the texture
## round it, the same on every frame edited; Shift+[ ] how far it looks),
## T texture (noise of the model's colours near the current one; its range
## sets how near), I eyedropper (or Ctrl+click).
## [ ] brush size, M mirror across the middle (x), L edit a range of frames
## (From / To, wrapping past the last), , . frame, Space play, R the sprite beside it, Ctrl+Z / Ctrl+Shift+Z
## (Ctrl+Y) undo / redo, Ctrl+S save, PageUp/PageDown the next model, F1 help.
## Camera, as Blender's: MMB (or Alt+LMB) orbit, Shift+MMB pan, Ctrl+MMB or the
## wheel zoom; numpad (or the number row) 1 front, 3 right, 7 top (Ctrl: the
## opposite side), 9 the opposite view, 5 perspective / orthographic, 2 4 6 8
## orbit by 15 degrees, . or Home frame the model. Snapping to a view turns
## orthographic, and orbiting away from it perspective again (as Blender's
## auto perspective).

const FILTERS := ["All", "NPCs", "Placeables"]
const TOOLS := ["add", "remove", "paint", "smart", "texture", "pick"]
const TOOL_NAMES := {"add": "Add (A)", "remove": "Remove (X)", "paint": "Paint (P)", "smart": "Smart paint (C)",
		"texture": "Texture (T)", "pick": "Eyedropper (I)"}
const CHUNK := 16
const ANIM_FPS := 8.0
const UNDO_LIMIT := 40
const ORBIT_STEP := PI / 12.0
## Room added round the grid when a voxel goes past its edge.
const GROW_PAD := 4
## How far back the orthographic camera sits (it shows the same at any distance).
const ORTHO_BACK := 100.0

var current := {}  # {type: "npc" or "block", name, key}
var tool := "add"
var face_paint := false
var mirror := false
## Edit frames frame_from to frame_to (wrapping past the last) instead of just
## the one shown.
var use_range := false
var frame_from := 0
var frame_to := 0
var brush := 1
## How far past the brush Smart paint looks for voxels to copy.
var reach := 3
## How different from the current colour the Texture brush's colours may be
## (0..1, a colour distance).
var texture_range := 0.15
var color := Color(0.85, 0.2, 0.2)
var frame := 0
var playing := false
var show_sprite := true
var mouse := Vector2.ZERO

var _sources: Array = []  # every NPC and placeable: {type, name, key, label}
var _shown: Array = []
var _model := {}
var _px := 0.05
var _frames := 1
var _unsaved := {}  # key -> true
var _undo: Array = []
var _redo: Array = []
var _stroke := {}
var _stroke_plane := Vector3i.ZERO  # the face an Add drag keeps to, and its depth:
var _stroke_layer := 0
var _last_cell = null
var _chunk_meshes := {}  # frame -> {chunk: ArrayMesh}
var _dirty := {}  # frame -> {chunk: true}
var _chunk_nodes := {}  # chunk -> MeshInstance3D
var _anim := 0.0
var _seed_armed := false
var _delete_armed := false

var _cam := Camera3D.new()
var _yaw := 0.5
var _pitch := 0.35
var _dist := 6.0
var _target := Vector3(0, 1, 0)
var _ortho := false
var _auto_ortho := false
var _orbiting := false
var _panning := false
var _zooming := false
var _painting := false
var _model_root := Node3D.new()
var _material := ShaderMaterial.new()
var _box := MeshInstance3D.new()
var _cursor := MeshInstance3D.new()
var _sprite := Sprite3D.new()

var _ui := Control.new()
var _filter := OptionButton.new()
var _search := LineEdit.new()
var _list := ItemList.new()
var _header := Label.new()
var _status := Label.new()
var _message_time := 0.0
var _help := PanelContainer.new()
var _seed := OptionButton.new()
var _seed_button := Button.new()
var _delete_button := Button.new()
var _tool_buttons := {}
var _face_check := CheckBox.new()
var _mirror_check := CheckBox.new()
var _range_check := CheckBox.new()
var _range_from := SpinBox.new()
var _range_to := SpinBox.new()
var _reach_label := Label.new()
var _texture_label := Label.new()
var _texture_slider := HSlider.new()
var _texture_cache := {}  # {key, colours: [Color], weights}
var _stroke_seed := 0
var _rng := RandomNumberGenerator.new()
var _sprite_check := CheckBox.new()
var _brush_label := Label.new()
var _color_button := ColorPickerButton.new()
var _palette := GridContainer.new()
var _frame_label := Label.new()
var _view_label := Label.new()
var _info := Label.new()


func _ready() -> void:
	get_tree().auto_accept_quit = false
	for k in Data.npcs:
		var label: String = Assets.npc_name(k)
		_sources.append({"type": "npc", "name": k, "key": TunedModels.npc_key(k), "label": label if label != "" else k})
	for name in Data.placeable_blocks():
		var d := Data.block(Data.block_id(name))
		if not d.has("sprite"):
			continue
		_sources.append({"type": "block", "name": name, "key": TunedModels.block_key(d.get("settings", name)),
				"label": Data.placeable_label(name)})
	_sources.sort_custom(func(a, b): return a.label.naturalnocasecmp_to(b.label) < 0)
	_build_scene()
	_build_ui()
	_fill_list()
	var first := _sources.filter(func(s): return s.name == "EyeofCthulhu")
	select(first[0] if not first.is_empty() else _sources[0])


# ------------------------------------------------------------ the scene

func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.24, 0.28)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_material.shader = preload("res://shaders/npc_model.gdshader")
	_material.set_shader_parameter("textured", false)
	add_child(_model_root)
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.vertex_color_use_as_albedo = true
	line_mat.no_depth_test = false
	_box.material_override = line_mat
	add_child(_box)
	var cursor_mat := line_mat.duplicate()
	cursor_mat.no_depth_test = true
	_cursor.material_override = cursor_mat
	add_child(_cursor)
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.shaded = false
	_sprite.centered = false
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	add_child(_sprite)
	add_child(_cam)
	_cam.fov = 40.0
	_cam.near = 0.02
	_cam.make_current()
	_update_camera()


# ------------------------------------------------------------ the UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = Assets.font("Mouse_Text")
	theme.default_font_size = 20
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.9))
	theme.set_constant("shadow_offset_x", "Label", 2)
	theme.set_constant("shadow_offset_y", "Label", 2)
	_ui.theme = theme
	layer.add_child(_ui)
	_fit_ui()
	get_viewport().size_changed.connect(_fit_ui)

	var left := _side_panel(_ui)
	left.offset_left = 12
	left.offset_top = 12
	left.offset_right = 270
	left.anchor_bottom = 1.0
	left.offset_bottom = -12
	var box := VBoxContainer.new()
	left.add_child(box)
	box.add_child(_small("Model sculptor", 20))
	for f in FILTERS:
		_filter.add_item(f)
	_filter.item_selected.connect(func(_i):
		_fill_list()
		get_viewport().gui_release_focus())
	box.add_child(_filter)
	_search.placeholder_text = "Search"
	_search.text_changed.connect(func(_s): _fill_list())
	box.add_child(_search)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(28, 28)
	_list.item_selected.connect(func(i):
		select(_shown[i])
		get_viewport().gui_release_focus())
	box.add_child(_list)
	var save := Button.new()
	save.text = "Save (Ctrl+S)"
	save.pressed.connect(func():
		save_all()
		get_viewport().gui_release_focus())
	box.add_child(save)

	# The right column scrolls when the window is too short for it.
	var scroll := ScrollContainer.new()
	scroll.anchor_left = 1.0
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = -306
	scroll.offset_right = -6
	scroll.offset_top = 12
	scroll.offset_bottom = -12
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ui.add_child(scroll)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 288
	right.add_theme_constant_override("separation", 8)
	scroll.add_child(right)

	var start := _side_panel(right)
	var sb := VBoxContainer.new()
	start.add_child(sb)
	sb.add_child(_small("Start from"))
	for m in TunedModels.SEED_METHODS:
		_seed.add_item(m.capitalize())
	_seed.select(TunedModels.SEED_METHODS.find("hull"))
	_seed.item_selected.connect(func(_i):
		_seed_armed = false
		_sync_ui()
		get_viewport().gui_release_focus())
	sb.add_child(_seed)
	_seed_button.pressed.connect(func():
		_on_seed_pressed()
		get_viewport().gui_release_focus())
	sb.add_child(_seed_button)
	_delete_button.pressed.connect(func():
		_on_delete_pressed()
		get_viewport().gui_release_focus())
	sb.add_child(_delete_button)

	var tools := _side_panel(right)
	var tb := VBoxContainer.new()
	tools.add_child(tb)
	tb.add_child(_small("Tools"))
	var grid := GridContainer.new()
	grid.columns = 2
	var group := ButtonGroup.new()
	for t in TOOLS:
		var b := Button.new()
		b.text = TOOL_NAMES[t]
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func():
			set_tool(t)
			get_viewport().gui_release_focus())
		grid.add_child(b)
		_tool_buttons[t] = b
	tb.add_child(grid)
	for pair in [[_face_check, "Paint one face (F)", "face_paint"], [_mirror_check, "Mirror x (M)", "mirror"],
			[_sprite_check, "Sprite beside it (R)", "show_sprite"], [_range_check, "Frames (L)", "use_range"]]:
		var cb: CheckBox = pair[0]
		cb.text = pair[1]
		cb.add_theme_font_size_override("font_size", 16)
		var prop: String = pair[2]
		cb.toggled.connect(func(on):
			set(prop, on)
			_sync_ui()
			get_viewport().gui_release_focus())
		tb.add_child(cb)
	var rrow := HBoxContainer.new()
	for pair in [[_range_from, "frame_from"], [_range_to, "frame_to"]]:
		var spin: SpinBox = pair[0]
		var prop: String = pair[1]
		spin.min_value = 1
		spin.step = 1
		spin.value_changed.connect(func(v):
			set(prop, int(v) - 1)
			_sync_ui())
		rrow.add_child(_small("From" if prop == "frame_from" else "to", 16))
		rrow.add_child(spin)
	tb.add_child(rrow)
	var brow := HBoxContainer.new()
	_brush_label.add_theme_font_size_override("font_size", 16)
	_brush_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(_brush_label)
	for d in [-1, 1]:
		var b := Button.new()
		b.text = "-" if d < 0 else "+"
		b.pressed.connect(func():
			set_brush(brush + d)
			get_viewport().gui_release_focus())
		brow.add_child(b)
	tb.add_child(brow)
	var reach_row := HBoxContainer.new()
	_reach_label.add_theme_font_size_override("font_size", 16)
	_reach_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reach_row.add_child(_reach_label)
	for d in [-1, 1]:
		var b := Button.new()
		b.text = "-" if d < 0 else "+"
		b.pressed.connect(func():
			set_reach(reach + d)
			get_viewport().gui_release_focus())
		reach_row.add_child(b)
	tb.add_child(reach_row)
	_texture_label.add_theme_font_size_override("font_size", 16)
	tb.add_child(_texture_label)
	_texture_slider.min_value = 0.02
	_texture_slider.max_value = 0.5
	_texture_slider.step = 0.01
	_texture_slider.value_changed.connect(func(v):
		texture_range = v
		_sync_ui())
	tb.add_child(_texture_slider)
	var crow := HBoxContainer.new()
	crow.add_child(_small("Colour"))
	_color_button.custom_minimum_size = Vector2(80, 28)
	_color_button.edit_alpha = false
	_color_button.color_changed.connect(func(c): color = c)
	crow.add_child(_color_button)
	tb.add_child(crow)
	_palette.columns = 10
	_palette.add_theme_constant_override("h_separation", 2)
	_palette.add_theme_constant_override("v_separation", 2)
	tb.add_child(_palette)

	var frames := _side_panel(right)
	var fb := VBoxContainer.new()
	frames.add_child(fb)
	var frow := HBoxContainer.new()
	_frame_label.add_theme_font_size_override("font_size", 16)
	_frame_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frow.add_child(_frame_label)
	for pair in [["<", -1], [">", 1]]:
		var b := Button.new()
		b.text = pair[0]
		var d: int = pair[1]
		b.pressed.connect(func():
			set_frame(frame + d)
			get_viewport().gui_release_focus())
		frow.add_child(b)
	var play := Button.new()
	play.text = "Play"
	play.pressed.connect(func():
		playing = not playing
		get_viewport().gui_release_focus())
	frow.add_child(play)
	fb.add_child(frow)
	var vrow := HBoxContainer.new()
	for pair in [["Front", "front"], ["Right", "right"], ["Top", "top"], ["Back", "back"]]:
		var b := Button.new()
		b.text = pair[0]
		b.add_theme_font_size_override("font_size", 15)
		var v: String = pair[1]
		b.pressed.connect(func():
			view(v)
			get_viewport().gui_release_focus())
		vrow.add_child(b)
	fb.add_child(vrow)
	_view_label.add_theme_font_size_override("font_size", 15)
	fb.add_child(_view_label)
	var ib := _side_panel(right)
	_info.add_theme_font_size_override("font_size", 15)
	ib.add_child(_info)

	_header.position = Vector2(290, 10)
	_header.add_theme_font_size_override("font_size", 24)
	_ui.add_child(_header)
	_status.position = Vector2(290, 40)
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_ui.add_child(_status)

	_help.anchor_left = 0.5
	_help.anchor_right = 0.5
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.offset_left = -360
	_help.offset_right = 360
	_help.offset_top = -120
	_help.offset_bottom = -12
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0, 0, 0, 0.6)
	hsb.set_content_margin_all(10)
	hsb.set_corner_radius_all(6)
	_help.add_theme_stylebox_override("panel", hsb)
	var ht := Label.new()
	ht.add_theme_font_size_override("font_size", 15)
	ht.text = "LMB: tool   A add   X remove   P paint (F one face)   C smart paint (Shift+[ ] reach)   T texture   I / Ctrl+click eyedropper   [ ] brush   M mirror   L frame range\n" \
			+ "MMB / Alt+LMB orbit   Shift+MMB pan   Wheel zoom   Numpad or 1-9: 1 front  3 right  7 top (Ctrl: opposite)  9 flip  5 ortho  2468 orbit\n" \
			+ ", . frame   Space play   R sprite   Ctrl+Z / Ctrl+Y undo / redo   Ctrl+S save   PageUp/PageDown model   F1 hide this"
	_help.add_child(ht)
	_ui.add_child(_help)


func _side_panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.16, 0.88)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)
	return panel


func _small(text: String, size := 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _fit_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := clampf(float(Settings.get_value("ui_scale")), 0.5, maxf(0.5, vp.x / 1450.0))
	_ui.scale = Vector2(s, s)
	_ui.size = vp / s


func _fill_list() -> void:
	_list.clear()
	_shown.clear()
	var f: String = FILTERS[maxi(_filter.selected, 0)]
	var q := _search.text.strip_edges().to_lower()
	for src in _sources:
		if (f == "NPCs" and src.type != "npc") or (f == "Placeables" and src.type != "block"):
			continue
		if q != "" and not q in src.label.to_lower() and not q in src.name.to_lower():
			continue
		var marks := ""
		if TunedModels.has(src.key):
			marks = "   · tuned" + (" *" if _unsaved.has(src.key) else "")
		_list.add_item(src.label + marks, _icon(src))
		_shown.append(src)
		if not current.is_empty() and src.key == current.key and src.name == current.name:
			_list.select(_list.item_count - 1)


func _icon(src: Dictionary) -> Texture2D:
	if src.type == "npc":
		return NPCModels.texture(src.name, 0)
	var d := Data.block(Data.block_id(src.name))
	return ImageTexture.create_from_image(d.sprite) if d.get("sprite") is Image else null


# ------------------------------------------------------------ the source sprite

## Metres per voxel (one art pixel of the sprite).
func _px_of(src: Dictionary) -> float:
	if src.type == "npc":
		return NPCModels.frames_of(src.name).apx
	var d := Data.block(Data.block_id(src.name))
	return float(d.get("art_px", d.sprite_px))


func _frame_count(src: Dictionary) -> int:
	if src.type == "npc":
		return NPCModels.frames_of(src.name).arts.size()
	return Data.anim_frames(Data.block(Data.block_id(src.name)))


## The frame's sprite at art resolution (one pixel per voxel).
func _art(src: Dictionary, f: int) -> Image:
	if src.type == "npc":
		return NPCModels.frames_of(src.name).arts[f]
	var d := Data.block(Data.block_id(src.name))
	if f > 0:
		return d.anim_arts[f]
	return d.get("art", d.sprite)


## The frame's sprite as drawn, and its blocks per pixel (the reference beside it).
func _sheet(src: Dictionary, f: int) -> Array:
	if src.type == "npc":
		var fr := NPCModels.frames_of(src.name)
		return [fr.images[f], fr.px]
	var d := Data.block(Data.block_id(src.name))
	return [d.anim_sprites[f] if f > 0 else d.sprite, float(d.sprite_px)]


## A method's mesh for the frame: {mesh, textured}.
func _method_mesh(src: Dictionary, method: String, f: int) -> Dictionary:
	if src.type == "npc":
		return NPCModels.mesh(src.name, method, f)
	return BlockModelMesh.build(Data.block_id(src.name), method, f)


# ------------------------------------------------------------ selecting and seeding

func select(src: Dictionary) -> void:
	current = src
	_px = _px_of(src)
	_frames = _frame_count(src)
	frame = clampi(frame, 0, _frames - 1)
	frame_from = 0
	frame_to = _frames - 1
	_model = TunedModels.model(src.key) if TunedModels.has(src.key) else {}
	_undo.clear()
	_redo.clear()
	_seed_armed = false
	_delete_armed = false
	_rebuild_all()
	_fill_palette()
	_update_sprite()
	_frame_view()
	_fill_list()
	_sync_ui()


## Makes a new model for the current NPC or placeable from `method`.
func seed_from(method: String) -> void:
	var m := TunedModels.make_seed(current.key, method, TunedModels.method_options(current.key, method))
	_model = m
	TunedModels.put(current.key, m)
	_unsaved[current.key] = true
	_undo.clear()
	_redo.clear()
	_rebuild_all()
	_fill_palette()
	_update_sprite()
	_frame_view()
	_fill_list()
	_sync_ui()


func _on_seed_pressed() -> void:
	var method: String = TunedModels.SEED_METHODS[maxi(_seed.selected, 0)]
	if not _model.is_empty() and not _seed_armed:
		_seed_armed = true
		_flash("Press again to replace this model with a copy of its %s" % method.capitalize())
		_sync_ui()
		return
	_seed_armed = false
	_flash("Building from its %s..." % method.capitalize())
	await get_tree().process_frame
	seed_from(method)
	_flash("Started from its %s: sculpt away, Ctrl+S to save" % method.capitalize())


func _on_delete_pressed() -> void:
	if _model.is_empty():
		return
	if not _delete_armed:
		_delete_armed = true
		_flash("Press again to delete the tuned model (the file too)")
		_sync_ui()
		return
	TunedModels.remove(current.key)
	_unsaved.erase(current.key)
	select(current)
	_flash("Deleted: it shows its hull again")


func save_all() -> void:
	var saved := 0
	for key in _unsaved.keys():
		var m := TunedModels.model(key)
		if not m.is_empty() and TunedModels.save(key, m):
			saved += 1
			_unsaved.erase(key)
	_flash("Saved %d model%s to %s" % [saved, "" if saved == 1 else "s", TunedModels.dir] if saved > 0 else "Nothing to save")
	_fill_list()


# ------------------------------------------------------------ settings

func set_tool(t: String) -> void:
	tool = t
	_sync_ui()


func set_brush(n: int) -> void:
	brush = clampi(n, 1, 8)
	_sync_ui()


func set_reach(n: int) -> void:
	reach = clampi(n, 1, 12)
	_sync_ui()


## The frames an edit changes: the one shown, or the range (wrapping past the
## last frame, so 5 to 2 is 5, 6, 1, 2).
func edit_frames() -> Array:
	if not use_range:
		return [frame]
	var out := []
	var f := clampi(frame_from, 0, _frames - 1)
	var last := clampi(frame_to, 0, _frames - 1)
	for i in _frames:
		out.append(f)
		if f == last:
			break
		f = (f + 1) % _frames
	return out


func set_frame(f: int) -> void:
	frame = posmod(f, _frames)
	_show_frame()
	_sync_ui()


func _sync_ui() -> void:
	if current.is_empty():
		return
	var tuned := not _model.is_empty()
	_header.text = current.label + ("   (tuned)" if tuned else "   (not tuned yet)")
	var method: String = TunedModels.SEED_METHODS[maxi(_seed.selected, 0)]
	if not tuned:
		_seed_button.text = "Start tuning from its %s" % method.capitalize()
	else:
		_seed_button.text = ("Really replace it? (press again)" if _seed_armed else "Start over from its %s" % method.capitalize())
	_delete_button.text = "Really delete? (press again)" if _delete_armed else "Delete tuned model"
	_delete_button.disabled = not tuned
	for t in _tool_buttons:
		_tool_buttons[t].set_pressed_no_signal(t == tool)
	_face_check.set_pressed_no_signal(face_paint)
	_mirror_check.set_pressed_no_signal(mirror)
	_range_check.set_pressed_no_signal(use_range)
	for spin in [_range_from, _range_to]:
		spin.max_value = _frames
		spin.editable = use_range
	_range_from.set_value_no_signal(frame_from + 1)
	_range_to.set_value_no_signal(frame_to + 1)
	_reach_label.text = "Smart paint reach: %d" % reach
	_texture_slider.set_value_no_signal(texture_range)
	_texture_label.text = "Texture range: %d%%  (%d colours)" % [roundi(texture_range * 100.0), _texture_colors().colors.size() if not _model.is_empty() else 0]
	_sprite_check.set_pressed_no_signal(show_sprite)
	_brush_label.text = "Brush: %d" % brush
	_color_button.color = color
	_frame_label.text = "Frame %d / %d" % [frame + 1, _frames]
	if use_range:
		_frame_label.text += "  (editing %s)" % ", ".join(edit_frames().map(func(f): return str(f + 1)))
	_sprite.visible = show_sprite
	_view_label.text = ("Orthographic" if _ortho else "Perspective")
	if tuned:
		var n := 0
		for id in _model.frames[frame]:
			if id != 0:
				n += 1
		_info.text = "Grid %d x %d x %d   ·   %d voxels\nStarted from: %s   ·   %d colours\n%s" % [_model.size.x, _model.size.y, _model.size.z, n,
				str(_model.get("seeded_from", "?")).capitalize(), _model.looks.size() - 1, "Unsaved changes" if _unsaved.has(current.key) else "Saved"]
	else:
		_info.text = "Not tuned yet: in the game and the pickers it\nshows its hull. Pick what to start from above."


## The sprite's own colours, to pick from.
func _fill_palette() -> void:
	for c in _palette.get_children():
		c.queue_free()
	var seen := {}
	var cols: Array[Color] = []
	for f in _frames:
		var art := _art(current, f)
		for y in art.get_height():
			for x in art.get_width():
				var c := art.get_pixel(x, y)
				if c.a > 0.5 and not seen.has(c.to_html(false)):
					seen[c.to_html(false)] = true
					cols.append(Color(c, 1.0))
	cols.sort_custom(func(a, b): return a.get_luminance() < b.get_luminance())
	for c in cols.slice(0, 60):
		var b := Button.new()
		b.custom_minimum_size = Vector2(22, 22)
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		var col: Color = c
		b.pressed.connect(func():
			color = col
			_sync_ui()
			get_viewport().gui_release_focus())
		_palette.add_child(b)


func _flash(text: String) -> void:
	_status.text = text
	_message_time = 4.0


# ------------------------------------------------------------ meshes

func _rebuild_all() -> void:
	_chunk_meshes.clear()
	_dirty.clear()
	for n in _chunk_nodes.values():
		n.queue_free()
	_chunk_nodes.clear()
	_show_frame()
	_update_box()


## Shows the frame's chunks, building any it doesn't have yet.
func _show_frame() -> void:
	if _model.is_empty():
		for n in _chunk_nodes.values():
			n.mesh = null
		_update_sprite()
		return
	var counts := _chunk_counts()
	var meshes: Dictionary = _chunk_meshes.get(frame, {})
	var dirty: Dictionary = _dirty.get(frame, {})
	for cz in counts.z:
		for cy in counts.y:
			for cx in counts.x:
				var ch := Vector3i(cx, cy, cz)
				if not meshes.has(ch) or dirty.has(ch):
					var lo := ch * CHUNK
					var hi := (lo + Vector3i.ONE * CHUNK).min(_model.size)
					meshes[ch] = BlockModelMesh.mesh_from_arrays(TunedModels.arrays(_model, frame, _px, {}, lo, hi))
				if not _chunk_nodes.has(ch):
					var mi := MeshInstance3D.new()
					mi.material_override = _material
					mi.set_instance_shader_parameter("light", Color(1, 1, 1, 1))
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					_model_root.add_child(mi)
					_chunk_nodes[ch] = mi
				_chunk_nodes[ch].mesh = meshes[ch]
	_chunk_meshes[frame] = meshes
	_dirty[frame] = {}
	_update_sprite()


func _chunk_counts() -> Vector3i:
	var s: Vector3i = _model.size
	return Vector3i(ceili(s.x / float(CHUNK)), ceili(s.y / float(CHUNK)), ceili(s.z / float(CHUNK)))


## A cell changed on frame f: its chunk (and a neighbour it borders) rebuilds.
func _mark(f: int, c: Vector3i) -> void:
	if not _dirty.has(f):
		_dirty[f] = {}
	for d in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n: Vector3i = c + d
		_dirty[f][Vector3i(floori(n.x / float(CHUNK)), floori(n.y / float(CHUNK)), floori(n.z / float(CHUNK)))] = true


func _update_box() -> void:
	var im := ImmediateMesh.new()
	if not _model.is_empty():
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		var lo: Vector3 = _model.offset * _px
		var hi: Vector3 = (_model.offset + Vector3(_model.size)) * _px
		_box_lines(im, lo, hi, Color(1, 1, 1, 0.35))
		# The ground under it, and the middle (where mirroring folds).
		im.surface_set_color(Color(0.5, 0.8, 1.0))
		im.surface_add_vertex(Vector3(0, 0, lo.z))
		im.surface_add_vertex(Vector3(0, 0, hi.z))
		im.surface_end()
	_box.mesh = im


func _box_lines(im: ImmediateMesh, lo: Vector3, hi: Vector3, c: Color) -> void:
	var p := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)]
	im.surface_set_color(c)
	for i in 4:
		var a: Vector3 = p[i]
		var b: Vector3 = p[(i + 1) % 4]
		for y in [lo.y, hi.y]:
			im.surface_add_vertex(Vector3(a.x, y, a.z))
			im.surface_add_vertex(Vector3(b.x, y, b.z))
		im.surface_add_vertex(a)
		im.surface_add_vertex(Vector3(a.x, hi.y, a.z))


func _update_sprite() -> void:
	if current.is_empty():
		return
	var sheet := _sheet(current, frame)
	var img: Image = sheet[0]
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.pixel_size = sheet[1]
	var left: float = (_model.offset.x if not _model.is_empty() else -_art(current, frame).get_width() * 0.5) * _px
	_sprite.position = Vector3(left - img.get_width() * sheet[1] - 0.3, 0, 0)
	_sprite.offset = Vector2(0, 0)
	_sprite.flip_v = false
	# Sprite3D's pixels run up from its position when not centred.
	_sprite.visible = show_sprite


# ------------------------------------------------------------ the camera

func _update_camera() -> void:
	_pitch = clampf(_pitch, -PI * 0.5, PI * 0.5)
	var b := Basis.from_euler(Vector3(-_pitch, _yaw, 0))
	_cam.transform = Transform3D(b, _target + b.z * _dist)
	if _ortho:
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.size = 2.0 * _dist * tan(deg_to_rad(_cam.fov * 0.5))
	else:
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	if _ortho:
		# Far back, so nothing round the pivot is cut off by the near plane.
		_cam.position = _target + b.z * ORTHO_BACK
		_cam.near = 0.05
		_cam.far = ORTHO_BACK * 2.0
	else:
		_cam.near = 0.02
		_cam.far = _dist * 20.0 + 50.0
	_view_label.text = "Orthographic" if _ortho else "Perspective"


## Snaps to a view: front, back, right, left, top or bottom (orthographic).
func view(which: String) -> void:
	match which:
		"front":
			_yaw = 0.0
			_pitch = 0.0
		"back":
			_yaw = PI
			_pitch = 0.0
		"right":
			_yaw = PI * 0.5
			_pitch = 0.0
		"left":
			_yaw = -PI * 0.5
			_pitch = 0.0
		"top":
			_yaw = 0.0
			_pitch = PI * 0.5
		"bottom":
			_yaw = 0.0
			_pitch = -PI * 0.5
	if not _ortho:
		_ortho = true
		_auto_ortho = true
	_update_camera()


## Orbiting by hand leaves an auto-orthographic view for perspective.
func _orbit(dyaw: float, dpitch: float) -> void:
	_yaw += dyaw
	_pitch += dpitch
	if _auto_ortho:
		_ortho = false
		_auto_ortho = false
	_update_camera()


## Frames the model (or the sprite's box when there's none) and the sprite
## beside it, a little high so the help below doesn't hide it.
func _frame_view() -> void:
	var lo := Vector3.ZERO
	var hi := Vector3.ONE
	if not _model.is_empty():
		lo = _model.offset * _px
		hi = (_model.offset + Vector3(_model.size)) * _px
	elif not current.is_empty():
		var art := _art(current, 0)
		lo = Vector3(-art.get_width() * 0.5, 0, -art.get_width() * 0.5) * _px
		hi = Vector3(art.get_width() * 0.5, art.get_height(), art.get_width() * 0.5) * _px
	if show_sprite and _sprite.texture:
		lo.x = minf(lo.x, _sprite.position.x)
	_target = (lo + hi) * 0.5 - Vector3(0, (hi.y - lo.y) * 0.12, 0)
	_dist = maxf(1.0, maxf(hi.x - lo.x, hi.y - lo.y) * 2.4)
	_update_camera()


# ------------------------------------------------------------ picking

## What the mouse points at: {hit: the voxel (or null), face: its face index,
## add: where Add puts a voxel}; {} when nothing.
func pick(at: Vector2) -> Dictionary:
	if _model.is_empty():
		return {}
	var o: Vector3 = _cam.project_ray_origin(at) / _px - _model.offset
	var d := _cam.project_ray_normal(at)
	var size: Vector3 = Vector3(_model.size)
	var lo := Vector3(-GROW_PAD, -GROW_PAD, -GROW_PAD)
	var hi := size + Vector3.ONE * GROW_PAD
	# Clip the ray to the grid (and the room round it).
	var t0 := 0.0
	var t1 := INF
	for a in 3:
		if absf(d[a]) < 1e-9:
			if o[a] < lo[a] or o[a] > hi[a]:
				return {}
			continue
		var ta: float = (lo[a] - o[a]) / d[a]
		var tb: float = (hi[a] - o[a]) / d[a]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t0 > t1:
		return {}
	var p: Vector3 = o + d * (t0 + 1e-4)
	var c := Vector3i(p.floor())
	var step := Vector3i(int(signf(d.x)), int(signf(d.y)), int(signf(d.z)))
	var t_max := Vector3.ZERO
	var t_delta := Vector3.ZERO
	for a in 3:
		if step[a] == 0:
			t_max[a] = INF
			t_delta[a] = INF
		else:
			var edge := float(c[a] + (1 if step[a] > 0 else 0))
			t_max[a] = (edge - p[a]) / d[a]
			t_delta[a] = absf(1.0 / d[a])
	var normal := Vector3i.ZERO
	var dominant := d.abs().max_axis_index()
	normal[dominant] = -step[dominant]
	var travelled := 0.0
	var plane_cell = null
	for i in 2000:
		if TunedModels.get_look(_model, frame, c) != 0:
			return {"hit": c, "face": TunedModels.FACES.find(normal), "add": c + normal}
		# An empty grid: Add draws on the plane through the middle, facing you.
		if plane_cell == null and roundi(float(c[dominant])) == int(size[dominant] * 0.5):
			plane_cell = c
		var a := t_max.min_axis_index()
		travelled = t_max[a]
		if travelled > t1 - t0:
			break
		c[a] += step[a]
		t_max[a] += t_delta[a]
		normal = Vector3i.ZERO
		normal[a] = -step[a]
	if plane_cell != null:
		return {"hit": null, "face": -1, "add": plane_cell}
	return {}


# ------------------------------------------------------------ editing

## A face's mirror image's face: right and left swap.
const MIRROR_FACE := [0, 1, 3, 2, 4, 5]


## The cells a brush at c covers: [cell, mirrored] pairs (with mirror on, each
## cell's image across the model's middle too).
func _brush_cells(c: Vector3i) -> Array:
	var out := []
	var seen := {}
	var r := brush - 1
	for dz in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy + dz * dz <= r * r + r:
					var cell := c + Vector3i(dx, dy, dz)
					out.append([cell, false])
					seen[cell] = true
	if mirror:
		for entry in out.duplicate():
			var m := mirrored(entry[0])
			if not seen.has(m):
				out.append([m, true])
				seen[m] = true
	return out


static func _idot(a: Vector3i, b: Vector3i) -> int:
	return a.x * b.x + a.y * b.y + a.z * b.z


## A cell's mirror image across the model's middle (x = 0).
func mirrored(c: Vector3i) -> Vector3i:
	return Vector3i(roundi(-c.x - 1 - 2.0 * _model.offset.x), c.y, c.z)


func _begin_stroke() -> void:
	_stroke = {"size": _model.size, "offset": _model.offset, "frames": {}, "changed": false}
	_last_cell = null
	_stroke_seed = randi() % 100000


func _end_stroke() -> void:
	if not _stroke.is_empty() and _stroke.changed:
		_stroke.erase("changed")
		_undo.append(_stroke)
		if _undo.size() > UNDO_LIMIT:
			_undo.pop_front()
		_redo.clear()
		_unsaved[current.key] = true
		TunedModels.forget_meshes(current.key)
		_fill_list()
	_stroke = {}
	_sync_ui()


## Grows the grid to hold `cells` (plus some room round the side it grew):
## returns how far cells moved (zero when they already fit).
func _grow_to(cells: Array) -> Vector3i:
	var size: Vector3i = _model.size
	var lo := Vector3i.ZERO
	var hi := size
	for entry in cells:
		lo = lo.min(entry[0])
		hi = hi.max(entry[0] + Vector3i.ONE)
	if lo == Vector3i.ZERO and hi == size:
		return Vector3i.ZERO
	var pad_lo := Vector3i(int(lo.x < 0), int(lo.y < 0), int(lo.z < 0)) * GROW_PAD
	var pad_hi := Vector3i(int(hi.x > size.x), int(hi.y > size.y), int(hi.z > size.z)) * GROW_PAD
	var shift := -lo + pad_lo
	var new_size := hi - lo + pad_lo + pad_hi
	# Every frame's old grid is kept for undo before they all move.
	if not _stroke.is_empty():
		for f in _model.frames.size():
			if not _stroke.frames.has(f):
				_stroke.frames[f] = (_model.frames[f] as PackedInt32Array).duplicate()
		_stroke.changed = true
	for f in _model.frames.size():
		var old: PackedInt32Array = _model.frames[f]
		var g := PackedInt32Array()
		g.resize(new_size.x * new_size.y * new_size.z)
		for z in size.z:
			for y in size.y:
				for x in size.x:
					var id := old[x + size.x * (y + size.y * z)]
					if id != 0:
						g[(x + shift.x) + new_size.x * ((y + shift.y) + new_size.y * (z + shift.z))] = id
		_model.frames[f] = g
	_model.size = new_size
	_model.offset -= Vector3(shift)
	_rebuild_all()
	return shift


## Uses the tool at the mouse (one step of a stroke).
func apply_at(at: Vector2) -> void:
	var hit := pick(at)
	if hit.is_empty():
		return
	var target = hit.add if tool == "add" else hit.hit
	if target == null or target == _last_cell:
		return
	if tool == "add":
		# A drag lays one layer: it keeps to the first click's face and depth.
		var n: Vector3i = (target as Vector3i) - (hit.hit if hit.hit != null else target)
		if _last_cell == null:
			_stroke_plane = n
			_stroke_layer = _idot(target, n)
		elif n != _stroke_plane or _idot(target, n) != _stroke_layer:
			return
	var shift := apply_tool(tool, target, hit.face)
	_last_cell = (target as Vector3i) + shift
	_stroke_layer += _idot(shift, _stroke_plane)


## The tool's effect on cell c (face: the face pointed at), on this frame or
## all of them, with the brush and mirror. Returns how far cells moved if Add
## grew the grid.
func apply_tool(t: String, c: Vector3i, face := -1) -> Vector3i:
	if t == "pick":
		var id := TunedModels.get_look(_model, frame, c)
		if id != 0:
			color = _model.looks[id][maxi(face, 0)]
			_sync_ui()
		return Vector3i.ZERO
	var cells := _brush_cells(c)
	var shift := Vector3i.ZERO
	if t == "add":
		shift = _grow_to(cells)
		if shift != Vector3i.ZERO:
			cells = _brush_cells(c + shift)
	var solid := TunedModels.solid_look(_model, color)
	var targets := edit_frames()
	# Smart paint picks each voxel's look once, from the frame shown (or the
	# range's first), and gives every frame the same: no flicker between them.
	var picks := {}
	if t == "texture":
		var tex := _texture_colors()
		for entry in cells:
			# Mirrored voxels take their original's colour; a voxel keeps its
			# colour for the whole stroke (and on every frame).
			var key: Vector3i = mirrored(entry[0]) if entry[1] else entry[0]
			var r := BlockModelMesh._hash(key.x, key.y, key.z, _stroke_seed, 41)
			picks[entry[0]] = tex.colors[_weighted(tex.weights, r)]
	elif t == "smart":
		var ref: int = frame if frame in targets else targets[0]
		var sources := _smart_sources(_model.frames[ref], cells)
		for entry in cells:
			var src := _smart_pick(sources, entry[0])
			if not src.is_empty():
				picks[entry[0]] = src.id
	for f in targets:
		var g: PackedInt32Array = _model.frames[f]
		_model.frames[f] = PackedInt32Array()  # g alone holds it now, so writes don't copy it
		if not _stroke.is_empty() and not _stroke.frames.has(f):
			_stroke.frames[f] = g.duplicate()
		for entry in cells:
			var cell: Vector3i = entry[0]
			if not TunedModels.inside(_model, cell):
				continue
			var i := TunedModels.index(_model, cell)
			var id := g[i]
			var new_id := id
			match t:
				"add":
					if id == 0:
						new_id = solid
				"remove":
					new_id = 0
				"paint":
					if id == 0:
						continue
					if face_paint and face >= 0:
						var faces: PackedColorArray = (_model.looks[id] as PackedColorArray).duplicate()
						faces[MIRROR_FACE[face] if entry[1] else face] = color
						new_id = TunedModels.look_id(_model, faces)
					else:
						new_id = solid
				"texture":
					if id == 0:
						continue
					if face_paint and face >= 0:
						var faces: PackedColorArray = (_model.looks[id] as PackedColorArray).duplicate()
						faces[MIRROR_FACE[face] if entry[1] else face] = picks[cell]
						new_id = TunedModels.look_id(_model, faces)
					else:
						new_id = TunedModels.solid_look(_model, picks[cell])
				"smart":
					if id == 0 or not picks.has(cell):
						continue
					if face_paint and face >= 0:
						var fi: int = MIRROR_FACE[face] if entry[1] else face
						var faces: PackedColorArray = (_model.looks[id] as PackedColorArray).duplicate()
						faces[fi] = _model.looks[picks[cell]][fi]
						new_id = TunedModels.look_id(_model, faces)
					else:
						new_id = picks[cell]
			if new_id != id:
				g[i] = new_id
				_mark(f, cell)
				if not _stroke.is_empty():
					_stroke.changed = true
		_model.frames[f] = g
	_show_frame()
	return shift


## The Texture brush's colours: the model's colours (its voxels' faces) within
## texture_range of the current colour, nearer ones weighted more; the current
## colour itself when none is near. {colors: Array[Color], weights}.
func _texture_colors() -> Dictionary:
	var key := "%s|%s|%d" % [color.to_html(false), texture_range, _model.looks.size() if not _model.is_empty() else 0]
	if _texture_cache.get("key", "") == key:
		return _texture_cache
	var colors: Array[Color] = []
	var weights := PackedFloat32Array()
	if not _model.is_empty():
		for c in TunedModels.colors_used(_model):
			var d := color_distance(c, color)
			if d <= texture_range:
				colors.append(c)
				weights.append(1.0 - d / (texture_range * 1.25))
	if colors.is_empty():
		colors.append(color)
		weights.append(1.0)
	_texture_cache = {"key": key, "colors": colors, "weights": weights}
	return _texture_cache


## How different two colours look (0 the same, about 1 black and white):
## RGB weighted as the eye sees it ("redmean").
static func color_distance(a: Color, b: Color) -> float:
	var rm := (a.r + b.r) * 0.5
	var d := Vector3(a.r - b.r, a.g - b.g, a.b - b.b)
	return sqrt((2.0 + rm) * d.x * d.x + 4.0 * d.y * d.y + (3.0 - rm) * d.z * d.z) / 3.0


## The index `r` (0..1) falls on, by weight.
static func _weighted(weights: PackedFloat32Array, r: float) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var at := r * total
	for i in weights.size():
		at -= weights[i]
		if at < 0.0:
			return i
	return weights.size() - 1


## Smart paint's sources on a frame's grid: the voxels showing on the surface
## (an empty cell beside them) within reach of the brush, not under it:
## [{cell, id}].
func _smart_sources(g: PackedInt32Array, cells: Array) -> Array:
	var under := {}
	var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi := -lo
	for entry in cells:
		under[entry[0]] = true
		lo = lo.min(entry[0])
		hi = hi.max(entry[0])
	lo -= Vector3i.ONE * reach
	hi += Vector3i.ONE * reach
	var size: Vector3i = _model.size
	lo = lo.max(Vector3i.ZERO)
	hi = hi.min(size - Vector3i.ONE)
	var out := []
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var c := Vector3i(x, y, z)
				var id := g[x + size.x * (y + size.y * z)]
				if id == 0 or under.has(c):
					continue
				for d in TunedModels.FACES:
					var n: Vector3i = c + d
					if not TunedModels.inside(_model, n) or g[TunedModels.index(_model, n)] == 0:
						out.append({"cell": c, "id": id})
						break
	return out


## One of the sources for a cell, nearer ones likelier ({} when none is within
## reach of it, counting from the brush's edge).
func _smart_pick(sources: Array, cell: Vector3i) -> Dictionary:
	var limit := float(reach + brush - 1)
	var near := []
	var weights := PackedFloat32Array()
	for s in sources:
		var d := Vector3(s.cell - cell).length()
		if d <= limit + 0.01:
			near.append(s)
			weights.append(1.0 / (d * d))
	if near.is_empty():
		return {}
	return near[_rng.rand_weighted(weights)]


func undo() -> void:
	_swap(_undo, _redo)


func redo() -> void:
	_swap(_redo, _undo)


## Puts back a snapshot from `from`, keeping the present in `to`.
func _swap(from: Array, to: Array) -> void:
	if from.is_empty():
		return
	var rec: Dictionary = from.pop_back()
	var now := {"size": _model.size, "offset": _model.offset, "frames": {}}
	var regrid: bool = rec.size != _model.size
	for f in rec.frames:
		now.frames[f] = _model.frames[f]
		_model.frames[f] = rec.frames[f]
	_model.size = rec.size
	_model.offset = rec.offset
	to.append(now)
	_unsaved[current.key] = true
	TunedModels.forget_meshes(current.key)
	if regrid:
		_rebuild_all()
	else:
		for f in rec.frames:
			_chunk_meshes.erase(f)
		_show_frame()
	_sync_ui()


# ------------------------------------------------------------ input and frames

func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			_status.text = ""
	if playing and _frames > 1:
		_anim += delta * ANIM_FPS
		if _anim >= 1.0:
			_anim = 0.0
			set_frame(frame + 1)
	_update_cursor()


func _update_cursor() -> void:
	var im := ImmediateMesh.new()
	var hit := pick(mouse) if not _orbiting and not _panning else {}
	if not hit.is_empty():
		var target = hit.add if tool == "add" else hit.hit
		if target != null:
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			var col: Color = {"add": Color(0.4, 1, 0.4), "remove": Color(1, 0.4, 0.4), "paint": color, "smart": Color(0.8, 0.5, 1.0), "texture": color, "pick": Color(1, 1, 1)}[tool]
			for entry in _brush_cells(target):
				var lo: Vector3 = (Vector3(entry[0]) + _model.offset) * _px
				_box_lines(im, lo, lo + Vector3.ONE * _px, col)
			im.surface_end()
	_cursor.mesh = im


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse = event.position
		if _orbiting:
			_orbit(-event.relative.x * 0.008, event.relative.y * 0.008)
		elif _panning:
			var b := _cam.global_transform.basis
			_target += (-b.x * event.relative.x + b.y * event.relative.y) * _dist * 0.0015
			_update_camera()
		elif _zooming:
			_dist = clampf(_dist * (1.0 + event.relative.y * 0.01), 0.2, 200.0)
			_update_camera()
		elif _painting:
			apply_at(mouse)
	elif event is InputEventMouseButton:
		mouse = event.position
		var orbit_button: bool = event.button_index == MOUSE_BUTTON_MIDDLE or (event.button_index == MOUSE_BUTTON_LEFT and event.alt_pressed)
		if orbit_button:
			_orbiting = event.pressed and not event.shift_pressed and not event.ctrl_pressed
			_panning = event.pressed and event.shift_pressed
			_zooming = event.pressed and event.ctrl_pressed and not event.shift_pressed
			if not event.pressed:
				_orbiting = false
				_panning = false
				_zooming = false
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not _model.is_empty():
				if event.ctrl_pressed:
					var hit := pick(mouse)
					if not hit.is_empty() and hit.hit != null:
						apply_tool("pick", hit.hit, hit.face)
					return
				_painting = true
				_begin_stroke()
				apply_at(mouse)
			elif not event.pressed and _painting:
				_painting = false
				_end_stroke()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_dist = clampf(_dist * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.2, 200.0)
			_update_camera()
	elif event is InputEventKey and event.pressed:
		_key(event)


func _key(event: InputEventKey) -> void:
	var k := event.keycode
	if _search.has_focus():
		return
	var handled := true
	# Numpad views, and the number row standing in for it (Blender's emulate numpad).
	var pad := {KEY_KP_1: 1, KEY_KP_2: 2, KEY_KP_3: 3, KEY_KP_4: 4, KEY_KP_5: 5, KEY_KP_6: 6, KEY_KP_7: 7, KEY_KP_8: 8, KEY_KP_9: 9,
			KEY_1: 1, KEY_2: 2, KEY_3: 3, KEY_4: 4, KEY_5: 5, KEY_6: 6, KEY_7: 7, KEY_8: 8, KEY_9: 9}
	if event.ctrl_pressed and k == KEY_S:
		save_all()
	elif event.ctrl_pressed and (k == KEY_Y or (k == KEY_Z and event.shift_pressed)):
		redo()
	elif event.ctrl_pressed and k == KEY_Z:
		undo()
	elif pad.has(k):
		match pad[k]:
			1:
				view("back" if event.ctrl_pressed else "front")
			3:
				view("left" if event.ctrl_pressed else "right")
			7:
				view("bottom" if event.ctrl_pressed else "top")
			9:
				_yaw += PI
				_update_camera()
			5:
				_ortho = not _ortho
				_auto_ortho = false
				_update_camera()
			2:
				_orbit(0.0, -ORBIT_STEP)
			8:
				_orbit(0.0, ORBIT_STEP)
			4:
				_orbit(-ORBIT_STEP, 0.0)
			6:
				_orbit(ORBIT_STEP, 0.0)
	elif event.echo:
		handled = false
	elif k in [KEY_KP_PERIOD, KEY_HOME]:
		_frame_view()
	elif k in [KEY_KP_ADD, KEY_EQUAL]:
		_dist = maxf(0.2, _dist * 0.85)
		_update_camera()
	elif k in [KEY_KP_SUBTRACT, KEY_MINUS]:
		_dist = minf(200.0, _dist / 0.85)
		_update_camera()
	elif k == KEY_A:
		set_tool("add")
	elif k == KEY_X or k == KEY_DELETE:
		set_tool("remove")
	elif k == KEY_P:
		set_tool("paint")
	elif k == KEY_I:
		set_tool("pick")
	elif k == KEY_C:
		set_tool("smart")
	elif k == KEY_T:
		set_tool("texture")
	elif k == KEY_F:
		face_paint = not face_paint
		_sync_ui()
	elif k == KEY_M:
		mirror = not mirror
		_sync_ui()
	elif k == KEY_L:
		use_range = not use_range
		_sync_ui()
	elif k == KEY_R:
		show_sprite = not show_sprite
		_sync_ui()
	elif k == KEY_BRACKETLEFT and event.shift_pressed:
		set_reach(reach - 1)
	elif k == KEY_BRACKETRIGHT and event.shift_pressed:
		set_reach(reach + 1)
	elif k == KEY_BRACKETLEFT:
		set_brush(brush - 1)
	elif k == KEY_BRACKETRIGHT:
		set_brush(brush + 1)
	elif k == KEY_COMMA:
		set_frame(frame - 1)
	elif k == KEY_PERIOD:
		set_frame(frame + 1)
	elif k == KEY_SPACE:
		playing = not playing
	elif k in [KEY_PAGEDOWN, KEY_DOWN]:
		_step(1)
	elif k in [KEY_PAGEUP, KEY_UP]:
		_step(-1)
	elif k == KEY_F1:
		_help.visible = not _help.visible
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _step(d: int) -> void:
	if _shown.is_empty():
		return
	var i := -1
	for j in _shown.size():
		if _shown[j].name == current.get("name", "") and _shown[j].type == current.get("type", ""):
			i = j
	select(_shown[wrapi(i + d, 0, _shown.size())])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _unsaved.is_empty():
			get_tree().quit()
			return
		var dlg := ConfirmationDialog.new()
		dlg.title = "Unsaved changes"
		dlg.dialog_text = "Save the %d changed model%s before quitting?" % [_unsaved.size(), "" if _unsaved.size() == 1 else "s"]
		dlg.ok_button_text = "Save and quit"
		dlg.add_button("Quit without saving", true, "discard")
		dlg.confirmed.connect(func():
			save_all()
			get_tree().quit())
		dlg.custom_action.connect(func(action):
			if action == "discard":
				get_tree().quit())
		add_child(dlg)
		dlg.popup_centered()
