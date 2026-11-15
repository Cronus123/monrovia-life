class_name TaxiJob
extends Node3D
## Taxi side job. In a taxi or keke, T switches the hire light on: people waving at the
## kerb nearby (yellow !) get in when you stop beside them and ask for a real place in
## Monrovia. Get them there for the fare, plus a tip for a quick ride.

const PedScript := preload("res://proto3d/pedestrian.gd")

var state: GameState
var main                          # main_city.gd
var shops: Shops
var hire := false
var fare := {}                    # {dest, amount, started, dist}
var waiting: Array = []           # pedestrians waving for a ride
var rng := RandomNumberGenerator.new()
var _spawn_t := 0.0


func setup(game_state: GameState, main_node, s: Shops) -> void:
	state = game_state
	main = main_node
	shops = s
	rng.seed = 77


func can_hire() -> bool:
	return main.car != null and main.car.kind in ["taxi", "keke"]


func toggle() -> void:
	if not can_hire():
		state.say("You need a taxi or keke for taxi work.")
		return
	if main.missions.active():
		state.say("Finish your mission first.")
		return
	if hire and not fare.is_empty():
		state.say("Drop your passenger first.")
		return
	hire = not hire
	if hire:
		state.say("Hire light ON. Look for people waving at the kerb.")
	else:
		stop()
		state.say("Hire light OFF.")


func stop() -> void:
	hire = false
	fare = {}
	for p in waiting:
		if is_instance_valid(p):
			p.queue_free()
	waiting.clear()


## The player got out: the passenger leaves without paying.
func on_exit_car() -> void:
	if hire:
		if not fare.is_empty():
			state.say("Your passenger got out without paying.")
		stop()


func target() -> Variant:
	if not hire:
		return null
	if not fare.is_empty():
		return fare["dest"]["pos"]
	var best = null
	var bd := INF
	for p in waiting:
		var d: float = p.global_position.distance_to(main.car.global_position)
		if d < bd:
			bd = d
			best = p.global_position
	return best


func objective() -> String:
	if not hire:
		return ""
	if not fare.is_empty():
		return "Passenger to %s, fare %s" % [fare["dest"]["name"], GameState.money_text(fare["amount"])]
	return "Taxi work: pick up someone waving at the kerb (yellow !)"


func _process(delta: float) -> void:
	if not hire:
		return
	if main.car == null or not can_hire():
		stop()
		return
	var car = main.car
	if fare.is_empty():
		_spawn_t -= delta
		if waiting.size() < 3 and _spawn_t <= 0.0:
			_spawn_t = 1.0
			_spawn_waiting(car.global_position)
		for p in waiting.duplicate():
			if not is_instance_valid(p) or p.global_position.distance_to(car.global_position) > 220.0:
				waiting.erase(p)
				if is_instance_valid(p):
					p.queue_free()
				continue
			if p.global_position.distance_to(car.global_position) < 5.0 and absf(car.speed) < 1.5:
				_pick_up(p, car)
				break
	else:
		var dest: Vector3 = fare["dest"]["pos"]
		if dest.distance_to(car.global_position) < 9.0 and absf(car.speed) < 2.0:
			var secs := (Time.get_ticks_msec() - int(fare["started"])) / 1000.0
			var tip := int(fare["amount"] * (0.2 + main.perks.effect("keke_king", "tip_bonus"))) if secs < fare["dist"] / 9.0 + 20.0 else 0
			main.perks.add_fare()
			state.add_money(fare["amount"] + tip)
			state.say("+%s%s" % [GameState.money_text(fare["amount"] + tip), "  with a tip for a quick ride!" if tip > 0 else "  Fare paid."], Color("#f5c518"), 4.0)
			fare = {}


func _spawn_waiting(around: Vector3) -> void:
	var paths: Array = main.streamer.nearby(around, 170.0, "paths")
	if paths.is_empty():
		return
	for _t in 6:
		var path: Array = paths[rng.randi() % paths.size()]
		var q: Array = path[rng.randi() % path.size()]
		var at := Vector3(q[0], q[1], q[2])
		var d := at.distance_to(around)
		if d < 40.0 or d > 170.0:
			continue
		var p = PedScript.new()
		p.setup(PackedVector3Array([at]), 0, rng.randi())
		p.main = main
		p.waiting = true
		add_child(p)
		p.global_position = at + Vector3(0, 0.3, 0)
		var mark := Label3D.new()
		mark.text = "!"
		mark.font_size = 96
		mark.pixel_size = 0.01
		mark.outline_size = 16
		mark.modulate = Color("#f5c518")
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.position.y = 2.6
		p.add_child(mark)
		waiting.append(p)
		return


func _pick_up(p, car) -> void:
	var options: Array = []
	for d in shops.dests:
		if (d["pos"] as Vector3).distance_to(car.global_position) > 500.0:
			options.append(d)
	if options.is_empty():
		options = shops.dests
	var dest: Dictionary = options[rng.randi() % options.size()]
	var dist: float = (dest["pos"] as Vector3).distance_to(car.global_position)
	var amount := int(round((40.0 + dist * 0.09) * (1.7 if car.kind == "taxi" else 1.0) / 5.0)) * 5
	fare = {"dest": dest, "amount": amount, "started": Time.get_ticks_msec(), "dist": dist}
	waiting.erase(p)
	p.queue_free()
	for w in waiting:
		w.queue_free()
	waiting.clear()
	state.say("Passenger: \"Take me to %s, I beg you.\" Fare %s" % [dest["name"], GameState.money_text(amount)], Color.WHITE, 5.0)
