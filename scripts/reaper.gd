class_name Reaper
extends Node2D
## The Reaper: a vast, slow, armored serpent that comes for the hive's stores.
## It latches onto the Nectar Vault and siphons 15-30% of every store (less the
## more you've hurt it), then slithers off. It usually gets away — but kill it
## before it leaves and it bursts, spilling everything it stole as globs.

const NSEG := 8
const SPACING := 44.0

var kind := "reaper"
var field = null
var index := 0
var hp := 3200.0
var max_hp := 3200.0
var hit_radius := 60.0
var vel := Vector2.ZERO
var color := Gfx.C_REAPER
var dead := false
var t := 0.0
var flash := 0.0
var state := "approach"
var speed := 55.0
var heading := 0.0
var segs: Array = []
var stolen := {"nectar": 0.0, "ore": 0.0, "ice": 0.0}
var snapshot := {}
var stolen_frac := 0.0
var lash_cd := 2.0
var exit_point := Vector2.ZERO

var _head: Sprite2D
var _seg_sprites: Array = []
var _tail: Sprite2D
var _glow: Sprite2D


func setup(pos: Vector2, idx: int) -> void:
	index = idx
	position = pos
	max_hp = 3200.0 + 1400.0 * idx
	hp = max_hp
	heading = (-pos).angle()
	z_index = 5
	for i in NSEG:
		segs.append(pos - Vector2.RIGHT.rotated(heading) * SPACING * (i + 1))
	_tail = Gfx.sprite("reaper_t")
	add_child(_tail)
	for i in range(NSEG - 1, -1, -1):
		var s := Gfx.sprite("reaper_s")
		s.scale = Vector2.ONE * (1.0 - 0.05 * i)
		add_child(s)
		_seg_sprites.push_front(s)
	_head = Gfx.sprite("reaper_h")
	add_child(_head)
	_glow = Gfx.sprite("glow", Color(Gfx.C_REAPER, 0.0))
	_glow.scale = Vector2.ONE * 1.6
	add_child(_glow)


func _process(delta: float) -> void:
	var g := Game.inst
	t += delta
	flash = maxf(0.0, flash - delta)
	var vault: HiveModule = g.hive.modules.vault
	var goal := position
	match state:
		"approach":
			goal = vault.position
			if position.distance_to(vault.position) < vault.radius() + 70.0:
				state = "siphon"
				snapshot = g.hive.stores.duplicate()
				g.hud.push_message("THE REAPER IS SIPHONING THE VAULT!", Color(1, 0.4, 0.8), 4.0)
				g.shake = maxf(g.shake, 8.0)
		"siphon":
			goal = vault.position + Vector2.RIGHT.rotated(t * 0.3) * (vault.radius() + 40.0)
			var rate := 0.016 * delta
			for k in stolen.keys():
				var amt := minf(snapshot[k] * rate, g.hive.stores[k])
				g.hive.stores[k] -= amt
				stolen[k] += amt
			stolen_frac += rate
			if randf() < 0.5:
				var k: String = ["nectar", "ore", "ice"][randi() % 3]
				g.fx.homing(vault.position + Vector2(randf_range(-40, 40), randf_range(-40, 40)), self, Gfx.res_color(k), 2.4)
			var cap := 0.15 + 0.15 * (hp / max_hp)
			if stolen_frac >= cap:
				state = "flee"
				var dir := position.normalized()
				if dir == Vector2.ZERO:
					dir = Vector2.RIGHT
				exit_point = dir * (Game.WORLD_HALF * 1.5)
				g.hud.push_message("THE REAPER IS FLEEING WITH %d%% OF THE STORES — CHASE IT DOWN!" % int(round(stolen_frac * 100.0)), Color(1, 0.5, 0.85), 4.0)
		"flee":
			goal = exit_point
			if absf(position.x) > Game.WORLD_HALF + 200.0 or absf(position.y) > Game.WORLD_HALF + 200.0:
				g.on_reaper_escaped(self)
				dead = true
				g.enemies.erase(self)
				queue_free()
				return
	var spd := speed if state != "flee" else 78.0
	if state == "siphon":
		spd = 30.0
	var want := (goal - position).angle() + 0.3 * sin(t * 1.4)
	heading = lerp_angle(heading, want, 1.0 - exp(-0.9 * delta))
	vel = Vector2.RIGHT.rotated(heading) * spd
	position += vel * delta
	# chain
	var prev := position - Vector2.RIGHT.rotated(heading) * 34.0
	for i in NSEG:
		var p: Vector2 = segs[i]
		var d := p - prev
		if d.length() < 0.01:
			d = -Vector2.RIGHT.rotated(heading)
		segs[i] = prev + d.normalized() * SPACING
		prev = segs[i]
	# tail lash
	lash_cd -= delta
	if lash_cd <= 0.0:
		lash_cd = 2.0
		var pts := [position, segs[3], segs[NSEG - 1]]
		for a in g.allies:
			if a.dead:
				continue
			for p in pts:
				if a.position.distance_to(p) < 150.0:
					a.damage(12.0)
					g.fx.ring(p, Gfx.C_REAPER, 150.0, 0.4, 2.5)
					break
	_update_visuals()
	visible = g.fog.is_seen(position) or g.fog.is_seen(segs[NSEG / 2]) or g.fog.is_seen(segs[NSEG - 1])


func _update_visuals() -> void:
	var c := Color(1, 1, 1).lerp(Color(1.8, 1.8, 1.8), flash * 5.0)
	_head.rotation = heading
	Gfx.tint(_head, c)
	var prev := position
	for i in NSEG:
		var p: Vector2 = segs[i]
		var s: Sprite2D = _seg_sprites[i]
		s.position = p - position
		s.rotation = (prev - p).angle()
		Gfx.tint(s, c)
		prev = p
	var last: Vector2 = segs[NSEG - 1]
	_tail.position = last - position + (last - segs[NSEG - 2]).normalized() * 30.0
	_tail.rotation = (segs[NSEG - 2] - last).angle()
	Gfx.tint(_tail, c)
	var gl := 0.0
	if state == "siphon":
		gl = 0.45 + 0.25 * sin(t * 6.0)
	Gfx.tint(_glow, Color(Gfx.C_REAPER, gl))


func damage(amount: float, by_player: bool = false) -> void:
	if dead:
		return
	hp -= amount
	flash = 0.08
	if hp <= 0.0:
		die(by_player)


func die(_by_player: bool) -> void:
	if dead:
		return
	dead = true
	var g := Game.inst
	g.fx.explosion(position, Gfx.C_REAPER, 3.0)
	for p in segs:
		g.fx.explosion(p, Gfx.C_REAPER, 1.2)
	g.shake = 18.0
	var total := 0.0
	for k in stolen.keys():
		var amt: float = stolen[k]
		total += amt
		var n := mini(int(ceil(amt / 15.0)), 14)
		for i in n:
			var at: Vector2 = segs[randi() % NSEG] if i % 2 == 0 else position
			g.spawn_glob(k, amt / n, at + Vector2(randf_range(-30, 30), randf_range(-30, 30)))
	g.on_reaper_killed(self, total)
	g.enemies.erase(self)
	queue_free()
