class_name FX
extends Node2D
## Lightweight particle / effect system drawn in one node.

const MAX_PARTS := 1400

# particle: [pos, vel, life, max_life, color, size, drag, target]
var parts := []
# ring: [pos, max_r, life, max_life, color, width]
var rings := []
# text: [pos, text, color, life, max_life, size]
var texts := []
# beam: [a, b, color, life, max_life, width]
var beams := []


var _dots: FXDots
var _sp := PackedVector2Array()
var _sc_glow := PackedColorArray()
var _sc_core := PackedColorArray()


func _ready() -> void:
	z_index = 8
	_dots = FXDots.new()
	_dots.fx = self
	_dots.material = Gfx.premult
	add_child(_dots)


func spark(pos: Vector2, vel: Vector2, color: Color, size: float = 2.0, life: float = 0.5, drag: float = 2.0) -> void:
	if parts.size() >= (MAX_PARTS / 3 if Game.inst.low_quality else MAX_PARTS):
		return
	parts.append([pos, vel, life, life, color, size, drag, null])


func burst(pos: Vector2, color: Color, count: int, speed: float, size: float = 2.0, life: float = 0.6) -> void:
	if Game.inst.low_quality:
		count = maxi(1, count / 2)
	for i in count:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * speed * randf_range(0.25, 1.0)
		spark(pos, v, color, size * randf_range(0.6, 1.3), life * randf_range(0.6, 1.2), 2.5)


func homing(pos: Vector2, target: Node2D, color: Color, size: float = 2.0) -> void:
	if parts.size() >= MAX_PARTS:
		return
	var v := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(20, 60)
	parts.append([pos, v, 1.5, 1.5, color, size, 0.0, target])


func ring(pos: Vector2, color: Color, max_r: float, life: float = 0.5, width: float = 2.0) -> void:
	rings.append([pos, max_r, life, life, color, width])


func text(pos: Vector2, txt: String, color: Color, size: int = 16) -> void:
	texts.append([pos, txt, color, 1.4, 1.4, size])


func beam(a: Vector2, b: Vector2, color: Color, life: float = 0.12, width: float = 2.0) -> void:
	beams.append([a, b, color, life, life, width])


func explosion(pos: Vector2, color: Color, scale: float = 1.0) -> void:
	burst(pos, color, int(22 * scale), 230.0 * scale, 2.6, 0.8)
	burst(pos, Color(1, 0.85, 0.5), int(12 * scale), 150.0 * scale, 2.2, 0.5)
	burst(pos, Color(1, 1, 1), int(6 * scale), 90.0 * scale, 3.0, 0.25)
	ring(pos, color, 50.0 * scale, 0.45, 3.0)
	ring(pos, Color(1, 0.9, 0.6), 28.0 * scale, 0.3, 2.0)
	var g := Game.inst
	if g.player != null and pos.distance_to(g.camera.position) < 700.0:
		g.shake = maxf(g.shake, 3.0 * scale)


func _process(delta: float) -> void:
	var i := 0
	while i < parts.size():
		var p: Array = parts[i]
		p[2] -= delta
		var tgt = p[7]
		if tgt != null:
			if not is_instance_valid(tgt):
				p[2] = 0.0
			else:
				var to: Vector2 = tgt.position - p[0]
				var d := to.length()
				p[1] = p[1].lerp(to / maxf(d, 1.0) * (220.0 + 380.0 * (1.0 - p[2] / p[3])), 1.0 - exp(-7.0 * delta))
				if d < 12.0:
					p[2] = 0.0
		else:
			p[1] = p[1] * exp(-p[6] * delta)
		p[0] += p[1] * delta
		if p[2] <= 0.0:
			parts[i] = parts[parts.size() - 1]
			parts.pop_back()
		else:
			i += 1
	for pair in [[rings, 2], [texts, 3], [beams, 3]]:
		var arr: Array = pair[0]
		var li: int = pair[1]
		var j := 0
		while j < arr.size():
			arr[j][li] -= delta
			if arr[j][li] <= 0.0:
				arr.remove_at(j)
			else:
				j += 1
	for tx in texts:
		tx[0] += Vector2(0, -28.0 * delta)
	queue_redraw()
	_dots.queue_redraw()


func _draw() -> void:
	# fast-moving particles: two batched multiline commands
	_sp.clear()
	_sc_glow.clear()
	_sc_core.clear()
	for p in parts:
		var v: Vector2 = p[1]
		if v.length_squared() <= 3600.0:
			continue
		var a: float = p[2] / p[3]
		var c: Color = p[4]
		_sp.append(p[0] - v * 0.035)
		_sp.append(p[0])
		_sc_glow.append(Color(c, a * 0.25))
		_sc_core.append(Color(c.lerp(Color.WHITE, 0.3), a))
	if _sp.size() > 0:
		draw_multiline_colors(_sp, _sc_glow, 5.0)
		draw_multiline_colors(_sp, _sc_core, 1.8)
	for r in rings:
		var f: float = 1.0 - r[2] / r[3]
		var rad: float = r[1] * (0.2 + 0.8 * sqrt(f))
		var c: Color = r[4]
		draw_arc(r[0], rad, 0, TAU, 32, Color(c, (1.0 - f) * 0.25), r[5] * 3.5)
		draw_arc(r[0], rad, 0, TAU, 32, Color(c, 1.0 - f), r[5])
	for b in beams:
		var a: float = b[3] / b[4]
		var c: Color = b[2]
		draw_line(b[0], b[1], Color(c, a * 0.18), b[5] * 5.0)
		draw_line(b[0], b[1], Color(c.lerp(Color.WHITE, 0.4), a), b[5])
	var font := ThemeDB.fallback_font
	for tx in texts:
		var a: float = clampf(tx[3] / tx[4] * 1.6, 0.0, 1.0)
		var c: Color = tx[2]
		draw_string_outline(font, tx[0] - Vector2(80, 0), tx[1], HORIZONTAL_ALIGNMENT_CENTER, 160, tx[5], 6, Color(0, 0, 0, a * 0.7))
		draw_string(font, tx[0] - Vector2(80, 0), tx[1], HORIZONTAL_ALIGNMENT_CENTER, 160, tx[5], Color(c, a))


## Slow particles drawn as glow sprites from the atlas — all one texture, so they batch.
class FXDots extends Node2D:
	var fx

	func _draw() -> void:
		for p in fx.parts:
			var v: Vector2 = p[1]
			if v.length_squared() > 3600.0:
				continue
			var a: float = p[2] / p[3]
			var c: Color = p[4]
			Gfx.blit(self, "dot", p[0], p[5] * 0.22, Color(c.lerp(Color.WHITE, 0.2), a))
