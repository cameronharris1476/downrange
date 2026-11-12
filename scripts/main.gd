extends Node3D

var catalog: Dictionary = {}
var company: Company
var pad: Pad
var rocket: RocketView
var board: Board
var camera: Camera3D
var sun: DirectionalLight3D
var player: AudioStreamPlayer
var report: Dictionary = {}
var yaw := 0.62
var elev := 0.34
var dist := 28.0
var dist_target := 28.0
var user_dist := false
var dragging := false
var shake := 0.0
var shot := false
var shot_phase := 0
var shot_time := 0.0
var shot_busy := false
var _log_open := false


func _ready() -> void:
	shot = OS.get_cmdline_user_args().has("--shot")
	_log("Downrange boot shot=%s" % shot)
	catalog = Catalog.load_default()
	company = Company.new()
	company.setup(catalog, not shot, not shot)
	if shot:
		company.buy_starter()
	_world()
	var tex := TexLib.new()
	tex.setup(load("res://shaders/surface.gdshader"))
	pad = Pad.new()
	add_child(pad)
	pad.build(tex)
	for line in tex.log_lines:
		_log(line)
	rocket = RocketView.new()
	rocket.hull_shader = load("res://shaders/hull.gdshader")
	rocket.plume_shader = load("res://shaders/plume.gdshader")
	add_child(rocket)
	rocket.rebuild(catalog, company.loadout)
	pad.set_clearance(rocket.radius, rocket.cabin_y)
	pad.apply_upgrades(company.upgrades)
	_audio()
	var layer := CanvasLayer.new()
	add_child(layer)
	board = Board.new()
	layer.add_child(board)
	board.build(company)
	board.launch_pressed.connect(_on_launch)
	board.returned_to_pad.connect(_on_return)
	_frame_rocket()
	_apply_camera(Vector3(0, maxf(rocket.stack_length * 0.38, 1.5), 0))


func _process(delta: float) -> void:
	var status := {}
	if rocket.playing:
		status = rocket.advance(delta)
		pad.set_retracted(float(status["retract"]))
		_telemetry(status)
		if rocket.done:
			_finish_flight()
	elif shake > 0.0:
		shake = maxf(shake - delta, 0.0)
	_apply_camera(_focus(status))
	_mix(status)
	if shot and not shot_busy:
		shot_time += delta
		_shot_tick()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			if button.pressed and _over_ui():
				return
			dragging = button.pressed
			return
		if button.pressed and not _over_ui():
			if button.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom(0.9)
			elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.11)
	elif event is InputEventMouseMotion and dragging:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * 0.005
		elev = clampf(elev - motion.relative.y * 0.0035, deg_to_rad(6.0), deg_to_rad(58.0))


func _on_launch() -> void:
	if rocket.playing or board.debrief_panel.visible:
		return
	var result: Dictionary = company.commit_launch()
	if bool(result.get("blocked", false)):
		board.refresh()
		return
	report = result
	board.show_flight()
	user_dist = false
	dist_target = clampf(rocket.stack_length * 0.9 + 12.0, 18.0, 48.0)
	rocket.begin(result["sim"])
	if result["sim"]["samples"].is_empty():
		shake = 0.55
		_finish_flight()
		return
	if player.stream and not company.muted:
		player.play()


func _finish_flight() -> void:
	if player.playing:
		player.stop()
	pad.set_retracted(1.0)
	board.show_debrief(report)


func _on_return() -> void:
	rocket.rebuild(catalog, company.loadout)
	pad.set_clearance(rocket.radius, rocket.cabin_y)
	pad.apply_upgrades(company.upgrades)
	pad.set_retracted(0.0)
	user_dist = false
	_frame_rocket()
	board.show_pad()


func _telemetry(status: Dictionary) -> void:
	var hold := float(status["hold"])
	var line := ""
	if hold > 0.05:
		line = "HOLD    T-%.1f s" % hold
	else:
		var altitude := float(status["altitude"])
		var downrange := float(status["downrange"])
		var alt_text := "%d m" % int(altitude) if altitude < 1000.0 else "%.1f km" % (altitude / 1000.0)
		var down_text := "%d m" % int(downrange) if absf(downrange) < 1000.0 else "%.1f km" % (downrange / 1000.0)
		line = "T+%.0f s    ALT %s    DOWNRANGE %s    PITCH %d°    THR %d%%" % [
			float(status["sim_t"]), alt_text, down_text, int(status["pitch"]), int(float(status["throttle"]) * 100.0),
		]
	board.set_telemetry(line, status["events"], bool(status["coasting"]))


func _focus(status: Dictionary) -> Vector3:
	if rocket.playing or board.debrief_panel.visible:
		return rocket.focus_position()
	return Vector3(0, maxf(rocket.stack_length * 0.38, 1.6), 0)


func _frame_rocket() -> void:
	dist_target = clampf(rocket.stack_length * 1.35 + 14.0, 18.0, 78.0)
	dist = dist_target


func _offset() -> Vector3:
	var planar := cos(elev)
	return Vector3(sin(yaw) * planar, sin(elev), cos(yaw) * planar) * dist


func _apply_camera(focus: Vector3) -> void:
	if rocket.playing and not user_dist:
		dist = lerpf(dist, dist_target, 0.04)
	var pos := focus + _offset()
	if not rocket.playing and pos.y < 1.5:
		pos.y = 1.5
	if shake > 0.0:
		pos += Vector3(sin(shake * 90.0), cos(shake * 70.0), 0.0) * 0.08 * shake
	camera.global_position = pos
	if pos.distance_to(focus) > 0.05:
		camera.look_at(focus, Vector3.UP)


func _zoom(factor: float) -> void:
	user_dist = true
	dist = clampf(dist * factor, 6.0, 180.0)
	dist_target = dist


func _over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _mix(status: Dictionary) -> void:
	var throttle := float(status.get("throttle", 0.0)) if rocket.playing else 0.0
	if company.muted or throttle < 0.02 or player.stream == null:
		player.volume_db = -80.0
		return
	player.volume_db = linear_to_db(maxf(throttle, 0.001)) - 8.0
	if not player.playing:
		player.play()


func _world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var hdr_path := "res://assets/third_party/polyhaven/hdri/kloofendal_43d_clear_puresky_2k.hdr"
	var hdr := load(hdr_path)
	var sun_dir := Vector3(-0.42, 0.74, 0.52).normalized()
	if hdr:
		var panorama := PanoramaSkyMaterial.new()
		panorama.panorama = hdr
		sky.sky_material = panorama
		var image := Image.new()
		var err := image.load(ProjectSettings.globalize_path(hdr_path))
		if err == OK:
			sun_dir = _brightest_dir(image)
		else:
			_log("hdr scan failed %s" % err)
	else:
		var fallback := ProceduralSkyMaterial.new()
		fallback.sky_top_color = Color(0.16, 0.36, 0.68)
		fallback.sky_horizon_color = Color(0.74, 0.8, 0.84)
		fallback.ground_horizon_color = Color(0.45, 0.4, 0.34)
		fallback.ground_bottom_color = Color(0.08, 0.07, 0.06)
		fallback.sun_angle_max = 12.0
		sky.sky_material = fallback
		_log("hdr missing, procedural sky")
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.36
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.96
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.15
	env.ssr_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.18
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 2.4
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.00085
	env.fog_light_color = Color(0.64, 0.74, 0.82)
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.06
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 280.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.8
	sun.light_angular_distance = 0.35
	add_child(sun)
	_aim(sun, sun_dir)
	_log("sun dir %s" % sun_dir)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.74, 0.86)
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	add_child(fill)
	_aim(fill, Vector3(-0.15, 0.45, -0.88).normalized())

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 36.0
	camera.near = 0.15
	camera.far = 800000.0
	add_child(camera)


func _aim(light: DirectionalLight3D, direction: Vector3) -> void:
	var dir := direction.normalized()
	light.position = dir * 50.0
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	light.look_at(light.position - dir, up)


func _brightest_dir(image: Image) -> Vector3:
	var width := image.get_width()
	var height := image.get_height()
	var best := -1.0
	var bu := 0
	var bv := 0
	for y in range(0, height, 4):
		for x in range(0, width, 4):
			var color := image.get_pixel(x, y)
			var luma := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			if luma > best:
				best = luma
				bu = x
				bv = y
	var x0 := maxi(bu - 6, 0)
	var y0 := maxi(bv - 6, 0)
	var x1 := mini(bu + 7, width)
	var y1 := mini(bv + 7, height)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var color := image.get_pixel(x, y)
			var luma := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			if luma > best:
				best = luma
				bu = x
				bv = y
	var u := (float(bu) + 0.5) / float(width)
	var v := (float(bv) + 0.5) / float(height)
	var phi := (u - 0.5) * TAU
	var theta := v * PI
	var dir := Vector3(sin(theta) * sin(phi), cos(theta), sin(theta) * cos(phi)).normalized()
	_log("sun pixel %d,%d uv %.3f,%.3f lum %.2f" % [bu, bv, u, v, best])
	return dir


func _audio() -> void:
	player = AudioStreamPlayer.new()
	var stream = load("res://assets/audio/rumble.wav")
	if stream:
		stream = stream.duplicate()
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		player.stream = stream
	player.volume_db = -80.0
	add_child(player)


func _shot_tick() -> void:
	if shot_phase == 0 and shot_time > 2.2:
		shot_busy = true
		_shot_spar()
	elif shot_phase == 1 and shot_time > 1.8:
		shot_busy = true
		_shot_keel()
	elif shot_phase == 2 and shot_time > 1.6:
		shot_busy = true
		_shot_yard()
	elif shot_phase == 3 and shot_time > 4.6:
		shot_busy = true
		_shot_liftoff()


func _shot_spar() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_png("pad_spar.png")
	_log("board %s left %s launch %s" % [board.size, board.left_panel.size, board.launch_button.position])
	for line in pad.log_bounds():
		_log(line)
	company.cash += 140000000
	company.orbital_successes = 1
	for id in ["keel", "gg620", "gimbal", "kick", "fairing", "grid_al", "legs"]:
		company.buy_part(id)
	company.set_slot("core", "keel")
	company.set_slot("engine", "gg620")
	company.set_slot("cabin", "auto")
	company.set_slot("aero", "fins")
	company.set_slot("gimbal", "gimbal")
	company.set_slot("upper", "kick")
	company.set_slot("fairing", "fairing")
	company.set_slot("booster", "")
	company.set_slot("legs", "")
	company.set_contract("cubesat")
	for id in ["weld_cell", "reuse_program", "payload_office", "second_pad", "station"]:
		var bought := company.buy_upgrade(id)
		_log("upgrade %s %s cash %d" % [id, bought, company.cash])
	_sync_rocket()
	user_dist = true
	dist = 46.0
	yaw = 0.85
	elev = 0.3
	board.refresh()
	shot_phase = 1
	shot_time = 0.0
	shot_busy = false


func _shot_keel() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_png("pad_keel.png")
	board.visible = false
	camera.fov = 68.0
	yaw = 0.05
	elev = 0.95
	dist = 150.0
	shot_phase = 2
	shot_time = 0.0
	shot_busy = false


func _shot_yard() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_png("pad_yard.png")
	board.visible = true
	camera.fov = 36.0
	yaw = 0.62
	elev = 0.3
	for slot in ["booster", "upper", "gimbal", "legs", "fairing"]:
		company.set_slot(slot, "")
	company.set_slot("core", "spar")
	company.set_slot("engine", "ps80")
	company.set_slot("cabin", "auto")
	company.set_slot("aero", "fins")
	company.set_contract("uni")
	_sync_rocket()
	user_dist = false
	_frame_rocket()
	dist = clampf(rocket.stack_length * 1.1 + 16.0, 20.0, 36.0)
	dist_target = dist
	yaw = 0.78
	elev = 0.26
	board.refresh()
	shot_phase = 3
	shot_time = 0.0
	shot_busy = false
	_on_launch()


func _shot_liftoff() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_png("liftoff.png")
	_log("shot done")
	get_tree().quit()


func _sync_rocket() -> void:
	rocket.rebuild(catalog, company.loadout)
	pad.set_clearance(rocket.radius, rocket.cabin_y)
	pad.apply_upgrades(company.upgrades)


func _png(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://shots/" + file_name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var err := image.save_png(path)
	_log("saved %s %dx%d err %s" % [file_name, image.get_width(), image.get_height(), err])


func _log(line: String) -> void:
	print(line)
	var dir := ProjectSettings.globalize_path("res://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var mode := FileAccess.WRITE if not _log_open else FileAccess.READ_WRITE
	var file := FileAccess.open(dir + "/log.txt", mode)
	_log_open = true
	if file == null:
		return
	if mode == FileAccess.READ_WRITE:
		file.seek_end()
	file.store_line(line)
