extends SceneTree
## Windowed capture of the 3D game: screenshots to build/screens/game_*.png and per-frame
## FPS on foot, in a police chase, and at night.
## Run: Godot.exe --path . --script res://tests/capture_game.gd

const OUT := "res://build/screens"
var m
var dt := 0.016
var samples := {}
var sampling := ""
var done := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	m = load("res://proto3d/main_city.tscn").instantiate()
	m.auto_start = true
	root.add_child(m)
	run()


func _process(d: float) -> bool:
	dt = d
	if sampling != "":
		if not samples.has(sampling):
			samples[sampling] = []
		samples[sampling].append(1.0 / maxf(d, 0.001))
	return done


func shot(n: String) -> void:
	printerr("shot ", n, " ", Time.get_ticks_msec())
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "/game_" + n + ".png"))
	print("saved ", n)


func seconds(t: float) -> void:
	await create_timer(t).timeout


func until(cond: Callable, max_seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(max_seconds * 1000.0)
	while Time.get_ticks_msec() < end and not cond.call():
		await process_frame


func measure(n: String, t: float) -> void:
	sampling = n
	await seconds(t)
	sampling = ""


func run() -> void:
	printerr("waiting ready")
	await until(func(): return m.ready_done, 60.0)
	printerr("ready ", Time.get_ticks_msec())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await seconds(3.0)
	# on foot, HUD
	m.state.add_money(1200)
	await measure("on_foot", 4.0)
	shot("hud_on_foot")
	# Auntie Musu at Waterside, mission menu
	m.teleport_player(m.shops.place_pos("auntie") + Vector3(0, 0, 4.0))
	await seconds(1.0)
	await until(func(): return not m._busy, 60.0)
	m.rig.yaw = 0.0
	await seconds(2.0)
	m.missions.open_menu()
	await seconds(0.3)
	shot("mission_auntie")
	m.hud.choose(0)
	get_root().get_tree().paused = false
	await seconds(1.0)
	# full map
	m.hud.toggle_map()
	await seconds(0.3)
	shot("map")
	m.hud.toggle_map()
	# settings menu (from the pause menu)
	m.open_settings(func(): pass)
	await seconds(0.5)
	shot("settings")
	m.settings_menu.close()
	get_root().get_tree().paused = false
	await seconds(0.5)
	# a traffic-light junction near downtown
	var best := -1
	var bd := INF
	for nd in m.signals.signals:
		var dd: float = (m.graph.nodes[nd] as Vector3).distance_to(m.streamer.spawn_point())
		if dd < bd:
			bd = dd
			best = nd
	var jpos: Vector3 = m.graph.nodes[best]
	var ap: Array = m.signals.signals[best]["approaches"][0]
	var dir_in: Vector3 = ap[1]
	m.teleport_player(jpos - dir_in * 22.0 + Vector3(-dir_in.z, 0, dir_in.x) * (float(ap[2]) * 0.5 + 2.5))
	await seconds(1.0)
	await until(func(): return not m._busy, 60.0)
	m.rig.yaw = atan2(-dir_in.x, -dir_in.z)
	m.rig.pitch = -0.05
	await measure("junction_on_foot", 4.0)
	shot("traffic_lights")
	# police chase: in a car on the road, 3 stars
	var n: Dictionary = m.graph.nearest(m.player.global_position, 3)
	var lp: Array = m.graph.lane_point(n["edge"], 5.0, 1)
	var fwd: Vector3 = lp[1]
	var c = m.spawn_car("taxi", Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), (lp[0] as Vector3) + Vector3(0, 0.6, 0)))
	await seconds(0.5)
	m.enter_car(c)
	m.missions.fail("test")
	m.police.add_stars(3)
	await until(func(): return m.police.cars.size() >= 2, 20.0)
	for pc in m.police.cars:
		pc.global_position = c.global_transform * Vector3(2.0, 0.6, 14.0 + randf() * 8.0)
		pc.global_rotation.y = c.global_rotation.y
		pc.linear_velocity = Vector3.ZERO
	Input.action_press("p3_forward")
	await measure("police_chase_driving", 5.0)
	shot("police_chase")
	Input.action_release("p3_forward")
	# drive-by: shooting out of the left window
	m.state.give_pistol(30)
	m.rig.yaw = PI / 2
	m.rig._idle_look = -30.0
	await seconds(0.6)
	for k in 40:
		m.weapons._cd = 0.0 if k % 8 == 0 else m.weapons._cd
		m.weapons.try_fire_from_car()
		await process_frame
		if k == 24:
			shot("driveby")
	m.rig.yaw = 0.0
	m.police.clear()
	m.police.remove_all()
	# night
	m.state.time_min = 21.5 * 60.0
	await seconds(2.0)
	Input.action_press("p3_forward")
	await measure("night_driving", 5.0)
	Input.action_release("p3_forward")
	m.exit_car(true)
	m.teleport_player(m.streamer.spawn_point())
	await seconds(1.0)
	await until(func(): return not m._busy, 60.0)
	m.rig.yaw = -0.6
	await seconds(2.0)
	await measure("night_on_foot", 3.0)
	shot("night")
	for k in samples:
		var a: Array = samples[k]
		a.sort()
		var s := 0.0
		for v in a:
			s += v
		print("FPS %s: avg %.0f, 1%% low %.0f, worst %.0f" % [k, s / a.size(), a[int(a.size() * 0.01)], a[0]])
	print("traffic %d, police %d, peds %d" % [m.traffic.cars.size(), m.police.cars.size(), m.peds.size()])
	print("CAPTURE DONE")
	done = true
