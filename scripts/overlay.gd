class_name Overlay
extends Node2D
## World-space UI drawn in one place: mining beams, cargo rings, bot callsigns,
## shield hits, enemy health bars and the missile lock reticle.

var reticle: Sprite2D
var t := 0.0


func _ready() -> void:
	z_index = 7
	reticle = Gfx.sprite("reticle", Color(0.4, 0.95, 1.0))
	reticle.visible = false
	add_child(reticle)


func _process(delta: float) -> void:
	t += delta
	var g := Game.inst
	var lt = g.player.lock_target if g.player != null else null
	if lt != null and is_instance_valid(lt) and not lt.dead:
		reticle.visible = true
		reticle.position = lt.position
		reticle.rotation = t * 2.0
		reticle.scale = Vector2.ONE * ((lt.hit_radius + 10.0) / 26.0)
	else:
		reticle.visible = false
	queue_redraw()


func _draw() -> void:
	var g := Game.inst
	if g == null:
		return
	var font := ThemeDB.fallback_font
	var cargo_col := Color(0.8, 0.5, 1.0)
	for s in g.allies:
		if s.dead:
			continue
		var pos: Vector2 = s.position
		var hr: float = s.hit_radius
		var mt = s.mining_target
		if mt != null and is_instance_valid(mt):
			_beam(s, mt)
		if s.depositing:
			draw_line(pos, g.station.position, Color(cargo_col, 0.25), 2.0)
		if s.cargo > 0.0:
			var f: float = s.cargo / s.cargo_cap()
			draw_arc(pos, hr + 10.0, -PI * 0.5, -PI * 0.5 + TAU * f, 24, Color(cargo_col, 0.15), 7.0)
			draw_arc(pos, hr + 10.0, -PI * 0.5, -PI * 0.5 + TAU * f, 24, Color(cargo_col, 0.8), 2.5)
		if not s.is_player and not g.low_quality:
			draw_string(font, pos + Vector2(-50, -hr - 16), s.callsign, HORIZONTAL_ALIGNMENT_CENTER, 100, 11, Color(s.color, 0.65))
		if s.hit_flash > 0.0:
			draw_arc(pos, hr + 7.0, 0.0, TAU, 24, Color(s.color, s.hit_flash * 2.5), 2.0)
	for e in g.enemies:
		if e.dead or e.hp >= e.max_hp:
			continue
		var w: float = e.hit_radius * 2.0
		var p: Vector2 = e.position + Vector2(-w * 0.5, -e.hit_radius - 12.0)
		draw_rect(Rect2(p, Vector2(w, 3)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p, Vector2(w * e.hp / e.max_hp, 3)), Color(e.color, 0.9))


func _beam(s, a) -> void:
	var start: Vector2 = s.to_global(Ship.tier_data(s.tier).nose)
	var dir: Vector2 = (start - a.position).normalized()
	var end: Vector2 = a.position + dir * a.cur_radius() * 0.75
	var c: Color = a.color
	var pts := PackedVector2Array([start])
	var perp := (end - start).orthogonal().normalized()
	for i in range(1, 4):
		pts.append(start.lerp(end, i / 4.0) + perp * randf_range(-5.0, 5.0))
	pts.append(end)
	draw_polyline(pts, Color(c, 0.18), 8.0)
	draw_polyline(pts, Color(c.lerp(Color.WHITE, 0.5), 0.9), 2.0)
	draw_circle(end, 9.0, Color(c, 0.2))
	draw_circle(end, 3.5, Color(1, 1, 1, 0.9))
