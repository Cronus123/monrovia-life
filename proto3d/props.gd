extends RefCounted
## Street furniture as physics props, spawned per detailed tile from the tile meta:
##   pole   street light: stands still (frozen) until a car hits it hard, then topples
##   bin    wheelie bin, drum (oil drum), crate: light rigid bodies, asleep until hit
##   stall  market stall: canopy on posts (breaks away when hit), table and produce boxes
## Hitting one calls knock(velocity) (from car.gd); knocked lamps go dark
## (Prop.knocked_lamps, read by the world clock).

static var _meshes := {}
static var _mats := {}

const PROP_LAYER := 8


static func spawn(tile: Node3D, meta: Dictionary, glow: Material, plain: Material) -> int:
	_mats["glow"] = glow
	_mats["plain"] = plain
	var n := 0
	for p in meta.get("poles", []):
		tile.add_child(_pole(Vector3(p[0], p[1], p[2]), p[3]))
		n += 1
	for p in meta.get("props", []):
		var at := Vector3(p[0], p[1], p[2])
		match String(p[3]):
			"bin":
				tile.add_child(_loose("bin", at, p[4], 18.0))
			"drum":
				tile.add_child(_loose("drum", at, p[4], 30.0))
			"crate":
				tile.add_child(_loose("crate", at, p[4], 12.0))
			"stall":
				_stall(tile, at, p[4])
		n += 1
	return n


# ------------------------------------------------------------------ bodies
class Prop extends RigidBody3D:
	static var knocked_lamps: Array[Vector3] = []     # world_clock skips lights near these
	var breakaway := false          # frozen until knocked (poles, stall canopies)
	var lamp_at := Vector3.INF

	func _ready() -> void:
		add_to_group("props")
		collision_layer = 8
		collision_mask = 1 | 4 | 8
		if breakaway:
			freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			freeze = true
		else:
			can_sleep = true
			sleeping = true

	## Hit by something moving at `v` (m/s).
	func knock(v: Vector3) -> void:
		if breakaway:
			if v.length() < 4.0:
				return
			breakaway = false
			freeze = false
			if lamp_at != Vector3.INF:
				knocked_lamps.append(lamp_at)
				for c in find_children("Head", "MeshInstance3D", true, false):
					(c as MeshInstance3D).material_override = null
		sleeping = false
		var top := global_basis.y * 2.5
		apply_impulse(v * mass * 0.35 + Vector3.UP * mass * 0.8, top)


static func _body(breakaway: bool, mass: float) -> Prop:
	var b := Prop.new()
	b.breakaway = breakaway
	b.mass = mass
	return b


static func _shape(b: Node3D, size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = at
	b.add_child(cs)


static func _mesh_inst(b: Node3D, key: String, at: Vector3 = Vector3.ZERO, name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(key)
	mi.position = at
	if name != "":
		mi.name = name
	mi.visibility_range_end = 160.0
	b.add_child(mi)
	return mi


static func _pole(at: Vector3, yaw: float) -> Prop:
	var b := _body(true, 140.0)
	b.position = at
	b.rotation.y = yaw
	_shape(b, Vector3(0.2, 7.0, 0.2), Vector3(0, 3.5, 0))
	_mesh_inst(b, "pole")
	var head := _mesh_inst(b, "lamp_head", Vector3(0, 6.75, -1.6), "Head")
	head.material_override = _mats["glow"]
	b.lamp_at = at + Basis(Vector3.UP, yaw) * Vector3(0, 6.45, -1.6)
	return b


static func _loose(kind: String, at: Vector3, yaw: float, mass: float) -> Prop:
	var b := _body(false, mass)
	b.position = at
	b.rotation.y = yaw + (hash(at) % 100) * 0.03
	match kind:
		"bin":
			_shape(b, Vector3(0.6, 1.0, 0.7), Vector3(0, 0.5, 0))
		"drum":
			_shape(b, Vector3(0.58, 0.9, 0.58), Vector3(0, 0.45, 0))
		"crate":
			_shape(b, Vector3(0.6, 0.6, 0.6), Vector3(0, 0.3, 0))
	_mesh_inst(b, kind)
	return b


static func _stall(tile: Node3D, at: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var canopy := _body(true, 60.0)
	canopy.position = at
	canopy.rotation.y = yaw
	_shape(canopy, Vector3(2.4, 0.1, 1.8), Vector3(0, 2.3, 0))
	for x in [-1.1, 1.1]:
		for z in [-0.8, 0.8]:
			_shape(canopy, Vector3(0.08, 2.3, 0.08), Vector3(x, 1.15, z))
	_mesh_inst(canopy, "stall_canopy")
	tile.add_child(canopy)
	var table := _body(false, 25.0)
	table.position = at
	table.rotation.y = yaw
	_shape(table, Vector3(2.0, 0.85, 1.0), Vector3(0, 0.43, 0))
	_mesh_inst(table, "stall_table")
	tile.add_child(table)
	for i in 3:
		var box := _body(false, 4.0)
		box.position = at + basis * Vector3(-0.6 + i * 0.6, 0.9, 0.0)
		box.rotation.y = yaw + i * 0.4
		_shape(box, Vector3(0.45, 0.3, 0.4), Vector3(0, 0.15, 0))
		_mesh_inst(box, "produce_%d" % i)
		tile.add_child(box)


# ------------------------------------------------------------------ meshes (built once)
static func _mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match key:
		"pole":
			_box(st, Vector3(0, 3.5, 0), Vector3(0.18, 7.0, 0.18), Color("#5a5e64"))
			_box(st, Vector3(0, 6.9, -0.8), Vector3(0.1, 0.1, 1.7), Color("#5a5e64"))
			_box(st, Vector3(0, 0.3, 0), Vector3(0.32, 0.6, 0.32), Color("#4a4d52"))
		"lamp_head":
			_box(st, Vector3.ZERO, Vector3(0.5, 0.2, 0.5), Color("#fff4cc"))
		"bin":
			_box(st, Vector3(0, 0.48, 0), Vector3(0.58, 0.96, 0.68), Color("#2e6b3a"))
			_box(st, Vector3(0, 1.0, 0.02), Vector3(0.62, 0.06, 0.74), Color("#24552e"))
		"drum":
			_cyl(st, 0.29, 0.9, Color("#3a5a8c"))
		"crate":
			_box(st, Vector3(0, 0.3, 0), Vector3(0.6, 0.6, 0.6), Color("#a8834f"))
		"stall_canopy":
			for x in [-1.1, 1.1]:
				for z in [-0.8, 0.8]:
					_box(st, Vector3(x, 1.15, z), Vector3(0.07, 2.3, 0.07), Color("#6b4f33"))
			_box(st, Vector3(0, 2.32, 0), Vector3(2.5, 0.06, 1.95), Color("#8e969c"))
		"stall_table":
			_box(st, Vector3(0, 0.82, 0), Vector3(2.0, 0.06, 1.0), Color("#8a6a45"))
			for x in [-0.9, 0.9]:
				for z in [-0.42, 0.42]:
					_box(st, Vector3(x, 0.4, z), Vector3(0.06, 0.8, 0.06), Color("#6b4f33"))
		_:
			var cols := [Color("#d9472b"), Color("#f2b632"), Color("#4f9a3a")]   # peppers, bananas, greens
			_box(st, Vector3(0, 0.12, 0), Vector3(0.45, 0.24, 0.4), Color("#a8834f"))
			_box(st, Vector3(0, 0.27, 0), Vector3(0.4, 0.08, 0.35), cols[int(key.right(1)) % 3])
	st.generate_normals()
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.surface_set_material(0, mat)
	_meshes[key] = m
	return m


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := c + n * h
		var du := u * h
		var dv := v * h
		var q := [o - du - dv, o + du - dv, o + du + dv, o - du + dv]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.add_vertex(q[i])


static func _cyl(st: SurfaceTool, r: float, h: float, col: Color) -> void:
	var n := 10
	for i in n:
		var a0 := i * TAU / n
		var a1 := (i + 1) * TAU / n
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var up := Vector3(0, h, 0)
		for v in [p0, p1 + up, p1, p0, p0 + up, p1 + up]:
			st.set_color(col)
			st.add_vertex(v)
		for v in [up, p1 + up, p0 + up]:
			st.set_color(col.darkened(0.1))
			st.add_vertex(v)
