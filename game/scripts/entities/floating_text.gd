class_name FloatingText
extends Label3D
## Combat/pickup text that rises and fades, drawn with Terraria's font.

var life := 1.2
var velocity := Vector3(0, 1.6, 0)


func setup(msg: String, color: Color, big := false) -> void:
	text = msg
	font = Assets.font("Combat_Crit" if big else "Combat_Text")
	font_size = 36 if big else 28
	pixel_size = 0.006
	modulate = color
	outline_modulate = Color(0, 0, 0, 0.8)
	outline_size = 0
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = false
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	render_priority = 10


func _process(delta: float) -> void:
	life -= delta
	position += velocity * delta
	velocity.y = maxf(0.2, velocity.y - 2.0 * delta)
	modulate.a = clampf(life / 0.5, 0.0, 1.0)
	if life <= 0:
		queue_free()
