extends Node3D
## Visual smoke test: generates a world, streams chunks around spawn and saves
## screenshots from a few camera poses into the directory given after `--`.
## godot --path game res://tests/render_test.tscn -- <out dir> [seed]

var world := VoxelWorld.new()
var renderer := ChunkRenderer.new()
var sky := SkySystem.new()
var camera := Camera3D.new()
var decorations := Decorations.new()
var waterfalls := Waterfalls.new()
var _pour_built := false
var out_dir := "user://"
var shots := []
var frames_waited := 0
var t0 := 0
var _built := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var seed := int(args[1]) if args.size() > 1 else 1234
	add_child(sky)
	add_child(renderer)
	camera.far = 600.0
	camera.fov = 80.0
	add_child(camera)
	sky.camera = camera
	Data.register_blocks(world)
	t0 = Time.get_ticks_msec()
	world.start_generate(seed, Vector3i(512, 256, 512))


func _process(_delta: float) -> void:
	if world.is_busy():
		return
	if shots.is_empty() and frames_waited == 0:
		print("generated in %d ms" % (Time.get_ticks_msec() - t0))
		renderer.setup(world)
		add_child(decorations)
		decorations.setup(world)
		add_child(waterfalls)
		waterfalls.setup(world)
		var s := Vector3(world.get_spawn())
		var layers := world.get_layers()
		shots = [
			["surface", s + Vector3(0.5, 6, 0.5), s + Vector3(30, 0, 30), 13500.0],
			["overview", s + Vector3(-40, 40, -40), s + Vector3(10, 0, 10), 27000.0],
			["dusk", s + Vector3(0.5, 3, 0.5), s + Vector3(-30, 2, 20), 52500.0],
			["cave", _find_cave(s, int(layers.cavern_top)), Vector3.ZERO, 27000.0],
			["waterfall", Vector3.ZERO, Vector3.ZERO, 27000.0],
			["lavafall", Vector3.ZERO, Vector3.ZERO, 27000.0],
			["pour", Vector3.ZERO, Vector3.ZERO, 27000.0],
			["water", Vector3.ZERO, Vector3.ZERO, 27000.0],
			["lava", Vector3.ZERO, Vector3.ZERO, 27000.0],
			["sun_wall", Vector3.ZERO, Vector3.ZERO, 27000.0],
			["sun_open", Vector3.ZERO, Vector3.ZERO, 27000.0],
		]
		t0 = Time.get_ticks_msec()
	frames_waited += 1
	var shot: Array = shots[0]
	sky.time = shot[3]
	if shot[0].begins_with("sun_"):
		_aim_at_sun(shot[0] == "sun_wall")
	elif shot[0] in ["water", "lava"]:
		_view_liquid(1 if shot[0] == "water" else 2)
	elif shot[0] in ["waterfall", "lavafall"]:
		_view_waterfall(1 if shot[0] == "waterfall" else 2)
	elif shot[0] == "pour":
		_view_pour()
	else:
		camera.global_position = shot[1]
		if shot[2] != Vector3.ZERO:
			camera.look_at(shot[2])
		else:
			camera.rotation = Vector3(-0.2, 0.7, 0)
	if frames_waited % 3 == 0:
		world.step_liquids(30000)  # 20 ticks/s, like the game
	waterfalls.focus = camera.global_position
	waterfalls.set_sky(sky.sky_light, sky.sky_tint)
	renderer.focus = camera.global_position
	renderer.set_sky(sky.sky_light, sky.sky_tint)
	decorations.set_sky(sky.sky_light, sky.sky_tint)
	# Wait for nearby chunks, then a few frames for the GPU.
	var min_frames := 90 if shot[0].begins_with("sun_") or shot[0] in ["pour", "waterfall", "lavafall"] else 30
	var settle: bool = frames_waited < 240 and renderer._pending.size() > 0 and shot[0] != "pour"
	if settle or frames_waited < min_frames:
		return
	var img := get_viewport().get_texture().get_image()
	var path: String = out_dir.path_join("shot_%s.png" % shot[0])
	img.save_png(path)
	print("saved %s after %d frames (%d chunks)" % [path, frames_waited, renderer.loaded_count()])
	shots.pop_front()
	frames_waited = 1
	if shots.is_empty():
		print("RESULT: ok")  # every shot saved (run_tests.sh looks for this)
		get_tree().quit()


var _fall_views := {}


## Water: a stone cliff built in daylight with a spring added to its face.
## Lava: the Underworld lavafall nearest to spawn.
func _view_waterfall(t: int) -> void:
	if t == 1 and not _fall_views.has(t):
		var base := Vector3i(world.get_spawn()) + Vector3i(-14, 0, -14)
		var stone := Data.block_id("stone")
		for x in range(-3, 4):
			for y in range(-2, 11):
				for z in range(-2, 1):
					world.set_block(base + Vector3i(x, y, z), stone)
				for z in range(1, 6):
					if y >= 0:
						world.set_block(base + Vector3i(x, y, z), 0)
		waterfalls.add_fall(base + Vector3i(0, 8, 1), 1, 2)
		_fall_views[t] = [Vector3(base) + Vector3(5.5, 4.0, 9.0), Vector3(base) + Vector3(0.5, 4.0, 1.0)]
	if not _fall_views.has(t):
		var s := Vector3(world.get_spawn())
		var best = null
		for d in world.get_decorations():
			if d.kind == "waterfall" and int(d.style) / 10 == t:
				if best == null or Vector3(d.pos).distance_to(s) < Vector3(best.pos).distance_to(s):
					best = d
		if best == null:
			_fall_views[t] = [s, s]
		else:
			var dir_i := int(best.style) % 10
			var out: Vector3 = Vector3(1, 0, 0) if dir_i == 4 else Waterfalls.DIRS[dir_i]
			var mouth := Vector3(best.pos) + Vector3(0.5, 0.5, 0.5)
			# Stand in the open space in front of the spring, a little to the side.
			var cam: Vector3 = mouth + out * 4.5 + Vector3(out.z, 0, out.x) * 1.5 + Vector3(0, -1.0, 0)
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					for dz in range(-1, 2):
						var c := Vector3i(cam.floor()) + Vector3i(dx, dy, dz)
						if world.get_liquid(c).y == 0:
							world.set_block(c, 0)
			# Light the scene from the camera's pocket and next to the spring.
			world.set_block(Vector3i(cam.floor()) + Vector3i(0, -1, 0), Data.block_id("torch"))
			var torch := Vector3i((mouth + out * 1.0 + Vector3(0, -1, 0)).floor())
			if world.get_block(torch) == 0 and not world.is_solid(torch + Vector3i.DOWN) == false:
				world.set_block(torch, Data.block_id("torch"))
			var target := mouth + Vector3(0, -2.5, 0)
			_fall_views[t] = [cam, target]
	camera.global_position = _fall_views[t][0]
	camera.look_at(_fall_views[t][1])


## Water on a raised shelf, walled on three sides, pours off the open edge.
func _view_pour() -> void:
	var base := Vector3i(world.get_spawn()) + Vector3i(14, 12, 0)
	if not _pour_built:
		_pour_built = true
		var stone := Data.block_id("stone")
		for x in range(-1, 4):
			for z in range(-1, 4):
				world.set_block(base + Vector3i(x, -1, z), stone)
				for y in range(0, 6):
					var wall := x == -1 or z == -1 or z == 3
					world.set_block(base + Vector3i(x, y, z), stone if wall else 0)
		for x in range(0, 3):
			for z in range(0, 3):
				for y in range(0, 5):
					world.set_liquid(base + Vector3i(x, y, z), 1, 63)
	camera.global_position = Vector3(base) + Vector3(9.0, 1.0, 9.0)
	camera.look_at(Vector3(base) + Vector3(4.0, -5.0, 1.5))


var _liquid_views := {}


## Frames the nearest pool of a liquid type (1 water, 2 lava), with a torch for light.
func _view_liquid(t: int) -> void:
	if not _liquid_views.has(t):
		_liquid_views[t] = _find_liquid(t)
	var target: Vector3 = _liquid_views[t]
	camera.global_position = target + Vector3(3.5, 3.0, 4.5)
	camera.look_at(target)


func _find_liquid(t: int) -> Vector3:
	var s := Vector3(world.get_spawn())
	for r in range(0, 200, 4):
		for a in 24:
			var x := int(s.x + cos(a * TAU / 24) * r)
			var z := int(s.z + sin(a * TAU / 24) * r)
			for y in range(int(s.y) + 10, 2, -1):
				var l := world.get_liquid(Vector3i(x, y, z))
				if l.x == t and l.y > 0 and world.get_liquid(Vector3i(x, y + 1, z)).y == 0 and not world.is_solid(Vector3i(x, y + 1, z)):
					# Clear a viewing pocket and light it.
					for dx in range(0, 6):
						for dy in range(1, 6):
							for dz in range(0, 7):
								var c := Vector3i(x + dx, y + dy, z + dz)
								if world.get_liquid(c).y == 0:
									world.set_block(c, 0)
					world.set_block(Vector3i(x + 3, y + 1, z + 4), Data.block_id("torch"))
					print("  found liquid %d at %s" % [t, Vector3i(x, y, z)])
					return Vector3(x + 0.5, y + 0.5, z + 0.5)
	return s


## Looks straight at the sun (midday), optionally with a stone wall built in between.
func _aim_at_sun(walled: bool) -> void:
	var s := Vector3(world.get_spawn()) + Vector3(0.5, 40.0, 0.5)
	camera.global_position = s
	var sun_dir := sky.sun_direction()
	camera.look_at(camera.global_position + sun_dir)
	if walled and _built != "sun_wall":
		_built = "sun_wall"
		var c := Vector3i((s + sun_dir * 7.0).floor())
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				for dz in range(-2, 3):
					world.set_block(c + Vector3i(dx, dy, dz), Data.block_id("stone"))
	elif not walled and _built != "sun_open":
		_built = "sun_open"
		var c := Vector3i((s + sun_dir * 7.0).floor())
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				for dz in range(-2, 3):
					world.set_block(c + Vector3i(dx, dy, dz), 0)


## Finds an open cave spot in the cavern layer with a torch placed nearby.
func _find_cave(s: Vector3, y_hint: int) -> Vector3:
	for r in range(0, 120, 3):
		for a in 16:
			var x := int(s.x + cos(a * TAU / 16) * r)
			var z := int(s.z + sin(a * TAU / 16) * r)
			for y in range(y_hint, y_hint - 40, -1):
				if world.get_block(Vector3i(x, y, z)) == 0 and world.get_block(Vector3i(x, y + 1, z)) == 0 \
						and world.get_block(Vector3i(x, y + 2, z)) == 0 and world.is_solid(Vector3i(x, y - 1, z)):
					world.set_block(Vector3i(x, y, z), Data.block_id("torch"))
					return Vector3(x + 2.5, y + 1.5, z + 2.5)
	return s
