extends Node3D
## Streams the generated 1:1 Monrovia tiles (proto3d/city, from tools/build_osm_city.py)
## around a focus point (the player or the car being driven):
##   within hi_radius: detailed tile with collision, street signs, sidewalk paths, parking
##   within lo_radius: low-detail tile (no collision)
## Tiles are parsed on worker threads with GLTFDocument (they're kept as raw .glb files,
## not imported), collision shapes are built on the worker too, and only the final
## add_child happens on the main thread - a few per frame - so driving doesn't stutter.

signal tile_loaded(key: Vector2i, detailed: bool)

const CITY_DIR := "res://proto3d/city/"
var hi_radius := 420.0          # detailed tiles (Settings: graphics quality)
var lo_radius := 1300.0         # low-detail ring
var detail_range := 260.0       # building details fade out beyond this (Settings: quality)
const MAX_JOBS := 3
const ATTACH_PER_FRAME := 1
## Browser build: tile .glb files aren't in the game package (it would be 285 MB to download
## before playing); they're fetched over HTTP from <page>/city/ as they're needed, and the
## browser's HTTP cache keeps them. No threads on the web build, so each fetched tile is
## parsed on the main thread, one per frame.
var web := OS.has_feature("web")
var web_base := ""                # e.g. https://play.libgamer.com/city/
var web_bytes := 0               # downloaded so far (for the loading screen / report)
var first_request_s := 0.0       # when the first tile was asked for / arrived (benchmark)
var first_tile_s := 0.0
var _parse_queue: Array = []
var _web_failed := {}            # tile -> failed fetches (gives up after 3)
const WEB_MAX_REQUESTS := 4
const SHADER := preload("res://proto3d/city_surfaces.gdshader")
const SHADER_WEB := preload("res://proto3d/city_surfaces_web.gdshader")   # quick to compile in browsers
const PropsScript := preload("res://proto3d/props.gd")

var manifest: Dictionary
var tile_size := 256.0
var focus := Vector3.ZERO
var tiles := {}                 # Vector2i -> {"lod": 0|1|2, "node": Node3D, "meta": Dictionary}
var _has_hi := {}
var _jobs := {}                 # Vector2i -> {"lod": int, "task": int, "result": Variant}
var _ready_queue: Array = []
var _mats := {}
var _timer := 0.0
var _grass_mesh: ArrayMesh
var _plants: Array = []         # Palm, Tree, Bush meshes (proto3d/city/vegetation.glb)
var grass_enabled := true      # Settings: off on Low
var _prop_queue: Array = []     # [tile instance id, meta chunk]: physics props, a few per frame
const PROPS_PER_FRAME := 6


func _ready() -> void:
	if web:
		hi_radius = 300.0           # until Settings apply: the first area is all downloaded
		lo_radius = 800.0
	manifest = JSON.parse_string(FileAccess.get_file_as_string(CITY_DIR + "manifest.json"))
	tile_size = manifest["tile_size"]
	for t in manifest["hi"]:
		_has_hi[Vector2i(t[0], t[1])] = true
	# Shared materials for every tile, by the material names the generator writes.
	var kinds := {"Terrain": 0, "Road": 1, "Sidewalk": 2, "Wall": 3, "Roof": 4, "Props": 5, "Rail": 5, "LoVC": 5}
	for n in kinds:
		var m := ShaderMaterial.new()
		m.shader = SHADER_WEB if web else SHADER
		m.set_shader_parameter("kind", kinds[n])
		_mats[n] = m
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.vertex_color_is_srgb = true
	paint.roughness = 0.6
	_mats["Paint"] = paint
	var fol := ShaderMaterial.new()
	fol.shader = preload("res://proto3d/foliage.gdshader")
	_mats["Foliage"] = fol
	_grass_mesh = _make_grass_tuft()
	_load_plants()
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("#fff4cc")
	glow.emission_enabled = true
	glow.emission = Color("#fff4cc")
	glow.emission_energy_multiplier = 1.2
	_mats["Glow"] = glow


func spawn_point() -> Vector3:
	var s: Array = manifest["spawn"]
	return Vector3(s[0], s[1], s[2])


func tile_key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / tile_size)), int(floor(-p.z / tile_size)))


func tile_center(k: Vector2i) -> Vector3:
	return Vector3((k.x + 0.5) * tile_size, 0.0, -(k.y + 0.5) * tile_size)


## Detailed tiles currently loaded around the focus (with collision).
func detailed_loaded(radius: float = -1.0) -> int:
	if radius < 0.0:
		radius = hi_radius
	var n := 0
	for k in tiles:
		if tiles[k]["lod"] == 2 and _dist(k) < radius:
			n += 1
	return n


func is_area_ready(p: Vector3, radius: float = 200.0) -> bool:
	var k := tile_key(p)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var kk := k + Vector2i(dx, dy)
			if _has_hi.has(kk) and _dist_from(kk, p) < radius and (not tiles.has(kk) or tiles[kk]["lod"] != 2):
				return false
	return true


## How much of what is_area_ready() waits for has loaded, 0..1 (the title's progress bar).
func area_progress(p: Vector3, radius: float = 200.0) -> float:
	var k := tile_key(p)
	var need := 0
	var have := 0
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var kk := k + Vector2i(dx, dy)
			if _has_hi.has(kk) and _dist_from(kk, p) < radius:
				need += 1
				if tiles.has(kk) and tiles[kk]["lod"] == 2:
					have += 1
	return 1.0 if need == 0 else float(have) / need


func _dist(k: Vector2i) -> float:
	return _dist_from(k, focus)


func _dist_from(k: Vector2i, p: Vector3) -> float:
	# distance from p to the nearest point of the tile square
	var x0 := k.x * tile_size
	var z1 := -k.y * tile_size
	var dx := maxf(0.0, maxf(x0 - p.x, p.x - (x0 + tile_size)))
	var dz := maxf(0.0, maxf((z1 - tile_size) - p.z, p.z - z1))
	return Vector2(dx, dz).length()


func _process(delta: float) -> void:
	if web and not _parse_queue.is_empty():
		_load_tile(_parse_queue.pop_front())
	# finish loaded jobs (a few per frame)
	for _i in ATTACH_PER_FRAME:
		if _ready_queue.is_empty():
			break
		_attach(_ready_queue.pop_front())
	if not _prop_queue.is_empty():
		var job: Array = _prop_queue.pop_front()
		var tile := instance_from_id(job[0]) as Node3D
		if tile != null and tile.is_inside_tree():
			PropsScript.spawn(tile, job[1], _mats["Glow"], _mats["Props"])
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.15
	_update_wanted()


func _update_wanted() -> void:
	var want := {}
	var fk := tile_key(focus)
	var r := int(ceil(lo_radius / tile_size)) + 1
	for t in manifest["tiles"]:
		var k := Vector2i(t[0], t[1])
		if absi(k.x - fk.x) > r or absi(k.y - fk.y) > r:
			continue
		var d := _dist(k)
		if d < hi_radius and _has_hi.has(k):
			want[k] = 2
		elif d < lo_radius:
			want[k] = 1
	# unload tiles no longer wanted
	for k in tiles.keys():
		if not want.has(k):
			_free_tile(k)
	# start loads, nearest first
	var todo: Array = []
	for k in want:
		var cur: int = tiles[k]["lod"] if tiles.has(k) else 0
		if cur != want[k] and not _jobs.has(k) and int(_web_failed.get(k, 0)) < 3:
			todo.append(k)
	todo.sort_custom(func(a, b): return _dist(a) < _dist(b))
	for k in todo:
		if _jobs.size() >= (WEB_MAX_REQUESTS if web else MAX_JOBS):
			break
		_start_job(k, want[k])


func _start_job(k: Vector2i, lod: int) -> void:
	var path := CITY_DIR + ("hi/" if lod == 2 else "lo/") + "t_%d_%d.glb" % [k.x, k.y]
	var job := {"key": k, "lod": lod, "path": path, "result": null}
	_jobs[k] = job
	if web:
		_fetch(job)
		return
	if DisplayServer.get_name() == "headless":
		# The headless dummy renderer isn't thread-safe for mesh/material creation
		# (the real renderers are), so tests load tiles on the main thread.
		_load_tile(job)
		return
	# High priority on purpose: the Forward+ renderer compiles shader pipelines on the pool's
	# low-priority threads, and a tile job creating meshes can wait on the renderer - if the
	# tile jobs filled the low-priority lane, the two would wait on each other forever.
	job["task"] = WorkerThreadPool.add_task(_load_tile.bind(job), true, "city tile")


## Worker thread: parse the glb, build collision shapes, assign shared materials.
func _load_tile(job: Dictionary) -> void:
	var bytes: PackedByteArray = job["bytes"] if job.has("bytes") else FileAccess.get_file_as_bytes(job["path"])
	job.erase("bytes")
	var node: Node3D = null
	if not bytes.is_empty():
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_buffer(bytes, "", state) == OK:
			node = doc.generate_scene(state) as Node3D
	var shapes: Array = []
	if node != null:
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for i in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(i)
				var nm: String = mat.resource_name if mat != null else ""
				if _mats.has(nm):
					m.set_surface_override_material(i, _mats[nm])
			if String(m.name).ends_with("-col"):
				shapes.append([m, m.mesh.create_trimesh_shape()])
			if String(m.name) == "Props":
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			elif String(m.name) == "Foliage":
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				m.visibility_range_end = detail_range + 120.0
			elif String(m.name) == "Details":
				# building clutter (ledges, tanks, AC units, awnings): fades out with distance
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				m.visibility_range_end = detail_range
				m.visibility_range_end_margin = 30.0
				m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			elif String(m.name) in ["Lo", "Sidewalks-col", "Roads-col"]:
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var meta: Dictionary = {}
	if job["lod"] == 2:
		var mp: String = String(job["path"]).replace("/hi/", "/meta/").replace(".glb", ".json")
		if job.has("meta_text"):
			# browser build: fetched over HTTP with the tile (not in the game package)
			var parsed = JSON.parse_string(String(job["meta_text"])) if String(job["meta_text"]) != "" else null
			meta = parsed if parsed is Dictionary else {}
			job.erase("meta_text")
		elif FileAccess.file_exists(mp):
			meta = JSON.parse_string(FileAccess.get_file_as_string(mp))
	job["result"] = {"node": node, "shapes": shapes, "meta": meta}
	call_deferred("_job_done", job)


func _job_done(job: Dictionary) -> void:
	if job.has("task"):
		WorkerThreadPool.wait_for_task_completion(job["task"])
		job.erase("task")          # a task id may only be waited on once
	_ready_queue.append(job)


func _attach(job: Dictionary) -> void:
	var k: Vector2i = job["key"]
	_jobs.erase(k)
	var res: Dictionary = job["result"]
	var node: Node3D = res["node"]
	if node == null:
		return
	# still wanted at this detail?
	var d := _dist(k)
	var still: int = 2 if (d < hi_radius and _has_hi.has(k)) else (1 if d < lo_radius else 0)
	if still != job["lod"]:
		node.queue_free()
		return
	for s in res["shapes"]:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		cs.shape = s[1]
		body.add_child(cs)
		(s[0] as Node3D).add_child(body)
	node.name = "Tile_%d_%d_%s" % [k.x, k.y, "hi" if job["lod"] == 2 else "lo"]
	add_child(node)
	if job["lod"] == 2:
		_add_signs_later.call_deferred(node.get_instance_id(), res["meta"])   # next frame: spreads the work
	if tiles.has(k):
		(tiles[k]["node"] as Node).queue_free()
	tiles[k] = {"lod": job["lod"], "node": node, "meta": res["meta"]}
	tile_loaded.emit(k, job["lod"] == 2)


## On exit: wait for tiles still loading on worker threads and free what they built,
## so nothing is left half-created (or leaked) when the game closes.
func _exit_tree() -> void:
	for job in _jobs.values():
		if job.has("task"):
			WorkerThreadPool.wait_for_task_completion(job["task"])
		_free_job(job)
	for job in _ready_queue:
		_free_job(job)
	_jobs.clear()
	_ready_queue.clear()


func _free_job(job: Dictionary) -> void:
	var res = job.get("result")
	if res is Dictionary and res.get("node") != null and not (res["node"] as Node).is_inside_tree():
		(res["node"] as Node).free()
		job["result"] = null


func _free_tile(k: Vector2i) -> void:
	(tiles[k]["node"] as Node).queue_free()
	tiles.erase(k)


## Grass tufts on the green spots listed in the tile meta (one MultiMesh per tile).
func _add_grass(tile: Node3D, meta: Dictionary) -> void:
	var spots: Array = meta.get("grass", [])
	if spots.is_empty() or not grass_enabled:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _grass_mesh
	mm.instance_count = spots.size() * 3
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tile.name)
	var i := 0
	for s in spots:
		for k in 3:
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4))
			mm.set_instance_transform(i, Transform3D(b, Vector3(s[0] + rng.randf_range(-2.0, 2.0), s[1] - 0.05, s[2] + rng.randf_range(-2.0, 2.0))))
			i += 1
	var mi := MultiMeshInstance3D.new()
	mi.name = "Grass"
	mi.multimesh = mm
	mi.material_override = _mats["Foliage"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 75.0
	mi.visibility_range_end_margin = 15.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	tile.add_child(mi)


## One grass tuft: 3 crossed blades-cards, tips sway (vertex alpha).
func _make_grass_tuft() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var d := Vector3(cos(a), 0, sin(a)) * 0.35
		var h := 0.55
		var base := Color(0.3, 0.45, 0.16, 0.0)
		var tip := Color(0.55, 0.62, 0.25, 1.0)
		var v := [[-d, base], [d, base], [d * 0.6 + Vector3(0, h, 0), tip], [-d * 0.6 + Vector3(0, h, 0), tip]]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(v[idx][1])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[idx][0])
	return st.commit()


func _load_plants() -> void:
	var bytes := FileAccess.get_file_as_bytes(CITY_DIR + "vegetation.glb")
	if bytes.is_empty():
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_buffer(bytes, "", state) != OK:
		return
	var scene := doc.generate_scene(state)
	for n in ["Palm", "Tree", "Bush"]:
		var mi := scene.find_child(n, true, false) as MeshInstance3D
		var mesh: Mesh = mi.mesh if mi != null else null
		if mesh != null:
			for i in mesh.get_surface_count():
				var mat := mesh.surface_get_material(i)
				var nm: String = mat.resource_name if mat != null else ""
				if _mats.has(nm):
					mesh.surface_set_material(i, _mats[nm])
		_plants.append(mesh)
	scene.free()


## Palms, trees and bushes: one MultiMesh per kind per tile, at the spots in the tile meta.
func _add_plants(tile: Node3D, meta: Dictionary) -> void:
	var by_kind := [[], [], []]
	for t in meta.get("trees", []):
		by_kind[int(t[3])].append(t)
	for k in 3:
		if by_kind[k].is_empty() or k >= _plants.size() or _plants[k] == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _plants[k]
		mm.instance_count = by_kind[k].size()
		for i in by_kind[k].size():
			var t: Array = by_kind[k][i]
			var r: float = t[4]
			var b := Basis(Vector3.UP, r * TAU * 7.0).scaled(Vector3.ONE * (0.75 + r * 0.55))
			mm.set_instance_transform(i, Transform3D(b, Vector3(t[0], t[1], t[2])))
		var mi := MultiMeshInstance3D.new()
		mi.name = ["Palms", "Trees", "Bushes"][k]
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = 120.0 if k == 2 else 520.0
		tile.add_child(mi)


func _add_signs_later(id: int, meta: Dictionary) -> void:
	var tile := instance_from_id(id) as Node3D
	if tile != null and tile.is_inside_tree():
		_add_signs(tile, meta)


func _add_signs(tile: Node3D, meta: Dictionary) -> void:
	_add_grass(tile, meta)
	_add_plants(tile, meta)
	# street furniture: queued in small batches (creating physics bodies isn't free)
	var items: Array = []
	for p in meta.get("poles", []):
		items.append(["poles", p])
	for p in meta.get("props", []):
		items.append(["props", p])
	for i in range(0, items.size(), PROPS_PER_FRAME):
		var chunk := {"poles": [], "props": []}
		for it in items.slice(i, i + PROPS_PER_FRAME):
			chunk[it[0]].append(it[1])
		_prop_queue.append([tile.get_instance_id(), chunk])
	# shop names on the signboards over shopfronts (made-up businesses)
	for s in meta.get("shops", []):
		var lab := Label3D.new()
		lab.text = String(s[5]).to_upper()
		lab.position = Vector3(s[0], s[1], s[2])
		lab.rotation.y = s[3]
		lab.font_size = 64
		lab.outline_size = 0
		lab.pixel_size = minf(0.006, float(s[4]) / maxf(1.0, lab.text.length() * 40.0))
		lab.modulate = Color("#f4f1e8") if int(s[6]) == 1 else Color("#1d2430")
		lab.double_sided = false
		lab.shaded = true
		lab.visibility_range_end = 90.0
		tile.add_child(lab)
	var green := _sign_mat()
	for s in meta.get("signs", []):
		# a break-away post: stands until a car knocks it over
		var post: RigidBody3D = PropsScript._body(true, 30.0)
		post.position = Vector3(s[0], s[1], s[2])      # a free street corner (build_osm_city.py)
		PropsScript._shape(post, Vector3(0.12, 3.2, 0.12), Vector3(0, 1.6, 0))
		tile.add_child(post)
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.05
		cyl.height = 3.2
		pole.mesh = cyl
		pole.position.y = 1.6
		pole.material_override = _mats["Props"]
		post.add_child(pole)
		var names: Array = s[3]
		for i in names.size():
			var plate := Node3D.new()
			plate.position.y = 3.05 - i * 0.3
			plate.rotation.y = i * PI / 2
			post.add_child(plate)
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.7, 0.26, 0.04)
			box.mesh = bm
			box.material_override = green
			plate.add_child(box)
			for f in [1.0, -1.0]:
				var lab := Label3D.new()
				lab.text = String(names[i]).to_upper()
				lab.font_size = 36
				lab.pixel_size = 0.0045
				lab.outline_size = 0
				lab.position.z = 0.025 * f
				lab.rotation.y = 0.0 if f > 0 else PI
				lab.visibility_range_end = 60.0
				plate.add_child(lab)


func _sign_mat() -> StandardMaterial3D:
	if not _mats.has("Sign"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#1f6b3a")
		_mats["Sign"] = m
	return _mats["Sign"]


## Sidewalk paths and parking spots from the detailed tiles within `radius` of p.
func nearby(p: Vector3, radius: float, field: String) -> Array:
	var out: Array = []
	for k in tiles:
		if tiles[k]["lod"] != 2 or _dist_from(k, p) > radius:
			continue
		for e in tiles[k]["meta"].get(field, []):
			out.append(e)
	return out


# ------------------------------------------------------------------ browser build
## Where the tile files are: next to the page (the export copies proto3d/city/hi and lo
## into <build>/city/). Set from the page's own address so it works on any host.
func _web_base() -> String:
	if web_base == "":
		var href = JavaScriptBridge.eval("new URL('city/', document.baseURI).href", true)
		web_base = String(href) if href != null else "city/"
	return web_base


func _fetch(job: Dictionary) -> void:
	var req := HTTPRequest.new()
	req.use_threads = false
	# Hosts like GitHub Pages send tiles gzip-compressed; the browser has already unpacked
	# them by the time Godot sees the body, so Godot must not try to gunzip it again
	# (that failed with RESULT_BODY_DECOMPRESS_FAILED and the city never loaded).
	req.accept_gzip = false
	req.timeout = 0.0              # no timeout: with slow first frames (shader compiles) a
	                               # finished download can wait seconds to be noticed
	add_child(req)
	var rel: String = String(job["path"]).trim_prefix(CITY_DIR)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			print("city tile %s: HTTP %d (result %d), will retry" % [rel, code, result])
			_web_failed[job["key"]] = int(_web_failed.get(job["key"], 0)) + 1
			_jobs.erase(job["key"])               # tried again on the next update (3 times)
			return
		web_bytes += body.size()
		if first_tile_s == 0.0:
			first_tile_s = Time.get_ticks_msec() / 1000.0
		job["bytes"] = body
		if job["lod"] == 2:
			_fetch_meta(job)
		else:
			_parse_queue.append(job))
	if first_request_s == 0.0:
		first_request_s = Time.get_ticks_msec() / 1000.0
	if req.request(_web_base() + rel) != OK:
		req.queue_free()
		_jobs.erase(job["key"])


## Browser build: a detailed tile's metadata (sidewalk paths, parking, trees, signs, shops)
## comes from <page>/city/meta/ next to the tile, not from the game package - that keeps
## 4.5 MB of JSON out of index.pck. A missing or failed file just means an emptier tile.
func _fetch_meta(job: Dictionary) -> void:
	var req := HTTPRequest.new()
	req.use_threads = false
	req.accept_gzip = false
	req.timeout = 0.0
	add_child(req)
	var rel: String = String(job["path"]).trim_prefix(CITY_DIR).replace("hi/", "meta/").replace(".glb", ".json")
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			web_bytes += body.size()
			job["meta_text"] = body.get_string_from_utf8()
		else:
			job["meta_text"] = ""
		_parse_queue.append(job))
	if req.request(_web_base() + rel) != OK:
		req.queue_free()
		job["meta_text"] = ""
		_parse_queue.append(job)
