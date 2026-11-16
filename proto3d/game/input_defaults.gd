class_name InputDefaults
extends RefCounted
## Default controls for the 3D game: keyboard + mouse and gamepad (Xbox layout names).
## These are written into project.godot's Input Map (run proto3d/game/write_input_map.gd
## once after changing them); ensure() also adds any that are missing at runtime, and
## the Settings menu rebinds on top of them (saved in user://settings.cfg).

## action: [label shown in Settings, keyboard/mouse events, gamepad events]
## event forms: "key:W", "mouse:1", "joy:0" (button), "axis:1:-1" (axis, direction)
const ACTIONS := {
	"p3_forward": ["Forward / accelerate", ["key:W", "key:Up"], ["axis:1:-1", "axis:5:1"]],
	"p3_back": ["Back / brake / reverse", ["key:S", "key:Down"], ["axis:1:1", "axis:4:1"]],
	"p3_left": ["Left / steer left", ["key:A", "key:Left"], ["axis:0:-1"]],
	"p3_right": ["Right / steer right", ["key:D", "key:Right"], ["axis:0:1"]],
	"p3_look_left": ["Look left (stick)", [], ["axis:2:-1"]],
	"p3_look_right": ["Look right (stick)", [], ["axis:2:1"]],
	"p3_look_up": ["Look up (stick)", [], ["axis:3:-1"]],
	"p3_look_down": ["Look down (stick)", [], ["axis:3:1"]],
	"p3_sprint": ["Run", ["key:Shift"], ["joy:7"]],
	"p3_jump": ["Jump / handbrake", ["key:Space"], ["joy:0"]],
	"p3_fire": ["Shoot / punch", ["mouse:1"], ["joy:10"]],
	"p3_interact": ["Get in / out of a car", ["key:F"], ["joy:3"]],
	"p3_use": ["Use / talk", ["key:E"], ["joy:2"]],
	"p3_horn": ["Horn", ["key:H"], ["joy:1"]],
	"p3_hire": ["Taxi hire light", ["key:T"], ["joy:11"]],
	"p3_radio": ["Change radio station", ["key:R"], ["joy:14"]],
	"p3_camera": ["Switch camera view", ["key:V"], ["joy:8"]],
	"p3_weapon": ["Next weapon", ["key:Q"], []],
	"p3_wheel": ["Weapon wheel (hold)", ["key:Tab"], ["joy:9"]],
	"p3_aim": ["Aim", ["mouse:2"], ["axis:4:1"]],
	"p3_reload": ["Reload (on foot)", ["key:R"], ["joy:12"]],
	"p3_dodge": ["Dodge roll", ["key:C"], ["joy:1"]],
	"p3_crouch": ["Crouch", ["key:Ctrl"], ["joy:13"]],
	# gamepad: View is shared with the map: a tap opens the map, holding it uses the perk
	# (main_city.gd tells the two apart)
	"p3_ability": ["Perk ability (repair / call Big Talk)", ["key:B"], ["joy:4"]],
	"p3_fists": ["Fists", ["key:1"], []],
	"p3_pistol": ["Pistol", ["key:2"], []],
	"p3_slot_3": ["Baseball bat", ["key:3"], []],
	"p3_slot_4": ["Machete", ["key:4"], []],
	"p3_slot_5": ["SMG", ["key:5"], []],
	"p3_slot_6": ["Shotgun", ["key:6"], []],
	"p3_map": ["Map", ["key:M"], ["joy:4"]],
	"p3_pause": ["Pause", ["key:Escape"], ["joy:6"]],
	"p3_bug_report": ["Bug report", ["key:F8"], []],
}


static func make_event(spec: String) -> InputEvent:
	var p := spec.split(":")
	match p[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = OS.find_keycode_from_string(p[1])
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(p[1]) as MouseButton
			return m
		"joy":
			var j := InputEventJoypadButton.new()
			j.button_index = int(p[1]) as JoyButton
			return j
		"axis":
			var a := InputEventJoypadMotion.new()
			a.axis = int(p[1]) as JoyAxis
			a.axis_value = float(p[2])
			return a
	return null


static func events_for(action: String) -> Array:
	var out: Array = []
	var d: Array = ACTIONS[action]
	for s in d[1] + d[2]:
		var e := make_event(s)
		if e != null:
			out.append(e)
	return out


## Menu navigation on a gamepad (title, pause, shops, settings): the d-pad is in Godot's
## defaults; the left stick is added here, plus A / B for accept / back.
const UI_PAD := {
	"ui_up": ["axis:1:-1", "joy:11"], "ui_down": ["axis:1:1", "joy:12"],
	"ui_left": ["axis:0:-1", "joy:13"], "ui_right": ["axis:0:1", "joy:14"],
	"ui_accept": ["joy:0"], "ui_cancel": ["joy:1"],
}


## Adds any missing action with its default events (a safety net if project.godot lacks them).
static func ensure() -> void:
	for a in ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.25)
			for e in events_for(a):
				InputMap.action_add_event(a, e)
	ensure_ui_pad()


static func ensure_ui_pad() -> void:
	for a in UI_PAD:
		if not InputMap.has_action(a):
			continue
		for spec in UI_PAD[a]:
			var e := make_event(spec)
			if not InputMap.action_has_event(a, e):
				InputMap.action_add_event(a, e)


## Puts the actions back to their defaults (Settings: "Reset controls").
static func reset() -> void:
	for a in ACTIONS:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
		else:
			InputMap.add_action(a, 0.25)
		for e in events_for(a):
			InputMap.action_add_event(a, e)


## A short readable name for the first keyboard/mouse event of an action.
static func key_text(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return OS.get_keycode_string((e as InputEventKey).physical_keycode)
		if e is InputEventMouseButton:
			return ["", "Left mouse", "Right mouse", "Middle mouse"][clampi((e as InputEventMouseButton).button_index, 0, 3)]
	return "—"
