extends Node
## Creative mode (Minecraft-style): no damage, double-tap flight, instant
## breaking without drops, nothing used up, pick block, the item palette,
## switching modes and saving it. Runs headless: ./run_tests.sh

const PATH := "user://worlds/_creative_check.twld"

var game: Game
var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures.append(what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	Settings.persist = false
	Settings.set_value("render_distance", 4)
	_run()


func start(params: Dictionary) -> void:
	game = Game.new()
	add_child(game)
	game.start(params)
	while game.state != Game.State.PLAYING:
		await frames(1)
	game.spawner.process_mode = Node.PROCESS_MODE_DISABLED
	await frames(10)


func tap_jump() -> void:
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(2)


func drops_near(p: Vector3) -> int:
	return game.entities.get_children().filter(func(e): return e is ItemDrop and e.global_position.distance_to(p) < 4.0).size()


func _run() -> void:
	await start({"mode": "new", "name": "CreativeCheck", "seed": 3, "path": PATH, "size": Vector3i(256, 256, 256), "creative": true})
	var p := game.player
	var w := game.world
	check(game.creative and p.creative, "a creative world puts the player in creative mode")
	check(p.inventory.slots.all(func(s): return s == null), "creative starts empty-handed")
	check(not game.hud._hearts.visible and not game.hud._stars.visible, "no life or mana shown")

	# No damage: hits, long falls.
	p.hurt(80, p.global_position + Vector3(1, 0, 0))
	check(p.life == p.life_max, "hits do no damage")
	p.global_position += Vector3(0, 30, 0)
	p.velocity = Vector3.ZERO
	for i in 200:
		await frames(1)
		if i > 5 and p.on_floor:
			break
	check(p.on_floor and p.life == p.life_max, "a 30 block fall does no damage")

	# Double-tap jump to fly; touching the ground ends it.
	await tap_jump()
	await tap_jump()
	check(p.flying, "double-tapping jump starts flying")
	var y0 := p.global_position.y
	Input.action_press("jump")
	await frames(30)
	Input.action_release("jump")
	await frames(5)
	check(p.flying and p.global_position.y > y0 + 2.0, "holding jump flies up (%.1f -> %.1f)" % [y0, p.global_position.y])
	await tap_jump()
	await tap_jump()
	check(not p.flying, "double-tapping again stops flying")
	await tap_jump()
	await tap_jump()
	p.velocity = Vector3(0, -12, 0)
	for i in 240:
		await frames(1)
		if not p.flying:
			break
		p.velocity.y = -12.0  # descending
	check(not p.flying and p.on_floor, "landing ends flight")

	# Instant breaking without drops, even unbreakable blocks.
	p.look_at_yaw_pitch(0.0, -1.5)
	await frames(3)
	var below: Vector3i = p.target.block
	var id_before: int = w.get_block(below)
	p._use_timer = 0.0
	p.use_item()
	await frames(5)
	check(id_before != 0 and w.get_block(below) == 0, "one hit breaks the block (%s)" % Data.block(id_before).get("name", "?"))
	check(drops_near(Vector3(below)) == 0, "nothing drops")
	w.set_block(below, Data.block_id("demon_altar"))
	await frames(3)
	p._use_timer = 0.0
	p.use_item()
	await frames(3)
	check(w.get_block(below) == 0, "even a demon altar breaks")

	# Nothing used up: blocks, ammo, buckets. (Placed a few blocks away: the
	# player dropped into the hole they just dug.)
	var ground := Vector3i(floori(p.global_position.x) + 3, 0, floori(p.global_position.z))
	ground.y = w.surface_y(ground.x, ground.z)
	var spot := ground + Vector3i.UP
	p.inventory.slots[0] = Inventory.stack("DirtBlock", 5)
	p.select(0)
	# (The Guide wanders about the spawn point: keep him out of the way.)
	for n in game.npcs():
		n.global_position += Vector3(40, 0, 40)
	p.target = {"block": ground, "normal": Vector3i.UP, "id": w.get_block(ground), "distance": 3.0}
	check(p._place(Data.item("DirtBlock")) and w.get_block(spot) == Data.block_id("dirt") and p.inventory.count_of("DirtBlock") == 5,
			"placing doesn't use up blocks")
	p.inventory.slots[1] = Inventory.stack("WoodenBow", 1)
	p.inventory.slots[2] = Inventory.stack("WoodenArrow", 3)
	p.select(1)
	p.look_at_yaw_pitch(0.0, 0.0)
	await frames(2)
	p._use_timer = 0.0
	p.use_item()
	check(p.inventory.count_of("WoodenArrow") == 3, "shooting doesn't use up arrows")
	p.inventory.slots[3] = Inventory.stack("WaterBucket", 1)
	p.select(3)
	p.look_at_yaw_pitch(0.0, -1.5)
	await frames(3)
	p._use_timer = 0.0
	p.use_item()
	await frames(2)
	check(p.inventory.slots[3] != null and p.inventory.slots[3].item == "WaterBucket", "a water bucket never runs dry")

	# Pick block: middle-click puts the targeted block in the hotbar.
	p.inventory.slots[3] = null
	p.select(3)
	w.set_block(spot, Data.block_id("stone"))
	p.target = {"block": spot, "normal": Vector3i.UP, "id": w.get_block(spot), "distance": 3.0}
	check(p.pick_block() and p.selected == 3 and p.held().get("place", "") == "stone" and p.inventory.slots[3].count == p.inventory.max_stack("StoneBlock"),
			"pick block gives a full stack of the targeted block (%s)" % p.held().get("name", "?"))
	p.select(5)
	p.target = {"block": spot, "normal": Vector3i.UP, "id": w.get_block(spot), "distance": 3.0}
	check(p.pick_block() and p.selected == 3, "picking it again selects the hotbar slot that has it")

	# The creative inventory: every item, by tab and search; clicks take stacks.
	var hud := game.hud
	hud.toggle_inventory()
	await frames(2)
	check(hud._creative_panel.visible and not hud._crafting_scroll.visible, "the inventory shows the creative palette, not crafting")
	check(hud.palette.slots.size() == Data.items.size(), "the palette has every item (%d of %d)" % [hud.palette.slots.size(), Data.items.size()])
	hud._creative_search.text = "pickaxe"
	hud._fill_palette()
	var names: Array = hud.palette.slots.map(func(s): return s.item)
	check(names.size() >= 4 and names.all(func(n): return n.ends_with("Pickaxe")), "search finds the pickaxes (%s)" % [names])
	hud._creative_search.text = ""
	hud._creative_tab = "Blocks"
	hud._fill_palette()
	check(hud.palette.slots.all(func(s): return Data.item(s.item).type == "block"), "the Blocks tab shows only blocks")
	await frames(2)
	var slot0 = hud._creative_grid.get_child(0)
	hud.slot_clicked(slot0, MOUSE_BUTTON_LEFT)
	var first: String = hud.palette.slots[0].item
	check(hud._cursor_stack != null and hud._cursor_stack.item == first and hud._cursor_stack.count == p.inventory.max_stack(first), "clicking takes a full stack")
	hud.slot_clicked(slot0, MOUSE_BUTTON_LEFT)
	check(hud._cursor_stack == null, "clicking the palette with a stack deletes it")
	hud.close_inventory()
	await frames(2)

	# Switching to survival and back (pause menu's game mode button).
	p.flying = true
	game.set_creative(false)
	check(not p.creative and not p.flying and hud._hearts.visible, "survival: life shown, no flight")
	p.inventory.slots[0] = Inventory.stack("DirtBlock", 5)
	p.select(0)
	w.set_block(spot, 0)
	p.target = {"block": ground, "normal": Vector3i.UP, "id": w.get_block(ground), "distance": 3.0}
	check(p._place(Data.item("DirtBlock")) and p.inventory.count_of("DirtBlock") == 4, "survival uses blocks up again")
	p.hurt(10, p.global_position + Vector3(1, 0, 0))
	check(p.life < p.life_max, "survival takes damage again")
	game.set_creative(true)
	check(p.creative and not hud._hearts.visible, "back to creative")

	# Palm trees on the beach (PalmArt): Terraria's curve, drawn along it, felled for Palm Wood.
	var palm_id := Data.block_id("palm_trunk")
	var palm_tops := w.get_decorations().filter(func(d): return d.kind == "tree_top" and int(d.style) / 10 == PalmArt.CANOPY_SHEET)
	check(palm_tops.size() > 5, "palms grow on the beach (%d)" % palm_tops.size())
	var leaning := {}
	for d in palm_tops:
		var s := PalmArt.at(w, Vector3i(d.pos) + Vector3i.DOWN)
		if s.is_empty() or s.offsets[-1] < 6:
			continue
		leaning = s
		leaning["top"] = Vector3i(d.pos)
		break
	check(not leaning.is_empty(), "some lean well")
	var sh := PalmArt.shape(Vector3i(7, 40, 9), 15)
	var steps_ok := true
	for k in range(1, sh.height):
		var d: int = sh.offsets[k] - sh.offsets[k - 1]
		steps_ok = steps_ok and d in [0, 2] and (d == 0 or float(k) / sh.height >= 0.25)
	check(sh.frames[0] == PalmArt.BASE and sh.frames[-1] in PalmArt.TOPS and sh.frames.slice(1, -1).all(func(f): return f in [0, 1, 2])
			and steps_ok and sh.offsets[-1] <= 16 and PalmArt.shape(Vector3i(7, 40, 9), 15).offsets == sh.offsets,
			"Terraria's palm: roots at the base, a top frame, 2 px steps from a quarter up, at most 16 px (%s)" % [sh.offsets])
	if not leaning.is_empty():
		var base: Vector3i = leaning.base
		var top_cell: Vector3i = base + Vector3i.UP * (leaning.height - 1)
		p.global_position = Vector3(base) + Vector3(3.5, 2, 0.5)
		await frames(30)
		var m: Dictionary = game.block_models._models.get(Chests.key(top_cell), {})
		var expect: Vector3 = BlockModels.billboard_instance(palm_id, top_cell).origin + PalmArt.segment_offset(leaning, leaning.height - 1)
		check(not m.is_empty() and m.transform.origin.is_equal_approx(expect) and (m.transform.origin - Vector3(top_cell)).length() > 0.4,
				"its top segment is drawn out along the lean (%s)" % [m.get("transform", Transform3D()).origin - Vector3(top_cell)])
		var bm: Dictionary = game.block_models._models.get(Chests.key(base), {})
		var tb: Basis = m.get("transform", Transform3D()).basis
		var bb: Basis = bm.get("transform", Transform3D()).basis
		check(not bm.is_empty() and is_equal_approx(bb.z.length() - bb.y.length(), (leaning.height - 1) * PalmArt.NUDGE) and is_equal_approx(tb.z.length(), tb.y.length()),
				"each segment is drawn a little nearer than the one above (no z-fighting where they overlap)")
		var top_style := int(palm_tops.filter(func(d): return Vector3i(d.pos) == leaning.top)[0].style)
		var want: Vector3 = Vector3(leaning.top) + Vector3(0.5, -1.0, 0.5) + PalmArt.top_offset(leaning)
		var on_curve: bool = game.decorations.canopy_position(leaning.top, top_style).is_equal_approx(want) and game.decorations._instances.has(top_style) \
				and game.decorations.canopy_position(leaning.top, 0).is_equal_approx(Vector3(leaning.top) + Vector3(0.5, -0.6, 0.5))
		check(on_curve, "its canopy sits on the end of the curve")
		game.break_block(base, true)
		await frames(3)
		var wood := 0
		for e in game.entities.get_children():
			if e is ItemDrop and e.item == "PalmWood":
				wood += e.count
		check(w.get_block(top_cell) == 0 and w.get_decorations().all(func(d): return Vector3i(d.pos) != leaning.top) and wood >= leaning.height + 2,
				"felled: the whole palm comes down as Palm Wood (%d), canopy and all" % wood)
	check(Data.recipes.any(func(r): return r.result == "PalmWoodPlatform" and r.ingredients.has("PalmWood"))
			and Data.recipes.any(func(r): return r.result == "Torch" and r.ingredients.keys().any(func(k): return "PalmWood" in k)),
			"Palm Wood crafts like Terraria's (its platform; any-wood recipes like the Torch)")

	# Tree branches (TreeBranches): Terraria's rolls, cards on the trunks, gone with the tree.
	var rules_ok := true
	var leafy := 0
	var total := 0
	for i in 300:
		var h := 6 + i % 10
		var bl := TreeBranches.branches(Vector3i(i, 50, i * 3), h)
		var sides := {}
		for b in bl:
			rules_ok = rules_ok and b.cell > 0 and b.cell < h - 1 and b.variant in [0, 1, 2] and absf(b.dir.length() - 1.0) < 0.001 and is_zero_approx(b.dir.y)
			sides[Vector2i(b.cell, int(b.left))] = true
			leafy += int(b.leafy)
			total += 1
		for k in sides:
			rules_ok = rules_ok and not sides.has(Vector2i(k.x + 1, k.y))  # never the same side twice in a row
	check(rules_ok and total > 300 and absf(float(leafy) / total - 2.0 / 3.0) < 0.06,
			"Terraria's branches: not on the bottom or top cell, never the same side twice running, leafy 2 in 3 (%d of %d)" % [leafy, total])
	var stems_ok := true
	for b in [{"variant": 1, "leafy": true, "left": true}, {"variant": 2, "leafy": true, "left": false}, {"variant": 0, "leafy": false, "left": true}, {"variant": 0, "leafy": false, "left": false}]:
		var img := TreeBranches.art("Tree_Branches_0", "Tiles_5", b)
		var at_trunk := false
		for y in img.get_height():
			at_trunk = at_trunk or img.get_pixel(0, y).a > 0.5
		stems_ok = stems_ok and at_trunk
	check(stems_ok and TreeBranches.sheet_for(52) == "Tree_Branches_6" and TreeBranches.sheet_for(0) == "Tree_Branches_0",
			"each branch's stem is at the trunk end of its art; branches match their tree top's sheet")
	# Trunk frames: from either edge, the first pixel of every row is outline
	# (bumps in and out, but no branch-joint openings).
	var trunk_def := Data.block(Data.block_id("tree_trunk"))
	var outlines_ok := true
	for spr in trunk_def.raw_sprites:
		for y in spr.get_height():
			for from_right in [false, true]:
				for i in spr.get_width():
					var c: Color = spr.get_pixel(spr.get_width() - 1 - i if from_right else i, y)
					if c.a > 0.5:
						outlines_ok = outlines_ok and c.v < 0.35
						break
	check(outlines_ok, "trunk frames have their outline down both sides (no gaps)")
	# In the world: a tree with branches near the player has branch cards drawn.
	var tree := []
	var tree_branches := []
	for d in w.get_decorations():
		if d.kind != "tree_top" or int(d.style) / 10 == PalmArt.CANOPY_SHEET:
			continue
		var col := TreeBranches.column(w, Vector3i(d.pos) + Vector3i.DOWN)
		if col[1] > 0 and TreeBranches.branches(col[0], col[1]).size() >= 2:
			tree = col
			tree_branches = TreeBranches.branches(col[0], col[1])
			break
	check(not tree.is_empty(), "there are trees with branches")
	if not tree.is_empty():
		var tbase: Vector3i = tree[0]
		p.global_position = Vector3(tbase) + Vector3(4.5, 1, 0.5)
		await frames(40)
		var cards := func() -> int:
			var n := 0
			for node in game.block_models.get_children():
				var nearer = node.material_override.get_shader_parameter("toward_camera") if node is MultiMeshInstance3D and node.material_override is ShaderMaterial else null
				if nearer != null and nearer > 0.0:
					for i in node.multimesh.instance_count:
						n += 1
			return n
		var before_cards: int = cards.call()
		check(before_cards >= tree_branches.size(), "branch cards are drawn (%d)" % before_cards)
		var tb := TreeBranches.transform(tbase, tree_branches[0])
		check(is_equal_approx((tb.origin - (Vector3(tbase) + Vector3(0.5, tree_branches[0].cell + 0.5, 0.5))).length(), TreeBranches.STEM_START) and tb.basis.x.is_equal_approx(tree_branches[0].dir),
				"a branch starts just inside the trunk's edge, reaching out its way")
		game.break_block(tbase + Vector3i.UP, true)
		await frames(20)
		check(cards.call() <= before_cards - tree_branches.filter(func(b): return b.cell >= 1).size(), "felled: its branches go with it (%d -> %d)" % [before_cards, cards.call()])

	check(Data.block_textures.get_layers() <= Data.MAX_LAYERS, "block textures fit a GPU's texture array (%d of %d layers)" % [Data.block_textures.get_layers(), Data.MAX_LAYERS])

	# Gem trees in the caves: their gems, drops, recipes and light.
	var gem_tops := w.get_decorations().filter(func(d): return d.kind == "tree_top" and int(d.style) / 10 >= 16 and int(d.style) / 10 <= 22)
	check(gem_tops.size() > 5 and gem_tops.all(func(d): return int(d.pos.y) < int(w.get_layers().surface)), "gem trees grow underground (%d)" % gem_tops.size())
	var ruby := Data.block(Data.block_id("ruby_tree_trunk"))
	var gems_dropped := 0
	var check_drop_ok := true
	for i in 2000:
		var dr := game.block_drop(ruby)
		check_drop_ok = check_drop_ok and dr in ["Ruby", "StoneBlock"]
		gems_dropped += int(dr == "Ruby")
	check(check_drop_ok and absf(gems_dropped / 2000.0 - 0.1) < 0.025, "a gem tree's trunk drops its gem 1 in 10, else stone (%d / 2000)" % gems_dropped)
	check(["Amethyst", "Topaz", "Sapphire", "Emerald", "Ruby", "Diamond", "Amber"].all(func(g): return not Data.item(g).is_empty())
			and Data.recipes.any(func(r): return r.result == "AmethystStaff" and r.ingredients.has("Amethyst")),
			"the seven gems exist, and their recipes (the Amethyst Staff) work")
	var gt: Dictionary = gem_tops[0]
	var gpos: Vector3 = game.decorations.canopy_position(Vector3i(gt.pos), int(gt.style)) + Decorations.LIGHT_AT
	var dark: Color = w.get_light(gpos)
	check(dark.a < 0.2 and dark.r < 0.3, "deep in a cave its canopy is in the dark (%s), not sunlit" % dark)

	# Vanity trees in the forest, ash trees in the Underworld (and its glow).
	var tops_of := func(sheet: int) -> Array: return w.get_decorations().filter(func(d): return d.kind == "tree_top" and int(d.style) / 10 == sheet)
	check(tops_of.call(25).size() > 5 and tops_of.call(25).all(func(d): return Data.block(w.get_block(Vector3i(d.pos) + Vector3i.DOWN)).name == "ash_trunk"),
			"ash trees grow in the Underworld (%d)" % tops_of.call(25).size())
	check(tops_of.call(23).size() + tops_of.call(24).size() > 0, "vanity trees (Sakura %d, Yellow Willow %d)" % [tops_of.call(23).size(), tops_of.call(24).size()])
	check(Data.block(Data.block_id("ash_trunk")).drop == "AshWood" and Data.block(Data.block_id("sakura_trunk")).drop == "Wood" and Data.block(Data.block_id("willow_trunk")).drop == "Wood"
			and Data.block(Data.block_id("ash_grass")).drop == "AshBlock" and Data.block(Data.block_id("ash_grass")).hit_to == "ash",
			"ash trees drop Ash Wood, vanity trees Wood; ash grass is ash underneath")
	check(Data.recipes.any(func(r): return r.result == "AshWoodPlatform" and r.ingredients.has("AshWood"))
			and Data.recipes.any(func(r): return r.result == "Torch" and r.ingredients.keys().any(func(k): return "AshWood" in k)),
			"Ash Wood crafts like Terraria's (its own recipes; any wood)")
	var glow: Vector3 = game.hell_light
	check(glow.x > 0.6 and glow.x > glow.y and glow.y > glow.z,
			"the Underworld glows orange below its top (%s)" % glow)

	# The Ivy Chest: Living Mahogany trees' chest, with Terraria's jungle loot.
	var primaries := {}
	for i in 3000:
		var loot := Game.roll_loot("ivy_chest")
		primaries[loot[0][0]] = primaries.get(loot[0][0], 0) + 1
	var main4: int = ["FeralClaws", "AnkletoftheWind", "StaffofRegrowth", "Boomstick"].reduce(func(acc, k): return acc + primaries.get(k, 0), 0)
	check(primaries.keys().all(func(k): return k in ["FeralClaws", "AnkletoftheWind", "StaffofRegrowth", "Boomstick", "FiberglassFishingPole", "FlowerBoots"])
			and absf(primaries.get("FiberglassFishingPole", 0) / 3000.0 - 1.0 / 15.0) < 0.02 and primaries.get("FlowerBoots", 0) > 60 and main4 > 2400
			and primaries.keys().all(func(k): return not Data.item(k).is_empty()),
			"Ivy Chest loot: Feral Claws, Anklet, Staff of Regrowth or Boomstick; 1 in 15 a Fiberglass Fishing Pole, then 1 in 20 Flower Boots (%s)" % [primaries])
	var ivy := Data.block(Data.block_id("ivy_chest"))
	check(ivy.get("interact") == "chest" and ivy.drop == "IvyChest" and Data.item("IvyChest").place == "ivy_chest", "the Ivy Chest is a chest you can pick up and place")
	var cs := Chests.new()
	w.add_decoration("chest", Vector3i(3, 70, 3), 2)
	cs.setup(w)
	check(cs._worldgen.get(Chests.key(Vector3i(3, 70, 3))) == "ivy_chest", "a worldgen chest of style 2 holds Ivy Chest loot")
	# The loot itself does what Terraria's does.
	p.accessories.slots[0] = Inventory.stack("FeralClaws", 1)
	check(p.stat("melee_speed") >= 12.0 and p.auto_reuses(Data.item("CopperBroadsword") if not Data.item("CopperBroadsword").is_empty() else {"type": "melee", "auto_reuse": false}),
			"Feral Claws: faster melee and autoswing")
	p.accessories.slots[0] = Inventory.stack("AnkletoftheWind", 1)
	check(p.stat("move_speed") >= 10.0, "Anklet of the Wind: 10% faster")
	p.accessories.slots[0] = null
	var before_proj := game.entities.get_children().filter(func(e): return e is Projectile).size()
	p.inventory.slots[0] = Inventory.stack("Boomstick", 1)
	p.inventory.slots[1] = Inventory.stack("MusketBall", 50)
	p.select(0)
	p._use_timer = 0.0
	p._use_released = true
	p.use_item()
	var pellets := game.entities.get_children().filter(func(e): return e is Projectile).size() - before_proj
	check(pellets >= 3 and pellets <= 4, "the Boomstick fires 3-4 pellets at once (%d)" % pellets)
	var dirt_at := Vector3i(p.global_position.floor()) + Vector3i(2, -1, 0)
	w.set_block(dirt_at, Data.block_id("dirt"))
	w.set_block(dirt_at + Vector3i.UP, 0)
	p.target = {"block": dirt_at, "normal": Vector3i.UP, "id": w.get_block(dirt_at), "distance": 2.0}
	p._regrow()
	check(w.get_block(dirt_at) == Data.block_id("grass"), "the Staff of Regrowth turns dirt to grass")

	# More placeables: furniture in every wood, bricks, Gemspark, torches, platforms, decor.
	var newer := ["BorealWoodTable", "PalmWoodChair", "RichMahoganyBed", "EbonwoodPiano", "ShadewoodBookcase", "AshWoodChandelier", "CactusDresser",
			"RedBrick", "SapphireGemsparkBlock", "BlueTorch", "StonePlatform", "Campfire", "Keg", "Sofa", "WoodenSink"]
	var all_ok := true
	for n in newer:
		var it := Data.item(n)
		var b := Data.block(Data.block_id(String(it.get("place", ""))))
		var made := Data.recipes.any(func(r): return r.result == n)
		if it.is_empty() or b.is_empty() or not made:
			all_ok = false
			print("  missing: ", n, " item ", not it.is_empty(), " block ", not b.is_empty(), " recipe ", made)
	check(all_ok, "new placeables have blocks and Terraria's recipes")
	check(Data.block(Data.block_id("boreal_wood_work_bench")).get("station_as") == "work_bench"
			and Data.block(Data.block_id("blue_torch")).emit[2] > 0.8 and Data.block(Data.block_id("blue_wall_torch")).get("wall", false)
			and Data.block(Data.block_id("ruby_gemspark_block")).emit[0] > 0.8,
			"wood work benches count as work benches; coloured torches (and their wall twins) and Gemspark light up in their colours")

	# Every sink and bathtub has a hand-made ("claude") model of its own.
	var made_ok := true
	var count := 0
	for b in Data.blocks:
		var n: String = b.get("name", "")
		if not (n.ends_with("_sink") or n.ends_with("_bathtub")):
			continue
		count += 1
		var spec: Dictionary = Data.handmade_models.get(n, {})
		var vox := BlockModelMesh.handmade_voxels(b.art, spec) if not spec.is_empty() else {}
		var deep := 0
		for v in vox:
			deep = maxi(deep, v.z)
		if spec.is_empty() or b.get("default_method") != "claude" or vox.size() < 200:
			made_ok = false
			print("  no hand-made model: ", n, " voxels ", vox.size())
	check(made_ok and count == 20, "all %d sinks and bathtubs have hand-made models" % count)

	# Saved with the world.
	check(game.save_world(), "saved")
	game.queue_free()
	await frames(5)
	await start({"mode": "load", "name": "CreativeCheck", "path": PATH})
	check(game.creative and game.player.creative, "creative mode is saved with the world")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT: %d failures" % failures.size())
	for f in failures:
		print("  - " + f)
	get_tree().quit(1 if failures.size() > 0 else 0)
