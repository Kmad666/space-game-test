class_name Painter
extends Node2D
## Runs a draw callback once inside an offscreen SubViewport (used for baking).

var fn: Callable


func _draw() -> void:
	if fn.is_valid():
		fn.call(self)
