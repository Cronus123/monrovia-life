class_name GraphDriver
extends RefCounted
## AI driver for a physics car (car.gd `controller`). Follows a route of points along the
## road graph and steers toward a look-ahead point, slowing for sharp corners. Modes:
##   "pursue": route to the target, recomputed every few seconds; drives straight at it
##             when close (police)
##   "wander": drives to random places around the city (the rival car)
##   "hold":   brakes and waits (police that stopped to get out)
## Getting unstuck: reverse with opposite lock, then re-plan from where the car is now.
## Stuck again and again while well away from the player: put back on the road.

var graph: RoadGraph
var mode := "wander"
var target: Node3D = null
var top_speed := 18.0
var viewer: Node3D = null         # the player, to know when a quiet reset is safe
var rng := RandomNumberGenerator.new()
var _route := PackedVector3Array()
var _i := 0
var _replan := 0.0
var _stuck := 0.0
var _reverse := 0.0
var _rev_steer := 1.0
var _stuck_times: Array[float] = []
var _last := Time.get_ticks_msec()


func _init(g: RoadGraph, m: String, t: Node3D = null, top: float = 18.0, seed_value: int = 1) -> void:
	graph = g
	mode = m
	target = t
	top_speed = top
	rng.seed = seed_value


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func drive_input(car: RigidBody3D) -> Vector3:
	var now := Time.get_ticks_msec()
	var dt := clampf((now - _last) / 1000.0, 0.0, 0.1)
	_last = now
	if mode == "hold":
		return Vector3(0, 0, 1)
	if _reverse > 0.0:
		_reverse -= dt
		if _reverse <= 0.0:
			_replan = 0.0                # re-plan from the new position
			_route = PackedVector3Array()
		return Vector3(-1.0, -_rev_steer, 0)
	var pos := car.global_position
	var aim := pos
	var direct := false
	var target_ok := target != null and is_instance_valid(target)
	if mode == "pursue" and target_ok:
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
	var corner := 0.0
	if not direct:
		# skip waypoints already passed (also after being pushed off the route)
		var best := _i
		var bd := INF
		for k in range(_i, mini(_i + 6, _route.size())):
			var dk := _route[k].distance_to(pos)
			if dk < bd:
				bd = dk
				best = k
		_i = best
		while _i < _route.size() and _route[_i].distance_to(pos) < 9.0:
			_i += 1
		if _i < _route.size():
			aim = _route[_i]
			if _i + 1 < _route.size():
				aim = aim.lerp(_route[_i + 1], 0.5)
			if _i + 3 < _route.size():
				var a := _route[_i + 1] - _route[_i]
				var b := _route[_i + 3] - _route[_i + 1]
				a.y = 0.0
				b.y = 0.0
				if a.length() > 0.1 and b.length() > 0.1:
					corner = a.normalized().angle_to(b.normalized())
		elif target_ok:
			aim = target.global_position
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	var to := aim - pos
	to.y = 0.0
	if to.length() < 0.5:
		return Vector3(0, 0, 1)
	var ang := atan2(fwd.normalized().cross(to.normalized()).y, fwd.normalized().dot(to.normalized()))
	var steer := clampf(ang * 2.2, -1.0, 1.0)
	var want := top_speed
	if absf(ang) > 0.9:
		want *= 0.45
	if corner > 0.6:
		want = minf(want, lerpf(14.0, 7.0, clampf((corner - 0.6) / 1.0, 0.0, 1.0)))
	if direct:
		want = minf(want, 4.0 + to.length() * 0.6)
	var spd: float = car.speed
	var throttle := 1.0 if spd < want else -0.4
	if absf(spd) < 1.0 and throttle > 0.0:
		_stuck += dt
		if _stuck > 1.2:
			_on_stuck(car, steer)
	else:
		_stuck = maxf(0.0, _stuck - dt)
	return Vector3(throttle, steer, 0)


func _on_stuck(car: RigidBody3D, steer: float) -> void:
	_stuck = 0.0
	_reverse = 1.2
	_rev_steer = signf(steer) if steer != 0.0 else 1.0
	var now := _now()
	_stuck_times.append(now)
	while not _stuck_times.is_empty() and now - _stuck_times[0] > 15.0:
		_stuck_times.pop_front()
	# stuck three times in 15 s and nobody's watching: put it back on the road
	var far := viewer == null or not is_instance_valid(viewer) or viewer.global_position.distance_to(car.global_position) > 60.0
	if _stuck_times.size() >= 3 and far:
		_stuck_times.clear()
		_reverse = 0.0
		var n := graph.nearest(car.global_position, 3)
		if not n.is_empty():
			var lp: Array = graph.lane_point(n["edge"], float(graph.edges[n["edge"]]["cum"][n["index"]]), 1)
			var fwd: Vector3 = lp[1]
			if target != null and is_instance_valid(target) and fwd.dot(target.global_position - (lp[0] as Vector3)) < 0.0:
				fwd = -fwd
			car.reset_to(Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), (lp[0] as Vector3) + Vector3(0, 0.6, 0)))
		_route = PackedVector3Array()
		_replan = 0.0
