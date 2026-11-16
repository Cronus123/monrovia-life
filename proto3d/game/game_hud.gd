class_name GameHud
extends CanvasLayer
## The game's screen overlay, built from Godot UI nodes:
## status panel (clock, money, area/street, health and armour, weapon), minimap and
## wanted stars, messages, objective / prompt / vehicle panels, crosshair, big screen
## text (MISSION PASSED, ARRESTED...), the full map (M), and menus (shops, missions,
## pause). Map data credit at the bottom left.

signal menu_closed

const NAVY := Color(0.063, 0.102, 0.196, 0.86)
const MAP_ZOOM := 2.0             # minimap: screen pixels per map pixel (map pixel = 4 m)

var state: GameState
var main                          # main_city.gd
var credits := ""
var menu_open := false
var map_open := false

var _money: Label
var _clock: Label
var _area: Label
var _street: Label
var _health: ProgressBar
var _armor: ProgressBar
var _weapon: Label
var _stamina: ProgressBar
var _mini: Control
var _mini_tex: TextureRect
var _mini_marks: Control
var _stars: Control
var _toasts: VBoxContainer
var _objective: Label
var _prompt: Label
var _vehicle: Label
var _big: Label
var _big_t := 0.0
var _cross: Control
var _map: Control
var _map_tex: TextureRect
var _map_marks: Control
var _menu: PanelContainer
var _menu_title: Label
var _menu_text: Label
var _menu_buttons: VBoxContainer
var _menu_cb: Callable
var _minimap: Texture2D
var _mm := {}                     # minimap.json: x0, z0, m_per_px, w, h
var _root: Control
var _hint: Label
var _map_title: Label
var _mode_serial := -1            # InputMode.serial the hints were last written for

## Key names written into prompts by the game systems, swapped for the button of the
## control scheme in use (and for rebound keys).
const PROMPT_KEYS := {"[E]": "p3_use", "[F]": "p3_interact", "[T]": "p3_hire", "[R]": "p3_reload"}
const HINTS := [
	"WASD move  Shift run  Space jump/handbrake  Mouse aim  LMB shoot  F car  E use  H horn  R radio  T hire  V camera  Q weapon  M map  Esc pause",
	"",          # touch: the buttons are labelled
	"Left stick move  L3 run  A jump/handbrake  RB shoot  LT aim  Y car  X use  B horn/roll  hold LB weapons  R3 camera  View map  Menu pause",
]


func setup(game_state: GameState, main_node) -> void:
	state = game_state
	main = main_node
	state.message.connect(toast)
	state.big_text.connect(show_big)
	if FileAccess.file_exists("res://proto3d/city/minimap.json"):
		_mm = JSON.parse_string(FileAccess.get_file_as_string("res://proto3d/city/minimap.json"))
		var img := Image.load_from_file("res://proto3d/city/minimap.png") if not ResourceLoader.exists("res://proto3d/city/minimap.png") else null
		_minimap = load("res://proto3d/city/minimap.png") if img == null else ImageTexture.create_from_image(img)
	_build()


# ------------------------------------------------------------------ building the UI
func _style(alpha := 0.86) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(NAVY, alpha)
	sb.border_color = Color(0.54, 0.59, 0.64, 0.35)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	return sb


func _label(size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.1))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _bar(col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(230, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.name = "Root"
	_root = root
	add_child(root)
	# status panel
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style())
	panel.position = Vector2(12, 12)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	_clock = _label(13, Color("#b9c3cc"))
	_money = _label(26, Color("#f5c518"))
	_area = _label(16)
	_street = _label(13, Color("#b9c3cc"))
	_health = _bar(Color("#3ccf7a"))
	_armor = _bar(Color("#5aa9ff"))
	_weapon = _label(13, Color("#dfe6ec"))
	_stamina = _bar(Color("#f5c518"))          # sprint stamina (shown while it's not full)
	_stamina.custom_minimum_size.y = 4
	_stamina.visible = false
	for n in [_clock, _money, _area, _street, _health, _armor, _stamina, _weapon]:
		v.add_child(n)
	# minimap
	_mini = Panel.new()
	_mini.add_theme_stylebox_override("panel", _style(0.9))
	_mini.clip_contents = true
	_mini.size = Vector2(260, 190)
	_mini.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_mini.position = Vector2(-272, 12)
	root.add_child(_mini)
	_mini_tex = TextureRect.new()
	_mini_tex.texture = _minimap
	_mini_tex.stretch_mode = TextureRect.STRETCH_SCALE
	if _minimap != null:
		_mini_tex.size = _minimap.get_size() * MAP_ZOOM
	_mini.add_child(_mini_tex)
	_mini_marks = Control.new()
	_mini_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mini_marks.draw.connect(_draw_minimap_marks)
	_mini.add_child(_mini_marks)
	_stars = Control.new()
	_stars.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stars.position = Vector2(-262, 212)
	_stars.size = Vector2(250, 30)
	_stars.draw.connect(_draw_stars)
	root.add_child(_stars)
	# messages
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.position = Vector2(-300, 14)
	_toasts.size = Vector2(600, 0)
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(_toasts)
	_objective = _panel_label(root, 15, Color("#f5e9b0"), -122)
	_prompt = _panel_label(root, 16, Color("#8ff0ea"), -166)
	_vehicle = _panel_label(root, 14, Color.WHITE, -82)
	_big = _label(54)
	_big.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_big.position.y -= 60
	_big.visible = false
	root.add_child(_big)
	_cross = Control.new()
	_cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	root.add_child(_cross)
	var hint := _label(12, Color(1, 1, 1, 0.75))
	hint.text = HINTS[0]
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(12, -44)
	hint.name = "Hint"
	_hint = hint
	root.add_child(hint)
	if credits != "":
		var c := _label(12, Color(1, 1, 1, 0.8))
		c.text = credits
		c.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		c.position = Vector2(12, -24)
		root.add_child(c)
	_build_map(root)
	_build_menu(root)


func _panel_label(root: Control, size: int, col: Color, y: float) -> Label:
	var l := _label(size, col)
	var sb := _style()
	sb.set_content_margin_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	l.add_theme_stylebox_override("normal", sb)
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.position.y = y
	l.visible = false
	root.add_child(l)
	return l


func _build_map(root: Control) -> void:
	_map = ColorRect.new()
	(_map as ColorRect).color = Color(0.02, 0.04, 0.08, 0.92)
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.visible = false
	root.add_child(_map)
	_map_tex = TextureRect.new()
	_map_tex.texture = _minimap
	_map_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_tex.offset_top = 50
	_map_tex.offset_bottom = -20
	_map_tex.offset_left = 20
	_map_tex.offset_right = -20
	_map.add_child(_map_tex)
	_map_marks = Control.new()
	_map_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_marks.draw.connect(_draw_full_map)
	_map.add_child(_map_marks)
	var title := _label(18)
	title.text = "MONROVIA  ·  press M to close"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-150, 14)
	_map_title = title
	_map.add_child(title)


func _build_menu(root: Control) -> void:
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", _style(0.95))
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.custom_minimum_size = Vector2(520, 0)
	_menu.visible = false
	root.add_child(_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_menu.add_child(v)
	_menu_title = _label(22)
	_menu_text = _label(14, Color("#b9c3cc"))
	_menu_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_text.custom_minimum_size = Vector2(490, 0)
	_menu_buttons = VBoxContainer.new()
	v.add_child(_menu_title)
	v.add_child(_menu_text)
	v.add_child(_menu_buttons)


# ------------------------------------------------------------------ devices
## "[E] Eat at ..." -> "(X) Eat at ..." on a gamepad, "(Use) Eat at ..." on touch.
static func keys_to_glyphs(text: String) -> String:
	if text == "" or not text.contains("["):
		return text
	var out := text
	for k in PROMPT_KEYS:
		if out.contains(k):
			var g := InputGlyphs.of(PROMPT_KEYS[k])
			if g != "":
				out = out.replace(k, g)
	return out


## Bottom-left control hints and the map's close hint for the scheme in use.
func _update_hints() -> void:
	var m := InputMode.active
	if _hint != null:
		_hint.text = HINTS[m]
		_hint.visible = HINTS[m] != ""
	if _map_title != null:
		_map_title.text = "MONROVIA  ·  %s to close" % ("tap Close" if m == InputMode.TOUCH else "press " + InputGlyphs.of("p3_map"))


## Keeps the HUD inside the screen's safe area (notches, rounded corners, home bar):
## Vector4(left, top, right, bottom) in canvas units.
func apply_safe_area(m: Vector4) -> void:
	if _root == null:
		return
	_root.offset_left = m.x
	_root.offset_top = m.y
	_root.offset_right = -m.z
	_root.offset_bottom = -m.w


# ------------------------------------------------------------------ menus
## options: [{label, cost?, disabled?}]; callback(index) runs when one is chosen.
func open_menu(title: String, text: String, options: Array, callback: Callable) -> void:
	_menu_title.text = title
	_menu_text.text = text
	_menu_cb = callback
	for c in _menu_buttons.get_children():
		c.queue_free()
	var all := options.duplicate()
	all.append({"label": "Close"})
	for i in all.size():
		var o: Dictionary = all[i]
		var b := Button.new()
		var label := "%d.  %s" % [i + 1, o["label"]]
		if o.has("cost") and int(o["cost"]) > 0:
			label += "   —   " + GameState.money_text(int(o["cost"]))
		b.text = label
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = bool(o.get("disabled", false))
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(choose.bind(i if i < options.size() else -1))
		_menu_buttons.add_child(b)
	_menu.visible = true
	menu_open = true
	if main != null and main.get("tutorial") != null:
		main.tutorial._update_ui()               # its panel steps aside (it doesn't update while paused)
	if main != null and main.audio != null:
		main.audio.ui("ui_click")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu.reset_size()
	_menu.position = (get_viewport().get_visible_rect().size - _menu.size) / 2.0
	await get_tree().process_frame               # re-centre once the container has sized itself
	if is_instance_valid(_menu):
		_menu.position = (get_viewport().get_visible_rect().size - _menu.size) / 2.0
		# keyboard arrows / gamepad d-pad: start on the first button that can be pressed,
		# and wrap from the last back to the first
		var live: Array[Button] = []
		for b in _menu_buttons.get_children():
			if b is Button and not (b as Button).disabled and not b.is_queued_for_deletion():
				live.append(b as Button)
		if not live.is_empty():
			live[0].focus_neighbor_top = live[0].get_path_to(live[-1])
			live[-1].focus_neighbor_bottom = live[-1].get_path_to(live[0])
			live[0].grab_focus()


func choose(i: int) -> void:
	if not menu_open:
		return
	if i >= 0:
		var b := _menu_buttons.get_child(i) as Button
		if b != null and b.disabled:
			return
	if main != null and main.audio != null:
		main.audio.ui("ui_confirm" if i >= 0 else "ui_click")
	close_menu()
	if i >= 0 and _menu_cb.is_valid():
		_menu_cb.call(i)


func close_menu() -> void:
	_menu.visible = false
	menu_open = false
	menu_closed.emit()
	if not map_open and DisplayServer.get_name() != "headless" and not InputMode.is_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle_map() -> void:
	map_open = not map_open
	_map.visible = map_open
	_map_marks.queue_redraw()


# ------------------------------------------------------------------ messages
func toast(text: String, col: Color = Color.WHITE, seconds: float = 3.5) -> void:
	var l := _label(15, col)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sb := _style()
	sb.set_content_margin_all(6)
	l.add_theme_stylebox_override("normal", sb)
	_toasts.add_child(l)
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))
	get_tree().create_timer(seconds).timeout.connect(_expire.bind(l.get_instance_id()))


func _expire(id: int) -> void:
	var o := instance_from_id(id)
	if o != null:
		(o as Node).queue_free()


func show_big(text: String, col: Color) -> void:
	_big.text = text
	_big.add_theme_color_override("font_color", col)
	_big.visible = true
	_big_t = 3.0


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if state == null or main == null or not main.ready_done:
		return
	var p: Vector3 = main.focus_pos()
	var rain: float = main.clock.rain_amount()
	_clock.text = "DAY %d   %s%s" % [state.day(), state.clock_text(), "   ·   RAIN" if rain > 0.0 else ""]
	_money.text = GameState.money_text(state.money)
	_area.text = main.shops.district_at(p)
	_street.text = main.graph.street_name(p)
	_health.value = state.health
	_health.get_theme_stylebox("fill").bg_color = Color("#3ccf7a") if state.health > 30.0 else Color("#ff5a6e")
	_armor.value = state.armor
	_armor.visible = state.armor > 0.0
	if _stamina != null and "perks" in main:
		var mx: float = main.perks.max_stamina()
		_stamina.max_value = mx
		_stamina.value = main.perks.stamina
		_stamina.visible = main.perks.stamina < mx - 0.5
	_weapon.text = String(main.weapons.defs[state.weapon]["name"]) + (("   %d" % state.ammo) if GameState.is_gun(state.weapon) else "")
	# minimap: player at the centre
	if _minimap != null and not _mm.is_empty():
		var px := (p.x - float(_mm["x0"])) / float(_mm["m_per_px"]) * MAP_ZOOM
		var pz := (p.z - float(_mm["z0"])) / float(_mm["m_per_px"]) * MAP_ZOOM
		_mini_tex.position = _mini.size / 2.0 - Vector2(px, pz)
	_mini_marks.queue_redraw()
	_stars.queue_redraw()
	_cross.queue_redraw()
	if map_open:
		_map_marks.queue_redraw()
	# panels
	# the tutorial shows its objective in its own panel at the top
	var obj: String = "" if (main.get("tutorial") != null and main.tutorial.active) else main.objective_text()
	_objective.visible = obj != "" and not map_open
	_objective.text = obj
	var pr: String = keys_to_glyphs(main.prompt_text())
	_prompt.visible = pr != "" and not menu_open and not map_open
	_prompt.text = pr
	if _mode_serial != InputMode.serial:
		_mode_serial = InputMode.serial
		_update_hints()
	var car = main.car
	_vehicle.visible = car != null
	if car != null:
		var vt := "%s   %d km/h   Condition %d%%" % [main.vehicle_name(car.kind).capitalize(), car.kmh(), car.condition()]
		if car.kind in ["taxi", "keke"]:
			vt += "   Hire: %s %s" % ["ON" if main.taxi.hire else "OFF", InputGlyphs.of("p3_hire")]
		_vehicle.text = vt
	if _big_t > 0.0:
		_big_t -= delta
		_big.modulate.a = clampf(_big_t, 0.0, 1.0)
		_big.visible = _big_t > 0.0


func _world_to_minimap(w: Vector3) -> Vector2:
	var px := (w.x - float(_mm["x0"])) / float(_mm["m_per_px"]) * MAP_ZOOM
	var pz := (w.z - float(_mm["z0"])) / float(_mm["m_per_px"]) * MAP_ZOOM
	return _mini_tex.position + Vector2(px, pz)


func _draw_minimap_marks() -> void:
	if _mm.is_empty():
		return
	var r := Rect2(Vector2.ZERO, _mini.size)
	for q in main.shops.pois:
		var m := _world_to_minimap(q["pos"])
		if r.has_point(m) and Shops.COLORS.has(q["type"]):
			_mini_marks.draw_rect(Rect2(m - Vector2(3, 3), Vector2(6, 6)), Shops.COLORS[q["type"]])
	for c in main.police.cars:
		if is_instance_valid(c) and not c.wrecked:
			var m := _world_to_minimap(c.global_position)
			if r.has_point(m):
				_mini_marks.draw_circle(m, 4.0, Color("#ff2a3a") if int(Time.get_ticks_msec() / 250) % 2 == 0 else Color("#2a6bff"))
	var tg = main.target_pos()
	if tg != null:
		var m := _world_to_minimap(tg)
		m = Vector2(clampf(m.x, 6, r.size.x - 6), clampf(m.y, 6, r.size.y - 6))
		_mini_marks.draw_circle(m, 6.0, Color("#f5c518"))
		_mini_marks.draw_arc(m, 6.0, 0, TAU, 14, Color("#14213d"), 1.5)
	_draw_arrow(_mini_marks, r.size / 2.0, main.heading(), 9.0)


func _draw_arrow(ci: Control, c: Vector2, yaw: float, s: float) -> void:
	# yaw: 0 = north (up on the map), positive = turning left (counter-clockwise)
	var a := -yaw - PI / 2.0
	var pts := PackedVector2Array([c + Vector2(cos(a), sin(a)) * s, c + Vector2(cos(a + 2.5), sin(a + 2.5)) * s * 0.75,
		c + Vector2(cos(a - 2.5), sin(a - 2.5)) * s * 0.75])
	ci.draw_colored_polygon(pts, Color("#c8173a"))
	pts.append(pts[0])
	ci.draw_polyline(pts, Color.WHITE, 1.5)


func _draw_stars() -> void:
	for k in 5:
		var c := Vector2(14 + k * 26, 14)
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI / 2 + i * PI / 5
			pts.append(c + Vector2(cos(a), sin(a)) * (10.0 if i % 2 == 0 else 4.5))
		_stars.draw_colored_polygon(pts, Color("#f5c518") if k < state.stars else Color(0, 0, 0, 0.35))
		pts.append(pts[0])
		_stars.draw_polyline(pts, Color(0.05, 0.08, 0.15, 0.9), 1.5)


func _draw_cross() -> void:
	if main == null or main.car != null or menu_open or map_open:
		return
	if not (main.rig.is_first_person() or GameState.is_gun(state.weapon)):
		return
	var c := _cross.size / 2.0
	var col := Color(1, 1, 1, 0.9 if main.weapons.aiming else 0.55)
	_cross.draw_circle(c, 2.0, col)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_cross.draw_line(c + d * 6.0, c + d * 13.0, col, 2.0)


func _draw_full_map() -> void:
	if _minimap == null or _mm.is_empty():
		return
	var tex_size := _minimap.get_size()
	var area := _map_tex.get_rect()
	var sc := minf(area.size.x / tex_size.x, area.size.y / tex_size.y)
	var o := area.position + (area.size - tex_size * sc) / 2.0
	var to_map := func(w: Vector3) -> Vector2:
		return o + Vector2((w.x - float(_mm["x0"])) / float(_mm["m_per_px"]), (w.z - float(_mm["z0"])) / float(_mm["m_per_px"])) * sc
	var font := ThemeDB.fallback_font
	for d in main.shops.districts:
		var m: Vector2 = to_map.call(d["pos"])
		var w := font.get_string_size(d["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_map_marks.draw_string_outline(font, m - Vector2(w / 2, 0), d["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0.03, 0.05, 0.1))
		_map_marks.draw_string(font, m - Vector2(w / 2, 0), d["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	for q in main.shops.pois:
		if Shops.COLORS.has(q["type"]):
			_map_marks.draw_circle(to_map.call(q["pos"]), 5.0, Shops.COLORS[q["type"]])
	var tg = main.target_pos()
	if tg != null:
		_map_marks.draw_arc(to_map.call(tg), 10.0, 0, TAU, 20, Color("#f5c518"), 3.0)
	var me: Vector2 = to_map.call(main.focus_pos())
	_draw_arrow(_map_marks, me, main.heading(), 10.0)
	var legend := [["Safehouse", "home"], ["Auntie Musu (missions)", "mission"], ["Weapon shop", "guns"],
		["Respray shop", "spray"], ["Cookshop", "food"], ["Vehicle park", "park"], ["Hospital", "hospital"], ["Police HQ", "police"]]
	for i in legend.size():
		var y := _map.size.y - 30.0 - i * 20.0
		_map_marks.draw_circle(Vector2(34, y), 5.0, Shops.COLORS[legend[i][1]])
		_map_marks.draw_string_outline(font, Vector2(46, y + 5), legend[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0.03, 0.05, 0.1))
		_map_marks.draw_string(font, Vector2(46, y + 5), legend[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
