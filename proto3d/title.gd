extends Node
## Title screen and main menu (the project's main scene). Loads the city behind it in
## title mode and flies a camera slowly around Monrovia while you choose:
## Continue (if there's a save), New Game, Settings, Controls, Credits, Quit.
## Keyboard, mouse and gamepad all work (arrows / d-pad / stick, Enter / A, Esc / B).

const CityScene := preload("res://proto3d/main_city.tscn")
const YELLOW := Color("#f5c518")
const NAVY := Color(0.063, 0.102, 0.196)

var city
var ui: CanvasLayer
var _menu: VBoxContainer
var _buttons: Array[Button] = []
var _loading: Label
var _overlay: PanelContainer
var _overlay_text: RichTextLabel
var _overlay_back: Button
var _t := 0.0
var _starting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	city = CityScene.instantiate()
	city.title_mode = true
	add_child(city)
	_build_ui()


static func version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "dev"))


func _process(delta: float) -> void:
	if city == null or not is_instance_valid(city):
		return
	if not city.ready_done:
		_loading.text = "Loading Monrovia" + ".".repeat(1 + int(Time.get_ticks_msec() / 400) % 3)
		return
	if _loading.visible:
		_loading.visible = false
		_menu.visible = true
		_buttons[0].grab_focus()
	if city.flyover_cam == null:
		return
	# a slow orbit over the start of the game (Waterside / downtown)
	_t += delta
	var center: Vector3 = city.player.spawn_point
	var a := _t * 0.035 + 0.6
	var r := 170.0 + sin(_t * 0.05) * 30.0
	var pos := center + Vector3(cos(a) * r, 62.0 + sin(_t * 0.08) * 10.0, sin(a) * r)
	city.flyover_cam.global_transform = Transform3D(Basis.IDENTITY, pos).looking_at(center + Vector3(0, 8, 0))
	city.flyover_focus = center.lerp(Vector3(pos.x, center.y, pos.z), 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if city != null and city.settings_menu.visible:
		city.settings_menu.close()
		get_viewport().set_input_as_handled()
	elif _overlay.visible:
		_close_overlay()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ actions
func _on_continue() -> void:
	_start(true)


func _on_new_game() -> void:
	_start(false)


func _start(continue_saved: bool) -> void:
	if _starting:
		return
	_starting = true
	ui.visible = false
	city.start_from_title(continue_saved)


func _on_settings() -> void:
	_menu.visible = false
	var sm: Control = city.settings_menu
	sm.reparent(ui)                       # the HUD it lives in is hidden behind the title
	city.open_settings(func():
		sm.reparent(city.hud)
		get_tree().paused = false
		_menu.visible = true
		_buttons[0].grab_focus())


func _on_controls() -> void:
	var lines := PackedStringArray(["[font_size=26][b]Controls[/b][/font_size]", "",
		"[table=3][cell][b]Action[/b]   [/cell][cell][b]Keyboard / mouse[/b]   [/cell][cell][b]Gamepad[/b][/cell]"])
	for a in InputDefaults.ACTIONS:
		var kb := PackedStringArray()
		var pad := PackedStringArray()
		if InputMap.has_action(a):
			for e in InputMap.action_get_events(a):
				var s := InputGlyphs._name(e)
				if s == "":
					continue
				if e is InputEventJoypadButton or e is InputEventJoypadMotion:
					if not s in pad:
						pad.append(s)
				elif not s in kb:
					kb.append(s)
		lines.append("[cell]%s   [/cell][cell]%s   [/cell][cell]%s[/cell]" % [String(InputDefaults.ACTIONS[a][0]), " ".join(kb), " ".join(pad)])
	lines.append("[/table]")
	lines.append("")
	lines.append("Keys can be changed in Settings > Controls.   F8 reports a bug.")
	_show_overlay("\n".join(lines))


func _on_credits() -> void:
	var md := FileAccess.get_file_as_string("res://CREDITS.md")
	if md == "":
		md = "# Credits\n\nMap data (c) OpenStreetMap contributors, ODbL 1.0."
	_show_overlay(_markdown_to_bbcode(md))


func _on_quit() -> void:
	get_tree().quit()


static func _markdown_to_bbcode(md: String) -> String:
	var out := PackedStringArray()
	for raw in md.split("\n"):
		var l := raw.replace("[", "[lb]")
		if l.begins_with("## "):
			l = "[font_size=20][b][color=#f5c518]%s[/color][/b][/font_size]" % l.substr(3)
		elif l.begins_with("# "):
			l = "[font_size=28][b]%s[/b][/font_size]" % l.substr(2)
		var parts := l.split("**")
		l = ""
		for i in parts.size():
			l += parts[i] if i % 2 == 0 else "[b]%s[/b]" % parts[i]
		out.append(l.replace("`", ""))
	return "\n".join(out)


# ------------------------------------------------------------------ overlay
func _show_overlay(bbcode: String) -> void:
	_menu.visible = false
	_overlay_text.text = bbcode
	_overlay_text.scroll_to_line(0)
	_overlay.visible = true
	_overlay_back.grab_focus()


func _close_overlay() -> void:
	_overlay.visible = false
	_menu.visible = true
	_buttons[0].grab_focus()


# ------------------------------------------------------------------ layout
func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	# a dark band on the left so the text reads over the city
	var band := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(NAVY, 0.92))
	grad.set_color(1, Color(NAVY, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	band.texture = gt
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.anchor_bottom = 1.0
	band.offset_right = 760
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(band)

	var col := VBoxContainer.new()
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_left = 80
	col.offset_top = 90
	col.offset_bottom = -60
	col.offset_right = 600
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)
	var logo := Label.new()
	logo.text = "MONROVIA LIFE"
	logo.add_theme_font_size_override("font_size", 72)
	logo.add_theme_color_override("font_color", YELLOW)
	logo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	logo.add_theme_constant_override("outline_size", 10)
	col.add_child(logo)
	var sub := Label.new()
	sub.text = "S T R E E T S"
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(sub)
	var tag := Label.new()
	tag.text = "Run jobs for Auntie Musu, drive keke and taxi, and stay ahead\nof the police from Mamba Point to Sinkor."
	tag.add_theme_font_size_override("font_size", 16)
	tag.add_theme_color_override("font_color", Color(0.85, 0.88, 0.93))
	col.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	col.add_child(gap)

	_loading = Label.new()
	_loading.text = "Loading Monrovia..."
	_loading.add_theme_font_size_override("font_size", 22)
	col.add_child(_loading)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 8)
	_menu.visible = false
	col.add_child(_menu)
	if SaveSystem.has_save():
		_add_button("Continue", _on_continue)
	_add_button("New Game", _on_new_game)
	_add_button("Settings", _on_settings)
	_add_button("Controls", _on_controls)
	_add_button("Credits", _on_credits)
	_add_button("Quit", _on_quit)
	# wrap focus top <-> bottom
	_buttons[0].focus_neighbor_top = _buttons[0].get_path_to(_buttons[-1])
	_buttons[-1].focus_neighbor_bottom = _buttons[-1].get_path_to(_buttons[0])

	var ver := Label.new()
	ver.text = version()
	ver.add_theme_font_size_override("font_size", 16)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -220
	ver.offset_top = -40
	ver.offset_right = -24
	ver.offset_bottom = -14
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.name = "Version"
	root.add_child(ver)
	var osm := Label.new()
	osm.text = "Map data (c) OpenStreetMap contributors, ODbL.   A LibGamer community game."
	osm.add_theme_font_size_override("font_size", 13)
	osm.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	osm.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	osm.offset_left = 24
	osm.offset_top = -36
	osm.offset_right = 700
	osm.offset_bottom = -14
	root.add_child(osm)

	_overlay = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(NAVY, 0.96)
	sb.border_color = Color(YELLOW, 0.6)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(20)
	sb.set_corner_radius_all(6)
	_overlay.add_theme_stylebox_override("panel", sb)
	_overlay.anchor_left = 0.5
	_overlay.anchor_right = 0.5
	_overlay.anchor_top = 0.08
	_overlay.anchor_bottom = 0.92
	_overlay.offset_left = -430
	_overlay.offset_right = 430
	_overlay.visible = false
	root.add_child(_overlay)
	var ov := VBoxContainer.new()
	_overlay.add_child(ov)
	_overlay_text = RichTextLabel.new()
	_overlay_text.bbcode_enabled = true
	_overlay_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_overlay_text.scroll_active = true
	_overlay_text.focus_mode = Control.FOCUS_NONE
	ov.add_child(_overlay_text)
	_overlay_back = _styled_button("Back")
	_overlay_back.pressed.connect(_close_overlay)
	ov.add_child(_overlay_back)


func _add_button(label: String, cb: Callable) -> void:
	var b := _styled_button(label)
	b.pressed.connect(cb)
	b.name = label.replace(" ", "")
	_menu.add_child(b)
	_buttons.append(b)


func _styled_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(320, 46)
	b.add_theme_font_size_override("font_size", 22)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0.35)
	normal.set_content_margin_all(10)
	normal.content_margin_left = 18
	var hot := normal.duplicate() as StyleBoxFlat
	hot.bg_color = Color(YELLOW, 0.92)
	hot.border_width_left = 6
	hot.border_color = Color.WHITE
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("focus", hot)
	b.add_theme_stylebox_override("pressed", hot)
	b.add_theme_color_override("font_hover_color", NAVY)
	b.add_theme_color_override("font_focus_color", NAVY)
	b.add_theme_color_override("font_pressed_color", NAVY)
	b.mouse_entered.connect(func(): b.grab_focus())
	return b
