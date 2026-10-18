extends Node
## Tuned models (TunedModels), the model sculptor, and every voxel method's
## "one colour per voxel" option.

const DIR := "user://model_sculptor_test/"

var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func key(code: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		Input.parse_input_event(e)
		await frames(1)


## A left click on the sculptor's view (straight to it: a headless window is
## too small to keep its panels out of the way).
func click(ed: Node, at: Vector2, ctrl := false) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = at
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		ed._unhandled_input(e)
		await frames(1)


func _ready() -> void:
	Settings.persist = false
	TunedModels.dir = DIR
	TunedModels.patch_dir = DIR + "patches/"
	_run()


## True if every voxel of the mesh shows one colour on all its faces (within
## rounding: vertex colours are kept to 8 bits in linear light, coarse in the
## dark, so compare them there).
func one_colour(mesh: ArrayMesh, textured: bool, tex: Image, px: float) -> bool:
	var vx := TunedModels.voxelize(mesh.surface_get_arrays(0), textured, tex, px)
	for c in vx.cells:
		var first := Color(0, 0, 0, 0)
		for col in vx.cells[c]:
			if col.a < 0.5:
				continue
			var lin: Color = col.srgb_to_linear()
			if first.a < 0.5:
				first = lin
			elif absf(lin.r - first.r) + absf(lin.g - first.g) + absf(lin.b - first.b) > 0.04:
				return false
	return not vx.cells.is_empty()


func _run() -> void:
	NPCModels.load_file("user://no_such_file.json")
	var zombie := NPCModels.frames_of("Zombie")

	# 1. Meshes back into voxels: the same model again.
	var same := []
	for m in ["hull", "hull_top", "lathe", "extruded"]:
		var built: Dictionary = NPCModels.mesh("Zombie", m, 0)
		var model := TunedModels.from_voxelized([TunedModels.voxelize(built.mesh.surface_get_arrays(0), built.textured, zombie.arts[0], zombie.apx)], true)
		var back := BlockModelMesh.mesh_from_arrays(TunedModels.arrays(model, 0, zombie.apx))
		# Hulls come back face for face; the lathe within a few faces (and the
		# extruded model's whole-sprite front splits into a face per voxel).
		var n0: int = built.mesh.surface_get_array_len(0)
		var n1 := back.surface_get_array_len(0)
		var close: bool = n1 == n0 if m.begins_with("hull") else (m == "extruded" or absi(n1 - n0) <= n0 / 50)
		# (The extruded front is the whole sprite, see-through pixels too: the
		# voxels sit inside its box.)
		var box_ok: bool = back.get_aabb().is_equal_approx(built.mesh.get_aabb()) if m != "extruded" \
				else built.mesh.get_aabb().grow(0.001).encloses(back.get_aabb())
		if box_ok and close:
			same.append(m)
	check(same.size() == 4, "hull, hull top, lathe and extruded models turn back into voxels that rebuild the same mesh (%s)" % [same])
	var hull: ArrayMesh = NPCModels.mesh("Zombie", "hull", 0).mesh
	var filled := TunedModels.from_voxelized([TunedModels.voxelize(hull.surface_get_arrays(0), false, null, zombie.apx)], true)
	var shell := TunedModels.from_voxelized([TunedModels.voxelize(hull.surface_get_arrays(0), false, null, zombie.apx)], false)
	check(filled.frames[0].count(0) < shell.frames[0].count(0), "seeding fills the inside, so sculpting never opens a hollow")
	var hidden_ok := true
	for i in range(1, filled.looks.size()):
		var l: PackedColorArray = filled.looks[i]
		for col in l:
			if col == Color(0, 0, 0) and l[0] != Color(0, 0, 0):
				hidden_ok = false
	check(hidden_ok, "faces the method didn't draw take the voxel's own colour (none turn up black when uncovered)")
	var enc := TunedModels.decode(TunedModels.encode(filled))
	check(enc.size == filled.size and enc.offset == filled.offset and enc.frames[0] == filled.frames[0] and enc.looks.size() == filled.looks.size(),
			"a model saves and loads unchanged")

	# 2. One colour per voxel, on every voxel method.
	check(not one_colour(hull, false, null, zombie.apx), "a hull has voxels with faces of different colours (its tops)")
	NPCModels.set_option("Zombie", "hull", "one_color", true)
	check(one_colour(NPCModels.mesh("Zombie", "hull", 0).mesh, false, null, zombie.apx), "with one colour per voxel, every voxel of the hull is one colour")
	NPCModels.set_option("Zombie", "extruded", "one_color", true)
	var ex: Dictionary = NPCModels.mesh("Zombie", "extruded", 0)
	check(not ex.textured and one_colour(ex.mesh, false, null, zombie.apx), "and of the (textured) extruded model")
	NPCModels.reset_options("Zombie", "hull")
	NPCModels.reset_options("Zombie", "extruded")
	var saw := Data.block_id("sawmill")
	var saw_d := Data.block(saw)
	var saw_px: float = saw_d.get("art_px", saw_d.sprite_px)
	Data.set_method_option("sawmill", "lathe", "one_color", true)
	BlockModelMesh.clear_cache()
	check(one_colour(BlockModelMesh.build(saw, "lathe").mesh, false, null, saw_px), "placeables have it too (the sawmill's lathe)")
	Data.reset_method_options("sawmill", "lathe")
	BlockModelMesh.clear_cache()

	# 3. The sculptor.
	var ed: Node3D = load("res://editor/model_sculptor.tscn").instantiate()
	add_child(ed)
	await frames(3)
	var zsrc: Dictionary = ed._sources.filter(func(s): return s.name == "Zombie")[0]
	ed.select(zsrc)
	check(ed._model.is_empty() and "not tuned" in ed._header.text, "a Zombie isn't tuned yet")
	ed.seed_from("hull")
	var zkey := TunedModels.npc_key("Zombie")
	check(ed._model.frames.size() == 3 and ed._model.frames[0].count(0) < ed._model.frames[0].size() and TunedModels.model(zkey) == ed._model,
			"starting from its hull: all 3 frames, in the game's store")
	# Camera: Blender's views.
	await key(KEY_KP_1)
	check(ed._ortho and ed._auto_ortho and is_zero_approx(ed._yaw) and is_zero_approx(ed._pitch), "numpad 1: the front, orthographic")
	await key(KEY_KP_3)
	check(is_equal_approx(ed._yaw, PI * 0.5), "numpad 3: the right side")
	await key(KEY_KP_1, true)
	check(is_equal_approx(ed._yaw, PI), "Ctrl+numpad 1: the back")
	await key(KEY_KP_7)
	check(is_equal_approx(ed._pitch, PI * 0.5) and ed._cam.global_basis.z.is_equal_approx(Vector3.UP), "numpad 7: from the top")
	await key(KEY_KP_4)
	check(not ed._ortho, "orbiting away from a view goes back to perspective")
	await key(KEY_KP_5)
	check(ed._ortho and not ed._auto_ortho, "numpad 5: orthographic")
	await key(KEY_KP_5)
	await key(KEY_1)
	check(ed._ortho and is_zero_approx(ed._yaw), "the number row works as the numpad (1: the front)")
	# Pointing at it from the front.
	var g0: PackedInt32Array = ed._model.frames[0].duplicate()
	var centre := Vector2.ZERO
	var hit := {}
	var box: AABB = hull.get_aabb()
	for dy in range(0, 20):
		centre = ed._cam.unproject_position(box.get_center() + Vector3(0, (dy - 10) * 0.05, 0))
		hit = ed.pick(centre)
		if not hit.is_empty() and hit.hit != null:
			break
	check(not hit.is_empty() and hit.hit != null and hit.face == 0 and hit.add == hit.hit + Vector3i(0, 0, 1), "from the front it points at a voxel's front face")
	if hit.is_empty() or hit.hit == null:
		hit = {"hit": Vector3i(ed._model.size.x / 2, ed._model.size.y / 2, ed._model.size.z - 1), "face": 0, "add": Vector3i.ZERO}
	var c: Vector3i = hit.hit
	ed.set_tool("remove")
	await click(ed, centre)
	check(TunedModels.get_look(ed._model, 0, c) == 0 and ed._undo.size() == 1, "clicking with Remove takes the voxel out (one undo step)")
	await key(KEY_Z, true)
	check(ed._model.frames[0] == g0, "Ctrl+Z puts it back")
	await key(KEY_Y, true)
	check(TunedModels.get_look(ed._model, 0, c) == 0, "Ctrl+Y takes it out again")
	await key(KEY_Z, true)
	# Add, paint, one face, the eyedropper.
	ed.color = Color(0.0, 1.0, 0.0)
	ed._begin_stroke()
	ed.apply_tool("add", hit.add)
	ed._end_stroke()
	check(TunedModels.get_look(ed._model, 0, hit.add) != 0, "Add puts a voxel on the face pointed at")
	ed.color = Color(0.0, 0.0, 1.0)
	ed.face_paint = true
	ed._begin_stroke()
	ed.apply_tool("paint", c, 0)
	ed._end_stroke()
	var look: PackedColorArray = ed._model.looks[TunedModels.get_look(ed._model, 0, c)]
	check(look[0] == Color(0, 0, 1) and look[4] != Color(0, 0, 1), "painting one face colours just that face")
	ed.face_paint = false
	ed.color = Color(1, 1, 1)
	await click(ed, ed._cam.unproject_position((Vector3(hit.add) + ed._model.offset + Vector3(0.5, 0.5, 1.0)) * ed._px), true)
	check(ed.color.is_equal_approx(Color(0, 1, 0)), "Ctrl+click picks the colour of the face pointed at (the added voxel's)")
	# Mirror and all frames.
	ed.mirror = true
	var m: Vector3i = ed.mirrored(c)
	ed._begin_stroke()
	ed.apply_tool("remove", c)
	ed._end_stroke()
	check(m != c and TunedModels.get_look(ed._model, 0, m) == 0 and TunedModels.get_look(ed._model, 0, c) == 0, "with mirror, the voxel across the middle goes too")
	ed.mirror = false
	ed.use_range = true
	ed.frame_from = 0
	ed.frame_to = 2
	ed.color = Color(1, 0, 1)
	# A cell every frame has (the legs move).
	var other := c + Vector3i(0, -2, -1)
	for tries in 200:
		var everywhere := true
		for f in 3:
			everywhere = everywhere and TunedModels.get_look(ed._model, f, other) != 0
		if everywhere and other != c:
			break
		other = Vector3i(c.x, c.y - 1 - tries / 20, ed._model.size.z / 2 + tries % 10 - 5)
	ed._begin_stroke()
	ed.apply_tool("paint", other)
	ed._end_stroke()
	var every := true
	for f in 3:
		var id := TunedModels.get_look(ed._model, f, other)
		every = every and id != 0 and ed._model.looks[id][0] == Color(1, 0, 1)
	check(every, "with the frame range 1 to 3, an edit changes every frame")
	ed.frame_from = 1
	ed.color = Color(1, 1, 0)
	ed._begin_stroke()
	ed.apply_tool("paint", other)
	ed._end_stroke()
	var first: PackedColorArray = ed._model.looks[TunedModels.get_look(ed._model, 0, other)]
	var later: PackedColorArray = ed._model.looks[TunedModels.get_look(ed._model, 2, other)]
	check(first[0] == Color(1, 0, 1) and later[0] == Color(1, 1, 0), "with 2 to 3, frame 1 is left alone")
	ed.frame_from = 2
	ed.frame_to = 0
	check(ed.edit_frames() == [2, 0], "a range can wrap past the last frame (3 to 1: frames 3 and 1)")
	ed.use_range = false
	check(ed.edit_frames() == [ed.frame], "with the range off, only the frame shown")
	# Smart paint: a voxel takes on what's round it (behind the voxel removed
	# above, now on the surface).
	var q := c + Vector3i(0, 0, -1)
	while TunedModels.get_look(ed._model, 0, q) == 0 and q.z > 0:
		q.z -= 1
	ed.color = Color(0.2, 0.4, 0.6)
	ed.set_brush(4)
	ed._begin_stroke()
	ed.apply_tool("paint", q)
	ed._end_stroke()
	var patch := TunedModels.solid_look(ed._model, Color(0.2, 0.4, 0.6))
	ed.set_brush(1)
	ed.color = Color(1, 0.5, 0)
	ed._begin_stroke()
	ed.apply_tool("paint", q)
	ed._end_stroke()
	var odd := TunedModels.get_look(ed._model, 0, q)
	ed.set_reach(2)
	ed._begin_stroke()
	ed.apply_tool("smart", q)
	ed._end_stroke()
	check(odd != patch and TunedModels.get_look(ed._model, 0, q) == patch, "smart paint covers an odd voxel with the look of the voxels round it")
	# Over a range of frames, each voxel gets the same pick on every frame.
	ed.set_brush(3)
	ed.set_reach(3)
	ed.use_range = true
	ed.frame_from = 0
	ed.frame_to = 2
	ed._begin_stroke()
	ed.apply_tool("smart", other)
	ed._end_stroke()
	var consistent := true
	var varied := {}
	for entry in ed._brush_cells(other):
		var ids := []
		for f in 3:
			ids.append(TunedModels.get_look(ed._model, f, entry[0]))
		if not 0 in ids:
			consistent = consistent and ids[0] == ids[1] and ids[1] == ids[2]
			varied[ids[0]] = true
	check(consistent, "smart paint gives a voxel the same look on every frame of the range (%d looks used)" % varied.size())
	# Texture: noise of the model's own colours near the current one.
	ed.color = ed._model.looks[TunedModels.get_look(ed._model, ed.frame, other)][0]
	ed.texture_range = 0.3
	var palette := TunedModels.colors_used(ed._model)
	var near_ok := 0
	for col in palette:
		if ed.color_distance(col, ed.color) <= 0.3:
			near_ok += 1
	ed._begin_stroke()
	ed.apply_tool("texture", other)
	ed._end_stroke()
	var textured := {}
	var tex_ok := true
	for entry in ed._brush_cells(other):
		var ids := []
		for f in 3:
			ids.append(TunedModels.get_look(ed._model, f, entry[0]))
		if 0 in ids:
			continue
		var col: Color = ed._model.looks[ids[0]][0]
		tex_ok = tex_ok and ids[0] == ids[1] and ids[1] == ids[2] and col in palette and ed.color_distance(col, ed.color) <= 0.3
		textured[col.to_html(false)] = true
	check(near_ok > 1 and tex_ok and textured.size() > 1,
			"the texture brush mixes %d of the model's colours near the current one, the same on every frame" % textured.size())
	ed.use_range = false
	ed.set_tool("texture")
	check(ed.tool == "texture", "T picks the texture brush")
	ed.set_tool("smart")
	check(ed.tool == "smart", "C picks smart paint")
	# Past the grid's edge: it grows, and nothing moves.
	var edge := Vector3i(ed._model.size.x - 1, c.y, c.z)
	while TunedModels.get_look(ed._model, 0, edge) == 0 and edge.x > 0:
		edge.x -= 1
	var at_mesh: Vector3 = (Vector3(edge) + ed._model.offset) * ed._px
	var old_size: Vector3i = ed._model.size
	ed._begin_stroke()
	var shift: Vector3i = ed.apply_tool("add", Vector3i(old_size.x, edge.y, edge.z))
	ed._end_stroke()
	var moved := edge + shift
	check(ed._model.size.x > old_size.x and TunedModels.get_look(ed._model, 0, moved) != 0
			and ((Vector3(moved) + ed._model.offset) * ed._px).is_equal_approx(at_mesh), "adding past the edge grows the grid, the model where it was")
	await key(KEY_Z, true)
	check(ed._model.size == old_size, "and undo shrinks it back")
	# Saving, and the game's use of it.
	await key(KEY_S, true)
	check(FileAccess.file_exists(TunedModels.path(zkey)) and ed._unsaved.is_empty(), "Ctrl+S saves it to data/tuned/ (here: %s)" % DIR)
	var saved: Dictionary = ed._model
	TunedModels.clear_cache()
	var loaded := TunedModels.model(zkey)
	check(loaded.frames[0] == saved.frames[0] and loaded.size == saved.size, "it loads back as sculpted")
	# The patch: the start (rebuilt from the sprite) and the edits, no art.
	var zpatch: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TunedModels.patch_path(zkey)))
	var edited := 0
	for n in zpatch.edits:
		edited += int(n) / 2
	var voxels := 0
	for g in saved.frames:
		voxels += g.size() - g.count(0)
	check(zpatch.base.method == "hull" and edited > 0 and edited < voxels / 10,
			"its patch says what it started from and keeps only the edited cells (%d of %d voxels)" % [edited, voxels])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TunedModels.path(zkey)))
	TunedModels.clear_cache()
	var rebuilt := TunedModels.model(zkey)
	check(TunedModels.fingerprint(rebuilt) == TunedModels.fingerprint(saved) and FileAccess.file_exists(TunedModels.path(zkey)),
			"without the whole copy, it's rebuilt from the patch and the sprite exactly (and cached again)")
	NPCModels.clear_cache()
	NPCModels.set_method("Zombie", "tuned")
	var npc := NPC.new()
	npc.setup("Zombie")
	var shown: ArrayMesh = npc.sprite.get_child(0).mesh if npc.sprite is NPCModel else null
	check(shown != null and shown.surface_get_array_len(0) == TunedModels.arrays(loaded, 0, zombie.apx)[Mesh.ARRAY_VERTEX].size(),
			"a Zombie set to Tuned spawns as the sculpted model")
	npc.free()
	NPCModels.set_option("Zombie", "tuned", "one_color", true)
	check(one_colour(NPCModels.mesh("Zombie", "tuned", 0).mesh, false, null, zombie.apx), "tuned models take one colour per voxel too")
	NPCModels.reset_options("Zombie", "tuned")
	NPCModels.set_method("Zombie", "billboard")
	check(NPCModels.mesh("Goblin" if Data.npcs.has("Goblin") else "GreenSlime", "tuned", 0).mesh.get_aabb().is_equal_approx(
			NPCModels.mesh("Goblin" if Data.npcs.has("Goblin") else "GreenSlime", "hull", 0).mesh.get_aabb()), "an NPC not tuned yet shows its hull")
	# A placeable.
	var ssrc: Dictionary = ed._sources.filter(func(s): return s.name == "sawmill")[0]
	ed.select(ssrc)
	ed.seed_from("claude")
	ed.save_all()
	BlockModelMesh.clear_cache()
	var tuned_saw: Dictionary = BlockModelMesh.build(saw, "tuned")
	check(not tuned_saw.textured and tuned_saw.mesh.get_aabb().is_equal_approx(BlockModelMesh.build(saw, "claude").mesh.get_aabb()),
			"placeables tune the same way (the sawmill, from Claude's model)")
	# Deleting.
	ed._on_delete_pressed()
	ed._on_delete_pressed()
	check(not TunedModels.has(TunedModels.block_key("sawmill")) and not FileAccess.file_exists(TunedModels.path(TunedModels.block_key("sawmill"))),
			"Delete (pressed twice) removes the tuned model and its file")
	ed.queue_free()
	await frames(2)

	TunedModels.remove(zkey)
	TunedModels.clear_cache()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "patches/"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	TunedModels.dir = "res://data/tuned/"
	TunedModels.patch_dir = "res://data/tuned_patches/"
	BlockModelMesh.clear_cache()
	NPCModels.load_file()
	print("RESULT: %d failures" % failures.size())
	for f in failures:
		print("  - " + f)
	get_tree().quit(1 if failures.size() > 0 else 0)
