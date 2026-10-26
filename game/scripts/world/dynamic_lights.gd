class_name DynamicLights
extends Node
## Lights that move or lie about in the world, not in the voxel light (a
## thrown glowstick: Terraria's Projectile.light). Each frame the MAX nearest
## the camera go to the shaders as a little texture (global uniform
## dynamic_lights: row 0 position and reach, row 1 colour) with their count
## (dynamic_light_count); shaders/player_light.gdshaderinc adds them in.
## Like the light you carry, they shine through blocks: no shadows.
## A node joins GROUP and has `light_color` (black: dark).

const MAX := 16
const GROUP := "dynamic_light"
## Blocks of reach at full brightness (the carried light's, a torch's 15
## light levels falling one a block).
const RANGE := 14.0

var _img := Image.create(MAX, 2, false, Image.FORMAT_RGBAF)
var _tex: ImageTexture
var _count := -1


## The lights the shaders have this frame.
func count() -> int:
	return maxi(_count, 0)


func _ready() -> void:
	_tex = ImageTexture.create_from_image(_img)
	RenderingServer.global_shader_parameter_set("dynamic_lights", _tex)
	_set_count(0)


func _exit_tree() -> void:
	_set_count(0)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else Vector3.ZERO
	var lit := []
	for n in get_tree().get_nodes_in_group(GROUP):
		var c: Color = n.light_color
		if n is Node3D and n.is_visible_in_tree() and (c.r > 0.0 or c.g > 0.0 or c.b > 0.0):
			lit.append([eye.distance_squared_to(n.global_position), n])
	if lit.is_empty():
		_set_count(0)
		return
	lit.sort_custom(func(a, b): return a[0] < b[0])
	var n := mini(MAX, lit.size())
	for i in n:
		var node: Node3D = lit[i][1]
		var p := node.global_position
		var c: Color = node.light_color
		_img.set_pixel(i, 0, Color(p.x, p.y, p.z, RANGE))
		_img.set_pixel(i, 1, Color(c.r, c.g, c.b, 1.0))
	_tex.update(_img)
	_set_count(n)


func _set_count(n: int) -> void:
	if n != _count:
		_count = n
		RenderingServer.global_shader_parameter_set("dynamic_light_count", n)
