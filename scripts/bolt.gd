class_name Bolt
extends Node2D
## Enemy projectile (spore glob or spine). Hits any allied ship it touches.

var vel := Vector2.ZERO
var dmg := 4.0
var col := Gfx.C_FOE
var size := 3.0
var art := "spore"
var life := 2.0


func _ready() -> void:
	z_index = 6
	rotation = vel.angle()
	var sp := Gfx.sprite(art, col)
	if art == "spine":
		sp.scale = Vector2.ONE * (size / 3.0)
	else:
		sp.scale = Vector2.ONE * (size / 5.0)
	add_child(sp)


func _process(delta: float) -> void:
	var g := Game.inst
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	position += vel * delta
	if not g.cave.inside(position, 0.0):
		g.fx.burst(position, col, 4, 80.0, 1.6, 0.3)
		queue_free()
		return
	visible = g.fog.is_seen(position)
	for a in g.allies:
		if a.dead:
			continue
		if position.distance_to(a.position) < a.hit_radius + size:
			a.damage(dmg)
			g.fx.burst(position, col, 6, 100.0, 1.6, 0.3)
			queue_free()
			return
