class_name Bio
extends RefCounted
## Shape + shading helpers for the organic look: chitin shells with a soft
## highlight and a lit rim, translucent glowing membranes, and luminous veins.
## Only used at bake time (see Gfx), so none of this costs anything per frame.


static func ellipse(c: Vector2, rx: float, ry: float, rot := 0.0, n := 28) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return out


static func hexagon(c: Vector2, r: float, rot := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 6:
		out.append(c + Vector2.RIGHT.rotated(rot + TAU * i / 6.0) * r)
	return out


static func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Catmull-Rom curve through the control points.
static func smooth(pts: Array, closed := true, sub := 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	if n < 3:
		for p in pts:
			out.append(p)
		return out
	var segs := n if closed else n - 1
	for i in segs:
		var p0: Vector2 = pts[(i - 1 + n) % n] if (closed or i > 0) else pts[0]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		var p3: Vector2 = pts[(i + 2) % n] if (closed or i + 2 < n) else pts[n - 1]
		for k in sub:
			out.append(_cr(p0, p1, p2, p3, float(k) / sub))
	if not closed:
		out.append(pts[n - 1])
	return out


## Mirror a half outline (nose -> tail along the -y side) and smooth it.
static func sym(half: Array, s := 1.0, sub := 5) -> PackedVector2Array:
	return smooth(Array(Neon.mirror(half, s)), true, sub)


static func wobble(c: Vector2, r: float, n: int, amp: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := []
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2.RIGHT.rotated(a) * r * rng.randf_range(1.0 - amp, 1.0 + amp * 0.5))
	return smooth(pts, true, 5)


static func centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v in p:
		c += v
	return c / maxf(p.size(), 1)


static func scale_about(p: PackedVector2Array, c: Vector2, f: float, off := Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in p:
		out.append(c + (v - c) * f + off)
	return out


static func fill(ci: CanvasItem, poly: PackedVector2Array, col: Color) -> void:
	if poly.size() >= 3 and not Geometry2D.triangulate_polygon(poly).is_empty():
		ci.draw_colored_polygon(poly, col)


static func closed(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate()
	if q.size() > 0:
		q.append(q[0])
	return q


static func radius_of(p: PackedVector2Array) -> float:
	var c := centroid(p)
	var r := 0.0
	for v in p:
		r = maxf(r, v.distance_to(c))
	return r


## Chitin shell: dark base, soft highlight toward the upper left, lit rim.
static func chitin(ci: CanvasItem, poly: PackedVector2Array, base: Color, rim: Color, rim_w := 1.3) -> void:
	if poly.size() < 3:
		return
	var c := centroid(poly)
	var r := radius_of(poly)
	fill(ci, poly, base)
	var lit := base.lightened(0.22)
	fill(ci, scale_about(poly, c, 0.74, Vector2(-0.1, -0.16) * r), Color(lit, 0.45))
	fill(ci, scale_about(poly, c, 0.42, Vector2(-0.18, -0.26) * r), Color(base.lightened(0.4), 0.3))
	var cl := closed(poly)
	ci.draw_polyline(cl, Color(rim, 0.18), rim_w * 4.0, true)
	ci.draw_polyline(cl, rim, rim_w, true)


## Translucent glowing membrane (wings, sacs, fins).
static func membrane(ci: CanvasItem, poly: PackedVector2Array, glow: Color, fill_a := 0.16) -> void:
	if poly.size() < 3:
		return
	var c := centroid(poly)
	fill(ci, poly, Color(glow, fill_a))
	fill(ci, scale_about(poly, c, 0.7), Color(glow, fill_a * 0.6))
	var cl := closed(poly)
	ci.draw_polyline(cl, Color(glow, 0.14), 6.0, true)
	ci.draw_polyline(cl, Color(glow, 0.8), 1.2, true)


## Luminous vein / glowing line.
static func vein(ci: CanvasItem, pts: PackedVector2Array, col: Color, w := 1.4, a := 1.0) -> void:
	if pts.size() < 2:
		return
	ci.draw_polyline(pts, Color(col, 0.12 * a), w * 5.0, true)
	ci.draw_polyline(pts, Color(col, 0.3 * a), w * 2.2, true)
	ci.draw_polyline(pts, Color(col, 0.95 * a), w, true)
	ci.draw_polyline(pts, Color(1, 1, 1, 0.45 * a), maxf(w * 0.35, 0.6), true)


## Soft radial glow made of stacked translucent discs.
static func halo(ci: CanvasItem, c: Vector2, r: float, col: Color, strength := 1.0, steps := 10) -> void:
	for k in steps:
		var f := 1.0 - float(k) / steps
		ci.draw_circle(c, r * f, Color(col, 0.035 * strength))


static func spot(ci: CanvasItem, c: Vector2, r: float, col: Color, intensity := 1.0) -> void:
	Neon.dot(ci, c, r, col, intensity)


## Points along an elliptical arc (for segment bands).
static func arc_pts(c: Vector2, rx: float, ry: float, a0: float, a1: float, n := 10) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


## A tapered curved spike/tentacle as a polygon along a centerline.
static func taper(path: PackedVector2Array, w0: float, w1: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n := path.size()
	for i in n:
		var t := float(i) / maxf(n - 1, 1)
		var dir: Vector2
		if i == 0:
			dir = (path[1] - path[0]).normalized()
		elif i == n - 1:
			dir = (path[i] - path[i - 1]).normalized()
		else:
			dir = (path[i + 1] - path[i - 1]).normalized()
		var nrm := dir.orthogonal()
		var w := lerpf(w0, w1, t) * 0.5
		left.append(path[i] + nrm * w)
		right.append(path[i] - nrm * w)
	right.reverse()
	left.append_array(right)
	return left
