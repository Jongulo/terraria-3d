class_name WofTexture
## The Wall of Flesh's body (WallOfFlesh.png's pink bubbly flesh), made
## rather than tiled from the sprite: a seamless tile of bubbles in its own
## colours, random-looking, at the art's pixel size (16 art pixels a block).

## Terraria's flesh colours (WallOfFlesh.png), darkest first, and the share of
## the flesh each covers.
const PALETTE := [[Color8(66, 31, 45), 11.6], [Color8(75, 35, 50), 21.2], [Color8(103, 45, 66), 32.1], [Color8(158, 47, 83), 18.3],
		[Color8(183, 77, 112), 7.8], [Color8(191, 93, 126), 5.3], [Color8(201, 113, 144), 1.0], [Color8(209, 131, 159), 2.6]]


## A tile of `size` art pixels: bubbles on a jittered grid of `cells` (wrapped,
## so it tiles), each a lit dome, dark creases where they meet (a power
## diagram: straight creases between bubbles of any size). Slow waves that
## tile (whole periods across it) vary the bubbles' size and brightness.
static func flesh(size: int, cells: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cell := float(size) / cells
	var waves := []
	for k in 4:
		waves.append([rng.randi_range(1, 3), rng.randi_range(1, 3), rng.randf() * TAU, rng.randf_range(0.5, 1.0)])
	var wave := func(v: Vector2) -> float:
		var t := 0.0
		for w in waves:
			t += w[3] * sin(TAU * (w[0] * v.x + w[1] * v.y) / size + w[2])
		return t / 2.5
	# Each grid cell's bubbles: [centre, radius, brightness].
	var grid := []
	for gy in cells:
		for gx in cells:
			var here := []
			for k in (2 if rng.randf() < 0.3 else 1):
				var c := Vector2((gx + rng.randf()) * cell, (gy + rng.randf()) * cell)
				var big: float = 1.0 + 0.25 * wave.call(c)
				here.append([c, cell * rng.randf_range(0.5, 0.9) * big * (0.7 if k > 0 else 1.0), rng.randf_range(-0.15, 0.15) + 0.12 * wave.call(c + Vector2(size * 0.37, size * 0.61))])
			grid.append(here)
	var shade := PackedFloat32Array()
	shade.resize(size * size)
	var light := Vector3(-0.55, -0.6, 0.6).normalized()
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var gx := int(p.x / cell)
			var gy := int(p.y / cell)
			var best := INF
			var second := INF
			var bq := Vector2.ZERO
			var br := 1.0
			var bb := 0.0
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					var cx := posmod(gx + ox, cells)
					var cy := posmod(gy + oy, cells)
					for b in grid[cy * cells + cx]:
						var d: Vector2 = p - b[0]
						d.x -= roundf(d.x / size) * size
						d.y -= roundf(d.y / size) * size
						var pw: float = d.length_squared() - b[1] * b[1]
						if pw < best:
							second = best
							best = pw
							bq = d / b[1]
							br = b[1]
							bb = b[2]
						elif pw < second:
							second = pw
			var h := sqrt(maxf(0.0, 1.0 - bq.length_squared()))
			var n := Vector3(bq.x, bq.y, h).normalized()
			var s: float = 0.55 * h + 0.6 * maxf(0.0, n.dot(light)) + bb
			# The crease between two bubbles (power distance gap, in pixels).
			var crease := clampf((sqrt(maxf(0.0, second - best)) - 1.0) / (br * 0.6), 0.0, 1.0)
			s *= lerpf(0.2, 1.0, crease)
			if bq.length() > 1.0:
				s *= 0.35
			shade[y * size + x] = s
	# Colours by share: the darkest 11.6% get the darkest colour, and so on.
	var sorted := shade.duplicate()
	sorted.sort()
	var cuts := []
	var acc := 0.0
	for c in PALETTE:
		acc += c[1]
		cuts.append(sorted[clampi(int(acc / 100.0 * sorted.size()) - 1, 0, sorted.size() - 1)])
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var s: float = shade[y * size + x]
			var k := 0
			while k < cuts.size() - 1 and s > cuts[k]:
				k += 1
			img.set_pixel(x, y, PALETTE[k][0])
	return img
