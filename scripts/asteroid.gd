class_name Asteroid
extends Node2D
## A mineable rock studded with glowing crystals. Shrinks as it is mined.

var radius := 40.0
var ore := 40.0
var ore_max := 40.0
var value := 1.0
var gold := false
var color := Color(0.78, 0.45, 1.0)
var shape := PackedVector2Array()
var crystals := []
var cracks := []
var spin := 0.0
var depleted := false
var flash := 0.0
var t := 0.0
var _redraw_t := 0.0
var _near := false


func setup(r: float, is_gold: bool, rng: RandomNumberGenerator) -> void:
	radius = r
	gold = is_gold
	ore_max = r * (0.55 if gold else 0.9)
	ore = ore_max
	value = 3.0 if gold else 1.0
	color = Color(1.0, 0.8, 0.28) if gold else Color(0.78, 0.45, 1.0)
	shape = Neon.rock(rng, 1.0, rng.randi_range(11, 15), 0.28)
	spin = rng.randf_range(-0.25, 0.25)
	t = rng.randf() * 10.0
	var nc := rng.randi_range(3, 6)
	for i in nc:
		var p := Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(0.05, 0.6)
		crystals.append([p, rng.randf() * TAU, rng.randf_range(0.14, 0.26), rng.randf() * TAU])
	for i in rng.randi_range(2, 4):
		var a := Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(0.2, 0.8)
		var b := a + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(0.2, 0.4)
		cracks.append([a, b])
	z_index = 0


func cur_radius() -> float:
	return radius * lerpf(0.5, 1.0, ore / ore_max)


func take(amt: float) -> float:
	if depleted:
		return 0.0
	var a := minf(amt, ore)
	ore -= a
	flash = 0.12
	if ore <= 0.05:
		deplete()
	return a


func deplete() -> void:
	depleted = true
	var g := Game.inst
	g.fx.burst(position, color, 26, 140.0, 2.5, 0.9)
	g.fx.burst(position, Color(0.5, 0.45, 0.55), 14, 90.0, 3.0, 1.2)
	g.fx.ring(position, color, cur_radius() * 2.0, 0.5, 2.0)
	g.on_asteroid_depleted(self)
	queue_free()


func _process(delta: float) -> void:
	t += delta
	rotation += spin * delta
	flash = maxf(0.0, flash - delta)
	var g := Game.inst
	var near := false
	if g.player != null and not g.player.dead:
		near = g.player.position.distance_to(position) < radius + g.player.mine_reach() + 220.0
	_redraw_t -= delta
	if flash > 0.0 or near or near != _near or _redraw_t <= 0.0:
		_redraw_t = 0.12
		queue_redraw()
	_near = near


func _draw() -> void:
	var r := cur_radius()
	var pts := Neon.scaled(Array(shape), r)
	var g := Game.inst
	# mining range hint when the player is close
	if _near and g.player != null:
		var reach := r + g.player.mine_reach()
		var in_range := g.player.position.distance_to(position) < reach
		var segs := 40
		var c := Color(color, 0.35 if in_range else 0.16)
		for i in segs:
			if i % 2 == 0:
				var a0 := TAU * i / segs - rotation
				draw_arc(Vector2.ZERO, reach, a0, a0 + TAU / segs, 3, c, 1.5, true)
	# body
	draw_colored_polygon(pts, Color(0.06, 0.05, 0.09, 0.96))
	draw_colored_polygon(Neon.scaled(Array(shape), r * 0.72), Color(0.09, 0.07, 0.13, 0.9))
	for cr in cracks:
		draw_line(cr[0] * r, cr[1] * r, Color(color, 0.22), 1.2, true)
	var rock_col := Color(0.55, 0.48, 0.7, 0.85).lerp(Color(1, 1, 1), flash * 4.0)
	Neon.outline(self, pts, rock_col, 1.6, 0.6)
	# crystals
	for c in crystals:
		var p: Vector2 = c[0] * r
		var sz: float = c[2] * r
		var ang: float = c[1]
		var pulse := 0.75 + 0.25 * sin(t * 2.2 + c[3])
		var dpts := PackedVector2Array([
			p + Vector2(sz, 0).rotated(ang), p + Vector2(0, sz * 0.45).rotated(ang),
			p + Vector2(-sz * 0.6, 0).rotated(ang), p + Vector2(0, -sz * 0.45).rotated(ang)])
		draw_circle(p, sz * 1.4, Color(color, 0.08 * pulse))
		draw_colored_polygon(dpts, Color(color, 0.55 * pulse))
		Neon.outline(self, dpts, Color(color.lerp(Color.WHITE, 0.3 + flash * 3.0), pulse), 1.2, 0.8)
