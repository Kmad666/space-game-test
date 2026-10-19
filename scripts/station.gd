class_name Station
extends Node2D
## Aegis Station. Grows a level each time enough ore is delivered: bigger
## rings, more modules, solar arrays, defense turrets and a new escort bot.

const MAX_LEVEL := 12

var level := 1
var xp := 0.0
var hp := 400.0
var max_hp := 400.0
var radius := 80.0
var hit_radius := 80.0
var t := 0.0
var hit_flash := 0.0
var deposit_glow := 0.0
var level_pulse := 0.0
var dead := false
var turret_cd := []
var turret_aim := []


func _ready() -> void:
	z_index = 1
	_apply_level()
	hp = max_hp


func need() -> float:
	return roundf(80.0 * pow(level, 1.6))


func dock_radius() -> float:
	return radius + 90.0


func turret_count() -> int:
	return mini(level / 2, 6)


func turret_range() -> float:
	return 430.0 + 22.0 * level


func _apply_level() -> void:
	radius = minf(80.0 + 13.0 * (level - 1), 230.0)
	hit_radius = radius
	max_hp = 400.0 + 130.0 * (level - 1)
	while turret_cd.size() < turret_count():
		turret_cd.append(randf())
		turret_aim.append(0.0)


func deposit(amount: float) -> void:
	if dead:
		return
	deposit_glow = 1.0
	if level >= MAX_LEVEL:
		return
	xp += amount
	while xp >= need() and level < MAX_LEVEL:
		xp -= need()
		level += 1
		_apply_level()
		hp = max_hp
		level_pulse = 1.0
		Game.inst.on_station_level_up(level)


func damage(amount: float, _by_player: bool = false) -> void:
	if dead:
		return
	hp -= amount
	hit_flash = 0.3
	var g := Game.inst
	g.shake = maxf(g.shake, 3.0)
	g.station_hit_t = 1.2
	if hp <= 0.0:
		hp = 0.0
		dead = true
		g.station_destroyed()


func turret_pos(i: int) -> Vector2:
	var n := turret_count()
	var a := TAU * (float(i) + 0.5) / float(n) + t * 0.12
	return position + Vector2.RIGHT.rotated(a) * radius


func _process(delta: float) -> void:
	t += delta
	hit_flash = maxf(0.0, hit_flash - delta)
	deposit_glow = maxf(0.0, deposit_glow - delta * 2.0)
	level_pulse = maxf(0.0, level_pulse - delta * 0.7)
	if dead:
		queue_redraw()
		return
	hp = minf(max_hp, hp + (1.5 + 0.6 * level) * delta)
	var g := Game.inst
	for i in turret_count():
		turret_cd[i] -= delta
		var tp := turret_pos(i)
		var e = g.nearest_enemy(tp, turret_range())
		if e != null:
			turret_aim[i] = (e.position - tp).angle()
			if turret_cd[i] <= 0.0:
				turret_cd[i] = 1.15
				g.fx.beam(tp, e.position, Color(0.55, 0.95, 1.0), 0.14, 2.5)
				g.fx.burst(e.position, Color(0.6, 0.95, 1.0), 5, 90.0, 1.6, 0.3)
				e.damage(8.0 + 3.0 * level, false)
	queue_redraw()


func _draw() -> void:
	var R := radius
	var cyan := Color(0.4, 0.9, 1.0)
	var white := Color(1, 1, 1)
	var hurt := 1.0 - hp / max_hp
	var ring_col := cyan.lerp(Color(1, 0.35, 0.3), clampf(hurt * 1.3 - 0.3, 0.0, 0.8))

	# docking zone
	var dr := dock_radius()
	var segs := 48
	var dock_a := 0.14 + deposit_glow * 0.35
	for i in segs:
		if i % 2 == 0:
			var a0 := TAU * i / segs + t * 0.08
			draw_arc(Vector2.ZERO, dr, a0, a0 + TAU / segs * 0.9, 4, Color(cyan, dock_a), 2.0, true)
	draw_circle(Vector2.ZERO, dr, Color(cyan, 0.015 + deposit_glow * 0.03))

	# level-up shockwave
	if level_pulse > 0.0:
		Neon.ring(self, Vector2.ZERO, R + (1.0 - level_pulse) * 400.0, Color(cyan, level_pulse), 3.0)

	# solar arrays (level 3+)
	var arrays := 0
	if level >= 3:
		arrays = 2
	if level >= 6:
		arrays = 4
	if level >= 9:
		arrays = 6
	for i in arrays:
		var a := TAU * i / arrays + t * 0.05 + 0.4
		var dir := Vector2.RIGHT.rotated(a)
		var perp := dir.orthogonal()
		var L := 40.0 + 8.0 * level
		var W := 14.0 + level * 0.8
		var base := dir * (R + 6.0)
		var quad := PackedVector2Array([base + perp * W * 0.5, base + dir * L + perp * W * 0.5, base + dir * L - perp * W * 0.5, base - perp * W * 0.5])
		draw_colored_polygon(quad, Color(0.05, 0.12, 0.3, 0.9))
		for k in range(1, 5):
			var f := float(k) / 5.0
			draw_line(base + dir * L * f + perp * W * 0.5, base + dir * L * f - perp * W * 0.5, Color(0.3, 0.55, 1.0, 0.45), 1.0, true)
		draw_line(base, base + dir * L, Color(0.3, 0.55, 1.0, 0.4), 1.0, true)
		Neon.outline(self, quad, Color(0.4, 0.65, 1.0, 0.85), 1.2, 0.5)

	# outer ring + modules
	var nmod := 3 + level
	var ring_rot := t * 0.12
	draw_circle(Vector2.ZERO, R, Color(0.02, 0.05, 0.09, 0.6))
	Neon.ring(self, Vector2.ZERO, R, ring_col, 3.0, 1.0, 64)
	Neon.ring(self, Vector2.ZERO, R - 9.0, Color(ring_col, 0.35), 1.0, 0.4, 64)
	for i in nmod:
		var a := TAU * i / nmod + ring_rot
		var dir := Vector2.RIGHT.rotated(a)
		var perp := dir.orthogonal()
		Neon.line(self, dir * R * 0.36, dir * (R - 9.0), Color(cyan, 0.35), 1.2, 0.4)
		var c := dir * R
		var mw := 9.0 + level * 0.6
		var mh := 6.0 + level * 0.3
		var box := PackedVector2Array([c + perp * mw + dir * mh, c - perp * mw + dir * mh, c - perp * mw - dir * mh, c + perp * mw - dir * mh])
		draw_colored_polygon(box, Color(0.03, 0.09, 0.14, 1))
		Neon.outline(self, box, Color(ring_col, 0.95), 1.4, 0.6)
		var blink := 0.3 + 0.7 * maxf(0.0, sin(t * 3.0 + i * 1.3))
		Neon.dot(self, c + dir * (mh + 3.0), 1.6, Color(1, 0.85, 0.4), blink)

	# middle dashed ring (counter-rotating)
	var mid := R * 0.62
	var mseg := 12 + level * 2
	for i in mseg:
		var a0 := TAU * i / mseg - t * 0.3
		Neon.arc(self, Vector2.ZERO, mid, a0, a0 + TAU / mseg * 0.6, Color(0.6, 0.85, 1.0, 0.7), 2.0, 0.5, 4)

	# hub
	var hub := PackedVector2Array()
	var hsides := 6 if level < 5 else 8
	for i in hsides:
		hub.append(Vector2.RIGHT.rotated(TAU * i / hsides + t * 0.2) * R * 0.34)
	draw_colored_polygon(hub, Color(0.03, 0.08, 0.16, 1))
	Neon.outline(self, hub, Color(0.7, 0.95, 1.0), 2.0, 0.8)

	# core
	var pulse := 0.85 + 0.15 * sin(t * 3.0) + deposit_glow * 0.4
	Neon.dot(self, Vector2.ZERO, R * 0.11 * pulse, Color(0.75, 0.6, 1.0).lerp(white, 0.2), 1.0)
	draw_circle(Vector2.ZERO, R * 0.24, Color(0.75, 0.6, 1.0, 0.05 + deposit_glow * 0.12))

	# turrets
	for i in turret_count():
		var tp := turret_pos(i) - position
		var a: float = turret_aim[i]
		var tri := PackedVector2Array([tp + Vector2(11, 0).rotated(a), tp + Vector2(-6, -6).rotated(a), tp + Vector2(-6, 6).rotated(a)])
		draw_colored_polygon(tri, Color(0.05, 0.12, 0.18, 1))
		Neon.outline(self, tri, white.lerp(cyan, 0.4), 1.4, 0.8)

	# shield flash
	if hit_flash > 0.0:
		Neon.ring(self, Vector2.ZERO, R + 16.0, Color(0.5, 0.85, 1.0, hit_flash * 2.5), 2.5, 1.0, 64)
