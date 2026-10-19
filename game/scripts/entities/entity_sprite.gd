class_name EntitySprite
extends MeshInstance3D
## A camera-facing sprite showing one frame of a vertically stacked Terraria sheet,
## shaded by the voxel light at its position.

var frames := 1
var _mat: ShaderMaterial


## `size` in world units. Grounded sprites have their origin at the bottom
## centre; centred sprites (fliers, projectiles) at the middle.
func setup(tex: Texture2D, frame_count: int, size: Vector2, centred := false, spherical := false) -> void:
	frames = frame_count
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	if not centred:
		quad.center_offset = Vector3(0, 0.5, 0)
	mesh = quad
	scale = Vector3(size.x, size.y, 1.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = _shader()
	_mat.set_shader_parameter("sprite", tex)
	_mat.set_shader_parameter("frames", frame_count)
	_mat.set_shader_parameter("spherical", spherical)
	material_override = _mat
	# Billboarding happens in the vertex shader; keep the culling box generous.
	extra_cull_margin = maxf(size.x, size.y)


## The shader it's drawn with (RenderedSprite's pushes its depth).
func _shader() -> Shader:
	return preload("res://shaders/billboard.gdshader")


## Cuts `px` pixels off the bottom of every frame (of `frame_height` pixels).
func set_trim_bottom(px: float, frame_height: float) -> void:
	_mat.set_shader_parameter("trim_bottom", px / frame_height)


func set_frame(f: int) -> void:
	_mat.set_shader_parameter("frame", clampi(f, 0, frames - 1))


func set_flip(f: bool) -> void:
	_mat.set_shader_parameter("flip", f)


func set_tint(c: Color) -> void:
	_mat.set_shader_parameter("tint", c)


func set_flash(v: float) -> void:
	_mat.set_shader_parameter("flash", v)


## 1: whole; less fades it out (Terraria's gore alpha).
func set_fade(v: float) -> void:
	_mat.set_shader_parameter("fade", v)


func set_rotation_angle(a: float) -> void:
	_mat.set_shader_parameter("rotation", a)


## Lays the sprite's up along world direction `dir` (turned round it to face
## the camera), so it points that way in 3D; Vector3.ZERO: a plain billboard.
func set_axis(dir: Vector3) -> void:
	_mat.set_shader_parameter("axis", dir.normalized() if dir.length_squared() > 1e-8 else Vector3.ZERO)


func update_light(world: VoxelWorld, sky: SkySystem, at: Vector3) -> void:
	_mat.set_shader_parameter("light", world.get_light(at))
	_mat.set_shader_parameter("sky_light", sky.sky_light)
	_mat.set_shader_parameter("sky_color", sky.sky_tint)


## Lit by nothing but itself (a glowing star): full brightness.
func set_glow() -> void:
	_mat.set_shader_parameter("light", Color(1, 1, 1, 0))
	_mat.set_shader_parameter("sky_light", 0.0)


## Screen-plane angle that makes a sprite's "down" point along world direction `dir`.
static func facing_angle(camera: Camera3D, dir: Vector3) -> float:
	var local := camera.global_transform.basis.inverse() * dir
	return atan2(local.y, local.x) + PI / 2.0
