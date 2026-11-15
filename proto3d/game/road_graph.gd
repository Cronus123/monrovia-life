class_name RoadGraph
extends RefCounted
## The drivable street network of the 1:1 city (proto3d/city/roads_graph.json, made by
## tools/build_osm_city.py from OpenStreetMap). Edges are road pieces between junctions;
## vehicles drive on the right-hand lane. Used by traffic, police routing, the rival
## car and the HUD's street names.

var nodes: PackedVector3Array = PackedVector3Array()
var edges: Array[Dictionary] = []          # {a, b, pts: PackedVector3Array, cum: PackedFloat32Array, len, w, kind, name, oneway}
var links: Array = []                      # per node: Array of [edge index, dir (+1 from a, -1 from b)]
var _grid := {}                            # Vector2i(64 m cell) -> Array of [edge, point index]
const CELL := 64.0
const SPEED := {"trunk": 14.0, "primary": 13.0, "secondary": 12.0, "tertiary": 10.5, "trunk_link": 9.0,
	"primary_link": 9.0, "secondary_link": 8.0, "tertiary_link": 8.0, "residential": 8.5, "unclassified": 8.5,
	"living_street": 5.0, "road": 8.0, "motorway": 16.0}


func load_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for n in d["nodes"]:
		nodes.append(Vector3(n[0], n[1], n[2]))
	links.resize(nodes.size())
	for i in links.size():
		links[i] = []
	for e in d["edges"]:
		var pts := PackedVector3Array()
		for p in e["p"]:
			pts.append(Vector3(p[0], p[1], p[2]))
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
		var ei := edges.size()
		var oneway: int = int(e["o"])
		edges.append({"a": int(e["a"]), "b": int(e["b"]), "pts": pts, "cum": cum, "len": cum[cum.size() - 1],
			"w": float(e["w"]), "kind": String(e["k"]), "name": String(e["n"]), "oneway": oneway})
		if oneway >= 0:
			links[int(e["a"])].append([ei, 1])
		if oneway <= 0:
			links[int(e["b"])].append([ei, -1])
		for i in pts.size():
			var c := Vector2i(int(floor(pts[i].x / CELL)), int(floor(pts[i].z / CELL)))
			if not _grid.has(c):
				_grid[c] = []
			_grid[c].append([ei, i])
	return true


func speed_limit(e: int) -> float:
	return SPEED.get(edges[e]["kind"], 8.0)


## Position and travel direction at distance s along edge e when driving in direction dir,
## shifted to the right-hand lane.
func lane_point(e: int, s: float, dir: int) -> Array:
	var ed: Dictionary = edges[e]
	var L: float = ed["len"]
	var t := clampf(s, 0.0, L)
	var along := t if dir > 0 else L - t
	var pts: PackedVector3Array = ed["pts"]
	var cum: PackedFloat32Array = ed["cum"]
	var i := 1
	while i < cum.size() - 1 and cum[i] < along:
		i += 1
	var seg := maxf(cum[i] - cum[i - 1], 0.001)
	var f := clampf((along - cum[i - 1]) / seg, 0.0, 1.0)
	var p := pts[i - 1].lerp(pts[i], f)
	var fwd := (pts[i] - pts[i - 1])
	fwd.y = 0.0
	fwd = fwd.normalized() * dir
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var lane: float = minf(float(ed["w"]) * 0.25, 2.6) if ed["oneway"] == 0 else 0.0
	return [p + right * lane, fwd]


## Nearest point on the network: {edge, index, pos, dist}.
func nearest(p: Vector3, max_cells: int = 2) -> Dictionary:
	var c := Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))
	var best := {}
	var bd := INF
	for dx in range(-max_cells, max_cells + 1):
		for dz in range(-max_cells, max_cells + 1):
			for item in _grid.get(c + Vector2i(dx, dz), []):
				var q: Vector3 = edges[item[0]]["pts"][item[1]]
				var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
				if d < bd:
					bd = d
					best = {"edge": item[0], "index": item[1], "pos": q, "dist": sqrt(d)}
	return best


func street_name(p: Vector3) -> String:
	var n := nearest(p, 1)
	if n.is_empty() or n["dist"] > 25.0:
		return ""
	return String(edges[n["edge"]]["name"])


## Next edge to take at a junction (avoids U-turns unless it's a dead end).
func next_edge(node: int, from_edge: int, rng: RandomNumberGenerator) -> Array:
	var opts: Array = []
	for l in links[node]:
		if l[0] != from_edge:
			opts.append(l)
	if opts.is_empty():
		opts = links[node]
	if opts.is_empty():
		return []
	return opts[rng.randi() % opts.size()]


func end_node(e: int, dir: int) -> int:
	return edges[e]["b"] if dir > 0 else edges[e]["a"]


## A spawn spot on a road between min_d and max_d metres from p: [edge, dir, s] or [].
func random_spot(p: Vector3, min_d: float, max_d: float, rng: RandomNumberGenerator, tries: int = 24) -> Array:
	var cells := int(ceil(max_d / CELL))
	var c := Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))
	for _t in tries:
		var cc := c + Vector2i(rng.randi_range(-cells, cells), rng.randi_range(-cells, cells))
		var items: Array = _grid.get(cc, [])
		if items.is_empty():
			continue
		var item: Array = items[rng.randi() % items.size()]
		var ed: Dictionary = edges[item[0]]
		var q: Vector3 = ed["pts"][item[1]]
		var d := q.distance_to(p)
		if d < min_d or d > max_d or not SPEED.has(ed["kind"]):
			continue
		var dir := 1 if ed["oneway"] > 0 else (-1 if ed["oneway"] < 0 else (1 if rng.randf() < 0.5 else -1))
		var along: float = ed["cum"][item[1]]
		return [item[0], dir, along if dir > 0 else ed["len"] - along]
	return []


## Shortest route (A*) between junctions; returns a list of points to drive through.
func route(from_p: Vector3, to_p: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var s := nearest(from_p, 3)
	var g := nearest(to_p, 3)
	if s.is_empty() or g.is_empty():
		return out
	var start: int = edges[s["edge"]]["b"]
	var goal: int = edges[g["edge"]]["a"]
	var open := {start: true}
	var came := {}
	var gs := {start: 0.0}
	var fs := {start: nodes[start].distance_to(nodes[goal])}
	var guard := 0
	while not open.is_empty() and guard < 4000:
		guard += 1
		var cur := -1
		var cf := INF
		for k in open:
			if fs.get(k, INF) < cf:
				cf = fs[k]
				cur = k
		if cur == goal:
			break
		open.erase(cur)
		for l in links[cur]:
			var nb := end_node(l[0], l[1])
			var cost: float = gs[cur] + float(edges[l[0]]["len"])
			if cost < gs.get(nb, INF):
				came[nb] = [cur, l[0], l[1]]
				gs[nb] = cost
				fs[nb] = cost + nodes[nb].distance_to(nodes[goal])
				open[nb] = true
	if not came.has(goal) and goal != start:
		return out
	var chain: Array = []
	var n := goal
	while came.has(n):
		chain.push_front(came[n])
		n = came[n][0]
	for step in chain:
		var e: int = step[1]
		var dir: int = step[2]
		var L: float = edges[e]["len"]
		var d := 0.0
		while d < L:
			out.append(lane_point(e, d, dir)[0])
			d += 8.0
	out.append(to_p)
	return out
