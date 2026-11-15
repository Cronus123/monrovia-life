extends SceneTree
## Headless smoke test for the 3D prototype (res://proto3d/main_3d.tscn).
## Checks the district loads with collision and street dressing, pedestrians walk,
## the player stands, walks and gets knocked down and up, the camera switches views,
## and a car can be entered, driven, braked and left.
## Run: Godot_console.exe --headless --path . --script res://tests/smoke_3d.gd

var m
var frame := 0
var failures: Array[String] = []
var start_pos := Vector3.ZERO
var car_start := Vector3.ZERO
var ped_start: Array = []


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
			check(m.ready_done, "street dressing finished")
			check(m.player.is_on_floor(), "player lands on the district's collision (y=%.2f)" % m.player.global_position.y)
			check(m.cars.size() >= 6, "spawned and parked cars (got %d)" % m.cars.size())
			check(m.dresser.sidewalk_paths.size() >= 6, "sidewalk paths built (got %d)" % m.dresser.sidewalk_paths.size())
			check(m.peds.size() == m.PEDESTRIANS, "pedestrians spawned")
			for p in m.peds:
				ped_start.append(p.global_position)
			start_pos = m.player.global_position
			Input.action_press("p3_forward")
		120:
			var pb = m.player.body
			for a in ["Idle", "Walk", "Run", "Jump", "SitDown", "Death"]:
				check(pb.anim_player.has_animation(a), "character has the %s animation" % a)
			check(pb.tree.active and pb.current_state() == "move", "locomotion state is playing (%s)" % pb.current_state())
			check(pb.tree.get("parameters/move/blend/blend_position") > 1.0, "walk/run blend follows speed")
			var models := {}
			for ped in m.peds:
				models[ped.body.rig.scene_file_path] = true
			check(models.size() >= 3, "pedestrians use varied character models (%d)" % models.size())
			Input.action_release("p3_forward")
			check(m.player.global_position.distance_to(start_pos) > 2.0, "player walks forward")
			m.rig.toggle_view()
			check(m.rig.is_first_person(), "V switches to first person on foot")
		130:
			m.rig.toggle_view()
			check(not m.rig.is_first_person(), "V switches back to third person")
			m.player.knockdown(Vector3(4, 0, 0))
			check(m.player.is_down(), "player can be knocked down")
		140:
			check(m.player.body.is_ragdolling() or m.player.body.current_state() == "knocked", "player falls (ragdoll or fall animation)")
		300:
			check(not m.player.is_down(), "player gets back up")
			var moved := 0
			for i in m.peds.size():
				if m.peds[i].global_position.distance_to(ped_start[i]) > 1.0:
					moved += 1
			check(moved >= m.peds.size() / 2, "pedestrians walk (%d of %d moved)" % [moved, m.peds.size()])
			var fallen := 0
			for p in m.peds:
				if p.global_position.y < -1.0:
					fallen += 1
			check(fallen == 0, "no pedestrian fell through the world (%d fell)" % fallen)
			var c = m.cars[0]
			m.player.global_position = c.exit_point()
		310:
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
		430:
			Input.action_release("p3_forward")
			if m.car != null:
				var d: float = m.car.global_position.distance_to(car_start)
				check(d > 5.0, "car drives (moved %.1f m)" % d)
				check(m.car.global_position.y > -1.0 and m.car.global_basis.y.y > 0.7, "car stays upright on the road")
			Input.action_press("p3_jump")   # handbrake
		560:
			Input.action_release("p3_jump")
			if m.car != null:
				check(absf(m.car.speed) < 4.0, "handbrake stops the car (%.1f m/s)" % m.car.speed)
			m.exit_car()
			check(m.car == null, "player gets out of the car")
			check(not m.rig.is_first_person(), "on-foot view remembered (third person)")
		561:
			m.enter_car(m.nearest_car())
			check(m.rig.is_first_person(), "in-car view remembered (first person)")
			m.exit_car()
		600:
			if failures.is_empty():
				print("SMOKE3D TEST PASSED (player %s)" % str(m.player.global_position.snapped(Vector3(0.1, 0.1, 0.1))))
			else:
				print("SMOKE3D TEST FAILED: ", ", ".join(failures))
			return true
	return frame > 700
