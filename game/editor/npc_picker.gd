extends Node3D
## NPC picker: the placeable picker's sister, for enemies, bosses and town
## NPCs. Choose how each one is turned into 3D: shows the selected NPC in every
## method side by side (NPCModels.METHODS), walking or flapping through its
## frames; pick one by clicking it or pressing 1-9 and 0. Saves data/npc_models.json,
## which the game reads. Run with ./npc_picker.sh.
##
## Controls: click / 1-9, 0 choose a method · PageUp/PageDown (or Up/Down) change
## NPC · Space turntable · Q/E turn models · P pause the animation · MMB orbit,
## Shift+MMB pan, wheel zoom · Ctrl+S save · F1 help
## Settings panel (right): pixel noise, strength and seed for Extruded, Hull,
## Hull Top, Lathe, Claude and Tuned ("Settings for" picks which; it follows the chosen
## method), plus depth, bevel and which sides are bevelled for Extruded.
## [ / ] depth -/+1 voxel, N next noise mode, Shift+N new seed, B / Shift+B
## next / previous bevel. "Rendered" (at the bottom) picks the model the
## rendered method shoots: Auto (tuned, Claude's or the hull) or Extruded.

const SPACING := 2.0
## Models bigger than this (blocks) are shrunk to fit their slot.
const SLOT := 1.7
const GRASS_BLOCKS := 6
const ANIM_FPS := 8.0
const FILTERS := ["All", "Enemies", "Bosses", "Town NPCs"]

## Overridable before entering the tree (tests write elsewhere).
var save_path := NPCModels.PATH
var current := ""
var dirty := false
var animate := true
var mouse := Vector2.ZERO

var _kinds: Array = []  # every NPC kind, sorted by name
var _shown: Array = []  # the kinds the list shows (filter and search)
var _cam := Camera3D.new()
var _yaw := 0.35
var _pitch := 0.3
var _dist := 12.0  # all 10 methods fit between the side panels
var _target := Vector3(2.2, 0.7, 0)  # the row runs away to the left: aim right of its middle
var _orbiting := false
var _panning := false
var _spin := false
var _turn := 0.0
var _stage := Node3D.new()
var _slots: Array[Node3D] = []  # one per method: holds its model, turns
var _models: Array[Node3D] = []
var _labels: Array[Label3D] = []
var _marker := MeshInstance3D.new()
var _player := Sprite3D.new()
var _anim := 0.0
var _fit := 1.0
var _rebuild_methods := {}
var _settings_method := "extruded"

var _ui := Control.new()
var _filter := OptionButton.new()
var _search := LineEdit.new()
var _list := ItemList.new()
var _header := Label.new()
var _status := Label.new()
var _help := PanelContainer.new()
var _message_time := 0.0
var _ex_title := Label.new()
var _ex_for := OptionButton.new()
var _ex_depth := HSlider.new()
var _ex_depth_label := Label.new()
var _ex_noise := OptionButton.new()
## Every voxel one colour (all voxel methods).
var _one_color := CheckBox.new()
## Extruded, hull, hull_top and lathe: cut the sprite's outline away first.
var _no_outline := CheckBox.new()
var _render_model := OptionButton.new()
## Rendered: an outline round every shot.
var _render_outline := CheckBox.new()
var _ex_strength := HSlider.new()
var _ex_strength_label := Label.new()
var _ex_seed := SpinBox.new()
var _ex_bevel_title := Label.new()
var _ex_bevel := OptionButton.new()
var _ex_bevel_size := HSlider.new()
var _ex_bevel_label := Label.new()
var _ex_sides_label := Label.new()
var _ex_sides := {}  # BlockModelMesh.BEVEL_SIDES entry -> CheckBox
var _extruded_only: Array[Control] = []
var _info := Label.new()


func _ready() -> void:
	get_tree().auto_accept_quit = false
	NPCModels.ensure_loaded()
	_kinds = Data.npcs.keys()
	_kinds.sort_custom(func(a, b): return Assets.npc_name(a) < Assets.npc_name(b))
	_build_scene()
	_build_ui()
	_fill_list()
	select("Zombie" if _kinds.has("Zombie") else _kinds[0])


func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.6, 0.98)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_texture = _grass_texture()
	gm.uv1_scale = Vector3(60.0 / GRASS_BLOCKS, 60.0 / GRASS_BLOCKS, 1)
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ground.material_override = gm
	add_child(ground)
	add_child(_stage)
	# A Terraria player (as the inventory draws them) at the row's end, for scale.
	var doll := PaperDoll.standing_image()
	_player.texture = ImageTexture.create_from_image(doll)
	_player.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_player.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_player.shaded = false
	_player.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_player.offset = Vector2(0, doll.get_height() * 0.5)  # stands on the ground
	add_child(_player)
	# Selection marker: a gold square under the chosen method.
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var pts := [Vector3(-0.85, 0.02, -0.85), Vector3(0.85, 0.02, -0.85), Vector3(0.85, 0.02, 0.85), Vector3(-0.85, 0.02, 0.85)]
	for i in 4:
		im.surface_add_vertex(pts[i])
		im.surface_add_vertex(pts[(i + 1) % 4])
	im.surface_end()
	_marker.mesh = im
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1.0, 0.85, 0.2)
	_marker.material_override = mm
	add_child(_marker)
	add_child(_cam)
	_cam.make_current()
	_update_camera()


## The ground: the game's grass block top, variants mixed like the world's.
func _grass_texture() -> Texture2D:
	var d := Data.block(Data.block_id("grass"))
	var first: int = d.tex_top
	var cell := Data.LAYER_SIZE
	var img := Image.create(cell * GRASS_BLOCKS, cell * GRASS_BLOCKS, false, Image.FORMAT_RGBA8)
	for z in GRASS_BLOCKS:
		for x in GRASS_BLOCKS:
			var layer := Data.block_textures.get_layer_data(first + absi(hash(Vector2i(x, z))) % int(d.variants))
			if layer == null:
				continue  # headless: the texture array has no images
			layer.decompress()
			layer.clear_mipmaps()
			layer.convert(Image.FORMAT_RGBA8)
			img.blit_rect(layer, Rect2i(0, 0, cell, cell), Vector2i(x * cell, z * cell))
	return ImageTexture.create_from_image(img)


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
	var t := Label.new()
	t.text = "Enemies & NPCs"
	box.add_child(t)
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
		_save()
		get_viewport().gui_release_focus())
	box.add_child(save)

	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -290
	right.offset_right = -12
	right.offset_top = 12
	right.add_theme_constant_override("separation", 8)
	_ui.add_child(right)
	_build_settings_panel(right)
	var ib := _side_panel(right)
	_info.add_theme_font_size_override("font_size", 16)
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
	_help.offset_left = -300
	_help.offset_right = 300
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
	ht.text = "Click a model or press 1-9, 0 to choose its method   ·   PageUp/PageDown: NPC\nSpace: turntable   Q/E: turn   P: pause   MMB: orbit   Shift+MMB: pan   Wheel: zoom\nNoise: N mode   Shift+N seed   O one colour per voxel   L remove outline   Shift+L rendered outline   ·   Extruded: [ ] depth   B bevel   ·   Ctrl+S: save"
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


func _build_settings_panel(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_side_panel(parent).add_child(box)
	_ex_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_ex_title)
	box.add_child(_small("Settings for"))
	for m in NPCModels.NOISE_METHODS:
		_ex_for.add_item(m.capitalize())
	_ex_for.item_selected.connect(func(i):
		_settings_method = NPCModels.NOISE_METHODS[i]
		_sync_settings_ui()
		get_viewport().gui_release_focus())
	box.add_child(_ex_for)

	_ex_depth_label.add_theme_font_size_override("font_size", 16)
	box.add_child(_ex_depth_label)
	_ex_depth.min_value = 1
	_ex_depth.step = 1
	_ex_depth.value_changed.connect(func(v): _set_option("depth", int(v), "extruded"))
	box.add_child(_ex_depth)

	box.add_child(_small("Side noise"))
	for n in Data.EXTRUDE_NOISES:
		_ex_noise.add_item(n.capitalize())
	_ex_noise.item_selected.connect(func(i):
		_set_option("noise", Data.EXTRUDE_NOISES[i])
		get_viewport().gui_release_focus())
	box.add_child(_ex_noise)
	_ex_strength_label.add_theme_font_size_override("font_size", 16)
	box.add_child(_ex_strength_label)
	_ex_strength.min_value = 0.0
	_ex_strength.max_value = 1.0
	_ex_strength.step = 0.05
	_ex_strength.value_changed.connect(func(v): _set_option("strength", snappedf(v, 0.05)))
	box.add_child(_ex_strength)
	var row := HBoxContainer.new()
	row.add_child(_small("Seed"))
	_ex_seed.min_value = 0
	_ex_seed.max_value = 9999
	_ex_seed.step = 1
	_ex_seed.value_changed.connect(func(v): _set_option("seed", int(v)))
	row.add_child(_ex_seed)
	box.add_child(row)
	_one_color.text = "One colour per voxel (O)"
	_one_color.add_theme_font_size_override("font_size", 16)
	_one_color.toggled.connect(func(on):
		_set_option("one_color", on)
		get_viewport().gui_release_focus())
	box.add_child(_one_color)
	_no_outline.text = "Remove outline (L)"
	_no_outline.tooltip_text = "Cut the sprite's dark outline away before building the model"
	_no_outline.add_theme_font_size_override("font_size", 16)
	_no_outline.toggled.connect(func(on):
		_set_option("no_outline", on)
		get_viewport().gui_release_focus())
	box.add_child(_no_outline)

	_ex_bevel_title.text = "Bevel"
	_ex_bevel_title.add_theme_font_size_override("font_size", 16)
	box.add_child(_ex_bevel_title)
	for b in Data.EXTRUDE_BEVELS:
		_ex_bevel.add_item(b.capitalize())
	_ex_bevel.item_selected.connect(func(i):
		_set_option("bevel", Data.EXTRUDE_BEVELS[i], "extruded")
		get_viewport().gui_release_focus())
	box.add_child(_ex_bevel)
	_ex_bevel_label.add_theme_font_size_override("font_size", 16)
	box.add_child(_ex_bevel_label)
	_ex_bevel_size.min_value = 1
	_ex_bevel_size.max_value = Data.BEVEL_MAX
	_ex_bevel_size.step = 1
	_ex_bevel_size.value_changed.connect(func(v): _set_option("bevel_size", int(v), "extruded"))
	box.add_child(_ex_bevel_size)
	_ex_sides_label.text = "Bevel sides"
	_ex_sides_label.add_theme_font_size_override("font_size", 16)
	box.add_child(_ex_sides_label)
	_extruded_only = [_ex_depth_label, _ex_depth, _ex_bevel_title, _ex_bevel, _ex_bevel_label, _ex_bevel_size, _ex_sides_label]
	for group in [["Edges", ["top", "bottom", "left", "right"]], ["Faces", ["front", "back"]]]:
		var sides_row := HBoxContainer.new()
		var gl := _small(group[0], 14)
		gl.custom_minimum_size.x = 52
		sides_row.add_child(gl)
		for side in group[1]:
			var cb := CheckBox.new()
			cb.text = side.capitalize()
			cb.add_theme_font_size_override("font_size", 14)
			cb.toggled.connect(func(on): _toggle_bevel_side(side, on))
			sides_row.add_child(cb)
			_ex_sides[side] = cb
		box.add_child(sides_row)
		_extruded_only.append(sides_row)
	var reset := Button.new()
	reset.text = "Reset these settings"
	reset.pressed.connect(func():
		NPCModels.reset_options(current, _settings_method)
		dirty = true
		_sync_settings_ui()
		_rebuild_methods[_settings_method] = true
		if _settings_method == NPCRenders.source(current):
			NPCRenders.forget(current)
			_rebuild_methods["rendered"] = true
		get_viewport().gui_release_focus())
	box.add_child(reset)
	var hint := _small("[ ] depth   N noise   Shift+N seed   B bevel   O one colour   L outline", 14)
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)

	var rendered_title := _small("Rendered", 20)
	box.add_child(rendered_title)
	box.add_child(_small("Shots taken of"))
	_render_model.add_item("Auto (tuned, Claude or hull)")
	_render_model.add_item("Extruded model")
	_render_model.add_theme_font_size_override("font_size", 16)
	_render_model.item_selected.connect(func(i):
		_set_option("model", NPCModels.RENDER_MODELS[i], "rendered")
		get_viewport().gui_release_focus())
	box.add_child(_render_model)
	_render_outline.text = "Add outline (Shift+L)"
	_render_outline.tooltip_text = "Draw a dark one-pixel outline round every shot, as Terraria's sprites have"
	_render_outline.add_theme_font_size_override("font_size", 16)
	_render_outline.toggled.connect(func(on):
		_set_option("outline", on, "rendered")
		get_viewport().gui_release_focus())
	box.add_child(_render_outline)


func _fit_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := clampf(float(Settings.get_value("ui_scale")), 0.5, maxf(0.5, vp.x / 1450.0))
	_ui.scale = Vector2(s, s)
	_ui.size = vp / s


## Which list an NPC belongs to: "Bosses", "Town NPCs" or "Enemies".
static func category(kind: String) -> String:
	var d: Dictionary = Data.npcs[kind]
	if d.get("boss", false):
		return "Bosses"
	if d.ai == "town":
		return "Town NPCs"
	return "Enemies"


## The list: NPCs in the filter matching the search; ones not drawn as
## billboards are marked with their method.
func _fill_list() -> void:
	_list.clear()
	_shown.clear()
	var f: String = FILTERS[maxi(_filter.selected, 0)]
	var q := _search.text.strip_edges().to_lower()
	for k in _kinds:
		if f != "All" and category(k) != f:
			continue
		var label: String = "%s (%s)" % [Assets.npc_name(k), k] if Assets.npc_name(k) != k else k
		if q != "" and not q in label.to_lower():
			continue
		var m := NPCModels.method(k)
		_list.add_item(label + ("   · " + m if m != "billboard" else ""), NPCModels.texture(k, 0))
		_shown.append(k)
		if k == current:
			_list.select(_shown.size() - 1)


# ------------------------------------------------------------------ models

## Shows an NPC in every method (UI and tests).
func select(kind: String) -> void:
	if not Data.npcs.has(kind):
		return
	current = kind
	_anim = 0.0
	for s in _slots:
		s.queue_free()
	for l in _labels:
		l.queue_free()
	_slots.clear()
	_models.clear()
	_labels.clear()
	var fr := NPCModels.frames_of(kind)
	var size: Vector2 = fr.size
	_fit = minf(1.0, SLOT / maxf(size.x, size.y))
	var n := NPCModels.METHODS.size()
	for i in n:
		var m: String = NPCModels.METHODS[i]
		var slot := Node3D.new()
		_stage.add_child(slot)
		slot.position = Vector3(_slot_x(i), 0, 0)
		slot.scale = Vector3.ONE * _fit
		slot.rotation.y = _turn
		_slots.append(slot)
		_models.append(null)
		_make_model(i)
		var lab := Label3D.new()
		lab.text = "%d  %s\n%s" % [i + 1, m.capitalize(), NPCModels.DESCRIPTIONS[m]]
		if m == "claude" and not NPCSculpt.has(kind):
			lab.text = "%d  Claude\nNot made yet (shows Hull)" % (i + 1)
		elif m == "tuned" and not TunedModels.has(TunedModels.npc_key(kind)):
			lab.text = "%d  Tuned\nNot tuned yet (shows Hull)" % (i + 1)
		lab.font = Assets.font("Mouse_Text")
		lab.font_size = 18
		lab.pixel_size = 0.012
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_stage.add_child(lab)
		lab.position = Vector3(_slot_x(i), size.y * _fit + 0.35, 0)
		_labels.append(lab)
	# The player shrinks with the models, so it stays to scale with them.
	_player.pixel_size = PaperDoll.player_pixel_size() * _fit
	_player.position = Vector3(_slot_x(0) - SPACING * 0.9, 0, 0)
	_refresh_choice()
	_sync_settings_ui()
	_sync_info()
	var li := _shown.find(kind)
	if li >= 0:
		_list.select(li)
		_list.ensure_current_is_visible()


func _slot_x(i: int) -> float:
	return (i - (NPCModels.METHODS.size() - 1) * 0.5) * SPACING


## Builds method `i`'s model in its slot: the billboard as the game draws it
## (on the ground here, fliers too), or an NPCModel.
func _make_model(i: int) -> void:
	var m: String = NPCModels.METHODS[i]
	var lk := NPC.look(current)
	var node: Node3D
	if m == "billboard":
		var s := EntitySprite.new()
		s.setup(lk.tex, lk.frames, lk.sprite_size, false)
		if lk.trim >= 0.0:
			s.set_trim_bottom(lk.trim, lk.frame_h)
		if lk.has("tint"):
			s.set_tint(lk.tint)
		node = s
	elif m == "rendered":
		var r := RenderedSprite.new()
		r.setup_rendered(current)
		r.set_glow()
		node = r
	else:
		var model := NPCModel.new()
		model.setup(current, m)
		if lk.has("tint"):
			model.set_tint(lk.tint)
		model.set_full_light()
		node = model
	if _models[i] != null:
		_models[i].queue_free()
	_slots[i].add_child(node)
	_models[i] = node
	_show_frame(node)


## The frame the walk (or flap) cycle is on, as the game animates it.
func _frame_now() -> int:
	var d: Dictionary = Data.npcs[current]
	var wf: Array = d.get("walk_frames", d.get("fly_frames", [0, int(d.frames) - 1]))
	var n := int(wf[1]) - int(wf[0]) + 1
	return int(wf[0]) + int(_anim) % maxi(n, 1)


func _show_frame(node: Node3D) -> void:
	node.call("set_frame", _frame_now())


func choose(m: String) -> void:
	if current == "" or not m in NPCModels.METHODS:
		return
	if m in NPCModels.NOISE_METHODS:
		_settings_method = m
		_sync_settings_ui()
	if m == NPCModels.method(current):
		return
	NPCModels.set_method(current, m)
	dirty = true
	_refresh_choice()
	_fill_list()


func _refresh_choice() -> void:
	var i := NPCModels.METHODS.find(NPCModels.method(current))
	for j in _labels.size():
		_labels[j].modulate = Color(1.0, 0.85, 0.2) if j == i else Color(1, 1, 1)
	_marker.position = Vector3(_slot_x(i), 0, 0)
	_marker.scale = Vector3.ONE * maxf(_fit, 0.6)


func _sync_info() -> void:
	var fr := NPCModels.frames_of(current)
	var d: Dictionary = Data.npcs[current]
	var size: Vector2 = fr.size
	_info.text = "%s\n%s · %d frames\nSprite: %.2f x %.2f blocks\nArt: %d x %d pixels%s" % [
		Assets.npc_name(current), category(current).trim_suffix("s").replace("Bosse", "Boss"), int(d.frames),
		size.x, size.y, fr.arts[0].get_width(), fr.arts[0].get_height(),
		"\nShown at %d%% to fit" % roundi(_fit * 100.0) if _fit < 1.0 else ""]


func _sync_settings_ui() -> void:
	if current == "":
		return
	var o := NPCModels.options(current, _settings_method)
	var ex := NPCModels.options(current, "extruded")
	var mx := NPCModels.max_depth(current)
	_ex_title.text = "%s: %s" % [_settings_method.capitalize(), Assets.npc_name(current)]
	_ex_for.select(NPCModels.NOISE_METHODS.find(_settings_method))
	for c in _extruded_only:
		c.visible = _settings_method == "extruded"
	_ex_depth.max_value = mx
	_ex_depth.set_value_no_signal(ex.depth)
	_ex_depth_label.text = "Depth: %d voxels (%d%% of its width)" % [ex.depth, roundi(100.0 * ex.depth / mx)]
	_ex_noise.select(Data.EXTRUDE_NOISES.find(o.noise))
	_ex_strength.set_value_no_signal(o.strength)
	_ex_strength_label.text = "Noise strength: %d%%" % roundi(o.strength * 100.0)
	_ex_seed.set_value_no_signal(o.seed)
	_one_color.set_pressed_no_signal(o.one_color)
	_no_outline.visible = _settings_method in Data.OUTLINE_METHODS
	_no_outline.set_pressed_no_signal(o.get("no_outline", false))
	_render_outline.set_pressed_no_signal(NPCModels.options(current, "rendered").outline)
	_render_model.select(NPCModels.RENDER_MODELS.find(NPCModels.options(current, "rendered").model))
	_ex_bevel.select(Data.EXTRUDE_BEVELS.find(ex.bevel))
	_ex_bevel_size.set_value_no_signal(ex.bevel_size)
	_ex_bevel_label.text = "Bevel size: %d voxels" % ex.bevel_size
	for side in _ex_sides:
		_ex_sides[side].set_pressed_no_signal(side in ex.bevel_sides)
		_ex_sides[side].disabled = ex.bevel == "none"


func _toggle_bevel_side(side: String, on: bool) -> void:
	if current == "":
		return
	var sides: Array = NPCModels.options(current, "extruded").bevel_sides.duplicate()
	if on and not side in sides:
		sides.append(side)
	elif not on:
		sides.erase(side)
	_set_option("bevel_sides", BlockModelMesh.BEVEL_SIDES.filter(func(s): return s in sides), "extruded")
	get_viewport().gui_release_focus()


## Changes a setting of `m` (default: the one the panel is editing).
func _set_option(key: String, value, m := "") -> void:
	if m == "":
		m = _settings_method
	if current == "" or NPCModels.options(current, m).get(key) == value:
		return
	NPCModels.set_option(current, m, key, value)
	dirty = true
	_sync_settings_ui()
	_rebuild_methods[m] = true
	# The rendered sprite is shot again when the model it shoots changes.
	if m == "rendered" or m == NPCRenders.source(current):
		NPCRenders.forget(current)
		_rebuild_methods["rendered"] = true


func _save() -> void:
	if NPCModels.save(save_path):
		dirty = false
		_flash("Saved " + save_path)
	else:
		_flash("Could not save " + save_path)


func _flash(text: String) -> void:
	_status.text = text
	_message_time = 3.0


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		mouse = event.position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			get_viewport().gui_release_focus()
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_pick_at(event.position)
			MOUSE_BUTTON_MIDDLE:
				_orbiting = event.pressed and not event.shift_pressed
				_panning = event.pressed and event.shift_pressed
			MOUSE_BUTTON_WHEEL_UP:
				_dist = maxf(1.5, _dist * 0.9)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = minf(30.0, _dist / 0.9)
				_update_camera()
	elif event is InputEventMouseMotion:
		if _orbiting:
			_yaw -= event.relative.x * 0.008
			_pitch = clampf(_pitch + event.relative.y * 0.008, -0.2, 1.45)
			_update_camera()
		elif _panning:
			var b := _cam.global_transform.basis
			_target += (-b.x * event.relative.x + b.y * event.relative.y) * _dist * 0.0015
			_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return  # typing in the search box
		var k: int = event.keycode
		if event.ctrl_pressed and k == KEY_S:
			_save()
		elif k >= KEY_1 and k <= KEY_9 and k - KEY_1 < NPCModels.METHODS.size():
			choose(NPCModels.METHODS[k - KEY_1])
		elif k == KEY_0 and NPCModels.METHODS.size() >= 10:
			choose(NPCModels.METHODS[9])
		elif k in [KEY_PAGEDOWN, KEY_DOWN]:
			_step(1)
		elif k in [KEY_PAGEUP, KEY_UP]:
			_step(-1)
		elif k == KEY_SPACE:
			_spin = not _spin
		elif k == KEY_Q:
			_turn -= PI * 0.5
		elif k == KEY_E:
			_turn += PI * 0.5
		elif k == KEY_P:
			animate = not animate
		elif k == KEY_F1:
			_help.visible = not _help.visible
		elif k == KEY_BRACKETLEFT or k == KEY_BRACKETRIGHT:
			var o := NPCModels.options(current, "extruded")
			_set_option("depth", clampi(o.depth + (1 if k == KEY_BRACKETRIGHT else -1), 1, NPCModels.max_depth(current)), "extruded")
		elif k == KEY_B:
			var o := NPCModels.options(current, "extruded")
			var step := -1 if event.shift_pressed else 1
			_set_option("bevel", Data.EXTRUDE_BEVELS[posmod(Data.EXTRUDE_BEVELS.find(o.bevel) + step, Data.EXTRUDE_BEVELS.size())], "extruded")
		elif k == KEY_O:
			_set_option("one_color", not NPCModels.options(current, _settings_method).one_color)
		elif k == KEY_L and event.shift_pressed:
			_set_option("outline", not NPCModels.options(current, "rendered").outline, "rendered")
		elif k == KEY_L and _settings_method in Data.OUTLINE_METHODS:
			_set_option("no_outline", not NPCModels.options(current, _settings_method).no_outline)
		elif k == KEY_N and event.shift_pressed:
			_set_option("seed", (int(NPCModels.options(current, _settings_method).seed) + 1) % 10000)
		elif k == KEY_N:
			var o := NPCModels.options(current, _settings_method)
			_set_option("noise", Data.EXTRUDE_NOISES[(Data.EXTRUDE_NOISES.find(o.noise) + 1) % Data.EXTRUDE_NOISES.size()])
		else:
			return
		get_viewport().set_input_as_handled()


func _step(d: int) -> void:
	if _shown.is_empty():
		return
	select(_shown[wrapi(_shown.find(current) + d, 0, _shown.size())])


## Chooses the method whose model is nearest the click on screen.
func _pick_at(pos: Vector2) -> void:
	var best := -1
	var best_d := 100.0
	var h: float = NPCModels.frames_of(current).size.y * _fit * 0.5 if current != "" else 0.5
	for i in _slots.size():
		var p := _cam.unproject_position(_slots[i].global_position + Vector3(0, h, 0))
		var d := p.distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		choose(NPCModels.METHODS[best])


func _update_camera() -> void:
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_cam.global_position = _target + dir * _dist
	_cam.look_at(_target)


func _process(delta: float) -> void:
	for m in _rebuild_methods.keys():
		_make_model(NPCModels.METHODS.find(m))
	_rebuild_methods.clear()
	if animate and current != "":
		var before := _frame_now()
		_anim += delta * ANIM_FPS
		if _frame_now() != before:
			for node in _models:
				_show_frame(node)
	if _spin:
		_turn += delta * 0.9
	for s in _slots:
		s.rotation.y = lerp_angle(s.rotation.y, _turn, minf(1.0, delta * 10.0))
	_message_time -= delta
	if _message_time <= 0.0:
		_status.text = "Click a model or press 1-9, 0 to choose"
	_header.text = "%s  ·  %s%s" % [Assets.npc_name(current), NPCModels.method(current), "   ●  unsaved" if dirty else ""]


## The frame the models show (tests).
func frame() -> int:
	return _frame_now()


## The model node shown for method `m` (tests).
func model_for(m: String) -> Node3D:
	return _models[NPCModels.METHODS.find(m)]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not dirty:
			get_tree().quit()
			return
		var dlg := ConfirmationDialog.new()
		dlg.title = "Unsaved changes"
		dlg.dialog_text = "Save the NPC methods before quitting?"
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
