class_name InputMode
extends RefCounted
## Which controls the player is using right now: keyboard + mouse, touch, or gamepad.
## On Auto (the default) it follows the last device touched; Settings > Controls can fix
## it to one. Changing it shows or hides the touch overlay and swaps the button prompts
## (InputGlyphs). Watchers compare `serial` to notice a change (no autoload needed).
##
## While touch is in use the mouse buttons are taken off the actions (shoot, aim):
## the browser and Godot turn every tap into a mouse click as well, and that must not
## fire a gun. They are put back as soon as the mouse or keyboard is used again.

enum { KEYBOARD, TOUCH, GAMEPAD }
const NAMES := ["Keyboard / mouse", "Touch", "Gamepad"]
## Settings "Control scheme": 0 Auto, then a fixed scheme (KEYBOARD + 1 ...)
const SCHEMES := ["Auto", "Keyboard / mouse", "Touch", "Gamepad"]

static var active := KEYBOARD
static var scheme := 0                 # 0 auto, 1 keyboard, 2 touch, 3 gamepad
static var serial := 0                 # bumps on every change of `active`
static var _last_touch_ms := -100000
static var _stashed := {}              # action -> [mouse button events] while on touch


## Start-up choice: touch on phones/tablets, keyboard elsewhere (a gamepad takes over the
## moment it's used).
static func reset_for_device() -> void:
	if scheme != 0:
		_switch_to(scheme - 1)
	else:
		_switch_to(TOUCH if DeviceProfile.touch and DeviceProfile.is_handheld() else KEYBOARD)


static func set_scheme(s: int) -> void:
	scheme = clampi(s, 0, 3)
	reset_for_device()


static func is_touch() -> bool:
	return active == TOUCH


static func is_pad() -> bool:
	return active == GAMEPAD


## Feed every input event here (from an _input handler).
static func note(event: InputEvent) -> void:
	var want := -1
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_last_touch_ms = Time.get_ticks_msec()
		want = TOUCH
	elif event is InputEventJoypadButton:
		want = GAMEPAD
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			want = GAMEPAD
	elif event is InputEventKey:
		want = KEYBOARD
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		# taps also arrive as (emulated) mouse events: ignore those and anything just after a touch
		if event.device == InputEvent.DEVICE_ID_EMULATION or Time.get_ticks_msec() - _last_touch_ms < 800:
			return
		if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() < 4.0:
			return
		want = KEYBOARD
	if want < 0:
		return
	if scheme != 0:
		return                            # fixed in Settings
	_switch_to(want)


static func _switch_to(m: int) -> void:
	if m == active and serial > 0:
		return
	active = m
	serial += 1
	InputGlyphs.pad = m == GAMEPAD
	InputGlyphs.touch = m == TOUCH
	_mouse_buttons(m != TOUCH)


## Takes the mouse buttons off (touch) or puts them back on (other schemes) every action.
static func _mouse_buttons(on: bool) -> void:
	if on:
		for a in _stashed:
			if InputMap.has_action(a):
				for e in _stashed[a]:
					InputMap.action_add_event(a, e)
		_stashed.clear()
		return
	for a in InputMap.get_actions():
		if String(a).begins_with("ui_"):
			continue
		for e in InputMap.action_get_events(a):
			if e is InputEventMouseButton:
				if not _stashed.has(a):
					_stashed[a] = []
				_stashed[a].append(e)
				InputMap.action_erase_event(a, e)
