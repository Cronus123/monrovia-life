class_name InputGlyphs
extends RefCounted
## Button names for on-screen prompts, from the live Input Map (so rebinding in Settings
## shows up): keyboard/mouse as "[F]", gamepad (Xbox layout) as "(Y)". `pad` follows the
## last device the player touched (InputGlyphs.note(event) from an _input handler).

static var pad := false

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
	"move": ["[W A S D]", "(Left stick)"],
	"look": ["[Mouse]", "(Right stick)"],
	"drive": ["[W] [S] [A] [D]", "(RT) (LT) (Left stick)"],
}


static func note(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		pad = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false


## "[F]" or "(Y)" for an action (or a GROUPS name), "" if it has nothing on that device.
static func of(action: String) -> String:
	if GROUPS.has(action):
		return GROUPS[action][1 if pad else 0]
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
