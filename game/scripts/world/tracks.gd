class_name Tracks
## Minecart tracks (Terraria's tile 314) in 3D. A track cell is drawn and
## ridden from the track cells beside it: it joins a neighbour along x or z on
## its own level or a cell up or down (a cell up: it rises to meet it, 45
## degrees as Terraria's slopes). Two sides joined straight across make a
## straight run (or a ramp); two at right angles a corner, a quarter circle
## round the cell's corner; one side an end; none, a piece along its placed
## facing. A shape is its entry side, exit side and the height (0 or 1) of
## each end: (a | b << 2 | ha << 4 | hb << 5).
##
## The minecart (Player._cart) rides the shape's path: point(shape, s) from
## its entry end (s 0) to its exit end (s 1), RAIL_TOP over the rails' feet.

## The sides, by index: +x, +z, -x, -z.
const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)]
## Height of the rails' top over the track's path (a cart's wheels ride on it).
const RAIL_TOP := 3.5 / 16.0
const TIE_COLOR := Color(0.42, 0.27, 0.16)
const RAIL_COLOR := Color(0.58, 0.58, 0.62)
const RAIL_EDGE := Color(0.32, 0.32, 0.36)

static var _meshes := {}


static func is_track(world, p: Vector3i) -> bool:
	return Data.block(world.get_block(p)).get("track", false)


## The track beside `p` on side `d`: on its level (0), a cell up (1) or down
## (-1); 2 for none.
static func link(world, p: Vector3i, d: int) -> int:
	for dy in [0, 1, -1]:
		if is_track(world, p + DIRS[d] + Vector3i(0, dy, 0)):
			return dy
	return 2


## The track cell at `p`'s shape (see the class doc). `facing`: a lone
## piece's side (0-3), its placed facing.
static func shape(world, p: Vector3i, facing := 0) -> int:
	var sides: Array[int] = []
	for d in 4:
		if link(world, p, d) != 2:
			sides.append(d)
	var a := (facing + 2) % 4
	var b := facing % 4
	if sides.size() == 1:
		b = sides[0]
		a = (b + 2) % 4
	elif sides.size() >= 2:
		a = sides[0]
		b = sides[1]
		# A straight run if it has one (a junction runs straight).
		for i in sides:
			if (i + 2) % 4 in sides:
				a = i
				b = (i + 2) % 4
				break
	var ha := 0
	var hb := 0
	if (a + 2) % 4 == b:
		ha = 1 if link(world, p, a) == 1 else 0
		hb = 1 if link(world, p, b) == 1 else 0
	return a | (b << 2) | (ha << 4) | (hb << 5)


## A placed block's rotation (quarter turns of the yaw it was placed with:
## even looking along z) as the side a lone piece runs toward.
static func facing(rotation: int) -> int:
	return 1 if posmod(rotation, 2) == 0 else 0


static func entry(sh: int) -> int:
	return sh & 3


static func exit(sh: int) -> int:
	return (sh >> 2) & 3


## The shape ridden from side `from` (its other end the exit).
static func from_side(sh: int, from: int) -> int:
	if entry(sh) == from:
		return sh
	return exit(sh) | (entry(sh) << 2) | (((sh >> 5) & 1) << 4) | (((sh >> 4) & 1) << 5)


static func is_corner(sh: int) -> bool:
	return (entry(sh) + 2) % 4 != exit(sh)


## How high the path is at `s` (0-1 of a block over the cell's floor).
static func height(sh: int, s: float) -> float:
	var ha := float((sh >> 4) & 1)
	var hb := float((sh >> 5) & 1)
	if ha > 0.0 and hb > 0.0:
		return absf(2.0 * s - 1.0)  # a dip between two higher cells
	return lerpf(ha, hb, s)


## The path at `s`, from the cell's floor centre.
static func point(sh: int, s: float) -> Vector3:
	var ea := Vector3(DIRS[entry(sh)]) * 0.5
	var eb := Vector3(DIRS[exit(sh)]) * 0.5
	var xz: Vector3
	if is_corner(sh):
		var c := ea + eb
		var t := s * PI / 2.0
		xz = c - eb * cos(t) - ea * sin(t)
	else:
		xz = ea.lerp(eb, s)
	return Vector3(xz.x, height(sh, s), xz.z)


## The path's direction at `s` (unit).
static func tangent(sh: int, s: float) -> Vector3:
	var e := 0.01
	var a := clampf(s - e, 0.0, 1.0)
	var b := clampf(s + e, 0.0, 1.0)
	return (point(sh, b) - point(sh, a)).normalized()


## The path's length in blocks.
static func length(sh: int) -> float:
	var n := 8
	var l := 0.0
	for i in n:
		l += point(sh, float(i + 1) / n).distance_to(point(sh, float(i) / n))
	return l


## The next track cell from `p` out of its shape's exit, and the side it's
## entered by: [cell, side], or [] at the track's end.
static func next(world, p: Vector3i, sh: int) -> Array:
	var b := exit(sh)
	var dy := link(world, p, b)
	if dy == 2:
		return []
	return [p + DIRS[b] + Vector3i(0, dy, 0), (b + 2) % 4]


## A shape's mesh: wooden ties across it, two rails along it (vertex colours).
static func mesh(sh: int) -> ArrayMesh:
	if _meshes.has(sh):
		return _meshes[sh]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [1.0 / 6.0, 0.5, 5.0 / 6.0]:
		var at := point(sh, s)
		var t := tangent(sh, s)
		var across := Vector3(-t.z, 0.0, t.x).normalized()
		var up := across.cross(t).normalized()
		if up.y < 0.0:
			up = -up
		_box(st, at + up * (1.5 / 32.0), t * (2.5 / 16.0), across * 0.92, up * (3.0 / 32.0), TIE_COLOR)
	var n := 8 if is_corner(sh) or height(sh, 0.5) != lerpf(height(sh, 0.0), height(sh, 1.0), 0.5) else 1
	for side in [-1.0, 1.0]:
		for i in n:
			var s0 := float(i) / n
			var s1 := float(i + 1) / n
			var a := point(sh, s0)
			var b := point(sh, s1)
			var t := (b - a).normalized()
			var across := Vector3(-t.z, 0.0, t.x).normalized()
			var up := across.cross(t).normalized()
			if up.y < 0.0:
				up = -up
			# From the ties' top (3/32) to RAIL_TOP.
			var mid: Vector3 = (a + b) * 0.5 + across * side * 0.3 + up * ((RAIL_TOP + 3.0 / 32.0) * 0.5)
			_box(st, mid, t * (a.distance_to(b) + 0.02), across * (1.5 / 16.0), up * (RAIL_TOP - 3.0 / 32.0), RAIL_COLOR)
	st.generate_normals()
	var m := st.commit()
	_meshes[sh] = m
	return m


## A box centred at `c`, its three edges `x`, `y`, `z` (full lengths), its
## top `color` and its sides darker.
static func _box(st: SurfaceTool, c: Vector3, x: Vector3, y: Vector3, z: Vector3, color: Color) -> void:
	var hx := x * 0.5
	var hy := y * 0.5
	var hz := z * 0.5
	var p := func(i: int, j: int, k: int) -> Vector3: return c + hx * i + hy * j + hz * k
	var faces := [
		[p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1), color],  # top
		[p.call(-1, 1, -1), p.call(1, 1, -1), p.call(1, -1, -1), p.call(-1, -1, -1), color.darkened(0.5)],
		[p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1), color.darkened(0.25)],
		[p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1), p.call(-1, 1, -1), color.darkened(0.25)],
		[p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1), p.call(1, -1, 1), color.darkened(0.15)],
		[p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1), p.call(-1, -1, -1), color.darkened(0.15)],
	]
	for f in faces:
		st.set_color(f[4])
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(f[i])
