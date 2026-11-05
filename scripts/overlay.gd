class_name Overlay
extends Node2D
## World-space UI drawn in one place: harvesting tendrils, cargo rings, the
## mending beam, module labels and health, growth progress on buds, field
## names, enemy health bars, the Reaper's siphon and the missile lock reticle.

var reticle: Sprite2D
var t := 0.0


func _ready() -> void:
	z_index = 22
	reticle = Gfx.sprite("reticle", Gfx.C_PLAYER)
	reticle.visible = false
	add_child(reticle)


func _process(delta: float) -> void:
	t += delta
	var g := Game.inst
	var lt = g.player.lock_target if g.player != null else null
	if lt != null and is_instance_valid(lt) and not lt.dead and lt.visible:
		reticle.visible = true
		reticle.position = lt.position
		reticle.rotation = t * 2.0
		reticle.scale = Vector2.ONE * ((lt.hit_radius + 10.0) / 26.0)
	else:
		reticle.visible = false
	queue_redraw()


func _draw() -> void:
	var g := Game.inst
	if g == null or g.camera == null:
		return
	var font := ThemeDB.fallback_font
	var z: float = g.camera.zoom.x
	var inv := 1.0 / z
	var view := Rect2(g.camera.position - g.get_viewport_rect().size * 0.5 * inv, g.get_viewport_rect().size * inv).grow(200.0)
	var p: Ship = g.player

	# fields
	for f in g.fields:
		if not f.discovered:
			continue
		var top: Vector2 = f.position + Vector2(0, -f.radius - 30.0)
		if view.has_point(top) and (z < 0.75 or p.position.distance_to(f.position) < f.radius + 600.0):
			var fs := int(clampf(15.0 * inv, 13.0, 44.0))
			_label(font, top, f.field_name.to_upper(), fs, Color(f.color, 0.75))

	# hive modules
	for m in g.hive.all_modules():
		if not view.has_point(m.position):
			continue
		var r: float = m.radius()
		if m.level == 0:
			if m.growing:
				var gr: float = r * 0.8 + 16.0
				draw_arc(m.position, gr, -PI * 0.5, -PI * 0.5 + TAU * m.grow_frac, 40, Color(Gfx.C_HIVE, 0.85), 3.0)
				draw_arc(m.position, gr, 0, TAU, 40, Color(Gfx.C_HIVE, 0.15), 3.0)
				_label(font, m.position + Vector2(0, -gr - 12.0), "GROWING: " + m.label, int(clampf(11.0 * inv, 11.0, 30.0)), Color(Gfx.C_HIVE, 0.8))
			continue
		var near: bool = p.position.distance_to(m.position) < 650.0
		var hurt: bool = m.hp < m.max_hp
		if near or hurt or z < 0.6:
			var fs := int(clampf(11.0 * inv, 11.0, 30.0))
			var c := Color(Gfx.HIVE_RIM, 0.85)
			if not m.online():
				c = Color(1, 0.35, 0.3, 0.7 + 0.3 * sin(t * 8.0))
			elif m.hp < m.max_hp * 0.5:
				c = Color(1, 0.65, 0.35)
			_label(font, m.position + Vector2(0, -r - 22.0 * maxf(inv, 1.0)), m.label if m.level <= 1 else "%s %s" % [m.label, Hive._roman(m.level)], fs, c)
		if hurt and m.type != "heart":
			var w := r * 1.4
			var y: float = m.position.y + r + 12.0
			var f: float = m.hp / m.max_hp
			draw_rect(Rect2(m.position.x - w * 0.5, y, w, 6), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(m.position.x - w * 0.5, y, w * f, 6), Color(0.4, 1.0, 0.6).lerp(Color(1, 0.3, 0.3), 1.0 - f))

	# ships
	for s in g.allies:
		if s.dead or not view.has_point(s.position):
			continue
		var pos: Vector2 = s.position
		var hr: float = s.hit_radius
		var mt = s.mining_target
		if mt != null and is_instance_valid(mt):
			_tendril(s, mt)
		var tot: float = s.cargo_total()
		if tot > 0.05:
			var capv: float = s.cargo_cap()
			var a0 := -PI * 0.5
			for k in ["nectar", "ore", "ice"]:
				var f: float = s.cargo[k] / capv
				if f <= 0.0:
					continue
				var a1 := a0 + TAU * f
				var col := Gfx.res_color(k)
				draw_arc(pos, hr + 9.0, a0, a1, 16, Color(col, 0.15), 7.0)
				draw_arc(pos, hr + 9.0, a0, a1, 16, Color(col, 0.9), 2.4)
				a0 = a1
		if s.depositing != "":
			var m: HiveModule = g.hive.module_for(s.depositing)
			draw_line(pos, m.position, Color(Gfx.res_color(s.depositing), 0.22), 2.0)
		if s.hit_flash > 0.0:
			draw_arc(pos, hr + 7.0, 0.0, TAU, 24, Color(s.color, s.hit_flash * 2.5), 2.0)
	if p != null and not p.dead and p.repairing != null and is_instance_valid(p.repairing):
		var m: HiveModule = p.repairing
		var pts := PackedVector2Array()
		for i in 9:
			var f := i / 8.0
			pts.append(p.position.lerp(m.position, f) + (m.position - p.position).orthogonal().normalized() * sin(f * PI * 3.0 + t * 12.0) * 8.0 * sin(f * PI))
		draw_polyline(pts, Color(Gfx.C_HIVE, 0.2), 7.0)
		draw_polyline(pts, Color(Gfx.C_HIVE, 0.9), 2.0)

	# enemies
	for e in g.enemies:
		if e.dead or not e.visible or not view.has_point(e.position):
			continue
		if e.kind == "reaper":
			var w := 160.0
			var y: float = e.position.y - 90.0
			draw_rect(Rect2(e.position.x - w * 0.5, y, w, 6), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(e.position.x - w * 0.5, y, w * e.hp / e.max_hp, 6), Gfx.C_REAPER)
			if e.state == "siphon":
				var vault: HiveModule = g.hive.modules.vault
				var pts := PackedVector2Array()
				for i in 11:
					var f := i / 10.0
					pts.append(e.position.lerp(vault.position, f) + (vault.position - e.position).orthogonal().normalized() * sin(f * 9.0 - t * 10.0) * 10.0 * sin(f * PI))
				draw_polyline(pts, Color(Gfx.C_REAPER, 0.18), 12.0)
				draw_polyline(pts, Color(Gfx.C_REAPER, 0.9), 3.0)
			continue
		if e.hp >= e.max_hp:
			continue
		var w: float = e.hit_radius * 2.0
		var bp: Vector2 = e.position + Vector2(-w * 0.5, -e.hit_radius - 12.0)
		draw_rect(Rect2(bp, Vector2(w, 3)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bp, Vector2(w * e.hp / e.max_hp, 3)), Color(e.color, 0.9))


func _label(font: Font, at: Vector2, txt: String, fs: int, col: Color) -> void:
	var w := 600.0
	draw_string_outline(font, at - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs, maxi(4, fs / 3), Color(0, 0, 0, 0.7 * col.a))
	draw_string(font, at - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)


## Organic harvesting tendril from the ship's head to the growth.
func _tendril(s, a) -> void:
	var start: Vector2 = s.to_global(Vector2(12.0, 0) * s._spec.s)
	var dir: Vector2 = (start - a.position).normalized()
	var end: Vector2 = a.position + dir * a.cur_radius() * 0.7
	var c: Color = a.color
	var pts := PackedVector2Array()
	var perp := (end - start).orthogonal().normalized()
	for i in 9:
		var f := i / 8.0
		pts.append(start.lerp(end, f) + perp * sin(f * PI * 2.0 + t * 14.0 + s.orbit_phase) * 5.0 * sin(f * PI))
	draw_polyline(pts, Color(c, 0.16), 7.0)
	draw_polyline(pts, Color(c.lerp(Color.WHITE, 0.4), 0.9), 1.8)
	draw_circle(end, 8.0, Color(c, 0.2))
	draw_circle(end, 3.0, Color(1, 1, 1, 0.85))
