class_name TrailLayer
extends Node2D
## Draws every engine trail and missile smoke trail in the world with a handful
## of batched multiline commands (instead of one command per segment).

var _pts_glow := PackedVector2Array()
var _col_glow := PackedColorArray()
var _pts_core := PackedVector2Array()
var _col_core := PackedColorArray()
var _mpts_glow := PackedVector2Array()
var _mcol_glow := PackedColorArray()
var _mpts_core := PackedVector2Array()
var _mcol_core := PackedColorArray()


func _ready() -> void:
	z_index = 4


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var g := Game.inst
	if g == null:
		return
	_pts_glow.clear()
	_col_glow.clear()
	_pts_core.clear()
	_col_core.clear()
	_mpts_glow.clear()
	_mcol_glow.clear()
	_mpts_core.clear()
	_mcol_core.clear()
	var white := Color(1, 1, 1)
	for s in g.allies:
		if s.dead:
			continue
		var col: Color = s.color
		for tr in s.trails:
			var n: int = tr.size()
			for i in range(1, n):
				var a := float(i) / float(n)
				_pts_glow.append(tr[i - 1])
				_pts_glow.append(tr[i])
				_col_glow.append(Color(col, a * 0.13))
				_pts_core.append(tr[i - 1])
				_pts_core.append(tr[i])
				_col_core.append(Color(col.lerp(white, a * 0.35), a * 0.6))
	for m in g.layer_proj.get_children():
		if not (m is Missile):
			continue
		var tr: PackedVector2Array = m.trail
		var n := tr.size()
		var col: Color = m.col
		for i in range(1, n):
			var a := float(i) / float(n)
			_mpts_glow.append(tr[i - 1])
			_mpts_glow.append(tr[i])
			_mcol_glow.append(Color(col, a * 0.12))
			_mpts_core.append(tr[i - 1])
			_mpts_core.append(tr[i])
			_mcol_core.append(Color(col.lerp(white, 0.5), a * 0.6))
	if _pts_glow.size() > 0:
		draw_multiline_colors(_pts_glow, _col_glow, 8.0)
		draw_multiline_colors(_pts_core, _col_core, 2.5)
	if _mpts_glow.size() > 0:
		draw_multiline_colors(_mpts_glow, _mcol_glow, 6.0)
		draw_multiline_colors(_mpts_core, _mcol_core, 1.6)
