class_name Asteroid
extends Node2D
## A mineable rock studded with glowing crystals. Shrinks as it is mined.
## Visual is a pre-baked atlas sprite; nothing is redrawn per frame.

var radius := 40.0
var ore := 40.0
var ore_max := 40.0
var value := 1.0
var gold := false
var color := Color(0.78, 0.45, 1.0)
var spin := 0.0
var depleted := false
var flash := 0.0
var _ref := 45.0
var _body: Sprite2D
var _hint: Sprite2D
var _last_scale := -1.0


func setup(r: float, is_gold: bool, rng: RandomNumberGenerator) -> void:
	radius = r
	gold = is_gold
	ore_max = r * (0.55 if gold else 0.9)
	ore = ore_max
	value = 3.0 if gold else 1.0
	color = Color(1.0, 0.8, 0.28) if gold else Color(0.78, 0.45, 1.0)
	spin = rng.randf_range(-0.25, 0.25)
	rotation = rng.randf() * TAU
	_ref = 30.0 if gold else 45.0
	var name := ("gold%d" % rng.randi_range(0, 3)) if gold else ("ast%d" % rng.randi_range(0, 9))
	_body = Gfx.sprite(name)
	add_child(_body)
	_hint = Gfx.sprite("dashring", Color(color, 0.2))
	_hint.visible = false
	add_child(_hint)
	_apply_scale()
	z_index = 0


func cur_radius() -> float:
	return radius * lerpf(0.5, 1.0, ore / ore_max)


func _apply_scale() -> void:
	var sc := cur_radius() / _ref
	if absf(sc - _last_scale) > 0.004:
		_last_scale = sc
		_body.scale = Vector2.ONE * sc


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
	rotation += spin * delta
	if flash > 0.0:
		flash = maxf(0.0, flash - delta)
		Gfx.tint(_body, Color(1, 1, 1).lerp(Color(1.5, 1.5, 1.5), flash * 6.0))
		_apply_scale()
	var g := Game.inst
	var p: Ship = g.player
	if p != null and not p.dead and p.position.distance_squared_to(position) < pow(radius + p.mine_reach() + 220.0, 2.0):
		var reach := cur_radius() + p.mine_reach()
		var in_range := p.position.distance_to(position) < reach
		_hint.visible = true
		_hint.scale = Vector2.ONE * (reach / 128.0)
		Gfx.tint(_hint, Color(color, 0.4 if in_range else 0.18))
	elif _hint.visible:
		_hint.visible = false
