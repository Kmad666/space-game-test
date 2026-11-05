extends Node2D
func _ready() -> void:
	var f := FogOfWar.new()
	var n := 8
	f.n = n
	f.half = 300.0
	var data := PackedByteArray(); data.resize(n * n)
	for i in n * n:
		data[i] = 255 if (i % 3 == 0) else 0
	f.img = Image.create_from_data(n, n, false, Image.FORMAT_R8, data)
	f.tex = ImageTexture.create_from_image(f.img)
	f.texture = f.tex
	f.centered = false
	f.position = Vector2(100, 50)
	f.scale = Vector2(60, 60)
	var mat := ShaderMaterial.new(); var sh := Shader.new(); sh.code = FogOfWar.SHADER; mat.shader = sh
	f.material = mat
	f.set_process(false)
	var bg := ColorRect.new(); bg.color = Color(0.2, 0.6, 0.3); bg.size = Vector2(800, 600)
	add_child(bg)
	add_child(f)
	var s2 := Sprite2D.new(); s2.texture = f.tex; s2.centered = false; s2.position = Vector2(700, 50); s2.scale = Vector2(20, 20)
	add_child(s2)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
	get_tree().quit()
