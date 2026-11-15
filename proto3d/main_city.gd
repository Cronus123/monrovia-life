extends Node3D
## Monrovia Life: 1:1 central Monrovia (Mamba Point to Sinkor) built from OpenStreetMap.
## The world streams in 256 m tiles around the player or car (world_streamer.gd); the
## player, cars, pedestrians, cameras and physics are the same as the district prototype.
## Map data (c) OpenStreetMap contributors, ODbL.

const PlayerScript := preload("res://proto3d/player.gd")
const PedScript := preload("res://proto3d/pedestrian.gd")
const CarScript := preload("res://proto3d/car.gd")
const RigScript := preload("res://proto3d/camera_rig.gd")
const HudScript := preload("res://proto3d/hud.gd")
const StreamerScript := preload("res://proto3d/world_streamer.gd")
const CAR_MODELS := {
	"taxi": preload("res://proto3d/models/veh_taxi.glb"),
	"car": preload("res://proto3d/models/veh_car.glb"),
	"suv": preload("res://proto3d/models/veh_suv.glb"),
	"police": preload("res://proto3d/models/veh_police.glb"),
}
const ENTER_RANGE := 3.4
const PEDESTRIANS := 16
const PARKED := 8
const PEOPLE_RADIUS := 160.0      # pedestrians live within this distance of the player
const PARKED_RADIUS := 200.0

var streamer
var player
var rig
var hud
var car = null
var cars: Array = []              # drivable cars near the player (the player's car first)
var peds: Array = []
var ready_done := false
var _entering := 0.0
var _enter_target = null
var _water: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _people_t := 0.0


func _ready() -> void:
	_rng.seed = 2026
	_setup_input()
	_build_environment()
	streamer = StreamerScript.new()
	add_child(streamer)
	var spawn: Vector3 = streamer.spawn_point()
	streamer.focus = spawn
	rig = RigScript.new()
	add_child(rig)
	player = PlayerScript.new()
	player.rig = rig
	player.spawn_point = spawn
	hud = HudScript.new()
	hud.main = self
	hud.credits = String(streamer.manifest["credits"])
	add_child(hud)
	_add_landmark_labels()
	# Wait for the ground around the spawn before dropping the player in.
	while not streamer.is_area_ready(spawn, 140.0):
		await get_tree().process_frame
	add_child(player)
	player.global_position = spawn
	rig.yaw = 0.0
	rig.follow(player, false)
	_spawn_start_car(spawn)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_done = true


# ------------------------------------------------------------------ setup
func _setup_input() -> void:
	var keys := {
		"p3_forward": [KEY_W, KEY_UP], "p3_back": [KEY_S, KEY_DOWN], "p3_left": [KEY_A, KEY_LEFT],
		"p3_right": [KEY_D, KEY_RIGHT], "p3_sprint": [KEY_SHIFT], "p3_jump": [KEY_SPACE],
		"p3_interact": [KEY_F], "p3_camera": [KEY_V],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#2f6fb3")
	sky_mat.sky_horizon_color = Color("#a9cbe0")
	sky_mat.ground_horizon_color = Color("#a9cbe0")
	sky_mat.ground_bottom_color = Color("#1d5e86")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color("#bcd3e2")
	env.fog_density = 0.0006          # the low-detail ring fades out around 1.3 km
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	# Endless sea at y = 0 that follows the player, with a sea floor to stand on.
	_water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, 6000)
	_water.mesh = plane
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("#1d6e9e")
	wm.roughness = 0.08
	wm.metallic_specular = 0.9
	_water.material_override = wm
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	var floor_body := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var wb := WorldBoundaryShape3D.new()
	wb.plane = Plane(Vector3.UP, -1.6)
	fs.shape = wb
	floor_body.add_child(fs)
	add_child(floor_body)
	# Invisible walls at the edge of the built area.
	var b: Array = []
	if FileAccess.file_exists("res://proto3d/city/manifest.json"):
		b = JSON.parse_string(FileAccess.get_file_as_string("res://proto3d/city/manifest.json"))["bounds"]
	if b.size() == 4:
		var cx: float = (b[0] + b[2]) / 2.0
		var cz: float = (b[1] + b[3]) / 2.0
		var sx: float = b[2] - b[0]
		var sz: float = b[3] - b[1]
		for w in [[Vector3(b[0] - 1, 50, cz), Vector3(2, 100, sz)], [Vector3(b[2] + 1, 50, cz), Vector3(2, 100, sz)],
				[Vector3(cx, 50, b[1] - 1), Vector3(sx, 100, 2)], [Vector3(cx, 50, b[3] + 1), Vector3(sx, 100, 2)]]:
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = w[1]
			cs.shape = box
			body.add_child(cs)
			body.position = w[0]
			add_child(body)


func _add_landmark_labels() -> void:
	for L in streamer.manifest["landmarks"]:
		var lab := Label3D.new()
		lab.text = String(L["name"]).to_upper()
		lab.font_size = 96
		lab.pixel_size = 0.03
		lab.outline_size = 18
		lab.outline_modulate = Color(0.05, 0.08, 0.15)
		lab.modulate = Color("#ffe9a8")
		lab.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lab.visibility_range_end = 900.0
		var p: Array = L["pos"]
		lab.position = Vector3(p[0], p[1] + 24.0, p[2])
		add_child(lab)


func _spawn_start_car(at: Vector3) -> void:
	var spots: Array = streamer.nearby(at, 120.0, "parking")
	var best = null
	var bd := INF
	for s in spots:
		var d := Vector3(s[0], s[1], s[2]).distance_to(at)
		if d < bd and d > 4.0:
			bd = d
			best = s
	var c = _make_car("taxi")
	if best != null:
		c.reset_to(Transform3D(Basis(Vector3.UP, best[3]), Vector3(best[0], best[1] + 0.3, best[2])))
	else:
		c.reset_to(Transform3D(Basis.IDENTITY, at + Vector3(4.0, 0.5, 0.0)))
	c.set_meta("keep", true)


func _make_car(kind: String):
	var c = CarScript.new()
	c.model_scene = CAR_MODELS[kind]
	add_child(c)
	cars.append(c)
	return c


# ------------------------------------------------------------------ people and parked cars near the player
func _manage_population() -> void:
	var p: Vector3 = car.global_position if car != null else player.global_position
	# pedestrians: recycle the far ones onto sidewalks near the player
	var paths: Array = streamer.nearby(p, PEOPLE_RADIUS, "paths")
	for ped in peds.duplicate():
		if ped.global_position.distance_to(p) > PEOPLE_RADIUS + 60.0 or ped.global_position.y < -5.0:
			peds.erase(ped)
			ped.queue_free()
	var tries := 0
	while peds.size() < PEDESTRIANS and not paths.is_empty() and tries < 6:
		tries += 1
		var raw: Array = paths[_rng.randi() % paths.size()]
		var path := PackedVector3Array()
		for q in raw:
			path.append(Vector3(q[0], q[1], q[2]))
		var start := _rng.randi() % path.size()
		if path[start].distance_to(p) < 25.0 or path[start].distance_to(p) > PEOPLE_RADIUS:
			continue
		var ped = PedScript.new()
		ped.setup(path, start, _rng.randi())
		ped.main = self
		add_child(ped)
		ped.global_position = path[start] + Vector3(0, 0.3, 0)
		peds.append(ped)
	# parked cars
	for c in cars.duplicate():
		if c == car or c.has_meta("keep"):
			continue
		if c.global_position.distance_to(p) > PARKED_RADIUS + 60.0:
			cars.erase(c)
			c.queue_free()
	var spots: Array = streamer.nearby(p, PARKED_RADIUS, "parking")
	tries = 0
	while cars.size() < PARKED + 1 and not spots.is_empty() and tries < 4:
		tries += 1
		var s: Array = spots[_rng.randi() % spots.size()]
		var at := Vector3(s[0], s[1] + 0.3, s[2])
		if at.distance_to(p) < 40.0:
			continue
		var taken := false
		for c in cars:
			if c.global_position.distance_to(at) < 6.0:
				taken = true
		if taken:
			continue
		var c = _make_car(["taxi", "car", "suv", "car"][_rng.randi() % 4])
		c.reset_to(Transform3D(Basis(Vector3.UP, s[3]), at))


# ------------------------------------------------------------------ play
func nearest_car():
	var best = null
	var bd := ENTER_RANGE
	for c in cars:
		var d: float = (c.global_position - player.global_position).length()
		if d < bd:
			bd = d
			best = c
	return best


func begin_enter(c) -> void:
	if _entering > 0.0 or c == null:
		return
	_enter_target = c
	_entering = 0.45
	player.body.play("get_in")
	var to: Vector3 = c.global_position - player.global_position
	player.model.rotation.y = atan2(-to.x, -to.z)


func enter_car(c) -> void:
	_entering = 0.0
	_enter_target = null
	car = c
	car.driven = true
	car.sleeping = false
	car.set_meta("keep", true)
	player.set_active(false)
	rig.follow(car, true)


func exit_car() -> void:
	if car == null or absf(car.speed) > 4.0:
		return
	var c = car
	c.driven = false
	car = null
	player.global_position = c.exit_point()
	player.set_active(true)
	player.model.rotation.y = c.global_rotation.y
	rig.follow(player, false)


func _process(delta: float) -> void:
	if not ready_done:
		return
	var focus: Vector3 = car.global_position if car != null else player.global_position
	streamer.focus = focus
	_water.global_position = Vector3(snappedf(focus.x, 50.0), 0.0, snappedf(focus.z, 50.0))
	_people_t -= delta
	if _people_t <= 0.0:
		_people_t = 0.5
		_manage_population()


func _physics_process(delta: float) -> void:
	if _entering > 0.0:
		_entering -= delta
		if _entering <= 0.0 and _enter_target != null:
			enter_car(_enter_target)


func _unhandled_input(event: InputEvent) -> void:
	if not ready_done:
		return
	if event.is_action_pressed("p3_camera"):
		rig.toggle_view()
	elif event.is_action_pressed("p3_interact"):
		if car != null:
			exit_car()
		elif not player.is_down():
			begin_enter(nearest_car())
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
