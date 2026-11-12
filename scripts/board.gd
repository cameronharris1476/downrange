extends Control
class_name Board

signal launch_pressed
signal returned_to_pad

const TEXT := Color("e7e1d6")
const COPPER := Color("d36b3a")
const GOOD := Color("8fbf7a")
const BAD := Color("e15d45")
const GOLD := Color("e6c36a")
const MUTED := Color("9aa194")
const SLOT_LABELS := {
	"core": "Core",
	"engine": "Engine",
	"booster": "Booster",
	"upper": "Upper stage",
	"cabin": "Cabin",
	"aero": "Aero",
	"gimbal": "Gimbal",
	"legs": "Legs",
	"fairing": "Fairing",
}

var company: Company
var name_edit: LineEdit
var cash_label: Label
var meta_label: Label
var mute_button: Button
var slot_box: VBoxContainer
var banner: PanelContainer
var banner_label: Label
var preview_label: Label
var hint_label: Label
var launch_button: Button
var shop_root: Control
var contract_root: Control
var yard_root: Control
var shop_box: VBoxContainer
var contract_box: VBoxContainer
var yard_box: VBoxContainer
var left_panel: PanelContainer
var right_panel: PanelContainer
var flight_panel: PanelContainer
var flight_label: Label
var event_label: Label
var coast_label: Label
var debrief_panel: PanelContainer
var debrief_label: Label
var tab := "shop"
var _options := {}
var _reset_armed := false
var _tab_buttons := {}
var _regular: Font
var _semibold: Font
var _mono: Font


func build(source: Company) -> void:
	company = source
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit_viewport()
	_load_fonts()
	theme = _make_theme()
	_build_top()
	_build_left()
	_build_right()
	_build_launch()
	_build_flight()
	_build_debrief()
	refresh()


func _process(_delta: float) -> void:
	# A Control parented to a CanvasLayer does not pick up Full Rect until
	# its size has been written. Keep it on the viewport so the shop stays put.
	var rect := get_viewport().get_visible_rect()
	if anchor_right < 0.99 or anchor_bottom < 0.99 or size.distance_to(rect.size) > 1.0:
		_fit_viewport()


func _fit_viewport() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	var rect := get_viewport().get_visible_rect()
	position = Vector2.ZERO
	size = rect.size


func refresh() -> void:
	if company == null:
		return
	cash_label.text = Company.money(company.cash)
	var payroll_in := company.next_payroll - company.day
	meta_label.text = "Day %d   ·   payroll in %d days   ·   flights %d   ·   orbits %d" % [company.day, payroll_in, company.flights, company.orbital_successes]
	if not name_edit.has_focus():
		name_edit.text = company.company_name
	mute_button.text = "Sound off" if company.muted else "Sound on"
	_fill_slots()
	_fill_shop()
	_fill_contracts()
	_fill_yard()
	_fill_preview()
	_show_tab(tab)


func show_flight() -> void:
	left_panel.visible = false
	right_panel.visible = false
	launch_button.visible = false
	flight_panel.visible = true
	debrief_panel.visible = false


func show_pad() -> void:
	left_panel.visible = true
	right_panel.visible = true
	launch_button.visible = true
	flight_panel.visible = false
	debrief_panel.visible = false
	refresh()


func set_telemetry(line: String, events: PackedStringArray, coast: bool) -> void:
	flight_label.text = line
	var tail := PackedStringArray()
	var start := maxi(events.size() - 5, 0)
	for i in range(start, events.size()):
		tail.append(events[i])
	event_label.text = "\n".join(tail)
	coast_label.visible = coast


func show_debrief(report: Dictionary) -> void:
	flight_panel.visible = false
	debrief_panel.visible = true
	debrief_label.text = _debrief_text(report)


func _debrief_text(report: Dictionary) -> String:
	var sim: Dictionary = report["sim"]
	var lines: PackedStringArray = PackedStringArray()
	if bool(sim["ok"]):
		lines.append("CONTRACT MET")
	else:
		lines.append(str(sim["outcome"]).to_upper())
	lines.append(str(report["contract"]))
	lines.append(str(sim["reason"]))
	lines.append("Apogee %d km    perigee %d km    max-q %d kPa" % [
		int(float(sim["apogee_m"]) / 1000.0),
		int(float(sim["perigee_m"]) / 1000.0),
		int(float(sim["max_q"]) / 1000.0),
	])
	lines.append("")
	for entry in report["ledger"]:
		var amount := int(entry["amount"])
		var shown := "+" + Company.money(amount) if amount > 0 else Company.money(amount)
		lines.append("%s    %s" % [str(entry["label"]), shown])
	lines.append("")
	if report["recovered"].size() > 0:
		lines.append("Back in the hangar: " + ", ".join(PackedStringArray(report["recovered"])))
	if report["expended"].size() > 0:
		lines.append("Expended: " + ", ".join(PackedStringArray(report["expended"])))
	lines.append("")
	lines.append("Cash %s    ·    day %d" % [Company.money(int(report["cash"])), int(report["day"])])
	return "\n".join(lines)


func _fill_preview() -> void:
	var missing := company.starter_missing()
	if missing.is_empty():
		hint_label.text = "Right-drag orbits the pad. The wheel zooms. The cabin flies the rocket."
	else:
		hint_label.text = "Start with Spar, the PS-80, an instrument cabin, and fixed fins. A full-flow methalox engine does not fit this month."
	var blocked := company.block_reason()
	if blocked != "":
		_paint_banner(BAD, "INCOMPLETE — " + blocked)
		preview_label.text = "Hardware on the stack  %s" % Company.money(company.hardware_cost())
		launch_button.disabled = true
		launch_button.text = "COMMIT LAUNCH"
		return
	var view: Dictionary = company.preview()
	var sim: Dictionary = view["sim"]
	var contract := company.current_contract()
	var body := "TWR %.2f\nApogee %d km\nPerigee %d km\nMax-q %d kPa\nHardware at risk  %s\nRange fee  %s\nContract pays  %s" % [
		float(sim["twr"]),
		int(float(sim["apogee_m"]) / 1000.0),
		int(float(sim["perigee_m"]) / 1000.0),
		int(float(sim["max_q"]) / 1000.0),
		Company.money(company.hardware_cost()),
		Company.money(int(company.economy["range_fee"])),
		Company.money(int(contract["payout"])),
	]
	if company.reserve and company.reserve_allowed():
		body += "\nLanding reserve is armed."
		if bool(sim["recovered"]):
			body += "\nThe sim brings the booster back."
	preview_label.text = body
	launch_button.disabled = false
	if bool(sim["ok"]):
		_paint_banner(GOOD, "CLEARS — " + str(sim["reason"]))
		launch_button.text = "COMMIT LAUNCH"
	else:
		_paint_banner(BAD, "FAILS — " + str(sim["reason"]))
		launch_button.text = "LAUNCH ANYWAY"


func _fill_slots() -> void:
	for child in slot_box.get_children():
		slot_box.remove_child(child)
		child.free()
	_options.clear()
	for slot in Company.SLOTS:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var label := Label.new()
		label.text = SLOT_LABELS[slot]
		label.add_theme_color_override("font_color", MUTED)
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var picked := str(company.loadout[slot])
		var index := 0
		var select := 0
		if picked == "":
			option.add_item("None" if slot in Company.OPTIONAL else "Not assigned")
			option.set_item_metadata(0, "")
			index = 1
		elif slot in Company.OPTIONAL:
			option.add_item("None")
			option.set_item_metadata(0, "")
			index = 1
		var any := false
		for part in company.catalog["parts"]:
			if str(part["slot"]) != slot:
				continue
			var id := str(part["id"])
			if company.count_of(id) < 1:
				continue
			any = true
			option.add_item("%s   ×%d" % [str(part["name"]), company.count_of(id)])
			option.set_item_metadata(index, id)
			if id == picked:
				select = index
			index += 1
		if not any and not slot in Company.OPTIONAL:
			option.add_item("None in the hangar")
			option.set_item_metadata(0, "")
		option.select(select)
		option.item_selected.connect(_on_slot.bind(slot))
		_options[slot] = option
		row.add_child(option)
		slot_box.add_child(row)


func _fill_shop() -> void:
	_clear(shop_box)
	var ff: Dictionary = company.part("ff1900")
	if company.cash < int(ff["cost"]) and company.count_of("ff1900") < 1:
		shop_box.add_child(_note("A full-flow methalox engine is out of reach. Fly the cheapest stack that pays the bills, then spend on the yard."))
	var missing := company.starter_missing()
	if not missing.is_empty():
		var buy := Button.new()
		buy.text = "Buy the sounding stack   %s" % Company.money(company.starter_price())
		buy.disabled = company.cash < company.starter_price()
		buy.pressed.connect(_on_starter)
		shop_box.add_child(buy)
	var order: Array[String] = ["Cores", "Engines", "Boosters", "Stages", "Cabins", "Control"]
	for category in order:
		var header := Label.new()
		header.text = category.to_upper()
		header.add_theme_font_override("font", _semibold)
		header.add_theme_color_override("font_color", COPPER)
		shop_box.add_child(header)
		for part in company.catalog["parts"]:
			if str(part["category"]) != category:
				continue
			shop_box.add_child(_part_row(part))


func _part_row(part: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var top := HBoxContainer.new()
	var name := Label.new()
	name.text = "%s    %s" % [str(part["name"]), str(part["title"])]
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	var price := company.price_of(part)
	var price_label := Label.new()
	price_label.text = Company.money(price)
	price_label.add_theme_font_override("font", _mono)
	price_label.add_theme_color_override("font_color", GOLD)
	top.add_child(price_label)
	var button := Button.new()
	button.text = "Buy"
	button.disabled = company.cash < price
	button.pressed.connect(_on_buy.bind(str(part["id"])))
	top.add_child(button)
	box.add_child(top)
	var blurb := Label.new()
	blurb.text = str(part["blurb"])
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_color_override("font_color", MUTED)
	blurb.add_theme_font_size_override("font_size", 14)
	box.add_child(blurb)
	if company.count_of(str(part["id"])) > 0:
		var stock := Label.new()
		stock.text = "In the hangar ×%d" % company.count_of(str(part["id"]))
		stock.add_theme_color_override("font_color", GOOD)
		box.add_child(stock)
	return box


func _fill_contracts() -> void:
	_clear(contract_box)
	for contract in company.catalog["contracts"]:
		var selected := str(contract["id"]) == company.contract_id
		var button := Button.new()
		button.text = str(contract["name"]) + ("    · selected" if selected else "")
		button.pressed.connect(_on_contract.bind(str(contract["id"])))
		contract_box.add_child(button)
		var blurb := Label.new()
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var need := str(contract.get("needs_upgrade", ""))
		var extra := ""
		if need != "":
			extra = " Needs the %s." % str(company.upgrade(need).get("name", need))
		if bool(contract["needs_fairing"]):
			extra += " Fairing, unless the cabin is crewed."
		if bool(contract["needs_crew"]):
			extra += " Crew cabin."
		blurb.text = "%s   %s\n%s%s" % [str(contract["customer"]), Company.money(int(contract["payout"])), str(contract["blurb"]), extra]
		blurb.add_theme_color_override("font_color", TEXT if selected else MUTED)
		blurb.add_theme_font_size_override("font_size", 14)
		contract_box.add_child(blurb)


func _fill_yard() -> void:
	_clear(yard_box)
	var reserve := CheckBox.new()
	reserve.text = "Hold propellant for a landing burn"
	reserve.button_pressed = company.reserve and company.reserve_allowed()
	reserve.disabled = not company.reserve_allowed()
	reserve.toggled.connect(_on_reserve)
	yard_box.add_child(reserve)
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Reuse needs the program, a gimbal, legs, and grid fins or flaps. Fixed fins do not come home."
	note.add_theme_color_override("font_color", MUTED)
	note.add_theme_font_size_override("font_size", 14)
	yard_box.add_child(note)
	for upgrade in company.catalog["upgrades"]:
		var owned := bool(company.upgrades.get(str(upgrade["id"]), false))
		var row := HBoxContainer.new()
		var name := Label.new()
		name.text = str(upgrade["name"])
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var cost := Label.new()
		cost.text = "In the yard" if owned else Company.money(int(upgrade["cost"]))
		cost.add_theme_font_override("font", _mono)
		cost.add_theme_color_override("font_color", GOOD if owned else GOLD)
		row.add_child(cost)
		if not owned:
			var button := Button.new()
			button.text = "Buy"
			var locked := bool(upgrade.get("requires_orbit", false)) and company.orbital_successes < 1
			button.disabled = locked or company.cash < int(upgrade["cost"])
			button.pressed.connect(_on_upgrade.bind(str(upgrade["id"])))
			row.add_child(button)
		yard_box.add_child(row)
		var blurb := Label.new()
		blurb.text = str(upgrade["blurb"])
		if bool(upgrade.get("requires_orbit", false)) and company.orbital_successes < 1:
			blurb.text += " One orbit has to be on the books first."
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.add_theme_color_override("font_color", MUTED)
		blurb.add_theme_font_size_override("font_size", 14)
		yard_box.add_child(blurb)
	var reset := Button.new()
	reset.text = "Click again to erase the company" if _reset_armed else "Reset company"
	reset.pressed.connect(_on_reset)
	yard_box.add_child(reset)


func _build_top() -> void:
	var bar := PanelContainer.new()
	bar.anchor_right = 1.0
	bar.offset_left = 12
	bar.offset_top = 10
	bar.offset_right = -12
	bar.offset_bottom = 58
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	var title := Label.new()
	title.text = "DOWNRANGE"
	title.add_theme_font_override("font", _semibold)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COPPER)
	row.add_child(title)
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(180, 0)
	name_edit.placeholder_text = "Independent"
	name_edit.focus_exited.connect(_on_name)
	name_edit.text_submitted.connect(_on_name_submitted)
	row.add_child(name_edit)
	var where := Label.new()
	where.text = "Cape Halcyon"
	where.add_theme_color_override("font_color", MUTED)
	row.add_child(where)
	cash_label = Label.new()
	cash_label.add_theme_font_override("font", _mono)
	cash_label.add_theme_font_size_override("font_size", 18)
	cash_label.add_theme_color_override("font_color", GOLD)
	cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(cash_label)
	mute_button = Button.new()
	mute_button.pressed.connect(_on_mute)
	row.add_child(mute_button)
	meta_label = Label.new()
	meta_label.anchor_right = 1.0
	meta_label.offset_left = 16
	meta_label.offset_top = 60
	meta_label.offset_right = -16
	meta_label.offset_bottom = 82
	meta_label.add_theme_font_override("font", _mono)
	meta_label.add_theme_font_size_override("font_size", 13)
	meta_label.add_theme_color_override("font_color", MUTED)
	meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(meta_label)


func _build_left() -> void:
	left_panel = _panel()
	left_panel.anchor_bottom = 1.0
	left_panel.offset_left = 12
	left_panel.offset_top = 86
	left_panel.offset_right = 408
	left_panel.offset_bottom = -16
	add_child(left_panel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	var heading := Label.new()
	heading.text = "STACK"
	heading.add_theme_font_override("font", _semibold)
	heading.add_theme_color_override("font_color", COPPER)
	box.add_child(heading)
	slot_box = VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 6)
	box.add_child(slot_box)
	banner = PanelContainer.new()
	banner_label = Label.new()
	banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_label.add_theme_font_override("font", _semibold)
	banner_label.add_theme_font_size_override("font_size", 18)
	banner.add_child(banner_label)
	box.add_child(banner)
	preview_label = Label.new()
	preview_label.add_theme_font_override("font", _mono)
	preview_label.add_theme_font_size_override("font_size", 14)
	preview_label.add_theme_color_override("font_color", TEXT)
	box.add_child(preview_label)
	hint_label = Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_color_override("font_color", MUTED)
	hint_label.add_theme_font_size_override("font_size", 14)
	box.add_child(hint_label)


func _build_right() -> void:
	right_panel = _panel()
	right_panel.anchor_left = 1.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_bottom = 1.0
	right_panel.offset_left = -460
	right_panel.offset_top = 86
	right_panel.offset_right = -12
	right_panel.offset_bottom = -84
	add_child(right_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(column)
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	for id in ["shop", "contracts", "yard"]:
		var button := Button.new()
		button.text = id.to_upper()
		button.pressed.connect(_on_tab.bind(id))
		tabs.add_child(button)
		_tab_buttons[id] = button
	shop_root = _scroller()
	contract_root = _scroller()
	yard_root = _scroller()
	shop_box = shop_root.get_child(0)
	contract_box = contract_root.get_child(0)
	yard_box = yard_root.get_child(0)
	column.add_child(shop_root)
	column.add_child(contract_root)
	column.add_child(yard_root)


func _build_launch() -> void:
	launch_button = Button.new()
	launch_button.anchor_left = 0.5
	launch_button.anchor_right = 0.5
	launch_button.anchor_top = 1.0
	launch_button.anchor_bottom = 1.0
	launch_button.offset_left = -190
	launch_button.offset_right = 190
	launch_button.offset_top = -70
	launch_button.offset_bottom = -16
	launch_button.add_theme_font_override("font", _semibold)
	launch_button.add_theme_font_size_override("font_size", 20)
	launch_button.add_theme_color_override("font_color", Color("1a120e"))
	var up := _flat(COPPER, 0)
	var down := _flat(COPPER.darkened(0.12), 0)
	launch_button.add_theme_stylebox_override("normal", up)
	launch_button.add_theme_stylebox_override("hover", _flat(COPPER.lightened(0.08), 0))
	launch_button.add_theme_stylebox_override("pressed", down)
	launch_button.add_theme_stylebox_override("disabled", _flat(Color(0.25, 0.22, 0.2), 0))
	launch_button.pressed.connect(func(): launch_pressed.emit())
	add_child(launch_button)


func _build_flight() -> void:
	flight_panel = _panel()
	flight_panel.anchor_top = 1.0
	flight_panel.anchor_bottom = 1.0
	flight_panel.offset_left = 16
	flight_panel.offset_right = 760
	flight_panel.offset_top = -150
	flight_panel.offset_bottom = -16
	flight_panel.visible = false
	add_child(flight_panel)
	var box := VBoxContainer.new()
	flight_panel.add_child(box)
	coast_label = Label.new()
	coast_label.text = "COAST"
	coast_label.add_theme_font_override("font", _semibold)
	coast_label.add_theme_font_size_override("font_size", 22)
	coast_label.add_theme_color_override("font_color", COPPER)
	coast_label.visible = false
	box.add_child(coast_label)
	flight_label = Label.new()
	flight_label.add_theme_font_override("font", _mono)
	flight_label.add_theme_font_size_override("font_size", 16)
	box.add_child(flight_label)
	event_label = Label.new()
	event_label.add_theme_color_override("font_color", MUTED)
	box.add_child(event_label)


func _build_debrief() -> void:
	debrief_panel = _panel()
	debrief_panel.anchor_left = 0.5
	debrief_panel.anchor_right = 0.5
	debrief_panel.anchor_top = 0.5
	debrief_panel.anchor_bottom = 0.5
	debrief_panel.offset_left = -280
	debrief_panel.offset_right = 280
	debrief_panel.offset_top = -230
	debrief_panel.offset_bottom = 230
	debrief_panel.visible = false
	add_child(debrief_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	debrief_panel.add_child(box)
	debrief_label = Label.new()
	debrief_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debrief_label.add_theme_font_override("font", _mono)
	debrief_label.add_theme_font_size_override("font_size", 15)
	debrief_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(debrief_label)
	var back := Button.new()
	back.text = "Return to the pad"
	back.pressed.connect(func(): returned_to_pad.emit())
	box.add_child(back)


func _scroller() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(400, 0)
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return scroll


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _flat(Color(0.07, 0.086, 0.078, 0.94), 12))
	return panel


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", TEXT)
	return label


func _paint_banner(color: Color, word: String) -> void:
	var style := _flat(Color(color.r, color.g, color.b, 0.18), 8)
	style.border_color = color
	style.border_width_left = 3
	banner.add_theme_stylebox_override("panel", style)
	banner_label.add_theme_color_override("font_color", color)
	banner_label.text = word


func _show_tab(id: String) -> void:
	tab = id
	shop_root.visible = id == "shop"
	contract_root.visible = id == "contracts"
	yard_root.visible = id == "yard"
	for key in _tab_buttons:
		var button: Button = _tab_buttons[key]
		button.add_theme_color_override("font_color", COPPER if key == id else MUTED)


func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.free()


func _on_slot(index: int, slot: String) -> void:
	var option: OptionButton = _options[slot]
	company.set_slot(slot, str(option.get_item_metadata(index)))
	call_deferred("refresh")


func _on_buy(id: String) -> void:
	company.buy_part(id)
	_reset_armed = false
	call_deferred("refresh")


func _on_starter() -> void:
	company.buy_starter()
	_reset_armed = false
	call_deferred("refresh")


func _on_contract(id: String) -> void:
	company.set_contract(id)
	_reset_armed = false
	call_deferred("refresh")


func _on_upgrade(id: String) -> void:
	company.buy_upgrade(id)
	_reset_armed = false
	call_deferred("refresh")


func _on_reserve(on: bool) -> void:
	company.set_reserve(on)
	call_deferred("refresh")


func _on_tab(id: String) -> void:
	_show_tab(id)


func _on_mute() -> void:
	company.muted = not company.muted
	company.save()
	refresh()


func _on_name() -> void:
	company.set_company_name(name_edit.text)
	if not name_edit.has_focus():
		name_edit.text = company.company_name


func _on_name_submitted(text: String) -> void:
	company.set_company_name(text)
	name_edit.release_focus()


func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		call_deferred("refresh")
		return
	_reset_armed = false
	company.reset_company()
	call_deferred("refresh")


func _load_fonts() -> void:
	_regular = load("res://assets/fonts/Barlow-Regular.ttf")
	_semibold = load("res://assets/fonts/Barlow-SemiBold.ttf")
	_mono = load("res://assets/fonts/IBMPlexMono-Regular.ttf")


func _make_theme() -> Theme:
	var made := Theme.new()
	if _regular:
		made.default_font = _regular
	made.default_font_size = 16
	made.set_color("font_color", "Label", TEXT)
	made.set_color("font_color", "Button", TEXT)
	made.set_color("font_hover_color", "Button", TEXT)
	made.set_color("font_pressed_color", "Button", TEXT)
	made.set_color("font_disabled_color", "Button", MUTED)
	made.set_stylebox("normal", "Button", _flat(Color(0.14, 0.16, 0.15), 8))
	made.set_stylebox("hover", "Button", _flat(Color(0.2, 0.22, 0.2), 8))
	made.set_stylebox("pressed", "Button", _flat(Color(0.1, 0.11, 0.1), 8))
	made.set_stylebox("disabled", "Button", _flat(Color(0.1, 0.11, 0.1), 8))
	made.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	made.set_color("font_color", "LineEdit", TEXT)
	made.set_color("caret_color", "LineEdit", COPPER)
	made.set_stylebox("normal", "LineEdit", _flat(Color(0.1, 0.12, 0.11), 6))
	made.set_color("font_color", "CheckBox", TEXT)
	made.set_color("font_color", "PopupMenu", TEXT)
	made.set_stylebox("panel", "PopupMenu", _flat(Color(0.1, 0.12, 0.11, 0.98), 6))
	made.set_stylebox("hover", "PopupMenu", _flat(Color(0.22, 0.16, 0.12), 4))
	return made


func _flat(color: Color, pad: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = pad
	style.content_margin_right = pad
	style.content_margin_top = pad * 0.6
	style.content_margin_bottom = pad * 0.6
	return style
