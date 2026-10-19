class_name Backdrop
extends Node2D
## Screen-space parallax starfield + nebula, drawn on a background CanvasLayer.

const TILE := 1024.0

var layers := []  # each: {factor, stars: [[pos, size, bright, hue]]}
var nebulae := []
var t := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	var specs := [[0.08, 70, 0.8], [0.2, 60, 1.2], [0.4, 40, 1.7]]
	for sp in specs:
		var stars := []
		for i in sp[1]:
			var hue := rng.randf()
			var c := Color(0.75, 0.85, 1.0)
			if hue < 0.15:
				c = Color(1.0, 0.85, 0.7)
			elif hue < 0.25:
				c = Color(0.8, 0.7, 1.0)
			stars.append([Vector2(rng.randf() * TILE, rng.randf() * TILE), sp[2] * rng.randf_range(0.6, 1.2), rng.randf_range(0.3, 1.0), c, rng.randf() * TAU])
		layers.append({"f": sp[0], "stars": stars})
	for i in 7:
		nebulae.append([Vector2(rng.randf_range(-3000, 3000), rng.randf_range(-3000, 3000)), rng.randf_range(500, 1100),
			[Color(0.35, 0.15, 0.6), Color(0.1, 0.3, 0.6), Color(0.05, 0.4, 0.45), Color(0.5, 0.1, 0.35)][i % 4]])


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var g := Game.inst
	if g == null or g.camera == null:
		return
	var vs := get_viewport_rect().size
	var cam: Vector2 = g.camera.position
	var center := vs * 0.5
	# nebulae
	for n in nebulae:
		var p: Vector2 = (n[0] - cam * 0.05) * 0.5 + center
		var r: float = n[1]
		var c: Color = n[2]
		for k in 5:
			var f := 1.0 - k * 0.18
			draw_circle(p, r * f, Color(c, 0.022))
	# stars
	for L in layers:
		var f: float = L.f
		var off := Vector2(fposmod(-cam.x * f, TILE), fposmod(-cam.y * f, TILE))
		var nx := int(ceil(vs.x / TILE)) + 1
		var ny := int(ceil(vs.y / TILE)) + 1
		for tx in range(-1, nx):
			for ty in range(-1, ny):
				var base := off + Vector2(tx * TILE, ty * TILE)
				for s in L.stars:
					var p: Vector2 = base + s[0]
					if p.x < -4 or p.y < -4 or p.x > vs.x + 4 or p.y > vs.y + 4:
						continue
					var tw: float = 0.7 + 0.3 * sin(t * 1.5 + s[4])
					var c: Color = s[3]
					var sz: float = s[1]
					if sz > 1.4:
						draw_circle(p, sz * 2.5, Color(c, 0.06 * tw))
						draw_circle(p, sz * 0.7, Color(c, s[2] * tw))
					else:
						draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(c, s[2] * tw * 0.8))
