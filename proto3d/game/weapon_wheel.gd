extends Control
## Weapon wheel: hold Tab (or LB) to open. The game slows right down while it's open;
## point with the mouse or the right stick, release to pick. Owned weapons show their
## icon, name and ammo (magazine / spare); weapons you don't have are greyed out.
## Plus the weapon widget in the corner: icon, name, ammo, and a reload bar.

const ICON_DIR := "res://proto3d/ui/weapons/%s.png"
const SLOW := 0.25
const NAVY := Color(0.063, 0.102, 0.196, 0.82)
const GOLD := Color("#f5c518")

var main                          # main_city.gd
var state: GameState
var weapons                       # weapons.gd
var open := false
var selected := 0
var _icons := {}
var _point := Vector2.ZERO        # mouse movement while open (no cursor)
var _widget: Control


func setup(main_node) -> void:
	main = main_node
	state = main.state
	weapons = main.weapons
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for d in weapons.defs:
		var id: String = d["id"]
		if ResourceLoader.exists(ICON_DIR % id):
			_icons[id] = load(ICON_DIR % id)
	_widget = Control.new()
	_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_widget.set_anchors_preset(Control.PRESET_FULL_RECT)
	_widget.draw.connect(_draw_widget)
	# the weapon box goes under the HUD's panels and menus (this node, the wheel overlay,
	# stays on top): it stops redrawing while the game is paused, and on touch screens it
	# sits where the pause menu opens, so it used to show through the menu
	_widget.name = "WeaponBox"
	main.hud.add_child(_widget)
	main.hud.move_child(_widget, 0)
	visible = true


func _process(delta: float) -> void:
	if main == null or not main.ready_done:
		return
	var want: bool = Input.is_action_pressed("p3_wheel") and not main.hud.menu_open and not main.hud.map_open
	if want and not open:
		_open()
	elif not want and open:
		_close(true)
	if open:
		var stick := Input.get_vector("p3_look_left", "p3_look_right", "p3_look_up", "p3_look_down")
		if stick.length() > 0.5:
			_point = stick * 100.0
		if _point.length() > 30.0:
			var a := fposmod(_point.angle() + PI / 2.0 + PI / 6.0, TAU)       # slot 0 at the top
			selected = int(a / (TAU / 6.0)) % 6
		queue_redraw()
	_widget.queue_redraw()


func _input(event: InputEvent) -> void:
	if open and event is InputEventMouseMotion:
		_point += (event as InputEventMouseMotion).relative
		_point = _point.limit_length(160.0)
		get_viewport().set_input_as_handled()       # don't turn the camera while choosing


func _open() -> void:
	open = true
	selected = state.weapon
	_point = Vector2.ZERO
	Engine.time_scale = SLOW
	queue_redraw()


func _close(pick: bool) -> void:
	open = false
	Engine.time_scale = 1.0
	if pick and selected != state.weapon:
		if state.select_weapon(selected):
			state.say(String(weapons.defs[selected]["name"]), Color("#dfe6ec"), 1.2)
		else:
			state.say("You don't have the %s. Weapon shops sell it." % String(weapons.defs[selected]["name"]).to_lower(), Color("#ff9a9a"), 2.5)
	queue_redraw()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func ammo_text(w: int) -> String:
	if not GameState.is_gun(w):
		return ""
	return "%d / %d" % [state.clip[w], state.reserve[w]]


func _draw() -> void:
	if not open:
		return
	var c := get_viewport_rect().size / 2.0
	var r_out := 190.0
	var r_in := 70.0
	draw_circle(c, r_out + 8.0, Color(0, 0, 0, 0.25))
	for i in 6:
		var a0 := -PI / 2.0 - PI / 6.0 + i * TAU / 6.0
		var a1 := a0 + TAU / 6.0
		var pts := PackedVector2Array()
		for k in 13:
			var a := lerpf(a0, a1, k / 12.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r_out)
		for k in 13:
			var a := lerpf(a1, a0, k / 12.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r_in)
		var owned: bool = state.owned[i]
		var col := NAVY
		if i == selected:
			col = Color(0.2, 0.35, 0.6, 0.92) if owned else Color(0.35, 0.15, 0.15, 0.85)
		draw_colored_polygon(pts, col)
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.25), 1.5)
		var mid := (a0 + a1) / 2.0
		var at := c + Vector2(cos(mid), sin(mid)) * (r_in + r_out) / 2.0
		var d: Dictionary = weapons.defs[i]
		var tex: Texture2D = _icons.get(String(d["id"]))
		var tint := Color(1, 1, 1, 1.0 if owned else 0.25)
		if i == state.weapon:
			tint = GOLD
		if tex != null:
			var sz := Vector2(96, 48)
			draw_texture_rect(tex, Rect2(at - sz / 2.0 - Vector2(0, 8), sz), false, tint)
		var font := get_theme_default_font()
		var name: String = d["name"]
		draw_string(font, at + Vector2(-60, 30), name, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color(1, 1, 1, 0.95 if owned else 0.4))
		if owned and GameState.is_gun(i):
			draw_string(font, at + Vector2(-60, 46), ammo_text(i), HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color("#dfe6ec"))
	# centre: what's selected
	draw_circle(c, r_in - 6.0, Color(0, 0, 0, 0.55))
	var font2 := get_theme_default_font()
	var sel: Dictionary = weapons.defs[selected]
	draw_string(font2, c + Vector2(-60, 6), String(sel["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 120, 15, GOLD)


func _draw_widget() -> void:
	if main == null or main.hud.menu_open or main.hud.map_open:
		return
	var w: int = state.weapon
	var d: Dictionary = weapons.defs[w]
	var vs := get_viewport_rect().size
	var box := Rect2(vs.x - 250, vs.y - 128, 230, 92)
	if InputMode.is_touch():
		# the bottom right belongs to the touch buttons: sit under the status panel instead
		var m: Vector4 = main.safe_margins if main.get("safe_margins") != null else Vector4.ZERO
		box.position = Vector2(12.0 + m.x, 190.0 + m.y)
		var tc = main.get("touch")
		if DeviceProfile.kind == DeviceProfile.TABLET and tc != null and tc._pos.has("perk"):
			# tablets put Reload / Crouch / Roll above the joystick, right where the box would
			# be: beside the small Pause / Map / View / Perk buttons instead
			box.position = Vector2(float(tc._pos["perk"].x) + float(tc._size["perk"]) + 14.0, float(tc._pos["pause"].y) - float(tc._size["pause"]))
	_widget.draw_rect(box, NAVY)
	var tex: Texture2D = _icons.get(String(d["id"]))
	if tex != null:
		_widget.draw_texture_rect(tex, Rect2(box.position + Vector2(10, 10), Vector2(112, 56)), false)
	var font := get_theme_default_font()
	_widget.draw_string(font, box.position + Vector2(130, 30), String(d["name"]), HORIZONTAL_ALIGNMENT_LEFT, 96, 15, Color("#dfe6ec"))
	if GameState.is_gun(w):
		var low: bool = state.clip[w] <= int(GameState.MAGS[w]) / 4
		_widget.draw_string(font, box.position + Vector2(130, 58), str(state.clip[w]), HORIZONTAL_ALIGNMENT_LEFT, 60, 26, Color("#ff5a6e") if low else Color.WHITE)
		_widget.draw_string(font, box.position + Vector2(172, 58), "/ %d" % state.reserve[w], HORIZONTAL_ALIGNMENT_LEFT, 60, 15, Color("#9fb0c0"))
		if weapons.reloading > 0.0:
			var total := float(d.get("reload", 1.2))
			var f: float = 1.0 - float(weapons.reloading) / total
			_widget.draw_rect(Rect2(box.position + Vector2(10, 76), Vector2(210, 6)), Color(1, 1, 1, 0.15))
			_widget.draw_rect(Rect2(box.position + Vector2(10, 76), Vector2(210 * f, 6)), GOLD)
			_widget.draw_string(font, box.position + Vector2(10, 72), "RELOADING", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, GOLD)
		elif state.clip[w] == 0 and state.reserve[w] > 0:
			_widget.draw_string(font, box.position + Vector2(10, 84), (InputGlyphs.of("p3_reload") + " RELOAD"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, GOLD)
	_widget.draw_string(font, box.position + Vector2(130, 84), (InputGlyphs.of("p3_weapon") + " next" if InputMode.is_touch() else InputGlyphs.of("p3_wheel") + " wheel"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
