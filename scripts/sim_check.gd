extends SceneTree

## Headless balance check. Ranges, not exact flight floats.
## Run: godot --headless --path <Downrange> -s res://scripts/sim_check.gd

var fails := 0
var cat: Dictionary = {}


func _init() -> void:
	cat = Catalog.load_default()
	if cat.is_empty():
		print("FAIL catalog")
		quit(1)
		return
	_geometry()
	_flights()
	_economy()
	print("----")
	if fails == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILURES %d" % fails)
		quit(1)


func _geometry() -> void:
	var mesh := MeshUtil.lathe(PackedVector2Array([Vector2(1.0, 0.0), Vector2(1.0, 2.0), Vector2(0.2, 3.0)]), 16)
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var a: Vector3 = verts[indices[0]]
	var b: Vector3 = verts[indices[1]]
	var c: Vector3 = verts[indices[2]]
	var winding: Vector3 = (b - a).cross(c - a)
	var radial := Vector3(a.x, 0.0, a.z)
	_expect("lathe winding out", winding.dot(radial) > 0.0, "dot %.3f" % winding.normalized().dot(radial.normalized()))
	var upright := Basis(Vector3.RIGHT, deg_to_rad(90.0 - 90.0)).y
	var flat := Basis(Vector3.RIGHT, deg_to_rad(0.0 - 90.0)).y
	_expect("nose upright is +Y", upright.dot(Vector3.UP) > 0.99, str(upright))
	_expect("nose flat points -Z", flat.dot(Vector3(0, 0, -1)) > 0.99, str(flat))
	var root := Node3D.new()
	var beamed := MeshUtil.beam(root, Vector3.ZERO, Vector3(0, 2, 0), 0.1, null)
	_expect("beam axis is the span", beamed.transform.basis.y.dot(Vector3.UP) > 0.99, str(beamed.transform.basis.y))
	_expect("beam basis right-handed", beamed.transform.basis.determinant() > 0.5, str(beamed.transform.basis.determinant()))
	var fin := MeshUtil.fin_prism(1.0, 1.2, 0.04)
	_expect("fin has triangles", fin.get_faces().size() > 3, str(fin.get_faces().size()))
	root.free()


func _flights() -> void:
	var uni := _contract("uni")
	var micro := _contract("micro")
	var cubesat := _contract("cubesat")
	var crew := _contract("crew")
	var truss := _contract("truss")
	var starter := _loadout("spar", "ps80", "auto", {"aero": "fins"})
	var hopped: Dictionary = _fly(starter, uni, false)
	_expect("starter clears uni", bool(hopped["ok"]) and float(hopped["apogee_m"]) >= 180000.0 and float(hopped["apogee_m"]) < 450000.0, _summ(hopped))
	_expect("starter stays under spar max-q", float(hopped["max_q"]) < 105000.0, "q %.0f" % float(hopped["max_q"]))
	var bare := _loadout("spar", "ps80", "auto", {})
	var tumbled: Dictionary = _fly(bare, uni, false)
	_expect("no fins tumbles", str(tumbled["outcome"]) == "tumble", _summ(tumbled))
	var srb := _loadout("spar", "ps80", "auto", {"aero": "fins", "booster": "srb1"})
	var buckled: Dictionary = _fly(srb, uni, false)
	_expect("single SRB buckles Spar", str(buckled["outcome"]) == "buckle", _summ(buckled))
	var weak := _loadout("keel", "ps80", "auto", {"aero": "fins"})
	var stuck: Dictionary = _fly(weak, uni, false)
	_expect("PS-80 cannot lift Keel", str(stuck["outcome"]) == "no_liftoff", _summ(stuck))
	var micro_flight: Dictionary = _fly(starter, micro, false)
	_expect("starter misses 500 km", not bool(micro_flight["ok"]) and float(micro_flight["apogee_m"]) < 500000.0 and float(micro_flight["apogee_m"]) > 100000.0, _summ(micro_flight))
	var leo := _loadout("keel", "gg620", "auto", {"upper": "kick", "fairing": "fairing", "gimbal": "gimbal"})
	var orbited: Dictionary = _fly(leo, cubesat, false)
	_expect("Keel GG kick reaches LEO", bool(orbited["ok"]) and float(orbited["perigee_m"]) >= 180000.0 and float(orbited["perigee_m"]) < 600000.0, _summ(orbited))
	var no_kick := _loadout("keel", "gg620", "auto", {"fairing": "fairing", "gimbal": "gimbal", "aero": "fins"})
	var short: Dictionary = _fly(no_kick, cubesat, false)
	_expect("LEO without a kick falls short", not bool(short["ok"]), _summ(short))
	var ff_spar := _loadout("spar", "ff1900", "auto", {"aero": "fins"})
	var over: Dictionary = _fly(ff_spar, uni, false)
	_expect("full-flow buckles Spar", str(over["outcome"]) == "buckle", _summ(over))
	var crew_spar := _loadout("spar", "ps80", "crew", {"aero": "fins"})
	var crew_fail: Dictionary = _fly(crew_spar, crew, false)
	_expect("crew cabin is too heavy for Spar", not bool(crew_fail["ok"]), _summ(crew_fail))
	var crew_keel := _loadout("keel", "gg620", "crew", {"aero": "fins"})
	var crew_ok: Dictionary = _fly(crew_keel, crew, false)
	_expect("crew hop works on Keel", bool(crew_ok["ok"]) and float(crew_ok["apogee_m"]) >= 80000.0, _summ(crew_ok))
	var heavy := {"upper": "kick", "fairing": "fairing", "gimbal": "gimbal", "aero": "fins"}
	var mast := _loadout("mast", "ff1900", "auto", heavy)
	var delivered: Dictionary = _fly(mast, truss, false)
	_expect("Mast and full-flow fly the truss", bool(delivered["ok"]) and float(delivered["perigee_m"]) >= 320000.0, _summ(delivered))
	var spine := _loadout("spine", "ff1900", "auto", heavy)
	var shy: Dictionary = _fly(spine, truss, false)
	_expect("Spine and full-flow miss the truss", not bool(shy["ok"]), _summ(shy))
	var reuse := _loadout("keel", "gg620", "auto", {"upper": "kick", "fairing": "fairing", "gimbal": "gimbal", "aero": "grid_al", "legs": "legs"})
	var back: Dictionary = _fly(reuse, cubesat, true)
	_expect("grid-fin booster comes home", bool(back["ok"]) and bool(back["recovered"]) and float(back["max_q"]) <= 70000.0, _summ(back))


func _economy() -> void:
	var start := int(cat["economy"]["starting_cash"])
	var ff := int(cat["by_id"]["ff1900"]["cost"])
	var gg := int(cat["by_id"]["gg620"]["cost"])
	_expect("full-flow costs several times the seed cash", ff > start * 4, "%d vs %d" % [ff, start])
	var pack := 0
	for id in Company.STARTER:
		pack += int(cat["by_id"][id]["cost"])
	_expect("sounding stack is the known price", pack == 1560000, str(pack))
	var company := Company.new()
	company.setup(cat, false, false)
	_expect("university contract is preselected", company.contract_id == "uni", company.contract_id)
	company.set_contract("micro")
	for id in Company.STARTER:
		if not company.buy_part(id):
			_expect("buy " + id, false, "cash %d" % company.cash)
	_expect("starter cash left cannot buy GG-620", company.cash == start - pack and company.cash < gg and not company.buy_part("gg620"), str(company.cash))
	_expect("micro is legal and the sim says it fails", company.block_reason() == "" and bool(company.preview()["legal"]) and not bool(company.preview()["sim"]["ok"]), company.block_reason())
	company.set_contract("uni")
	var report: Dictionary = company.commit_launch()
	var expect_cash := start - pack + int(_contract("uni")["payout"]) - int(cat["economy"]["range_fee"])
	_expect("first university flight pays the ledger", not bool(report["blocked"]) and bool(report["sim"]["ok"]) and company.cash == expect_cash and expect_cash == 5550000, "cash %d expect %d" % [company.cash, expect_cash])
	_expect("payroll waits until day 30", company.day == 13 and company.orbital_successes == 0, "day %d" % company.day)
	var rich := Company.new()
	rich.setup(cat, false, false)
	rich.cash = 100000000
	for id in ["keel", "gg620", "crew", "kick"]:
		rich.buy_part(id)
	rich.set_contract("cubesat")
	_expect("crew cabin satisfies a fairing", rich.block_reason() == "", rich.block_reason())
	rich.buy_part("auto")
	rich.set_slot("cabin", "auto")
	_expect("uncrewed LEO without a fairing is blocked", rich.block_reason() != "", rich.block_reason())


func _fly(loadout: Dictionary, contract: Dictionary, reserve: bool) -> Dictionary:
	return AscentSim.new().fly(cat, loadout, contract, reserve, false)


func _loadout(core: String, engine: String, cabin: String, extra: Dictionary) -> Dictionary:
	var row := {
		"core": core,
		"engine": engine,
		"booster": "",
		"upper": "",
		"cabin": cabin,
		"aero": "",
		"gimbal": "",
		"legs": "",
		"fairing": "",
	}
	for key in extra:
		row[key] = extra[key]
	return row


func _contract(id: String) -> Dictionary:
	for item in cat["contracts"]:
		if str(item["id"]) == id:
			return item
	return {}


func _summ(row: Dictionary) -> String:
	return "%s apo %.0f km peri %.0f km q %.0f kPa twr %.2f rec %s" % [
		str(row["outcome"]),
		float(row["apogee_m"]) / 1000.0,
		float(row["perigee_m"]) / 1000.0,
		float(row["max_q"]) / 1000.0,
		float(row["twr"]),
		str(row["recovered"]),
	]


func _expect(name: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS  ", name, "  ", detail)
	else:
		fails += 1
		print("FAIL  ", name, "  ", detail)
