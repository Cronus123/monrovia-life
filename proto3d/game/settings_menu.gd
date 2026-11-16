class_name SettingsMenu
extends PanelContainer
## The Settings screen (opened from the start and pause menus): Audio, Display, Gameplay
## and Controls tabs. Changes apply immediately and are saved when the screen closes.

signal closed

var settings: GameSettings
var main                          # main_city.gd
var _waiting_action := ""
var _bind_buttons := {}
var _tabs: TabContainer


func open(s: GameSettings, main_node) -> void:
	settings = s
	main = main_node
	if get_parent() != null:
		get_parent().move_child(self, -1)        # over the weapon box and anything added later
	for c in get_children():
		c.queue_free()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.063, 0.102, 0.196, 0.96)
	sb.border_color = Color(0.54, 0.59, 0.64, 0.4)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)
	# fits a phone's screen too (the UI is drawn bigger there, so the canvas is smaller)
	var vs := get_viewport().get_visible_rect().size
	custom_minimum_size = Vector2(minf(640.0, vs.x - 24.0), minf(470.0, vs.y - 24.0))
	var v := VBoxContainer.new()
	add_child(v)
	var title := Label.new()
	title.text = "Settings" + ("      (LB / RB: change tab)" if InputMode.is_pad() else "")
	title.add_theme_font_size_override("font_size", 24 if vs.y >= 560.0 else 18)
	v.add_child(title)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs = tabs
	v.add_child(tabs)
	tabs.add_child(_audio_tab())
	tabs.add_child(_display_tab())
	tabs.add_child(_gameplay_tab())
	tabs.add_child(_controls_tab())
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(0, 36)
	done.pressed.connect(close)
	done.call_deferred("grab_focus")          # gamepad: something focused to start from
	v.add_child(done)
	visible = true
	reset_size()
	position = (get_viewport().get_visible_rect().size - size) / 2.0


func close() -> void:
	settings.save_file()
	visible = false
	closed.emit()


func _grid(name: String) -> GridContainer:
	var g := GridContainer.new()
	g.name = name
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 10)
	return g


func _row(g: GridContainer, label: String, ctrl: Control) -> void:
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(200, 0)
	g.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(ctrl)


func _slider(value: float, lo: float, hi: float, step: float, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(280, 24)
	s.value_changed.connect(on_change)
	return s


func _check(value: bool, on_change: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.button_pressed = value
	c.toggled.connect(on_change)
	return c


func _audio_tab() -> Control:
	var g := _grid("Audio")
	for item in [["Master volume", "master"], ["Music", "music"], ["Sound effects", "sfx"], ["Ambience", "ambience"]]:
		var key: String = item[1]
		_row(g, item[0], _slider(settings.get(key), 0.0, 1.0, 0.05, func(v: float):
			settings.set(key, v)
			settings.apply_system()))
	return g


func _display_tab() -> Control:
	var g := _grid("Display")
	var res := OptionButton.new()
	for i in GameSettings.RESOLUTIONS.size():
		var r: Vector2i = GameSettings.RESOLUTIONS[i]
		res.add_item("%d × %d" % [r.x, r.y], i)
		if r == settings.resolution:
			res.select(i)
	res.item_selected.connect(func(i: int):
		settings.resolution = GameSettings.RESOLUTIONS[i]
		settings.apply_system())
	_row(g, "Resolution (windowed)", res)
	_row(g, "Fullscreen", _check(settings.fullscreen, func(b: bool):
		settings.fullscreen = b
		settings.apply_system()))
	_row(g, "V-sync", _check(settings.vsync, func(b: bool):
		settings.vsync = b
		settings.apply_system()))
	var note := Label.new()
	var q := OptionButton.new()
	for i in GameSettings.QUALITY.size():
		q.add_item(GameSettings.QUALITY[i], i)
	q.select(settings.quality)
	q.item_selected.connect(func(i: int):
		settings.quality = i
		settings.apply_world(main)
		if settings.write_renderer_override():
			note.text = "Restart the game to switch renderer (Low uses OpenGL, Medium/High use Vulkan)."
		)
	_row(g, "Graphics quality", q)
	note.text = "Low: OpenGL, no shadows or effects.  Medium: shadows, ambient occlusion, glow.\nHigh: + light bounce, reflections, light shafts, longer view, more traffic."
	note.add_theme_font_size_override("font_size", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g.add_child(Control.new())
	g.add_child(note)
	var light := OptionButton.new()
	light.name = "LightMode"
	for i in GameSettings.LIGHT.size():
		light.add_item(GameSettings.LIGHT[i], i)
	light.select(settings.light_mode)
	light.item_selected.connect(func(i: int):
		settings.light_mode = i
		settings.apply_world(main))
	_row(g, "Light mode (phones)", light)
	var rs := OptionButton.new()
	rs.name = "RenderScale"
	for i in GameSettings.RENDER_SCALES.size():
		var v: float = GameSettings.RENDER_SCALES[i]
		rs.add_item("Auto" if v <= 0.0 else "%d%%" % int(round(v * 100.0)), i)
		if is_equal_approx(v, settings.render_scale):
			rs.select(i)
	rs.item_selected.connect(func(i: int):
		settings.render_scale = GameSettings.RENDER_SCALES[i]
		settings.apply_world(main))
	_row(g, "3D resolution", rs)
	var ln := Label.new()
	ln.text = "This device: %s.  Light mode: lower 3D resolution, no shadows, a shorter view, less traffic and fewer people." % DeviceProfile.kind
	ln.add_theme_font_size_override("font_size", 12)
	ln.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ln.custom_minimum_size = Vector2(280, 0)
	g.add_child(Control.new())
	g.add_child(ln)
	var scroll := ScrollContainer.new()
	scroll.name = "Display"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(g)
	return scroll


func _gameplay_tab() -> Control:
	var g := _grid("Gameplay")
	_row(g, "Mouse / stick sensitivity", _slider(settings.sensitivity, 0.3, 2.5, 0.05, func(v: float):
		settings.sensitivity = v
		settings.apply_world(main)))
	_row(g, "Invert Y", _check(settings.invert_y, func(b: bool):
		settings.invert_y = b
		settings.apply_world(main)))
	_row(g, "Field of view", _slider(settings.fov, 55.0, 95.0, 1.0, func(v: float):
		settings.fov = v
		settings.apply_world(main)))
	_row(g, "Tutorial on a new game", _check(settings.tutorial, func(b: bool):
		settings.tutorial = b
		if not b and main.get("tutorial") != null and main.tutorial.active:
			main.tutorial.skip()))
	return g


func _controls_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Controls"
	var g := _grid("List")
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(g)
	var scheme := OptionButton.new()
	scheme.name = "ControlScheme"
	for i in InputMode.SCHEMES.size():
		scheme.add_item(InputMode.SCHEMES[i], i)
	scheme.select(settings.control_scheme)
	scheme.item_selected.connect(func(i: int):
		settings.control_scheme = i
		InputMode.set_scheme(i))
	_row(g, "Control scheme", scheme)
	var sn := Label.new()
	sn.text = "Auto switches to whatever you last used: keyboard and mouse, touch or a gamepad. The touch buttons show only while touch is in use."
	sn.add_theme_font_size_override("font_size", 12)
	sn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sn.custom_minimum_size = Vector2(280, 0)
	g.add_child(Label.new())
	g.add_child(sn)
	for a in InputDefaults.ACTIONS:
		var d: Array = InputDefaults.ACTIONS[a]
		if (d[1] as Array).is_empty():
			continue                  # stick-only actions
		var b := Button.new()
		b.text = InputDefaults.key_text(a)
		b.custom_minimum_size = Vector2(200, 30)
		b.pressed.connect(_start_rebind.bind(a))
		_bind_buttons[a] = b
		_row(g, d[0], b)
	var reset := Button.new()
	reset.text = "Reset controls to defaults"
	reset.pressed.connect(func():
		settings.reset_bindings()
		for a in _bind_buttons:
			(_bind_buttons[a] as Button).text = InputDefaults.key_text(a))
	g.add_child(Label.new())
	g.add_child(reset)
	var pad := Label.new()
	pad.text = "Gamepad (Xbox names; PlayStation: A=Cross, B=Circle, X=Square, Y=Triangle): left stick move, right stick camera, RT accelerate, LT brake/aim, A jump/handbrake, Y car, X use, B horn/roll, RB shoot, hold LB weapon wheel, R3 camera, L3 run, D-pad up hire, right radio, down reload, left crouch, View map (hold: perk ability), Menu pause. In menus: d-pad or left stick, A choose, B back.\nTouch: left thumb joystick (push to the rim to run), drag on the right to look, buttons bottom right."
	pad.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pad.custom_minimum_size = Vector2(280, 0)
	pad.add_theme_font_size_override("font_size", 12)
	g.add_child(Label.new())
	g.add_child(pad)
	return scroll


func _start_rebind(action: String) -> void:
	_waiting_action = action
	(_bind_buttons[action] as Button).text = "Press a key…"


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# gamepad: LB / RB flip through the tabs
	if _waiting_action == "" and _tabs != null and event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var bi := (event as InputEventJoypadButton).button_index
		if bi == JOY_BUTTON_LEFT_SHOULDER or bi == JOY_BUTTON_RIGHT_SHOULDER:
			var n := _tabs.get_tab_count()
			_tabs.current_tab = (_tabs.current_tab + (1 if bi == JOY_BUTTON_RIGHT_SHOULDER else -1) + n) % n
			_focus_first(_tabs.get_current_tab_control())
			get_viewport().set_input_as_handled()
			return
	if _waiting_action == "":
		return
	if (event is InputEventKey and (event as InputEventKey).pressed) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		get_viewport().set_input_as_handled()
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE and _waiting_action != "p3_pause":
			(_bind_buttons[_waiting_action] as Button).text = InputDefaults.key_text(_waiting_action)
			_waiting_action = ""
			return
		settings.set_binding(_waiting_action, GameSettings.spec_for(event))
		(_bind_buttons[_waiting_action] as Button).text = InputDefaults.key_text(_waiting_action)
		_waiting_action = ""


## Focuses the first control a gamepad can use inside a tab.
func _focus_first(n: Node) -> void:
	if n == null:
		return
	for c in n.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.focus_mode == Control.FOCUS_ALL and ctl.is_visible_in_tree():
			ctl.grab_focus()
			return
