class_name Hive
extends Node2D
## The colony. Owns the stores, the upkeep that constantly eats nectar, the
## Comb Forge's automatic growth plan, the Brood Chamber's hatching, and the
## Heart's vitality (the run ends if the Heart withers from starvation).

const CORE_R := 260.0
const GLAND_R := 430.0
const SPIRE_R := 555.0
const ZONE_R := 650.0
const CORE_ANG := {"vault": -45.0, "cistern": 45.0, "forge": 135.0, "brood": 225.0}
const GLAND_ANG := {"proboscis": 0.0, "pouch": 60.0, "carapace": 120.0, "venom": 180.0, "wing": 240.0, "eye": 300.0}
const SPIRE_ORDER := [0, 4, 2, 6, 1, 5, 3, 7]
const PLAN := [
	["spire", 1], ["proboscis", 1], ["brood", 2], ["carapace", 1], ["spire", 2], ["pouch", 1], ["wing", 1],
	["eye", 1], ["venom", 1], ["vault", 2], ["spire", 3], ["cistern", 2], ["forge", 2], ["carapace", 2],
	["proboscis", 2], ["brood", 3], ["spire", 4], ["pouch", 2], ["venom", 2], ["wing", 2], ["spire", 5],
	["vault", 3], ["eye", 2], ["carapace", 3], ["spire", 6], ["venom", 3], ["brood", 4], ["proboscis", 3],
	["cistern", 3], ["forge", 3], ["pouch", 3], ["wing", 3], ["spire", 7], ["carapace", 4], ["venom", 4],
	["spire", 8], ["spires", 2], ["vault", 4], ["eye", 3], ["wing", 4], ["pouch", 4], ["proboscis", 4],
	["brood", 5], ["cistern", 4], ["forge", 4], ["eye", 4], ["spires", 3],
]

var stores := {"nectar": 230.0, "ore": 60.0, "ice": 70.0}
var delivered := {"nectar": 0.0, "ore": 0.0, "ice": 0.0}
var modules := {}  # type -> HiveModule (not spires)
var spires: Array = []
var heart: HiveModule
var vitality := 1.0
var starving := false
var plan_i := 0
var plan_spent := 0.0
var building_active := false
var build_stall := ""
var hatch_t := 0.0
var last_hit_t := 0.0
var grown := 0
var _starve_msg_t := 0.0
var veins: HiveVeins


func _ready() -> void:
	z_index = 0
	veins = HiveVeins.new()
	veins.hive = self
	veins.z_index = -1
	add_child(veins)
	heart = _add("heart", Vector2.ZERO)
	for k in CORE_ANG.keys():
		var m := _add(k, Vector2.RIGHT.rotated(deg_to_rad(CORE_ANG[k])) * CORE_R)
		m.set_level(1)
	for k in GLAND_ANG.keys():
		_add(k, Vector2.RIGHT.rotated(deg_to_rad(GLAND_ANG[k])) * GLAND_R)
	for i in 8:
		var a := deg_to_rad(22.5 + 45.0 * SPIRE_ORDER[i])
		var m := HiveModule.new()
		m.setup("spire")
		m.position = Vector2.RIGHT.rotated(a) * SPIRE_R
		add_child(m)
		spires.append(m)
	veins.rebuild()
	_mark_growing()


func _add(tp: String, pos: Vector2) -> HiveModule:
	var m := HiveModule.new()
	m.setup(tp)
	m.position = pos
	add_child(m)
	modules[tp] = m
	return m


func all_modules() -> Array:
	var out: Array = modules.values()
	out.append_array(spires)
	return out


func built_modules() -> Array:
	var out := []
	for m in all_modules():
		if m.level > 0 and m.type != "heart":
			out.append(m)
	return out


# ---------------------------------------------------------------- stores
func cap(kind: String) -> float:
	match kind:
		"nectar":
			return 300.0 + 200.0 * modules.vault.level
		"ore":
			return 250.0 + 200.0 * modules.forge.level
		"ice":
			return 200.0 + 160.0 * modules.cistern.level
	return 0.0


func fill(kind: String) -> float:
	return clampf(stores[kind] / cap(kind), 0.0, 1.0)


func use(kind: String, amt: float) -> bool:
	if stores[kind] < amt:
		return false
	stores[kind] -= amt
	return true


func module_for(kind: String) -> HiveModule:
	match kind:
		"nectar":
			return modules.vault
		"ore":
			return modules.forge
		"ice":
			return modules.cistern
	return null


## Deposit into the matching module; returns what was accepted.
func deposit(kind: String, amt: float) -> float:
	var room: float = cap(kind) - stores[kind]
	var a := clampf(amt, 0.0, maxf(room, 0.0))
	stores[kind] += a
	delivered[kind] += a
	return a


## What the hive is most short of, for foragers and the HUD.
func craving() -> String:
	var up := upkeep()
	if stores.nectar < up * 60.0 or fill("nectar") < 0.2:
		return "nectar"
	var best := "nectar"
	var bv := INF
	var weights := {"nectar": 0.8, "ore": 1.0, "ice": 1.15}
	for k in ["nectar", "ore", "ice"]:
		var v: float = fill(k) * weights[k]
		if v < bv:
			bv = v
			best = k
	return best


func total_levels() -> int:
	var s := 0
	for m in built_modules():
		s += m.level
	return s


func drone_count() -> int:
	return Game.inst.allies.size() - 1


func upkeep() -> float:
	return 0.15 + 0.012 * total_levels() + 0.015 * maxi(drone_count(), 0)


# ---------------------------------------------------------------- augments
func gland(kind: String) -> int:
	var m: HiveModule = modules[kind]
	return m.level if m.online() else 0


func vision_mult() -> float:
	return 1.0 + 0.12 * gland("eye")


func pop_cap() -> int:
	return 3 + 3 * modules.brood.level


func hatch_frac() -> float:
	return clampf(hatch_t / 10.0, 0.0, 1.0)


# ---------------------------------------------------------------- growth plan
func plan_item() -> Array:
	return PLAN[plan_i] if plan_i < PLAN.size() else []


func plan_cost(i: int) -> float:
	return roundf(40.0 + 10.0 * i + 0.4 * i * i)


func plan_label(item: Array) -> String:
	if item.is_empty():
		return "—"
	var tp: String = item[0]
	var lv: int = item[1]
	if tp == "spire":
		return "STINGER SPIRE %s" % _roman(lv)
	if tp == "spires":
		return "HARDEN SPIRES %s" % _roman(lv)
	var name: String = HiveModule.INFO[tp].name
	return name if lv == 1 else "%s %s" % [name, _roman(lv)]


static func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"][clampi(n, 0, 8)]


func plan_frac() -> float:
	if plan_i >= PLAN.size():
		return 1.0
	return clampf(plan_spent / plan_cost(plan_i), 0.0, 1.0)


func _plan_target() -> HiveModule:
	var item := plan_item()
	if item.is_empty():
		return null
	if item[0] == "spire":
		return spires[item[1] - 1]
	if item[0] == "spires":
		return null
	return modules[item[0]]


func _mark_growing() -> void:
	for m in all_modules():
		m.growing = false
	var tm := _plan_target()
	if tm != null:
		tm.growing = true


func _complete_item() -> void:
	var item := plan_item()
	var g := Game.inst
	var tp: String = item[0]
	var lv: int = item[1]
	var where := Vector2.ZERO
	if tp == "spire":
		spires[lv - 1].set_level(1)
		where = spires[lv - 1].position
	elif tp == "spires":
		for s in spires:
			if s.level > 0:
				s.set_level(lv)
	else:
		modules[tp].set_level(lv)
		where = modules[tp].position
	grown += 1
	g.on_hive_grew(plan_label(item), tp, where)
	plan_i += 1
	plan_spent = 0.0
	veins.rebuild()
	_mark_growing()


# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	var g := Game.inst
	if g.state != "playing" and g.state != "dying":
		return
	last_hit_t = maxf(0.0, last_hit_t - delta)
	# upkeep
	stores.nectar -= upkeep() * delta
	if stores.nectar <= 0.0:
		stores.nectar = 0.0
		if not starving:
			starving = true
			g.hud.push_message("THE HIVE IS STARVING — BRING NECTAR TO THE VAULT!", Color(1, 0.35, 0.3), 4.0)
		vitality -= delta / 100.0
		for m in built_modules():
			if m.hp > 1.0:
				m.hp -= 0.5 * delta
		if vitality <= 0.0:
			vitality = 0.0
			g.hive_died()
	else:
		if starving:
			starving = false
			g.hud.push_message("THE HIVE IS FED", Gfx.C_HIVE, 2.0)
		vitality = minf(1.0, vitality + delta / 30.0)
		_starve_msg_t -= delta
		if stores.nectar < upkeep() * 40.0 and _starve_msg_t <= 0.0:
			_starve_msg_t = 20.0
			g.hud.push_message("NECTAR RUNNING LOW", C_WARN, 2.5)
		for m in built_modules():
			if m.online() and m.hp < m.max_hp:
				m.hp = minf(m.max_hp, m.hp + 0.6 * delta)
	for k in stores.keys():
		stores[k] = minf(stores[k], cap(k))
	_grow(delta)
	_hatch(delta)


const C_WARN := Color(1, 0.75, 0.3)


func _grow(delta: float) -> void:
	building_active = false
	build_stall = ""
	if plan_i >= PLAN.size():
		return
	var forge: HiveModule = modules.forge
	var eff := forge.efficiency()
	if eff <= 0.0:
		build_stall = "FORGE DOWN"
		return
	if starving or stores.nectar < 60.0:
		build_stall = "NEEDS NECTAR"
		return
	if stores.ore < 0.5:
		build_stall = "NEEDS ORE"
		return
	var rate := 3.5 * forge.level * eff
	var cost := plan_cost(plan_i)
	var spend := minf(minf(rate * delta, stores.ore), cost - plan_spent)
	stores.ore -= spend
	stores.nectar -= spend * 0.1
	plan_spent += spend
	building_active = true
	var tm := _plan_target()
	if tm != null:
		tm.grow_frac = plan_frac()
	if plan_spent >= cost - 0.001:
		_complete_item()


func _hatch(delta: float) -> void:
	var brood: HiveModule = modules.brood
	var g := Game.inst
	if drone_count() >= pop_cap() or starving or stores.nectar < 50.0 or not brood.online():
		return
	hatch_t += delta * brood.efficiency() * (0.7 + 0.3 * brood.level)
	if hatch_t >= 10.0:
		hatch_t = 0.0
		stores.nectar -= 15.0
		var guards := 0
		for a in g.allies:
			if a.role == "guard":
				guards += 1
		var want_guards := int((drone_count() + 1) / 3)
		g.spawn_drone(guards < want_guards, brood.position)


## Fleshy veins between the organs, with glowing pulses flowing outward.
class HiveVeins extends Node2D:
	var hive
	var links: Array = []  # [a, b, ctrl, built]
	var pulses: Array = []  # [sprite, link index, t]

	func rebuild() -> void:
		links.clear()
		var h: HiveModule = hive.heart
		for k in hive.CORE_ANG.keys():
			_link(h, hive.modules[k])
		for k in hive.GLAND_ANG.keys():
			var gm: HiveModule = hive.modules[k]
			var best: HiveModule = null
			var bd := INF
			for c in hive.CORE_ANG.keys():
				var cm: HiveModule = hive.modules[c]
				var d := cm.position.distance_to(gm.position)
				if d < bd:
					bd = d
					best = cm
			_link(best, gm)
		for s in hive.spires:
			var best: HiveModule = null
			var bd := INF
			for k in hive.GLAND_ANG.keys():
				var gm: HiveModule = hive.modules[k]
				var d := gm.position.distance_to(s.position)
				if d < bd:
					bd = d
					best = gm
			_link(best, s)
		for p in pulses:
			p[0].queue_free()
		pulses.clear()
		for i in links.size():
			if links[i][3]:
				var sp := Gfx.sprite("glow", Color(Gfx.C_HIVE, 0.7))
				sp.scale = Vector2.ONE * 0.16
				add_child(sp)
				pulses.append([sp, i, randf()])
		queue_redraw()

	func _link(a: HiveModule, b: HiveModule) -> void:
		var mid := (a.position + b.position) * 0.5
		var perp := (b.position - a.position).orthogonal().normalized()
		var ctrl := mid + perp * (b.position - a.position).length() * 0.12 * (1.0 if (links.size() % 2 == 0) else -1.0)
		links.append([a.position, b.position, ctrl, b.level > 0])

	func _bez(l: Array, t: float) -> Vector2:
		var a: Vector2 = l[0]
		var b: Vector2 = l[1]
		var c: Vector2 = l[2]
		return a.lerp(c, t).lerp(c.lerp(b, t), t)

	func _process(delta: float) -> void:
		for p in pulses:
			p[2] = fmod(p[2] + delta * 0.35, 1.0)
			var l: Array = links[p[1]]
			p[0].position = _bez(l, p[2])
			Gfx.tint(p[0], Color(Gfx.C_HIVE, 0.8 * sin(p[2] * PI)))

	func _draw() -> void:
		for l in links:
			var pts := PackedVector2Array()
			for i in 17:
				pts.append(_bez(l, i / 16.0))
			if l[3]:
				draw_polyline(pts, Color(Gfx.HIVE_RIM, 0.12), 26.0, true)
				draw_polyline(pts, Color(0.2, 0.08, 0.07, 0.95), 16.0, true)
				draw_polyline(pts, Color(Gfx.FLESH_RIM, 0.35), 2.0, true)
				draw_polyline(pts, Color(Gfx.C_HIVE, 0.12), 9.0, true)
				draw_polyline(pts, Color(Gfx.C_HIVE, 0.6), 2.2, true)
			else:
				draw_polyline(pts, Color(0.2, 0.1, 0.08, 0.5), 6.0, true)
				draw_polyline(pts, Color(Gfx.C_HIVE, 0.15), 1.2, true)
