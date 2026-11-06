class_name Field
extends Node2D
## A resource field: a cluster of one resource type, far from the hive, with
## its own resident guardians. Growths regrow after they're harvested and
## guardians come back some time after they're killed, so a field is never
## safe for long.

const NAMES := {
	"nectar": ["Hybla Bloom", "Hymettus Bloom"],
	"ore": ["Hephaestus Vein", "Cyclops Vein"],
	"ice": ["Khione Shelf", "Boreas Shelf"],
}
const GUARD := {"nectar": "polyp", "ore": "spitter", "ice": "lurker"}
const NEST_NAMES := ["VESPA BURROW", "TARTARUS BURROW", "EREBUS BURROW"]

var kind := "nectar"
var tier := 1
var radius := 420.0
var field_name := ""
var color := Color.WHITE
var node_target := 9
var regrow: Array = []
var slots: Array = []  # {kind, home, enemy, t}
var discovered := false
var awake := true
var danger := 0.0
var nest_slot := -1
var rng := RandomNumberGenerator.new()
var _aura: Sprite2D


func setup(k: String, t: int, pos: Vector2, seed_v: int, r: float, idx := 0) -> void:
	kind = k
	tier = t
	position = pos
	rng.seed = seed_v
	radius = r
	z_index = -2
	if k == "nest":
		color = Gfx.C_FOE
		field_name = NEST_NAMES[idx % NEST_NAMES.size()]
		node_target = 0
		_aura = Gfx.sprite("blob", Color(color, 0.22))
		_aura.scale = Vector2.ONE * (radius * 1.2 / 128.0)
		add_child(_aura)
		slots.append({"kind": "nestcore", "home": position, "enemy": null, "t": 0.0})
		for i in 3:
			var home := position + Vector2.RIGHT.rotated(TAU * i / 3.0 + rng.randf() * 0.5) * radius * 0.6
			slots.append({"kind": "spitter" if i < 2 else "polyp", "home": home, "enemy": null, "t": 0.0})
		tier = 2
		for i in slots.size():
			_spawn_guardian(i)
		return
	color = Gfx.res_color(k)
	node_target = 9 if tier == 1 else 13
	field_name = NAMES[k][tier - 1]
	_aura = Gfx.sprite("blob", Color(color, 0.18))
	_aura.scale = Vector2.ONE * (radius * 1.25 / 128.0)
	add_child(_aura)
	for i in node_target:
		spawn_node()
	# guardians
	var gk: String = GUARD[k]
	var count := 0
	match gk:
		"polyp":
			count = 1 if tier == 1 else 2
		"lurker":
			count = 2 if tier == 1 else 3
		"spitter":
			count = 2 if tier == 1 else 5
	for i in count:
		var home: Vector2
		if gk == "spitter":
			home = position + Vector2.RIGHT.rotated(TAU * i / count + rng.randf_range(-0.3, 0.3)) * radius * rng.randf_range(0.55, 0.85)
		elif gk == "polyp":
			home = position + (Vector2.ZERO if i == 0 else Vector2.RIGHT.rotated(rng.randf() * TAU) * radius * 0.5)
		else:
			home = position + Vector2.RIGHT.rotated(rng.randf() * TAU) * radius * rng.randf_range(0.2, 0.6)
		slots.append({"kind": gk, "home": home, "enemy": null, "t": 0.0})
		_spawn_guardian(slots.size() - 1)


func spawn_node() -> void:
	var g := Game.inst
	var r := rng.randf_range(26.0, 40.0) * (1.15 if tier == 2 else 1.0)
	var pos := position
	for tries in 24:
		pos = position + Vector2.RIGHT.rotated(rng.randf() * TAU) * radius * sqrt(rng.randf()) * 0.88
		var ok := true
		for o in g.res_nodes:
			if o.field == self and o.position.distance_to(pos) < o.radius + r + 30.0:
				ok = false
				break
		if ok:
			for s in slots:
				if s.home.distance_to(pos) < 70.0:
					ok = false
		if ok:
			break
	var nd := ResNode.new()
	nd.setup(kind, r * (1.2 if tier == 2 else 1.0), r, self, rng)
	nd.position = pos
	g.layer_res.add_child(nd)
	g.res_nodes.append(nd)


func on_node_depleted(_nd) -> void:
	regrow.append(rng.randf_range(35.0, 60.0))


func node_count() -> int:
	var c := 0
	for nd in Game.inst.res_nodes:
		if nd.field == self:
			c += 1
	return c


func _spawn_guardian(i: int) -> void:
	var s: Dictionary = slots[i]
	var e: Enemy = Game.inst.spawn_enemy(s.kind, s.home, self)
	e.slot = i
	s.enemy = e
	if not awake:
		e.process_mode = Node.PROCESS_MODE_DISABLED
		e.visible = false
	if s.kind == "nestcore" and Game.inst.state == "playing":
		Game.inst.hud.push_message("%s HAS REGROWN ITS CORE" % field_name, Gfx.C_FOE, 3.0)


func on_guardian_died(i: int) -> void:
	if i < 0 or i >= slots.size():
		return
	var s: Dictionary = slots[i]
	s.enemy = null
	s.t = rng.randf_range(70.0, 100.0) if s.kind != "lurker" else rng.randf_range(55.0, 80.0)
	if s.kind == "nestcore":
		s.t = 240.0
		Game.inst.hud.push_message("%s SILENCED — NO SWARMS FROM IT FOR A WHILE" % field_name, Color(1, 0.8, 0.4), 4.0)


## A rival burrow with its core alive sends swarms; a silenced one doesn't.
func dormant() -> bool:
	return kind == "nest" and slots[0].enemy == null


## Far-away zones sleep: their creatures freeze until the player comes near.
func set_awake(on: bool) -> void:
	if on == awake:
		return
	awake = on
	var pm := Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	for e in Game.inst.enemies:
		if e.field == self:
			e.process_mode = pm
			if not on:
				e.visible = false
	for nd in Game.inst.res_nodes:
		if nd.field == self:
			nd.process_mode = pm


## Rough danger rating used by forager drones to pick where to go.
func threat() -> float:
	var th := 0.0
	for s in slots:
		if s.enemy != null:
			th += 1.0
	for e in Game.inst.enemies:
		if e.kind == "mite" and e.field == self:
			th += 0.4
	return th


func _process(delta: float) -> void:
	danger = maxf(0.0, danger - delta)
	var i := 0
	while i < regrow.size():
		regrow[i] -= delta
		if regrow[i] <= 0.0:
			regrow.remove_at(i)
			spawn_node()
			Game.inst.fx.ring(Game.inst.res_nodes[Game.inst.res_nodes.size() - 1].position, color, 50.0, 0.8, 2.0)
		else:
			i += 1
	for j in slots.size():
		var s: Dictionary = slots[j]
		if s.enemy == null:
			s.t -= delta
			if s.t <= 0.0:
				_spawn_guardian(j)
	if not discovered and Game.inst.fog.is_seen(position):
		discovered = true
		Game.inst.on_field_discovered(self)
