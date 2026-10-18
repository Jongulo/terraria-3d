extends Node3D
## Falling liquid scrolls DOWN: renders a 1 x 2 block stream face (UV.y = world
## height, UV2.x = 3 as the mesher makes them) with each stream material, close
## up, and measures how the pattern moves between consecutive frames.
## Needs a window (rendering): ./run_tests.sh --visual

const CASES := [
	["water stream", "liquid_water", {"liquid_tex": "Liquid_0", "fall_tex": "Waterfall_0"}],
	["lava stream", "liquid_lava", {"liquid_tex": "Liquid_1", "fall_tex": "Waterfall_1"}],
	["waterfall", "waterfall", {"fall_tex": "Waterfall_0"}],
	["lavafall", "waterfall", {"fall_tex": "Waterfall_1", "lava": true}],
]

var failures: Array[String] = []


func _mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 2, 0), Vector3(-0.5, 2, 0)]
	var uv := [Vector2(0, 10), Vector2(1, 10), Vector2(1, 12), Vector2(0, 12)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(1, 1, 1, 1))
		st.set_uv(uv[i])
		st.set_uv2(Vector2(3, 1))
		st.add_vertex(v[i])
	return st.commit()


## Brightness down a 40 px wide band at the centre of the screen.
func _profile(img: Image) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var x := img.get_width() / 2 - 20
	for y in img.get_height():
		var s := 0.0
		for dx in 40:
			var c := img.get_pixel(x + dx, y)
			s += c.r * 3.0 + c.g * 5.0 + c.b
		out.append(s)
	return out


## Screen pixels the pattern moved from `a` to `b` (positive = down).
func _shift(a: PackedFloat32Array, b: PackedFloat32Array) -> int:
	var best := 0
	var best_err := INF
	for s in range(-60, 61):
		var err := 0.0
		for y in range(100, a.size() - 100):
			err += absf(b[y] - a[y - s])
		if err < best_err:
			best_err = err
			best = s
	return best


func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1, 0.75)
	add_child(cam)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh()
	add_child(mi)
	for t in CASES:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/%s.gdshader" % t[1])
		for k in t[2]:
			var val = t[2][k]
			mat.set_shader_parameter(k, Assets.texture("Images/" + val) if val is String else val)
		mi.material_override = mat
		await RenderingServer.frame_post_draw
		# Several frame pairs: a pair that straddles a change of animation
		# frame can measure anything, so the median decides.
		var shifts := []
		for i in 9:
			await RenderingServer.frame_post_draw
			var a := _profile(get_viewport().get_texture().get_image())
			await RenderingServer.frame_post_draw
			shifts.append(_shift(a, _profile(get_viewport().get_texture().get_image())))
		shifts.sort()
		var median: int = shifts[shifts.size() / 2]
		var ok := median > 0
		print(("PASS " if ok else "FAIL ") + "%s flows down (median shift %d px/frame, %s)" % [t[0], median, shifts])
		if not ok:
			failures.append(t[0])
	print("RESULT: %d failures" % failures.size())
	get_tree().quit()
