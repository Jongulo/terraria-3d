class_name NPCSculpt
## Claude's hand-made NPC models (the NPC picker's "claude" method), sculpted
## from shapes in data/handmade_npc_models.json: a ball (a shell) wearing the
## sprite, projected straight through it so that from the front it is the
## sprite (its colours, and see-through gaps cut right through) and from the
## back its mirror image, as a card's back would be; the sprite's parts outside
## the ball (tendrils) keep their place seen from the front but spread out in
## depth. Each frame of the sprite builds its own model, so they animate with
## it. Voxels are art pixels: x right, y down (like the image), z 0 (back) to
## w - 1 (front); the model is kept inside the sprite's w x h x w box.

const PATH := "res://data/handmade_npc_models.json"

## What carve sinks (and the back's flanks skip): darker than this luminance
## and no more saturated than this (HSV): a skull's sockets, not a red hat.
const DARK_LIGHT := 0.26
const DARK_MAX_SAT := 0.44

static var _specs := {}
static var _loaded := false


## The NPC's spec, or {} when Claude hasn't made one.
static func spec(kind: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		_specs = d if d is Dictionary else {}
		_specs.erase("_doc")
	return _specs.get(kind, {})


static func has(kind: String) -> bool:
	return not spec(kind).is_empty()


## Vector3i -> Color for one frame (`art`: its sprite at art resolution).
## `faces` gets Vector3i -> {face: Color} for voxels whose faces don't all
## take the voxel's colour (see _project; faces as BlockModelMesh.voxel_mesh).
## A solid body (revolve) keeps only its surface voxels: `body` gets its
## columns, and solid_test(body) tells the mesher what's inside.
static func voxels(sp: Dictionary, art: Image, faces := {}, body := {}) -> Dictionary:
	if sp.get("outline", "ignore") == "ignore":
		art = without_outline(art)
	var w := art.get_width()
	var h := art.get_height()
	var c := _fit_ball(art)
	var r := float(sp.get("r", w * 0.5))
	var solid := false
	var vox := {}
	for op: Dictionary in sp.get("ops", []):
		match str(op.op):
			"ball":
				_ball(vox, c, r, _colors(op.color), _colors(op.get("inner", op.color)))
			"revolve":
				c = _revolve(vox, art, float(op.get("depth", 1.0)), _colors(op.color), body)
				solid = true
			"carve":
				_carve(vox, art, op, _colors(op.get("color", "#808080")), body)
			"project":
				_project(vox, c, r, art, float(op.get("side_band", 35.0)), float(op.get("bottom_cap", 0.0)), float(op.get("top_cap", 0.0)), faces, solid,
						int(op.get("back_inset", -1)), body)
			"mouth":
				_mouth(vox, c, r, art, op, faces)
			"outside":
				_outside(vox, c, r, art, float(op.get("drift", 16.0)), float(op.get("rise", 20.0)), float(op.get("wave", 0.1)))
	var out := {}
	for v: Vector3i in vox:
		if v.x >= 0 and v.x < w and v.y >= 0 and v.y < h and v.z >= 0 and v.z < w:
			out[v] = vox[v]
	return out


## The ball's centre in a frame: across the middle of the sprite, at the
## height of its widest rows (frames place it differently: the Eye's mouth
## frames sit lower).
static func _fit_ball(art: Image) -> Vector3:
	var w := art.get_width()
	var widths: Array[int] = []
	var widest := 0
	for y in art.get_height():
		var first := -1
		var last := -1
		for x in w:
			if art.get_pixel(x, y).a > 0.5:
				last = x
				if first < 0:
					first = x
		widths.append(last - first + 1 if first >= 0 else 0)
		widest = maxi(widest, widths[y])
	var sum := 0.0
	var n := 0
	for y in widths.size():
		if widths[y] >= widest - 1:
			sum += y
			n += 1
	return Vector3(w * 0.5, sum / maxi(n, 1) + 0.5, w * 0.5)


## "#rrggbb" or a list of them (a mottle: each voxel picks one).
static func _colors(c) -> Array[Color]:
	var out: Array[Color] = []
	for s in (c if c is Array else [c]):
		out.append(Color.html(str(s)))
	return out


static func _pick(cols: Array[Color], v: Vector3i) -> Color:
	return cols[int(BlockModelMesh._hash(v.x, v.y, v.z, 7, 7) * cols.size()) % cols.size()]


## A shell two voxels thick: an outer layer (seen from outside) and an inner
## one (seen only through a gap). Neither ever shows through the other.
static func _ball(vox: Dictionary, c: Vector3, r: float, outer: Array[Color], inner: Array[Color]) -> void:
	var lo := Vector3i((c - Vector3.ONE * r).floor())
	var hi := Vector3i((c + Vector3.ONE * r).ceil())
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			for z in range(lo.z, hi.z + 1):
				var v := Vector3i(x, y, z)
				var d := (Vector3(v) + Vector3(0.5, 0.5, 0.5) - c).length()
				if d <= r and d >= r - 2.0:
					vox[v] = _pick(outer if d >= r - 1.0 else inner, v)


## The sprite projected through the ball along z: each voxel takes the pixel
## of its column, so the front is the sprite and the back its mirror. A band
## `side_band` degrees wide round each side (x), whose columns are the
## sprite's thin edge, takes its columns folded instead: from the band's edges
## (matching the projection there) in to the sprite's middle at the side's
## centre; each column's front-most face and back-most face still take the
## column's own pixel, so the front and back are exact. In caps `bottom_cap`
## and `top_cap` degrees round the ball's bottom and top, the faces looking
## down or up take the sprite's middle column row by row, so the caps are
## round seen from below or above (the Eye's iris, which it turns on you).
## Where its column is see-through the voxel goes (both layers: a gap right
## through, like the Eye's mouth); the band never cuts gaps of its own.
## With `back_inset` 0 or more the back half and the sides (outside the front
## 180 - side_band degrees) aren't the mirror image or the sprite's edge:
## each of their voxels takes a pixel of its row's flank (the brightest few
## of the pixels from `back_inset` in from the silhouette's edge on its side,
## passing over dark dull ones: shadows and sockets; a row with none borrows
## the nearest row's), so a skull's back is plain bone and a hat's is its
## crown and brim, not the face again. So do the faces looking down or up
## (the ledges between rows: the chin seen from below is bone, not the teeth
## dragged back, and a hat's brim is red underneath).
static func _project(vox: Dictionary, c: Vector3, r: float, art: Image, side_band: float, bottom_cap: float, top_cap: float, faces: Dictionary,
		solid := false, back_inset := -1, body := {}) -> void:
	var w := art.get_width()
	var h := art.get_height()
	var edge := deg_to_rad(90.0 - side_band * 0.5)
	# Each row's flank colours, left and right: [row] -> [left, right].
	var spans := _flanks(art, back_inset) if back_inset >= 0 else {}
	var flank := func(v: Vector3i, left: bool) -> Color:
		var pick: Array = spans[v.y][0 if left else 1]
		return pick[int(BlockModelMesh._hash(v.x, v.y, v.z, 3, 5) * pick.size()) % pick.size()]
	for v: Vector3i in vox.keys():
		var own := art.get_pixel(v.x, v.y) if v.x >= 0 and v.x < w and v.y >= 0 and v.y < h else Color(0, 0, 0, 0)
		if own.a <= 0.5:
			vox.erase(v)
			continue
		# (A solid body keeps only its surface: every voxel is coloured.)
		var p := Vector3(v) + Vector3(0.5, 0.5, 0.5) - c
		if not solid and p.length() < r - 1.0:
			continue
		var off := p.x
		var a := atan2(absf(p.x), absf(p.z))  # 0 facing front or back, PI / 2 facing the side
		if a > edge:
			off = signf(p.x) * Vector2(p.x, p.z).length() * sin(edge) * (PI * 0.5 - a) / (PI * 0.5 - edge)
		var px := floori(c.x + off)
		var col := art.get_pixel(px, v.y) if px >= 0 and px < w and v.y >= 0 and v.y < h else Color(0, 0, 0, 0)
		# The band only colours (where its pixel is see-through it keeps the
		# ball's): gaps come from the columns themselves, so the Eye's mouth
		# is an oval seen from below, not a cross.
		if back_inset >= 0 and (p.z < 0.0 or a > edge) and spans.has(v.y):
			col = flank.call(v, p.x < 0.0)
		if col.a > 0.5:
			vox[v] = col
		# Art y runs down: +y is the ball's bottom.
		if v.y >= 0 and v.y < h and (p.angle_to(Vector3.DOWN) < deg_to_rad(top_cap) or p.angle_to(Vector3.UP) < deg_to_rad(bottom_cap)):
			var mid := art.get_pixel(floori(c.x), v.y)
			if mid.a > 0.5:
				faces[v] = {BlockModelMesh.FACE_UP: mid, BlockModelMesh.FACE_DOWN: mid}
	# The ledges between rows, seen from below or above: the flanks' colours.
	if back_inset >= 0:
		var columns: Dictionary = body.get("columns", {})
		var filled := func(q: Vector3i) -> bool:
			if not solid:
				return vox.has(q)
			var cr = columns.get(Vector2i(q.x, q.y))
			return cr != null and q.z >= cr.x and q.z <= cr.y
		for v: Vector3i in vox:
			if not spans.has(v.y):
				continue
			for d in [[Vector3i(0, 1, 0), BlockModelMesh.FACE_DOWN], [Vector3i(0, -1, 0), BlockModelMesh.FACE_UP]]:
				if not filled.call(v + d[0]):
					if not faces.has(v):
						faces[v] = {}
					faces[v][d[1]] = flank.call(v, v.x + 0.5 < c.x)
	# What the front and back show: each column's nearest face, its pixel.
	var near := {}
	var far := {}
	for v: Vector3i in vox:
		var k := Vector2i(v.x, v.y)
		if not near.has(k) or v.z > near[k]:
			near[k] = v.z
		if not far.has(k) or v.z < far[k]:
			far[k] = v.z
	for k: Vector2i in near:
		var own := art.get_pixel(k.x, k.y)
		for end in [[Vector3i(k.x, k.y, near[k]), BlockModelMesh.FACE_FRONT], [Vector3i(k.x, k.y, far[k]), BlockModelMesh.FACE_BACK]]:
			if not faces.has(end[0]):
				faces[end[0]] = {}
			var back: bool = end[1] == BlockModelMesh.FACE_BACK and back_inset >= 0 and spans.has(k.y)
			faces[end[0]][end[1]] = vox[end[0]] if back else own


## Each row's flank colours (project's back_inset): [left, right] lists of
## the brightest few pixels from `inset` to inset + 7 in from the
## silhouette's edge, passing over dark dull ones; a row with none of its own
## borrows the nearest row's.
static func _flanks(art: Image, inset: int) -> Dictionary:
	var w := art.get_width()
	var out := {}
	var own := {}
	for y in art.get_height():
		var first := -1
		var last := -1
		for x in w:
			if art.get_pixel(x, y).a > 0.5:
				last = x
				if first < 0:
					first = x
		if first < 0:
			continue
		var sides := []
		for left in [true, false]:
			var light: Array[Color] = []
			for i in range(inset, inset + 8):
				var x: int = first + i if left else last - i
				if x < first or x > last:
					break
				var col := art.get_pixel(x, y)
				if col.a > 0.5 and (col.get_luminance() >= DARK_LIGHT or col.s > DARK_MAX_SAT):
					light.append(col)
			light.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() > b.get_luminance())
			# (Not a shade much darker than the brightest: no stripes round the back.)
			var keep: Array[Color] = []
			for col in light.slice(0, 3):
				if col.get_luminance() >= 0.8 * light[0].get_luminance():
					keep.append(col)
			sides.append(keep)
		out[y] = sides
		own[y] = [not sides[0].is_empty(), not sides[1].is_empty()]
	for y: int in out:
		for i in 2:
			if own[y][i]:
				continue
			for dy in range(1, art.get_height()):
				var near := -1
				if own.has(y - dy) and own[y - dy][i]:
					near = y - dy
				elif own.has(y + dy) and own[y + dy][i]:
					near = y + dy
				if near >= 0:
					out[y][i] = out[near][i]
					break
			if out[y][i].is_empty():
				out[y][i] = [art.get_pixel(clampi(w / 2, 0, w - 1), y)]
	return out


## A solid body spun from the sprite's silhouette (a slime): each row's span of
## opaque pixels becomes an ellipse round its middle, `depth` times as deep as
## it is wide, in `color`. Only its surface goes in `vox` (each opaque pixel's
## column of voxels is in `body.columns` as its first and last z); returns its
## middle.
static func _revolve(vox: Dictionary, art: Image, depth: float, cols: Array[Color], body: Dictionary) -> Vector3:
	var w := art.get_width()
	var mz := w * 0.5
	var top := -1
	var bottom := -1
	var columns := {}
	for y in art.get_height():
		var first := -1
		var last := -1
		for x in w:
			if art.get_pixel(x, y).a > 0.5:
				last = x
				if first < 0:
					first = x
		if first < 0:
			continue
		if top < 0:
			top = y
		bottom = y
		var cx := (first + last + 1) * 0.5
		var a := (last - first + 1) * 0.5
		var b := minf(a * depth, mz)
		for x in range(first, last + 1):
			if art.get_pixel(x, y).a <= 0.5:
				continue  # a gap in the row (a slime's feet in the air)
			var dx := (x + 0.5 - cx) / a
			var half := b * sqrt(maxf(0.0, 1.0 - dx * dx))
			var z0 := ceili(mz - half - 0.5)
			var z1 := floori(mz + half - 0.5)
			if z1 < z0:
				z0 = floori(mz)
				z1 = z0
			columns[Vector2i(x, y)] = Vector2i(z0, z1)
	_surface(vox, columns, cols)
	body["columns"] = columns
	return Vector3(w * 0.5, (top + bottom + 1) * 0.5, mz)


## A solid body's surface voxels (in `cols`): each column's ends, and the
## depths its neighbours don't reach.
static func _surface(vox: Dictionary, columns: Dictionary, cols: Array[Color]) -> void:
	for k: Vector2i in columns:
		var r: Vector2i = columns[k]
		var lo := r.x
		var hi := r.y
		var whole := false
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			if not columns.has(k + d):
				whole = true
				break
			var n: Vector2i = columns[k + d]
			lo = maxi(lo, n.x)
			hi = mini(hi, n.y)
		for z in range(r.x, r.y + 1):
			if whole or z <= maxi(lo - 1, r.x) or z >= mini(hi + 1, r.y) or lo > hi:
				var v := Vector3i(k.x, k.y, z)
				vox[v] = _pick(cols, v)


## Hollows in a solid body's front (a skull's eye sockets, nose and the gaps
## between its teeth): each pixel darker than `light` (luminance) and duller
## than `max_sat` (HSV; so a hat's dark red folds stay) sinks, `depth` voxels where
## it's as dark as `dark` or darker, less as it lightens, so the sockets are
## bowls. Rebuilds the surface (in `cols`, before project colours it).
static func _carve(vox: Dictionary, art: Image, op: Dictionary, cols: Array[Color], body: Dictionary) -> void:
	if not body.has("columns"):
		return
	var columns: Dictionary = body.columns
	var depth := float(op.get("depth", 4.0))
	var light := float(op.get("light", DARK_LIGHT))
	var dark := float(op.get("dark", 0.15))
	var max_sat := float(op.get("max_sat", DARK_MAX_SAT))
	for k: Vector2i in columns:
		var col := art.get_pixel(k.x, k.y)
		var lum := col.get_luminance()
		if lum >= light or col.s > max_sat:
			continue
		var r: Vector2i = columns[k]
		var sink := roundi(depth * clampf((light - lum) / maxf(light - dark, 0.001), 0.0, 1.0))
		columns[k] = Vector2i(r.x, maxi(r.x, r.y - sink))
	vox.clear()
	_surface(vox, columns, cols)


## What's inside a solid body (voxels() `body`): for the mesher, which mustn't
## draw faces against it. Invalid when there's no body.
static func solid_test(body: Dictionary) -> Callable:
	if not body.has("columns"):
		return Callable()
	var columns: Dictionary = body.columns
	return func(v: Vector3i) -> bool:
		var r = columns.get(Vector2i(v.x, v.y))
		return r != null and v.z >= r.x and v.z <= r.y


## The sprite without its outline (PixelArt.without_outline: recoloured, the
## silhouette as it is).
static func without_outline(art: Image) -> Image:
	return PixelArt.without_outline(art)


## Fills the inside of the ball on the rows where the sprite has gaps in it
## (the Eye's open mouth), behind its opaque pixels (front and back still show
## the shell), leaving a cavity: an oval as wide as the sprite's gap and
## `aspect` times as long front to back, so that seen from below the mouth is
## that oval, ringed by `count` teeth (`ring` voxels deep), then a lip, then
## the ball's skin, instead of the whole open bottom. Every face looking down
## on those rows is painted with that pattern (no one sees them from the front
## or back), so seen from below the oval is clean whatever pieces of the shell
## the sprite leaves there.
static func _mouth(vox: Dictionary, c: Vector3, r: float, art: Image, op: Dictionary, faces: Dictionary) -> void:
	var w := art.get_width()
	var rows: Array[int] = []
	var half := 1.0  # the gap's half width at its widest
	for y in art.get_height():
		# Gaps between the row's first and last opaque pixels (not its outside).
		var first := -1
		var last := -1
		for x in w:
			if art.get_pixel(x, y).a > 0.5:
				last = x
				if first < 0:
					first = x
		var widest := 0.0
		for x in range(first + 1, last):
			var dx := x + 0.5 - c.x
			if art.get_pixel(x, y).a <= 0.5 and Vector2(dx, y + 0.5 - c.y).length() < r - 1.0:
				widest = maxf(widest, absf(dx) + 0.5)
		if widest > 0.0:
			rows.append(y)
			half = maxf(half, widest)
	var ax := half
	var az := half * float(op.get("aspect", 1.8))
	var ring := float(op.get("ring", 3.0))
	var lip := float(op.get("lip", 1.5))
	var count := int(op.get("count", 14))
	var flesh := _colors(op.color)
	var teeth := _colors(op.teeth)
	var lips := _colors(op.get("lip_color", op.color))
	var skin := _colors(op.skin)
	# The pattern at a voxel: flesh inside the oval, then teeth, lip, skin.
	var pattern := func(v: Vector3i, p: Vector3) -> Color:
		var e := Vector2(p.x / ax, p.z / az)
		if e.length() < 1.0:
			return _pick(flesh, v)
		var out := (e.length() - 1.0) * minf(ax, az)  # voxels out from the edge, roughly
		if out < ring:
			return _pick(teeth, v) if fposmod(atan2(e.y, e.x) * count / TAU, 1.0) < 0.55 else _pick(flesh, v)
		return _pick(lips, v) if out < ring + lip else _pick(skin, v)
	for y in rows:
		for x in w:
			if art.get_pixel(x, y).a <= 0.5:
				continue
			for z in w:
				var v := Vector3i(x, y, z)
				var p := Vector3(v) + Vector3(0.5, 0.5, 0.5) - c
				if vox.has(v) or p.length() >= r - 2.0 or Vector2(p.x / ax, p.z / az).length() < 1.0:
					continue  # taken, the shell, or the cavity
				vox[v] = pattern.call(v, p)
	var on_rows := {}
	for y in rows:
		on_rows[y] = true
	for v: Vector3i in vox:
		if on_rows.has(v.y):
			if not faces.has(v):
				faces[v] = {}
			faces[v][BlockModelMesh.FACE_DOWN] = pattern.call(v, Vector3(v) + Vector3(0.5, 0.5, 0.5) - c)


## The sprite's pixels outside the ball (its tendrils), each where it is seen
## from the front, two voxels deep; the higher above the ball, the further it
## drifts from the middle in depth (up to `drift` voxels, `rise` pixels up),
## by a gentle wave across the sprite (`wave` per pixel), so neighbouring
## pixels stay joined and the tendrils fan out round the ball.
static func _outside(vox: Dictionary, c: Vector3, r: float, art: Image, drift: float, rise: float, wave: float) -> void:
	for y in art.get_height():
		for x in art.get_width():
			var col := art.get_pixel(x, y)
			if col.a <= 0.5:
				continue
			var dx := x + 0.5 - c.x
			if Vector2(dx, y + 0.5 - c.y).length() <= r:
				continue
			# How far above the ball's top at this column (beside it: none).
			var top := c.y - sqrt(maxf(0.0, r * r - dx * dx))
			var t := clampf((top - y) / rise, 0.0, 1.0)
			var z := floori(c.z + t * drift * sin(x * wave + 1.3) - 1.0)
			for dz in 2:
				var v := Vector3i(x, y, z + dz)
				if not vox.has(v):
					vox[v] = col
