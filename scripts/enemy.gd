class_name Enemy
extends Node2D
## Raiders (fast strafing fighters), bombers (slow station-busters) and rogue
## meteors (ram the station).

var kind := "raider"
var hp := 20.0
var max_hp := 20.0
var speed := 160.0
var color := Color(1, 0.25, 0.3)
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
var _body: Sprite2D
var _flames := []


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
			_add_flame(Vector2(-16, 0), 0.55)
			_body = Gfx.sprite("raider")
		"bomber":
			hp = 110.0 * mult
			speed = 70.0
			color = Color(1, 0.2, 0.65)
			hit_radius = 32.0
			reward = 45.0
			_add_flame(Vector2(-32, -11), 0.5)
			_add_flame(Vector2(-32, 11), 0.5)
			_body = Gfx.sprite("bomber")
		"meteor":
			var r := rng.randf_range(22.0, 36.0)
			hp = 40.0 * mult * (r / 29.0)
			speed = minf(95.0 + 3.0 * w, 160.0)
			color = Color(1, 0.5, 0.15)
			hit_radius = r
			reward = 10.0
			spin = rng.randf_range(-1.5, 1.5)
			_body = Gfx.sprite("meteor%d" % rng.randi_range(0, 5))
			_body.scale = Vector2.ONE * (r / 30.0)
	max_hp = hp
	add_child(_body)
	z_index = 4


func _add_flame(at: Vector2, sc: float) -> void:
	var f := Gfx.sprite("flame", Color(1, 0.6, 0.35) if kind == "raider" else Color(1, 0.5, 0.8))
	f.position = at
	f.scale = Vector2(sc, sc * 0.6)
	add_child(f)
	_flames.append(f)


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
		fx_t = (0.035 if kind == "meteor" else 0.06) * (2.5 if g.low_quality else 1.0)
		var back := -vel.normalized()
		var off := hit_radius * (0.7 if kind == "meteor" else 0.9)
		var c := color if kind != "meteor" else Color(1, randf_range(0.35, 0.75), 0.1)
		g.fx.spark(position + back * off + Vector2(randf_range(-4, 4), randf_range(-4, 4)), back * randf_range(30, 90) + vel * 0.3, c, randf_range(1.5, 3.2) if kind == "meteor" else 1.6, randf_range(0.3, 0.7))
	_update_visuals()


func _update_visuals() -> void:
	var white := Color(1, 1, 1)
	if kind == "meteor":
		var fl := 0.9 + 0.15 * sin(t * 20.0)
		Gfx.tint(_body, Color(fl, fl, fl).lerp(white * 1.6, flash * 6.0))
	else:
		Gfx.tint(_body, white.lerp(Color(1.8, 1.8, 1.8), flash * 6.0))
		for i in _flames.size():
			var f: Sprite2D = _flames[i]
			f.scale.x = (0.45 + 0.15 * sin(t * 38.0 + i)) * (1.0 if kind == "raider" else 0.9)


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
