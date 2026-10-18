extends Node
## NPC display scales (Data.npc_scale, NPC.look) and the NPC scale editor.

const SAVE := "user://npc_scale_editor_test.json"

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
	var saved := Data.npc_scales.duplicate(true)
	# 1. Scales: the sprite and hitbox grow together, or the sprite alone.
	Data.npc_scales = {}
	var base := NPC.look("Zombie")
	check(Data.npc_scale("Zombie") == {"scale": 1.0, "hitbox": true}, "NPCs start at their npcs.json size")
	Data.set_npc_scale("Zombie", 1.5)
	var big := NPC.look("Zombie")
	check(big.sprite_size.is_equal_approx(base.sprite_size * 1.5) and is_equal_approx(big.hitbox[1], base.hitbox[1] * 1.5)
			and is_equal_approx(big.top, base.top * 1.5), "x1.5: the sprite and the hitbox are half as big again")
	Data.set_npc_scale("Zombie", 1.5, false)
	var sprite_only := NPC.look("Zombie")
	check(sprite_only.sprite_size.is_equal_approx(base.sprite_size * 1.5) and is_equal_approx(sprite_only.hitbox[1], base.hitbox[1]),
			"with the hitbox unticked only the sprite grows")
	var npc := NPC.new()
	Data.set_npc_scale("Zombie", 2.0)
	npc.setup("Zombie")
	check(is_equal_approx(npc.half.y, float(Data.npcs.Zombie.size[1]) * 2.0) and is_equal_approx(npc.health_bar.position.y, base.top * 2.0 + 0.25),
			"a spawned Zombie at x2 is twice as tall, health bar over its head")
	npc.free()
	# Fliers and town NPCs scale too.
	Data.set_npc_scale("DemonEye", 0.5)
	check(is_equal_approx(NPC.look("DemonEye").sprite_y, float(Data.npcs.DemonEye.size[1]) * 0.25), "a flier's sprite stays centred on it")
	Data.set_npc_scale("Guide", 1.2)
	var guide := NPC.look("Guide")
	Data.set_npc_scale("Guide", 1.0)
	check(is_equal_approx(guide.top, NPC.look("Guide").top * 1.2), "town NPCs (drawn at the player's height) scale too")
	check(not Data.npc_scales.has("Guide"), "back to 1 is no setting at all")

	# 2. The editor: pick an NPC, scale it, see it, save.
	Data.npc_scales = {}
	Data.save_npc_scales(SAVE)
	var ed: Node3D = load("res://editor/npc_scale_editor.tscn").instantiate()
	ed.save_path = SAVE
	add_child(ed)
	await frames(5)
	check(ed._list.item_count == Data.npcs.size() and ed.current == "Zombie", "the editor lists every NPC (%d)" % ed._list.item_count)
	ed._search.text = "slime"
	ed._search.text_changed.emit("slime")
	check(ed._shown.size() > 3 and ed._shown.all(func(k): return "slime" in (Assets.npc_name(k) + k).to_lower()), "search narrows the list (%d slimes)" % ed._shown.size())
	ed.select("BlueSlime")
	var before: Vector2 = NPC.look("BlueSlime").sprite_size
	ed._scale_box.value = 2.0
	await frames(2)
	check(ed.dirty and is_equal_approx(Data.npc_scale("BlueSlime").scale, 2.0) and ed._npc.scale.is_equal_approx(Vector3(before.x * 2.0, before.y * 2.0, 1.0)),
			"the scale box resizes the preview (%s)" % ed._npc.scale)
	check("x2" in ed._list.get_item_text(ed._shown.find("BlueSlime")), "scaled NPCs are marked in the list")
	ed._hitbox_check.button_pressed = false
	await frames(2)
	check(not Data.npc_scale("BlueSlime").hitbox, "the hitbox can be left as it was")
	# Matching the player's pixel size: a sprite pixel as big as the player's.
	var px := func(k: String) -> float:
		var lk := NPC.look(k)
		return (lk.sprite_size.y / (lk.frame_h - maxf(lk.trim, 0.0))) / PaperDoll.player_pixel_size()
	check(is_equal_approx(PaperDoll.player_pixel_size() * PaperDoll.standing_image().get_height(), 1.8), "the player's pixel: 1.8 m over the standing figure's height")
	ed.select("EyeofCthulhu")
	ed.match_player_pixels("EyeofCthulhu")
	check(absf(px.call("EyeofCthulhu") - 1.0) < 0.01 and Data.npc_scale("EyeofCthulhu").scale > 1.5,
			"Match player pixels: the Eye of Cthulhu grows to x%.2f, its pixels the player's" % Data.npc_scale("EyeofCthulhu").scale)
	ed.match_all_player_pixels()
	var off := Data.npcs.keys().filter(func(k): return absf(px.call(k) - 1.0) > 0.01 and Data.npc_scale(k).scale > ed.SCALE_MIN and Data.npc_scale(k).scale < ed.SCALE_MAX)
	check(off.is_empty() and not Data.npc_scale("BlueSlime").hitbox, "Match all NPCs: every one on the player's pixel grid, settings kept (%s)" % [off])
	ed._revert()
	check(Data.npc_scales.is_empty() and not ed.dirty, "Revert to saved undoes it")
	ed.select("BlueSlime")
	ed.set_size_scale(2.0)
	ed.set_hitbox_scales(false)
	await key(KEY_PAGEDOWN)
	check(ed.current != "BlueSlime", "PageDown shows the next NPC (%s)" % ed.current)
	await key(KEY_S, true)
	check(not ed.dirty and FileAccess.file_exists(SAVE), "Ctrl+S saves")
	Data.load_npc_scales(SAVE)
	check(Data.npc_scale("BlueSlime") == {"scale": 2.0, "hitbox": false} and Data.npc_scales.size() == 1, "saved settings are what was edited (%s)" % [Data.npc_scales])
	ed.queue_free()
	await frames(2)

	Data.npc_scales = saved
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("RESULT: %d failures" % failures.size())
	for f in failures:
		print("  - " + f)
	get_tree().quit(1 if failures.size() > 0 else 0)
