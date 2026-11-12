extends Node3D
class_name RocketView

var hull_shader: Shader
var plume_shader: Shader
var stack_length := 8.0
var radius := 0.35
var cabin_y := 6.0
var playing := false
var done := false
var hold := 0.0
var sim_t := 0.0
var coasting := false
var outcome := ""

var _stack: Node3D
var _booster: Node3D
var _upper: Node3D
var _srb_nodes: Array[Node3D] = []
var _fairing: Node3D
var _core_plume: Node3D
var _kick_plume: Node3D
var _core_light: OmniLight3D
var _samples: Array = []
var _events: PackedStringArray = PackedStringArray()
var _debris: Array = []
var _srb_live := false
var _booster_live := false
var _fairing_live := false
var _coast_for := 0.0
var _family := "storable"


func rebuild(catalog: Dictionary, loadout: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_debris.clear()
	_srb_nodes.clear()
	_fairing = null
	_core_plume = null
	_kick_plume = null
	playing = false
	done = false
	hold = 0.0
	coasting = false
	stack_length = 8.0
	radius = 0.35
	cabin_y = 5.0
	var parts: Dictionary = catalog["by_id"]
	var core_id := str(loadout.get("core", ""))
	if core_id == "" or not parts.has(core_id):
		return
	var core: Dictionary = parts[core_id]
	var engine: Dictionary = parts[str(loadout.get("engine", ""))] if parts.has(str(loadout.get("engine", ""))) else {}
	var booster: Dictionary = parts[str(loadout.get("booster", ""))] if str(loadout.get("booster", "")) != "" else {}
	var upper: Dictionary = parts[str(loadout.get("upper", ""))] if str(loadout.get("upper", "")) != "" else {}
	var cabin: Dictionary = parts[str(loadout.get("cabin", ""))] if str(loadout.get("cabin", "")) != "" else {}
	var aero: Dictionary = parts[str(loadout.get("aero", ""))] if str(loadout.get("aero", "")) != "" else {}
	var gimbal := str(loadout.get("gimbal", "")) != ""
	var legs := str(loadout.get("legs", "")) != ""
	var fairing := str(loadout.get("fairing", "")) != ""
	radius = float(core["diameter"]) * 0.5
	_family = str(engine.get("family", "storable"))
	var thrust := float(engine.get("thrust_sl", 155000.0))
	var bell_h := clampf(0.42 + thrust / 1400000.0, 0.55, 2.6)
	var exit_r := clampf(radius * 0.34 * pow(thrust / 155000.0, 0.22), radius * 0.28, radius * 0.72)
	var throat_r := exit_r * 0.42
	var tank_h := float(core["length"])
	var y := 0.0

	_stack = Node3D.new()
	_stack.name = "Stack"
	_stack.position = Vector3(0, 0.2, 0)
	add_child(_stack)
	_booster = Node3D.new()
	_booster.name = "Booster"
	_stack.add_child(_booster)
	_upper = Node3D.new()
	_upper.name = "Upper"
	_stack.add_child(_upper)

	var copper := _metal(Color(0.72, 0.40, 0.22), 0.85, 0.32)
	var graphite := _metal(Color(0.16, 0.16, 0.17), 0.55, 0.42)
	var fin_mat := _metal(Color(0.22, 0.23, 0.24), 0.7, 0.34)
	var frost := 0.85 if _family == "methalox" else (0.12 if _family == "kerolox" else 0.0)
	var soot := 0.08 if _family == "methalox" else (0.82 if _family == "kerolox" else 0.15)
	var skirt_end := bell_h + maxf(radius * 0.7, 0.45)
	var band_0 := bell_h + tank_h * 0.22
	var band_1 := band_0 + clampf(radius * 0.36, 0.16, 0.46)
	var band_2 := -1.0
	var band_3 := -1.0
	if float(core["length"]) >= 20.0:
		band_2 = bell_h + tank_h * 0.62
		band_3 = band_2 + 0.12
	var hull := _hull(frost, soot, skirt_end, band_0, band_1, band_2, band_3, -1.0, -1.0)

	var bell := PackedVector2Array()
	for i in 10:
		var t := float(i) / 9.0
		bell.append(Vector2(lerpf(exit_r, throat_r, pow(t, 0.7)), bell_h * t))
	MeshUtil.add_mesh(_booster, MeshUtil.lathe(bell, 48), copper, "Bell")
	if gimbal:
		var ring := PackedVector2Array()
		var joint_y := bell_h * 0.72
		for i in 14:
			var a := TAU * float(i) / 13.0
			ring.append(Vector2(throat_r + 0.05 + cos(a) * 0.045, joint_y + sin(a) * 0.045))
		MeshUtil.add_mesh(_booster, MeshUtil.lathe(ring, 28), copper, "Gimbal")

	var tank := PackedVector2Array()
	tank.append(Vector2(radius * 0.78, bell_h))
	tank.append(Vector2(radius * 0.94, bell_h + 0.18))
	tank.append(Vector2(radius, bell_h + 0.42))
	tank.append(Vector2(radius, bell_h + tank_h - 0.06))
	tank.append(Vector2(radius * 0.97, bell_h + tank_h))
	MeshUtil.add_mesh(_booster, MeshUtil.lathe(tank, 64), hull, "Core")
	_cap(_booster, radius * 0.97, bell_h + tank_h, hull)
	y = bell_h + tank_h

	var control := str(aero.get("control", ""))
	if control == "fins":
		_place_fins(_booster, radius, bell_h + 0.15, maxf(radius * 1.15, 0.55), maxf(tank_h * 0.22, 0.7), fin_mat)
	elif control == "grid":
		_place_grids(_booster, radius, bell_h + maxf(tank_h * 0.16, 0.8), maxf(radius * 0.85, 0.42), fin_mat)
	elif control == "flaps":
		_place_flaps(_booster, radius, bell_h + tank_h * 0.48, maxf(radius * 0.9, 0.5), fin_mat)
	if legs:
		_place_legs(_booster, radius, bell_h + 0.35, graphite)

	if not booster.is_empty():
		var count := int(booster["count"])
		var srb_r := float(booster["diameter"]) * 0.5
		var srb_h := tank_h * 0.78
		for n in count:
			var angle := 0.0 if count == 1 else PI * float(n)
			var srb := _build_srb(srb_r, srb_h)
			var mount := Node3D.new()
			mount.name = "SRB"
			mount.position = Vector3(cos(angle) * (radius + srb_r + 0.08), 0.0, sin(angle) * (radius + srb_r + 0.08))
			mount.add_child(srb)
			_booster.add_child(mount)
			_srb_nodes.append(mount)

	_core_plume = _plume(_booster, exit_r * 0.55, _plume_color(), 4.2)
	_core_plume.position = Vector3(0, 0.02, 0)
	_core_light = OmniLight3D.new()
	_core_light.light_color = _plume_color()
	_core_light.omni_range = 26.0
	_core_light.shadow_enabled = false
	_core_light.light_energy = 0.0
	_core_plume.add_child(_core_light)

	_upper.position = Vector3(0, y, 0)
	var cursor := 0.0
	if not upper.is_empty():
		var kick_r := minf(float(upper["diameter"]) * 0.5, radius)
		var kick_h := float(upper["length"])
		var kick_hull := _hull(0.0, 0.2, 0.35, -1, -1, -1, -1, -1, -1)
		var kick := PackedVector2Array()
		kick.append(Vector2(kick_r * 0.45, 0.0))
		kick.append(Vector2(kick_r * 0.72, 0.22))
		kick.append(Vector2(kick_r, 0.55))
		kick.append(Vector2(kick_r, kick_h - 0.08))
		kick.append(Vector2(kick_r * 0.92, kick_h))
		MeshUtil.add_mesh(_upper, MeshUtil.lathe(kick, 40), kick_hull, "Kick")
		_cap(_upper, kick_r * 0.92, kick_h, kick_hull)
		if radius - kick_r > 0.05:
			var step := PackedVector2Array()
			step.append(Vector2(radius * 0.96, -0.28))
			step.append(Vector2(kick_r * 1.02, 0.0))
			MeshUtil.add_mesh(_upper, MeshUtil.lathe(step, 40), graphite, "Interstage")
		_kick_plume = _plume(_upper, kick_r * 0.28, Color(0.95, 0.72, 0.28), 2.4)
		_kick_plume.position = Vector3(0, 0.02, 0)
		cursor = kick_h
	cabin_y = y + cursor
	if not cabin.is_empty():
		var crew := bool(cabin.get("crew", false))
		var cabin_h := 2.15 if crew else 0.95
		var cabin_r := radius * (0.92 if crew else 0.72)
		var window_0 := 0.72 if crew else -1.0
		var window_1 := 1.05 if crew else -1.0
		var cabin_hull := _hull(frost * 0.25, 0.0, -1, -1, -1, -1, -1, window_0, window_1)
		MeshUtil.add_mesh(_upper, MeshUtil.lathe(_capsule(cabin_r, cabin_h, 0.62 if crew else 0.45), 40), cabin_hull, "Cabin")
		cursor += cabin_h
	if fairing:
		var fair_r := maxf(radius * 0.98, 0.55)
		var fair_h := maxf(fair_r * 2.4, 2.4)
		var fair_hull := _hull(0.0, 0.0, -1, fair_h * 0.18, fair_h * 0.18 + 0.1, -1, -1, -1, -1)
		var shell := Node3D.new()
		shell.name = "Fairing"
		shell.position = Vector3(0, cursor - 0.2, 0)
		MeshUtil.add_mesh(shell, MeshUtil.lathe(_hammerhead(fair_r, fair_h), 48), fair_hull, "Shell")
		_upper.add_child(shell)
		_fairing = shell
		cursor += fair_h * 0.92
	elif cabin.is_empty():
		var nose_h := radius * 1.6
		MeshUtil.add_mesh(_booster, MeshUtil.lathe(_ogive(radius, nose_h, bell_h + tank_h - 0.02), 40), hull, "Nose")
		cursor = maxf(cursor, nose_h)
	stack_length = y + cursor
	_set_plumes(0.0, false, false)


func begin(sim: Dictionary) -> void:
	_samples = sim["samples"]
	_events = sim["events"]
	outcome = str(sim["outcome"])
	sim_t = 0.0
	hold = 3.0
	coasting = false
	_coast_for = 0.0
	done = _samples.is_empty()
	playing = not done
	_srb_live = not _srb_nodes.is_empty()
	_booster_live = true
	_fairing_live = _fairing != null
	_debris.clear()
	if _stack:
		_stack.position = Vector3(0, 0.2, 0)
		_stack.rotation = Vector3.ZERO


func advance(delta: float) -> Dictionary:
	if not playing:
		return status()
	if hold > 0.0:
		hold -= delta
		var spool := clampf((1.0 - hold / 3.0) - 0.55, 0.0, 1.0)
		_set_plumes(spool * 0.22, true, false)
		return status()
	var duration := maxf(float(_samples[-1][0]), 0.05)
	var rate := duration / 22.0
	sim_t = minf(sim_t + delta * rate, duration)
	_apply_time(sim_t, delta)
	_step_debris(delta)
	if _coast_for > 0.0:
		_coast_for -= delta
		coasting = _coast_for > 0.0
	if sim_t >= duration - 0.001:
		playing = false
		done = true
		_set_plumes(0.0, false, false)
	return status()


func status() -> Dictionary:
	var altitude := 0.2
	var downrange := 0.0
	var pitch := 90.0
	var throttle := 0.0
	if playing and hold <= 0.0 and not _samples.is_empty():
		var sample := _blend(sim_t)
		altitude = float(sample[1])
		downrange = float(sample[2])
		pitch = float(sample[3])
		throttle = float(sample[4])
	elif hold > 0.0:
		throttle = clampf((1.0 - hold / 3.0) - 0.55, 0.0, 1.0) * 0.22
	return {
		"throttle": throttle,
		"altitude": altitude,
		"downrange": downrange,
		"pitch": pitch,
		"sim_t": 0.0 if hold > 0.0 else sim_t,
		"hold": maxf(hold, 0.0),
		"coasting": coasting,
		"done": done,
		"playing": playing,
		"events": _visible_events(),
		"focus": focus_position(),
		"retract": clampf(1.0 - maxf(hold, 0.0) / 3.0, 0.0, 1.0) if playing or done else 0.0,
	}


func focus_position() -> Vector3:
	if _stack == null:
		return Vector3(0, 2, 0)
	return _stack.global_position + _stack.global_transform.basis.y * stack_length * 0.4


func _apply_time(t: float, delta: float) -> void:
	var sample := _blend(t)
	var altitude := float(sample[1])
	var downrange := float(sample[2])
	var pitch := float(sample[3])
	var throttle := float(sample[4])
	var srb_on := float(sample[5]) > 0.5
	var booster_on := float(sample[6]) > 0.5
	var previous := _stack.global_position
	_stack.position = Vector3(0.0, altitude, -downrange)
	_stack.rotation = Vector3(deg_to_rad(pitch - 90.0), 0.0, 0.0)
	var velocity := (_stack.global_position - previous) / maxf(delta, 0.001)
	if _srb_live and not srb_on:
		_srb_live = false
		for node in _srb_nodes:
			_detach(node, velocity + node.global_transform.basis.x * 6.0)
		_srb_nodes.clear()
	if _booster_live and not booster_on:
		_booster_live = false
		_set_plumes(0.0, false, throttle > 0.05)
		_detach(_booster, velocity * 0.92)
	if _fairing_live and altitude > 105000.0:
		_fairing_live = false
		_detach(_fairing, velocity + Vector3(8, 2, 0))
		_fairing = null
	var core_burn := booster_on and throttle > 0.04
	var kick_burn := (not booster_on) and throttle > 0.04
	_set_plumes(throttle if core_burn or kick_burn else 0.0, core_burn, kick_burn)
	if _index_jump(t):
		coasting = true
		_coast_for = 2.4


func _blend(t: float) -> Array:
	if _samples.size() == 1:
		return _samples[0]
	var i := 0
	while i < _samples.size() - 2 and float(_samples[i + 1][0]) < t:
		i += 1
	var a: Array = _samples[i]
	var b: Array = _samples[mini(i + 1, _samples.size() - 1)]
	var span := float(b[0]) - float(a[0])
	var u := 0.0 if span <= 0.001 else clampf((t - float(a[0])) / span, 0.0, 1.0)
	if absf(float(b[1]) - float(a[1])) > 8000.0:
		u = 1.0 if u > 0.02 else 0.0
	var mixed: Array = []
	for k in 5:
		mixed.append(lerpf(float(a[k]), float(b[k]), u))
	mixed.append(float(b[5]) if u > 0.02 else float(a[5]))
	mixed.append(float(b[6]) if u > 0.02 else float(a[6]))
	return mixed


func _index_jump(t: float) -> bool:
	if _samples.size() < 2:
		return false
	var i := 0
	while i < _samples.size() - 2 and float(_samples[i + 1][0]) < t:
		i += 1
	return absf(float(_samples[mini(i + 1, _samples.size() - 1)][1]) - float(_samples[i][1])) > 8000.0


func _detach(node: Node3D, velocity: Vector3) -> void:
	if node == null or not is_instance_valid(node):
		return
	var kept := node.global_transform
	var parent := node.get_parent()
	if parent:
		parent.remove_child(node)
	add_child(node)
	node.global_transform = kept
	_debris.append({"node": node, "vel": velocity, "life": 0.0})


func _step_debris(delta: float) -> void:
	for piece in _debris:
		piece["life"] = float(piece["life"]) + delta
		var vel: Vector3 = piece["vel"]
		vel.y -= 12.0 * delta
		piece["vel"] = vel
		var node: Node3D = piece["node"]
		node.position += vel * delta
		node.rotate_object_local(Vector3(1, 0, 0), delta * 0.35)
		if float(piece["life"]) > 0.45:
			for plume in node.find_children("*", "MeshInstance3D", true, false):
				if str(plume.name).begins_with("Plume"):
					plume.visible = false


func _visible_events() -> PackedStringArray:
	var shown := PackedStringArray()
	for line in _events:
		if _event_due(line):
			shown.append(line)
	return shown


func _event_due(line: String) -> bool:
	if line.begins_with("T+"):
		var digits := ""
		for i in range(2, line.length()):
			var ch := line[i]
			if ch == "s" or ch == " ":
				break
			digits += ch
		return sim_t + 0.05 >= float(digits) and hold <= 0.0
	if line.find("Coast") >= 0:
		return coasting or sim_t > 20.0
	return hold <= 0.0 and not _samples.is_empty() and sim_t > float(_samples[-1][0]) * 0.82


func _set_plumes(amount: float, core_on: bool, kick_on: bool) -> void:
	var length := clampf(0.35 + amount * (4.5 + radius * 3.0), 0.2, 28.0)
	if _core_plume:
		_core_plume.visible = core_on and amount > 0.02
		_core_plume.scale = Vector3(1.0, length, 1.0)
	if _core_light:
		_core_light.light_energy = amount * (10.0 if core_on else 0.0)
	if _kick_plume:
		_kick_plume.visible = kick_on and amount > 0.02
		_kick_plume.scale = Vector3(1.0, clampf(length * 0.45, 0.2, 8.0), 1.0)
	for node in _srb_nodes:
		for child in node.find_children("Plume", "", true, false):
			child.visible = core_on
			child.scale = Vector3(1.0, clampf(length * 0.7, 0.3, 16.0), 1.0)


func _plume(parent: Node3D, width: float, color: Color, energy: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Plume"
	var mat := ShaderMaterial.new()
	mat.shader = plume_shader
	mat.set_shader_parameter("plume_color", color)
	mat.set_shader_parameter("energy", energy)
	var mesh := MeshUtil.lathe(PackedVector2Array([Vector2(0.22, 0.0), Vector2(1.0, -1.0)]), 24)
	var mi := MeshUtil.add_mesh(root, mesh, mat, "PlumeMesh")
	mi.scale = Vector3(width, 1.0, width)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(root)
	root.visible = false
	return root


func _plume_color() -> Color:
	if _family == "methalox":
		return Color(0.55, 0.78, 1.0)
	if _family == "kerolox":
		return Color(1.0, 0.48, 0.16)
	return Color(0.95, 0.62, 0.18)


func _hull(frost: float, soot: float, skirt: float, b0: float, b1: float, b2: float, b3: float, w0: float, w1: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = hull_shader
	mat.set_shader_parameter("paint_color", Color(0.90, 0.86, 0.78))
	mat.set_shader_parameter("skirt_color", Color(0.20, 0.20, 0.21))
	mat.set_shader_parameter("band_color", Color(0.78, 0.42, 0.22))
	mat.set_shader_parameter("frost", frost)
	mat.set_shader_parameter("soot", soot)
	mat.set_shader_parameter("skirt_end", skirt)
	mat.set_shader_parameter("band_0", b0)
	mat.set_shader_parameter("band_1", b1)
	mat.set_shader_parameter("band_2", b2)
	mat.set_shader_parameter("band_3", b3)
	mat.set_shader_parameter("window_0", w0)
	mat.set_shader_parameter("window_1", w1)
	return mat


func _metal(color: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = rough
	return mat


func _cap(parent: Node3D, cap_radius: float, y: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = cap_radius
	cyl.bottom_radius = cap_radius
	cyl.height = 0.05
	mi.mesh = cyl
	mi.position = Vector3(0, y, 0)
	mi.material_override = mat
	parent.add_child(mi)


func _capsule(cap_radius: float, height: float, blunt: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(cap_radius * 0.72, 0.0))
	pts.append(Vector2(cap_radius, height * 0.18))
	var steps := 8
	for i in steps:
		var t := float(i + 1) / float(steps)
		var y := height * 0.18 + (height * 0.82) * t
		var x := cap_radius * pow(1.0 - t, blunt)
		pts.append(Vector2(maxf(x, 0.02), y))
	return pts


func _ogive(cap_radius: float, height: float, y0: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var t := float(i) / 9.0
		pts.append(Vector2(maxf(cap_radius * pow(1.0 - t, 0.58), 0.02), y0 + height * t))
	return pts


func _hammerhead(cap_radius: float, height: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(cap_radius * 0.86, 0.0))
	pts.append(Vector2(cap_radius * 1.08, height * 0.08))
	pts.append(Vector2(cap_radius * 1.12, height * 0.22))
	for i in 9:
		var t := float(i) / 8.0
		var y := height * 0.22 + height * 0.78 * t
		var x := cap_radius * 1.12 * pow(1.0 - t, 0.72)
		pts.append(Vector2(maxf(x, 0.02), y))
	return pts


func _build_srb(srb_r: float, height: float) -> Node3D:
	var root := Node3D.new()
	var body := PackedVector2Array()
	body.append(Vector2(srb_r * 0.55, 0.0))
	body.append(Vector2(srb_r * 0.75, 0.25))
	body.append(Vector2(srb_r, 0.55))
	body.append(Vector2(srb_r, height - 0.4))
	body.append(Vector2(srb_r * 0.35, height))
	var hull := _hull(0.0, 0.6, 0.7, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0)
	MeshUtil.add_mesh(root, MeshUtil.lathe(body, 28), hull, "SRBBody")
	var plume := _plume(root, srb_r * 0.7, Color(1.0, 0.78, 0.42), 2.6)
	plume.position = Vector3(0, 0.02, 0)
	return root


func _mount(parent: Node3D, angle: float, radial: float, y: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(cos(angle) * radial, y, sin(angle) * radial)
	pivot.transform.basis = MeshUtil.outward_basis(angle)
	parent.add_child(pivot)
	return pivot


func _place_fins(parent: Node3D, body_r: float, y: float, length: float, root_h: float, mat: Material) -> void:
	var mesh := MeshUtil.fin_prism(length, root_h, 0.035 + body_r * 0.02)
	for i in 4:
		var pivot := _mount(parent, PI * 0.25 + float(i) * PI * 0.5, body_r * 0.92, y)
		MeshUtil.add_mesh(pivot, mesh, mat, "Fin")


func _place_grids(parent: Node3D, body_r: float, y: float, span: float, mat: Material) -> void:
	for i in 4:
		var pivot := _mount(parent, PI * 0.25 + float(i) * PI * 0.5, body_r * 0.96, y)
		_grid(pivot, span, span * 0.22, mat)


func _place_flaps(parent: Node3D, body_r: float, y: float, span: float, mat: Material) -> void:
	for i in 4:
		var pivot := _mount(parent, float(i) * PI * 0.5, body_r * 0.98, y)
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(span, span * 0.62, 0.06)
		mi.mesh = box
		mi.position = Vector3(span * 0.42, 0, 0)
		mi.material_override = mat
		pivot.add_child(mi)


func _place_legs(parent: Node3D, body_r: float, y: float, mat: Material) -> void:
	for i in 4:
		var pivot := _mount(parent, PI * 0.25 + float(i) * PI * 0.5, body_r * 0.8, y)
		var reach := maxf(body_r * 0.85, 0.45)
		MeshUtil.beam(pivot, Vector3(0.05, 0.15, 0), Vector3(reach, -0.85, 0), 0.07, mat)
		var foot := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.28, 0.06, 0.22)
		foot.mesh = box
		foot.position = Vector3(reach, -0.88, 0)
		foot.material_override = mat
		pivot.add_child(foot)


func _grid(parent: Node3D, span: float, depth: float, mat: Material) -> void:
	var thick := maxf(span * 0.055, 0.018)
	_plate(parent, Vector3(span * 0.5, 0, -span * 0.5), Vector3(span, depth, thick), mat)
	_plate(parent, Vector3(span * 0.5, 0, span * 0.5), Vector3(span, depth, thick), mat)
	_plate(parent, Vector3(thick * 0.5, 0, 0), Vector3(thick, depth, span), mat)
	_plate(parent, Vector3(span, 0, 0), Vector3(thick, depth, span), mat)
	for i in 3:
		var x := span * float(i + 1) / 4.0
		_plate(parent, Vector3(x, 0, 0), Vector3(thick * 0.65, depth, span), mat)
		var z := -span * 0.5 + span * float(i + 1) / 4.0
		_plate(parent, Vector3(span * 0.5, 0, z), Vector3(span, depth, thick * 0.65), mat)


func _plate(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
