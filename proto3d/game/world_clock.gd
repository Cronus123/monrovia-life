class_name WorldClock
extends Node
## Time of day and weather. Game time runs at 2 game minutes per real second (as in the
## 2D game). Drives the sun, sky and ambient light, the street lights (a pool of real
## lights moved to the nearest lamps, plus glowing lamp heads), car headlights, and
## rain (a 40% chance each day, for 1.5-4 hours).

const MINUTES_PER_SECOND := 2.0
const LAMP_LIGHTS := 10

var state: GameState
var sun: DirectionalLight3D
var env: Environment
var sky: ShaderMaterial
var water: ShaderMaterial          # ocean surface (choppier in rain)
var wet := 0.0                      # how wet the streets are: rises in rain, dries slowly
var _cloud_t := 0.0
var streamer                         # world_streamer.gd (lamp positions, glow material)
var focus := Vector3.ZERO
var paused := false
var rng := RandomNumberGenerator.new()
var _lamps: Array[OmniLight3D] = []
var _rain: CPUParticles3D
var _last_day := -1
var _lamp_t := 0.0


func setup(game_state: GameState, sun_light: DirectionalLight3D, environment: Environment, world_streamer) -> void:
	state = game_state
	sun = sun_light
	env = environment
	sky = env.sky.sky_material as ShaderMaterial
	streamer = world_streamer
	for i in LAMP_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.85, 0.6)
		l.omni_range = 18.0
		l.light_energy = 0.0          # always visible (energy 0 by day): no shader recompiles at dusk
		add_child(l)
		_lamps.append(l)
	_rain = CPUParticles3D.new()
	_rain.amount = 1600
	_rain.lifetime = 0.9
	_rain.emitting = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(28, 1, 28)
	_rain.direction = Vector3(0.1, -1, 0)
	_rain.spread = 2.0
	_rain.gravity = Vector3(0, -30, 0)
	_rain.initial_velocity_min = 16.0
	_rain.initial_velocity_max = 20.0
	var drop := QuadMesh.new()
	drop.size = Vector2(0.02, 0.5)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(0.8, 0.85, 0.95, 0.45)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = dm
	_rain.mesh = drop
	add_child(_rain)
	rng.seed = 99
	_apply()


## 0 = full day, 1 = full night.
func darkness() -> float:
	var h := state.minute_of_day() / 60.0
	if h >= 7.0 and h < 17.5:
		return 0.0
	if h >= 17.5 and h < 19.5:
		return (h - 17.5) / 2.0
	if h >= 5.0 and h < 7.0:
		return (7.0 - h) / 2.0
	return 1.0


func rain_amount() -> float:
	if state.time_min < state.rain_from or state.time_min > state.rain_until:
		return 0.0
	return clampf(minf(state.time_min - state.rain_from, state.rain_until - state.time_min) / 25.0, 0.0, 1.0)


func advance(minutes: float) -> void:
	state.time_min += minutes
	_roll_weather()
	_apply()


func _roll_weather() -> void:
	if state.day() == _last_day:
		return
	_last_day = state.day()
	if rng.randf() < 0.4:
		state.rain_from = (state.day() - 1) * 1440.0 + rng.randf_range(8.0, 18.0) * 60.0
		state.rain_until = state.rain_from + rng.randf_range(90.0, 240.0)


func _process(delta: float) -> void:
	if state == null:
		return
	if not paused:
		state.time_min += delta * MINUTES_PER_SECOND
		_roll_weather()
	_cloud_t += delta * (1.0 + rain_amount() * 2.0)
	var ra := rain_amount()
	wet = move_toward(wet, 1.0, delta * 0.08) if ra > 0.3 else move_toward(wet, 0.0, delta * 0.004)
	_apply()
	_lamp_t -= delta
	if _lamp_t <= 0.0:
		_lamp_t = 0.5
		_place_lamps()
	_rain.global_position = focus + Vector3(0, 14, 0)


func _apply() -> void:
	var dk := darkness()
	var ra := rain_amount()
	var h := state.minute_of_day() / 60.0
	# sun arc: rises in the east around 6:30, sets in the west around 18:30
	var arc := clampf((h - 6.5) / 12.0, 0.0, 1.0)
	# light points west in the morning (sun in the east), east in the evening
	sun.rotation = Vector3(-deg_to_rad(12.0 + sin(arc * PI) * 58.0), deg_to_rad(90.0 - arc * 180.0), 0)
	sun.light_energy = lerpf(1.55, 0.22, dk) * (1.0 - ra * 0.55)        # moonlight at night
	sun.light_color = Color(1.0, 0.94, 0.84).lerp(Color(1.0, 0.65, 0.4), clampf(absf(arc - 0.5) * 2.0 - 0.6, 0.0, 1.0) * 2.0).lerp(Color(0.55, 0.65, 1.0), dk)
	# the sun stays on (at zero energy at night) so the renderer never switches shader variants
	# by day the sky lights the scene; at night a soft blue moonlit ambient takes over
	env.ambient_light_sky_contribution = lerpf(0.45, 0.0, dk)
	env.ambient_light_color = Color("#d9cfc0").lerp(Color(0.36, 0.42, 0.62), dk)
	env.ambient_light_energy = lerpf(0.55, 0.75, dk) * (1.0 - ra * 0.25)
	var night_top := Color("#0b1433")
	var night_hor := Color("#26304f")
	var rain_top := Color("#6e7a86")
	var sunset := clampf(absf(arc - 0.5) * 2.0 - 0.7, 0.0, 0.3) / 0.3 * (1.0 - dk * 0.6)
	sky.set_shader_parameter("top_color", Color("#2f6fb3").lerp(rain_top, ra * 0.8).lerp(night_top, dk))
	sky.set_shader_parameter("horizon_color", Color("#a9cbe0").lerp(Color("#e8a77a"), sunset * 0.6).lerp(Color("#9aa4ad"), ra * 0.8).lerp(night_hor, dk))
	sky.set_shader_parameter("ground_color", Color("#1d5e86").lerp(Color("#0a1424"), dk))
	sky.set_shader_parameter("night", dk)
	sky.set_shader_parameter("rain", ra)
	sky.set_shader_parameter("sunset", sunset)
	sky.set_shader_parameter("cloud_time", _cloud_t)
	if water != null:
		water.set_shader_parameter("choppy", ra * 0.8)
	if streamer != null and streamer._mats.has("Foliage"):
		(streamer._mats["Foliage"] as ShaderMaterial).set_shader_parameter("wind", 0.8 + ra * 1.6)
	if streamer != null:
		for n in ["Terrain", "Road", "Sidewalk", "Roof"]:
			if streamer._mats.has(n):
				(streamer._mats[n] as ShaderMaterial).set_shader_parameter("wetness", wet)
	env.fog_light_color = Color("#bcd3e2").lerp(Color("#8d969e"), ra).lerp(Color("#1a2236"), dk)
	env.fog_density = 0.0006 + ra * 0.004
	_rain.emitting = ra > 0.05
	if streamer != null and streamer._mats.has("Glow"):
		var g: StandardMaterial3D = streamer._mats["Glow"]
		g.emission_energy_multiplier = lerpf(0.0, 3.0, dk)
	if streamer != null and streamer._mats.has("Wall"):
		(streamer._mats["Wall"] as ShaderMaterial).set_shader_parameter("night_windows", dk * 1.6)
	get_tree().call_group("cars", "set_headlights", dk > 0.35 or ra > 0.6)


func _place_lamps() -> void:
	var dk := darkness()
	if dk < 0.25 or streamer == null:
		for l in _lamps:
			l.light_energy = 0.0
		return
	var near: Array = []
	for p in streamer.nearby(focus, 120.0, "lamps"):
		var v := Vector3(p[0], p[1], p[2])
		near.append([v.distance_squared_to(focus), v])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in _lamps.size():
		var l := _lamps[i]
		if i < near.size():
			l.global_position = near[i][1] - Vector3(0, 0.3, 0)
			l.light_energy = dk * 1.6
		else:
			l.light_energy = 0.0
