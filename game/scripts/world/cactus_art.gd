class_name CactusArt
## Cacti, drawn like Terraria's: one flat sprite facing you, a trunk with an
## arm or two, put together from Tiles_80's pieces (16 x 16, 18 apart):
##   column 0 trunk, 1 trunk with a joint on its right, 4 on its left, 5 both;
##   row 0 the trunk's top, rows 1-2 the rest (joint columns: row 2 has the
##   joint, row 1 is plain);
##   column 2 the right arm, column 3 the left: row 0 its tip, 1 its middle,
##   2 its elbow (beside the trunk's joint, curving into it);
##   rows 3-5, 6-8, 9-11: the same in Corruption, Hallow and Crimson colours.
## A cactus in the world is a column of "cactus" cells (walk-through, for
## aiming at, mining and chopping); its base cell draws the whole sprite
## (BlockModels). Its arms come from the column's height and position, so
## nothing else is saved. The art goes through SpriteFx ("cactus" settings,
## edited in the sprite editor).

const SHEET := "Images/Tiles_80"
## Art pixels per block (Terraria's 16 px tiles are 2x art).
const ART := 8
## Colour sets: rows of three in the sheet.
const COLORS := {"": 0, "corruption": 1, "hallow": 2, "crimson": 3}

static var _cache := {}  # shape code -> {image, k, px, margin, material, mesh}


## The shape of a cactus `height` cells tall standing at `base`: {height,
## left: [elbow row, tip row] or [], right: same, color}. Rows count up from
## the base (0); arms start at row 1 or higher and end at or below the top.
static func shape(base: Vector3i, height: int, color := 0) -> Dictionary:
	var s := {"height": height, "left": [], "right": [], "color": color}
	if height < 3:
		return s
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(base)
	for side in ["left", "right"]:
		if rng.randf() < 0.65:
			var elbow := rng.randi_range(1, height - 2)
			var tip := rng.randi_range(elbow + 1, height - 1)
			s[side] = [elbow, tip]
	return s


## A whole number for a shape (cache key).
static func code(s: Dictionary) -> int:
	var c: int = s.height | (s.color << 5)
	if not s.left.is_empty():
		c |= (s.left[0] << 8) | (s.left[1] << 12)
	if not s.right.is_empty():
		c |= (s.right[0] << 16) | (s.right[1] << 20)
	return c


## Cells of cactus in a shape: the trunk and both arms (what felling drops).
static func pieces(s: Dictionary) -> int:
	var n: int = s.height
	for side in ["left", "right"]:
		if not s[side].is_empty():
			n += s[side][1] - s[side][0] + 1
	return n


## The shape at art resolution: three tiles wide (left arm, trunk, right arm)
## and `height` tiles tall.
static func compose(s: Dictionary) -> Image:
	var sheet: Image = Assets.image(SHEET)
	var h: int = s.height
	var img := Image.create(48, h * 16, false, Image.FORMAT_RGBA8)
	var oy: int = int(s.color) * 54
	for r in h:
		var y := (h - 1 - r) * 16
		var joint_l: bool = not s.left.is_empty() and s.left[0] == r
		var joint_r: bool = not s.right.is_empty() and s.right[0] == r
		var col := 5 if joint_l and joint_r else (4 if joint_l else (1 if joint_r else 0))
		# (In the joint columns only rows 0 and 2 have the stub; row 1 is plain.)
		var row := 0 if r == h - 1 else (2 if joint_l or joint_r else 1 + (r % 2))
		_blit(img, sheet, col, row, oy, Vector2i(16, y))
		for side in ["left", "right"]:
			var arm: Array = s[side]
			if arm.is_empty() or r < arm[0] or r > arm[1]:
				continue
			var arow := 2 if r == arm[0] else (0 if r == arm[1] else 1)
			_blit(img, sheet, 3 if side == "left" else 2, arow, oy, Vector2i(0 if side == "left" else 32, y))
	return PixelArt.downsample(img, Vector3i(2, 0, 0))


static func _blit(img: Image, sheet: Image, col: int, row: int, oy: int, at: Vector2i) -> void:
	img.blend_rect(sheet, Rect2i(col * 18, oy + row * 18, 16, 16), at)


## A shape processed with `o` (default: the saved "cactus" settings): {image,
## k (output pixels per art pixel), px (world size of an output pixel),
## margin (output pixels the effects added round the art)}.
static func build(s: Dictionary, o := {}) -> Dictionary:
	if o.is_empty():
		o = SpriteFx.options("cactus")
	var art := compose(s)
	var r := SpriteFx.process(art, o, code(s) % 9973)
	r["px"] = 1.0 / (ART * r.k)
	r["margin"] = Vector2((r.image.get_width() - art.get_width() * r.k) * 0.5, (r.image.get_height() - art.get_height() * r.k) * 0.5)
	return r


## The cached sprite, quad and material for a shape (BlockModels' batches).
static func get_art(s: Dictionary) -> Dictionary:
	var c := code(s)
	if not _cache.has(c):
		var b := build(s)
		var w: float = b.image.get_width() * b.px
		var h: float = b.image.get_height() * b.px
		var bottom: float = -b.margin.y * b.px
		b["mesh"] = quad(w, h, bottom)
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/block_model_batched.gdshader")
		m.set_shader_parameter("sprite", ImageTexture.create_from_image(b.image))
		m.set_shader_parameter("art_scale", PixelArt.detect_scale(b.image).x)
		m.set_shader_parameter("textured", true)
		m.set_shader_parameter("billboard", true)
		b["material"] = m
		_cache[c] = b
	return _cache[c]


## Forgets the built sprites (after the sprite settings change).
static func clear_cache() -> void:
	_cache.clear()


## The built materials (BlockModels gives them the sky's light as it changes).
static func materials() -> Array:
	return _cache.values().map(func(b): return b.material)


## A `w` x `h` quad standing on its bottom edge (at `bottom`), centred on the
## origin: the billboard shader turns it to face you.
static func quad(w: float, h: float, bottom: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(-w * 0.5, bottom), Vector2(w * 0.5, bottom), Vector2(w * 0.5, bottom + h), Vector2(-w * 0.5, bottom + h)]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_color(Color.WHITE)
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(uvs[i])
		st.add_vertex(Vector3(corners[i].x, corners[i].y, 0.0))
	return st.commit()


## The cactus column through `p`: [base, height] (height 0 if `p` isn't cactus).
static func column(world: VoxelWorld, p: Vector3i) -> Array:
	if not Data.block(world.get_block(p)).get("cactus", false):
		return [p, 0]
	var base := p
	while Data.block(world.get_block(base + Vector3i.DOWN)).get("cactus", false):
		base += Vector3i.DOWN
	var h := 1
	while Data.block(world.get_block(base + Vector3i.UP * h)).get("cactus", false):
		h += 1
	return [base, h]


## The colour set for a cactus on this ground (ebonsand: Corruption...).
static func color_for(ground: Dictionary) -> int:
	return COLORS.get(String(ground.get("biome", "")), 0) if String(ground.get("biome", "")) in COLORS else 0
