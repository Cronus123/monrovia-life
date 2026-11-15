class_name Weapons
extends Node
## The player's weapons, from data/weapons.json: fists (a three-hit combo), baseball bat,
## machete, pistol, SMG (automatic) and shotgun (pellets). Guns have magazines and reloads,
## fire along the camera's aim (the crosshair), kick the camera (recoil), flash at the
## muzzle and throw out shells. The weapon in hand is shown in the player's right hand.
## Shooting scares people nearby and can raise the wanted level; hitting the police
## always does.

const DATA := "res://proto3d/game/data/weapons.json"
const MODELS := {
	"pistol": preload("res://proto3d/models/weapons/pistol.glb"),
	"smg": preload("res://proto3d/models/weapons/smg.glb"),
	"shotgun": preload("res://proto3d/models/weapons/shotgun.glb"),
	"bat": preload("res://proto3d/models/weapons/bat.glb"),
	"machete": preload("res://proto3d/models/weapons/machete.glb"),
}
const COMBO_WINDOW := 0.8

var state: GameState
var main                          # main_city.gd
var police: Police
var effects: Effects
var defs: Array = []
var aiming := false
var reloading := 0.0              # seconds left of a reload
var _cd := 0.0
var _hint_t := 0.0
var _combo := 0
var _combo_t := 0.0
var _trigger_down := false
var _held: Node3D                 # weapon model in the player's hand
var _held_id := ""
var _held_rest := Transform3D()
var _kick := 0.0                  # weapon recoil (decays)
var _hold_t := 0.0                # arm stays up for a moment after a hip-fire shot


func setup(game_state: GameState, main_node, pol: Police, fx: Effects) -> void:
	state = game_state
	main = main_node
	police = pol
	effects = fx
	defs = JSON.parse_string(FileAccess.get_file_as_string(DATA))["weapons"]
	_make_shells()
	state.weapon_changed.connect(func(_w, _a): _cancel_reload())


func def(w: int = -1) -> Dictionary:
	return defs[state.weapon if w < 0 else w]


func is_gun() -> bool:
	return GameState.is_gun(state.weapon)


func _process(delta: float) -> void:
	_cd -= delta
	_hint_t -= delta
	_combo_t -= delta
	if _combo_t <= 0.0:
		_combo = 0
	if not Input.is_action_pressed("p3_fire"):
		_trigger_down = false
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			reloading = 0.0
			state.reload()
	var p = main.player if main != null else null
	aiming = p != null and main.car == null and p.active and not p.is_down() and is_gun() \
		and Input.is_action_pressed("p3_aim")
	_hold_t -= delta
	if p != null:
		p.aiming = aiming
		p.arm_up = aiming or (_hold_t > 0.0 and is_gun())
	if main != null and main.rig != null:
		main.rig.aiming = aiming
	_update_held(delta)


# ------------------------------------------------------------------ firing
## Called every frame while the fire button is held (on foot).
func try_fire() -> void:
	if _cd > 0.0 or main.car != null or main.player.is_down():
		return
	var d := def()
	if d.get("melee", false):
		if _trigger_down:
			return
		_trigger_down = true
		_melee(d)
		return
	if not bool(d.get("auto", false)) and _trigger_down:
		return
	_trigger_down = true
	if reloading > 0.0:
		return
	if not state.use_ammo():
		if state.can_reload():
			start_reload()
		else:
			state.say("Out of ammo. Buy more at a weapon shop.")
			state.select_weapon(GameState.FISTS)
			_cd = 0.4
		return
	_cd = float(d["cooldown"])
	_shoot(d)


## Drive-by: in a car with a gun, shoot where the camera aims, out of the side or rear
## windows (not through the windscreen).
func try_fire_from_car() -> void:
	if _cd > 0.0 or main.car == null or not is_gun() or reloading > 0.0:
		return
	var d := def()
	if not bool(d.get("auto", false)) and _trigger_down:
		return
	_trigger_down = true
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
		if state.can_reload():
			start_reload()
		else:
			state.say("Out of ammo.")
			_cd = 0.5
		return
	_cd = float(d["cooldown"])
	var side: Vector3 = car.global_basis.x * signf(flat.dot(car.global_basis.x))
	var muzzle: Vector3 = car.global_position + Vector3(0, 1.3, 0) + side * 1.0
	_fire_pellets(d, ray[0], dir, muzzle, [car.get_rid()])


func start_reload() -> void:
	if reloading > 0.0 or not state.can_reload():
		return
	var d := def()
	reloading = float(d.get("reload", 1.2))
	if main.car == null:
		main.player.body.play_reload(reloading)
	main.audio.play("reload", main.player.global_position, -2.0, 1.2 / maxf(0.5, reloading))


func _cancel_reload() -> void:
	reloading = 0.0
	_combo = 0                    # a new weapon starts a new combo


func _aim_ray() -> Array:
	var cam: Camera3D = main.rig.cam
	var vp := cam.get_viewport().get_visible_rect().size
	var from := cam.project_ray_origin(vp / 2.0)
	var dir := cam.project_ray_normal(vp / 2.0)
	return [from, dir]


func _shoot(d: Dictionary) -> void:
	var player = main.player
	var ray := _aim_ray()
	var from: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	player.model.rotation.y = atan2(-dir.x, -dir.z)        # face the shot
	_hold_t = 0.7                                          # raise the gun arm (aim layer)
	var muzzle := muzzle_position()
	_fire_pellets(d, from, dir, muzzle, [player.get_rid()])
	_kick = 1.0
	# recoil: the camera kicks up a little (more when not aiming)
	main.rig.pitch += float(d.get("recoil", 0.03)) * (0.6 if aiming else 1.0)
	if main.rig.has_method("shake"):
		main.rig.shake(minf(0.25, float(d.get("recoil", 0.03)) * 2.5))
	_eject_shell()


## Where shots leave the gun (the held model's muzzle, else in front of the chest).
func muzzle_position() -> Vector3:
	if _held != null and is_instance_valid(_held):
		var m := _held.find_child("muzzle", true, false) as Node3D
		if m != null:
			return m.global_position
	var p = main.player
	var fwd: Vector3 = Basis(Vector3.UP, p.model.global_rotation.y) * Vector3.FORWARD
	return p.global_position + Vector3(0, 1.35, 0) + fwd * 0.5


func _fire_pellets(d: Dictionary, from: Vector3, dir: Vector3, muzzle: Vector3, exclude: Array[RID]) -> void:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var spread := float(d.get("spread", 0.0)) * (0.5 if aiming else 1.0)
	var rng: float = d.get("range", 150.0)
	var hit_any: Array = []
	for i in int(d.get("pellets", 1)):
		var dd := dir
		if spread > 0.0:
			var basis := Basis.looking_at(dir)
			dd = (basis * Vector3(randf_range(-spread, spread), randf_range(-spread, spread), -1.0)).normalized()
		var q := PhysicsRayQueryParameters3D.create(from + dd * 1.5, from + dd * rng, 1 | 2 | 4 | 8, exclude)
		var hit: Dictionary = space.intersect_ray(q)
		var end: Vector3 = hit.position if not hit.is_empty() else from + dd * rng
		if i < 3:
			effects.tracer(muzzle, end)
		if not hit.is_empty():
			hit_any.append(hit)
	effects.muzzle(muzzle)
	main.audio.play(String(d.get("sound", "gunshot")), muzzle, 4.0, randf_range(0.95, 1.05))
	main.scare_people(muzzle, 25.0)
	if state.stars == 0 and randf() < 0.3:
		police.crime(1, muzzle)
	for hit in hit_any:
		_hit(hit.collider, float(d["damage"]), float(d.get("car_damage", 0.0)))


func _melee(d: Dictionary) -> void:
	var player = main.player
	var anims: Array = d.get("anims", ["punch"])
	var step := _combo % anims.size()
	var finisher := String(d["id"]) == "fists" and step == anims.size() - 1
	player.body.play(String(anims[step]))
	_combo += 1
	_combo_t = COMBO_WINDOW
	_cd = float(d["cooldown"]) * (1.3 if finisher else 1.0)
	main.audio.play("swing", player.global_position, -6.0, randf_range(0.9, 1.15))
	var fwd: Vector3 = Basis(Vector3.UP, player.model.rotation.y) * Vector3.FORWARD
	var reach := float(d.get("reach", 0.95))
	var at: Vector3 = player.global_position + fwd * reach
	var dmg := float(d["damage"]) * (float(d.get("combo_bonus", 1.0)) if finisher else 1.0)
	for w in main.all_walkers():
		if w != player and not w.is_down() and w.global_position.distance_to(at) < reach:
			main.audio.play("melee_hit" if String(d["id"]) != "fists" else "punch", at, 0.0)
			_hit(w, dmg, 0.0)
			if finisher or String(d["id"]) != "fists":
				w.push(fwd * 3.0)
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


# ------------------------------------------------------------------ the weapon in hand
## Shows the current weapon in the player's right hand; dips it while reloading and
## kicks it back on each shot.
func _update_held(delta: float) -> void:
	var p = main.player if main != null else null
	if p == null or p.body == null or p.body.skeleton == null:
		return
	var want: String = def()["id"] if main.car == null and p.active else ""
	if want == "fists":
		want = ""
	if want != _held_id:
		if _held != null and is_instance_valid(_held):
			_held.get_parent().queue_free()
		_held = null
		_held_id = want
		if MODELS.has(want):
			var sk: Skeleton3D = p.body.skeleton
			var ba := BoneAttachment3D.new()
			ba.bone_name = "Fist.R"
			sk.add_child(ba)
			_held = (MODELS[want] as PackedScene).instantiate() as Node3D
			ba.add_child(_held)
			# hand space -> weapon: skeleton units are scaled by the rig (0.55); undo that,
			# and point the barrel forward out of the fist
			var s := 1.0 / maxf(0.01, sk.global_basis.get_scale().x)
			# (the characters are chunky, with big fists: weapons are drawn 1.8x so they read)
			_held_rest = Transform3D(Basis.from_euler(Vector3(PI / 2, 0, 0)).scaled(Vector3.ONE * s * 1.8), Vector3(0, 0.22, 0.04))
			_held.transform = _held_rest
	if _held == null:
		return
	_kick = maxf(0.0, _kick - delta * 9.0)
	var dip := 0.0
	if reloading > 0.0:
		var total := float(def().get("reload", 1.2))
		dip = sin(clampf(1.0 - reloading / total, 0.0, 1.0) * PI) * 0.9
	_held.transform = _held_rest * Transform3D(Basis(Vector3.RIGHT, dip + _kick * 0.25), Vector3(0, 0, _kick * 0.06))


var _shell_mesh: CylinderMesh


func _make_shells() -> void:
	_shell_mesh = CylinderMesh.new()
	_shell_mesh.top_radius = 0.006
	_shell_mesh.bottom_radius = 0.006
	_shell_mesh.height = 0.022
	_shell_mesh.radial_segments = 6
	_shell_mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#c9a24a")
	mat.metallic = 0.9
	mat.roughness = 0.3
	_shell_mesh.material = mat


## A brass casing flies out to the right and falls (a short arc, no physics body).
func _eject_shell() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var at := muzzle_position()
	var p = main.player
	var right: Vector3 = Basis(Vector3.UP, p.model.global_rotation.y) * Vector3.RIGHT
	var v := right * randf_range(1.5, 2.5) + Vector3(0, randf_range(1.5, 2.5), 0)
	var mi := MeshInstance3D.new()
	mi.mesh = _shell_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	var spin := Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	var tw := create_tween()
	tw.tween_method(func(t: float):
		mi.global_position = at + v * t + Vector3(0, -4.9, 0) * t * t
		mi.rotation = spin * t, 0.0, 0.55, 0.55)
	tw.tween_callback(mi.queue_free)
	main.audio.play("shell", at + Vector3(0, -1.2, 0), -10.0, randf_range(0.9, 1.2))
