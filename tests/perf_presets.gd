extends SceneTree
## Frame-by-frame FPS of one quality preset on this machine (V-sync off, so the real
## headroom shows). The same route every time: on foot downtown, driving across tiles
## with traffic, a rain shower, then night driving.
## Run (one preset per run; Low needs the Compatibility renderer):
##   Godot.exe --path . --rendering-method forward_plus --script res://tests/perf_presets.gd -- --quality=2
##   Godot.exe --path . --rendering-method gl_compatibility --script res://tests/perf_presets.gd -- --quality=0

var m
var q := 1
var sampling := ""
var frames := {}
var drop: PackedStringArray = []          # --drop=ssil,fog,ssr,shadows4 : experiments


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			q = int(a.get_slice("=", 1))
		if a.begins_with("--drop="):
			drop = a.get_slice("=", 1).split(",")
	m = load("res://proto3d/main_city.tscn").instantiate()
	m.auto_start = true
	root.add_child(m)
	run()


func _process(d: float) -> bool:
	if Engine.get_process_frames() % 120 == 0:
		printerr("frame ", Engine.get_process_frames(), " t ", Time.get_ticks_msec())
	if sampling != "":
		if not frames.has(sampling):
			frames[sampling] = []
		frames[sampling].append(d * 1000.0)
	return false


func seconds(t: float) -> void:
	await create_timer(t).timeout


func until(cond: Callable, max_s: float) -> void:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end and not cond.call():
		await process_frame


func measure(n: String, t: float) -> void:
	printerr("measure ", n, " ", Time.get_ticks_msec())
	sampling = n
	await seconds(t)
	sampling = ""


func run() -> void:
	printerr("start ", Time.get_ticks_msec())
	await until(func(): return m.ready_done, 90.0)
	printerr("ready ", Time.get_ticks_msec())
	m.settings.quality = q
	m.settings.apply_world(m)
	if "ssil" in drop: m._env.ssil_enabled = false
	if "fog" in drop: m._env.volumetric_fog_enabled = false
	if "ssr" in drop: m._env.ssr_enabled = false
	if "shadows4" in drop: m._sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await seconds(4.0)
	await measure("on_foot", 6.0)
	# driving along the road graph (an AI driver steers the player's car)
	var n: Dictionary = m.graph.nearest(m.player.global_position, 3)
	var lp: Array = m.graph.lane_point(n["edge"], 5.0, 1)
	var fwd: Vector3 = lp[1]
	var c = m.spawn_car("taxi", Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), (lp[0] as Vector3) + Vector3(0, 0.6, 0)))
	await seconds(0.5)
	m.enter_car(c)
	Input.action_press("p3_forward")
	await measure("driving", 8.0)
	Input.action_release("p3_forward")
	# rain shower
	m.state.rain_from = m.state.time_min - 60.0
	m.state.rain_until = m.state.time_min + 120.0
	m.clock.wet = 1.0
	await seconds(1.0)
	await measure("rain", 5.0)
	m.state.rain_until = m.state.time_min - 1.0
	# night
	m.state.time_min = 21.5 * 60.0
	await seconds(1.5)
	Input.action_press("p3_forward")
	await measure("night_driving", 6.0)
	Input.action_release("p3_forward")
	var all: Array = []
	print("PERF renderer %s, quality %s%s, %s" % [RenderingServer.get_current_rendering_method(), m.settings.QUALITY[q], (" minus " + ",".join(drop)) if not drop.is_empty() else "", RenderingServer.get_video_adapter_name()])
	for k in ["on_foot", "driving", "rain", "night_driving"]:
		if frames.has(k):
			all.append_array(frames[k])
			print("PERF " + _line(k, frames[k]))
	print("PERF " + _line("ALL", all))
	m.queue_free()
	await process_frame
	await process_frame
	quit()


func _line(n: String, ms: Array) -> String:
	ms = ms.duplicate()
	ms.sort()
	var s := 0.0
	for v in ms:
		s += v
	var avg_ms := s / ms.size()
	var p99: float = ms[int(ms.size() * 0.99)]
	var over := 0
	for v in ms:
		if v > 16.9:
			over += 1
	return "%-14s avg %5.1f fps (%.1f ms)  1%% low %5.1f fps  worst %5.1f ms  frames >16.7 ms: %d of %d" % [
		n, 1000.0 / avg_ms, avg_ms, 1000.0 / p99, ms[ms.size() - 1], over, ms.size()]
