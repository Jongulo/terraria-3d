class_name TreeBranches
## Branches on tree trunks, like Terraria's (WorldGen.GrowTree): going up the
## trunk, each cell but the bottom and top one rolls 1 in 10 for a branch on
## its left, on its right or both, never the same side twice in a row; a branch
## is one of three frames, leafy two times in three (Tree_Branches_N, N being
## the tree top's sheet, so a tree's branches match its canopy), otherwise a
## bare stub from the trunk's own sheet (Tiles_5...). Terraria draws a leafy
## branch 40 px long from the trunk's edge, centred on the trunk tile; a stub
## fills the tile beside the trunk.
## In 3D a tree's left and right are two opposite ways round it (each branch
## turned a little), and a branch is a fixed upright card sticking out of the
## trunk: not a billboard, so it doesn't swing round as you walk by (from the
## other side you see its back, mirrored, as you would). Everything comes from
## the trunk column and its canopy, so nothing is saved; felling the tree takes
## them with it. Palms have none. BlockModels draws them; the leafy ones go
## through SpriteFx with the canopy's settings (no warp), the stubs with the
## trunk's.

## Terraria's leafy branch frame (texture pixels; 40 px is 2.5 blocks).
const LEAFY_PX := 40
## Art pixels per block (Terraria's 16 px tiles are 2x art).
const ART := 8
## How far a branch may turn from its side's way (radians).
const JITTER := 0.5
## Where the stem starts, from the trunk's axis: one art pixel inside its
## edge, over the trunk's dark outline (Terraria opens the outline there with
## branch-joint trunk frames; a trunk that turns to face you can't, so the
## stem covers it), and drawn a little nearer so it stays on top.
const STEM_START := 0.5 - 1.0 / ART
const NEARER := 0.03

static var _cache := {}  # art key -> {mesh, material}


## A trunk column through `p` (cells of one non-palm trunk block):
## [base, height] (height 0 if `p` isn't such a trunk).
static func column(world: VoxelWorld, p: Vector3i) -> Array:
	var id := world.get_block(p)
	var d := Data.block(id)
	if not d.get("trunk", false) or d.get("palm", false) or not d.get("branches", true):
		return [p, 0]
	var base := p
	while world.get_block(base + Vector3i.DOWN) == id:
		base += Vector3i.DOWN
	var h := 1
	while world.get_block(base + Vector3i.UP * h) == id:
		h += 1
	return [base, h]


## The branches of a trunk `height` cells tall at `base`: [{cell (0 = the
## base), dir (outward, horizontal unit vector), variant (0-2), leafy, left
## (Terraria's side: which art)}].
static func branches(base: Vector3i, height: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(base) ^ 0x6b7a4c3
	var yaw := rng.randf() * TAU
	var out := []
	var had_left := false
	var had_right := false
	for k in height:
		var roll := rng.randi_range(0, 9)
		if k == 0 or k == height - 1:
			roll = 0
		while ((roll == 5 or roll == 7) and had_left) or ((roll == 6 or roll == 7) and had_right):
			roll = rng.randi_range(0, 9)
		had_left = roll == 5 or roll == 7
		had_right = roll == 6 or roll == 7
		for left in [true, false]:
			if (left and had_left) or (not left and had_right):
				var a := yaw + (PI if left else 0.0) + rng.randf_range(-JITTER, JITTER)
				var variant := rng.randi_range(0, 2)
				out.append({"cell": k, "dir": Vector3(cos(a), 0.0, sin(a)), "variant": variant,
						"leafy": rng.randi_range(0, 2) < 2, "left": left})
	return out


## The branch sheet for a canopy style (Tree_Tops_N -> Tree_Branches_N).
static func sheet_for(canopy_style: int) -> String:
	var k := clampi(canopy_style / 10, 0, CanopyArt.SHEETS.size() - 1)
	return String(CanopyArt.SHEETS[k]).replace("Tree_Tops_", "Tree_Branches_")


## One branch's art at art resolution, its stem on the left (the trunk end):
## a leafy frame of `sheet`, or a bare stub from `trunk_sheet`.
static func art(sheet: String, trunk_sheet: String, b: Dictionary) -> Image:
	var img: Image
	if b.leafy:
		var src: Image = Assets.image("Images/" + sheet)
		img = src.get_region(Rect2i(0 if b.left else 42, int(b.variant) * 42, LEAFY_PX, LEAFY_PX))
	else:
		# Tiles_5: left stubs at x 66 (rows 0-2), right ones at x 88 (rows 3-5);
		# like the trunk's, their 16 px sit 2 px into each 20 px frame.
		var src: Image = Assets.image("Images/" + trunk_sheet)
		img = src.get_region(Rect2i((66 if b.left else 88) + 2, (int(b.variant) + (0 if b.left else 3)) * 22, 16, 16))
	if b.left:
		img.flip_x()
	return PixelArt.downsample(img, Vector3i(2, 0, 0))


## The card's mesh and material for a branch (cached per look): the card
## stands on the trunk's edge and reaches out along +x, centred on its cell.
## (Guarded by BlockModelMesh.lock: BlockModels builds them on workers too.)
static func get_art(sheet: String, trunk_sheet: String, b: Dictionary) -> Dictionary:
	var key := art_key(sheet, trunk_sheet, b)
	BlockModelMesh.lock.lock()
	var hit = _cache.get(key)
	BlockModelMesh.lock.unlock()
	if hit == null:
		var built := build(sheet, trunk_sheet, b)
		var img: Image = built.image
		var w: float = img.get_width() * built.px
		var h: float = img.get_height() * built.px
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/block_model_batched.gdshader")
		m.set_shader_parameter("sprite", ImageTexture.create_from_image(img))
		m.set_shader_parameter("art_scale", PixelArt.detect_scale(img).x)
		m.set_shader_parameter("textured", true)
		m.set_shader_parameter("toward_camera", NEARER)
		hit = {"mesh": card(w, h), "material": m, "size": Vector2(w, h)}
		BlockModelMesh.lock.lock()
		_cache[key] = hit
		BlockModelMesh.lock.unlock()
	return hit


## A branch card's cache key: a leafy one's look is its canopy sheet's, a
## bare stub's its trunk's.
static func art_key(sheet: String, trunk_sheet: String, b: Dictionary) -> String:
	return "%s:%d:%s:%s" % [sheet if b.leafy else trunk_sheet, b.variant, b.leafy, b.left]


## Whether a branch's card is built yet (get_art).
static func has_art(sheet: String, trunk_sheet: String, b: Dictionary) -> bool:
	BlockModelMesh.lock.lock()
	var built := _cache.has(art_key(sheet, trunk_sheet, b))
	BlockModelMesh.lock.unlock()
	return built


## A branch processed for drawing: {image (stem on the left), px (world size
## of a pixel)}. Leafy ones get the canopy's settings without the warp (the
## stem must stay on the trunk), stubs the trunk's (default: the saved ones).
static func build(sheet: String, trunk_sheet: String, b: Dictionary, canopy_o := {}, trunk_o := {}) -> Dictionary:
	var o: Dictionary
	if b.leafy:
		o = (canopy_o if not canopy_o.is_empty() else SpriteFx.options("tree_canopy")).duplicate()
		o.warp = 0.0
	else:
		o = trunk_o if not trunk_o.is_empty() else SpriteFx.options("tree_trunk")
	var r := SpriteFx.process(art(sheet, trunk_sheet, b), o, int(b.variant), not b.leafy)
	return {"image": r.image, "px": 1.0 / (ART * r.k)}


## Forgets the built cards (after the sprite settings change).
static func clear_cache() -> void:
	BlockModelMesh.lock.lock()
	_cache.clear()
	BlockModelMesh.lock.unlock()


## The built materials (BlockModels gives them the sky's light as it changes).
static func materials() -> Array:
	BlockModelMesh.lock.lock()
	var built := _cache.values()
	BlockModelMesh.lock.unlock()
	return built.map(func(b): return b.material)


## A `w` x `h` quad from x = 0 out to w, centred on y = 0, in the xy plane.
static func card(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0, -h * 0.5), Vector2(w, -h * 0.5), Vector2(w, h * 0.5), Vector2(0, h * 0.5)]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_color(Color.WHITE)
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(uvs[i])
		st.add_vertex(Vector3(corners[i].x, corners[i].y, 0.0))
	return st.commit()


## Where a branch's card goes: from just inside the trunk's edge
## (STEM_START) at the middle of its cell, reaching out along `dir`.
static func transform(base: Vector3i, b: Dictionary) -> Transform3D:
	var x: Vector3 = b.dir
	var basis := Basis(x, Vector3.UP, x.cross(Vector3.UP))
	return Transform3D(basis, Vector3(base) + Vector3(0.5, b.cell + 0.5, 0.5) + x * STEM_START)
