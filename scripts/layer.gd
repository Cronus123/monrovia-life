extends Node2D
## A Node2D that delegates its drawing to a Callable (used for chunks, roads, actors).

var draw_fn: Callable

func _draw() -> void:
	if draw_fn.is_valid():
		draw_fn.call(self)
