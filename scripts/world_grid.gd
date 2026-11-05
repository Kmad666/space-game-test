class_name WorldGrid
extends Node2D
## The membrane at the edge of the known dark: a soft crimson boundary.


func _ready() -> void:
	z_index = -5


func _draw() -> void:
	var W := Game.WORLD_HALF
	var rect := PackedVector2Array([Vector2(-W, -W), Vector2(W, -W), Vector2(W, W), Vector2(-W, W), Vector2(-W, -W)])
	draw_polyline(rect, Color(1, 0.3, 0.45, 0.1), 30.0)
	draw_polyline(rect, Color(1, 0.3, 0.45, 0.55), 3.0)
