extends SceneTree
## Windowed screenshots of the vehicles (build/screens/veh_*.png): a lineup of the whole
## fleet, a taxi close-up, the keke, a busy street, a crash, and the lights at night.
## Run: Godot.exe --path . --script res://tests/capture_vehicles.gd

const OUT := "res://build/screens"
const FLEET := ["taxi", "keke", "car", "suv", "sport", "pickup", "minibus", "truck", "van", "police"]
var m


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	m = load("res://proto3d/main_city.tscn").instantiate()
	m.auto_start = true
	root.add_child(m)
	run()


class Floor:
	func drive_input(_c) -> Vector3:
		return Vector3(1, 0, 0)


func seconds(t: float) -> void:
	await create_timer(t).timeout


func until(cond: Callable, max_s: float) -> void:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end and not cond.call():
		await process_frame


func snap(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "/veh_" + name + ".png"))
	printerr("saved ", name)


func cam(eye: Vector3, look: Vector3) -> void:
	m.rig.process_mode = Node.PROCESS_MODE_DISABLED
	m.rig.cam.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(look)


func goto(p: Vector3) -> void:
	m.rig.process_mode = Node.PROCESS_MODE_INHERIT
	m.teleport_player(p)
	await process_frame
	await until(func(): return not m._busy, 60.0)
	await seconds(1.0)


func run() -> void:
	await until(func(): return m.ready_done, 90.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	m.state.time_min = 10.0 * 60.0
	m.state.rain_until = -1.0
	m.hud.visible = false
	# lineup on the open ground of the Sinkor rally site
	var base: Vector3 = m.big_talk.spot("rally") + Vector3(-20, 0.8, -30)
	await goto(base + Vector3(0, 0, 12))
	var cars := []
	for i in FLEET.size():
		var c = m.spawn_car(FLEET[i], Transform3D(Basis(Vector3.UP, PI * 0.5), base + Vector3(i * 4.2 - 19.0, 0.3, 0)))
		cars.append(c)
	await seconds(2.5)
	cam(base + Vector3(-24, 5.5, 13), base + Vector3(0, 0.5, 0))
	await seconds(0.4)
	await snap("lineup")
	cam(base + Vector3(-17.0, 1.6, 5.0), base + Vector3(-19.0, 0.9, 0))
	await seconds(0.4)
	await snap("taxi")
	cam(base + Vector3(-12.6, 1.7, 3.6), base + Vector3(-14.8, 0.8, 0))
	await seconds(0.4)
	await snap("keke")
	# crash: two cars into each other
	var a = cars[2]
	var b = cars[3]
	var mid := base + Vector3(10, 0.6, 30)
	a.reset_to(Transform3D(Basis.IDENTITY, mid + Vector3(0, 0, 18)))
	b.reset_to(Transform3D(Basis(Vector3.UP, PI * 0.5), mid + Vector3(-14, 0, 0.5)))
	a.controller = Floor.new()
	b.controller = Floor.new()
	a.sleeping = false
	b.sleeping = false
	await seconds(0.6)
	a.linear_velocity = Vector3(0, 0, -22)
	b.linear_velocity = Vector3(16, 0, 0)
	await until(func(): return a.damage > 0.0 or b.damage > 0.0, 4.0)
	await seconds(0.35)
	var hit: Vector3 = (a.global_position + b.global_position) / 2.0
	cam(hit + Vector3(6.5, 3.2, 7.0), hit + Vector3(0, 0.6, 0))
	await seconds(0.2)
	await snap("crash")
	for c in cars:
		m.remove_car(c)
	# busy street: Broad Street downtown with traffic
	var spawn: Vector3 = m.streamer.spawn_point()
	await goto(spawn)
	await until(func(): return m.traffic.cars.size() >= 12, 20.0)
	await seconds(4.0)
	# frame the busiest stretch: the traffic car with the most others near it
	var best = null
	var bn := -1
	for c in m.traffic.cars:
		var k := 0
		for o in m.traffic.cars:
			if o.global_position.distance_to(c.global_position) < 45.0:
				k += 1
		if k > bn:
			bn = k
			best = c
	var p: Vector3 = best.global_position
	var fwd: Vector3 = -best.global_basis.z
	cam(p - fwd * 16.0 + Vector3(0, 6.0, 0) + Vector3(fwd.z, 0, -fwd.x) * 5.0, p + fwd * 12.0)
	await seconds(0.3)
	await snap("street")
	# night lights
	m.state.time_min = 21.0 * 60.0
	var t = m.spawn_car("taxi", Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), p + Vector3(0, 0.6, 0)))
	t.controller = load("res://proto3d/game/graph_driver.gd").new(m.graph, "wander", null, 8.0, 3)
	t.set_headlights(true)
	await seconds(3.0)
	cam(t.global_position + t.global_basis * Vector3(1.5, 1.6, -8), t.global_position + Vector3(0, 0.6, 0))
	await seconds(0.3)
	await snap("night")
	m.queue_free()
	await seconds(1.0)
	quit()
