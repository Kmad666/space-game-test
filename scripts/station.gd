class_name Station
extends Node2D
## Aegis Station. Grows a level each time enough ore is delivered: bigger
## rings, more modules, solar arrays, defense turrets and a new escort bot.
## Its rings are baked into textures once per level and simply rotated.

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

var _dock: Sprite2D
var _assembly: Sprite2D
var _mid: Sprite2D
var _hub: Sprite2D
var _core: Sprite2D
var _dyn: StationDyn
var _baking := false
var _baked_level := -1


func _ready() -> void:
	z_index = 1
	_apply_level()
	hp = max_hp
	_dock = Gfx.sprite("dashring", Color(0.4, 0.9, 1.0, 0.2))
	add_child(_dock)
	_assembly = _premult_sprite()
	_mid = _premult_sprite()
	_hub = _premult_sprite()
	_core = Gfx.sprite("dot", Color(0.85, 0.75, 1.0))
	add_child(_core)
	_dyn = StationDyn.new()
	_dyn.st = self
	add_child(_dyn)
	_rebake()


func _premult_sprite() -> Sprite2D:
	var s := Sprite2D.new()
	s.material = Gfx.premult
	add_child(s)
	return s


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
	if _baked_level != level:
		_rebake()


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
	_update_visuals()
	if dead:
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


func _update_visuals() -> void:
	var hurt := 1.0 - hp / max_hp
	var tint := Color(1, 1, 1).lerp(Color(1, 0.45, 0.4), clampf(hurt * 1.3 - 0.3, 0.0, 0.8))
	_assembly.rotation = t * 0.12
	_mid.rotation = -t * 0.3
	_hub.rotation = t * 0.2
	_dock.rotation = t * 0.08
	_dock.scale = Vector2.ONE * (dock_radius() / 128.0)
	Gfx.tint(_dock, Color(0.4, 0.9, 1.0, 0.16 + deposit_glow * 0.35))
	_assembly.modulate = tint
	var pulse := 0.85 + 0.15 * sin(t * 3.0) + deposit_glow * 0.4
	_core.scale = Vector2.ONE * (radius * 0.11 / 6.0) * pulse
	_dyn.queue_redraw()


# ---------------------------------------------------------------- baking
func _rebake() -> void:
	if _baking:
		return
	_baking = true
	while _baked_level != level:
		var lvl := level
		var R := radius
		var arrays_len := 40.0 + 8.0 * lvl
		var ext := int(ceil(R + arrays_len + 24.0))
		var sz := Vector2i(ext * 2, ext * 2)
		var c := Vector2(ext, ext)
		var tex_a: Texture2D = await Gfx.bake(self, sz, func(ci): _draw_assembly(ci, c, R, lvl))
		var mid_ext := int(ceil(R * 0.62 + 16.0))
		var tex_m: Texture2D = await Gfx.bake(self, Vector2i(mid_ext * 2, mid_ext * 2), func(ci): _draw_mid(ci, Vector2(mid_ext, mid_ext), R, lvl))
		var hub_ext := int(ceil(R * 0.34 + 18.0))
		var tex_h: Texture2D = await Gfx.bake(self, Vector2i(hub_ext * 2, hub_ext * 2), func(ci): _draw_hub(ci, Vector2(hub_ext, hub_ext), R, lvl))
		_assembly.texture = tex_a
		_mid.texture = tex_m
		_hub.texture = tex_h
		_baked_level = lvl
	_baking = false


static func _draw_assembly(ci: CanvasItem, o: Vector2, R: float, lvl: int) -> void:
	var cyan := Color(0.4, 0.9, 1.0)
	var arrays := 0
	if lvl >= 3:
		arrays = 2
	if lvl >= 6:
		arrays = 4
	if lvl >= 9:
		arrays = 6
	for i in arrays:
		var a := TAU * i / arrays + 0.4
		var dir := Vector2.RIGHT.rotated(a)
		var perp := dir.orthogonal()
		var L := 40.0 + 8.0 * lvl
		var W := 14.0 + lvl * 0.8
		var base := o + dir * (R + 6.0)
		var quad := PackedVector2Array([base + perp * W * 0.5, base + dir * L + perp * W * 0.5, base + dir * L - perp * W * 0.5, base - perp * W * 0.5])
		ci.draw_colored_polygon(quad, Color(0.05, 0.12, 0.3, 0.9))
		for k in range(1, 5):
			var f := float(k) / 5.0
			ci.draw_line(base + dir * L * f + perp * W * 0.5, base + dir * L * f - perp * W * 0.5, Color(0.3, 0.55, 1.0, 0.45), 1.0, true)
		ci.draw_line(base, base + dir * L, Color(0.3, 0.55, 1.0, 0.4), 1.0, true)
		Neon.outline(ci, quad, Color(0.4, 0.65, 1.0, 0.85), 1.2, 0.5)
	var nmod := 3 + lvl
	ci.draw_circle(o, R, Color(0.02, 0.05, 0.09, 0.6))
	Neon.ring(ci, o, R, cyan, 3.0, 1.0, 64)
	Neon.ring(ci, o, R - 9.0, Color(cyan, 0.35), 1.0, 0.4, 64)
	for i in nmod:
		var a := TAU * i / nmod
		var dir := Vector2.RIGHT.rotated(a)
		var perp := dir.orthogonal()
		Neon.line(ci, o + dir * R * 0.36, o + dir * (R - 9.0), Color(cyan, 0.35), 1.2, 0.4)
		var c := o + dir * R
		var mw := 9.0 + lvl * 0.6
		var mh := 6.0 + lvl * 0.3
		var box := PackedVector2Array([c + perp * mw + dir * mh, c - perp * mw + dir * mh, c - perp * mw - dir * mh, c + perp * mw - dir * mh])
		ci.draw_colored_polygon(box, Color(0.03, 0.09, 0.14, 1))
		Neon.outline(ci, box, Color(cyan, 0.95), 1.4, 0.6)
		Neon.dot(ci, c + dir * (mh + 3.0), 1.6, Color(1, 0.85, 0.4), 0.8)


static func _draw_mid(ci: CanvasItem, o: Vector2, R: float, lvl: int) -> void:
	var mid := R * 0.62
	var mseg := 12 + lvl * 2
	for i in mseg:
		var a0 := TAU * i / mseg
		Neon.arc(ci, o, mid, a0, a0 + TAU / mseg * 0.6, Color(0.6, 0.85, 1.0, 0.7), 2.0, 0.5, 4)


static func _draw_hub(ci: CanvasItem, o: Vector2, R: float, lvl: int) -> void:
	var hub := PackedVector2Array()
	var hsides := 6 if lvl < 5 else 8
	for i in hsides:
		hub.append(o + Vector2.RIGHT.rotated(TAU * i / hsides) * R * 0.34)
	ci.draw_colored_polygon(hub, Color(0.03, 0.08, 0.16, 1))
	Neon.outline(ci, hub, Color(0.7, 0.95, 1.0), 2.0, 0.8)


## Cheap per-frame bits: turrets, shield flash and the level-up shockwave.
class StationDyn extends Node2D:
	var st

	func _draw() -> void:
		var R: float = st.radius
		var cyan := Color(0.4, 0.9, 1.0)
		if st.level_pulse > 0.0:
			var lp: float = st.level_pulse
			draw_arc(Vector2.ZERO, R + (1.0 - lp) * 400.0, 0, TAU, 48, Color(cyan, lp * 0.25), 8.0)
			draw_arc(Vector2.ZERO, R + (1.0 - lp) * 400.0, 0, TAU, 48, Color(cyan, lp), 2.5)
		for i in st.turret_count():
			var tp: Vector2 = st.turret_pos(i) - st.position
			var a: float = st.turret_aim[i]
			var tri := PackedVector2Array([tp + Vector2(11, 0).rotated(a), tp + Vector2(-6, -6).rotated(a), tp + Vector2(-6, 6).rotated(a)])
			draw_colored_polygon(tri, Color(0.05, 0.12, 0.18, 1))
			tri.append(tri[0])
			draw_polyline(tri, Color(0.75, 0.95, 1.0), 1.6)
		if st.hit_flash > 0.0:
			draw_arc(Vector2.ZERO, R + 16.0, 0, TAU, 48, Color(0.5, 0.85, 1.0, st.hit_flash * 0.8), 8.0)
			draw_arc(Vector2.ZERO, R + 16.0, 0, TAU, 48, Color(0.5, 0.85, 1.0, st.hit_flash * 2.5), 2.5)
