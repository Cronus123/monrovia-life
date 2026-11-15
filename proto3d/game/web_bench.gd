class_name WebBench
extends Node
## Browser benchmark (open the page with ?bench=1): waits for the city, measures the title
## flyover, starts a game without the tutorial, walks, sprints and drives the starting taxi,
## and reports frame rate, slow frames, load time, download size and memory - printed to
## the console and sent to the page's own server as GET bench?... (tools/serve_web.py logs
## it). Only ever runs when asked for in the URL.

var title
var city
var results := {}


static func wanted() -> bool:
	if not OS.has_feature("web"):
		return false
	var q = JavaScriptBridge.eval("window.location.search", true)
	return q != null and String(q).contains("bench=1")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run()


func run() -> void:
	while title.city == null or not title.city.ready_done:
		await get_tree().process_frame
	city = title.city
	results["ready_s"] = snappedf(Time.get_ticks_msec() / 1000.0, 0.1)
	results["tiles_mb"] = snappedf(city.streamer.web_bytes / 1048576.0, 0.1)
	results["first_request_s"] = snappedf(city.streamer.first_request_s, 0.1)
	results["first_tile_s"] = snappedf(city.streamer.first_tile_s, 0.1)
	for k in city.load_marks:
		results[k] = snappedf(float(city.load_marks[k]), 0.1)
	await _seconds(3.0)
	results["title"] = await _measure(6.0)
	await _shot("title")
	city.settings.tutorial = false
	title._on_new_game()
	while city._busy or city.title_mode:
		await get_tree().process_frame
	await _seconds(3.0)
	city.rig.yaw = city.player.model.rotation.y
	var p0: Vector3 = city.player.global_position
	Input.action_press("p3_forward")
	results["walk"] = await _measure(8.0)
	await _shot("walk")
	Input.action_press("p3_sprint")
	results["sprint"] = await _measure(8.0)
	Input.action_release("p3_sprint")
	results["walked_m"] = snappedf(city.player.global_position.distance_to(p0), 0.1)
	Input.action_release("p3_forward")
	if city.start_car != null and is_instance_valid(city.start_car):
		city.enter_car(city.start_car)
		results["in_car"] = city.car != null and not city.player.active
		var c0: Vector3 = city.start_car.global_position
		await _seconds(2.0)
		Input.action_press("p3_forward")
		results["drive"] = await _measure(12.0)
		results["drove_m"] = snappedf(city.start_car.global_position.distance_to(c0), 0.1)
		results["still_in_car"] = city.car != null
		await _shot("drive")
		Input.action_release("p3_forward")
	results["tiles_mb_after"] = snappedf(city.streamer.web_bytes / 1048576.0, 0.1)
	results["static_mem_mb"] = snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1)
	results["video_mem_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
	results["renderer"] = RenderingServer.get_current_rendering_method()
	results["gpu"] = RenderingServer.get_video_adapter_name()
	var text := JSON.stringify(results)
	print("BENCH " + text)
	var req := HTTPRequest.new()
	add_child(req)
	req.request(String(JavaScriptBridge.eval("new URL('bench', document.baseURI).href", true)) + "?r=" + text.uri_encode())


func _seconds(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


## Average FPS, 1%-low FPS and the worst frame over `t` seconds.
func _measure(t: float) -> Dictionary:
	var frames: Array[float] = []
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	frames.sort()
	var total := 0.0
	for f in frames:
		total += f
	var p99: float = frames[int(frames.size() * 0.99)] if frames.size() > 0 else 0.0
	return {"fps": snappedf(frames.size() / (total / 1000.0), 0.1), "low1": snappedf(1000.0 / maxf(p99, 0.001), 0.1),
		"worst_ms": roundi(frames.back()) if frames.size() > 0 else 0}


## Screenshot to the local test server (tools/serve_web.py saves it in build/screens/web/).
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var png := get_viewport().get_texture().get_image().save_png_to_buffer()
	var req := HTTPRequest.new()
	add_child(req)
	var url := String(JavaScriptBridge.eval("new URL('shot/" + name + "', document.baseURI).href", true))
	req.request_raw(url, PackedStringArray(["Content-Type: image/png"]), HTTPClient.METHOD_POST, png)
	await req.request_completed
	req.queue_free()
