class_name ItemMesh
## Builds Minecraft-style held-item models: a sprite extruded one pixel deep.
## Front and back faces show the whole sprite (alpha-cut); every opaque pixel
## that borders transparency gets an edge face coloured from that pixel.
##
## Mesh units are pixels with the origin at the sprite's bottom-left corner
## (where Terraria draws the grip), x right, y up, depth centred on z = 0.
## Vertex COLOR carries baked face shading.

const FRONT_SHADE := 1.0
const TOP_SHADE := 0.9
const SIDE_SHADE := 0.72
const BOTTOM_SHADE := 0.55

static var _cache := {}


## Builds at the sprite's art resolution (see PixelArt) and scales the result
## back to texture-pixel units, so a held item is one art pixel thick.
static func build_art(image: Image, key: String) -> ArrayMesh:
	var scale := PixelArt.detect_scale(image)
	if scale.x <= 1:
		return build(image, key)
	var full_key := key + "@art"
	BlockModelMesh.lock.lock()
	var hit = _cache.get(full_key)
	BlockModelMesh.lock.unlock()
	if hit != null:
		return hit
	var m := build(PixelArt.downsample(image, scale), key + "~art")
	var st := SurfaceTool.new()
	st.create_from(m, 0)
	var arrays := st.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var k := float(scale.x)
	for i in verts.size():
		verts[i] = verts[i] * k + Vector3(scale.y, 0, 0)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	BlockModelMesh.lock.lock()
	_cache[full_key] = out
	BlockModelMesh.lock.unlock()
	return out


## `depth` is the thickness in pixels (1 for held items). With `inset_edges`,
## each edge face takes its colour from inside the sprite (the brightest of the
## next 3 pixels inward) instead of the edge pixel itself: Terraria sprites have
## a dark outline, which would otherwise turn the sides of thick extrusions black.
static func build(image: Image, key: String, depth := 1.0, inset_edges := false) -> ArrayMesh:
	key = "%s@%s%s" % [key, depth, "i" if inset_edges else ""]
	BlockModelMesh.lock.lock()
	var hit = _cache.get(key)
	BlockModelMesh.lock.unlock()
	if hit != null:
		return hit
	var dz := depth * 0.5
	var img := image
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Front (z = +depth/2) and back (z = -depth/2) faces.
	_quad(st, Vector3(0, 0, dz), Vector3(w, 0, dz), Vector3(w, h, dz), Vector3(0, h, dz),
			[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], FRONT_SHADE)
	_quad(st, Vector3(w, 0, -dz), Vector3(0, 0, -dz), Vector3(0, h, -dz), Vector3(w, h, -dz),
			[Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)], FRONT_SHADE)

	var solid := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h and img.get_pixel(x, y).a > 0.5

	for py in h:
		for px in w:
			if not solid.call(px, py):
				continue
			# Each edge face is one flat colour: the centre of the edge pixel, or
			# (inset) of the pixel just inside it, away from the open side.
			var edge_uvs := func(dx: int, dy: int) -> Array:
				var sx := px
				var sy := py
				if inset_edges:
					# Up to 3 pixels inward, take the brightest: outlines are often
					# followed by a dark shading pixel before the real colour.
					var best := -1.0
					for step in range(1, 4):
						var ix := px + dx * step
						var iy := py + dy * step
						if not solid.call(ix, iy):
							break
						var lum := img.get_pixel(ix, iy).get_luminance()
						if lum > best:
							best = lum
							sx = ix
							sy = iy
				var uv := Vector2((sx + 0.5) / w, (sy + 0.5) / h)
				return [uv, uv, uv, uv]
			var x0 := float(px)
			var x1 := float(px + 1)
			var y0 := float(h - py - 1)  # image rows go down, mesh y goes up
			var y1 := float(h - py)
			if not solid.call(px - 1, py):
				_quad(st, Vector3(x0, y0, -dz), Vector3(x0, y0, dz), Vector3(x0, y1, dz), Vector3(x0, y1, -dz), edge_uvs.call(1, 0), SIDE_SHADE)
			if not solid.call(px + 1, py):
				_quad(st, Vector3(x1, y0, dz), Vector3(x1, y0, -dz), Vector3(x1, y1, -dz), Vector3(x1, y1, dz), edge_uvs.call(-1, 0), SIDE_SHADE)
			if not solid.call(px, py - 1):
				_quad(st, Vector3(x0, y1, dz), Vector3(x1, y1, dz), Vector3(x1, y1, -dz), Vector3(x0, y1, -dz), edge_uvs.call(0, 1), TOP_SHADE)
			if not solid.call(px, py + 1):
				_quad(st, Vector3(x0, y0, -dz), Vector3(x1, y0, -dz), Vector3(x1, y0, dz), Vector3(x0, y0, dz), edge_uvs.call(0, -1), BOTTOM_SHADE)
	var mesh := st.commit()
	BlockModelMesh.lock.lock()
	_cache[key] = mesh
	BlockModelMesh.lock.unlock()
	return mesh


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uvs: Array, shade: float) -> void:
	var col := Color(shade, shade, shade)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_uv(uvs[i])
		st.add_vertex([a, b, c, d][i])
