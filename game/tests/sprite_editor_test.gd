extends Node
## Sprite FX (upscalers, noise, settings) and the sprite editor tool.

const SAVE := "user://sprite_editor_test.json"

var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func key(code: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		Input.parse_input_event(e)
		await frames(1)


func _colors(img: Image) -> Dictionary:
	var out := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				out[c.to_rgba32()] = true
	return out


func _mask(img: Image) -> PackedByteArray:
	var m := PackedByteArray()
	for y in img.get_height():
		for x in img.get_width():
			m.append(1 if img.get_pixel(x, y).a > 0.5 else 0)
	return m


func _ready() -> void:
	Settings.persist = false
	_run()


func _run() -> void:
	# Built-in settings, not whatever the user saved.
	SpriteFx.load_file("user://no_sprite_fx.json")
	var art := CanopyArt.frame_art(0)
	var art_cols := _colors(art)

	# 1. Upscalers: 2x, existing colours only, and different from each other.
	var outs := {}
	for m in PixelArt.MAGNIFIERS:
		var big := PixelArt.magnify2x(art, m)
		outs[m] = big
		check(big.get_size() == art.get_size() * 2, "%s doubles the size" % m)
		var extra := _colors(big).keys().filter(func(c): return not art_cols.has(c))
		check(extra.is_empty(), "%s only uses the sprite's colours" % m)
	check(outs.scale2x.get_data() != outs.eagle.get_data() and outs.scale2x.get_data() != outs.epb.get_data(), "the upscalers differ")
	for u in SpriteFx.UPSCALES:
		var r := SpriteFx.process(art, SpriteFx.sanitized(SpriteFx.DEFAULTS.tree_trunk.merged({"upscale": u}, true)), 0)
		check(r.k == SpriteFx.UPSCALES[u] and r.image.get_width() == art.get_width() * r.k, "upscale %s is %dx" % [u, r.k])

	# 2. Noise keeps the silhouette; palette noise adds no colours.
	var big4 := SpriteFx.upscale(art, "scale2x_x2")
	for mode in PixelArt.NOISES:
		if mode == "none":
			continue
		var n := PixelArt.noise(big4, mode, 1.0, 1, 3)
		check(_mask(n) == _mask(big4), "%s noise keeps the outline" % mode)
		check(n.get_data() != big4.get_data(), "%s noise changes pixels" % mode)
	var pal := PixelArt.noise(big4, "palette", 1.0, 2, 3)
	check(_colors(pal).keys().all(func(c): return _colors(big4).has(c)), "palette noise only uses the sprite's colours")
	check(PixelArt.noise(big4, "speckle", 0.0, 1, 3).get_data() == big4.get_data(), "zero strength is no noise")

	# 3. Defaults reproduce the game's canopy; no warp and no noise = plain upscale.
	check(CanopyArt.cell(0).get_data() == SpriteFx.process(art, SpriteFx.options("tree_canopy"), 0).image.get_data(), "canopy is built by SpriteFx")
	var plain: Image = SpriteFx.process(art, SpriteFx.options("tree_trunk"), 0).image
	check(plain.get_data() == big4.get_data(), "trunk defaults: upscale only")

	# 4. Settings: only differences are kept; save and load round trip.
	SpriteFx.set_options("tree_trunk", SpriteFx.options("tree_trunk").merged({"noise": "palette"}, true))
	check(SpriteFx._settings.tree_trunk == {"noise": "palette"}, "only changed settings are stored (%s)" % SpriteFx._settings.tree_trunk)
	check(SpriteFx.save(SAVE), "settings saved")
	SpriteFx.load_file("user://no_sprite_fx.json")
	check(SpriteFx.options("tree_trunk").noise == "none", "defaults without a file")
	SpriteFx.load_file(SAVE)
	check(SpriteFx.options("tree_trunk").noise == "palette", "settings load back")
	SpriteFx.load_file("user://no_sprite_fx.json")

	# 5. The editor: builds a preview, follows setting changes, switches views and sprites, saves.
	var ed: Control = load("res://editor/sprite_editor.tscn").instantiate()
	ed.save_path = SAVE
	add_child(ed)
	await frames(20)
	check(not ed._canopy.is_empty() and ed._trunk.size() >= 9, "editor built canopies and trunk variants")
	var before: PackedByteArray = ed._canopy[0].image.get_data()
	ed._upscale.select(SpriteFx.UPSCALES.keys().find("epb_x2"))
	ed._upscale.item_selected.emit(SpriteFx.UPSCALES.keys().find("epb_x2"))
	ed._warp.value = 1.0
	await frames(20)
	check(ed._opts.tree_canopy.upscale == "epb_x2" and ed._opts.tree_canopy.warp == 1.0 and ed.dirty, "panel changes the canopy settings")
	check(ed._canopy[0].image.get_data() != before, "the preview was rebuilt")
	await key(KEY_PAGEDOWN)
	check(ed.target == "tree_trunk" and not ed._fade_row.visible, "PageDown switches to the trunk (no fade setting)")
	ed._noise.item_selected.emit(PixelArt.NOISES.find("speckle"))
	await frames(20)
	check(ed._opts.tree_trunk.noise == "speckle" and ed._opts.tree_canopy.noise == "none", "trunk settings are separate")
	for v in 3:
		await key(KEY_1 + v)
		await frames(2)
		check(ed.view == v, "key %d shows the %s view" % [v + 1, ed.VIEWS[v]])
	# Every tree top: a sheet's three frames, or all of them side by side.
	ed._select("tree_canopy")
	var n_sheets := CanopyArt.SHEETS.size()
	check(ed._sheet_row.visible and ed._sheet.item_count == n_sheets + 1, "the canopy lists all %d tree tops, and All" % n_sheets)
	ed.set_sheet(14)
	check(ed._canopy.has(140) and ed._canopy.has(142) and not ed._canopy.has(50) and ed.canopy_style() == 140,
			"picking the bushy jungle builds just its frames")
	ed.set_sheet(ed.ALL_SHEETS)
	check(CanopyArt.STYLE_IDS.all(func(st): return ed._canopy.has(st)) and ed._sheet.get_selected_id() == ed.ALL_ITEM, "All builds every tree top")
	for v in 3:
		ed.set_view(v)
		await frames(2)
	await key(KEY_RIGHT)
	check(ed.sheet == 0, "Right after All goes back to the first")
	await key(KEY_LEFT)
	await key(KEY_LEFT)
	check(ed.sheet == n_sheets - 1 and ed._canopy[ed.canopy_style()].image.get_data() == CanopyArt.build(ed.canopy_style(), ed._opts.tree_canopy).image.get_data(),
			"Left steps back; the preview is the canopy with the edited settings")
	ed.set_sheet(0)
	ed.set_view(2)
	ed._select("tree_trunk")
	await frames(2)
	check(not ed._sheet_row.visible, "the trunk has no tree tops menu")

	# The cactus: its sample shapes as styles, settings of its own.
	await key(KEY_PAGEDOWN)
	check(ed.target == "cactus" and ed._style_row.visible and ed._style.item_count == ed.CACTUS_SHAPES.size() and ed._cactus.size() == ed.CACTUS_SHAPES.size(),
			"PageDown again: the cactus, with its sample cacti as styles")
	var cactus_before: PackedByteArray = ed._cactus[0].image.get_data()
	ed._upscale.item_selected.emit(SpriteFx.UPSCALES.keys().find("none"))
	await frames(20)
	check(ed._opts.cactus.upscale == "none" and ed._cactus[0].image.get_data() != cactus_before and ed._opts.tree_canopy.upscale == "epb_x2",
			"cactus settings change its preview, not the trees'")
	check(ed._cactus[0].image.get_size() == CactusArt.compose(ed.CACTUS_SHAPES[0]).get_size(), "with no upscale the cactus is its art (3 tiles wide)")
	await key(KEY_3)
	await frames(2)
	check(ed.view == 2, "the scene view shows cacti on sand")
	await key(KEY_S, true)
	check(not ed.dirty and FileAccess.file_exists(SAVE), "Ctrl+S saves")
	SpriteFx.load_file(SAVE)
	check(SpriteFx.options("tree_canopy").upscale == "epb_x2" and SpriteFx.options("tree_trunk").noise == "speckle" and SpriteFx.options("cactus").upscale == "none",
			"saved settings are what was edited")
	ed.queue_free()

	SpriteFx.load_file()  # back to the real settings
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("RESULT: %d failures" % failures.size())
	for f in failures:
		print("  - " + f)
	get_tree().quit(1 if failures.size() > 0 else 0)
