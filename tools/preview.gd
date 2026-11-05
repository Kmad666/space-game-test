extends Node2D
## Dev tool: bakes the atlas and lays every sprite out on a sheet, then saves a PNG.

func _ready() -> void:
	await Gfx.build(self)
	var names: Array = Gfx.regions.keys()
	var filt: String = OS.get_environment("PREVIEW_FILTER")
	var sc := float(OS.get_environment("PREVIEW_SCALE")) if OS.get_environment("PREVIEW_SCALE") != "" else 1.0
	var x := 20.0
	var y := 20.0
	var row := 0.0
	var W := get_viewport_rect().size.x
	for n in names:
		if filt != "":
			var ok := false
			for f in filt.split(","):
				if n.begins_with(f):
					ok = true
			if not ok:
				continue
		var r: Rect2 = Gfx.regions[n]
		var sz := r.size * sc
		if x + sz.x > W - 10:
			x = 20.0
			y += row + 22.0
			row = 0.0
		var s := Gfx.sprite(n)
		s.scale = Vector2.ONE * sc
		s.position = Vector2(x, y) + sz * 0.5 - Gfx.centers[n] * sc
		add_child(s)
		var l := Label.new()
		l.text = n
		l.position = Vector2(x, y + sz.y)
		l.add_theme_font_size_override("font_size", 10)
		add_child(l)
		x += sz.x + 12.0
		row = maxf(row, sz.y)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("PREVIEW_OUT"))
	get_tree().quit()
