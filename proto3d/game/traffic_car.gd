class_name TrafficCar
extends AnimatableBody3D
## A background traffic vehicle: kinematic (cheap and predictable) and driven along the
## right-hand lane of the road graph. Solid to the player and to physics cars. When the
## player takes it or crashes into it hard, traffic.gd swaps it for a physics car.

var kind := "car"
var graph: RoadGraph
var traffic                       # traffic.gd (obstacle checks)
var edge := 0
var dir := 1
var s := 0.0
var speed := 0.0
var hits := 0                     # bullets taken (driver flees after a few)
var abandoned := false
var rng := RandomNumberGenerator.new()
var _yaw := 0.0
var _honk_t := 0.0
var paint: Variant = null
var _pickup_t := 0.0              # keke: pulled over for a passenger (seconds left)
var _pickup_check := 0.0
var _wheels: Array = []           # [MeshInstance3D, rest Transform3D]
var _spin := 0.0
const Look := preload("res://proto3d/vehicle_look.gd")


func setup(g: RoadGraph, spot: Array, k: String, model_scene: PackedScene, seed_value: int) -> void:
	graph = g
	edge = spot[0]
	dir = spot[1]
	s = spot[2]
	kind = k
	rng.seed = seed_value
	collision_layer = 4
	collision_mask = 0
	sync_to_physics = false
	var m := model_scene.instantiate() as Node3D
	m.rotation.y = PI / 2
	add_child(m)
	paint = Look.random_paint(k, rng)
	var parts: Dictionary = Look.style(m, paint, false)
	for w in parts["wheels"]:
		_wheels.append([w, (w as Node3D).transform])
	# collision box from the model's size
	var aabb := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = _rel(mi as Node3D) * (mi as MeshInstance3D).get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x * 0.95, minf(aabb.size.y, 2.6) * 0.8, aabb.size.z * 0.95) if not first else Vector3(1.85, 1.3, 4.3)
	shape.shape = box
	shape.position.y = 0.85 if first else aabb.get_center().y
	add_child(shape)
	var lp: Array = graph.lane_point(edge, s, dir)
	_yaw = atan2(-(lp[1] as Vector3).x, -(lp[1] as Vector3).z)
	speed = graph.speed_limit(edge) * 0.8


## Transform of a model part relative to this car (works before entering the tree).
func _rel(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != self:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func place() -> void:
	var lp: Array = graph.lane_point(edge, s, dir)
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), lp[0])


func limit() -> float:
	var v := graph.speed_limit(edge)
	return v * (0.75 if kind in ["keke", "truck"] else 1.0)


func _physics_process(delta: float) -> void:
	if graph == null:
		return
	var lp: Array = graph.lane_point(edge, s, dir)
	var pos: Vector3 = lp[0]
	var fwd: Vector3 = lp[1]
	var target := 0.0 if abandoned else limit()
	if not abandoned:
		var look := clampf(4.0 + speed * 0.9, 5.0, 16.0)
		var ahead: Vector3 = graph.lane_point(edge, s + look, dir)[0]
		var near: float = traffic.clearance(self, pos, ahead) if traffic != null else INF
		if near < 3.0:
			target = 0.0
		elif near < 9.0:
			target = minf(target, near - 2.5)
	# kekes pull over now and then where someone is standing at the roadside
	if kind == "keke" and not abandoned:
		_pickup_check -= delta
		if _pickup_t > 0.0:
			_pickup_t -= delta
			target = 0.0
		elif _pickup_check <= 0.0:
			_pickup_check = 2.0
			if rng.randf() < 0.25 and traffic != null and traffic.main != null:
				for ped in traffic.main.peds:
					if is_instance_valid(ped) and not ped.is_down() and ped.global_position.distance_to(pos) < 5.0:
						_pickup_t = rng.randf_range(2.5, 4.5)
						break
	# traffic lights and right of way at the junction ahead: stop at the line (7 m before)
	var remaining: float = float(graph.edges[edge]["len"]) - s
	if not abandoned and remaining < 26.0 and traffic != null and traffic.signals != null:
		if traffic.signals.must_stop(graph.end_node(edge, dir), edge, remaining, self):
			target = minf(target, maxf(0.0, (remaining - 7.0) * 0.7))
	# honk at a player who stands or parks in the way
	if not abandoned and traffic != null and speed < 0.5 and target < 0.5 and traffic.player_blocking(pos, fwd):
		_honk_t += delta
		if _honk_t > 2.5:
			_honk_t = -6.0
			traffic.honk(self)
	else:
		_honk_t = maxf(0.0, _honk_t - delta) if _honk_t >= 0.0 else _honk_t + delta
	var accel := 3.5 if target > speed else 9.0
	speed = move_toward(speed, target, accel * delta)
	s += speed * delta
	if not _wheels.is_empty():
		_spin = fmod(_spin + speed / 0.36 * delta, TAU)
		for w in _wheels:
			var rest: Transform3D = w[1]
			(w[0] as Node3D).transform = Transform3D(Basis(Vector3(0, 0, 1), -_spin) * rest.basis, rest.origin)
	var L: float = graph.edges[edge]["len"]
	if s > L:
		var node := graph.end_node(edge, dir)
		var nxt: Array = graph.next_edge(node, edge, rng)
		if nxt.is_empty():
			dir = -dir
			s = 0.0
		else:
			s -= L
			edge = nxt[0]
			dir = nxt[1]
	var want := atan2(-fwd.x, -fwd.z)
	_yaw = lerp_angle(_yaw, want, clampf(delta * 6.0, 0.0, 1.0))
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), pos)


func velocity() -> Vector3:
	return -global_basis.z * speed
