class_name HealthBar
extends MeshInstance3D
## Terraria's enemy health bar, floating above the head once the enemy is
## hurt (shaders/health_bar.gdshader). Terraria draws it under the enemy; in
## first person above reads better. Hidden at full life, for town NPCs and
## dummies, and when Settings "enemy_health_bars" is off.

## Terraria's bar art is 36x12 pixels.
const ART := Vector2(36, 12)
## Metres per art pixel: a normal enemy's bar is 0.9 m wide.
const PIXEL := 0.025

var _mat := ShaderMaterial.new()


func _init() -> void:
	var quad := QuadMesh.new()
	quad.size = ART * PIXEL
	mesh = quad
	_mat.shader = preload("res://shaders/health_bar.gdshader")
	_mat.set_shader_parameter("back_tex", Assets.texture("Images/HealthBar2"))
	_mat.set_shader_parameter("fill_tex", Assets.texture("Images/HealthBar1"))
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## Shows `life` of `life_max` (hidden when full or empty).
func set_life(life: int, life_max: int) -> void:
	visible = life > 0 and life < life_max and Settings.get_value("enemy_health_bars")
	if not visible:
		return
	var ratio := clampf(float(life) / float(life_max), 0.0, 1.0)
	_mat.set_shader_parameter("filled", float(maxi(3, int(ART.x * ratio))))
	_mat.set_shader_parameter("color", bar_color(ratio))


## Terraria's colour for a life ratio: green when healthy, through yellow, to
## red (Main.DrawHealthBar).
static func bar_color(ratio: float) -> Color:
	var r := ratio - 0.1
	var red: float
	var green: float
	if r > 0.5:
		green = 1.0
		red = (1.0 - r) * 2.0
	else:
		green = r * 2.0
		red = 1.0
	return Color(clampf(red, 0.0, 1.0) * 0.95, clampf(green, 0.0, 1.0) * 0.95, 0.0)
