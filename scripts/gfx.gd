class_name Gfx
extends RefCounted
## Sprite baking. All the organic art (chitin shells, glowing membranes, veins)
## is painted ONCE at startup into a couple of texture-atlas pages via an
## offscreen SubViewport, then shown as sprites. Sprites that share a page and
## material are batched by the renderer into a handful of draw calls.
##
## Baked pixels are premultiplied-alpha (they were blended onto a transparent
## target), so every sprite uses the shared PREMULT material and tints must go
## through pm().

const PAGE_W := 2048
const PAGE_H := 2048
const PAD := 8

# palette
const C_PLAYER := Color(0.4, 1.0, 0.82)
const C_FORAGER := Color(0.78, 1.0, 0.42)
const C_GUARD := Color(0.36, 1.0, 0.5)
const C_NECTAR := Color(1.0, 0.72, 0.2)
const C_ORE := Color(0.78, 0.46, 1.0)
const C_ICE := Color(0.55, 0.88, 1.0)
const C_FOE := Color(1.0, 0.26, 0.45)
const C_SWARM := Color(1.0, 0.48, 0.2)
const C_REAPER := Color(0.95, 0.28, 0.85)
const C_HIVE := Color(0.45, 1.0, 0.75)
const ALLY_BASE := Color(0.2, 0.16, 0.08)
const ALLY_RIM := Color(0.9, 0.68, 0.32)
const FOE_BASE := Color(0.12, 0.03, 0.07)
const FOE_RIM := Color(0.8, 0.24, 0.4)
const HIVE_BASE := Color(0.17, 0.12, 0.06)
const HIVE_RIM := Color(0.95, 0.72, 0.36)
const FLESH := Color(0.24, 0.09, 0.1)
const FLESH_RIM := Color(1.0, 0.55, 0.45)

const GLANDS := {
	"carapace": Color(0.95, 0.66, 0.3),
	"wing": Color(0.5, 1.0, 0.85),
	"pouch": Color(1.0, 0.78, 0.25),
	"venom": Color(0.6, 1.0, 0.25),
	"proboscis": Color(1.0, 0.5, 0.75),
	"eye": Color(0.55, 0.85, 1.0),
}

static var pages: Array = []
static var page_of := {}
static var regions := {}  # name -> Rect2 (page pixels)
static var centers := {}  # name -> Vector2 (sprite offset that puts local 0,0 on the node origin)
static var premult: CanvasItemMaterial
static var ready := false


static func pm(c: Color) -> Color:
	return Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a)


static func res_color(kind: String) -> Color:
	match kind:
		"nectar":
			return C_NECTAR
		"ore":
			return C_ORE
		"ice":
			return C_ICE
	return Color.WHITE


static func sprite(name: String, tint := Color.WHITE) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = pages[page_of[name]]
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
	ci.draw_texture_rect_region(pages[page_of[name]], Rect2(pos + (centers[name] * scale) - sz * 0.5, sz), r, pm(c))


## Render fn(canvas_item) into a texture of the given size.
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


# ---------------------------------------------------------------- creature specs
## Player forms grow as the hive's glands mature.
static func form(k: int) -> Dictionary:
	var t: Array = [
		{"s": 1.0, "nseg": 3, "spikes": 0, "mand": 0.6, "ant": 0.9, "sting": 0.9, "crown": false, "pairs": 1, "wl": 15.0},
		{"s": 1.12, "nseg": 3, "spikes": 0, "mand": 0.8, "ant": 1.0, "sting": 1.0, "crown": false, "pairs": 2, "wl": 16.0},
		{"s": 1.26, "nseg": 4, "spikes": 2, "mand": 1.0, "ant": 1.1, "sting": 1.1, "crown": false, "pairs": 2, "wl": 17.0},
		{"s": 1.4, "nseg": 5, "spikes": 4, "mand": 1.2, "ant": 1.2, "sting": 1.25, "crown": true, "pairs": 2, "wl": 18.0},
		{"s": 1.55, "nseg": 6, "spikes": 6, "mand": 1.4, "ant": 1.35, "sting": 1.4, "crown": true, "pairs": 2, "wl": 19.0},
	]
	var d: Dictionary = t[clampi(k, 0, 4)].duplicate()
	d.glow = C_PLAYER
	d.base = ALLY_BASE
	d.rim = ALLY_RIM
	d.slim = 1.0
	return d


static func drone_spec(guard: bool) -> Dictionary:
	if guard:
		return {"s": 0.86, "nseg": 3, "spikes": 2, "mand": 0.7, "ant": 0.8, "sting": 1.5, "crown": false, "pairs": 1, "wl": 13.0,
			"glow": C_GUARD, "base": ALLY_BASE, "rim": ALLY_RIM, "slim": 0.8}
	return {"s": 0.82, "nseg": 2, "spikes": 0, "mand": 0.5, "ant": 0.9, "sting": 0.6, "crown": false, "pairs": 1, "wl": 13.0,
		"glow": C_FORAGER, "base": ALLY_BASE, "rim": ALLY_RIM, "slim": 1.2, "sac": C_NECTAR}


static func swarm_spec() -> Dictionary:
	return {"s": 0.74, "nseg": 2, "spikes": 0, "mand": 0.9, "ant": 0.7, "sting": 1.4, "crown": false, "pairs": 1, "wl": 11.0,
		"glow": C_SWARM, "base": FOE_BASE, "rim": Color(0.95, 0.42, 0.25), "slim": 0.78}


## Where the wings attach, in body space (port side; starboard mirrors y).
static func wing_roots(p: Dictionary) -> Array:
	var s: float = p.s
	return [Vector2(4.6, -4.4) * s, Vector2(1.6, -5.0) * s]


static func bee_radius(p: Dictionary) -> float:
	return (9.0 + 1.6 * p.nseg) * p.s


static func _bee_bounds(p: Dictionary) -> Rect2:
	var s: float = p.s
	var back: float = (2.5 + 4.1 * p.nseg + 3.0 + 6.5 * p.sting + 6.0) * s
	var front: float = (21.0 + p.ant * 4.0) * s
	var h: float = (13.0 + p.spikes * 0.7 + p.ant * 2.5) * s + 6.0
	return Rect2(-back, -h, back + front, 2.0 * h)


# ---------------------------------------------------------------- atlas build
static func build(host: Node) -> void:
	premult = CanvasItemMaterial.new()
	premult.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var items := []  # [name, bounds Rect2, fn]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	# player forms
	for k in 5:
		var p := form(k)
		var b := _bee_bounds(p)
		items.append(["pf%d" % k, b, _bee.bind(p, false)])
		items.append(["pf%d_v" % k, b, _bee.bind(p, true)])
		var wl: float = p.wl * p.s
		items.append(["pf%d_wf" % k, _wing_bounds(wl), _wing.bind(wl, p.glow, false)])
		items.append(["pf%d_wh" % k, _wing_bounds(wl), _wing.bind(wl, p.glow, true)])
	for guard in [false, true]:
		var p := drone_spec(guard)
		var key := "dg" if guard else "df"
		items.append([key, _bee_bounds(p), _bee.bind(p, false)])
		items.append([key + "_v", _bee_bounds(p), _bee.bind(p, true)])
		var wl: float = p.wl * p.s
		items.append([key + "_w", _wing_bounds(wl), _wing.bind(wl, p.glow, false)])
	var sw := swarm_spec()
	items.append(["swarm", _bee_bounds(sw), _bee.bind(sw, false)])
	items.append(["swarm_v", _bee_bounds(sw), _bee.bind(sw, true)])
	items.append(["swarm_w", _wing_bounds(sw.wl * sw.s), _wing.bind(sw.wl * sw.s, C_SWARM, false)])

	# field guardians
	items.append(["mite", Rect2(-26, -26, 52, 52), _mite])
	items.append(["polyp", Rect2(-40, -40, 80, 80), _polyp.bind(rng.randi())])
	items.append(["polyp_t", Rect2(-6, -12, 52, 24), _polyp_tentacle])
	items.append(["lurker", Rect2(-62, -40, 100, 80), _lurker])
	items.append(["lurker_f", Rect2(-26, -42, 42, 48), _lurker_fin])
	items.append(["spitter", Rect2(-40, -40, 84, 80), _spitter])
	items.append(["reaper_h", Rect2(-56, -62, 152, 124), _reaper_head])
	items.append(["reaper_s", Rect2(-40, -66, 80, 132), _reaper_seg])
	items.append(["reaper_t", Rect2(-84, -32, 116, 64), _reaper_tail])

	# resource nodes
	for i in 4:
		items.append(["nectar%d" % i, Rect2(-52, -52, 104, 104), _bloom.bind(rng.randi())])
		items.append(["ice%d" % i, Rect2(-52, -52, 104, 104), _rime.bind(rng.randi())])
		items.append(["ore%d" % i, Rect2(-52, -52, 104, 104), _geode.bind(rng.randi())])

	# hive
	items.append(["heart", Rect2(-340, -340, 680, 680), _heart.bind(rng.randi())])
	items.append(["vault", Rect2(-112, -112, 224, 224), _vault.bind(false)])
	items.append(["vault_honey", Rect2(-112, -112, 224, 224), _vault.bind(true)])
	items.append(["forge", Rect2(-112, -112, 224, 224), _forge.bind(rng.randi())])
	items.append(["forge_core", Rect2(-48, -48, 96, 96), _forge_core])
	items.append(["cistern", Rect2(-110, -110, 220, 220), _cistern.bind(rng.randi())])
	items.append(["brood", Rect2(-112, -112, 224, 224), _brood.bind(rng.randi())])
	items.append(["spire", Rect2(-62, -62, 124, 124), _spire_base.bind(rng.randi())])
	items.append(["spire_h", Rect2(-22, -16, 76, 32), _spire_head])
	for gk in GLANDS.keys():
		items.append(["g_" + gk, Rect2(-86, -86, 172, 172), _gland.bind(gk, rng.randi())])
	items.append(["eye_iris", Rect2(-34, -34, 68, 68), _eye_iris])
	items.append(["bud", Rect2(-46, -46, 92, 92), _bud])
	items.append(["nodule", Rect2(-20, -20, 40, 40), _nodule])

	# generic
	items.append(["glow", Rect2(-66, -66, 132, 132), _glow])
	items.append(["dot", Rect2(-21, -21, 42, 42), _dot])
	items.append(["dart", Rect2(-16, -9, 30, 18), _dart])
	items.append(["spore", Rect2(-14, -14, 28, 28), _spore])
	items.append(["spine", Rect2(-22, -8, 36, 16), _spine])
	items.append(["dashring", Rect2(-136, -136, 272, 272), _dashring])
	items.append(["reticle", Rect2(-40, -40, 80, 80), _reticle])
	items.append(["blob", Rect2(-130, -130, 260, 260), _blob])

	# shelf-pack into pages, tallest first
	var order := range(items.size())
	order.sort_custom(func(a, b): return items[a][1].size.y > items[b][1].size.y)
	var page_cells := [{}]
	var page_h := [0]
	var x := PAD
	var y := PAD
	var row_h := 0
	for idx in order:
		var sz: Vector2 = items[idx][1].size.ceil()
		if x + sz.x + PAD > PAGE_W:
			x = PAD
			y += row_h + PAD
			row_h = 0
		if y + sz.y + PAD > PAGE_H:
			page_cells.append({})
			page_h.append(0)
			x = PAD
			y = PAD
			row_h = 0
		var pi := page_cells.size() - 1
		page_cells[pi][idx] = Vector2(x, y)
		page_h[pi] = maxi(page_h[pi], int(y + sz.y + PAD))
		x += int(sz.x) + PAD
		row_h = maxi(row_h, int(sz.y))

	pages.clear()
	for pi in page_cells.size():
		var cells: Dictionary = page_cells[pi]
		var draw_all := func(ci: CanvasItem) -> void:
			for idx in cells.keys():
				var b: Rect2 = items[idx][1]
				ci.draw_set_transform(cells[idx] - b.position)
				items[idx][2].call(ci)
			ci.draw_set_transform(Vector2.ZERO)
		pages.append(await bake(host, Vector2i(PAGE_W, page_h[pi]), draw_all))
		for idx in cells.keys():
			var b: Rect2 = items[idx][1]
			regions[items[idx][0]] = Rect2(cells[idx], b.size)
			centers[items[idx][0]] = b.get_center()
			page_of[items[idx][0]] = pi
	ready = true


# ---------------------------------------------------------------- creatures
static func _seg_layout(p: Dictionary) -> Array:
	var s: float = p.s
	var n: int = p.nseg
	var L := 4.8
	var segs := []
	for i in n:
		var t := float(i) / maxf(n - 1, 1)
		var cx := -2.5 - L * 0.78 * i - L * 0.5
		var ry: float = 7.6 * p.slim * (1.0 - 0.45 * t)
		segs.append([Vector2(cx, 0) * s, L * 0.7 * s, ry * s])
	return segs


## Top-down insect: segmented chitin abdomen with glowing bands, thorax, head
## with compound eyes, mandibles and antennae. `veins` paints only the
## bioluminescent parts (pulsed at runtime).
static func _bee(ci: CanvasItem, p: Dictionary, veins: bool) -> void:
	var s: float = p.s
	var glow: Color = p.glow
	var base: Color = p.base
	var rim: Color = p.rim
	var segs := _seg_layout(p)
	var last: Array = segs[segs.size() - 1]
	var tail_x: float = last[0].x - last[1] * 0.85
	var sting_tip := Vector2(tail_x - 6.5 * p.sting * s, 0)
	var thorax := Vector2(3.2, 0) * s
	var head := Vector2(10.2, 0) * s

	if veins:
		for sg in segs:
			var c: Vector2 = sg[0]
			Bio.vein(ci, Bio.arc_pts(c, sg[1] * 0.82, sg[2] * 0.86, PI * 0.62, PI * 1.38, 10), glow, 1.3 * s, 0.9)
		Bio.vein(ci, PackedVector2Array([thorax + Vector2(-3.5, 0) * s, thorax + Vector2(3.5, 0) * s]), glow, 1.2 * s, 0.7)
		for sy in [-1.0, 1.0]:
			Bio.spot(ci, head + Vector2(1.0, 3.0 * sy) * s, 1.4 * s, glow, 0.9)
		Bio.spot(ci, sting_tip + Vector2(1.5 * s, 0), 1.3 * s, glow, 0.8)
		if p.has("sac"):
			Bio.halo(ci, segs[0][0], 8.0 * s, p.sac, 1.5)
		return

	Bio.halo(ci, Vector2(-2, 0) * s, 15.0 * s, glow, 0.4)
	# legs
	for sy in [-1.0, 1.0]:
		for j in 3:
			var a := thorax + Vector2(-2.0 + j * 2.4, 4.5 * sy) * s
			var knee := a + Vector2(-1.0 + j * 1.2, 4.0 * sy) * s
			var foot := knee + Vector2(-2.5 + j * 2.0, 2.4 * sy) * s
			ci.draw_polyline(PackedVector2Array([a, knee, foot]), Color(rim, 0.3), 0.9 * s, true)
	# stinger
	var sp := Bio.smooth([Vector2(tail_x + 1.5 * s, 0), Vector2(tail_x - 3.0 * p.sting * s, 0), sting_tip], false, 4)
	Bio.chitin(ci, Bio.taper(sp, 2.6 * s, 0.3), base.lightened(0.05), rim, 0.8)
	# abdomen, tail first so front segments overlap
	for i in range(segs.size() - 1, -1, -1):
		var sg: Array = segs[i]
		var poly := Bio.ellipse(sg[0], sg[1], sg[2], 0.0, 26)
		Bio.chitin(ci, poly, base, rim, 1.0 * s)
		ci.draw_polyline(Bio.arc_pts(sg[0], sg[1] * 0.82, sg[2] * 0.86, PI * 0.62, PI * 1.38, 10), Color(glow, 0.45), 1.0 * s, true)
	if p.has("sac"):
		var sac := Bio.ellipse(segs[0][0] + Vector2(-0.5, 0) * s, segs[0][1] * 0.7, segs[0][2] * 0.6, 0.0, 20)
		Bio.membrane(ci, sac, p.sac, 0.35)
	# thorax + spikes
	for j in int(p.spikes / 2):
		for sy in [-1.0, 1.0]:
			var b0 := thorax + Vector2(-1.5 + j * 2.6, 5.2 * sy) * s
			var tip := thorax + Vector2(-4.0 + j * 2.0, (9.5 + j * 1.2) * sy) * s
			var spike := PackedVector2Array([b0 + Vector2(1.6, 0) * s, tip, b0 + Vector2(-1.6, 0) * s])
			Bio.chitin(ci, spike, base, rim, 0.8)
	Bio.chitin(ci, Bio.ellipse(thorax, 5.6 * s, 6.2 * s, 0.0, 26), base, rim, 1.1 * s)
	ci.draw_polyline(PackedVector2Array([thorax + Vector2(-3.5, 0) * s, thorax + Vector2(3.5, 0) * s]), Color(glow, 0.5), 1.0 * s, true)
	# crown horns
	if p.crown:
		for sy in [-1.0, 1.0]:
			var hp := Bio.smooth([head + Vector2(-1.5, 2.5 * sy) * s, head + Vector2(-4.5, 5.5 * sy) * s, head + Vector2(-8.5, 7.0 * sy) * s], false, 4)
			Bio.chitin(ci, Bio.taper(hp, 2.2 * s, 0.3), base, rim, 0.8)
	# head
	Bio.chitin(ci, Bio.ellipse(head, 3.9 * s, 4.7 * s, 0.0, 22), base, rim, 1.0 * s)
	for sy in [-1.0, 1.0]:
		var eye := Bio.ellipse(head + Vector2(0.9, 3.0 * sy) * s, 2.4 * s, 1.6 * s, 0.45 * sy, 16)
		Bio.membrane(ci, eye, glow, 0.55)
		# mandibles
		var mp := Bio.smooth([head + Vector2(2.8, 1.4 * sy) * s, head + Vector2(4.6 + p.mand * 1.5, 2.8 * sy) * s,
			head + Vector2(5.4 + p.mand * 2.6, 0.9 * sy) * s], false, 4)
		Bio.chitin(ci, Bio.taper(mp, 1.6 * s, 0.3), base.lightened(0.08), rim, 0.7)
		# antennae
		var a: float = p.ant
		var ap := Bio.smooth([head + Vector2(2.4, 1.6 * sy) * s, head + Vector2(5.0, (4.0 + a) * sy) * s,
			head + Vector2(6.5 + a * 3.0, (6.5 + a * 2.5) * sy) * s], false, 5)
		ci.draw_polyline(ap, Color(rim, 0.85), 0.9 * s, true)
		Bio.spot(ci, ap[ap.size() - 1], 1.2 * s, glow, 0.9)


static func _wing_bounds(L: float) -> Rect2:
	return Rect2(-0.62 * L - 6.0, -1.06 * L - 6.0, 0.86 * L + 12.0, 1.2 * L + 12.0)


## Membrane wing rooted at the origin, sweeping out (-y) and back (-x).
static func _wing(ci: CanvasItem, L: float, glow: Color, hind: bool) -> void:
	var pts: Array
	if hind:
		pts = [Vector2(0.04, 0), Vector2(0.06, -0.28), Vector2(-0.08, -0.6), Vector2(-0.3, -0.72), Vector2(-0.46, -0.56), Vector2(-0.38, -0.26), Vector2(-0.14, 0.02)]
	else:
		pts = [Vector2(0.06, 0), Vector2(0.12, -0.26), Vector2(0.05, -0.62), Vector2(-0.14, -0.94), Vector2(-0.36, -1.0), Vector2(-0.54, -0.84), Vector2(-0.5, -0.48), Vector2(-0.3, -0.18), Vector2(-0.1, 0.03)]
	var scl := L * (0.78 if hind else 1.0)
	var poly := PackedVector2Array()
	for v in Bio.smooth(pts, true, 5):
		poly.append(v * scl)
	Bio.membrane(ci, poly, glow, 0.13)
	# veins: a main spar to the tip plus branches
	var tip: Vector2 = (pts[4] if not hind else pts[3]) * scl
	var mid := tip * 0.55
	Bio.vein(ci, Bio.smooth([Vector2.ZERO, mid + Vector2(0.06, 0) * scl, tip], false, 4), glow, 0.8, 0.55)
	for f in [0.35, 0.6]:
		var a := Vector2.ZERO.lerp(tip, f)
		var rimp: Vector2 = poly[int(poly.size() * (0.28 if f < 0.5 else 0.2))]
		Bio.vein(ci, PackedVector2Array([a, a.lerp(rimp, 0.55), rimp]), glow, 0.6, 0.4)
		var rimq: Vector2 = poly[int(poly.size() * (0.68 if f < 0.5 else 0.6))]
		Bio.vein(ci, PackedVector2Array([a, rimq]), glow, 0.6, 0.35)


static func _mite(ci: CanvasItem) -> void:
	var s := 1.25
	Bio.halo(ci, Vector2.ZERO, 16.0 * s, C_FOE, 0.4)
	for sy in [-1.0, 1.0]:
		for j in 3:
			var x := (-4.0 + j * 3.5) * s
			var a := Vector2(x, 4.5 * sy * s)
			var knee := a + Vector2(1.5 + j * 0.8, 5.0 * sy) * s
			var foot := knee + Vector2(3.5 + j, 3.5 * sy) * s
			Bio.chitin(ci, Bio.taper(PackedVector2Array([a, knee, foot]), 1.8 * s, 0.4), FOE_BASE, FOE_RIM, 0.7)
	Bio.chitin(ci, Bio.ellipse(Vector2(-1, 0) * s, 8.0 * s, 6.5 * s), FOE_BASE, FOE_RIM, 1.2)
	Bio.chitin(ci, Bio.ellipse(Vector2(7, 0) * s, 3.6 * s, 3.4 * s), FOE_BASE, FOE_RIM, 1.0)
	for sy in [-1.0, 1.0]:
		var pin := Bio.smooth([Vector2(9.5, 1.2 * sy) * s, Vector2(12.5, 2.6 * sy) * s, Vector2(14.0, 0.6 * sy) * s], false, 4)
		Bio.chitin(ci, Bio.taper(pin, 1.5 * s, 0.3), FOE_BASE, FOE_RIM, 0.7)
		Bio.spot(ci, Vector2(8.2, 1.6 * sy) * s, 1.1 * s, C_FOE, 1.0)
	for v in [Vector2(-1, 0), Vector2(-5, -2.5), Vector2(-5, 2.5)]:
		Bio.spot(ci, v * s, 1.3 * s, C_FOE, 0.8)


static func _polyp(ci: CanvasItem, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	Bio.halo(ci, Vector2.ZERO, 38.0, C_FOE, 0.5)
	Bio.chitin(ci, Bio.wobble(Vector2.ZERO, 27.0, 12, 0.18, rng), FOE_BASE, FOE_RIM, 1.6)
	Bio.fill(ci, Bio.ellipse(Vector2.ZERO, 15.0, 15.0), Color(0.05, 0.0, 0.03, 1))
	for i in 9:
		var a := TAU * i / 9.0
		var d := Vector2.RIGHT.rotated(a)
		var tooth := PackedVector2Array([d * 15.0 + d.orthogonal() * 3.0, d * 8.0, d * 15.0 - d.orthogonal() * 3.0])
		Bio.fill(ci, tooth, FOE_RIM.lightened(0.3))
	Bio.spot(ci, Vector2.ZERO, 4.5, C_FOE, 1.0)
	for i in 7:
		var a := TAU * i / 7.0 + 0.3
		Bio.spot(ci, Vector2.RIGHT.rotated(a) * 21.0, 1.6, C_FOE, 0.8)


static func _polyp_tentacle(ci: CanvasItem) -> void:
	var path := Bio.smooth([Vector2(0, 0), Vector2(12, 3), Vector2(24, -2), Vector2(38, 2)], false, 5)
	Bio.chitin(ci, Bio.taper(path, 7.0, 1.4), FOE_BASE, FOE_RIM, 0.9)
	for f in [0.3, 0.55, 0.78]:
		var p := path[int((path.size() - 1) * f)]
		Bio.spot(ci, p, 1.2, C_FOE, 0.7)
	Bio.spot(ci, path[path.size() - 1], 2.0, C_FOE, 1.0)


static func _lurker(ci: CanvasItem) -> void:
	var body := Bio.sym([Vector2(26, 0), Vector2(16, -7), Vector2(4, -11), Vector2(-8, -9), Vector2(-18, -4), Vector2(-28, -1.5), Vector2(-56, 0)])
	var glow := Color(0.95, 0.35, 0.85)
	Bio.halo(ci, Vector2(-4, 0), 34.0, glow, 0.4)
	Bio.chitin(ci, body, Color(0.13, 0.04, 0.12), Color(0.85, 0.35, 0.75), 1.3)
	var spine := Bio.smooth([Vector2(18, 0), Vector2(0, 0), Vector2(-24, 0), Vector2(-50, 0)], false, 4)
	ci.draw_polyline(spine, Color(glow, 0.4), 1.2, true)
	for i in 6:
		var x := 12.0 - i * 7.0
		for sy in [-1.0, 1.0]:
			Bio.spot(ci, Vector2(x, (3.0 + (5 - i) * 0.6) * sy), 1.3, glow, 0.85)
	for sy in [-1.0, 1.0]:
		Bio.spot(ci, Vector2(22, 3.5 * sy), 1.8, Color(1, 0.5, 0.6), 1.0)


static func _lurker_fin(ci: CanvasItem) -> void:
	var glow := Color(0.95, 0.35, 0.85)
	var fin := Bio.smooth([Vector2(10, 0), Vector2(5, -14), Vector2(-4, -30), Vector2(-14, -36), Vector2(-20, -28), Vector2(-15, -10), Vector2(-8, 1)], true, 5)
	Bio.membrane(ci, fin, glow, 0.2)
	for t in [Vector2(-14, -34), Vector2(-18, -22), Vector2(-4, -28)]:
		Bio.vein(ci, Bio.smooth([Vector2(1, 0), t * 0.5 + Vector2(2, 0), t], false, 3), glow, 0.7, 0.5)


static func _spitter(ci: CanvasItem) -> void:
	Bio.halo(ci, Vector2.ZERO, 32.0, C_FOE, 0.45)
	for i in 10:
		var a := TAU * i / 10.0 + 0.3
		var d := Vector2.RIGHT.rotated(a)
		if absf(wrapf(a, -PI, PI)) < 0.5:
			continue
		var sp := PackedVector2Array([d * 16.0 + d.orthogonal() * 4.0, d * 33.0, d * 16.0 - d.orthogonal() * 4.0])
		Bio.chitin(ci, sp, FOE_BASE, FOE_RIM, 0.8)
	var tube := Bio.smooth([Vector2(6, 0), Vector2(20, 0), Vector2(36, 0)], false, 3)
	Bio.chitin(ci, Bio.taper(tube, 11.0, 7.0), FOE_BASE.lightened(0.05), FOE_RIM, 1.0)
	Bio.chitin(ci, Bio.ellipse(Vector2.ZERO, 19.0, 18.0), FOE_BASE, FOE_RIM, 1.4)
	Bio.membrane(ci, Bio.ellipse(Vector2(-2, 0), 9.0, 8.0), C_FOE, 0.45)
	Bio.spot(ci, Vector2(37, 0), 3.0, C_FOE, 1.0)


static func _reaper_head(ci: CanvasItem) -> void:
	var rim := Color(0.85, 0.32, 0.75)
	Bio.halo(ci, Vector2(10, 0), 60.0, C_REAPER, 0.45)
	for sy in [-1.0, 1.0]:
		var mp := Bio.smooth([Vector2(36, 12 * sy), Vector2(58, 26 * sy), Vector2(78, 14 * sy), Vector2(88, 3 * sy)], false, 5)
		Bio.chitin(ci, Bio.taper(mp, 10.0, 1.2), FOE_BASE.lightened(0.04), rim, 1.0)
	var skull := Bio.sym([Vector2(50, 0), Vector2(42, -14), Vector2(28, -27), Vector2(8, -35), Vector2(-12, -33), Vector2(-27, -22), Vector2(-32, -8), Vector2(-32, 0)])
	Bio.chitin(ci, skull, Color(0.1, 0.02, 0.08), rim, 2.0)
	for k in 3:
		var r := 18.0 + k * 9.0
		ci.draw_polyline(Bio.arc_pts(Vector2(4, 0), r, r * 1.1, PI * 0.55, PI * 1.45, 12), Color(rim, 0.35), 1.4, true)
	for e in [Vector2(30, 10), Vector2(20, 19), Vector2(30, -10), Vector2(20, -19)]:
		Bio.membrane(ci, Bio.ellipse(e, 4.6, 3.2, e.angle()), C_REAPER, 0.6)
		Bio.spot(ci, e, 2.2, C_REAPER, 1.0)
	Bio.vein(ci, PackedVector2Array([Vector2(-26, 0), Vector2(14, 0)]), C_REAPER, 1.6, 0.7)


static func _reaper_seg(ci: CanvasItem) -> void:
	var rim := Color(0.85, 0.32, 0.75)
	for sy in [-1.0, 1.0]:
		for j in 2:
			var a := Vector2(-6.0 + j * 12.0, 28.0 * sy)
			var leg := Bio.smooth([a, a + Vector2(-4, 16 * sy), a + Vector2(-14, 30 * sy)], false, 4)
			Bio.chitin(ci, Bio.taper(leg, 5.0, 1.0), FOE_BASE, rim, 0.8)
	var plate := Bio.ellipse(Vector2.ZERO, 25.0, 35.0, 0.0, 30)
	Bio.chitin(ci, plate, Color(0.1, 0.02, 0.08), rim, 1.8)
	ci.draw_polyline(Bio.arc_pts(Vector2(3, 0), 18.0, 28.0, PI * 0.55, PI * 1.45, 12), Color(rim, 0.4), 1.4, true)
	for sy in [-1.0, 1.0]:
		Bio.spot(ci, Vector2(-4, 16 * sy), 2.4, C_REAPER, 0.9)
		Bio.spot(ci, Vector2(8, 22 * sy), 1.6, C_REAPER, 0.7)
	Bio.vein(ci, PackedVector2Array([Vector2(-20, 0), Vector2(20, 0)]), C_REAPER, 1.4, 0.6)


static func _reaper_tail(ci: CanvasItem) -> void:
	var rim := Color(0.85, 0.32, 0.75)
	var tail := Bio.sym([Vector2(24, 0), Vector2(16, -20), Vector2(0, -22), Vector2(-22, -15), Vector2(-48, -6), Vector2(-80, 0)])
	Bio.chitin(ci, tail, Color(0.1, 0.02, 0.08), rim, 1.6)
	for k in 3:
		var x := 6.0 - k * 16.0
		ci.draw_polyline(Bio.arc_pts(Vector2(x, 0), 6.0, 17.0 - k * 4.0, PI * 0.55, PI * 1.45, 8), Color(rim, 0.4), 1.2, true)
	Bio.halo(ci, Vector2(-40, 0), 22.0, C_REAPER, 0.8)
	Bio.membrane(ci, Bio.ellipse(Vector2(-40, 0), 11.0, 7.0), C_REAPER, 0.6)
	Bio.spot(ci, Vector2(-40, 0), 3.5, C_REAPER, 1.0)


# ---------------------------------------------------------------- resources
static func _bloom(ci: CanvasItem, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := rng.randi_range(5, 7)
	var rot := rng.randf() * TAU
	Bio.halo(ci, Vector2.ZERO, 46.0, C_NECTAR, 0.45)
	for i in n:
		var a := rot + TAU * i / n + rng.randf_range(-0.15, 0.15)
		var L := rng.randf_range(32.0, 42.0)
		var d := Vector2.RIGHT.rotated(a)
		var o := d.orthogonal()
		var petal := Bio.smooth([d * 4.0, d * L * 0.4 + o * L * 0.24, d * L, d * L * 0.4 - o * L * 0.24], true, 5)
		Bio.chitin(ci, petal, Color(0.15, 0.1, 0.04), Color(0.95, 0.62, 0.22), 1.1)
		ci.draw_polyline(PackedVector2Array([d * 8.0, d * L * 0.85]), Color(C_NECTAR, 0.55), 1.2, true)
	Bio.halo(ci, Vector2.ZERO, 22.0, C_NECTAR, 1.3)
	Bio.membrane(ci, Bio.ellipse(Vector2.ZERO, 12.0, 12.0), C_NECTAR, 0.6)
	Bio.spot(ci, Vector2(-2, -2), 4.0, Color(1, 0.88, 0.5), 0.9)
	for i in 7:
		var p := Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(16.0, 30.0)
		Bio.spot(ci, p, rng.randf_range(1.2, 2.2), C_NECTAR, 0.9)


static func _rime(ci: CanvasItem, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	Bio.halo(ci, Vector2.ZERO, 44.0, C_ICE, 0.5)
	var n := rng.randi_range(5, 8)
	var order := []
	for i in n:
		order.append([rng.randf() * TAU, rng.randf_range(18.0, 42.0), rng.randf_range(4.0, 7.5)])
	order.sort_custom(func(a, b): return a[1] > b[1])
	for c in order:
		var d := Vector2.RIGHT.rotated(c[0])
		var o := d.orthogonal()
		var L: float = c[1]
		var w: float = c[2]
		var poly := PackedVector2Array([-d * 3.0, o * w, d * L * 0.78 + o * w, d * L, d * L * 0.78 - o * w, -o * w])
		Bio.fill(ci, poly, Color(0.08, 0.16, 0.24, 0.95))
		Bio.fill(ci, PackedVector2Array([-d * 3.0, o * w, d * L * 0.78 + o * w, d * L]), Color(C_ICE, 0.28))
		ci.draw_polyline(Bio.closed(poly), Color(C_ICE, 0.18), 5.0, true)
		ci.draw_polyline(Bio.closed(poly), Color(C_ICE.lightened(0.3), 0.95), 1.1, true)
		ci.draw_line(-d * 2.0, d * L, Color(1, 1, 1, 0.45), 0.8, true)
	Bio.spot(ci, Vector2.ZERO, 3.5, C_ICE, 0.9)


static func _geode(ci: CanvasItem, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	Bio.halo(ci, Vector2.ZERO, 44.0, C_ORE, 0.35)
	var rock := Bio.wobble(Vector2.ZERO, 38.0, 11, 0.26, rng)
	Bio.chitin(ci, rock, Color(0.08, 0.06, 0.11), Color(0.55, 0.45, 0.65), 1.4)
	for i in rng.randi_range(3, 5):
		var a := Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(5.0, 22.0)
		var b := a + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(10.0, 18.0)
		Bio.vein(ci, Bio.smooth([a, a.lerp(b, 0.5) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)), b], false, 3), C_ORE, 1.0, 0.7)
	for i in rng.randi_range(4, 6):
		var p := Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(4.0, 24.0)
		var ang := rng.randf() * TAU
		var sz := rng.randf_range(5.0, 9.0)
		var dpts := PackedVector2Array([p + Vector2(sz, 0).rotated(ang), p + Vector2(0, sz * 0.45).rotated(ang),
			p + Vector2(-sz * 0.6, 0).rotated(ang), p + Vector2(0, -sz * 0.45).rotated(ang)])
		Bio.fill(ci, dpts, Color(C_ORE, 0.6))
		ci.draw_polyline(Bio.closed(dpts), C_ORE.lightened(0.35), 1.1, true)


# ---------------------------------------------------------------- hive
static func _heart(ci: CanvasItem, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	# honeycomb apron
	var hs := 22.0
	var sq3 := sqrt(3.0)
	for q in range(-16, 17):
		for r in range(-16, 17):
			var c := Vector2(hs * 1.5 * q, hs * sq3 * (r + q * 0.5))
			var d := c.length()
			if d < 132.0 or d > 330.0:
				continue
			var fade := 1.0 - (d - 132.0) / 198.0
			var hx := Bio.hexagon(c, hs * 0.9)
			var roll := rng.randf()
			if roll < 0.25:
				Bio.fill(ci, hx, Color(1.0, 0.66, 0.18, 0.28 * fade))
				Bio.spot(ci, c, 2.0, C_NECTAR, 0.35 * fade)
			else:
				Bio.fill(ci, hx, Color(HIVE_BASE, 0.55 * fade))
			ci.draw_polyline(Bio.closed(hx), Color(HIVE_RIM, 0.45 * fade), 1.4, true)
	# fleshy organ
	Bio.halo(ci, Vector2.ZERO, 175.0, FLESH_RIM, 0.35)
	var organ := Bio.wobble(Vector2.ZERO, 140.0, 16, 0.08, rng)
	Bio.chitin(ci, organ, FLESH, FLESH_RIM, 2.6)
	Bio.membrane(ci, Bio.wobble(Vector2.ZERO, 92.0, 12, 0.06, rng), Color(1.0, 0.5, 0.5), 0.12)
	for i in 11:
		var a := TAU * i / 11.0 + rng.randf_range(-0.1, 0.1)
		var pts := [Vector2.RIGHT.rotated(a) * 30.0]
		var cur := a
		for k in 4:
			cur += rng.randf_range(-0.25, 0.25)
			pts.append(Vector2.RIGHT.rotated(cur) * (55.0 + k * 22.0))
		Bio.vein(ci, Bio.smooth(pts, false, 4), C_HIVE, 2.0, 0.8)
	Bio.fill(ci, Bio.ellipse(Vector2.ZERO, 34.0, 34.0), Color(0.08, 0.02, 0.04, 1))


static func _honey_cells() -> Array:
	var out := [Vector2.ZERO]
	for i in 6:
		out.append(Vector2.RIGHT.rotated(TAU * i / 6.0 + PI / 6.0) * 30.0 * sqrt(3.0))
	return out


static func _vault(ci: CanvasItem, honey: bool) -> void:
	var cells := _honey_cells()
	if honey:
		for c in cells:
			Bio.fill(ci, Bio.hexagon(c, 26.0), Color(1.0, 0.62, 0.12, 0.85))
			Bio.fill(ci, Bio.hexagon(c + Vector2(-3, -4), 15.0), Color(1.0, 0.86, 0.45, 0.55))
			Bio.spot(ci, c + Vector2(-7, -9), 2.5, Color(1, 0.95, 0.7), 0.8)
		return
	Bio.halo(ci, Vector2.ZERO, 108.0, C_NECTAR, 0.35)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	Bio.chitin(ci, Bio.wobble(Vector2.ZERO, 98.0, 14, 0.1, rng), HIVE_BASE, HIVE_RIM, 2.0)
	for c in cells:
		var hx := Bio.hexagon(c, 29.0)
		Bio.fill(ci, hx, Color(0.06, 0.04, 0.02, 1))
		ci.draw_polyline(Bio.closed(hx), Color(HIVE_RIM, 0.25), 6.0, true)
		ci.draw_polyline(Bio.closed(hx), HIVE_RIM, 2.2, true)


static func _forge(ci: CanvasItem, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	Bio.halo(ci, Vector2.ZERO, 108.0, C_ORE, 0.4)
	Bio.chitin(ci, Bio.wobble(Vector2.ZERO, 92.0, 14, 0.1, rng), HIVE_BASE, HIVE_RIM, 2.0)
	for k in 2:
		var r := 76.0 - k * 14.0
		ci.draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(HIVE_RIM, 0.3), 1.4, true)
	for i in 8:
		var a := TAU * i / 8.0
		var c := Vector2.RIGHT.rotated(a) * 62.0
		Bio.fill(ci, Bio.ellipse(c, 9.0, 5.0, a), Color(0.04, 0.02, 0.05, 1))
		Bio.spot(ci, c, 2.6, C_ORE, 0.8)
	Bio.chitin(ci, Bio.ellipse(Vector2.ZERO, 38.0, 38.0), Color(0.08, 0.05, 0.08), HIVE_RIM, 2.0)


static func _forge_core(ci: CanvasItem) -> void:
	Bio.halo(ci, Vector2.ZERO, 46.0, C_ORE, 1.6)
	Bio.membrane(ci, Bio.ellipse(Vector2.ZERO, 24.0, 24.0), C_ORE, 0.5)
	Bio.spot(ci, Vector2.ZERO, 8.0, C_ORE.lightened(0.3), 1.0)


static func _cistern(ci: CanvasItem, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	Bio.halo(ci, Vector2.ZERO, 106.0, C_ICE, 0.45)
	Bio.chitin(ci, Bio.wobble(Vector2.ZERO, 90.0, 14, 0.08, rng), HIVE_BASE, HIVE_RIM, 2.0)
	Bio.fill(ci, Bio.ellipse(Vector2.ZERO, 72.0, 72.0), Color(0.03, 0.08, 0.12, 1))
	Bio.membrane(ci, Bio.wobble(Vector2.ZERO, 70.0, 12, 0.05, rng), C_ICE, 0.32)
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf() * 0.3
		var d := Vector2.RIGHT.rotated(a)
		var L := rng.randf_range(14.0, 24.0)
		var o := d.orthogonal() * 3.5
		var base := d * 66.0
		var poly := PackedVector2Array([base + o, base - d * L + o * 0.6, base - d * (L + 5.0), base - d * L - o * 0.6, base - o])
		Bio.fill(ci, poly, Color(C_ICE, 0.35))
		ci.draw_polyline(Bio.closed(poly), Color(C_ICE.lightened(0.3), 0.9), 1.0, true)
	for i in 5:
		Bio.spot(ci, Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(10, 45), rng.randf_range(1.5, 3.0), C_ICE, 0.6)


static func _brood(ci: CanvasItem, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	Bio.halo(ci, Vector2.ZERO, 108.0, C_HIVE, 0.35)
	Bio.chitin(ci, Bio.wobble(Vector2.ZERO, 92.0, 14, 0.12, rng), HIVE_BASE, HIVE_RIM, 2.0)
	var eggs := [[Vector2.ZERO, 0.0]]
	for i in 6:
		var a := TAU * i / 6.0 + 0.25
		eggs.append([Vector2.RIGHT.rotated(a) * 54.0, a])
	for e in eggs:
		var c: Vector2 = e[0]
		var a: float = e[1]
		Bio.fill(ci, Bio.ellipse(c, 21.0, 16.0, a), Color(0.05, 0.08, 0.06, 1))
		Bio.membrane(ci, Bio.ellipse(c, 20.0, 15.0, a), C_HIVE, 0.28)
		var curl := PackedVector2Array()
		for k in 9:
			var t := float(k) / 8.0
			curl.append(c + Vector2(cos(t * 4.0) * 8.0 * (1.0 - t * 0.5), sin(t * 4.0) * 6.0 * (1.0 - t * 0.5)).rotated(a))
		Bio.vein(ci, curl, C_HIVE, 1.6, 0.8)


static func _spire_base(ci: CanvasItem, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	Bio.halo(ci, Vector2.ZERO, 50.0, C_ICE, 0.3)
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf_range(-0.2, 0.2)
		var root := Bio.smooth([Vector2.RIGHT.rotated(a) * 14.0, Vector2.RIGHT.rotated(a + 0.25) * 34.0, Vector2.RIGHT.rotated(a + 0.1) * 56.0], false, 4)
		Bio.chitin(ci, Bio.taper(root, 12.0, 2.0), HIVE_BASE, HIVE_RIM, 1.0)
	Bio.chitin(ci, Bio.ellipse(Vector2.ZERO, 22.0, 22.0), HIVE_BASE, HIVE_RIM, 1.8)
	Bio.fill(ci, Bio.ellipse(Vector2.ZERO, 12.0, 12.0), Color(0.03, 0.05, 0.08, 1))


static func _spire_head(ci: CanvasItem) -> void:
	var path := Bio.smooth([Vector2(-10, 0), Vector2(14, 0), Vector2(48, 0)], false, 4)
	Bio.chitin(ci, Bio.taper(path, 15.0, 1.0), HIVE_BASE.lightened(0.05), HIVE_RIM, 1.2)
	Bio.vein(ci, PackedVector2Array([Vector2(-4, 0), Vector2(40, 0)]), C_ICE, 1.3, 0.85)
	Bio.chitin(ci, Bio.ellipse(Vector2(-6, 0), 10.0, 10.0), HIVE_BASE, HIVE_RIM, 1.2)
	Bio.spot(ci, Vector2(46, 0), 2.6, C_ICE, 1.0)


static func _gland(ci: CanvasItem, key: String, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var col: Color = GLANDS[key]
	Bio.halo(ci, Vector2.ZERO, 82.0, col, 0.45)
	if key == "eye":
		var stalk := Bio.wobble(Vector2.ZERO, 50.0, 10, 0.15, rng)
		Bio.chitin(ci, stalk, FLESH, FLESH_RIM, 1.8)
		for i in 6:
			var a := TAU * i / 6.0
			Bio.vein(ci, Bio.smooth([Vector2.RIGHT.rotated(a) * 30.0, Vector2.RIGHT.rotated(a + 0.2) * 40.0, Vector2.RIGHT.rotated(a + 0.1) * 48.0], false, 3), col, 1.0, 0.5)
		return
	Bio.chitin(ci, Bio.wobble(Vector2.ZERO, 62.0, 12, 0.1, rng), HIVE_BASE, HIVE_RIM, 1.8)
	var sac := Bio.wobble(Vector2(0, 2), 48.0, 11, 0.08, rng)
	Bio.fill(ci, sac, Color(col.darkened(0.8), 1.0))
	Bio.membrane(ci, sac, col, 0.3)
	for i in 5:
		var a := TAU * i / 5.0 + rng.randf() * 0.4
		Bio.vein(ci, Bio.smooth([Vector2.ZERO, Vector2.RIGHT.rotated(a) * 20.0, Vector2.RIGHT.rotated(a + 0.4) * 40.0], false, 3), col, 1.1, 0.55)
	match key:
		"carapace":
			for k in 3:
				var c := Vector2(-14 + k * 14, -6 + k * 6)
				Bio.chitin(ci, Bio.ellipse(c, 20.0, 13.0, -0.6), Color(0.3, 0.2, 0.08), Color(1, 0.8, 0.45), 1.4)
		"wing":
			for k in 3:
				var a := -0.9 + k * 0.9
				var poly := PackedVector2Array()
				for v in Bio.smooth([Vector2(0, 0), Vector2(14, -8), Vector2(40, -6), Vector2(30, 6), Vector2(10, 6)], true, 4):
					poly.append(v.rotated(a))
				Bio.membrane(ci, poly, col, 0.25)
		"pouch":
			for k in 5:
				Bio.spot(ci, Vector2.RIGHT.rotated(TAU * k / 5.0) * 24.0, 3.2, Color(1, 0.85, 0.4), 0.9)
			Bio.spot(ci, Vector2.ZERO, 7.0, Color(1, 0.85, 0.4), 0.9)
		"venom":
			for k in 6:
				var d := Vector2.RIGHT.rotated(TAU * k / 6.0 + 0.3)
				var sp := PackedVector2Array([d * 44.0 + d.orthogonal() * 5.0, d * 70.0, d * 44.0 - d.orthogonal() * 5.0])
				Bio.chitin(ci, sp, HIVE_BASE, HIVE_RIM, 1.0)
			for k in 3:
				Bio.spot(ci, Vector2(-10 + k * 10, 12 - k * 8), 3.5, col, 1.0)
		"proboscis":
			var coil := PackedVector2Array()
			for k in 40:
				var t := float(k) / 39.0
				coil.append(Vector2.RIGHT.rotated(t * TAU * 2.2) * (6.0 + 30.0 * t))
			Bio.vein(ci, coil, col, 2.2, 0.85)


static func _eye_iris(ci: CanvasItem) -> void:
	var col: Color = GLANDS["eye"]
	Bio.fill(ci, Bio.ellipse(Vector2.ZERO, 27.0, 27.0), Color(0.85, 0.9, 0.85, 1))
	Bio.halo(ci, Vector2(8, 0), 18.0, col, 1.4)
	Bio.fill(ci, Bio.ellipse(Vector2(8, 0), 13.0, 13.0), col.darkened(0.2))
	Bio.fill(ci, Bio.ellipse(Vector2(10, 0), 3.5, 10.0), Color(0.02, 0.02, 0.05, 1))
	Bio.spot(ci, Vector2(4, -6), 2.4, Color.WHITE, 0.9)
	ci.draw_arc(Vector2.ZERO, 27.0, 0, TAU, 40, Color(FLESH_RIM, 0.9), 2.0, true)


static func _bud(ci: CanvasItem) -> void:
	Bio.chitin(ci, Bio.ellipse(Vector2.ZERO, 30.0, 24.0, 0.0, 24), HIVE_BASE.darkened(0.2), Color(HIVE_RIM, 0.5), 1.4)
	ci.draw_polyline(Bio.smooth([Vector2(-22, 0), Vector2(-6, -3), Vector2(8, 2), Vector2(22, 0)], false, 4), Color(C_HIVE, 0.45), 1.2, true)


static func _nodule(ci: CanvasItem) -> void:
	Bio.chitin(ci, Bio.ellipse(Vector2.ZERO, 12.0, 11.0), HIVE_BASE, HIVE_RIM, 1.2)
	Bio.spot(ci, Vector2.ZERO, 3.2, C_HIVE, 1.0)


# ---------------------------------------------------------------- generic
static func _glow(ci: CanvasItem) -> void:
	for k in 16:
		var f := 1.0 - k / 16.0
		ci.draw_circle(Vector2.ZERO, 64.0 * f * f, Color(1, 1, 1, 0.06 + 0.012 * k))


static func _dot(ci: CanvasItem) -> void:
	var r := 6.0
	for k in 8:
		var f := 1.0 - k / 8.0
		ci.draw_circle(Vector2.ZERO, r * 3.2 * f, Color(1, 1, 1, 0.045 + 0.02 * k))
	ci.draw_circle(Vector2.ZERO, r, Color(1, 1, 1, 0.9))
	ci.draw_circle(Vector2.ZERO, r * 0.5, Color(1, 1, 1, 1))


static func _dart(ci: CanvasItem) -> void:
	Bio.halo(ci, Vector2(-3, 0), 8.0, Color.WHITE, 1.0)
	var path := Bio.smooth([Vector2(-9, 0), Vector2(0, 0), Vector2(11, 0)], false, 3)
	var t := Bio.taper(path, 4.2, 0.4)
	Bio.fill(ci, t, Color(1, 1, 1, 0.95))
	ci.draw_polyline(Bio.closed(t), Color(1, 1, 1, 0.3), 3.0, true)


static func _spore(ci: CanvasItem) -> void:
	Bio.halo(ci, Vector2.ZERO, 13.0, Color.WHITE, 1.6)
	ci.draw_circle(Vector2.ZERO, 5.0, Color(1, 1, 1, 0.9))
	ci.draw_circle(Vector2(-1.5, -1.5), 2.0, Color(1, 1, 1, 1))


static func _spine(ci: CanvasItem) -> void:
	Bio.halo(ci, Vector2(-2, 0), 8.0, Color.WHITE, 0.9)
	var t := Bio.taper(Bio.smooth([Vector2(-18, 0), Vector2(0, 0), Vector2(10, 0)], false, 3), 3.6, 0.4)
	Bio.fill(ci, t, Color(1, 1, 1, 0.95))


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
