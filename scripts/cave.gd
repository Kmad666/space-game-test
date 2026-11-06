class_name Cave
extends Node2D
## The burrow network. The whole world is solid rock carved into chambers
## (circles) linked by winding tunnels (chains of capsules). Provides:
##   - collision: inside() / constrain() keep things in open space, sliding on walls
##   - navigation: a waypoint graph through the tunnels with cached next-hop tables
##   - drawing: rock, glowing wall rims and fungus, painted once (static)

const BUCKET := 400.0

var chambers: Array = []  # {pos, r, kind, name}
var shapes: Array = []  # [a: Vector2, b: Vector2, r: float]  (circle when a == b)
var tunnels: Array = []  # PackedVector2Array centerlines + radius: [pts, r]
var buckets := {}
var wp: PackedVector2Array = PackedVector2Array()
var wp_adj: Array = []  # [[neighbor, dist], ...]
var _toward := {}  # dest index -> PackedInt32Array next hop
var rng := RandomNumberGenerator.new()


# ---------------------------------------------------------------- generation
func generate(seed_v: int, half: float) -> void:
	rng.seed = seed_v
	var lim := half - 260.0
	chambers.append({"pos": Vector2.ZERO, "r": 640.0, "kind": "hive"})
	var a0 := rng.randf() * TAU
	for i in 3:
		var a := a0 + TAU * i / 3.0 + rng.randf_range(-0.2, 0.2)
		chambers.append({"pos": Vector2.RIGHT.rotated(a) * rng.randf_range(1750.0, 2000.0), "r": 430.0, "kind": "field1", "slot": i})
	for i in 3:
		var a := a0 + TAU * i / 3.0 + PI / 3.0 + rng.randf_range(-0.15, 0.15)
		chambers.append({"pos": Vector2.RIGHT.rotated(a) * rng.randf_range(2900.0, 3150.0), "r": 520.0, "kind": "field2", "slot": i})
	for i in 3:
		var a := a0 + TAU * i / 3.0 + rng.randf_range(-0.25, 0.25)
		var p := Vector2.RIGHT.rotated(a) * rng.randf_range(3350.0, 3550.0)
		chambers.append({"pos": p.clamp(Vector2(-lim, -lim), Vector2(lim, lim)), "r": 470.0, "kind": "nest", "slot": i})
	# junction caverns to make the network feel interconnected
	var tries := 0
	while chambers.size() < 26 and tries < 600:
		tries += 1
		var p := Vector2(rng.randf_range(-lim, lim), rng.randf_range(-lim, lim))
		if p.length() < 950.0:
			continue
		var r := rng.randf_range(200.0, 320.0)
		var ok := true
		for c in chambers:
			if p.distance_to(c.pos) < c.r + r + 320.0:
				ok = false
				break
		if ok:
			chambers.append({"pos": p, "r": r, "kind": "junction"})
	for c in chambers:
		shapes.append([c.pos, c.pos, c.r])
	# links: minimum spanning tree + a few extra short links + extra hive exits
	var n := chambers.size()
	var links := {}
	var in_tree := [0]
	while in_tree.size() < n:
		var best := Vector2i(-1, -1)
		var bd := INF
		for i in in_tree:
			for j in n:
				if j in in_tree:
					continue
				var d: float = chambers[i].pos.distance_to(chambers[j].pos)
				if d < bd:
					bd = d
					best = Vector2i(i, j)
		in_tree.append(best.y)
		links[_key(best.x, best.y)] = best
	for i in n:
		var near := []
		for j in n:
			if j != i:
				near.append([chambers[i].pos.distance_to(chambers[j].pos), j])
		near.sort_custom(func(x, y): return x[0] < y[0])
		var extra := 3 if chambers[i].kind == "hive" else 2
		for k in extra:
			var j: int = near[k][1]
			if near[k][0] < 2100.0 or chambers[i].kind == "hive":
				links[_key(i, j)] = Vector2i(i, j)
	# carve tunnels
	var chamber_wp := []
	for c in chambers:
		chamber_wp.append(_add_wp(c.pos))
	for l in links.values():
		_carve(l.x, l.y, chamber_wp)
	# spatial buckets for fast collision queries
	for si in shapes.size():
		var s: Array = shapes[si]
		var r: float = s[2] + 40.0
		var lo := Vector2(minf(s[0].x, s[1].x), minf(s[0].y, s[1].y)) - Vector2(r, r)
		var hi := Vector2(maxf(s[0].x, s[1].x), maxf(s[0].y, s[1].y)) + Vector2(r, r)
		for bx in range(int(floor(lo.x / BUCKET)), int(floor(hi.x / BUCKET)) + 1):
			for by in range(int(floor(lo.y / BUCKET)), int(floor(hi.y / BUCKET)) + 1):
				var k := Vector2i(bx, by)
				if not buckets.has(k):
					buckets[k] = []
				buckets[k].append(si)


func _key(i: int, j: int) -> String:
	return "%d-%d" % [mini(i, j), maxi(i, j)]


func _add_wp(p: Vector2) -> int:
	wp.append(p)
	wp_adj.append([])
	return wp.size() - 1


func _link_wp(i: int, j: int) -> void:
	var d := wp[i].distance_to(wp[j])
	wp_adj[i].append([j, d])
	wp_adj[j].append([i, d])


func _carve(i: int, j: int, chamber_wp: Array) -> void:
	var A: Vector2 = chambers[i].pos
	var B: Vector2 = chambers[j].pos
	var dir := (B - A).normalized()
	var perp := dir.orthogonal()
	var L := A.distance_to(B)
	var ctrl := [A]
	var k := maxi(2, int(L / 700.0))
	for m in range(1, k + 1):
		var f := float(m) / (k + 1)
		ctrl.append(A.lerp(B, f) + perp * rng.randf_range(-260.0, 260.0))
	ctrl.append(B)
	var curve := Bio.smooth(ctrl, false, 8)
	# resample evenly
	var pts := PackedVector2Array([curve[0]])
	var acc := 0.0
	for q in range(1, curve.size()):
		var seg := curve[q].distance_to(curve[q - 1])
		acc += seg
		if acc >= 110.0:
			pts.append(curve[q])
			acc = 0.0
	if pts[pts.size() - 1].distance_to(B) > 20.0:
		pts.append(B)
	var r := rng.randf_range(135.0, 175.0)
	tunnels.append([pts, r])
	for q in range(1, pts.size()):
		shapes.append([pts[q - 1], pts[q], r * rng.randf_range(0.92, 1.08)])
	# waypoints every other sample (outside the end chambers)
	var prev: int = chamber_wp[i]
	for q in range(2, pts.size() - 1, 2):
		var p := pts[q]
		if p.distance_to(A) < chambers[i].r * 0.8 or p.distance_to(B) < chambers[j].r * 0.8:
			continue
		var w := _add_wp(p)
		_link_wp(prev, w)
		prev = w
	_link_wp(prev, chamber_wp[j])


# ---------------------------------------------------------------- collision
static func _closest(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.001:
		return a
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)


func _cands(p: Vector2) -> Array:
	var k := Vector2i(int(floor(p.x / BUCKET)), int(floor(p.y / BUCKET)))
	return buckets.get(k, [])


func inside(p: Vector2, margin := 0.0) -> bool:
	for si in _cands(p):
		var s: Array = shapes[si]
		var r: float = s[2] - margin
		if p.distance_squared_to(_closest(p, s[0], s[1])) <= r * r:
			return true
	return false


## Pushes p back into open space (by the least amount). Returns p if already inside.
func constrain(p: Vector2, margin := 0.0) -> Vector2:
	var cands := _cands(p)
	if cands.is_empty():
		cands = range(shapes.size())
	var best := p
	var bv := INF
	for si in cands:
		var s: Array = shapes[si]
		var cp := _closest(p, s[0], s[1])
		var r: float = maxf(s[2] - margin, 4.0)
		var d := p.distance_to(cp)
		if d <= r:
			return p
		if d - r < bv:
			bv = d - r
			best = cp + (p - cp) / d * r
	return best


func clear_line(a: Vector2, b: Vector2, margin := 20.0) -> bool:
	var d := a.distance_to(b)
	var steps := int(d / 55.0) + 1
	for i in range(1, steps + 1):
		if not inside(a.lerp(b, float(i) / steps), margin):
			return false
	return true


# ---------------------------------------------------------------- navigation
func nearest_wp(p: Vector2) -> int:
	var order := []
	for i in wp.size():
		order.append([p.distance_squared_to(wp[i]), i])
	order.sort_custom(func(x, y): return x[0] < y[0])
	for k in mini(5, order.size()):
		var i: int = order[k][1]
		if clear_line(p, wp[i], 10.0):
			return i
	return order[0][1]


func _table(dest: int) -> PackedInt32Array:
	if _toward.has(dest):
		return _toward[dest]
	var n := wp.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var nxt := PackedInt32Array()
	nxt.resize(n)
	nxt.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	dist[dest] = 0.0
	nxt[dest] = dest
	for it in n:
		var u := -1
		var bd := INF
		for i in n:
			if done[i] == 0 and dist[i] < bd:
				bd = dist[i]
				u = i
		if u < 0:
			break
		done[u] = 1
		for e in wp_adj[u]:
			var v: int = e[0]
			var nd: float = dist[u] + e[1]
			if nd < dist[v]:
				dist[v] = nd
				nxt[v] = u
	_toward[dest] = nxt
	return nxt


## Where to head next to get from `from` to `to` through the tunnels.
func steer(from: Vector2, to: Vector2) -> Vector2:
	if clear_line(from, to, 24.0):
		return to
	var a := nearest_wp(from)
	var b := nearest_wp(to)
	if a == b:
		return to if from.distance_to(wp[a]) < 60.0 else wp[a]
	var tbl := _table(b)
	var cur := a
	# skip ahead along the path while it stays in sight
	var target := wp[a]
	for k in 4:
		var nx := tbl[cur]
		if nx < 0 or nx == cur:
			break
		if clear_line(from, wp[nx], 24.0):
			target = wp[nx]
			cur = nx
		else:
			break
	if cur == b and clear_line(from, to, 24.0):
		return to
	return target


func chamber_of(kind: String, slot := -1) -> Dictionary:
	for c in chambers:
		if c.kind == kind and (slot < 0 or c.get("slot", -1) == slot):
			return c
	return {}


# ---------------------------------------------------------------- drawing
const ROCK := Color(0.012, 0.009, 0.015)
const FLOOR := Color(0.105, 0.085, 0.1)
const FLOOR_EDGE := Color(0.07, 0.055, 0.07)
const RIM := Color(0.55, 0.3, 0.7)


func _shape_poly(s: Array, grow: float) -> PackedVector2Array:
	var a: Vector2 = s[0]
	var b: Vector2 = s[1]
	var r: float = s[2] + grow
	var out := PackedVector2Array()
	if a.distance_to(b) < 0.5:
		var n := clampi(int(r / 14.0), 24, 72)
		for i in n:
			var ang := TAU * i / n
			var wob := 1.0 + 0.035 * sin(ang * 5.0 + a.x * 0.01) + 0.025 * sin(ang * 11.0 + a.y * 0.01)
			out.append(a + Vector2.RIGHT.rotated(ang) * r * wob)
		return out
	var d := (b - a).normalized()
	var base := d.angle()
	for i in 9:
		out.append(b + Vector2.RIGHT.rotated(base - PI * 0.5 + PI * i / 8.0) * r)
	for i in 9:
		out.append(a + Vector2.RIGHT.rotated(base + PI * 0.5 + PI * i / 8.0) * r)
	return out


func _ready() -> void:
	z_index = -20


func _draw() -> void:
	var half := Game.WORLD_HALF + 600.0
	draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), ROCK)
	# rock speckle
	var r2 := RandomNumberGenerator.new()
	r2.seed = 99
	for i in 1400:
		var p := Vector2(r2.randf_range(-half, half), r2.randf_range(-half, half))
		draw_circle(p, r2.randf_range(6.0, 28.0), Color(0.035, 0.025, 0.04, r2.randf_range(0.3, 0.7)))
	# glowing rims (enlarged shapes), then edge band, then floor on top
	for s in shapes:
		draw_colored_polygon(_shape_poly(s, 22.0), Color(RIM, 0.10))
	for s in shapes:
		draw_colored_polygon(_shape_poly(s, 9.0), Color(RIM, 0.32))
	for s in shapes:
		draw_colored_polygon(_shape_poly(s, 0.0), FLOOR_EDGE)
	for s in shapes:
		draw_colored_polygon(_shape_poly(s, -26.0), FLOOR)
	# floor detail + wall fungus
	for c in chambers:
		var cnt := int(c.r * c.r / 9000.0)
		for i in cnt:
			var p: Vector2 = c.pos + Vector2.RIGHT.rotated(r2.randf() * TAU) * c.r * sqrt(r2.randf()) * 0.9
			draw_circle(p, r2.randf_range(2.0, 7.0), Color(0.13, 0.105, 0.125, 0.7))
	var fungus := [Color(0.45, 1.0, 0.75), Color(1.0, 0.72, 0.3), Color(0.7, 0.5, 1.0)]
	for t in tunnels:
		var pts: PackedVector2Array = t[0]
		var r: float = t[1]
		for q in range(1, pts.size(), 2):
			if r2.randf() < 0.45:
				continue
			var dir := (pts[q] - pts[q - 1]).normalized().orthogonal() * (1.0 if r2.randf() < 0.5 else -1.0)
			var at := pts[q] + dir * (r - 8.0)
			var col: Color = fungus[r2.randi() % 3]
			for k in r2.randi_range(2, 5):
				var fp := at + Vector2(r2.randf_range(-18, 18), r2.randf_range(-18, 18)) - dir * r2.randf_range(0, 14)
				var fr := r2.randf_range(2.0, 4.5)
				draw_circle(fp, fr * 3.0, Color(col, 0.06))
				draw_circle(fp, fr, Color(col, 0.75))
	for c in chambers:
		for i in int(c.r / 30.0):
			if r2.randf() < 0.5:
				continue
			var ang := r2.randf() * TAU
			var at: Vector2 = c.pos + Vector2.RIGHT.rotated(ang) * (c.r - 10.0)
			var col: Color = fungus[r2.randi() % 3]
			for k in r2.randi_range(2, 4):
				var fp := at + Vector2(r2.randf_range(-16, 16), r2.randf_range(-16, 16))
				var fr := r2.randf_range(2.0, 4.0)
				draw_circle(fp, fr * 3.0, Color(col, 0.06))
				draw_circle(fp, fr, Color(col, 0.7))
