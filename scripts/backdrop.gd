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


var _neb: NebulaLayer
var _cam_last := Vector2(INF, INF)


func _process(delta: float) -> void:
	t += delta
	var g := Game.inst
	if g == null or g.camera == null:
		return
	if _neb == null and Gfx.ready:
		_neb = NebulaLayer.new()
		_neb.bd = self
		_neb.material = Gfx.premult
		_neb.show_behind_parent = true
		add_child(_neb)
	# stars only need redrawing when the camera moves (twinkle is skipped in low quality)
	var cam: Vector2 = g.camera.position
	if not g.low_quality or cam.distance_squared_to(_cam_last) > 0.25:
		_cam_last = cam
		queue_redraw()
		if _neb != null:
			_neb.queue_redraw()


func _draw() -> void:
	var g := Game.inst
	if g == null or g.camera == null:
		return
	var vs := get_viewport_rect().size
	var cam: Vector2 = g.camera.position
	var tw_on := not g.low_quality
	for L in layers:
		var f: float = L.f
		var off := Vector2(fposmod(-cam.x * f, TILE), fposmod(-cam.y * f, TILE))
		var nx := int(ceil(vs.x / TILE)) + 1
		var ny := int(ceil(vs.y / TILE)) + 1
		for tx in range(0, nx + 1):
			for ty in range(0, ny + 1):
				var base := off + Vector2((tx - 1) * TILE, (ty - 1) * TILE)
				for st in L.stars:
					var p: Vector2 = base + st[0]
					if p.x < -4 or p.y < -4 or p.x > vs.x + 4 or p.y > vs.y + 4:
						continue
					var tw: float = (0.7 + 0.3 * sin(t * 1.5 + st[4])) if tw_on else 0.85
					var c: Color = st[3]
					var sz: float = st[1]
					if sz > 1.4:
						draw_rect(Rect2(p - Vector2(2.5, 2.5) * sz * 0.5, Vector2(2.5, 2.5) * sz), Color(c, 0.07 * tw))
					draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(c, st[2] * tw * 0.85))


class NebulaLayer extends Node2D:
	var bd

	func _draw() -> void:
		var g := Game.inst
		if g.low_quality:
			return
		var vs := get_viewport_rect().size
		var cam: Vector2 = g.camera.position
		for n in bd.nebulae:
			var p: Vector2 = (n[0] - cam * 0.05) * 0.5 + vs * 0.5
			var r: float = n[1]
			if p.x < -r or p.y < -r or p.x > vs.x + r or p.y > vs.y + r:
				continue
			var c: Color = n[2]
			Gfx.blit(self, "blob", p, r / 128.0, Color(c, 0.2))
