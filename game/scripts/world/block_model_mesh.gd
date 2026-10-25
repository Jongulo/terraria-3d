class_name BlockModelMesh
## Builds a placeable block's mesh for each placeable method, from its Terraria
## sprite. Meshes are in metres, centred on the block's vertical axis (x = z = 0)
## with the bottom at y = 0 and the front facing +z.
##
##   panels    the sprite on the four sides of the block
##   cross     two crossed planes
##   billboard a camera-facing sprite (built by BlockModels; here: a plain quad)
##   flat      the sprite extruded one pixel thick, standing in the middle
##   extruded  the sprite pushed through the block (cookie cutter); its sides
##             take the colour just inside the sprite's dark outline, split into
##             voxel cells along the depth with optional pixelated noise, and its
##             edges can be bevelled (Data.extrude_options: depth, noise,
##             strength, seed, bevel, bevel_size)
##   hull      carved from the front and side silhouettes (the sprite seen from both);
##             tops and bottoms take the colour just inside the dark outline;
##             optional pixel noise on its sides, tops and bottoms
##   lathe     (below) optional pixel noise over its whole surface
##   lathe     the right half of the outline spun around the vertical axis
##   claude    a voxel model made by hand for the block (data/handmade_models.json);
##             its front view is the sprite. Blocks without one show the hull.
##   tuned     a voxel model sculpted in the model sculptor (TunedModels,
##             data/tuned/); blocks without one show the hull.
##   rendered  shots of a model from every angle (PlaceableRenders; BlockModels
##             draws them): here, the model they're of.
## Every voxel method has a "one colour per voxel" setting (one_color): each
## voxel's faces all take one colour (TunedModels.one_color_mesh). Extruded,
## hull, hull_top and lathe can cut the sprite's dark outline away first
## (no_outline; Data.OUTLINE_METHODS).

## Where an extruded model's bevel goes (Data.extrude_options "bevel_sides"):
## which edges of the silhouette, and the front and/or back face.
const BEVEL_SIDES := ["top", "bottom", "left", "right", "front", "back"]
const SHADES := {"front": 1.0, "top": 0.9, "side": 0.72, "bottom": 0.55}
## voxel_mesh's faces, in its order.
const FACE_FRONT := 0
const FACE_BACK := 1
const FACE_UP := 4
const FACE_DOWN := 5
## Voxel models are built at the sprite's art resolution (PixelArt): one voxel
## per pixel of the original art. Noise patches and bevel steps are measured in
## those voxels: NOISE_CELL x NOISE_CELL per noise value, BEVEL_CELL per step.
const NOISE_CELL := 1
const BEVEL_CELL := 1

static var _cache := {}


## Forgets built meshes (after sprites were rebuilt).
## A voxel face's corners' UVs (in the order of its quad's corners): the
## voxel meshes are untextured, so these only tell the shader where in the
## face it is (it looks up the sun's shadow at the face's middle).
const FACE_UVS := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]


static func clear_cache() -> void:
	_cache.clear()


## {mesh: ArrayMesh, textured: bool}; `frame`: an animated block's frame.
static func build(block_id: int, method: String, frame := 0) -> Dictionary:
	var d := Data.block(block_id)
	# Settings come from the block itself, or from the one it shares them with
	# (the hidden tree canopy styles).
	var settings: String = d.get("settings", d.name)
	frame = clampi(frame, 0, Data.anim_frames(d) - 1)
	if method == "rendered":
		return build(block_id, PlaceableRenders.source(block_id), frame)
	var key := "%d:%s:%d" % [block_id, method, frame]
	if method in Data.NOISE_METHODS:
		key += JSON.stringify(Data.method_options(settings, method))
	if _cache.has(key):
		return _cache[key]
	var img: Image = d.anim_sprites[frame] if frame > 0 else d.sprite
	var px: float = d.sprite_px
	var w := img.get_width()
	var h := img.get_height()
	var sw := w * px
	var sh := h * px
	# Voxel methods work at art resolution.
	var art: Image = d.anim_arts[frame] if frame > 0 else d.get("art", img)
	if method in Data.OUTLINE_METHODS and Data.method_options(settings, method).no_outline:
		art = PixelArt.without_outline(art, true)
	var apx: float = d.get("art_px", px)
	var out := {}
	match method:
		"panels":
			out = {"mesh": _panels(sw, sh), "textured": true}
		"cross", "billboard":
			out = {"mesh": _cross(sw, sh, method == "billboard"), "textured": true}
		"flat":
			var m := ItemMesh.build(art, "block%d:%d" % [block_id, frame], 1.0)
			out = {"mesh": transformed(m, Transform3D(Basis().scaled(Vector3(apx, apx, apx)), Vector3(-sw * 0.5, 0, 0))), "textured": true}
		"extruded":
			out = {"mesh": _extrude(art, apx, Data.extrude_options(settings)), "textured": true}
		"claude":
			var spec: Dictionary = Data.handmade_models.get(settings, {})
			if spec.is_empty():
				return build(block_id, "hull", frame)
			out = {"mesh": _handmade(art, apx, spec, Data.method_options(settings, method), frame), "textured": false}
		"tuned":
			var tk := TunedModels.block_key(settings)
			if not TunedModels.has(tk):
				return build(block_id, "hull", frame)
			out = {"mesh": TunedModels.mesh(tk, frame, apx, Data.method_options(settings, method)), "textured": false}
		"hull", "hull_top", "lathe":
			# A side-view sprite (wall torch) has no axis to spin: always a hull.
			var side_view: bool = d.get("side_view", false)
			out = {"mesh": _voxels(art, apx, "hull" if side_view else method, Data.method_options(settings, method), side_view),
					"textured": false}
	if method != "tuned" and method in Data.NOISE_METHODS and Data.method_options(settings, method).one_color:
		out = {"mesh": TunedModels.one_color_mesh(out.mesh, out.textured, art, apx), "textured": false}
	_cache[key] = out
	return out


static func _quad(st: SurfaceTool, v: Array, uv: Array, shade: float) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(shade, shade, shade))
		st.set_uv(uv[i])
		st.add_vertex(v[i])


const _UV := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]


static func _panels(sw: float, sh: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := sw * 0.5
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var b := Basis(Vector3.UP, a)
		var v := [b * Vector3(-hw, 0, 0.5), b * Vector3(hw, 0, 0.5), b * Vector3(hw, sh, 0.5), b * Vector3(-hw, sh, 0.5)]
		_quad(st, v, _UV, 1.0 if a == 0.0 else 0.8)
	return st.commit()


static func _cross(sw: float, sh: float, single: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := sw * 0.5
	for a in ([0.0] if single else [PI * 0.25, PI * 0.75]):
		var b := Basis(Vector3.UP, a)
		_quad(st, [b * Vector3(-hw, 0, 0), b * Vector3(hw, 0, 0), b * Vector3(hw, sh, 0), b * Vector3(-hw, sh, 0)], _UV, 1.0)
	return st.commit()


## The sides a platform cell can link to the platform beside it, as bits of
## platform()'s `links`: +x, -x, +z, -z.
const PLATFORM_LINKS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
## Unit cube face corners and shade per face (voxel_arrays' order and shades):
## +z, -z, +x, -x, up, down.
const _CUBE_FACES := [
	[[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)], 1.0],
	[[Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)], 0.85],
	[[Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)], 0.72],
	[[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)], 0.72],
	[[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)], 0.9],
	[[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)], 0.55],
]


## One platform cell of a merged platform floor (BlockModels): the slab of
## the platform's middle frame (Terraria's frame for a platform with platforms
## on both sides, which tiles) laid across the whole block both ways, with no
## faces toward the platforms it links to (`links`: PLATFORM_LINKS bits), so
## platforms that touch read as one surface whatever its shape, without the
## end caps and seams of single planks. Top and bottom take one colour each
## (the frame's commonest just inside its outline); the sides show the frame's
## pixels, running on round the edge. The pattern doesn't turn with the block,
## so every cell lines up with its neighbours. Lifted like the block's model
## (its transform's height); cached per block and links.
static func platform(block_id: int, links: int) -> ArrayMesh:
	var key := "%d:platform:%d" % [block_id, links]
	if _cache.has(key):
		return _cache[key].mesh
	var d := Data.block(block_id)
	var art: Image = d.art
	var n := art.get_width()
	var h := art.get_height()
	var tiles: Array = d.get("tex", {}).get("all", {}).get("tiles", [2, 1])
	var fw := maxi(1, n / maxi(1, int(tiles[0])))
	var px := float(d.art_px)
	var lift := Data.block_transform(d).origin.y
	# The slab's layers: the frame's rows that are mostly opaque, filled right
	# across (gaps in the art, between bricks or round a cloud's rim, would cut
	# a grid of grooves into the floor). A gap's pixel on the sides takes the
	# nearest opaque pixel above or below it.
	var solid_rows := []
	for y in h:
		var opaque := 0
		for x in fw:
			opaque += int(art.get_pixel(x, y).a > 0.5)
		solid_rows.append(opaque * 2 >= fw)
	var top := _platform_face_colour(art, fw, true)
	var bottom := _platform_face_colour(art, fw, false)
	var art_at := func(u: int, y: int) -> Color:
		var x := posmod(u, fw)
		for step in h:
			for yy in [y - step, y + step]:
				if yy >= 0 and yy < h and art.get_pixel(x, yy).a > 0.5:
					return art.get_pixel(x, yy)
		return top
	# A voxel of the slab. Past the block's edge it's the linked platform's.
	var filled := func(x: int, y: int, z: int) -> bool:
		if y < 0 or y >= h or not solid_rows[y]:
			return false
		var side := 0 if x >= n else 1 if x < 0 else 2 if z >= n else 3 if z < 0 else -1
		return side < 0 or links & (1 << side) != 0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(fi: int, x: int, y: int, z: int, length: int, colour: Color) -> void:
		var p := Vector3((x - n * 0.5) * px, lift + (h - 1 - y) * px, (z - n * 0.5) * px)
		var size := Vector3(length * px, px, px)
		var c: Color = colour.srgb_to_linear() * float(_CUBE_FACES[fi][1])
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(c.r, c.g, c.b))
			st.set_uv(FACE_UVS[i] * Vector2(length, 1))
			st.add_vertex(p + _CUBE_FACES[fi][0][i] * size)
	for y in h:
		for z in n:
			# Tops and bottoms in runs along x (one colour); UVs count voxels, so
			# the sun's shadow is still looked up per voxel.
			for fi in [4, 5]:
				var above := -1 if fi == 4 else 1
				var x := 0
				while x < n:
					if not filled.call(x, y, z) or filled.call(x, y + above, z):
						x += 1
						continue
					var x1 := x + 1
					while x1 < n and filled.call(x1, y, z) and not filled.call(x1, y + above, z):
						x1 += 1
					quad.call(fi, x, y, z, x1 - x, top if fi == 4 else bottom)
					x = x1
			for x in n:
				if not filled.call(x, y, z):
					continue
				if not filled.call(x, y, z + 1):
					quad.call(0, x, y, z, 1, art_at.call(x, y))
				if not filled.call(x, y, z - 1):
					quad.call(1, x, y, z, 1, art_at.call(x, y))
				if not filled.call(x + 1, y, z):
					quad.call(2, x, y, z, 1, art_at.call(z, y))
				if not filled.call(x - 1, y, z):
					quad.call(3, x, y, z, 1, art_at.call(z, y))
	var mesh := st.commit()
	_cache[key] = {"mesh": mesh, "textured": false}
	return mesh


## The commonest colour just inside the outline of a platform frame's top (or
## bottom), across its columns.
static func _platform_face_colour(art: Image, fw: int, from_top: bool) -> Color:
	var h := art.get_height()
	var counts := {}
	var best := Color(0.5, 0.4, 0.3)
	var most := 0
	for x in fw:
		var rows: Array = range(h) if from_top else range(h - 1, -1, -1)
		var edge := -1
		for y in rows:
			if art.get_pixel(x, y).a > 0.5:
				edge = y
				break
		if edge < 0:
			continue
		var inner := edge + (1 if from_top else -1)
		var y := inner if inner >= 0 and inner < h and art.get_pixel(x, inner).a > 0.5 else edge
		var c := art.get_pixel(x, y)
		counts[c] = counts.get(c, 0) + 1
		if counts[c] > most:
			most = counts[c]
			best = c
	return best


static func transformed(m: ArrayMesh, t: Transform3D) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(m, 0)
	var arrays := st.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = t * verts[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func _hash(a: int, b: int, c: int, d: int, e: int) -> float:
	var n := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ (d * 50331653) ^ (e * 2654435)
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 65535.0


## The sprite pushed `o.depth` voxels deep. Front and back show the sprite; each
## edge pixel's side is split into one cell per voxel of depth, coloured from
## just inside the outline and varied by `o.noise`:
##   none     flat colour
##   speckle  random lighter/darker cells
##   grain    wavy bands along the depth (wood-like)
##   palette  some cells take a random colour from the sprite's interior
## `o.strength` (0..1) scales the effect; `o.seed` changes the pattern.
## `o.bevel` recesses the front and back near the outline, in voxel steps, by
## each pixel's distance from the edge (`o.bevel_size` voxels wide). Only the
## edges and faces in `o.bevel_sides` (BEVEL_SIDES) are bevelled, e.g. a chest's
## top and sides but not its bottom, which sits on the floor:
##   chamfer  straight 45 degree slope
##   round    convex quarter circle (rounded edge)
##   cove     concave quarter circle
##   step     a single ledge
static func _extrude(img: Image, px: float, o: Dictionary) -> ArrayMesh:
	var w := img.get_width()
	var h := img.get_height()
	var depth: int = o.depth
	var strength: float = o.strength
	var seed: int = o.seed
	var noise: String = o.noise
	var opaque := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h and img.get_pixel(x, y).a > 0.5
	# Interior pixels (not touching transparency) for the palette mode.
	var interior: Array[Vector2i] = []
	for y in h:
		for x in w:
			if opaque.call(x, y) and opaque.call(x - 1, y) and opaque.call(x + 1, y) and opaque.call(x, y - 1) and opaque.call(x, y + 1):
				interior.append(Vector2i(x, y))
	# How far each pixel's front and back are recessed (voxels), for the bevel:
	# measured from the enabled silhouette edges, on the enabled faces only.
	var sides: Array = o.get("bevel_sides", BEVEL_SIDES)
	var faces := int("front" in sides) + int("back" in sides)
	var inset := PackedInt32Array()
	if faces > 0:
		inset = _bevel_insets(img, opaque, o.get("bevel", "none"), int(o.get("bevel_size", 3)), (depth - 1) / faces, sides)
	else:
		inset.resize(w * h)
	var beveled := inset.count(0) != inset.size()
	# Each pixel's own front and back (not the whole sprite alpha-cut, which
	# would show an outline the art no longer has).
	var per_pixel: bool = beveled or o.get("no_outline", false)
	var front_k := 1 if "front" in sides else 0
	var back_k := 1 if "back" in sides else 0
	var ins_f := func(x: int, y: int) -> int:
		return inset[y * w + x] * front_k
	var ins_b := func(x: int, y: int) -> int:
		return inset[y * w + x] * back_k

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ox := -w * 0.5
	var dz := depth * 0.5
	var to_m := func(x: float, y: float, z: float) -> Vector3:
		return Vector3((x + ox) * px, y * px, z * px)
	if not per_pixel:
		# Front and back: the whole sprite (alpha-cut in the shader).
		var full := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		_quad(st, [to_m.call(0, 0, dz), to_m.call(w, 0, dz), to_m.call(w, h, dz), to_m.call(0, h, dz)], full, SHADES.front)
		_quad(st, [to_m.call(w, 0, -dz), to_m.call(0, 0, -dz), to_m.call(0, h, -dz), to_m.call(w, h, -dz)],
				[Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)], SHADES.front)
	# (pixel step to the open side, shade)
	var dirs := [[Vector2i(-1, 0), SHADES.side], [Vector2i(1, 0), SHADES.side], [Vector2i(0, -1), SHADES.top], [Vector2i(0, 1), SHADES.bottom]]
	# Quad for the face of pixel (x0..x1, y0..y1) on side `di`, spanning z0..z1.
	var wall := func(di: int, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> Array:
		match di:
			0: return [to_m.call(x0, y0, z0), to_m.call(x0, y0, z1), to_m.call(x0, y1, z1), to_m.call(x0, y1, z0)]
			1: return [to_m.call(x1, y0, z1), to_m.call(x1, y0, z0), to_m.call(x1, y1, z0), to_m.call(x1, y1, z1)]
			2: return [to_m.call(x0, y1, z1), to_m.call(x1, y1, z1), to_m.call(x1, y1, z0), to_m.call(x0, y1, z0)]
		return [to_m.call(x0, y0, z0), to_m.call(x1, y0, z0), to_m.call(x1, y0, z1), to_m.call(x0, y0, z1)]
	for py in h:
		for pxl in w:
			if not opaque.call(pxl, py):
				continue
			var y0 := float(h - py - 1)
			var y1 := float(h - py)
			var x0 := float(pxl)
			var x1 := float(pxl + 1)
			var my_f: int = ins_f.call(pxl, py)
			var my_b: int = ins_b.call(pxl, py)
			var own_uv := Vector2((pxl + 0.5) / w, (py + 0.5) / h)
			if per_pixel:
				# This pixel's own front and back, at their recessed depths.
				var zf: float = dz - my_f
				var zb: float = -dz + my_b
				_quad(st, [to_m.call(x0, y0, zf), to_m.call(x1, y0, zf), to_m.call(x1, y1, zf), to_m.call(x0, y1, zf)], [own_uv, own_uv, own_uv, own_uv], SHADES.front)
				_quad(st, [to_m.call(x1, y0, zb), to_m.call(x0, y0, zb), to_m.call(x0, y1, zb), to_m.call(x1, y1, zb)], [own_uv, own_uv, own_uv, own_uv], SHADES.front)
			for di in 4:
				var open: Vector2i = dirs[di][0]
				var nx := pxl + open.x
				var ny := py + open.y
				if opaque.call(nx, ny):
					# Bevel steps: where the neighbour is recessed further, this pixel's
					# relief shows a short wall (coloured like the pixel's front).
					var shade: float = dirs[di][1]
					var their_f: int = ins_f.call(nx, ny)
					var their_b: int = ins_b.call(nx, ny)
					if their_f > my_f:
						_quad(st, wall.call(di, x0, x1, y0, y1, dz - their_f, dz - my_f), [own_uv, own_uv, own_uv, own_uv], shade)
					if their_b > my_b:
						_quad(st, wall.call(di, x0, x1, y0, y1, -dz + my_b, -dz + their_b), [own_uv, own_uv, own_uv, own_uv], shade)
					continue
				# Silhouette side: colour from the brightest of the next 3 pixels inward.
				var src := Vector2i(pxl, py)
				var best := -1.0
				for step in range(1, 4):
					var q := Vector2i(pxl, py) - open * step
					if not opaque.call(q.x, q.y):
						break
					var lum := img.get_pixel(q.x, q.y).get_luminance()
					if lum > best:
						best = lum
						src = q
				# Noise is looked up per NOISE_CELL-sized patch (along the edge and
				# along the depth), so neighbouring voxels share a value.
				var cx := pxl / NOISE_CELL
				var cy := py / NOISE_CELL
				var row_phase := _hash(cx, cy, di, 7, seed) * TAU
				for k in range(my_b, depth - my_f):
					var z0 := -dz + k
					var ck := k / NOISE_CELL
					var cell_src := src
					var factor := 1.0
					var r := _hash(cx, cy, ck, di, seed)
					match noise:
						"speckle":
							factor = 1.0 + (r * 2.0 - 1.0) * strength * 0.45
						"grain":
							factor = 1.0 + sin(ck * 0.55 + row_phase + (cy * 0.9)) * strength * 0.3 + (r - 0.5) * strength * 0.12
						"palette":
							if not interior.is_empty() and r < strength * 0.6:
								cell_src = interior[int(_hash(cx, cy, ck, di, seed + 1) * interior.size()) % interior.size()]
					var uv := Vector2((cell_src.x + 0.5) / w, (cell_src.y + 0.5) / h)
					_quad(st, wall.call(di, x0, x1, y0, y1, z0, z0 + 1.0), [uv, uv, uv, uv], dirs[di][1] * factor)
	return st.commit()


## Per-pixel recess (voxels) for a bevel profile: each opaque pixel's distance
## to the outline's enabled `sides` (left/right/top/bottom of the sprite; 0 at
## the edge, 8-neighbour steps) mapped through the profile
## over `size` voxels, capped at `max_inset` so at least one voxel remains.
## Worked out in BEVEL_CELL-sized steps: pixels pair up by distance and each
## step recesses by BEVEL_CELL voxels.
static func _bevel_insets(img: Image, opaque: Callable, profile: String, size: int, max_inset: int, sides: Array = BEVEL_SIDES) -> PackedInt32Array:
	var w := img.get_width()
	var h := img.get_height()
	var out := PackedInt32Array()
	out.resize(w * h)
	if profile == "none" or max_inset <= 0:
		return out
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var queue: Array[Vector2i] = []
	# Edge pixels on the enabled sides of the silhouette (open to the left,
	# right, top or bottom of the sprite) are where the bevel starts.
	var open_sides := [["left", Vector2i(-1, 0)], ["right", Vector2i(1, 0)], ["top", Vector2i(0, -1)], ["bottom", Vector2i(0, 1)]]
	for y in h:
		for x in w:
			if not opaque.call(x, y):
				continue
			for side in open_sides:
				if side[0] in sides and not opaque.call(x + side[1].x, y + side[1].y):
					dist[y * w + x] = 0
					queue.append(Vector2i(x, y))
					break
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		var d := dist[p.y * w + p.x]
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q := p + Vector2i(dx, dy)
				if opaque.call(q.x, q.y) and dist[q.y * w + q.x] < 0:
					dist[q.y * w + q.x] = d + 1
					queue.append(q)
	var s := ceilf(float(size) / BEVEL_CELL)  # bevel width in steps
	for i in w * h:
		if dist[i] < 0:
			continue
		var d := float(dist[i] / BEVEL_CELL)  # which step this pixel is on
		if d >= s:
			continue
		var f := 0.0
		match profile:
			"chamfer":
				f = s - d
			"round":
				f = s - sqrt(s * s - (s - d) * (s - d))
			"cove":
				f = sqrt(s * s - d * d)
			"step":
				f = ceilf(s * 0.5)
		out[i] = mini(roundi(f) * BEVEL_CELL, max_inset)
	return out


## Voxel solids from the sprite: a w x h x w grid (depth = sprite width).
## "hull" is the front silhouette cut by the same one seen from the sides;
## "hull_top" cuts it by the sprite seen from above and below instead (a
## w x h x h grid: as deep as the sprite is tall, its top row at the back).
## Same noise modes as the extruded sides (see _extrude), per voxel face. Hull
## keeps its front/back art clean; the lathe's whole surface gets noise, with
## grain as horizontal rings (like thrown pottery). A `side_view` hull (a sprite
## drawn from the side, like a wall torch) is as deep at each column as the
## sprite is thick there, centred: a slanted stick stays round.
static func _voxels(img: Image, px: float, method: String, o := {}, side_view := false) -> ArrayMesh:
	var noise: String = o.get("noise", "none")
	var strength: float = o.get("strength", 0.5)
	var seed: int = o.get("seed", 0)
	var w := img.get_width()
	var h := img.get_height()
	var opaque := PackedByteArray()
	opaque.resize(w * h)
	for y in h:
		for x in w:
			opaque[y * w + x] = 1 if img.get_pixel(x, y).a > 0.5 else 0
	var c := (w - 1) * 0.5
	var depth := h if method == "hull_top" else w
	# Side view: each column's opaque pixel count is its depth.
	var thickness := PackedInt32Array()
	thickness.resize(w)
	for x in w:
		for y in h:
			thickness[x] += opaque[y * w + x]
	# Column of the sprite each (x, z) voxel takes its silhouette and colour from.
	var lathe_col := PackedInt32Array()
	lathe_col.resize(w * w)
	for z in w:
		for x in w:
			var r := sqrt((x - c) * (x - c) + (z - c) * (z - c))
			var u := int(round(c + r))
			lathe_col[z * w + x] = u if u < w else -1
	var solid := func(x: int, y: int, z: int) -> bool:
		if x < 0 or y < 0 or z < 0 or x >= w or y >= h or z >= depth:
			return false
		var row := (h - 1 - y) * w
		if method == "hull_top":
			return opaque[row + x] == 1 and opaque[z * w + x] == 1
		if method == "hull":
			if side_view:
				return opaque[row + x] == 1 and absf(z - c) * 2.0 < thickness[x]
			return opaque[row + x] == 1 and opaque[row + z] == 1
		var u := lathe_col[z * w + x]
		return u >= 0 and opaque[row + u] == 1
	# Brightest of the next 3 opaque pixels from (col, row) stepping `drow` rows:
	# skips Terraria's dark outline (and the shading pixel often behind it).
	var inward := func(col: int, row: int, drow: int) -> Color:
		var best := img.get_pixel(col, row)
		var best_lum := -1.0
		for step in range(1, 4):
			var r := row + drow * step
			if r < 0 or r >= h or opaque[r * w + col] == 0:
				break
			var c2 := img.get_pixel(col, r)
			if c2.get_luminance() > best_lum:
				best_lum = c2.get_luminance()
				best = c2
		return best
	# The same stepping `dcol` columns along a row.
	var inward_x := func(col: int, row: int, dcol: int) -> Color:
		var best := img.get_pixel(col, row)
		var best_lum := -1.0
		for step in range(1, 4):
			var cc := col + dcol * step
			if cc < 0 or cc >= w or opaque[row * w + cc] == 0:
				break
			var c2 := img.get_pixel(cc, row)
			if c2.get_luminance() > best_lum:
				best_lum = c2.get_luminance()
				best = c2
		return best
	var color := func(x: int, y: int, z: int, kind: String) -> Color:
		var row := h - 1 - y
		if method == "hull_top":
			match kind:
				"top", "bottom":
					return img.get_pixel(x, z)  # the sprite, seen from above
				"left":
					return inward_x.call(x, row, 1)
				"right":
					return inward_x.call(x, row, -1)
			return img.get_pixel(x, row)
		if method == "hull":
			match kind:
				"top":
					return inward.call(x, row, 1)
				"bottom":
					return inward.call(x, row, -1)
				"left", "right":
					return img.get_pixel(x if side_view else z, row)
			return img.get_pixel(x, row)
		# The lathe's outer surface comes from the silhouette edge, which in
		# Terraria sprites is a dark outline; take the colour from just inside it.
		var u := lathe_col[z * w + x]
		var inner := maxi(u - 2, ceili(c))
		while inner < u and opaque[row * w + inner] == 0:
			inner += 1
		return img.get_pixel(inner, row)

	# Interior pixels (not touching transparency) for the palette mode.
	var interior: Array[Color] = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if opaque[y * w + x] == 1 and opaque[y * w + x - 1] == 1 and opaque[y * w + x + 1] == 1 \
					and opaque[(y - 1) * w + x] == 1 and opaque[(y + 1) * w + x] == 1:
				interior.append(img.get_pixel(x, y))
	# Noise for a face of voxel (x, y, z): returns the (possibly replaced) colour and a brightness factor.
	var apply_noise := func(col: Color, x: int, y: int, z: int, face: int) -> Array:
		var cx := x / NOISE_CELL
		var cy := y / NOISE_CELL
		var cz := z / NOISE_CELL
		var r := _hash(cx * 31 + cz, cy, face, 11, seed)
		match noise:
			"speckle":
				return [col, 1.0 + (r * 2.0 - 1.0) * strength * 0.45]
			"grain":
				var wave := 0.0
				if method == "lathe":
					wave = sin(cy * 0.9 + _hash(cx, cz, 3, 5, seed) * 1.5)  # rings around the axis
				else:
					wave = sin(cz * 0.55 + _hash(cx, cy, 3, 5, seed) * TAU)  # bands along the depth
				return [col, 1.0 + wave * strength * 0.3 + (r - 0.5) * strength * 0.12]
			"palette":
				if not interior.is_empty() and r < strength * 0.6:
					return [interior[int(_hash(cx * 31 + cz, cy, face, 13, seed) * interior.size()) % interior.size()], 1.0]
		return [col, 1.0]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ox := -w * 0.5
	var oz := -depth * 0.5
	for y in h:
		for z in depth:
			for x in w:
				if not solid.call(x, y, z):
					continue
				var p := Vector3(x + ox, y, z + oz) * px
				var s := px
				# (neighbour offset, quad corners, shade, which way the face looks)
				var faces := [
					[Vector3i(0, 0, 1), [Vector3(0, 0, s), Vector3(s, 0, s), Vector3(s, s, s), Vector3(0, s, s)], SHADES.front, "front"],
					[Vector3i(0, 0, -1), [Vector3(s, 0, 0), Vector3(0, 0, 0), Vector3(0, s, 0), Vector3(s, s, 0)], SHADES.front * 0.85, "front"],
					[Vector3i(1, 0, 0), [Vector3(s, 0, s), Vector3(s, 0, 0), Vector3(s, s, 0), Vector3(s, s, s)], SHADES.side, "right"],
					[Vector3i(-1, 0, 0), [Vector3(0, 0, 0), Vector3(0, 0, s), Vector3(0, s, s), Vector3(0, s, 0)], SHADES.side, "left"],
					[Vector3i(0, 1, 0), [Vector3(0, s, s), Vector3(s, s, s), Vector3(s, s, 0), Vector3(0, s, 0)], SHADES.top, "top"],
					[Vector3i(0, -1, 0), [Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, 0, s), Vector3(0, 0, s)], SHADES.bottom, "bottom"],
				]
				for fi in faces.size():
					var f: Array = faces[fi]
					var n: Vector3i = f[0]
					if solid.call(x + n.x, y + n.y, z + n.z):
						continue
					var base: Color = color.call(x, y, z, f[3])
					var factor := 1.0
					if noise != "none" and (method == "lathe" or f[3] != "front"):
						var nz: Array = apply_noise.call(base, x, y, z, fi)
						base = nz[0]
						factor = nz[1]
					# Sprite pixels are sRGB; the shader works in linear (like the
					# textured methods, whose texture is converted on sampling).
					var col: Color = base.srgb_to_linear() * float(f[2]) * factor
					for i in [0, 1, 2, 0, 2, 3]:
						st.set_color(Color(col.r, col.g, col.b))
						st.set_uv(FACE_UVS[i])
						st.add_vertex(p + f[1][i])
	return st.commit()


## A hand-made model's voxels: Vector3i(x, y, z) -> Color, x and y in art
## pixels (y down, like the image), z 0 (back) to w - 1 (front). See
## data/handmade_models.json. Each opaque pixel's column gets its part's z
## ranges; its front-most voxel takes the pixel's colour, the rest its fill.
static func handmade_voxels(img: Image, spec: Dictionary, frame := 0) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var parts: Array = spec.get("parts", [])
	var fallback: Dictionary = spec.get("default", {"z": [[0, w - 1]]})
	var out := {}
	for y in h:
		for x in w:
			var own := img.get_pixel(x, y)
			if own.a <= 0.5:
				continue
			var part := fallback
			var at := Vector2i.ZERO
			for p in parts:
				# "shift": where the part has moved to in each animation frame.
				var sh := Vector2i.ZERO
				if p.has("shift") and not p.shift.is_empty():
					var o: Array = p.shift[frame % p.shift.size()]
					sh = Vector2i(int(o[0]), int(o[1]))
				var r: Array = p.rect
				if x >= int(r[0]) + sh.x and y >= int(r[1]) + sh.y and x <= int(r[2]) + sh.x and y <= int(r[3]) + sh.y:
					# "match": only pixels of that art pixel's colour (book gaps, knobs).
					if p.has("match") and own != img.get_pixel(clampi(int(p.match[0]) + sh.x, 0, w - 1), clampi(int(p.match[1]) + sh.y, 0, h - 1)):
						continue
					part = p
					at = sh
					break
			var fill := own
			if part.has("fill"):
				fill = img.get_pixel(clampi(int(part.fill[0]) + at.x, 0, w - 1), clampi(int(part.fill[1]) + at.y, 0, h - 1))
			var front := -1
			for zr in part.z:
				front = maxi(front, mini(int(zr[1]), w - 1))
			for zr in part.z:
				for z in range(maxi(int(zr[0]), 0), mini(int(zr[1]), w - 1) + 1):
					out[Vector3i(x, y, z)] = own if z == front else fill
	return out


## The mesh of a hand-made model: a cube face wherever a voxel has no
## neighbour, shaded like the other voxel models (front faces at full
## brightness, so the front view shows the sprite's own colours). Side noise
## (`o`: noise, strength, seed, as for hull) goes on every face but the
## front-facing ones, so the front view stays the sprite:
##   speckle  random lighter/darker voxel faces
##   grain    wavy bands along the depth (wood-like)
##   palette  some faces take a random colour from the sprite's interior
static func _handmade(img: Image, px: float, spec: Dictionary, o := {}, frame := 0) -> ArrayMesh:
	return voxel_mesh(handmade_voxels(img, spec, frame), img, px, o)


## The mesh of voxels (Vector3i -> Color, in `img`'s art pixels; see
## handmade_voxels), with side noise `o` ("palette" picks from `img`'s
## interior). `plain_front`: front faces get no noise (the front view stays
## the sprite). `face_colors`: Vector3i -> {face (FACE_*): Color} for faces that
## take another colour than their voxel. `solid`: (Vector3i) -> bool, cells
## that count as filled though not in `vox` (a solid body's inside: no faces
## are drawn against them).
static func voxel_mesh(vox: Dictionary, img: Image, px: float, o := {}, plain_front := true, face_colors := {}, solid := Callable()) -> ArrayMesh:
	return mesh_from_arrays(voxel_arrays(vox, img, px, o, plain_front, face_colors, solid))


## An ArrayMesh from surface arrays (an empty one for no vertices).
static func mesh_from_arrays(arrays: Array) -> ArrayMesh:
	var out := ArrayMesh.new()
	if not arrays.is_empty() and not (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## voxel_mesh's surface arrays, without touching the rendering server (so it
## can run on a worker thread).
static func voxel_arrays(vox: Dictionary, img: Image, px: float, o := {}, plain_front := true, face_colors := {}, solid := Callable()) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var noise: String = o.get("noise", "none")
	var strength: float = o.get("strength", 0.5)
	var seed: int = o.get("seed", 0)
	var interior: Array[Color] = []
	if noise == "palette":
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				if img.get_pixel(x, y).a > 0.5 and img.get_pixel(x - 1, y).a > 0.5 and img.get_pixel(x + 1, y).a > 0.5 \
						and img.get_pixel(x, y - 1).a > 0.5 and img.get_pixel(x, y + 1).a > 0.5:
					interior.append(img.get_pixel(x, y))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := px
	# (neighbour in voxel space - y down -, quad corners, shade)
	var faces := [
		[Vector3i(0, 0, 1), [Vector3(0, 0, s), Vector3(s, 0, s), Vector3(s, s, s), Vector3(0, s, s)], SHADES.front],
		[Vector3i(0, 0, -1), [Vector3(s, 0, 0), Vector3(0, 0, 0), Vector3(0, s, 0), Vector3(s, s, 0)], SHADES.front * 0.85],
		[Vector3i(1, 0, 0), [Vector3(s, 0, s), Vector3(s, 0, 0), Vector3(s, s, 0), Vector3(s, s, s)], SHADES.side],
		[Vector3i(-1, 0, 0), [Vector3(0, 0, 0), Vector3(0, 0, s), Vector3(0, s, s), Vector3(0, s, 0)], SHADES.side],
		[Vector3i(0, -1, 0), [Vector3(0, s, s), Vector3(s, s, s), Vector3(s, s, 0), Vector3(0, s, 0)], SHADES.top],
		[Vector3i(0, 1, 0), [Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, 0, s), Vector3(0, 0, s)], SHADES.bottom],
	]
	for v: Vector3i in vox:
		# Metres: centred on x and z, bottom at y = 0 (art y runs down).
		var p := Vector3((v.x - w * 0.5) * s, (h - 1 - v.y) * s, (v.z - w * 0.5) * s)
		var col: Color = vox[v]
		for fi in faces.size():
			var f: Array = faces[fi]
			if vox.has(v + f[0]) or (solid.is_valid() and solid.call(v + f[0])):
				continue
			var base: Color = face_colors[v].get(fi, col) if face_colors.has(v) else col
			var factor := 1.0
			if noise != "none" and (fi != 0 or not plain_front):
				# Looked up per NOISE_CELL patch, so neighbouring voxels share a value.
				var cx := v.x / NOISE_CELL
				var cy := v.y / NOISE_CELL
				var cz := v.z / NOISE_CELL
				var r := _hash(cx * 31 + cz, cy, fi, 17, seed)
				match noise:
					"speckle":
						factor = 1.0 + (r * 2.0 - 1.0) * strength * 0.45
					"grain":
						factor = 1.0 + sin(cz * 0.55 + _hash(cx, cy, 3, 5, seed) * TAU) * strength * 0.3 + (r - 0.5) * strength * 0.12
					"palette":
						if not interior.is_empty() and r < strength * 0.6:
							base = interior[int(_hash(cx * 31 + cz, cy, fi, 19, seed) * interior.size()) % interior.size()]
			var c: Color = base.srgb_to_linear() * float(f[2]) * factor
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_color(Color(c.r, c.g, c.b))
				st.set_uv(FACE_UVS[i])
				st.add_vertex(p + f[1][i])
	if vox.is_empty():
		return []
	return st.commit_to_arrays()
