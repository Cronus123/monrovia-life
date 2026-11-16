class_name TouchControls
extends Control
## On-screen touch controls for phones and tablets (shown only while the touch scheme is
## active, see InputMode): a floating joystick on the left (push to the rim to run), drag
## anywhere else on the right to look, and buttons in the thumb zone of the bottom-right
## corner (tablets also use the bottom-left corner above the joystick, where a thumb can
## reach on a big screen). Small buttons along the top: pause, map, camera, perk.
##
## Buttons send the same Input Map actions as keys and gamepad buttons, so the game code
## doesn't know touch from keyboard. Multi-touch is tracked per finger.

const FOOT := 1
const CAR := 2
const BOTH := 3
## id: [label, action, mode ("hold" | "tap" | "toggle"), where (FOOT/CAR/BOTH)]
const BUTTONS := {
	"fire": ["Shoot", "p3_fire", "hold", BOTH],
	"jump": ["Jump", "p3_jump", "hold", FOOT],
	"brake": ["Brake", "p3_jump", "hold", CAR],
	"aim": ["Aim", "p3_aim", "toggle", FOOT],
	"car": ["Car", "p3_interact", "tap", BOTH],
	"use": ["Use", "p3_use", "tap", FOOT],
	"weapon": ["Weapon", "p3_weapon", "tap", FOOT],
	"reload": ["Reload", "p3_reload", "tap", FOOT],
	"crouch": ["Crouch", "p3_crouch", "tap", FOOT],
	"dodge": ["Roll", "p3_dodge", "tap", FOOT],
	"horn": ["Horn", "p3_horn", "hold", CAR],
	"radio": ["Radio", "p3_radio", "tap", CAR],
	"hire": ["Hire", "p3_hire", "tap", CAR],
	"pause": ["II", "p3_pause", "tap", BOTH],
	"map": ["Map", "p3_map", "tap", BOTH],
	"camera": ["View", "p3_camera", "tap", BOTH],
	"perk": ["Perk", "p3_ability", "tap", BOTH],
}
const TOP := ["pause", "map", "camera", "perk"]
const MOVE := ["p3_forward", "p3_back", "p3_left", "p3_right"]
const LOOK_SENS := 0.0062
const RUN_AT := 0.92                    # joystick deflection that starts running

var main                                # main_city.gd
var layout_kind := DeviceProfile.DESKTOP   # "tablet" uses both thumb corners
var margins := Vector4.ZERO              # safe area (left, top, right, bottom) in canvas units
var radius := 36.0                       # button radius in canvas units

var _pos := {}                           # id -> centre
var _size := {}                          # id -> radius
var _held := {}                          # id -> finger index
var _toggled := {}                       # id -> bool (aim)
var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_rest := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _look_finger := -1
var _running := false
var _font: Font


func setup(main_node) -> void:
	main = main_node
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	resized.connect(relayout)
	relayout()


## In play and on touch: everything; with the map open: only the map button; menus,
## title screen, cut-ins: hidden.
func wanted() -> bool:
	if main == null or not InputMode.is_touch() or not main.ready_done or main.title_mode:
		return false
	if main.hud.menu_open or main.settings_menu.visible or not main.hud.visible:
		return false
	return true


func on_foot() -> bool:
	return main == null or main.car == null


func visible_ids() -> Array:
	var out: Array = []
	if main != null and main.hud.map_open:
		return ["map"]
	var where := FOOT if on_foot() else CAR
	for id in BUTTONS:
		if int(BUTTONS[id][3]) & where:
			out.append(id)
	return out


func relayout() -> void:
	var s := size if size.x > 1.0 else get_viewport_rect().size
	var tablet := layout_kind == DeviceProfile.TABLET
	radius = 42.0 if tablet else 33.0
	var r := radius
	var inner := 3.6 if tablet else 3.5       # arc radii in button radii: the phone's are
	var outer := 6.0 if tablet else 5.6       # tighter so they stay below the minimap
	# bottom-right thumb pivot, one button in from the safe edges so every arc stays on screen
	var c := Vector2(s.x - margins.z - r - 4.0, s.y - margins.w - r - 4.0)
	var fire_r := r * 1.4
	_pos.clear()
	_size.clear()
	_place("fire", c + Vector2(-0.55, -0.55) * r, fire_r)
	# right thumb: an inner and an outer arc around the corner
	var foot_inner := ["jump", "aim", "car"]
	var foot_outer := ["use", "weapon", "reload", "crouch", "dodge"] if not tablet else ["use", "weapon"]
	# in a car the same spots carry the car's buttons ("car" stays where it is on foot)
	var car_inner := ["brake", "horn", "car"]
	var car_outer := ["radio", "hire"]
	_arc(c, inner * r, foot_inner, 180.0, 270.0)
	_arc(c, outer * r, foot_outer, 180.0, 270.0)
	_arc(c, inner * r, car_inner, 180.0, 270.0)
	_arc(c, outer * r, car_outer, 200.0, 250.0)
	# joystick rest spot (it follows the thumb when you touch)
	var cl := Vector2(margins.x + r + 4.0, s.y - margins.w - r - 4.0)
	_stick_rest = cl + Vector2(1.7, -1.7) * r
	if tablet:
		# big screen: the left thumb takes the secondary moves, above the joystick
		_arc(cl, 5.6 * r, ["reload", "crouch", "dodge"], 270.0, 360.0)
	# small buttons in a 2 x 2 block beside the weapon box (under the status panel, left),
	# clear of the messages and tutorial panel along the top
	var small := r * 0.72
	var origin := Vector2(margins.x + 12.0 + 230.0 + 14.0 + small, margins.y + 190.0 + small)
	for i in TOP.size():
		_place(TOP[i], origin + Vector2(i % 2, i / 2) * (small * 2.0 + 10.0), small)
	queue_redraw()


func _place(id: String, p: Vector2, rad: float) -> void:
	_pos[id] = p
	_size[id] = rad


func _arc(pivot: Vector2, dist: float, ids: Array, from_deg: float, to_deg: float) -> void:
	for i in ids.size():
		var t := 0.5 if ids.size() == 1 else float(i) / float(ids.size() - 1)
		var a := deg_to_rad(lerpf(from_deg, to_deg, t))
		if not _pos.has(ids[i]):          # first placement wins (a shared button keeps its spot)
			_place(ids[i], pivot + Vector2(cos(a), sin(a)) * dist, radius)


func button_at(p: Vector2) -> String:
	for id in visible_ids():
		if _pos.has(id) and p.distance_to(_pos[id]) <= float(_size[id]) * 1.12:
			return id
	return ""


func _process(_delta: float) -> void:
	var w := wanted()
	if w != visible:
		visible = w
		if not w:
			release_all()
	if visible:
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_finger:
			_stick_move(d.position)
		elif d.index == _look_finger and main != null and main.rig != null:
			main.rig.touch_look(d.relative * LOOK_SENS)
		get_viewport().set_input_as_handled()


func _touch_down(finger: int, p: Vector2) -> void:
	var id := button_at(p)
	if id != "":
		_press(id, finger)
		return
	var s := size
	if _stick_finger < 0 and p.x < s.x * 0.45 and p.y > s.y * 0.3:
		_stick_finger = finger
		_stick_origin = p
		_stick_vec = Vector2.ZERO
		return
	if _look_finger < 0 and p.x >= s.x * 0.35:
		_look_finger = finger


func _touch_up(finger: int) -> void:
	if finger == _stick_finger:
		_stick_finger = -1
		_stick_vec = Vector2.ZERO
		_apply_stick()
	if finger == _look_finger:
		_look_finger = -1
	for id in _held.keys():
		if _held[id] == finger:
			_release(id)


func _stick_move(p: Vector2) -> void:
	var range_px := radius * 2.0
	var v := (p - _stick_origin) / range_px
	if v.length() > 1.0:
		# drag the base along so the thumb never falls off the edge
		_stick_origin = p - v.normalized() * range_px
		v = v.normalized()
	_stick_vec = v
	_apply_stick()


func _apply_stick() -> void:
	var v := _stick_vec if _stick_vec.length() > 0.12 else Vector2.ZERO
	var strengths := [maxf(0.0, -v.y), maxf(0.0, v.y), maxf(0.0, -v.x), maxf(0.0, v.x)]
	for i in MOVE.size():
		if strengths[i] > 0.0:
			Input.action_press(MOVE[i], minf(strengths[i] * 1.15, 1.0))
		else:
			Input.action_release(MOVE[i])
	var run := v.length() >= RUN_AT and on_foot()
	if run != _running:
		_running = run
		if run:
			Input.action_press("p3_sprint")
		else:
			Input.action_release("p3_sprint")


func _press(id: String, finger: int) -> void:
	var def: Array = BUTTONS[id]
	var action: String = def[1]
	if def[2] == "toggle":
		var on := not bool(_toggled.get(id, false))
		_toggled[id] = on
		_send(action, on)
		return
	_held[id] = finger
	_send(action, true)


func _release(id: String) -> void:
	_held.erase(id)
	_send(BUTTONS[id][1], false)


## Like pressing / letting go of a key bound to the action.
func _send(action: String, pressed: bool) -> void:
	if not InputMap.has_action(action):
		return
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(e)


## Lets go of everything (menus opening, switching to another input device).
func release_all() -> void:
	for id in _held.keys():
		_release(id)
	for id in _toggled.keys():
		if _toggled[id]:
			_send(BUTTONS[id][1], false)
	_toggled.clear()
	_stick_finger = -1
	_look_finger = -1
	_stick_vec = Vector2.ZERO
	_apply_stick()


func pressed_ids() -> Array:
	return _held.keys()


func _draw() -> void:
	if not visible:
		return
	# joystick
	var base := _stick_origin if _stick_finger >= 0 else _stick_rest
	var rr := radius * 2.0
	draw_circle(base, rr, Color(0.06, 0.1, 0.2, 0.28))
	draw_arc(base, rr, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
	draw_arc(base, rr * RUN_AT, 0.0, TAU, 48, Color(0.96, 0.77, 0.09, 0.25), 1.5, true)
	draw_circle(base + _stick_vec * rr, radius * 0.8, Color(1, 1, 1, 0.45 if _stick_finger >= 0 else 0.25))
	# buttons
	for id in visible_ids():
		if not _pos.has(id):
			continue
		var p: Vector2 = _pos[id]
		var rad: float = _size[id]
		var hot := _held.has(id) or bool(_toggled.get(id, false))
		var fill := Color(0.96, 0.77, 0.09, 0.75) if hot else Color(0.06, 0.1, 0.2, 0.5)
		draw_circle(p, rad, fill)
		draw_arc(p, rad, 0.0, TAU, 40, Color(1, 1, 1, 0.55), 2.0, true)
		var label: String = BUTTONS[id][0]
		if id == "map" and main != null and main.hud.map_open:
			label = "Close"
		var fs := int(clampf(rad * 0.42, 11.0, 22.0))
		var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(_font, p + Vector2(-tw / 2.0, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(0.06, 0.1, 0.2) if hot else Color.WHITE)
