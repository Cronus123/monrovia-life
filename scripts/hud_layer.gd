extends Control
## Full-screen Control that delegates its drawing to a Callable (the whole HUD).

var draw_fn: Callable

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# set_anchors_preset() alone keeps the old (zero) offsets, which left the HUD
	# at a tiny size and crammed the map, minimap and menus into the top-left corner.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	if draw_fn.is_valid():
		draw_fn.call(self)
