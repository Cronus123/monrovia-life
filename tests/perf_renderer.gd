extends SceneTree
## Measures per-frame FPS of the city in the current renderer, then with each Forward+
## effect added in turn (vsync off, so the true cost shows).
## Run: Godot.exe --path . --rendering-method forward_plus --script res://tests/perf_renderer.gd

var m
var samples: Array = []
var sampling := false


func _initialize() -> void:
	m = load("res://proto3d/main_city.tscn").instantiate()
	m.auto_start = true
	root.add_child(m)
	run()


func _process(d: float) -> bool:
	if sampling:
		samples.append(1.0 / maxf(d, 0.0001))
	return false


func seconds(t: float) -> void:
	await create_timer(t).timeout


func measure(label: String) -> void:
	samples.clear()
	sampling = true
	await seconds(4.0)
	sampling = false
	samples.sort()
	var s := 0.0
	for v in samples:
		s += v
	print("PERF %-28s avg %4.0f  1%% low %4.0f" % [label, s / samples.size(), samples[int(samples.size() * 0.01)]])


func run() -> void:
	while not m.ready_done:
		await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await seconds(4.0)
	print("PERF renderer: ", RenderingServer.get_current_rendering_method(), " / ", RenderingServer.get_video_adapter_name())
	await measure("base")
	var env: Environment = m._env
	env.ssao_enabled = true
	await measure("+ SSAO")
	env.ssil_enabled = true
	await measure("+ SSIL")
	env.ssr_enabled = true
	await measure("+ SSR")
	env.glow_enabled = true
	await measure("+ glow")
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.01
	await measure("+ volumetric fog")
	m._sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	m._sun.directional_shadow_max_distance = 150.0
	await measure("+ 4-split shadows 150 m")
	quit()
