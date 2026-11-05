class_name TrailLayer
extends Node2D
## Every wing-wake and dart trail in the world, drawn with a handful of
## batched multiline commands (instead of one command per segment).

var _pg := PackedVector2Array()
var _cg := PackedColorArray()
var _cc := PackedColorArray()
var _mg := PackedVector2Array()
var _mcg := PackedColorArray()
var _mcc := PackedColorArray()


func _ready() -> void:
	z_index = 4


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var g := Game.inst
	if g == null:
		return
	_pg.clear()
	_cg.clear()
	_cc.clear()
	_mg.clear()
	_mcg.clear()
	_mcc.clear()
	var white := Color(1, 1, 1)
	for s in g.allies:
		if s.dead:
			continue
		var col: Color = s.color
		var tr: PackedVector2Array = s.trail
		var n: int = tr.size()
		for i in range(1, n):
			var a := float(i) / float(n)
			_pg.append(tr[i - 1])
			_pg.append(tr[i])
			_cg.append(Color(col, a * 0.1))
			_cc.append(Color(col.lerp(white, a * 0.3), a * 0.4))
	for m in g.layer_proj.get_children():
		if not (m is Missile):
			continue
		var tr: PackedVector2Array = m.trail
		var n := tr.size()
		var col: Color = m.col
		for i in range(1, n):
			var a := float(i) / float(n)
			_mg.append(tr[i - 1])
			_mg.append(tr[i])
			_mcg.append(Color(col, a * 0.12))
			_mcc.append(Color(col.lerp(white, 0.5), a * 0.6))
	if _pg.size() > 0:
		draw_multiline_colors(_pg, _cg, 7.0)
		draw_multiline_colors(_pg, _cc, 1.8)
	if _mg.size() > 0:
		draw_multiline_colors(_mg, _mcg, 5.0)
		draw_multiline_colors(_mg, _mcc, 1.4)
