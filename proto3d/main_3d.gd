extends Node3D
## Monrovia Life 3D prototype: one district (Downtown / Mamba Point / Waterside /
## Capitol Hill) from the Blender city, dressed with sidewalks, street furniture,
## parked cars and pedestrians; an on-foot player and drivable cars, with a
## third-person / first-person camera (V), entering and leaving cars (F).

const DISTRICT := preload("res://proto3d/models/district_downtown.glb")
const CAR_MODELS := {
	"taxi": preload("res://proto3d/models/veh_taxi.glb"),
	"car": preload("res://proto3d/models/veh_car.glb"),
	"police": preload("res://proto3d/models/veh_police.glb"),
}
const PlayerScript := preload("res://proto3d/player.gd")
const PedScript := preload("res://proto3d/pedestrian.gd")
const CarScript := preload("res://proto3d/car.gd")
const RigScript := preload("res://proto3d/camera_rig.gd")
const HudScript := preload("res://proto3d/hud.gd")
const DresserScript := preload("res://proto3d/street_dresser.gd")
const WALL_SHADER := preload("res://proto3d/walls.gdshader")
const ASPHALT_SHADER := preload("res://proto3d/asphalt.gdshader")
const CONCRETE_SHADER := preload("res://proto3d/concrete.gdshader")
const ROOF_SHADER := preload("res://proto3d/roof.gdshader")

# District placement: map tile (tx, ty) -> world (tx*4 - 188, y, ty*4 - 236).
const TILE := 4.0
const ORIGIN := Vector2(188.0, 236.0)
const HALF_EXTENT := Vector2(140.0, 76.0)
const ENTER_RANGE := 3.4
const PEDESTRIANS := 16

var player
var rig
var hud
var dresser
var car = null                # the car being driven, or null on foot
var cars: Array = []          # every drivable car (spawned + parked)
var peds: Array = []
var ready_done := false
var _entering := 0.0
var _enter_target = null


static func tile_pos(tx: float, ty: float, y: float = 1.5) -> Vector3:
	return Vector3(tx * TILE - ORIGIN.x, y, ty * TILE - ORIGIN.y)


func _ready() -> void:
	_setup_input()
	_build_environment()
	_build_city()
	rig = RigScript.new()
	add_child(rig)
	player = PlayerScript.new()
	player.rig = rig
	player.spawn_point = tile_pos(35.0, 60.6, 2.0)   # Broad Street, Downtown
	add_child(player)
	player.global_position = player.spawn_point
	rig.yaw = -PI / 2                                  # look east along Broad Street
	rig.follow(player, false)
	player.model.rotation.y = rig.yaw
	_spawn_car("taxi", tile_pos(38.5, 59.3, 0.6), -PI / 2)
	_spawn_car("car", tile_pos(44.0, 59.2, 0.6), -PI / 2)
	_spawn_car("police", tile_pos(30.0, 60.4, 0.6), PI / 2)
	hud = HudScript.new()
	hud.main = self
	add_child(hud)
	# Browsers only allow pointer lock after a click, so on the web wait for the first click.
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Street dressing measures the road surfaces, so it waits for the collision to exist.
	await get_tree().physics_frame
	await get_tree().physics_frame
	dresser = DresserScript.new()
	add_child(dresser)
	dresser.dress()
	cars.append_array(dresser.parked)
	_spawn_pedestrians()
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
	sky_mat.sun_angle_max = 20.0
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
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
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
	if OS.has_feature("web"):               # lighter profile for browsers
		sun.directional_shadow_max_distance = 35.0
		env.fog_density = 0.0018
	add_child(sun)


func _build_city() -> void:
	var city := DISTRICT.instantiate() as Node3D
	city.name = "District"
	add_child(city)
	_restyle(city)
	# Sea floor under the water so you wade rather than fall forever.
	_static_box(Vector3(0, -2.1, 0), Vector3(2400, 1.0, 2400))
	# Invisible walls at the edge of the district.
	var h := 30.0
	_static_box(Vector3(HALF_EXTENT.x + 1, h / 2, 0), Vector3(2, h, HALF_EXTENT.y * 2 + 4))
	_static_box(Vector3(-HALF_EXTENT.x - 1, h / 2, 0), Vector3(2, h, HALF_EXTENT.y * 2 + 4))
	_static_box(Vector3(0, h / 2, HALF_EXTENT.y + 1), Vector3(HALF_EXTENT.x * 2 + 4, h, 2))
	_static_box(Vector3(0, h / 2, -HALF_EXTENT.y - 1), Vector3(HALF_EXTENT.x * 2 + 4, h, 2))


func _static_box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	add_child(body)


## Swap the flat colours from the glTF for richer shaders (walls with windows,
## asphalt, concrete, rusty/zinc roofs) and make the water glossy.
func _restyle(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m == null:
				continue
			var n := m.resource_name
			var sm: ShaderMaterial = null
			if n.begins_with("Wall_") or n in ["LM_Cream", "LM_White", "LM_Brick", "LM_Navy", "LM_Grey"]:
				sm = _shader_mat(WALL_SHADER, "wall_color", m.albedo_color)
			elif n == "Asphalt" or n == "Tarmac":
				sm = _shader_mat(ASPHALT_SHADER, "base_color", m.albedo_color)
			elif n == "Concrete" or n == "BridgeConcrete":
				sm = _shader_mat(CONCRETE_SHADER, "base_color", m.albedo_color.darkened(0.18))
			elif n == "RoofRust" or n == "RoofZinc":
				sm = _shader_mat(ROOF_SHADER, "base_color", m.albedo_color)
				sm.set_shader_parameter("rust", 1.0 if n == "RoofRust" else 0.15)
			if sm != null:
				mi.set_surface_override_material(i, sm)
			elif n == "Ocean" or n == "River":
				var w := m.duplicate() as StandardMaterial3D
				w.roughness = 0.05
				w.metallic_specular = 0.9
				mi.set_surface_override_material(i, w)
	for c in node.get_children():
		_restyle(c)


func _shader_mat(shader: Shader, param: String, col: Color) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = shader
	sm.set_shader_parameter(param, col)
	return sm


func _spawn_car(kind: String, pos: Vector3, heading: float) -> void:
	var c = CarScript.new()
	c.model_scene = CAR_MODELS[kind]
	c.name = "Car_" + kind
	add_child(c)
	c.reset_to(Transform3D(Basis(Vector3.UP, heading), pos))
	cars.append(c)


func _spawn_pedestrians() -> void:
	var paths: Array = dresser.sidewalk_paths
	if paths.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in (PEDESTRIANS if not OS.has_feature("web") else 8):
		var path: PackedVector3Array = paths[rng.randi() % paths.size()]
		var start := rng.randi() % path.size()
		var p = PedScript.new()
		p.setup(path, start, 1000 + i)
		p.main = self
		add_child(p)
		p.global_position = path[start] + Vector3(0, 0.2, 0)
		peds.append(p)


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


## Starts the get-in animation; the player is seated when it finishes.
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


func _physics_process(delta: float) -> void:
	if _entering > 0.0:
		_entering -= delta
		if _entering <= 0.0 and _enter_target != null:
			enter_car(_enter_target)


func _unhandled_input(event: InputEvent) -> void:
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
