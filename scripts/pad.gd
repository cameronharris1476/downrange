extends Node3D
class_name Pad

const TOWER_X := 8.6
const TOWER_HALF := 1.55
const MODEL_ROOT := "res://assets/third_party/polyhaven/models/"

var arm_pivot: Node3D
var arm_y := 8.0
var prop_nodes: Array[Node3D] = []
var _yard := {}
var _paint: StandardMaterial3D
var _copper: StandardMaterial3D
var _dark: StandardMaterial3D


func build(tex: TexLib) -> void:
	_paint = _std(Color(0.46, 0.47, 0.48), 0.28, 0.52)
	_copper = _std(Color(0.72, 0.40, 0.22), 0.8, 0.34)
	_dark = _std(Color(0.12, 0.13, 0.13), 0.4, 0.55)
	var concrete := tex.material("concrete_floor_worn_001", 0.0)
	var sand := tex.material("coast_sand_01", 0.0)
	var ground := tex.material("dry_ground_01", 0.0)
	var rock := tex.material("rock_face", 0.0)
	var asphalt := tex.material("asphalt_01", 0.0)
	var plate := tex.material("metal_plate", 0.65)
	var rust := tex.material("rusty_metal_02", 0.55)

	_top(self, -120.0, 140.0, -26.0, 200.0, 0.0, ground, "Land")
	_top(self, -22.0, -2.7, -20.0, 9.0, 0.07, concrete, "PadLeft")
	_top(self, 2.7, 24.0, -20.0, 9.0, 0.07, concrete, "PadRight")
	_top(self, -22.0, 24.0, 9.0, 36.0, 0.07, concrete, "PadRear")
	_top(self, -22.0, 24.0, -26.0, -20.0, 0.07, concrete, "PadLip")
	_top(self, -2.6, 2.6, -26.0, 9.0, -2.2, concrete, "TrenchFloor")
	_wall_x(self, -2.6, -2.2, 0.07, -26.0, 9.0, true, concrete, "TrenchWest")
	_wall_x(self, 2.6, -2.2, 0.07, -26.0, 9.0, false, concrete, "TrenchEast")
	_wall_z(self, -90.0, 130.0, -9.0, 0.0, -26.0, rock, "CliffSea")
	_wall_z_land(self, -90.0, 130.0, -9.0, 0.0, -25.92, rock, "CliffLand")
	_top(self, -40.0, 50.0, -48.0, -27.0, -1.6, sand, "Beach")
	_top(self, -12.2, -7.0, 18.0, 180.0, 0.08, asphalt, "Road")
	_ramp(rust)

	var ocean := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(5200, 6400)
	plane.orientation = PlaneMesh.FACE_Y
	ocean.mesh = plane
	ocean.position = Vector3(0, -7.6, -2200)
	var water := ShaderMaterial.new()
	water.shader = load("res://shaders/ocean.gdshader")
	ocean.material_override = water
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)

	_ring(4.6)
	_tower()
	_tanks(plate)
	_blockhouse(concrete)
	_people()
	_props()
	_dunes(sand)
	_upgrades(concrete, plate, asphalt)
	set_clearance(0.4, 7.0)
	set_retracted(0.0)


func set_clearance(body_radius: float, cabin_height: float) -> void:
	arm_y = clampf(cabin_height, 3.5, 30.0)
	if arm_pivot == null:
		return
	for child in arm_pivot.get_children():
		arm_pivot.remove_child(child)
		child.free()
	var reach := maxf((TOWER_X - TOWER_HALF) - body_radius - 0.4, 1.4)
	MeshUtil.beam(arm_pivot, Vector3.ZERO, Vector3(-reach, 0.2, 0.0), 0.16, _paint)
	MeshUtil.beam(arm_pivot, Vector3(-reach, 0.2, 0.0), Vector3(-reach, -1.1, 0.0), 0.1, _copper)
	set_retracted(0.0)


func set_retracted(amount: float) -> void:
	if arm_pivot == null:
		return
	var t := clampf(amount, 0.0, 1.0)
	arm_pivot.position = Vector3(TOWER_X - TOWER_HALF + t * 2.8, arm_y + t * 1.6, 0.35)


func apply_upgrades(owned: Dictionary) -> void:
	for key in _yard:
		var node: Node3D = _yard[key]
		node.visible = bool(owned.get(key, false))


func log_bounds() -> PackedStringArray:
	var lines := PackedStringArray()
	for node in prop_nodes:
		var box := _bounds(node)
		lines.append("%s size %s pos %s" % [node.name, box.size, node.global_position])
	return lines


func _tower() -> void:
	var height := 34.0
	var x0 := TOWER_X - TOWER_HALF
	var x1 := TOWER_X + TOWER_HALF
	var z0 := -TOWER_HALF
	var z1 := TOWER_HALF
	var corners: Array[Vector3] = [
		Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1),
	]
	for corner in corners:
		MeshUtil.beam(self, corner, corner + Vector3(0, height, 0), 0.18, _paint)
	var level := 4.0
	while level < height:
		for i in 4:
			var a: Vector3 = corners[i] + Vector3(0, level, 0)
			var b: Vector3 = corners[(i + 1) % 4] + Vector3(0, level, 0)
			MeshUtil.beam(self, a, b, 0.1, _paint)
			MeshUtil.beam(self, corners[i] + Vector3(0, level - 4.0, 0), b, 0.06, _paint)
		level += 4.0
	_deck(x0, x1, z0, z1, 8.0)
	_deck(x0, x1, z0, z1, 16.0)
	_deck(x0, x1, z0, z1, 24.0)
	var cap := MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.18
	bulb.height = 0.36
	cap.mesh = bulb
	cap.position = Vector3(TOWER_X, height + 0.2, 0)
	var red := _std(Color(0.8, 0.12, 0.1), 0.1, 0.4)
	red.emission_enabled = true
	red.emission = Color(0.9, 0.15, 0.08)
	red.emission_energy_multiplier = 2.0
	cap.material_override = red
	add_child(cap)
	arm_pivot = Node3D.new()
	arm_pivot.name = "SwingArm"
	add_child(arm_pivot)


func _deck(x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(x1 - x0 + 0.4, 0.08, z1 - z0 + 0.4)
	mi.mesh = box
	mi.position = Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5)
	mi.material_override = _paint
	add_child(mi)


func _tanks(_plate: Material) -> void:
	var shell := _std(Color(0.78, 0.75, 0.68), 0.12, 0.46)
	for i in 3:
		var tank := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.25
		cyl.bottom_radius = 1.25
		cyl.height = 6.4
		tank.mesh = cyl
		tank.position = Vector3(-15.5, 3.2, -6.0 + float(i) * 3.3)
		tank.material_override = shell
		add_child(tank)
		var band := MeshInstance3D.new()
		var ring := CylinderMesh.new()
		ring.top_radius = 1.3
		ring.bottom_radius = 1.3
		ring.height = 0.18
		band.mesh = ring
		band.position = tank.position + Vector3(0, 1.2, 0)
		band.material_override = _copper
		add_child(band)


func _blockhouse(concrete: Material) -> void:
	_box(self, Vector3(-30.0, 2.4, 22.0), Vector3(14.0, 4.8, 10.0), concrete, "Blockhouse")
	_box(self, Vector3(-30.0, 2.0, 17.2), Vector3(3.2, 2.4, 0.2), _dark, "Door")
	for i in 4:
		_box(self, Vector3(-34.0 + float(i) * 2.4, 3.3, 17.15), Vector3(1.1, 0.7, 0.12), _dark, "Window")


func _people() -> void:
	for pos in [Vector3(-5.4, 0.08, 15.5), Vector3(-8.8, 0.08, 19.0), Vector3(5.8, 0.08, 13.5)]:
		var person := Node3D.new()
		person.position = pos
		var body := MeshUtil.lathe(PackedVector2Array([
			Vector2(0.16, 0.0), Vector2(0.2, 0.2), Vector2(0.2, 1.15), Vector2(0.12, 1.35),
		]), 12)
		var suit := _std(Color(0.18, 0.27, 0.34), 0.05, 0.7)
		MeshUtil.add_mesh(person, body, suit, "Suit")
		var head := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.13
		sphere.height = 0.26
		head.mesh = sphere
		head.position = Vector3(0, 1.52, 0)
		head.material_override = _std(Color(0.55, 0.40, 0.32), 0.0, 0.65)
		person.add_child(head)
		var hat := MeshInstance3D.new()
		var helm := SphereMesh.new()
		helm.radius = 0.15
		helm.height = 0.22
		hat.mesh = helm
		hat.position = Vector3(0, 1.64, 0)
		hat.material_override = _copper
		person.add_child(hat)
		add_child(person)


func _props() -> void:
	var spots := [
		["Barrel_01/Barrel_01.gltf", Vector3(-6.6, 0, 14.2), 0.6],
		["Barrel_01/Barrel_01.gltf", Vector3(-6.9, 0, 15.0), 1.4],
		["plastic_crate_01/plastic_crate_01.gltf", Vector3(-5.0, 0, 17.2), 0.2],
		["plastic_crate_01/plastic_crate_01.gltf", Vector3(-5.3, 0, 17.8), 1.0],
		["portable_generator/portable_generator.gltf", Vector3(6.4, 0, 11.5), -0.4],
		["portable_welding_cart/portable_welding_cart.gltf", Vector3(-9.6, 0, 22.0), 0.8],
		["portable_searchlight/portable_searchlight.gltf", Vector3(12.5, 0, 8.0), 2.4],
		["power_box_01/power_box_01.gltf", Vector3(7.6, 0, 16.5), 0.3],
		["utility_box_01/utility_box_01.gltf", Vector3(-13.2, 0, 12.0), 1.2],
		["propane_tank/propane_tank.gltf", Vector3(-13.8, 0, -1.5), 0.4],
		["propane_tank/propane_tank.gltf", Vector3(-14.4, 0, -1.2), 1.1],
		["security_light/security_light.gltf", Vector3(-8.0, 0, 6.5), 2.2],
		["concrete_road_barrier/concrete_road_barrier.gltf", Vector3(-4.2, 0, 12.4), 0.15],
		["concrete_road_barrier/concrete_road_barrier.gltf", Vector3(-2.2, 0, 12.6), 0.15],
	]
	for spot in spots:
		_prop(str(spot[0]), spot[1], float(spot[2]))


func _prop(rel: String, pos: Vector3, rot_y: float) -> void:
	var packed := load(MODEL_ROOT + rel)
	if packed == null or not packed is PackedScene:
		push_warning("Missing prop " + rel)
		return
	var node := (packed as PackedScene).instantiate()
	node.name = rel.get_file().get_basename()
	add_child(node)
	node.position = Vector3(pos.x, 0.0, pos.z)
	node.rotation.y = rot_y
	_seat(node)
	node.position.y += 0.08
	prop_nodes.append(node)


func _dunes(sand: Material) -> void:
	var specs := [
		[Vector3(-28, 0, -8), 7.0, 2.2],
		[Vector3(26, 0, 4), 9.0, 2.6],
		[Vector3(18, 0, 48), 12.0, 3.0],
		[Vector3(-36, 0, 55), 10.0, 2.4],
	]
	for spec in specs:
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = float(spec[1])
		mesh.height = float(spec[2]) * 0.9
		mi.mesh = mesh
		var p: Vector3 = spec[0]
		mi.position = Vector3(p.x, -float(spec[2]) * 0.2, p.z)
		mi.material_override = sand
		add_child(mi)


func _upgrades(concrete: Material, plate: Material, asphalt: Material) -> void:
	var hangar := Node3D.new()
	hangar.name = "WeldHangar"
	_box(hangar, Vector3(0, 4.0, 0), Vector3(18, 8, 22), plate, "Shell")
	_box(hangar, Vector3(0, 3.0, 11.05), Vector3(8, 5.5, 0.2), _dark, "Door")
	_box(hangar, Vector3(0, 7.2, 11.1), Vector3(6, 0.35, 0.25), _copper, "Stripe")
	hangar.position = Vector3(-24, 0, 46)
	add_child(hangar)
	_yard["weld_cell"] = hangar

	var apron := Node3D.new()
	apron.name = "LandingApron"
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 9.0
	cyl.bottom_radius = 9.0
	cyl.height = 0.08
	disc.mesh = cyl
	disc.material_override = asphalt
	apron.add_child(disc)
	var pts := PackedVector2Array()
	pts.append(Vector2(6.55, 0.04))
	pts.append(Vector2(6.55, 0.12))
	pts.append(Vector2(7.35, 0.12))
	pts.append(Vector2(7.35, 0.04))
	MeshUtil.add_mesh(apron, MeshUtil.lathe(pts, 72), _copper, "ApronRing")
	apron.position = Vector3(20, 0.12, 22)
	add_child(apron)
	_yard["reuse_program"] = apron

	var dish := _dish()
	dish.position = Vector3(-12.5, 0, -16)
	add_child(dish)
	_yard["payload_office"] = dish

	var second := Node3D.new()
	second.name = "SecondPad"
	_top(second, -10, 10, -12, 12, 0.08, concrete, "Slab")
	_top(second, -1.6, 1.6, -12, 6, -1.4, concrete, "Trench")
	for i in 4:
		var a := PI * 0.25 + float(i) * PI * 0.5
		MeshUtil.beam(second, Vector3(cos(a) * 2.2, 0, sin(a) * 2.2), Vector3(cos(a) * 2.2, 16, sin(a) * 2.2), 0.14, _paint)
	second.position = Vector3(80, 0, 0)
	add_child(second)
	_yard["second_pad"] = second

	var cradle := Node3D.new()
	cradle.name = "StationCradle"
	for i in 3:
		MeshUtil.beam(cradle, Vector3(-6 + float(i) * 6, 0, -1.2), Vector3(-6 + float(i) * 6, 1.6, -1.2), 0.12, _paint)
		MeshUtil.beam(cradle, Vector3(-6 + float(i) * 6, 0, 1.2), Vector3(-6 + float(i) * 6, 1.6, 1.2), 0.12, _paint)
		MeshUtil.beam(cradle, Vector3(-6 + float(i) * 6, 1.6, -1.2), Vector3(-6 + float(i) * 6, 1.6, 1.2), 0.1, _paint)
	var truss := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.55
	tube.bottom_radius = 0.55
	tube.height = 14.0
	truss.mesh = tube
	truss.rotation.z = PI * 0.5
	truss.position = Vector3(0, 2.3, 0)
	truss.material_override = plate
	cradle.add_child(truss)
	cradle.position = Vector3(28, 0, 42)
	add_child(cradle)
	_yard["station"] = cradle
	apply_upgrades({})


func _dish() -> Node3D:
	var root := Node3D.new()
	root.name = "Dish"
	MeshUtil.beam(root, Vector3.ZERO, Vector3(0, 5.2, 0), 0.16, _paint)
	var pts := PackedVector2Array()
	for i in 12:
		var t := float(i) / 11.0
		var r := 0.08 + t * 1.7
		pts.append(Vector2(r, 5.2 + t * t * 0.55))
	MeshUtil.add_mesh(root, MeshUtil.lathe(pts, 28), _paint, "Reflector")
	return root


func _ring(ring_radius: float) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(ring_radius - 0.18, 0.08))
	pts.append(Vector2(ring_radius - 0.18, 0.14))
	pts.append(Vector2(ring_radius + 0.18, 0.14))
	pts.append(Vector2(ring_radius + 0.18, 0.08))
	MeshUtil.add_mesh(self, MeshUtil.lathe(pts, 64), _copper, "PadRing")


func _ramp(rust: Material) -> void:
	var mesh := MeshUtil.quad(
		Vector3(-2.6, -2.2, -22.0),
		Vector3(2.6, -2.2, -22.0),
		Vector3(2.6, -0.4, -28.0),
		Vector3(-2.6, -0.4, -28.0),
		Vector2(-1.3, -11.0), Vector2(1.3, -11.0), Vector2(1.3, -14.0), Vector2(-1.3, -14.0)
	)
	var mi := MeshUtil.add_mesh(self, mesh, rust, "Deflector")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, node_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _top(parent: Node3D, x0: float, x1: float, z0: float, z1: float, y: float, mat: Material, node_name: String) -> void:
	var mesh := MeshUtil.quad(
		Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1),
		Vector2(x0, z0) * 0.5, Vector2(x1, z0) * 0.5, Vector2(x1, z1) * 0.5, Vector2(x0, z1) * 0.5
	)
	MeshUtil.add_mesh(parent, mesh, mat, node_name)


func _wall_z(parent: Node3D, x0: float, x1: float, y0: float, y1: float, z: float, mat: Material, node_name: String) -> void:
	# Faces -Z, toward the sea.
	var mesh := MeshUtil.quad(
		Vector3(x0, y0, z), Vector3(x0, y1, z), Vector3(x1, y1, z), Vector3(x1, y0, z),
		Vector2(x0, y0) * 0.5, Vector2(x0, y1) * 0.5, Vector2(x1, y1) * 0.5, Vector2(x1, y0) * 0.5
	)
	MeshUtil.add_mesh(parent, mesh, mat, node_name)


func _wall_z_land(parent: Node3D, x0: float, x1: float, y0: float, y1: float, z: float, mat: Material, node_name: String) -> void:
	var mesh := MeshUtil.quad(
		Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z),
		Vector2(x0, y0) * 0.5, Vector2(x1, y0) * 0.5, Vector2(x1, y1) * 0.5, Vector2(x0, y1) * 0.5
	)
	MeshUtil.add_mesh(parent, mesh, mat, node_name)


func _wall_x(parent: Node3D, x: float, y0: float, y1: float, z0: float, z1: float, face_positive_x: bool, mat: Material, node_name: String) -> void:
	var mesh: ArrayMesh
	if face_positive_x:
		mesh = MeshUtil.quad(
			Vector3(x, y0, z0), Vector3(x, y1, z0), Vector3(x, y1, z1), Vector3(x, y0, z1),
			Vector2(z0, y0) * 0.5, Vector2(z0, y1) * 0.5, Vector2(z1, y1) * 0.5, Vector2(z1, y0) * 0.5
		)
	else:
		mesh = MeshUtil.quad(
			Vector3(x, y0, z1), Vector3(x, y1, z1), Vector3(x, y1, z0), Vector3(x, y0, z0),
			Vector2(z1, y0) * 0.5, Vector2(z1, y1) * 0.5, Vector2(z0, y1) * 0.5, Vector2(z0, y0) * 0.5
		)
	MeshUtil.add_mesh(parent, mesh, mat, node_name)


func _seat(node: Node3D) -> void:
	var box := _bounds(node)
	if box.size.length() < 0.001:
		return
	node.position.y += -box.position.y


func _bounds(node: Node) -> AABB:
	var found := false
	var box := AABB()
	var list: Array[Node] = []
	if node is VisualInstance3D:
		list.append(node)
	for child in node.find_children("*", "VisualInstance3D", true, false):
		list.append(child)
	for item in list:
		if not item is MeshInstance3D:
			continue
		var visual := item as MeshInstance3D
		if visual.mesh == null:
			continue
		var local := visual.get_aabb()
		var world := visual.global_transform * local
		if not found:
			box = world
			found = true
		else:
			box = box.merge(world)
	return box


func _std(color: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = rough
	return mat
