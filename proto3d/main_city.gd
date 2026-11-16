extends Node3D
## Monrovia Life: the game in 1:1 central Monrovia (Mamba Point to Sinkor), built from
## OpenStreetMap. This scene creates the world (streamed tiles, sea, sky) and the game
## systems, wires them together and handles the player's input. Each system lives in its
## own script under proto3d/game/:
##   game_state (money, health, wanted, weapons, clock data)   world_clock (day/night, rain)
##   road_graph + traffic / traffic_car (moving traffic)      police + cop (wanted response)
##   weapons + effects (shooting, explosions, cash)            shops (shops, rentals, respray, safehouse)
##   taxi_job (side job)    missions (Auntie Musu's story)    save_system    game_hud (HUD, map, menus)
## Map data (c) OpenStreetMap contributors, ODbL.

const PlayerScript := preload("res://proto3d/player.gd")
const PedScript := preload("res://proto3d/pedestrian.gd")
const CarScript := preload("res://proto3d/car.gd")
const RigScript := preload("res://proto3d/camera_rig.gd")
const StreamerScript := preload("res://proto3d/world_streamer.gd")
const BigTalkScript := preload("res://proto3d/game/big_talk.gd")
const VehicleLook := preload("res://proto3d/vehicle_look.gd")
const WheelScript := preload("res://proto3d/game/weapon_wheel.gd")
const StreetLifeScript := preload("res://proto3d/game/street_life.gd")
const PerksScript := preload("res://proto3d/game/perks.gd")
const CAR_MODELS := {
	"taxi": preload("res://proto3d/models/veh_taxi.glb"), "car": preload("res://proto3d/models/veh_car.glb"),
	"suv": preload("res://proto3d/models/veh_suv.glb"), "police": preload("res://proto3d/models/veh_police.glb"),
	"keke": preload("res://proto3d/models/veh_keke.glb"), "sport": preload("res://proto3d/models/veh_sport.glb"),
	"truck": preload("res://proto3d/models/veh_truck.glb"), "van": preload("res://proto3d/models/veh_van.glb"),
	"pickup": preload("res://proto3d/models/veh_pickup.glb"), "minibus": preload("res://proto3d/models/veh_minibus.glb"),
}
const NAMES := {"keke": "keke", "taxi": "taxi", "car": "car", "sport": "sports car", "suv": "SUV", "truck": "truck",
	"police": "police car", "van": "armoured van", "pickup": "pickup", "minibus": "minibus"}
const LINES := ["How da body?", "Ma people! How you doing?", "Ah, the sun hot today oh.", "Rain coming, find shade small.",
	"Keke business moving small small.", "The traffic by Tubman Boulevard... ya!", "Monrovia sweet at night time.",
	"You hear? LibGamer tournament coming soon!", "I beg you, come buy my kala.", "Take your time on that road oh.",
	"Waterside market full today.", "Where you going? Sinkor?", "Hello my friend!", "I just come from Vai Town.",
	"Football at the stadium this weekend!", "Mind yourself, police everywhere today."]
const ENTER_RANGE := 3.4
const PEDESTRIANS := 16
const PARKED := 6
const BACK_HOLD_MS := 450         # gamepad View: tap = map, hold = perk ability
const PEOPLE_RADIUS := 160.0
const PARKED_RADIUS := 200.0

# world
var streamer
var graph := RoadGraph.new()
var rig
var player
var car = null                    # the car the player is driving, or null on foot
var cars: Array = []              # physics cars near the player (parked, police, mission, taken)
var peds: Array = []
var ready_done := false
var auto_start := false           # tests: skip the start menu
var title_mode := false           # run by the title screen (proto3d/title.gd): flyover until a game starts
var flyover_cam: Camera3D = null
var flyover_focus := Vector3.ZERO   # where the world streams around during the flyover
var start_car = null              # the taxi parked by the spawn point
var save_path := SaveSystem.PATH   # tests point this into tests/output
var load_marks := {}              # start-up timings (s), reported by the browser benchmark
# systems
var state := GameState.new()
var clock := WorldClock.new()
var traffic := Traffic.new()
var police := Police.new()
var effects := Effects.new()
var weapons := Weapons.new()
var shops := Shops.new()
var taxi := TaxiJob.new()
var missions := Missions.new()
var hud := GameHud.new()
var audio := GameAudio.new()
var big_talk = BigTalkScript.new()
var wheel = WheelScript.new()          # weapon wheel + weapon widget
var street_life = StreetLifeScript.new()   # stall sellers, chatting groups, kids' football
var perks = PerksScript.new()              # skills that grow with use, unlockable perks
var tutorial := Tutorial.new()            # "Welcome to Monrovia", the first mission on a new game
var bug_report := BugReport.new()         # F8: playtest bug report (saved locally)
var signals := TrafficSignals.new()
var settings := GameSettings.new()
var settings_menu := SettingsMenu.new()

var _entering := 0.0
var _enter_target = null
var _water: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _people_t := 0.0
var _sun: DirectionalLight3D
var _env: Environment
var _busy := false                # respawning
# devices (phone / tablet / desktop, touch / gamepad / keyboard)
var ped_cap := PEDESTRIANS        # fewer people and parked cars in light mode (GameSettings)
var parked_cap := PARKED
var touch_layer: CanvasLayer
var touch: TouchControls
var safe_margins := Vector4.ZERO  # safe area in canvas units (left, top, right, bottom)
var _rotate_hint: Label
var _back_down_ms := -1           # gamepad View held since (ms), -1 when up
var _back_used := false
var _mode_serial := -1            # InputMode.serial last acted on


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 2026
	auto_start = (auto_start or DisplayServer.get_name() == "headless") and not title_mode
	DeviceProfile.detect()                  # phone / tablet / desktop, touch screen
	settings.load_file()
	settings.apply_system()                 # audio buses and volumes, display, key bindings
	_build_environment()
	streamer = StreamerScript.new()
	streamer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(streamer)
	graph.load_file("res://proto3d/city/roads_graph.json")
	var spawn: Vector3 = streamer.spawn_point()
	streamer.focus = spawn
	rig = RigScript.new()
	rig.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(rig)
	player = PlayerScript.new()
	player.rig = rig
	player.spawn_point = spawn
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	# systems
	for s in [state, clock, traffic, signals, police, effects, weapons, shops, taxi, missions, audio]:
		s.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(s)
	clock.setup(state, _sun, _env, streamer)
	clock.water = _water.material_override as ShaderMaterial
	traffic.setup(graph, self, CAR_MODELS)
	signals.setup(graph, traffic)
	traffic.signals = signals
	police.setup(state, graph, self, effects)
	weapons.setup(state, self, police, effects)
	shops.setup(state, self, police)
	taxi.setup(state, self, shops)
	missions.setup(state, self, shops, police)
	hud.credits = String(streamer.manifest["credits"])
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	hud.setup(state, self)
	if title_mode:
		hud.visible = false                 # the title screen covers the loading
	settings_menu.visible = false
	settings_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.add_child(settings_menu)
	_setup_devices()
	audio.process_mode = Node.PROCESS_MODE_ALWAYS
	audio.setup(self)
	effects.audio = audio
	perks.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(perks)
	perks.setup(state, self)
	missions.mission_passed.connect(func(_i): perks.add_rep("mission"))
	big_talk.job_passed.connect(func(_id): perks.add_rep("bigtalk_job"))
	street_life.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(street_life)
	street_life.setup(self)
	wheel.process_mode = Node.PROCESS_MODE_PAUSABLE
	hud.add_child(wheel)
	wheel.setup(self)
	tutorial.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(tutorial)
	tutorial.setup(self)
	bug_report.main = self
	add_child(bug_report)
	big_talk.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(big_talk)
	big_talk.setup(state, self, shops, police)
	missions.mission_passed.connect(func(_i): big_talk._try_advance())
	effects.cash_picked.connect(func(n: int):
		n = int(round(n * (1.0 + perks.effect("hustler", "cash_bonus"))))
		state.add_money(n)
		state.say("+" + GameState.money_text(n), Color("#f5c518"), 1.5))
	state.player_down.connect(down_and_out)
	police.arrested.connect(arrested)
	traffic.car_taken.connect(_on_car_taken)
	hud.menu_closed.connect(func(): get_tree().paused = hud.map_open)
	_add_landmark_labels()
	load_marks["setup_s"] = Time.get_ticks_msec() / 1000.0
	while not streamer.is_area_ready(spawn, 140.0):
		await get_tree().process_frame
	load_marks["area_ready_s"] = Time.get_ticks_msec() / 1000.0
	add_child(player)
	player.global_position = spawn
	player.knocked.connect(func(impulse: Vector3): state.hurt(impulse.length() * 2.5))
	player.drowning.connect(func(amount: float): state.hurt(amount))
	effects.player = player
	rig.follow(player, false)
	# Browser, title screen: shaders compile slowly the first time a page loads, so the
	# warm-up runs behind the menu instead of before it (the menu shows ~30 s sooner).
	var warm_later := OS.has_feature("web") and title_mode
	if not warm_later:
		await _prewarm()
	if OS.has_feature("web"):
		print("Monrovia ready in %.1f s (%.1f MB of city tiles downloaded)" % [Time.get_ticks_msec() / 1000.0, streamer.web_bytes / 1048576.0])
	settings.apply_world(self)
	_spawn_start_car(spawn)
	ready_done = true
	if auto_start:
		new_game()
	elif title_mode:
		_enter_title()
		if warm_later:
			await _prewarm()
			load_marks["warm_s"] = Time.get_ticks_msec() / 1000.0
	else:
		_start_menu()


# ------------------------------------------------------------------ devices
## Touch overlay, UI scale and safe area for the device (DeviceProfile), and the control
## scheme to start with (InputMode). Runs before the city has loaded.
func _setup_devices() -> void:
	touch_layer = CanvasLayer.new()
	touch_layer.layer = 5                      # over the HUD, under menus' own layers
	touch_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	touch_layer.name = "TouchLayer"
	add_child(touch_layer)
	touch = TouchControls.new()
	touch.name = "TouchControls"
	touch.visible = false
	touch_layer.add_child(touch)
	touch.setup(self)
	_rotate_hint = Label.new()
	_rotate_hint.text = "Turn your phone sideways to play"
	_rotate_hint.add_theme_font_size_override("font_size", 22)
	_rotate_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_rotate_hint.add_theme_constant_override("outline_size", 6)
	_rotate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rotate_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rotate_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rotate_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rotate_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rotate_hint.visible = false
	touch_layer.add_child(_rotate_hint)
	if not get_viewport().size_changed.is_connected(apply_device_layout):
		get_viewport().size_changed.connect(apply_device_layout)
	apply_device_layout()


## UI scale (phones and tablets draw the UI bigger), safe-area margins for the HUD and
## the touch controls, the tablet's two-corner touch layout. Re-run on every resize
## (rotating the device, resizing the browser window).
func apply_device_layout() -> void:
	if not is_inside_tree():
		return
	var win := get_tree().root
	if DisplayServer.get_name() != "headless" and not is_equal_approx(win.content_scale_factor, DeviceProfile.ui_scale()):
		win.content_scale_factor = DeviceProfile.ui_scale()
		call_deferred("apply_device_layout")     # the canvas size changes with the scale
	safe_margins = DeviceProfile.safe_margins(get_viewport())
	hud.apply_safe_area(safe_margins)
	if touch != null:
		touch.layout_kind = DeviceProfile.kind
		touch.margins = safe_margins
		touch.relayout()
	if _rotate_hint != null:
		_rotate_hint.visible = DeviceProfile.is_phone() and DeviceProfile.portrait(get_viewport())


func _input(event: InputEvent) -> void:
	InputMode.note(event)                     # follow the last device used (Auto scheme)
	if InputMode.serial != _mode_serial:
		_mode_serial = InputMode.serial
		_on_input_mode_changed()


func _on_input_mode_changed() -> void:
	if touch != null and not InputMode.is_touch():
		touch.release_all()
	if InputMode.is_touch() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# gamepad in a menu: make sure something has focus to move from
	if InputMode.is_pad() and (hud.menu_open or settings_menu.visible) and get_viewport().gui_get_focus_owner() == null:
		for b in (settings_menu if settings_menu.visible else hud).find_children("*", "Button", true, false):
			if (b as Button).is_visible_in_tree() and not (b as Button).disabled:
				(b as Button).grab_focus()
				break


# ------------------------------------------------------------------ title screen
## Behind the title screen: no player, no HUD, a camera the title screen flies around,
## and the city streaming around flyover_focus (traffic and people still live).
func _enter_title() -> void:
	hud.visible = false
	player.set_active(false)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	flyover_cam = Camera3D.new()
	flyover_cam.fov = 60.0
	flyover_cam.far = 2500.0
	add_child(flyover_cam)
	flyover_cam.make_current()
	flyover_focus = player.spawn_point
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## From the title screen: start a new game or continue the saved one.
func start_from_title(continue_saved: bool) -> void:
	title_mode = false
	if flyover_cam != null:
		flyover_cam.queue_free()
		flyover_cam = null
	get_tree().paused = false
	rig.process_mode = Node.PROCESS_MODE_PAUSABLE
	rig.cam.make_current()
	player.set_active(true)
	hud.visible = true
	if continue_saved:
		continue_game()
	else:
		teleport_player(player.spawn_point)
		new_game()


func quit_to_title() -> void:
	save_game()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://proto3d/title.tscn")


# ------------------------------------------------------------------ setup
## Camera exposure: auto exposure on Forward+ (adapts going from shade to sun and at
## night); depth of field stays off.
func apply_camera_effects(quality: int) -> void:
	var attr := CameraAttributesPractical.new()
	attr.dof_blur_far_enabled = false
	attr.dof_blur_near_enabled = false
	if quality >= 1 and RenderingServer.get_current_rendering_method() == "forward_plus":
		attr.auto_exposure_enabled = true
		attr.auto_exposure_scale = 0.35
		attr.auto_exposure_speed = 0.6
		attr.auto_exposure_min_sensitivity = 70.0
		attr.auto_exposure_max_sensitivity = 140.0
	rig.cam.attributes = attr


func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	# the browser build uses lighter versions of the sky and sea (quick to compile in WebGL)
	sky_mat.shader = load("res://proto3d/sky_web.gdshader" if OS.has_feature("web") else "res://proto3d/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.55
	_env.ambient_light_sky_contribution = 0.45       # less blue in the shadows
	_env.ambient_light_color = Color("#d9cfc0")
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = 1.0
	_env.tonemap_white = 8.0
	_env.fog_enabled = true
	_env.fog_light_color = Color("#bcd3e2")
	_env.fog_density = 0.0006
	_env.fog_sky_affect = 0.25
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.1
	_env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.94, 0.84)
	_sun.light_energy = 1.55
	_sun.shadow_enabled = true
	_sun.shadow_bias = 0.04
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 70.0
	add_child(_sun)
	_water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000, 3000)
	plane.subdivide_width = 300          # 10 m: enough for the long swell
	plane.subdivide_depth = 300
	_water.mesh = plane
	var wm := ShaderMaterial.new()
	wm.shader = load("res://proto3d/water_web.gdshader" if OS.has_feature("web") else "res://proto3d/water.gdshader")
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
	var b: Array = JSON.parse_string(FileAccess.get_file_as_string("res://proto3d/city/manifest.json"))["bounds"]
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


## Draws every vehicle model, a headlight, a lamp light, fire and an explosion for a few
## frames, tiny and right in front of the camera, while the game loads. The renderer
## compiles their shaders now instead of stuttering the first time each appears in play.
func _prewarm() -> void:
	var holder := Node3D.new()
	var cam: Camera3D = get_viewport().get_camera_3d()
	(cam if cam != null else rig.cam).add_child(holder)
	holder.position = Vector3(0, 0, -2.0)
	holder.scale = Vector3.ONE * 0.002
	var x := 0.0
	for k in CAR_MODELS:
		var m := (CAR_MODELS[k] as PackedScene).instantiate() as Node3D
		m.position.x = x
		x += 5.0
		holder.add_child(m)
	var spot := SpotLight3D.new()
	spot.light_energy = 0.01
	holder.add_child(spot)
	var omni := OmniLight3D.new()
	omni.light_energy = 0.01
	holder.add_child(omni)
	effects.explosion(holder.global_position)
	var temp = spawn_car("car", Transform3D(Basis.IDENTITY, holder.global_position + Vector3(0, -200, 0)))
	temp.freeze = true
	temp._start_fire()
	temp._fire.reparent(holder, false)
	temp.set_headlights(true)
	for i in 6:
		await get_tree().process_frame
	# (on the title screen New Game can free the flyover camera this hangs from meanwhile)
	if is_instance_valid(temp):
		remove_car(temp)
	if is_instance_valid(holder):
		holder.queue_free()


# ------------------------------------------------------------------ game flow
func _start_menu() -> void:
	var opts := [{"label": "New game"}, {"label": "Settings"}]
	if SaveSystem.has_save():
		opts.append({"label": "Continue"})
	hud.open_menu("MONROVIA LIFE: STREETS", "A LibGamer community game. Steal rides, run jobs for Auntie Musu and stay ahead of the police from Mamba Point to Sinkor. Map data (c) OpenStreetMap contributors.", opts,
		func(i: int):
			if i == 1:
				open_settings(_start_menu)
			elif i == 2:
				continue_game()
			else:
				new_game())
	get_tree().paused = true


func new_game() -> void:
	get_tree().paused = false
	clock.advance(0.0)
	# the tests start straight into the game (auto_start): no tutorial there
	if settings.tutorial and not state.tutorial_done and not auto_start:
		tutorial.start()
		return
	state.tutorial_done = true
	state.say("Welcome home, Kollie. Auntie Musu is waiting at Waterside (M on your map).", Color.WHITE, 7.0)
	state.say("F: take a car   E: use   Mouse: aim and shoot   M: map", Color.WHITE, 7.0)


func continue_game() -> void:
	get_tree().paused = false
	var pos = SaveSystem.load_into(state, save_path)
	clock.advance(0.0)
	if pos != null:
		teleport_player(pos)
	state.say("Welcome back to Monrovia.")
	if not state.tutorial_done and settings.tutorial:
		tutorial.start()                         # saved part-way through it: from the top


func save_game() -> void:
	SaveSystem.save(state, player.global_position if car == null else car.global_position, save_path)


func teleport_player(pos: Vector3) -> void:
	_busy = true
	if car != null:
		exit_car(true)
	streamer.focus = pos
	player.global_position = pos + Vector3(0, 30, 0)
	player.velocity = Vector3.ZERO
	player.set_active(false)
	var guard := 0
	while not streamer.is_area_ready(pos, 120.0) and guard < 900:
		guard += 1
		await get_tree().process_frame
	player.global_position = pos + Vector3(0, 0.5, 0)
	player.set_active(true)
	rig.follow(player, false)
	_busy = false


func down_and_out() -> void:
	var fee := state.charge(int(state.money * 0.1) + 100)
	state.big_text.emit("DOWN AND OUT", Color("#c8173a"))
	state.say("JFK Medical Center patched you up. Hospital bill: " + GameState.money_text(fee), Color.WHITE, 5.0)
	_respawn(shops.place_pos("hospital"))


func arrested() -> void:
	var fee := state.charge(int(state.money * 0.1) + 200)
	state.lose_weapons()
	state.big_text.emit("ARRESTED", Color("#c8173a"))
	state.say("Released from Police HQ. Fine paid: %s. Your weapon was taken." % GameState.money_text(fee), Color.WHITE, 5.0)
	_respawn(shops.place_pos("police_hq"))


func _respawn(at: Vector3) -> void:
	missions.fail("Mission failed.")
	taxi.stop()
	police.clear()
	police.remove_all()
	state.health = 100.0
	state.health_changed.emit(state.health, state.armor)
	clock.advance(120.0)
	teleport_player(at)


# ------------------------------------------------------------------ cars
func vehicle_name(kind: String) -> String:
	return NAMES.get(kind, "car")


func spawn_car(kind: String, t: Transform3D, paint: Variant = "random"):
	var c = CarScript.new()
	c.kind = kind
	c.model_scene = CAR_MODELS.get(kind, CAR_MODELS["car"])
	c.paint_color = VehicleLook.random_paint(kind, _rng) if typeof(paint) == TYPE_STRING else paint
	add_child(c)
	c.reset_to(t)
	c.hit_person.connect(_on_car_hit_person)
	c.crashed.connect(_on_car_crashed)
	c.exploded.connect(_on_car_exploded)
	c.set_headlights(clock.darkness() > 0.35)
	cars.append(c)
	return c


func remove_car(c) -> void:
	if c == null or not is_instance_valid(c) or c == car:
		return
	cars.erase(c)
	c.queue_free()


func _spawn_start_car(at: Vector3) -> void:
	var spots: Array = streamer.nearby(at, 120.0, "parking")
	var best = null
	var bd := INF
	for s in spots:
		var d := Vector3(s[0], s[1], s[2]).distance_to(at)
		if d < bd and d > 4.0:
			bd = d
			best = s
	var t := Transform3D(Basis(Vector3.UP, best[3]), Vector3(best[0], best[1] + 0.3, best[2])) if best != null else Transform3D(Basis.IDENTITY, at + Vector3(4.0, 0.5, 0.0))
	var c = spawn_car("taxi", t)
	c.set_meta("keep", true)
	start_car = c


func rent_vehicle(kind: String, near: Vector3) -> void:
	var n := graph.nearest(near, 2)
	var t := Transform3D(Basis.IDENTITY, near + Vector3(3, 0.6, 0))
	if not n.is_empty():
		var lp: Array = graph.lane_point(n["edge"], 0.0, 1)
		var fwd: Vector3 = lp[1]
		t = Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), (n["pos"] as Vector3) + Vector3(0, 0.6, 0))
	var c = spawn_car(kind, t)
	c.set_meta("keep", true)
	state.say("Your %s is parked by the road. F to get in, T for taxi work." % vehicle_name(kind))


func nearest_car():
	var best = null
	var bd := ENTER_RANGE
	for c in cars:
		if c.wrecked or (c.controller != null and c.kind == "police" and not c.has_meta("cops_out")):
			continue
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
	if c is TrafficCar:
		c = traffic.take(c)
	elif c.kind == "police" and c.controller != null:
		police.cars.erase(c)
		c.siren = false
		police.add_stars(2)
		state.say("You stole a police car!", Color("#ff5a6e"), 3.0)
	audio.play("door", c.global_position, -2.0)
	car = c
	car.driven = true
	car.controller = null
	car.grip_bonus = perks.bonus("driving")
	car.speed_bonus = perks.effect("keke_king", "keke_speed") if car.kind == "keke" else 0.0
	car.sleeping = false
	car.set_meta("keep", true)
	car.set_headlights(clock.darkness() > 0.35)
	player.set_active(false)
	rig.follow(car, true)


func exit_car(force: bool = false) -> void:
	if car == null or (absf(car.speed) > 4.0 and not force):
		return
	var c = car
	c.driven = false
	car = null
	audio.play("door", c.global_position, -2.0)
	player.global_position = c.exit_point()
	player.set_active(true)
	player.model.rotation.y = c.global_rotation.y
	rig.follow(player, false)
	taxi.on_exit_car()
	c.set_headlights(false)


func _on_car_taken(_c, kind: String, was_police: bool) -> void:
	if was_police:
		police.add_stars(2)
		state.say("You stole a police car!", Color("#ff5a6e"), 3.0)
	else:
		state.say("You pulled the driver out and took the %s." % vehicle_name(kind))
		police.crime(1, player.global_position)


func eject_driver(at: Vector3, was_police: bool) -> void:
	var p = PedScript.new()
	p.setup(PackedVector3Array([at]), 0, _rng.randi())
	p.main = self
	add_child(p)
	p.global_position = at
	p.scare(player.global_position)
	peds.append(p)
	if was_police:
		police.add_stars(1)


func _on_car_hit_person(c, person, _spd: float) -> void:
	if c != car:
		return
	if person.get("police") != null:
		police.add_stars(2)
	else:
		police.crime(1, person.global_position)
		if randf() < 0.6:
			effects.drop_cash(person.global_position, randi_range(10, 80))
	scare_people(person.global_position, 12.0)


func _on_car_crashed(c, other, impact: float) -> void:
	audio.play("crash", c.global_position, clampf(-10.0 + impact * 0.6, -10.0, 6.0))
	if c != car:
		return
	rig.shake(clampf(impact / 25.0, 0.15, 1.0))
	if other is TrafficCar:
		var tc: TrafficCar = other
		if tc.kind == "police":
			police.add_stars(1)
		elif impact > 10.0:
			police.crime(1, tc.global_position)
		traffic.to_physics(tc, c.linear_velocity * 0.4)
	elif other.get("kind") == "police":
		police.add_stars(1)


func _on_car_exploded(c) -> void:
	var at: Vector3 = c.global_position
	effects.explosion(at)
	rig.shake(clampf(1.2 - rig.cam.global_position.distance_to(at) / 40.0, 0.0, 1.0))
	scare_people(at, 30.0)
	for w in all_walkers():
		if w != player and w.global_position.distance_to(at) < 6.0:
			w.knockdown((w.global_position - at).normalized() * 6.0)
	for o in cars:
		if o != c and o.global_position.distance_to(at) < 6.0:
			o.apply_damage(60.0)
	if c == car:
		exit_car(true)
		state.hurt(200.0)
	elif player.active and player.global_position.distance_to(at) < 5.0:
		state.hurt(60.0)
	if c.kind == "police":
		police.cars.erase(c)


# ------------------------------------------------------------------ people
func all_walkers() -> Array:
	var out: Array = [player]
	out.append_array(peds)
	out.append_array(police.cops)
	out.append_array(taxi.waiting)
	if tutorial.dummy != null and is_instance_valid(tutorial.dummy):
		out.append(tutorial.dummy)
	return out


func scare_people(at: Vector3, r: float) -> void:
	for p in peds:
		if is_instance_valid(p) and p.global_position.distance_to(at) < r:
			p.scare(at)


## How many people are out on the street: busy mornings and evenings, quiet late at night,
## fewer in heavy rain.
func ped_target() -> int:
	var h: float = state.minute_of_day() / 60.0
	var f := 1.0
	if h < 5.0 or h >= 23.0:
		f = 0.3
	elif h < 7.0 or h >= 21.0:
		f = 0.6
	elif (h >= 7.0 and h < 9.5) or (h >= 16.5 and h < 19.0):
		f = 1.15
	f *= 1.0 - clock.rain_amount() * 0.35
	return clampi(int(round(ped_cap * f)), mini(4, ped_cap), ped_cap + 3)


func _manage_population() -> void:
	var p := focus_pos()
	var paths: Array = streamer.nearby(p, PEOPLE_RADIUS, "paths")
	for ped in peds.duplicate():
		if not is_instance_valid(ped) or ped.global_position.distance_to(p) > PEOPLE_RADIUS + 60.0 or ped.global_position.y < -5.0:
			peds.erase(ped)
			if is_instance_valid(ped):
				ped.queue_free()
	# fewer allowed (light mode switched on, night falling): let the farthest go first
	while peds.size() > ped_target() + 3:
		var far = peds[0]
		for ped in peds:
			if ped.global_position.distance_to(p) > far.global_position.distance_to(p):
				far = ped
		peds.erase(far)
		far.queue_free()
	var tries := 0
	while peds.size() < ped_target() and not paths.is_empty() and tries < 6:
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
		ped.vendor = _rng.randf() < 0.08 and clock.darkness() < 0.5          # pushing a barrow of goods
		add_child(ped)
		ped.global_position = path[start] + Vector3(0, 0.3, 0)
		peds.append(ped)
	for c in cars.duplicate():
		if c == car or (c.has_meta("keep") and bool(c.get_meta("keep"))) or c.controller != null or c.kind == "police":
			continue
		if c.global_position.distance_to(p) > PARKED_RADIUS + 60.0:
			remove_car(c)
	var parked := 0
	for c in cars:
		if c.controller == null and c != car and not c.has_meta("keep"):
			parked += 1
	var spots: Array = streamer.nearby(p, PARKED_RADIUS, "parking")
	tries = 0
	while parked < parked_cap and not spots.is_empty() and tries < 4:
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
		spawn_car(["taxi", "car", "suv", "car", "keke"][_rng.randi() % 5], Transform3D(Basis(Vector3.UP, s[3]), at))
		parked += 1


# ------------------------------------------------------------------ queries used by the HUD and systems
func focus_pos() -> Vector3:
	if flyover_cam != null:
		return flyover_focus
	return car.global_position if car != null else player.global_position


func heading() -> float:
	if car != null:
		return car.global_rotation.y
	return player.model.global_rotation.y if player.model != null and player.model.is_inside_tree() else 0.0


func target_pos():
	if tutorial.active:
		return tutorial.target()
	if missions.active():
		return missions.target()
	if big_talk.active():
		return big_talk.target()
	if taxi.hire:
		return taxi.target()
	return missions.target()


func objective_text() -> String:
	if tutorial.active:
		return tutorial.objective()
	if missions.active():
		return missions.objective()
	if big_talk.active() or big_talk.blocks_missions():
		return big_talk.objective()
	if taxi.hire:
		return taxi.objective()
	return missions.objective()


func prompt_text() -> String:
	if hud.menu_open or hud.map_open or not ready_done:
		return ""
	var s := shops.prompt()
	if s != "":
		return s
	s = big_talk.prompt()
	if s != "":
		return s
	if car != null:
		return "[F] Get out" if absf(car.speed) < 4.0 else ""
	var c = nearest_car()
	if c != null:
		return "[F] Get in the " + vehicle_name(c.kind)
	var t := traffic.nearest_to(player.global_position, ENTER_RANGE + 0.6)
	if t != null:
		return "[F] Take the " + vehicle_name(t.kind)
	return ""


# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	if not ready_done:
		return
	clock.paused = get_tree().paused
	if get_tree().paused:
		return
	var focus := focus_pos()
	streamer.focus = focus
	clock.focus = focus
	signals.focus = focus
	_water.global_position = Vector3(snappedf(focus.x, 50.0), 0.0, snappedf(focus.z, 50.0))
	_people_t -= delta
	if _people_t <= 0.0:
		_people_t = 0.5
		_manage_population()
	if _back_down_ms >= 0 and not _back_used and Time.get_ticks_msec() - _back_down_ms >= BACK_HOLD_MS:
		_back_used = true                       # gamepad View held: perk ability
		perks.use_ability()
	if not title_mode and Input.is_action_pressed("p3_fire") and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.get_connected_joypads().size() > 0 or InputMode.is_touch()):
		if car == null:
			weapons.try_fire()
		else:
			weapons.try_fire_from_car()           # drive-by out of a side window


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	if _entering > 0.0:
		_entering -= delta
		if _entering <= 0.0 and _enter_target != null and is_instance_valid(_enter_target):
			enter_car(_enter_target)


func _unhandled_input(event: InputEvent) -> void:
	if not ready_done or _busy or title_mode:
		return
	if settings_menu.visible:
		if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			settings_menu.close()
		elif event is InputEventJoypadButton and event.is_action_pressed("ui_cancel"):     # gamepad B
			settings_menu.close()
		return
	# gamepad View: a tap opens / closes the map, holding it uses the perk ability
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_BACK and not hud.menu_open:
		var jb := event as InputEventJoypadButton
		if jb.pressed and not jb.is_echo():
			if hud.map_open:
				hud.toggle_map()
				get_tree().paused = false
			else:
				_back_down_ms = Time.get_ticks_msec()
				_back_used = false
		elif not jb.pressed and _back_down_ms >= 0:
			if not _back_used:
				hud.toggle_map()
				get_tree().paused = hud.map_open
			_back_down_ms = -1
		return
	if hud.menu_open:
		if event is InputEventJoypadButton and event.is_action_pressed("ui_cancel"):     # gamepad B
			hud.close_menu()
			get_tree().paused = false
			return
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			var k := (event as InputEventKey).physical_keycode
			if k == KEY_ESCAPE:
				hud.close_menu()
				get_tree().paused = false
			elif k >= KEY_1 and k <= KEY_9:
				hud.choose(k - KEY_1)
				if not hud.menu_open:
					get_tree().paused = false
		return
	if event.is_action_pressed("p3_map"):
		hud.toggle_map()
		get_tree().paused = hud.map_open
		return
	if hud.map_open:
		return
	if event.is_action_pressed("p3_pause"):
		_pause_menu()
	elif event.is_action_pressed("p3_camera"):
		rig.toggle_view()
	elif event.is_action_pressed("p3_interact"):
		if car != null:
			exit_car()
		elif not player.is_down():
			var c = nearest_car()
			if c == null:
				c = traffic.nearest_to(player.global_position, ENTER_RANGE + 0.6)
			begin_enter(c)
	elif event.is_action_pressed("p3_use"):
		if not shops.interact() and not big_talk.interact() and car == null:
			_talk()
	elif event.is_action_pressed("p3_hire"):
		taxi.toggle()
	elif event.is_action_pressed("p3_horn") and car != null:
		audio.horn(car)
	elif event.is_action_pressed("p3_radio") and car != null:
		state.say("Radio: " + audio.next_station(), Color("#8ff0ea"), 2.0)
	elif event.is_action_pressed("p3_ability"):
		perks.use_ability()
	elif event.is_action_pressed("p3_reload") and car == null:
		weapons.start_reload()
	elif event.is_action_pressed("p3_weapon"):
		# next weapon you own
		for k in range(1, GameState.WEAPON_COUNT + 1):
			if state.select_weapon((state.weapon + k) % GameState.WEAPON_COUNT):
				break
	elif event.is_action_pressed("p3_fists"):
		state.select_weapon(GameState.FISTS)
	elif event.is_action_pressed("p3_pistol"):
		_pick(GameState.PISTOL)
	elif event.is_action_pressed("p3_slot_3"):
		_pick(GameState.BAT)
	elif event.is_action_pressed("p3_slot_4"):
		_pick(GameState.MACHETE)
	elif event.is_action_pressed("p3_slot_5"):
		_pick(GameState.SMG)
	elif event.is_action_pressed("p3_slot_6"):
		_pick(GameState.SHOTGUN)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not InputMode.is_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _pick(w: int) -> void:
	if not state.select_weapon(w):
		state.say("You don't have the %s. Buy one at a weapon shop." % String(weapons.defs[w]["name"]).to_lower())


func _talk() -> void:
	for p in peds:
		if p.global_position.distance_to(player.global_position) < 1.8 and not p.is_down():
			var line: String = big_talk.street_line() if _rng.randf() < 0.4 else ""
			if line == "":
				line = LINES[_rng.randi() % LINES.size()]
			state.say("\"%s\"" % line, Color("#f5e9b0"), 3.2)
			return


## Settings screen; ack reopens the menu it came from.
func open_settings(back: Callable) -> void:
	get_tree().paused = true
	hud.menu_open = true
	tutorial._update_ui()                      # hides its panel (it doesn't update while paused)
	settings_menu.open(settings, self)
	if not settings_menu.closed.is_connected(_on_settings_closed):
		settings_menu.closed.connect(_on_settings_closed)
	settings_menu.set_meta("back", back)


func _on_settings_closed() -> void:
	hud.menu_open = false
	var back: Callable = settings_menu.get_meta("back")
	if back.is_valid():
		back.call()


func _pause_menu() -> void:
	get_tree().paused = true
	var opts := [{"label": "Resume"}, {"label": "Settings"}, {"label": "Save game"}, {"label": "Skills & perks"},
		{"label": "Quit to title (saves)"}]
	if not OS.has_feature("web"):
		opts.append({"label": "Quit to desktop (saves)"})      # a browser tab is just closed
	opts.append({"label": "Report a bug"})       # F8 on a keyboard; this is for touch and gamepads
	hud.open_menu("Paused", "Day %d, %s. Missions done: %d of %d." % [state.day(), state.clock_text(), state.mission_idx, missions.list.size()],
		opts, _on_pause_choice)


func _on_pause_choice(i: int) -> void:
	get_tree().paused = false
	if i == (5 if OS.has_feature("web") else 6):
		bug_report.open()
		return
	match i:
		1:
			open_settings(_pause_menu)
		2:
			save_game()
			state.say("Game saved.")
		3:
			_perks_screen()
		4:
			quit_to_title()
		5:
			save_game()
			get_tree().quit()


## Skills (level and progress) and perks (unlocked, or what they still need).
func _perks_screen() -> void:
	get_tree().paused = true
	var lines := PackedStringArray()
	lines.append("Reputation %d   ·   Taxi fares %d" % [state.rep, state.fares])
	lines.append("")
	lines.append("SKILLS (they grow as you use them)")
	for k in perks.data["skills"]:
		var sk: Dictionary = perks.data["skills"][k]
		var prog: Array = perks.xp_to_next(k)
		var lv: int = perks.level(k)
		var bar := ""
		var filled := int(round(float(prog[0]) / maxf(1.0, float(prog[1])) * 10.0)) if lv < 5 else 10
		for i in 10:
			bar += "■" if i < filled else "□"
		lines.append("%s   Lv %d  %s   %s" % [String(sk["name"]), lv, bar, String(sk["text"])])
	lines.append("")
	lines.append("PERKS")
	for p in perks.data["perks"]:
		var got: bool = perks.has(String(p["id"]))
		lines.append(("✔ %s: %s" if got else "✖ %s: needs %s") % [String(p["name"]), String(p["text"]) if got else perks.needs_text(p)])
	hud.open_menu("Skills & perks", "\n".join(lines), [{"label": "Back"}], func(_i): _pause_menu())


func _exit_tree() -> void:
	VehicleLook.release()


