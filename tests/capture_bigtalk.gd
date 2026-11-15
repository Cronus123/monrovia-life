extends SceneTree
## Windowed screenshots of Big Talk Dweh at each stage (build/screens/bigtalk_*.png) and
## frame times at his busiest scene (the rally: crowd + convoy) with V-sync off.
## Run: Godot.exe --path . --script res://tests/capture_bigtalk.gd

const OUT := "res://build/screens"
var m
var bt
var st: GameState
var sampling := false
var ms: Array = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	m = load("res://proto3d/main_city.tscn").instantiate()
	m.auto_start = true
	root.add_child(m)
	run()


func _process(d: float) -> bool:
	if sampling:
		ms.append(d * 1000.0)
	return false


func seconds(t: float) -> void:
	await create_timer(t).timeout


func until(cond: Callable, max_s: float) -> void:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end and not cond.call():
		await process_frame


func stage(n: int, ending: String = "") -> void:
	st.bt_stage = n
	st.bt_ending = ending
	st.bt_posters = [0, 1, 2, 3, 4, 5]
	st.mission_idx = n
	bt.refresh()


## Stand the player near `at`, then frame the shot from `eye` looking at `look`.
func shot(name: String, at: Vector3, eye: Vector3, look: Vector3) -> void:
	m.teleport_player(at)
	await process_frame
	await until(func(): return not m._busy, 60.0)
	m.rig.process_mode = Node.PROCESS_MODE_DISABLED
	await seconds(2.5)
	m.rig.cam.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(look)
	bt._line_t = 0.05                       # say something for the picture
	await seconds(0.6)
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "/bigtalk_" + name + ".png"))
	printerr("saved ", name)
	m.rig.process_mode = Node.PROCESS_MODE_INHERIT


func around(target: Vector3, yaw: float, dist: float, height: float) -> Vector3:
	return target + Basis(Vector3.UP, yaw) * Vector3(0, height, -dist)


func run() -> void:
	await until(func(): return m.ready_done, 90.0)
	bt = m.big_talk
	st = m.state
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	st.time_min = 10.0 * 60.0
	st.rain_until = -1.0
	m.hud.visible = false
	# 1 crate
	stage(0)
	var p: Vector3 = bt.npc.global_position
	await shot("1_crate", p + Vector3(4, 0, -6), p + Vector3(3.5, 1.4, -5.5), p + Vector3(0, 1.2, 0))
	# 2 billboard
	stage(1)
	var b: Array = bt.spots["billboard"]
	var bp := Vector3(b[0], b[1], b[2])
	var by := float(b[3])
	await shot("2_billboard", around(bp, by, 14.0, 0.3), around(bp, by, 15.0, 2.2), bp + Vector3(0, 3.8, 0))
	# 3 rally
	stage(2)
	var r: Vector3 = bt.spot("rally")
	await shot("3_rally", r + Vector3(0, 0.5, -18), r + Vector3(3, 4.0, -17), r + Vector3(0, 1.5, 0))
	# FPS at the rally (Medium preset, V-sync off)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	m.rig.process_mode = Node.PROCESS_MODE_INHERIT
	await seconds(2.0)
	sampling = true
	await seconds(6.0)
	sampling = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	# 4 house
	stage(3)
	var h: Vector3 = bt.spot("house")
	var hy := float(bt.spots["house"]["yaw"])
	await shot("4_house", around(h, hy, 40.0, 0.5), around(h, hy, 42.0, 9.0), h + Vector3(0, 4.0, 0))
	# 5 endings
	stage(4, "senator")
	var s: Array = bt.spots["statue"]
	var sp := Vector3(s[0], s[1], s[2])
	await shot("5_senator", around(sp, float(s[3]), 12.0, 0.3), around(sp, float(s[3]), 11.0, 2.4), sp + Vector3(0, 3.0, 0))
	stage(4, "expose")
	var q: Vector3 = bt.npc.global_position
	await shot("5_exposed", q + Vector3(0, 0, -6), q + Vector3(2.5, 1.6, -4.5), q + Vector3(0, 1.1, 0))
	ms.sort()
	var tot := 0.0
	for v in ms:
		tot += v
	print("RALLY FPS (Medium, V-sync off): avg %.0f, 1%% low %.0f, worst frame %.1f ms over %d frames" % [
		1000.0 / (tot / ms.size()), 1000.0 / ms[int(ms.size() * 0.99)], ms[ms.size() - 1], ms.size()])
	m.queue_free()
	await seconds(1.0)
	quit()
