extends CanvasLayer
## Minimal prototype HUD: control hints, view name, speed, FPS and a crosshair in first person.

var main                      # main_3d.gd
var _hint: Label
var _status: Label
var _cross: Control


func _ready() -> void:
	_hint = _label(Vector2(16, 12), 16)
	_hint.text = "WASD move   Shift sprint   Space jump / handbrake   F car   V camera   Esc mouse"
	_status = _label(Vector2(16, 40), 18)
	_cross = Control.new()
	_cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	add_child(_cross)


func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.1))
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	return l


func _draw_cross() -> void:
	if main == null or not main.rig.is_first_person() or main.rig.in_vehicle:
		return
	var c := _cross.size / 2.0
	var col := Color(1, 1, 1, 0.9)
	_cross.draw_circle(c, 2.0, col)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_cross.draw_line(c + d * 6.0, c + d * 13.0, col, 2.0)


func _process(_delta: float) -> void:
	if main == null:
		return
	var view: String = "First person" if main.rig.is_first_person() else "Third person"
	var where := "On foot"
	if main.car != null:
		where = "Driving  %d km/h  |  Damage %d%%" % [main.car.kmh(), int(main.car.damage)]
	var mouse := "" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "   (click to capture the mouse)"
	_status.text = "%s  |  %s  |  %d FPS%s" % [view, where, Engine.get_frames_per_second(), mouse]
	var near: bool = main.car == null and main.nearest_car() != null
	_hint.modulate = Color(1, 0.9, 0.4) if near else Color.WHITE
	_cross.queue_redraw()
