class_name Game
extends Node2D
## Game manager: builds the world, runs raids, tracks credits and upgrades.

static var inst: Game
static var skip_title := false

const WORLD_HALF := 2200.0
const ASTEROID_COUNT := 62
const MAX_BOTS := 7
const UPGRADE_MAX := 8
const BOT_NAMES := ["CASTOR", "POLLUX", "ATALANTA", "ORION", "THESEUS", "AJAX", "PHOEBE", "DAEDALUS", "CASSIA", "LEDA"]
const BOT_COLORS := [Color(0.5, 1.0, 0.45), Color(1.0, 0.82, 0.35), Color(0.6, 0.65, 1.0), Color(0.4, 1.0, 0.82),
	Color(0.88, 1.0, 0.4), Color(0.85, 0.95, 1.0), Color(0.3, 0.75, 1.0), Color(0.95, 0.9, 0.6), Color(0.55, 0.9, 0.65)]
const UPGRADES := [
	{"key": "engine", "name": "ENGINES", "desc": "+9% speed"},
	{"key": "cargo", "name": "CARGO HOLD", "desc": "+40% capacity"},
	{"key": "drill", "name": "MINING LASER", "desc": "faster, longer reach"},
	{"key": "missiles", "name": "WARHEADS", "desc": "+25% damage"},
	{"key": "launcher", "name": "LAUNCHERS", "desc": "fire rate, +missiles"},
	{"key": "targeting", "name": "TARGETING", "desc": "+lock-on range"},
	{"key": "hull", "name": "HULL PLATING", "desc": "+30 hull, repair"},
]

var rng := RandomNumberGenerator.new()
var world: Node2D
var layer_ast: Node2D
var layer_ships: Node2D
var layer_enemies: Node2D
var layer_proj: Node2D
var fx: FX
var station: Station
var player: Ship
var camera: Camera2D
var hud: HUD

var allies: Array = []
var enemies: Array = []
var asteroids: Array = []
var respawn_queue: Array = []

var credits := 0.0
var state := "title"
var time_played := 0.0
var wave := 0
var wave_timer := 50.0
var raid_dir := Vector2.RIGHT
var kills := 0
var ore_delivered := 0.0
var shake := 0.0
var bot_index := 0
var cam_zoom := 1.0
var station_hit_t := 0.0
var over_t := 0.0
var autopilot := false
var low_quality := false
var quality_auto := true
var _fps_frames := 0
var _fps_time := 0.0
var _slow_windows := 0
var fps_now := 60.0
var trails: TrailLayer
var overlay: Overlay
var bench := false
var _bench_frames := 0
var _bench_us := 0
var _bench_last := 0
var _bench_draws := 0.0
var _bench_prims := 0.0
var _bench_proc := 0.0
var _autoguard := false
var shot_dir := ""
var shot_times := []
var title_shot := false
var kill_test := false
var real_t := 0.0


func _ready() -> void:
	inst = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	var uargs := OS.get_cmdline_user_args()
	if "--low" in uargs:
		low_quality = true
		quality_auto = false
	if "--autotest" in uargs:
		autopilot = true
		skip_title = true
		_autoguard = true
	for a in uargs:
		if a.begins_with("--shots="):
			shot_dir = a.substr(8)
			shot_times = [58.0, 112.0]
		if a == "--bench":
			bench = true
			autopilot = true
			skip_title = true
			_autoguard = true
		if a == "--titleshot":
			title_shot = true
		if a == "--killstation":
			kill_test = true

	await Gfx.build(self)

	var bg := CanvasLayer.new()
	bg.layer = -10
	add_child(bg)
	bg.add_child(Backdrop.new())

	world = Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.add_child(WorldGrid.new())
	layer_ast = _layer()
	station = Station.new()
	world.add_child(station)
	layer_enemies = _layer()
	layer_ships = _layer()
	trails = TrailLayer.new()
	world.add_child(trails)
	layer_proj = _layer()
	fx = FX.new()
	world.add_child(fx)
	overlay = Overlay.new()
	world.add_child(overlay)

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()

	player = _make_ship(true, "YOU", Color(0.3, 0.92, 1.0))
	player.position = Vector2(0, station.dock_radius() + 40.0)
	player.rotation = PI * 0.5
	player.guard = _autoguard
	for i in 3:
		spawn_bot()
	for i in ASTEROID_COUNT:
		spawn_asteroid()
	raid_dir = Vector2.RIGHT.rotated(rng.randf() * TAU)
	camera.position = player.position

	var hl := CanvasLayer.new()
	hl.layer = 10
	hl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hl)
	hud = HUD.new()
	hl.add_child(hud)
	if low_quality:
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT

	if bench:
		_bench_setup()
	if skip_title:
		start_game()
	else:
		state = "title"
		get_tree().paused = true


func _layer() -> Node2D:
	var n := Node2D.new()
	world.add_child(n)
	return n


func start_game() -> void:
	state = "playing"
	get_tree().paused = false
	hud.push_message("MINE ORE · HAUL IT TO AEGIS STATION", Color(0.5, 0.95, 1.0), 4.0)


# ---------------------------------------------------------------- spawning
func _make_ship(is_player: bool, callsign: String, col: Color) -> Ship:
	var s := Ship.new()
	s.is_player = is_player
	s.callsign = callsign
	s.color = col
	layer_ships.add_child(s)
	allies.append(s)
	return s


func spawn_bot() -> void:
	if allies.size() - 1 >= MAX_BOTS:
		return
	var s := _make_ship(false, BOT_NAMES[bot_index % BOT_NAMES.size()], BOT_COLORS[bot_index % BOT_COLORS.size()])
	s.guard = bot_index % 2 == 1
	bot_index += 1
	var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
	s.position = station.position + dir * (station.radius + 60.0)
	s.rotation = dir.angle()
	for i in station.level - 1:
		_bot_random_upgrade(s)
	if state == "playing":
		fx.ring(s.position, s.color, 70.0, 0.7, 3.0)


func _bot_random_upgrade(s: Ship) -> void:
	var opts := []
	for k in Ship.UPGRADE_KEYS:
		if s.levels[k] < UPGRADE_MAX:
			opts.append(k)
	if opts.is_empty():
		return
	var k: String = opts[rng.randi() % opts.size()]
	s.levels[k] += 1
	s.on_upgraded(k)


func spawn_asteroid() -> void:
	var a := Asteroid.new()
	var gold := rng.randf() < 0.14
	var r := rng.randf_range(22.0, 34.0) if gold else rng.randf_range(28.0, 58.0)
	a.setup(r, gold, rng)
	var pos := Vector2.ZERO
	for tries in 30:
		pos = Vector2(rng.randf_range(-WORLD_HALF + 120, WORLD_HALF - 120), rng.randf_range(-WORLD_HALF + 120, WORLD_HALF - 120))
		if pos.length() < 450.0:
			continue
		var ok := true
		for o in asteroids:
			if o.position.distance_to(pos) < o.radius + r + 70.0:
				ok = false
				break
		if ok:
			break
	a.position = pos
	layer_ast.add_child(a)
	asteroids.append(a)


func on_asteroid_depleted(a: Asteroid) -> void:
	asteroids.erase(a)
	respawn_queue.append(rng.randf_range(5.0, 10.0))


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


func spawn_bolt(pos: Vector2, vel: Vector2, dmg: float, col: Color, size: float) -> void:
	var b := Bolt.new()
	b.position = pos
	b.vel = vel
	b.dmg = dmg
	b.col = col
	b.size = size
	layer_proj.add_child(b)


func spawn_enemy(kind: String, pos: Vector2) -> void:
	var e := Enemy.new()
	e.setup(kind, wave, rng)
	e.position = pos
	e.rotation = (station.position - pos).angle()
	layer_enemies.add_child(e)
	enemies.append(e)


func spawn_wave() -> void:
	wave += 1
	var center := raid_dir * (WORLD_HALF - 150.0)
	var raiders := 2 + int(wave * 1.5)
	var bombers := (wave + 1) / 3
	var meteors := 1 + wave / 2
	for i in raiders:
		spawn_enemy("raider", center + Vector2(rng.randf_range(-220, 220), rng.randf_range(-220, 220)))
	for i in bombers:
		spawn_enemy("bomber", center * 1.04 + Vector2(rng.randf_range(-160, 160), rng.randf_range(-160, 160)))
	var mdir := raid_dir.rotated(rng.randf_range(1.3, TAU - 1.3))
	for i in meteors:
		spawn_enemy("meteor", mdir * (WORLD_HALF - 60.0) + Vector2(rng.randf_range(-350, 350), rng.randf_range(-350, 350)))
	hud.push_message("WAVE %d — RAID INBOUND!" % wave, Color(1, 0.35, 0.4), 3.5)
	shake = maxf(shake, 6.0)
	wave_timer = 38.0 + minf(wave * 1.5, 15.0)
	raid_dir = Vector2.RIGHT.rotated(rng.randf() * TAU)


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
func on_enemy_killed(e: Enemy, by_player: bool) -> void:
	kills += 1
	var r := e.reward if by_player else e.reward * 0.25
	credits += r
	if by_player:
		fx.text(e.position + Vector2(0, -20), "+%d CR" % int(r), Color(1, 0.85, 0.35), 16)


func on_station_level_up(lvl: int) -> void:
	hud.push_message("AEGIS STATION REACHED LEVEL %d" % lvl, Color(0.5, 0.95, 1.0), 3.5)
	var extras := []
	if lvl % 2 == 0 and lvl / 2 <= 6:
		extras.append("DEFENSE TURRET ONLINE")
	if allies.size() - 1 < MAX_BOTS:
		extras.append("NEW ESCORT LAUNCHED")
	if not extras.is_empty():
		hud.push_message(" · ".join(extras), Color(0.75, 0.9, 1.0), 3.0)
	spawn_bot()
	for a in allies:
		if not a.is_player:
			_bot_random_upgrade(a)
	fx.ring(station.position, Color(0.5, 0.95, 1.0), station.radius * 3.5, 1.2, 4.0)
	shake = maxf(shake, 5.0)


func station_destroyed() -> void:
	fx.explosion(station.position, Color(0.5, 0.9, 1.0), 4.0)
	fx.explosion(station.position, Color(1, 0.5, 0.3), 3.0)
	shake = 22.0
	state = "dying"
	over_t = 2.5


func upgrade_cost(key: String) -> int:
	return int(round(40.0 * pow(1.55, player.levels[key])))


func buy_upgrade(i: int) -> void:
	if state != "playing" or i < 0 or i >= UPGRADES.size():
		return
	var key: String = UPGRADES[i].key
	if player.levels[key] >= UPGRADE_MAX:
		return
	var cost := upgrade_cost(key)
	if credits < cost:
		hud.flash_button(i)
		return
	credits -= cost
	player.levels[key] += 1
	var tier_up := player.on_upgraded(key)
	fx.ring(player.position, player.color, 60.0, 0.5, 2.5)
	if tier_up:
		hud.push_message("SHIP UPGRADED — %s CLASS" % Ship.TIER_NAMES[player.tier], Color(0.45, 1.0, 1.0), 3.5)
		fx.ring(player.position, Color(1, 1, 1), 160.0, 0.9, 4.0)
		fx.burst(player.position, player.color, 50, 260.0, 2.5, 0.9)
		shake = maxf(shake, 6.0)
	else:
		hud.push_message("%s  MK %d" % [UPGRADES[i].name, player.levels[key]], Color(0.6, 0.95, 1.0), 1.5)


# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	if hud == null:
		return
	_track_fps(delta)
	if state == "playing" or state == "dying":
		time_played += delta
		station_hit_t = maxf(0.0, station_hit_t - delta)
		var rate := 1.0 if enemies.is_empty() else 0.35
		if state == "playing":
			wave_timer -= delta * rate
			if wave_timer <= 0.0:
				spawn_wave()
		var i := 0
		while i < respawn_queue.size():
			respawn_queue[i] -= delta
			if respawn_queue[i] <= 0.0:
				respawn_queue.remove_at(i)
				spawn_asteroid()
			else:
				i += 1
		if state == "dying":
			over_t -= delta
			if over_t <= 0.0:
				state = "over"
				get_tree().paused = true

	if autopilot and state == "playing":
		_autotest_tick()
	if bench:
		_bench_tick()
	real_t += delta
	if title_shot and real_t > 1.5:
		_snap("title")
		get_tree().quit()
	if shot_dir != "" and not shot_times.is_empty() and time_played >= shot_times[0]:
		_snap("t%03d" % int(shot_times[0]))
		shot_times.pop_front()
		if shot_times.is_empty():
			get_tree().quit()
	if kill_test and time_played > 6.0 and not station.dead:
		station.damage(99999.0)
	if kill_test and state == "over" and real_t > 12.0:
		_snap("over")
		get_tree().quit()

	var focus := player.position if not player.dead else station.position
	camera.position = camera.position.lerp(focus, 1.0 - exp(-7.0 * delta))
	var tz := 1.0 - 0.07 * player.tier
	cam_zoom = lerpf(cam_zoom, tz, 1.0 - exp(-2.0 * delta))
	camera.zoom = Vector2.ONE * cam_zoom
	if shake > 0.0 and state != "over" and state != "title":
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
		shake = maxf(0.0, shake - delta * 30.0)
	else:
		camera.offset = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if hud == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k == KEY_Q:
			quality_auto = false
			set_low_quality(not low_quality)
			return
		if k == KEY_F:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
		match state:
			"playing":
				if k == KEY_P or k == KEY_ESCAPE:
					state = "paused"
					get_tree().paused = true
				elif k >= KEY_1 and k <= KEY_7:
					buy_upgrade(k - KEY_1)
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


func _autotest_tick() -> void:
	var best := -1
	var bc := INF
	for i in UPGRADES.size():
		var k: String = UPGRADES[i].key
		if player.levels[k] < UPGRADE_MAX and upgrade_cost(k) < bc:
			bc = upgrade_cost(k)
			best = i
	if best >= 0 and credits >= bc:
		buy_upgrade(best)
	if Engine.get_process_frames() % 600 == 0:
		print("t=%d wave=%d enemies=%d st_lv=%d st_hp=%d cr=%d tier=%d kills=%d ore=%d allies=%d ast=%d parts=%d" % [
			int(time_played), wave, enemies.size(), station.level, int(station.hp), int(credits), player.tier, kills,
			int(ore_delivered), allies.size(), asteroids.size(), fx.parts.size()])


func _snap(name: String) -> void:
	var dir := shot_dir if shot_dir != "" else "/tmp"
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("saved ", name)


func _bench_setup() -> void:
	for i in 4:
		station.deposit(station.need())
	credits = 600.0
	wave = 4
	raid_dir = Vector2.RIGHT
	spawn_wave()
	spawn_wave()
	for e in enemies:
		e.position *= 0.3
	player.position = Vector2(350, 0)


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
		print("BENCH frame_ms=%.2f fps=%.1f draws=%.0f prims=%.0f process_ms=%.2f enemies=%d parts=%d" % [
			_bench_us / n / 1000.0, 1000000.0 / (_bench_us / n), _bench_draws / n, _bench_prims / n, _bench_proc / n,
			enemies.size(), fx.parts.size()])
		get_tree().quit()
