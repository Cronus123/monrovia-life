class_name SettingsMenu
extends PanelContainer
## The Settings screen (opened from the start and pause menus): Audio, Display, Gameplay
## and Controls tabs. Changes apply immediately and are saved when the screen closes.

signal closed

var settings: GameSettings
var main                          # main_city.gd
var _waiting_action := ""
var _bind_buttons := {}


func open(s: GameSettings, main_node) -> void:
	settings = s
	main = main_node
	for c in get_children():
		c.queue_free()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.063, 0.102, 0.196, 0.96)
	sb.border_color = Color(0.54, 0.59, 0.64, 0.4)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(640, 470)
	var v := VBoxContainer.new()
	add_child(v)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 24)
	v.add_child(title)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	tabs.add_child(_audio_tab())
	tabs.add_child(_display_tab())
	tabs.add_child(_gameplay_tab())
	tabs.add_child(_controls_tab())
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(0, 36)
	done.pressed.connect(close)
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
	g.add_child(Control.new())
	g.add_child(note)
	return g


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
	return g


func _controls_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Controls"
	var g := _grid("List")
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(g)
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
	pad.text = "Gamepad: left stick move, right stick camera, RT accelerate, LT brake, A jump/handbrake, Y car, X use, B horn, RB shoot, LB weapon, R3 camera, L3 run, D-pad up hire, D-pad right radio, Back map, Start pause."
	pad.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pad.custom_minimum_size = Vector2(560, 0)
	pad.add_theme_font_size_override("font_size", 12)
	g.add_child(Label.new())
	g.add_child(pad)
	return scroll


func _start_rebind(action: String) -> void:
	_waiting_action = action
	(_bind_buttons[action] as Button).text = "Press a key…"


func _input(event: InputEvent) -> void:
	if _waiting_action == "" or not visible:
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
