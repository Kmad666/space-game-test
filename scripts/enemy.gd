class_name Enemy
extends Node2D
## Raiders (fast strafing fighters), bombers (slow station-busters) and rogue
## meteors (ram the station).

var kind := "raider"
var hp := 20.0
var max_hp := 20.0
var speed := 160.0
var color := Color(1, 0.25, 0.3)
var shape := PackedVector2Array()
var vel := Vector2.ZERO
var target = null
var retarget_t := 0.0
var fire_cd := 1.0
var hit_radius := 13.0
var reward := 15.0
var dead := false
var spin := 0.0
var t := 0.0
var flash := 0.0
var orbit_sign := 1.0
var wave := 1
var fx_t := 0.0
var fill_ok := true


func setup(k: String, w: int, rng: RandomNumberGenerator) -> void:
	kind = k
	wave = w
	var mult := 1.0 + 0.22 * (w - 1)
	orbit_sign = 1.0 if rng.randf() < 0.5 else -1.0
	fire_cd = rng.randf_range(0.5, 1.5)
	t = rng.randf() * 5.0
	match kind:
		"raider":
			hp = 22.0 * mult
			speed = minf(165.0 + 4.0 * w, 235.0)
			color = Color(1, 0.25, 0.32)
			hit_radius = 17.0
			reward = 15.0
			shape = Neon.mirror([Vector2(17, 0), Vector2(3, -4), Vector2(9, -13), Vector2(-3, -10), Vector2(-11, -15), Vector2(-8, -4), Vector2(-12, 0)], 1.4)
			scale = Vector2.ONE
		"bomber":
			hp = 110.0 * mult
			speed = 70.0
			color = Color(1, 0.2, 0.65)
			hit_radius = 32.0
			reward = 45.0
			shape = Neon.mirror([Vector2(22, 0), Vector2(14, -8), Vector2(4, -10), Vector2(0, -20), Vector2(-14, -22), Vector2(-10, -10), Vector2(-20, -8), Vector2(-18, 0)], 1.75)
		"meteor":
			var r := rng.randf_range(22.0, 36.0)
			hp = 40.0 * mult * (r / 29.0)
			speed = minf(95.0 + 3.0 * w, 160.0)
			color = Color(1, 0.5, 0.15)
			hit_radius = r
			reward = 10.0
			shape = Neon.rock(rng, r, rng.randi_range(9, 12), 0.3)
			spin = rng.randf_range(-1.5, 1.5)
	max_hp = hp
	fill_ok = not Geometry2D.triangulate_polygon(shape).is_empty()
	z_index = 4


func _process(delta: float) -> void:
	var g := Game.inst
	t += delta
	flash = maxf(0.0, flash - delta)
	match kind:
		"raider":
			_raider(delta)
		"bomber":
			_bomber(delta)
		"meteor":
			_meteor(delta)
	if dead:
		return
	position += vel * delta
	var lim := Game.WORLD_HALF + 400.0
	if absf(position.x) > lim or absf(position.y) > lim:
		remove(false)
		return
	fx_t -= delta
	if fx_t <= 0.0:
		fx_t = 0.035 if kind == "meteor" else 0.06
		var back := -vel.normalized()
		var off := hit_radius * (0.7 if kind == "meteor" else 0.9)
		var c := color if kind != "meteor" else Color(1, randf_range(0.35, 0.75), 0.1)
		g.fx.spark(position + back * off + Vector2(randf_range(-4, 4), randf_range(-4, 4)), back * randf_range(30, 90) + vel * 0.3, c, randf_range(1.5, 3.2) if kind == "meteor" else 1.6, randf_range(0.3, 0.7))
	queue_redraw()


func _raider(delta: float) -> void:
	var g := Game.inst
	retarget_t -= delta
	if retarget_t <= 0.0 or target == null or not is_instance_valid(target) or target.dead:
		retarget_t = 0.6
		target = g.nearest_ally(position, 320.0)
		if target == null:
			target = g.station
	var tp: Vector2 = target.position
	var to := tp - position
	var d := to.length()
	var dir := to / maxf(d, 1.0)
	var want_d := 200.0 if target != g.station else g.station.radius + 170.0
	var desired: Vector2
	if d > want_d + 60.0:
		desired = dir * speed
	else:
		var tang := dir.orthogonal() * orbit_sign
		desired = (tang + dir * clampf((d - want_d) / 80.0, -1.0, 1.0) * 0.6).normalized() * speed * 0.85
	vel = vel.lerp(desired, 1.0 - exp(-3.0 * delta))
	var face := vel.angle() if d > 340.0 else dir.angle()
	rotation = lerp_angle(rotation, face, 1.0 - exp(-8.0 * delta))
	fire_cd -= delta
	if d < 340.0 and fire_cd <= 0.0:
		fire_cd = randf_range(1.2, 1.7)
		var aim: Vector2 = (tp + (target.vel if "vel" in target else Vector2.ZERO) * 0.35 - position).normalized()
		g.spawn_bolt(position + aim * 14.0, aim * 360.0, 5.0 + 0.6 * wave, color, 3.0)


func _bomber(delta: float) -> void:
	var g := Game.inst
	var st: Station = g.station
	var to := st.position - position
	var d := to.length()
	var dir := to / maxf(d, 1.0)
	var stop := st.radius + 240.0
	var desired := dir * speed if d > stop else dir.orthogonal() * orbit_sign * speed * 0.35
	vel = vel.lerp(desired, 1.0 - exp(-2.0 * delta))
	rotation = lerp_angle(rotation, dir.angle(), 1.0 - exp(-3.0 * delta))
	fire_cd -= delta
	if d < stop + 140.0 and fire_cd <= 0.0:
		fire_cd = randf_range(2.2, 2.8)
		for s in [-1.0, 1.0]:
			var p := position + Vector2(12, 20.0 * s).rotated(rotation)
			g.spawn_bolt(p, (st.position - p).normalized() * 260.0, 13.0 + wave, Color(1, 0.35, 0.8), 6.0)


func _meteor(delta: float) -> void:
	var g := Game.inst
	rotation += spin * delta
	var st: Station = g.station
	if vel == Vector2.ZERO:
		vel = (st.position - position).normalized() * speed
	if position.distance_to(st.position) < st.radius + hit_radius:
		st.damage(24.0 + 2.0 * wave)
		g.shake = maxf(g.shake, 8.0)
		remove(false)
		return
	for a in g.allies:
		if a.dead:
			continue
		if position.distance_to(a.position) < a.hit_radius + hit_radius:
			a.damage(18.0)
			remove(false)
			return


func damage(amount: float, by_player: bool = false) -> void:
	if dead:
		return
	hp -= amount
	flash = 0.12
	if hp <= 0.0:
		var g := Game.inst
		g.on_enemy_killed(self, by_player)
		remove(true)


func remove(killed: bool) -> void:
	if dead:
		return
	dead = true
	var g := Game.inst
	var sc := 1.0
	if kind == "bomber":
		sc = 1.8
	elif kind == "meteor":
		sc = hit_radius / 18.0
	g.fx.explosion(position, color, sc)
	if kind == "meteor":
		g.fx.burst(position, Color(0.45, 0.35, 0.3), 12, 120.0, 3.5, 1.2)
	if not killed and kind != "meteor":
		pass
	g.enemies.erase(self)
	queue_free()


func _draw() -> void:
	var white := Color(1, 1, 1)
	var c := color.lerp(white, flash * 5.0)
	match kind:
		"meteor":
			var hot := (vel.normalized() * hit_radius * 0.5).rotated(-rotation)
			draw_circle(hot, hit_radius * 1.3, Color(1, 0.45, 0.1, 0.08))
			if fill_ok:
				draw_colored_polygon(shape, Color(0.13, 0.06, 0.03, 1))
			for i in 3:
				var a := TAU * i / 3.0 + 0.4
				draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(a) * hit_radius * 0.6, Color(1, 0.55, 0.15, 0.45), 1.5, true)
			Neon.outline(self, shape, c, 2.0, 0.9 + 0.2 * sin(t * 20.0))
		"raider":
			if fill_ok:
				draw_colored_polygon(shape, Color(0.14, 0.02, 0.04, 0.95))
			var fl := 6.0 + 4.0 * sin(t * 40.0)
			draw_colored_polygon(PackedVector2Array([Vector2(-16, -4), Vector2(-16 - fl * 1.3, 0), Vector2(-16, 4)]), Color(1, 0.6, 0.3, 0.8))
			Neon.outline(self, shape, c, 1.8, 1.0)
			Neon.dot(self, Vector2(7, -3.2), 1.8, Color(1, 0.9, 0.4), 0.9)
			Neon.dot(self, Vector2(7, 3.2), 1.8, Color(1, 0.9, 0.4), 0.9)
		"bomber":
			if fill_ok:
				draw_colored_polygon(shape, Color(0.13, 0.02, 0.09, 0.95))
			for s in [-1.0, 1.0]:
				var e := Vector2(-32, 11.0 * s)
				var fl := 8.0 + 5.0 * sin(t * 35.0 + s)
				draw_colored_polygon(PackedVector2Array([e + Vector2(0, -3), e + Vector2(-fl, 0), e + Vector2(0, 3)]), Color(1, 0.5, 0.8, 0.8))
			Neon.outline(self, shape, c, 2.2, 1.0)
			var hex := PackedVector2Array()
			for i in 6:
				hex.append(Vector2.RIGHT.rotated(TAU * i / 6.0 + t) * 10.0)
			Neon.outline(self, hex, Color(1, 0.6, 0.9), 1.4, 0.8)
			Neon.dot(self, Vector2.ZERO, 3.0 + sin(t * 6.0), Color(1, 0.4, 0.8), 1.0)

	# un-rotated overlays: health bar + lock reticle
	draw_set_transform(Vector2.ZERO, -rotation)
	if hp < max_hp:
		var w := hit_radius * 2.0
		var y := -hit_radius - 12.0
		draw_rect(Rect2(-w * 0.5, y, w, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w * 0.5, y, w * hp / max_hp, 3), Color(c, 0.9))
	var g := Game.inst
	if g.player != null and g.player.lock_target == self:
		var r := hit_radius + 10.0
		var rot := t * 2.0
		for i in 4:
			var a := rot + TAU * i / 4.0
			Neon.arc(self, Vector2.ZERO, r, a - 0.35, a + 0.35, Color(0.4, 0.95, 1.0), 1.6, 0.8, 6)
		var tri_d := r + 6.0
		for i in 4:
			var a := TAU * i / 4.0 + PI / 4.0
			var p := Vector2.RIGHT.rotated(a) * tri_d
			draw_line(p, p * 0.86, Color(0.4, 0.95, 1.0, 0.9), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0)
