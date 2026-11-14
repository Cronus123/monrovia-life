extends SceneTree
## Headless smoke test for the 3D prototype (res://proto3d/main_3d.tscn).
## Checks the district loads with collision, the player stands and walks, the camera
## switches views, and a car can be entered, driven and left.
## Run: Godot_console.exe --headless --path . --script res://tests/smoke_3d.gd

var m
var frame := 0
var failures: Array[String] = []
var start_pos := Vector3.ZERO
var car_start := Vector3.ZERO


func _initialize() -> void:
	m = load("res://proto3d/main_3d.tscn").instantiate()
	root.add_child(m)


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)
		push_error("SMOKE3D CHECK FAILED: " + what)


func _physics_process(_d: float) -> bool:
	frame += 1
	match frame:
		60:
			check(m.player.is_on_floor(), "player lands on the district's collision (y=%.2f)" % m.player.global_position.y)
			check(m.cars.size() == 3, "three cars spawned")
			start_pos = m.player.global_position
			Input.action_press("p3_forward")
		120:
			Input.action_release("p3_forward")
			check(m.player.global_position.distance_to(start_pos) > 2.0, "player walks forward")
			m.rig.toggle_view()
			check(m.rig.is_first_person(), "V switches to first person on foot")
		130:
			m.rig.toggle_view()
			check(not m.rig.is_first_person(), "V switches back to third person")
			# walk to the nearest car and get in
			var c = m.cars[0]
			m.player.global_position = c.global_position + Vector3(-2.0, 0.5, 0.0)
		140:
			var c = m.nearest_car()
			check(c != null, "a car is in reach")
			if c != null:
				m.enter_car(c)
				car_start = c.global_position
			check(m.car != null, "player gets in the car")
			check(not m.rig.is_first_person(), "car starts in chase view")
			m.rig.toggle_view()
			check(m.rig.is_first_person(), "V switches the car to first person")
			Input.action_press("p3_forward")
		260:
			Input.action_release("p3_forward")
			if m.car != null:
				check(m.car.global_position.distance_to(car_start) > 5.0, "car drives (moved %.1f m)" % m.car.global_position.distance_to(car_start))
				check(m.car.global_position.y > -1.0, "car stays on the road")
			Input.action_press("p3_jump")   # handbrake
		330:
			Input.action_release("p3_jump")
			m.exit_car()
			check(m.car == null, "player gets out of the car")
			check(not m.rig.is_first_person(), "on-foot view remembered (third person)")
		331:
			m.enter_car(m.nearest_car())
			check(m.rig.is_first_person(), "in-car view remembered (first person)")
			m.exit_car()
		360:
			if failures.is_empty():
				print("SMOKE3D TEST PASSED (player %s)" % str(m.player.global_position.snapped(Vector3(0.1, 0.1, 0.1))))
			else:
				print("SMOKE3D TEST FAILED: ", ", ".join(failures))
			return true
	return frame > 400
