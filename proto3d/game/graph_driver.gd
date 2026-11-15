class_name GraphDriver
extends RefCounted
## AI driver for a physics car (car.gd `controller`). Follows a route of points along the
## road graph and steers toward a look-ahead point. Modes:
##   "pursue": route to the target node, recomputed every few seconds; drives straight at
##             it when close (police)
##   "wander": drives to random places around the city (the rival car)
##   "hold":   brakes and waits (police that stopped to get out)
## Gets unstuck by reversing for a moment.

var graph: RoadGraph
var mode := "wander"
var target: Node3D = null
var top_speed := 18.0
var rng := RandomNumberGenerator.new()
var _route := PackedVector3Array()
var _i := 0
var _replan := 0.0
var _stuck := 0.0
var _reverse := 0.0
var _rev_steer := 1.0
var _last := Time.get_ticks_msec()


func _init(g: RoadGraph, m: String, t: Node3D = null, top: float = 18.0, seed_value: int = 1) -> void:
	graph = g
	mode = m
	target = t
	top_speed = top
	rng.seed = seed_value


func drive_input(car: RigidBody3D) -> Vector3:
	var now := Time.get_ticks_msec()
	var dt := clampf((now - _last) / 1000.0, 0.0, 0.1)
	_last = now
	if mode == "hold":
		return Vector3(0, 0, 1)
	var pos := car.global_position
	var aim := pos
	var direct := false
	if mode == "pursue" and target != null and is_instance_valid(target):
		var d := pos.distance_to(target.global_position)
		direct = d < 35.0
		_replan -= dt
		if not direct and (_replan <= 0.0 or _i >= _route.size()):
			_replan = 2.5
			_route = graph.route(pos, target.global_position)
			_i = 0
		if direct:
			aim = target.global_position
	elif _i >= _route.size():
		var spot := graph.random_spot(pos, 250.0, 700.0, rng)
		if not spot.is_empty():
			_route = graph.route(pos, graph.lane_point(spot[0], spot[2], spot[1])[0])
			_i = 0
	if not direct:
		while _i < _route.size() and _route[_i].distance_to(pos) < 9.0:
			_i += 1
		if _i < _route.size():
			aim = _route[_i]
			if _i + 1 < _route.size():
				aim = aim.lerp(_route[_i + 1], 0.5)
		elif target != null and is_instance_valid(target):
			aim = target.global_position
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	var to := aim - pos
	to.y = 0.0
	if to.length() < 0.5:
		return Vector3(0, 0, 1)
	var ang := atan2(fwd.normalized().cross(to.normalized()).y, fwd.normalized().dot(to.normalized()))
	var steer := clampf(ang * 2.2, -1.0, 1.0)
	var want := top_speed * (0.45 if absf(ang) > 0.9 else 1.0)
	if direct:
		want = minf(want, 4.0 + to.length() * 0.6)
	var spd: float = car.speed
	var throttle := 1.0 if spd < want else -0.4
	# unstick: reverse briefly with opposite lock
	if _reverse > 0.0:
		_reverse -= dt
		return Vector3(-1.0, -_rev_steer, 0)
	if absf(spd) < 1.0 and throttle > 0.0:
		_stuck += dt
		if _stuck > 1.4:
			_stuck = 0.0
			_reverse = 1.0
			_rev_steer = signf(steer) if steer != 0.0 else 1.0
	else:
		_stuck = maxf(0.0, _stuck - dt)
	return Vector3(throttle, steer, 0)
