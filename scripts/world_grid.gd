class_name WorldGrid
extends Node2D
## Faint navigation grid and the glowing edge of the play area.

const STEP := 200.0


func _ready() -> void:
	z_index = -5


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var g := Game.inst
	if g == null or g.camera == null:
		return
	var vs := get_viewport_rect().size / g.camera.zoom
	var cam: Vector2 = g.camera.position
	var tl := cam - vs * 0.5 - Vector2(STEP, STEP)
	var br := cam + vs * 0.5 + Vector2(STEP, STEP)
	var W := Game.WORLD_HALF
	var col := Color(0.25, 0.5, 0.9, 0.07)
	var pts := PackedVector2Array()
	var x := floorf(tl.x / STEP) * STEP
	while x < br.x:
		if absf(x) <= W:
			pts.append(Vector2(x, maxf(tl.y, -W)))
			pts.append(Vector2(x, minf(br.y, W)))
		x += STEP
	var y := floorf(tl.y / STEP) * STEP
	while y < br.y:
		if absf(y) <= W:
			pts.append(Vector2(maxf(tl.x, -W), y))
			pts.append(Vector2(minf(br.x, W), y))
		y += STEP
	if pts.size() > 0 and not g.low_quality:
		draw_multiline(pts, col, 1.0)
	# boundary
	var rect := PackedVector2Array([Vector2(-W, -W), Vector2(W, -W), Vector2(W, W), Vector2(-W, W)])
	rect.append(rect[0])
	draw_polyline(rect, Color(1, 0.3, 0.4, 0.12), 14.0)
	draw_polyline(rect, Color(1, 0.3, 0.4, 0.7), 3.0)
