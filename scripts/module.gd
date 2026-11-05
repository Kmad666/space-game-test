class_name HiveModule
extends Node2D
## One organ of the hive. Unbuilt modules sit as dormant buds until the Comb
## Forge grows them. Raiders can wound modules: below half health they work at
## half strength, at zero they go dark until you fly over and mend them.

const INFO := {
	"heart": {"name": "QUEEN'S HEART", "r": 140.0, "body": "heart"},
	"vault": {"name": "NECTAR VAULT", "r": 98.0, "body": "vault", "accepts": "nectar"},
	"forge": {"name": "COMB FORGE", "r": 92.0, "body": "forge", "accepts": "ore"},
	"cistern": {"name": "RIME CISTERN", "r": 90.0, "body": "cistern", "accepts": "ice"},
	"brood": {"name": "BROOD CHAMBER", "r": 92.0, "body": "brood"},
	"spire": {"name": "STINGER SPIRE", "r": 46.0, "body": "spire"},
	"carapace": {"name": "CARAPACE VAT", "r": 62.0, "body": "g_carapace"},
	"wing": {"name": "WING GLAND", "r": 62.0, "body": "g_wing"},
	"pouch": {"name": "POUCH GLAND", "r": 62.0, "body": "g_pouch"},
	"venom": {"name": "VENOM GLAND", "r": 62.0, "body": "g_venom"},
	"proboscis": {"name": "PROBOSCIS GLAND", "r": 62.0, "body": "g_proboscis"},
	"eye": {"name": "EYE STALK", "r": 52.0, "body": "g_eye"},
}
const CORE := ["vault", "forge", "cistern", "brood"]
const GLANDS := ["carapace", "wing", "pouch", "venom", "proboscis", "eye"]

var type := "vault"
var label := ""
var level := 0
var hp := 1.0
var max_hp := 1.0
var base_r := 60.0
var accepts := ""
var t := 0.0
var hit_flash := 0.0
var repair_glow := 0.0
var growing := false
var grow_frac := 0.0
var aim := 0.0
var fire_cd := 0.0
var target = null

var _body: Sprite2D
var _over: Sprite2D
var _over2: Sprite2D
var _bud: Sprite2D
var _dock: Sprite2D
var _nodules: Array = []


func setup(tp: String) -> void:
	type = tp
	var inf: Dictionary = INFO[tp]
	label = inf.name
	base_r = inf.r
	accepts = inf.get("accepts", "")
	z_index = 1 if tp != "heart" else 0
	t = randf() * 10.0
	fire_cd = randf()
	_bud = Gfx.sprite("bud")
	_bud.scale = Vector2.ONE * clampf(base_r / 50.0, 0.7, 1.6)
	add_child(_bud)
	if accepts != "":
		_dock = Gfx.sprite("dashring", Color(Gfx.res_color(accepts), 0.2))
		add_child(_dock)
	_body = Gfx.sprite(inf.body)
	add_child(_body)
	match tp:
		"heart":
			_over = Gfx.sprite("glow", Color(1.0, 0.45, 0.4, 0.8))
			_over.scale = Vector2.ONE * 0.9
			add_child(_over)
			_over2 = Gfx.sprite("dot", Color(1.0, 0.75, 0.6))
			_over2.scale = Vector2.ONE * 2.2
			add_child(_over2)
		"vault":
			_over = Gfx.sprite("vault_honey")
			add_child(_over)
		"forge":
			_over = Gfx.sprite("forge_core")
			add_child(_over)
		"cistern":
			_over = Gfx.sprite("glow", Color(Gfx.C_ICE, 0.5))
			_over.scale = Vector2.ONE * 1.1
			add_child(_over)
		"brood":
			_over = Gfx.sprite("glow", Color(Gfx.C_HIVE, 0.4))
			_over.scale = Vector2.ONE * 1.2
			add_child(_over)
		"spire":
			_over = Gfx.sprite("spire_h")
			add_child(_over)
		"eye":
			_over = Gfx.sprite("eye_iris")
			add_child(_over)
	set_level(0 if tp != "heart" else 1)


func built() -> bool:
	return level > 0


func online() -> bool:
	return level > 0 and hp > 0.0


func efficiency() -> float:
	if not online():
		return 0.0
	if type != "heart" and hp < max_hp * 0.5:
		return 0.5
	return 1.0


func radius() -> float:
	return base_r * (1.0 + 0.08 * maxi(level - 1, 0))


func dock_radius() -> float:
	return radius() + 70.0


func vision() -> float:
	if type == "heart":
		return 780.0
	if type == "spire":
		return 560.0
	return 520.0 if type in CORE else 480.0


func _calc_max_hp() -> float:
	var l := maxi(level, 1)
	if type in CORE:
		return 320.0 + 80.0 * (l - 1)
	if type == "spire":
		return 180.0 + 50.0 * (l - 1)
	return 220.0 + 50.0 * (l - 1)


func set_level(l: int) -> void:
	var was := level
	level = l
	var frac := hp / max_hp if was > 0 else 1.0
	max_hp = _calc_max_hp()
	hp = max_hp * frac if was > 0 else max_hp
	var b := built()
	_bud.visible = not b
	_body.visible = b
	if _over != null:
		_over.visible = b
	if _over2 != null:
		_over2.visible = b
	if _dock != null:
		_dock.visible = b
	var sc := 1.0 + 0.08 * maxi(level - 1, 0)
	_body.scale = Vector2.ONE * sc
	if _over != null and type in ["vault", "forge"]:
		_over.scale = Vector2.ONE * sc
	for nd in _nodules:
		nd.queue_free()
	_nodules.clear()
	if b and type != "heart":
		for i in maxi(level - 1, 0):
			var nd := Gfx.sprite("nodule")
			var a := TAU * i / maxf(level - 1, 1) + 0.6
			nd.position = Vector2.RIGHT.rotated(a) * radius() * 0.92
			add_child(nd)
			_nodules.append(nd)


func damage(amount: float) -> void:
	if type == "heart" or not online():
		return
	var before := hp
	hp = maxf(0.0, hp - amount)
	hit_flash = 0.25
	var g := Game.inst
	g.hive.last_hit_t = 1.5
	if before > 0.0 and hp <= 0.0:
		g.fx.burst(position, Color(1, 0.5, 0.4), 30, 200.0, 2.6, 0.9)
		g.hud.push_message("%s IS DOWN — FLY OVER TO MEND IT" % label, Color(1, 0.4, 0.35), 3.5)
	elif before >= max_hp * 0.5 and hp < max_hp * 0.5:
		g.hud.push_message("%s WOUNDED" % label, Color(1, 0.65, 0.35), 2.5)


## Returns how much health was restored.
func mend(amount: float) -> float:
	if level == 0 or hp >= max_hp:
		return 0.0
	var before := hp
	hp = minf(max_hp, hp + amount)
	repair_glow = 0.3
	if before <= 0.0 and hp > 0.0:
		Game.inst.hud.push_message("%s RESTORED" % label, Gfx.C_HIVE, 2.0)
	return hp - before


func _process(delta: float) -> void:
	t += delta
	hit_flash = maxf(0.0, hit_flash - delta)
	repair_glow = maxf(0.0, repair_glow - delta)
	var g := Game.inst
	if not built():
		var pulse := 0.6 + 0.25 * sin(t * 2.0)
		if growing:
			pulse = 0.75 + 0.25 * sin(t * 6.0)
			_bud.scale = Vector2.ONE * clampf(base_r / 50.0, 0.7, 1.6) * (0.8 + 0.4 * grow_frac)
		Gfx.tint(_bud, Color(pulse, pulse, pulse, 0.85))
		return
	# health tint
	var c := Color(1, 1, 1)
	if not online():
		var fl := 0.35 + 0.1 * sin(t * 9.0)
		c = Color(fl, fl * 0.8, fl * 0.8)
	elif hp < max_hp * 0.5:
		c = Color(1, 0.72, 0.65)
	if hit_flash > 0.0:
		c = c.lerp(Color(1.6, 0.8, 0.7), hit_flash * 3.0)
	if repair_glow > 0.0:
		c = c.lerp(Color(0.9, 1.5, 1.1), 0.5)
	Gfx.tint(_body, c)
	var hv: Hive = g.hive
	match type:
		"heart":
			var vit := hv.vitality
			var beat := 0.5 + 0.5 * pow(maxf(0.0, sin(t * (2.2 + (1.0 - vit) * 3.0))), 6.0)
			_over.scale = Vector2.ONE * (0.75 + 0.35 * beat)
			Gfx.tint(_over, Color(1.0, 0.45 * vit + 0.1, 0.4 * vit + 0.1, 0.55 + 0.35 * beat))
			Gfx.tint(_over2, Color(1.0, 0.7, 0.6, 0.6 + 0.4 * beat))
		"vault":
			Gfx.tint(_over, Color(1, 1, 1, 0.12 + 0.88 * hv.fill("nectar")) * Color(c.r, c.g, c.b, 1))
		"forge":
			var on := hv.building_active
			var p := (0.55 + 0.45 * sin(t * 5.0)) if on else 0.3
			Gfx.tint(_over, Color(1, 1, 1, p * (1.0 if online() else 0.2)))
		"cistern":
			Gfx.tint(_over, Color(Gfx.C_ICE, (0.1 + 0.55 * hv.fill("ice")) * (1.0 if online() else 0.3)))
		"brood":
			var p := hv.hatch_frac()
			Gfx.tint(_over, Color(Gfx.C_HIVE, (0.15 + 0.5 * p * (0.7 + 0.3 * sin(t * 8.0))) * (1.0 if online() else 0.2)))
		"spire":
			_spire(delta)
		"eye":
			var look := Vector2.RIGHT.rotated(t * 0.4)
			if g.player != null and not g.player.dead:
				look = g.player.position - position
			var e = g.nearest_enemy(position, 1400.0)
			if e != null:
				look = e.position - position
			_over.rotation = lerp_angle(_over.rotation, look.angle(), 1.0 - exp(-4.0 * delta))
	if _dock != null:
		var carrying: bool = g.player != null and not g.player.dead and g.player.cargo.get(accepts, 0.0) > 0.5
		_dock.rotation = t * 0.08
		_dock.scale = Vector2.ONE * (dock_radius() / 128.0)
		var a := 0.12 + (0.3 + 0.15 * sin(t * 5.0) if carrying else 0.0)
		Gfx.tint(_dock, Color(Gfx.res_color(accepts), a * (1.0 if online() else 0.3)))


func spire_range() -> float:
	return 500.0 + 40.0 * level


func _spire(delta: float) -> void:
	var g := Game.inst
	fire_cd -= delta
	if target == null or not is_instance_valid(target) or target.dead or position.distance_to(target.position) > spire_range():
		target = g.nearest_enemy(position, spire_range())
	if target != null and online():
		aim = lerp_angle(aim, (target.position - position).angle(), 1.0 - exp(-10.0 * delta))
		if fire_cd <= 0.0:
			fire_cd = 1.05 / efficiency()
			if g.hive.use("ice", 0.6):
				var tip := position + Vector2.RIGHT.rotated(aim) * 44.0
				g.fx.beam(tip, target.position, Gfx.C_ICE, 0.16, 2.6)
				g.fx.burst(target.position, Gfx.C_ICE, 4, 90.0, 1.6, 0.3)
				target.damage(9.0 + 4.0 * level, false)
	else:
		aim += delta * 0.3
	_over.rotation = aim
	var dry: bool = g.hive.stores.ice < 0.6
	Gfx.tint(_over, Color(0.5, 0.5, 0.5) if (dry or not online()) else Color.WHITE)
