class_name Weapons
extends Node
## The player's weapons. Fists: a punch at whoever is right in front. Pistol: a shot
## along the camera's aim (the crosshair), up to 150 m, hitting people, cars and traffic.
## Shooting scares people nearby and can raise the wanted level; hitting the police
## always does.

const PISTOL_CD := 0.28
const FIST_CD := 0.45
const RANGE := 150.0

var state: GameState
var main                          # main_city.gd
var police: Police
var effects: Effects
var _cd := 0.0
var _hint_t := 0.0


func setup(game_state: GameState, main_node, pol: Police, fx: Effects) -> void:
	state = game_state
	main = main_node
	police = pol
	effects = fx


func _process(delta: float) -> void:
	_cd -= delta
	_hint_t -= delta


## Called while the fire button is held (on foot only).
func try_fire() -> void:
	if _cd > 0.0 or main.car != null or main.player.is_down():
		return
	if state.weapon == GameState.PISTOL:
		if not state.use_ammo():
			state.say("Out of ammo. Buy more at a weapon shop.")
			state.select_weapon(GameState.FISTS)
			_cd = 0.5
			return
		_cd = PISTOL_CD
		_shoot()
	else:
		_cd = FIST_CD
		_punch()


## Drive-by: in a car with the pistol, shoot where the camera aims, out of the side or
## rear windows (not through the windscreen).
func try_fire_from_car() -> void:
	if _cd > 0.0 or main.car == null or state.weapon != GameState.PISTOL:
		return
	var ray := _aim_ray()
	var dir: Vector3 = ray[1]
	var car = main.car
	var fwd: Vector3 = -car.global_basis.z
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	if flat.dot(Vector3(fwd.x, 0, fwd.z).normalized()) > 0.8:
		if _hint_t <= 0.0:
			_hint_t = 6.0
			state.say("Aim out of a side window to shoot from the car.")
		return
	if not state.use_ammo():
		state.say("Out of ammo.")
		_cd = 0.5
		return
	_cd = PISTOL_CD
	var side: Vector3 = car.global_basis.x * signf(flat.dot(car.global_basis.x))
	var muzzle: Vector3 = car.global_position + Vector3(0, 1.3, 0) + side * 1.0
	_fire_ray(ray[0], dir, muzzle, [car.get_rid()])


func _aim_ray() -> Array:
	var cam: Camera3D = main.rig.cam
	var vp := cam.get_viewport().get_visible_rect().size
	var from := cam.project_ray_origin(vp / 2.0)
	var dir := cam.project_ray_normal(vp / 2.0)
	return [from, dir]


func _shoot() -> void:
	var player = main.player
	var ray := _aim_ray()
	var from: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	# face the shot
	player.model.rotation.y = atan2(-dir.x, -dir.z)
	player.body.play("shoot")
	var muzzle: Vector3 = player.global_position + Vector3(0, 1.35, 0) + Vector3(dir.x, 0, dir.z).normalized() * 0.5
	_fire_ray(from, dir, muzzle, [player.get_rid()])


func _fire_ray(from: Vector3, dir: Vector3, muzzle: Vector3, exclude: Array[RID]) -> void:
	var q := PhysicsRayQueryParameters3D.create(from + dir * 1.5, from + dir * RANGE, 1 | 2 | 4 | 8, exclude)
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit.position if not hit.is_empty() else from + dir * RANGE
	effects.tracer(muzzle, end)
	effects.muzzle(muzzle)
	main.audio.play("gunshot", muzzle, 4.0)
	main.scare_people(muzzle, 25.0)
	if state.stars == 0 and randf() < 0.3:
		police.crime(1, muzzle)
	if not hit.is_empty():
		_hit(hit.collider, 40.0, 18.0)


func _punch() -> void:
	var player = main.player
	player.body.play("punch")
	var fwd: Vector3 = Basis(Vector3.UP, player.model.rotation.y) * Vector3.FORWARD
	var at: Vector3 = player.global_position + fwd * 0.9
	for w in main.all_walkers():
		if w != player and not w.is_down() and w.global_position.distance_to(at) < 0.9:
			main.audio.play("punch", at, 0.0)
			_hit(w, 25.0, 0.0)
			return


func _hit(target: Object, person_damage: float, car_damage: float) -> void:
	if target == null:
		return
	if target.has_method("shot"):
		var was_down: bool = target.is_down()
		target.shot(person_damage, true, main.player.global_position)
		if target.has_method("cops_may_shoot") or target.get("police") != null:
			police.add_stars(1)                    # attacking an officer
		elif not was_down:
			police.crime(1, target.global_position)
		if target.is_down() and not was_down and target.get("police") == null and randf() < 0.6:
			effects.drop_cash(target.global_position, randi_range(10, 80))
	elif target.has_method("apply_damage") and car_damage > 0.0:
		target.apply_damage(car_damage)
		if target.get("kind") == "police":
			police.add_stars(1)
	elif target is TrafficCar and car_damage > 0.0:
		main.traffic.on_shot(target)
		police.crime(1, (target as Node3D).global_position)
