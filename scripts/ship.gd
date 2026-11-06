class_name Ship
extends Node2D
## You and the hive's drones. Same body plan; drones get an AI brain.
## You: a worker that grows as the hive's glands mature (no menus, just fly).
## Foragers: harvest whatever the hive craves and haul it home.
## Guards: patrol the hive and intercept anything that comes for it.

const FORM_NAMES := ["NYMPH", "WORKER", "FORAGER", "WARDEN", "ARISTAEUS"]
const FORM_THRESH := [0, 2, 5, 9, 14]
const ACCEL := 3.6

var is_player := false
var role := "forager"  # player / forager / guard
var callsign := ""
var color := Gfx.C_PLAYER
var vel := Vector2.ZERO
var hp := 60.0
var cargo := {"nectar": 0.0, "ore": 0.0, "ice": 0.0}
var form := 0
var dead := false
var respawn_t := 0.0
var invuln := 0.0
var hit_flash := 0.0
var last_hit := 99.0
var thrust := 0.0
var t := 0.0
var hit_radius := 14.0
var trail := PackedVector2Array()

var lock_target = null
var lock_scan := 0.0
var fire_cd := 0.6
var side := 1.0
var mining_target = null
var mine_fx_t := 0.0
var depositing := ""
var repairing = null
var deposit_accum := 0.0

# brain
var ai_state := "forage"
var ai_field = null
var ai_node = null
var ai_enemy = null
var think_t := 0.0
var orbit_phase := 0.0
var field_pick_t := 0.0
var nav_t := 0.0
var nav_goal := Vector2(INF, INF)
var nav_pt := Vector2.ZERO

var _vis: Node2D
var _body: Sprite2D
var _veins: Sprite2D
var _wings: Array = []  # [sprite, root, base_rot, side, phase]
var _spec: Dictionary


func _ready() -> void:
	z_index = 5
	orbit_phase = randf() * TAU
	t = randf() * 5.0
	if is_player:
		role = "player"
		color = Gfx.C_PLAYER
		form = _calc_form()
	else:
		color = Gfx.C_GUARD if role == "guard" else Gfx.C_FORAGER
	_build_visuals()
	hp = max_hp()


# ---------------------------------------------------------------- stats
func _gl(k: String) -> int:
	return Game.inst.hive.gland(k)


func max_speed() -> float:
	if is_player:
		return 215.0 * (1.0 + 0.1 * _gl("wing"))
	return (185.0 if role == "guard" else 175.0) * (1.0 + 0.04 * _gl("wing"))


func cargo_cap() -> float:
	if is_player:
		return 18.0 * (1.0 + 0.45 * _gl("pouch"))
	return 14.0 * (1.0 + 0.15 * _gl("pouch")) if role == "forager" else 0.0


func cargo_total() -> float:
	return cargo.nectar + cargo.ore + cargo.ice


func mine_rate() -> float:
	if is_player:
		return 7.0 * (1.0 + 0.35 * _gl("proboscis"))
	return 6.0 * (1.0 + 0.15 * _gl("proboscis"))


func mine_reach() -> float:
	if is_player:
		return 60.0 + 14.0 * _gl("proboscis")
	return 55.0


func missile_dmg() -> float:
	var v := _gl("venom")
	if is_player:
		return 10.0 * (1.0 + 0.3 * v)
	return (8.0 if role == "guard" else 5.0) * (1.0 + 0.15 * v)


func fire_interval() -> float:
	if is_player:
		return 0.95 / (1.0 + 0.15 * _gl("venom"))
	return 1.0 if role == "guard" else 1.5


func volley() -> int:
	return 1 + int(_gl("venom") / 2) if is_player else 1


func lock_range() -> float:
	if is_player:
		return 370.0 + 30.0 * _gl("eye")
	return 340.0 if role == "guard" else 280.0


func max_hp() -> float:
	if is_player:
		return 60.0 + 35.0 * _gl("carapace") + 8.0 * form
	return (55.0 if role == "guard" else 50.0) + 6.0 * _gl("carapace")


func vision() -> float:
	var base := 560.0 if is_player else 380.0
	return base * Game.inst.hive.vision_mult()


func _calc_form() -> int:
	var hv: Hive = Game.inst.hive
	var s := 0
	for k in ["carapace", "wing", "pouch", "venom", "proboscis"]:
		s += hv.modules[k].level
	var f := 0
	for i in FORM_THRESH.size():
		if s >= FORM_THRESH[i]:
			f = i
	return f


## Called by the game when the hive grows; re-forms the player's body.
func on_hive_grew() -> bool:
	if not is_player:
		return false
	var nf := _calc_form()
	hp = minf(hp + 25.0, max_hp())
	if nf != form:
		form = nf
		hp = max_hp()
		_build_visuals()
		return true
	return false


# ---------------------------------------------------------------- visuals
func _build_visuals() -> void:
	if _vis != null:
		_vis.queue_free()
	_wings.clear()
	_vis = Node2D.new()
	add_child(_vis)
	var key: String
	if is_player:
		_spec = Gfx.form(form)
		key = "pf%d" % form
	else:
		_spec = Gfx.drone_spec(role == "guard")
		key = "dg" if role == "guard" else "df"
	hit_radius = Gfx.bee_radius(_spec)
	if is_player:
		var halo := Gfx.sprite("glow", Color(color, 0.1))
		halo.scale = Vector2.ONE * (hit_radius / 26.0)
		_vis.add_child(halo)
	var roots := Gfx.wing_roots(_spec)
	var pairs: int = _spec.pairs
	# hind wings first so the fore wings draw over them
	for pi in range(pairs - 1, -1, -1):
		var wname: String
		if is_player:
			wname = "%s_%s" % [key, "wh" if pi == 1 else "wf"]
		else:
			wname = key + "_w"
		for sd in [-1.0, 1.0]:
			var w := Gfx.sprite(wname)
			var root: Vector2 = roots[pi]
			w.position = Vector2(root.x, -root.y * sd)
			_vis.add_child(w)
			_wings.append([w, w.position, 0.0, sd, pi * 0.6])
	_body = Gfx.sprite(key)
	_vis.add_child(_body)
	_veins = Gfx.sprite(key + "_v")
	_vis.add_child(_veins)
	_vis.visible = not dead


func _update_visuals() -> void:
	var white := Color(1, 1, 1)
	var hz := 15.0 + 6.0 * thrust
	for w in _wings:
		var sp: Sprite2D = w[0]
		var ph: float = sin(t * hz + w[4])
		var fold := lerpf(0.4, 1.0, absf(ph))
		var sd: float = w[3]
		# the wing art points to -y (port); starboard wings are mirrored
		sp.scale = Vector2(1.0, -sd * fold)
		sp.rotation = -sd * 0.2 * ph
		Gfx.tint(sp, Color(1, 1, 1, 0.55 + 0.35 * absf(ph)))
	var flash := hit_flash * 2.0
	if invuln > 0.0 and int(t * 12.0) % 2 == 0:
		flash = 0.6
	Gfx.tint(_body, white.lerp(Color(2, 2, 2), clampf(flash, 0.0, 1.0)))
	var pulse := 0.65 + 0.35 * sin(t * 3.0 + orbit_phase)
	Gfx.tint(_veins, Color(1, 1, 1, pulse))


# ---------------------------------------------------------------- update
func _process(delta: float) -> void:
	var g := Game.inst
	t += delta
	if dead:
		if is_player:
			respawn_t -= delta
			if respawn_t <= 0.0:
				respawn()
		return
	hit_flash = maxf(0.0, hit_flash - delta)
	invuln = maxf(0.0, invuln - delta)
	last_hit += delta

	var desired: Vector2
	if is_player and not g.autopilot:
		desired = _player_desired()
	elif role == "guard":
		desired = _guard_desired(delta)
	else:
		desired = _forager_desired(delta)
	for o in g.allies:
		if o == self or o.dead:
			continue
		var dv: Vector2 = position - o.position
		var dl := dv.length()
		var min_d: float = hit_radius + o.hit_radius + 10.0
		if dl < min_d and dl > 0.1:
			desired += dv / dl * (min_d - dl) * 5.0
	vel = vel.lerp(desired, 1.0 - exp(-ACCEL * delta))
	position += vel * delta
	var c := g.cave.constrain(position, hit_radius * 0.6)
	if c != position:
		var nrm := (c - position).normalized()
		var vn := vel.dot(nrm)
		if vn < 0.0:
			vel -= nrm * vn
		position = c
	if vel.length() > 14.0:
		rotation = lerp_angle(rotation, vel.angle(), 1.0 - exp(-9.0 * delta))
	thrust = clampf(vel.length() / max_speed(), 0.0, 1.0)
	# heal inside the hive
	if position.length() < Hive.ZONE_R and not g.hive.starving:
		hp = minf(max_hp(), hp + (5.0 if is_player else 3.0) * delta)

	_update_trail()
	_mine(delta)
	_deposit(delta)
	if is_player:
		_repair(delta)
	_combat(delta)
	_update_visuals()


func _player_desired() -> Vector2:
	if Input.is_key_pressed(KEY_SPACE):
		return Vector2.ZERO
	return _arrive(get_global_mouse_position(), 190.0)


## Like _arrive, but routes through the tunnels when the target isn't in sight.
func _go(tp: Vector2, slow_radius: float = 150.0) -> Vector2:
	nav_t -= get_process_delta_time()
	if nav_t <= 0.0 or tp.distance_to(nav_goal) > 60.0 or position.distance_to(nav_pt) < 50.0:
		nav_t = 0.35
		nav_goal = tp
		nav_pt = Game.inst.cave.steer(position, tp)
	if nav_pt.distance_to(tp) < 1.0:
		return _arrive(tp, slow_radius)
	return _arrive(nav_pt, 30.0)


func _arrive(tp: Vector2, slow_radius: float = 150.0) -> Vector2:
	var d := tp - position
	var dist := d.length()
	if dist < 6.0:
		return Vector2.ZERO
	return d / dist * max_speed() * clampf((dist - 6.0) / slow_radius, 0.0, 1.0)


func _update_trail() -> void:
	var tail := to_global(Vector2(-(4.0 + 4.1 * _spec.nseg) * _spec.s, 0))
	trail.append(tail)
	var mx := (18 if is_player else 10) / (2 if Game.inst.low_quality else 1)
	while trail.size() > mx:
		trail.remove_at(0)


func _mine(delta: float) -> void:
	var g := Game.inst
	mining_target = null
	var capv := cargo_cap()
	if capv <= 0.0 or cargo_total() >= capv - 0.01:
		return
	var best = null
	var bd := INF
	var reach := mine_reach()
	for a in g.res_nodes:
		var d: float = position.distance_to(a.position) - a.cur_radius()
		if d < reach and d < bd:
			best = a
			bd = d
	if best == null:
		return
	var want := minf(mine_rate() * best.rich * delta, capv - cargo_total())
	var amt: float = best.take(want / best.rich) * best.rich
	cargo[best.kind] += amt
	mining_target = best
	mine_fx_t -= delta
	if mine_fx_t <= 0.0:
		mine_fx_t = 0.08 if is_player else 0.16
		var dir: Vector2 = (position - best.position).normalized()
		var p: Vector2 = best.position + dir.rotated(randf_range(-0.6, 0.6)) * best.cur_radius() * 0.7
		g.fx.homing(p, self, best.color, randf_range(1.6, 2.6))


func _deposit(delta: float) -> void:
	var g := Game.inst
	depositing = ""
	if cargo_total() <= 0.01:
		if deposit_accum > 0.5 and is_player:
			g.fx.text(position + Vector2(0, -hit_radius - 26), "+%d to the hive" % int(round(deposit_accum)), Gfx.C_HIVE, 18)
		deposit_accum = 0.0
		return
	for k in ["nectar", "ore", "ice"]:
		if cargo[k] <= 0.0:
			continue
		var m: HiveModule = g.hive.module_for(k)
		if not m.online() or position.distance_to(m.position) > m.dock_radius():
			continue
		var rate := 26.0 + cargo_cap() * 0.8
		var amt: float = minf(cargo[k], rate * delta)
		var took := g.hive.deposit(k, amt)
		cargo[k] -= took
		if cargo[k] < 0.01:
			cargo[k] = 0.0
		if took > 0.0:
			depositing = k
			if is_player:
				deposit_accum += took
				g.stats_delivered += took
			if randf() < 0.5:
				g.fx.homing(position + Vector2(randf_range(-8, 8), randf_range(-8, 8)), m, Gfx.res_color(k), 2.2)
		elif is_player and randf() < 0.02:
			g.fx.text(m.position + Vector2(0, -m.radius() - 20), "%s FULL" % m.label, Color(1, 0.7, 0.4), 14)


func _repair(delta: float) -> void:
	var g := Game.inst
	repairing = null
	for m in g.hive.built_modules():
		if m.hp >= m.max_hp:
			continue
		if position.distance_to(m.position) > m.dock_radius() + 20.0:
			continue
		var amt := 30.0 * delta
		if g.hive.use("ice", amt * 0.25):
			m.mend(amt)
		else:
			m.mend(amt * 0.35)
		repairing = m
		if randf() < 0.3:
			g.fx.homing(position, m, Gfx.C_HIVE, 2.0)
		return


func _combat(delta: float) -> void:
	var g := Game.inst
	lock_scan -= delta
	if lock_target != null and (not is_instance_valid(lock_target) or lock_target.dead \
			or position.distance_to(lock_target.position) > lock_range() * 1.15):
		lock_target = null
	if lock_scan <= 0.0:
		lock_scan = 0.15
		var n = g.nearest_enemy(position, lock_range())
		if n != null:
			lock_target = n
	fire_cd -= delta
	if lock_target != null and fire_cd <= 0.0:
		fire_cd = fire_interval()
		var n := volley()
		for i in n:
			side = -side
			var p := to_global(Vector2(2.0, 5.0 * side) * _spec.s)
			var spread := (float(i) - float(n - 1) * 0.5) * 0.35
			var dir := Vector2.RIGHT.rotated(rotation + side * 1.1 + spread)
			g.spawn_missile(p, dir * 170.0 + vel * 0.6, lock_target, missile_dmg(), color, is_player)


func damage(amount: float) -> void:
	if dead or invuln > 0.0:
		return
	hp -= amount
	hit_flash = 0.3
	last_hit = 0.0
	if not is_player and ai_field != null and position.distance_to(ai_field.position) < ai_field.radius + 300.0:
		ai_field.danger = 45.0
		field_pick_t = 0.0
	var g := Game.inst
	if is_player:
		g.shake = maxf(g.shake, 5.0)
	if hp <= 0.0:
		die()


func die() -> void:
	if dead:
		return
	var g := Game.inst
	dead = true
	g.fx.explosion(position, color, 0.9 + form * 0.2)
	g.fx.burst(position, Color(0.6, 1.0, 0.7), 14, 120.0, 2.4, 1.0)
	for k in cargo.keys():
		cargo[k] = 0.0
	mining_target = null
	lock_target = null
	vel = Vector2.ZERO
	_vis.visible = false
	trail.clear()
	if is_player:
		respawn_t = 5.0
		g.shake = 14.0
		g.deaths += 1
		g.hud.push_message("YOU FELL — CARGO LOST. REBORN AT THE HEART…", Color(1, 0.4, 0.4), 3.0)
	else:
		g.on_drone_lost(self)
		queue_free()


func respawn() -> void:
	var g := Game.inst
	dead = false
	hp = max_hp()
	invuln = 2.5
	var dir := Vector2.RIGHT.rotated(randf() * TAU)
	position = dir * 140.0
	rotation = dir.angle()
	vel = dir * 100.0
	trail.clear()
	_vis.visible = true
	g.fx.ring(position, color, 60.0, 0.6, 3.0)


# ---------------------------------------------------------------- brains
func _forager_desired(delta: float) -> Vector2:
	var g := Game.inst
	var hv: Hive = g.hive
	think_t -= delta
	field_pick_t -= delta
	if think_t <= 0.0:
		think_t = randf_range(0.35, 0.6)
		_forager_think()
	match ai_state:
		"flee":
			return _go(Vector2.RIGHT.rotated(orbit_phase) * 150.0, 120.0)
		"return":
			var k := _biggest_cargo()
			var m: HiveModule = hv.module_for(k) if k != "" else hv.heart
			if not m.online():
				m = hv.heart
			var dir: Vector2 = (position - m.position).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			return _go(m.position + dir * (m.radius() + 24.0), 110.0)
		"glob":
			if ai_node != null and is_instance_valid(ai_node):
				return _go(ai_node.position, 60.0)
		"forage":
			if ai_node != null and is_instance_valid(ai_node) and not ai_node.depleted:
				var dir: Vector2 = (position - ai_node.position).normalized()
				if dir == Vector2.ZERO:
					dir = Vector2.RIGHT
				dir = dir.rotated(0.3 * sin(t * 0.5 + orbit_phase))
				return _go(ai_node.position + dir * (ai_node.cur_radius() + mine_reach() * 0.45), 110.0)
			if ai_field != null:
				return _go(ai_field.position, 160.0)
	return vel * 0.5


func _biggest_cargo() -> String:
	var best := ""
	var bv := 0.01
	for k in cargo.keys():
		if cargo[k] > bv:
			bv = cargo[k]
			best = k
	return best


func _forager_think() -> void:
	var g := Game.inst
	var mh := max_hp()
	if ai_state == "flee":
		if hp > mh * 0.85:
			ai_state = "return" if cargo_total() > 0.5 else "forage"
		return
	if (not is_player and hp < mh * 0.55 and last_hit < 1.0) or (hp < mh * 0.4 and last_hit < 3.0):
		ai_state = "flee"
		return
	var capv := cargo_cap()
	if cargo_total() >= capv * 0.97:
		ai_state = "return"
		return
	if ai_state == "return" and cargo_total() > 0.5:
		return
	# loose globs (Reaper spill) are worth grabbing
	for gl in g.globs:
		if position.distance_to(gl.position) < 900.0:
			ai_state = "glob"
			ai_node = gl
			return
	ai_state = "forage"
	var want := g.hive.craving()
	if ai_field == null or field_pick_t <= 0.0 or ai_field.node_count() == 0:
		field_pick_t = randf_range(18.0, 30.0)
		ai_field = _pick_field(want)
		ai_node = null
	if ai_field == null:
		if cargo_total() > 0.5:
			ai_state = "return"
		return
	if ai_node == null or not is_instance_valid(ai_node) or not (ai_node is ResNode) or ai_node.depleted or ai_node.amount < 2.0:
		ai_node = _pick_node(ai_field)
		if ai_node == null:
			field_pick_t = 0.0
			if cargo_total() > 0.5:
				ai_state = "return"


func _pick_field(want: String):
	var g := Game.inst
	var best = null
	var bs := INF
	for f in g.fields:
		if f.node_count() == 0:
			continue
		var s: float = f.position.length() + f.threat() * (700.0 if not is_player else 250.0) + (1800.0 if f.danger > 0.0 else 0.0)
		if f.kind != want:
			s += 2500.0
		s += randf_range(0.0, 300.0)
		if s < bs:
			bs = s
			best = f
	return best


func _pick_node(f):
	var g := Game.inst
	var best = null
	var bs := INF
	for nd in g.res_nodes:
		if nd.field != f or nd.amount < 2.0:
			continue
		var claims := 0
		for o in g.allies:
			if o != self and o.ai_node == nd:
				claims += 1
		var s: float = position.distance_to(nd.position) + 300.0 * claims - nd.amount * 2.0
		if s < bs:
			bs = s
			best = nd
	return best


func _guard_desired(delta: float) -> Vector2:
	var g := Game.inst
	think_t -= delta
	if think_t <= 0.0:
		think_t = randf_range(0.3, 0.5)
		ai_enemy = null
		var best = null
		var bd := Hive.ZONE_R + 300.0
		for e in g.enemies:
			if e.dead:
				continue
			var d: float = e.position.length()
			if e.kind == "reaper":
				d -= 600.0
			if d < bd:
				bd = d
				best = e
		ai_enemy = best
		if hp < max_hp() * 0.35:
			ai_enemy = null
	if ai_enemy != null and is_instance_valid(ai_enemy) and not ai_enemy.dead:
		var away: Vector2 = (position - ai_enemy.position).normalized()
		if away == Vector2.ZERO:
			away = Vector2.RIGHT
		away = away.rotated(0.7 * sin(t * 0.8 + orbit_phase))
		return _go(ai_enemy.position + away * lock_range() * 0.6, 100.0)
	var a := orbit_phase + t * 0.06
	var r := 420.0 + 140.0 * sin(t * 0.13 + orbit_phase)
	return _go(Vector2.RIGHT.rotated(a) * r, 160.0) * 0.7
