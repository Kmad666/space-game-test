class_name Missile
extends Node2D
## Homing missile. Launches sideways off the wing, then accelerates and curves
## onto the locked target.

var vel := Vector2.ZERO
var target = null
var dmg := 10.0
var life := 3.0
var col := Color.WHITE
var speed := 170.0
var by_player := false
var trail := PackedVector2Array()
var t := 0.0


func _ready() -> void:
	z_index = 6


func _process(delta: float) -> void:
	var g := Game.inst
	t += delta
	life -= delta
	if life <= 0.0:
		_explode()
		return
	if target == null or not is_instance_valid(target) or target.dead:
		target = g.nearest_enemy(position, 420.0)
	speed = minf(speed + 950.0 * delta, 580.0)
	if target != null and t > 0.1:
		var want: float = (target.position - position).angle()
		var cur := vel.angle()
		var diff := wrapf(want - cur, -PI, PI)
		var turn := (5.0 + 12.0 * t) * delta
		vel = Vector2.RIGHT.rotated(cur + clampf(diff, -turn, turn))
	vel = vel.normalized() * speed
	position += vel * delta
	rotation = vel.angle()
	trail.append(position)
	if trail.size() > 16:
		trail.remove_at(0)
	if target != null and position.distance_to(target.position) < target.hit_radius + 8.0:
		target.damage(dmg, by_player)
		_explode()
		return
	queue_redraw()


func _explode() -> void:
	var g := Game.inst
	g.fx.burst(position, col.lerp(Color(1, 0.8, 0.4), 0.5), 9, 150.0, 2.0, 0.35)
	g.fx.ring(position, Color(1, 0.85, 0.5), 22.0, 0.25, 2.0)
	queue_free()


func _draw() -> void:
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	var n := trail.size()
	for i in range(1, n):
		var a := float(i) / n
		draw_line(trail[i - 1], trail[i], Color(col, a * 0.12), 7.0 * a, true)
		draw_line(trail[i - 1], trail[i], Color(col.lerp(Color.WHITE, 0.5), a * 0.6), 2.0 * a, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var body := PackedVector2Array([Vector2(8, 0), Vector2(-4, -2.6), Vector2(-2, 0), Vector2(-4, 2.6)])
	draw_colored_polygon(body, Color(1, 1, 1, 0.95))
	Neon.outline(self, body, col, 1.0, 0.8)
	Neon.dot(self, Vector2(-4, 0), 2.2, Color(1, 0.8, 0.45), 1.0)
