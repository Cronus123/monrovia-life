class_name InputGlyphs
extends RefCounted
## Button names for on-screen prompts, from the live Input Map (so rebinding in Settings
## shows up): keyboard/mouse as "[F]", gamepad (Xbox layout) as "(Y)", touch as the
## on-screen button's name, "(Car)". `pad` / `touch` follow the active control scheme
## (InputMode: the last device used, or the one fixed in Settings).

static var pad := false
static var touch := false

## On-screen touch button names (TouchControls) per action.
const TOUCH := {"p3_fire": "Shoot", "p3_jump": "Jump", "p3_aim": "Aim", "p3_interact": "Car",
	"p3_use": "Use", "p3_weapon": "Weapon", "p3_wheel": "Weapon", "p3_reload": "Reload", "p3_crouch": "Crouch",
	"p3_dodge": "Roll", "p3_horn": "Horn", "p3_radio": "Radio", "p3_hire": "Hire", "p3_pause": "II",
	"p3_map": "Map", "p3_camera": "View", "p3_ability": "Perk", "p3_sprint": "Stick to the edge",
	"p3_forward": "Stick", "p3_back": "Stick", "p3_left": "Stick", "p3_right": "Stick",
	"p3_fists": "Weapon", "p3_pistol": "Weapon", "p3_slot_3": "Weapon", "p3_slot_4": "Weapon",
	"p3_slot_5": "Weapon", "p3_slot_6": "Weapon"}
## Gamepad actions that are a long press rather than a button of their own.
const PAD_HOLD := {"p3_ability": "(hold View)"}

const JOY := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_DPAD_UP: "D-pad up",
	JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right"}
const AXIS := {JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT", JOY_AXIS_LEFT_X: "Left stick",
	JOY_AXIS_LEFT_Y: "Left stick", JOY_AXIS_RIGHT_X: "Right stick", JOY_AXIS_RIGHT_Y: "Right stick"}
const MOUSE := {MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse", MOUSE_BUTTON_MIDDLE: "Middle mouse",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down"}
## Groups of actions shown as one glyph.
const GROUPS := {
	"move": ["[W A S D]", "(Left stick)", "(Stick)"],
	"look": ["[Mouse]", "(Right stick)", "(drag on the right)"],
	"drive": ["[W] [S] [A] [D]", "(RT) (LT) (Left stick)", "(Stick)"],
}


## Kept for older callers: device tracking lives in InputMode now.
static func note(event: InputEvent) -> void:
	InputMode.note(event)


## "[F]", "(Y)" or "(Car)" for an action (or a GROUPS name), "" if it has nothing on that device.
static func of(action: String) -> String:
	if GROUPS.has(action):
		return GROUPS[action][2 if touch else (1 if pad else 0)]
	if touch and TOUCH.has(action):
		return "(%s)" % TOUCH[action]
	if pad and PAD_HOLD.has(action):
		return PAD_HOLD[action]
	if not InputMap.has_action(action):
		return ""
	var fallback := ""
	for e in InputMap.action_get_events(action):
		var s := _name(e)
		if s == "":
			continue
		var is_pad := e is InputEventJoypadButton or e is InputEventJoypadMotion
		if is_pad == pad:
			return s
		if fallback == "":
			fallback = s
	return fallback


static func _name(e: InputEvent) -> String:
	if e is InputEventKey:
		var k := e as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return "[%s]" % OS.get_keycode_string(code)
	if e is InputEventMouseButton:
		return "[%s]" % MOUSE.get((e as InputEventMouseButton).button_index, "Mouse")
	if e is InputEventJoypadButton:
		return "(%s)" % JOY.get((e as InputEventJoypadButton).button_index, "Button %d" % (e as InputEventJoypadButton).button_index)
	if e is InputEventJoypadMotion:
		return "(%s)" % AXIS.get((e as InputEventJoypadMotion).axis, "Stick")
	return ""


## "Press {p3_interact} to get in" -> "Press [F] to get in".
static func fill(text: String) -> String:
	var out := text
	var i := out.find("{")
	while i >= 0:
		var j := out.find("}", i)
		if j < 0:
			break
		var g := of(out.substr(i + 1, j - i - 1))
		out = out.substr(0, i) + g + out.substr(j + 1)
		i = out.find("{", i + g.length())
	return out
