extends SceneTree
## Renders the 3D prototype in a window and saves screenshots of the third-person,
## first-person and in-car views, plus average FPS for each, to build/screens/.
## Run (windowed, not headless):
##   Godot.exe --path . --script res://tests/capture_3d.gd

const OUT := "res://build/screens"
var m
var frame := 0
var fps_samples := {}
var shot := ""
var _dt := 0.016


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	m = load("res://proto3d/main_3d.tscn").instantiate()
	root.add_child(m)


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "/" + name + ".png"))


func _sample(name: String) -> void:
	if not fps_samples.has(name):
		fps_samples[name] = []
	fps_samples[name].append(1.0 / maxf(_dt, 0.001))   # per-frame, not the 1 s average


func _process(_d: float) -> bool:
	_dt = _d
	frame += 1
	if frame == 2:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Third person on foot, walking toward the taxi.
	if frame == 60:
		Input.action_press("p3_forward")
	if frame > 120 and frame < 240:
		_sample("third_person")
	if frame == 240:
		Input.action_release("p3_forward")
		_save("third_person")
		m.rig.toggle_view()
	if frame > 320 and frame < 400:
		_sample("first_person")
	if frame == 400:
		_save("first_person")
		m.rig.toggle_view()
		var c = m.cars[1]   # the red car: clear road ahead (the taxi is parked behind it)
		m.player.global_position = c.exit_point()
	if frame == 410:
		m.enter_car(m.cars[1])
		Input.action_press("p3_forward")
	if frame > 500 and frame < 600:
		_sample("in_car_chase")
	if frame == 600:
		_save("in_car_chase")
		m.rig.toggle_view()
	if frame > 640 and frame < 720:
		_sample("in_car_first_person")
	if frame == 720:
		Input.action_release("p3_forward")
		_save("in_car_first_person")
		for k in fps_samples:
			var a: Array = fps_samples[k]
			var total := 0.0
			for v in a:
				total += v
			a.sort()
			print("FPS %s: avg %.0f, 1%% low %.0f" % [k, total / a.size(), a[int(a.size() * 0.01)]])
		print("CAPTURE DONE")
		return true
	return false
