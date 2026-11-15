extends SceneTree
## Browser-build checks that run headless on the desktop:
##  - the city streams over HTTP the way the browser build does (a tiny HTTP server in this
##    script serves proto3d/city/, the streamer is switched to web mode), including a
##    missing tile, which is retried 3 times and then left alone
##  - the "Web City" export preset: Compatibility-friendly, single-threaded, tiles left out
##    of the package, the WebGL2 check in the page
##  - the browser-only shaders load, and Import save accepts a save and rejects junk
## Run: Godot.exe --headless --path . --script res://tests/smoke_web.gd

const StreamerScript := preload("res://proto3d/world_streamer.gd")
const OUT := "res://tests/output/web"

var failures := 0
var checks := 0
var server := TCPServer.new()
var port := 0
var clients: Array = []
var served := {}           # path -> times served
var missing := "/city/hi/t_9_9.glb"


func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("SMOKEWEB CHECK FAILED: ", what)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for p in range(18471, 18490):
		if server.listen(p, "127.0.0.1") == OK:
			port = p
			break
	run()


func _process(_delta: float) -> bool:
	_serve()
	return false


## Minimal static file server: GET /city/<lod>/<tile>.glb -> res://proto3d/city/...
func _serve() -> void:
	while server.is_connection_available():
		clients.append({"peer": server.take_connection(), "buf": ""})
	for c in clients.duplicate():
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			clients.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			c["buf"] += peer.get_utf8_string(n)
		if not String(c["buf"]).contains("\r\n\r\n"):
			continue
		var path := String(c["buf"]).split(" ")[1]
		served[path] = int(served.get(path, 0)) + 1
		var file := "res://proto3d" + path
		var body := FileAccess.get_file_as_bytes(file) if path.begins_with("/city/") and FileAccess.file_exists(file) else PackedByteArray()
		var status := "200 OK" if not body.is_empty() else "404 Not Found"
		peer.put_data(("HTTP/1.1 %s\r\nContent-Type: model/gltf-binary\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, body.size()]).to_utf8_buffer())
		if not body.is_empty():
			peer.put_data(body)
		peer.disconnect_from_host()
		clients.erase(c)


func until(cond: Callable, max_s: float) -> bool:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func run() -> void:
	await process_frame
	print("streaming over HTTP")
	check(port > 0, "test HTTP server listening (port %d)" % port)
	var st = StreamerScript.new()
	st.web = true
	st.web_base = "http://127.0.0.1:%d/city/" % port
	root.add_child(st)
	check(st.hi_radius <= 300.0 and st.lo_radius <= 800.0, "web mode starts with the tighter rings (%.0f / %.0f m)" % [st.hi_radius, st.lo_radius])
	var spawn: Vector3 = st.spawn_point()
	st.focus = spawn
	check(await until(func(): return st.is_area_ready(spawn, 140.0), 90.0), "the start area streams in over HTTP")
	var hi := 0
	for p in served:
		if String(p).begins_with("/city/hi/"):
			hi += 1
	check(hi >= 4 and st.web_bytes > 1000000, "%d detailed tiles fetched, %.1f MB" % [hi, st.web_bytes / 1048576.0])
	check(st.detailed_loaded(200.0) >= 4, "and built with collision (%d detailed tiles)" % st.detailed_loaded(200.0))
	var ground := false
	var space := st.get_world_3d().direct_space_state
	await physics_frame
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(spawn + Vector3(0, 50, 0), spawn + Vector3(0, -50, 0), 1))
	ground = not hit.is_empty()
	check(ground, "there's ground to stand on at the spawn point")
	# a tile the server doesn't have: three tries, then left alone (no endless requests)
	var k := Vector2i(9, 9)
	st._has_hi[k] = true
	for i in 6:
		var job := {"key": k, "lod": 2, "path": StreamerScript.CITY_DIR + "hi/t_9_9.glb", "result": null}
		if int(st._web_failed.get(k, 0)) < 3:
			st._jobs[k] = job
			st._fetch(job)
			await until(func(): return not st._jobs.has(k), 10.0)
	check(int(served.get(missing, 0)) == 3 and int(st._web_failed.get(k, 0)) == 3, "a missing tile is tried 3 times, then skipped (%d requests)" % int(served.get(missing, 0)))
	st.queue_free()
	await process_frame

	print("export preset")
	var cfg := ConfigFile.new()
	cfg.load("res://export_presets.cfg")
	var sec := ""
	for s in cfg.get_sections():
		if String(cfg.get_value(s, "name", "")) == "Web City":
			sec = s
	check(sec != "", "a \"Web City\" export preset")
	if sec != "":
		var ex := String(cfg.get_value(sec, "exclude_filter", ""))
		check(ex.contains("proto3d/city/hi/*") and ex.contains("proto3d/city/lo/*"), "city tiles are left out of the package")
		check(String(cfg.get_value(sec, "include_filter", "")).contains("proto3d/city/*"), "the city's small data files are packed")
		var opt := sec + ".options"
		check(cfg.get_value(opt, "variant/thread_support", true) == false, "single-threaded (no special server headers needed)")
		check(String(cfg.get_value(opt, "html/head_include", "")).contains("webgl2"), "the page checks for WebGL 2")
		check(String(cfg.get_value(sec, "custom_features", "")) == "city3d", "starts on the title screen (city3d feature)")

	print("browser shaders and saves")
	for s in ["city_surfaces_web", "sky_web", "water_web"]:
		var sh := load("res://proto3d/%s.gdshader" % s) as Shader
		check(sh != null and sh.get_shader_uniform_list().size() > 0, "%s.gdshader loads" % s)
	var TitleScript = load("res://proto3d/title.gd")
	var good := JSON.stringify({"version": 1, "money": 1234, "pos": [0, 0, 0]})
	check(TitleScript.import_save_text(good, OUT + "/save.json") and FileAccess.file_exists(OUT + "/save.json"),
		"Import save accepts a save file (written to tests/output)")
	check(not TitleScript.import_save_text("<html>not a save</html>", OUT + "/save2.json") and not TitleScript.import_save_text("{\"a\":1}", OUT + "/save2.json"),
		"and rejects other files")

	server.stop()
	if failures == 0:
		print("SMOKEWEB TEST PASSED (%d checks)" % checks)
	else:
		print("SMOKEWEB TEST FAILED: %d of %d checks" % [failures, checks])
	quit(1 if failures > 0 else 0)
