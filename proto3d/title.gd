extends Node
## Title screen and main menu (the project's main scene). The menu shows as soon as the
## engine has started, over an animated skyline (TitleBackdrop); the city loads behind it
## in title mode and fades in once the tiles near the camera are ready, then a camera flies
## slowly around Monrovia while you choose:
## Continue (if there's a save), New Game, Sign in / Account, Settings, Controls, Credits, Quit.
## New Game / Continue wait for the starting area if it's still loading (with a progress bar).
## Keyboard, mouse, touch and gamepad all work (arrows / d-pad / stick, Enter / A, Esc / B).

const CITY_SCENE := "res://proto3d/main_city.tscn"
const YELLOW := Color("#f5c518")
const NAVY := Color(0.063, 0.102, 0.196)

var city
var ui: CanvasLayer
var _menu: VBoxContainer
var _buttons: Array[Button] = []
var _overlay: PanelContainer
var _overlay_text: RichTextLabel
var _overlay_back: Button
var _t := 0.0
var _starting := false
var _compact := false                     # phones / tablets: smaller title and buttons
# fast start
var backdrop: TitleBackdrop               # covers the 3D view until the city is ready
var _city_shown := false
var _pending := -1                        # New Game (0) / Continue (1) pressed before the city was ready
var _wait_box: VBoxContainer
var _wait_label: Label
var _wait_bar: ProgressBar
var menu_shown_s := 0.0                   # engine time when the menu was first drawn (benchmark)
var city_shown_s := 0.0
# accounts
var account: TitleAccount                 # sign in / create account panel, cloud save offer
var _account_label: Label
var _account_button: Button
var _column: VBoxContainer                 # logo, tagline, menu (see _fit_menu)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DeviceProfile.detect()
	if DisplayServer.get_name() != "headless":
		get_tree().root.content_scale_factor = DeviceProfile.ui_scale()
	_build_ui()
	_buttons[0].grab_focus.call_deferred()
	_announce_menu()
	_load_city()
	account.start()                       # signed in last time: refresh in the background
	if WebBench.wanted():
		var b := WebBench.new()
		b.title = self
		add_child(b)


static func version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "dev"))


## Browser: say when the menu is on screen (tools measure time-to-menu from this line).
func _announce_menu() -> void:
	if not OS.has_feature("web"):
		menu_shown_s = Time.get_ticks_msec() / 1000.0
		return
	await RenderingServer.frame_post_draw
	menu_shown_s = Time.get_ticks_msec() / 1000.0
	print("MENU_SHOWN at %.1f s" % menu_shown_s)


## The city is loaded after the menu has been drawn (two frames), so the menu shows first.
func _load_city() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var scene := load(CITY_SCENE) as PackedScene
	city = scene.instantiate()
	city.title_mode = true
	add_child(city)
	move_child(city, 0)                    # under the title UI


func _process(delta: float) -> void:
	if _pending >= 0:
		_update_wait()
	if city == null or not is_instance_valid(city) or not city.ready_done:
		return
	if not _city_shown:
		_show_city()
	if _pending >= 0 and not _starting:
		var cont := _pending == 1
		_pending = -1
		_wait_box.visible = false
		_start(cont)
		return
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


## The tiles around the camera are in: fade the skyline out and the city in.
func _show_city() -> void:
	_city_shown = true
	city_shown_s = Time.get_ticks_msec() / 1000.0
	if OS.has_feature("web"):
		print("CITY_SHOWN at %.1f s" % city_shown_s)
	var tw := create_tween()
	tw.tween_property(backdrop, "modulate:a", 0.0, 1.4)
	tw.tween_callback(func(): backdrop.visible = false)


func _update_wait() -> void:
	var p := 0.0
	if city != null and is_instance_valid(city) and city.streamer != null:
		p = city.streamer.area_progress(city.player.spawn_point, 140.0)
		if p >= 1.0 and not city.ready_done:
			p = 0.97                           # tiles in, last touches
	_wait_bar.value = p * 100.0
	_wait_label.text = "Getting the streets ready... %d%%" % int(p * 100.0)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if city != null and city.settings_menu.visible:
		city.settings_menu.close()
		get_viewport().set_input_as_handled()
	elif account.is_open():
		account.close()
		get_viewport().set_input_as_handled()
	elif _overlay.visible:
		_close_overlay()
		get_viewport().set_input_as_handled()
	elif _pending >= 0:
		_pending = -1                          # changed your mind while it loads
		_wait_box.visible = false
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ actions
func _on_continue() -> void:
	_start(true)


func _on_new_game() -> void:
	_start(false)


func _start(continue_saved: bool) -> void:
	if _starting:
		return
	if city == null or not is_instance_valid(city) or not city.ready_done:
		_pending = 1 if continue_saved else 0
		_wait_box.visible = true
		_update_wait()
		return
	_starting = true
	ui.visible = false
	city.start_from_title(continue_saved)


func _on_account() -> void:
	_menu.visible = false
	account.open()


## Called by the account panel when it closes.
func account_closed() -> void:
	_menu.visible = true
	_account_button.grab_focus()


func _update_account() -> void:
	if _account_label == null:
		return
	var on := Online.get_instance()
	if on.signed_in():
		var who := on.display_name if on.display_name != "" else on.email
		_account_label.text = ("Signed in as %s   ·   cloud saves on" % who) if not on.offline else ("Signed in as %s   ·   offline, saving on this device" % who)
		_account_button.text = "Account"
	else:
		_account_label.text = "Playing as guest   ·   saves stay on this device"
		_account_button.text = "Sign in / Create account"

func _on_settings() -> void:
	if city == null or not is_instance_valid(city):
		return                                 # (only for the first two frames)
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
					s = String(InputGlyphs.PAD_HOLD.get(a, s))
					if not s in pad:
						pad.append(s)
				elif not s in kb:
					kb.append(s)
		lines.append("[cell]%s   [/cell][cell]%s   [/cell][cell]%s[/cell]" % [String(InputDefaults.ACTIONS[a][0]), " ".join(kb), " ".join(pad)])
	lines.append("[/table]")
	lines.append("")
	lines.append("Keys can be changed in Settings > Controls.   F8 reports a bug (or Report a bug in the pause menu).")
	lines.append("")
	lines.append("[b]Touch[/b] (phones and tablets): the joystick under your left thumb moves you (push it to the rim to run), drag on the right side to look around, and the buttons by your right thumb shoot, jump, get in cars and more. II pauses.")
	lines.append("[b]Gamepad[/b]: Xbox and PlayStation pads both work, in the browser too; menus use the d-pad or left stick, A / Cross to choose, B / Circle to go back.")
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
	# the skyline until the city has streamed in (then it fades out)
	backdrop = TitleBackdrop.new()
	backdrop.name = "Backdrop"
	root.add_child(backdrop)
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

	# phones and tablets: the UI is drawn bigger (DeviceProfile.UI_SCALE), so the menu is
	# made more compact to fit, and kept inside the screen's safe area
	var compact := DeviceProfile.is_handheld()
	var phone := DeviceProfile.is_phone()
	var safe: Vector4 = DeviceProfile.safe_margins(get_viewport())
	var col := VBoxContainer.new()
	col.name = "Column"
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_left = (24 if compact else 80) + safe.x
	col.offset_top = (14 if phone else (30 if compact else 44)) + safe.y
	col.offset_bottom = -(40 if compact else 70) - safe.w
	col.offset_right = col.offset_left + 520
	col.add_theme_constant_override("separation", 3 if phone else 6)
	root.add_child(col)
	var logo := Label.new()
	logo.text = "MONROVIA LIFE"
	logo.add_theme_font_size_override("font_size", 40 if phone else (58 if compact else 72))
	logo.add_theme_color_override("font_color", YELLOW)
	logo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	logo.add_theme_constant_override("outline_size", 10)
	col.add_child(logo)
	var sub := Label.new()
	sub.text = "S T R E E T S"
	sub.add_theme_font_size_override("font_size", 18 if phone else 26)
	sub.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(sub)
	var tag := Label.new()
	tag.text = "Run jobs for Auntie Musu, drive keke and taxi, and stay ahead\nof the police from Mamba Point to Sinkor."
	tag.add_theme_font_size_override("font_size", 16)
	tag.add_theme_color_override("font_color", Color(0.85, 0.88, 0.93))
	tag.visible = not phone
	tag.name = "Tagline"
	col.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6 if phone else (12 if compact else 14))
	col.add_child(gap)
	_compact = compact

	_account_label = Label.new()
	_account_label.name = "AccountStatus"
	_account_label.add_theme_font_size_override("font_size", 14 if phone else 16)
	_account_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.93))
	col.add_child(_account_label)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 4 if compact else 5)
	col.add_child(_menu)
	if SaveSystem.has_save():
		_add_button("Continue", _on_continue)
	_add_button("New Game", _on_new_game)
	_add_button("Sign in / Create account", _on_account)
	_account_button = _buttons[-1]
	_account_button.name = "Account"
	_add_button("Settings", _on_settings)
	_add_button("Controls", _on_controls)
	_add_button("Credits", _on_credits)
	if OS.has_feature("web"):
		# browser saves live in the browser's storage: let players keep a copy / move it
		if SaveSystem.has_save():
			_add_button("Export save", _on_export_save)
		_add_button("Import save", _on_import_save)
	else:
		_add_button("Quit", _on_quit)          # a browser tab is closed, not quit
	# wrap focus top <-> bottom
	_buttons[0].focus_neighbor_top = _buttons[0].get_path_to(_buttons[-1])
	_buttons[-1].focus_neighbor_bottom = _buttons[-1].get_path_to(_buttons[0])

	# New Game / Continue pressed while the starting area is still downloading
	_wait_box = VBoxContainer.new()
	_wait_box.name = "Waiting"
	_wait_box.visible = false
	col.add_child(_wait_box)
	_wait_label = Label.new()
	_wait_label.add_theme_font_size_override("font_size", 16)
	_wait_box.add_child(_wait_label)
	_wait_bar = ProgressBar.new()
	_wait_bar.custom_minimum_size = Vector2(300, 10)
	_wait_bar.show_percentage = false
	_wait_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var fill := StyleBoxFlat.new()
	fill.bg_color = YELLOW
	_wait_bar.add_theme_stylebox_override("fill", fill)
	_wait_box.add_child(_wait_bar)

	var ver := Label.new()
	ver.text = version() + ("   ·   Browser version" if OS.has_feature("web") else "")
	ver.add_theme_font_size_override("font_size", 16)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -420
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
	var half := minf(430.0, root.get_viewport_rect().size.x / 2.0 - 12.0)
	_overlay.offset_left = -half
	_overlay.offset_right = half
	if compact:
		_overlay.anchor_top = 0.03
		_overlay.anchor_bottom = 0.97
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

	account = TitleAccount.new()
	account.name = "AccountPanel"
	account.title = self
	root.add_child(account)
	Online.get_instance().changed.connect(_update_account)
	_update_account()
	_column = col
	root.resized.connect(_fit_menu)
	_fit_menu.call_deferred()


## The menu must never run under the credit line at the bottom (a short window, or the
## browser's extra Export / Import save buttons): drop the tagline when it doesn't fit.
func _fit_menu() -> void:
	if _column == null:
		return
	var tag := _column.get_node_or_null("Tagline") as Control
	if tag == null:
		return
	# the space between the column's offsets (a container never shrinks below its contents)
	var room := _column.get_parent_control().size.y + _column.offset_bottom - _column.offset_top
	if tag.visible:
		if _column.get_combined_minimum_size().y > room:
			tag.visible = false
	elif not DeviceProfile.is_phone() and _column.get_combined_minimum_size().y + tag.get_combined_minimum_size().y + 6.0 <= room:
		tag.visible = true                       # the window grew back


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
	b.custom_minimum_size = Vector2(300, 34) if _compact else Vector2(320, 42)
	b.add_theme_font_size_override("font_size", 18 if _compact else 22)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0.35)
	normal.set_content_margin_all(10)
	normal.content_margin_left = 18
	normal.content_margin_top = 6 if _compact else 7
	normal.content_margin_bottom = 6 if _compact else 7
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


# ------------------------------------------------------------------ browser saves
var _import_cb: JavaScriptObject           # kept alive while the file picker is open


func _on_export_save() -> void:
	var bytes := FileAccess.get_file_as_bytes(SaveSystem.PATH)
	if bytes.is_empty():
		return
	JavaScriptBridge.download_buffer(bytes, "monrovia-life-save.json", "application/json")


func _on_import_save() -> void:
	_import_cb = JavaScriptBridge.create_callback(_on_import_text)
	JavaScriptBridge.get_interface("window").monroviaImportSave = _import_cb
	JavaScriptBridge.eval("""(function(){var i=document.createElement('input');i.type='file';
		i.accept='.json,application/json';i.onchange=function(){var f=i.files[0];if(!f)return;
		f.text().then(function(t){window.monroviaImportSave(t);});};i.click();})();""", true)


func _on_import_text(args: Array) -> void:
	var text := String(args[0]) if args.size() > 0 else ""
	if not import_save_text(text):
		_show_overlay("[font_size=24][b]Import save[/b][/font_size]\n\nThat file isn't a Monrovia Life save.")
		return
	get_tree().reload_current_scene()         # the menu now offers Continue


## Checks a save file's text and stores it as the save. Used by Import save (and tests).
static func import_save_text(text: String, path: String = SaveSystem.PATH) -> bool:
	var json := JSON.new()
	if json.parse(text) != OK:              # (quietly: parse_string would log an error)
		return false
	var d = json.data
	if typeof(d) != TYPE_DICTIONARY or not d.has("money") or not d.has("version"):
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true
