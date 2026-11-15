extends RigidBody3D
## Raycast car: a rigid body held up by four spring/damper "wheels".
## Each wheel adds suspension force, tyre force and engine/brake force:
##  - tyres: lateral force from the slip angle through a grip curve (peaks at ~8 degrees,
##    then falls off, so you can slide), combined with drive/brake force in a friction
##    circle (wheelspin costs grip: power oversteer), limited by the load on that wheel
##  - weight transfer comes from the suspension itself (braking loads the front,
##    cornering loads the outside), with anti-roll bars per axle
##  - per-vehicle tuning: a keke is light, twitchy and tippy, trucks are heavy and slow
## Damage: crashes dent the body where they hit, break the headlights, knock off loose
## parts (bumpers, doors, mirrors), make the engine smoke and finally burn and explode.
## Forward is -Z. W/S throttle and brake/reverse, A/D steer, Space handbrake.
##
## Driven by the player (driven = true), by an AI `controller` (any object with
## drive_input(car) -> Vector3(throttle, steer, handbrake)), or parked.

signal exploded(car: RigidBody3D)
signal hit_person(car: RigidBody3D, person: Node, speed: float)
signal crashed(car: RigidBody3D, other: Node, impact: float)

const Look := preload("res://proto3d/vehicle_look.gd")
const DEBRIS := {"bumper": preload("res://proto3d/models/debris/debris-bumper.glb"),
	"door": preload("res://proto3d/models/debris/debris-door.glb"),
	"door_window": preload("res://proto3d/models/debris/debris-door-window.glb"),
	"tire": preload("res://proto3d/models/debris/debris-tire.glb"),
	"plate": preload("res://proto3d/models/debris/debris-plate-a.glb")}

const REST := 0.42            # suspension travel (m)
const WHEEL_R := 0.36
const ROLLING := 45.0         # rolling resistance per wheel (N per m/s)
const STEER_RATE := 2.6       # rad/s the wheels turn
const BURN_TIME := 4.0
const PEAK_SLIP := 0.14       # rad: slip angle where the tyre grips best

## mass kg, engine N, top speed m/s, tyre mu, spring N/m and damper per wheel,
## centre of mass height, half track (m), half wheelbase, steering lock (slow, fast),
## anti-roll N/m, drag
const TUNING := {
	"car":    {"mass": 1200.0, "engine": 8800.0, "vmax": 31.0, "mu": 1.35, "spring": 26000.0, "damp": 2600.0, "com": 0.45, "track": 0.82, "base": 1.35, "steer": Vector2(0.55, 0.13), "arb": 9000.0, "drag": 0.95},
	"taxi":   {"mass": 1150.0, "engine": 8000.0, "vmax": 29.0, "mu": 1.3, "spring": 25000.0, "damp": 2500.0, "com": 0.47, "track": 0.82, "base": 1.35, "steer": Vector2(0.55, 0.13), "arb": 8000.0, "drag": 0.95},
	"police": {"mass": 1350.0, "engine": 10800.0, "vmax": 37.0, "mu": 1.45, "spring": 30000.0, "damp": 2900.0, "com": 0.42, "track": 0.84, "base": 1.4, "steer": Vector2(0.55, 0.12), "arb": 12000.0, "drag": 0.9},
	"sport":  {"mass": 1250.0, "engine": 12500.0, "vmax": 43.0, "mu": 1.6, "spring": 33000.0, "damp": 3100.0, "com": 0.36, "track": 0.86, "base": 1.35, "steer": Vector2(0.52, 0.11), "arb": 15000.0, "drag": 0.8},
	"suv":    {"mass": 1900.0, "engine": 12000.0, "vmax": 31.0, "mu": 1.25, "spring": 38000.0, "damp": 3800.0, "com": 0.68, "track": 0.88, "base": 1.45, "steer": Vector2(0.5, 0.12), "arb": 9000.0, "drag": 1.15},
	"van":    {"mass": 2600.0, "engine": 13500.0, "vmax": 27.0, "mu": 1.2, "spring": 48000.0, "damp": 4800.0, "com": 0.62, "track": 0.9, "base": 1.55, "steer": Vector2(0.48, 0.12), "arb": 14000.0, "drag": 1.3},
	"truck":  {"mass": 6000.0, "engine": 26000.0, "vmax": 23.0, "mu": 1.1, "spring": 110000.0, "damp": 10500.0, "com": 0.85, "track": 1.0, "base": 1.9, "steer": Vector2(0.45, 0.1), "arb": 30000.0, "drag": 2.2},
	"pickup": {"mass": 1800.0, "engine": 11500.0, "vmax": 30.0, "mu": 1.25, "spring": 36000.0, "damp": 3600.0, "com": 0.62, "track": 0.86, "base": 1.6, "steer": Vector2(0.5, 0.12), "arb": 9000.0, "drag": 1.1},
	"minibus": {"mass": 2200.0, "engine": 11000.0, "vmax": 27.0, "mu": 1.2, "spring": 42000.0, "damp": 4200.0, "com": 0.72, "track": 0.86, "base": 1.5, "steer": Vector2(0.5, 0.12), "arb": 9000.0, "drag": 1.3},
	"keke":   {"mass": 380.0, "engine": 2600.0, "vmax": 17.0, "mu": 1.05, "spring": 9000.0, "damp": 900.0, "com": 0.75, "track": 0.5, "base": 1.05, "steer": Vector2(0.65, 0.2), "arb": 0.0, "drag": 0.55},
}

@export var model_scene: PackedScene
var kind := "car"             # taxi, keke, car, suv, sport, truck, van, police
var driven := false
var controller: Object = null # AI driver
var speed := 0.0              # forward speed (m/s), for the HUD and tests
var steer := 0.0
var damage := 0.0             # 0..100, from crashes and bullets
var burning := -1.0           # seconds until the explosion while on fire, else < 0
var wrecked := false
var siren := false
var mission_tag := ""
var model: Node3D
var hit_area: Area3D
var tune: Dictionary
var lights_broken := false
var wheel_slip := 0.0         # 0..1, how much the tyres are sliding (for skid sounds)
var _wheels: Array[Vector3] = []
var _spawn := Transform3D()
var _upside_t := 0.0
var _still_t := 0.0
var _lights: Array[SpotLight3D] = []
var _fire: CPUParticles3D
var _smoke: CPUParticles3D
var _beacon: MeshInstance3D
var _beacon_mats: Array[StandardMaterial3D] = []
var _glb: Node3D                    # the model's root (parts are its children)
var _parts: Array[MeshInstance3D] = []
var _wheel_parts: Array = []         # [MeshInstance3D, rest Transform3D, front: bool]
var _spin := 0.0
var _contact := Vector3.ZERO         # last contact point (global) and normal
var _contact_n := Vector3.UP
var _detached := 0
var paint_color: Variant = null      # set before adding (traffic colours), or set_paint()
var look := {}                      # vehicle_look.gd parts: lights, wheels, paint surfaces
var braking_now := false
var _ind_side := 0                  # indicator: -1 left, 1 right, 0 off
var _ind_t := 0.0
var _prev_vel := Vector3.ZERO


func _ready() -> void:
	add_to_group("cars")
	tune = TUNING.get(kind, TUNING["car"])
	mass = tune["mass"]
	var tr: float = tune["track"]
	var wb: float = tune["base"]
	_wheels = [Vector3(-tr, 0.45, -wb), Vector3(tr, 0.45, -wb), Vector3(-tr, 0.45, wb), Vector3(tr, 0.45, wb)]
	collision_layer = 4
	collision_mask = 1 | 4 | 8          # world, cars, props (people are handled by hit_area)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, tune["com"], 0.1)
	angular_damp = 1.2
	linear_damp = 0.02
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	model = Node3D.new()
	model.position.y = -0.22           # wheels on the ground at the spring's rest load
	add_child(model)
	if model_scene != null:
		_glb = model_scene.instantiate() as Node3D
		_glb.rotation.y = PI / 2       # Blender models face +X; the car drives along -Z
		model.add_child(_glb)
		_find_parts()
		_wheels_from_model()
	_fit_collision()
	# Detects people the car runs into (they aren't solid to the car).
	hit_area = Area3D.new()
	hit_area.collision_layer = 0
	hit_area.collision_mask = 2
	var hs := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = Vector3(tr * 2.0 + 0.45, 1.2, wb * 2.0 + 2.0)
	hs.shape = hbox
	hs.position.y = 1.0
	hit_area.add_child(hs)
	add_child(hit_area)
	if kind == "police":
		_add_beacon()
	_spawn = global_transform


## Body collision boxes sized from the model (lower body + cabin).
func _fit_collision() -> void:
	var box_size := Vector3(1.85, 0.8, 4.3)
	var top := 1.65
	if _glb != null:
		var aabb := AABB()
		var first := true
		for mi in _parts:
			var a: AABB = (model.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
		if not first:
			box_size = Vector3(aabb.size.x * 0.96, 0.8, aabb.size.z * 0.96)
			top = aabb.end.y - 0.22
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	shape.position.y = 0.75
	add_child(shape)
	var cabin := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	var ch := clampf(top - 1.15, 0.3, 2.5)
	cbox.size = Vector3(box_size.x * 0.86, ch, box_size.z * 0.5)
	cabin.shape = cbox
	cabin.position = Vector3(0, 1.15 + ch * 0.5, 0.2)
	add_child(cabin)


func _find_parts() -> void:
	look = Look.style(_glb, paint_color, true)
	for n in _glb.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := String(mi.name)
		if nm.begins_with("Cylinder") or (nm.begins_with("wheel") and not nm.contains("_hub")):
			# wheels: spin them, steer the front ones (models face +X: front = +x)
			_wheel_parts.append([mi, mi.transform, mi.transform.origin.x > 0.0])
		elif not nm.begins_with("interior"):
			_parts.append(mi)


## Suspension rays under the model's own wheels (track and wheelbase of that vehicle).
func _wheels_from_model() -> void:
	var front: Array = []
	var rear: Array = []
	for w in _wheel_parts:
		var p: Vector3 = to_local((w[0] as Node3D).global_position)
		(front if w[2] else rear).append(Vector3(p.x, 0.45, p.z))
	if rear.size() < 2 or front.is_empty():
		return
	if front.size() == 1:                     # keke: one front wheel - two rays close together
		var f: Vector3 = front[0]
		front = [f + Vector3(-0.18, 0, 0), f + Vector3(0.18, 0, 0)]
	front.sort_custom(func(a, b): return a.x < b.x)
	rear.sort_custom(func(a, b): return a.x < b.x)
	_wheels = [front[0], front[front.size() - 1], rear[0], rear[rear.size() - 1]]


## New paint (respray shop, mission cars, traffic colours).
func set_paint(col: Color) -> void:
	paint_color = col
	Look.repaint(look, col)


## Close-up driving view: a hood camera just in front of the windscreen.
func first_person_point() -> Vector3:
	return global_transform * Vector3(0.0, 1.1, -1.35)


## Where the player stands after getting out (driver's side).
func exit_point() -> Vector3:
	var p := global_transform * Vector3(-2.0, 0.6, 0.0)
	return Vector3(p.x, maxf(p.y, global_position.y + 0.3), p.z)


func kmh() -> int:
	return int(absf(speed) * 3.6)


func reset_to(t: Transform3D) -> void:
	_spawn = t
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func condition() -> int:
	return int(clampf(100.0 - damage, 0.0, 100.0))


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if state.get_contact_count() > 0:
		_contact = state.get_contact_local_position(0)
		_contact_n = state.get_contact_local_normal(0)


func _physics_process(delta: float) -> void:
	var fwd := -global_basis.z
	speed = linear_velocity.dot(fwd)
	_prev_vel = linear_velocity
	_update_fire(delta)
	_spin_wheels(delta)
	_update_lights(delta)
	if _beacon != null and siren:
		var on := int(Time.get_ticks_msec() / 180) % 2 == 0
		_beacon_mats[0].emission_energy_multiplier = 3.0 if on else 0.2
		_beacon_mats[1].emission_energy_multiplier = 0.2 if on else 3.0
	var ai := controller != null and not driven and not wrecked
	# Parked and settled: let the physics engine put it to sleep (a hit wakes it up).
	if not driven and not ai:
		if sleeping:
			return
		if linear_velocity.length() < 0.08 and angular_velocity.length() < 0.08:
			_still_t += delta
			if _still_t > 1.0:
				sleeping = true
				return
		else:
			_still_t = 0.0
	var throttle := 0.0
	var steer_in := 0.0
	var handbrake := not driven and not ai
	if driven and not wrecked:
		throttle = Input.get_axis("p3_back", "p3_forward")
		steer_in = Input.get_axis("p3_right", "p3_left")
		handbrake = Input.is_action_pressed("p3_jump")
	elif ai:
		var inp: Vector3 = controller.drive_input(self)
		throttle = inp.x
		steer_in = inp.y
		handbrake = inp.z > 0.5
	if burning >= 0.0:
		throttle *= 0.4
	throttle *= 1.0 - clampf((damage - 60.0) / 80.0, 0.0, 0.4)     # a battered engine is weaker
	var flooded := global_position.y < -0.7                       # driven into the sea / river
	if flooded:
		throttle = 0.0
		linear_velocity *= 1.0 - minf(1.0, delta * 1.5)
		if damage < 99.0:
			damage = minf(99.0, damage + delta * 8.0)
			_update_smoke()
	var vmax: float = tune["vmax"]
	var engine: float = tune["engine"]
	var brake: float = mass * 9.2
	# Speed-sensitive steering, turned smoothly.
	var sl: Vector2 = tune["steer"]
	var lock := lerpf(sl.x, sl.y, clampf(absf(speed) / vmax, 0.0, 1.0))
	steer = move_toward(steer, steer_in * lock, STEER_RATE * delta)

	# Throttle forward, or brake then reverse.
	var drive := 0.0
	var braking := 0.0
	if throttle > 0.0:
		if speed < -0.5:
			braking = brake * throttle
		elif speed < vmax:
			drive = engine * throttle * (1.0 - 0.6 * clampf(speed / vmax, 0.0, 1.0))
	elif throttle < 0.0:
		if speed > 0.5:
			braking = brake * -throttle
		elif speed > -8.0:
			drive = engine * 0.55 * throttle
	if handbrake:
		braking = maxf(braking, brake * 0.6)
	braking_now = braking > 0.0 and not handbrake
	_ind_side = 0 if absf(steer_in) < 0.3 or absf(speed) < 1.0 else (-1 if steer_in > 0.0 else 1)

	var space := get_world_3d().direct_space_state
	var up := global_basis.y
	var spring: float = tune["spring"]
	var damp: float = tune["damp"]
	var mu0: float = tune["mu"]
	# suspension first (all four), so the anti-roll bars can compare left and right
	var comp: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var contacts: Array = [null, null, null, null]
	for i in 4:
		var origin: Vector3 = global_transform * _wheels[i]
		var q := PhysicsRayQueryParameters3D.create(origin, origin - up * (REST + WHEEL_R), 1 | 8, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		contacts[i] = hit.position
		comp[i] = (REST + WHEEL_R) - origin.distance_to(hit.position)
	var arb: float = tune["arb"]
	var slip_sum := 0.0
	for i in 4:
		if contacts[i] == null:
			continue
		var front := i < 2
		var contact: Vector3 = contacts[i]
		var r := contact - global_position
		var pv := linear_velocity + angular_velocity.cross(r)
		var other := i ^ 1
		var roll := (comp[i] - comp[other]) * arb
		var load := maxf(0.0, comp[i] * spring - pv.dot(up) * damp + roll)
		apply_force(up * load, r)
		# Tyre directions: the front wheels turn with the steering.
		var wheel_basis := global_basis * (Basis(Vector3.UP, steer) if front else Basis.IDENTITY)
		var wfwd := -wheel_basis.z
		var wside := wheel_basis.x
		var at := r + up * 0.25                # at axle height: leans the body without flipping it
		var mu := mu0 * (0.55 if (handbrake and not front and driven) else 1.0)
		var limit := mu * load
		var side_v := pv.dot(wside)
		var long_v := pv.dot(wfwd)
		# longitudinal: rolling resistance, rear-wheel drive, brakes (more at the front)
		var long_f := -long_v * ROLLING
		if not front:
			long_f += drive * 0.5
		if braking > 0.0 and absf(long_v) > 0.05:
			long_f -= signf(long_v) * braking * (0.3 if front else 0.2)
		elif braking > 0.0:
			long_f -= long_v * mass * 0.25 / maxf(delta, 0.001) * 0.5   # hold still
		# lateral: slip-angle grip curve at speed, plain friction when crawling
		var slip := atan2(side_v, absf(long_v) + 0.5)
		var curve := _grip_curve(absf(slip)) * signf(slip)
		var side_fast := -curve * limit
		var side_slow := clampf(-side_v * mass * 0.25 / maxf(delta, 0.001) * 0.35, -limit, limit)
		var w := clampf((absf(long_v) - 2.0) / 4.0, 0.0, 1.0)
		var side_f := lerpf(side_slow, side_fast, w)
		# friction circle: drive/brake force uses up grip the tyre can't give sideways
		var total := Vector2(long_f, side_f)
		if total.length() > limit:
			total = total.normalized() * limit
			slip_sum += 0.25
		slip_sum += clampf((absf(slip) - PEAK_SLIP) * 3.0, 0.0, 1.0) * 0.25 * w
		apply_force(wside * total.y + wfwd * total.x, at)
	wheel_slip = clampf(slip_sum, 0.0, 1.0)
	apply_central_force(-linear_velocity * linear_velocity.length() * float(tune["drag"]))

	_hit_people()
	_recover(delta)


## Lateral grip (0..1 of the friction limit) vs slip angle: rises steeply, peaks at
## PEAK_SLIP, then falls to about 75% when sliding (simplified "magic formula").
static func _grip_curve(a: float) -> float:
	var x := a / PEAK_SLIP
	if x < 1.0:
		return sin(x * PI * 0.5)
	return maxf(0.75, 1.0 - (x - 1.0) * 0.08)


## Head, tail/brake lights and indicators (hazards when wrecked or on fire).
func _update_lights(delta: float) -> void:
	var ls: Dictionary = look.get("lights", {})
	if ls.is_empty():
		return
	var lamps_on := not _lights.is_empty() and (_lights[0] as Light3D).visible
	_set_glow(ls.get("light_head"), 0.0 if lights_broken or wrecked else (3.5 if lamps_on else 0.0))
	_set_glow(ls.get("light_tail"), 0.0 if wrecked else (4.0 if braking_now else (1.2 if lamps_on else 0.0)))
	_ind_t += delta
	var blink := fmod(_ind_t, 0.8) < 0.4
	var hazard := burning >= 0.0 or (damage > 60.0 and not wrecked)
	_set_glow(ls.get("light_ind_l"), 3.0 if blink and (hazard or _ind_side == -1) else 0.0)
	_set_glow(ls.get("light_ind_r"), 3.0 if blink and (hazard or _ind_side == 1) else 0.0)


func _set_glow(mi, energy: float) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	var m := (mi as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
	if m != null:
		m.emission_energy_multiplier = energy


func _spin_wheels(delta: float) -> void:
	_spin = fmod(_spin + speed / WHEEL_R * delta, TAU)
	for w in _wheel_parts:
		var mi: MeshInstance3D = w[0]
		var rest: Transform3D = w[1]
		# axle = model Z (models face +X); front wheels also turn about Y
		var b := Basis(Vector3.UP, steer if w[2] else 0.0) * Basis(Vector3(0, 0, 1), -_spin) * rest.basis
		mi.transform = Transform3D(b, rest.origin)


## People aren't solid to the car: fast hits knock them down, slow ones push them aside.
func _hit_people() -> void:
	var v := linear_velocity
	for b in hit_area.get_overlapping_bodies():
		if not b.has_method("knockdown"):
			continue
		var rel: Vector3 = b.global_position - global_position
		rel.y = 0.0
		var away := rel.normalized()
		if v.length() > 4.0 and v.dot(away) > 0.0:
			if not b.is_down():
				hit_person.emit(self, b, v.length())
			b.knockdown(v * 0.8 + away * 2.0)
			damage = minf(100.0, damage + 1.0)
		else:
			b.push(away * 2.5)


func _on_body_entered(other: Node) -> void:
	if other.has_method("knock"):
		# street furniture: knock it flying; poles and stalls give way instead of acting
		# like walls, so the car only loses a little speed
		var was_fixed: bool = other.get("breakaway") == true
		other.knock(_prev_vel)
		if was_fixed and _prev_vel.length() > 4.0:
			linear_velocity = _prev_vel * (0.8 if mass < 3000.0 else 0.92)
			apply_damage(_prev_vel.length() * 0.25)
			dent(global_position + _prev_vel.normalized() * 2.0, 0.06)
		return
	# speed just before the hit (by now the collision has already slowed the car)
	var impact := _prev_vel.length()
	if other is RigidBody3D:
		impact = (_prev_vel - (other as RigidBody3D).linear_velocity).length()
	if impact > 6.0:
		apply_damage(impact * 0.8 * clampf(1500.0 / mass, 0.35, 2.0))
		_crash_effects(impact)
		crashed.emit(self, other, impact)


# ------------------------------------------------------------------ damage, fire, explosion
func apply_damage(amount: float) -> void:
	if wrecked:
		return
	damage = minf(100.0, damage + amount)
	_update_smoke()
	if damage >= 100.0 and burning < 0.0:
		burning = BURN_TIME
		_start_fire()


## Where the car was hit: dent the body there, break the lights on a front hit, and
## knock loose parts off on a hard one.
func _crash_effects(impact: float) -> void:
	var p := _contact
	if p == Vector3.ZERO or p.distance_to(global_position) > 6.0:
		p = global_position + linear_velocity.normalized() * 2.0
	var lp := to_local(p)
	dent(p, clampf(impact * 0.012, 0.03, 0.28))
	if lp.z < -1.0 and impact > 12.0 and not lights_broken:
		lights_broken = true
		for l in _lights:
			l.visible = false
	if impact > 15.0 and _detached < 3:
		_detach_part_near(p, impact)


## Pushes the body's vertices near `point` inward (a dent). Each car gets its own copy
## of the meshes the first time it's dented.
func dent(point: Vector3, depth: float) -> void:
	if _glb == null:
		return
	var radius := 0.55 + depth * 2.5
	var centre := global_transform * Vector3(0, 0.8, 0)
	for mi in _parts:
		if not is_instance_valid(mi) or not mi.is_inside_tree():
			continue
		var inv := mi.global_transform.affine_inverse()
		var lp := inv * point
		var lc := inv * centre
		var aabb := mi.get_aabb().grow(radius)
		if not aabb.has_point(lp):
			continue
		if not mi.has_meta("own_mesh"):
			mi.mesh = mi.mesh.duplicate(true)
			mi.set_meta("own_mesh", true)
		var am := mi.mesh as ArrayMesh
		if am == null:
			continue
		# rebuild every surface in order (surface overrides - paint, glass - stay valid)
		var out := ArrayMesh.new()
		for s in am.get_surface_count():
			var mdt := MeshDataTool.new()
			if mdt.create_from_surface(am, s) != OK:
				continue
			for v in mdt.get_vertex_count():
				var vp := mdt.get_vertex(v)
				var d := vp.distance_to(lp)
				if d < radius:
					var k := 1.0 - d / radius
					var dir := (lc - vp).normalized()
					mdt.set_vertex(v, vp + dir * depth * k * k)
			mdt.commit_to_surface(out)
			out.surface_set_material(out.get_surface_count() - 1, am.surface_get_material(s))
		if out.get_surface_count() == am.get_surface_count():
			mi.mesh = out


func _detach_part_near(point: Vector3, impact: float) -> void:
	var best: MeshInstance3D = null
	var bd := 1.6
	for mi in _parts:
		if not is_instance_valid(mi) or mi.get_parent() != _glb:
			continue
		var a := mi.get_aabb()
		var vol := a.size.x * a.size.y * a.size.z
		if vol > 0.5 or vol < 0.002:
			continue            # the main body shell, or tiny bits
		var c := mi.global_transform * a.get_center()
		var d := c.distance_to(point)
		if d < bd:
			bd = d
			best = mi
	_fling_debris(point, impact)
	if best == null:
		return
	_detached += 1
	var a := best.get_aabb()
	var body := RigidBody3D.new()
	body.mass = 20.0
	body.collision_layer = 8
	body.collision_mask = 1 | 4 | 8
	get_parent().add_child(body)
	body.global_transform = best.global_transform * Transform3D(Basis.IDENTITY, a.get_center())
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (a.size * best.global_basis.get_scale()).max(Vector3(0.05, 0.05, 0.05))
	cs.shape = box
	body.add_child(cs)
	var gt := best.global_transform
	best.get_parent().remove_child(best)
	body.add_child(best)
	best.global_transform = gt
	_parts.erase(best)
	body.linear_velocity = linear_velocity * 0.6 + (best.global_position - global_position).normalized() * impact * 0.15 + Vector3.UP * 2.0
	body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	get_tree().create_timer(40.0).timeout.connect(body.queue_free)


## A hard hit throws off a body panel (Kenney Car Kit debris, in this car's paint):
## a bumper from the front or back, a door from the side, sometimes a wheel.
func _fling_debris(point: Vector3, impact: float) -> void:
	var lp := to_local(point)
	var key: String = "bumper" if absf(lp.z) > 1.2 else (["door", "door_window"][randi() % 2])
	if impact > 24.0 and randf() < 0.35:
		key = "tire"
	var node := (DEBRIS[key] as PackedScene).instantiate() as Node3D
	var body := RigidBody3D.new()
	body.mass = 15.0 if key != "tire" else 20.0
	body.collision_layer = 8
	body.collision_mask = 1 | 4 | 8
	get_parent().add_child(body)
	body.global_transform = Transform3D(global_basis, point + Vector3(0, 0.3, 0))
	node.scale = Vector3.ONE * 2.2
	body.add_child(node)
	if paint_color != null and key != "tire" and DisplayServer.get_name() != "headless":
		var m: StandardMaterial3D = Look.paint_material(paint_color)
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = m
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.5, 0.4) if key == "bumper" else (Vector3(0.7, 0.7, 0.3) if key == "tire" else Vector3(1.0, 0.9, 0.12))
	cs.shape = box
	body.add_child(cs)
	body.linear_velocity = _prev_vel * 0.5 + (point - global_position).normalized() * impact * 0.2 + Vector3.UP * 3.0
	body.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	get_tree().create_timer(40.0).timeout.connect(body.queue_free)


## Engine smoke: light grey past 45% damage, thick and dark past 75%.
func _update_smoke() -> void:
	if damage < 45.0 or wrecked:
		return
	if _smoke == null:
		_smoke = CPUParticles3D.new()
		_smoke.amount = 24
		_smoke.lifetime = 1.6
		_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_smoke.emission_box_extents = Vector3(0.4, 0.1, 0.3)
		_smoke.direction = Vector3.UP
		_smoke.spread = 25.0
		_smoke.gravity = Vector3(0, 1.2, 0)
		_smoke.initial_velocity_min = 0.6
		_smoke.initial_velocity_max = 1.4
		_smoke.scale_amount_min = 0.6
		_smoke.scale_amount_max = 1.6
		var q := QuadMesh.new()
		q.size = Vector2(0.7, 0.7)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.vertex_color_use_as_albedo = true
		q.material = m
		_smoke.mesh = q
		_smoke.position = Vector3(0, 1.1, -1.5)
		add_child(_smoke)
	var heavy := damage >= 75.0
	_smoke.color = Color(0.12, 0.12, 0.12, 0.6) if heavy else Color(0.75, 0.75, 0.75, 0.35)
	_smoke.amount = 40 if heavy else 20


## Back to new (the respray shop): fresh body meshes, lights, no smoke.
func repair() -> void:
	damage = 0.0
	burning = -1.0
	lights_broken = false
	if _smoke != null:
		_smoke.queue_free()
		_smoke = null
	if _fire != null:
		_fire.queue_free()
		_fire = null
	if _glb != null and model_scene != null:
		_glb.queue_free()
		_parts.clear()
		_wheel_parts.clear()
		_glb = model_scene.instantiate() as Node3D
		_glb.rotation.y = PI / 2
		model.add_child(_glb)
		_find_parts()
		if paint_color != null:
			set_paint(paint_color)
	_detached = 0


func _start_fire() -> void:
	_fire = CPUParticles3D.new()
	_fire.amount = 40
	_fire.lifetime = 0.8
	_fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_fire.emission_box_extents = Vector3(0.6, 0.2, 1.2)
	_fire.direction = Vector3.UP
	_fire.spread = 15.0
	_fire.gravity = Vector3(0, 2, 0)
	_fire.initial_velocity_min = 1.5
	_fire.initial_velocity_max = 3.0
	_fire.scale_amount_min = 0.5
	_fire.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(1.0, 0.55, 0.15)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.1)
	q.material = m
	_fire.mesh = q
	_fire.position = Vector3(0, 1.3, -1.0)
	add_child(_fire)


func _update_fire(delta: float) -> void:
	if burning < 0.0 or wrecked:
		return
	burning -= delta
	if burning < 0.0:
		explode()


func explode() -> void:
	if wrecked:
		return
	wrecked = true
	burning = -1.0
	siren = false
	controller = null
	if _fire != null:
		_fire.emitting = false
	if _smoke != null:
		_smoke.color = Color(0.08, 0.08, 0.08, 0.7)
		_smoke.amount = 40
	apply_central_impulse(Vector3(0, mass * 6.0, 0))
	apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * 2.0)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.13, 0.12, 0.11)
		dark.roughness = 1.0
		(mi as MeshInstance3D).material_override = dark
	set_headlights(false)
	exploded.emit(self)


# ------------------------------------------------------------------ lights
func set_headlights(on: bool) -> void:
	on = on and not wrecked and not lights_broken and (driven or controller != null)
	if on and _lights.is_empty():
		for x in [-0.6, 0.6]:
			var l := SpotLight3D.new()
			l.position = Vector3(x, 0.8, -2.2)
			l.spot_range = 36.0
			l.spot_angle = 30.0
			l.spot_attenuation = 0.8
			l.light_energy = 2.6
			l.light_volumetric_fog_energy = 2.0    # visible beams in rain / haze (High)
			l.light_color = Color(1.0, 0.96, 0.85)
			add_child(l)
			_lights.append(l)
	for l in _lights:
		l.visible = on


func _add_beacon() -> void:
	_beacon = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.12, 0.25)
	_beacon.mesh = bm
	_beacon.position = Vector3(-0.32, 1.55, 0.2)
	add_child(_beacon)
	var blue := _beacon.duplicate() as MeshInstance3D
	blue.position.x = 0.32
	add_child(blue)
	for pair in [[_beacon, Color(1, 0.15, 0.2)], [blue, Color(0.2, 0.4, 1)]]:
		var m := StandardMaterial3D.new()
		m.albedo_color = pair[1]
		m.emission_enabled = true
		m.emission = pair[1]
		m.emission_energy_multiplier = 0.2
		(pair[0] as MeshInstance3D).material_override = m
		_beacon_mats.append(m)


## Fell out of the world or stuck on the roof: put it back on its wheels.
func _recover(delta: float) -> void:
	if global_position.y < -12.0:
		reset_to(_spawn)
		return
	if global_basis.y.y < 0.35 and linear_velocity.length() < 2.0:
		_upside_t += delta
		if _upside_t > 2.5:
			_upside_t = 0.0
			var yaw := global_rotation.y
			reset_to(Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3(0, 1.2, 0)))
	else:
		_upside_t = 0.0
