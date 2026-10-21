class_name TunedModels
## Hand-tuned voxel models: the "tuned" method of both pickers, sculpted in the
## model sculptor (./model_sculptor.sh). A model starts as a copy of another
## method's model (voxelize: any mesh built of voxel faces turns back into
## voxels, each face keeping its own colour) and is then edited voxel by voxel.
##
## Saved two ways: data/tuned_patches/ (in the repo) holds a model as a patch:
## what it started from (method and settings) and the voxels changed since, so
## no art is kept in it; the start is rebuilt from the sprite on whoever's
## machine has the extracted Terraria assets, then the edits applied. The
## whole model is cached in data/tuned/ (not in the repo) so it loads at once.
##
## A model: {size: Vector3i, offset: Vector3 (where cell 0 sits in the mesh, in
## voxels), looks: Array of PackedColorArray (a voxel's six face colours, in
## FACES order; look 0 is empty), frames: Array of PackedInt32Array (a look per
## cell, x fastest then y then z)}. Cells are mesh space: x right, y up, z
## toward the front; a cell is px metres (one art pixel of the sprite) wide.
##
## voxelize + one_color_mesh also give every voxel method its "one colour per
## voxel" option (the same faces, recoloured): each voxel's faces all take its front face's colour (or,
## where its front doesn't show, its most visible face's).

## Where models are cached whole (not in the repo; tests use other folders).
static var dir := "res://data/tuned/"
## Where their patches are saved (in the repo).
static var patch_dir := "res://data/tuned_patches/"
## Face directions: front, back, right, left, top, bottom.
const FACES := [Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]
## Baked shading per face, as the other voxel models (BlockModelMesh.SHADES).
const FACE_SHADES := [1.0, 0.85, 0.72, 0.72, 0.9, 0.55]
## Which face a voxel's single colour comes from, the first that shows.
const PRIMARY_ORDER := [0, 1, 4, 2, 3, 5]
## Methods a tuned model can start from ("blank": an empty grid).
const SEED_METHODS := ["blank", "flat", "extruded", "hull", "hull_top", "lathe", "claude"]

static var _models := {}
static var _meshes := {}


static func npc_key(kind: String) -> String:
	return "npc:" + kind


static func block_key(name: String) -> String:
	return "block:" + name


static func path(key: String) -> String:
	return dir + key.replace(":", "_") + ".json"


static func patch_path(key: String) -> String:
	return patch_dir + key.replace(":", "_") + ".json"


static func has(key: String) -> bool:
	return _models.has(key) or FileAccess.file_exists(path(key)) or FileAccess.file_exists(patch_path(key))


## The model saved for `key` ({} if none), loaded once: its cached whole copy,
## else rebuilt from its patch (and cached).
static func model(key: String) -> Dictionary:
	if not _models.has(key):
		var m := {}
		if FileAccess.file_exists(path(key)):
			m = decode(FileAccess.get_file_as_string(path(key)))
		elif FileAccess.file_exists(patch_path(key)):
			m = from_patch(key, FileAccess.get_file_as_string(patch_path(key)))
			if not m.is_empty():
				_write(path(key), encode(m))
		_models[key] = m
	return _models[key]


## Keeps an edited (or new) model in memory, so the game and pickers show it.
static func put(key: String, m: Dictionary) -> void:
	_models[key] = m
	forget_meshes(key)


## Saves the patch (the repo's copy) and the whole model (the local cache).
static func save(key: String, m: Dictionary) -> bool:
	var patch := make_patch(key, m)
	if patch.is_empty() or not _write(patch_path(key), JSON.stringify(patch)):
		return false
	if not _write(path(key), encode(m)):
		return false
	put(key, m)
	return true


static func _write(file: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(file.get_base_dir()))
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	return true


## Deletes the saved model and its patch (back to "not tuned yet").
static func remove(key: String) -> void:
	for file in [path(key), patch_path(key)]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	_models.erase(key)
	forget_meshes(key)


# ------------------------------------------------------------ seeds and patches

## The NPC or placeable a key names: {npc: bool, name, px (metres per voxel),
## frames}.
static func source(key: String) -> Dictionary:
	var name := key.get_slice(":", 1)
	if key.begins_with("npc:"):
		var fr := NPCModels.frames_of(name)
		return {"npc": true, "name": name, "px": fr.apx, "frames": fr.arts.size()}
	var d := Data.block(Data.block_id(name))
	return {"npc": false, "name": name, "px": float(d.get("art_px", d.sprite_px)), "frames": Data.anim_frames(d)}


## A frame's sprite at art resolution (one pixel per voxel).
static func source_art(key: String, frame: int) -> Image:
	var src := source(key)
	if src.npc:
		return NPCModels.frames_of(src.name).arts[frame]
	var d := Data.block(Data.block_id(src.name))
	return d.anim_arts[frame] if frame > 0 else d.get("art", d.sprite)


## A method's settings for the NPC or placeable, as its picker has them now.
static func method_options(key: String, method: String) -> Dictionary:
	if method in ["blank", "flat"]:
		return {}
	var src := source(key)
	return NPCModels.options(src.name, method) if src.npc else Data.method_options(src.name, method)


## A new model: a copy of `method`'s model with `options` (its settings),
## every frame, the enclosed inside filled. Rebuilt the same from the same
## sprite and settings, which is what lets a patch leave the art out.
static func make_seed(key: String, method: String, options := {}) -> Dictionary:
	var src := source(key)
	var m := {}
	if method == "blank":
		var art := source_art(key, 0)
		var w := art.get_width()
		m = empty_model(Vector3i(w, art.get_height(), w), Vector3(-w * 0.5, 0, -w * 0.5), src.frames)
	else:
		var vox := []
		for f in src.frames:
			var built := _built_with(src, method, options, f)
			var arrays: Array = built.mesh.surface_get_arrays(0) if built.mesh.get_surface_count() > 0 else []
			vox.append(voxelize(arrays, built.textured, source_art(key, f), src.px))
		m = from_voxelized(vox, true)
	m.seeded_from = method
	m.seed_options = options
	return m


## A method's mesh for a frame with the given settings (in place of the
## picker's for the moment it takes): {mesh, textured}.
static func _built_with(src: Dictionary, method: String, options: Dictionary, frame: int) -> Dictionary:
	var store: Dictionary = {}
	if src.npc:
		NPCModels.ensure_loaded()
		store = NPCModels.extruded if method == "extruded" else NPCModels.noise.get(method, {})
	else:
		store = Data.extrude_settings if method == "extruded" else Data.noise_settings.get(method, {})
	var had = store.get(src.name)
	if method != "flat":
		store[src.name] = options
	var built: Dictionary = NPCModels.mesh(src.name, method, frame) if src.npc else BlockModelMesh.build(Data.block_id(src.name), method, frame)
	if method != "flat":
		if had == null:
			store.erase(src.name)
		else:
			store[src.name] = had
	return built


## Each look's colours as one number (0: empty), to compare models whose look
## ids differ.
static func _look_hashes(m: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(m.looks.size())
	for i in range(1, m.looks.size()):
		out[i] = hash(_look_key(m.looks[i])) | 1  # never 0
	return out


## A short fingerprint of a model's voxels (their colours, not their ids).
static func fingerprint(m: Dictionary) -> String:
	var canon := _look_hashes(m)
	var h := hash([m.size, m.offset])
	for g: PackedInt32Array in m.frames:
		var c := PackedInt32Array()
		c.resize(g.size())
		for i in g.size():
			c[i] = canon[g[i]]
		h = hash([h, c])
	return "%x" % h


## The model as a patch: what it started from (rebuilt with make_seed()), that
## start's fingerprint, its grid, and per frame the cells that differ from
## the start ([cell, look] pairs; look 0: emptied), with only the looks those
## edits use. {} if it has nothing to start from.
static func make_patch(key: String, m: Dictionary) -> Dictionary:
	var method: String = m.get("seeded_from", "")
	if not method in SEED_METHODS:
		return {}
	var options: Dictionary = m.get("seed_options", method_options(key, method))
	var base := make_seed(key, method, options)
	var canon_m := _look_hashes(m)
	var canon_b := _look_hashes(base)
	var shift := Vector3i((base.offset - m.offset).round())
	var size: Vector3i = m.size
	var bs: Vector3i = base.size
	var used := {}  # model look -> patch look
	var looks := []
	var frames := []
	var counts := []
	for f in m.frames.size():
		var gm: PackedInt32Array = m.frames[f]
		var gb: PackedInt32Array = base.frames[f] if f < base.frames.size() else PackedInt32Array()
		var edits := PackedInt32Array()
		for z in size.z:
			for y in size.y:
				for x in size.x:
					var i := x + size.x * (y + size.y * z)
					var hb := 0
					var b := Vector3i(x, y, z) - shift
					if not gb.is_empty() and b.x >= 0 and b.y >= 0 and b.z >= 0 and b.x < bs.x and b.y < bs.y and b.z < bs.z:
						hb = canon_b[gb[b.x + bs.x * (b.y + bs.y * b.z)]]
					var id := gm[i]
					if canon_m[id] == hb:
						continue
					var v := 0
					if id != 0:
						if not used.has(id):
							looks.append(_look_strings(m.looks[id]))
							used[id] = looks.size()
						v = used[id]
					edits.append(i)
					edits.append(v)
		frames.append(Marshalls.raw_to_base64(edits.to_byte_array().compress(FileAccess.COMPRESSION_ZSTD)) if not edits.is_empty() else "")
		counts.append(edits.size())
	return {"version": 1, "patch": key, "base": {"method": method, "options": options, "fingerprint": fingerprint(base)},
			"size": [size.x, size.y, size.z], "offset": [m.offset.x, m.offset.y, m.offset.z], "looks": looks, "frames": frames, "edits": counts}


static func _look_strings(cols: PackedColorArray) -> Variant:
	var same := true
	for c in cols:
		same = same and c == cols[0]
	if same:
		return cols[0].to_html(false)
	var six := []
	for c in cols:
		six.append(c.to_html(false))
	return six


## A model rebuilt from its patch: the start made again from the sprite, the
## edits applied ({} if the patch can't be read). Warns if the start comes
## out different from the one the patch was made against.
static func from_patch(key: String, text: String) -> Dictionary:
	var d = JSON.parse_string(text)
	if not d is Dictionary or not d.has("base"):
		return {}
	var base := make_seed(key, str(d.base.method), d.base.get("options", {}))
	if fingerprint(base) != str(d.base.get("fingerprint", "")):
		push_warning("%s: its start (%s) comes out different now; the edits are applied to it anyway" % [key, d.base.method])
	var size := Vector3i(int(d.size[0]), int(d.size[1]), int(d.size[2]))
	var m := empty_model(size, Vector3(float(d.offset[0]), float(d.offset[1]), float(d.offset[2])), d.frames.size())
	m.seeded_from = str(d.base.method)
	m.seed_options = d.base.get("options", {})
	var shift := Vector3i((base.offset - m.offset).round())
	var bs: Vector3i = base.size
	var from_base := {}
	var patch_looks := [0]
	for l in d.looks:
		var cols := PackedColorArray()
		for i in 6:
			cols.append(Color.html(str(l[i] if l is Array else l)))
		patch_looks.append(look_id(m, cols))
	for f in d.frames.size():
		var g: PackedInt32Array = m.frames[f]
		m.frames[f] = PackedInt32Array()
		if f < base.frames.size():
			var gb: PackedInt32Array = base.frames[f]
			for z in bs.z:
				for y in bs.y:
					for x in bs.x:
						var id := gb[x + bs.x * (y + bs.y * z)]
						if id == 0:
							continue
						var c := Vector3i(x, y, z) + shift
						if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= size.x or c.y >= size.y or c.z >= size.z:
							continue
						if not from_base.has(id):
							from_base[id] = look_id(m, base.looks[id])
						g[c.x + size.x * (c.y + size.y * c.z)] = from_base[id]
		var n := int(d.edits[f])
		var edits := Marshalls.base64_to_raw(str(d.frames[f])).decompress(n * 4, FileAccess.COMPRESSION_ZSTD).to_int32_array() if n > 0 else PackedInt32Array()
		for k in range(0, edits.size() - 1, 2):
			g[edits[k]] = patch_looks[edits[k + 1]] if edits[k + 1] > 0 else 0
		m.frames[f] = g
	return m


static func forget_meshes(key: String) -> void:
	for k in _meshes.keys():
		if str(k).begins_with(key + "|"):
			_meshes.erase(k)


static func clear_cache() -> void:
	_models.clear()
	_meshes.clear()


# ------------------------------------------------------------ the model

static func empty_model(size: Vector3i, offset: Vector3, frames: int) -> Dictionary:
	var m := {"size": size, "offset": offset, "looks": [PackedColorArray()], "look_ids": {}, "frames": []}
	for f in frames:
		var g := PackedInt32Array()
		g.resize(size.x * size.y * size.z)
		m.frames.append(g)
	return m


static func index(m: Dictionary, c: Vector3i) -> int:
	return c.x + m.size.x * (c.y + m.size.y * c.z)


static func inside(m: Dictionary, c: Vector3i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < m.size.x and c.y < m.size.y and c.z < m.size.z


static func get_look(m: Dictionary, frame: int, c: Vector3i) -> int:
	return m.frames[frame][index(m, c)] if inside(m, c) else 0


## The look id for six face colours (added if new). Colours are kept to 8 bits.
static func look_id(m: Dictionary, faces: PackedColorArray) -> int:
	if not m.has("look_ids") or m.look_ids.size() != m.looks.size() - 1:
		m.look_ids = {}
		for i in range(1, m.looks.size()):
			m.look_ids[_look_key(m.looks[i])] = i
	var q := PackedColorArray()
	for c in faces:
		q.append(Color8(roundi(clampf(c.r, 0, 1) * 255), roundi(clampf(c.g, 0, 1) * 255), roundi(clampf(c.b, 0, 1) * 255)))
	var k := _look_key(q)
	if not m.look_ids.has(k):
		m.looks.append(q)
		m.look_ids[k] = m.looks.size() - 1
	return m.look_ids[k]


static func solid_look(m: Dictionary, c: Color) -> int:
	return look_id(m, PackedColorArray([c, c, c, c, c, c]))


static func _look_key(faces: PackedColorArray) -> String:
	var parts := PackedStringArray()
	for c in faces:
		parts.append(c.to_html(false))
	return ",".join(parts)


## Every voxel's colours, from `frame` (for the sculptor's palette).
static func colors_used(m: Dictionary) -> Array[Color]:
	var seen := {}
	var out: Array[Color] = []
	for i in range(1, m.looks.size()):
		for c in m.looks[i]:
			var k: String = c.to_html(false)
			if not seen.has(k):
				seen[k] = true
				out.append(c)
	return out


# ------------------------------------------------------------ the file

static func encode(m: Dictionary) -> String:
	var looks := [null]
	for i in range(1, m.looks.size()):
		var cols: PackedColorArray = m.looks[i]
		var same := true
		for c in cols:
			same = same and c == cols[0]
		if same:
			looks.append(cols[0].to_html(false))
		else:
			var six := []
			for c in cols:
				six.append(c.to_html(false))
			looks.append(six)
	var frames := []
	for g: PackedInt32Array in m.frames:
		frames.append(Marshalls.raw_to_base64(g.to_byte_array().compress(FileAccess.COMPRESSION_ZSTD)))
	var out := {"version": 1, "size": [m.size.x, m.size.y, m.size.z], "offset": [m.offset.x, m.offset.y, m.offset.z],
			"seeded_from": m.get("seeded_from", ""), "seed_options": m.get("seed_options", {}), "looks": looks, "frames": frames}
	return JSON.stringify(out)


static func decode(text: String) -> Dictionary:
	var d = JSON.parse_string(text)
	if not d is Dictionary or not d.has("size"):
		return {}
	var size := Vector3i(int(d.size[0]), int(d.size[1]), int(d.size[2]))
	var m := {"size": size, "offset": Vector3(float(d.offset[0]), float(d.offset[1]), float(d.offset[2])),
			"seeded_from": str(d.get("seeded_from", "")), "looks": [PackedColorArray()], "frames": []}
	if d.get("seed_options") is Dictionary and not d.seed_options.is_empty():
		m.seed_options = d.seed_options
	for i in range(1, d.looks.size()):
		var l = d.looks[i]
		var cols := PackedColorArray()
		for f in 6:
			cols.append(Color.html(str(l[f] if l is Array else l)))
		m.looks.append(cols)
	var n := size.x * size.y * size.z
	for s in d.frames:
		var g := Marshalls.base64_to_raw(str(s)).decompress(n * 4, FileAccess.COMPRESSION_ZSTD).to_int32_array()
		g.resize(n)
		m.frames.append(g)
	return m


# ------------------------------------------------------------ voxelizing

## A mesh made of voxel faces (every voxel method's) back into voxels:
## {offset: Vector3 (cell 0's corner, in voxels), cells: Vector3i -> six face
## colours (transparent: that face wasn't drawn)}. `px`: metres per voxel;
## textured meshes sample `tex` (the sprite the UVs point into). Faces that
## aren't axis-aligned on the grid (crossed planes) are skipped.
static func voxelize(arrays: Array, textured: bool, tex: Image, px: float) -> Dictionary:
	var cells := {}
	if arrays.is_empty():
		return {"offset": Vector3.ZERO, "cells": cells}
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return {"offset": Vector3.ZERO, "cells": cells}
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var lo := Vector3(INF, INF, INF)
	for v in verts:
		lo = lo.min(v / px)
	var offset := (lo * 2.0).round() * 0.5
	var tw := tex.get_width() if tex else 1
	var th := tex.get_height() if tex else 1
	var tris := (idx.size() if not idx.is_empty() else verts.size()) / 3
	for t in tris:
		var i0 := idx[t * 3] if not idx.is_empty() else t * 3
		var i1 := idx[t * 3 + 1] if not idx.is_empty() else t * 3 + 1
		var i2 := idx[t * 3 + 2] if not idx.is_empty() else t * 3 + 2
		var a := verts[i0] / px - offset
		var b := verts[i1] / px - offset
		var c := verts[i2] / px - offset
		var n := (b - a).cross(c - a)
		if n.length() < 1e-6:
			continue
		var axis := n.abs().max_axis_index()
		if absf(n.normalized()[axis]) < 0.999:
			continue
		var positive := n[axis] > 0.0
		var face: int = [2, 4, 0][axis] + (0 if positive else 1)
		var layer := roundi(a[axis]) - (1 if positive else 0)
		var ua := (axis + 1) % 3
		var va := (axis + 2) % 3
		var pa := Vector2(a[ua], a[va])
		var pb := Vector2(b[ua], b[va])
		var pc := Vector2(c[ua], c[va])
		var area := (pb - pa).cross(pc - pa)
		if absf(area) < 1e-9:
			continue
		var mn := pa.min(pb).min(pc)
		var mx := pa.max(pb).max(pc)
		for cu in range(floori(mn.x + 0.001), ceili(mx.x - 0.001)):
			for cv in range(floori(mn.y + 0.001), ceili(mx.y - 0.001)):
				var q := Vector2(cu + 0.5, cv + 0.5)
				var w0 := (pc - pb).cross(q - pb) / area
				var w1 := (pa - pc).cross(q - pc) / area
				var w2 := 1.0 - w0 - w1
				if w0 < -0.0001 or w1 < -0.0001 or w2 < -0.0001:
					continue
				var col := Color(1, 1, 1)
				if not cols.is_empty():
					col = cols[i0] * w0 + cols[i1] * w1 + cols[i2] * w2
				col = col / FACE_SHADES[face]
				if textured and tex and not uvs.is_empty():
					var uv := uvs[i0] * w0 + uvs[i1] * w1 + uvs[i2] * w2
					var tc := tex.get_pixel(clampi(floori(uv.x * tw), 0, tw - 1), clampi(floori(uv.y * th), 0, th - 1))
					if tc.a < 0.5:
						continue  # alpha-cut, as the shader does
					col = tc.srgb_to_linear() * col
				col = Color(clampf(col.r, 0, 1), clampf(col.g, 0, 1), clampf(col.b, 0, 1)).linear_to_srgb()
				var cell := Vector3i.ZERO
				cell[axis] = layer
				cell[ua] = cu
				cell[va] = cv
				if not cells.has(cell):
					var blank := PackedColorArray()
					blank.resize(6)
					blank.fill(Color(0, 0, 0, 0))  # (resize fills opaque black)
					cells[cell] = blank
				var faces: PackedColorArray = cells[cell]
				faces[face] = Color(col, 1.0)
				cells[cell] = faces
	return {"offset": offset, "cells": cells}


## A voxel's single colour: its first drawn face in PRIMARY_ORDER.
static func primary(faces: PackedColorArray) -> Color:
	for f in PRIMARY_ORDER:
		if faces[f].a > 0.5:
			return faces[f]
	return Color.WHITE


## A new model from voxelized frames (voxelize's results), sharing one grid.
## Faces no frame drew take the voxel's single colour; with `fill`, space
## enclosed by voxels is filled (each cell the colour of the voxel it's
## reached from), so sculpting into it never shows a hollow.
static func from_voxelized(frames: Array, fill := true) -> Dictionary:
	var lo := Vector3(INF, INF, INF)
	for fr in frames:
		lo = lo.min(fr.offset)
	if lo.x == INF:
		lo = Vector3.ZERO
	var hi := Vector3i.ZERO
	var shifts: Array[Vector3i] = []
	for fr in frames:
		var shift := Vector3i((fr.offset - lo).round())
		shifts.append(shift)
		for c: Vector3i in fr.cells:
			hi = hi.max(c + shift + Vector3i.ONE)
	var m := empty_model(hi.max(Vector3i.ONE), lo, frames.size())
	for f in frames.size():
		var g: PackedInt32Array = m.frames[f]
		for c: Vector3i in frames[f].cells:
			var faces: PackedColorArray = frames[f].cells[c]
			var own := primary(faces)
			var full := PackedColorArray()
			for i in 6:
				full.append(faces[i] if faces[i].a > 0.5 else own)
			g[index(m, c + shifts[f])] = look_id(m, full)
		m.frames[f] = g
	if fill:
		# Solid versions of every look first, so the threads only read.
		var solid := PackedInt32Array()
		solid.resize(m.looks.size())
		for i in range(1, solid.size()):
			solid[i] = solid_look(m, m.looks[i][0])
		var grids: Array = m.frames.duplicate()
		var filled := {}
		var lock := Mutex.new()
		var task := WorkerThreadPool.add_group_task(func(f: int):
			var g := fill_inside(m.size, grids[f], solid)
			lock.lock()
			filled[f] = g
			lock.unlock(), frames.size())
		WorkerThreadPool.wait_for_group_task_completion(task)
		for f in frames.size():
			m.frames[f] = filled[f]
	return m


## `grid` with the empty space it encloses (not reachable from outside the
## grid) filled: each cell takes `solid[look]` of the voxel it's reached from.
static func fill_inside(size: Vector3i, grid: PackedInt32Array, solid: PackedInt32Array) -> PackedInt32Array:
	var n := size.x * size.y * size.z
	var sx := 1
	var sy := size.x
	var sz := size.x * size.y
	var outside := PackedByteArray()
	outside.resize(n)
	var queue := PackedInt32Array()
	for z in size.z:
		for y in size.y:
			for x in size.x:
				if x == 0 or y == 0 or z == 0 or x == size.x - 1 or y == size.y - 1 or z == size.z - 1:
					var i := x + sy * y + sz * z
					if grid[i] == 0:
						outside[i] = 1
						queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % size.x
		var y := (i / sy) % size.y
		var z := i / sz
		for step in [[x > 0, -sx], [x < size.x - 1, sx], [y > 0, -sy], [y < size.y - 1, sy], [z > 0, -sz], [z < size.z - 1, sz]]:
			if step[0]:
				var j: int = i + step[1]
				if grid[j] == 0 and outside[j] == 0:
					outside[j] = 1
					queue.append(j)
	# Inside: spread in from the voxels round it.
	queue = PackedInt32Array()
	for i in n:
		if grid[i] != 0:
			queue.append(i)
	head = 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % size.x
		var y := (i / sy) % size.y
		var z := i / sz
		for step in [[x > 0, -sx], [x < size.x - 1, sx], [y > 0, -sy], [y < size.y - 1, sy], [z > 0, -sz], [z < size.z - 1, sz]]:
			if step[0]:
				var j: int = i + step[1]
				if grid[j] == 0 and outside[j] == 0:
					grid[j] = solid[grid[i]] if grid[i] < solid.size() else grid[i]
					queue.append(j)
	return grid


## `mesh` (any voxel method's) with every voxel one colour.
static func one_color_mesh(mesh: ArrayMesh, textured: bool, tex: Image, px: float) -> ArrayMesh:
	if mesh.get_surface_count() == 0:
		return mesh
	return BlockModelMesh.mesh_from_arrays(one_color_arrays(mesh.surface_get_arrays(0), textured, tex, px))


## The same faces as a voxel method's surface arrays (one quad per voxel
## face), each in its voxel's single colour. Thread safe (no mesh made).
static func one_color_arrays(source: Array, textured: bool, tex: Image, px: float) -> Array:
	var vx := voxelize(source, textured, tex, px)
	var off: Vector3 = vx.offset
	var s := px
	var corners := _corners(s)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for c: Vector3i in vx.cells:
		var faces: PackedColorArray = vx.cells[c]
		var own := primary(faces).srgb_to_linear()
		var p := (Vector3(c) + off) * s
		for f in 6:
			if faces[f].a < 0.5:
				continue
			var col: Color = own * FACE_SHADES[f]
			var q: Array = corners[f]
			for k in [0, 1, 2, 0, 2, 3]:
				verts.append(p + q[k])
				colors.append(Color(col.r, col.g, col.b))
				uvs.append(BlockModelMesh.FACE_UVS[k])
	if verts.is_empty():
		return []
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_TEX_UV] = uvs
	return out


## A cell's face quads (FACES order), `s` metres across.
static func _corners(s: float) -> Array:
	return [
		[Vector3(0, 0, s), Vector3(s, 0, s), Vector3(s, s, s), Vector3(0, s, s)],
		[Vector3(s, 0, 0), Vector3(0, 0, 0), Vector3(0, s, 0), Vector3(s, s, 0)],
		[Vector3(s, 0, s), Vector3(s, 0, 0), Vector3(s, s, 0), Vector3(s, s, s)],
		[Vector3(0, 0, 0), Vector3(0, 0, s), Vector3(0, s, s), Vector3(0, s, 0)],
		[Vector3(0, s, s), Vector3(s, s, s), Vector3(s, s, 0), Vector3(0, s, 0)],
		[Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, 0, s), Vector3(0, 0, s)],
	]


# ------------------------------------------------------------ meshing

## The surface arrays of `frame` (cells lo to hi, exclusive; default all),
## shaded like the other voxel models. Options `o`: one_color (each voxel its
## single colour), noise / strength / seed (as the hull's). Doesn't touch the
## rendering server, so it can run on a worker thread.
static func arrays(m: Dictionary, frame: int, px: float, o := {}, lo := Vector3i.ZERO, hi := Vector3i(-1, -1, -1)) -> Array:
	if m.is_empty() or m.frames.is_empty():
		return []
	var size: Vector3i = m.size
	if hi.x < 0:
		hi = size
	var g: PackedInt32Array = m.frames[frame % m.frames.size()]
	var looks: Array = m.looks
	var one: bool = o.get("one_color", false)
	var noise: String = o.get("noise", "none")
	var strength: float = o.get("strength", 0.5)
	var seed: int = o.get("seed", 0)
	var palette: Array[Color] = []
	if noise == "palette":
		palette = colors_used(m)
	var off: Vector3 = m.offset
	var s := px
	var corners := _corners(s)
	var sy := size.x
	var sz := size.x * size.y
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for z in range(lo.z, hi.z):
		for y in range(lo.y, hi.y):
			for x in range(lo.x, hi.x):
				var id := g[x + sy * y + sz * z]
				if id == 0:
					continue
				var look: PackedColorArray = looks[id]
				var p := (Vector3(x, y, z) + off) * s
				for f in 6:
					var d: Vector3i = FACES[f]
					var nx := x + d.x
					var ny := y + d.y
					var nz := z + d.z
					if nx >= 0 and ny >= 0 and nz >= 0 and nx < size.x and ny < size.y and nz < size.z and g[nx + sy * ny + sz * nz] != 0:
						continue
					var base: Color = look[0] if one else look[f]
					var factor := 1.0
					if noise != "none":
						var r := BlockModelMesh._hash(x * 31 + z, y, f, 17, seed)
						match noise:
							"speckle":
								factor = 1.0 + (r * 2.0 - 1.0) * strength * 0.45
							"grain":
								factor = 1.0 + sin(z * 0.55 + BlockModelMesh._hash(x, y, 3, 5, seed) * TAU) * strength * 0.3 + (r - 0.5) * strength * 0.12
							"palette":
								if not palette.is_empty() and r < strength * 0.6:
									base = palette[int(BlockModelMesh._hash(x * 31 + z, y, f, 19, seed) * palette.size()) % palette.size()]
					var c: Color = base.srgb_to_linear() * FACE_SHADES[f] * factor
					var q: Array = corners[f]
					for k in [0, 1, 2, 0, 2, 3]:
						verts.append(p + q[k])
						colors.append(Color(c.r, c.g, c.b))
						uvs.append(BlockModelMesh.FACE_UVS[k])
	if verts.is_empty():
		return []
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_TEX_UV] = uvs
	return out


## The game's mesh of a saved model's frame (built once per settings).
static func mesh(key: String, frame: int, px: float, o := {}) -> ArrayMesh:
	var m := model(key)
	var k := "%s|%d|%s|%s" % [key, frame, px, JSON.stringify(o)]
	if not _meshes.has(k):
		_meshes[k] = BlockModelMesh.mesh_from_arrays(arrays(m, frame, px, o))
	return _meshes[k]
