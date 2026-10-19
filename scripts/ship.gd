class_name Ship
extends Node2D
## Player ship and allied bots. Same hull, stats and weapons; bots just get an
## AI brain instead of the mouse.

const TIER_NAMES := ["WISP", "HERMES", "PERSEUS", "ACHILLES", "ATLAS"]
const TIER_THRESH := [0, 4, 10, 18, 28]
const ACCEL := 3.6
const UPGRADE_KEYS := ["engine", "cargo", "drill", "missiles", "launcher", "targeting", "hull"]

static var _tier_cache := {}

var is_player := false
var callsign := ""
var color := Color(0.3, 0.92, 1.0)
var vel := Vector2.ZERO
var hp := 60.0
var cargo := 0.0
var cargo_value := 0.0
var levels := {}
var tier := 0
var dead := false
var respawn_t := 0.0
var invuln := 0.0
var hit_flash := 0.0
var thrust := 0.0
var t := 0.0
var hit_radius := 12.0

var lock_target = null
var lock_scan := 0.0
var fire_cd := 0.6
var side := 1.0
var mining_target = null
var mine_fx_t := 0.0
var depositing := false
var deposit_accum := 0.0
var trails := []

# bot brain
var ai_state := "mine"
var ai_ast = null
var ai_enemy = null
var think_t := 0.0
var orbit_phase := 0.0
var guard := false


func _ready() -> void:
	for k in UPGRADE_KEYS:
		if not levels.has(k):
			levels[k] = 0
	z_index = 5
	orbit_phase = randf() * TAU
	_refresh_tier()
	hp = max_hp()


# ---------------------------------------------------------------- stats
func max_speed() -> float:
	return 225.0 * (1.0 + 0.09 * levels.engine) * (1.0 if is_player else 0.93)

func cargo_cap() -> float:
	return 20.0 * (1.0 + 0.4 * levels.cargo)

func mine_rate() -> float:
	return 7.0 * (1.0 + 0.3 * levels.drill)

func mine_reach() -> float:
	return 60.0 + 12.0 * levels.drill

func missile_dmg() -> float:
	return 10.0 * (1.0 + 0.25 * levels.missiles)

func fire_interval() -> float:
	return 0.95 / (1.0 + 0.15 * levels.launcher)

func volley() -> int:
	return 1 + int(levels.launcher / 3)

func lock_range() -> float:
	return 360.0 + 32.0 * levels.targeting

func max_hp() -> float:
	return 60.0 + 30.0 * levels.hull + 12.0 * tier

func total_levels() -> int:
	var s := 0
	for k in UPGRADE_KEYS:
		s += int(levels[k])
	return s


func _refresh_tier() -> void:
	var tl := total_levels()
	var nt := 0
	for i in TIER_THRESH.size():
		if tl >= TIER_THRESH[i]:
			nt = i
	tier = nt
	hit_radius = tier_data(tier).r


## Returns true if the hull class changed.
func on_upgraded(key: String) -> bool:
	var old := tier
	_refresh_tier()
	if key == "hull":
		hp = minf(hp + 30.0, max_hp())
	if tier != old:
		hp = max_hp()
		trails.clear()
		return true
	return false


# ---------------------------------------------------------------- update
func _process(delta: float) -> void:
	var g := Game.inst
	t += delta
	if dead:
		respawn_t -= delta
		if respawn_t <= 0.0:
			respawn()
		return
	hit_flash = maxf(0.0, hit_flash - delta)
	invuln = maxf(0.0, invuln - delta)

	var desired := _player_desired() if (is_player and not g.autopilot) else _bot_desired(delta)
	for o in g.allies:
		if o == self or o.dead:
			continue
		var dv: Vector2 = position - o.position
		var dl := dv.length()
		var min_d: float = hit_radius + o.hit_radius + 14.0
		if dl < min_d and dl > 0.1:
			desired += dv / dl * (min_d - dl) * 5.0
	vel = vel.lerp(desired, 1.0 - exp(-ACCEL * delta))
	position += vel * delta
	var w := Game.WORLD_HALF - 20.0
	position = position.clamp(Vector2(-w, -w), Vector2(w, w))
	if vel.length() > 14.0:
		rotation = lerp_angle(rotation, vel.angle(), 1.0 - exp(-9.0 * delta))
	thrust = clampf(vel.length() / max_speed(), 0.0, 1.0)

	_update_trails()
	_mine(delta)
	_deposit(delta)
	_combat(delta)
	queue_redraw()


func _player_desired() -> Vector2:
	if Input.is_key_pressed(KEY_SPACE):
		return Vector2.ZERO
	return _arrive(get_global_mouse_position(), 190.0)


func _arrive(tp: Vector2, slow_radius: float = 150.0) -> Vector2:
	var d := tp - position
	var dist := d.length()
	if dist < 6.0:
		return Vector2.ZERO
	return d / dist * max_speed() * clampf((dist - 6.0) / slow_radius, 0.0, 1.0)


func _update_trails() -> void:
	var engines: Array = tier_data(tier).engines
	if trails.size() != engines.size():
		trails.clear()
		for i in engines.size():
			trails.append(PackedVector2Array())
	var max_pts := 22 if is_player else 14
	for i in engines.size():
		var tr: PackedVector2Array = trails[i]
		tr.append(to_global(engines[i]))
		while tr.size() > max_pts:
			tr.remove_at(0)
		trails[i] = tr


func _mine(delta: float) -> void:
	var g := Game.inst
	mining_target = null
	if cargo >= cargo_cap() - 0.01:
		return
	var best = null
	var bd := INF
	var reach := mine_reach()
	for a in g.asteroids:
		if a.depleted:
			continue
		var d: float = position.distance_to(a.position) - a.cur_radius()
		if d < reach and d < bd:
			best = a
			bd = d
	if best == null:
		return
	var amt: float = best.take(minf(mine_rate() * delta, cargo_cap() - cargo))
	cargo += amt
	cargo_value += amt * best.value
	mining_target = best
	mine_fx_t -= delta
	if mine_fx_t <= 0.0:
		mine_fx_t = 0.07
		var dir: Vector2 = (position - best.position).normalized()
		var p: Vector2 = best.position + dir.rotated(randf_range(-0.6, 0.6)) * best.cur_radius() * 0.8
		g.fx.homing(p, self, best.color, randf_range(1.6, 2.6))


func _deposit(delta: float) -> void:
	var g := Game.inst
	depositing = false
	if cargo <= 0.0:
		if deposit_accum > 0.5 and is_player:
			g.fx.text(position + Vector2(0, -hit_radius - 26), "+%d CR" % int(round(deposit_accum)), Color(1, 0.85, 0.35), 20)
		deposit_accum = 0.0
		return
	if position.distance_to(g.station.position) > g.station.dock_radius():
		return
	var amt := minf(cargo, (24.0 + cargo_cap() * 0.7) * delta)
	var frac := amt / cargo
	var val := cargo_value * frac
	cargo -= amt
	cargo_value -= val
	if cargo < 0.01:
		cargo = 0.0
		cargo_value = 0.0
	g.station.deposit(amt)
	g.ore_delivered += amt
	if is_player:
		g.credits += val
		deposit_accum += val
	else:
		g.credits += val * 0.2
	depositing = true
	if randf() < 0.6:
		g.fx.homing(position + Vector2(randf_range(-8, 8), randf_range(-8, 8)), g.station, Color(0.85, 0.6, 1.0), 2.2)


func _combat(delta: float) -> void:
	var g := Game.inst
	lock_scan -= delta
	if lock_target != null and (not is_instance_valid(lock_target) or lock_target.dead \
			or position.distance_to(lock_target.position) > lock_range() * 1.1):
		lock_target = null
	if lock_scan <= 0.0:
		lock_scan = 0.15
		var n = g.nearest_enemy(position, lock_range())
		if n != null:
			lock_target = n
	fire_cd -= delta
	if lock_target != null and fire_cd <= 0.0:
		fire_cd = fire_interval()
		var d: Dictionary = tier_data(tier)
		var n := volley()
		for i in n:
			side = -side
			var launch_local: Vector2 = d.lights[0] if side < 0 else d.lights[1]
			var p := to_global(launch_local * 0.8)
			var spread := (float(i) - float(n - 1) * 0.5) * 0.35
			var dir := Vector2.RIGHT.rotated(rotation + side * 1.1 + spread)
			g.spawn_missile(p, dir * 170.0 + vel * 0.6, lock_target, missile_dmg(), color, is_player)


func damage(amount: float) -> void:
	if dead or invuln > 0.0:
		return
	hp -= amount
	hit_flash = 0.3
	var g := Game.inst
	if is_player:
		g.shake = maxf(g.shake, 5.0)
	if hp <= 0.0:
		die()


func die() -> void:
	var g := Game.inst
	dead = true
	g.fx.explosion(position, color, 1.0 + tier * 0.25)
	if cargo > 1.0:
		g.fx.burst(position, Color(0.8, 0.5, 1.0), int(cargo), 160.0, 2.0, 1.0)
	cargo = 0.0
	cargo_value = 0.0
	mining_target = null
	lock_target = null
	vel = Vector2.ZERO
	respawn_t = 4.0 if is_player else 8.0
	if is_player:
		g.shake = 14.0
		g.hud.push_message("SHIP DESTROYED — CARGO LOST", Color(1, 0.35, 0.35), 2.5)
	queue_redraw()


func respawn() -> void:
	var g := Game.inst
	dead = false
	hp = max_hp()
	invuln = 2.5
	var dir := Vector2.RIGHT.rotated(randf() * TAU)
	position = g.station.position + dir * (g.station.radius + 50.0)
	rotation = dir.angle()
	vel = dir * 100.0
	trails.clear()
	g.fx.ring(position, color, 60.0, 0.6, 3.0)
	ai_state = "mine"
	ai_ast = null


# ---------------------------------------------------------------- bot brain
func _bot_desired(delta: float) -> Vector2:
	think_t -= delta
	if think_t <= 0.0:
		think_t = randf_range(0.35, 0.6)
		_bot_think()
	var g := Game.inst
	var st: Station = g.station
	match ai_state:
		"defend":
			if ai_enemy != null and is_instance_valid(ai_enemy) and not ai_enemy.dead:
				var away: Vector2 = (position - ai_enemy.position).normalized()
				if away == Vector2.ZERO:
					away = Vector2.RIGHT
				away = away.rotated(0.7 * sin(t * 0.8 + orbit_phase))
				return _arrive(ai_enemy.position + away * lock_range() * 0.62, 120.0)
			think_t = 0.0
		"return":
			var dir: Vector2 = (position - st.position).normalized()
			return _arrive(st.position + dir * (st.radius + 45.0), 120.0)
		"mine":
			if ai_ast != null and is_instance_valid(ai_ast) and not ai_ast.depleted:
				var dir: Vector2 = (position - ai_ast.position).normalized()
				dir = dir.rotated(0.25 * sin(t * 0.5 + orbit_phase))
				return _arrive(ai_ast.position + dir * (ai_ast.cur_radius() + mine_reach() * 0.45), 120.0)
			think_t = 0.0
	return vel * 0.5


func _bot_think() -> void:
	var g := Game.inst
	var st: Station = g.station
	var cap := cargo_cap()
	var threat = g.nearest_enemy(st.position, 1100.0) if guard else null
	var near_me = g.nearest_enemy(position, 420.0)
	if near_me != null:
		threat = near_me
	if threat != null and (cargo < cap * 0.95 or near_me != null):
		ai_state = "defend"
		ai_enemy = threat
		return
	if cargo >= cap * 0.98:
		ai_state = "return"
		return
	if ai_state == "return" and cargo > 0.0:
		return
	ai_state = "mine"
	if ai_ast == null or not is_instance_valid(ai_ast) or ai_ast.depleted or ai_ast.ore < 2.0:
		ai_ast = _pick_asteroid()
		if ai_ast == null and cargo > 0.0:
			ai_state = "return"


func _pick_asteroid():
	var g := Game.inst
	var best = null
	var bs := INF
	for a in g.asteroids:
		if a.depleted or a.ore < 4.0:
			continue
		var claims := 0
		for o in g.allies:
			if o != self and o.ai_ast == a:
				claims += 1
		var s: float = position.distance_to(a.position) + 0.4 * a.position.distance_to(g.station.position) \
				+ 550.0 * claims - a.ore * 2.0 - (160.0 if a.gold else 0.0)
		if s < bs:
			bs = s
			best = a
	return best


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if dead:
		return
	var g := Game.inst
	var font := ThemeDB.fallback_font
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	for tr in trails:
		_draw_trail(tr)
	if mining_target != null and is_instance_valid(mining_target):
		_draw_beam(mining_target)
	if depositing:
		Neon.line(self, position, g.station.position, Color(0.85, 0.6, 1.0, 0.25), 1.5, 0.6)
	var cap := cargo_cap()
	var ring_r := hit_radius + 10.0
	if cargo > 0.0:
		var f := cargo / cap
		draw_arc(position, ring_r, -PI * 0.5, -PI * 0.5 + TAU * f, 32, Color(0.8, 0.5, 1.0, 0.75), 2.5, true)
		draw_arc(position, ring_r, -PI * 0.5, -PI * 0.5 + TAU * f, 32, Color(0.8, 0.5, 1.0, 0.15), 7.0, true)
	if not is_player:
		draw_string(font, position + Vector2(-50, -hit_radius - 16), callsign, HORIZONTAL_ALIGNMENT_CENTER, 100, 11, Color(color, 0.65))
	draw_set_transform_matrix(Transform2D.IDENTITY)

	var flash := hit_flash * 2.0
	if invuln > 0.0 and int(t * 12.0) % 2 == 0:
		flash = 0.6
	draw_ship(self, tier, color, t, thrust, flash)
	if hit_flash > 0.0:
		Neon.ring(self, Vector2.ZERO, hit_radius + 7.0, Color(color, hit_flash * 2.5), 1.5)


func _draw_trail(tr: PackedVector2Array) -> void:
	var n := tr.size()
	if n < 2:
		return
	var base_w := 2.0 + tier * 0.6
	for i in range(1, n):
		var a := float(i) / float(n)
		var c := color.lerp(Color.WHITE, a * 0.35)
		draw_line(tr[i - 1], tr[i], Color(c, a * 0.12), base_w * 3.5 * a, true)
		draw_line(tr[i - 1], tr[i], Color(c, a * 0.55), base_w * a, true)


func _draw_beam(a) -> void:
	var start := to_global(tier_data(tier).nose)
	var dir: Vector2 = (start - a.position).normalized()
	var end: Vector2 = a.position + dir * a.cur_radius() * 0.75
	var c: Color = a.color
	var pts := PackedVector2Array([start])
	var seg := 5
	var perp := (end - start).orthogonal().normalized()
	for i in range(1, seg):
		var f := float(i) / seg
		pts.append(start.lerp(end, f) + perp * randf_range(-5.0, 5.0))
	pts.append(end)
	draw_polyline(pts, Color(c, 0.12), 9.0, true)
	draw_polyline(pts, Color(c, 0.6), 2.5, true)
	draw_polyline(pts, Color(1, 1, 1, 0.8), 1.0, true)
	Neon.dot(self, end, 4.0 + randf() * 2.0, c, 0.9)


## Shared hull renderer (also used for the title screen line-up).
static func draw_ship(ci: CanvasItem, tr: int, col: Color, time: float, thr: float, flash: float = 0.0) -> void:
	var d: Dictionary = tier_data(tr)
	var s: float = d.s
	var hull: PackedVector2Array = d.hull
	var white := Color(1, 1, 1)
	# engine flames
	for i in d.engines.size():
		var e: Vector2 = d.engines[i]
		var flick := 0.8 + 0.2 * sin(time * 45.0 + i * 1.7)
		var flen := (5.0 + 18.0 * thr) * s * flick
		var fw := 2.8 * s
		ci.draw_colored_polygon(PackedVector2Array([e + Vector2(0, -fw * 1.6), e + Vector2(-flen * 1.5, 0), e + Vector2(0, fw * 1.6)]), Color(col, 0.18))
		ci.draw_colored_polygon(PackedVector2Array([e + Vector2(0, -fw), e + Vector2(-flen, 0), e + Vector2(0, fw)]), Color(col.lerp(white, 0.4), 0.7))
		ci.draw_colored_polygon(PackedVector2Array([e + Vector2(0, -fw * 0.45), e + Vector2(-flen * 0.55, 0), e + Vector2(0, fw * 0.45)]), Color(1, 1, 1, 0.9))
	# hull fill
	if d.fill_ok:
		ci.draw_colored_polygon(hull, Color(col.r * 0.1 + 0.02, col.g * 0.1 + 0.02, col.b * 0.14 + 0.04, 0.94))
	# panel lines
	for ln in d.lines:
		ci.draw_line(ln[0], ln[1], Color(col, 0.18), 4.0, true)
		ci.draw_line(ln[0], ln[1], Color(col, 0.55), 1.2, true)
	var oc := col.lerp(white, clampf(flash, 0.0, 1.0))
	Neon.outline(ci, hull, oc, 1.6 + s * 0.5, 1.0)
	# cockpit
	var cp: PackedVector2Array = d.cockpit
	ci.draw_colored_polygon(cp, Color(col.lerp(white, 0.65), 0.85))
	Neon.outline(ci, cp, Color(col.lerp(white, 0.5), 0.9), 1.0, 0.5)
	# engine glow
	for e in d.engines:
		Neon.dot(ci, e, 2.4 * s, col.lerp(white, 0.3), 0.8 + 0.2 * thr)
	# nav lights: port red, starboard green, strobing
	var blink := 0.35 + 0.65 * maxf(0.0, sin(time * 5.0))
	Neon.dot(ci, d.lights[0], 1.8, Color(1, 0.3, 0.35), blink)
	Neon.dot(ci, d.lights[1], 1.8, Color(0.35, 1, 0.5), blink)


static func tier_data(tr: int) -> Dictionary:
	if _tier_cache.has(tr):
		return _tier_cache[tr]
	var k := 1.5
	var d := {}
	match tr:
		0:
			d.hull = Neon.mirror([Vector2(16, 0), Vector2(6, -4), Vector2(-4, -11), Vector2(-9, -11), Vector2(-6, -4), Vector2(-9, 0)], k)
			d.cockpit = Neon.mirror([Vector2(9, 0), Vector2(4, -2.2), Vector2(0, 0)], k)
			d.engines = [Vector2(-8, 0) * k]
			d.lines = [[Vector2(2, -3) * k, Vector2(-5, -9) * k], [Vector2(2, 3) * k, Vector2(-5, 9) * k]]
			d.lights = [Vector2(-6, -11) * k, Vector2(-6, 11) * k]
			d.nose = Vector2(16, 0) * k
			d.s = 1.0
			d.r = 16.0
		1:
			d.hull = Neon.mirror([Vector2(22, 0), Vector2(10, -3), Vector2(2, -5), Vector2(-2, -15), Vector2(-8, -16), Vector2(-8, -6), Vector2(-13, -4), Vector2(-12, 0)], k)
			d.cockpit = Neon.mirror([Vector2(12, 0), Vector2(6, -2.5), Vector2(2, 0)], k)
			d.engines = [Vector2(-12.5, -2.2) * k, Vector2(-12.5, 2.2) * k]
			d.lines = [[Vector2(10, -3) * k, Vector2(-8, -6) * k], [Vector2(10, 3) * k, Vector2(-8, 6) * k],
				[Vector2(0, -9) * k, Vector2(-6, -14) * k], [Vector2(0, 9) * k, Vector2(-6, 14) * k]]
			d.lights = [Vector2(-5, -15.5) * k, Vector2(-5, 15.5) * k]
			d.nose = Vector2(22, 0) * k
			d.s = 1.15
			d.r = 20.0
		2:
			d.hull = Neon.mirror([Vector2(28, 0), Vector2(14, -4), Vector2(4, -6), Vector2(0, -10), Vector2(6, -19), Vector2(0, -21),
				Vector2(-12, -21), Vector2(-10, -12), Vector2(-16, -12), Vector2(-14, -6), Vector2(-18, -4), Vector2(-16, 0)], k)
			d.cockpit = Neon.mirror([Vector2(16, 0), Vector2(9, -3), Vector2(4, 0)], k)
			d.engines = [Vector2(-17.5, -2.2) * k, Vector2(-17.5, 2.2) * k, Vector2(-11.5, -17) * k, Vector2(-11.5, 17) * k]
			d.lines = [[Vector2(14, -4) * k, Vector2(-14, -6) * k], [Vector2(14, 4) * k, Vector2(-14, 6) * k],
				[Vector2(0, -10) * k, Vector2(-10, -12) * k], [Vector2(0, 10) * k, Vector2(-10, 12) * k],
				[Vector2(3, -17) * k, Vector2(-10, -17) * k], [Vector2(3, 17) * k, Vector2(-10, 17) * k]]
			d.lights = [Vector2(4, -19.5) * k, Vector2(4, 19.5) * k]
			d.nose = Vector2(28, 0) * k
			d.s = 1.3
			d.r = 25.0
		3:
			d.hull = Neon.mirror([Vector2(34, 0), Vector2(20, -5), Vector2(8, -7), Vector2(4, -12), Vector2(14, -26), Vector2(6, -28),
				Vector2(-10, -26), Vector2(-14, -14), Vector2(-22, -14), Vector2(-20, -8), Vector2(-26, -6), Vector2(-24, 0)], k)
			d.cockpit = Neon.mirror([Vector2(21, 0), Vector2(12, -3.5), Vector2(6, 0)], k)
			d.engines = [Vector2(-25.5, -3) * k, Vector2(-25.5, 3) * k, Vector2(-21, -11) * k, Vector2(-21, 11) * k]
			d.lines = [[Vector2(20, -5) * k, Vector2(-20, -8) * k], [Vector2(20, 5) * k, Vector2(-20, 8) * k],
				[Vector2(4, -12) * k, Vector2(-14, -14) * k], [Vector2(4, 12) * k, Vector2(-14, 14) * k],
				[Vector2(10, -24) * k, Vector2(-8, -21) * k], [Vector2(10, 24) * k, Vector2(-8, 21) * k],
				[Vector2(4, -6) * k, Vector2(4, 6) * k], [Vector2(-6, -7) * k, Vector2(-6, 7) * k]]
			d.lights = [Vector2(7, -27) * k, Vector2(7, 27) * k]
			d.nose = Vector2(34, 0) * k
			d.s = 1.5
			d.r = 31.0
		_:
			d.hull = Neon.mirror([Vector2(44, 0), Vector2(30, -6), Vector2(16, -8), Vector2(12, -14), Vector2(22, -30), Vector2(14, -34),
				Vector2(-6, -32), Vector2(-12, -20), Vector2(-18, -20), Vector2(-14, -38), Vector2(-24, -40), Vector2(-34, -22),
				Vector2(-30, -12), Vector2(-36, -8), Vector2(-34, 0)], k)
			d.cockpit = Neon.mirror([Vector2(28, 0), Vector2(18, -4), Vector2(10, 0)], k)
			d.engines = [Vector2(-35.5, -3.5) * k, Vector2(-35.5, 3.5) * k, Vector2(-31.5, -17) * k, Vector2(-31.5, 17) * k]
			d.lines = [[Vector2(30, -6) * k, Vector2(-30, -10) * k], [Vector2(30, 6) * k, Vector2(-30, 10) * k],
				[Vector2(12, -14) * k, Vector2(-12, -20) * k], [Vector2(12, 14) * k, Vector2(-12, 20) * k],
				[Vector2(18, -30) * k, Vector2(-4, -28) * k], [Vector2(18, 30) * k, Vector2(-4, 28) * k],
				[Vector2(-16, -36) * k, Vector2(-30, -22) * k], [Vector2(-16, 36) * k, Vector2(-30, 22) * k],
				[Vector2(6, -8) * k, Vector2(6, 8) * k], [Vector2(-8, -10) * k, Vector2(-8, 10) * k], [Vector2(-20, -10) * k, Vector2(-20, 10) * k]]
			d.lights = [Vector2(16, -33) * k, Vector2(16, 33) * k]
			d.nose = Vector2(44, 0) * k
			d.s = 1.8
			d.r = 40.0
	d.fill_ok = not Geometry2D.triangulate_polygon(d.hull).is_empty()
	_tier_cache[tr] = d
	return d
