extends Control
## Sprite editor: chooses how the tree sprites (canopy, trunk) and cacti are
## made from Terraria's art - upscaler, smooth warp and pixel noise - with a
## live preview.
## Saves data/sprite_fx.json, which the game reads (SpriteFx). Run with
## ./sprite_editor.sh.
##
## Views: 1 sprite · 2 before / after · 3 trees (canopy and trunk together, at
## in-game proportions; for the cactus, a row of cacti on sand). Wheel zoom · MMB drag pan · F reset view ·
## PageUp/PageDown switch sprite · Ctrl+S save · F1 help.

const TARGET_NAMES := {"tree_canopy": "Tree canopy", "tree_trunk": "Tree trunk", "cactus": "Cactus"}
## Cacti shown as the cactus's styles: a few shapes (CactusArt.shape), the
## last two in Corruption and Crimson colours.
const CACTUS_SHAPES := [
	{"height": 5, "left": [1, 2], "right": [2, 4], "color": 0},
	{"height": 6, "left": [2, 4], "right": [], "color": 0},
	{"height": 4, "left": [], "right": [1, 3], "color": 0},
	{"height": 5, "left": [1, 3], "right": [2, 4], "color": 1},
	{"height": 5, "left": [2, 4], "right": [1, 3], "color": 3},
]
const SAND := Color(0.86, 0.76, 0.45)
const UPSCALE_NAMES := {
	"none": "None (original pixels)",
	"scale2x": "Scale2x (2x)", "scale2x_x2": "Scale2x twice (4x)",
	"eagle": "Eagle (2x)", "eagle_x2": "Eagle twice (4x)",
	"epb": "EPB (2x)", "epb_x2": "EPB twice (4x)",
}
const NOISE_NAMES := {"none": "None", "speckle": "Speckle", "palette": "Palette shades",
		"hue": "Hue + value", "blotch": "Blotches"}
const VIEWS := ["Sprite", "Before / after", "Trees"]
const CELLS := [1, 2, 4]
const SKY := Color(0.42, 0.61, 0.95)
const GROUND := Color(0.11, 0.55, 0.25)
const TREE_HEIGHT := 5  # trunk blocks in the trees view
const REBUILD_DELAY := 0.12  # seconds after the last change (sliders drag smoothly)

## Overridable before entering the tree (tests write elsewhere).
var save_path := SpriteFx.PATH
var target := "tree_canopy"
var style := 0
## The canopy's Tree_Tops sheet (CanopyArt.SHEETS index), or ALL_SHEETS for
## every one side by side; `style` is then the frame (0-2).
var sheet := 0
const ALL_SHEETS := -1
const ALL_ITEM := 99  # its id in the menu (-1 there means "automatic")
var view := 0
var dirty := false

var _opts := {}  # target -> settings being edited
var _canopy := {}  # style -> {image, k, px} (processed with _opts)
var _trunk: Array = []  # variant -> {image, k}
var _palm: Array = []  # palm_trunk variant -> {image, k} (the trunk's settings)
var _branches := {}  # [sheet, leafy, left, variant] -> {image, px} (the edited settings)
var _cactus: Array = []  # CACTUS_SHAPES index -> {image, k, px, margin}
var _textures := {}  # Image -> ImageTexture
var _pending := true
var _since_change := 0.0
var _zoom := 1.0
var _pan := Vector2.ZERO
var _panning := false
var _syncing := false
var _build_ms := 0

var _preview := Control.new()
var _ui := Control.new()
var _list := ItemList.new()
var _style := OptionButton.new()
var _style_row := HBoxContainer.new()
var _sheet := OptionButton.new()
var _sheet_row := HBoxContainer.new()
var _view := OptionButton.new()
var _header := Label.new()
var _status := Label.new()
var _help := PanelContainer.new()
var _title := Label.new()
var _upscale := OptionButton.new()
var _warp := HSlider.new()
var _warp_size := HSlider.new()
var _fade := HSlider.new()
var _fade_row := VBoxContainer.new()
var _warp_seed := SpinBox.new()
var _noise := OptionButton.new()
var _noise_strength := HSlider.new()
var _noise_cell := OptionButton.new()
var _noise_seed := SpinBox.new()
var _value_labels := {}  # slider -> [label, format]
var _message_time := 0.0


func _ready() -> void:
	get_tree().auto_accept_quit = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for t in SpriteFx.TARGETS:
		_opts[t] = SpriteFx.options(t)
	_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.draw.connect(_draw_preview)
	add_child(_preview)
	_build_ui()
	_select(target)


# ------------------------------------------------------------------ UI

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

	# Left: sprites, style, view, save.
	var left := _panel()
	left.offset_left = 12
	left.offset_top = 12
	left.offset_right = 250
	_ui.add_child(left)
	var box := VBoxContainer.new()
	left.add_child(box)
	box.add_child(_label("Sprites"))
	for t in SpriteFx.TARGETS:
		_list.add_item(TARGET_NAMES[t])
	_list.auto_height = true
	_list.item_selected.connect(func(i):
		_select(SpriteFx.TARGETS[i])
		get_viewport().gui_release_focus())
	box.add_child(_list)
	# Which of Terraria's tree tops the canopy previews (they all share its settings).
	_sheet_row.add_child(_label("Tree tops"))
	for k in CanopyArt.SHEETS.size():
		_sheet.add_item(CanopyArt.sheet_label(k), k)
	_sheet.add_item("All tree tops", ALL_ITEM)
	_sheet.fit_to_longest_item = false
	_sheet.custom_minimum_size.x = 150
	_sheet.clip_text = true
	_sheet.item_selected.connect(func(i):
		set_sheet(ALL_SHEETS if _sheet.get_item_id(i) == ALL_ITEM else _sheet.get_item_id(i))
		get_viewport().gui_release_focus())
	_sheet_row.add_child(_sheet)
	box.add_child(_sheet_row)
	_style_row.add_child(_label("Style"))
	_style.item_selected.connect(func(i):
		style = i
		_preview.queue_redraw())
	_style_row.add_child(_style)
	box.add_child(_style_row)
	var view_row := HBoxContainer.new()
	view_row.add_child(_label("View"))
	for v in VIEWS:
		_view.add_item(v)
	_view.item_selected.connect(func(i): set_view(i))
	view_row.add_child(_view)
	box.add_child(view_row)
	var save := Button.new()
	save.text = "Save (Ctrl+S)"
	save.pressed.connect(func():
		_save()
		get_viewport().gui_release_focus())
	box.add_child(save)

	# Right: settings for the selected sprite.
	var right := _panel()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -330
	right.offset_right = -12
	right.offset_top = 12
	_ui.add_child(right)
	var r := VBoxContainer.new()
	r.add_theme_constant_override("separation", 4)
	right.add_child(r)
	_title.add_theme_font_size_override("font_size", 22)
	r.add_child(_title)
	r.add_child(_section("Upscale"))
	for k in SpriteFx.UPSCALES:
		_upscale.add_item(UPSCALE_NAMES[k])
	_upscale.item_selected.connect(func(i): set_option("upscale", SpriteFx.UPSCALES.keys()[i]))
	r.add_child(_upscale)
	r.add_child(_section("Warp"))
	_slider(r, _warp, "Amount: %.2f art px", 0.0, 2.0, 0.05, "warp")
	_slider(r, _warp_size, "Size: %.2f art px", 0.5, 8.0, 0.25, "warp_size")
	_fade_row.add_theme_constant_override("separation", 4)
	_slider(_fade_row, _fade, "Fade at the bottom: %.1f art px", 0.0, 20.0, 0.5, "fade")
	r.add_child(_fade_row)
	_seed_box(r, _warp_seed, "warp_seed")
	r.add_child(_section("Noise"))
	for k in PixelArt.NOISES:
		_noise.add_item(NOISE_NAMES[k])
	_noise.item_selected.connect(func(i): set_option("noise", PixelArt.NOISES[i]))
	r.add_child(_noise)
	_slider(r, _noise_strength, "Strength: %d%%", 0.0, 1.0, 0.05, "noise_strength", 100.0)
	var cell_row := HBoxContainer.new()
	cell_row.add_child(_label("Patch size", 16))
	for c in CELLS:
		_noise_cell.add_item("%d px" % c)
	_noise_cell.item_selected.connect(func(i): set_option("noise_cell", CELLS[i]))
	cell_row.add_child(_noise_cell)
	r.add_child(cell_row)
	_seed_box(r, _noise_seed, "noise_seed")
	var buttons := HBoxContainer.new()
	var reset := Button.new()
	reset.text = "Defaults"
	reset.tooltip_text = "Back to the built-in settings for this sprite"
	reset.pressed.connect(func():
		_opts[target] = SpriteFx.sanitized(SpriteFx.DEFAULTS[target].duplicate())
		_changed())
	buttons.add_child(reset)
	var revert := Button.new()
	revert.text = "Revert to saved"
	revert.pressed.connect(func():
		SpriteFx.load_file(save_path)
		_opts[target] = SpriteFx.options(target)
		_changed())
	buttons.add_child(revert)
	r.add_child(buttons)

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
	ht.text = "1 / 2 / 3: sprite, before / after, trees   ·   PageUp/PageDown: sprite   ·   Left/Right: tree tops   ·   Ctrl+S: save\nWheel: zoom   ·   MMB drag: pan   ·   F: reset view   ·   F1: hide this help"
	_help.add_child(ht)
	_ui.add_child(_help)


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.16, 0.88)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(text: String, size := 0) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


func _section(text: String) -> Label:
	var l := _label(text)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	return l


func _slider(parent: Control, s: HSlider, fmt: String, lo: float, hi: float, step: float, key: String, mult := 1.0) -> void:
	var l := _label("", 16)
	parent.add_child(l)
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.x = 290
	s.value_changed.connect(func(v):
		l.text = fmt % (v * mult)
		set_option(key, v))
	parent.add_child(s)
	_value_labels[s] = [l, fmt, mult]


func _seed_box(parent: Control, b: SpinBox, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_child(_label("Seed", 16))
	b.min_value = 0
	b.max_value = 999
	b.value_changed.connect(func(v): set_option(key, int(v)))
	row.add_child(b)
	var roll := Button.new()
	roll.text = "New"
	roll.pressed.connect(func(): b.value = randi() % 1000)
	row.add_child(roll)
	parent.add_child(row)


func _fit_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := clampf(float(Settings.get_value("ui_scale")), 0.5, maxf(0.5, vp.x / 1450.0))
	_ui.scale = Vector2(s, s)
	_ui.size = vp / s


## Shows the settings of the selected sprite in the panel.
func _sync_ui() -> void:
	_syncing = true
	var o: Dictionary = _opts[target]
	_title.text = TARGET_NAMES[target]
	_upscale.select(SpriteFx.UPSCALES.keys().find(o.upscale))
	_warp.value = o.warp
	_warp_size.value = o.warp_size
	_fade.value = o.fade
	_warp_seed.value = o.warp_seed
	_noise.select(PixelArt.NOISES.find(o.noise))
	_noise_strength.value = o.noise_strength
	_noise_cell.select(maxi(0, CELLS.find(o.noise_cell)))
	_noise_seed.value = o.noise_seed
	for s in _value_labels:
		var e: Array = _value_labels[s]
		e[0].text = e[1] % (s.value * e[2])
	# Trunk tiles stack, so their warp repeats vertically instead of fading.
	_fade_row.visible = target != "tree_trunk"
	_style_row.visible = target != "tree_trunk"
	_sheet_row.visible = target == "tree_canopy"
	_sheet.select(_sheet.get_item_index(ALL_ITEM if sheet == ALL_SHEETS else sheet))
	# Canopy styles, or the sample cacti.
	var styles := CanopyArt.STYLES if target == "tree_canopy" else CACTUS_SHAPES.size()
	if _style.item_count != styles:
		_style.clear()
		for i in styles:
			_style.add_item("%d" % (i + 1))
	style = clampi(style, 0, styles - 1)
	_style.select(style)
	_syncing = false


# ------------------------------------------------------------------ state

## Shows another Tree_Tops sheet (or ALL_SHEETS), building what it needs.
func set_sheet(k: int) -> void:
	sheet = k if k == ALL_SHEETS else clampi(k, 0, CanopyArt.SHEETS.size() - 1)
	_sync_ui()
	_build_canopies()
	_preview.queue_redraw()


## The canopy style a sheet shows (the chosen frame of it).
func canopy_style(k := sheet) -> int:
	return (0 if k == ALL_SHEETS else k) * 10 + clampi(style, 0, 2)


## The canopy styles on screen: the sheet's three frames, or every sheet's.
func _shown_styles() -> Array[int]:
	var out: Array[int] = []
	for k in (range(CanopyArt.SHEETS.size()) if sheet == ALL_SHEETS else [sheet]):
		for f in 3:
			out.append(k * 10 + f)
	return out


## Builds the shown canopy styles not built yet (on worker threads).
func _build_canopies() -> void:
	var missing: Array[int] = []
	for st in _shown_styles():
		if not _canopy.has(st):
			missing.append(st)
	if not missing.is_empty():
		_canopy.merge(CanopyArt.build_all(_opts.tree_canopy, missing))


func _select(t: String) -> void:
	target = t
	_list.select(SpriteFx.TARGETS.find(t))
	_sync_ui()
	_preview.queue_redraw()


func set_view(v: int) -> void:
	view = clampi(v, 0, VIEWS.size() - 1)
	_view.select(view)
	_preview.queue_redraw()


## Changes one setting of the selected sprite (UI and tests).
func set_option(key: String, value) -> void:
	if _syncing or _opts[target][key] == value:
		return
	_opts[target][key] = value
	_opts[target] = SpriteFx.sanitized(_opts[target])
	dirty = true
	_pending = true
	_since_change = 0.0
	_sync_ui()  # when changed from code (the widgets already show it otherwise)


func _changed() -> void:
	_opts[target] = SpriteFx.sanitized(_opts[target])
	dirty = true
	_pending = true
	_since_change = REBUILD_DELAY
	_sync_ui()


## Re-processes the sprites with the settings being edited.
func rebuild() -> void:
	var t0 := Time.get_ticks_msec()
	_textures.clear()
	_canopy.clear()
	_build_canopies()
	_trunk.clear()
	var raw: Array = _trunk_raw()
	for v in raw.size():
		var art := PixelArt.downsample(raw[v], PixelArt.detect_scale(raw[v]))
		_trunk.append(SpriteFx.process(art, _opts.tree_trunk, v, true))
	_branches.clear()
	_palm.clear()
	for img in _palm_raw():
		_palm.append(SpriteFx.process(PixelArt.downsample(img, PixelArt.detect_scale(img)), _opts.tree_trunk, _palm.size(), true))
	_cactus.clear()
	for sh in CACTUS_SHAPES:
		_cactus.append(CactusArt.build(sh, _opts.cactus))
	_pending = false
	_build_ms = Time.get_ticks_msec() - t0
	_preview.queue_redraw()


func _palm_raw() -> Array:
	var d := Data.block(Data.block_id("palm_trunk"))
	return d.get("raw_sprites", d.get("sprites", []))


## Palm trees in the trees view: this tall, leaning this way (PalmArt).
const PALM_HEIGHT := 12


static func _palm_shape(s: int) -> Dictionary:
	# A palm that leans well (Terraria's lean is random; some stand straight).
	for i in 64:
		var sh := PalmArt.shape(Vector3i(i, s, 0), PALM_HEIGHT, Vector3.RIGHT)
		if sh.offsets[-1] >= 8:
			return sh
	return PalmArt.shape(Vector3i.ZERO, PALM_HEIGHT, Vector3.RIGHT)


func _tree_height(s: int) -> int:
	return PALM_HEIGHT if s / 10 == PalmArt.CANOPY_SHEET else TREE_HEIGHT


func _trunk_raw() -> Array:
	var d := Data.block(Data.block_id("tree_trunk"))
	return d.get("raw_sprites", d.get("sprites", []))


## World size of one trunk pixel: 16 texture pixels per block, finer by the upscale.
func _trunk_px(k: int) -> float:
	var d := Data.block(Data.block_id("tree_trunk"))
	var raw: Array = _trunk_raw()
	var art_k := PixelArt.detect_scale(raw[0]).x if not raw.is_empty() else 2
	return 1.0 / (float(d.get("fx_ppb", 16.0)) * k / art_k)


func _save() -> void:
	for t in _opts:
		SpriteFx.set_options(t, _opts[t])
	CactusArt.clear_cache()
	if SpriteFx.save(save_path):
		dirty = false
		_flash("Saved " + save_path + " (the game uses it next time it starts)")
	else:
		_flash("Could not save " + save_path)


func _flash(text: String) -> void:
	_status.text = text
	_message_time = 4.0


# ------------------------------------------------------------------ preview

func _tex(img: Image) -> ImageTexture:
	if not _textures.has(img):
		_textures[img] = ImageTexture.create_from_image(img)
	return _textures[img]


func _draw_preview() -> void:
	var size := _preview.size
	_preview.draw_rect(Rect2(Vector2.ZERO, size), SKY)
	if _canopy.is_empty():
		return
	# Fit the free area between the side panels.
	var left := (_ui.get_child(0) as Control).get_global_rect().end.x if _ui.get_child_count() > 0 else 0.0
	var right := _side_panel_left()
	var area := Rect2(left, 0, maxf(100.0, right - left), size.y)
	var center := area.get_center() + _pan
	match view:
		0:
			_draw_sprite(center, area.size)
		1:
			_draw_before_after(center, area.size)
		2:
			_draw_trees(center, area.size)


func _side_panel_left() -> float:
	for c in _ui.get_children():
		if c is PanelContainer and c.anchor_left == 1.0:
			return (c as Control).get_global_rect().position.x
	return _preview.size.x


## World blocks to screen pixels at the current zoom, fitting `blocks` (w x h)
## into `size`.
func _block_px(size: Vector2, blocks: Vector2) -> float:
	return minf(size.y * 0.7 / blocks.y, size.x * 0.9 / blocks.x) * _zoom


func _draw_sprite(center: Vector2, size: Vector2) -> void:
	if target == "cactus":
		var cc: Dictionary = _cactus[style]
		var cb := _block_px(size, Vector2(cc.image.get_width(), cc.image.get_height()) * cc.px)
		_draw_image(cc.image, center, cc.px * cb)
	elif target == "tree_canopy" and sheet == ALL_SHEETS:
		_draw_canopy_grid(center, size)
	elif target == "tree_canopy":
		var c: Dictionary = _canopy[canopy_style()]
		var b := _block_px(size, Vector2(c.image.get_width(), c.image.get_height()) * c.px)
		_draw_image(c.image, center, c.px * b)
	else:
		# Three variants stacked, as trunks are in game.
		var b := _block_px(size, Vector2(1.5, 3.0))
		for i in 3:
			var t: Dictionary = _trunk[(i * 5) % _trunk.size()]
			var img: Image = t.image
			var sc := _trunk_px(t.k) * b
			var h := img.get_height() * sc
			_draw_image(img, center + Vector2(0, (i - 1) * h), sc)


## Every sheet's canopy (the chosen frame) in a grid, named.
func _draw_canopy_grid(center: Vector2, size: Vector2) -> void:
	const COLS := 5
	var n := CanopyArt.SHEETS.size()
	var rows := ceili(float(n) / COLS)
	var cell := Vector2(7.5, 8.5)  # blocks per canopy, with room for its name
	var b := _block_px(size, Vector2(cell.x * COLS, cell.y * rows))
	for k in n:
		var c: Dictionary = _canopy[canopy_style(k)]
		var at := center + (Vector2(k % COLS, k / COLS) - Vector2(COLS - 1, rows - 1) * 0.5) * cell * b
		_draw_image(c.image, at - Vector2(0, 1.0 * b), c.px * b)
		_draw_name(k, at + Vector2(-cell.x * b * 0.5, cell.y * b * 0.5 - 22), cell.x * b)


func _draw_before_after(center: Vector2, size: Vector2) -> void:
	if target == "tree_canopy" and sheet == ALL_SHEETS:
		_draw_canopy_grid(center, size)
		return
	var before: Image
	var after: Image
	var before_px: float
	var after_px: float
	var shown: Dictionary = _canopy[canopy_style()]
	var tall: float = shown.image.get_height() * shown.px
	if target == "cactus":
		before = CactusArt.compose(CACTUS_SHAPES[style])
		before_px = 1.0 / CactusArt.ART
		after = _cactus[style].image
		after_px = _cactus[style].px
		tall = after.get_height() * after_px
	elif target == "tree_canopy":
		before = CanopyArt.frame_art(canopy_style())
		after = shown.image
		after_px = shown.px
		# An 80 px frame is SIZE wide (the jungle's bigger frames are bigger).
		before_px = CanopyArt.SIZE * CanopyArt.FRAMES[canopy_style() / 10].x / CanopyArt.FRAME / before.get_width()
	else:
		var raw: Image = _trunk_raw()[0]
		before = PixelArt.downsample(raw, PixelArt.detect_scale(raw))
		before_px = 1.0 / before.get_height()
		after = _trunk[0].image
		after_px = _trunk_px(_trunk[0].k)
		tall = 1.0
	var wide := maxf(after.get_width() * after_px, before.get_width() * before_px)
	var b := _block_px(size, Vector2(wide * 2.4, tall * 1.2))
	var gap := wide * b * 0.6
	_draw_image(before, center - Vector2(gap, 0), before_px * b)
	_draw_image(after, center + Vector2(gap, 0), after_px * b)
	var font := Assets.font("Mouse_Text")
	for i in 2:
		var x := center.x + (gap if i == 1 else -gap)
		var text: String = ["Before", "After"][i]
		_preview.draw_string(font, Vector2(x - 40, center.y + tall * b * 0.5 + 34), text, HORIZONTAL_ALIGNMENT_CENTER, 80, 24)


## Trees on the ground, like in game: trunks of TREE_HEIGHT blocks with mixed
## variants, the canopy overlapping the top block. One sheet: its three frames
## in a row; all sheets: rows of five (the chosen frame), each named.
func _draw_trees(center: Vector2, size: Vector2) -> void:
	if target == "cactus":
		_draw_cacti(center, size)
		return
	var styles: Array[int] = []
	if sheet == ALL_SHEETS:
		for k in CanopyArt.SHEETS.size():
			styles.append(canopy_style(k))
	else:
		styles = [sheet * 10, sheet * 10 + 1, sheet * 10 + 2]
	var cols := mini(styles.size(), 5)
	var rows := ceili(float(styles.size()) / cols)
	var tallest := 0
	for st in styles:
		tallest = maxi(tallest, _tree_height(st))
	# Rows of named trees: the names take LABEL_PX under each row's ground.
	const LABEL_PX := 46.0
	var label := LABEL_PX if rows > 1 else 0.0
	var tree_h := tallest + CanopyArt.SIZE
	var spacing := 7.5 if rows > 1 else 6.0
	var b := minf((size.y * 0.85 - rows * label) / (rows * tree_h), size.x * 0.9 / (spacing * cols)) * _zoom
	var row_px := tree_h * b + label
	for r in rows:
		var ground_y := center.y - rows * row_px * 0.5 + r * row_px + tree_h * b
		var strip := 8.0 if rows > 1 else _preview.size.y - ground_y
		_preview.draw_rect(Rect2(0, ground_y, _preview.size.x, strip), SAND if sheet == PalmArt.CANOPY_SHEET else GROUND)
		for col in cols:
			var n := r * cols + col
			if n < styles.size():
				_draw_tree(styles[n], center.x + (col - (cols - 1) * 0.5) * spacing * b, ground_y, b)
				if rows > 1:
					_draw_name(styles[n] / 10, Vector2(center.x + (col - cols * 0.5) * spacing * b, ground_y + 24), spacing * b)


## A sheet's name over its Tree_Tops number, centred in `width` from `at`.
func _draw_name(k: int, at: Vector2, width: float) -> void:
	var font := Assets.font("Mouse_Text")
	_preview.draw_string(font, at, CanopyArt.SHEET_NAMES[k], HORIZONTAL_ALIGNMENT_CENTER, width, 16)
	_preview.draw_string(font, at + Vector2(0, 16), CanopyArt.SHEETS[k], HORIZONTAL_ALIGNMENT_CENTER, width, 13, Color(1, 1, 1, 0.7))


## Branches for a tree in the trees view: a trunk TREE_HEIGHT tall with one
## on each side (TreeBranches' rules).
static func _branch_sample(s: int) -> Array:
	for i in 64:
		var bl := TreeBranches.branches(Vector3i(i, s, 1), TREE_HEIGHT)
		if bl.any(func(br): return br.left) and bl.any(func(br): return not br.left):
			return bl
	return []


func _draw_branches(s: int, x: float, ground_y: float, b: float) -> void:
	var sheet_name := TreeBranches.sheet_for(s)
	for br in _branch_sample(s):
		var key := [sheet_name, br.leafy, br.left, br.variant]
		if not _branches.has(key):
			var built := TreeBranches.build(sheet_name, "Tiles_5", br, _opts.tree_canopy, _opts.tree_trunk)
			if br.left:
				built.image = built.image.duplicate()
				built.image.flip_x()  # drawn pointing left, its stem on the right
			_branches[key] = built
		var art: Dictionary = _branches[key]
		var img: Image = art.image
		var w: float = img.get_width() * art.px * b
		var h: float = img.get_height() * art.px * b
		var cy: float = ground_y - (br.cell + 0.5) * b
		var start := TreeBranches.STEM_START * b
		var left_x: float = x - start - w if br.left else x + start
		_preview.draw_texture_rect(_tex(img), Rect2(left_x, cy - h * 0.5, w, h), false)


func _draw_tree(s: int, x: float, ground_y: float, b: float) -> void:
	if s / 10 == PalmArt.CANOPY_SHEET:
		_draw_palm(s, x, ground_y, b)
		return
	for i in TREE_HEIGHT:
		var t: Dictionary = _trunk[(s * 7 + i * 5) % _trunk.size()]
		var img: Image = t.image
		var sc := _trunk_px(t.k) * b
		# Each tile is one block tall, bottom at its block's bottom.
		var top := ground_y - (i + 1) * b
		_preview.draw_texture_rect(_tex(img), Rect2(x - img.get_width() * sc * 0.5, top, img.get_width() * sc, img.get_height() * sc), false)
	_draw_branches(s, x, ground_y, b)
	var c: Dictionary = _canopy[s]
	var cimg: Image = c.image
	var csc: float = c.px * b
	var bottom := ground_y - (TREE_HEIGHT - 0.6) * b
	_preview.draw_texture_rect(_tex(cimg), Rect2(x - cimg.get_width() * csc * 0.5, bottom - cimg.get_height() * csc,
			cimg.get_width() * csc, cimg.get_height() * csc), false)


## A palm: its segments along the curve (each hangs a quarter block into the
## one below, drawn top first like Terraria's), the canopy on the end.
func _draw_palm(s: int, x: float, ground_y: float, b: float) -> void:
	var sh := _palm_shape(s)
	var raw: Array = _palm_raw()
	var art_k := PixelArt.detect_scale(raw[0]).x if not raw.is_empty() else 2
	for k in range(PALM_HEIGHT - 1, -1, -1):
		var t: Dictionary = _palm[sh.frames[k]]
		var img: Image = t.image
		var sc: float = b / (16.0 * t.k / art_k)
		var sx: float = x + sh.offsets[k] / PalmArt.PX * b
		var top := ground_y - (k + 1) * b
		_preview.draw_texture_rect(_tex(img), Rect2(sx - img.get_width() * sc * 0.5, top, img.get_width() * sc, img.get_height() * sc), false)
	var c: Dictionary = _canopy[s]
	var cimg: Image = c.image
	var csc: float = c.px * b
	var cx: float = x + sh.offsets[-1] / PalmArt.PX * b
	var bottom := ground_y - (PALM_HEIGHT - 1) * b
	_preview.draw_texture_rect(_tex(cimg), Rect2(cx - cimg.get_width() * csc * 0.5, bottom - cimg.get_height() * csc,
			cimg.get_width() * csc, cimg.get_height() * csc), false)


## The sample cacti in a row on sand, standing on their bases like in game.
func _draw_cacti(center: Vector2, size: Vector2) -> void:
	var n := _cactus.size()
	var b := _block_px(size, Vector2(4.0 * n, 7.0))
	var ground_y := center.y + 3.5 * b
	_preview.draw_rect(Rect2(0, ground_y, _preview.size.x, _preview.size.y - ground_y), SAND)
	for i in n:
		var c: Dictionary = _cactus[i]
		var img: Image = c.image
		var sc: float = c.px * b
		var x := center.x + (i - (n - 1) * 0.5) * 4.0 * b
		var bottom: float = ground_y + c.margin.y * sc
		_preview.draw_texture_rect(_tex(img), Rect2(x - img.get_width() * sc * 0.5, bottom - img.get_height() * sc, img.get_width() * sc, img.get_height() * sc), false)


func _draw_image(img: Image, center: Vector2, scale: float) -> void:
	var s := Vector2(img.get_size()) * scale
	_preview.draw_texture_rect(_tex(img), Rect2(center - s * 0.5, s), false)


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_S when event.ctrl_pressed:
				_save()
			KEY_1, KEY_2, KEY_3:
				set_view(event.keycode - KEY_1)
			KEY_PAGEUP, KEY_PAGEDOWN:
				var i := SpriteFx.TARGETS.find(target) + (1 if event.keycode == KEY_PAGEDOWN else -1)
				_select(SpriteFx.TARGETS[wrapi(i, 0, SpriteFx.TARGETS.size())])
			KEY_LEFT, KEY_RIGHT when target == "tree_canopy":
				# Next / previous tree tops (All after the last).
				var ids: Array = range(CanopyArt.SHEETS.size()) + [ALL_SHEETS]
				set_sheet(ids[wrapi(ids.find(sheet) + (1 if event.keycode == KEY_RIGHT else -1), 0, ids.size())])
			KEY_F:
				_zoom = 1.0
				_pan = Vector2.ZERO
				_preview.queue_redraw()
			KEY_F1:
				_help.visible = not _help.visible
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP when event.pressed:
				_zoom = minf(_zoom * 1.15, 12.0)
				_preview.queue_redraw()
			MOUSE_BUTTON_WHEEL_DOWN when event.pressed:
				_zoom = maxf(_zoom / 1.15, 0.2)
				_preview.queue_redraw()
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
	elif event is InputEventMouseMotion and _panning:
		_pan += event.relative
		_preview.queue_redraw()


func _process(delta: float) -> void:
	if _pending:
		_since_change += delta
		if _since_change >= REBUILD_DELAY:
			rebuild()
	_message_time -= delta
	if _message_time <= 0.0:
		_status.text = "Built in %d ms" % _build_ms if not _pending else "Building..."
	_header.text = "%s  ·  %s%s" % [TARGET_NAMES[target], VIEWS[view], "   ●  unsaved" if dirty else ""]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not dirty:
			get_tree().quit()
			return
		var dlg := ConfirmationDialog.new()
		dlg.title = "Unsaved changes"
		dlg.dialog_text = "Save the sprite settings before quitting?"
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
