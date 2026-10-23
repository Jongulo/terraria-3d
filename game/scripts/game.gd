class_name Game
extends Node3D
## One play session: owns the voxel world, rendering, sky, player, entities and
## HUD; handles loading, saving and the world rules shared by everything else.

signal exit_to_menu

enum State { LOADING, STREAMING, PLAYING }

## World sizes (blocks): Terraria's Small / Medium / Large keep their 1 : 1.5 : 2
## proportions here, scaled to what fits in memory in 3D (Large is ~9 GB).
const WORLD_SIZES := {
	"small": Vector3i(768, 384, 768),
	"medium": Vector3i(1152, 576, 1152),
	"large": Vector3i(1536, 768, 1536),
}
const SAVE_DIR := "user://worlds/"
## Screenshots (take_screenshot) go here, named by the date and time.
const SCREENSHOT_DIR := "user://screenshots/"
## True while a screenshot waits for its frame (the block outline stays hidden).
var taking_screenshot := false
const AUTOSAVE_INTERVAL := 300.0

static var current: Game

var world := VoxelWorld.new()
var renderer := ChunkRenderer.new()
## Far terrain past the full-detail chunks.
var lod := LodRenderer.new()
var far_trees := FarTrees.new()
var decorations := Decorations.new()
var waterfalls := Waterfalls.new()
var block_models := BlockModels.new()
var starfall := Starfall.new()
var torch_flames := TorchFlames.new()
var falling_leaves := FallingLeaves.new()
## Terraria's dust: what blocks throw off when hit or broken.
var dust := DustParticles.new()
## "x,y,z" -> quarter turns, for directional block models (set when placed).
var block_rotations := {}
## Where the Dungeon's entrance is (its hall floor), or NO_DUNGEON.
var dungeon_entrance := NO_DUNGEON
const NO_DUNGEON := Vector3i(-1, -1, -1)
## What worldgen signs say (by their decoration's style).
const WORLDGEN_SIGNS := ["The dungeon's depths are sealed. (The rest of the Dungeon isn't in this version yet.)"]
## What's written on each sign: "x,y,z" -> text.
var signs := {}
## The biome the player is in ("", "ocean", "snow", "desert", "jungle",
## "corruption", "crimson", "dungeon", "mushroom"): the coast, or the biome blocks around them; orbs/hearts smashed toward the next boss.
var biome := ""
var orbs_broken := 0
var _biome_timer := 0.0
const BIOME_RADIUS := 24
const BIOME_THRESHOLD := 400
const EVIL_SKY := {"corruption": Color(0.34, 0.26, 0.5), "crimson": Color(0.5, 0.15, 0.13)}
var sky := SkySystem.new()
## The sun's and moon's real-time shadows (optional: Settings → Shaders).
var sun_shadows := SunShadows.new()
var global_illumination := GlobalIllumination.new()
var player := Player.new()
var hud: Hud
var entities := Node3D.new()
var spawner := Spawner.new()
var chests := Chests.new()
## Terraria's wiring: wire, actuators, triggers and what they set off.
var wiring := Wiring.new()
var wire_view := WireView.new()
var laser_ruler := LaserRuler.new()
var senses := Senses.new()
var herbs := Herbs.new()
## A Staff of Regrowth swing (Player.staffOfRegrowthBonus): herbs cut give more.
var regrowth := false
## The town NPCs and their homes.
var town := Town.new()
## The Goblin Army (Invasion): on its way, here, beaten.
var invasion := Invasion.new(self)
## Set in test worlds (see scripts/world/test_world.gd).
var test_world: TestWorld
var _mode := "new"

var state := State.LOADING
var world_name := "World"
var surface_level := 170
var space_height := 42
var cavern_level := 100
var underworld_level := 30
## The ocean round the world's edge (worlds made before it existed have none):
## sea surface, how far the sea and beach reach inland, the sea's depth.
var has_ocean := false
## Minecraft-style creative mode (per world): invulnerable, double-tap jump to
## fly, instant breaking without drops, nothing used up, every item on hand.
var creative := false
var sea_level := 0
var ocean_width := 0.0
var beach_width := 0.0
var ocean_depth := 0.0
var defeated_bosses := {}
## Kills by banner kind (Terraria's NPC.killCount).
var kill_counts := {}
## A boss made of many NPCs (the Eater of Worlds' segments, boss_group in
## npcs.json): its life when it appeared, for the boss bar.
var boss_life_max := {}

var _save_path := ""
var _pending_meta := {}
var _stream_wait := 0.0
var _autosave := AUTOSAVE_INTERVAL
var _evil_presence := -1.0
var _liquid_acc := 0.0
## Liquid simulation rate (ticks per second) and per-tick work cap.
const LIQUID_TPS := 20.0
const LIQUID_CELLS_PER_TICK := 30000


## params: {mode: "new"|"load", name, seed, path}
func start(params: Dictionary) -> void:
	current = self
	Settings.changed.connect(_on_setting_changed)
	world_name = params.get("name", "World")
	_save_path = params.get("path", SAVE_DIR + world_name.validate_filename() + ".twld")
	add_child(sky)
	sun_shadows.sky = sky
	add_child(sun_shadows)
	global_illumination.sky = sky
	global_illumination.sun_shadows = sun_shadows
	add_child(global_illumination)
	add_child(renderer)
	town.game = self
	add_child(town)
	add_child(decorations)
	add_child(waterfalls)
	add_child(block_models)
	add_child(entities)
	add_child(starfall)
	add_child(torch_flames)
	add_child(falling_leaves)
	add_child(dust)
	hud = Hud.new()
	add_child(hud)
	Data.register_blocks(world)
	_mode = params.mode
	creative = params.get("creative", false)
	if params.mode == "load":
		world.start_load(ProjectSettings.globalize_path(_save_path))
	elif params.mode == "test":
		world.start_generate_flat(int(params.get("seed", 1)), TestWorld.SIZE, TestWorld.GROUND)
		_make_test_world()
		test_world.kind = params.get("test_kind", "all")
	else:
		world.set_world_evil(int(params.get("evil", 0)))
		# A size name ("small"...), or exact dimensions (tests).
		var size = params.get("size", "small")
		world.start_generate(int(params.get("seed", randi())), size if size is Vector3i else WORLD_SIZES.get(size, WORLD_SIZES.small))
		has_ocean = true
	hud.show_loading("Loading world..." if params.mode == "load" else "Generating world...")
	Audio.set_music("TitleClassic")


func _process(delta: float) -> void:
	match state:
		State.LOADING:
			hud.set_loading_progress(world.get_progress())
			if not world.is_busy():
				_on_world_ready()
		State.STREAMING:
			_stream_wait += delta
			renderer.focus = player.global_position
			hud.set_loading_progress(1.0)
			if (renderer._pending.is_empty() and renderer.loaded_count() > 50) or _stream_wait > 8.0:
				_begin_play()
		State.PLAYING:
			_update_playing(delta)
			wiring.update(self, delta)


## Terraria's Underworld glow (TileLightScanner.ApplyHellLight): open tiles
## below its top are lit (k, 0.6k, 0.2k), k = 0.55 pulsing by 0.08 (sin of
## twice the time). The shaders square light levels, so they get the root.
func _update_hell_light() -> void:
	var k := 0.55 + sin(Time.get_ticks_msec() / 1000.0 * 2.0) * 0.08
	hell_light = Vector3(sqrt(k), sqrt(k * 0.6), sqrt(k * 0.2))
	RenderingServer.global_shader_parameter_set("underworld_top", float(world.get_layers().underworld_top))
	RenderingServer.global_shader_parameter_set("hell_light", hell_light)


## The Underworld glow given to the shaders this frame.
var hell_light := Vector3.ZERO


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("hell_light", Vector3.ZERO)


func _on_world_ready() -> void:
	var msg := world.get_message()
	if msg.begins_with("error:"):
		hud.show_error("Could not load world: " + msg.trim_prefix("error: "))
		await get_tree().create_timer(3.0).timeout
		exit_to_menu.emit()
		return
	var layers := world.get_layers()
	surface_level = int(layers.surface)
	space_height = int(layers.space) - surface_level
	cavern_level = int(layers.cavern_top)
	underworld_level = int(layers.underworld_top)
	sea_level = int(layers.sea_level)
	ocean_width = float(layers.ocean_width)
	beach_width = float(layers.beach_width)
	ocean_depth = float(layers.ocean_depth)
	var meta := {}
	if msg != "":
		meta = JSON.parse_string(msg)
		if meta.get("test_world") is Dictionary:
			_make_test_world()
			test_world.load_state(meta.test_world)
		has_ocean = meta.get("ocean", false)
		# A world saved before plants had styles (blocks.json "variant_of"):
		# its plants take theirs now, as a new world's do (not the test
		# world's, whose plants are each placed as themselves).
		if not meta.get("styles", false) and test_world == null:
			world.scatter_styles(world.get_seed())
	if test_world:
		surface_level = TestWorld.GROUND
		cavern_level = 20
		underworld_level = 10
		has_ocean = false
		if _mode == "test":
			test_world.build()
	renderer.render_distance = int(Settings.get_value("render_distance"))
	renderer.setup(world)
	add_child(lod)
	lod.far_distance = int(Settings.get_value("far_distance"))
	lod.setup(world, renderer)
	# Far terrain leaves out dark faces in caves, not under floating islands.
	world.set_lod_cave_level(surface_level - 8)
	add_child(far_trees)
	far_trees.setup(world, self)
	if has_ocean:
		_add_open_sea()
	decorations.setup(world)
	waterfalls.setup(world)
	block_models.setup(world, self)
	starfall.setup(self)
	torch_flames.setup(world, self)
	falling_leaves.setup(world, self)
	renderer.chunk_updated.connect(block_models.chunk_updated)
	renderer.chunk_updated.connect(decorations.relight)
	renderer.chunk_unloaded.connect(block_models.chunk_unloaded)
	renderer.chunk_updated.connect(torch_flames.chunk_updated)
	renderer.chunk_unloaded.connect(torch_flames.chunk_unloaded)
	chests.setup(world)
	wiring.setup(self)
	wire_view.setup(self)
	add_child(wire_view)
	laser_ruler.setup(self)
	add_child(laser_ruler)
	senses.setup(self)
	add_child(senses)
	herbs.setup(self)
	add_child(herbs)

	add_child(player)
	sky.camera = player.camera
	var spawn := Vector3(world.get_spawn()) + Vector3(0.5, 0, 0.5)
	player.spawn_point = spawn
	player.global_position = spawn
	if not meta.is_empty():
		_pending_meta = meta
		_apply_meta(_pending_meta)
	elif test_world:
		test_world.give_loadout(player)
	elif not creative:  # creative starts empty-handed, like Minecraft's
		_give_starting_items()
	player.creative = creative
	# Worldgen leaves which way some blocks face (island house chests and
	# banners) as "rotation" decorations; the player's own choices win.
	for d in world.get_decorations():
		if d.kind == "rotation" and not block_rotations.has(Chests.key(d.pos)):
			block_rotations[Chests.key(d.pos)] = int(d.style)
		elif d.kind == "sign" and not signs.has(Chests.key(d.pos)):
			signs[Chests.key(d.pos)] = WORLDGEN_SIGNS[int(d.style) % WORLDGEN_SIGNS.size()]
		elif d.kind == "dungeon":
			dungeon_entrance = Vector3i(d.pos)
	player.input_enabled = false
	hud.bind(player)
	player.died.connect(func(): hud.show_death())
	player.respawned.connect(func(): hud.hide_death())
	sky.dusk.connect(_on_dusk)
	sky.dawn.connect(_on_dawn)
	state = State.STREAMING


func _make_test_world() -> void:
	test_world = TestWorld.new()
	test_world.game = self
	add_child(test_world)


func _begin_play() -> void:
	state = State.PLAYING
	hud.hide_loading()
	add_child(spawner)
	# Town NPCs that worldgen placed (the Old Man at the Dungeon's door,
	# until Skeletron is beaten).
	_spawn_old_man()
	# No mountains rising out of the sea on the horizon.
	if has_ocean:
		sky.sea_query = func(at: Vector2, n: int, reach: float) -> PackedFloat32Array:
			return world.sea_distances(at, n, reach, ocean_width)
	# The town: as saved, else (a new world, or one from before towns) the Guide.
	invasion.load_state(_pending_meta.get("invasion", {}))
	if _pending_meta.has("town"):
		town.load_state(_pending_meta.town)
	elif test_world == null:
		town.start_new()
	if test_world:
		test_world.activate()
	# The Angler's fish for today (a new world has one from the start).
	if town.angler_quest == "":
		town.new_angler_quest()
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	message("Welcome to %s!" % world_name, Color(0.6, 0.9, 1.0))


func _give_starting_items() -> void:
	for item in ["CopperShortsword", "CopperPickaxe", "CopperAxe"]:
		player.inventory.add(item, 1)


func _update_playing(delta: float) -> void:
	var pos := player.global_position
	renderer.focus = pos
	_update_hell_light()
	sky.strongest_life = player.life_max
	# Fade the sky and backdrop out underground.
	sky.depth_factor = clampf((surface_level - 18.0 - pos.y) / 12.0, 0.0, 1.0)
	_biome_timer -= delta
	if _biome_timer <= 0.0:
		_biome_timer = 0.5
		biome = detect_biome(pos)
	sky.evil_amount = move_toward(sky.evil_amount, 1.0 if EVIL_SKY.has(biome) else 0.0, delta * 0.5)
	if EVIL_SKY.has(biome):
		sky.evil_color = EVIL_SKY[biome]
	sky.biome = biome
	# Space: the sky darkens and the stars come out over its first 30 blocks.
	sky.space_factor = clampf((pos.y - (surface_level + space_height)) / 30.0, 0.0, 1.0)
	renderer.set_sky(sky.sky_light, sky.sky_tint)
	lod.set_sky(sky.sky_light, sky.sky_tint)
	far_trees.set_sky(sky.sky_light, sky.sky_tint)
	# Canopies: full detail near you, sprites to the edge of what's drawn.
	decorations.set_focus(pos, (lod.far_distance if lod.enabled() else renderer.render_distance + 1) * 32.0)
	decorations.set_sky(sky.sky_light, sky.sky_tint)
	waterfalls.set_sky(sky.sky_light, sky.sky_tint)
	waterfalls.focus = pos
	block_models.set_sky(sky.sky_light, sky.sky_tint)
	# The fog ends past whatever's drawn: the far terrain, or the chunks. With
	# far terrain it starts at the full-detail edge, so the coarse ground fades
	# into the haze.
	if lod.enabled():
		sky.env.fog_depth_end = lod.far_distance * 32.0 - 8.0
		sky.env.fog_depth_begin = minf(renderer.render_distance * 32.0 * 0.6, sky.env.fog_depth_end * 0.55)
	else:
		sky.env.fog_depth_end = renderer.render_distance * 32.0 - 8.0
		sky.env.fog_depth_begin = sky.env.fog_depth_end * 0.55
	# The camera reaches the sky's backdrops, clouds and sun beyond it.
	player.camera.far = maxf(1000.0, sky.body_distance() + 100.0)
	invasion.update(delta)
	_update_music(pos)
	# The time only with a watch on you (Terraria's informational accessories).
	var watch := int(player.info_accessories().get("watch", 0))
	hud.set_clock(sky.clock_text(watch) if watch > 0 else "")
	_liquid_acc = minf(_liquid_acc + delta, 0.25)
	while _liquid_acc >= 1.0 / LIQUID_TPS:
		_liquid_acc -= 1.0 / LIQUID_TPS
		world.step_liquids(LIQUID_CELLS_PER_TICK)

	if _evil_presence > 0.0:
		_evil_presence -= delta
		if _evil_presence <= 0.0 and not sky.is_day:
			summon_boss("EyeofCthulhu")
	_autosave -= delta
	if _autosave <= 0.0:
		_autosave = AUTOSAVE_INTERVAL
		save_world()


## The biome at `pos`: the ocean on the coast (the sea and its beach, from
## the sea floor up to the sky), else the evil biome like Terraria's tile
## counts: enough Corruption or Crimson blocks nearby (the stronger wins).
func detect_biome(pos: Vector3) -> String:
	if in_ocean(pos):
		return "ocean"
	var counts := world.count_blocks(Vector3i(pos.floor()), BIOME_RADIUS)
	var best := ""
	var best_n := BIOME_THRESHOLD - 1
	for b in Data.biome_blocks:
		var n := 0
		for id in Data.biome_blocks[b]:
			if id < counts.size():
				n += counts[id]
		if n > best_n:
			best = b
			best_n = n
	# The Dungeon counts only inside it (under its roof), like Terraria's
	# dungeon walls; outside the keep you're still in the forest.
	if best == "dungeon" and world.surface_y(floori(pos.x), floori(pos.z)) <= int(pos.y):
		return ""
	return best


## The sea beyond the world's edge: a water surface at sea level reaching to
## the horizon, so the island sits in an endless ocean.
func _add_open_sea() -> void:
	var size := world.get_size()
	var y := sea_level + 0.94  # a full top cell's surface (see the mesher)
	var far := 4000.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Four slabs round the world: west, east (full depth), north, south.
	var rects := [
		Rect2(-far, -far, far, size.z + 2.0 * far), Rect2(size.x, -far, far, size.z + 2.0 * far),
		Rect2(0, -far, size.x, far), Rect2(0, size.z, size.x, far),
	]
	# Dark deep water just under it: the open sea isn't see-through, so the
	# mountain backdrop's foot (below the horizon) stays hidden behind it.
	var floor_st := SurfaceTool.new()
	floor_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rects:
		var c := [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_color(Color(0, 0, 0, 1))  # sunlight only
			st.set_uv(c[i])
			st.set_uv2(Vector2.ZERO)  # a liquid top
			st.add_vertex(Vector3(c[i].x, y, c[i].y))
			floor_st.add_vertex(Vector3(c[i].x, sea_level - 1.0, c[i].y))
	var sea := MeshInstance3D.new()
	sea.name = "OpenSea"
	sea.mesh = st.commit()
	sea.material_override = renderer.water_material
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	# ...and down the world's edges to below the sea floor, where sight lines
	# from inside the world pass under it.
	var lo := sea_level - ocean_depth - 12.0
	var hi := sea_level - 1.0
	var corners := [Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.z), Vector2(0, size.z)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		for v in [Vector3(a.x, hi, a.y), Vector3(b.x, hi, b.y), Vector3(b.x, lo, b.y), Vector3(a.x, hi, a.y), Vector3(b.x, lo, b.y), Vector3(a.x, lo, a.y)]:
			floor_st.add_vertex(v)
	var deep := MeshInstance3D.new()
	deep.mesh = floor_st.commit()
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.04, 0.1, 0.24)
	deep.material_override = m
	deep.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(deep)


## Terraria's music for a biome, on the surface or underground.
func biome_music(b: String, under: bool) -> String:
	match b:
		"snow":
			return "Ice" if under else "Snow"
		"desert":
			return "UndergroundDesert" if under else "Desert"
		"jungle":
			return "UndergroundJungle" if under else ("JungleDay" if sky.is_day else "JungleNight")
		"crimson":
			return ("Underground" if under else "") + "Crimson"
		"dungeon":
			return "Dungeon"
		"mushroom":
			return "Mushroom"
	return ("Underground" if under else "") + "Corruption"


func in_ocean(pos: Vector3) -> bool:
	if test_world != null:
		return test_world.in_ocean(pos)
	if not has_ocean or pos.y < sea_level - ocean_depth - 8.0 or pos.y > space_level():
		return false
	return world.coast_inland(floori(pos.x), floori(pos.z)) < ocean_width + beach_width * 0.6


## Where the Magic Conch takes you from `pos` (Terraria's: the ocean furthest
## from you, on the sand by the water): here the sea is all round the island,
## so the beach across the world from you, through its middle. The first spot
## in from the sea, clear of water, with room to stand; null if none.
func far_beach(pos: Vector3):
	if not has_ocean:
		return null
	var size := world.get_size()
	var mid := Vector2(size.x, size.z) * 0.5
	var away := Vector2(pos.x, pos.z) - mid
	if away.length() < 1.0:
		var f := player.forward()
		away = -Vector2(f.x, f.z)
	var dir := -away.normalized()
	var t := mid.length()
	while t > 0.0:
		var p := mid + dir * t
		t -= 1.0
		var x := floori(p.x)
		var z := floori(p.y)
		if x < 0 or z < 0 or x >= size.x or z >= size.z or world.coast_inland(x, z) < ocean_width:
			continue
		var y := world.surface_y(x, z)
		if y < sea_level:
			continue
		var stand := Vector3i(x, y + 1, z)
		if world.is_solid(stand) or world.is_solid(stand + Vector3i.UP) or world.get_liquid(stand).y > 0:
			continue
		return Vector3(x + 0.5, y + 1, z + 0.5)
	return null


## Height where Terraria's Space layer (the floating islands) begins: the
## world generator's, a fixed height above the surface level, clear of the
## mountains (harpies spawn there, Space music plays).
func space_level() -> float:
	return surface_level + space_height


func _update_music(pos: Vector3) -> void:
	if boss_alive():
		Audio.set_music(boss().def.get("music", "Boss1"))
	elif invasion.near(pos):
		Audio.set_music("GoblinArmy")
	elif pos.y > space_level():
		Audio.set_music("SpaceDay" if sky.is_day else "SpaceNight")
	elif biome == "ocean":
		Audio.set_music("OceanDay" if sky.is_day else "OceanNight")
	elif biome != "" and pos.y > underworld_level:
		Audio.set_music(biome_music(biome, pos.y < surface_level - 15.0))
	elif pos.y < underworld_level:
		Audio.set_music("Underworld")
	elif pos.y < surface_level - 15.0:
		Audio.set_music("Underground")
	elif sky.is_day:
		Audio.set_music("OverworldDay")
	else:
		Audio.set_music("OverworldNight")


func _unhandled_input(event: InputEvent) -> void:
	if state != State.PLAYING:
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		if hud.sign_open:
			hud.close_sign(false)
		elif hud.chat_npc != null and not hud.shop_open:
			hud.close_chat()
		elif hud.inventory_open:
			hud.close_inventory()
		else:
			hud.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("screenshot") and not event.is_echo():
		take_screenshot()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") and not event.is_echo() and not hud.paused and not hud.sign_open:
		if hud.chat_npc != null and not hud.shop_open:
			hud.close_chat()
		hud.toggle_inventory()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not hud.inventory_open and not hud.paused and not hud.sign_open and hud.chat_npc == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_setting_changed(key: String) -> void:
	match key:
		"render_distance":
			renderer.render_distance = int(Settings.get_value(key))
			renderer.refocus()
			lod.refocus()
		"far_distance":
			lod.far_distance = int(Settings.get_value(key))
			renderer.refocus()
		"fov":
			player.camera.fov = float(Settings.get_value(key))
		"enemy_health_bars":
			for npc in npcs():
				npc._bar_shown = Vector2i(-1, -1)  # redraw (or hide) on the next frame


# ------------------------------------------------------------------ entities

func npcs() -> Array:
	return get_tree().get_nodes_in_group("npcs")


func spawn_npc(kind: String, pos: Vector3) -> NPC:
	if not Data.npcs.has(kind):
		return null
	var npc := NPC.new()
	npc.setup(kind)
	npc.add_to_group("npcs")
	entities.add_child(npc)
	npc.global_position = pos
	return npc


func any_npc_in_block(p: Vector3i) -> bool:
	for npc in npcs():
		if npc.overlaps_box(Vector3(p) + Vector3(0.5, 0, 0.5), Vector3(0.5, 1.0, 0.5)):
			return true
	return false


func boss_alive() -> bool:
	for npc in npcs():
		if npc.boss:
			return true
	return false


func boss() -> NPC:
	for npc in npcs():
		if npc.boss:
			return npc
	return null


func summon_boss(kind: String) -> void:
	if boss_alive():
		return
	var a := randf() * TAU
	var pos := player.global_position + Vector3(cos(a) * 30.0, 18.0, sin(a) * 30.0)
	if Data.npcs[kind].ai == "worm":
		# Worms come up out of the ground below you.
		pos = player.global_position + Vector3(cos(a) * 24.0, -24.0, sin(a) * 24.0)
		pos.y = maxf(pos.y, 4.0)
	spawn_npc(kind, pos)
	Audio.play("Roar_0")
	message("%s has awoken!" % Assets.npc_name(kind), Color(0.69, 0.29, 1.0))


## A boss's name and life for the bar: {name, life, max}; a boss made of many
## NPCs (boss_group) counts them all.
func boss_status() -> Dictionary:
	var b := boss()
	if b == null:
		return {}
	var group: String = b.def.get("boss_group", "")
	var adds: Array = b.def.get("bar_adds", [])
	if not adds.is_empty():
		# Its minions' life counts too, out of all of theirs at full
		# (Terraria's BrainOfCthuluBigProgressBar: the Creepers).
		var life := maxi(b.life, 0)
		for npc in npcs():
			if npc.kind == adds[0] and not npc.is_queued_for_deletion():
				life += maxi(npc.life, 0)
		return {"name": Assets.npc_name(b.kind), "life": life, "max": b.life_max + int(Data.npcs[adds[0]].life) * int(adds[1])}
	if group == "":
		return {"name": Assets.npc_name(b.kind), "life": maxi(b.life, 0), "max": b.life_max}
	var total := 0
	for npc in npcs():
		if npc.def.get("boss_group", "") == group and not npc.is_queued_for_deletion():
			total += maxi(npc.life, 0)
	return {"name": Assets.npc_name(group), "life": total, "max": maxi(int(boss_life_max.get(group, total)), 1)}


## True if another NPC of `npc`'s boss group is still about.
func _group_left(npc: NPC) -> bool:
	var group: String = npc.def.get("boss_group", "")
	for other in npcs():
		if other != npc and not other.is_queued_for_deletion() and other.life > 0 and other.def.get("boss_group", "") == group:
			return true
	return false


func on_boss_despawned(npc: NPC) -> void:
	var group: String = npc.def.get("boss_group", "")
	if group != "":
		if _group_left(npc):
			return
		message("%s has departed!" % Assets.npc_name(group), Color(0.69, 0.29, 1.0))
		return
	message("%s has departed!" % Assets.npc_name(npc.kind), Color(0.69, 0.29, 1.0))


func on_npc_killed(npc: NPC) -> void:
	invasion.on_kill(npc)
	# Kills by banner (Terraria's NPC.killCount: the Tally Counter's).
	if npc.def.ai != "town" and not npc.is_critter() and not npc.def.get("invulnerable", false):
		var banner: String = npc.def.get("banner", npc.kind)
		kill_counts[banner] = int(kill_counts.get(banner, 0)) + 1
	var group: String = npc.def.get("boss_group", "")
	if group != "":
		# The last of it: the boss is beaten, and this one drops its loot.
		if _group_left(npc):
			return
		defeated_bosses[group] = true
		for d in Data.npcs[group].get("boss_drops", []):
			if randf() < float(d[3]):
				spawn_item(d[0], randi_range(int(d[1]), int(d[2])), npc.center(), Vector3.ZERO, 0.0, Prefixes.NATURAL)
		message("%s has been defeated!" % Assets.npc_name(group), Color(0.69, 0.29, 1.0))
		return
	if npc.boss:
		defeated_bosses[npc.kind] = true
		message("%s has been defeated!" % Assets.npc_name(npc.kind), Color(0.69, 0.29, 1.0))


## The Dungeon's wall at `pos` (worldgen's "dungeon_part" blobs: dungeon.rs
## wall_variants, the last one it's in): 0 brick, 1 slab, 2 tiled.
func dungeon_wall(pos: Vector3) -> int:
	if _dungeon_parts.is_empty():
		for d in world.get_decorations():
			if d.kind == "dungeon_part":
				_dungeon_parts.append([Vector3(d.pos), float(int(d.style) >> 2) / 10.0, int(d.style) & 3])
	var v := 0
	for part in _dungeon_parts:
		if pos.distance_to(part[0]) < part[1]:
			v = part[2]
	return v


var _dungeon_parts: Array = []


## The Old Man at the Dungeon's door (worldgen's "old_man" decoration), if
## Skeletron isn't beaten and he isn't there already.
func _spawn_old_man() -> void:
	if defeated_bosses.has("SkeletronHead") or npcs().any(func(n): return n.kind == "OldMan"):
		return
	for d in world.get_decorations():
		if d.kind == "old_man":
			spawn_npc("OldMan", Vector3(d.pos) + Vector3(0.5, 0, 0.5))


## Terraria's NPC.SpawnSkeletron: the Old Man, cursed at night, dies and
## Skeletron rises where he stood (he's back at dawn if it isn't beaten).
func curse_old_man(old_man: NPC) -> void:
	if sky.is_day or boss_alive() or not is_instance_valid(old_man):
		return
	var at := old_man.center()
	Audio.play_at(old_man.def.get("death_sound", "NPC_Killed_1"), at)
	spawn_dust(at, Color(0.65, 0.05, 0.05), 14)
	old_man.queue_free()
	spawn_npc("SkeletronHead", at + Vector3(0, 1.0, 0))
	message("Skeletron has awoken!", Color(0.69, 0.29, 1.0))


func _on_dawn() -> void:
	_spawn_old_man()
	invasion.dawn()
	# A new day, a new fish for the Angler (Main.AnglerQuestSwap).
	town.new_angler_quest()
	spawner.roll_critter_odds()


## Terraria: at dusk a strong enough player may be visited by the Eye of Cthulhu.
func _on_dusk() -> void:
	if not defeated_bosses.has("EyeofCthulhu") and player.life_max >= 200 and randf() < 0.33:
		message("You feel an evil presence watching you...", Color(0.2, 0.4, 1.0))
		_evil_presence = 20.0


## `prefix`: the item's prefix, or Prefixes.NATURAL to roll one (enemy, boss
## and tile drops, like Terraria's).
func spawn_item(item: String, count: int, pos: Vector3, vel := Vector3.ZERO, delay := 0.0, prefix := 0) -> void:
	if item == "" or count <= 0 or Data.item(item).is_empty():
		return
	if prefix == Prefixes.NATURAL:
		prefix = Prefixes.roll(Data.item(item))
	if _collected_drops != null and prefix == 0:
		_collected_drops[item] = _collected_drops.get(item, 0) + count
		return
	var d := ItemDrop.new()
	d.setup(item, count, prefix)
	entities.add_child(d)
	d.global_position = pos
	d.velocity = vel if vel != Vector3.ZERO else Vector3(randf_range(-2, 2), 4.0, randf_range(-2, 2))
	d.age = -delay


## Splits a copper value into gold/silver/copper coin drops.
func spawn_coins(value: int, pos: Vector3) -> void:
	value = int(value * randf_range(0.8, 1.2))
	var gold := value / 10000
	var silver := (value % 10000) / 100
	var copper := value % 100
	spawn_item("GoldCoin", gold, pos)
	spawn_item("SilverCoin", silver, pos)
	spawn_item("CopperCoin", copper, pos)


func spawn_projectile(proj: String, pos: Vector3, vel: Vector3, damage: int, knockback: float,
		gravity := 0.0, spin := 0.0, size := 0.5, friendly := true, crit := 0.04) -> Projectile:
	var p := Projectile.new()
	p.setup(proj, size)
	p.velocity = vel
	p.gravity = gravity
	p.spin = spin
	p.damage = damage
	p.knockback = knockback
	p.friendly = friendly
	p.crit = crit
	entities.add_child(p)
	p.global_position = pos
	return p


func floating_text(text: String, pos: Vector3, color: Color, big := false) -> void:
	var t := FloatingText.new()
	t.setup(text, color, big)
	entities.add_child(t)
	t.global_position = pos


## Takes a screenshot without the HUD: hides every screen overlay (the HUD,
## the test world's panel), the block outline, enemy health bars and damage
## numbers, waits for a frame drawn without them, saves it to SCREENSHOT_DIR
## and puts them back. Returns the file's path ("" if nothing was drawn:
## headless).
func take_screenshot() -> String:
	var hidden: Array[Node] = []
	var overlays: Array[Node] = get_tree().root.find_children("*", "CanvasLayer", true, false)
	overlays.append(player._highlight)
	overlays.append_array(entities.find_children("*", "HealthBar", true, false))
	overlays.append_array(entities.find_children("*", "FloatingText", true, false))
	for n in overlays:
		if n.visible:
			n.visible = false
			hidden.append(n)
	taking_screenshot = true
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		await get_tree().process_frame  # nothing is drawn (tests)
	else:
		await RenderingServer.frame_post_draw
	var img: Image = null if headless else get_viewport().get_texture().get_image()
	taking_screenshot = false
	for n in hidden:
		if is_instance_valid(n):
			n.visible = true
	if img == null or img.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCREENSHOT_DIR))
	var stamp := Time.get_datetime_string_from_system().replace("T", " ").replace(":", "-")
	var path := SCREENSHOT_DIR + "Terraria 3D %s.png" % stamp
	var n := 2
	while FileAccess.file_exists(path):
		path = SCREENSHOT_DIR + "Terraria 3D %s (%d).png" % [stamp, n]
		n += 1
	if img.save_png(path) != OK:
		message("Couldn't save the screenshot", Color(1, 0.4, 0.4))
		return ""
	message("Screenshot saved: screenshots/" + path.get_file(), Color(0.6, 0.9, 1.0))
	return path


func message(text: String, color := Color.WHITE) -> void:
	hud.message(text, color)


## A one-shot burst of coloured square particles (Terraria "dust").
func spawn_dust(pos: Vector3, color: Color, amount := 8) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var light := world.get_light(pos)
	var l := maxf(maxf(light.r, light.g), maxf(light.b, light.a * sky.sky_light))
	mat.albedo_color = color * clampf(l * l + 0.05, 0.0, 1.0)
	quad.material = mat
	p.mesh = quad
	entities.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


## Where lava pockets start, 20 blocks under the caverns' top (worldgen's
## lava pools; Terraria's lavaLine).
func lava_level() -> float:
	return cavern_level - 20.0


static func roll_loot(table_name: String, lava := false) -> Array:
	var table: Dictionary = Data.loot.get(table_name, {})
	var out := []
	var pick: Array = table.get("pick_one", [])
	if not pick.is_empty():
		var e: Array = pick[randi() % pick.size()]
		# A rarer primary item instead now and then (the Ivy Chest's; a Lava
		# Charm only below the lava line, `lava`).
		for alt in table.get("instead", []):
			if alt.size() > 4 and alt[4] == "lava" and not lava:
				continue
			if randf() < float(alt[3]):
				e = alt
				break
		out.append([e[0], randi_range(int(e[1]), int(e[2]))])
	for e in table.get("extras", []):
		if randf() < float(e[3]):
			out.append([e[0], randi_range(int(e[1]), int(e[2]))])
	# One of a few, that often (a Shadow Chest's Meteorite or Gold Bars).
	for e in table.get("either", []):
		if randf() < float(e[1]):
			var c: Array = e[0].pick_random()
			out.append([c[0], randi_range(int(c[1]), int(c[2]))])
	# Sets that come together (the Mushroom Chest's Mushroom Hat, Vest and Pants).
	for e in table.get("sets", []):
		if randf() < float(e[1]):
			for item in e[0]:
				out.append([item, 1])
	# Items not in this game (the Gravitation Potion) roll but come to nothing.
	return out.filter(func(d): return Data.items.has(d[0]))


# ------------------------------------------------------------------ blocks

const _SOUNDS := {"dig": "Dig_*", "tink": "Tink_*", "grass": "Grass", "shatter": "Shatter"}


func block_hit_effects(p: Vector3i, id: int) -> void:
	var b := Data.block(id)
	var c := Vector3(p) + Vector3(0.5, 0.5, 0.5)
	Audio.play_at(_SOUNDS.get(b.get("sound", "dig"), "Dig_*"), c, 0.8)
	_block_dust(p, id, false)


## A block's dust on a hit (`kill` false) or when it breaks: Terraria's for
## its tile (DustParticles); our own blocks with no Terraria tile behind them
## get plain specks of their colour.
func _block_dust(p: Vector3i, id: int, kill: bool) -> void:
	var b := Data.block(id)
	if Data.tile_dust.has(b.get("name", "")):
		dust.tile_dust(p, id, kill)
	else:
		var c := Vector3(p) + Vector3(0.5, 0.5, 0.5)
		spawn_dust(c, b.get("color", Color(0.5, 0.4, 0.3)), 12 if kill else 5)


## Breaks a block like Terraria: drops its item, fells trees above axed trunks,
## pops unsupported plants/torches, and rolls pot loot.
## Drops gathered while an explosion breaks blocks (null otherwise): one
## stack of each item instead of hundreds.
var _collected_drops = null


## Terraria's explosion at `pos`: hurts enemies (and you, unless "self" is
## false) within `ex.radius`, pushing them away, and with "tiles" blows away
## the blocks in that sphere (not chests, dungeon brick, Hellstone or
## anything unbreakable), dropping what they drop.
func explode(pos: Vector3, damage: int, knockback: float, ex: Dictionary) -> void:
	var r := float(ex.get("radius", 3.0))
	Audio.play_at("Item_14", pos)
	for i in 6:
		var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * r * 0.4
		spawn_dust(pos + off, [Color(1.0, 0.6, 0.15), Color(1.0, 0.85, 0.4), Color(0.4, 0.4, 0.4)][i % 3], 16)
	for npc in npcs():
		var to: Vector3 = npc.center() - pos
		if to.length() < r + npc.half.x and not npc.def.get("invulnerable", false) and not npc.dont_take_damage:
			npc.hit(damage, knockback, to.normalized(), 0.04)
	if ex.get("self", true) and player.alive and player.center().distance_to(pos) < r + 0.5:
		player.hurt(damage, pos)
	if ex.get("tiles", false):
		blast_blocks(pos, r)


## Whether explosions can break this block (Terraria's: not chests, dungeon
## brick, Hellstone before Hardmode, orbs, altars, or anything unbreakable).
static func blastproof(b: Dictionary) -> bool:
	return b.has("unbreakable") or b.get("interact") in ["chest", "spawner"] or (b.get("biome") == "dungeon" and not b.get("cracked", false)) \
			or b.get("name") == "hellstone" or b.get("on_break") == "orb" or int(b.get("min_pick", 0)) > 65


## Breaks the blocks in the sphere of `r` round `pos` (top down, so what
## rests on them goes with them); their drops land in one pile per item.
func blast_blocks(pos: Vector3, r: float) -> int:
	var c := Vector3i(pos.floor())
	var n := ceili(r)
	var cells := []
	for y in range(n, -n - 1, -1):
		for z in range(-n, n + 1):
			for x in range(-n, n + 1):
				var q := c + Vector3i(x, y, z)
				if (Vector3(q) + Vector3(0.5, 0.5, 0.5)).distance_to(pos) <= r:
					cells.append(q)
	_collected_drops = {}
	var broken := 0
	for q in cells:
		var id := world.get_block(q)
		if id == 0 or blastproof(Data.block(id)):
			continue
		break_block(q, true, true)
		broken += 1
	var drops: Dictionary = _collected_drops
	_collected_drops = null
	for item in drops:
		spawn_item(item, drops[item], pos)
	return broken


const CORDAGE_VINES := ["vines", "vine_flowers", "jungle_vines"]


func break_block(p: Vector3i, drop := true, quiet := false) -> void:
	var id := world.get_block(p)
	if id == 0:
		return
	var b := Data.block(id)
	if Doors.is_part(b):
		# Either half takes the whole door; the bottom drops it.
		var top := p + Vector3i.UP if Doors.is_door(b) else p
		p = Doors.break_top(self, p)
		id = world.get_block(p)
		b = Data.block(id)
		_drop_dependents(top, drop)
	if test_world and b.get("interact") == "spawner":
		test_world.remove_spawner(p)
	if b.get("interact") == "chest":
		if not chests.is_empty(p):
			message("The chest must be empty", Color(0.9, 0.7, 0.7))
			return
		chests.remove(p)
		world.remove_decorations_at(p)
	world.set_block(p, 0)
	block_rotations.erase(Chests.key(p))
	signs.erase(Chests.key(p))
	_drop_bait(p, b)
	for n in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK, Vector3i.DOWN]:
		if waterfalls.has_fall(p + n, Waterfalls.dir_index(n)):
			waterfalls.remove_fall(p + n)
	var c := Vector3(p) + Vector3(0.5, 0.4, 0.5)
	if not quiet:
		Audio.play_at(_SOUNDS.get(b.get("sound", "dig"), "Dig_*"), c)
		_block_dust(p, id, true)
	if drop:
		spawn_item(block_drop(b), 1, c, Vector3.ZERO, 0.0, Prefixes.NATURAL)
		if b.get("on_break") == "pot":
			for d in roll_loot("pot"):
				spawn_item(d[0], d[1], c)
		if b.has("herb"):
			for d in herbs.drops(b, p, regrowth):
				spawn_item(d[0], d[1], c)
		# The Guide to Plant Fiber Cordage: vines (plain, flower and jungle)
		# drop Vine Rope half the time (Terraria's KillTile_GetItemDrops).
		if Data.kind_of(id) in CORDAGE_VINES and player != null and player.has_effect("cordage") and randf() < 0.5:
			spawn_item("VineRope", 1, c)

	if b.get("trunk", false):
		_fell_tree(p, id)
	if b.get("on_break") == "larva":
		_larva_burst(c)
	if b.get("on_break") == "orb":
		_orb_smashed(c, b)
	if b.get("on_break") == "cactus":
		_fell_cactus(p, drop)
	_drop_dependents(p, drop)
	# Sand resting on it falls.
	settle_falling(p + Vector3i.UP)


## Whether the block at `p` holds up sand (Terraria's
## WorldGen.BlockBelowMakesSandFall, the other way round): any solid block or
## platform; not air, an actuated block or an icicle; a non-solid block (a
## torch, a plant) only with something under it.
static func supports_falling(w: VoxelWorld, p: Vector3i) -> bool:
	var id := w.get_block(p)
	if id == 0 or w.is_inactive(p):
		return false
	var b := Data.block(id)
	if b.get("solid", true) or b.get("platform", false):
		return int(b.get("tile_id", -1)) != 165
	return w.get_block(p + Vector3i.DOWN) != 0


## Blocks that sand holds up instead of falling under them (Terraria's
## WorldGen.AllowsSandfall: chests, dressers, altars, cacti, palms...).
const HELD_UP_BY_SAND := [26, 77, 80, 88, 323, 470, 475, 597]


## If the block at `p` is one that falls (sand, silt, slush...) and nothing
## holds it up, it drops as a FallingBlock; so does the column of them above.
func settle_falling(p: Vector3i) -> void:
	while true:
		var id := world.get_block(p)
		var b := Data.block(id)
		# A boulder with nothing under it rolls (Terraria's Check2x2 for them).
		if b.has("boulder") or b.get("trap", "") == "boulder":
			if not supports_falling(world, p + Vector3i.DOWN):
				drop_boulder(p)
			return
		if not b.get("falls", false) or supports_falling(world, p + Vector3i.DOWN):
			return
		var above := Data.block(world.get_block(p + Vector3i.UP))
		if above.get("interact") == "chest" or above.get("cactus", false) or int(above.get("tile_id", -1)) in HELD_UP_BY_SAND:
			return
		world.set_block(p, 0)
		var f := FallingBlock.new()
		f.setup(id)
		entities.add_child(f)
		f.global_position = Vector3(p)
		p += Vector3i.UP


## A boulder block at `p` comes loose: it falls and rolls (its block's
## "boulder": Projectile "Boulder", "LavaBoulder", "Ghoulder"...). Terraria's
## Check2x2: 70 damage (doubled on you as hostile), the Rainbow Boulder's 100.
func drop_boulder(p: Vector3i) -> void:
	var kind: String = Data.block(world.get_block(p)).get("boulder", "Boulder")
	world.set_block(p, 0)
	var b: Projectile = spawn_projectile(kind, Vector3(p) + Vector3(0.5, 0.5, 0.5), Vector3.ZERO, 100 if kind == "RainbowBoulder" else 70, 10.0, 0.0, 0.0, 1.0, false)
	b.boulder = true


## Terraria's tile cutting: a block of Main.tileCut (grass, flowers, vines,
## cobwebs, pots...) at `p` breaks, dropping as usual, unless it's a plant in
## a pot or planter box (WorldGen.CanCutTile). True if it was cut.
func cut_tile(p: Vector3i) -> bool:
	var b := Data.block(world.get_block(p))
	if not b.get("cut", false):
		return false
	# The Staff of Regrowth cuts only herbs ready to harvest, in pots too.
	if regrowth and b.has("herb"):
		if not herbs.harvestable(b, p):
			return false
	elif int(Data.block(world.get_block(p + Vector3i.DOWN)).get("tile_id", -1)) in [78, 380, 579]:
		return false
	break_block(p)
	return true


## Cuts every cuttable block touching the box `radius` round `center` (a
## projectile of the player's: Projectile.CutTiles).
func cut_tiles_at(center: Vector3, radius: float) -> void:
	var lo := Vector3i((center - Vector3.ONE * radius).floor())
	var hi := Vector3i((center + Vector3.ONE * radius).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				cut_tile(Vector3i(x, y, z))


## A swing's cut (Player.ItemCheck_CutTiles): the cuttable blocks within
## `reach` of `origin` inside the cone round `dir` (cos of its half angle), that
## no solid block hides.
func cut_tiles_in_cone(origin: Vector3, dir: Vector3, reach: float, cone: float) -> void:
	var r := ceili(reach)
	var o := Vector3i(origin.floor())
	for x in range(-r, r + 1):
		for y in range(-r, r + 1):
			for z in range(-r, r + 1):
				var p := o + Vector3i(x, y, z)
				if not Data.block(world.get_block(p)).get("cut", false):
					continue
				var to := Vector3(p) + Vector3(0.5, 0.5, 0.5) - origin
				var dist := to.length()
				if dist > reach + 0.5 or (dist > 0.5 and to.normalized().dot(dir) < cone):
					continue
				var seen := true
				for k in range(1, int(dist / 0.25)):
					var q := Vector3i((origin + to.normalized() * k * 0.25).floor())
					if q != p and world.is_solid(q):
						seen = false
						break
				if seen:
					cut_tile(p)


## Breaks what needs the (just removed) block at `p` to stay up.
func _drop_dependents(p: Vector3i, drop: bool) -> void:
	# Wall torches hanging on this block fall off.
	for r in 4:
		var n: Vector3i = Player.WALL_NORMALS[r]
		var q := p + n
		if Data.block(world.get_block(q)).get("wall", false) and block_rotation(q) == r:
			break_block(q, drop)
	# So do paintings with this block behind any of them.
	for q in Paintings.resting_on(self, p):
		break_block(q, drop)
	# Lanterns hanging from it fall.
	var below := p + Vector3i.DOWN
	if Data.block(world.get_block(below)).get("hangs", false):
		break_block(below, drop)
	# Anything resting on this block that needs support falls with it.
	var above := p + Vector3i.UP
	var above_def := Data.block(world.get_block(above))
	if Doors.is_door(above_def) or not above_def.is_empty() and not above_def.get("solid", true) and not above_def.get("platform", false) and not above_def.get("floats", false) \
			and not above_def.get("wall", false) and not above_def.get("hangs", false) and not above_def.get("door_top", false):
		break_block(above, drop)


## A cactus cell broken (already gone): the whole cactus comes down, a Cactus
## for each piece of it, arms included.
func _fell_cactus(p: Vector3i, drop: bool) -> void:
	var cactus := func(q: Vector3i) -> bool: return Data.block(world.get_block(q)).get("cactus", false)
	var base := p
	while cactus.call(base + Vector3i.DOWN):
		base += Vector3i.DOWN
	var top := p
	while cactus.call(top + Vector3i.UP):
		top += Vector3i.UP
	var s := CactusArt.shape(base, top.y - base.y + 1, CactusArt.color_for(Data.block(world.get_block(base + Vector3i.DOWN))))
	for y in range(base.y, top.y + 1):
		var q := Vector3i(p.x, y, p.z)
		if q != p:
			world.set_block(q, 0)
	if drop:
		spawn_item("Cactus", CactusArt.pieces(s) - 1, Vector3(p) + Vector3(0.5, 0.5, 0.5))


## A bee larva broken (Terraria's tile 231): its sounds, and the Queen Bee
## comes for you (NPC.SpawnOnPlayer).
func _larva_burst(c: Vector3) -> void:
	Audio.play_at("NPC_Killed_1", c)
	Audio.play_at("Item_173", c)
	spawn_dust(c, Color(1.0, 0.75, 0.2), 16)
	summon_boss("QueenBee")


## A Shadow Orb or Crimson Heart smashed: its loot, and Terraria's warnings.
func _orb_smashed(c: Vector3, b: Dictionary) -> void:
	var table: String = b.get("loot", "shadow_orb")
	var drops := roll_loot(table)
	if orbs_broken == 0:
		# Terraria (WorldGen.CheckOrb): the world's first orb always gives its
		# first item (the Musket, The Undertaker).
		var first: Array = Data.loot[table].pick_one[0]
		drops[0] = [first[0], int(first[1])]
	for d in drops:
		spawn_item(d[0], d[1], c, Vector3.ZERO, 0.0, Prefixes.NATURAL)
	orbs_broken += 1
	match orbs_broken % 3:
		1:
			message("A horrible chill goes down your spine...", Color(0.6, 0.45, 1.0))
		2:
			message("Screams echo around you...", Color(0.6, 0.45, 1.0))
		0:
			# Terraria: the third orb wakes the Eater of Worlds, the third
			# heart the Brain of Cthulhu.
			summon_boss("EaterofWorldsHead" if table == "shadow_orb" else "BrainofCthulhu")


## What breaking a block drops: its "drop", or for a gem tree's trunk its gem
## 1 time in 10 (Terraria's SetGemTreeDrops; else Stone Block), or its
## "rare_drop" [item, n] 1 time in n (the sword in stone's Terragrim, 1 in 30;
## a glowing mushroom's Mushroom Grass Seeds, 1 in 40); with "drop_chance" its
## drop only that often (the glowing mushrooms: half the time), else nothing.
## Terraria's WorldGen.KillTile_DropBait: grass and plants broken now and
## then let out a critter: a worm (1 in 400 from grass, 1 in 200 from tall
## grass) or a grasshopper (1 in 100, 1 in 50); jungle plants grubs (Grubby,
## 1 in 4 a Sluggy, 1 in 12 a Buggy: 1 in 100 from jungle plants, 1 in 50
## from tall ones, 1 in 312 from vines, 1 in 12 from big ones); ash plants
## a Hell Butterfly or a Lavafly (1 in 100). Not past 5 worms or grasshoppers
## or 8 grubs or lava critters at once; a worm is gold 1 in 400.
func _drop_bait(p: Vector3i, b: Dictionary) -> void:
	var tile := int(b.get("tile_id", -1))
	var worm := 0
	var hopper := 0
	var grub := 0
	var lava := 0
	match tile:
		3:
			worm = 400
			hopper = 100
		73:
			worm = 200
			hopper = 50
		61:
			grub = 80
		74:
			grub = 40
		62:
			grub = 250
		233:
			grub = 10
		637:
			lava = 100
		_:
			return
	var count := func(kinds: Array) -> int:
		return npcs().filter(func(n): return n.kind in kinds).size()
	var at := Vector3(p) + Vector3(0.5, 0.1, 0.5)
	if worm > 0 and count.call(["Worm", "GoldWorm"]) < 5 and randi() % worm == 0:
		_pop_critter("GoldWorm" if randi() % Spawner.GOLD_CHANCE == 0 else "Worm", at)
	if hopper > 0 and count.call(["Grasshopper", "GoldGrasshopper"]) < 5 and randi() % hopper == 0:
		_pop_critter("GoldGrasshopper" if randi() % Spawner.GOLD_CHANCE == 0 else "Grasshopper", at)
	if grub > 0 and count.call(["Grubby", "Sluggy", "Buggy"]) < 8 and randi() % int(grub * 1.25) == 0:
		var kind := "Sluggy" if randi() % 4 == 0 else "Grubby"
		if randi() % 12 == 0:
			kind = "Buggy"
		_pop_critter(kind, at)
	if lava > 0 and count.call(["HellButterfly", "Lavafly"]) < 8 and randi() % lava == 0:
		_pop_critter("HellButterfly" if randi() % 2 == 0 else "Lavafly", at)


## A critter jumping out of a broken plant (2.2-5 px/tick up, up to 2.5 aside).
func _pop_critter(kind: String, at: Vector3) -> void:
	var npc := spawn_npc(kind, at)
	var a := randf() * TAU
	npc.velocity = Vector3(cos(a), 0, sin(a)) * randf_range(0.0, 2.5) * NPC.PX_TICK + Vector3(0, randf_range(2.2, 5.0) * NPC.PX_TICK, 0)


func block_drop(b: Dictionary) -> String:
	if b.has("gem") and randf() < 0.1:
		return b.gem
	if b.has("rare_drop") and randi() % int(b.rare_drop[1]) == 0:
		return b.rare_drop[0]
	if b.has("drop_chance") and randf() >= float(b.drop_chance):
		return ""
	return b.get("drop", "")


func _fell_tree(p: Vector3i, trunk: int) -> void:
	# The trunk's own wood (boreal, mahogany, palm...; a gem tree's stone and gems).
	var b := Data.block(trunk)
	var y := p.y + 1
	while world.get_block(Vector3i(p.x, y, p.z)) == trunk:
		world.set_block(Vector3i(p.x, y, p.z), 0)
		spawn_item(block_drop(b), 1, Vector3(p.x + 0.5, y + 0.5, p.z + 0.5))
		y += 1
	if world.remove_decorations_at(Vector3i(p.x, y, p.z)) > 0:
		# The canopy drops a few extra logs, like Terraria's tree tops (a
		# giant mushroom's cap is just its top cell: one more roll).
		for i in (randi_range(2, 5) if b.get("top_drops", true) else 1):
			spawn_item(block_drop(b), 1, Vector3(p.x + 0.5, y, p.z + 0.5))
		decorations.refresh()
		far_trees.invalidate()


## A hammer hit reshapes a block, like Terraria's: full -> half block ->
## ramp -> upside-down ramp -> full. The ramp rises toward `dir` (0-3,
## Player.WALL_NORMALS: away from whoever hits it). Returns false if the block
## can't take a shape (not a solid cube, or unbreakable).
func hammer_shape(p: Vector3i, dir: int) -> bool:
	var id := world.get_block(p)
	var b := Data.block(id)
	if b.get("platform", false):
		# Terraria's platform stairs: a stair rising away from you, then the
		# other way, then flat again.
		var was := world.get_shape(p)
		var next := SHAPE_RAMP + dir
		if was >= SHAPE_RAMP and was < SHAPE_CEILING:
			next = SHAPE_FULL if was != SHAPE_RAMP + dir else SHAPE_RAMP + (dir + 2) % 4
		if not world.set_shape(p, next):
			return false
		block_hit_effects(p, id)
		return true
	if id == 0 or b.has("unbreakable") or b.get("trunk", false) or b.get("render_id", 1) != 1:
		return false
	var shape := world.get_shape(p)
	var next := 0
	if shape == SHAPE_FULL:
		next = SHAPE_HALF
	elif shape == SHAPE_HALF:
		next = SHAPE_RAMP + dir
	elif shape < SHAPE_CEILING:
		next = SHAPE_CEILING + (shape - SHAPE_RAMP)
	if not world.set_shape(p, next):
		return false
	block_hit_effects(p, id)
	return true


## The text on the sign at `p` ("" if it's blank).
func sign_text(p: Vector3i) -> String:
	return signs.get(Chests.key(p), "")


func set_sign_text(p: Vector3i, text: String) -> void:
	if text.strip_edges() == "":
		signs.erase(Chests.key(p))
	else:
		signs[Chests.key(p)] = text


## Hammered block shapes (VoxelWorld.get_shape): half block, ramps 2-5 (rising
## toward Player.WALL_NORMALS[shape - 2]), upside-down ramps 6-9.
const SHAPE_FULL := 0
const SHAPE_HALF := 1
const SHAPE_RAMP := 2
const SHAPE_CEILING := 6


func block_rotation(p: Vector3i) -> int:
	return int(block_rotations.get(Chests.key(p), 0))


func open_chest(p: Vector3i) -> void:
	Audio.play("Menu_Open")
	hud.open_chest(chests.get_inventory(p), p)


## A locked chest (the Dungeon's Locked Gold Chests, the Underworld's Locked
## Shadow Chests): its key, if you carry one, opens it for good - it becomes
## its unlocked chest, its loot still in it (Terraria's Chest.Unlock). A Golden
## Key is used up; a Shadow Key ("key_kept") isn't.
func unlock_chest(p: Vector3i) -> bool:
	var b := Data.block(world.get_block(p))
	var key: String = b.get("key", "")
	var kept: bool = b.get("key_kept", false)
	if key == "" or not (player.inventory.count_of(key) > 0 if kept else player.inventory.remove(key, 1)):
		message("It's locked", Color(0.9, 0.7, 0.7))
		return false
	world.set_block(p, Data.block_id(b.unlocks_to))
	Audio.play_at("Unlock", Vector3(p) + Vector3(0.5, 0.5, 0.5))
	open_chest(p)
	return true


## Flips a switch and the light it's wired to (Terraria's Wiring.HitSwitch:
## the light goes on or off).
func hit_switch(p: Vector3i) -> void:
	wiring.flip(self, p)


## Crafting stations within reach (block names like "work_bench").
func nearby_stations(radius := 4) -> Dictionary:
	var found := {}
	var c := Vector3i(player.global_position.floor())
	for x in range(c.x - radius, c.x + radius + 1):
		for y in range(c.y - 2, c.y + 4):
			for z in range(c.z - radius, c.z + radius + 1):
				var b := Data.block(world.get_block(Vector3i(x, y, z)))
				if b.get("station", false):
					found[b.name] = true
					if b.has("station_as"):
						found[b.station_as] = true
				# Water, lava or honey nearby (Bottled Honey: a Bottle by honey).
				var liq: Vector2i = world.get_liquid(Vector3i(x, y, z))
				if liq.y > 0:
					found[LIQUID_STATIONS.get(liq.x, "")] = true
	return found


const LIQUID_STATIONS := {1: "water", 2: "lava", 3: "honey"}


# ------------------------------------------------------------------ saving

func save_world() -> bool:
	if state != State.PLAYING:
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	hud.stow_temporary_items()
	var meta := {
		"name": world_name,
		"player": player.save_state(),
		"sky": sky.save_state(),
		"chests": chests.save_state(),
		"bosses": defeated_bosses,
		"kills": kill_counts,
		"saved_at": Time.get_datetime_string_from_system(),
	}
	if test_world:
		meta["test_world"] = test_world.save_state()
	meta["rotations"] = block_rotations
	meta["orbs_broken"] = orbs_broken
	meta["ocean"] = has_ocean
	meta["creative"] = creative
	meta["styles"] = true
	meta["shapes"] = Array(world.get_shapes())
	meta["wiring"] = wiring.save_state()
	meta["inactive"] = Array(world.get_inactive())
	meta["signs"] = signs
	meta["town"] = town.save_state()
	meta["invasion"] = invasion.save_state()
	var ok := world.save(ProjectSettings.globalize_path(_save_path), JSON.stringify(meta))
	message("World saved" if ok else "Saving failed!", Color(0.7, 0.9, 0.7) if ok else Color(1, 0.4, 0.4))
	return ok


func _apply_meta(meta: Dictionary) -> void:
	world_name = meta.get("name", world_name)
	player.load_state(meta.get("player", {}))
	sky.load_state(meta.get("sky", {}))
	chests.load_state(meta.get("chests", {}))
	defeated_bosses = meta.get("bosses", {})
	kill_counts = meta.get("kills", {})
	block_rotations = meta.get("rotations", {})
	orbs_broken = int(meta.get("orbs_broken", 0))
	creative = meta.get("creative", false)
	signs = meta.get("signs", {})
	var shapes: Array = meta.get("shapes", [])
	for i in range(0, shapes.size() - 3, 4):
		world.set_shape(Vector3i(int(shapes[i]), int(shapes[i + 1]), int(shapes[i + 2])), int(shapes[i + 3]))
	# Saves from before the wiring keep worldgen's (setup's).
	if meta.has("wiring"):
		wiring.load_state(self, meta.wiring)
	var off: Array = meta.get("inactive", [])
	for i in range(0, off.size() - 2, 3):
		world.set_inactive(Vector3i(int(off[i]), int(off[i + 1]), int(off[i + 2])), true)


## Switches the world between creative and survival (the pause menu's game
## mode button, like Minecraft's /gamemode).
func set_creative(on: bool) -> void:
	creative = on
	player.creative = on
	if not on:
		player.flying = false
	hud.mode_changed()
	message("Game mode: " + ("Creative" if on else "Survival"), Color(0.7, 0.9, 1.0))


func quit_to_menu(save := true) -> void:
	get_tree().paused = false
	if save:
		save_world()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	exit_to_menu.emit()
