class_name PlayerFile
extends RefCounted
## Characters, saved apart from the worlds as Terraria's .plr files are: who
## you are (name, difficulty, look) and what you carry (Player.save_state:
## inventory, armor, piggy bank, life...), taken from world to world. Where
## your bed is, each world keeps on you (Terraria's spawn points, by world).
## JSON in DIR, one file a character.

const DIR := "user://players/"
const EXT := ".tplr"
const VERSION := 1
## Terraria's character difficulties (Player.difficulty): what a death
## costs you (Player._die).
const CLASSIC := 0
const MEDIUMCORE := 1
const HARDCORE := 2
const DIFFICULTIES := ["Classic", "Mediumcore", "Hardcore"]
## Lang.menu[31], [30], [29].
const DIFFICULTY_TEXT := [
	"Classic characters drop money on death",
	"Mediumcore characters drop items on death",
	"Hardcore characters die for good",
]
## Their names in the lists (Terraria's: white, light blue, red).
const DIFFICULTY_COLOURS := [Color(1, 1, 1), Color8(175, 175, 255), Color8(255, 60, 60)]
## Terraria's longest name.
const NAME_MAX := 20
## Deleted characters go to the system trash (tests turn this off).
static var use_trash := true


## A new character's file (not yet written): its starting tools are given
## the first time it enters a world ("fresh").
static func new_data(name: String, difficulty: int, look: PlayerLook) -> Dictionary:
	return {
		"version": VERSION,
		"name": name,
		"difficulty": difficulty,
		"look": look.to_data(),
		"state": {},
		"spawns": {},
		"play_time": 0.0,
		"fresh": true,
		"created": Time.get_datetime_string_from_system(),
	}


## The saved characters' files, last played first.
static func list() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(DIR)
	if dir:
		for f in dir.get_files():
			if f.ends_with(EXT):
				out.append(DIR + f)
	var age := func(p: String) -> int: return FileAccess.get_modified_time(p)
	out.sort_custom(func(a, b): return age.call(a) > age.call(b))
	return out


## A character's data, or {} if the file can't be read.
static func read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary and d.has("name") else {}


## Writes a character (through a temporary file, so a crash mid-save keeps
## the old one).
static func write(path: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK


## A file for a new character called `name` (its name, numbered if taken).
static func path_for(name: String) -> String:
	var base := name.validate_filename()
	if base == "":
		base = "Player"
	var path := DIR + base + EXT
	var n := 2
	while FileAccess.file_exists(path):
		path = "%s%s %d%s" % [DIR, base, n, EXT]
		n += 1
	return path


## Deletes a character: to the system trash if there is one (use_trash),
## otherwise removed.
static func delete(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	if not (use_trash and OS.move_to_trash(abs) == OK):
		DirAccess.remove_absolute(abs)


## How long it's been played, as Terraria lists it (h:mm:ss).
static func play_time_text(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
