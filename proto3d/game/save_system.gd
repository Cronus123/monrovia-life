class_name SaveSystem
extends RefCounted
## Versioned save file for the 3D game (separate from the 2D game's save). Writes to a
## temporary file first and then swaps it in, so a crash mid-save can't corrupt it.

const PATH := "user://monrovia_city_save.json"
const VERSION := 1


static func has_save(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)


static func save(state: GameState, player_pos: Vector3, path: String = PATH) -> bool:
	var data := state.to_dict()
	data["version"] = VERSION
	data["pos"] = [player_pos.x, player_pos.y, player_pos.z]
	data["saved_at"] = Time.get_datetime_string_from_system()
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, " "))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	if FileAccess.file_exists(path):
		dir.remove(path.get_file())
	return dir.rename(tmp.get_file(), path.get_file()) == OK


## Returns the saved player position (or null) after loading the state.
static func load_into(state: GameState, path: String = PATH):
	if not FileAccess.file_exists(path):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var version := int(d.get("version", 0))
	if version > VERSION:
		push_warning("Save file is from a newer version of the game; loading what we can.")
	state.from_dict(d)
	var p: Array = d.get("pos", [])
	return Vector3(p[0], p[1], p[2]) if p.size() == 3 else null
