class_name Whip
extends Node3D
## Terraria's whips (Projectile.AI_165_Whip, FillWhipControlPoints,
## Main.DrawWhip_*), in its pixels (24 a block) and ticks. A crack lasts the
## whip's use time (faster with summon weapon speed: Snapthorn's Jungle's
## Fury); each tick the whip is a chain of control points from your hand,
## its segments `segments` of them, flying out and curling over and back
## (Terraria works them out in 2D, aimed right; here that plane holds your
## aim and a slant down and left across it, from your right hand). Every
## enemy any part of it passes through (Terraria's 18 px box at each point,
## now and a tick ago) is hit once a crack, each for less than the one before
## (the whip's falloff: the Leather Whip's half), and is tagged for 240
## ticks: your minions' hits on it do the whip's tag damage more (the
## Snapthorn's also poison it 1 in 5, and give you its speed buff), and it's
## your minions' target from then on. The Meteor Whip's tag readies a
## falling meteor for your minions' next hit on it (1.33x that hit).

const PX := 24.0
const TICK := 1.0 / 60.0
## Each whip, by its ProjectileID name (GetWhipSettings, the falloff in
## Damage_PVE_Inner, Sets.UniqueTagEffects, Main.DrawWhip): segments,
## range (rangeMultiplier), falloff (damage kept after each enemy), tag
## damage, speed (its shootSpeed, px a tick: how far it reaches), rows of its sheet and how its middle uses them ("bland": by how
## far along, "cycle3" / "cycle4": in turn, "lerp": spread along it, every
## third drawn), its string's colour, buff it gives you (BuffID name, ticks).
const KINDS := {
	"BlandWhip": {"speed": 4, "segments": 20, "range": 0.75, "falloff": 0.5, "tag": 4, "rows": 5, "middle": "bland", "string": [1.0, 1.0, 1.0]},
	"SlimeWhip": {"speed": 4, "segments": 36, "range": 0.75, "falloff": 0.4, "tag": 3, "rows": 5, "middle": "lerp", "string": [78 / 255.0, 136 / 255.0, 1.0]},
	"CobWhip": {"speed": 3, "segments": 12, "range": 0.75, "falloff": 0.4, "tag": 3, "rows": 6, "middle": "cycle4", "string": [0.5, 0.5, 0.5]},
	"CorruptWhip": {"speed": 4, "segments": 20, "range": 0.95, "falloff": 0.6, "tag": 5, "rows": 6, "middle": "cycle4", "shrink": 0.5,
		"string": [0.5, 0.0, 0.5], "crack": "NPC_Killed_1"},
	"CrimsonWhip": {"speed": 4, "segments": 20, "range": 0.85, "falloff": 0.6, "tag": 5, "rows": 6, "middle": "cycle4", "shrink": 0.5,
		"string": [1.0, 0.0, 0.0], "crack": "NPC_Hit_9"},
	"MeteorWhip": {"speed": 4, "segments": 20, "range": 1.1, "falloff": 0.7, "tag": 2, "rows": 6, "middle": "lerp", "proc": "meteor",
		"string": [88 / 255.0, 85 / 255.0, 155 / 255.0]},
	"ThornWhip": {"speed": 4, "segments": 20, "range": 1.0, "falloff": 0.6, "tag": 6, "rows": 5, "middle": "cycle3", "poison": [5, 180],
		"buff": ["ThornWhipPlayerBuff", 180], "string": [34 / 255.0, 139 / 255.0, 34 / 255.0]},
	"BoneWhip": {"speed": 5, "segments": 20, "range": 0.95, "falloff": 0.9, "tag": 7, "rows": 5, "middle": "cycle3", "string": [210 / 255.0, 180 / 255.0, 140 / 255.0]},
}
## The whip's own box at each point (its projectile: 18 x 18 px).
const HIT_BOX := 9.0 / PX
const TAG_TICKS := 240

var player: Player
var def := {}
var kind := ""
var cfg := {}
## Its time out (ticks) and how far through it is (Terraria's ai[0]).
var duration := 30.0
var ticks := 0.0
## How much it curls (Terraria's ai[1]: 0.6 to 1).
var curl := 1.0
## Enemies hit this crack, in order.
var hit: Array = []
var _acc := 0.0
var _aim := Vector3.FORWARD
var _down := Vector3.DOWN
var _prev := PackedVector3Array()
var _line := MeshInstance3D.new()
var _mesh := ImmediateMesh.new()
var _sprites: Array[EntitySprite] = []
var _size := Vector3.ONE
var _cracked := false


func setup(p: Player, item: Dictionary) -> void:
	player = p
	def = item
	kind = item.whip
	cfg = KINDS[kind]
	curl = 0.6 + 0.4 * randf()
	# Your summon weapon speed (Jungle's Fury's 12%) cracks it faster.
	duration = float(item.get("use_time", 30)) / (1.0 + p.stat("whip_speed") / 100.0)
	# Its plane: your aim, and across it down and to your left, so it
	# comes over your right shoulder and cracks down across your view.
	_aim = p.forward()
	var basis := p.camera.global_transform.basis
	var across := -basis.y * 0.85 - basis.x * 0.5
	_down = (across - _aim * across.dot(_aim)).normalized()
	_line.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	_line.material_override = mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)
	var tex := Assets.texture("Images/Projectile_%d" % int(Assets.ids.ProjectileID.get(kind, 841)))
	var rows := int(cfg.rows)
	var frame := Vector2(tex.get_width(), tex.get_height() / float(rows))
	for i in int(cfg.segments) + 1:
		var s := EntitySprite.new()
		s.setup(tex, rows, frame / PX, true, true)
		add_child(s)
		_sprites.append(s)
	_size = _sprites[0].scale


## Your hand: right of and below your eyes, a little ahead.
func hand() -> Vector3:
	var cam := player.camera.global_transform
	return cam.origin + cam.basis.x * 0.45 - cam.basis.y * 0.4 - cam.basis.z * 0.45


## Terraria's FillWhipControlPoints at `t` ticks, its 2D points (px, y down,
## aimed right) turned into the world. `full`: fully curled (its hit test).
func points(t: float, full := false) -> PackedVector3Array:
	var segs := int(cfg.segments)
	var p := t / duration
	if kind == "CobWhip":
		p = remap(clampf(p, 0.0, 1.0), 0.0, 1.0, 0.3, 0.95)
	var l4 := 0.5
	var l5 := 1.0 + l4
	var turn := 31.4159 * (1.0 - p * l5) * -1.0 / segs
	var out_k := p * l5
	var back := 0.0
	if out_k > 1.0:
		back = (out_k - 1.0) / l4
		out_k = lerpf(1.0, 0.0, back)
	var reach := float(def.get("use_time", 30)) * 2.0 * p
	var seg := float(cfg.speed) * reach * out_k * float(cfg.range) / segs
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var c := Vector2.ZERO
	var ang_a := -PI / 2.0
	var ang_b := PI
	var ang_c := PI / 2.0
	var k := 1.0 if full else curl
	var spin := PI / 2.0 + 4.71239 * back * back
	var origin := hand()
	var pts := PackedVector3Array([origin])
	for i in segs:
		var step := turn * (float(i) / segs) * k
		var na := a + Vector2.from_angle(ang_a) * seg
		var nc := c + Vector2.from_angle(ang_c) * seg * 2.0
		var nb := b + Vector2.from_angle(ang_b) * seg * 2.0
		var ease := 1.0 - (1.0 - out_k) * (1.0 - out_k)
		var mid := nc.lerp(na, ease * 0.9 + 0.1)
		var q := nb.lerp(mid, ease * 0.7 + 0.3)
		q = Vector2(q.x, q.y * l5).rotated(spin)
		pts.append(origin + _aim * q.x / PX + _down * q.y / PX)
		ang_a += step
		ang_c += step
		ang_b += step
		a = na
		c = nc
		b = nb
	return pts


func _physics_process(delta: float) -> void:
	var game := Game.current
	if not is_instance_valid(player) or not player.alive:
		queue_free()
		return
	_acc += delta
	while _acc >= TICK and not is_queued_for_deletion():
		_acc -= TICK
		_tick(game)
	if not is_queued_for_deletion():
		_draw(game)


func _tick(game) -> void:
	ticks += 1.0
	if ticks >= duration:
		queue_free()
		return
	if not _cracked and ticks >= floorf(duration / 2.0):
		_cracked = true
		var tip := points(ticks)[-1]
		Audio.play_at(cfg.get("crack", "Item_153"), tip, 0.8)
	# Its hits: any part of it now or a tick ago.
	var now := points(ticks, true)
	var before := points(ticks - 1.0, true) if ticks > 1.0 else now
	for npc in game.npcs():
		if npc in hit or npc.untouchable or npc.dont_take_damage or npc.def.ai == "town":
			continue
		for i in range(1, now.size()):
			if _touches(npc, now[i], before[i]):
				_strike(game, npc)
				break


## Its box at a point, swept from where that point was a tick ago.
func _touches(npc, a: Vector3, b: Vector3) -> bool:
	var h := Vector3(HIT_BOX, HIT_BOX * 2.0, HIT_BOX)
	for s in 3:
		var at := b.lerp(a, s / 2.0)
		if npc.overlaps_box(at - Vector3(0, HIT_BOX, 0), h):
			return true
	return false


func _strike(game, npc) -> void:
	var base := float(player.weapon_damage(def))
	for i in hit.size():
		base *= float(cfg.falloff)
	hit.append(npc)
	var dir: Vector3 = (npc.center() - player.center()).normalized()
	npc.hit(maxi(1, int(base)), player.weapon_knockback(def), dir, player.crit_chance(def))
	if not is_instance_valid(npc) or npc.life <= 0:
		return
	# Its tag: your minions' hits on it do more, and they go for it.
	npc.whip_tag = {"damage": int(cfg.tag), "crit": int(cfg.get("crit", 0)), "until": Engine.get_physics_frames() + TAG_TICKS,
			"proc": cfg.get("proc", "")}
	player.minion_target = npc
	player.imbue_hit(npc)
	if cfg.has("poison") and randi() % int(cfg.poison[0]) == 0:
		npc.poison(float(cfg.poison[1]) / 60.0)
	if cfg.has("buff"):
		player.timed_buffs[cfg.buff[0]] = float(cfg.buff[1]) / 60.0


func _draw(game) -> void:
	var pts := points(ticks)
	var cam: Camera3D = player.view()
	# The string through it, in the whip's colour.
	var sc: Array = cfg.string
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in pts:
		_mesh.surface_set_color(Color(sc[0], sc[1], sc[2]))
		_mesh.surface_add_vertex(to_local(p))
	_mesh.surface_end()
	# Its segments: the handle, the middle by Terraria's rule, the tip.
	var rows := int(cfg.rows)
	var last := pts.size() - 2
	for i in _sprites.size():
		var s := _sprites[i]
		if i > last:
			s.visible = false
			continue
		var row := 0
		var shown := true
		if i == last:
			row = rows - 1
		elif i > 0:
			match cfg.middle:
				"bland":
					row = 1 if i <= 10 else (2 if i <= 20 else 3)
				"cycle3":
					row = 1 + i % 3
				"cycle4":
					shown = i != 1
					row = 1 + i % 4
				"lerp":
					row = int(round(lerpf(1.0, float(maxi(1, rows - 2)), float(i - 1) / maxf(1.0, last - 1.0))))
					shown = i % 3 == 0
		s.visible = shown
		if not shown:
			continue
		s.global_position = pts[i]
		s.set_frame(row)
		var along := pts[i + 1] - pts[i]
		if along.length() > 0.001:
			s.set_rotation_angle(EntitySprite.facing_angle(cam, along))
		var scale_k := 1.0
		if i == last and cfg.middle == "bland":
			var p := ticks / duration
			scale_k = lerpf(0.5, 1.5, _lerp01(0.1, 0.7, p) * _lerp01(0.9, 0.7, p))
		elif cfg.has("shrink") and i > 0:
			scale_k = remap(clampf(float(i), 5.0, last * 0.75), 5.0, last * 0.75, float(cfg.shrink), 1.0)
		# Near your eyes it's drawn smaller (a whole sprite at arm's length
		# would fill your view): to scale from 2 blocks off.
		scale_k *= clampf(cam.global_position.distance_to(pts[i]) / 2.0, 0.3, 1.0)
		s.scale = _size * scale_k
		s.update_light(game.world, game.sky, pts[i])


static func _lerp01(from: float, to: float, x: float) -> float:
	return clampf((x - from) / (to - from), 0.0, 1.0)
