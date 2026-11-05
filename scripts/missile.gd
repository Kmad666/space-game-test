class_name Missile
extends Node2D
## Homing stinger dart. Launches sideways, then accelerates and curves onto the
## locked target.

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
	add_child(Gfx.sprite("dart", col.lerp(Color.WHITE, 0.35)))


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
	if trail.size() > (7 if g.low_quality else 13):
		trail.remove_at(0)
	if target != null and position.distance_to(target.position) < target.hit_radius + 8.0:
		target.damage(dmg, by_player)
		_explode()


func _explode() -> void:
	var g := Game.inst
	g.fx.burst(position, col.lerp(Color(1, 0.9, 0.5), 0.4), 3 if g.low_quality else 7, 140.0, 2.0, 0.35)
	g.fx.ring(position, col, 18.0, 0.25, 1.6)
	queue_free()
