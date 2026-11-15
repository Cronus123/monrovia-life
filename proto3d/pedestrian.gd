extends "res://proto3d/walker.gd"
## A pedestrian strolling along a sidewalk path: walks to the end and turns back,
## stops now and then, gives the player room, and runs from fast cars.

var path := PackedVector3Array()
var main                       # main_3d.gd (for the player and cars)
var rng := RandomNumberGenerator.new()
var _i := 0
var _dir := 1
var _pause := 0.0
var _flee := 0.0
var _flee_dir := Vector3.ZERO
var _speed := 1.4
var _female := false
var waiting := false              # hailing a taxi: stands at the kerb and waves
var vendor := false               # pushes a wheelbarrow of goods (set before adding)
var _shelter := Vector3.INF       # where it's waiting out the rain (under a shop awning)
var _rain_t := 0.0


func setup(p: PackedVector3Array, start: int, seed_value: int) -> void:
	path = p
	rng.seed = seed_value
	_female = rng.randf() < 0.5
	_i = clampi(start, 0, path.size() - 1)
	_dir = 1 if rng.randf() < 0.5 else -1
	_speed = rng.randf_range(1.15, 1.6)


func _ready() -> void:
	_setup_walker(CharacterScript.random_outfit(rng, _female))
	collision_mask = 1 | 2 | 4 | 8        # bump into the player and each other too
	spawn_point = path[_i] + Vector3(0, 0.3, 0)
	if vendor:
		_add_barrow()
		body.loop_anim.call_deferred("ual/Push")
		_speed = 1.0


func _physics_process(delta: float) -> void:
	var wish := Vector3.ZERO
	var speed := _speed
	if waiting and not is_down() and _flee <= 0.0:
		walk(Vector3.ZERO, 8.0, delta)
		body.set_speed(0.0)
		return
	_rain_t -= delta
	if _rain_t <= 0.0:
		_rain_t = 1.5
		_check_rain()
	if not is_down() and _shelter != Vector3.INF and _flee <= 0.0:
		# waiting out the rain under an awning
		var to := _shelter - global_position
		to.y = 0.0
		walk(to.normalized() * 2.6 if to.length() > 0.5 else Vector3.ZERO, 8.0, delta)
		if to.length() > 0.5:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(-to.x, -to.z), clampf(delta * 8.0, 0.0, 1.0))
		body.set_speed(Vector2(velocity.x, velocity.z).length())
		return
	if not is_down():
		_watch_traffic()
		if _flee > 0.0:
			_flee -= delta
			wish = _flee_dir * 5.5
		elif _pause > 0.0:
			_pause -= delta
		else:
			var target := path[_i]
			var to := target - global_position
			to.y = 0.0
			if to.length() < 0.6:
				_i += _dir
				if _i < 0 or _i >= path.size():
					_dir = -_dir
					_i = clampi(_i + _dir * 2, 0, path.size() - 1)
					_pause = rng.randf_range(0.5, 3.0)
				elif rng.randf() < 0.02:
					_pause = rng.randf_range(1.0, 4.0)
			else:
				wish = to.normalized() * speed
				# Give the player room: wait if they're right in front.
				var pl = main.player if main != null else null
				if pl != null and pl.active:
					var rel: Vector3 = pl.global_position - global_position
					rel.y = 0.0
					if rel.length() < 1.3 and rel.dot(wish) > 0.0:
						wish = Vector3.ZERO
	walk(wish, 8.0, delta)
	var flat := Vector2(velocity.x, velocity.z)
	if not is_down() and flat.length() > 0.2:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-velocity.x, -velocity.z), clampf(delta * 8.0, 0.0, 1.0))
	body.set_speed(flat.length() if is_on_floor() else 0.0)


## Rain: head for the nearest shop awning (or hurry if there isn't one); back to the
## sidewalk when it stops.
func _check_rain() -> void:
	if main == null or not ("clock" in main) or main.clock == null:
		return
	var raining: bool = main.clock.rain_amount() > 0.3
	if not raining:
		_shelter = Vector3.INF
		return
	if _shelter != Vector3.INF or vendor:
		return
	var best := Vector3.INF
	var bd := 40.0
	for s in main.streamer.nearby(global_position, 40.0, "shops"):
		var out := Basis(Vector3.UP, float(s[3])) * Vector3(0, 0, 1)
		var spot := Vector3(s[0], global_position.y, s[2]) + out * 0.9 + Basis(Vector3.UP, float(s[3])) * Vector3(rng.randf_range(-2.0, 2.0), 0, 0)
		var d := spot.distance_to(global_position)
		if d < bd:
			bd = d
			best = spot
	if best != Vector3.INF:
		_shelter = best
	else:
		_speed = 2.6                                       # no shelter near: hurry


## A wooden wheelbarrow with goods, pushed in front of the vendor.
func _add_barrow() -> void:
	var b := Node3D.new()
	b.position = Vector3(0, 0, -0.9)
	body.add_child(b)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#6b4f33")
	var tray := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.6, 0.25, 0.9)
	tray.mesh = tm
	tray.position = Vector3(0, 0.55, 0)
	tray.material_override = wood
	b.add_child(tray)
	var goods := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.5, 0.2, 0.75)
	goods.mesh = gm
	goods.position = Vector3(0, 0.75, 0)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = [Color("#d9472b"), Color("#f2b632"), Color("#4f9a3a"), Color("#efeadc")][rng.randi() % 4]
	goods.material_override = gmat
	b.add_child(goods)
	var wheel := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.2
	wm.bottom_radius = 0.2
	wm.height = 0.08
	wheel.mesh = wm
	wheel.rotation.z = PI / 2
	wheel.position = Vector3(0, 0.2, -0.45)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.1, 0.1, 0.1)
	wheel.material_override = black
	b.add_child(wheel)


## Run away from gunfire or an explosion at rom.
func scare(from: Vector3) -> void:
	if is_down():
		return
	var away := global_position - from
	away.y = 0.0
	_flee_dir = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
	_flee = 4.0


## Run sideways out of the way of a car coming fast.
func _watch_traffic() -> void:
	if main == null or _flee > 0.0:
		return
	for c in main.cars:
		var v: Vector3 = c.linear_velocity
		if v.length() < 8.0:
			continue
		var rel: Vector3 = global_position - c.global_position
		rel.y = 0.0
		if rel.length() > 14.0 or rel.dot(v) < 0.0:
			continue
		var side := Vector3(-v.z, 0, v.x).normalized()
		_flee_dir = side if rel.dot(side) > 0.0 else -side
		_flee = 1.2
		return
