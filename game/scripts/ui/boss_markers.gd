class_name BossMarkers
extends Control
## Terraria's boss head icons (NPC_Head_Boss_<n>) at the edge of the screen,
## each with an arrow pointing toward its boss while that boss is out of view
## (behind you or off to the side). In Terraria's wide 2D view a boss is
## rarely off screen; in first person it easily is.

## How far in from each edge the icons sit (in the HUD's units): clear of the
## hotbar and hearts at the top and the boss bar at the bottom.
const INSET_SIDE := 40.0
const INSET_TOP := 110.0
const INSET_BOTTOM := 140.0
## Each mark: [icon, where (local), arrow angle].
var marks := []


## Places a mark for each of `npcs` (those with a head icon) that `cam` can't see.
func update_marks(cam: Camera3D, npcs: Array) -> void:
	marks.clear()
	if cam != null:
		var screen := get_viewport_rect().size
		var to_local := get_global_transform_with_canvas().affine_inverse()
		var area := Rect2(Vector2(INSET_SIDE, INSET_TOP), size - Vector2(INSET_SIDE * 2.0, INSET_TOP + INSET_BOTTOM))
		var mid := area.get_center()
		for npc in npcs:
			var icon: int = npc.head_icon()
			if icon < 0 or npc.is_queued_for_deletion():
				continue
			var at: Vector3 = npc.center()
			if not cam.is_position_behind(at) and Rect2(Vector2.ZERO, screen).has_point(cam.unproject_position(at)):
				continue
			# Its way on the screen, in the camera's terms: right and up; behind
			# you, along the bottom toward the side you'd turn to.
			var v := cam.global_transform.basis.inverse() * (at - cam.global_position)
			var d := Vector2(v.x, -v.y)
			if v.z > 0.0:
				d = Vector2(v.x, absf(v.y) + v.z)
			if d.length() < 0.001:
				d = Vector2(0, 1)
			var room := (area.size * 0.5).max(Vector2.ONE)
			var k := minf(room.x / maxf(absf(d.x), 0.001), room.y / maxf(absf(d.y), 0.001))
			marks.append([Assets.texture("Images/NPC_Head_Boss_%d" % icon), mid + d * k, d.angle()])
	queue_redraw()


func _draw() -> void:
	for m in marks:
		var tex: Texture2D = m[0]
		var at: Vector2 = m[1]
		var dir := Vector2.from_angle(m[2])
		var side := dir.orthogonal()
		var r := maxf(tex.get_width(), tex.get_height()) * 0.5
		draw_texture(tex, at - tex.get_size() * 0.5)
		# The arrow, just outside the icon, toward the boss.
		var tip := at + dir * (r + 16.0)
		var base := at + dir * (r + 4.0)
		var arrow := PackedVector2Array([tip, base + side * 9.0, base - side * 9.0])
		draw_colored_polygon(arrow, Color(0, 0, 0, 0.8))
		var inner := PackedVector2Array([tip - dir * 3.0, base + side * 6.0 + dir * 1.5, base - side * 6.0 + dir * 1.5])
		draw_colored_polygon(inner, Color(1.0, 0.85, 0.4))
