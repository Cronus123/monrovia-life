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
	main.rig.base_fov = fov
	main.rig.motion_blur = quality >= 1
	var sun: DirectionalLight3D = main._sun
	var env: Environment = main._env
	var fplus := RenderingServer.get_current_rendering_method() == "forward_plus"
	match quality:
		0:
			sun.shadow_enabled = false
			main.streamer.hi_radius = 360.0
			main.streamer.lo_radius = 900.0
			main.streamer.detail_range = 140.0
			main.streamer.grass_enabled = false
			main.traffic.max_cars = 10
		1:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 90.0
			main.streamer.hi_radius = 420.0
			main.streamer.lo_radius = 1300.0
			main.streamer.detail_range = 220.0
			main.streamer.grass_enabled = true
			main.traffic.max_cars = 16
		2:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 150.0
			main.streamer.hi_radius = 480.0
			main.streamer.lo_radius = 1700.0
			main.streamer.detail_range = 320.0
			main.streamer.grass_enabled = true
			main.traffic.max_cars = 20
	# Forward+ screen-space effects (the Compatibility renderer ignores these)
	var med := fplus and quality >= 1
	var high := fplus and quality >= 2
	env.ssao_enabled = med
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.2
	env.ssao_light_affect = 0.15
	env.ssil_enabled = high
	env.ssil_intensity = 0.8
	env.ssr_enabled = high                  # wet roads, water, windows
	env.ssr_max_steps = 48
	env.glow_enabled = med
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.volumetric_fog_enabled = high       # light shafts at dawn/dusk, haze in rain
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 160.0
	env.volumetric_fog_sky_affect = 0.0
	sun.light_volumetric_fog_energy = 1.2
	sun.shadow_blur = 1.5 if high else 1.0
	RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if high else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	# half-resolution SSAO/SSIL and a coarser fog volume: what keeps High near 60 on a GTX 760
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW, true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_LOW, true, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_volumetric_fog_volume_size(48, 48)
	main.get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	main.get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality >= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	if main.has_method("apply_camera_effects"):
		main.apply_camera_effects(quality)


## The Low preset runs on the Compatibility (OpenGL) renderer, Medium/High on Forward+
## (Vulkan). The renderer is chosen at start-up, so it's written to override.cfg next to
## the game and needs a restart. Returns true when a restart is needed.
func write_renderer_override() -> bool:
	var want := "gl_compatibility" if quality == 0 else "forward_plus"
	var dir := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
	var path := dir.path_join("override.cfg")
	if want == "forward_plus":
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string("[rendering]\n\nrenderer/rendering_method=\"gl_compatibility\"\n")
	return want != RenderingServer.get_current_rendering_method() and DisplayServer.get_name() != "headless"


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
