class_name Neon
extends RefCounted
## Static helpers for the glowing vector look. Every "neon" stroke is drawn as
## a few stacked passes: a wide faint halo, a medium glow, the core line and a
## thin white-hot center.

static func outline(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float = 2.0, glow: float = 1.0, closed: bool = true) -> void:
	if pts.size() < 2:
		return
	var p := pts
	if closed:
		p = pts.duplicate()
		p.append(pts[0])
	ci.draw_polyline(p, Color(col, 0.06 * glow * col.a), w * 7.0, true)
	ci.draw_polyline(p, Color(col, 0.17 * glow * col.a), w * 3.2, true)
	ci.draw_polyline(p, col, w, true)
	ci.draw_polyline(p, Color(1, 1, 1, 0.5 * glow * col.a), maxf(w * 0.35, 0.8), true)


static func line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float = 2.0, glow: float = 1.0) -> void:
	ci.draw_line(a, b, Color(col, 0.07 * glow * col.a), w * 6.0, true)
	ci.draw_line(a, b, Color(col, 0.2 * glow * col.a), w * 2.6, true)
	ci.draw_line(a, b, col, w, true)


static func ring(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float = 2.0, glow: float = 1.0, segs: int = 48) -> void:
	ci.draw_arc(c, r, 0.0, TAU, segs, Color(col, 0.06 * glow * col.a), w * 7.0, true)
	ci.draw_arc(c, r, 0.0, TAU, segs, Color(col, 0.17 * glow * col.a), w * 3.0, true)
	ci.draw_arc(c, r, 0.0, TAU, segs, col, w, true)


static func arc(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, col: Color, w: float = 2.0, glow: float = 1.0, segs: int = 12) -> void:
	ci.draw_arc(c, r, a0, a1, segs, Color(col, 0.08 * glow * col.a), w * 5.0, true)
	ci.draw_arc(c, r, a0, a1, segs, Color(col, 0.22 * glow * col.a), w * 2.4, true)
	ci.draw_arc(c, r, a0, a1, segs, col, w, true)


static func dot(ci: CanvasItem, c: Vector2, r: float, col: Color, intensity: float = 1.0) -> void:
	ci.draw_circle(c, r * 3.2, Color(col, 0.05 * intensity))
	ci.draw_circle(c, r * 1.9, Color(col, 0.16 * intensity))
	ci.draw_circle(c, r, Color(col, 0.9 * intensity))
	ci.draw_circle(c, r * 0.5, Color(1, 1, 1, 0.85 * intensity))


## Build a closed hull from its top half. The half runs nose -> tail along the
## port (negative y) side; both endpoints sit on the center line.
static func mirror(half: Array, s: float = 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in half:
		out.append(p * s)
	for i in range(half.size() - 2, 0, -1):
		var p: Vector2 = half[i]
		out.append(Vector2(p.x, -p.y) * s)
	return out


static func scaled(pts: Array, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p * s)
	return out


static func rock(rng: RandomNumberGenerator, r: float, n: int, jag: float = 0.25) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n)
		out.append(Vector2.RIGHT.rotated(a) * r * rng.randf_range(1.0 - jag, 1.0 + jag * 0.4))
	return out
