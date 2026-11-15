class_name BugReport
extends CanvasLayer
## F8: playtest bug report. Takes a screenshot first, pauses, asks for a short note, then
## writes user://bug_reports/<timestamp>/ with screenshot.png, report.txt (note, version,
## place, position, FPS, settings, hardware) and log_tail.txt (end of the game's log).
## Nothing is sent anywhere: the dialog shows the folder and can open it.

const DIR := "user://bug_reports"
const LOG := "user://logs/godot.log"
const LOG_LINES := 120

var main                          # main_city.gd (or null)
var last_dir := ""                # where the last report went (tests read it)
var dir_root := DIR               # tests point this into tests/output
var _shot: Image
var _was_paused := false
var _mouse := Input.MOUSE_MODE_VISIBLE
var _panel: PanelContainer
var _note: TextEdit
var _info: Label
var _status: Label
var _save: Button
var _open: Button
var _close: Button


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("p3_bug_report") and not _panel.visible:
		get_viewport().set_input_as_handled()
		open()
	elif _panel.visible and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


static func version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "dev"))


func open() -> void:
	# the screenshot is of the game, before the dialog covers it
	_shot = null if DisplayServer.get_name() == "headless" else get_viewport().get_texture().get_image()
	_was_paused = get_tree().paused
	_mouse = Input.mouse_mode
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_note.text = ""
	_info.text = _summary()
	_status.text = "Nothing is uploaded: the report is saved on this computer."
	_save.visible = true
	_save.disabled = false
	_open.visible = false
	_close.text = "Cancel"
	_panel.visible = true
	_note.grab_focus()


func close() -> void:
	_panel.visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _mouse


## Writes the report; returns its folder (absolute path) or "" on failure.
func save_report(note: String) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var dir := "%s/%s" % [dir_root, stamp]
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	if _shot != null:
		_shot.save_png(dir + "/screenshot.png")
	var f := FileAccess.open(dir + "/report.txt", FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string("Monrovia Life %s bug report\n\nNOTE\n%s\n\n%s\n" % [version(), note.strip_edges() if note.strip_edges() != "" else "(no note)", _summary()])
	f.close()
	var lf := FileAccess.open(dir + "/log_tail.txt", FileAccess.WRITE)
	if lf != null:
		lf.store_string(_log_tail())
		lf.close()
	last_dir = ProjectSettings.globalize_path(dir)
	return last_dir


func _summary() -> String:
	var lines := PackedStringArray()
	lines.append("Version: %s (Godot %s)" % [version(), Engine.get_version_info()["string"]])
	lines.append("Time: %s" % Time.get_datetime_string_from_system(false, true))
	var scene := get_tree().current_scene
	lines.append("Scene: %s" % (scene.scene_file_path if scene != null else "?"))
	lines.append("FPS: %d" % Engine.get_frames_per_second())
	if main != null and main.ready_done:
		var on_foot: bool = main.car == null
		var p: Vector3 = main.player.global_position if on_foot else main.car.global_position
		lines.append("Position: %.1f, %.1f, %.1f (%s)" % [p.x, p.y, p.z, main.shops.district_at(p)])
		lines.append("Player: %s" % ("on foot" if on_foot else "driving a " + String(main.vehicle_name(main.car.kind))))
		lines.append("Game time: day %d, %s" % [main.state.day(), main.state.clock_text()])
		lines.append("Wanted: %d stars   Health: %d   Money: %d" % [main.state.stars, int(main.state.health), main.state.money])
		if main.get("tutorial") != null and main.tutorial.active:
			lines.append("Tutorial step: %s" % main.tutorial.step_id())
		lines.append("Quality preset: %s" % ["Low", "Medium", "High"][clampi(main.settings.quality, 0, 2)])
	lines.append("Renderer: %s, %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	lines.append("OS: %s %s, %d CPU threads" % [OS.get_name(), OS.get_version(), OS.get_processor_count()])
	lines.append("Window: %s" % str(DisplayServer.window_get_size()))
	return "\n".join(lines)


func _log_tail() -> String:
	if not FileAccess.file_exists(LOG):
		return "(no log file: file logging is off)"
	var all := FileAccess.get_file_as_string(LOG).split("\n")
	return "\n".join(all.slice(maxi(0, all.size() - LOG_LINES)))


func _on_save() -> void:
	var where := save_report(_note.text)
	if where == "":
		_status.text = "Couldn't write the report (disk full or no permission?)."
		return
	_status.text = "Saved. Send this folder to the developers:\n" + where
	_save.visible = false
	_open.visible = true
	_close.text = "Close"
	_open.grab_focus()


func _build() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.063, 0.102, 0.196, 0.97)
	sb.border_color = Color("#ff5a6e")
	sb.set_border_width_all(2)
	sb.set_content_margin_all(18)
	sb.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(560, 0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	var t := Label.new()
	t.text = "Report a bug"
	t.add_theme_font_size_override("font_size", 24)
	v.add_child(t)
	var q := Label.new()
	q.text = "What happened? What did you expect? (A screenshot was taken.)"
	v.add_child(q)
	_note = TextEdit.new()
	_note.custom_minimum_size = Vector2(0, 110)
	_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note.placeholder_text = "e.g. The keke flipped over the kerb by Randall Street."
	v.add_child(_note)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 12)
	_info.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	v.add_child(_info)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(520, 0)
	v.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_save = Button.new()
	_save.text = "Save report"
	_save.custom_minimum_size = Vector2(160, 38)
	_save.pressed.connect(_on_save)
	row.add_child(_save)
	_open = Button.new()
	_open.text = "Open folder"
	_open.custom_minimum_size = Vector2(160, 38)
	_open.pressed.connect(func(): OS.shell_open(last_dir))
	row.add_child(_open)
	_close = Button.new()
	_close.text = "Cancel"
	_close.custom_minimum_size = Vector2(120, 38)
	_close.pressed.connect(close)
	row.add_child(_close)
