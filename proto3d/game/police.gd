class_name Police
extends Node
## Wanted level and police response.
## Crimes raise the wanted level (1-5 stars) when a witness or officer sees them.
## Police cars (more per star) route through the streets to the player; near a player on
## foot they stop and officers get out and chase on foot. From 2 stars officers shoot;
## from 3 stars the cars' officers shoot too. Lose them by staying out of sight long
## enough, or at a respray shop. Officers grabbing a player on foot, or a cruiser
## pinning a stopped car at 1-2 stars, ends in ARRESTED.

signal arrested

const WANT_CARS := [0, 1, 2, 3, 4, 6]
const CopScript := preload("res://proto3d/game/cop.gd")
const GraphDriverScript := preload("res://proto3d/game/graph_driver.gd")

var state: GameState
var graph: RoadGraph
var main                          # main_city.gd
var effects: Effects
var cars: Array[RigidBody3D] = []  # pursuing / responding police cars
var cops: Array = []
var evade_t := 0.0
var bust_t := 0.0
var rng := RandomNumberGenerator.new()
var _dispatch_t := 0.0


func setup(game_state: GameState, g: RoadGraph, main_node, fx: Effects) -> void:
	state = game_state
	graph = g
	main = main_node
	effects = fx
	rng.seed = 911


func player_pos() -> Vector3:
	return main.car.global_position if main.car != null else main.player.global_position


func player_node() -> Node3D:
	return main.car if main.car != null else main.player


## A crime at `at`: raises the wanted level if someone saw it.
func crime(n: int, at: Vector3) -> void:
	var seen := rng.randf() < 0.4 or state.stars > 0 or _police_near(at, 45.0)
	if seen:
		add_stars(n)


func add_stars(n: int) -> void:
	var before := state.stars
	state.set_stars(state.stars + n)
	evade_t = 0.0
	if before == 0 and state.stars > 0:
		state.say("The police are after you!", Color("#ff5a6e"), 3.0)


func clear() -> void:
	state.set_stars(0)
	bust_t = 0.0
	for c in cars:
		c.siren = false
	for cop in cops:
		cop.target = null


func cops_may_shoot() -> bool:
	return state.stars >= 2


func _police_near(at: Vector3, r: float) -> bool:
	for c in cars:
		if c.global_position.distance_to(at) < r:
			return true
	for cop in cops:
		if cop.global_position.distance_to(at) < r:
			return true
	for t in main.traffic.cars:
		if t.kind == "police" and t.global_position.distance_to(at) < r:
			return true
	return false


func _physics_process(delta: float) -> void:
	if state == null or not main.ready_done:
		return
	var p := player_pos()
	# despawn far or wrecked police; drop officers that are far away
	for c in cars.duplicate():
		if not is_instance_valid(c) or c.global_position.distance_to(p) > 420.0 or (state.stars == 0 and c.global_position.distance_to(p) > 150.0):
			cars.erase(c)
			main.remove_car(c)
	for cop in cops.duplicate():
		if not is_instance_valid(cop) or cop.global_position.distance_to(p) > 160.0 or (state.stars == 0 and cop.global_position.distance_to(p) > 40.0):
			cops.erase(cop)
			if is_instance_valid(cop):
				cop.queue_free()
	if state.stars == 0:
		bust_t = 0.0
		return
	_dispatch(delta, p)
	_officers_out(p)
	_update_cruisers()
	_update_evasion(delta, p)
	_update_bust(delta, p)


func _dispatch(delta: float, p: Vector3) -> void:
	_dispatch_t -= delta
	var live := 0
	for c in cars:
		if not c.wrecked:
			live += 1
	if live >= WANT_CARS[state.stars] or _dispatch_t > 0.0:
		return
	var spot := graph.random_spot(p, 110.0, 240.0, rng)
	if spot.is_empty():
		return
	_dispatch_t = 2.5
	var lp: Array = graph.lane_point(spot[0], spot[2], spot[1])
	var fwd: Vector3 = lp[1]
	var t := Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), (lp[0] as Vector3) + Vector3(0, 0.6, 0))
	var c: RigidBody3D = main.spawn_car("police", t)
	c.controller = GraphDriverScript.new(graph, "pursue", player_node(), 24.0, rng.randi())
	c.controller.viewer = main.player
	c.siren = true
	c.set_headlights(main.clock.darkness() > 0.35)
	cars.append(c)


func _update_cruisers() -> void:
	var target := player_node()
	for c in cars:
		if c.controller != null and c.controller.mode == "pursue":
			c.controller.target = target
		# the car's officers shoot from the window at 3+ stars
		if state.stars >= 3 and not c.wrecked and c.global_position.distance_to(target.global_position) < 18.0:
			if not c.has_meta("shoot_t") or float(c.get_meta("shoot_t")) <= 0.0:
				c.set_meta("shoot_t", rng.randf_range(1.2, 1.8))
				_fire_at_player(c.global_position + Vector3(0, 1.4, 0), c.global_position.distance_to(target.global_position))
			else:
				c.set_meta("shoot_t", float(c.get_meta("shoot_t")) - get_physics_process_delta_time())


## Officers get out when the player is on foot near a cruiser; back in when the player drives off.
func _officers_out(p: Vector3) -> void:
	for c in cars:
		if c.wrecked:
			continue
		var d := c.global_position.distance_to(p)
		if main.car == null and d < 16.0 and not c.has_meta("cops_out"):
			c.set_meta("cops_out", true)
			c.controller.mode = "hold"
			for k in mini(state.stars + 1, 3):
				var cop = CopScript.new()
				cop.police = self
				cop.target = main.player
				cop.car = c
				add_child(cop)
				cop.global_position = c.global_transform * Vector3(-2.2 + k * 0.6, 0.6, -0.8 + k * 1.2)
				cop.knocked.connect(_on_cop_knocked)
				cops.append(cop)
		elif main.car != null and d > 28.0 and c.has_meta("cops_out"):
			c.remove_meta("cops_out")
			c.controller.mode = "pursue"
			for cop in cops.duplicate():
				if cop.car == c:
					cops.erase(cop)
					cop.queue_free()
	for cop in cops:
		cop.target = main.player if main.car == null else null


func _on_cop_knocked(_impulse: Vector3) -> void:
	add_stars(1)


func _update_evasion(delta: float, p: Vector3) -> void:
	var seen := false
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var watchers: Array = []
	watchers.append_array(cars)
	watchers.append_array(cops)
	for n in watchers:
		if not is_instance_valid(n):
			continue
		var from: Vector3 = (n as Node3D).global_position + Vector3(0, 1.5, 0)
		if from.distance_to(p) > 75.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, p + Vector3(0, 1.2, 0), 1)
		if space.intersect_ray(q).is_empty():
			seen = true
			break
	if seen:
		evade_t = 0.0
	else:
		evade_t += delta
		if evade_t > (5.0 + state.stars * 2.5) * (1.0 - main.perks.effect("cool_head", "evade")):
			clear()
			state.say("You lost the police.", Color("#3ccf7a"), 3.0)


func _update_bust(delta: float, p: Vector3) -> void:
	var near := false
	if main.car == null:
		for cop in cops:
			if not cop.is_down() and cop.global_position.distance_to(p) < 1.4:
				near = true
	elif state.stars <= 2 and absf(main.car.speed) < 0.8:
		for c in cars:
			if not c.wrecked and c.global_position.distance_to(p) < 5.5:
				near = true
	bust_t = bust_t + delta if near else maxf(0.0, bust_t - delta)
	if bust_t > 1.6:
		bust_t = 0.0
		arrested.emit()


func cop_fire(cop, d: float) -> void:
	_fire_at_player(cop.global_position + Vector3(0, 1.4, 0), d)


func _fire_at_player(from: Vector3, d: float) -> void:
	var p := player_pos() + Vector3(0, 1.1, 0)
	var hit := rng.randf() < clampf(0.6 - d * 0.02, 0.15, 0.6)
	var to := p if hit else p + Vector3(rng.randf_range(-2, 2), rng.randf_range(-0.5, 1.5), rng.randf_range(-2, 2))
	effects.tracer(from, to)
	effects.muzzle(from)
	main.audio.play("gunshot", from, 2.0, 0.9)
	if hit:
		if main.car != null:
			main.car.apply_damage(6.0)
		else:
			state.hurt(9.0)


func remove_all() -> void:
	for c in cars:
		main.remove_car(c)
	cars.clear()
	for cop in cops:
		cop.queue_free()
	cops.clear()
