extends RefCounted
class_name AscentSim

## Point-mass ascent. Suborbital flights loft. Orbital flights cut off, coast
## to apogee, and circularize with the kick stage. Same math the balance pass used.

const G0 := 9.80665
const MU := 3.986004418e14
const R_E := 6371000.0
const H_SCALE := 8400.0
const RHO0 := 1.225
const DT := 0.05

func fly(cat: Dictionary, loadout: Dictionary, contract: Dictionary, reserve: bool, record: bool) -> Dictionary:
	var parts: Dictionary = cat["by_id"]
	var core: Dictionary = parts[loadout["core"]]
	var engine: Dictionary = parts[loadout["engine"]]
	var booster: Dictionary = parts[loadout["booster"]] if str(loadout.get("booster", "")) != "" else {}
	var upper: Dictionary = parts[loadout["upper"]] if str(loadout.get("upper", "")) != "" else {}
	var cabin: Dictionary = parts[loadout["cabin"]]
	var aero: Dictionary = parts[loadout["aero"]] if str(loadout.get("aero", "")) != "" else {}
	var gimbal: Dictionary = parts["gimbal"] if str(loadout.get("gimbal", "")) != "" else {}
	var legs: Dictionary = parts["legs"] if str(loadout.get("legs", "")) != "" else {}
	var fairing: Dictionary = parts["fairing"] if str(loadout.get("fairing", "")) != "" else {}
	var payload := float(contract["payload"])
	var has_gimbal := not gimbal.is_empty()
	var has_aero := not aero.is_empty()
	var has_upper := not upper.is_empty()
	var has_booster := not booster.is_empty()
	var srb_thrust := float(booster.get("thrust_sl", 0.0))
	var liftoff_thrust := float(engine["thrust_sl"]) + srb_thrust
	if liftoff_thrust > float(core["max_thrust"]):
		return _blank("buckle", "Thrust exceeds what this core can hold.", 0.0)

	var area := PI * pow(float(core["diameter"]) * 0.5, 2.0)
	if has_booster:
		area += float(booster["count"]) * PI * pow(float(booster["diameter"]) * 0.5, 2.0)
	if has_aero:
		area *= {"fins": 1.06, "grid": 1.1, "flaps": 1.16}[str(aero["control"])]
	var cd_a := float(core["cd"]) * area

	var dry_land := float(core["dry"]) + float(engine["mass"])
	if has_aero:
		dry_land += float(aero["mass"])
	if has_gimbal:
		dry_land += float(gimbal["mass"])
	if not legs.is_empty():
		dry_land += float(legs["mass"])
	var reserve_kg := 0.0
	var reserve_fit := false
	var landing_dv := float(aero.get("landing_dv", 0.0))
	if reserve and has_gimbal and not legs.is_empty() and has_aero and landing_dv > 0.0 and landing_dv < 5000.0:
		var ratio := exp(landing_dv / (float(engine["isp_sl"]) * G0))
		reserve_kg = dry_land * (ratio - 1.0)
		reserve_fit = reserve_kg < float(core["prop"]) * 0.4
		if not reserve_fit:
			reserve_kg = 0.0
	var ascent_prop := float(core["prop"]) - reserve_kg
	var mass := float(core["dry"]) + float(engine["mass"]) + ascent_prop + reserve_kg + float(cabin["mass"]) + payload
	if has_booster:
		mass += float(booster["dry"]) + float(booster["prop"])
	if has_upper:
		mass += float(upper["dry"]) + float(upper["prop"])
	if has_aero:
		mass += float(aero["mass"])
	if has_gimbal:
		mass += float(gimbal["mass"])
	if not legs.is_empty():
		mass += float(legs["mass"])
	if not fairing.is_empty():
		mass += float(fairing["mass"])
	var twr := liftoff_thrust / (mass * G0)
	if liftoff_thrust < mass * G0 * 1.03:
		return _blank("no_liftoff", "TWR %.2f. It sat on the pad and burned." % twr, twr)

	var h := 2.0
	var downrange := 0.0
	var vr := 0.0
	var vt := 0.0
	var pitch := 90.0
	var core_prop := ascent_prop
	var srb_prop := float(booster.get("prop", 0.0))
	var kick_prop := float(upper.get("prop", 0.0))
	var srb_attached := has_booster
	var kick_live := false
	var sep_timer := -1.0
	var fairing_on := not fairing.is_empty()
	var max_q := 0.0
	var max_h := h
	var err_time := 0.0
	var t := 0.0
	var outcome := "flew"
	var reason := ""
	var destroyed := false
	var asym_loss := 0.97 if (has_booster and bool(booster.get("asym", false)) and has_gimbal) else 1.0
	var circularizing := false
	var inserted := false
	var kind := str(contract["kind"])
	var desired_apo := float(contract["perigee_m"]) + 80000.0 if kind == "orbital" else 1.0e12
	var events: PackedStringArray = PackedStringArray()
	var samples: Array = []
	var sample_acc := 0.0
	var saw_liftoff := false

	while t < 900.0 and not destroyed:
		if has_booster and bool(booster.get("asym", false)) and not has_gimbal and srb_attached and t >= 3.5:
			outcome = "tumble"
			reason = "Single SRB and no gimbal. It left the pad sideways."
			destroyed = true
			events.append("T+%.0fs  lost control" % t)
			break
		var core_burning := core_prop > 0.05 and sep_timer < 0.0
		var srb_burning := srb_attached and srb_prop > 0.05
		var apo_now: float = _osc(h, vr, vt)[2]
		var suppress_kick := kind == "orbital" and not circularizing and apo_now >= desired_apo and h > 90000.0
		var kick_burning := kick_live and kick_prop > 0.05 and not suppress_kick
		var speed := sqrt(vr * vr + vt * vt)
		var rho := RHO0 * _sigma(h)
		var q := 0.5 * rho * speed * speed
		max_q = maxf(max_q, q)
		var throttle := _bucket(q, float(core["max_q"])) if core_burning else 1.0
		if q > float(core["max_q"]):
			outcome = "structural"
			reason = "Max-q %.0f kPa buckled the core." % (q / 1000.0)
			destroyed = true
			events.append("T+%.0fs  structural failure" % t)
			break
		if not has_aero and not has_gimbal and q > 5000.0:
			outcome = "tumble"
			reason = "No fins and no gimbal. It tumbled once the air got hold of it."
			destroyed = true
			events.append("T+%.0fs  tumbled" % t)
			break
		if not saw_liftoff and t > 0.2:
			saw_liftoff = true
			events.append("T+0s  liftoff")

		var thrust := 0.0
		if core_burning:
			thrust += _thrust(engine, h, throttle) * asym_loss
		if srb_burning:
			thrust += _thrust(booster, h, 1.0)
		if kick_burning:
			thrust += _thrust(upper, h, 1.0)

		var want := 2.0 if circularizing else _pitch_target(h, kind)
		var rate := 0.04
		if has_gimbal and (core_burning or kick_burning):
			rate = 12.0
		elif has_aero and q > 250.0:
			rate = 5.0
		elif has_aero:
			rate = 0.3
		pitch += clampf(want - pitch, -rate * DT, rate * DT)
		if absf(want - pitch) > 14.0 and q > 9000.0:
			err_time += DT
			if err_time > 2.5:
				outcome = "tumble"
				reason = "Guidance could not hold the turn."
				destroyed = true
				events.append("T+%.0fs  tumbled in the turn" % t)
				break
		else:
			err_time = 0.0

		var radius := R_E + h
		var drag := q * cd_a
		var pr := deg_to_rad(pitch)
		var a_tr := sin(pr) * thrust / mass
		var a_tt := cos(pr) * thrust / mass
		var a_dr := 0.0
		var a_dt := 0.0
		if speed > 0.4:
			a_dr = -drag * vr / speed / mass
			a_dt = -drag * vt / speed / mass
		var grav := MU / (radius * radius)
		vr += (a_tr + a_dr - grav + (vt * vt) / radius) * DT
		vt += (a_tt + a_dt - (vr * vt) / radius) * DT
		h += vr * DT
		downrange += vt * DT
		max_h = maxf(max_h, h)
		t += DT

		if core_burning:
			var take := minf(core_prop, _mdot(engine, h, throttle) * DT)
			core_prop -= take
			mass -= take
		if srb_burning:
			var take_s := minf(srb_prop, _mdot(booster, h, 1.0) * DT)
			srb_prop -= take_s
			mass -= take_s
			if srb_prop <= 0.05:
				mass -= float(booster["dry"])
				srb_attached = false
				events.append("T+%.0fs  SRB separation" % t)
				cd_a = float(core["cd"]) * PI * pow(float(core["diameter"]) * 0.5, 2.0)
				if has_aero:
					cd_a *= {"fins": 1.06, "grid": 1.1, "flaps": 1.16}[str(aero["control"])]
		if kick_burning:
			var take_k := minf(kick_prop, _mdot(upper, h, 1.0) * DT)
			kick_prop -= take_k
			mass -= take_k
		if fairing_on and h > 105000.0 and q < 200.0:
			mass -= float(fairing["mass"])
			fairing_on = false
			events.append("T+%.0fs  fairing jettison" % t)
		if sep_timer < 0.0 and core_prop <= 0.05 and has_upper and not kick_live:
			var drop := float(core["dry"]) + float(engine["mass"]) + reserve_kg
			if has_aero:
				drop += float(aero["mass"])
			if has_gimbal:
				drop += float(gimbal["mass"])
			if not legs.is_empty():
				drop += float(legs["mass"])
			if srb_attached:
				drop += float(booster["dry"]) + maxf(srb_prop, 0.0)
				srb_attached = false
			mass -= drop
			if mass < 40.0:
				outcome = "structural"
				reason = "Staging left nothing to fly."
				destroyed = true
				break
			sep_timer = 1.6
			events.append("T+%.0fs  stage separation" % t)
		elif sep_timer > 0.0:
			sep_timer -= DT
			if sep_timer <= 0.0:
				kick_live = true
				sep_timer = -2.0
				events.append("T+%.0fs  upper stage ignition" % t)

		if kind == "orbital" and not destroyed:
			var el := _osc(h, vr, vt)
			if core_prop > 0.05 and sep_timer < 0.0 and h > 70000.0 and el[0] < 0.0 and el[2] >= desired_apo:
				core_prop = 0.0
				events.append("T+%.0fs  MECO, apogee is set" % t)
			if not circularizing and has_upper and kick_live and el[0] < 0.0 and el[2] >= desired_apo and h > 110000.0 and vr > 0.0:
				var jumped := _jump_apo(h, vr, vt)
				if not jumped.is_empty():
					var old_h := h
					h = jumped[0]
					vr = jumped[1]
					vt = jumped[2]
					downrange += maxf(0.0, (h - old_h) * 0.25)
					max_h = maxf(max_h, h)
					circularizing = true
					pitch = 2.0
					events.append("Coast to apogee, then the circularization burn")
			if circularizing and kick_prop > 0.05:
				var el2 := _osc(h, vr, vt)
				if el2[0] < 0.0 and el2[1] >= float(contract["perigee_m"]):
					kick_prop = 0.0
					inserted = true
					events.append("SECO, orbit closed")
		var prop_left := kick_prop if (has_upper and kick_live) else 0.0
		var burns_done := core_prop <= 0.05 and (not srb_attached or srb_prop <= 0.05) and prop_left <= 0.05 and sep_timer < 0.0
		if record:
			sample_acc += DT
			if sample_acc >= 0.25 or inserted:
				sample_acc = 0.0
				samples.append([t, h, downrange, pitch, throttle if core_burning else (1.0 if kick_burning else 0.0), 1.0 if srb_attached else 0.0, 0.0 if kick_live else 1.0])
		if h < 0.0 and t > 2.0:
			outcome = "impact"
			reason = "It came back down."
			events.append("Impact")
			break
		if inserted:
			break
		if burns_done and vr < 0.0:
			break

	var end := _osc(h, vr, vt)
	var energy: float = end[0]
	var perigee: float = end[1]
	var apogee := maxf(max_h, end[2] if energy < 0.0 and end[2] < 1.0e11 else max_h)
	if energy >= 0.0:
		apogee = maxf(apogee, 99999000.0)
		perigee = -1.0
	var ok := false
	if destroyed:
		ok = false
	elif kind == "suborbital":
		ok = apogee >= float(contract["apogee_m"]) and outcome == "flew"
		if not ok and outcome == "flew":
			outcome = "short"
			reason = "Apogee %.0f km. The contract wanted %.0f km." % [apogee / 1000.0, float(contract["apogee_m"]) / 1000.0]
	else:
		ok = perigee >= float(contract["perigee_m"]) and apogee > perigee and outcome == "flew"
		if not ok and outcome == "flew":
			outcome = "short"
			reason = "Perigee %.0f km. The contract wanted %.0f km." % [perigee / 1000.0, float(contract["perigee_m"]) / 1000.0]
	if ok:
		outcome = "success"
		reason = "Contract met."
		events.append("Contract met")
	var q_ok := has_aero and max_q <= float(aero.get("q_limit", 0.0))
	var recovered := (not destroyed) and reserve_fit and has_gimbal and not legs.is_empty() and q_ok and max_h > 30000.0
	if recovered:
		events.append("Booster recovered")
	elif reserve and not reserve_fit:
		events.append("Not enough propellant to reserve a landing")
	var recovered_cabin := ok and bool(cabin.get("crew", false)) and kind == "suborbital"
	if recovered_cabin:
		events.append("Crew cabin under canopy")
	return {
		"ok": ok,
		"outcome": outcome,
		"reason": reason,
		"apogee_m": apogee,
		"perigee_m": perigee,
		"max_q": max_q,
		"twr": twr,
		"recovered": recovered,
		"recovered_cabin": recovered_cabin,
		"events": events,
		"samples": samples,
		"h": h,
		"vt": vt,
	}


func _blank(outcome: String, reason: String, twr: float) -> Dictionary:
	return {
		"ok": false,
		"outcome": outcome,
		"reason": reason,
		"apogee_m": 0.0,
		"perigee_m": -1.0,
		"max_q": 0.0,
		"twr": twr,
		"recovered": false,
		"recovered_cabin": false,
		"events": PackedStringArray([reason]),
		"samples": [],
		"h": 0.0,
		"vt": 0.0,
	}


func _sigma(h: float) -> float:
	return 1.0 if h <= 0.0 else minf(1.0, exp(-h / H_SCALE))


func _thrust(part: Dictionary, h: float, throttle: float) -> float:
	var sigma := _sigma(h)
	var isp := float(part["isp_sl"]) * sigma + float(part["isp_vac"]) * (1.0 - sigma)
	var mdot := float(part["thrust_sl"]) / (float(part["isp_sl"]) * G0) * throttle
	return mdot * isp * G0


func _mdot(part: Dictionary, h: float, throttle: float) -> float:
	return float(part["thrust_sl"]) / (float(part["isp_sl"]) * G0) * throttle


func _pitch_target(h: float, kind: String) -> float:
	if kind == "suborbital":
		if h < 1000.0:
			return 90.0
		var t := clampf((h - 1000.0) / 16000.0, 0.0, 1.0)
		return 90.0 + (82.0 - 90.0) * t
	if h < 300.0:
		return 90.0
	var u := clampf((h - 300.0) / 42000.0, 0.0, 1.0)
	return 90.0 + (6.0 - 90.0) * pow(u, 0.65)


func _bucket(q: float, limit: float) -> float:
	var start := limit * 0.30
	if q <= start:
		return 1.0
	return clampf(1.0 - 0.75 * (q - start) / maxf(limit - start, 1.0), 0.22, 1.0)


func _osc(h: float, vr: float, vt: float) -> PackedFloat64Array:
	var radius := R_E + maxf(h, 1.0)
	var energy := (vr * vr + vt * vt) / 2.0 - MU / radius
	if energy >= -1.0:
		return PackedFloat64Array([energy, -1.0e6, 1.0e12])
	var a := -MU / (2.0 * energy)
	var hmom := radius * vt
	var e := sqrt(maxf(0.0, 1.0 + 2.0 * energy * hmom * hmom / (MU * MU)))
	return PackedFloat64Array([energy, a * (1.0 - e) - R_E, a * (1.0 + e) - R_E])


func _jump_apo(h: float, vr: float, vt: float) -> Array:
	var el := _osc(h, vr, vt)
	var energy: float = el[0]
	var apo: float = el[2]
	if energy >= 0.0 or apo < h:
		return []
	var r_a := R_E + apo
	var a := -MU / (2.0 * energy)
	var speed := sqrt(maxf(0.0, MU * (2.0 / r_a - 1.0 / a)))
	return [apo, 0.0, speed]
