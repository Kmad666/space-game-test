class_name HUD
extends Control
## All 2D interface drawing: status panels, minimap, upgrade bar, off-screen
## indicators and the title / pause / game-over overlays.

const CYAN := Color(0.4, 0.92, 1.0)
const GOLD := Color(1.0, 0.82, 0.35)
const RED := Color(1.0, 0.32, 0.38)
const VIOLET := Color(0.8, 0.5, 1.0)
const PANEL := Color(0.02, 0.05, 0.1, 0.72)

var messages := []  # [text, color, life, max]
var t := 0.0
var hover := -1
var btn_flash := {}
var font: Font
var _title_ships: TitleShips
var _redraw_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	_title_ships = TitleShips.new()
	_title_ships.hud = self
	_title_ships.material = Gfx.premult
	add_child(_title_ships)


func push_message(txt: String, col: Color, dur: float = 2.5) -> void:
	messages.append([txt, col, dur, dur])
	if messages.size() > 4:
		messages.pop_front()


func flash_button(i: int) -> void:
	btn_flash[i] = 0.4


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
	for k in btn_flash.keys():
		btn_flash[k] -= delta
		if btn_flash[k] <= 0.0:
			btn_flash.erase(k)
	var g := Game.inst
	hover = -1
	if g.state == "playing":
		var mp := get_local_mouse_position()
		var rects := _button_rects()
		for j in rects.size():
			if rects[j].has_point(mp):
				hover = j
	_title_ships.visible = g.state == "title"
	if g.state == "title":
		_title_ships.queue_redraw()
	# 30 Hz is plenty for the interface
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 1.0 / 30.0
		queue_redraw()


func _input(event: InputEvent) -> void:
	var g := Game.inst
	if g.state != "playing":
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var rects := _button_rects()
		for j in rects.size():
			if rects[j].has_point(event.position):
				g.buy_upgrade(j)
				get_viewport().set_input_as_handled()
				return


# ---------------------------------------------------------------- helpers
func _txt(pos: Vector2, s: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0, glow := false) -> void:
	if glow:
		draw_string_outline(font, pos, s, align, w, sz, 10, Color(col, 0.12 * col.a))
		draw_string_outline(font, pos, s, align, w, sz, 4, Color(col, 0.25 * col.a))
	else:
		draw_string_outline(font, pos, s, align, w, sz, 4, Color(0, 0, 0, 0.55 * col.a))
	draw_string(font, pos, s, align, w, sz, col)


func _bar(r: Rect2, f: float, col: Color, bg := Color(1, 1, 1, 0.07)) -> void:
	draw_rect(r, bg)
	var fr := Rect2(r.position, Vector2(r.size.x * clampf(f, 0.0, 1.0), r.size.y))
	draw_rect(fr.grow(2.0), Color(col, 0.12))
	draw_rect(fr, col)
	draw_rect(Rect2(fr.position, Vector2(fr.size.x, 1.0)), Color(1, 1, 1, 0.35))
	draw_rect(r, Color(col, 0.35), false, 1.0)


func _panel(r: Rect2, accent := CYAN) -> void:
	draw_rect(r, PANEL)
	draw_rect(r, Color(accent, 0.25), false, 1.0)
	var c := 10.0
	for corner in [[r.position, Vector2(1, 0), Vector2(0, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1)],
			[Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1)], [r.end, Vector2(-1, 0), Vector2(0, -1)]]:
		draw_line(corner[0], corner[0] + corner[1] * c, Color(accent, 0.9), 2.0)
		draw_line(corner[0], corner[0] + corner[2] * c, Color(accent, 0.9), 2.0)


func _diamond(c: Vector2, s: float, col: Color) -> void:
	var p := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.75, 0), c + Vector2(0, s), c + Vector2(-s * 0.75, 0)])
	draw_colored_polygon(p, col)


func _button_rects() -> Array:
	var vs := size
	if vs.x < 300.0 or vs.y < 200.0:
		return []
	var n := Game.UPGRADES.size()
	var gap := 8.0
	var bw := minf(150.0, (vs.x - 32.0 - gap * (n - 1)) / n)
	var bh := 64.0
	var total := bw * n + gap * (n - 1)
	var x0 := (vs.x - total) * 0.5
	var y := vs.y - bh - 14.0
	var out := []
	for i in n:
		out.append(Rect2(x0 + i * (bw + gap), y, bw, bh))
	return out


func _world_to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p


# ---------------------------------------------------------------- draw
func _draw() -> void:
	var g := Game.inst
	if g == null or g.player == null:
		return
	if g.state == "title":
		_draw_title()
		return
	_draw_indicators()
	_draw_status()
	_draw_station_panel()
	_draw_minimap()
	_draw_upgrades()
	_draw_messages()
	if g.player.dead and g.state == "playing":
		_txt(Vector2(0, size.y * 0.42), "SHIP DESTROYED", 34, RED, HORIZONTAL_ALIGNMENT_CENTER, size.x, true)
		_txt(Vector2(0, size.y * 0.42 + 36), "Relaunching from Aegis Station in %d…" % int(ceil(g.player.respawn_t)), 18, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if g.state == "paused":
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		_txt(Vector2(0, size.y * 0.45), "PAUSED", 56, CYAN, HORIZONTAL_ALIGNMENT_CENTER, size.x, true)
		_txt(Vector2(0, size.y * 0.45 + 44), "click or press P to resume", 18, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if g.state == "over":
		_draw_over()
	var q := "LOW-SPEC" if g.low_quality else "HIGH"
	_txt(Vector2(size.x - 194, 212), "%d FPS · Q quality: %s" % [int(round(g.fps_now)), q], 11, Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, 180)


func _draw_status() -> void:
	var g := Game.inst
	var p: Ship = g.player
	var r := Rect2(14, 14, 300, 118)
	_panel(r)
	var x := r.position.x + 14
	var y := r.position.y + 26
	_txt(Vector2(x, y), "%s-CLASS" % Ship.TIER_NAMES[p.tier], 18, CYAN, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var tl := p.total_levels()
	if p.tier < Ship.TIER_THRESH.size() - 1:
		var nxt: int = Ship.TIER_THRESH[p.tier + 1]
		_txt(Vector2(x, y - 1), "next %s: %d/%d" % [Ship.TIER_NAMES[p.tier + 1], tl, nxt], 11, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 28)
	else:
		_txt(Vector2(x, y - 1), "flagship", 11, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 28)
	y += 14
	var hf := p.hp / p.max_hp() if not p.dead else 0.0
	_txt(Vector2(x, y + 11), "HULL", 11, Color(1, 1, 1, 0.6))
	_bar(Rect2(x + 52, y + 2, 220, 9), hf, CYAN.lerp(RED, clampf(1.0 - hf * 1.6, 0.0, 1.0)))
	y += 18
	_txt(Vector2(x, y + 11), "CARGO", 11, Color(1, 1, 1, 0.6))
	var cf := p.cargo / p.cargo_cap()
	var full := cf > 0.99
	_bar(Rect2(x + 52, y + 2, 220, 9), cf, VIOLET if not full else VIOLET.lerp(Color.WHITE, 0.3 + 0.3 * sin(t * 8.0)))
	_txt(Vector2(x + 52, y + 11), "%d / %d" % [int(p.cargo), int(p.cargo_cap())], 10, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 216)
	y += 34
	_diamond(Vector2(x + 7, y - 7), 8, GOLD)
	_txt(Vector2(x + 22, y), "%d CR" % int(g.credits), 22, GOLD, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	if full:
		_txt(Vector2(x + 140, y - 2), "HOLD FULL — RETURN!", 12, Color(VIOLET, 0.6 + 0.4 * sin(t * 6.0)))


func _draw_station_panel() -> void:
	var g := Game.inst
	var st: Station = g.station
	var w := 380.0
	var r := Rect2((size.x - w) * 0.5, 14, w, 92)
	var accent := CYAN if g.station_hit_t <= 0.0 else CYAN.lerp(RED, 0.5 + 0.5 * sin(t * 18.0))
	_panel(r, accent)
	var x := r.position.x + 14
	var y := r.position.y + 24
	_txt(Vector2(x, y), "AEGIS STATION", 16, CYAN, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_txt(Vector2(x, y), "LV %d" % st.level, 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, w - 28, true)
	y += 10
	var growth := 1.0 if st.level >= Station.MAX_LEVEL else st.xp / st.need()
	_bar(Rect2(x, y, w - 28, 7), growth, VIOLET)
	y += 11
	_bar(Rect2(x, y, w - 28, 7), st.hp / st.max_hp, Color(0.45, 1.0, 0.7).lerp(RED, clampf(1.0 - st.hp / st.max_hp * 1.4, 0.0, 1.0)))
	y += 26
	var alive := g.enemies.size()
	if alive > 0:
		_txt(Vector2(r.position.x, y), "WAVE %d — %d HOSTILE%s" % [g.wave, alive, "" if alive == 1 else "S"], 15, Color(RED, 0.75 + 0.25 * sin(t * 6.0)), HORIZONTAL_ALIGNMENT_CENTER, w, true)
	else:
		var s := int(ceil(g.wave_timer))
		var col := Color(1, 1, 1, 0.75) if s > 10 else Color(1, 0.6, 0.4, 0.75 + 0.25 * sin(t * 10.0))
		_txt(Vector2(r.position.x, y), "NEXT RAID IN %d:%02d" % [s / 60, s % 60], 15, col, HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_minimap() -> void:
	var g := Game.inst
	var ms := 180.0
	var r := Rect2(size.x - ms - 14, 14, ms, ms)
	_panel(r)
	var W := Game.WORLD_HALF
	var center := r.get_center()
	var k := (ms - 12.0) / (W * 2.0)
	for a in g.asteroids:
		draw_rect(Rect2(center + a.position * k - Vector2(1.5, 1.5), Vector2(3, 3)), Color(a.color, 0.55))
	var st: Station = g.station
	draw_circle(center + st.position * k, 5.0, Color(CYAN, 0.25))
	draw_arc(center + st.position * k, 5.0, 0, TAU, 16, CYAN, 1.5, true)
	for e in g.enemies:
		var p: Vector2 = center + e.position * k
		draw_circle(p, 3.2 if e.kind == "bomber" else 2.2, Color(e.color, 0.65 + 0.35 * sin(t * 8.0)))
	for a in g.allies:
		if a.dead or a.is_player:
			continue
		draw_circle(center + a.position * k, 2.2, a.color)
	var p: Ship = g.player
	if not p.dead:
		var pp := center + p.position * k
		var tri := PackedVector2Array([pp + Vector2(6, 0).rotated(p.rotation), pp + Vector2(-4, -3.5).rotated(p.rotation), pp + Vector2(-4, 3.5).rotated(p.rotation)])
		draw_colored_polygon(tri, Color.WHITE)
	var vs := size / g.camera.zoom
	var vr := Rect2(center + (g.camera.position - vs * 0.5) * k, vs * k)
	draw_rect(vr.intersection(r), Color(1, 1, 1, 0.15), false, 1.0)
	if g.enemies.is_empty() and g.wave_timer < 12.0:
		var rp: Vector2 = center + g.raid_dir * (ms * 0.5 - 8.0)
		draw_circle(rp, 5.0 + 2.0 * sin(t * 8.0), Color(RED, 0.5))


func _draw_upgrades() -> void:
	var g := Game.inst
	var rects := _button_rects()
	for i in rects.size():
		var r: Rect2 = rects[i]
		var u: Dictionary = Game.UPGRADES[i]
		var lvl: int = g.player.levels[u.key]
		var maxed := lvl >= Game.UPGRADE_MAX
		var cost := g.upgrade_cost(u.key) if not maxed else 0
		var afford := not maxed and g.credits >= cost
		var accent := CYAN if afford else Color(0.5, 0.6, 0.7)
		if maxed:
			accent = GOLD
		if btn_flash.has(i):
			accent = RED
		var bg := PANEL
		if hover == i:
			bg = Color(0.06, 0.14, 0.22, 0.85)
		draw_rect(r, bg)
		if afford:
			draw_rect(r.grow(2), Color(CYAN, 0.08 + 0.06 * sin(t * 4.0)), false, 4.0)
		draw_rect(r, Color(accent, 0.55 if afford or maxed else 0.25), false, 1.5)
		var x := r.position.x + 8
		var small := r.size.x < 130.0
		_txt(Vector2(x, r.position.y + 17), "%d" % (i + 1), 12, Color(accent, 0.8))
		_txt(Vector2(x + 14, r.position.y + 17), u.name, 11 if small else 13, Color(1, 1, 1, 0.92 if afford or maxed else 0.55))
		var pw := (r.size.x - 16.0 - 7.0 * 2.0) / 8.0
		for k in Game.UPGRADE_MAX:
			var pr := Rect2(x + k * (pw + 2.0), r.position.y + 25, pw, 5)
			draw_rect(pr, Color(accent, 0.9) if k < lvl else Color(1, 1, 1, 0.1))
		if maxed:
			_txt(Vector2(x, r.position.y + 53), "MAXED", 13, GOLD)
		else:
			_diamond(Vector2(x + 5, r.position.y + 48), 5, GOLD if afford else Color(GOLD, 0.4))
			_txt(Vector2(x + 14, r.position.y + 53), "%d" % cost, 14, GOLD if afford else Color(GOLD, 0.45))
			if not small:
				_txt(Vector2(x, r.position.y + 52), u.desc, 10, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 16)


func _draw_messages() -> void:
	var y := size.y * 0.24
	for m in messages:
		var a := clampf(m[2] / m[3] * 3.0, 0.0, 1.0) * clampf((m[3] - m[2]) * 6.0, 0.0, 1.0)
		_txt(Vector2(0, y), m[0], 22, Color(m[1], a), HORIZONTAL_ALIGNMENT_CENTER, size.x, true)
		y += 30


func _edge_point(sp: Vector2, margin: float) -> Vector2:
	# keep arrows inside the area not covered by the HUD panels
	var area := Rect2(Vector2(margin, 150.0 + margin * 0.3), size - Vector2(margin * 2.0, 250.0 + margin * 0.6))
	var c := area.get_center()
	var d := sp - c
	var s := minf((area.size.x * 0.5) / maxf(absf(d.x), 0.001), (area.size.y * 0.5) / maxf(absf(d.y), 0.001))
	return c + d * minf(s, 1.0)


func _arrow(p: Vector2, ang: float, sz: float, col: Color) -> void:
	var tri := PackedVector2Array([p + Vector2(sz, 0).rotated(ang), p + Vector2(-sz * 0.6, -sz * 0.6).rotated(ang), p + Vector2(-sz * 0.6, sz * 0.6).rotated(ang)])
	draw_colored_polygon(tri, col)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(col, 0.4), 4.0, true)


func _draw_indicators() -> void:
	var g := Game.inst
	if size.x < 100.0 or size.y < 100.0:
		return
	var screen := Rect2(Vector2.ZERO, size).grow(-20)
	var c := size * 0.5
	# station
	var sp := _world_to_screen(g.station.position)
	if not screen.has_point(sp):
		var ep := _edge_point(sp, 46.0)
		var ang := (sp - c).angle()
		_arrow(ep, ang, 14.0, Color(CYAN, 0.9))
		var dist := g.player.position.distance_to(g.station.position)
		_txt(ep - Vector2(60, 18), "AEGIS %.1fk" % (dist / 1000.0), 12, Color(CYAN, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 120)
	# enemies
	var shown := 0
	for e in g.enemies:
		if shown > 14:
			break
		var p := _world_to_screen(e.position)
		if screen.has_point(p):
			continue
		shown += 1
		var ep := _edge_point(p, 30.0)
		_arrow(ep, (p - c).angle(), 8.0 if e.kind != "bomber" else 11.0, Color(e.color, 0.8))
	# incoming raid
	if g.enemies.is_empty() and g.wave_timer < 10.0 and g.state == "playing":
		var wp: Vector2 = g.station.position + g.raid_dir * Game.WORLD_HALF
		var p2 := _world_to_screen(wp)
		var ep := _edge_point(p2, 70.0)
		var pulse := 0.5 + 0.5 * sin(t * 10.0)
		_arrow(ep, (p2 - c).angle(), 20.0 + 4.0 * pulse, Color(RED, 0.6 + 0.4 * pulse))
		_txt(ep + Vector2(-80, 34), "RAID INBOUND", 13, Color(RED, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 160)


func _draw_title() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.01, 0.03, 0.72))
	var cx := size.x * 0.5
	var y := size.y * 0.2
	_txt(Vector2(0, y), "AEGIS RUN", 84, CYAN, HORIZONTAL_ALIGNMENT_CENTER, size.x, true)
	_txt(Vector2(0, y + 40), "MINE  ·  HAUL  ·  DEFEND", 20, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	# ship line-up (drawn by the TitleShips child from the sprite atlas)
	var tiers := Ship.TIER_NAMES.size()
	var spacing := minf(190.0, (size.x - 80.0) / tiers)
	var x0 := cx - spacing * (tiers - 1) * 0.5
	var sy := y + 140
	for i in tiers:
		var p := Vector2(x0 + i * spacing, sy)
		_txt(Vector2(p.x - 80, sy + 96), Ship.TIER_NAMES[i], 14, Color(CYAN, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 160)
	var lines := [
		"Your ship follows the mouse. Fly near crystal asteroids to mine ore (gold ones are worth 3x).",
		"Haul ore back into the ring around Aegis Station — the station grows with every delivery.",
		"Raiders and rogue meteors will attack. Your missiles lock on and fire automatically.",
		"Escort bots fight and mine beside you. Spend credits on upgrades to grow your ship.",
		"Upgrades: click the bar or press 1-7   ·   SPACE brake   ·   P pause   ·   F fullscreen   ·   Q quality",
	]
	var ly := sy + 150
	for l in lines:
		_txt(Vector2(0, ly), l, 16, Color(1, 1, 1, 0.78), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		ly += 26
	var pulse := 0.6 + 0.4 * sin(t * 4.0)
	_txt(Vector2(0, ly + 34), "CLICK TO LAUNCH", 30, Color(GOLD, pulse), HORIZONTAL_ALIGNMENT_CENTER, size.x, true)


func _draw_over() -> void:
	var g := Game.inst
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.0, 0.01, 0.7))
	var y := size.y * 0.3
	_txt(Vector2(0, y), "AEGIS STATION LOST", 60, RED, HORIZONTAL_ALIGNMENT_CENTER, size.x, true)
	var tsec := int(g.time_played)
	var stats := [
		["Waves survived", str(maxi(g.wave - 1, 0))],
		["Station level", str(g.station.level)],
		["Ore delivered", str(int(g.ore_delivered))],
		["Hostiles destroyed", str(g.kills)],
		["Ship class", Ship.TIER_NAMES[g.player.tier]],
		["Time", "%d:%02d" % [tsec / 60, tsec % 60]],
	]
	var sy := y + 60
	for s in stats:
		_txt(Vector2(size.x * 0.5 - 220, sy), s[0], 20, Color(1, 1, 1, 0.7))
		_txt(Vector2(size.x * 0.5 - 220, sy), s[1], 20, CYAN, HORIZONTAL_ALIGNMENT_RIGHT, 440)
		sy += 30
	_txt(Vector2(0, sy + 40), "CLICK TO RELAUNCH", 28, Color(GOLD, 0.6 + 0.4 * sin(t * 4.0)), HORIZONTAL_ALIGNMENT_CENTER, size.x, true)


## Title-screen hull line-up, drawn from the sprite atlas (premultiplied material).
class TitleShips extends Node2D:
	var hud

	func _draw() -> void:
		var sz: Vector2 = hud.size
		var tiers := Ship.TIER_NAMES.size()
		var spacing := minf(190.0, (sz.x - 80.0) / tiers)
		var x0: float = sz.x * 0.5 - spacing * (tiers - 1) * 0.5
		var sy: float = sz.y * 0.2 + 140.0
		for i in tiers:
			Ship.blit_ship(self, i, Color(0.3, 0.92, 1.0), hud.t, 0.6 + 0.4 * sin(hud.t * 2.0 + i), Vector2(x0 + i * spacing, sy), -PI * 0.5 + 0.08 * sin(hud.t * 1.3 + i), 1.0)
