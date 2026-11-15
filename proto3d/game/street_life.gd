extends Node
## Ambient street life around the player (visual characters, no physics, within a budget):
##   sellers   behind market stalls (calling out, chatting)
##   groups    two or three people talking outside shops (fewer at night, none in rain)
##   football  kids kicking a ball about on open green ground (daytime, dry weather)
## Scenes appear within ~110 m of the player and are cleared beyond ~170 m. Positions come
## from the city tile data (stalls and shops in the tile meta, green "grass" spots).

const CharacterScript := preload("res://proto3d/character.gd")
const NEAR := 110.0
const FAR := 170.0
const MAX_PEOPLE := 16
const KID_SCALE := 0.72

var main
var scenes := {}                  # key -> {"people": [...], "kind": String, "pos": Vector3, "ball": RigidBody3D}
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _queue: Array = []            # [scene key, member]: people are placed one per frame
var _pool: Array = []             # hidden, ready-built characters (building one costs ~25 ms)
var _pool_t := 0.0


func setup(main_node) -> void:
	main = main_node
	_rng.seed = 9090
	# build everyone now, while the game is loading, and reuse them (no hitches in play)
	for i in MAX_PEOPLE:
		var c = CharacterScript.new()
		c.set_outfit(CharacterScript.random_outfit(_rng, _rng.randf() < 0.5))
		add_child(c)
		_park(c)


func people_count() -> int:
	var n := _queue.size()
	for k in scenes:
		n += (scenes[k]["people"] as Array).size()
	return n


func _process(delta: float) -> void:
	if main == null or not main.ready_done:
		return
	_update_football(delta)
	# build the pool slowly in quiet moments (one person every half second)
	_pool_t -= delta
	if _pool_t <= 0.0 and _pool.size() + _in_use() < MAX_PEOPLE:
		_pool_t = 0.5
		var c = CharacterScript.new()
		c.set_outfit(CharacterScript.random_outfit(_rng, _rng.randf() < 0.5))
		add_child(c)
		_park(c)
	if not _queue.is_empty() and not _pool.is_empty():
		var job: Array = _queue.pop_front()
		if scenes.has(job[0]):
			_build_person(job[0], job[1])
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	var p: Vector3 = main.focus_pos()
	# clear far scenes
	for k in scenes.keys():
		if (scenes[k]["pos"] as Vector3).distance_to(p) > FAR:
			_clear(k)
	var day: float = 1.0 - main.clock.darkness()
	var rain: float = main.clock.rain_amount()
	# rain sends groups and footballers home
	if rain > 0.3:
		for k in scenes.keys():
			if scenes[k]["kind"] in ["group", "football"]:
				_clear(k)
	if people_count() >= MAX_PEOPLE:
		return
	# sellers at stalls (any time but deep night)
	if day > 0.15:
		for s in main.streamer.nearby(p, NEAR, "props"):
			if String(s[3]) != "stall":
				continue
			var at := Vector3(s[0], s[1], s[2])
			var key := "stall:%d:%d" % [int(at.x), int(at.z)]
			if scenes.has(key) or at.distance_to(p) < 20.0:
				continue
			var back := Basis(Vector3.UP, float(s[4])) * Vector3(0, 0, 1.0)      # behind the table, away from the road
			_spawn_scene(key, "seller", at, [[at + back, float(s[4]) + PI, "ual/Idle_Talking", 1.0]])
			if people_count() >= MAX_PEOPLE:
				return
	# chatting groups outside shops (daytime, dry)
	if day > 0.5 and rain < 0.3:
		var shops: Array = main.streamer.nearby(p, NEAR, "shops")
		var made := 0
		for s in shops:
			var key := "group:%d:%d" % [int(s[0]), int(s[2])]
			if scenes.has(key) or made >= 2 or _rng.randf() > 0.25:
				continue
			var wall := Vector3(s[0], s[1] - 3.65, s[2])
			var out := Basis(Vector3.UP, float(s[3])) * Vector3(0, 0, 1)
			var c := wall + out * 2.2
			if c.distance_to(p) < 15.0:
				continue
			var ground := _ground(c)
			if ground == INF:
				continue
			c.y = ground
			var n := 2 + _rng.randi() % 2
			var members := []
			for i in n:
				var a := TAU * i / n + _rng.randf() * 0.3
				var at := c + Vector3(cos(a), 0, sin(a)) * 0.75
				members.append([at, atan2(at.x - c.x, at.z - c.z), "ual/Idle_Talking", 1.0])
			_spawn_scene(key, "group", c, members)
			made += 1
			if people_count() >= MAX_PEOPLE:
				return
	# a football game on open ground (daytime, dry, one at a time)
	if day > 0.6 and rain < 0.1 and not scenes.keys().any(func(k): return scenes[k]["kind"] == "football"):
		var spot := _open_ground(p)
		if spot != Vector3.INF:
			var kids := []
			for i in 4:
				var a := TAU * i / 4.0
				kids.append([spot + Vector3(cos(a) * 4.0, 0, sin(a) * 4.0), a, "", KID_SCALE])
			_spawn_scene("football:%d:%d" % [int(spot.x), int(spot.z)], "football", spot, kids)
			_add_ball(scenes.keys().back(), spot)


## The densest cluster of green "grass" spots near the player, if it's open enough.
func _open_ground(p: Vector3) -> Vector3:
	var grass: Array = main.streamer.nearby(p, NEAR, "grass")
	if grass.size() < 20:
		return Vector3.INF
	var best := Vector3.INF
	var bn := 0
	for i in mini(grass.size(), 60):
		var g: Array = grass[_rng.randi() % grass.size()]
		var gp := Vector3(g[0], g[1], g[2])
		if gp.distance_to(p) < 30.0:
			continue
		var n := 0
		for h in grass:
			if Vector2(h[0] - gp.x, h[2] - gp.z).length() < 12.0:
				n += 1
		if n > bn:
			bn = n
			best = gp
	return best if bn >= 8 else Vector3.INF


func _ground(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 6, 0), at + Vector3(0, -6, 0), 1)
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(q)
	return INF if hit.is_empty() else (hit.position as Vector3).y


func _spawn_scene(key: String, kind: String, pos: Vector3, members: Array) -> void:
	scenes[key] = {"people": [], "kind": kind, "pos": pos, "ball": null}
	for mbr in members:
		_queue.append([key, mbr])


func _in_use() -> int:
	var n := 0
	for k in scenes:
		n += (scenes[k]["people"] as Array).size()
	return n


func _park(c) -> void:
	c.visible = false
	c.process_mode = Node.PROCESS_MODE_DISABLED
	c.global_position = Vector3(0, -500, 0)
	_pool.append(c)


func _build_person(key: String, mbr: Array) -> void:
	var c = _pool.pop_back()
	c.visible = true
	c.process_mode = Node.PROCESS_MODE_INHERIT
	c.set_outfit(CharacterScript.random_outfit(_rng, _rng.randf() < 0.5))
	c.loop_anim("")
	var at: Vector3 = mbr[0]
	var g := _ground(at)
	c.global_position = Vector3(at.x, g if g != INF else at.y, at.z)
	c.rotation.y = float(mbr[1])
	c.scale = Vector3.ONE * float(mbr[3])
	if String(mbr[2]) != "":
		c.loop_anim.call_deferred(String(mbr[2]))
	(scenes[key]["people"] as Array).append(c)


func _clear(key: String) -> void:
	for c in scenes[key]["people"]:
		if is_instance_valid(c):
			c.scale = Vector3.ONE
			_park(c)
	var b = scenes[key]["ball"]
	if b != null and is_instance_valid(b):
		b.queue_free()
	scenes.erase(key)
	_queue = _queue.filter(func(j): return j[0] != key)


# ------------------------------------------------------------------ football
func _add_ball(key: String, at: Vector3) -> void:
	var ball := RigidBody3D.new()
	ball.mass = 0.45
	ball.collision_layer = 8
	ball.collision_mask = 1 | 4 | 8
	ball.linear_damp = 0.6
	ball.angular_damp = 0.5
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.11
	cs.shape = sp
	ball.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.95, 0.92)
	mi.material_override = m
	ball.add_child(mi)
	add_child(ball)
	var g := _ground(at)
	ball.global_position = Vector3(at.x, (g if g != INF else at.y) + 0.4, at.z)
	scenes[key]["ball"] = ball


## The kid nearest the ball runs to it and kicks it somewhere; the others drift after it.
func _update_football(delta: float) -> void:
	for k in scenes:
		var s: Dictionary = scenes[k]
		if s["kind"] != "football" or s["ball"] == null or not is_instance_valid(s["ball"]):
			continue
		var ball: RigidBody3D = s["ball"]
		var centre: Vector3 = s["pos"]
		if ball.global_position.distance_to(centre) > 18.0:           # rolled away: bring it back
			ball.linear_velocity = (centre - ball.global_position).normalized() * 4.0 + Vector3.UP
		var kids: Array = s["people"]
		var nearest = null
		var nd := INF
		for kid in kids:
			var d: float = (kid as Node3D).global_position.distance_to(ball.global_position)
			if d < nd:
				nd = d
				nearest = kid
		for kid in kids:
			var kp: Vector3 = kid.global_position
			var target: Vector3 = ball.global_position if kid == nearest else ball.global_position + (kp - ball.global_position).normalized() * 5.0
			var to := target - kp
			to.y = 0.0
			var speed := 3.6 if kid == nearest else 1.6
			if to.length() > 0.5:
				var step := to.normalized() * minf(speed * delta, to.length())
				var np := kp + step
				var g := _ground(np)
				kid.global_position = Vector3(np.x, g if g != INF else kp.y, np.z)
				kid.rotation.y = atan2(-to.x, -to.z)
				kid.set_speed(speed)
			else:
				kid.set_speed(0.0)
		if nearest != null and nd < 0.7:
			var dir := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
			ball.linear_velocity = dir * _rng.randf_range(5.0, 9.0) + Vector3.UP * _rng.randf_range(0.5, 2.5)
