extends Node3D
## Renders held-item poses and swing phases to PNGs for visual review.
## godot --path game res://tests/viewmodel_test.tscn -- <dir>

var out_dir := "user://"
var player := Player.new()
var sky := SkySystem.new()


func _ready() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out_dir = OS.get_cmdline_user_args()[0]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.62, 0.95)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.25, 0.55, 0.25)
	ground.material_override = gm
	add_child(ground)
	add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.camera.make_current()
	player.global_position = Vector3(0, 0, 0)
	player.viewmodel.update_light(Color(0, 0, 0, 1), sky)
	_run()


func _pose(item: String, style := "", p := 0.0) -> void:
	player.inventory.slots[0] = Inventory.stack(item, 1)
	player.selected = 0
	await get_tree().process_frame
	player.viewmodel._equip = 1.0
	if style != "":
		player.viewmodel.play(style, 1000.0)
		player.viewmodel._t = p
	for i in 3:
		await get_tree().process_frame
		player.viewmodel._equip = 1.0
		if style != "":
			player.viewmodel._t = p


func shot(name: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("vm_%s.png" % name))


func _run() -> void:
	for item in ["CopperBroadsword", "CopperPickaxe", "CopperAxe", "CopperShortsword", "FlintlockPistol", "WoodenBow", "AmethystStaff", "DirtBlock", "LesserHealingPotion"]:
		await _pose(item)
		await shot("idle_" + item)
	for p in [0.08, 0.2, 0.35, 0.55, 0.8]:
		await _pose("CopperBroadsword", "swing", p)
		await shot("swing_%d" % int(p * 100))
	await _pose("CopperPickaxe", "swing", 0.4)
	await shot("pick_swing")
	for p in [0.1, 0.25, 0.45]:
		await _pose("CopperAxe", "swing", p)
		await shot("axe_swing_%d" % int(p * 100))
	await _pose("CopperShortsword", "thrust", 0.5)
	await shot("thrust")
	await _pose("FlintlockPistol", "hold", 0.12)
	await shot("recoil")
	await _pose("LesserHealingPotion", "drink", 0.5)
	await shot("drink")
	# A wall right in front of the face: the item must still draw on top.
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4, 4, 0.1)
	wall.mesh = box
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.4, 0.35, 0.3)
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall.material_override = wm
	add_child(wall)
	wall.global_position = player.camera.global_position + Vector3(0, 0, -0.3)
	await _pose("CopperBroadsword", "swing", 0.35)
	await shot("wall")
	print("RESULT: ok")
	get_tree().quit()
