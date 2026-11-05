class_name FogOfWar
extends Sprite2D
## Fog of war. The world is split into coarse cells; every ~0.12 s we mark
## which cells allied eyes (you, your drones, hive modules) can see, write the
## result into a tiny R8 texture and draw it stretched over the world with
## linear filtering, which gives soft edges for free.
##   unexplored = near-black, explored but unseen = dim veil, seen = clear.
## Enemies hide themselves when their cell isn't currently seen.

const CELL := 80.0
const A_UNSEEN := 250
const A_EXPLORED := 150

var n := 0
var half := 0.0
var explored := PackedByteArray()
var base := PackedByteArray()
var out := PackedByteArray()
var img: Image
var tex: ImageTexture
var _t := 0.0
var sources := []  # rebuilt each update: [pos, radius]

const SHADER := """
shader_type canvas_item;
uniform vec4 fog_color : source_color = vec4(0.04, 0.022, 0.07, 1.0);
uniform vec4 edge_color : source_color = vec4(0.45, 0.3, 0.75, 1.0);
void fragment() {
	float a = texture(TEXTURE, UV).r;
	vec2 p = UV * 46.0;
	float n = sin(p.x * 1.3 + TIME * 0.15 + sin(p.y * 0.7)) * sin(p.y * 1.1 - TIME * 0.1 + sin(p.x * 0.6));
	vec3 c = fog_color.rgb * (1.0 + n * 0.35);
	float edge = smoothstep(0.04, 0.28, a) * (1.0 - smoothstep(0.28, 0.5, a));
	c += edge_color.rgb * edge * 0.35;
	COLOR = vec4(c, max(a, edge * 0.35));
}
"""


func setup(world_half: float) -> void:
	half = world_half + CELL
	n = int(ceil(half * 2.0 / CELL))
	explored.resize(n * n)
	explored.fill(0)
	base.resize(n * n)
	base.fill(A_UNSEEN)
	out.resize(n * n)
	out.fill(A_UNSEEN)
	img = Image.create_from_data(n, n, false, Image.FORMAT_R8, out)
	tex = ImageTexture.create_from_image(img)
	texture = tex
	centered = false
	position = Vector2(-half, -half)
	scale = Vector2(CELL, CELL)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	material = mat
	z_index = 20


func make_material() -> ShaderMaterial:
	return material as ShaderMaterial


func _cell(p: Vector2) -> int:
	var cx := int((p.x + half) / CELL)
	var cy := int((p.y + half) / CELL)
	if cx < 0 or cy < 0 or cx >= n or cy >= n:
		return -1
	return cy * n + cx


func is_seen(p: Vector2) -> bool:
	var i := _cell(p)
	return i >= 0 and out[i] < 120


func is_explored(p: Vector2) -> bool:
	var i := _cell(p)
	return i >= 0 and explored[i] == 1


func reveal_all() -> void:
	explored.fill(1)
	base.fill(A_EXPLORED)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.12
	refresh()


func refresh() -> void:
	var g := Game.inst
	if g == null:
		return
	sources.clear()
	var eye := g.hive.vision_mult()
	for a in g.allies:
		if not a.dead:
			sources.append([a.position, a.vision()])
	for m in g.hive.all_modules():
		if m.level > 0:
			sources.append([m.position, m.vision() * eye])
	# start from the explored map (native copy, no per-cell script loop)
	out = base.duplicate()
	for s in sources:
		var c: Vector2 = s[0]
		var r: float = s[1]
		var rc := r / CELL
		var cx := (c.x + half) / CELL - 0.5
		var cy := (c.y + half) / CELL - 0.5
		var x0 := maxi(0, int(floor(cx - rc)))
		var x1 := mini(n - 1, int(ceil(cx + rc)))
		var y0 := maxi(0, int(floor(cy - rc)))
		var y1 := mini(n - 1, int(ceil(cy + rc)))
		var inner := rc * 0.7
		var rc2 := rc * rc
		for y in range(y0, y1 + 1):
			var dy := float(y) - cy
			var row := y * n
			for x in range(x0, x1 + 1):
				var dx := float(x) - cx
				var d2 := dx * dx + dy * dy
				if d2 > rc2:
					continue
				var i := row + x
				if explored[i] == 0:
					explored[i] = 1
					base[i] = A_EXPLORED
				var d := sqrt(d2)
				var a := 0
				if d > inner:
					a = int((d - inner) / (rc - inner) * A_EXPLORED)
				if a < out[i]:
					out[i] = a
	img.set_data(n, n, false, Image.FORMAT_R8, out)
	tex.update(img)
