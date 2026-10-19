class_name Bolt
extends Node2D
## Enemy blaster bolt. Hits the station or any allied ship it touches.

var vel := Vector2.ZERO
var dmg := 4.0
var col := Color(1, 0.3, 0.3)
var size := 3.0
var life := 1.8


func _ready() -> void:
	z_index = 6
	rotation = vel.angle()
	var sp := Gfx.sprite("bolt", col)
	sp.scale = Vector2(1.0 + size * 0.1, size / 3.0)
	add_child(sp)


func _process(delta: float) -> void:
	var g := Game.inst
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	position += vel * delta
	var st: Station = g.station
	if not st.dead and position.distance_to(st.position) < st.radius + 10.0:
		st.damage(dmg)
		g.fx.burst(position, col, 6, 100.0, 1.6, 0.3)
		queue_free()
		return
	for a in g.allies:
		if a.dead:
			continue
		if position.distance_to(a.position) < a.hit_radius + size:
			a.damage(dmg)
			g.fx.burst(position, col, 6, 100.0, 1.6, 0.3)
			queue_free()
			return
