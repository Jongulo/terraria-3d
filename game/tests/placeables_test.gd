extends Node
## Placeable methods: mesh building, the picker tool, and block models in game.

const SAVE := "user://placeables_test.json"
const WORLD := "user://worlds/placeables_test.twld"

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
		# Parsed events are delivered on the next idle frame (a slow frame can
		# run several physics frames before it), so wait for idle frames.
		await get_tree().process_frame
		await get_tree().process_frame


## Whether `mesh` has a face lying in the plane x = `x` (a platform's edge).
func _side_faces(mesh: ArrayMesh, x: float) -> bool:
	if mesh.get_surface_count() == 0:
		return false
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0, verts.size(), 3):
		if absf(verts[i].x - x) < 0.001 and absf(verts[i + 1].x - x) < 0.001 and absf(verts[i + 2].x - x) < 0.001:
			return true
	return false


func _ready() -> void:
	Settings.persist = false
	Settings.set_value("render_distance", 4)
	_run()


## Scale2x, the smooth warp and the tree canopy atlas built from them.
func _pixel_art_checks() -> void:
	# A diagonal staircase: Scale2x fills the inner corner from the equal neighbours.
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	img.set_pixel(0, 0, Color.BLACK)
	img.set_pixel(1, 1, Color.BLACK)
	var big := PixelArt.scale2x(img)
	check(big.get_size() == Vector2i(4, 4), "scale2x doubles the size")
	check(big.get_pixel(2, 1) == Color.BLACK and big.get_pixel(1, 2) == Color.BLACK and big.get_pixel(1, 1) == Color.WHITE,
			"scale2x rounds the diagonal from equal neighbours")
	var flat := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	flat.fill(Color.RED)
	check(PixelArt.scale2x(flat).get_pixel(5, 5) == Color.RED, "scale2x keeps flat areas")
	# Warp: padding, a moved interior, and an untouched bottom row (fade).
	var grad := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	for y in 40:
		for x in 40:
			grad.set_pixel(x, y, Color8(x * 6, y * 6, 0))
	var w := PixelArt.warp(grad, 3.0, 8.0, 5, 10, 4)
	check(w.get_size() == Vector2i(48, 44), "warp pads left, right and top")
	var bottom_ok := true
	var moved := 0
	for x in 40:
		bottom_ok = bottom_ok and w.get_pixel(x + 4, 43) == grad.get_pixel(x, 39)
	for y in 30:
		for x in 40:
			if w.get_pixel(x + 4, y + 4) != grad.get_pixel(x, y):
				moved += 1
	check(bottom_ok, "warp fades to nothing at the bottom row")
	check(moved > 300, "warp moves pixels above the fade (%d moved)" % moved)
	# Grass top: Terraria's leaf block in grass greens, 8 rotated variants.
	var grass := Data.block(Data.block_id("grass"))
	var top_cols := {}
	var grass_def: Dictionary = {}
	for b in Data._read_json("res://data/blocks.json").blocks:
		if b.name == "grass":
			grass_def = b.tex.top
	for v in 2:
		var layer: Image = Data._cube_layer(grass_def, v)
		for y in range(0, Data.LAYER_SIZE, 2):
			for x in range(0, Data.LAYER_SIZE, 2):
				top_cols[layer.get_pixel(x, y).to_html(false)] = true
	check(grass.variants >= 8, "grass has 8+ variants (%d)" % grass.variants)
	check(top_cols.has("137530") and not top_cols.has("0d6524") and top_cols.size() <= 5,
			"grass top uses the grass ramp with the lighter dark (%s)" % [top_cols.keys()])
	var canopy := CanopyArt.cell(0)
	var pad := 4  # SpriteFx warp margin: ceil(2.5 px default warp) + 1
	check(canopy.get_size() == Vector2i(160 + 2 * pad, 160 + pad),
			"canopy: padded 4x frame (%s)" % canopy.get_size())
	# The trunk stub is unwarped: the bottom row matches the plain 4x art.
	var frame := Assets.image("Images/Tree_Tops_0").get_region(Rect2i(0, 0, 80, 80))
	var plain := PixelArt.scale2x(PixelArt.scale2x(PixelArt.downsample(frame, PixelArt.detect_scale(frame))))
	var stub_ok := true
	for x in 160:
		stub_ok = stub_ok and canopy.get_pixel(x + pad, canopy.get_height() - 1) == plain.get_pixel(x, 159)
	check(stub_ok, "canopy trunk stub stays in place")


func _run() -> void:
	# Start from the built-in defaults, not whatever the user saved in the picker
	# or the sprite editor.
	Data.reset_placeables()
	SpriteFx.load_file("user://no_sprite_fx.json")
	Data.rebuild_sprite_fx()
	_pixel_art_checks()
	# 1. Every placeable builds in every method, inside its block.
	var names := Data.placeable_blocks()
	check(names.size() >= 6, "placeable blocks found: %s" % [names])
	var bad := []
	for n in names:
		var id := Data.block_id(n)
		for m in Data.PLACEABLE_METHODS:
			var built := BlockModelMesh.build(id, m)
			var mesh: ArrayMesh = built.mesh
			var aabb := mesh.get_aabb()
			# The sprite's in-game size (panels sit on the block's faces).
			var img: Image = Data.block(id).sprite
			var spx: float = Data.block(id).sprite_px
			var half := maxf(img.get_width() * spx * 0.5, 0.5) + 0.06
			# The top hull is as deep as the sprite is tall.
			var half_z := maxf(half, img.get_height() * spx * 0.5 + 0.06) if m == "hull_top" else half
			var inside := aabb.position.x >= -half and aabb.end.x <= half and aabb.position.z >= -half_z \
					and aabb.end.z <= half_z and aabb.position.y >= -0.01 and aabb.end.y <= img.get_height() * spx + 0.05
			if mesh.get_surface_count() == 0 or not inside:
				bad.append("%s/%s %s" % [n, m, aabb])
	check(bad.is_empty(), "every method builds at the sprite's real size %s" % [bad])
	var furnace := Data.block(Data.block_id("furnace"))
	# Extruded's front face spans the full sprite rectangle.
	var fm: ArrayMesh = BlockModelMesh.build(Data.block_id("furnace"), "extruded").mesh
	check(absf(fm.get_aabb().size.x - 1.5) < 0.01 and absf(fm.get_aabb().size.y - 1.0) < 0.01, "furnace is 3x2 tiles = 1.5 x 1 blocks (%s)" % fm.get_aabb().size)
	check(furnace.oversize and furnace.render_id == 5, "oversize furnace is drawn as a block model")
	var chest_m: ArrayMesh = BlockModelMesh.build(Data.block_id("chest"), "extruded").mesh
	check(absf(chest_m.get_aabb().size.y - 1.0) < 0.01, "chest is 2x2 tiles = 1 block")
	# Tree canopies: every style a picker entry of its own (not a world block),
	# with its own method and settings, named for its art.
	var canopy_names: Array = CanopyArt.STYLE_IDS.map(func(st): return CanopyArt.block_name(st))
	check(canopy_names.size() == 84 and canopy_names.all(func(n): return n in names), "all 84 canopies (the giant mushroom caps too) are listed in the picker")
	check(Data.placeable_label("tree_canopy@11") == "Canopy: Corruption (Tree_Tops_1) 2", "named for their art (%s)" % Data.placeable_label("tree_canopy@11"))
	check(Data.blocks.all(func(b): return not b.name.begins_with("tree_canopy")), "tree canopy is not a world block")
	var canopy_d := Data.block(Data.block_id("tree_canopy"))
	check(canopy_d.method == "cross", "tree canopy defaults to cross")
	var cm: ArrayMesh = BlockModelMesh.build(Data.block_id("tree_canopy"), "cross").mesh
	check(absf(cm.get_aabb().size.y - CanopyArt.SIZE * (160 + 4) / 160.0) < 0.01, "canopy is %s blocks tall (%s)" % [CanopyArt.SIZE, cm.get_aabb().size])
	var c2_method: String = Data.block(Data.block_id("tree_canopy@2")).method
	Data.set_block_method("tree_canopy", "lathe")
	check(Data.block(Data.block_id("tree_canopy@2")).method == c2_method and Data.placeable_methods.get("tree_canopy") == "lathe",
			"each canopy's method is its own")
	var l2_plain: ArrayMesh = BlockModelMesh.build(Data.block_id("tree_canopy@2"), "lathe").mesh
	Data.set_method_option("tree_canopy", "lathe", "noise", "speckle")
	var l2: ArrayMesh = BlockModelMesh.build(Data.block_id("tree_canopy@2"), "lathe").mesh
	Data.reset_method_options("tree_canopy", "lathe")
	check(l2 == l2_plain, "and so are its settings")
	Data.set_block_method("tree_canopy", "cross")
	check(not Data.placeable_methods.has("tree_canopy"), "default canopy method isn't saved")
	# An older file's one set of canopy choices is copied to every canopy, once.
	var old_file := "user://_old_canopies.json"
	var old_f := FileAccess.open(old_file, FileAccess.WRITE)
	old_f.store_string(JSON.stringify({"units": "art", "methods": {"tree_canopy": "hull"}, "hull": {"tree_canopy": {"noise": "grain"}},
			"transform": {"tree_canopy": {"scale": 1.5}}}))
	old_f.close()
	Data.load_placeables(old_file)
	check(Data.placeable_methods.get("tree_canopy@41") == "hull" and Data.method_options("tree_canopy@41", "hull").noise == "grain"
			and is_equal_approx(Data.transform_options("tree_canopy@41").scale, 1.5), "an older file's canopy choices go to every canopy")
	Data.save_placeables(old_file)
	Data.set_block_method("tree_canopy@41", "cross")
	Data.placeable_methods.erase("tree_canopy@41")
	Data.save_placeables(old_file)
	Data.load_placeables(old_file)
	check(not Data.placeable_methods.has("tree_canopy@41") and Data.placeable_methods.get("tree_canopy") == "hull",
			"once saved, a canopy set back to its default stays apart")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_file))
	Data.reset_placeables()  # back to the defaults the rest of the test starts from
	# Tree trunk: a sprite block, one Terraria tile (16 px) per block, solid.
	var trunk := Data.block(Data.block_id("tree_trunk"))
	check("tree_trunk" in names and trunk.method == "panels" and trunk.get("solid", true), "tree trunk is a solid sprite block (panels)")
	var tm: ArrayMesh = BlockModelMesh.build(Data.block_id("tree_trunk"), "panels").mesh
	# Upscaled 4x (no warp): exactly one block.
	check(absf(tm.get_aabb().size.y - 1.0) < 0.01 and absf(tm.get_aabb().size.x - 1.0) < 0.01 and not trunk.oversize,
			"upscaled trunk tile fills one block (%s)" % tm.get_aabb().size)
	check(trunk.sprite.get_height() == 32 and trunk.sprites.size() == trunk.variants, "trunk sprites are upscaled 4x, every variant")
	# The trunk warp repeats vertically, so stacked blocks line up.
	var vn = PixelArt._ValueNoise.new(3, 10.0, 3, 32.0 / 3.0)
	var periodic := true
	for x in 40:
		periodic = periodic and is_equal_approx(vn.at(x, 0.0), vn.at(x, 32.0))
	check(periodic, "tileable warp noise repeats every tile height")
	check(trunk.variants >= 9, "trunk has knot and grain variants (%d)" % trunk.variants)
	var hull_faces := (BlockModelMesh.build(Data.block_id("pot"), "lathe").mesh as ArrayMesh).surface_get_array_len(0)
	check(hull_faces > 300, "lathe pot is a real voxel solid (%d vertices)" % hull_faces)

	# 2. The picker: number keys, clicking, block switching, saving.
	var picker: Node = load("res://editor/placeable_picker.tscn").instantiate()
	picker.save_path = SAVE
	add_child(picker)
	await frames(3)
	var first: String = picker.current
	await key(KEY_6)
	check(Data.block(Data.block_id(first)).method == "hull" and picker.dirty, "6 picks hull for %s" % first)
	await key(KEY_PAGEDOWN)
	var second: String = picker.current
	check(second != first, "PageDown moves to the next placeable (%s)" % second)
	picker._pick_at(picker._cam.unproject_position(picker._models[Data.PLACEABLE_METHODS.find("lathe")].global_position + Vector3(0, 0.5, 0)))
	check(Data.block(Data.block_id(second)).method == "lathe", "clicking the lathe model picks lathe")
	# Extruded settings: depth and side noise. (The panel follows the chosen
	# method, which is lathe right now; point it at extruded.)
	picker._settings_method = "extruded"
	picker._sync_extrude_ui()
	var ex_name: String = picker.current
	var ex_id := Data.block_id(ex_name)
	var px: float = Data.block(ex_id).art_px  # voxels are art pixels
	var d0: int = Data.extrude_options(ex_name).depth
	await key(KEY_BRACKETLEFT)
	await key(KEY_BRACKETLEFT)
	check(Data.extrude_options(ex_name).depth == d0 - 2, "[ makes the extrusion thinner (%d -> %d)" % [d0, Data.extrude_options(ex_name).depth])
	var thin: ArrayMesh = BlockModelMesh.build(ex_id, "extruded").mesh
	check(absf(thin.get_aabb().size.z - (d0 - 2) * px) < 0.001, "mesh depth follows the setting (%.3f m)" % thin.get_aabb().size.z)
	picker._set_extrude("depth", Data.extrude_max_depth(ex_name))
	var thick: ArrayMesh = BlockModelMesh.build(ex_id, "extruded").mesh
	check(absf(thick.get_aabb().size.z - 1.0) < 0.05, "max depth fills the block (%.3f m)" % thick.get_aabb().size.z)
	var variety := func(m: ArrayMesh) -> int:
		var seen := {}
		for c in (m.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray):
			seen[snappedf(c.r, 0.01)] = true
		return seen.size()
	var plain: int = variety.call(thick)
	await key(KEY_N)
	check(Data.extrude_options(ex_name).noise == "speckle", "N switches the side noise to speckle")
	var speckled: int = variety.call(BlockModelMesh.build(ex_id, "extruded").mesh)
	check(speckled > plain * 3, "speckle varies the side cells (%d shades vs %d)" % [speckled, plain])
	var seed0: int = Data.extrude_options(ex_name).seed
	await key(KEY_N, false)
	await key(KEY_N, false)
	check(Data.extrude_options(ex_name).noise == "palette", "N cycles grain -> palette")
	var e := InputEventKey.new()
	e.keycode = KEY_N
	e.pressed = true
	e.shift_pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame
	check(Data.extrude_options(ex_name).seed == seed0 + 1, "Shift+N rolls a new seed")
	# An animated block's previews step through its frames, every method.
	picker._select_block("campfire")
	var pf_seen := {}
	var meshes_seen := {}
	var sprites_seen := {}
	var rendered_seen := {}
	var pt0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - pt0 < 500:
		await frames(1)
		pf_seen[picker.anim_frame()] = true
		for i in picker._models.size():
			var m: Node3D = picker._models[i]
			if m is EntitySprite:
				sprites_seen[m.material_override.get_shader_parameter("sprite")] = true
			elif m is RenderedPlaceable:
				# Headless: its stand-in billboard.
				rendered_seen[m.get_child(0).material_override.get_shader_parameter("sprite")] = true
			else:
				meshes_seen["%d:%d" % [i, m.mesh.get_instance_id()]] = true
	check(not pf_seen.has(-1) and pf_seen.size() >= 4, "the picker animates the campfire (%d frames seen)" % pf_seen.size())
	check(meshes_seen.size() >= (picker._models.size() - 2) * 3 and sprites_seen.size() >= 3 and rendered_seen.size() >= 3,
			"every method's preview changes with it (%d meshes, %d billboard frames, %d rendered)" % [meshes_seen.size(), sprites_seen.size(), rendered_seen.size()])
	picker._select_block("chest")
	check(picker.anim_frame() == -1, "a chest doesn't animate")

	# Bevel (on the chest: wide enough that its middle is clear of the bevel):
	# B cycles profiles; the front recedes near the outline only.
	var noise_block := ex_name
	picker._select_block("chest")
	ex_name = "chest"
	ex_id = Data.block_id(ex_name)
	picker._set_extrude("depth", Data.extrude_max_depth(ex_name))
	await key(KEY_B)
	check(Data.extrude_options(ex_name).bevel == "chamfer", "B picks the chamfer bevel")
	picker._set_extrude("bevel_size", 3)  # art voxels; not the default, so it is saved
	var fronts := {}
	var bev_mesh: ArrayMesh = BlockModelMesh.build(ex_id, "extruded").mesh
	var verts: PackedVector3Array = bev_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var normals_z := {}
	for v in verts:
		if v.z > 0.0:
			fronts[snappedf(v.z, 0.001)] = true
	check(fronts.size() >= 4, "chamfer steps the front through several depths (%d levels)" % fronts.size())
	check(absf(bev_mesh.get_aabb().size.z - 1.0) < 0.05, "the middle keeps the full depth")
	for p in ["round", "cove", "step"]:
		picker._set_extrude("bevel", p)
		var m: ArrayMesh = BlockModelMesh.build(ex_id, "extruded").mesh
		check(m.get_surface_count() > 0 and absf(m.get_aabb().size.z - 1.0) < 0.05, "%s bevel builds" % p)
	var e2 := InputEventKey.new()
	e2.keycode = KEY_B
	e2.pressed = true
	e2.shift_pressed = true
	Input.parse_input_event(e2)
	await get_tree().process_frame
	await get_tree().process_frame
	check(Data.extrude_options(ex_name).bevel == "cove", "Shift+B steps back (step -> cove)")
	# Bevel sides: only the chosen edges of the silhouette, and faces.
	picker._set_extrude("bevel", "chamfer")
	check(Data.extrude_options(ex_name).bevel_sides == BlockModelMesh.BEVEL_SIDES, "every side is bevelled by default")
	var art: Image = Data.block(ex_id).art
	var aw := art.get_width()
	var ah := art.get_height()
	var solid := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < aw and y < ah and art.get_pixel(x, y).a > 0.5
	var mid := aw / 2
	var bottom_row := ah - 1
	while not solid.call(mid, bottom_row):
		bottom_row -= 1
	var top_row := 0
	while not solid.call(mid, top_row):
		top_row += 1
	var all_in := BlockModelMesh._bevel_insets(art, solid, "chamfer", 3, 6)
	var top_in := BlockModelMesh._bevel_insets(art, solid, "chamfer", 3, 6, ["top", "front", "back"])
	check(all_in[bottom_row * aw + mid] > 0 and top_in[bottom_row * aw + mid] == 0 and top_in[top_row * aw + mid] > 0,
			"with only the top edge on, the bottom edge stays square (bottom %d -> %d, top %d)" % [all_in[bottom_row * aw + mid], top_in[bottom_row * aw + mid], top_in[top_row * aw + mid]])
	# Faces: flat front/back quads (all three corners at one depth), by depth.
	var face_depths := func(m: ArrayMesh) -> Array:
		var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var front := {}
		var back := {}
		for t in range(0, vs.size(), 3):
			if absf(vs[t].z - vs[t + 1].z) < 1e-4 and absf(vs[t].z - vs[t + 2].z) < 1e-4:
				(front if vs[t].z > 0.0 else back)[snappedf(vs[t].z, 0.001)] = true
		return [front.size(), back.size()]
	var both: Array = face_depths.call(BlockModelMesh.build(ex_id, "extruded").mesh)
	picker._ex_sides["back"].button_pressed = false
	check(not "back" in Data.extrude_options(ex_name).bevel_sides and picker.dirty, "unticking Back takes the back face out of the bevel")
	var front_only: Array = face_depths.call(BlockModelMesh.build(ex_id, "extruded").mesh)
	check(both[0] >= 3 and both[1] >= 3 and front_only[0] >= 3 and front_only[1] == 1,
			"the back stays flat, the front is still bevelled (front/back depths %s -> %s)" % [both, front_only])
	picker._ex_sides["bottom"].button_pressed = false
	check(Data.extrude_options(ex_name).bevel_sides == ["top", "left", "right", "front"], "unticking Bottom too (%s)" % [Data.extrude_options(ex_name).bevel_sides])
	picker._set_extrude("bevel", "none")
	check(picker._ex_sides["top"].disabled, "side boxes are greyed out with no bevel")
	picker._set_extrude("bevel", "cove")
	check(not picker._ex_sides["top"].disabled and not picker._ex_sides["bottom"].button_pressed, "and come back with one")
	# Hull and lathe have their own noise settings; the panel follows the method.
	var vb := "pot"
	picker._select_block(vb)
	var vb_id := Data.block_id(vb)
	var shades := func(m: ArrayMesh) -> int:
		var seen := {}
		for c in (m.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray):
			seen[snappedf(c.r, 0.005)] = true
		return seen.size()
	var hull_plain: int = shades.call(BlockModelMesh.build(vb_id, "hull").mesh)
	await key(KEY_6)
	check(picker._settings_method == "hull", "choosing hull switches the settings panel to hull")
	await key(KEY_N)
	check(Data.method_options(vb, "hull").noise == "speckle" and Data.extrude_options(vb).noise == "none", "N sets hull noise without touching extruded")
	var hull_noisy: int = shades.call(BlockModelMesh.build(vb_id, "hull").mesh)
	check(hull_noisy > hull_plain * 2, "speckle varies the hull's surface (%d shades vs %d)" % [hull_noisy, hull_plain])
	await key(KEY_7)
	check(picker._settings_method == "hull_top", "7 picks the top hull, its own settings")
	var top_box: AABB = BlockModelMesh.build(vb_id, "hull_top").mesh.get_aabb()
	var side_box: AABB = BlockModelMesh.build(vb_id, "hull").mesh.get_aabb()
	check(is_equal_approx(top_box.size.z, top_box.size.y) and is_equal_approx(top_box.size.x, side_box.size.x),
			"the top hull is as deep as the sprite is tall (%s), as wide as the hull" % top_box.size)
	await key(KEY_8)
	check(picker._settings_method == "lathe", "choosing lathe switches the panel to lathe")
	var lathe_plain: int = shades.call(BlockModelMesh.build(vb_id, "lathe").mesh)
	picker._set_option("noise", "grain")
	picker._set_option("strength", 1.0)
	var lathe_grain: int = shades.call(BlockModelMesh.build(vb_id, "lathe").mesh)
	check(lathe_grain > lathe_plain, "grain rings vary the lathe (%d shades vs %d)" % [lathe_grain, lathe_plain])
	picker._set_option("noise", "palette")
	check(BlockModelMesh.build(vb_id, "lathe").mesh.get_surface_count() == 1, "palette lathe builds")
	# Claude's hand-made voxel models (method 8: sawmill, bench, bookcase,
	# piano...), whose front view is the sprite - every opaque art pixel's front-most voxel
	# has its colour, and transparent pixels have no voxels.
	for name in Data.handmade_models:
		var d: Dictionary = Data.block(Data.block_id(name))
		var hm_art: Image = d.art
		var vox := BlockModelMesh.handmade_voxels(hm_art, Data.handmade_models[name])
		var hm_front := {}  # Vector2i -> front-most z
		var hm_depth := {}
		for v: Vector3i in vox:
			var k := Vector2i(v.x, v.y)
			hm_front[k] = maxi(hm_front.get(k, -1), v.z)
			hm_depth[k] = hm_depth.get(k, 0) + 1
		var hm_bad := []
		for y in hm_art.get_height():
			for x in hm_art.get_width():
				var k := Vector2i(x, y)
				var hm_opaque := hm_art.get_pixel(x, y).a > 0.5
				if hm_opaque != hm_front.has(k) or (hm_opaque and vox[Vector3i(x, y, hm_front[k])] != hm_art.get_pixel(x, y)):
					hm_bad.append(k)
		check(hm_bad.is_empty() and vox.size() > 0, "%s's hand-made model looks like its sprite from the front (%d voxels, wrong pixels %s)" % [name, vox.size(), hm_bad.slice(0, 5)])
		var hm_deep := hm_depth.values().filter(func(n): return n >= 8).size()
		var hm_levels := {}
		for z in hm_front.values():
			hm_levels[z] = true
		check(hm_deep > 20 and hm_levels.size() >= 2, "%s's model has real depth: deep parts, and its front steps in and out (%d deep columns, front at %d depths)" % [name, hm_deep, hm_levels.size()])
		var hm_built: Dictionary = BlockModelMesh.build(Data.block_id(name), "claude")
		check(not hm_built.textured and hm_built.mesh.get_surface_count() == 1 and hm_built.mesh.get_aabb().size.z > 0.4, "%s's model builds (%s)" % [name, hm_built.mesh.get_aabb()])
	picker._select_block("sawmill")
	await key(KEY_9)
	check(Data.block(Data.block_id("sawmill")).method == "claude", "9 picks Claude's model for the sawmill")
	# Side noise on hand-made models: every face varies but the front ones,
	# so the front view is still the sprite.
	check(picker._settings_method == "claude", "choosing Claude's model switches the settings panel to it")
	var faces_of := func(m: ArrayMesh) -> Array:  # [front face colours, other face colours]
		var arr := m.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var fr := {}
		var other := {}
		for t in range(0, vs.size(), 6):
			var n := (vs[t + 1] - vs[t]).cross(vs[t + 2] - vs[t]).normalized()
			(fr if n.z > 0.9 else other)[str(vs[t]) + str(cs[t])] = cs[t]
		return [fr, other]
	var plain_saw: Array = faces_of.call(BlockModelMesh.build(Data.block_id("sawmill"), "claude").mesh)
	await key(KEY_N)
	picker._set_option("strength", 1.0)
	check(Data.method_options("sawmill", "claude").noise == "speckle" and Data.method_options("sawmill", "hull").noise == "none",
			"N sets the hand-made model's noise without touching hull")
	var noisy_saw: Array = faces_of.call(BlockModelMesh.build(Data.block_id("sawmill"), "claude").mesh)
	var shades_of := func(d: Dictionary) -> int:
		var seen := {}
		for c in d.values():
			seen[snappedf(c.r, 0.005)] = true
		return seen.size()
	check(shades_of.call(noisy_saw[1]) > shades_of.call(plain_saw[1]) * 2,
			"speckle varies its sides (%d shades vs %d)" % [shades_of.call(noisy_saw[1]), shades_of.call(plain_saw[1])])
	check(noisy_saw[0] == plain_saw[0], "and leaves its front faces as they were, so the front view is still the sprite")
	for mode in ["grain", "palette"]:
		picker._set_option("noise", mode)
		var m: Array = faces_of.call(BlockModelMesh.build(Data.block_id("sawmill"), "claude").mesh)
		check(m[0] == plain_saw[0] and shades_of.call(m[1]) > shades_of.call(plain_saw[1]), "%s noise on the hand-made model (%d shades)" % [mode, shades_of.call(m[1])])
	check("Hand-made" in picker._labels[Data.PLACEABLE_METHODS.find("claude")].text, "the picker labels it")
	picker._select_block("pot")
	var pot_method: String = Data.block(Data.block_id("pot")).method
	await key(KEY_9)
	check(Data.block(Data.block_id("pot")).method == pot_method and "Not made yet" in picker._labels[Data.PLACEABLE_METHODS.find("claude")].text,
			"blocks without a hand-made model can't pick it")
	# Rendered: shots of its model from every angle ("-" picks it). Headless
	# nothing renders, so it stands in as its billboard.
	picker._select_block("chest")
	var chest_id := Data.block_id("chest")
	await key(KEY_MINUS)
	var ren_i := Data.PLACEABLE_METHODS.find("rendered")
	var ren_model: Node3D = picker._models[ren_i]
	check(Data.block(chest_id).method == "rendered" and picker._labels[ren_i].text.begins_with("-  Rendered"),
			"- picks Rendered, the 11th method")
	check(ren_model is RenderedPlaceable and not ren_model.showing_shots() and ren_model.get_child_count() == 1,
			"headless (no shots can be made) it's the billboard")
	check(PlaceableRenders.YAWS == 16 and PlaceableRenders.PITCHES == [0.0] and NPCRenders.YAWS == 32,
			"placeables are shot from 16 directions straight on (NPCs keep every height)")
	var chest_src := PlaceableRenders.source(chest_id)
	check(chest_src in ["hull", "claude", "tuned"] and BlockModels.model_mesh(chest_id, "rendered").mesh == BlockModels.model_mesh(chest_id, chest_src).mesh,
			"its shots are of its tuned, Claude's or hull model (%s)" % chest_src)
	picker._render_model.select(1)
	picker._render_model.item_selected.emit(1)
	await frames(2)
	check(Data.method_options("chest", "rendered").model == "extruded" and PlaceableRenders.source(chest_id) == "extruded"
			and picker._models[ren_i] != ren_model, "\"Shots taken of: Extruded model\" shoots the Extruded model, and the slot is made again")
	check(NPCRenders._version_of("block-wooden_door_%x_0.png" % -77, "block-wooden_door") and not NPCRenders._version_of("block-wooden_door_open_ab_0.png", "block-wooden_door"),
			"a block's cached shots aren't mistaken for another block's whose name starts the same")
	await key(KEY_S, true)
	check(not picker.dirty and FileAccess.file_exists(SAVE), "Ctrl+S saves")
	var all_saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	check(all_saved.methods.get("chest") == "rendered" and all_saved.get("rendered", {}).get("chest", {}).get("model") == "extruded",
			"the rendered choice and its setting are saved")
	check(all_saved.get("hull", {}).get(vb, {}).get("noise") == "speckle" and all_saved.get("lathe", {}).get(vb, {}).get("noise") == "palette", "hull and lathe noise saved")
	check(all_saved.get("claude", {}).get("sawmill", {}).get("noise") == "palette", "the hand-made model's noise is saved")
	var saved_bevel: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE)).get("extruded", {}).get(ex_name, {})
	check(saved_bevel.get("bevel") == "cove" and int(saved_bevel.get("bevel_size", 0)) == 3
			and saved_bevel.get("bevel_sides") == ["top", "left", "right", "front"], "bevel settings saved (sides %s)" % [saved_bevel.get("bevel_sides")])
	var saved_ex: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE)).get("extruded", {})
	check(saved_ex.get(noise_block, {}).get("noise") == "palette", "extruded settings are saved")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	check(saved.methods.get(first) == "hull" and saved.methods.get(second) == "lathe", "saved file has both choices")
	# The wall torch is listed on its own, shown hanging on a stone block, with
	# a method of its own (the standing torch keeps its).
	check("wall_torch" in picker._names, "the wall torch is in the picker")
	picker._select_block("wall_torch")
	var backs_ok: bool = picker._backings.size() == picker._models.size()
	for i in picker._backings.size():
		backs_ok = backs_ok and absf(picker._backings[i].position.x - picker._models[i].position.x) < 0.01 \
				and picker._backings[i].position.z < picker._models[i].position.z - 0.4
	check(backs_ok and picker._models.size() == Data.PLACEABLE_METHODS.size(),
			"each wall torch model hangs on a stone block behind it (%d blocks)" % picker._backings.size())
	var torch_method: String = Data.block(Data.block_id("torch")).method
	picker.choose("extruded")
	check(Data.block(Data.block_id("wall_torch")).method == "extruded" and Data.block(Data.block_id("torch")).method == torch_method,
			"its method is its own (torch stays %s)" % torch_method)
	picker._select_block("chest")
	check(picker._backings.is_empty(), "other blocks stand on their own")

	# Transform panel: offset (art pixels), rotation and scale of every method's model.
	picker._select_block("pot")
	await frames(2)
	var pot := Data.block(Data.block_id("pot"))
	var hull_i := Data.PLACEABLE_METHODS.find("hull")
	var bb_i := Data.PLACEABLE_METHODS.find("billboard")
	var aabb0: AABB = picker._models[hull_i].mesh.get_aabb()
	var bb_y0: float = picker._models[bb_i].position.y
	picker._tr_spins.offset[1].value = 4
	await frames(2)
	var aabb1: AABB = picker._models[hull_i].mesh.get_aabb()
	check(Data.transform_options("pot").offset == [0.0, 4.0, 0.0] and picker.dirty, "offset Y set from the panel (%s)" % [Data.transform_options("pot").offset])
	check(absf(aabb1.position.y - aabb0.position.y - 4 * pot.art_px) < 0.001, "the hull model moved up 4 art pixels (%.3f -> %.3f)" % [aabb0.position.y, aabb1.position.y])
	check(absf(picker._models[bb_i].position.y - bb_y0 - 4 * pot.art_px * picker._fit_scale(Data.block_id("pot"))) < 0.001, "so did the billboard sprite")
	picker._tr_scale.value = 200
	await frames(2)
	var aabb2: AABB = picker._models[hull_i].mesh.get_aabb()
	check(absf(aabb2.size.y - aabb0.size.y * 2.0) < 0.001, "scale 200%% doubles the model (%.3f -> %.3f)" % [aabb0.size.y, aabb2.size.y])
	picker._tr_spins.rotation[2].value = 90
	await frames(2)
	var aabb3: AABB = picker._models[hull_i].mesh.get_aabb()
	check(absf(aabb3.size.x - aabb2.size.y) < 0.01, "rotation Z 90 lays it on its side (width %.3f, was height %.3f)" % [aabb3.size.x, aabb2.size.y])
	check(Data.render_for(pot) == 5, "a transformed placeable is always a block model")
	await key(KEY_S, true)
	var saved_tr: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE)).get("transform", {}).get("pot", {})
	check(saved_tr.get("offset") == [0.0, 4.0, 0.0] and is_equal_approx(float(saved_tr.get("scale", 0)), 2.0) and saved_tr.get("rotation") == [0.0, 0.0, 90.0],
			"the transform is saved (%s)" % saved_tr)
	for b in picker.find_children("*", "Button", true, false):
		if b.text == "Reset transform":
			b.pressed.emit()
	await frames(2)
	check(not Data.transform_settings.has("pot") and picker._models[hull_i].mesh.get_aabb().is_equal_approx(aabb0) and picker._tr_scale.value == 100,
			"Reset transform puts it back")
	Data.set_block_method("pot", "cross")
	Data.set_transform_option("pot", "scale", 1.5)
	var cross_model := Data.render_for(pot) == 5
	Data.reset_transform("pot")
	check(cross_model and Data.render_for(pot) == 3, "a cross placeable is drawn as a model only while transformed")
	Data.set_block_method("pot", "hull")
	# Copy one placeable's choices and paste them onto another (Ctrl+C,
	# Ctrl+V; Ctrl+Shift+V onto all its styles).
	Data.set_block_method("pot", "extruded")
	Data.set_method_option("pot", "extruded", "depth", 5)
	Data.set_method_option("pot", "extruded", "bevel", "round")
	Data.set_method_option("pot", "hull", "noise", "grain")
	Data.set_transform_option("pot", "scale", 1.5)
	picker._select_block("pot")
	await key(KEY_C, true)
	picker._select_block("small_rocks")
	Data.set_transform_option("small_rocks", "offset", [0.0, 2.0, 0.0])
	await key(KEY_V, true)
	await frames(2)
	var rocks := Data.block(Data.block_id("small_rocks"))
	check(rocks.method == "extruded" and Data.extrude_options("small_rocks").depth == mini(5, Data.extrude_max_depth("small_rocks")) and Data.extrude_options("small_rocks").bevel == "round"
			and Data.method_options("small_rocks", "hull").noise == "grain" and is_equal_approx(Data.transform_options("small_rocks").scale, 1.5)
			and Data.transform_options("small_rocks").offset == [0.0, 0.0, 0.0] and picker.dirty,
			"Ctrl+C on the pot, Ctrl+V on the rocks: its method, every method's settings and its transform, the rest back to defaults")
	check(picker._models[Data.PLACEABLE_METHODS.find("extruded")] != null and picker._status.text.begins_with("Pasted"), "the models are made again and it says so")
	picker._select_block("flowers_7")
	picker.paste_settings(true)
	await frames(2)
	var flower_styles := Data.placeable_blocks().filter(func(n): return Data.kind_of(Data.block_id(n)) == "flowers")
	check(flower_styles.size() == 38 and flower_styles.all(func(n): return Data.block(Data.block_id(n)).method == "extruded" and Data.extrude_options(n).bevel == "round"),
			"Paste to styles gives all 38 flower styles the copied settings")
	# Search: Ctrl+F types into the box, the list keeps only the matches
	# (label or block name) and PageDown/clicks go through them.
	await key(KEY_F, true)
	check(picker._search.has_focus(), "Ctrl+F puts the cursor in the search box")
	picker.get_viewport().gui_release_focus()
	picker.search("Cattail")
	check(not picker._shown.is_empty() and picker._shown.all(func(n): return "cattail" in Data.placeable_label(n).to_lower() or "cattail" in n)
			and picker._list.item_count == picker._shown.size() and picker._shown.size() < picker._names.size(),
			"searching \"Cattail\" lists only the cattails (%d)" % picker._shown.size())
	picker._list.item_selected.emit(1)
	await key(KEY_PAGEDOWN)
	check(picker.current == picker._shown[2 % picker._shown.size()], "clicks and PageDown go through the matches (%s)" % picker.current)
	picker.search("small_rocks_3")
	check(picker._shown == ["small_rocks_3"], "a block name finds its placeable")
	picker.search("")
	check(picker._list.item_count == picker._names.size(), "clearing the search lists every placeable again")
	Data.reset_placeables()
	picker.queue_free()
	await frames(2)

	# Voxel size comes from the sprite: Terraria sprites are drawn at 2x.
	var chest := Data.block(Data.block_id("chest"))
	check(chest.art_scale == 2 and chest.art.get_width() == chest.sprite.get_width() / 2, "chest art detected at 2x (%dx%d art pixels)" % [chest.art.get_width(), chest.art.get_height()])
	var plain_img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	for y in 6:
		for x in 6:
			plain_img.set_pixel(x, y, Color(randf(), randf(), randf()))
	check(PixelArt.detect_scale(plain_img).x == 1, "a 1x sprite is detected as 1x")
	var big := plain_img.duplicate()
	big.resize(18, 18, Image.INTERPOLATE_NEAREST)
	check(PixelArt.detect_scale(big).x == 3, "a 3x sprite is detected as 3x")

	# 3. In game: a chest drawn as a hull model, placed facing the player; tree
	# trunks as batched billboards.
	Data.set_block_method("chest", "hull")
	Data.set_block_method("tree_trunk", "billboard")
	Data.set_block_method("torch", "hull")
	Data.set_block_method("wall_torch", "hull")
	Data.set_transform_option("tree_trunk", "offset", [0, 2, 0])  # checked on the billboard batches
	var game := Game.new()
	add_child(game)
	game.start({"mode": "test", "name": "PlaceablesTest", "seed": 1, "path": WORLD})
	while game.state != Game.State.PLAYING:
		await frames(1)
	await frames(30)
	var batches := 0
	var trunk_instances := 0
	var variants_seen := {}
	for nodes in game.block_models._by_chunk.values():
		for n in nodes:
			if n is MultiMeshInstance3D and n.material_override.get_shader_parameter("billboard"):
				batches += 1
				trunk_instances += n.multimesh.instance_count
				variants_seen[n.material_override] = true
	check(batches > 0 and trunk_instances >= 10, "trunks are batched billboards (%d batches, %d blocks)" % [batches, trunk_instances])
	check(variants_seen.size() >= 3, "billboard trunks use several sprite variants (%d)" % variants_seen.size())
	# (MultiMesh data stays on the renderer, so check the instance transform it is given.)
	var trunk_lift: float = Data.block_transform(Data.block(Data.block_id("tree_trunk"))).origin.y
	var inst := BlockModels.billboard_instance(Data.block_id("tree_trunk"), Vector3i(10, 20, 30))
	check(trunk_lift > 0.1 and inst.origin.is_equal_approx(Vector3(10.5, 20.0 + trunk_lift, 30.5)),
			"batched billboards take the block's offset (%s)" % inst.origin)
	Data.reset_transform("tree_trunk")
	var p := game.player
	var before := game.block_models.count()
	p.look_at_yaw_pitch(PI * 0.5, -0.9)  # facing -x, looking at the ground
	await frames(3)
	p.inventory.slots[9] = Inventory.stack("Chest", 5)
	p.select(9)
	var placed: Vector3i = p.target.block + p.target.normal
	p._use_timer = 0.0
	p.use_item()
	await frames(20)
	check(Data.block(game.world.get_block(placed)).name == "chest", "chest placed")
	check(game.block_models.count() == before + 1, "a hull model appeared for it (%d -> %d)" % [before, game.block_models.count()])
	check(game.block_rotation(placed) == 1, "it faces the player (rotation %d)" % game.block_rotation(placed))
	var model: Dictionary = game.block_models.model_at(placed)
	check(not model.is_empty() and absf(model.transform.basis.get_euler().y - PI * 0.5) < 0.01, "model turned a quarter turn toward the player")
	check(not model.is_empty() and model.light == game.world.get_light(Vector3(placed) + Vector3(0.5, 0.5, 0.5)),
			"it is lit by its block's light")

	# Wall torches: a torch put on the side of a block hangs on it, leaning out.
	var stone := Data.block_id("stone")
	var wall := placed + Vector3i(0, 1, 3)
	game.world.set_block(wall, stone)
	var below := wall + Vector3i(1, -1, 0)
	game.world.set_block(below, stone)
	p.inventory.slots[9] = Inventory.stack("Torch", 5)
	p.select(9)
	p.target = {"block": wall, "normal": Vector3i(1, 0, 0), "id": stone, "distance": 2.0}
	check(p._place(Data.item("Torch")), "torch placed on a wall")
	var wt := wall + Vector3i(1, 0, 0)
	check(game.world.get_block(wt) == Data.block_id("wall_torch") and game.block_rotation(wt) == 1,
			"it is a wall torch facing out of the wall (rotation %d)" % game.block_rotation(wt))
	await frames(20)
	var wmodel: Dictionary = game.block_models.model_at(wt)
	var wnode: ArrayMesh = wmodel.get("mesh")
	var waabb: AABB = wnode.get_aabb() if wnode else AABB()
	check(wnode != null and waabb.position.x < -0.45 and waabb.end.x > waabb.position.x + 0.2 and waabb.position.y > 0.1,
			"its model sticks out from the wall, base against it and raised (%s)" % waabb)
	check(Data.block(Data.block_id("wall_torch")).sprite.get_data() != Data.block(Data.block_id("torch")).sprite.get_data(),
			"it uses Terraria's wall torch art, not the standing torch's")
	# The flame end (top) is further from the wall (x = -0.5) than the base.
	var ends := [0.0, 0.0, 0, 0]  # x sums and counts of the bottom / top fifths
	if wnode:
		for v in wnode.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var f: float = (v.y - waabb.position.y) / waabb.size.y
			if f < 0.2:
				ends[0] += v.x
				ends[2] += 1
			elif f > 0.8:
				ends[1] += v.x
				ends[3] += 1
	var base_x: float = ends[0] / maxi(ends[2], 1)
	var top_x: float = ends[1] / maxi(ends[3], 1)
	check(top_x > base_x + 0.1, "it leans out of the wall like Terraria's (base x %.2f, flame x %.2f)" % [base_x, top_x])
	game.break_block(below)
	await frames(2)
	check(game.world.get_block(wt) == Data.block_id("wall_torch"), "breaking the block under it doesn't knock it off")
	p.target = {"block": wall + Vector3i(0, -1, 0), "normal": Vector3i(0, 1, 0), "id": stone, "distance": 2.0}
	game.world.set_block(wall + Vector3i(0, -1, 0), stone)
	game.world.set_block(wall, 0)
	check(p._place(Data.item("Torch")) and game.world.get_block(wall) == Data.block_id("torch"), "a torch on top of a block stands upright")
	game.world.set_block(wall, stone)
	game.break_block(wall)
	await frames(2)
	check(game.world.get_block(wt) == 0, "breaking its wall makes the wall torch fall off")
	# Animated placeables (Terraria's animated tiles): a campfire and a
	# furnace go through their frames, all of a kind together.
	var fire := wall + Vector3i(-2, 0, 2)
	var furnace_at := fire + Vector3i(0, 0, 3)
	for at in [fire, furnace_at]:
		game.world.set_block(at + Vector3i.DOWN, stone)
		game.world.set_block(at, 0)
	game.world.set_block(fire, Data.block_id("campfire"))
	game.world.set_block(furnace_at, Data.block_id("furnace"))
	await frames(5)
	var camp_d := Data.block(Data.block_id("campfire"))
	check(Data.anim_frames(camp_d) == 8 and Data.anim_frames(Data.block(Data.block_id("furnace"))) == 12,
			"a campfire has Terraria's 8 frames and a furnace 12")
	check(camp_d.anim_sprites[1].get_data() != camp_d.anim_sprites[0].get_data(), "its frames are different art")
	var frames_seen := {}
	var furnace_seen := {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 700:
		await frames(1)
		frames_seen[game.block_models.anim_frame_at(fire)] = true
		furnace_seen[game.block_models.anim_frame_at(furnace_at)] = true
	check(not frames_seen.has(-1) and frames_seen.size() >= 5, "the campfire animates (%d frames seen)" % frames_seen.size())
	check(not furnace_seen.has(-1) and furnace_seen.size() >= 3, "so does the furnace (%d frames seen)" % furnace_seen.size())
	check(BlockModelMesh.build(Data.block_id("campfire"), "extruded", 1).mesh != BlockModelMesh.build(Data.block_id("campfire"), "extruded", 0).mesh,
			"each frame has its own model")

	# Cacti and tree branches darken at night with the rest of the tree.
	var cactus_art := CactusArt.get_art(CactusArt.shape(Vector3i(3, 0, 7), 4, CactusArt.color_for(Data.block(Data.block_id("sand")))))
	var branch_art := TreeBranches.get_art("Tree_Branches_0", "Tiles_5", {"variant": 0, "leafy": true, "left": true})
	game.block_models.set_sky(0.07, Color(0.5, 0.6, 1.0))
	check(is_equal_approx(cactus_art.material.get_shader_parameter("sky_light"), 0.07)
			and is_equal_approx(branch_art.material.get_shader_parameter("sky_light"), 0.07),
			"night reaches the cacti and branches (%s, %s)" % [cactus_art.material.get_shader_parameter("sky_light"),
			branch_art.material.get_shader_parameter("sky_light")])
	game.block_models.set_sky(game.sky.sky_light, game.sky.sky_tint)

	# Torch effects: flickering flames over torches, candles, lamps... (not
	# the lanterns Terraria draws none for), embers from torches, and a held
	# torch's flame.
	var torch_info := TorchFlames.info(Data.block_id("torch"))
	check(not torch_info.is_empty() and int(torch_info.params["count"]) == 7 and torch_info.params.x == [-10, 11, 0.15],
			"a torch has Terraria's flame: 7 copies, -10..10 x 0.15 px sideways")
	check(TorchFlames.info(Data.block_id("heart_lantern")).is_empty() and not TorchFlames.info(Data.block_id("candle")).is_empty(),
			"a Heart Lantern has no flame, a candle has")
	var flames_before: int = game.torch_flames.count()
	var torch_at := furnace_at + Vector3i(0, 0, 3)
	game.world.set_block(torch_at + Vector3i.DOWN, stone)
	game.world.set_block(torch_at, Data.block_id("torch"))
	await frames(5)
	check(game.torch_flames.count() == flames_before + 1, "a placed torch gets a flame (%d -> %d)" % [flames_before, game.torch_flames.count()])
	var embers := 0
	for i in 240:
		await get_tree().physics_frame
		embers = maxi(embers, game.torch_flames.ember_count())
	check(embers > 0, "torches puff embers (%d at once)" % embers)
	p.inventory.slots[9] = Inventory.stack("Torch", 5)
	p.select(9)
	await frames(3)
	check(p.viewmodel._flame.visible, "a held torch has its flame")
	p.inventory.slots[9] = Inventory.stack("Chest", 5)
	await frames(3)
	check(not p.viewmodel._flame.visible, "a held chest doesn't")

	# The Demon Torch's light pulses red <-> blue (Terraria's DemonTorchLight,
	# 200 ticks a cycle), relighting the world as it goes.
	var demon_at := torch_at + Vector3i(0, 0, 3)
	game.world.set_block(demon_at + Vector3i.DOWN, stone)
	game.world.set_block(demon_at, Data.block_id("demon_torch"))
	await frames(5)
	var lows := Vector2(9, 9)
	var highs := Vector2(-1, -1)
	var dt0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - dt0 < 3600:
		await frames(1)
		var dl := game.world.get_light(Vector3(demon_at) + Vector3(0.5, 0.5, 0.5))
		lows = Vector2(minf(lows.x, dl.r), minf(lows.y, dl.b))
		highs = Vector2(maxf(highs.x, dl.r), maxf(highs.y, dl.b))
	# (Another torch nearby keeps some red: the blue swings its whole way.)
	check(highs.y - lows.y > 0.4 and highs.x - lows.x > 0.1, "the Demon Torch's light pulses red <-> blue (red %.2f..%.2f, blue %.2f..%.2f)" % [lows.x, highs.x, lows.y, highs.y])
	var c0 := Data.pulse_color(Data.block(Data.block_id("demon_torch")).pulse)
	check(is_equal_approx(c0.r + c0.b, 1.5) and is_equal_approx(c0.g, 0.3), "with Terraria's colours (%s)" % c0)
	check(game.save_world(), "saved")

	# Falling leaves: Terraria's leaf frequency (from the wind) and leaf per
	# tree; a leaf drifts through tree trunks and slides down walls.
	check(FallingLeaves.frequency(0.0) == 14000 and FallingLeaves.frequency(0.45) == 1400 and FallingLeaves.frequency(1.5) == 70,
			"leaves fall at Terraria's rates for the wind")
	check(FallingLeaves.canopy_leaf(0) == 910 and FallingLeaves.canopy_leaf(40) == 914 and FallingLeaves.canopy_leaf(30) == -1,
			"forest trees drop forest leaves, jungle trees jungle leaves, snowy pines none")
	var fl := game.falling_leaves
	fl.process_mode = Node.PROCESS_MODE_DISABLED
	var leaf_at := demon_at + Vector3i(0, 0, 4)
	for y in range(0, 7):
		game.world.set_block(leaf_at + Vector3i(1, y, 0), Data.block_id("tree_trunk"))
		game.world.set_block(leaf_at + Vector3i(3, y, 3), stone)
	for y in range(0, 7):
		for x in range(-1, 3):
			game.world.set_block(leaf_at + Vector3i(x, y, 3), 0) if x != 3 else null
	var wind_was: float = game.sky.wind
	game.sky.wind = 0.6
	fl._leaves.clear()
	fl.spawn(Vector3(leaf_at) + Vector3(0.3, 6.0, 0.5), 910)
	fl.spawn(Vector3(leaf_at) + Vector3(2.5, 6.0, 3.5), 910)
	for l in fl._leaves:
		l.axis = Vector3.RIGHT
	var past_trunk := false
	for i in 400:
		fl._step_leaves()
		if fl._leaves.size() > 0 and fl._leaves[0].pos.x > leaf_at.x + 2.2:
			past_trunk = true
	check(past_trunk, "a leaf blows through a tree trunk")
	var wall_leaf: Dictionary = fl._leaves.back() if fl._leaves.size() > 0 else {}
	check(not wall_leaf.is_empty() and wall_leaf.pos.y < leaf_at.y + 1.0, "one blown against a wall slides down it (y %.1f above the floor)" % (wall_leaf.get("pos", Vector3.ZERO).y - leaf_at.y))
	game.sky.wind = wind_was
	fl._leaves.clear()
	fl.process_mode = Node.PROCESS_MODE_INHERIT
	# Wind: Terraria's random walk, weak (at most 0.35) until 120 max life.
	game.sky.strongest_life = 100
	for i in 20000:
		game.sky.wind_tick()
	check(absf(game.sky.wind_target) <= 0.35, "the wind stays light before 120 max life (%.2f)" % game.sky.wind_target)

	# Placeables' level of detail: a chest a few chunks away is drawn as its
	# crossed sprite; walk up to it and it's its full model again.
	var far_chest := Vector3i(p.global_position.floor()) + Vector3i(100, 0, 0)
	game.world.set_block(far_chest + Vector3i.DOWN, stone)
	game.world.set_block(far_chest, Data.block_id("chest"))
	for i in 30:
		await frames(1)
	var cross_mesh: ArrayMesh = BlockModels.model_mesh(Data.block_id("chest"), "cross", game.block_rotation(far_chest)).mesh
	var far_model: Dictionary = game.block_models.model_at(far_chest)
	check(not far_model.is_empty() and far_model.mesh == cross_mesh, "a placeable far off is drawn as its crossed sprite")
	var was_at := p.global_position
	p.global_position = Vector3(far_chest) + Vector3(-3, 0, 0.5)
	for i in 30:
		await frames(1)
	var near_model: Dictionary = game.block_models.model_at(far_chest)
	check(not near_model.is_empty() and near_model.mesh != cross_mesh, "and up close its full model")
	p.global_position = was_at
	game.world.set_block(far_chest, 0)

	# Platforms that touch are one floor: no side faces where they meet, the
	# same top height, and a lone platform is closed all round.
	var plat_at := leaf_at + Vector3i(0, 0, 6)
	for x in range(-1, 2):
		game.world.set_block(plat_at + Vector3i(x, -1, 0), stone)
		game.world.set_block(plat_at + Vector3i(x, 0, 0), 0)
	var wplat := Data.block_id("wood_platform")
	var left := plat_at + Vector3i(-1, 0, 0)
	game.world.set_block(left, wplat)
	await frames(5)
	var lone: ArrayMesh = game.block_models.model_at(left).get("mesh")
	check(lone != null and _side_faces(lone, 0.5) and _side_faces(lone, -0.5), "a lone platform has its edges")
	var top_edge := false
	if lone != null and lone.get_surface_count() > 0:
		for v: Vector3 in lone.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			top_edge = top_edge or (is_equal_approx(v.y, 1.0) and (absf(absf(v.x) - 0.5) < 0.001 or absf(absf(v.z) - 0.5) < 0.001))
	check(lone != null and not top_edge, "and they're bevelled (its top stops short of the block's edge)")
	game.world.set_block(plat_at, wplat)
	await frames(5)
	var lm: ArrayMesh = game.block_models.model_at(left).get("mesh")
	var rm: ArrayMesh = game.block_models.model_at(plat_at).get("mesh")
	check(lm != null and rm != null and not _side_faces(lm, 0.5) and _side_faces(lm, -0.5)
			and not _side_faces(rm, -0.5) and _side_faces(rm, 0.5), "platforms side by side have no faces where they meet")
	check(lm != null and rm != null and is_equal_approx(lm.get_aabb().end.y, 1.0) and is_equal_approx(rm.get_aabb().end.y, 1.0),
			"and their tops are level with the top of the block")
	# The floor takes the noise picked for the platform's method.
	var popts := Data.method_options("wood_platform", Data.block(wplat).method)
	var pmat := BlockModels.platform_material(wplat)
	check(pmat.get_shader_parameter("voxel_noise") == maxi(0, Data.EXTRUDE_NOISES.find(popts.get("noise", "none")))
			and is_equal_approx(pmat.get_shader_parameter("noise_strength"), float(popts.get("strength", 0.5))),
			"the floor has the platform's picked noise (%s)" % popts.get("noise", "none"))
	game.world.set_block(left, 0)
	game.world.set_block(plat_at, 0)
	await frames(5)

	# Platform stairs: the hammer turns a platform into a stair rising away
	# from you, then the other way, then flat; it's drawn as Terraria's stair.
	var stair_at := leaf_at + Vector3i(0, 0, 6)
	for x in range(-1, 2):
		game.world.set_block(stair_at + Vector3i(x, -1, 0), stone)
		game.world.set_block(stair_at + Vector3i(x, 0, 0), 0)
	var wp := Data.block_id("wood_platform")
	game.world.set_block(stair_at, wp)
	await frames(5)
	var flat_mesh = game.block_models.model_at(stair_at).get("mesh")
	var shapes := []
	for i in 3:
		game.hammer_shape(stair_at, 1)
		shapes.append(game.world.get_shape(stair_at))
	check(shapes == [Game.SHAPE_RAMP + 1, Game.SHAPE_RAMP + 3, 0], "a platform hammers into a stair, the other way, then flat (%s)" % [shapes])
	game.hammer_shape(stair_at, 1)
	await frames(5)
	var stair_mesh = game.block_models.model_at(stair_at).get("mesh")
	check(stair_mesh != null and stair_mesh != flat_mesh and Data.block_id("wood_platform_stair") >= Data.DECORATION_BASE,
			"a stair is drawn with Terraria's stair art")
	check(game.save_world(), "saved with the stair")
	game.queue_free()
	await frames(5)
	game = Game.new()
	add_child(game)
	game.start({"mode": "load", "name": "PlaceablesTest", "path": WORLD})
	while game.state != Game.State.PLAYING:
		await frames(1)
	await frames(30)
	check(game.block_rotation(placed) == 1, "rotation survives save/load")
	check(game.world.get_shape(stair_at) == Game.SHAPE_RAMP + 1, "a platform stair survives save/load")
	game.break_block(placed)
	await frames(20)
	check(game.world.get_block(placed) == 0 and not game.block_rotations.has(Chests.key(placed)), "breaking it removes block and rotation")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WORLD))
	print("RESULT: %d failures" % failures.size())
	for f in failures:
		print("  - " + f)
	get_tree().quit(1 if failures.size() > 0 else 0)
