class_name NPCRenders
## Pre-rendered sprites (the NPC picker's "rendered" method), as Fallout 1 did:
## an NPC's voxel model shot from every angle (YAWS round it, at each of
## PITCHES up and down; one shot straight above and below), every frame,
## each shrunk to the sprite's own pixel size (one pixel per art pixel), so
## it's drawn as a sprite again but turns in 3D. The model is its tuned one,
## else Claude's, else its hull. Shots are made off screen (a SubViewport per
## shot, a batch a frame), cached in user://rendered_npcs/ and made again when
## the model changes. Atlases hold premultiplied colour (the billboard shader's
## `unpremultiply`). A headless run can't render: there it stays the sheet.

const YAWS := 16
const PITCHES := [-90.0, -60.0, -30.0, 0.0, 30.0, 60.0, 90.0]
## Each shot is rendered this many times bigger, then shrunk (smoothly).
const SUPERSAMPLE := 4
const BATCH := 24
const DIR := "user://rendered_npcs/"
const VERSION := 1

## kind -> {n: pixels square, px: metres per pixel, center: the model's middle
## (its mesh space), atlases: an ImageTexture per frame (YAWS x PITCHES shots)}
static var _done := {}
static var _baking := {}
static var _baker: Node


## The model an NPC's renders are made from.
static func source(kind: String) -> String:
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
		if _baker == null or not is_instance_valid(_baker):
			_baker = Node.new()
			_baker.name = "NPCRenderBaker"
			(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_baker)
		_bake.call_deferred(kind)
	return {}


static func forget(kind := "") -> void:
	if kind == "":
		_done.clear()
	else:
		_done.erase(kind)


# ------------------------------------------------------------ views

## The direction a shot looks from (toward the model's middle), model space:
## column round from the front (+z), row up from straight below.
static func view_dir(col: int, row: int) -> Vector3:
	var p := deg_to_rad(PITCHES[row])
	var y := TAU * col / YAWS
	return Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)).normalized()


## The shot's "up" (model space): the model's up, or (straight above or
## below) its back / front.
static func view_up(col: int, row: int) -> Vector3:
	var p: float = PITCHES[row]
	var up := Vector3.UP
	if absf(p) > 89.0:
		up = Vector3(0, 0, -1) if p > 0 else Vector3(0, 0, 1)
	var d := view_dir(col, row)
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
	var baker := _baker
	while not baker.is_inside_tree():
		await (Engine.get_main_loop() as SceneTree).process_frame
	var src := source(kind)
	var fr := NPCModels.frames_of(kind)
	var nf: int = fr.arts.size()
	var apx: float = fr.apx
	NPCModels.prebuild(kind, src)
	var meshes: Array = []
	var box := AABB()
	var sig := [VERSION, src, YAWS, PITCHES, SUPERSAMPLE]
	for f in nf:
		var built: Dictionary = NPCModels.mesh(kind, src, f)
		meshes.append(built)
		var m: ArrayMesh = built.mesh
		if m.get_surface_count() == 0:
			continue
		box = m.get_aabb() if box.size == Vector3.ZERO else box.merge(m.get_aabb())
		sig.append(hash(m.surface_get_arrays(0)))
	var center := box.get_center()
	var n := ceili(box.size.length() / apx) + 2
	var tag := "%s_%x" % [kind, hash(sig)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var atlases: Array[Image] = []
	var cached := true
	for f in nf:
		var p := DIR + "%s_%d.png" % [tag, f]
		if FileAccess.file_exists(p):
			atlases.append(Image.load_from_file(ProjectSettings.globalize_path(p)))
		else:
			cached = false
			break
	if not cached:
		atlases.clear()
		for f in nf:
			atlases.append(Image.create(YAWS * n, PITCHES.size() * n, false, Image.FORMAT_RGBA8))
		var jobs := []
		for f in nf:
			for row in PITCHES.size():
				for col in (1 if absf(PITCHES[row]) > 89.0 else YAWS):
					jobs.append([f, col, row])
		while not jobs.is_empty():
			var batch := []
			for i in mini(BATCH, jobs.size()):
				var job: Array = jobs.pop_front()
				var built: Dictionary = meshes[job[0]]
				batch.append([job, _shot(baker, built.mesh, NPCModels.material(kind, job[0], built.textured), center, n, apx, job[1], job[2])])
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
				# Opaque voxels on a clear background: shrunk, the edges come out
				# premultiplied (colour times cover), which the sprite's shader
				# undoes, so they don't darken.
				img.resize(n, n, Image.INTERPOLATE_TRILINEAR)
				atlases[job[0]].blit_rect(img, Rect2i(0, 0, n, n), Vector2i(job[1] * n, job[2] * n))
		# Drop renders of older versions of the model.
		for file in DirAccess.get_files_at(DIR):
			if file.begins_with(kind + "_") and not file.begins_with(tag + "_"):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + file))
		for f in nf:
			atlases[f].save_png(ProjectSettings.globalize_path(DIR + "%s_%d.png" % [tag, f]))
	var textures: Array[ImageTexture] = []
	for img in atlases:
		textures.append(ImageTexture.create_from_image(img))
	_done[kind] = {"n": n, "px": apx, "center": center, "atlases": textures}
	_baking.erase(kind)


## One shot of the model, set up off screen (rendered when the batch asks).
static func _shot(parent: Node, mesh: ArrayMesh, mat: Material, center: Vector3, n: int, apx: float, col: int, row: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(n, n) * SUPERSAMPLE
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED  # not before the camera is placed
	vp.msaa_3d = Viewport.MSAA_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.set_instance_shader_parameter("light", Color(1, 1, 1, 1))
	vp.add_child(mi)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = n * apx
	cam.near = 0.01
	cam.far = n * apx * 4.0
	vp.add_child(cam)
	parent.add_child(vp)
	var d := view_dir(col, row)
	cam.look_at_from_position(center + d * n * apx * 2.0, center, view_up(col, row))
	cam.current = true
	return vp
