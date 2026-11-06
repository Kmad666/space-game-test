class_name HUD
extends Control
## Interface: the hive's vital signs, threats, growth, your own body, a fogged
## minimap, edge arrows for anything that needs you, and the title / pause /
## game-over screens. No buttons during play — you just fly.

const MINT := Gfx.C_HIVE
const AMBER := Color(1.0, 0.78, 0.38)
const RED := Color(1.0, 0.34, 0.36)
const MAG := Gfx.C_REAPER
const PANEL := Color(0.03, 0.03, 0.02, 0.74)
const MM := 200.0

var messages := []  # [text, color, life, max]
var t := 0.0
var font: Font
var _redraw_t := 0.0
var _title_ships: TitleShips
var _mini_fog: TextureRect
var _mini_top: MiniTop


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	_title_ships = TitleShips.new()
	_title_ships.hud = self
	_title_ships.material = Gfx.premult
	add_child(_title_ships)
	_mini_fog = TextureRect.new()
	_mini_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_fog.stretch_mode = TextureRect.STRETCH_SCALE
	_mini_fog.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_mini_fog)
	_mini_top = MiniTop.new()
	_mini_top.hud = self
	add_child(_mini_top)


func push_message(txt: String, col: Color, dur: float = 2.5) -> void:
	for m in messages:
		if m[0] == txt:
			m[2] = dur
			return
	messages.append([txt, col, dur, dur])
	if messages.size() > 4:
		messages.pop_front()


func minimap_rect() -> Rect2:
	return Rect2(size.x - MM - 14, 14, MM, MM)


func world_to_mini(p: Vector2) -> Vector2:
	var r := minimap_rect()
	return r.get_center() + p * ((MM - 8.0) / (Game.WORLD_HALF * 2.0))


func _process(delta: float) -> void:
	t += delta
	position = Vector2.ZERO
	size = get_viewport_rect().size
	var i := 0
	while i < messages.size():
		messages[i][2] -= delta
		if messages[i][2] <= 0.0:
			messages.remove_at(i)
		else:
			i += 1
	var g := Game.inst
	_title_ships.visible = g.state == "title"
	if g.state == "title":
		_title_ships.queue_redraw()
	var playing := g.state != "title" and g.fog != null
	_mini_fog.visible = playing
	_mini_top.visible = playing
	if playing:
		var r := minimap_rect()
		var inner := r.grow(-4)
		# the fog texture spans fog.half on each side; map it onto the minimap scale
		var k := (MM - 8.0) / (Game.WORLD_HALF * 2.0)
		var span := g.fog.half * 2.0 * k
		_mini_fog.position = inner.get_center() - Vector2(span, span) * 0.5
		_mini_fog.size = Vector2(span, span)
		if _mini_fog.texture != g.fog.tex:
			_mini_fog.texture = g.fog.tex
			_mini_fog.material = g.fog.material
		_mini_top.queue_redraw()
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 1.0 / 30.0
		queue_redraw()


# ---------------------------------------------------------------- helpers
func _txt(pos: Vector2, s: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0, glow := false) -> void:
	if glow:
		draw_string_outline(font, pos, s, align, w, sz, 10, Color(col, 0.12 * col.a))
		draw_string_outline(font, pos, s, align, w, sz, 4, Color(col, 0.25 * col.a))
	else:
		draw_string_outline(font, pos, s, align, w, sz, 4, Color(0, 0, 0, 0.6 * col.a))
	draw_string(font, pos, s, align, w, sz, col)


func _bar(r: Rect2, f: float, col: Color) -> void:
	draw_rect(r, Color(1, 1, 1, 0.07))
	var fr := Rect2(r.position, Vector2(r.size.x * clampf(f, 0.0, 1.0), r.size.y))
	draw_rect(fr.grow(2.0), Color(col, 0.12))
	draw_rect(fr, col)
	draw_rect(Rect2(fr.position, Vector2(fr.size.x, 1.0)), Color(1, 1, 1, 0.3))
	draw_rect(r, Color(col, 0.35), false, 1.0)


## Organic panel: dark comb backing with amber chitin corners.
func _panel(r: Rect2, accent := AMBER) -> void:
	draw_rect(r, PANEL)
	draw_rect(r, Color(accent, 0.2), false, 1.0)
	var c := 12.0
	for corner in [[r.position, Vector2(1, 0), Vector2(0, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1)],
			[Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1)], [r.end, Vector2(-1, 0), Vector2(0, -1)]]:
		var p: Vector2 = corner[0]
		var pts := PackedVector2Array([p + corner[1] * c, p, p + corner[2] * c])
		draw_polyline(pts, Color(accent, 0.9), 2.0, true)
		draw_circle(p, 2.5, Color(accent, 0.9))


func _hex(c: Vector2, r: float, col: Color, filled := true) -> void:
	var p := Bio.hexagon(c, r, PI / 6.0)
	if filled:
		draw_colored_polygon(p, col)
	else:
		p.append(p[0])
		draw_polyline(p, col, 1.4, true)


func _mmss(sec: float) -> String:
	var s := int(ceil(maxf(sec, 0.0)))
	return "%d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------- draw
func _draw() -> void:
	var g := Game.inst
	if g == null or g.player == null:
		return
	if g.state == "title":
		_draw_title()
		return
	_draw_indicators()
	_draw_hive_panel()
	_draw_threat_panel()
	_draw_minimap()
	_draw_self_panel()
	_draw_growth_panel()
	_draw_messages()
	var q := "LOW-SPEC" if g.low_quality else "HIGH"
	var mr := minimap_rect()
	_txt(Vector2(mr.position.x, mr.end.y + 16), "%d FPS · Q quality: %s" % [int(round(g.fps_now)), q], 11, Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, MM)
	_txt(Vector2(0, size.y - 8), "Mouse: fly   ·   Wheel / − + : zoom   ·   Space: hover   ·   P: pause   ·   F: fullscreen", 11, Color(1, 1, 1, 0.3), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if g.player.dead and g.state == "playing":
		_txt(Vector2(0, size.y * 0.42), "YOU FELL", 34, RED, HORIZONTAL_ALIGNMENT_CENTER, size.x, true)
		_txt(Vector2(0, size.y * 0.42 + 36), "Reborn at the Heart in %d…" % int(ceil(g.player.respawn_t)), 18, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if g.state == "paused":
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		_txt(Vector2(0, size.y * 0.45), "PAUSED", 56, AMBER, HORIZONTAL_ALIGNMENT_CENTER, size.x, true)
		_txt(Vector2(0, size.y * 0.45 + 44), "click or press P to resume", 18, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if g.state == "over":
		_draw_over()


func _draw_hive_panel() -> void:
	var g := Game.inst
	var hv: Hive = g.hive
	var r := Rect2(14, 14, 290, 168)
	var accent := AMBER
	if hv.starving:
		accent = AMBER.lerp(RED, 0.5 + 0.5 * sin(t * 8.0))
	_panel(r, accent)
	var x := r.position.x + 14
	var y := r.position.y + 24
	_txt(Vector2(x, y), "THE HIVE", 16, AMBER, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var crave := hv.craving()
	_txt(Vector2(x, y), "craves %s" % crave.to_upper(), 12, Color(Gfx.res_color(crave), 0.6 + 0.4 * sin(t * 3.0)), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 28)
	y += 12
	# heart vitality
	var vit := hv.vitality
	_txt(Vector2(x, y + 9), "HEART", 10, Color(1, 1, 1, 0.6))
	_bar(Rect2(x + 58, y + 1, 204, 8), vit, Color(1, 0.45, 0.45).lerp(RED, 1.0 - vit) if vit < 1.0 else Color(1, 0.55, 0.5))
	y += 18
	for k in ["nectar", "ore", "ice"]:
		var col := Gfx.res_color(k)
		_hex(Vector2(x + 5, y + 5), 5.0, col)
		_txt(Vector2(x + 14, y + 9), k.to_upper(), 10, Color(col, 0.85))
		_bar(Rect2(x + 58, y + 1, 204, 8), hv.fill(k), col)
		var label := "%d / %d" % [int(hv.stores[k]), int(hv.cap(k))]
		if k == "nectar":
			label = "−%.1f/s   %s" % [hv.upkeep(), label]
		_txt(Vector2(x + 58, y + 22), label, 10, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 204)
		y += 26
	y += 4
	var pop := hv.drone_count()
	_txt(Vector2(x, y + 9), "DRONES  %d / %d" % [pop, hv.pop_cap()], 11, Color(MINT, 0.9))
	if pop < hv.pop_cap():
		_bar(Rect2(x + 130, y + 2, 132, 6), hv.hatch_frac(), Color(MINT, 0.8))
	else:
		_txt(Vector2(x + 130, y + 9), "brood full", 10, Color(1, 1, 1, 0.4))
	if hv.starving:
		_txt(Vector2(x, r.end.y + 20), "STARVING — THE HEART WITHERS", 13, Color(RED, 0.7 + 0.3 * sin(t * 8.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, true)


func _draw_threat_panel() -> void:
	var g := Game.inst
	var w := 360.0
	var r := Rect2((size.x - w) * 0.5, 14, w, 64)
	var swarm := 0
	for e in g.enemies:
		if e.kind == "swarm":
			swarm += 1
	var rp = g.reaper_alive()
	var accent := AMBER
	if swarm > 0 or rp != null or g.hive.last_hit_t > 0.0:
		accent = AMBER.lerp(RED, 0.5 + 0.5 * sin(t * 10.0))
	_panel(r, accent)
	var cx := r.position.x
	var y := r.position.y + 25
	if swarm > 0:
		_txt(Vector2(cx, y), "SWARM — %d SWARMLING%s" % [swarm, "" if swarm == 1 else "S"], 15, Color(Gfx.C_SWARM, 0.8 + 0.2 * sin(t * 6.0)), HORIZONTAL_ALIGNMENT_CENTER, w, true)
	else:
		var col := Color(1, 1, 1, 0.75) if g.swarm_t > 12.0 else Color(Gfx.C_SWARM, 0.75 + 0.25 * sin(t * 10.0))
		var src := "?" if g.swarm_src == null or g.swarm_t >= 12.0 else g.swarm_src.field_name
		if g.swarm_src == null:
			src = "the burrows are quiet"
		_txt(Vector2(cx, y), "NEXT SWARM %s  ·  %s" % [_mmss(g.swarm_t), src], 14, col, HORIZONTAL_ALIGNMENT_CENTER, w)
	y += 24
	if rp != null:
		var s := "REAPER INBOUND"
		if rp.state == "siphon":
			s = "REAPER SIPHONING — %d%% TAKEN" % int(rp.stolen_frac * 100.0)
		elif rp.state == "flee":
			s = "REAPER FLEEING WITH %d%%" % int(rp.stolen_frac * 100.0)
		_txt(Vector2(cx, y), s, 15, Color(MAG, 0.8 + 0.2 * sin(t * 6.0)), HORIZONTAL_ALIGNMENT_CENTER, w, true)
	else:
		var col := Color(1, 1, 1, 0.55) if g.reaper_t > 30.0 else Color(MAG, 0.75 + 0.25 * sin(t * 8.0))
		_txt(Vector2(cx, y), "REAPER STIRS IN %s" % _mmss(g.reaper_t), 13, col, HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_minimap() -> void:
	var g := Game.inst
	var r := minimap_rect()
	_panel(r)
	draw_rect(r.grow(-4), Color(0.02, 0.025, 0.04, 1))
	var hv: Hive = g.hive
	var k := (MM - 8.0) / (Game.WORLD_HALF * 2.0)
	for tn in g.cave.tunnels:
		var pts := PackedVector2Array()
		for p in tn[0]:
			pts.append(world_to_mini(p))
		draw_polyline(pts, Color(0.35, 0.25, 0.42, 0.9), maxf(tn[1] * 2.0 * k, 2.0))
	for c in g.cave.chambers:
		draw_circle(world_to_mini(c.pos), c.r * k, Color(0.35, 0.25, 0.42, 0.9))
	for n in g.nests:
		if n.discovered:
			draw_circle(world_to_mini(n.position), 5.0, Color(Gfx.C_FOE, 0.4 if n.dormant() else 0.9))
	# hive: veins of the organs
	for m in hv.all_modules():
		var p := world_to_mini(m.position)
		if m.level == 0:
			draw_circle(p, 1.5, Color(MINT, 0.25))
			continue
		var col := Color(AMBER, 0.85)
		if m.accepts != "":
			col = Gfx.res_color(m.accepts)
		if not m.online():
			col = Color(RED, 0.5 + 0.5 * sin(t * 8.0))
		elif m.hp < m.max_hp * 0.5:
			col = Color(1, 0.6, 0.3)
		draw_circle(p, 4.5 if m.type == "heart" else (3.0 if m.type != "spire" else 2.0), col)
	for f in g.fields:
		if not f.discovered:
			continue
		var p := world_to_mini(f.position)
		var rr: float = f.radius * (MM - 8.0) / (Game.WORLD_HALF * 2.0)
		draw_circle(p, rr, Color(f.color, 0.18))
		draw_arc(p, rr, 0, TAU, 20, Color(f.color, 0.7), 1.2, true)
	for nd in g.res_nodes:
		if g.fog.is_explored(nd.position):
			draw_rect(Rect2(world_to_mini(nd.position) - Vector2(1, 1), Vector2(2, 2)), Color(nd.color, 0.6))


func _draw_self_panel() -> void:
	var g := Game.inst
	var p: Ship = g.player
	var hv: Hive = g.hive
	var r := Rect2(14, size.y - 136, 290, 112)
	_panel(r, Color(Gfx.C_PLAYER, 1.0))
	var x := r.position.x + 14
	var y := r.position.y + 24
	_txt(Vector2(x, y), "YOU · %s" % Ship.FORM_NAMES[p.form], 16, Gfx.C_PLAYER, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var s := 0
	for k in ["carapace", "wing", "pouch", "venom", "proboscis"]:
		s += hv.modules[k].level
	if p.form < Ship.FORM_THRESH.size() - 1:
		_txt(Vector2(x, y - 1), "next molt %d/%d" % [s, Ship.FORM_THRESH[p.form + 1]], 10, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 28)
	y += 12
	var hf := p.hp / p.max_hp() if not p.dead else 0.0
	_txt(Vector2(x, y + 9), "BODY", 10, Color(1, 1, 1, 0.6))
	_bar(Rect2(x + 52, y + 1, 210, 8), hf, Gfx.C_PLAYER.lerp(RED, clampf(1.0 - hf * 1.6, 0.0, 1.0)))
	y += 16
	_txt(Vector2(x, y + 9), "CARGO", 10, Color(1, 1, 1, 0.6))
	var cr := Rect2(x + 52, y + 1, 210, 8)
	draw_rect(cr, Color(1, 1, 1, 0.07))
	var cx := cr.position.x
	var capv := p.cargo_cap()
	for k in ["nectar", "ore", "ice"]:
		var w: float = cr.size.x * p.cargo[k] / capv
		if w > 0.5:
			draw_rect(Rect2(cx, cr.position.y, w, cr.size.y), Gfx.res_color(k))
			cx += w
	draw_rect(cr, Color(1, 1, 1, 0.25), false, 1.0)
	_txt(Vector2(x + 52, y + 22), "%d / %d" % [int(p.cargo_total()), int(capv)], 10, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 210)
	y += 30
	var parts := []
	for k in ["carapace", "wing", "pouch", "venom", "proboscis", "eye"]:
		var lv := hv.gland(k)
		if lv > 0:
			parts.append("%s %s" % [k.to_upper(), Hive._roman(lv)])
	var aug := " · ".join(parts) if not parts.is_empty() else "no glands grown yet"
	_txt(Vector2(x, y + 6), aug, 10, Color(MINT, 0.7), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24)
	if p.cargo_total() >= capv * 0.99:
		_txt(Vector2(x, r.position.y - 8), "POUCH FULL — HAUL IT HOME", 12, Color(AMBER, 0.6 + 0.4 * sin(t * 6.0)))


func _draw_growth_panel() -> void:
	var g := Game.inst
	var hv: Hive = g.hive
	var r := Rect2(size.x - 304, size.y - 104, 290, 80)
	_panel(r, MINT)
	var x := r.position.x + 14
	var y := r.position.y + 24
	var item := hv.plan_item()
	if item.is_empty():
		_txt(Vector2(x, y), "THE HIVE IS FULLY GROWN", 14, MINT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		return
	_txt(Vector2(x, y), "GROWING", 11, Color(1, 1, 1, 0.55))
	_txt(Vector2(x + 64, y), hv.plan_label(item), 13, MINT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	y += 10
	_bar(Rect2(x, y, 262, 7), hv.plan_frac(), MINT)
	y += 22
	var need := hv.plan_cost(hv.plan_i) - hv.plan_spent
	var s := "%d ore to go" % int(ceil(need))
	var col := Color(1, 1, 1, 0.55)
	if hv.build_stall != "":
		s = "STALLED — " + hv.build_stall
		col = Color(AMBER, 0.6 + 0.4 * sin(t * 5.0))
	_txt(Vector2(x, y), s, 11, col)
	if hv.plan_i + 1 < Hive.PLAN.size():
		_txt(Vector2(x, y), "next: " + hv.plan_label(Hive.PLAN[hv.plan_i + 1]), 10, Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, 262)


func _draw_messages() -> void:
	var y := size.y * 0.22
	for m in messages:
		var a := clampf(m[2] / m[3] * 3.0, 0.0, 1.0) * clampf((m[3] - m[2]) * 6.0, 0.0, 1.0)
		_txt(Vector2(0, y), m[0], 20, Color(m[1], a), HORIZONTAL_ALIGNMENT_CENTER, size.x, true)
		y += 28


# ---------------------------------------------------------------- edge arrows
func _world_to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p


func _edge_point(sp: Vector2, margin: float) -> Vector2:
	var area := Rect2(Vector2(margin, 100.0 + margin * 0.3), size - Vector2(margin * 2.0, 230.0 + margin * 0.6))
	var c := area.get_center()
	var d := sp - c
	var s := minf((area.size.x * 0.5) / maxf(absf(d.x), 0.001), (area.size.y * 0.5) / maxf(absf(d.y), 0.001))
	return c + d * minf(s, 1.0)


func _arrow(p: Vector2, ang: float, sz: float, col: Color) -> void:
	var tri := PackedVector2Array([p + Vector2(sz, 0).rotated(ang), p + Vector2(-sz * 0.6, -sz * 0.6).rotated(ang), p + Vector2(-sz * 0.6, sz * 0.6).rotated(ang)])
	draw_colored_polygon(tri, col)
	tri.append(tri[0])
	draw_polyline(tri, Color(col, 0.4), 4.0, true)


func _point_at(world: Vector2, label: String, col: Color, sz := 13.0, margin := 48.0) -> void:
	var screen := Rect2(Vector2.ZERO, size).grow(-30)
	var sp := _world_to_screen(world)
	if screen.has_point(sp):
		return
	var ep := _edge_point(sp, margin)
	_arrow(ep, (sp - size * 0.5).angle(), sz, col)
	if label != "":
		_txt(ep + Vector2(-80, -sz - 6), label, 11, col, HORIZONTAL_ALIGNMENT_CENTER, 160)


func _draw_indicators() -> void:
	var g := Game.inst
	var p: Ship = g.player
	var hv: Hive = g.hive
	if size.x < 100.0:
		return
	# where to deliver what you carry
	if not p.dead:
		for k in ["nectar", "ore", "ice"]:
			if p.cargo[k] > 0.5:
				var m: HiveModule = hv.module_for(k)
				_point_at(m.position, m.label, Gfx.res_color(k), 13.0, 56.0)
	# wounded organs
	for m in hv.built_modules():
		if m.hp < m.max_hp * 0.5:
			var col := Color(1, 0.6, 0.3) if m.online() else Color(RED, 0.6 + 0.4 * sin(t * 8.0))
			_point_at(m.position, ("MEND " if m.online() else "DOWN: ") + m.label, col, 12.0, 70.0)
	# the Reaper, wherever it is
	var rp = g.reaper_alive()
	if rp != null:
		_point_at(rp.position, "REAPER", MAG, 18.0, 40.0)
	elif g.reaper_t < 30.0 and g.state == "playing":
		_point_at(g.reaper_src.position, "REAPER STIRS", Color(MAG, 0.5 + 0.5 * sin(t * 6.0)), 16.0, 40.0)
	if g.swarm_t < 12.0 and g.state == "playing" and g.swarm_src != null:
		_point_at(g.swarm_src.position, "SWARM", Color(Gfx.C_SWARM, 0.5 + 0.5 * sin(t * 10.0)), 16.0, 40.0)
	# visible hostiles
	var shown := 0
	for e in g.enemies:
		if shown > 14 or e.kind == "reaper" or not e.visible:
			continue
		shown += 1
		_point_at(e.position, "", Color(e.color, 0.75), 7.0, 30.0)


# ---------------------------------------------------------------- screens
func _draw_title() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.7))
	var y := size.y * 0.17
	_txt(Vector2(0, y), "MELISSAE", 84, AMBER, HORIZONTAL_ALIGNMENT_CENTER, size.x, true)
	_txt(Vector2(0, y + 40), "TEND THE HIVE", 20, Color(MINT, 0.85), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	var tiers := Ship.FORM_NAMES.size()
	var spacing := minf(190.0, (size.x - 80.0) / tiers)
	var x0 := size.x * 0.5 - spacing * (tiers - 1) * 0.5
	var sy := y + 140
	for i in tiers:
		_txt(Vector2(x0 + i * spacing - 80, sy + 92), Ship.FORM_NAMES[i], 13, Color(Gfx.C_PLAYER, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 160)
	var lines := [
		"You are a worker of the hive. You fly toward the mouse — that's all you control.",
		"Hover near blooms, crystals and veins to harvest. Haul NECTAR to the Vault, ORE to the Forge, ICE to the Cistern.",
		"The hive eats nectar every second. If its stores run dry, the Heart withers and the hive dies.",
		"Every field has guardians. Swarms nibble the hive's organs — fly over wounded ones to mend them.",
		"The Reaper steals from the Vault. Kill it before it escapes and it spills its hoard.",
		"The hive grows itself from ore, and its glands reshape your body. Wheel to zoom out.",
	]
	var ly := sy + 140
	for l in lines:
		_txt(Vector2(0, ly), l, 15, Color(1, 1, 1, 0.78), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		ly += 24
	_txt(Vector2(0, ly + 34), "CLICK TO AWAKEN", 30, Color(AMBER, 0.6 + 0.4 * sin(t * 4.0)), HORIZONTAL_ALIGNMENT_CENTER, size.x, true)


func _draw_over() -> void:
	var g := Game.inst
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.0, 0.01, 0.75))
	var y := size.y * 0.28
	_txt(Vector2(0, y), "THE HIVE HAS FALLEN SILENT", 52, RED, HORIZONTAL_ALIGNMENT_CENTER, size.x, true)
	var tsec := int(g.time_played)
	var stats := [
		["Time the hive lived", "%d:%02d" % [tsec / 60, tsec % 60]],
		["Times the hive grew", str(g.hive.grown)],
		["Peak drones", str(g.peak_drones)],
		["You delivered", str(int(g.stats_delivered))],
		["Hostiles slain", str(g.kills)],
		["Reapers slain / escaped", "%d / %d" % [g.reapers_slain, g.reapers_escaped]],
		["Your final form", Ship.FORM_NAMES[g.player.form]],
	]
	var sy := y + 56
	for s in stats:
		_txt(Vector2(size.x * 0.5 - 230, sy), s[0], 19, Color(1, 1, 1, 0.7))
		_txt(Vector2(size.x * 0.5 - 230, sy), s[1], 19, AMBER, HORIZONTAL_ALIGNMENT_RIGHT, 460)
		sy += 28
	_txt(Vector2(0, sy + 36), "CLICK TO SEED A NEW HIVE", 26, Color(MINT, 0.6 + 0.4 * sin(t * 4.0)), HORIZONTAL_ALIGNMENT_CENTER, size.x, true)


## Minimap overlay drawn above the fog: you, drones, raid warnings, seen foes.
class MiniTop extends Node2D:
	var hud

	func _draw() -> void:
		var g := Game.inst
		var h: HUD = hud
		for a in g.allies:
			if a.dead or a.is_player:
				continue
			draw_circle(h.world_to_mini(a.position), 1.6, a.color)
		for e in g.enemies:
			if e.dead or not e.visible:
				continue
			var r := 4.0 if e.kind == "reaper" else 1.8
			draw_circle(h.world_to_mini(e.position), r, Color(e.color, 0.7 + 0.3 * sin(h.t * 8.0)))
		var rp = g.reaper_alive()
		if rp != null:
			var mp := h.world_to_mini(rp.position)
			draw_arc(mp, 6.0 + 2.0 * sin(h.t * 6.0), 0, TAU, 16, Gfx.C_REAPER, 1.5, true)
		var mr: Rect2 = h.minimap_rect()
		if g.swarm_t < 12.0 and g.swarm_src != null:
			draw_circle(h.world_to_mini(g.swarm_src.position), 4.0 + 2.0 * sin(h.t * 8.0), Color(Gfx.C_SWARM, 0.7))
		if rp == null and g.reaper_t < 30.0:
			draw_circle(h.world_to_mini(g.reaper_src.position), 5.0 + 2.0 * sin(h.t * 6.0), Color(Gfx.C_REAPER, 0.7))
		var p: Ship = g.player
		if not p.dead:
			var pp := h.world_to_mini(p.position)
			var tri := PackedVector2Array([pp + Vector2(6, 0).rotated(p.rotation), pp + Vector2(-4, -3.5).rotated(p.rotation), pp + Vector2(-4, 3.5).rotated(p.rotation)])
			draw_colored_polygon(tri, Color.WHITE)
		var vs: Vector2 = h.size / g.camera.zoom
		var k: float = (h.MM - 8.0) / (Game.WORLD_HALF * 2.0)
		var vr := Rect2(h.world_to_mini(g.camera.position - vs * 0.5), vs * k)
		draw_rect(vr.intersection(mr), Color(1, 1, 1, 0.18), false, 1.0)


## Title-screen line-up of the forms you can molt into.
class TitleShips extends Node2D:
	var hud

	func _draw() -> void:
		var sz: Vector2 = hud.size
		var tiers := Ship.FORM_NAMES.size()
		var spacing := minf(190.0, (sz.x - 80.0) / tiers)
		var x0: float = sz.x * 0.5 - spacing * (tiers - 1) * 0.5
		var sy: float = sz.y * 0.17 + 140.0
		var t: float = hud.t
		for i in tiers:
			var pos := Vector2(x0 + i * spacing, sy)
			var rot := -PI * 0.5 + 0.08 * sin(t * 1.3 + i)
			var spec := Gfx.form(i)
			var sc := 1.6
			var roots := Gfx.wing_roots(spec)
			for pi in range(spec.pairs - 1, -1, -1):
				var wname := "pf%d_%s" % [i, "wh" if pi == 1 else "wf"]
				for sd in [-1.0, 1.0]:
					var root: Vector2 = roots[pi]
					var lp := Vector2(root.x, -root.y * sd)
					var ph := sin(t * 16.0 + pi * 0.6 + i)
					var fold := lerpf(0.4, 1.0, absf(ph))
					draw_set_transform(pos + (lp * sc).rotated(rot), rot - sd * 0.2 * ph, Vector2(sc, -sd * fold * sc))
					Gfx.blit(self, wname, Vector2.ZERO, 1.0, Color(1, 1, 1, 0.55 + 0.35 * absf(ph)))
			draw_set_transform(pos, rot, Vector2.ONE * sc)
			Gfx.blit(self, "pf%d" % i, Vector2.ZERO, 1.0, Color.WHITE)
			Gfx.blit(self, "pf%d_v" % i, Vector2.ZERO, 1.0, Color(1, 1, 1, 0.65 + 0.35 * sin(t * 3.0 + i)))
		draw_set_transform(Vector2.ZERO)
