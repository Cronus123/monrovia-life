class_name TrafficSignals
extends Node3D
## Traffic lights and right of way.
## Junctions of three or more roads where a trunk, primary or secondary road meets get
## traffic lights: the approaches are split into two directions that take turns
## (green 10 s, yellow 3 s, then red while the other direction goes). Signal heads are
## drawn only near the player. Other junctions use right of way: cars on the smaller road
## wait while a car is moving through the junction.

const MAJOR := ["trunk", "primary", "secondary", "trunk_link", "primary_link", "secondary_link"]
const RANK := {"trunk": 8, "primary": 7, "secondary": 6, "tertiary": 5, "trunk_link": 4, "primary_link": 4,
	"secondary_link": 4, "tertiary_link": 4, "unclassified": 3, "residential": 3, "living_street": 2, "road": 2}
const CYCLE := 26.0
const SHOW_RADIUS := 260.0

var graph: RoadGraph
var traffic                       # traffic.gd
var signals := {}                 # node -> {axis: {edge: 0|1}, offset, approaches: [[edge, dir_in, width]]}
var junctions := {}               # node -> highest road rank there (right-of-way junctions)
var focus := Vector3.ZERO
var _built := {}                  # node -> {root, mats: [[r, y, g] per axis]}
var _t := 0.0
var _timer := 0.0


func setup(g: RoadGraph, t) -> void:
	graph = g
	traffic = t
	var touching := {}
	for ei in graph.edges.size():
		var e: Dictionary = graph.edges[ei]
		for end in [e["a"], e["b"]]:
			if not touching.has(end):
				touching[end] = []
			touching[end].append(ei)
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	for node in touching:
		var list: Array = touching[node]
		if list.size() < 3:
			continue
		var major := false
		var top := 0
		for ei in list:
			var k: String = graph.edges[ei]["kind"]
			major = major or k in MAJOR
			top = maxi(top, RANK.get(k, 1))
		if not major:
			junctions[node] = top
			continue
		var approaches: Array = []
		var axis := {}
		var ref := Vector3.ZERO
		for ei in list:
			var pts: PackedVector3Array = graph.edges[ei]["pts"]
			var dir_in: Vector3
			if graph.edges[ei]["a"] == node:
				dir_in = pts[0] - pts[1]
			else:
				dir_in = pts[pts.size() - 1] - pts[pts.size() - 2]
			dir_in.y = 0.0
			dir_in = dir_in.normalized()
			if ref == Vector3.ZERO:
				ref = dir_in
			axis[ei] = 0 if absf(dir_in.dot(ref)) > 0.6 else 1
			approaches.append([ei, dir_in, float(graph.edges[ei]["w"])])
		signals[node] = {"axis": axis, "offset": rng.randf() * CYCLE, "approaches": approaches}


## 0 green, 1 yellow, 2 red for traffic arriving at `node` along `edge`.
func light(node: int, edge: int) -> int:
	var s: Dictionary = signals[node]
	var t := fmod(_t + float(s["offset"]), CYCLE)
	var a: int = s["axis"].get(edge, 0)
	if a == 0:
		return 0 if t < 10.0 else (1 if t < 13.0 else 2)
	return 2 if t < 13.0 else (0 if t < 23.0 else 1)


## Should a traffic car on `edge` stop before `node`, `remaining` metres away?
func must_stop(node: int, edge: int, remaining: float, me) -> bool:
	if signals.has(node):
		var l := light(node, edge)
		return l == 2 or (l == 1 and remaining > 9.0)
	if junctions.has(node):
		var mine: int = RANK.get(graph.edges[edge]["kind"], 1)
		if mine >= int(junctions[node]):
			return false               # we're on the main road: we have right of way
		var at: Vector3 = graph.nodes[node]
		for c in traffic.cars:
			if c != me and c.edge != edge and c.speed > 1.0 and c.global_position.distance_to(at) < 13.0:
				return true
	return false


func _process(delta: float) -> void:
	_t += delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	for node in signals:
		var d := (graph.nodes[node] as Vector3).distance_to(focus)
		if d < SHOW_RADIUS and not _built.has(node):
			_build(node)
		elif d > SHOW_RADIUS + 60.0 and _built.has(node):
			(_built[node]["root"] as Node).queue_free()
			_built.erase(node)
	for node in _built:
		var mats: Array = _built[node]["mats"]
		for ax in 2:
			var edge := -1
			for e in signals[node]["axis"]:
				if signals[node]["axis"][e] == ax:
					edge = e
					break
			if edge < 0:
				continue
			var l := light(node, edge)
			for k in 3:       # red, yellow, green
				var on := (k == 0 and l == 2) or (k == 1 and l == 1) or (k == 2 and l == 0)
				(mats[ax][k] as StandardMaterial3D).emission_energy_multiplier = 4.0 if on else 0.0
				(mats[ax][k] as StandardMaterial3D).albedo_color.a = 1.0


func _lamp_mats() -> Array:
	var out: Array = []
	for col in [Color("#ff2a2a"), Color("#ffc21a"), Color("#2aff6a")]:
		var m := StandardMaterial3D.new()
		m.albedo_color = col.darkened(0.7)
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.0
		out.append(m)
	return out


func _build(node: int) -> void:
	var root := Node3D.new()
	add_child(root)
	var mats := [_lamp_mats(), _lamp_mats()]
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color("#2b2f35")
	var at: Vector3 = graph.nodes[node]
	for ap in signals[node]["approaches"]:
		var dir_in: Vector3 = ap[1]
		var w: float = ap[2]
		var right := Vector3(-dir_in.z, 0, dir_in.x)
		var base := at - dir_in * (w * 0.5 + 2.0) + right * (w * 0.5 + 1.2)
		var post := Node3D.new()
		root.add_child(post)
		post.global_position = base
		post.rotation.y = atan2(dir_in.x, dir_in.z)      # face the oncoming traffic
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.09
		cyl.height = 4.2
		cyl.radial_segments = 8
		pole.mesh = cyl
		pole.material_override = pole_mat
		pole.position.y = 2.1
		post.add_child(pole)
		var head := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.36, 1.0, 0.3)
		head.mesh = hb
		head.material_override = pole_mat
		head.position = Vector3(0, 3.9, 0)
		post.add_child(head)
		var ax: int = signals[node]["axis"].get(ap[0], 0)
		for k in 3:
			var lamp := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.11
			sm.height = 0.22
			sm.radial_segments = 8
			sm.rings = 4
			lamp.mesh = sm
			lamp.material_override = mats[ax][k]
			lamp.position = Vector3(0, 4.25 - k * 0.32, 0.16)
			post.add_child(lamp)
	_built[node] = {"root": root, "mats": mats}
