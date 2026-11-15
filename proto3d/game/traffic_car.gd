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
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.85, 1.3, 4.3) if k != "keke" else Vector3(1.3, 1.6, 2.6)
	shape.shape = box
	shape.position.y = 0.85
	add_child(shape)
	var m := model_scene.instantiate() as Node3D
	m.rotation.y = PI / 2
	add_child(m)
	var lp: Array = graph.lane_point(edge, s, dir)
	_yaw = atan2(-(lp[1] as Vector3).x, -(lp[1] as Vector3).z)
	speed = graph.speed_limit(edge) * 0.8


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
	var accel := 3.5 if target > speed else 9.0
	speed = move_toward(speed, target, accel * delta)
	s += speed * delta
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
