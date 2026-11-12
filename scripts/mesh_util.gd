extends RefCounted
class_name MeshUtil

## Lathe and beams. Lathe profile is (radius, height). Y is up.
## Outward winding was checked against a +X sample: p00, p10, p11 then p00, p11, p01.


static func lathe(profile: PackedVector2Array, segments: int = 64) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := profile.size()
	var cols := segments + 1
	for i in rings:
		var prev: Vector2 = profile[maxi(i - 1, 0)]
		var next: Vector2 = profile[mini(i + 1, rings - 1)]
		var dr := next.x - prev.x
		var dy := next.y - prev.y
		var nr := dy
		var ny := dr
		var nl := sqrt(nr * nr + ny * ny)
		if nl < 0.00001:
			nr = 1.0
			ny = 0.0
		else:
			nr /= nl
			ny /= nl
		var y := profile[i].y
		var radius := maxf(profile[i].x, 0.0008)
		for j in cols:
			var ang := TAU * float(j) / float(segments)
			var c := cos(ang)
			var s := sin(ang)
			st.set_normal(Vector3(nr * c, ny, nr * s).normalized())
			st.set_uv(Vector2(float(j) / float(segments), y))
			st.add_vertex(Vector3(radius * c, y, radius * s))
	for i in rings - 1:
		for j in segments:
			var p00 := i * cols + j
			var p10 := (i + 1) * cols + j
			var p11 := p10 + 1
			var p01 := p00 + 1
			st.add_index(p00)
			st.add_index(p10)
			st.add_index(p11)
			st.add_index(p00)
			st.add_index(p11)
			st.add_index(p01)
	st.generate_tangents()
	return st.commit()


static func outward_basis(angle: float) -> Basis:
	# Local +X points radially out. angle 0 is world +X.
	var x := Vector3(cos(angle), 0.0, sin(angle))
	var y := Vector3.UP
	var z := x.cross(y)
	return Basis(x, y, z)


static func beam(parent: Node3D, a: Vector3, b: Vector3, thickness: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	var length := a.distance_to(b)
	box.size = Vector3(thickness, maxf(length, 0.001), thickness)
	mi.mesh = box
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var dir := (b - a) / maxf(length, 0.001)
	var x_axis := dir.cross(Vector3.FORWARD)
	if x_axis.length() < 0.001:
		x_axis = dir.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(dir).normalized()
	mi.position = (a + b) * 0.5
	mi.transform.basis = Basis(x_axis, dir, z_axis)
	parent.add_child(mi)
	return mi


static func add_mesh(parent: Node3D, mesh: Mesh, mat: Material, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static func quad(p00: Vector3, p10: Vector3, p11: Vector3, p01: Vector3, uv00: Vector2, uv10: Vector2, uv11: Vector2, uv01: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [p00, p10, p11, p01]
	var uvs := [uv00, uv10, uv11, uv01]
	for i in 4:
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	# CCW when the geometric normal (p10-p00) × (p11-p00) points toward the viewer.
	st.add_index(0)
	st.add_index(1)
	st.add_index(2)
	st.add_index(0)
	st.add_index(2)
	st.add_index(3)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


static func fin_prism(length: float, root_h: float, thick: float) -> ArrayMesh:
	# Triangle in local XY, thin in Z. Local +X is outward. All vertices
	# are committed before any index.
	var poly: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(0.0, root_h),
		Vector2(length, root_h * 0.32),
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := thick * 0.5
	var n := poly.size()
	for p in poly:
		st.add_vertex(Vector3(p.x, p.y, hz))
	for p in poly:
		st.add_vertex(Vector3(p.x, p.y, -hz))
	st.add_index(0)
	st.add_index(1)
	st.add_index(2)
	st.add_index(3)
	st.add_index(5)
	st.add_index(4)
	for i in n:
		var j := (i + 1) % n
		var a := poly[i]
		var b := poly[j]
		var edge := b - a
		var outward := Vector2(edge.y, -edge.x)
		var mid := (a + b) * 0.5
		var center := Vector2.ZERO
		for p in poly:
			center += p
		center /= float(n)
		var i0 := i
		var i1 := j
		var i2 := j + n
		var i3 := i + n
		if outward.dot(mid - center) >= 0.0:
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i3)
		else:
			st.add_index(i0)
			st.add_index(i3)
			st.add_index(i2)
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
	st.generate_normals()
	return st.commit()
