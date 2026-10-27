class_name WofSculpt
## The Wall of Flesh's mouth and eyes (handmade_npc_models.json's
## "wall_of_flesh" op), sculpted so that seen from the side (along z: the
## sprite's own view) the model is the sprite, pixel for pixel - its outline,
## its gaps and its colours - and seen from anywhere else it's round:
##   body:     the flesh ball (the sprite's pixels inside the ellipse fitted
##             to its flesh and eyeball) inflated from its outline, thick in
##             the middle and thin at its edge; the mouth's gap (where the
##             sprite is see-through inside the ball) cut right through, so
##             the jaws are as thick as the ball would be there;
##   teeth:    each tooth pixel copied into fangs across the jaw, a few
##             voxels apart: a row of fangs seen from the front;
##   eyeball:  its pale pixels inflated on their own, so the eye bulges out
##             of the flesh, its pupil (and a dark red iris) looking straight
##             out (-x), red veins wandering over it;
##   tendrils: each of the sprite's pieces outside the ball a round tube along
##             its pixels, spreading out in depth the further it reaches from
##             the ball.
## Faces turned to the sides (along z) take the sprite's colours; the rest
## are coloured by what they are: the flesh as the wall's bubbles (its eight
## colours), the rest Terraria's colours lit from above and in front.
## Voxels are art pixels in NPCSculpt's box: x right (the wall at +x), y down,
## z across (0 to w - 1).

enum { EMPTY, FLESH, RIM, THROAT, TOOTH, EYE, VEIN, PUPIL, IRIS, TENDRIL }

## The wall's flesh colours (WallOfFlesh.png), darkest first, and their shares.
const FLESH_COLORS := [["#421f2d", 11.6], ["#4b2332", 21.2], ["#672d42", 32.1], ["#9e2f53", 18.3],
		["#b74d70", 7.8], ["#bf5d7e", 5.3], ["#c97190", 1.0], ["#d1839f", 2.6]]
const PALETTES := {
	RIM: ["#320d11", "#3e0f0f", "#6c1717", "#a61e1e"],
	THROAT: ["#110508", "#180608", "#320d11", "#4b2333"],
	TOOTH: ["#1d1810", "#3b2e1c", "#5c4a31", "#786243"],
	EYE: ["#b4b4b4", "#c4c4c4", "#d0d0d0", "#d7d7d7", "#dddddd"],
	VEIN: ["#6c1717", "#a61e1e", "#c23939"],
	PUPIL: ["#0a0204", "#180608"],
	IRIS: ["#320d11", "#4b2333", "#6c1717"],
	TENDRIL: ["#320d11", "#6c1717", "#a61e1e", "#c23939"],
}
const LIGHT := Vector3(-0.35, -1.0, -0.3)

enum { CLEAR, PINK, RED, PALE, DARK, BONE }


static func build(vox: Dictionary, art: Image, op: Dictionary) -> void:
	var w := art.get_width()
	var h := art.get_height()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(op.get("seed", 1))
	# What each pixel is.
	var kind := PackedByteArray()
	kind.resize(w * h)
	for y in h:
		for x in w:
			kind[x + w * y] = _classify(art.get_pixel(x, y))
	# The ball: the ellipse round its flesh and eyeball.
	var lo := Vector2(w, h)
	var hi := Vector2(-1, -1)
	for y in h:
		for x in w:
			if kind[x + w * y] in [PINK, PALE]:
				lo = Vector2(minf(lo.x, x), minf(lo.y, y))
				hi = Vector2(maxf(hi.x, x + 1), maxf(hi.y, y + 1))
	var centre := (lo + hi) * 0.5
	# (A little past the flesh, so the dark red rim round its back is the
	# ball's too, not tendrils.)
	var radii := (hi - lo) * 0.5 + Vector2(float(op.get("rim", 3.5)), 1.5)
	var in_ball := func(x: int, y: int) -> bool:
		return Vector2((x + 0.5 - centre.x) / radii.x, (y + 0.5 - centre.y) / radii.y).length_squared() <= 1.0
	var body := PackedByteArray()
	body.resize(w * h)
	var filled := PackedByteArray()
	filled.resize(w * h)
	var eye := PackedByteArray()
	eye.resize(w * h)
	var tendril := PackedByteArray()
	tendril.resize(w * h)
	for y in h:
		for x in w:
			var i := x + w * y
			var k := kind[i]
			if in_ball.call(x, y):
				filled[i] = 1
				if k == PALE or (k == DARK and _near(kind, w, h, x, y, PALE, 3)):
					eye[i] = 1
				elif k != CLEAR and k != BONE:
					body[i] = 1
			elif k != CLEAR:
				tendril[i] = 1
	# Half-depths: the ball inflated from its outline (the mouth's gap
	# included, so the jaws keep the ball's thickness), the eyeball on its own.
	var ball_depth := _inflate(filled, w, h, 1.0)
	var cz := w * 0.5
	var g := PackedByteArray()
	g.resize(w * h * w)
	var at := func(x: int, y: int, z: int) -> int: return x + w * (y + h * z)
	var fill := func(x: int, y: int, z0: float, z1: float, m: int) -> void:
		for z in range(maxi(0, floori(z0)), mini(w, ceili(z1))):
			if g[at.call(x, y, z)] == EMPTY or m == EYE or m == PUPIL:
				g[at.call(x, y, z)] = m
	for y in h:
		for x in w:
			var i := x + w * y
			if body[i]:
				var d := maxf(ball_depth[i], 1.0)
				fill.call(x, y, cz - d, cz + d, RIM if kind[i] == RED else FLESH)
	# The eyeball: a ball as tall as the white, its front at the white's
	# front, kept to the sprite's outline (so the side view stays the sprite).
	var ec := Vector3.ZERO
	var pupil := 0.3
	var e_lo := Vector2i(w, h)
	var e_hi := Vector2i(-1, -1)
	for y in h:
		for x in w:
			if eye[x + w * y]:
				e_lo = Vector2i(mini(e_lo.x, x), mini(e_lo.y, y))
				e_hi = Vector2i(maxi(e_hi.x, x), maxi(e_hi.y, y))
	if e_hi.x >= 0:
		var re := (e_hi.y - e_lo.y + 1) * 0.5
		ec = Vector3(e_lo.x + re, (e_lo.y + e_hi.y + 1) * 0.5, cz)
		for y in h:
			for x in w:
				var dd := re * re - pow(x + 0.5 - ec.x, 2) - pow(y + 0.5 - ec.y, 2)
				if dd > 0.0:
					# Behind the white it stays inside the flesh's thickness.
					var hz := sqrt(dd) if x <= e_hi.x else minf(sqrt(dd), ball_depth[x + w * y] - 1.0)
					if hz > 0.0:
						fill.call(x, y, cz - hz, cz + hz, EYE)
		var dark_rows := 0
		for y in h:
			for x in w:
				if eye[x + w * y] and kind[x + w * y] == DARK:
					dark_rows += 1
					break
		pupil = asin(clampf(dark_rows * 0.5 / re, 0.2, 0.47))
		# A round socket: no flesh in front of the eyeball.
		for z in w:
			for y in h:
				var rr := re * re - pow(y + 0.5 - ec.y, 2) - pow(z + 0.5 - ec.z, 2)
				if rr <= 0.0:
					continue
				var face := ec.x - sqrt(rr)
				for x in range(0, int(face)):
					if g[at.call(x, y, z)] in [FLESH, RIM]:
						g[at.call(x, y, z)] = EMPTY
	# Teeth: each of the sprite's teeth (at its depth into the mouth) a whole
	# row of fangs across the jaw, a fang every `teeth_apart` voxels, each
	# row staggered from the one before: row behind row of fangs seen from the
	# front, each the tooth's own shape seen from the side.
	var apart := float(op.get("teeth_apart", 6.0))
	var bone := PackedByteArray()
	bone.resize(w * h)
	for i in w * h:
		bone[i] = 1 if kind[i] == BONE and filled[i] else 0
	var teeth := _pieces(bone, w, h)
	# Each fang as thick as its tooth is wide there: pointed seen from the front.
	var fang := _inflate(bone, w, h, 0.55)
	for j in teeth.size():
		var piece: Array = teeth[j]
		var d := 1.0
		for p: Vector2i in piece:
			d = maxf(d, ball_depth[p.x + w * p.y] * 0.9)
		var n := maxi(1, int(2.0 * d / apart))
		var shift := 0.5 * (j % 2)
		for k in n:
			var zc := cz - d + (k + 0.5 + shift) / n * 2.0 * d
			if zc > cz + d:
				continue
			for p: Vector2i in piece:
				var r := clampf(fang[p.x + w * p.y], 0.5, 1.3)
				fill.call(p.x, p.y, zc - r, zc + r, TOOTH)
	# Tendrils: round tubes along the sprite's pieces outside the ball,
	# fanning out in depth away from it.
	var tube := _inflate(tendril, w, h, 1.0)
	var spread: float = op.get("spread", 0.8)
	for piece in _pieces(tendril, w, h):
		var root := Vector2(INF, 0)
		for p: Vector2i in piece:
			var dist := Vector2((p.x + 0.5 - centre.x) / radii.x, (p.y + 0.5 - centre.y) / radii.y).length()
			if dist < root.x:
				root = Vector2(dist, 0)
		# Off to one side or the other, never down the middle.
		var lean := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.35, 1.0) * spread * radii.y
		for p: Vector2i in piece:
			var out := Vector2((p.x + 0.5 - centre.x) / radii.x, (p.y + 0.5 - centre.y) / radii.y).length() - 1.0
			var zc := cz + lean * clampf(out / 0.8, 0.0, 1.0)
			var r := maxf(tube[p.x + w * p.y], 0.6)
			fill.call(p.x, p.y, zc - r, zc + r, TENDRIL)
	# The eye: its pupil and iris looking out (-x), veins over the white.
	if e_hi.x >= 0:
		_eye(g, at, w, h, ec, pupil, rng)
	# The mouth's throat: what you see looking into its gap (the see-through
	# pixels inside the ball with jaw above and below them).
	var gap := PackedByteArray()
	gap.resize(w * h)
	for x in w:
		for y in h:
			if not filled[x + w * y] or kind[x + w * y] not in [CLEAR, BONE]:
				continue
			var above := false
			var below := false
			for yy in range(y - 1, -1, -1):
				if body[x + w * yy]:
					above = true
					break
				if not filled[x + w * yy]:
					break
			for yy in range(y + 1, h):
				if body[x + w * yy]:
					below = true
					break
				if not filled[x + w * yy]:
					break
			gap[x + w * y] = 1 if above and below else 0
	for z in w:
		for y in h:
			for x in range(1, w):
				var m := g[at.call(x, y, z)]
				if (m == FLESH or m == RIM) and g[at.call(x - 1, y, z)] == EMPTY and gap[x - 1 + w * y]:
					g[at.call(x, y, z)] = THROAT
	_paint(vox, g, at, art, w, h, cz)


## A sprite colour's kind: see-through, the flesh's pinks, the reds (rim and
## tendrils), the eyeball's pale greys, the near-blacks, the teeth's browns.
static func _classify(c: Color) -> int:
	if c.a <= 0.5:
		return CLEAR
	var lum := 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
	if c.s < 0.15 and lum > 0.55:
		return PALE
	if lum < 0.09:
		return DARK
	var hue := c.h * 360.0
	if hue >= 20.0 and hue <= 60.0:
		return BONE
	if hue < 12.0 or hue > 352.0:
		return RED
	return PINK


static func _near(kind: PackedByteArray, w: int, h: int, x: int, y: int, k: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var xx := x + dx
			var yy := y + dy
			if xx >= 0 and yy >= 0 and xx < w and yy < h and kind[xx + w * yy] == k:
				return true
	return false


## A mask inflated: each pixel's half-depth as on a ball whose edge is the
## mask's outline (from its distance to the edge: sqrt(d (2R - d)), R the
## deepest), times `k`.
static func _inflate(mask: PackedByteArray, w: int, h: int, k: float) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(w * h)
	var big := 1e6
	for i in w * h:
		d[i] = big if mask[i] else 0.0
	# Chamfer distance (1, 1.414), forward then back.
	for pass_ in 2:
		var ys := range(h) if pass_ == 0 else range(h - 1, -1, -1)
		var xs := range(w) if pass_ == 0 else range(w - 1, -1, -1)
		var s := -1 if pass_ == 0 else 1
		for y in ys:
			for x in xs:
				var i: int = x + w * y
				if d[i] == 0.0:
					continue
				var best := d[i]
				for o in [Vector2i(s, 0), Vector2i(0, s), Vector2i(s, s), Vector2i(-s, s)]:
					var xx: int = x + o.x
					var yy: int = y + o.y
					var nd := 1.0 if xx < 0 or yy < 0 or xx >= w or yy >= h else d[xx + w * yy] + (1.414 if o.x != 0 and o.y != 0 else 1.0)
					best = minf(best, nd)
				d[i] = best
	var r := 0.0
	for i in w * h:
		r = maxf(r, d[i])
	var out := PackedFloat32Array()
	out.resize(w * h)
	for i in w * h:
		var v := d[i] - 0.5
		out[i] = sqrt(maxf(0.0, v * (2.0 * r - v))) * k if mask[i] else 0.0
	return out


## The mask's connected pieces (8-connected), each a list of Vector2i.
static func _pieces(mask: PackedByteArray, w: int, h: int) -> Array:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var out := []
	for y in h:
		for x in w:
			if not mask[x + w * y] or seen[x + w * y]:
				continue
			var piece: Array[Vector2i] = []
			var todo := [Vector2i(x, y)]
			seen[x + w * y] = 1
			while not todo.is_empty():
				var p: Vector2i = todo.pop_back()
				piece.append(p)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var q := p + Vector2i(dx, dy)
						if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and mask[q.x + w * q.y] and not seen[q.x + w * q.y]:
							seen[q.x + w * q.y] = 1
							todo.append(q)
			out.append(piece)
	return out


## The eyeball's pupil, iris and veins, by the direction from its middle.
static func _eye(g: PackedByteArray, at: Callable, w: int, h: int, ec: Vector3, pupil: float, rng: RandomNumberGenerator) -> void:
	var look := Vector3.LEFT
	var veins := []
	for k in 14:
		var a := rng.randf() * TAU
		veins.append([Vector3(0.1, sin(a), cos(a)).normalized(), rng.randf_range(0.35, 0.65)])
	for z in w:
		for y in h:
			for x in w:
				if g[at.call(x, y, z)] != EYE:
					continue
				var u := (Vector3(x + 0.5, y + 0.5, z + 0.5) - ec).normalized()
				var c := u.dot(look)
				if c > cos(pupil):
					g[at.call(x, y, z)] = PUPIL
				elif c > cos(pupil + 0.14):
					g[at.call(x, y, z)] = IRIS
	# Veins: wandering lines from round the back toward the iris.
	for v in veins:
		var u: Vector3 = v[0]
		var stop: float = v[1]
		for i in 60:
			var hit := _surface_along(g, at, w, h, ec, u)
			if hit != Vector3i(-1, -1, -1) and g[at.call(hit.x, hit.y, hit.z)] == EYE:
				g[at.call(hit.x, hit.y, hit.z)] = VEIN
			var side := u.cross(look).normalized() if absf(u.dot(look)) < 0.99 else Vector3.UP
			u = (u + look * 0.035 + side * rng.randf_range(-0.07, 0.07)).normalized()
			if u.dot(look) > stop:
				break


## The outermost eyeball voxel from `c` along `u`.
static func _surface_along(g: PackedByteArray, at: Callable, w: int, h: int, c: Vector3, u: Vector3) -> Vector3i:
	var last := Vector3i(-1, -1, -1)
	var t := 0.0
	while t < w:
		var q := Vector3i((c + u * t).floor())
		if q.x < 0 or q.y < 0 or q.z < 0 or q.x >= w or q.y >= h or q.z >= w:
			break
		var m := g[at.call(q.x, q.y, q.z)]
		if m in [EYE, VEIN, IRIS, PUPIL]:
			last = q
		elif last != Vector3i(-1, -1, -1):
			break
		t += 0.5
	return last


## The voxels that show, coloured: faces turned to the sides take the sprite's
## pixel (so the side view is the sprite); the rest by what they are.
static func _paint(vox: Dictionary, g: PackedByteArray, at: Callable, art: Image, w: int, h: int, cz: float) -> void:
	var light := -LIGHT.normalized()
	var flesh := []
	var flesh_shade := PackedFloat32Array()
	for z in w:
		for y in h:
			for x in w:
				var m := g[at.call(x, y, z)]
				if m == EMPTY:
					continue
				var n := Vector3.ZERO
				var shows := false
				for dz in range(-1, 2):
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							if dx == 0 and dy == 0 and dz == 0:
								continue
							var xx := x + dx
							var yy := y + dy
							var zz := z + dz
							if xx < 0 or yy < 0 or zz < 0 or xx >= w or yy >= h or zz >= w or g[at.call(xx, yy, zz)] == EMPTY:
								n += Vector3(dx, dy, dz)
								if absi(dx) + absi(dy) + absi(dz) == 1:
									shows = true
				if not shows:
					continue
				var v := Vector3i(x, y, z)
				n = n.normalized() if n.length() > 0.01 else Vector3.BACK
				# The side view: the outermost voxel each way along z is the sprite.
				var side := (z + 1 >= w or g[at.call(x, y, z + 1)] == EMPTY) or (z == 0 or g[at.call(x, y, z - 1)] == EMPTY)
				# (Not where it's only a voxel or two thick: seen from the front,
				# that's its middle, not its side.)
				if side and absf(n.z) >= 0.6 and absf(z + 0.5 - cz) >= 2.0 and art.get_pixel(x, y).a > 0.5 and m in [FLESH, RIM, TENDRIL]:
					vox[v] = art.get_pixel(x, y)
					continue
				var lit := clampf(n.dot(light) * 0.5 + 0.5, 0.0, 1.0)
				if m == FLESH:
					flesh.append(v)
					flesh_shade.append(_bubble(Vector3(v) + Vector3(0.5, 0.5, 0.5), n, 4.5, light) * 0.7 + lit * 0.3)
					continue
				var pal: Array = PALETTES[m]
				vox[v] = Color.html(pal[clampi(int(lit * pal.size()), 0, pal.size() - 1)])
	# The flesh: the wall's colours in their shares.
	var sorted := flesh_shade.duplicate()
	sorted.sort()
	var cuts := []
	var acc := 0.0
	for e in FLESH_COLORS:
		acc += float(e[1])
		cuts.append(sorted[clampi(int(acc / 100.0 * sorted.size()) - 1, 0, maxi(sorted.size() - 1, 0))] if not sorted.is_empty() else 0.0)
	for i in flesh.size():
		var s := flesh_shade[i]
		var k := 0
		while k < cuts.size() - 1 and s > cuts[k]:
			k += 1
		vox[flesh[i]] = Color.html(FLESH_COLORS[k][0])


## A bubbly surface's shade at `p`: the nearest bubble (a jittered grid of
## `cell`) lit as a little dome, dark where two bubbles meet.
static func _bubble(p: Vector3, n: Vector3, cell: float, light: Vector3) -> float:
	var g := (p / cell).floor()
	var best := INF
	var second := INF
	var bf := Vector3.ZERO
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var k := g + Vector3(dx, dy, dz)
				var f := (k + Vector3(_hash(k, 1), _hash(k, 2), _hash(k, 3))) * cell
				var d := p.distance_to(f)
				if d < best:
					second = best
					best = d
					bf = f
				elif d < second:
					second = d
	var bn := ((p - bf).normalized() * 0.7 + n * 0.3).normalized()
	var s := clampf(bn.dot(light) * 0.5 + 0.5, 0.0, 1.0)
	var crease := clampf((second - best) / (cell * 0.35), 0.0, 1.0)
	return s * lerpf(0.25, 1.0, crease)


static func _hash(k: Vector3, salt: int) -> float:
	var hv := int(k.x) * 73856093 ^ int(k.y) * 19349663 ^ int(k.z) * 83492791 ^ salt * 2654435761
	hv = (hv ^ (hv >> 13)) * 1274126177
	return float(posmod(hv ^ (hv >> 16), 100000)) / 100000.0
