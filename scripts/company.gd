extends RefCounted
class_name Company

const SLOTS: Array[String] = ["core", "engine", "booster", "upper", "cabin", "aero", "gimbal", "legs", "fairing"]
const OPTIONAL: Array[String] = ["booster", "upper", "aero", "gimbal", "legs", "fairing"]
const STARTER: Array[String] = ["spar", "ps80", "auto", "fins"]
const SAVE_PATH := "user://downrange.json"

var catalog: Dictionary = {}
var economy: Dictionary = {}
var autosave := true
var cash := 0
var day := 1
var next_payroll := 30
var company_name := "Independent"
var inventory: Dictionary = {}
var loadout: Dictionary = {}
var upgrades: Dictionary = {}
var orbital_successes := 0
var contract_id := "uni"
var reserve := false
var muted := false
var flights := 0
var successes := 0


func setup(cat: Dictionary, load_save: bool = true, save_ok: bool = true) -> void:
	catalog = cat
	economy = cat["economy"]
	autosave = save_ok
	_fresh()
	if load_save:
		_load()


func _fresh() -> void:
	cash = int(economy["starting_cash"])
	day = 1
	next_payroll = int(economy["payroll_period"])
	company_name = "Independent"
	inventory = {}
	loadout = {}
	for slot in SLOTS:
		loadout[slot] = ""
	upgrades = {}
	for upgrade in catalog["upgrades"]:
		upgrades[str(upgrade["id"])] = false
	orbital_successes = 0
	contract_id = "uni"
	reserve = false
	muted = false
	flights = 0
	successes = 0


func part(id: String) -> Dictionary:
	if id == "" or not catalog["by_id"].has(id):
		return {}
	return catalog["by_id"][id]


func upgrade(id: String) -> Dictionary:
	for item in catalog["upgrades"]:
		if str(item["id"]) == id:
			return item
	return {}


func current_contract() -> Dictionary:
	for item in catalog["contracts"]:
		if str(item["id"]) == contract_id:
			return item
	return {}


func price_of(item: Dictionary) -> int:
	var cost := int(item["cost"])
	if bool(item.get("weld", false)) and bool(upgrades.get("weld_cell", false)):
		cost = int(round(float(cost) * 0.7))
	return cost


func count_of(id: String) -> int:
	return int(inventory.get(id, 0))


func set_company_name(value: String) -> void:
	var trimmed := value.strip_edges()
	if trimmed == "":
		trimmed = "Independent"
	company_name = trimmed.substr(0, 32)
	save()


func set_contract(id: String) -> void:
	contract_id = id
	save()


func set_slot(slot: String, id: String) -> void:
	if id != "":
		var item := part(id)
		if item.is_empty() or str(item.get("slot", "")) != slot:
			return
		if count_of(id) < 1:
			return
	loadout[slot] = id
	if not reserve_allowed():
		reserve = false
	save()


func set_reserve(on: bool) -> void:
	reserve = on and reserve_allowed()
	save()


func reserve_allowed() -> bool:
	if not bool(upgrades.get("reuse_program", false)):
		return false
	if str(loadout["gimbal"]) == "" or str(loadout["legs"]) == "":
		return false
	var aero := part(str(loadout["aero"]))
	if aero.is_empty():
		return false
	var dv := float(aero.get("landing_dv", 0.0))
	return dv > 0.0 and dv < 5000.0


func buy_part(id: String) -> bool:
	var item := part(id)
	if item.is_empty():
		return false
	var price := price_of(item)
	if cash < price:
		return false
	cash -= price
	inventory[id] = count_of(id) + 1
	var slot := str(item["slot"])
	if str(loadout.get(slot, "")) == "":
		loadout[slot] = id
	if not reserve_allowed():
		reserve = false
	save()
	return true


func starter_missing() -> Array[String]:
	var missing: Array[String] = []
	for id in STARTER:
		if count_of(id) < 1:
			missing.append(id)
	return missing


func starter_price() -> int:
	var total := 0
	for id in starter_missing():
		total += price_of(part(id))
	return total


func buy_starter() -> bool:
	var missing := starter_missing()
	if missing.is_empty():
		return false
	if cash < starter_price():
		return false
	for id in missing:
		if not buy_part(id):
			return false
	return true


func buy_upgrade(id: String) -> bool:
	if bool(upgrades.get(id, false)):
		return false
	var item := upgrade(id)
	if item.is_empty():
		return false
	if bool(item.get("requires_orbit", false)) and orbital_successes < 1:
		return false
	var price := int(item["cost"])
	if cash < price:
		return false
	cash -= price
	upgrades[id] = true
	save()
	return true


func hardware_cost() -> int:
	var total := 0
	for slot in SLOTS:
		var id := str(loadout[slot])
		if id != "":
			total += price_of(part(id))
	return total


func block_reason() -> String:
	if str(loadout["core"]) == "" or str(loadout["engine"]) == "" or str(loadout["cabin"]) == "":
		return "The stack needs a core, an engine, and a cabin."
	for slot in SLOTS:
		var id := str(loadout[slot])
		if id != "" and count_of(id) < 1:
			return "The hangar is missing a part still assigned to the stack."
	var contract := current_contract()
	if contract.is_empty():
		return "Pick a contract."
	if not _fairing_ok(contract):
		return "This contract needs a fairing. A crew cabin can fly without one."
	if bool(contract["needs_crew"]) and not bool(part(str(loadout["cabin"])).get("crew", false)):
		return "This contract needs the crew cabin."
	var need := str(contract.get("needs_upgrade", ""))
	if need != "" and not bool(upgrades.get(need, false)):
		return "This contract needs the %s." % str(upgrade(need).get("name", need))
	return ""


func _fairing_ok(contract: Dictionary) -> bool:
	if not bool(contract["needs_fairing"]):
		return true
	if str(loadout["fairing"]) != "":
		return true
	return bool(part(str(loadout["cabin"])).get("crew", false))


func preview() -> Dictionary:
	var reason := block_reason()
	if reason != "":
		return {"legal": false, "reason": reason}
	var sim := AscentSim.new().fly(catalog, loadout, current_contract(), reserve and reserve_allowed(), false)
	return {"legal": true, "sim": sim}


func commit_launch() -> Dictionary:
	var reason := block_reason()
	if reason != "":
		return {"blocked": true, "reason": reason}
	var names := {}
	for slot in SLOTS:
		var id := str(loadout[slot])
		if id == "":
			continue
		names[slot] = str(part(id)["name"])
		inventory[id] = count_of(id) - 1
	var contract := current_contract()
	var use_reserve := reserve and reserve_allowed()
	var sim: Dictionary = AscentSim.new().fly(catalog, loadout.duplicate(), contract, use_reserve, true)
	var recovered_names: Array[String] = []
	if bool(sim["recovered"]):
		for slot in ["core", "engine", "aero", "gimbal", "legs"]:
			var id := str(loadout[slot])
			if id == "":
				continue
			inventory[id] = count_of(id) + 1
			recovered_names.append(names[slot])
	if bool(sim["recovered_cabin"]):
		var cabin_id := str(loadout["cabin"])
		inventory[cabin_id] = count_of(cabin_id) + 1
		recovered_names.append(names["cabin"])
	var expended: Array[String] = []
	for slot in SLOTS:
		if not names.has(slot):
			continue
		var came_back := false
		for recovered_name in recovered_names:
			if recovered_name == names[slot]:
				came_back = true
		if not came_back:
			expended.append(names[slot])
		var id := str(loadout[slot])
		if id != "" and count_of(id) <= 0:
			inventory.erase(id)
			loadout[slot] = ""
	var ledger: Array = []
	var fee := int(economy["range_fee"])
	cash -= fee
	ledger.append({"label": "Range fee", "amount": -fee})
	if bool(sim["ok"]):
		var payout := int(contract["payout"])
		cash += payout
		ledger.append({"label": str(contract["name"]), "amount": payout})
		if str(contract["kind"]) == "orbital":
			orbital_successes += 1
	elif str(sim["outcome"]) == "buckle" or str(sim["outcome"]) == "no_liftoff":
		var repair := int(economy["pad_repair"])
		cash -= repair
		ledger.append({"label": "Pad repair", "amount": -repair})
	elif float(sim["apogee_m"]) > 20000.0:
		var data := int(economy["data_payout"])
		cash += data
		ledger.append({"label": "Data sale", "amount": data})
	var turn := int(economy["fast_turnaround_days"]) if bool(upgrades.get("second_pad", false)) else int(economy["turnaround_days"])
	day += turn
	var payroll := int(economy["payroll"])
	var period := int(economy["payroll_period"])
	var hits := 0
	while day >= next_payroll:
		cash -= payroll
		next_payroll += period
		hits += 1
	if hits > 0:
		ledger.append({"label": "Payroll", "amount": -payroll * hits})
	flights += 1
	if bool(sim["ok"]):
		successes += 1
	if not reserve_allowed():
		reserve = false
	save()
	return {
		"blocked": false,
		"sim": sim,
		"ledger": ledger,
		"expended": expended,
		"recovered": recovered_names,
		"contract": str(contract["name"]),
		"day": day,
		"cash": cash,
	}


func reset_company() -> void:
	var absolute := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(absolute)
	_fresh()
	save()


func save() -> void:
	if not autosave:
		return
	var payload := {
		"cash": cash,
		"day": day,
		"next_payroll": next_payroll,
		"name": company_name,
		"inventory": inventory.duplicate(),
		"loadout": loadout.duplicate(),
		"upgrades": upgrades.duplicate(),
		"orbital_successes": orbital_successes,
		"contract_id": contract_id,
		"reserve": reserve,
		"muted": muted,
		"flights": flights,
		"successes": successes,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	cash = int(data.get("cash", cash))
	day = int(data.get("day", day))
	next_payroll = int(data.get("next_payroll", next_payroll))
	company_name = str(data.get("name", company_name))
	orbital_successes = int(data.get("orbital_successes", 0))
	contract_id = str(data.get("contract_id", "uni"))
	reserve = bool(data.get("reserve", false))
	muted = bool(data.get("muted", false))
	flights = int(data.get("flights", 0))
	successes = int(data.get("successes", 0))
	inventory = {}
	if data.has("inventory"):
		for key in data["inventory"]:
			inventory[str(key)] = int(data["inventory"][key])
	if data.has("loadout"):
		for slot in SLOTS:
			var id := str(data["loadout"].get(slot, ""))
			if id != "" and count_of(id) > 0 and str(part(id).get("slot", "")) == slot:
				loadout[slot] = id
	if data.has("upgrades"):
		for key in data["upgrades"]:
			if upgrades.has(str(key)):
				upgrades[str(key)] = bool(data["upgrades"][key])
	if not reserve_allowed():
		reserve = false


static func money(amount: int) -> String:
	var sign := "-" if amount < 0 else ""
	var digits := str(absi(amount))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3, 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	return "%s$%s%s" % [sign, digits, grouped]
