class_name Gfx
extends RefCounted
## Sprite baking. All the neon vector art is drawn ONCE at startup into a single
## texture atlas (via an offscreen SubViewport) and then shown as sprites.
## Sprites that share a texture + material are batched by the renderer into a
## few draw calls, instead of one draw call per glowing line.
##
## Baked pixels are premultiplied-alpha (they were blended onto a transparent
## target), so every sprite uses the shared PREMULT material and tints must go
## through pm().

const ATLAS_W := 2048
const PAD := 4

static var atlas: Texture2D
static var regions := {}  # name -> Rect2 (atlas pixels)
static var centers := {}  # name -> Vector2 (sprite offset that puts local 0,0 on the node origin)
static var premult: CanvasItemMaterial
static var ready := false


static func pm(c: Color) -> Color:
	return Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a)


static func sprite(name: String, tint := Color.WHITE) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = atlas
	s.region_enabled = true
	s.region_rect = regions[name]
	s.offset = centers[name]
	s.material = premult
	s.modulate = pm(tint)
	return s


static func tint(s: CanvasItem, c: Color) -> void:
	s.modulate = pm(c)


## Draw an atlas item directly (for immediate-mode effects). ci must use the premult material.
static func blit(ci: CanvasItem, name: String, pos: Vector2, scale: float, c: Color) -> void:
	var r: Rect2 = regions[name]
	var sz := r.size * scale
	ci.draw_texture_rect_region(atlas, Rect2(pos + (centers[name] * scale) - sz * 0.5, sz), r, pm(c))


## Render fn(canvas_item) into a texture of the given size. fn draws around
## `origin` (top-left based coordinates). Returns an ImageTexture.
static func bake(host: Node, size: Vector2i, fn: Callable) -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return ImageTexture.create_from_image(Image.create(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8))
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.process_mode = Node.PROCESS_MODE_ALWAYS
	var p := Painter.new()
	p.fn = fn
	vp.add_child(p)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		img = Image.create(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- atlas build
static func build(host: Node) -> void:
	premult = CanvasItemMaterial.new()
	premult.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var items := []  # [name, bounds Rect2, fn]
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210

	for tr in 5:
		var b := _poly_bounds(Ship.tier_data(tr).hull).grow(20.0)
		items.append(["ship%d_glow" % tr, b, _ship_glow.bind(tr)])
		items.append(["ship%d_core" % tr, b, _ship_core.bind(tr)])
	items.append(["flame", Rect2(-52, -13, 56, 26), _flame])
	items.append(["dot", Rect2(-21, -21, 42, 42), _dot])
	items.append(["missile", Rect2(-16, -12, 30, 24), _missile])
	items.append(["bolt", Rect2(-28, -9, 34, 18), _bolt])
	items.append(["dashring", Rect2(-136, -136, 272, 272), _dashring])
	items.append(["reticle", Rect2(-40, -40, 80, 80), _reticle])
	items.append(["blob", Rect2(-130, -130, 260, 260), _blob])

	var raider := Neon.mirror([Vector2(18, 0), Vector2(6, -3), Vector2(12, -10), Vector2(2, -7), Vector2(-4, -14), Vector2(-10, -13), Vector2(-6, -5), Vector2(-12, -3), Vector2(-11, 0)], 1.35)
	items.append(["raider", _poly_bounds(raider).grow(18.0), _raider.bind(raider)])
	var bomber := Neon.mirror([Vector2(22, 0), Vector2(14, -8), Vector2(4, -10), Vector2(0, -20), Vector2(-14, -22), Vector2(-10, -10), Vector2(-20, -8), Vector2(-18, 0)], 1.75)
	items.append(["bomber", _poly_bounds(bomber).grow(18.0), _bomber.bind(bomber)])
	for i in 6:
		var rock := Neon.rock(rng, 30.0, rng.randi_range(9, 12), 0.3)
		items.append(["meteor%d" % i, Rect2(-52, -52, 104, 104), _meteor.bind(rock, rng.randf() * TAU)])
	for i in 10:
		items.append(["ast%d" % i, Rect2(-66, -66, 132, 132), _asteroid.bind(_ast_data(rng), 45.0, Color(0.78, 0.45, 1.0))])
	for i in 4:
		items.append(["gold%d" % i, Rect2(-46, -46, 92, 92), _asteroid.bind(_ast_data(rng), 30.0, Color(1.0, 0.8, 0.28))])

	# shelf-pack tallest first
	var order := range(items.size())
	order.sort_custom(func(a, b): return items[a][1].size.y > items[b][1].size.y)
	var x := PAD
	var y := PAD
	var row_h := 0
	var cells := {}
	for idx in order:
		var it: Array = items[idx]
		var sz: Vector2 = it[1].size.ceil()
		if x + sz.x + PAD > ATLAS_W:
			x = PAD
			y += row_h + PAD
			row_h = 0
		cells[idx] = Vector2(x, y)
		x += int(sz.x) + PAD
		row_h = maxi(row_h, int(sz.y))
	var h := y + row_h + PAD

	var draw_all := func(ci: CanvasItem) -> void:
		for idx in cells.keys():
			var it: Array = items[idx]
			var b: Rect2 = it[1]
			ci.draw_set_transform(cells[idx] - b.position)
			it[2].call(ci)
		ci.draw_set_transform(Vector2.ZERO)

	atlas = await bake(host, Vector2i(ATLAS_W, h), draw_all)
	for idx in cells.keys():
		var it: Array = items[idx]
		var b: Rect2 = it[1]
		regions[it[0]] = Rect2(cells[idx], b.size)
		centers[it[0]] = b.get_center()
	ready = true


static func _poly_bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	return r


static func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate()
	q.append(p[0])
	return q


# ---------------------------------------------------------------- painters
static func _ship_glow(ci: CanvasItem, tr: int) -> void:
	var d: Dictionary = Ship.tier_data(tr)
	var s: float = d.s
	var hull: PackedVector2Array = d.hull
	if d.fill_ok:
		ci.draw_colored_polygon(hull, Color(0.11, 0.11, 0.14, 0.94))
	for ln in d.lines:
		ci.draw_line(ln[0], ln[1], Color(1, 1, 1, 0.16), 4.0, true)
		ci.draw_line(ln[0], ln[1], Color(1, 1, 1, 0.5), 1.2, true)
	var w := 1.6 + s * 0.5
	var p := _closed(hull)
	ci.draw_polyline(p, Color(1, 1, 1, 0.06), w * 7.0, true)
	ci.draw_polyline(p, Color(1, 1, 1, 0.17), w * 3.2, true)
	ci.draw_polyline(p, Color(1, 1, 1, 1), w, true)
	ci.draw_colored_polygon(d.cockpit, Color(1, 1, 1, 0.8))
	for e in d.engines:
		ci.draw_circle(e, 2.4 * s * 3.0, Color(1, 1, 1, 0.06))
		ci.draw_circle(e, 2.4 * s * 1.8, Color(1, 1, 1, 0.18))
		ci.draw_circle(e, 2.4 * s, Color(1, 1, 1, 0.9))


static func _ship_core(ci: CanvasItem, tr: int) -> void:
	var d: Dictionary = Ship.tier_data(tr)
	var s: float = d.s
	var w := 1.6 + s * 0.5
	ci.draw_polyline(_closed(d.hull), Color(1, 1, 1, 0.6), maxf(w * 0.38, 0.8), true)
	ci.draw_colored_polygon(d.cockpit, Color(1, 1, 1, 0.55))
	for e in d.engines:
		ci.draw_circle(e, 1.2 * s, Color(1, 1, 1, 0.85))


static func _flame(ci: CanvasItem) -> void:
	var L := 32.0
	var w := 7.0
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, -w * 1.6), Vector2(-L * 1.5, 0), Vector2(0, w * 1.6)]), Color(1, 1, 1, 0.18))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, -w), Vector2(-L, 0), Vector2(0, w)]), Color(1, 1, 1, 0.65))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, -w * 0.45), Vector2(-L * 0.55, 0), Vector2(0, w * 0.45)]), Color(1, 1, 1, 0.95))


static func _dot(ci: CanvasItem) -> void:
	var r := 6.0
	for k in 8:
		var f := 1.0 - k / 8.0
		ci.draw_circle(Vector2.ZERO, r * 3.2 * f, Color(1, 1, 1, 0.045 + 0.02 * k))
	ci.draw_circle(Vector2.ZERO, r, Color(1, 1, 1, 0.9))
	ci.draw_circle(Vector2.ZERO, r * 0.5, Color(1, 1, 1, 1))


static func _missile(ci: CanvasItem) -> void:
	var body := PackedVector2Array([Vector2(8, 0), Vector2(-4, -2.6), Vector2(-2, 0), Vector2(-4, 2.6)])
	ci.draw_circle(Vector2(-4, 0), 6.5, Color(1, 1, 1, 0.08))
	ci.draw_circle(Vector2(-4, 0), 3.8, Color(1, 1, 1, 0.25))
	ci.draw_polyline(_closed(body), Color(1, 1, 1, 0.2), 4.0, true)
	ci.draw_colored_polygon(body, Color(1, 1, 1, 0.95))
	ci.draw_circle(Vector2(-4, 0), 2.0, Color(1, 1, 1, 1))


static func _bolt(ci: CanvasItem) -> void:
	var L := 20.0
	ci.draw_line(Vector2(-L, 0), Vector2(0, 0), Color(1, 1, 1, 0.15), 12.0, true)
	ci.draw_line(Vector2(-L, 0), Vector2(0, 0), Color(1, 1, 1, 0.85), 3.0, true)
	ci.draw_line(Vector2(-L * 0.6, 0), Vector2(0, 0), Color(1, 1, 1, 1), 1.2, true)


static func _dashring(ci: CanvasItem) -> void:
	var r := 128.0
	var segs := 40
	for i in segs:
		if i % 2 == 0:
			var a0 := TAU * i / segs
			ci.draw_arc(Vector2.ZERO, r, a0, a0 + TAU / segs * 0.9, 4, Color(1, 1, 1, 0.25), 5.0, true)
			ci.draw_arc(Vector2.ZERO, r, a0, a0 + TAU / segs * 0.9, 4, Color(1, 1, 1, 1), 1.8, true)


static func _reticle(ci: CanvasItem) -> void:
	var r := 26.0
	for i in 4:
		var a := TAU * i / 4.0
		ci.draw_arc(Vector2.ZERO, r, a - 0.35, a + 0.35, 6, Color(1, 1, 1, 0.2), 5.0, true)
		ci.draw_arc(Vector2.ZERO, r, a - 0.35, a + 0.35, 6, Color(1, 1, 1, 1), 1.8, true)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var p := Vector2.RIGHT.rotated(a) * (r + 7.0)
		ci.draw_line(p, p * 0.84, Color(1, 1, 1, 0.9), 1.6, true)


static func _blob(ci: CanvasItem) -> void:
	for k in 24:
		var f := 1.0 - k / 24.0
		ci.draw_circle(Vector2.ZERO, 128.0 * f, Color(1, 1, 1, 0.035))


static func _raider(ci: CanvasItem, shape: PackedVector2Array) -> void:
	var c := Color(1, 0.25, 0.32)
	ci.draw_colored_polygon(shape, Color(0.14, 0.02, 0.04, 0.95))
	Neon.outline(ci, shape, c, 1.8, 1.0)
	Neon.dot(ci, Vector2(7, -3.2), 1.8, Color(1, 0.9, 0.4), 0.9)
	Neon.dot(ci, Vector2(7, 3.2), 1.8, Color(1, 0.9, 0.4), 0.9)


static func _bomber(ci: CanvasItem, shape: PackedVector2Array) -> void:
	var c := Color(1, 0.2, 0.65)
	ci.draw_colored_polygon(shape, Color(0.13, 0.02, 0.09, 0.95))
	Neon.outline(ci, shape, c, 2.2, 1.0)
	var hex := PackedVector2Array()
	for i in 6:
		hex.append(Vector2.RIGHT.rotated(TAU * i / 6.0) * 10.0)
	Neon.outline(ci, hex, Color(1, 0.6, 0.9), 1.4, 0.8)
	Neon.dot(ci, Vector2.ZERO, 3.5, Color(1, 0.4, 0.8), 1.0)


static func _meteor(ci: CanvasItem, shape: PackedVector2Array, crack_rot: float) -> void:
	ci.draw_circle(Vector2.ZERO, 40.0, Color(1, 0.45, 0.1, 0.06))
	ci.draw_colored_polygon(shape, Color(0.13, 0.06, 0.03, 1))
	for i in 3:
		var a := TAU * i / 3.0 + crack_rot
		ci.draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(a) * 18.0, Color(1, 0.55, 0.15, 0.45), 1.5, true)
	Neon.outline(ci, shape, Color(1, 0.5, 0.15), 2.0, 1.0)


static func _ast_data(rng: RandomNumberGenerator) -> Dictionary:
	var d := {}
	d.shape = Neon.rock(rng, 1.0, rng.randi_range(11, 15), 0.28)
	d.crystals = []
	for i in rng.randi_range(3, 6):
		var p := Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(0.05, 0.6)
		d.crystals.append([p, rng.randf() * TAU, rng.randf_range(0.14, 0.26)])
	d.cracks = []
	for i in rng.randi_range(2, 4):
		var a := Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(0.2, 0.8)
		var b := a + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(0.2, 0.4)
		d.cracks.append([a, b])
	return d


static func _asteroid(ci: CanvasItem, d: Dictionary, r: float, color: Color) -> void:
	var pts := Neon.scaled(Array(d.shape), r)
	ci.draw_colored_polygon(pts, Color(0.06, 0.05, 0.09, 0.96))
	ci.draw_colored_polygon(Neon.scaled(Array(d.shape), r * 0.72), Color(0.09, 0.07, 0.13, 0.9))
	for cr in d.cracks:
		ci.draw_line(cr[0] * r, cr[1] * r, Color(color, 0.22), 1.2, true)
	Neon.outline(ci, pts, Color(0.55, 0.48, 0.7, 0.85), 1.6, 0.6)
	for c in d.crystals:
		var p: Vector2 = c[0] * r
		var sz: float = c[2] * r
		var ang: float = c[1]
		var dpts := PackedVector2Array([
			p + Vector2(sz, 0).rotated(ang), p + Vector2(0, sz * 0.45).rotated(ang),
			p + Vector2(-sz * 0.6, 0).rotated(ang), p + Vector2(0, -sz * 0.45).rotated(ang)])
		ci.draw_circle(p, sz * 1.4, Color(color, 0.08))
		ci.draw_colored_polygon(dpts, Color(color, 0.55))
		Neon.outline(ci, dpts, color.lerp(Color.WHITE, 0.3), 1.2, 0.8)
