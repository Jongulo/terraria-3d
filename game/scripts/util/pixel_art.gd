class_name PixelArt
## Terraria's art is drawn at an integer scale (most sprites are 2x: every
## visible pixel is a 2x2 block of texture pixels). Voxel models are built at
## that "art pixel" resolution, so one voxel = one pixel of the original art.

## Fraction of k x k blocks that must be a single colour to accept scale k.
const MIN_UNIFORM := 0.98

static var _cache := {}


## Detects the art scale: Vector3i(scale, grid offset x, grid offset y).
static func detect_scale(img: Image) -> Vector3i:
	var key := img.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var result := Vector3i(1, 0, 0)
	for k in [4, 3, 2]:
		if img.get_width() < k or img.get_height() < k:
			continue
		for o in k * k:
			if _uniform_ratio(img, k, o % k, o / k) >= MIN_UNIFORM:
				result = Vector3i(k, o % k, o / k)
				break
		if result.x > 1:
			break
	_cache[key] = result
	return result


static func _uniform_ratio(img: Image, k: int, ox: int, oy: int) -> float:
	var total := 0
	var good := 0
	for by in range(oy, img.get_height() - k + 1, k):
		for bx in range(ox, img.get_width() - k + 1, k):
			var c := img.get_pixel(bx, by)
			var ok := true
			for y in k:
				for x in k:
					var p := img.get_pixel(bx + x, by + y)
					if (p.a > 0.5) != (c.a > 0.5) or (p.a > 0.5 and not p.is_equal_approx(c)):
						ok = false
			total += 1
			if ok:
				good += 1
	return float(good) / maxi(total, 1)


## The sprite at art resolution (one pixel per art pixel).
static func downsample(img: Image, scale: Vector3i) -> Image:
	if scale.x <= 1:
		return img
	var k := scale.x
	var w := (img.get_width() - scale.y) / k
	var h := (img.get_height() - scale.z) / k
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			out.set_pixel(x, y, img.get_pixel(scale.y + x * k, scale.z + y * k))
	return out


## Pixel-art 2x upscalers (ImageMagick's magnify methods): every pixel becomes
## 2x2, and corners take a neighbour's colour where the rule sees an edge.
## They only copy existing colours, so the palette and hard alpha are kept.
##   scale2x  (EPX) a corner takes the two equal neighbours it sits between
##   eagle    a corner takes its diagonal neighbour when the three around it match
##   epb      EPX with extra checks that keep thin lines and corners intact
const MAGNIFIERS := ["scale2x", "eagle", "epb"]


static func scale2x(img: Image) -> Image:
	return magnify2x(img, "scale2x")


static func magnify2x(img: Image, method: String) -> Image:
	var src := img
	if src.get_format() != Image.FORMAT_RGBA8:
		src = img.duplicate()
		src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	var p := src.get_data().to_int32_array()
	var out := PackedInt32Array()
	out.resize(w * h * 4)
	var n := PackedInt32Array()
	n.resize(9)
	var r := PackedInt32Array()
	r.resize(4)
	for y in h:
		for x in w:
			# 3x3 neighbourhood, row-major (4 = centre), edges clamped.
			for i in 9:
				n[i] = p[clampi(y + i / 3 - 1, 0, h - 1) * w + clampi(x + i % 3 - 1, 0, w - 1)]
			r.fill(n[4])  # TL, TR, BL, BR
			match method:
				"scale2x":
					if n[1] != n[7] and n[3] != n[5]:
						if n[1] == n[3]: r[0] = n[3]
						if n[1] == n[5]: r[1] = n[5]
						if n[3] == n[7]: r[2] = n[3]
						if n[5] == n[7]: r[3] = n[5]
				"eagle":
					if n[0] == n[1] and n[1] == n[3]: r[0] = n[0]
					if n[1] == n[2] and n[2] == n[5]: r[1] = n[2]
					if n[3] == n[6] and n[6] == n[7]: r[2] = n[6]
					if n[5] == n[8] and n[8] == n[7]: r[3] = n[8]
				"epb":
					if n[3] != n[5] and n[1] != n[7] and (n[4] == n[3] or n[4] == n[7] or n[4] == n[5] or n[4] == n[1] \
							or ((n[0] != n[8] or n[4] == n[6] or n[3] == n[2]) and (n[6] != n[2] or n[4] == n[0] or n[4] == n[8]))):
						if _epb(n, 1, 3, 4, 0, 8, 2, 6): r[0] = n[1]
						if _epb(n, 5, 1, 4, 2, 6, 8, 0): r[1] = n[5]
						if _epb(n, 3, 7, 4, 6, 2, 0, 8): r[2] = n[3]
						if _epb(n, 7, 5, 4, 8, 0, 6, 2): r[3] = n[7]
			var o := (y * 2) * (w * 2) + x * 2
			out[o] = r[0]
			out[o + 1] = r[1]
			out[o + w * 2] = r[2]
			out[o + w * 2 + 1] = r[3]
	return Image.create_from_data(w * 2, h * 2, false, Image.FORMAT_RGBA8, out.to_byte_array())


static func _epb(n: PackedInt32Array, a: int, b: int, c: int, d: int, e: int, f: int, g: int) -> bool:
	return n[a] == n[b] and (n[c] == n[d] or n[c] == n[e] or n[a] == n[f] or n[b] == n[g])


## Pixel noise over the opaque pixels, in `cell` x `cell` pixel patches:
##   speckle  each patch a bit lighter or darker
##   palette  some patches step one shade lighter or darker on the sprite's own
##            colour ramp (colours of a similar hue), so no new colours appear
##   hue      small hue and brightness shifts
##   blotch   soft large patches of light and shade, plus a little speckle
const NOISES := ["none", "speckle", "palette", "hue", "blotch"]


static func noise(img: Image, mode: String, strength: float, cell: int, seed: int) -> Image:
	if mode == "none" or strength <= 0.0:
		return img
	var out: Image = img.duplicate()
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	var w := out.get_width()
	var h := out.get_height()
	cell = maxi(1, cell)
	var ramp := {}  # colour (rgba32) -> [its ramp darkest to lightest, its index]
	if mode == "palette":
		var cols := {}
		for y in h:
			for x in w:
				var c := out.get_pixel(x, y)
				if c.a > 0.5:
					cols[c.to_rgba32()] = c
		var all: Array = cols.values()
		all.sort_custom(func(a: Color, b: Color): return a.get_luminance() < b.get_luminance())
		for c in all:
			var r := all.filter(func(o: Color): return _hue_close(c, o))
			ramp[c.to_rgba32()] = [r, r.find(c)]
	var blotches := _ValueNoise.new(seed + 17, 12.0)
	for y in h:
		for x in w:
			var c := out.get_pixel(x, y)
			if c.a <= 0.5:
				continue
			var k := Vector3i(x / cell, y / cell, seed)
			var r1 := (absi(hash(k)) % 10000) / 10000.0
			var r2 := (absi(hash(k + Vector3i(0, 0, 7777))) % 10000) / 10000.0
			match mode:
				"speckle":
					c = _scaled(c, 1.0 + (r1 * 2.0 - 1.0) * 0.18 * strength)
				"palette":
					if r1 < strength * 0.45:
						var e: Array = ramp[c.to_rgba32()]
						var step := -1 if r2 < 0.5 else 1
						c = e[0][clampi(e[1] + step, 0, e[0].size() - 1)]
				"hue":
					c.h = fposmod(c.h + (r1 * 2.0 - 1.0) * 0.035 * strength, 1.0)
					c.v = clampf(c.v * (1.0 + (r2 * 2.0 - 1.0) * 0.1 * strength), 0.0, 1.0)
				"blotch":
					c = _scaled(c, 1.0 + blotches.at(x, y) * 0.16 * strength + (r1 * 2.0 - 1.0) * 0.06 * strength)
			out.set_pixel(x, y, c)
	return out


static func _hue_close(a: Color, b: Color) -> bool:
	if a.s < 0.15 and b.s < 0.15:
		return true
	var d := absf(a.h - b.h)
	return minf(d, 1.0 - d) < 0.06


static func _scaled(c: Color, m: float) -> Color:
	return Color(clampf(c.r * m, 0, 1), clampf(c.g * m, 0, 1), clampf(c.b * m, 0, 1), c.a)


## Smooth warp: every pixel copies the pixel at a small, smoothly varying
## offset (value noise with `cell`-pixel features, up to `amp` pixels), so
## shapes bend organically while staying crisp. The offset fades to zero over
## the bottom `fade` rows, keeping whatever sits there (e.g. a trunk stub) put.
## `pad` adds transparent margin on the left, right and top for the silhouette
## to spread into. With `tile_y` the warp repeats vertically (no top margin):
## the top and bottom rows move the same way, so stacked tiles (tree trunks)
## still line up, and pixels pushed past one end come from the other.
static func warp(img: Image, amp: float, cell: float, seed: int, fade := 0, pad := 0, tile_y := false) -> Image:
	var src := img
	if src.get_format() != Image.FORMAT_RGBA8:
		src = img.duplicate()
		src.convert(Image.FORMAT_RGBA8)
	var sw := src.get_width()
	var sh := src.get_height()
	var w := sw + pad * 2
	var h := sh if tile_y else sh + pad
	var top := 0 if tile_y else pad
	var p := src.get_data().to_int32_array()
	var out := PackedInt32Array()
	out.resize(w * h)
	# Repeating vertically: a whole number of noise cells per tile height.
	var rows := maxi(1, roundi(h / cell)) if tile_y else 0
	var nx := _ValueNoise.new(seed, cell, rows, float(h) / rows if tile_y else cell)
	var ny := _ValueNoise.new(seed + 7919, cell, rows, float(h) / rows if tile_y else cell)
	for y in h:
		var f := 1.0
		if fade > 0:
			f = smoothstep(0.0, 1.0, float(h - 1 - y) / fade)
		for x in w:
			var sx := int(round(x - pad + amp * f * nx.at(x, y)))
			var sy := int(round(y - top + amp * f * ny.at(x, y)))
			if tile_y:
				sy = posmod(sy, sh)
			out[y * w + x] = p[sy * sw + sx] if sx >= 0 and sy >= 0 and sx < sw and sy < sh else 0
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out.to_byte_array())


## 2D value noise in [-1, 1]: random lattice values every `cell` pixels
## (`cell_y` vertically), smoothstep-interpolated; repeats every `period_y`
## lattice rows when that is above 0.
class _ValueNoise:
	var _cell: float
	var _cell_y: float
	var _period_y: int
	var _seed: int
	var _grid := {}

	func _init(noise_seed: int, cell: float, period_y := 0, cell_y := -1.0) -> void:
		_seed = noise_seed
		_cell = cell
		_period_y = period_y
		_cell_y = cell if cell_y <= 0.0 else cell_y

	func _lattice(x: int, y: int) -> float:
		if _period_y > 0:
			y = posmod(y, _period_y)
		var k := Vector2i(x, y)
		if not _grid.has(k):
			_grid[k] = (hash(Vector3i(x, y, _seed)) % 20001) / 10000.0 - 1.0
		return _grid[k]

	func at(x: float, y: float) -> float:
		var fx := x / _cell
		var fy := y / _cell_y
		var x0 := floori(fx)
		var y0 := floori(fy)
		var tx := smoothstep(0.0, 1.0, fx - x0)
		var ty := smoothstep(0.0, 1.0, fy - y0)
		var a := lerpf(_lattice(x0, y0), _lattice(x0 + 1, y0), tx)
		var b := lerpf(_lattice(x0, y0 + 1), _lattice(x0 + 1, y0 + 1), tx)
		return lerpf(a, b, ty)
