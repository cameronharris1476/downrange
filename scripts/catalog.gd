extends RefCounted
class_name Catalog

static func load_default() -> Dictionary:
	var file := FileAccess.open("res://data/catalog.json", FileAccess.READ)
	if file == null:
		push_error("Missing res://data/catalog.json")
		return {}
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Catalog did not parse")
		return {}
	var by_id := {}
	for part in data["parts"]:
		by_id[str(part["id"])] = part
	data["by_id"] = by_id
	return data
