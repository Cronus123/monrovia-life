class_name GameSettings
extends RefCounted
## Player settings, saved to user://settings.cfg and applied at start-up:
## audio volumes per bus, display (resolution, fullscreen, V-sync), gameplay (mouse
## sensitivity, invert Y, field of view), a graphics quality preset, and key bindings.

const PATH := "user://settings.cfg"
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const QUALITY := ["Low", "Medium", "High"]

var master := 1.0
var music := 0.7
var sfx := 0.9
var ambience := 0.8
var resolution := Vector2i(1280, 720)
var fullscreen := false
var vsync := true
var sensitivity := 1.0
var invert_y := false
var fov := 70.0
var quality := 1                  # 0 low, 1 medium, 2 high
var bindings := {}                # action -> keyboard/mouse spec ("key:W" / "mouse:1")


func load_file(path: String = PATH) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	master = cf.get_value("audio", "master", master)
	music = cf.get_value("audio", "music", music)
	sfx = cf.get_value("audio", "sfx", sfx)
	ambience = cf.get_value("audio", "ambience", ambience)
	resolution = cf.get_value("display", "resolution", resolution)
	fullscreen = cf.get_value("display", "fullscreen", fullscreen)
	vsync = cf.get_value("display", "vsync", vsync)
	quality = cf.get_value("display", "quality", quality)
	sensitivity = cf.get_value("gameplay", "sensitivity", sensitivity)
	invert_y = cf.get_value("gameplay", "invert_y", invert_y)
	fov = cf.get_value("gameplay", "fov", fov)
	bindings = cf.get_value("controls", "bindings", {})


func save_file(path: String = PATH) -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master)
	cf.set_value("audio", "music", music)
	cf.set_value("audio", "sfx", sfx)
	cf.set_value("audio", "ambience", ambience)
	cf.set_value("display", "resolution", resolution)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("display", "vsync", vsync)
	cf.set_value("display", "quality", quality)
	cf.set_value("gameplay", "sensitivity", sensitivity)
	cf.set_value("gameplay", "invert_y", invert_y)
	cf.set_value("gameplay", "fov", fov)
	cf.set_value("controls", "bindings", bindings)
	cf.save(path)


## Applies everything that doesn't need the game world (audio, display, key bindings).
func apply_system() -> void:
	GameAudio.ensure_buses()
	_bus("Master", master)
	_bus("Music", music)
	_bus("SFX", sfx)
	_bus("Ambience", ambience)
	_bus("Voice", sfx)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		if fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
	InputDefaults.ensure()
	for action in bindings:
		set_binding(action, String(bindings[action]), false)


## Applies the in-world settings: camera and graphics quality.
func apply_world(main) -> void:
	main.rig.sensitivity = sensitivity
	main.rig.invert_y = invert_y
	main.rig.cam.fov = fov
	var sun: DirectionalLight3D = main._sun
	match quality:
		0:
			sun.shadow_enabled = false
			main.streamer.hi_radius = 360.0
			main.streamer.lo_radius = 900.0
			main.traffic.max_cars = 10
		1:
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 70.0
			main.streamer.hi_radius = 420.0
			main.streamer.lo_radius = 1300.0
			main.traffic.max_cars = 16
		2:
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 110.0
			main.streamer.hi_radius = 480.0
			main.streamer.lo_radius = 1700.0
			main.traffic.max_cars = 20
	main.get_viewport().msaa_3d = Viewport.MSAA_2X if quality == 2 else Viewport.MSAA_DISABLED


func _bus(name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


## Replaces the keyboard/mouse event of an action, keeping its gamepad events.
func set_binding(action: String, spec: String, remember: bool = true) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			InputMap.action_erase_event(action, e)
	var ev := InputDefaults.make_event(spec)
	if ev != null:
		InputMap.action_add_event(action, ev)
	if remember:
		bindings[action] = spec


func reset_bindings() -> void:
	bindings = {}
	InputDefaults.reset()


static func spec_for(event: InputEvent) -> String:
	if event is InputEventKey:
		return "key:" + OS.get_keycode_string((event as InputEventKey).physical_keycode)
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	return ""
