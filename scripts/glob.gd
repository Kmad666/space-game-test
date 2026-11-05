class_name Glob
extends Node2D
## A floating blob of resource spilled by a slain Reaper. Fly through it to
## scoop it into your cargo, then haul it home.

var kind := "nectar"
var amount := 15.0
var vel := Vector2.ZERO
var life := 75.0
var depleted := false
var color := Color.WHITE
var _g: Sprite2D
var _d: Sprite2D
var t := 0.0


func setup(k: String, amt: float, pos: Vector2) -> void:
	kind = k
	amount = amt
	position = pos
	color = Gfx.res_color(k)
	vel = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60.0, 160.0)
	t = randf() * 5.0
	z_index = 3
	_g = Gfx.sprite("glow", Color(color, 0.6))
	_g.scale = Vector2.ONE * 0.4
	add_child(_g)
	_d = Gfx.sprite("dot", color.lerp(Color.WHITE, 0.3))
	_d.scale = Vector2.ONE * 0.9
	add_child(_d)


func cur_radius() -> float:
	return 14.0


func _process(delta: float) -> void:
	var g := Game.inst
	t += delta
	life -= delta
	vel *= exp(-1.2 * delta)
	position += vel * delta
	var s := 0.9 + 0.15 * sin(t * 4.0)
	_d.scale = Vector2.ONE * s
	if life < 10.0:
		modulate.a = life / 10.0
	if life <= 0.0:
		_remove()
		return
	for a in g.allies:
		if a.dead or a.role == "guard":
			continue
		if position.distance_to(a.position) < a.hit_radius + 22.0:
			var room: float = a.cargo_cap() - a.cargo_total()
			if room <= 0.1:
				continue
			var take := minf(room, amount)
			a.cargo[kind] += take
			amount -= take
			g.fx.burst(position, color, 8, 90.0, 2.0, 0.4)
			if a.is_player:
				g.fx.text(position + Vector2(0, -20), "+%d %s" % [int(take), kind.to_upper()], color, 15)
			if amount < 0.5:
				_remove()
				return


func _remove() -> void:
	depleted = true
	Game.inst.globs.erase(self)
	queue_free()
