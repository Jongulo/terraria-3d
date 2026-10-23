class_name NPCRenders
## Pre-rendered sprites (the NPC picker's "rendered" method), as Fallout 1 did:
## an NPC's voxel model shot from every angle (YAWS round it, at each of
## PITCHES up and down; one shot straight above and below), every frame,
## each shrunk to the sprite's own pixel size (one pixel per art pixel), so
## it's drawn as a sprite again but turns in 3D. The model is its tuned one,
## else Claude's, else its hull, or the Extruded one if chosen (source()). Shots are made off screen (a SubViewport per
## shot, a batch a frame), cached in user://rendered_npcs/ and made again when
## the model changes. Each shot is lined up so the model's voxels fall on whole
## sprite pixels (seen straight on, its pixels are the art's), and shrunk by
## majority (VoxelWorld.shrink_majority: each pixel the colour covering most
## of it, opaque only if mostly covered), so it stays crisp pixel art instead
## of blurring. Atlases hold premultiplied colour (the billboard shader's
## `unpremultiply`; with crisp edges it's the plain colour). A headless run
## can't render: there it stays the sheet.

## Shots round the model (every 11.25 degrees) and the heights they're taken
## at (every 15 degrees, straight below to straight above; evenly spaced:
## rendered_batched.gdshader picks a row by rounding).
const YAWS := 32
const PITCHES := [-90.0, -75.0, -60.0, -45.0, -30.0, -15.0, 0.0, 15.0, 30.0, 45.0, 60.0, 75.0, 90.0]
## Each shot is rendered this many times bigger, then shrunk by majority.
const SUPERSAMPLE := 4
const BATCH := 24
const DIR := "user://rendered_npcs/"
const VERSION := 2
## The "outline" setting's ring round every shot: its edge colours times this
## (Terraria's outlines are its colours, much darker: a skull's bone at a fifth).
const OUTLINE_SHADE := 0.25
## Where renders are cached (DIR; tests point it elsewhere).
static var dir := DIR

## kind -> bake_shots' result ({n, px, center, radius, atlases})
static var _done := {}
static var _baking := {}
## Kinds forgotten while their shots were being made: that bake is dropped.
static var _stale := {}
static var _baker: Node


## The model an NPC's renders are made from: the Extruded one if its rendered
## setting says so, else its tuned model, else Claude's, else its hull.
static func source(kind: String) -> String:
	if NPCModels.options(kind, "rendered").model == "extruded":
		return "extruded"
	if TunedModels.has(TunedModels.npc_key(kind)):
		return "tuned"
	if NPCSculpt.has(kind):
		return "claude"
	return "hull"


static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


## Its renders, or {} while they're being made (or can't be).
static func renders(kind: String) -> Dictionary:
	if _done.has(kind):
		return _done[kind]
	if not _baking.has(kind) and can_render():
		_baking[kind] = true
		_bake.call_deferred(kind)
	return {}


static func forget(kind := "") -> void:
	for k in _baking:
		if kind == "" or k == kind:
			_stale[k] = true
	if kind == "":
		_done.clear()
	else:
		_done.erase(kind)


# ------------------------------------------------------------ views

## The direction a shot looks from (toward the model's middle), model space:
## column round from the front (+z), row up from straight below. `yaws` and
## `pitches`: the set of shots (NPCs' by default; placeables have their own).
static func view_dir(col: int, row: int, yaws := YAWS, pitches := PITCHES) -> Vector3:
	var p := deg_to_rad(pitches[row])
	var y := TAU * col / yaws
	return Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)).normalized()


## The shot's "up" (model space): the model's up, or (straight above or
## below) its back / front.
static func view_up(col: int, row: int, yaws := YAWS, pitches := PITCHES) -> Vector3:
	var p: float = pitches[row]
	var up := Vector3.UP
	if absf(p) > 89.0:
		up = Vector3(0, 0, -1) if p > 0 else Vector3(0, 0, 1)
	var d := view_dir(col, row, yaws, pitches)
	return (up - d * up.dot(d)).normalized()


## The shot nearest a direction toward the camera (model space): (col, row).
static func pick(d: Vector3) -> Vector2i:
	d = d.normalized()
	var pitch := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
	var row := 0
	for i in PITCHES.size():
		if absf(PITCHES[i] - pitch) < absf(PITCHES[row] - pitch):
			row = i
	if absf(PITCHES[row]) > 89.0:
		return Vector2i(0, row)
	return Vector2i(posmod(roundi(atan2(d.x, d.z) / (TAU / YAWS)), YAWS), row)


## How far to turn the sprite in the screen plane so the shot's up lies along
## `world_up` as the camera sees it.
static func roll(world_up: Vector3, camera_basis: Basis) -> float:
	var ux := world_up.dot(camera_basis.x)
	var uy := world_up.dot(camera_basis.y)
	return atan2(-ux, uy)


# ------------------------------------------------------------ baking

static func _bake(kind: String) -> void:
	var src := source(kind)
	var fr := NPCModels.frames_of(kind)
	NPCModels.prebuild(kind, src)
	var meshes: Array = []
	for f in fr.arts.size():
		meshes.append(NPCModels.mesh(kind, src, f))
	var done := await bake_shots(kind, meshes, func(f: int, textured: bool): return NPCModels.material(kind, f, textured), fr.apx, [src],
			YAWS, PITCHES, NPCModels.options(kind, "rendered").outline)
	_baking.erase(kind)
	if _stale.has(kind):
		# Its model changed meanwhile: the next renders() shoots it again.
		_stale.erase(kind)
		return
	_done[kind] = done


## Shoots `meshes` (one {mesh, textured} per frame, drawn with
## `material.call(frame, textured)`) from every angle at `apx` metres a pixel,
## or loads the shots cached under `key` (`sig` and the meshes themselves pick
## the version): {n: pixels square, px, center: the model's middle (mesh
## space), radius: how far the model reaches from it, yaws and pitches (the
## shots: `yaws` round at each of `pitches`), atlases: an ImageTexture per
## frame (yaws x pitches shots)}. With `outline` each shot gets a one-pixel
## dark outline round it (OUTLINE_SHADE), as Terraria's sprites have, after
## it's shrunk: an outline of the view, not of the sprite it was built from.
## Can only run where things render (can_render()).
static func bake_shots(key: String, meshes: Array, material: Callable, apx: float, sig_extra := [],
		yaws := YAWS, pitches := PITCHES, outline := false) -> Dictionary:
	if _baker == null or not is_instance_valid(_baker):
		_baker = Node.new()
		_baker.name = "NPCRenderBaker"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_baker)
	var baker := _baker
	while not baker.is_inside_tree():
		await (Engine.get_main_loop() as SceneTree).process_frame
	var nf := meshes.size()
	var box := AABB()
	var sig := [VERSION, yaws, pitches, SUPERSAMPLE] + sig_extra
	if outline:
		sig.append(["outline", OUTLINE_SHADE])
	for built in meshes:
		var m: ArrayMesh = built.mesh
		if m.get_surface_count() == 0:
			continue
		box = m.get_aabb() if box.size == Vector3.ZERO else box.merge(m.get_aabb())
		sig.append(hash(m.surface_get_arrays(0)))
	var n := ceili(box.size.length() / apx) + 2
	# The shot's middle, moved (less than a pixel) so its edges are on the
	# voxel grid: straight on, each sprite pixel is one of the model's voxels.
	var half := Vector3.ONE * (n * apx * 0.5)
	var center := box.position + ((box.get_center() - half - box.position) / apx).round() * apx + half
	var tag := "%s_%x" % [key, hash(sig)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var atlases: Array[Image] = []
	var cached := true
	for f in nf:
		var p := dir + "%s_%d.png" % [tag, f]
		if FileAccess.file_exists(p):
			atlases.append(Image.load_from_file(ProjectSettings.globalize_path(p)))
		else:
			cached = false
			break
	if not cached:
		atlases.clear()
		for f in nf:
			atlases.append(Image.create(yaws * n, pitches.size() * n, false, Image.FORMAT_RGBA8))
		var jobs := []
		for f in nf:
			for row in pitches.size():
				for col in (1 if absf(pitches[row]) > 89.0 else yaws):
					jobs.append([f, col, row])
		while not jobs.is_empty():
			var batch := []
			for i in mini(BATCH, jobs.size()):
				var job: Array = jobs.pop_front()
				var built: Dictionary = meshes[job[0]]
				batch.append([job, _shot(baker, built.mesh, material.call(job[0], built.textured), center, n, apx,
						view_dir(job[1], job[2], yaws, pitches), view_up(job[1], job[2], yaws, pitches))])
			# Rendered once everything's in place (the first frame after they
			# join the tree), then read back once that's drawn.
			await (Engine.get_main_loop() as SceneTree).process_frame
			for b in batch:
				(b[1] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			for b in batch:
				var job: Array = b[0]
				var vp: SubViewport = b[1]
				var img := vp.get_texture().get_image()
				vp.queue_free()
				img.convert(Image.FORMAT_RGBA8)
				img = Image.create_from_data(n, n, false, Image.FORMAT_RGBA8,
						VoxelWorld.shrink_majority(img.get_data(), img.get_width(), img.get_height(), SUPERSAMPLE))
				if outline:
					img = Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, VoxelWorld.outline_rgba(img.get_data(), n, n, OUTLINE_SHADE))
				atlases[job[0]].blit_rect(img, Rect2i(0, 0, n, n), Vector2i(job[1] * n, job[2] * n))
		# Drop renders of older versions of the model (its own files only:
		# "<key>_<hex>_<frame>.png", not another key that starts the same).
		for file in DirAccess.get_files_at(dir):
			if _version_of(file, key) and not file.begins_with(tag + "_"):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + file))
		for f in nf:
			atlases[f].save_png(ProjectSettings.globalize_path(dir + "%s_%d.png" % [tag, f]))
	var textures: Array[ImageTexture] = []
	for img in atlases:
		textures.append(ImageTexture.create_from_image(img))
	var radius := box.size.length() * 0.5 + center.distance_to(box.get_center())
	return {"n": n, "px": apx, "center": center, "radius": radius, "yaws": yaws, "pitches": pitches, "atlases": textures}


## Whether `file` is a cached shot of `key` ("<key>_<hex>_<frame>.png").
static func _version_of(file: String, key: String) -> bool:
	if not file.begins_with(key + "_") or not file.ends_with(".png"):
		return false
	var parts := file.substr(key.length() + 1).trim_suffix(".png").split("_")
	return parts.size() == 2 and parts[0].is_valid_hex_number() and parts[1].is_valid_int()


## The material as drawn with the sun's shadows off: the shot has no sun,
## and with the shadows on the shaders leave the light to it (the renders came
## out black). A copy, so the game's own material keeps its shadows.
static var _sunless := {}


static func _without_sun(mat: Material) -> Material:
	if not mat is ShaderMaterial:
		return mat
	var id := mat.get_instance_id()
	if not _sunless.has(id) or not is_instance_valid(_sunless[id]):
		var m: ShaderMaterial = mat.duplicate()
		m.set_shader_parameter("no_sun_shadows", true)
		_sunless[id] = m
	return _sunless[id]


## One shot of the model, set up off screen (rendered when the batch asks).
static func _shot(parent: Node, mesh: ArrayMesh, mat: Material, center: Vector3, n: int, apx: float, d: Vector3, up: Vector3) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(n, n) * SUPERSAMPLE
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED  # not before the camera is placed
	vp.msaa_3d = Viewport.MSAA_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _without_sun(mat)
	mi.set_instance_shader_parameter("entity_light", Color(1, 1, 1, 1))
	vp.add_child(mi)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = n * apx
	cam.near = 0.01
	cam.far = n * apx * 4.0
	vp.add_child(cam)
	parent.add_child(vp)
	cam.look_at_from_position(center + d * n * apx * 2.0, center, up)
	cam.current = true
	return vp
