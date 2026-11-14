extends Node3D
## Dresses the district's streets from proto3d/data/roads.json: raised sidewalks with
## curbs, crosswalks and edge lines, street lights, utility poles and wires, street-name
## signs, parked cars and kekes, bins and market props, palms, flags and landmark signs.
## Also produces sidewalk paths for pedestrians. Run dress() after the district's
## collision exists (it measures road heights with raycasts).

const CarScript := preload("res://proto3d/car.gd")
const CONCRETE_SHADER := preload("res://proto3d/concrete.gdshader")
const KEKE := preload("res://proto3d/models/veh_keke.glb")
const CARS := {
	"taxi": preload("res://proto3d/models/veh_taxi.glb"),
	"car": preload("res://proto3d/models/veh_car.glb"),
	"suv": preload("res://proto3d/models/veh_suv.glb"),
}

const SIDEWALK_W := 2.4
const CURB_H := 0.15
const BOUND := Vector2(136.0, 72.0)
const PROP_LAYER := 8

# Landmarks in the district: name, centre (world x, z), roof height.
const LANDMARKS := [
	["DUCOR HOTEL", Vector2(-112, -4), 30.0], ["CENTENNIAL PAVILION", Vector2(-54, 16), 8.0],
	["WATERSIDE MARKET", Vector2(6, -28), 4.0], ["CAPITOL BUILDING", Vector2(78, -4), 14.0],
	["EXECUTIVE MANSION", Vector2(82, 26), 14.0], ["UNIVERSITY OF LIBERIA", Vector2(22, 18), 11.0],
	["POLICE HQ", Vector2(56, 20), 11.0],
]

var roads: Array = []           # {name, width, half, pts: PackedVector2Array}
var sidewalk_paths: Array = []  # PackedVector3Array per sidewalk run
var parked: Array = []          # cars placed at the curb
var rng := RandomNumberGenerator.new()
var _space: PhysicsDirectSpaceState3D
var _mats := {}


func dress() -> void:
	rng.seed = 2026
	_space = get_world_3d().direct_space_state
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://proto3d/data/roads.json"))
	for r in data["roads"]:
		var pts := PackedVector2Array()
		for p in r["points"]:
			pts.append(Vector2(p[0], p[1]))
		roads.append({"name": r["name"], "width": r["width"], "half": r["width"] / 2.0, "pts": pts})
	_build_sidewalks()
	_build_markings()
	_build_lamps_and_poles()
	_build_signs()
	_build_parking()
	_build_props()
	_build_landmark_touches()
	_build_palms()
	_limit_draw_distance(self)


## Small things stop drawing beyond 70 m (fog hides them anyway): fewer draw calls
## for old GPUs and the web build. Big shared meshes (sidewalks, MultiMeshes) stay.
func _limit_draw_distance(node: Node) -> void:
	for ch in node.get_children():
		if ch is MeshInstance3D and ch.name not in ["Sidewalks", "Curbs", "Markings", "Wires"]:
			(ch as MeshInstance3D).visibility_range_end = 70.0
		elif ch is Label3D:
			(ch as Label3D).visibility_range_end = 220.0 if (ch as Label3D).font_size >= 96 else 60.0
		_limit_draw_distance(ch)


# ------------------------------------------------------------------ helpers
func _mat(key: String, col: String, rough := 0.85, emit := false, metal := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col)
	m.roughness = rough
	m.metallic = metal
	if emit:
		m.emission_enabled = true
		m.emission = Color(col)
		m.emission_energy_multiplier = 1.2
	_mats[key] = m
	return m


func ground_y(p: Vector2, from := 40.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, from, p.y), Vector3(p.x, -5.0, p.y), 1)
	var hit := _space.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else -1.0


func in_bounds(p: Vector2, margin := 0.0) -> bool:
	return absf(p.x) < BOUND.x - margin and absf(p.y) < BOUND.y - margin


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Distance from p to the nearest road other than `skip`, minus that road's half width.
func clearance(p: Vector2, skip: int) -> float:
	var best := INF
	for i in roads.size():
		if i == skip:
			continue
		var pts: PackedVector2Array = roads[i]["pts"]
		for k in pts.size() - 1:
			best = minf(best, seg_dist(p, pts[k], pts[k + 1]) - roads[i]["half"])
	return best


## Points every `step` metres along a road: [pos, dir] pairs.
func samples(road: Dictionary, step: float) -> Array:
	var pts: PackedVector2Array = road["pts"]
	var out: Array = []
	var carry := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var L := a.distance_to(b)
		var d := (b - a) / maxf(L, 1e-6)
		var s := carry
		while s < L:
			out.append([a + d * s, d])
			s += step
		carry = s - L
	return out


func _static_body(pos: Vector3, shape: Shape3D, offset := Vector3.ZERO) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = offset
	b.add_child(cs)
	b.position = pos
	add_child(b)
	return b


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r_top: float, r_bot: float, h: float, segs := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


func _multimesh(mesh: Mesh, xforms: Array, mat: Material, shadows := true) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## A loose prop that cars can knock around.
func _prop(pos: Vector3, shape: Shape3D, mass_kg: float, visuals: Array, yaw := 0.0) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = PROP_LAYER
	rb.collision_mask = 1 | 4 | PROP_LAYER
	rb.mass = mass_kg
	rb.can_sleep = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = shape.get("size").y / 2.0 if shape is BoxShape3D else shape.get("height") / 2.0
	rb.add_child(cs)
	for v in visuals:   # [mesh, offset, material]
		var vm := _mesh(rb, v[0], v[1], v[2])
		vm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mass_kg < 30.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(rb)
	rb.position = pos
	rb.rotation.y = yaw
	rb.sleeping = true
	return rb


# ------------------------------------------------------------------ sidewalks
func _build_sidewalks() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curb := SurfaceTool.new()
	curb.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ri in roads.size():
		var road: Dictionary = roads[ri]
		var half: float = road["half"]
		var lift := ri * 0.003           # avoids z-fighting where two sidewalks overlap
		for side in [-1.0, 1.0]:
			var run: Array = []
			for s in samples(road, 2.0):
				var p: Vector2 = s[0]
				var d: Vector2 = s[1]
				var n: Vector2 = Vector2(-d.y, d.x) * side
				var inner: Vector2 = p + n * (half + 0.05)
				var outer: Vector2 = p + n * (half + SIDEWALK_W)
				var mid: Vector2 = p + n * (half + SIDEWALK_W * 0.5)
				var ok := in_bounds(mid, 2.0) and clearance(inner, ri) > 0.4 and clearance(outer, ri) > 0.4
				var ry := 0.0
				if ok:
					ry = ground_y(p)
					var gy := ground_y(mid)
					ok = ry > -0.3 and ry < 1.0 and gy > -0.3 and gy < ry + 0.5
				if ok:
					run.append([inner, outer, mid, ry + lift, n])
				else:
					_flush_run(run, st, curb)
					run = []
			_flush_run(run, st, curb)
	var mesh := ArrayMesh.new()
	st.generate_tangents()
	st.commit(mesh)
	var cm := curb.commit()
	var smat := ShaderMaterial.new()
	smat.shader = CONCRETE_SHADER
	var mi := _mesh(self, mesh, Vector3.ZERO, smat)
	mi.name = "Sidewalks"
	var ci := _mesh(self, cm, Vector3.ZERO, _mat("curb", "#d6d1c4", 0.8))
	ci.name = "Curbs"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.create_trimesh_collision()
	ci.create_trimesh_collision()


func _flush_run(run: Array, st: SurfaceTool, curb: SurfaceTool) -> void:
	if run.size() < 2:
		return
	var path := PackedVector3Array()
	for i in run.size():
		var e: Array = run[i]
		var ry: float = e[3]
		var m: Vector2 = e[2]
		path.append(Vector3(m.x, ry + CURB_H + 0.05, m.y))
		if i == run.size() - 1:
			break
		var f: Array = run[i + 1]
		var a_in: Vector2 = e[0]
		var a_out: Vector2 = e[1]
		var b_in: Vector2 = f[0]
		var b_out: Vector2 = f[1]
		var ya: float = e[3] + CURB_H
		var yb: float = f[3] + CURB_H
		var n: Vector2 = e[4]
		# top
		_quad(st, Vector3(a_in.x, ya, a_in.y), Vector3(b_in.x, yb, b_in.y), Vector3(b_out.x, yb, b_out.y), Vector3(a_out.x, ya, a_out.y), Vector3.UP)
		# curb face toward the road, and the back face
		var toward := Vector3(-n.x, 0, -n.y)
		_quad(curb, Vector3(a_in.x, ya - CURB_H - 0.05, a_in.y), Vector3(b_in.x, yb - CURB_H - 0.05, b_in.y), Vector3(b_in.x, yb, b_in.y), Vector3(a_in.x, ya, a_in.y), toward)
		_quad(st, Vector3(a_out.x, ya, a_out.y), Vector3(b_out.x, yb, b_out.y), Vector3(b_out.x, yb - 0.4, b_out.y), Vector3(a_out.x, ya - 0.4, a_out.y), -toward)
	if run.size() >= 5:
		sidewalk_paths.append(path)


## Adds a quad with the given facing; flips the winding if needed.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.dot(facing) > 0.0:     # Godot front faces wind clockwise: flip to keep them visible
		var t := b
		b = d
		d = t
	for v in [a, b, c, a, c, d]:
		st.set_normal(facing.normalized())
		st.set_uv(Vector2(v.x, v.z) * 0.25)
		st.add_vertex(v)


# ------------------------------------------------------------------ markings
func _build_markings() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# edge lines on the wide roads
	for ri in roads.size():
		var road: Dictionary = roads[ri]
		if road["width"] < 8.0:
			continue
		for side in [-1.0, 1.0]:
			for s in samples(road, 2.0):
				var p: Vector2 = s[0]
				var d: Vector2 = s[1]
				var n: Vector2 = Vector2(-d.y, d.x) * side
				var q: Vector2 = p + n * (road["half"] - 0.45)
				if not in_bounds(q) or clearance(q, ri) < 0.6:
					continue
				var y := ground_y(p) + 0.03
				if y > 1.0:
					continue
				_flat_strip(st, q, d, 2.0, 0.15, y)
	# zebra crossings next to junctions, across each road
	for j in _junctions():
		var ri: int = j[0]
		var road: Dictionary = roads[ri]
		for dist in [j[2] + 2.6, -(j[2] + 2.6)]:
			var at := _along(road, j[1], dist)
			if at.is_empty() or not in_bounds(at[0]):
				continue
			var p: Vector2 = at[0]
			var d: Vector2 = at[1]
			var y := ground_y(p) + 0.035
			if y > 1.0:
				continue
			var n: Vector2 = Vector2(-d.y, d.x)
			var w: float = road["half"] - 0.5
			var k := -w
			while k <= w:
				_flat_strip(st, p + n * k, d, 2.8, 0.5, y)
				k += 1.0
	var mesh := st.commit()
	var mi := _mesh(self, mesh, Vector3.ZERO, _mat("paint", "#f2f2ee", 0.6))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Markings"


func _flat_strip(st: SurfaceTool, c: Vector2, d: Vector2, length: float, width: float, y: float) -> void:
	var n: Vector2 = Vector2(-d.y, d.x) * (width / 2.0)
	var h := d * (length / 2.0)
	var a := c - h - n
	var b := c + h - n
	var cc := c + h + n
	var dd := c - h + n
	_quad(st, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(cc.x, y, cc.y), Vector3(dd.x, y, dd.y), Vector3.UP)


## Junctions: [road index, distance along that road, other road's half width, point].
func _junctions() -> Array:
	var out: Array = []
	for a in roads.size():
		var pa: PackedVector2Array = roads[a]["pts"]
		var along := 0.0
		for k in pa.size() - 1:
			var s0 := pa[k]
			var s1 := pa[k + 1]
			var L := s0.distance_to(s1)
			for b in roads.size():
				if b == a:
					continue
				var pb: PackedVector2Array = roads[b]["pts"]
				for m in pb.size() - 1:
					var hit = Geometry2D.segment_intersects_segment(s0, s1, pb[m], pb[m + 1])
					if hit == null:
						# T-junction: an end of road a touching road b
						for e in [[s0, 0.0], [s1, L]]:
							if (k == 0 and e[1] == 0.0) or (k == pa.size() - 2 and e[1] == L):
								if seg_dist(e[0], pb[m], pb[m + 1]) < roads[b]["half"] + 1.5:
									hit = e[0]
					if hit != null and in_bounds(hit):
						var dist := along + s0.distance_to(hit)
						var dup := false
						for o in out:
							if o[0] == a and absf(o[1] - dist) < 6.0:
								dup = true
						if not dup:
							out.append([a, dist, roads[b]["half"], hit, b])
			along += L
	return out


## Point and direction `offset` metres from distance `dist` along a road ([] if off the end).
func _along(road: Dictionary, dist: float, offset: float) -> Array:
	var target := dist + offset
	var pts: PackedVector2Array = road["pts"]
	var acc := 0.0
	for k in pts.size() - 1:
		var L := pts[k].distance_to(pts[k + 1])
		if target >= acc and target <= acc + L:
			var d := (pts[k + 1] - pts[k]) / maxf(L, 1e-6)
			return [pts[k] + d * (target - acc), d]
		acc += L
	return []


## Direction of a road at its segment nearest to p.
func _dir_near(road: Dictionary, p: Vector2) -> Vector2:
	var pts: PackedVector2Array = road["pts"]
	var best := INF
	var dir := Vector2.RIGHT
	for k in pts.size() - 1:
		var dd := seg_dist(p, pts[k], pts[k + 1])
		if dd < best:
			best = dd
			dir = (pts[k + 1] - pts[k]).normalized()
	return dir


# ------------------------------------------------------------------ lamps, poles, wires
func _build_lamps_and_poles() -> void:
	var poles: Array = []
	var arms: Array = []
	var heads: Array = []
	var upoles: Array = []
	var xarms: Array = []
	var wires := SurfaceTool.new()
	wires.begin(Mesh.PRIMITIVE_LINES)
	for ri in roads.size():
		var road: Dictionary = roads[ri]
		var half: float = road["half"]
		var wide: bool = road["width"] >= 8.0
		var count := 0
		var prev_tops: Array = []
		for s in samples(road, 2.0):
			count += 1
			var p: Vector2 = s[0]
			var d: Vector2 = s[1]
			var ry := ground_y(p)
			if ry > 1.0 or ry < -0.3:
				prev_tops = []
				continue
			# street lights, alternating sides, on the wide roads
			if wide and count % 13 == 0:
				var side := 1.0 if (count / 13) % 2 == 0 else -1.0
				var n: Vector2 = Vector2(-d.y, d.x) * side
				var q: Vector2 = p + n * (half + 0.55)
				if in_bounds(q, 2.0) and clearance(q, ri) > 0.8 and ground_y(q) < ry + 0.5:
					var y := ry + CURB_H
					var yaw := atan2(n.x, n.y) + PI       # arm reaches over the road
					poles.append(Transform3D(Basis.IDENTITY, Vector3(q.x, y + 3.4, q.y)))
					var arm_c: Vector2 = q - n * 0.8
					arms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(arm_c.x, y + 6.7, arm_c.y)))
					var hq: Vector2 = q - n * 1.55
					heads.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(hq.x, y + 6.6, hq.y)))
					_static_body(Vector3(q.x, y + 3.4, q.y), _cyl_shape(0.12, 6.8))
			# wooden utility poles on the other side, with three wires between them
			if count % 16 == 8:
				var n2: Vector2 = Vector2(-d.y, d.x) * -1.0
				var q2: Vector2 = p + n2 * (half + SIDEWALK_W - 0.35)
				if in_bounds(q2, 2.0) and clearance(q2, ri) > 0.8 and ground_y(q2) < ry + 0.5:
					var y2 := ry + CURB_H
					upoles.append(Transform3D(Basis(Vector3.UP, randf() * 0.2), Vector3(q2.x, y2 + 4.2, q2.y)))
					var yaw2 := atan2(d.x, d.y)
					xarms.append(Transform3D(Basis(Vector3.UP, yaw2 + PI / 2), Vector3(q2.x, y2 + 7.9, q2.y)))
					_static_body(Vector3(q2.x, y2 + 4.2, q2.y), _cyl_shape(0.14, 8.4))
					var tops: Array = []
					for o in [-0.75, 0.0, 0.75]:
						var w: Vector2 = q2 + d.rotated(PI / 2) * o
						tops.append(Vector3(w.x, y2 + 8.0 + (0.0 if o == 0.0 else -0.05), w.y))
					if prev_tops.size() == 3:
						for w in 3:
							_wire(wires, prev_tops[w], tops[w], 0.55)
					prev_tops = tops
				else:
					prev_tops = []
	var metal := _mat("lamp_metal", "#5b6168", 0.5, false, 0.6)
	_multimesh(_cyl(0.07, 0.12, 6.8), poles, metal)
	_multimesh(_box(Vector3(0.08, 0.08, 1.7)), arms, metal)
	_multimesh(_box(Vector3(0.35, 0.12, 0.6)), heads, _mat("lamp_head", "#fff4cc", 0.4, true), false)
	var wood := _mat("pole_wood", "#5e4630", 0.9)
	_multimesh(_cyl(0.11, 0.15, 8.4), upoles, wood)
	_multimesh(_box(Vector3(1.9, 0.1, 0.12)), xarms, wood, false)
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.albedo_color = Color("#1c1c1c")
	var wmi := _mesh(self, wires.commit(), Vector3.ZERO, wm)
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wmi.name = "Wires"


func _cyl_shape(r: float, h: float) -> CylinderShape3D:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	return c


func _wire(st: SurfaceTool, a: Vector3, b: Vector3, sag: float) -> void:
	var n := 10
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		st.add_vertex(prev)
		st.add_vertex(p)
		prev = p


# ------------------------------------------------------------------ signs
func _build_signs() -> void:
	var done: Array = []
	var done_keys: Array = []
	var green := _mat("sign_green", "#1f6b3a", 0.6)
	var metal := _mat("lamp_metal", "#5b6168", 0.5, false, 0.6)
	for j in _junctions():
		var a: Dictionary = roads[j[0]]
		var b: Dictionary = roads[j[4]]
		var hit: Vector2 = j[3]
		var key := "%d-%d" % [mini(j[0], j[4]), maxi(j[0], j[4])]
		var near_done := false
		for o in done:
			if (o as Vector2).distance_to(hit) < 10.0:
				near_done = true
		if near_done or key in done_keys:
			continue
		var at := _along(a, j[1], 0.0)
		if at.is_empty():
			continue
		var da: Vector2 = at[1]
		var na := Vector2(-da.y, da.x)
		var corner: Vector2 = hit + na * (a["half"] + 1.0) + da * (b["half"] + 1.0)
		if not in_bounds(corner, 3.0):
			continue
		var y := ground_y(corner)
		if y < -0.3 or y > 1.5:
			continue
		done.append(hit)
		done_keys.append(key)
		var post := Node3D.new()
		post.position = Vector3(corner.x, y, corner.y)
		add_child(post)
		_mesh(post, _cyl(0.04, 0.05, 3.2), Vector3(0, 1.6, 0), metal)
		_static_body(post.position + Vector3(0, 1.6, 0), _cyl_shape(0.06, 3.2))
		# one plate along each road
		var db := _dir_near(b, hit)
		var plates := [[a["name"], da, 3.05], [b["name"], db, 2.75]]
		for pl in plates:
			var dir: Vector2 = pl[1]
			var yaw := atan2(dir.x, dir.y) + PI / 2
			var plate := Node3D.new()
			plate.position = Vector3(0, pl[2], 0)
			plate.rotation.y = yaw
			post.add_child(plate)
			_mesh(plate, _box(Vector3(0.04, 0.26, 1.5)), Vector3.ZERO, green)
			for f in [1.0, -1.0]:
				var lab := Label3D.new()
				lab.text = String(pl[0]).to_upper()
				lab.font_size = 40
				lab.pixel_size = 0.0045
				lab.outline_size = 0
				lab.modulate = Color.WHITE
				lab.position = Vector3(0.025 * f, 0, 0)
				lab.rotation.y = PI / 2 * f
				plate.add_child(lab)


# ------------------------------------------------------------------ parking
func _build_parking() -> void:
	var junctions := _junctions()
	var kinds := ["taxi", "car", "suv", "car", "taxi"]
	var n_cars := 0
	var n_keke := 0
	for ri in roads.size():
		var road: Dictionary = roads[ri]
		if road["width"] > 9.0:
			continue
		var along := 0.0
		for s in samples(road, 9.0):
			along += 9.0
			var p: Vector2 = s[0]
			var d: Vector2 = s[1]
			if not in_bounds(p, 6.0) or rng.randf() > 0.42:
				continue
			var near_j := false
			for j in junctions:
				if (j[3] as Vector2).distance_to(p) < 13.0:
					near_j = true
			if near_j:
				continue
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var n: Vector2 = Vector2(-d.y, d.x) * side
			var q: Vector2 = p + n * (road["half"] - 1.25)
			if clearance(q, ri) < 1.5:
				continue
			var y := ground_y(q)
			if y < -0.3 or y > 1.0:
				continue
			var yaw := atan2(-d.x, -d.y) + (0.0 if side > 0 else PI)
			if n_keke < 7 and rng.randf() < 0.45:
				n_keke += 1
				var box := BoxShape3D.new()
				box.size = Vector3(1.3, 1.7, 2.5)
				var rb := _prop(Vector3(q.x, y + 0.05, q.y), box, 320.0, [], yaw)
				var m := KEKE.instantiate() as Node3D
				m.rotation.y = PI / 2
				rb.add_child(m)
			elif n_cars < 9:
				n_cars += 1
				var kind: String = kinds[rng.randi() % kinds.size()]
				var c = CarScript.new()
				c.model_scene = CARS[kind]
				c.name = "Parked_%s_%d" % [kind, n_cars]
				add_child(c)
				c.reset_to(Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, y + 0.35, q.y)))
				parked.append(c)


# ------------------------------------------------------------------ props
func _build_props() -> void:
	# bins along the sidewalks
	var bin_mesh := _cyl(0.32, 0.28, 0.95, 10)
	var bin_mat := _mat("bin", "#2f6b46", 0.7)
	var k := 0
	for path in sidewalk_paths:
		for i in range(3, path.size(), 14):
			k += 1
			var p: Vector3 = path[i]
			var c := CylinderShape3D.new()
			c.radius = 0.32
			c.height = 0.95
			_prop(p, c, 22.0, [[bin_mesh, Vector3(0, 0.475, 0), bin_mat]])
	# Waterside market: crates, baskets of produce, umbrellas, barrels
	var crate_mat := _mat("crate", "#8a6238", 0.9)
	var basket_mat := _mat("basket", "#b98c4a", 0.9)
	var produce := [_mat("p_red", "#c8282c", 0.6), _mat("p_orange", "#ef8a22", 0.6), _mat("p_green", "#4f9a2c", 0.6), _mat("p_yellow", "#f2c21a", 0.6)]
	var umbrella := [_mat("u1", "#c8173a"), _mat("u2", "#1aa39e"), _mat("u3", "#f5c518"), _mat("u4", "#2b5fb3")]
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(-20.0, 32.0), rng.randf_range(-37.0, -20.0))
		var y := ground_y(p)
		if y < 0.0 or y > 0.6:
			continue
		placed += 1
		var r := rng.randf()
		if r < 0.35:
			var b := BoxShape3D.new()
			b.size = Vector3(0.6, 0.45, 0.6)
			_prop(Vector3(p.x, y + 0.02, p.y), b, 12.0, [[_box(b.size), Vector3(0, 0.225, 0), crate_mat]], rng.randf() * TAU)
		elif r < 0.7:
			var c := CylinderShape3D.new()
			c.radius = 0.32
			c.height = 0.3
			var vis := [[_cyl(0.33, 0.26, 0.3, 10), Vector3(0, 0.15, 0), basket_mat]]
			var heap := SphereMesh.new()       # one mesh for the pile of produce
			heap.radius = 0.27
			heap.height = 0.24
			heap.radial_segments = 10
			heap.rings = 4
			vis.append([heap, Vector3(0, 0.3, 0), produce[rng.randi() % produce.size()]])
			_prop(Vector3(p.x, y + 0.02, p.y), c, 8.0, vis)
		elif r < 0.85:
			var c2 := CylinderShape3D.new()
			c2.radius = 0.3
			c2.height = 0.9
			_prop(Vector3(p.x, y + 0.02, p.y), c2, 40.0, [[_cyl(0.3, 0.3, 0.9, 10), Vector3(0, 0.45, 0), _mat("barrel", "#2b5fb3", 0.5, false, 0.4)]])
		else:
			var u := Node3D.new()
			u.position = Vector3(p.x, y, p.y)
			add_child(u)
			_mesh(u, _cyl(0.03, 0.03, 2.3), Vector3(0, 1.15, 0), _mat("lamp_metal", "#5b6168"))
			_mesh(u, _cyl(0.05, 1.3, 0.45, 12), Vector3(0, 2.3, 0), umbrella[rng.randi() % umbrella.size()])
			_static_body(u.position + Vector3(0, 1.15, 0), _cyl_shape(0.05, 2.3))
	# cones near the bridge approaches
	var cone_mat := _mat("cone", "#f26a1b", 0.6)
	for p in [Vector2(-21, -19), Vector2(-19, -19), Vector2(-17, -19), Vector2(27, -19), Vector2(29, -19)]:
		var y := ground_y(p)
		if y < 0.0 or y > 1.0:
			continue
		var c3 := CylinderShape3D.new()
		c3.radius = 0.2
		c3.height = 0.6
		_prop(Vector3(p.x, y + 0.02, p.y), c3, 3.0, [[_cyl(0.03, 0.2, 0.6, 8), Vector3(0, 0.3, 0), cone_mat]])


# ------------------------------------------------------------------ landmark touches
func _build_landmark_touches() -> void:
	for L in LANDMARKS:
		var c: Vector2 = L[1]
		var lab := Label3D.new()
		lab.text = L[0]
		lab.font_size = 96
		lab.pixel_size = 0.02
		lab.outline_size = 18
		lab.outline_modulate = Color(0.05, 0.08, 0.15)
		lab.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lab.position = Vector3(c.x, L[2] + 3.0, c.y)
		lab.modulate = Color("#ffe9a8")
		add_child(lab)
	# Liberian flags at the Capitol and the Executive Mansion
	var tex := _liberian_flag()
	for p in [Vector2(78, 8), Vector2(82, 12), Vector2(-54, 26)]:
		var y := ground_y(p)
		if y < -0.3:
			continue
		var base := Vector3(p.x, y, p.y)
		_mesh(self, _cyl(0.06, 0.09, 11.0), base + Vector3(0, 5.5, 0), _mat("flagpole", "#e8e8e8", 0.4, false, 0.5))
		_static_body(base + Vector3(0, 5.5, 0), _cyl_shape(0.1, 11.0))
		var q := QuadMesh.new()
		q.size = Vector2(2.85, 1.5)
		var fm := ShaderMaterial.new()
		fm.shader = preload("res://proto3d/flag.gdshader")
		fm.set_shader_parameter("flag", tex)
		_mesh(self, q, base + Vector3(1.48, 10.1, 0), fm)
	# market banner over the Waterside entrance
	var arch := Node3D.new()
	var ay := ground_y(Vector2(6, -21))
	arch.position = Vector3(6, maxf(ay, 0.1), -21)
	add_child(arch)
	var red := _mat("arch_red", "#c8173a", 0.7)
	for x in [-6.0, 6.0]:
		_mesh(arch, _cyl(0.12, 0.12, 5.0), Vector3(x, 2.5, 0), red)
		_static_body(arch.position + Vector3(x, 2.5, 0), _cyl_shape(0.14, 5.0))
	_mesh(arch, _box(Vector3(12.4, 1.1, 0.12)), Vector3(0, 4.6, 0), _mat("banner", "#f5c518", 0.7))
	for f in [1.0, -1.0]:
		var bl := Label3D.new()
		bl.text = "WATERSIDE MARKET"
		bl.font_size = 64
		bl.pixel_size = 0.012
		bl.modulate = Color("#14213d")
		bl.outline_size = 0
		bl.position = Vector3(0, 4.6, 0.07 * f)
		bl.rotation.y = 0.0 if f > 0 else PI
		arch.add_child(bl)


func _liberian_flag() -> ImageTexture:
	var w := 190
	var h := 100
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var red := Color("#bf0a30")
	var blue := Color("#002868")
	for y in h:
		var stripe := int(float(y) / h * 11.0)
		for x in w:
			img.set_pixel(x, y, red if stripe % 2 == 0 else Color.WHITE)
	var cs := int(h * 5.0 / 11.0)
	for y in cs:
		for x in cs:
			img.set_pixel(x, y, blue)
	# five-pointed white star in the canton
	var c := Vector2(cs / 2.0, cs / 2.0)
	var pts := PackedVector2Array()
	for i in 10:
		var r := cs * (0.36 if i % 2 == 0 else 0.15)
		var a := -PI / 2 + i * PI / 5
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	for y in cs:
		for x in cs:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ palms
func _build_palms() -> void:
	var trunks: Array = []
	var fronds: Array = []
	var coconut: Array = []
	for ri in roads.size():
		var road: Dictionary = roads[ri]
		if road["name"] != "UN Drive" and road["name"] != "Broad Street":
			continue
		var i := 0
		for s in samples(road, 2.0):
			i += 1
			if i % 11 != 5:
				continue
			var p: Vector2 = s[0]
			var d: Vector2 = s[1]
			var side := 1.0 if (i / 11) % 2 == 0 else -1.0
			var q: Vector2 = p + Vector2(-d.y, d.x) * side * (road["half"] + SIDEWALK_W - 0.6)
			if not in_bounds(q, 3.0) or clearance(q, ri) < 1.0:
				continue
			var y := ground_y(q)
			var ry := ground_y(p)
			if y < -0.3 or y > ry + 0.5:
				continue
			var h := rng.randf_range(6.5, 9.0)
			var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
			var tb := Basis.from_euler(lean)
			trunks.append(Transform3D(tb.scaled(Vector3(1, h, 1)), Vector3(q.x, y + h / 2.0, q.y)))
			var top := Vector3(q.x, y, q.y) + tb * Vector3(0, h, 0)
			_static_body(Vector3(q.x, y + h / 2.0, q.y), _cyl_shape(0.22, h))
			for f in 8:
				var a := f * TAU / 8.0 + rng.randf() * 0.3
				var fb := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -0.45)
				fronds.append(Transform3D(fb, top + fb * Vector3(0, 0, -1.6)))
			for cn in 3:
				coconut.append(Transform3D(Basis.IDENTITY, top + Vector3(cos(cn * 2.1) * 0.25, -0.3, sin(cn * 2.1) * 0.25)))
	_multimesh(_cyl(0.16, 0.24, 1.0, 7), trunks, _mat("palm_trunk", "#7a5a3a", 0.9))
	_multimesh(_box(Vector3(0.7, 0.05, 3.3)), fronds, _mat("palm_leaf", "#3f8a2e", 0.8))
	var nut := SphereMesh.new()
	nut.radius = 0.13
	nut.height = 0.26
	nut.radial_segments = 6
	nut.rings = 3
	_multimesh(nut, coconut, _mat("coconut", "#4d3a1f", 0.8), false)
