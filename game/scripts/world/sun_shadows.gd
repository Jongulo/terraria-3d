class_name SunShadows
extends Node3D
## Optional real-time shadows from the sun and moon (Settings → Shaders): a
## directional light along the sky's sun (or moon) direction, whose shadow
## map the block, model and sprite shaders read (shaders/sun_shadow.gdshaderinc);
## the light itself colours nothing. Off, there's no light (and so no shadow
## pass) and those shaders look as they always did.

var sky: SkySystem
## Whether the shaders are drawing the shadows (the "sun_shadows" global).
var active := false
var _light: DirectionalLight3D
## How far the sun moves between the shadows' steps (about every 1.5 s by day).
const SUN_STEP := deg_to_rad(0.25)
var _dir := Vector3.ZERO


func _ready() -> void:
	Settings.changed.connect(_on_setting_changed)
	_apply()


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("sun_shadows", false)


func _on_setting_changed(key: String) -> void:
	if key.begins_with("shadow"):
		_apply()


func _apply() -> void:
	var on: bool = Settings.get_value("shadows")
	if on and _light == null:
		_light = DirectionalLight3D.new()
		_light.shadow_enabled = true
		_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		# Each split on its own (blending them would give grey part-shadowed
		# art pixels where they meet).
		_light.directional_shadow_blend_splits = false
		# Leaves the sky shader alone (it draws its own sun).
		_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		_light.shadow_bias = 0.05
		_light.shadow_normal_bias = 1.5
		add_child(_light)
		_dir = Vector3.ZERO  # (so it's turned to the sun now)
		_follow_sun()
	elif not on and _light != null:
		_light.queue_free()
		_light = null
	if _light != null:
		_light.directional_shadow_max_distance = float(Settings.get_value("shadow_distance"))
		# Hard edges: each block texel is in the shadow or out of it.
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		RenderingServer.directional_shadow_atlas_set_size(1024 << clampi(int(Settings.get_value("shadow_detail")), 1, 3), true)
	RenderingServer.global_shader_parameter_set("sun_shade", float(Settings.get_value("shadow_shade")))
	RenderingServer.global_shader_parameter_set("sun_shadows", on)
	active = on


func _process(_delta: float) -> void:
	_follow_sun()


## The light shines from the sun (by day) or the moon (by night), turned in
## steps of SUN_STEP along its path across the sky: between steps the shadows
## hold still instead of creeping (a creeping edge flips art pixels one by
## one, which flickers).
func _follow_sun() -> void:
	if sky == null:
		return
	var d := sky.sun_direction()
	var a := snappedf(atan2(d.y, d.x), SUN_STEP)
	# (The sky's tilt off the east-west line, kept.)
	var dir := Vector3(cos(a), sin(a), d.z / maxf(Vector2(d.x, d.y).length(), 1e-6)).normalized()
	if dir.is_equal_approx(_dir):
		return
	_dir = dir
	RenderingServer.global_shader_parameter_set("sun_dir", dir)
	if _light != null:
		_light.basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
