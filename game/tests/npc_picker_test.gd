extends Node
## NPC 3D models (NPCModels, NPCModel) and the NPC picker.

const SAVE := "user://npc_picker_test.json"

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


func _ready() -> void:
	Settings.persist = false
	_run()


func _run() -> void:
	# 1. Meshes: every NPC in every method, its sprite's size, standing on y = 0.
	NPCModels.load_file("user://no_such_file.json")
	check(Data.npcs.keys().all(func(k): return NPCModels.method(k) == "billboard"), "with nothing saved every NPC is a billboard")
	var bad: Array = []
	for k in Data.npcs:
		var size: Vector2 = NPCModels.frames_of(k).size
		for m in NPCModels.METHODS:
			if m == "billboard":
				continue
			var mesh: ArrayMesh = NPCModels.mesh(k, m, 0).mesh
			var box := mesh.get_aabb() if mesh.get_surface_count() > 0 else AABB()
			# Hull and lathe drop see-through pixels: no taller or wider than the sprite.
			if box.size.y <= 0.0 or box.size.y > size.y + 0.01 or box.position.y < -0.01 or absf(box.get_center().x) > size.x * 0.5 + 0.01:
				bad.append("%s/%s" % [k, m])
	check(bad.is_empty(), "every NPC builds in every method, its sprite's size, feet on the ground (%s)" % [bad.slice(0, 8)])
	var zombie := NPCModels.frames_of("Zombie")
	check(zombie.images.size() == int(Data.npcs.Zombie.frames) and zombie.arts[0].get_width() * 2 == zombie.images[0].get_width(),
			"a Zombie's sheet is cut into its %d frames, built from its 2x art" % zombie.images.size())
	var top: AABB = NPCModels.mesh("Zombie", "hull_top", 0).mesh.get_aabb()
	var side: AABB = NPCModels.mesh("Zombie", "hull", 0).mesh.get_aabb()
	check(is_equal_approx(top.size.z, top.size.y) and side.size.z < top.size.z,
			"Hull Top: front and top silhouettes, as deep as the Zombie is tall (%.2f, the hull %.2f)" % [top.size.z, side.size.z])
	var ex := NPCModels.options("Zombie", "extruded")
	check(ex.depth == zombie.art_w / 2, "Extruded is half the art's width deep by default (%d voxels)" % ex.depth)
	var thin: float = NPCModels.mesh("Zombie", "extruded", 0).mesh.get_aabb().size.z
	NPCModels.set_option("Zombie", "extruded", "depth", 2)
	var thinner: float = NPCModels.mesh("Zombie", "extruded", 0).mesh.get_aabb().size.z
	check(is_equal_approx(thinner, 2 * zombie.apx) and thinner < thin, "the depth setting thins it (%.3f -> %.3f blocks)" % [thin, thinner])
	NPCModels.reset_options("Zombie", "extruded")
	check(NPCModels.options("Zombie", "extruded").depth == ex.depth, "reset brings the defaults back")

	# 1b. Claude's hand-made models (NPCSculpt): the Eye of Cthulhu.
	check(NPCSculpt.has("EyeofCthulhu") and not NPCSculpt.has("Zombie"), "Claude has made the Eye of Cthulhu (and not the Zombie)")
	check(NPCModels.mesh("Zombie", "claude", 0).mesh.get_aabb().is_equal_approx(NPCModels.mesh("Zombie", "hull", 0).mesh.get_aabb()),
			"an NPC Claude hasn't made shows its hull")
	var eoc := NPCModels.frames_of("EyeofCthulhu")
	var sp := NPCSculpt.spec("EyeofCthulhu")
	var seen := {"front": 0, "back": 0, "pixels": 0, "gaps": 0, "clear": 0}
	var round_iris := true
	var iris := 0
	var mouth := {"open": true, "teeth": 0}
	for f in [0, 3]:
		# (Sculpted models drop the sprite's dark outline: compare with that.)
		var art: Image = NPCSculpt.without_outline(eoc.arts[f])
		var faces := {}
		var vox := NPCSculpt.voxels(sp, eoc.arts[f], faces)
		# Each column's front-most and back-most voxel.
		var near := {}
		var far := {}
		for v: Vector3i in vox:
			var col_key := Vector2i(v.x, v.y)
			if not near.has(col_key) or v.z > near[col_key]:
				near[col_key] = v.z
			if not far.has(col_key) or v.z < far[col_key]:
				far[col_key] = v.z
		for y in art.get_height():
			for x in art.get_width():
				var px := art.get_pixel(x, y)
				var col_key := Vector2i(x, y)
				if px.a > 0.5:
					seen.pixels += 1
					# What shows: the face toward you (its own colour, or the voxel's).
					if near.has(col_key):
						var nv := Vector3i(x, y, near[col_key])
						if faces.get(nv, {}).get(BlockModelMesh.FACE_FRONT, vox[nv]) == px:
							seen.front += 1
					if far.has(col_key):
						var fv := Vector3i(x, y, far[col_key])
						if faces.get(fv, {}).get(BlockModelMesh.FACE_BACK, vox[fv]) == px:
							seen.back += 1
				else:
					seen.gaps += 1
					if not near.has(col_key):
						seen.clear += 1
		# Seen from below, the iris's colours go round in rings: one per row.
		if f == 3:
			# The mouth from below: open in the middle (its lowest rows, under
			# the ball's centre), up into the ball's dark inside.
			for v: Vector3i in vox:
				if v.y >= 70 and absi(v.x - 27) <= 6 and absi(v.z - 27) <= 6:
					mouth.open = false
		var ring := {}
		for v: Vector3i in faces:
			if not faces[v].has(BlockModelMesh.FACE_DOWN):
				continue
			if f == 3:
				if faces[v][BlockModelMesh.FACE_DOWN] == Color.html("#b9a57f"):
					mouth.teeth += 1
				continue
			var down: Color = faces[v][BlockModelMesh.FACE_DOWN]
			if ring.has(v.y) and ring[v.y] != down:
				round_iris = false
			ring[v.y] = down
			if f == 0 and down.b > 0.6 and down.r < 0.4:
				iris += 1
	check(seen.front >= seen.pixels * 0.995 and seen.back >= seen.pixels * 0.995,
			"from the front it is the sprite (its outline dropped), from the back its mirror (%d and %d of %d pixels)" % [seen.front, seen.back, seen.pixels])
	check(seen.clear == seen.gaps, "the sprite's see-through pixels (its open mouth) are gaps right through (%d of %d)" % [seen.clear, seen.gaps])
	check(round_iris and iris > 50, "from below its iris is round: one colour per ring (%d blue faces)" % iris)
	check(mouth.open and mouth.teeth > 20, "from below its mouth is an open oval ringed with teeth (%d tooth faces)" % mouth.teeth)
	check(NPCModels.mesh("EyeofCthulhu", "claude", 0).mesh.get_aabb().size.y > NPCModels.frames_of("EyeofCthulhu").size.y * 0.8,
			"its tendrils reach up like the sprite's")
	NPCModels.clear_cache()
	NPCModels.prebuild("EyeofCthulhu", "claude")
	check(NPCModels._pending.size() == eoc.arts.size(), "its %d frames build on worker threads" % NPCModels._pending.size())
	var threaded: ArrayMesh = NPCModels.mesh("EyeofCthulhu", "claude", 4).mesh
	var direct_faces := {}
	var direct := BlockModelMesh.voxel_mesh(NPCSculpt.voxels(sp, NPCModels.frames_of("EyeofCthulhu").arts[4], direct_faces),
			NPCModels.frames_of("EyeofCthulhu").arts[4], NPCModels.frames_of("EyeofCthulhu").apx, NPCModels.options("EyeofCthulhu", "claude"), false, direct_faces)
	check(threaded.surface_get_array_len(0) == direct.surface_get_array_len(0), "a frame built on a thread is the same model")
	await get_tree().create_timer(1.0).timeout
	NPCModels.mesh("EyeofCthulhu", "claude", 0)
	check(NPCModels._pending.is_empty(), "finished builds are collected")

	# 1b'. Claude's King Slime: a see-through slime spun from the sprite; the
	# ninja and crown stay billboards.
	var ks := NPCModels.frames_of("KingSlime")
	var ks_sp := NPCSculpt.spec("KingSlime")
	var outline_px := 0
	var raw: Image = ks.arts[0]
	var clean := NPCSculpt.without_outline(raw)
	for y in raw.get_height():
		for x in raw.get_width():
			if raw.get_pixel(x, y).a > 0.5 and raw.get_pixel(x, y) != clean.get_pixel(x, y):
				outline_px += 1
	var ks_faces := {}
	var ks_body := {}
	var ks_vox := NPCSculpt.voxels(ks_sp, raw, ks_faces, ks_body)
	var dark := 0
	var ks_front := {"match": 0, "pixels": 0}
	var ks_near := {}
	for v: Vector3i in ks_vox:
		var k := Vector2i(v.x, v.y)
		if not ks_near.has(k) or v.z > ks_near[k]:
			ks_near[k] = v.z
		var look: Color = ks_vox[v]
		for fc in ks_faces.get(v, {}).values():
			look = fc if fc.get_luminance() < look.get_luminance() else look
		if look.get_luminance() < 0.2:
			dark += 1
	for k: Vector2i in ks_near:
		ks_front.pixels += 1
		var nv := Vector3i(k.x, k.y, ks_near[k])
		if ks_faces.get(nv, {}).get(BlockModelMesh.FACE_FRONT, ks_vox[nv]) == clean.get_pixel(k.x, k.y):
			ks_front.match += 1
	check(outline_px > 100 and dark == 0, "the sprite's dark outline (%d pixels) leaves no black voxels on the slime" % outline_px)
	check(ks_front.match == ks_front.pixels, "from the front the slime is the sprite, its outline dropped (%d pixels)" % ks_front.pixels)
	var inside := NPCSculpt.solid_test(ks_body)
	var hollow_faces := 0
	for v: Vector3i in ks_vox:
		for d in TunedModels.FACES:
			if not ks_vox.has(v + d) and inside.call(v + d):
				hollow_faces += 1
	var ks_mesh: ArrayMesh = NPCModels.mesh("KingSlime", "claude", 0).mesh
	check(inside.is_valid() and hollow_faces > 0 and ks_vox.size() < 30000 and ks_mesh.surface_get_array_len(0) > 0,
			"it's a solid body kept as its surface (%d voxels; its inside counts as filled, so no faces show inside it)" % ks_vox.size())
	check(is_equal_approx(NPCModels.glass("KingSlime", "claude"), 0.8) and NPCModels.glass("KingSlime", "hull") == 1.0
			and NPCModels.material("KingSlime", 0, false, 0.8).shader.resource_path.ends_with("npc_model_glass.gdshader"),
			"Claude's King Slime is see-through (0.8 opaque), so the ninja inside shows")

	# 1c. Pre-rendered sprites (NPCRenders): the shot for a direction, and its turn.
	var round_trip := true
	for row in NPCRenders.PITCHES.size():
		for col in (1 if absf(NPCRenders.PITCHES[row]) > 89.0 else NPCRenders.YAWS):
			round_trip = round_trip and NPCRenders.pick(NPCRenders.view_dir(col, row)) == Vector2i(col, row)
	var level := NPCRenders.PITCHES.find(0.0)
	check(round_trip and NPCRenders.pick(Vector3(0, 0, 1)) == Vector2i(0, level) and NPCRenders.pick(Vector3(1, 0.1, 0)) == Vector2i(NPCRenders.YAWS / 4, level)
			and NPCRenders.pick(Vector3(0.1, -1, 0)) == Vector2i(0, 0), "every shot is the one picked looking from its direction (front, right, below)")
	check(NPCRenders.YAWS == 32 and NPCRenders.PITCHES.size() == 13 and NPCRenders.PITCHES[1] - NPCRenders.PITCHES[0] == 15.0,
			"shots every 11.25 degrees round and 15 degrees up and down")
	check(is_zero_approx(NPCRenders.roll(Vector3.UP, Basis.IDENTITY)) and is_equal_approx(NPCRenders.roll(Vector3.RIGHT, Basis.IDENTITY), -PI * 0.5),
			"a shot turns in the screen plane to keep its up along the model's")
	# (What's tuned is up to whoever sculpted: data/tuned/.)
	var eye_src := "tuned" if TunedModels.has(TunedModels.npc_key("EyeofCthulhu")) else "claude"
	var zombie_src := "tuned" if TunedModels.has(TunedModels.npc_key("Zombie")) else "hull"
	check(NPCRenders.source("EyeofCthulhu") == eye_src and NPCRenders.source("Zombie") == zombie_src,
			"shots are made of the tuned model, else Claude's, else the hull (the Eye: %s)" % eye_src)
	check(NPCModels.mesh("EyeofCthulhu", "rendered", 0).mesh == NPCModels.mesh("EyeofCthulhu", eye_src, 0).mesh, "the Rendered method's model is the one it shoots")
	NPCModels.set_option("Zombie", "rendered", "model", "extruded")
	check(NPCRenders.source("Zombie") == "extruded" and NPCModels.mesh("Zombie", "rendered", 0).mesh == NPCModels.mesh("Zombie", "extruded", 0).mesh,
			"set to shoot the Extruded model, the Rendered method shoots that")
	NPCModels.reset_options("Zombie", "rendered")
	check(NPCRenders.source("Zombie") == zombie_src and NPCModels.options("Zombie", "rendered").model == "auto", "reset, it's back to its own model")

	# 2. In the game: an NPC whose kind has a method is drawn as that model.
	NPCModels.set_method("Zombie", "hull")
	var npc := NPC.new()
	npc.setup("Zombie")
	check(npc.sprite is NPCModel and npc.sprite.method == "hull", "a Zombie set to Hull spawns as a hull model")
	var model: NPCModel = npc.sprite
	npc.process_mode = Node.PROCESS_MODE_DISABLED  # no game to act in
	add_child(npc)
	model.face(Vector3(0, 0, 3))
	var mi: MeshInstance3D = model.get_child(0)
	check((mi.global_basis * Vector3.LEFT).is_equal_approx(Vector3(0, 0, 1)), "it turns its face (the art looks left) the way it walks")
	model.set_frame(1)
	check(mi.mesh == NPCModels.mesh("Zombie", "hull", 1).mesh, "its frames step like the billboard's")
	model.set_flash(1.0)
	check(is_equal_approx(float(mi.get_instance_shader_parameter("flash")), 1.0), "hits flash it white")
	npc.queue_free()
	NPCModels.set_method("DemonEye", "extruded")
	var eye := NPC.new()
	eye.setup("DemonEye")
	eye.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(eye)
	var lk := NPC.look("DemonEye")
	var box: AABB = eye.sprite.get_child(0).mesh.get_aabb()
	check(is_equal_approx(eye.sprite.position.y + box.size.y * 0.5, lk.sprite_y), "a flier's model is centred where its billboard was")
	eye.sprite.face(Vector3(5, 0, 0))
	check((eye.sprite.get_child(0).global_basis * Vector3.LEFT).is_equal_approx(Vector3(1, 0, 0)), "a Demon Eye looks along its flight")
	eye.queue_free()
	NPCModels.set_method("GreenSlime", "lathe")
	var slime := NPC.new()
	slime.setup("GreenSlime")
	check(slime.sprite is NPCModel and slime.sprite.get_child(0).get_instance_shader_parameter("tint") == NPC.look("GreenSlime").tint,
			"slimes keep Terraria's tint")
	slime.free()
	NPCModels.set_method("EyeofCthulhu", "rendered")
	var shot := NPC.new()
	shot.setup("EyeofCthulhu")
	check(shot.sprite is RenderedSprite and shot.sprite.frames == 6 and shot.sprite._renders.is_empty(),
			"an Eye set to Rendered is a sprite; headless (nothing can be rendered) it stays the sheet")
	shot.free()
	# Turning: at most turn_rate a second (the Eye of Cthulhu), or at once.
	var turner := NPC.new()
	turner.setup("EyeofCthulhu")
	turner.turn_rate = 1.2
	turner.turn_facing(Vector3(1, 0, 0), 0.1)
	var turned := turner.turn_facing(Vector3(0, 0, 1), 0.5)
	var behind := turner.turn_facing(-turned, 0.5)
	check(is_equal_approx(Vector3(1, 0, 0).angle_to(turned), 0.6) and is_equal_approx(turned.angle_to(behind), 0.6),
			"a model turns toward where it looks at its turn rate (0.6 of a turn in half a second at 1.2), even right behind it")
	turner.turn_rate = -1.0
	check(turner.turn_facing(Vector3(0, 1, 0), 0.01).is_equal_approx(Vector3(0, 1, 0)), "with no turn rate it faces there at once")
	turner.free()
	NPCModels.set_method("Zombie", "billboard")
	var plain := NPC.new()
	plain.setup("Zombie")
	check(plain.sprite is EntitySprite and not NPCModels.methods.has("Zombie"), "back to Billboard: a sprite again, nothing saved for it")
	plain.free()

	# 3. The picker.
	NPCModels.load_file("user://no_such_file.json")
	var ed: Node3D = load("res://editor/npc_picker.tscn").instantiate()
	ed.save_path = SAVE
	add_child(ed)
	await frames(5)
	check(ed._list.item_count == Data.npcs.size() and ed.current == "Zombie", "the picker lists every NPC (%d), the Zombie first shown" % ed._list.item_count)
	check(ed._models.size() == NPCModels.METHODS.size() and ed.model_for("billboard") is EntitySprite and ed.model_for("lathe") is NPCModel,
			"it shows the NPC in all %d methods" % NPCModels.METHODS.size())
	ed._filter.select(2)
	ed._filter.item_selected.emit(2)
	check(not ed._shown.is_empty() and ed._shown.all(func(k): return Data.npcs[k].get("boss", false)) and "EyeofCthulhu" in ed._shown,
			"the Bosses filter lists bosses only (%d)" % ed._shown.size())
	ed._filter.select(3)
	ed._filter.item_selected.emit(3)
	check(ed._shown.has("Guide") and ed._shown.all(func(k): return Data.npcs[k].ai == "town"), "the Town NPCs filter")
	ed._filter.select(0)
	ed._search.text = "slime"
	ed._search.text_changed.emit("slime")
	check(ed._shown.size() > 3 and ed._shown.all(func(k): return "slime" in (Assets.npc_name(k) + k).to_lower()), "search narrows the list (%d slimes)" % ed._shown.size())
	ed._search.text = ""
	ed._search.text_changed.emit("")
	var f0: int = ed.frame()
	await frames(20)
	check(ed.frame() != f0 or Data.npcs.Zombie.get("walk_frames", [0, 0])[1] == Data.npcs.Zombie.get("walk_frames", [0, 0])[0],
			"the models walk through their frames")
	await key(KEY_4)
	check(ed.dirty and NPCModels.method("Zombie") == "extruded" and ed._settings_method == "extruded", "4 picks Extruded, and the settings follow it")
	check("extruded" in ed._list.get_item_text(ed._shown.find("Zombie")), "NPCs with a 3D method are marked in the list")
	var old: Node3D = ed.model_for("extruded")
	await key(KEY_BRACKETLEFT)
	await frames(1)
	check(NPCModels.options("Zombie", "extruded").depth == ex.depth - 1 and ed.model_for("extruded") != old, "[ thins the Extruded model and rebuilds it")
	# The Rendered setting: shots of the Extruded model, shot again when it changes.
	var shot_before: Node3D = ed.model_for("rendered")
	ed._render_model.select(1)
	ed._render_model.item_selected.emit(1)
	await frames(1)
	check(NPCModels.options("Zombie", "rendered").model == "extruded" and NPCRenders.source("Zombie") == "extruded"
			and ed.model_for("rendered") != shot_before, "Rendered: choosing \"Extruded model\" shoots the Extruded model")
	shot_before = ed.model_for("rendered")
	await key(KEY_BRACKETRIGHT)
	await frames(1)
	check(ed.model_for("rendered") != shot_before, "changing the Extruded model makes the rendered sprite again")
	await key(KEY_BRACKETLEFT)
	ed.select("EyeofCthulhu")
	check(ed._fit < 1.0 and ed._player.pixel_size < PaperDoll.player_pixel_size(), "a boss is shrunk to fit its slot, the player with it (%d%%)" % roundi(ed._fit * 100))
	ed._pick_at(ed._cam.unproject_position(ed._slots[NPCModels.METHODS.find("lathe")].global_position + Vector3(0, 0.6, 0)))
	check(NPCModels.method("EyeofCthulhu") == "lathe", "clicking a model chooses its method")
	var claude_label: Label3D = ed._labels[NPCModels.METHODS.find("claude")]
	check("Hand-made" in claude_label.text, "the Eye's Claude model is labelled hand-made")
	await key(KEY_PAGEDOWN)
	check(ed.current != "EyeofCthulhu", "PageDown shows the next NPC (%s)" % ed.current)
	await key(KEY_S, true)
	check(not ed.dirty and FileAccess.file_exists(SAVE), "Ctrl+S saves")
	NPCModels.load_file(SAVE)
	check(NPCModels.methods == {"Zombie": "extruded", "EyeofCthulhu": "lathe"} and int(NPCModels.extruded.Zombie.depth) == ex.depth - 1
			and NPCModels.options("Zombie", "rendered").model == "extruded",
			"saved: what was picked (%s)" % [NPCModels.methods])
	ed.queue_free()
	await frames(2)

	NPCModels.load_file()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("RESULT: %d failures" % failures.size())
	for f in failures:
		print("  - " + f)
	get_tree().quit(1 if failures.size() > 0 else 0)
