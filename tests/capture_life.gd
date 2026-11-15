extends SceneTree
## Windowed screenshots of street life (build/screens/life_*.png): a busy market street with
## stall sellers and chatting groups, kids playing football, people sheltering from rain,
## and a wheelbarrow vendor.
## Run: Godot.exe --path . --script res://tests/capture_life.gd

var m


func _initialize() -> void:
	m = load("res://proto3d/main_city.tscn").instantiate()
	m.auto_start = true
	root.add_child(m)
	run()


func seconds(t: float) -> void:
	await create_timer(t).timeout


func until(cond: Callable, max_s: float) -> void:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end and not cond.call():
		await process_frame


func snap(name: String) -> void:
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/screens/life_" + name + ".png"))
	printerr("saved ", name)


func look(eye: Vector3, at: Vector3) -> void:
	m.rig.process_mode = Node.PROCESS_MODE_DISABLED
	m.rig.cam.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(at)
	await seconds(0.4)


func goto(p: Vector3) -> void:
	m.rig.process_mode = Node.PROCESS_MODE_INHERIT
	m.teleport_player(p)
	await process_frame
	await until(func(): return not m._busy, 60.0)
	await seconds(4.0)


func run() -> void:
	await until(func(): return m.ready_done, 90.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	m.hud.visible = false
	m.state.time_min = 9.5 * 60.0
	m.state.rain_until = -1.0
	# a market street: the stall with the most life around it
	await goto(m.shops.place_pos("west_point_market"))
	await seconds(3.0)
	var best = null
	for k in m.street_life.scenes:
		if m.street_life.scenes[k]["kind"] == "seller":
			best = m.street_life.scenes[k]["pos"]
	if best == null:
		best = m.player.global_position
	await look(best + Vector3(9, 4.5, 9), best)
	await snap("market")
	# football: find a game near a few places
	for pid in ["sinkor", "park_sinkor", "capitol", "fiamah", "jallah_town"]:
		await goto(m.shops.place_pos(pid))
		await seconds(2.0)
		var f = null
		for k in m.street_life.scenes:
			if m.street_life.scenes[k]["kind"] == "football":
				f = m.street_life.scenes[k]["pos"]
		if f != null:
			await seconds(3.0)
			await look(f + Vector3(10, 5, 10), f)
			await snap("football")
			break
	# a vendor with a barrow
	for p in m.peds:
		if p.vendor:
			var vp: Vector3 = p.global_position
			var fw: Vector3 = Basis(Vector3.UP, p.body.rotation.y) * Vector3.FORWARD
			await look(vp + fw * 4.0 + Vector3(2.5, 1.8, 0), vp + Vector3(0, 0.8, 0))
			await snap("vendor")
			break
	# rain: people under the awnings
	await goto(m.streamer.spawn_point())
	m.state.rain_from = m.state.time_min - 60.0
	m.state.rain_until = m.state.time_min + 200.0
	m.clock.wet = 1.0
	await seconds(9.0)
	var sp: Vector3 = m.streamer.spawn_point()
	await look(sp + Vector3(-14, 6, 14), sp)
	await snap("rain")
	m.queue_free()
	await seconds(1.0)
	quit()
