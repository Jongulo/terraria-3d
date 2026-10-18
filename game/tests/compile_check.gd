extends Node
## Loads every script in the project (with autoloads available, unlike
## --check-only) and reports any that fail to compile. Used by run_tests.sh.


func _ready() -> void:
	var bad: Array[String] = []
	for dir in ["res://scripts", "res://tests", "res://editor"]:
		for path in _scripts(dir):
			var s = load(path)
			if s == null or not (s is Script) or not s.can_instantiate():
				bad.append(path)
	if bad.is_empty():
		print("COMPILE OK")
	else:
		print("COMPILE FAILED: ", ", ".join(bad))
	get_tree().quit(1 if bad.size() > 0 else 0)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_scripts(dir.path_join(sub)))
	return out
