class_name ResNode
extends Node2D
## One harvestable growth inside a field: an amber nectar bloom, a rime crystal
## cluster or an ore geode. Shrinks as it is mined; its field regrows it later.

var kind := "nectar"
var amount := 40.0
var amount_max := 40.0
var radius := 34.0
var rich := 1.0
var field
var depleted := false
var color := Color.WHITE
var spin := 0.0
var flash := 0.0
var _body: Sprite2D
var _hint: Sprite2D
var _last_scale := -1.0


func setup(k: String, amt: float, r: float, f, rng: RandomNumberGenerator) -> void:
	kind = k
	amount_max = amt
	amount = amt
	radius = r
	field = f
	rich = 1.45 if f.tier == 2 else 1.0
	color = Gfx.res_color(k)
	spin = rng.randf_range(-0.15, 0.15)
	rotation = rng.randf() * TAU
	_body = Gfx.sprite("%s%d" % [k, rng.randi_range(0, 3)])
	add_child(_body)
	_hint = Gfx.sprite("dashring", Color(color, 0.2))
	_hint.visible = false
	add_child(_hint)
	_apply_scale()
	z_index = 0


func cur_radius() -> float:
	return radius * lerpf(0.55, 1.0, amount / amount_max)


func _apply_scale() -> void:
	var sc := cur_radius() / 40.0
	if absf(sc - _last_scale) > 0.004:
		_last_scale = sc
		_body.scale = Vector2.ONE * sc


func take(amt: float) -> float:
	if depleted:
		return 0.0
	var a := minf(amt, amount)
	amount -= a
	flash = 0.12
	if amount <= 0.05:
		deplete()
	return a


func deplete() -> void:
	if depleted:
		return
	depleted = true
	var g := Game.inst
	g.fx.burst(position, color, 18, 120.0, 2.4, 0.8)
	g.fx.ring(position, color, cur_radius() * 1.8, 0.5, 2.0)
	g.res_nodes.erase(self)
	if field != null:
		field.on_node_depleted(self)
	queue_free()


func _process(delta: float) -> void:
	rotation += spin * delta
	if flash > 0.0:
		flash = maxf(0.0, flash - delta)
		Gfx.tint(_body, Color(1, 1, 1).lerp(Color(1.6, 1.6, 1.6), flash * 6.0))
		_apply_scale()
	var p: Ship = Game.inst.player
	if p != null and not p.dead and p.position.distance_squared_to(position) < pow(radius + p.mine_reach() + 200.0, 2.0):
		var reach := cur_radius() + p.mine_reach()
		var in_range := p.position.distance_to(position) < reach
		_hint.visible = true
		_hint.scale = Vector2.ONE * (reach / 128.0)
		_hint.rotation = -rotation
		Gfx.tint(_hint, Color(color, 0.42 if in_range else 0.16))
	elif _hint.visible:
		_hint.visible = false
