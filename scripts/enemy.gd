class_name Enemy
extends Node2D
## Hostile life.
## Field guardians (stay home, come back after being killed):
##   polyp   — rooted anemone in nectar blooms; spits spores, breeds mites
##   mite    — small fast biter that swarms intruders in a bloom
##   lurker  — translucent manta in the ice shelves; lies in wait, then lunges
##   spitter — rooted spine turret ringing the ore veins
## Raiders:
##   swarm   — swarmling packs that nibble hive modules until they go dark

var kind := "mite"
var tier := 1
var field = null
var slot := -1
var owner_polyp = null
var mites: Array = []
var hp := 20.0
var max_hp := 20.0
var hit_radius := 13.0
var speed := 150.0
var tm := 1.0
var mult := 1.0
var vel := Vector2.ZERO
var color := Gfx.C_FOE
var dead := false
var t := 0.0
var flash := 0.0
var target = null
var think_t := 0.0
var fire_cd := 1.0
var spawn_cd := 4.0
var bite_cd := 0.0
var state := "patrol"
var state_t := 0.0
var home := Vector2.ZERO
var wander := Vector2.ZERO
var wander_t := 0.0
var dash_dir := Vector2.ZERO
var dash_hit := false
var orbit := 1.0
var reward := 1
var nav_t := 0.0
var nav_pt := Vector2.ZERO

var _body: Sprite2D
var _veins: Sprite2D
var _parts: Array = []  # [sprite, base_rot, phase, kind]


func setup(k: String, pos: Vector2, f, wave: int) -> void:
	kind = k
	field = f
	position = pos
	home = pos
	wander = pos
	tier = f.tier if f != null else 1
	tm = 0.85 if tier == 1 else 1.45
	t = randf() * 5.0
	orbit = 1.0 if randf() < 0.5 else -1.0
	fire_cd = randf_range(0.6, 1.6)
	z_index = 4
	match kind:
		"mite":
			hp = 18.0 * tm
			speed = 150.0 if tier == 1 else 172.0
			hit_radius = 13.0
			_body = Gfx.sprite("mite")
		"polyp":
			hp = 280.0 * tm
			hit_radius = 30.0
			reward = 3
			for i in 7:
				var tp := Gfx.sprite("polyp_t")
				var a := TAU * i / 7.0
				tp.position = Vector2.RIGHT.rotated(a) * 18.0
				tp.rotation = a
				add_child(tp)
				_parts.append([tp, a, randf() * TAU, "tent"])
			_body = Gfx.sprite("polyp")
		"lurker":
			hp = 130.0 * tm
			speed = 70.0
			hit_radius = 24.0
			reward = 2
			for sd in [-1.0, 1.0]:
				var fn := Gfx.sprite("lurker_f")
				fn.position = Vector2(4, 5.0 * sd)
				fn.scale = Vector2(1, -sd)
				add_child(fn)
				_parts.append([fn, 0.0, 0.0, "fin%d" % int(sd)])
			_body = Gfx.sprite("lurker")
		"nestcore":
			hp = 1500.0 * tm
			hit_radius = 62.0
			reward = 10
			rotation = randf() * TAU
			_body = Gfx.sprite("nest")
		"spitter":
			hp = 150.0 * tm
			hit_radius = 22.0
			reward = 2
			rotation = randf() * TAU
			_body = Gfx.sprite("spitter")
		"swarm":
			mult = 1.0 + 0.08 * maxi(wave - 1, 0)
			hp = 14.0 * mult
			speed = 205.0
			hit_radius = 12.0
			color = Gfx.C_SWARM
			for sd in [-1.0, 1.0]:
				var w := Gfx.sprite("swarm_w")
				var root: Vector2 = Gfx.wing_roots(Gfx.swarm_spec())[0]
				w.position = Vector2(root.x, -root.y * sd)
				add_child(w)
				_parts.append([w, 0.0, randf() * TAU, "wing%d" % int(sd)])
			_body = Gfx.sprite("swarm")
			_veins = Gfx.sprite("swarm_v")
	max_hp = hp
	add_child(_body)
	if _veins != null:
		add_child(_veins)


func _zone_ok(p: Vector2) -> bool:
	return field == null or p.distance_to(field.position) < field.radius + 260.0


func _intruder(rng_max: float):
	var g := Game.inst
	var best = null
	var bd := rng_max
	for a in g.allies:
		if a.dead or not _zone_ok(a.position):
			continue
		var d: float = position.distance_to(a.position) * (1.0 if a.is_player else 1.5)
		if d < bd:
			bd = d
			best = a
	return best


func _process(delta: float) -> void:
	var g := Game.inst
	t += delta
	flash = maxf(0.0, flash - delta)
	bite_cd -= delta
	match kind:
		"mite":
			_mite(delta)
		"polyp":
			_polyp(delta)
		"lurker":
			_lurker(delta)
		"spitter":
			_spitter(delta)
		"swarm":
			_swarm(delta)
		"nestcore":
			_nestcore(delta)
	if dead:
		return
	position += vel * delta
	if kind == "mite" or kind == "lurker" or kind == "swarm":
		var c := g.cave.constrain(position, hit_radius * 0.6)
		if c != position:
			var nrm := (c - position).normalized()
			var vn := vel.dot(nrm)
			if vn < 0.0:
				vel -= nrm * vn
			position = c
			if kind == "lurker" and state == "dash":
				state = "recover"
				state_t = 1.0
	_update_visuals()
	visible = g.fog.is_seen(position)


func _update_visuals() -> void:
	var white := Color(1, 1, 1)
	var a := 1.0
	if kind == "lurker" and state == "patrol":
		a = 0.55
	var c := white.lerp(Color(2, 2, 2), flash * 6.0)
	if kind == "lurker" and state == "windup":
		c = Color(1.6, 1.2, 1.6)
	Gfx.tint(_body, Color(c, a))
	for p in _parts:
		var sp: Sprite2D = p[0]
		match p[3]:
			"tent":
				var sway := 0.35 * sin(t * (2.0 if target == null else 6.0) + p[2])
				sp.rotation = p[1] + sway
			"fin-1", "fin1":
				var sd := -1.0 if p[3] == "fin-1" else 1.0
				var ph := sin(t * (3.0 if state == "patrol" else 9.0))
				sp.scale = Vector2(1, -sd * lerpf(0.55, 1.1, 0.5 + 0.5 * ph))
				Gfx.tint(sp, Color(1, 1, 1, a))
			"wing-1", "wing1":
				var sd := -1.0 if p[3] == "wing-1" else 1.0
				var ph := sin(t * 24.0 + p[2])
				sp.scale = Vector2(1, -sd * lerpf(0.4, 1.0, absf(ph)))
				Gfx.tint(sp, Color(1, 1, 1, 0.5 + 0.3 * absf(ph)))
	if _veins != null:
		Gfx.tint(_veins, Color(1, 1, 1, 0.6 + 0.4 * sin(t * 5.0)))


func _face(dir: Vector2, delta: float, rate := 8.0) -> void:
	if dir.length_squared() > 1.0:
		rotation = lerp_angle(rotation, dir.angle(), 1.0 - exp(-rate * delta))


func _wander_to(center: Vector2, rad: float, spd: float, delta: float) -> void:
	wander_t -= delta
	if wander_t <= 0.0 or position.distance_to(wander) < 20.0:
		wander_t = randf_range(2.0, 4.0)
		wander = center + Vector2.RIGHT.rotated(randf() * TAU) * rad * sqrt(randf())
	var d := wander - position
	vel = vel.lerp(d.normalized() * spd * clampf(d.length() / 80.0, 0.2, 1.0), 1.0 - exp(-2.0 * delta))
	_face(vel, delta, 4.0)


func _mite(delta: float) -> void:
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.3
		target = _intruder(520.0)
	var hc: Vector2 = owner_polyp.position if (owner_polyp != null and is_instance_valid(owner_polyp)) else (field.position if field != null else home)
	if target != null and is_instance_valid(target) and not target.dead:
		var d: Vector2 = target.position - position
		vel = vel.lerp(d.normalized() * speed, 1.0 - exp(-5.0 * delta))
		_face(d, delta, 10.0)
		if d.length() < hit_radius + target.hit_radius + 4.0 and bite_cd <= 0.0:
			bite_cd = 0.8
			target.damage(5.0 * tm)
			Game.inst.fx.burst(target.position, color, 4, 80.0, 1.6, 0.25)
	else:
		_wander_to(hc, 200.0, speed * 0.4, delta)


func _polyp(delta: float) -> void:
	var g := Game.inst
	vel = Vector2.ZERO
	rotation += 0.15 * delta
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.3
		target = _intruder(440.0)
	spawn_cd -= delta
	var cap := 2 if tier == 1 else 4
	var i := 0
	while i < mites.size():
		if not is_instance_valid(mites[i]) or mites[i].dead:
			mites.remove_at(i)
		else:
			i += 1
	if spawn_cd <= 0.0 and mites.size() < cap:
		spawn_cd = 6.0
		var m: Enemy = g.spawn_enemy("mite", position + Vector2.RIGHT.rotated(randf() * TAU) * 30.0, field)
		m.owner_polyp = self
		mites.append(m)
		g.fx.burst(position, color, 8, 90.0, 2.0, 0.5)
	fire_cd -= delta
	if target != null and is_instance_valid(target) and not target.dead and fire_cd <= 0.0:
		fire_cd = 2.4
		var aim: Vector2 = (target.position + target.vel * 0.3 - position).normalized()
		for s in [-0.22, 0.0, 0.22]:
			var dir := aim.rotated(s)
			g.spawn_bolt(position + dir * 24.0, dir * 250.0, 6.0 * tm, color, "spore", 5.0)


func _lurker(delta: float) -> void:
	state_t -= delta
	var fc: Vector2 = field.position if field != null else home
	match state:
		"patrol":
			_wander_to(fc, field.radius * 0.7 if field != null else 200.0, speed, delta)
			think_t -= delta
			if think_t <= 0.0:
				think_t = 0.3
				target = _intruder(400.0)
				if target != null:
					state = "windup"
					state_t = 0.55
		"windup":
			vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-6.0 * delta))
			if target == null or not is_instance_valid(target) or target.dead:
				state = "patrol"
				return
			_face(target.position - position, delta, 12.0)
			if state_t <= 0.0:
				state = "dash"
				state_t = 0.55
				dash_hit = false
				dash_dir = (target.position + target.vel * 0.25 - position).normalized()
		"dash":
			vel = dash_dir * 560.0
			rotation = dash_dir.angle()
			if not dash_hit:
				for a in Game.inst.allies:
					if not a.dead and position.distance_to(a.position) < hit_radius + a.hit_radius:
						a.damage(16.0 * tm)
						dash_hit = true
						Game.inst.fx.burst(a.position, color, 10, 140.0, 2.0, 0.4)
						break
			if state_t <= 0.0:
				state = "recover"
				state_t = 1.4
		"recover":
			vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-3.0 * delta))
			if state_t <= 0.0:
				state = "patrol"
				if position.distance_to(fc) > (field.radius if field != null else 300.0) + 300.0:
					wander = fc
					wander_t = 4.0


func _spitter(delta: float) -> void:
	var g := Game.inst
	vel = Vector2.ZERO
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.3
		target = _intruder(560.0)
	fire_cd -= delta
	if target != null and is_instance_valid(target) and not target.dead:
		var lead: Vector2 = target.position + target.vel * (position.distance_to(target.position) / 430.0)
		var want := (lead - position).angle()
		rotation = lerp_angle(rotation, want, 1.0 - exp(-5.0 * delta))
		if fire_cd <= 0.0 and absf(wrapf(want - rotation, -PI, PI)) < 0.3:
			fire_cd = 1.8
			var dir := Vector2.RIGHT.rotated(rotation)
			g.spawn_bolt(position + dir * 36.0, dir * 430.0, 7.0 * tm, color, "spine", 3.0)
	else:
		rotation += 0.2 * delta


func _swarm(delta: float) -> void:
	var g := Game.inst
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.5
		var ship = g.nearest_ally(position, 140.0)
		if ship != null:
			target = ship
		elif target == null or not is_instance_valid(target) or (target is HiveModule and not target.online()) or (target is Ship and target.dead):
			target = _pick_module()
	if target == null or not is_instance_valid(target):
		_wander_to(Vector2.ZERO, 900.0, speed * 0.5, delta)
		return
	var tr: float = (target.radius() + 18.0) if target is HiveModule else (target.hit_radius + 10.0)
	var d: Vector2 = target.position - position
	var dist := d.length()
	if dist > tr + 40.0:
		nav_t -= delta
		if nav_t <= 0.0 or position.distance_to(nav_pt) < 50.0:
			nav_t = 0.4
			nav_pt = g.cave.steer(position, target.position)
		var nd := nav_pt - position
		vel = vel.lerp(nd.normalized() * speed, 1.0 - exp(-3.0 * delta))
	else:
		var tang := d.orthogonal().normalized() * orbit
		var radial := d / maxf(dist, 1.0) * clampf((dist - tr) / 30.0, -1.0, 1.0)
		vel = vel.lerp((tang + radial).normalized() * speed * 0.7, 1.0 - exp(-5.0 * delta))
		if bite_cd <= 0.0:
			bite_cd = 0.7
			if target is HiveModule:
				target.damage(3.0 * mult)
			else:
				target.damage(2.0 * mult)
			g.fx.burst(position + d * 0.6, color, 3, 70.0, 1.5, 0.25)
	_face(vel, delta, 10.0)


func _nestcore(delta: float) -> void:
	var g := Game.inst
	vel = Vector2.ZERO
	rotation += 0.1 * delta
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.3
		target = _intruder(540.0)
	fire_cd -= delta
	if target != null and is_instance_valid(target) and not target.dead and fire_cd <= 0.0:
		fire_cd = 2.2
		var aim: Vector2 = (target.position + target.vel * 0.3 - position).normalized()
		for s in [-0.4, -0.2, 0.0, 0.2, 0.4]:
			var dir := aim.rotated(s)
			g.spawn_bolt(position + dir * 60.0, dir * 240.0, 8.0, color, "spore", 6.0)


func _pick_module():
	var g := Game.inst
	var cands := []
	for m in g.hive.built_modules():
		if m.online():
			cands.append([position.distance_to(m.position), m])
	if cands.is_empty():
		return null
	cands.sort_custom(func(a, b): return a[0] < b[0])
	return cands[randi() % mini(3, cands.size())][1]


func damage(amount: float, by_player: bool = false) -> void:
	if dead:
		return
	hp -= amount
	flash = 0.12
	if kind == "lurker" and state == "patrol":
		target = Game.inst.nearest_ally(position, 600.0)
		if target != null:
			state = "windup"
			state_t = 0.4
	if hp <= 0.0:
		die(by_player)


func die(by_player: bool) -> void:
	if dead:
		return
	dead = true
	var g := Game.inst
	var sc := 1.0
	match kind:
		"polyp":
			sc = 2.0
		"lurker", "spitter":
			sc = 1.5
		"nestcore":
			sc = 3.5
		"mite", "swarm":
			sc = 0.7
	g.fx.explosion(position, color, sc)
	g.fx.burst(position, Color(0.5, 0.9, 0.5), int(6 * sc), 100.0 * sc, 2.4, 0.9)
	g.on_enemy_killed(self, by_player)
	if field != null and slot >= 0:
		field.on_guardian_died(slot)
	g.enemies.erase(self)
	queue_free()
