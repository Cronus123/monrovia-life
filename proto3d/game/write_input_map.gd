extends SceneTree
## Writes InputDefaults.ACTIONS into project.godot's Input Map.
## Run once after changing the defaults:
##   Godot_console.exe --headless --path . --script res://proto3d/game/write_input_map.gd


const Defaults := preload("res://proto3d/game/input_defaults.gd")


func _initialize() -> void:
	for a in Defaults.ACTIONS:
		ProjectSettings.set_setting("input/" + a, {"deadzone": 0.25, "events": Defaults.events_for(a)})
	var err := ProjectSettings.save()
	print("Input Map written to project.godot: ", "ok" if err == OK else "error %d" % err)
	quit()
