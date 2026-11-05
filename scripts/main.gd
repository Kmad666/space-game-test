class_name Game
extends Node2D
## Melissae — tend the hive.
## Game manager: builds the world (hive, fields, guardians), schedules raids,
## owns the camera, fog of war and quality settings.

static var inst: Game
static var skip_title := false

const WORLD_HALF := 4200.0
const BOT_NAMES := ["CASTOR", "POLLUX", "ATALANTA", "ORION", "THESEUS", "AJAX", "PHOEBE", "DAEDALUS", "CASSIA", "LEDA",
	"ARGO", "HELIOS", "IOLE", "NESTOR", "OENONE", "PAN", "RHEA", "TALOS", "XANTHE", "ZETES"]

var rng := RandomNumberGenerator.new()
var world: Node2D
var layer_res: Node2D
var layer_ships: Node2D
var layer_enemies: Node2D
var layer_proj: Node2D
var fx: FX
var hive: Hive
var fog: FogOfWar
var player: Ship
var camera: Camera2D
var hud: HUD
var trails: TrailLayer
var overlay: Overlay

var allies: Array = []
var enemies: Array = []
var res_nodes: Array = []
var fields: Array = []
var globs: Array = []

var state := "title"
var time_played := 0.0
var shake := 0.0
var cam_zoom := 1.0
var target_zoom := 1.0
var over_t := 0.0
var bot_index := 0

# raids
var swarm_t := 85.0
var swarm_wave := 0
var swarm_dir := Vector2.RIGHT
var swarm_warned := false
var reaper_t := 230.0
var reaper_n := 0
var reaper_dir := Vector2.LEFT
var reaper_warned := false

# stats
var kills := 0
var stats_delivered := 0.0
var reapers_slain := 0
var reapers_escaped := 0
var stolen_pct := 0.0
var peak_drones := 0
var deaths := 0

# quality + test hooks
var low_quality := false
var quality_auto := true
var _fps_frames := 0
var _fps_time := 0.0
var _slow_windows := 0
var fps_now := 60.0
var autopilot := false
var bench := false
var _bench_frames := 0
var _bench_us := 0
var _bench_last := 0
var _bench_draws := 0.0
var _bench_prims := 0.0
var _bench_proc := 0.0
var shot_dir := ""
var shot_times := []
var title_shot := false
var real_t := 0.0


func _ready() -> void:
	inst = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	var uargs := OS.get_cmdline_user_args()
	if "--low" in uargs:
		low_quality = true
		quality_auto = false
	for a in uargs:
		if a == "--autotest":
			autopilot = true
			skip_title = true
		if a == "--bench":
			bench = true
			autopilot = true
			skip_title = true
		if a.begins_with("--shots="):
			shot_dir = a.substr(8)
		if a.begins_with("--at="):
			for v in a.substr(5).split(","):
				shot_times.append(float(v))
		if a == "--titleshot":
			title_shot = true
		if a.begins_with("--zoom="):
			target_zoom = float(a.substr(7))
			cam_zoom = target_zoom
		if a.begins_with("--seed="):
			rng.seed = int(a.substr(7))
	if shot_dir != "" and shot_times.is_empty():
		shot_times = [30.0, 120.0, 240.0]

	await Gfx.build(self)

	var bg := CanvasLayer.new()
	bg.layer = -10
	add_child(bg)
	bg.add_child(Backdrop.new())

	world = Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.add_child(WorldGrid.new())
	hive = Hive.new()
	world.add_child(hive)
	layer_res = _layer()
	layer_enemies = _layer()
	trails = TrailLayer.new()
	world.add_child(trails)
	layer_ships = _layer()
	layer_proj = _layer()
	fx = FX.new()
	world.add_child(fx)
	fog = FogOfWar.new()
	fog.setup(WORLD_HALF)
	world.add_child(fog)
	overlay = Overlay.new()
	world.add_child(overlay)

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()

	var hl := CanvasLayer.new()
	hl.layer = 10
	hl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hl)
	hud = HUD.new()
	hl.add_child(hud)

	player = Ship.new()
	player.is_player = true
	player.callsign = "YOU"
	player.position = Vector2(0, 230)
	player.rotation = PI * 0.5
	layer_ships.add_child(player)
	allies.append(player)
	var brood: HiveModule = hive.modules.brood
	spawn_drone(false, brood.position)
	spawn_drone(false, brood.position)
	spawn_drone(true, brood.position)
	_make_fields()
	swarm_dir = Vector2.RIGHT.rotated(rng.randf() * TAU)
	reaper_dir = Vector2.RIGHT.rotated(rng.randf() * TAU)
	camera.position = player.position
	fog.refresh()
	if low_quality:
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT

	if bench:
		_bench_setup()
	if "--starve" in uargs:
		hive.stores.nectar = 0.0
		hive.vitality = 0.04
	if skip_title:
		start_game()
	else:
		state = "title"
		get_tree().paused = true


func _layer() -> Node2D:
	var n := Node2D.new()
	world.add_child(n)
	return n


func _make_fields() -> void:
	var kinds := ["nectar", "ore", "ice"]
	kinds.shuffle()
	var a0 := rng.randf() * TAU
	for i in 3:
		var a := a0 + TAU * i / 3.0 + rng.randf_range(-0.2, 0.2)
		var f := Field.new()
		world.add_child(f)
		world.move_child(f, layer_res.get_index())
		f.setup(kinds[i], 1, Vector2.RIGHT.rotated(a) * rng.randf_range(1800.0, 2050.0), rng.randi())
		fields.append(f)
	for i in 3:
		var a := a0 + TAU * i / 3.0 + PI / 3.0 + rng.randf_range(-0.2, 0.2)
		var f := Field.new()
		world.add_child(f)
		world.move_child(f, layer_res.get_index())
		f.setup(kinds[(i + 2) % 3], 2, Vector2.RIGHT.rotated(a) * rng.randf_range(3050.0, 3350.0), rng.randi())
		fields.append(f)


func start_game() -> void:
	state = "playing"
	get_tree().paused = false
	hud.push_message("TEND THE HIVE — HAUL NECTAR, ORE AND ICE TO ITS ORGANS", Gfx.C_HIVE, 5.0)


# ---------------------------------------------------------------- spawning
func spawn_drone(guard: bool, at: Vector2) -> Ship:
	var s := Ship.new()
	s.role = "guard" if guard else "forager"
	s.callsign = BOT_NAMES[bot_index % BOT_NAMES.size()]
	bot_index += 1
	s.position = at + Vector2.RIGHT.rotated(rng.randf() * TAU) * 60.0
	s.rotation = rng.randf() * TAU
	layer_ships.add_child(s)
	allies.append(s)
	peak_drones = maxi(peak_drones, allies.size() - 1)
	if state == "playing":
		fx.ring(s.position, s.color, 60.0, 0.6, 2.5)
		fx.burst(s.position, Gfx.C_HIVE, 12, 90.0, 2.0, 0.6)
	return s


func spawn_enemy(kind: String, pos: Vector2, f) -> Enemy:
	var e := Enemy.new()
	e.setup(kind, pos, f, swarm_wave)
	layer_enemies.add_child(e)
	enemies.append(e)
	return e


func spawn_missile(pos: Vector2, vel: Vector2, target, dmg: float, col: Color, by_player: bool) -> void:
	var m := Missile.new()
	m.position = pos
	m.vel = vel
	m.speed = vel.length()
	m.target = target
	m.dmg = dmg
	m.col = col
	m.by_player = by_player
	layer_proj.add_child(m)


func spawn_bolt(pos: Vector2, vel: Vector2, dmg: float, col: Color, art: String, size: float) -> void:
	var b := Bolt.new()
	b.position = pos
	b.vel = vel
	b.dmg = dmg
	b.col = col
	b.art = art
	b.size = size
	layer_proj.add_child(b)


func spawn_glob(kind: String, amt: float, pos: Vector2) -> void:
	var gl := Glob.new()
	gl.setup(kind, amt, pos)
	layer_res.add_child(gl)
	globs.append(gl)


func spawn_swarm() -> void:
	swarm_wave += 1
	var center := swarm_dir * (WORLD_HALF - 120.0)
	var n := mini(4 + swarm_wave, 16)
	for i in n:
		spawn_enemy("swarm", center + Vector2(rng.randf_range(-260, 260), rng.randf_range(-260, 260)), null)
	hud.push_message("A SWARM DESCENDS FROM THE %s!" % compass(swarm_dir), Color(1, 0.55, 0.3), 3.5)
	shake = maxf(shake, 5.0)
	swarm_t = rng.randf_range(55.0, 75.0)
	swarm_dir = Vector2.RIGHT.rotated(rng.randf() * TAU)
	swarm_warned = false


func spawn_reaper() -> void:
	var r := Reaper.new()
	r.setup(reaper_dir * (WORLD_HALF + 80.0), reaper_n)
	layer_enemies.add_child(r)
	enemies.append(r)
	reaper_n += 1
	hud.push_message("THE REAPER HAS COME FOR THE STORES", Color(1, 0.4, 0.85), 4.0)
	shake = maxf(shake, 8.0)
	reaper_t = rng.randf_range(220.0, 270.0)
	reaper_dir = Vector2.RIGHT.rotated(rng.randf() * TAU)
	reaper_warned = false


func reaper_alive():
	for e in enemies:
		if e.kind == "reaper" and not e.dead:
			return e
	return null


static func compass(v: Vector2) -> String:
	var a := fposmod(rad_to_deg(atan2(v.y, v.x)) + 90.0, 360.0)
	return ["NORTH", "NORTHEAST", "EAST", "SOUTHEAST", "SOUTH", "SOUTHWEST", "WEST", "NORTHWEST"][int(round(a / 45.0)) % 8]


# ---------------------------------------------------------------- queries
func nearest_enemy(pos: Vector2, rng_max: float):
	var best = null
	var bd := rng_max
	for e in enemies:
		if e.dead:
			continue
		var d: float = pos.distance_to(e.position) - e.hit_radius
		if d < bd:
			bd = d
			best = e
	return best


func nearest_ally(pos: Vector2, rng_max: float):
	var best = null
	var bd := rng_max
	for a in allies:
		if a.dead:
			continue
		var d: float = pos.distance_to(a.position)
		if d < bd:
			bd = d
			best = a
	return best


# ---------------------------------------------------------------- events
func on_enemy_killed(_e, _by_player: bool) -> void:
	kills += 1


func on_drone_lost(s: Ship) -> void:
	allies.erase(s)
	hud.push_message("%s HAS FALLEN" % s.callsign, Color(1, 0.6, 0.5), 2.0)


func on_hive_grew(label: String, _tp: String, where: Vector2) -> void:
	hud.push_message("THE HIVE GREW: %s" % label, Gfx.C_HIVE, 3.0)
	fx.ring(where, Gfx.C_HIVE, 220.0, 1.0, 3.5)
	fx.burst(where, Gfx.C_HIVE, 30, 160.0, 2.4, 0.9)
	if player.on_hive_grew():
		hud.push_message("YOU MOLTED — %s FORM" % Ship.FORM_NAMES[player.form], Gfx.C_PLAYER, 3.5)
		fx.ring(player.position, Color.WHITE, 140.0, 0.9, 3.5)
		fx.burst(player.position, Gfx.C_PLAYER, 40, 220.0, 2.4, 0.9)


func on_field_discovered(f: Field) -> void:
	hud.push_message("DISCOVERED %s — %s" % [f.field_name.to_upper(), f.kind.to_upper()], Color(f.color, 1.0), 3.0)


func on_reaper_escaped(r: Reaper) -> void:
	reapers_escaped += 1
	stolen_pct += r.stolen_frac
	hud.push_message("THE REAPER ESCAPED WITH %d%% OF THE STORES" % int(round(r.stolen_frac * 100.0)), Color(1, 0.5, 0.8), 4.0)


func on_reaper_killed(_r: Reaper, total: float) -> void:
	reapers_slain += 1
	var msg := "THE REAPER IS SLAIN!"
	if total > 1.0:
		msg = "THE REAPER IS SLAIN! ITS HOARD SPILLS — %d TO RECLAIM" % int(total)
	hud.push_message(msg, Color(1, 0.8, 0.4), 4.5)


func hive_died() -> void:
	if state != "playing":
		return
	fx.explosion(hive.heart.position, Color(1, 0.5, 0.4), 5.0)
	shake = 20.0
	state = "dying"
	over_t = 3.0
	hud.push_message("THE HEART HAS WITHERED", Color(1, 0.3, 0.3), 4.0)


# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	if hud == null:
		return
	_track_fps(delta)
	real_t += delta
	if state == "playing" or state == "dying":
		time_played += delta
		if state == "playing":
			swarm_t -= delta
			if swarm_t < 12.0 and not swarm_warned:
				swarm_warned = true
				hud.push_message("SWARM SIGHTED TO THE %s" % compass(swarm_dir), Color(1, 0.6, 0.35), 3.0)
			if swarm_t <= 0.0:
				spawn_swarm()
			if reaper_alive() == null:
				reaper_t -= delta
				if reaper_t < 30.0 and not reaper_warned:
					reaper_warned = true
					hud.push_message("A REAPER STIRS IN THE DARK TO THE %s…" % compass(reaper_dir), Color(1, 0.45, 0.85), 4.0)
				if reaper_t <= 0.0:
					spawn_reaper()
		if state == "dying":
			over_t -= delta
			if over_t <= 0.0:
				state = "over"
				get_tree().paused = true
				if autopilot:
					print("GAME OVER reached at t=%d" % int(time_played))
		if autopilot and state == "playing":
			_autotest_tick()
	if bench:
		_bench_tick()
	if title_shot and real_t > 1.5:
		_snap("title")
		get_tree().quit()
	if shot_dir != "" and not shot_times.is_empty() and time_played >= shot_times[0]:
		_snap("t%03d" % int(shot_times[0]))
		shot_times.pop_front()
		if shot_times.is_empty():
			get_tree().quit()

	var focus := player.position if not player.dead else Vector2.ZERO
	camera.position = camera.position.lerp(focus, 1.0 - exp(-7.0 * delta))
	cam_zoom = lerpf(cam_zoom, target_zoom, 1.0 - exp(-6.0 * delta))
	camera.zoom = Vector2.ONE * cam_zoom
	if shake > 0.0 and state != "over" and state != "title":
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
		shake = maxf(0.0, shake - delta * 30.0)
	else:
		camera.offset = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if hud == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = clampf(target_zoom * 1.12, 0.3, 1.6)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = clampf(target_zoom / 1.12, 0.3, 1.3)
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k == KEY_F:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
		if k == KEY_Q:
			quality_auto = false
			set_low_quality(not low_quality)
			return
		if k == KEY_EQUAL or k == KEY_KP_ADD:
			target_zoom = clampf(target_zoom * 1.15, 0.3, 1.6)
			return
		if k == KEY_MINUS or k == KEY_KP_SUBTRACT:
			target_zoom = clampf(target_zoom / 1.15, 0.3, 1.3)
			return
		match state:
			"playing":
				if k == KEY_P or k == KEY_ESCAPE:
					state = "paused"
					get_tree().paused = true
			"paused":
				if k == KEY_P or k == KEY_ESCAPE:
					state = "playing"
					get_tree().paused = false
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		match state:
			"title":
				start_game()
			"paused":
				state = "playing"
				get_tree().paused = false
			"over":
				restart()


# ---------------------------------------------------------------- quality
func _track_fps(delta: float) -> void:
	_fps_frames += 1
	_fps_time += delta
	if _fps_time < 2.0:
		return
	fps_now = _fps_frames / _fps_time
	_fps_frames = 0
	_fps_time = 0.0
	if not quality_auto or low_quality or state != "playing" or time_played < 3.0:
		return
	if fps_now < 45.0:
		_slow_windows += 1
		if _slow_windows >= 2:
			set_low_quality(true)
			hud.push_message("LOW-SPEC MODE ON — press Q to switch back", Color(1, 0.85, 0.4), 4.0)
	else:
		_slow_windows = 0


func set_low_quality(on: bool) -> void:
	low_quality = on
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if on else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if not on:
		hud.push_message("HIGH QUALITY", Color(0.6, 0.95, 1.0), 1.5)
	elif not quality_auto:
		hud.push_message("LOW-SPEC MODE", Color(1, 0.85, 0.4), 1.5)


func restart() -> void:
	skip_title = true
	get_tree().paused = false
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- test hooks
func _autotest_tick() -> void:
	if Engine.get_process_frames() % 600 == 0:
		var s := hive.stores
		print("t=%d nec=%d ore=%d ice=%d vit=%.2f up=%.2f plan=%d drones=%d form=%d hp=%d enemies=%d swarm=%d reaper=%d/%d deaths=%d kills=%d parts=%d" % [
			int(time_played), int(s.nectar), int(s.ore), int(s.ice), hive.vitality, hive.upkeep(), hive.plan_i,
			allies.size() - 1, player.form, int(player.hp), enemies.size(), swarm_wave, reapers_slain, reapers_escaped,
			deaths, kills, fx.parts.size()])
		if OS.get_environment("DBG") != "":
			var st := {}
			for a in allies:
				var key: String = "%s:%s:%s" % [a.role, a.ai_state, a.ai_field.kind if a.ai_field != null else "-"]
				st[key] = st.get(key, 0) + 1
			var rp = reaper_alive()
			print("   states=", st, " pcargo=", player.cargo, " ppos=", player.position.round(), " globs=", globs.size(), " reaper=", rp.state if rp != null else "none", " nodes=", res_nodes.size(), " stall=", hive.build_stall)


func _bench_setup() -> void:
	fog.reveal_all()
	target_zoom = 0.6
	cam_zoom = 0.6
	for i in 6:
		spawn_drone(i % 3 == 0, hive.modules.brood.position)
	for i in 3:
		hive.spires[i].set_level(1)
	swarm_wave = 4
	swarm_dir = Vector2(1, 0.4).normalized()
	spawn_swarm()
	for e in enemies:
		if e.kind == "swarm":
			e.position = e.position * 0.35


func _bench_tick() -> void:
	_bench_frames += 1
	var now := Time.get_ticks_usec()
	if _bench_frames > 120:
		_bench_us += now - _bench_last
		_bench_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_bench_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_bench_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_bench_last = now
	if _bench_frames == 720:
		var n := 600.0
		print("BENCH frame_ms=%.2f fps=%.1f draws=%.0f prims=%.0f process_ms=%.2f enemies=%d allies=%d parts=%d" % [
			_bench_us / n / 1000.0, 1000000.0 / (_bench_us / n), _bench_draws / n, _bench_prims / n, _bench_proc / n,
			enemies.size(), allies.size(), fx.parts.size()])
		get_tree().quit()


func _snap(name: String) -> void:
	var dir := shot_dir if shot_dir != "" else "/tmp"
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("saved ", name)
