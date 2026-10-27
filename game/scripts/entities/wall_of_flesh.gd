class_name WallOfFlesh
extends Node3D
## The Wall of Flesh (Terraria's aiStyle 27 mouth, 28 eyes, 29 the Hungry;
## NPC.SpawnWOF, Player.WOFTongue), in 3D: one giant wall of flesh across the
## whole world east to west, from the Underworld's floor up past its ceiling,
## sweeping from the north to the south through everything. Its mouth (the
## WallofFlesh NPC, whose life is the boss's) keeps in front of you along it,
## midway between the floor and ceiling there; its two eyes (WallofFleshEye,
## sharing the mouth's life) above and below it, halfway to the ceiling and
## floor, turn to look at you and fire lasers; eleven Hungry on tethers lunge
## at you from it; it spits Leeches.
##
## - It comes 1200 px (50 blocks: NPCs' 24 px a block) north of you and moves south at 1.5 px a
##   tick, 0.25 faster below 75% of its life, 0.4 more below half, 0.5 more
##   below a quarter and 0.6 more below a tenth.
## - Leeches: a count up a tick (twice below half, three times below a
##   fifth); past 2700, one every 60 ticks (velocity 8 px a tick its way),
##   three (four below 30%) then the count starts over; at most ten about.
## - Eyes: a count up a tick (more as it weakens: +1 below 75%, +1 below
##   half, +1 below a quarter, +2 below a tenth); after 600 they fire, every
##   45, while they can see you and you're in front, 4 lasers (5, 6, 8, 11 as
##   it weakens) then rest 600 again. A laser (EyeLaser) is 9 px a tick
##   (three moves a tick) and 11 damage, 10/12 below half, 11/13 below a
##   quarter, 13/15 below a tenth (doubled on you, as Terraria's hostile
##   shots).
## - The Hungry: eleven at the start, each tethered to its own spot on the
##   wall; they reach 300 px from it (500 and defense 20, 45 damage below
##   75%; 700, defense 30 and 60 damage below half), 1.3 times further each
##   100 of every 200 ticks.
## - You: in the Underworld within sight of it (1920 px) you're Horrified;
##   Horrified, leave the Underworld or get behind the wall and you're
##   Tongued: hauled to 200 px in front of its mouth at 11 px a tick, unable
##   to use anything. Tongued more than 3000 px from it, or with the wall at
##   the world's edge, you die. Horrified, the wall itself (its 140 px)
##   hurts 50.
## - You dead: 3 seconds and it's gone. Beaten: its loot (the mouth's), and
##   Hardmode ("The ancient spirits of light and dark have been released.").

signal beaten

## px a tick -> blocks a second, and px -> blocks (NPCs' scale: 24 px a block).
const PX_TICK := NPC.PX_TICK
const PX := NPC.PX_PER_BLOCK
const SPAWN_AWAY := 1200.0 / PX
const SIGHT := 1920.0 / PX
const TONGUE_SPEED := 11.0 * PX_TICK
const TONGUE_REACH := 3000.0 / PX
const TONGUE_FRONT := 200.0 / PX
const BAND := 140.0 / PX
const WALL_DAMAGE := 50
## Terraria's death text for it (DeathText.WasLicked).
const LICKED := "You were licked."
const HUNGRY := 11
const MAX_LEECHES := 10
## How far the eyes sit forward of the wall, and the mouth; the eyes at
## least this far above and below the mouth.
const FACE_OUT := 2.0
const EYE_APART := 10.5
const PART_DEPTH := 4.0
## How far the mouth and eyes turn from straight out of the wall toward you.
const MOUTH_TURN := deg_to_rad(45.0)
const EYE_TURN := deg_to_rad(70.0)

var mouth: NPC
var eyes: Array[NPC] = []
var hungry: Array[NPC] = []
## The wall's place along z, and which way it goes (+1: south).
var z := 0.0
var dir := 1.0
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
## Its middle and its reach up and down where the mouth is.
var _mid := 0.0
var _top := 0.0
var _bottom := 0.0
var _leech_count := 0.0
var _leech_phase := 0
var _leech_t := 0.0
var _roar := 0.0
var _gone := 0.0
var _ended := false
## The eyes' counts (localAI[1]) and shots in their burst (localAI[2]).
var _eye_t := [0.0, 0.0]
var _eye_shots := [0, 0]
## The Hungry's anchors (fractions across and up the wall) and their counts.
var _anchors: Array[Vector2] = []
var _tex_task := -1
static var _flesh: ImageTexture
static var _flesh_image: Image


## Brings it on in `game`, north of the player (Terraria's SpawnWOF).
static func spawn(game) -> WallOfFlesh:
	if game.wof != null and is_instance_valid(game.wof):
		return null
	var wof := WallOfFlesh.new()
	game.entities.add_child(wof)
	game.wof = wof
	wof._begin(game)
	return wof


func _begin(game) -> void:
	var p = game.player
	z = maxf(p.global_position.z - SPAWN_AWAY, 4.0)
	dir = 1.0
	var w: VoxelWorld = game.world
	var size: Vector3i = w.get_size()
	_mid = clampf(p.global_position.y + 2.0, 6.0, game.underworld_level - 2.0)
	_top = _mid + 10.0
	_bottom = _mid - 10.0
	# The wall: across the world, the Underworld's floor up past its ceiling.
	_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	var height: float = game.underworld_level + 8.0
	q.size = Vector2(size.x, height)
	_mesh.mesh = q
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color8(103, 45, 66)
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.uv1_scale = Vector3(size.x / 16.0, height / 16.0, 1)
	_mesh.material_override = _material
	_mesh.position = Vector3(size.x * 0.5, height * 0.5, 0)
	add_child(_mesh)
	_texture_later()
	global_position = Vector3(0, 0, z)
	# The mouth, its eyes, the Hungry.
	var at := Vector3(p.global_position.x, _mid, z + FACE_OUT)
	mouth = game.spawn_npc("WallofFlesh", at)
	# (Their boxes as deep as the models stand out of the wall, not as wide.)
	mouth.half.z = PART_DEPTH
	for k in 2:
		var e: NPC = game.spawn_npc("WallofFleshEye", at + Vector3(0, 8.0 if k == 0 else -8.0, 0))
		e.life_owner = mouth
		e.half.z = PART_DEPTH
		eyes.append(e)
	for i in HUNGRY:
		# Terraria's ai[0]: i x 0.1 - 0.05 up the wall; here spread across too.
		_anchors.append(Vector2((i - (HUNGRY - 1) * 0.5) * 2.6, i * 0.1 - 0.05))
		var h: NPC = game.spawn_npc("TheHungry", at)
		hungry.append(h)
	_roar = randf_range(600.0, 1600.0) / 60.0
	_place(game, 0.0)
	Audio.play("Roar_0")
	game.message("Wall of Flesh has awoken!", Color(0.69, 0.29, 1.0))


## The flesh texture (WallOfFlesh: the wall's bubbles), made off the main thread the first time.
func _texture_later() -> void:
	if _flesh != null:
		_material.albedo_texture = _flesh
		_material.albedo_color = Color.WHITE
		return
	_tex_task = WorkerThreadPool.add_task(func(): _flesh_image = WofTexture.flesh(256, 36, 7))


func _physics_process(delta: float) -> void:
	var game := Game.current
	if game == null or _ended:
		return
	if _tex_task >= 0 and WorkerThreadPool.is_task_completed(_tex_task):
		WorkerThreadPool.wait_for_task_completion(_tex_task)
		_tex_task = -1
		_flesh = ImageTexture.create_from_image(_flesh_image)
		_material.albedo_texture = _flesh
		_material.albedo_color = Color.WHITE
	if mouth == null or not is_instance_valid(mouth) or mouth.life <= 0:
		_end(game, true)
		return
	var p = game.player
	if not p.alive:
		# Its prey dead: 3 seconds, and it goes (localAI[1] + 1/180 a tick).
		_gone += delta
		if _gone >= 3.0:
			_end(game, false)
		return
	_gone = 0.0
	var share := float(mouth.life) / float(mouth.life_max)
	var speed := 1.5
	if share < 0.75:
		speed += 0.25
	if share < 0.5:
		speed += 0.4
	if share < 0.25:
		speed += 0.5
	if share < 0.1:
		speed += 0.6
	z += dir * speed * PX_TICK * delta
	global_position = Vector3(0, 0, z)
	var size: Vector3i = game.world.get_size()
	if z >= size.z - 10.0 or z <= 2.0:
		# Out of the world: anyone it held dies with it gone (WOFTongue).
		if p.has_buff("Horrified"):
			p.die_by(LICKED)
		_end(game, false)
		return
	_place(game, delta)
	_leeches(game, share, delta)
	_roars(delta)
	for k in eyes.size():
		if is_instance_valid(eyes[k]):
			_eye_fire(game, k, share, delta)
	_tongue(game, p)


## The mouth before you along the wall, midway between the floor and the
## ceiling there; the eyes halfway to them; the Hungry on their tethers.
func _place(game, delta: float) -> void:
	var p = game.player
	var mx: float = mouth.global_position.x
	var want := clampf(p.global_position.x, 4.0, game.world.get_size().x - 4.0)
	mx = move_toward(mx, want, 12.0 * maxf(delta, 0.0)) if delta > 0.0 else want
	# The floor and ceiling at the mouth (Terraria scans its columns).
	var ul: float = game.underworld_level
	var floor_y := _scan(game, mx, -1)
	var ceil_y := _scan(game, mx, 1)
	var mid := clampf((floor_y + ceil_y) * 0.5, 5.0, ul + 2.0)
	_mid = move_toward(_mid, mid, PX_TICK * maxf(delta, 0.0)) if delta > 0.0 else mid
	_top = ceil_y
	_bottom = floor_y
	mouth.global_position = Vector3(mx, _mid - mouth.half.y, z + FACE_OUT)
	mouth.aim_at(_turned(mouth, p.center(), MOUTH_TURN))
	for k in eyes.size():
		var e := eyes[k]
		if not is_instance_valid(e):
			continue
		# (Never into the mouth: they're as big.)
		var ey := maxf((_mid + _top) * 0.5, _mid + EYE_APART) if k == 0 else minf((_mid + _bottom) * 0.5, _mid - EYE_APART)
		var target := Vector3(mx, ey - e.half.y, z + FACE_OUT)
		e.global_position = e.global_position.move_toward(target, 5.0 * PX_TICK * maxf(delta, 0.0)) if delta > 0.0 else target
		e.global_position.z = z + FACE_OUT
		e.global_position.x = mx
		e.aim_at(_turned(e, p.center(), EYE_TURN))
		# (Its life is the mouth's: the bar shows it.)
		e.life = mouth.life
		e.life_max = mouth.life_max
	for i in hungry.size():
		var h := hungry[i]
		if is_instance_valid(h):
			h.tether = anchor(i)


## Where `part` looks to look at `at`: out of the wall, turned toward it by
## at most `most` radians.
func _turned(part: NPC, at: Vector3, most: float) -> Vector3:
	var out := Vector3(0, 0, dir)
	var to := (at - part.center()).normalized()
	var a := out.angle_to(to)
	if a > most:
		to = out.slerp(to, most / a)
	return part.center() + to * 10.0


## Where the Hungry `i` is tethered.
func anchor(i: int) -> Vector3:
	var a := _anchors[i]
	return Vector3(mouth.global_position.x + a.x, _bottom + (_top - _bottom) * clampf(a.y, 0.0, 1.0), z + 0.5)


## The nearest floor (`up` -1) or ceiling (+1) from the middle at x, along the wall.
func _scan(game, x: float, up: int) -> float:
	var w: VoxelWorld = game.world
	var ul: float = game.underworld_level
	var y := _mid
	var limit := 30.0
	for i in int(limit):
		y += up
		if y < 1.0 or y > ul + 6.0:
			break
		var solid := 0
		for dx in [-2, 0, 2]:
			if w.is_solid(Vector3i(int(x) + dx, int(y), int(z))):
				solid += 1
		if solid >= 2:
			return y
	return _mid + limit * up


## Leeches spat out its mouth (ai[1], ai[2]).
func _leeches(game, share: float, delta: float) -> void:
	var ticks := delta * 60.0
	_leech_count += ticks * (1.0 + (1.0 if share < 0.5 else 0.0) + (1.0 if share < 0.2 else 0.0)) if _leech_phase == 0 else ticks
	if _leech_phase == 0:
		if _leech_count > 2700.0:
			_leech_phase = 1
			_leech_count = 0.0
		return
	if _leech_count <= 60.0:
		return
	_leech_count = 0.0
	_leech_phase += 1
	var most := 3 + (1 if share < 0.3 else 0)
	if _leech_phase > most:
		_leech_phase = 0
	if game.npcs().filter(func(n): return n.kind == "LeechHead").size() < MAX_LEECHES:
		var l: NPC = game.spawn_npc("LeechHead", mouth.center() + Vector3(0, 0, mouth.half.x))
		if l != null:
			l.velocity = Vector3(0, 0, dir * 8.0 * PX_TICK)


func _roars(delta: float) -> void:
	_roar -= delta
	if _roar <= 0.0:
		_roar = randf_range(600.0, 1600.0) / 60.0 - randf_range(0.0, 200.0) / 60.0
		Audio.play_at("NPC_Killed_10", mouth.center())


## An eye's lasers (localAI[1], localAI[2]).
func _eye_fire(game, k: int, share: float, delta: float) -> void:
	var e := eyes[k]
	var p = game.player
	var rate := 1.0
	var burst := 4
	if share < 0.75:
		rate += 1.0
		burst += 1
	if share < 0.5:
		rate += 1.0
		burst += 1
	if share < 0.25:
		rate += 1.0
		burst += 2
	if share < 0.1:
		rate += 2.0
		burst += 3
	_eye_t[k] += rate * delta * 60.0
	if _eye_shots[k] == 0:
		if _eye_t[k] > 600.0:
			_eye_shots[k] = 1
			_eye_t[k] = 0.0
		return
	if _eye_t[k] <= 45.0 or not e._sees(p):
		return
	_eye_t[k] = 0.0
	_eye_shots[k] += 1
	if _eye_shots[k] > burst:
		_eye_shots[k] = 0
	# Only at you in front of it.
	if (p.center().z - z) * dir <= 0.0:
		return
	var speed := 9.0
	var dmg := 11
	if share < 0.5:
		speed += 1.0
		dmg += 1
	if share < 0.25:
		speed += 1.0
		dmg += 1
	if share < 0.1:
		speed += 2.0
		dmg += 2
	var to: Vector3 = (p.center() - e.center()).normalized()
	# Three moves a tick (its extraUpdates 2).
	game.spawn_projectile("EyeLaser", e.center() + to * 1.5, to * speed * 3.0 * PX_TICK, dmg * 2, 0.0, 0.0, 0.0, 0.5, false)
	Audio.play_at("Item_33", e.center(), 0.6)


## Horrified, Tongued, and the wall's touch.
func _tongue(game, p) -> void:
	var ul: float = game.underworld_level
	var pc: Vector3 = p.center()
	var horrified: bool = p.has_buff("Horrified")
	if not horrified and pc.y < ul and absf(pc.z - z) < SIGHT:
		p.debuff("Horrified", 10.0 / 60.0)
		Audio.play_at("NPC_Killed_10", mouth.center())
		horrified = true
	elif horrified:
		p.debuff("Horrified", 10.0 / 60.0)
	if not horrified:
		return
	# Behind it, or out of the Underworld: its tongue.
	if pc.y > ul + 1.0 or (pc.z - z) * dir < -1.0:
		p.debuff("TheTongue", 10.0 / 60.0)
	var front: Vector3 = mouth.center() + Vector3(0, 0, dir * TONGUE_FRONT)
	if p.has_buff("TheTongue"):
		if pc.distance_to(mouth.center()) > TONGUE_REACH:
			p.die_by(LICKED)
			return
		p.tongue_to = front
	else:
		p.tongue_to = Vector3.INF
	# The wall itself.
	var into: float = (pc.z - z) * dir
	if into > -BAND * 0.5 and into < FACE_OUT and p.alive:
		p.hurt(WALL_DAMAGE, Vector3(pc.x, pc.y, z), false, mouth)


func _end(game, won: bool) -> void:
	if _ended:
		return
	_ended = true
	game.player.tongue_to = Vector3.INF
	for e in eyes:
		if is_instance_valid(e):
			if won:
				# (Its eyes die with it: their gore.)
				e.gib(game, Data.npc_gore.get("WallofFleshEye", {}).get("gores", []))
			e.queue_free()
	for h in hungry:
		if is_instance_valid(h):
			h.queue_free()
	if not won and is_instance_valid(mouth) and mouth.life > 0:
		mouth.queue_free()
	if won:
		beaten.emit()
	game.wof = null
	queue_free()


func _exit_tree() -> void:
	var game := Game.current
	if game != null and game.player != null:
		game.player.tongue_to = Vector3.INF
