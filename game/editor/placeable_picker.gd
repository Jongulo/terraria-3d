extends Node3D
## Placeable picker: choose how each placeable block (chest, work bench, pots,
## torches...) is turned into 3D. Shows the selected block in every method side
## by side; pick one by clicking it or pressing 1-9 and 0. Saves data/placeables.json,
## which the game reads. Run with ./placeable_picker.sh.
##
## Controls: click / 1-9, 0 choose a method · PageUp/PageDown (or Up/Down) change
## block · Space turntable · Q/E turn models · MMB orbit, Shift+MMB pan,
## wheel zoom · Ctrl+S save · F1 help
## Settings panel (right): pixel noise, strength and seed for Extruded, Hull,
## Hull Top, Lathe, Claude's hand-made models and tuned models ("Settings for" picks which; it follows the chosen
## method), one colour per voxel (O) for all of them, plus
## depth, bevel and which sides are bevelled (edges top / bottom / left / right,
## faces front / back) for Extruded. Transform panel (below it): the block's model
## offset (art pixels), rotation (degrees) and scale, for every method
## (billboards take offset and scale only: they always face you). [ / ] depth -/+1 voxel, N next noise mode,
## Shift+N new seed, B / Shift+B next / previous bevel profile.

const SPACING := 1.8
## The ground texture's repeat, in blocks.
const GRASS_BLOCKS := 6
const DESCRIPTIONS := {
	"panels": "Sprite on the four sides",
	"cross": "Two crossed planes",
	"billboard": "Always faces you",
	"flat": "1 voxel thick cut-out",
	"extruded": "Pushed through the block",
	"hull": "Front + side silhouettes",
	"hull_top": "Front + top silhouettes",
	"lathe": "Outline spun around",
	"claude": "Hand-made voxels",
	"tuned": "Sculpted by you",
}

## Overridable before entering the tree (tests write elsewhere).
var save_path := Data.PLACEABLES_PATH
var current := ""
var dirty := false
var mouse := Vector2.ZERO

var _cam := Camera3D.new()
var _yaw := 0.35
var _pitch := 0.32
var _dist := 11.5  # all 10 methods fit between the side panels
var _target := Vector3(2.6, 0.55, 0)  # the row runs away to the left: aim right of its middle
var _orbiting := false
var _panning := false
var _spin := false
var _turn := 0.0
var _stage := Node3D.new()
var _models: Array[Node3D] = []
var _labels: Array[Label3D] = []
var _backings: Array[Node3D] = []  # the stone block each wall model hangs on
var _marker := MeshInstance3D.new()
var _player := Sprite3D.new()
var _materials := {}

var _ui := Control.new()
var _list := ItemList.new()
var _names: Array = []
var _header := Label.new()
var _status := Label.new()
var _help := PanelContainer.new()
var _message_time := 0.0
var _ex_title := Label.new()
var _ex_depth := HSlider.new()
var _ex_depth_label := Label.new()
var _ex_noise := OptionButton.new()
var _ex_strength := HSlider.new()
var _ex_strength_label := Label.new()
var _ex_seed := SpinBox.new()
## Every voxel one colour (all voxel methods).
var _one_color := CheckBox.new()
var _ex_bevel := OptionButton.new()
var _ex_bevel_size := HSlider.new()
var _ex_bevel_label := Label.new()
var _rebuild_methods := {}
## The animation frame the models show (animated blocks; -1: not animated).
var _anim_frame := -1
## Which method the settings panel edits: "extruded", "hull" or "lathe".
var _settings_method := "extruded"
var _ex_for := OptionButton.new()
var _ex_bevel_title := Label.new()
var _ex_sides_label := Label.new()
var _ex_sides := {}  # BlockModelMesh.BEVEL_SIDES entry -> CheckBox
var _ex_sides_rows: Array[Control] = []
var _extruded_only: Array[Control] = []
var _tr_title := Label.new()
var _tr_spins := {}  # "offset" / "rotation" -> [SpinBox x, y, z]
var _tr_scale := SpinBox.new()
var _rebuild_all := false


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_build_scene()
	_build_ui()
	_names = Data.placeable_blocks()
	for n in _names:
		var d := Data.block(Data.block_id(n))
		var icon := ImageTexture.create_from_image(d.sprite)
		_list.add_item(n.replace("_", " ").capitalize(), icon)
	if not _names.is_empty():
		_select_block(_names[0])
		_list.select(0)


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
	# A Terraria player (as the inventory draws them) standing at the row's
	# end, for scale.
	_player.texture = ImageTexture.create_from_image(PaperDoll.standing_image())
	_player.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_player.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_player.shaded = false
	_player.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_player.centered = true
	_player.offset = Vector2(0, PaperDoll.standing_image().get_height() * 0.5)  # stands on the ground
	add_child(_player)
	# Selection marker: a gold square under the chosen method.
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var pts := [Vector3(-0.7, 0.02, -0.7), Vector3(0.7, 0.02, -0.7), Vector3(0.7, 0.02, 0.7), Vector3(-0.7, 0.02, 0.7)]
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

	var left := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.16, 0.88)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(6)
	left.add_theme_stylebox_override("panel", sb)
	left.offset_left = 12
	left.offset_top = 12
	left.offset_right = 250
	left.anchor_bottom = 1.0
	left.offset_bottom = -12
	_ui.add_child(left)
	var box := VBoxContainer.new()
	left.add_child(box)
	var t := Label.new()
	t.text = "Placeables"
	box.add_child(t)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(28, 28)
	_list.item_selected.connect(func(i):
		_select_block(_names[i])
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
	_build_extrude_panel(right)
	_build_transform_panel(right)

	_header.position = Vector2(270, 10)
	_header.add_theme_font_size_override("font_size", 24)
	_ui.add_child(_header)
	_status.position = Vector2(270, 40)
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
	ht.text = "Click a model or press 1-9, 0 to choose its method   ·   PageUp/PageDown: block\nSpace: turntable   Q/E: turn   MMB: orbit   Shift+MMB: pan   Wheel: zoom\nNoise: N mode   Shift+N seed   O one colour per voxel   ·   Extruded: [ ] depth   B bevel   ·   Ctrl+S: save"
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


func _build_extrude_panel(parent: Control) -> void:
	var panel := _side_panel(parent)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	_ex_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_ex_title)
	var fl := Label.new()
	fl.text = "Settings for"
	fl.add_theme_font_size_override("font_size", 16)
	box.add_child(fl)
	for m in Data.NOISE_METHODS:
		_ex_for.add_item(m.capitalize())
	_ex_for.item_selected.connect(func(i):
		_settings_method = Data.NOISE_METHODS[i]
		_sync_extrude_ui()
		get_viewport().gui_release_focus())
	box.add_child(_ex_for)

	_ex_depth_label.add_theme_font_size_override("font_size", 16)
	box.add_child(_ex_depth_label)
	_ex_depth.min_value = 1
	_ex_depth.step = 1
	_ex_depth.value_changed.connect(func(v): _set_extrude("depth", int(v)))
	box.add_child(_ex_depth)

	var nl := Label.new()
	nl.text = "Side noise"
	nl.add_theme_font_size_override("font_size", 16)
	box.add_child(nl)
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
	var sl := Label.new()
	sl.text = "Seed"
	sl.add_theme_font_size_override("font_size", 16)
	row.add_child(sl)
	_ex_seed.min_value = 0
	_ex_seed.max_value = 9999
	_ex_seed.step = 1
	_ex_seed.value_changed.connect(func(v): _set_option("seed", int(v)))
	row.add_child(_ex_seed)
	box.add_child(row)

	_ex_bevel_title.text = "Bevel"
	_ex_bevel_title.add_theme_font_size_override("font_size", 16)
	box.add_child(_ex_bevel_title)
	for b in Data.EXTRUDE_BEVELS:
		_ex_bevel.add_item(b.capitalize())
	_ex_bevel.item_selected.connect(func(i):
		_set_extrude("bevel", Data.EXTRUDE_BEVELS[i])
		get_viewport().gui_release_focus())
	box.add_child(_ex_bevel)
	_ex_bevel_label.add_theme_font_size_override("font_size", 16)
	box.add_child(_ex_bevel_label)
	_ex_bevel_size.min_value = 1
	_ex_bevel_size.max_value = Data.BEVEL_MAX
	_ex_bevel_size.step = 1
	_ex_bevel_size.value_changed.connect(func(v): _set_extrude("bevel_size", int(v)))
	box.add_child(_ex_bevel_size)
	# Which sides get the bevel: edges of the silhouette, and the two faces.
	_ex_sides_label.text = "Bevel sides"
	_ex_sides_label.add_theme_font_size_override("font_size", 16)
	box.add_child(_ex_sides_label)
	for group in [["Edges", ["top", "bottom", "left", "right"]], ["Faces", ["front", "back"]]]:
		var sides_row := HBoxContainer.new()
		var gl := Label.new()
		gl.text = group[0]
		gl.custom_minimum_size.x = 52
		gl.add_theme_font_size_override("font_size", 14)
		sides_row.add_child(gl)
		for side in group[1]:
			var cb := CheckBox.new()
			cb.text = side.capitalize()
			cb.add_theme_font_size_override("font_size", 14)
			cb.toggled.connect(func(on): _toggle_bevel_side(side, on))
			sides_row.add_child(cb)
			_ex_sides[side] = cb
		box.add_child(sides_row)
		_ex_sides_rows.append(sides_row)

	_extruded_only = [_ex_depth_label, _ex_depth, _ex_bevel_title, _ex_bevel, _ex_bevel_label, _ex_bevel_size, _ex_sides_label]
	_extruded_only.append_array(_ex_sides_rows)
	_one_color.text = "One colour per voxel (O)"
	_one_color.add_theme_font_size_override("font_size", 16)
	_one_color.toggled.connect(func(on):
		_set_option("one_color", on)
		get_viewport().gui_release_focus())
	box.add_child(_one_color)
	var reset := Button.new()
	reset.text = "Reset these settings"
	reset.pressed.connect(func():
		Data.reset_method_options(current, _settings_method)
		dirty = true
		_sync_extrude_ui()
		_rebuild_methods[_settings_method] = true
		get_viewport().gui_release_focus())
	box.add_child(reset)
	var hint := Label.new()
	hint.text = "[ ] depth   N noise   Shift+N seed   B bevel   O one colour"
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)


## Transform panel: offset, rotation (X / Y / Z) and scale of the block's model.
func _build_transform_panel(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_side_panel(parent).add_child(box)
	_tr_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_tr_title)
	for key in ["offset", "rotation"]:
		var l := Label.new()
		l.text = "Offset (art pixels)" if key == "offset" else "Rotation (degrees)"
		l.add_theme_font_size_override("font_size", 16)
		box.add_child(l)
		var row := HBoxContainer.new()
		var spins: Array = []
		for axis in 3:
			var al := Label.new()
			al.text = "XYZ"[axis]
			al.add_theme_font_size_override("font_size", 16)
			row.add_child(al)
			var sp := SpinBox.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sp.custom_minimum_size.x = 0
			if key == "offset":
				sp.min_value = -64
				sp.max_value = 64
				sp.step = 1
			else:
				sp.min_value = -180
				sp.max_value = 180
				sp.step = 1
				sp.custom_arrow_step = 15
			sp.value_changed.connect(func(v): _set_transform_axis(key, axis, v))
			row.add_child(sp)
			spins.append(sp)
		_tr_spins[key] = spins
		box.add_child(row)
	var srow := HBoxContainer.new()
	var sl := Label.new()
	sl.text = "Scale %"
	sl.add_theme_font_size_override("font_size", 16)
	srow.add_child(sl)
	_tr_scale.min_value = 5
	_tr_scale.max_value = 800
	_tr_scale.step = 5
	_tr_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tr_scale.value_changed.connect(func(v): _set_transform("scale", v / 100.0))
	srow.add_child(_tr_scale)
	box.add_child(srow)
	var reset := Button.new()
	reset.text = "Reset transform"
	reset.pressed.connect(func():
		if Data.transform_settings.has(current):
			Data.reset_transform(current)
			_transform_changed()
		get_viewport().gui_release_focus())
	box.add_child(reset)


func _set_transform_axis(key: String, axis: int, value: float) -> void:
	var v: Array = Data.transform_options(current)[key].duplicate()
	v[axis] = value
	_set_transform(key, v)


## Changes a transform setting of the current block ("offset"/"rotation":
## [x, y, z], "scale": factor).
func _set_transform(key: String, value) -> void:
	if current == "" or Data.transform_options(current)[key] == value:
		return
	Data.set_transform_option(current, key, value)
	_transform_changed()


func _transform_changed() -> void:
	dirty = true
	_sync_transform_ui()
	_rebuild_all = true


func _sync_transform_ui() -> void:
	if current == "":
		return
	var o := Data.transform_options(current)
	_tr_title.text = "Transform: %s" % current.replace("_", " ").capitalize()
	for key in _tr_spins:
		for axis in 3:
			_tr_spins[key][axis].set_value_no_signal(o[key][axis])
	_tr_scale.set_value_no_signal(roundf(o.scale * 100.0))


func _sync_extrude_ui() -> void:
	if current == "":
		return
	var o := Data.method_options(current, _settings_method)  # noise, strength, seed
	var ex := Data.extrude_options(current)  # depth and bevel (Extruded only)
	var mx := Data.extrude_max_depth(current)
	_ex_title.text = "%s: %s" % [_settings_method.capitalize(), current.replace("_", " ").capitalize()]
	_ex_for.select(Data.NOISE_METHODS.find(_settings_method))
	for c in _extruded_only:
		c.visible = _settings_method == "extruded"
	_ex_depth.max_value = mx
	_ex_depth.set_value_no_signal(ex.depth)
	_ex_depth_label.text = "Depth: %d voxels (%d%% of a block)" % [ex.depth, roundi(100.0 * ex.depth / mx)]
	_ex_noise.select(Data.EXTRUDE_NOISES.find(o.noise))
	_ex_strength.set_value_no_signal(o.strength)
	_ex_strength_label.text = "Noise strength: %d%%" % roundi(o.strength * 100.0)
	_ex_seed.set_value_no_signal(o.seed)
	_one_color.set_pressed_no_signal(o.one_color)
	_ex_bevel.select(Data.EXTRUDE_BEVELS.find(ex.bevel))
	_ex_bevel_size.set_value_no_signal(ex.bevel_size)
	_ex_bevel_label.text = "Bevel size: %d voxels" % ex.bevel_size
	for side in _ex_sides:
		_ex_sides[side].set_pressed_no_signal(side in ex.bevel_sides)
		_ex_sides[side].disabled = ex.bevel == "none"


## Turns the bevel on or off for one side (an edge of the silhouette or a face).
func _toggle_bevel_side(side: String, on: bool) -> void:
	if current == "":
		return
	var sides: Array = Data.extrude_options(current).bevel_sides.duplicate()
	if on and not side in sides:
		sides.append(side)
	elif not on:
		sides.erase(side)
	_set_extrude("bevel_sides", BlockModelMesh.BEVEL_SIDES.filter(func(s): return s in sides))
	get_viewport().gui_release_focus()


## Changes an Extruded setting (depth, bevel...; noise via _set_option).
func _set_extrude(key: String, value) -> void:
	_set_option(key, value, "extruded")


## Changes a setting of `method` (default: the one the panel is editing).
func _set_option(key: String, value, method := "") -> void:
	if method == "":
		method = _settings_method
	if current == "" or Data.method_options(current, method).get(key) == value:
		return
	Data.set_method_option(current, method, key, value)
	dirty = true
	_sync_extrude_ui()
	_rebuild_methods[method] = true


## Replaces just one method's model (its mesh depends on the settings).
func _rebuild_model(method: String) -> void:
	var i := Data.PLACEABLE_METHODS.find(method)
	if i < 0 or i >= _models.size():
		return
	var old := _models[i]
	var node := BlockModels.make_model(Data.block_id(current), method, 0, _materials, maxi(_anim_frame, 0))
	_stage.add_child(node)
	_place_model(node, i, _fit_scale(Data.block_id(current)))
	node.rotation = old.rotation
	_models[i] = node
	old.queue_free()


## The ground: the game's grass block top (its texture array layers), a
## GRASS_BLOCKS square of blocks with the variants mixed like the world's.
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


func _fit_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := clampf(float(Settings.get_value("ui_scale")), 0.5, maxf(0.5, vp.x / 1450.0))
	_ui.scale = Vector2(s, s)
	_ui.size = vp / s


# ------------------------------------------------------------------ model

func _method_of(name: String) -> String:
	return Data.block(Data.block_id(name)).get("method", "panels")


func _select_block(name: String) -> void:
	current = name
	for m in _models:
		m.queue_free()
	for l in _labels:
		l.queue_free()
	for b in _backings:
		b.queue_free()
	_models.clear()
	_labels.clear()
	_backings.clear()
	var id := Data.block_id(name)
	_anim_frame = Data.anim_frame_now(Data.block(id)) if Data.anim_frames(Data.block(id)) > 1 else -1
	var on_wall: bool = Data.block(id).get("wall", false)
	var n := Data.PLACEABLE_METHODS.size()
	var fit := _fit_scale(id)
	for i in n:
		var method: String = Data.PLACEABLE_METHODS[i]
		var x := (i - (n - 1) * 0.5) * SPACING
		var node := BlockModels.make_model(id, method, 0, _materials, maxi(_anim_frame, 0))
		_stage.add_child(node)
		_place_model(node, i, fit)
		_models.append(node)
		if on_wall:
			# Wall models (wall torch) face +z out of a wall behind them.
			var back := _stone_block()
			_stage.add_child(back)
			back.position = Vector3(x, 0.5 * fit, -fit)
			back.scale = Vector3.ONE * fit
			_backings.append(back)
		var lab := Label3D.new()
		lab.text = "%d  %s\n%s" % [i + 1, method.capitalize(), DESCRIPTIONS[method]]
		if method == "claude" and not has_handmade(current):
			lab.text = "%d  Claude\nNot made yet (shows Hull)" % (i + 1)
		elif method == "tuned" and not TunedModels.has(TunedModels.block_key(_settings_name(current))):
			lab.text = "%d  Tuned\nNot tuned yet (shows Hull)" % (i + 1)
		lab.font = Assets.font("Mouse_Text")
		lab.font_size = 18
		lab.pixel_size = 0.012
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_stage.add_child(lab)
		lab.position = Vector3(x, 1.45, 0)
		_labels.append(lab)
	# The player shrinks with the models, so it stays to scale with them.
	_player.pixel_size = PaperDoll.player_pixel_size() * fit
	_player.position = Vector3(-(n - 1) * 0.5 * SPACING - 1.1, 0, 0)
	_refresh_choice()
	_sync_extrude_ui()
	_sync_transform_ui()


## Puts method `i`'s model in its slot of the row, shrunk by `fit`. Billboard
## sprites carry the block's offset and scale on the node (meshes have them
## baked in), so those are kept.
func _place_model(node: Node3D, i: int, fit: float) -> void:
	var n := Data.PLACEABLE_METHODS.size()
	node.position = Vector3((i - (n - 1) * 0.5) * SPACING, 0, 0) + node.position * fit
	node.scale *= fit  # billboards keep their size in their scale


static var _stone_mat: StandardMaterial3D


## A stone block (Terraria's stone texture) for wall models to hang on.
func _stone_block() -> MeshInstance3D:
	if _stone_mat == null:
		_stone_mat = StandardMaterial3D.new()
		_stone_mat.albedo_texture = ImageTexture.create_from_image(
				Assets.image("Images/Tiles_1").get_region(Rect2i(18, 18, 16, 16)))
		_stone_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_stone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # like the models
		_stone_mat.uv1_scale = Vector3(3, 2, 1)  # one tile per face of the box
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = _stone_mat
	return mi


## Scale that shrinks models bigger than a block (tree canopies are 5 blocks
## wide) to fit their slot in the row; block-sized ones stay at 1.
func _fit_scale(id: int) -> float:
	var d := Data.block(id)
	var img: Image = d.sprite
	var size := maxf(img.get_width(), img.get_height()) * float(d.sprite_px)
	return minf(1.0, 1.4 / size)


## True if Claude has made a voxel model for the block (the "claude" method).
func has_handmade(name: String) -> bool:
	return Data.handmade_models.has(_settings_name(name))


## The name a block's settings (and hand-made or tuned model) go by.
func _settings_name(name: String) -> String:
	return Data.block(Data.block_id(name)).get("settings", name)


func choose(method: String) -> void:
	if method == "claude" and not has_handmade(current):
		_flash("No hand-made model for %s yet" % current.replace("_", " "))
		return
	if method == "tuned" and not TunedModels.has(TunedModels.block_key(_settings_name(current))):
		_flash("%s isn't tuned yet: sculpt it in ./model_sculptor.sh" % current.replace("_", " ").capitalize())
		return
	if method in Data.NOISE_METHODS:
		_settings_method = method
		_sync_extrude_ui()
	if current == "" or method == _method_of(current):
		return
	Data.set_block_method(current, method)
	dirty = true
	_refresh_choice()


func _refresh_choice() -> void:
	var chosen := _method_of(current)
	var i := Data.PLACEABLE_METHODS.find(chosen)
	for j in _labels.size():
		_labels[j].modulate = Color(1.0, 0.85, 0.2) if j == i else Color(1, 1, 1)
	var n := Data.PLACEABLE_METHODS.size()
	_marker.position = Vector3((i - (n - 1) * 0.5) * SPACING, 0, 0)


func _save() -> void:
	if Data.save_placeables(save_path):
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
		var k: int = event.keycode
		if event.ctrl_pressed and k == KEY_S:
			_save()
		elif k >= KEY_1 and k <= KEY_9 and k - KEY_1 < Data.PLACEABLE_METHODS.size():
			choose(Data.PLACEABLE_METHODS[k - KEY_1])
		elif k == KEY_0 and Data.PLACEABLE_METHODS.size() >= 10:
			choose(Data.PLACEABLE_METHODS[9])
		elif k == KEY_O:
			_set_option("one_color", not Data.method_options(current, _settings_method).one_color)
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
		elif k == KEY_F1:
			_help.visible = not _help.visible
		elif k == KEY_BRACKETLEFT or k == KEY_BRACKETRIGHT:
			var o := Data.extrude_options(current)
			_set_extrude("depth", clampi(o.depth + (1 if k == KEY_BRACKETRIGHT else -1), 1, Data.extrude_max_depth(current)))
		elif k == KEY_B:
			var o := Data.extrude_options(current)
			var step := -1 if event.shift_pressed else 1
			_set_extrude("bevel", Data.EXTRUDE_BEVELS[posmod(Data.EXTRUDE_BEVELS.find(o.bevel) + step, Data.EXTRUDE_BEVELS.size())])
		elif k == KEY_N and event.shift_pressed:
			_set_option("seed", (int(Data.method_options(current, _settings_method).seed) + 1) % 10000)
		elif k == KEY_N:
			var o := Data.method_options(current, _settings_method)
			_set_option("noise", Data.EXTRUDE_NOISES[(Data.EXTRUDE_NOISES.find(o.noise) + 1) % Data.EXTRUDE_NOISES.size()])
		else:
			return
		get_viewport().set_input_as_handled()


func _step(d: int) -> void:
	if _names.is_empty():
		return
	var i := wrapi(_names.find(current) + d, 0, _names.size())
	_list.select(i)
	_list.ensure_current_is_visible()
	_select_block(_names[i])


## Chooses the method whose model is nearest the click on screen.
func _pick_at(pos: Vector2) -> void:
	var best := -1
	var best_d := 90.0
	for i in _models.size():
		var p := _cam.unproject_position(_models[i].global_position + Vector3(0, 0.5, 0))
		var d := p.distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		choose(Data.PLACEABLE_METHODS[best])


func _update_camera() -> void:
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_cam.global_position = _target + dir * _dist
	_cam.look_at(_target)


func _process(delta: float) -> void:
	if _rebuild_all:
		_rebuild_all = false
		_rebuild_methods.clear()
		for m in Data.PLACEABLE_METHODS:
			_rebuild_model(m)
	for m in _rebuild_methods.keys():
		_rebuild_model(m)
	_rebuild_methods.clear()
	_animate_models()
	if _spin:
		_turn += delta * 0.9
	for m in _models:
		if not (m is EntitySprite):
			m.rotation.y = lerp_angle(m.rotation.y, _turn, minf(1.0, delta * 10.0))
	_message_time -= delta
	if _message_time <= 0.0:
		_status.text = "Click a model or press 1-9, 0 to choose"
	_header.text = "%s  ·  %s%s" % [current.replace("_", " ").capitalize(), _method_of(current), "   ●  unsaved" if dirty else ""]


## An animated block's models step through its frames, like in the world.
func _animate_models() -> void:
	if _anim_frame < 0 or current == "":
		return
	var id := Data.block_id(current)
	var frame := Data.anim_frame_now(Data.block(id))
	if frame == _anim_frame:
		return
	_anim_frame = frame
	for i in mini(_models.size(), Data.PLACEABLE_METHODS.size()):
		BlockModels.set_model_frame(_models[i], id, Data.PLACEABLE_METHODS[i], frame, 0, _materials)


## The frame the models show (-1: the block isn't animated; tests).
func anim_frame() -> int:
	return _anim_frame


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not dirty:
			get_tree().quit()
			return
		var dlg := ConfirmationDialog.new()
		dlg.title = "Unsaved changes"
		dlg.dialog_text = "Save the placeable methods before quitting?"
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
