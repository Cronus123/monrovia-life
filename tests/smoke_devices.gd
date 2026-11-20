extends SceneTree
## Device checks: phone / tablet / desktop detection, switching between keyboard + mouse,
## touch and gamepad (prompts, touch overlay, mouse buttons off while on touch), the touch
## controls (joystick, run, buttons, look, getting in and out of a car, pause), gamepad
## events for every action and menu navigation (pause menu focus, B to close, View tap /
## hold, LB / RB settings tabs), the tablet layout and safe areas, light graphics on
## phones and the Settings overrides. Writes only to tests/output.
## Run: Godot.exe --headless --path . --script res://tests/smoke_devices.gd

const OUT := "res://tests/output/devices"

var failures := 0
var checks := 0
var title
var city


func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("SMOKEDEV CHECK FAILED: ", what)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	run()


func seconds(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func frames(n: int) -> void:
	for i in n:
		await process_frame


func until(cond: Callable, max_s: float) -> bool:
	var end := Time.get_ticks_msec() + int(max_s * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


## Canvas units (what the game lays out in) -> window pixels (what input events carry).
func to_win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func touch_event(finger: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = finger
	e.position = to_win(at)
	e.pressed = down
	Input.parse_input_event(e)


func drag_event(finger: int, at: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = finger
	e.position = to_win(at)
	e.relative = root.get_final_transform().basis_xform(rel)
	Input.parse_input_event(e)


func pad_button(b: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = down
	e.pressure = 1.0 if down else 0.0
	Input.parse_input_event(e)


func key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)


## Taps an on-screen button by id (finger 7 so it never collides with the joystick test).
func tap(id: String, hold_s: float = 0.0) -> void:
	var p: Vector2 = city.touch._pos[id]
	touch_event(7, p, true)
	await frames(2)
	if hold_s > 0.0:
		await seconds(hold_s)
	touch_event(7, p, false)
	await frames(2)


func has_mouse_event(action: String) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventMouseButton:
			return true
	return false


func run() -> void:
	print("device detection")
	var C := DeviceProfile
	var iphone := "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
	var pixel := "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36"
	var tab := "Mozilla/5.0 (Linux; Android 14; SM-X710) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
	var ipad := "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
	var mac := "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
	var win := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36 Edg/130.0"
	check(C.classify({"ua": iphone, "touch_points": 5, "screen_w": 390, "screen_h": 844}) == C.PHONE, "iPhone -> phone")
	check(C.classify({"ua": pixel, "touch_points": 5, "mobile": true, "screen_w": 412, "screen_h": 915}) == C.PHONE, "Android phone -> phone")
	check(C.classify({"ua": tab, "touch_points": 10, "screen_w": 800, "screen_h": 1280}) == C.TABLET, "Android tablet -> tablet")
	check(C.classify({"ua": ipad, "touch_points": 5}) == C.TABLET, "iPad -> tablet")
	check(C.classify({"ua": mac, "touch_points": 5, "screen_w": 1024, "screen_h": 1366}) == C.TABLET, "iPadOS (desktop-mode Safari) -> tablet")
	check(C.classify({"ua": mac, "touch_points": 0, "screen_w": 1512, "screen_h": 982}) == C.DESKTOP, "Mac -> desktop")
	check(C.classify({"ua": win, "touch_points": 10, "coarse": false, "screen_w": 1920, "screen_h": 1080}) == C.DESKTOP, "Windows touch laptop -> desktop")
	check(C.classify({"ua": "", "mobile": true, "screen_w": 360, "screen_h": 780}) == C.PHONE, "UA-CH mobile, small screen -> phone")
	check(C.classify({"ua": "", "coarse": true, "touch_points": 5, "screen_w": 768, "screen_h": 1024}) == C.TABLET, "no UA, touch-first big screen -> tablet")
	check(C.classify({"ua": win, "override": "phone"}) == C.PHONE and C.classify({"ua": iphone, "override": "desktop"}) == C.DESKTOP, "?device= override wins")
	check(C.detect() == C.DESKTOP and not C.touch, "this headless run is a desktop without touch")
	check(is_equal_approx(C.UI_SCALE[C.PHONE], 1.5) and C.UI_SCALE[C.TABLET] > 1.0 and is_equal_approx(C.UI_SCALE[C.DESKTOP], 1.0), "phones and tablets draw the UI bigger")

	print("gamepad bindings")
	InputDefaults.ensure()
	var no_pad := ["p3_weapon", "p3_fists", "p3_pistol", "p3_slot_3", "p3_slot_4", "p3_slot_5", "p3_slot_6", "p3_bug_report"]
	var missing: Array = []
	for a in InputDefaults.ACTIONS:
		var has_pad := false
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				has_pad = true
		if not has_pad and not a in no_pad:
			missing.append(a)
	check(missing.is_empty(), "every gameplay action has a gamepad event (missing: %s)" % str(missing))
	check(InputGlyphs.of("p3_wheel") != "" and InputDefaults.ACTIONS["p3_wheel"][2].size() > 0,
		"weapon choice (next weapon, slots 1-6) is on the gamepad's LB wheel")
	var cfg := ConfigFile.new()
	cfg.load("res://project.godot")
	var ab: Dictionary = cfg.get_value("input", "p3_ability", {})
	var ab_pad := false
	for e in ab.get("events", []):
		ab_pad = ab_pad or e is InputEventJoypadButton
	check(ab_pad, "project.godot's Input Map has the perk ability on the gamepad")
	for a in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		var stick := false
		var dpad := false
		for e in InputMap.action_get_events(a):
			stick = stick or e is InputEventJoypadMotion
			dpad = dpad or e is InputEventJoypadButton
		check(stick and dpad, "%s: left stick and d-pad move through menus" % a)
	check(InputMap.action_has_event("ui_accept", InputDefaults.make_event("joy:0")) and InputMap.action_has_event("ui_cancel", InputDefaults.make_event("joy:1")),
		"A chooses, B goes back")

	print("control scheme switching")
	InputMode.set_scheme(0)
	InputMode.note(InputDefaults.make_event("key:W"))
	check(InputMode.active == InputMode.KEYBOARD and InputGlyphs.of("p3_interact") == "[F]", "keyboard: [F]")
	var t := InputEventScreenTouch.new()
	t.pressed = true
	InputMode.note(t)
	check(InputMode.is_touch() and InputGlyphs.of("p3_interact") == "(Car)" and InputGlyphs.of("move") == "(Stick)", "touch: (Car), (Stick)")
	check(not has_mouse_event("p3_fire") and not has_mouse_event("p3_aim"), "on touch, taps can't shoot or aim through the mouse buttons")
	var em := InputEventMouseButton.new()
	em.device = InputEvent.DEVICE_ID_EMULATION
	em.pressed = true
	em.button_index = MOUSE_BUTTON_LEFT
	InputMode.note(em)
	check(InputMode.is_touch(), "a tap's emulated mouse click doesn't switch away from touch")
	InputMode.note(InputDefaults.make_event("joy:3"))
	check(InputMode.is_pad() and InputGlyphs.of("p3_interact") == "(Y)" and InputGlyphs.of("p3_ability") == "(hold View)", "gamepad: (Y), (hold View)")
	check(has_mouse_event("p3_fire") and has_mouse_event("p3_aim"), "the mouse buttons come back after touch")
	var small := InputEventJoypadMotion.new()
	small.axis = JOY_AXIS_LEFT_X
	small.axis_value = 0.2
	InputMode.note(InputDefaults.make_event("key:W"))
	InputMode.note(small)
	check(InputMode.active == InputMode.KEYBOARD, "a resting stick's drift doesn't switch to the gamepad")
	InputMode.set_scheme(2)
	InputMode.note(InputDefaults.make_event("key:W"))
	check(InputMode.is_touch(), "Settings 'Touch' keeps touch whatever is pressed")
	InputMode.set_scheme(3)
	check(InputMode.is_pad(), "Settings 'Gamepad'")
	InputMode.set_scheme(0)
	InputMode.note(InputDefaults.make_event("key:W"))
	check(GameHud.keys_to_glyphs("[E] Weapon shop") == "[E] Weapon shop", "prompt on keyboard: [E] Weapon shop")
	InputMode.note(InputDefaults.make_event("joy:0"))
	check(GameHud.keys_to_glyphs("[E] Weapon shop") == "(X) Weapon shop", "prompt on a gamepad: (X) Weapon shop")
	InputMode.note(t)
	check(GameHud.keys_to_glyphs("[F] Get in the taxi") == "(Car) Get in the taxi", "prompt on touch: (Car) Get in the taxi")
	InputMode.note(InputDefaults.make_event("key:W"))

	print("settings")
	var gs := GameSettings.new()
	gs.control_scheme = 2
	gs.light_mode = 1
	gs.render_scale = 0.75
	gs.save_file(OUT + "/settings.cfg")
	var gs2 := GameSettings.new()
	gs2.load_file(OUT + "/settings.cfg")
	check(gs2.control_scheme == 2 and gs2.light_mode == 1 and is_equal_approx(gs2.render_scale, 0.75), "control scheme, light mode and 3D resolution are saved")
	check(not GameSettings.new().light_on(), "light mode Auto is off on a desktop")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(preset.contains("viewport-fit=cover"), "the browser page asks for the full screen (safe areas reported)")

	print("the game")
	title = load("res://proto3d/title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	while title.city == null:              # the title loads the city after drawing its menu
		await process_frame
	city = title.city
	city.save_path = OUT + "/save.json"
	city.bug_report.dir_root = OUT + "/bug_reports"
	check(await until(func(): return city.ready_done, 120.0), "the city loads")
	check(city.touch != null and city.touch_layer != null and not city.touch.visible, "touch overlay exists, hidden on the title screen")
	city.settings.tutorial = false
	title._on_new_game()
	await until(func(): return not city._busy and city.player.active, 60.0)
	await seconds(0.5)
	check(not city.touch.visible, "keyboard: no touch overlay in play")
	var hint: Label = city.hud._hint
	check(hint.visible and hint.text.contains("WASD"), "keyboard hints at the bottom")

	# --- touch
	var vs: Vector2 = city.touch.size
	touch_event(3, Vector2(vs.x * 0.6, vs.y * 0.15), true)
	await frames(3)
	touch_event(3, Vector2(vs.x * 0.6, vs.y * 0.15), false)
	await frames(3)
	check(InputMode.is_touch() and city.touch.visible, "a touch brings up the touch controls")
	check(not hint.visible, "and hides the keyboard hints")
	check(city.touch.visible_ids().has("fire") and city.touch.visible_ids().has("jump") and not city.touch.visible_ids().has("horn"), "on-foot buttons")
	var stick_at := Vector2(vs.x * 0.18, vs.y * 0.75)
	var p0: Vector3 = city.player.global_position
	touch_event(0, stick_at, true)
	await frames(2)
	drag_event(0, stick_at + Vector2(0, -city.touch.radius * 1.2), Vector2(0, -city.touch.radius * 1.2))
	await frames(3)
	var fwd := Input.get_action_strength("p3_forward")
	check(fwd > 0.5 and fwd < 0.9 and not Input.is_action_pressed("p3_sprint"), "joystick half way: walk forward (%.2f)" % fwd)
	drag_event(0, stick_at + Vector2(0, -city.touch.radius * 3.0), Vector2(0, -city.touch.radius * 1.8))
	await frames(3)
	check(Input.get_action_strength("p3_forward") > 0.95 and Input.is_action_pressed("p3_sprint"), "pushed to the rim: run")
	await seconds(1.0)
	var moved: float = city.player.global_position.distance_to(p0)
	check(moved > 2.0, "the player runs (%.1f m)" % moved)
	touch_event(0, stick_at, false)
	await frames(3)
	check(Input.get_action_strength("p3_forward") == 0.0 and not Input.is_action_pressed("p3_sprint"), "letting go stops")
	var yaw0: float = city.rig.yaw
	touch_event(1, Vector2(vs.x * 0.55, vs.y * 0.4), true)
	await frames(2)
	for i in 5:
		drag_event(1, Vector2(vs.x * 0.55 + 20.0 * (i + 1), vs.y * 0.4), Vector2(20, 0))
		await frames(1)
	touch_event(1, Vector2(vs.x * 0.65, vs.y * 0.4), false)
	await frames(2)
	check(absf(city.rig.yaw - yaw0) > 0.3, "dragging on the right turns the camera (%.2f rad)" % (city.rig.yaw - yaw0))
	touch_event(7, city.touch._pos["jump"], true)
	await frames(2)
	check(Input.is_action_pressed("p3_jump") and city.touch.pressed_ids().has("jump"), "Jump button holds jump")
	touch_event(7, city.touch._pos["jump"], false)
	await frames(2)
	check(not Input.is_action_pressed("p3_jump"), "and lets go")
	touch_event(7, city.touch._pos["fire"], true)
	await frames(2)
	check(Input.is_action_pressed("p3_fire"), "Shoot button fires")
	touch_event(7, city.touch._pos["fire"], false)
	await frames(2)
	var w0: int = city.state.weapon
	city.state.owned[GameState.BAT] = true
	await tap("weapon")
	check(city.state.weapon != w0, "Weapon button: next weapon")
	await tap("aim")
	check(Input.is_action_pressed("p3_aim"), "Aim button toggles aiming on")
	await tap("aim")
	check(not Input.is_action_pressed("p3_aim"), "and off")
	# get in the taxi by the spawn point
	var sc = city.start_car
	city.teleport_player(sc.global_position + sc.global_basis.x * 2.4)
	await until(func(): return not city._busy, 15.0)
	await seconds(0.3)
	await tap("car")
	check(await until(func(): return city.car != null, 5.0), "Car button: gets in")
	await frames(2)
	check(city.touch.visible_ids().has("horn") and city.touch.visible_ids().has("brake") and not city.touch.visible_ids().has("jump"), "in a car: car buttons")
	var g0: float = Input.get_action_strength("p3_forward")
	touch_event(0, stick_at, true)
	await frames(2)
	drag_event(0, stick_at + Vector2(0, -city.touch.radius * 2.0), Vector2(0, -city.touch.radius * 2.0))
	await frames(3)
	check(Input.get_action_strength("p3_forward") > 0.95 and g0 == 0.0 and not Input.is_action_pressed("p3_sprint"), "joystick forward accelerates (no run in a car)")
	touch_event(0, stick_at, false)
	await frames(2)
	await seconds(0.5)
	await tap("brake", 1.5)                   # handbrake to a stop
	city.car.linear_velocity = Vector3.ZERO
	await frames(3)
	await tap("car")
	check(await until(func(): return city.car == null, 5.0), "Car button: gets out")
	await tap("pause")
	await frames(3)
	check(city.hud.menu_open and paused and not city.touch.visible, "II pauses; the touch controls step aside for the menu")
	city.hud.close_menu()
	paused = false
	await frames(2)
	check(city.touch.visible, "and come back after it")
	await tap("map")
	await frames(2)
	check(city.hud.map_open and city.touch.visible_ids() == ["map"], "Map button opens the map; only its close button shows")
	await tap("map")
	await frames(2)
	check(not city.hud.map_open, "and closes it")
	paused = false

	# --- layouts
	print("layouts")
	var phone_m := Vector4(44, 0, 44, 21)          # a notched phone on its side
	DeviceProfile.kind = DeviceProfile.PHONE
	city.touch.layout_kind = DeviceProfile.PHONE
	city.touch.margins = phone_m
	city.touch.relayout()
	check(_layout_ok(phone_m), "phone layout: no overlaps, inside the safe area")
	var right_only := true
	for id in ["fire", "jump", "aim", "car", "use", "weapon", "reload", "crouch", "dodge"]:
		right_only = right_only and city.touch._pos[id].x > vs.x * 0.5
	check(right_only, "phone: action buttons under the right thumb")
	# a short phone screen: landscape phones are 480 canvas units tall at the phone UI scale
	# (16:9 or wider). Crouch and Roll used to sit on the wanted stars there.
	var root_win: Window = root
	var old_win_size := root_win.size
	root_win.size = Vector2i(1280, 720)               # 16:9 (headless windows aren't)
	root_win.content_scale_factor = DeviceProfile.UI_SCALE[DeviceProfile.PHONE]
	await frames(4)
	city.hud.apply_safe_area(phone_m)
	city.hud.set_compact(true)
	city.touch.margins = phone_m                       # the resize re-ran apply_device_layout
	city.touch.relayout()
	await frames(2)
	check(city.touch.size.y <= 481.0, "short phone canvas (%.0f units tall)" % city.touch.size.y)
	check(_layout_ok(phone_m), "short phone layout: no overlaps, inside the safe area")
	check(_clear_of_hud(), "short phone: touch buttons clear of the minimap and wanted stars")
	root_win.content_scale_factor = 1.0
	root_win.size = old_win_size
	city.hud.set_compact(false)
	city.hud.apply_safe_area(Vector4.ZERO)
	await frames(2)
	DeviceProfile.kind = DeviceProfile.TABLET
	city.touch.layout_kind = DeviceProfile.TABLET
	city.touch.margins = Vector4(8, 8, 8, 20)
	city.touch.relayout()
	check(_layout_ok(Vector4(8, 8, 8, 20)), "tablet layout: no overlaps, inside the safe area")
	check(city.touch.radius > 36.0, "tablet: bigger buttons (%.0f)" % city.touch.radius)
	var left_ok := true
	for id in ["reload", "crouch", "dodge"]:
		var p: Vector2 = city.touch._pos[id]
		left_ok = left_ok and p.x < vs.x * 0.4 and p.y > vs.y * 0.45
	check(left_ok, "tablet: reload / crouch / roll in the left thumb's reach")
	var reach := true
	var corner_r := Vector2(vs.x, vs.y)
	for id in ["fire", "jump", "aim", "car", "use", "weapon"]:
		reach = reach and city.touch._pos[id].distance_to(corner_r) < vs.y * 0.62
	check(reach, "tablet: right-thumb buttons stay near the corner")
	city.hud.apply_safe_area(Vector4(44, 10, 44, 21))
	check(is_equal_approx(city.hud._root.offset_left, 44.0) and is_equal_approx(city.hud._root.offset_bottom, -21.0), "the HUD keeps inside the safe area")
	city.hud.apply_safe_area(Vector4.ZERO)

	# --- light graphics on phones
	print("light mode")
	DeviceProfile.kind = DeviceProfile.PHONE
	city.settings.light_mode = 0
	city.settings.render_scale = 0.0
	city.settings.apply_world(city)
	var vp: Viewport = city.get_viewport()
	check(is_equal_approx(vp.scaling_3d_scale, GameSettings.LIGHT_SCALE), "phone: lower 3D resolution (%.2f)" % vp.scaling_3d_scale)
	check(not city._sun.shadow_enabled, "phone: no shadows")
	check(city.streamer.hi_radius <= 220.0 and city.streamer.lo_radius <= 560.0, "phone: shorter streaming radius (%.0f / %.0f m)" % [city.streamer.hi_radius, city.streamer.lo_radius])
	check(city.traffic.max_cars <= 6 and city.ped_cap == 6 and city.parked_cap == 3 and city.street_life.max_people == 8, "phone: less traffic, fewer people")
	await seconds(1.5)
	check(city.peds.size() <= city.ped_target() + 3 and city.ped_target() <= int(round(city.ped_cap * 1.15)),
		"people thin out (%d, target %d)" % [city.peds.size(), city.ped_target()])
	city.settings.light_mode = 2
	city.settings.apply_world(city)
	check(is_equal_approx(vp.scaling_3d_scale, 1.0) and city.ped_cap == city.PEDESTRIANS and city.traffic.max_cars > 6, "Settings: light mode Off overrides it")
	city.settings.render_scale = 0.5
	city.settings.apply_world(city)
	check(is_equal_approx(vp.scaling_3d_scale, 0.5), "Settings: 3D resolution can be set by hand")
	city.settings.light_mode = 1
	city.settings.render_scale = 0.0
	DeviceProfile.kind = DeviceProfile.DESKTOP
	city.settings.apply_world(city)
	check(city.settings.light_on() and not city._sun.shadow_enabled, "Settings: light mode On works on any device")
	city.settings.light_mode = 0
	city.settings.apply_world(city)
	check(is_equal_approx(vp.scaling_3d_scale, 1.0) and city._sun.shadow_enabled, "back to full graphics on a desktop")
	city.touch.layout_kind = DeviceProfile.DESKTOP
	city.touch.margins = Vector4.ZERO
	city.touch.relayout()

	# --- gamepad
	print("gamepad")
	pad_button(JOY_BUTTON_A, true)
	await frames(2)
	pad_button(JOY_BUTTON_A, false)
	await frames(2)
	check(InputMode.is_pad() and not city.touch.visible, "a gamepad button switches to the gamepad and hides the touch controls")
	check(city.hud._hint.visible and city.hud._hint.text.contains("Left stick"), "gamepad hints at the bottom")
	pad_button(JOY_BUTTON_START, true)
	await frames(2)
	pad_button(JOY_BUTTON_START, false)
	await frames(4)
	var buttons: Array = []
	for b in city.hud._menu_buttons.get_children():
		if not b.is_queued_for_deletion():
			buttons.append(b)
	check(city.hud.menu_open and paused and buttons.size() > 3 and buttons[0].has_focus(), "Menu button pauses; Resume has focus")
	var labels := " | ".join(buttons.map(func(b): return String(b.text)))
	check(labels.contains("Report a bug"), "pause menu offers Report a bug (no F8 on a pad or phone)")
	pad_button(JOY_BUTTON_DPAD_DOWN, true)
	await frames(2)
	pad_button(JOY_BUTTON_DPAD_DOWN, false)
	await frames(2)
	check(buttons[1].has_focus(), "d-pad down moves to Settings")
	pad_button(JOY_BUTTON_DPAD_UP, true)
	await frames(2)
	pad_button(JOY_BUTTON_DPAD_UP, false)
	await frames(2)
	pad_button(JOY_BUTTON_DPAD_UP, true)
	await frames(2)
	pad_button(JOY_BUTTON_DPAD_UP, false)
	await frames(2)
	check(buttons[-1].has_focus(), "and wraps from the top to the bottom")
	pad_button(JOY_BUTTON_B, true)
	await frames(2)
	pad_button(JOY_BUTTON_B, false)
	await frames(2)
	check(not city.hud.menu_open and not paused, "B closes the pause menu")
	# settings: LB / RB through the tabs, B back
	city.open_settings(func(): pass)
	await frames(3)
	var tabs: TabContainer = city.settings_menu._tabs
	check(city.settings_menu.find_child("ControlScheme", true, false) != null, "Settings > Controls has the control scheme option")
	check(city.settings_menu.find_child("LightMode", true, false) != null and city.settings_menu.find_child("RenderScale", true, false) != null,
		"Settings > Display has light mode and 3D resolution")
	var t0 := tabs.current_tab
	pad_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	await frames(2)
	pad_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	await frames(2)
	check(tabs.current_tab == (t0 + 1) % tabs.get_tab_count() and city.get_viewport().gui_get_focus_owner() != null, "RB: next settings tab, with focus in it")
	pad_button(JOY_BUTTON_LEFT_SHOULDER, true)
	await frames(2)
	pad_button(JOY_BUTTON_LEFT_SHOULDER, false)
	await frames(2)
	check(tabs.current_tab == t0, "LB: back a tab")
	pad_button(JOY_BUTTON_B, true)
	await frames(2)
	pad_button(JOY_BUTTON_B, false)
	await frames(2)
	check(not city.settings_menu.visible, "B leaves Settings")
	city.hud.menu_open = false
	paused = false
	# View: tap = map, hold = perk ability. On a fake clock: a slow headless frame (tiles
	# loading) used to stretch the "tap" past the 450 ms hold time now and then.
	var fake := {"ms": 1000}
	var real_clock: Callable = city.clock_ms
	city.clock_ms = func() -> int: return int(fake["ms"])
	pad_button(JOY_BUTTON_BACK, true)
	await frames(2)
	fake["ms"] += city.BACK_HOLD_MS - 300                # a quick tap: well under the hold time
	await frames(2)
	pad_button(JOY_BUTTON_BACK, false)
	await frames(2)
	check(city.hud.map_open and not city._back_used, "View tap opens the map")
	pad_button(JOY_BUTTON_BACK, true)
	await frames(2)
	pad_button(JOY_BUTTON_BACK, false)
	await frames(2)
	check(not city.hud.map_open and not paused, "and closes it")
	pad_button(JOY_BUTTON_BACK, true)
	await frames(2)
	fake["ms"] += city.BACK_HOLD_MS - 50                 # just short of a hold: nothing yet
	await frames(2)
	check(not city._back_used and not city.hud.map_open, "View held under the hold time: nothing yet")
	fake["ms"] += 300                                    # past it
	await frames(2)
	check(city._back_used and not city.hud.map_open, "holding View uses the perk ability, no map")
	pad_button(JOY_BUTTON_BACK, false)
	await frames(2)
	check(not city.hud.map_open and city._back_down_ms < 0, "and letting go doesn't open the map")
	city.clock_ms = real_clock
	paused = false

	# --- back to keyboard
	key(KEY_W, true)
	await frames(2)
	key(KEY_W, false)
	await frames(2)
	check(InputMode.active == InputMode.KEYBOARD and has_mouse_event("p3_fire"), "a key press goes back to keyboard and mouse")

	title.queue_free()
	await seconds(1.0)
	if failures == 0:
		print("SMOKEDEV TEST PASSED (%d checks)" % checks)
	else:
		print("SMOKEDEV TEST FAILED: %d of %d checks" % [failures, checks])
	quit(1 if failures > 0 else 0)


## No touch button (on foot or in a car) covers the minimap or the wanted stars.
func _clear_of_hud() -> bool:
	var tc: TouchControls = city.touch
	var ok := true
	for id in TouchControls.BUTTONS:
		if not tc._pos.has(id):
			continue
		var p: Vector2 = tc._pos[id]
		var rad: float = tc._size[id]
		for rect in city.hud.top_right_rects():
			var q := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
			if p.distance_to(q) < rad:
				print("    %s covers the HUD at %s (button at %s)" % [id, rect, p])
				ok = false
	return ok


## Every button (on foot and in a car) inside the screen and the safe area, none overlapping
## another shown at the same time, none on the joystick's resting spot.
func _layout_ok(m: Vector4) -> bool:
	var tc: TouchControls = city.touch
	var s := tc.size
	var ok := true
	for where in [TouchControls.FOOT, TouchControls.CAR]:
		var ids: Array = []
		for id in TouchControls.BUTTONS:
			if int(TouchControls.BUTTONS[id][3]) & where:
				ids.append(id)
		for i in ids.size():
			var a: String = ids[i]
			var pa: Vector2 = tc._pos[a]
			var ra: float = tc._size[a]
			if pa.x - ra < m.x or pa.y - ra < m.y or pa.x + ra > s.x - m.z or pa.y + ra > s.y - m.w:
				print("    %s outside the safe area at %s" % [a, pa])
				ok = false
			if pa.distance_to(tc._stick_rest) < ra + tc.radius * 2.0:
				print("    %s on the joystick" % a)
				ok = false
			for j in range(i + 1, ids.size()):
				var b: String = ids[j]
				if pa.distance_to(tc._pos[b]) < ra + float(tc._size[b]) - 0.5:
					print("    %s overlaps %s" % [a, b])
					ok = false
	return ok
