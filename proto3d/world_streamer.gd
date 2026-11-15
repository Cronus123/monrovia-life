extends Node3D
## Streams the generated 1:1 Monrovia tiles (proto3d/city, from tools/build_osm_city.py)
## around a focus point (the player or the car being driven):
##   within HI_RADIUS: detailed tile with collision, street signs, sidewalk paths, parking
##   within LO_RADIUS: low-detail tile (no collision)
## Tiles are parsed on worker threads with GLTFDocument (they're kept as raw .glb files,
## not imported), collision shapes are built on the worker too, and only the final
## add_child happens on the main thread - a few per frame - so driving doesn't stutter.

signal tile_loaded(key: Vector2i, detailed: bool)

const CITY_DIR := "res://proto3d/city/"
const HI_RADIUS := 420.0
const LO_RADIUS := 1300.0
const MAX_JOBS := 3
const ATTACH_PER_FRAME := 2
const SHADER := preload("res://proto3d/city_surfaces.gdshader")

var manifest: Dictionary
var tile_size := 256.0
var focus := Vector3.ZERO
var tiles := {}                 # Vector2i -> {"lod": 0|1|2, "node": Node3D, "meta": Dictionary}
var _has_hi := {}
var _jobs := {}                 # Vector2i -> {"lod": int, "task": int, "result": Variant}
var _ready_queue: Array = []
var _mats := {}
var _timer := 0.0


func _ready() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(CITY_DIR + "manifest.json"))
	tile_size = manifest["tile_size"]
	for t in manifest["hi"]:
		_has_hi[Vector2i(t[0], t[1])] = true
	# Shared materials for every tile, by the material names the generator writes.
	var kinds := {"Terrain": 0, "Road": 1, "Sidewalk": 2, "Wall": 3, "Roof": 4, "Props": 5, "Rail": 5, "LoVC": 5}
	for n in kinds:
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("kind", kinds[n])
		_mats[n] = m
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.vertex_color_is_srgb = true
	paint.roughness = 0.6
	_mats["Paint"] = paint
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
func detailed_loaded(radius: float = HI_RADIUS) -> int:
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
	# finish loaded jobs (a few per frame)
	for _i in ATTACH_PER_FRAME:
		if _ready_queue.is_empty():
			break
		_attach(_ready_queue.pop_front())
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.15
	_update_wanted()


func _update_wanted() -> void:
	var want := {}
	var fk := tile_key(focus)
	var r := int(ceil(LO_RADIUS / tile_size)) + 1
	for t in manifest["tiles"]:
		var k := Vector2i(t[0], t[1])
		if absi(k.x - fk.x) > r or absi(k.y - fk.y) > r:
			continue
		var d := _dist(k)
		if d < HI_RADIUS and _has_hi.has(k):
			want[k] = 2
		elif d < LO_RADIUS:
			want[k] = 1
	# unload tiles no longer wanted
	for k in tiles.keys():
		if not want.has(k):
			_free_tile(k)
	# start loads, nearest first
	var todo: Array = []
	for k in want:
		var cur: int = tiles[k]["lod"] if tiles.has(k) else 0
		if cur != want[k] and not _jobs.has(k):
			todo.append(k)
	todo.sort_custom(func(a, b): return _dist(a) < _dist(b))
	for k in todo:
		if _jobs.size() >= MAX_JOBS:
			break
		_start_job(k, want[k])


func _start_job(k: Vector2i, lod: int) -> void:
	var path := CITY_DIR + ("hi/" if lod == 2 else "lo/") + "t_%d_%d.glb" % [k.x, k.y]
	var job := {"key": k, "lod": lod, "path": path, "result": null}
	_jobs[k] = job
	if DisplayServer.get_name() == "headless":
		# The headless dummy renderer isn't thread-safe for mesh/material creation
		# (the real renderers are), so tests load tiles on the main thread.
		_load_tile(job)
		return
	job["task"] = WorkerThreadPool.add_task(_load_tile.bind(job), false, "city tile")


## Worker thread: parse the glb, build collision shapes, assign shared materials.
func _load_tile(job: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(job["path"])
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
			elif String(m.name) in ["Lo", "Sidewalks-col", "Roads-col"]:
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var meta: Dictionary = {}
	if job["lod"] == 2:
		var mp: String = String(job["path"]).replace("/hi/", "/meta/").replace(".glb", ".json")
		if FileAccess.file_exists(mp):
			meta = JSON.parse_string(FileAccess.get_file_as_string(mp))
	job["result"] = {"node": node, "shapes": shapes, "meta": meta}
	call_deferred("_job_done", job)


func _job_done(job: Dictionary) -> void:
	if job.has("task"):
		WorkerThreadPool.wait_for_task_completion(job["task"])
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
	var still: int = 2 if (d < HI_RADIUS and _has_hi.has(k)) else (1 if d < LO_RADIUS else 0)
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
		_add_signs(node, res["meta"])
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


func _add_signs(tile: Node3D, meta: Dictionary) -> void:
	var green := _sign_mat()
	for s in meta.get("signs", []):
		var post := Node3D.new()
		post.position = Vector3(s[0] + 5.0, s[1], s[2] + 5.0)
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
