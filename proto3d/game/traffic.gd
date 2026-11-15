class_name Traffic
extends Node3D
## Keeps the streets around the player busy: spawns traffic on the road graph 90-260 m
## away (taxis, kekes, cars, SUVs, trucks, the odd police patrol), despawns it beyond
## 330 m, and turns a traffic car into a full physics car when the player takes it or
## crashes into it.

signal car_taken(car: RigidBody3D, from_kind: String, was_police: bool)

var max_cars := 16               # Settings: graphics quality
const SPAWN_MIN := 90.0
const SPAWN_MAX := 260.0
const DESPAWN := 330.0
const KINDS := [["taxi", 30], ["keke", 22], ["car", 18], ["suv", 12], ["truck", 8], ["police", 6], ["van", 4]]
const TrafficCarScript := preload("res://proto3d/game/traffic_car.gd")

var graph: RoadGraph
var signals: TrafficSignals
var main                         # main_city.gd: player, car, peds, spawn_car()
var models := {}
var cars: Array[TrafficCar] = []
var rng := RandomNumberGenerator.new()
var _spawn_t := 0.0
var _obstacles: PackedVector3Array = PackedVector3Array()
var _pool: Array = []


func setup(g: RoadGraph, main_node, vehicle_models: Dictionary) -> void:
	graph = g
	main = main_node
	models = vehicle_models
	rng.seed = 4242
	for k in KINDS:
		for _i in k[1]:
			_pool.append(k[0])


func focus() -> Vector3:
	return main.car.global_position if main.car != null else main.player.global_position


func _physics_process(delta: float) -> void:
	if graph == null or not main.ready_done:
		return
	# things traffic must not drive into this frame
	_obstacles.clear()
	if main.player.active:
		_obstacles.append(main.player.global_position)
	for c in main.cars:
		_obstacles.append(c.global_position)
	for p in main.peds:
		_obstacles.append(p.global_position)
	var f := focus()
	for c in cars.duplicate():
		if c.global_position.distance_to(f) > DESPAWN:
			_remove(c)
	_spawn_t -= delta
	if _spawn_t <= 0.0 and cars.size() < max_cars:
		_spawn_t = 0.35
		var spot := graph.random_spot(f, SPAWN_MIN, SPAWN_MAX, rng)
		if not spot.is_empty() and _spot_free(spot):
			spawn(spot, _pool[rng.randi() % _pool.size()])


func _spot_free(spot: Array) -> bool:
	var p: Vector3 = graph.lane_point(spot[0], spot[2], spot[1])[0]
	for c in cars:
		if c.global_position.distance_to(p) < 12.0:
			return false
	return true


func spawn(spot: Array, kind: String) -> TrafficCar:
	var c: TrafficCar = TrafficCarScript.new()
	c.traffic = self
	c.setup(graph, spot, kind, models[kind], rng.randi())
	add_child(c)
	c.place()                    # on the road now, not at the origin until its first physics step
	cars.append(c)
	return c


func _remove(c: TrafficCar) -> void:
	cars.erase(c)
	c.queue_free()


## Distance from `ahead` to the nearest thing in the lane (other traffic, the player,
## physics cars, pedestrians), ignoring things behind the car.
func clearance(me: TrafficCar, pos: Vector3, ahead: Vector3) -> float:
	var best := INF
	var fwd := (ahead - pos)
	fwd.y = 0.0
	var reach := fwd.length()
	fwd = fwd.normalized()
	for c in cars:
		if c == me:
			continue
		best = minf(best, _lane_dist(pos, fwd, reach, c.global_position, 2.2))
	for o in _obstacles:
		best = minf(best, _lane_dist(pos, fwd, reach, o, 2.0))
	return best


func _lane_dist(pos: Vector3, fwd: Vector3, reach: float, o: Vector3, half: float) -> float:
	var rel := o - pos
	rel.y = 0.0
	var along := rel.dot(fwd)
	if along < 0.5 or along > reach + 3.0:
		return INF
	var side := absf(rel.dot(Vector3(-fwd.z, 0.0, fwd.x)))
	return along if side < half else INF


## Is the player (on foot or in a car) standing in this car's lane just ahead?
func player_blocking(pos: Vector3, fwd: Vector3) -> bool:
	var p: Vector3 = main.focus_pos()
	return _lane_dist(pos, fwd, 9.0, p, 2.2) < INF


func honk(c: TrafficCar) -> void:
	if main.audio != null:
		main.audio.play("horn_keke" if c.kind == "keke" else "horn_car", c.global_position, 1.0)


func nearest_to(p: Vector3, max_d: float) -> TrafficCar:
	var best: TrafficCar = null
	var bd := max_d
	for c in cars:
		var d := c.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = c
	return best


## Replace a traffic car with a physics car (taken by the player or wrecked in a crash).
func to_physics(c: TrafficCar, push: Vector3 = Vector3.ZERO) -> RigidBody3D:
	var t := c.global_transform
	var v := c.velocity()
	var kind := c.kind
	_remove(c)
	var car: RigidBody3D = main.spawn_car(kind, t.translated(Vector3(0, 0.25, 0)))
	car.linear_velocity = v + push
	return car


## The player pulls the driver out and takes the car.
func take(c: TrafficCar) -> RigidBody3D:
	var kind := c.kind
	var side: Vector3 = c.global_transform * Vector3(-2.2, 0.3, 0.0)
	var car := to_physics(c)
	if not c.abandoned:
		main.eject_driver(side, kind == "police")
	car_taken.emit(car, kind, kind == "police")
	return car


## Shot at: stop, and after a few hits the driver runs away.
func on_shot(c: TrafficCar) -> void:
	c.hits += 1
	if c.hits >= 2 and not c.abandoned:
		c.abandoned = true
		main.eject_driver(c.global_transform * Vector3(-2.2, 0.3, 0.0), c.kind == "police")
