class_name M1Design
extends RefCounted
## Mission design for Mission 1, following the NASA mission-design loop:
##   Scientific goal -> Requirements -> Mission design -> Verification -> Launch -> Science results.
## Four segments are modelled: Launch (rocket), Space (satellite: power, battery, orbit),
## Ground (downlink to a ground station) and Users (what the science is worth).
##
## SIMPLIFICATIONS (stated honestly): one ground contact of fixed length per orbit, constant
## eclipse length, no orbit decay or radiation model, linear degradation of science value
## outside the best altitude window. The numbers are game-balanced, not mission-grade (GMAT).

const BUDGET := 200
const BUS_MASS := 480.0
const BUS_POWER := 40.0
const BUS_COST := 20
const PASS_SECONDS := 480.0          # ground-station contact per orbit
const ORBIT_SECONDS := 5400.0        # ~90 min
const ECLIPSE_HOURS := 0.6
const ORBITS_IN_MISSION := 100       # science campaign length (for "data returned")

const GOALS := {
	"earth": {"name": "M1D_GOAL_EARTH", "desc": "M1D_GOAL_EARTH_D", "instruments": ["img_s", "img_a"],
		"best": [90, 140], "ok": [80, 300], "duty": 0.05, "ap_target": 135000.0},
	"space": {"name": "M1D_GOAL_SPACE", "desc": "M1D_GOAL_SPACE_D", "instruments": ["mag_s", "mag_a"],
		"best": [150, 400], "ok": [90, 700], "duty": 0.09, "ap_target": 300000.0},
	"atmo": {"name": "M1D_GOAL_ATMO", "desc": "M1D_GOAL_ATMO_D", "instruments": ["spec_s", "spec_a"],
		"best": [85, 125], "ok": [80, 250], "duty": 0.08, "ap_target": 120000.0},
}
## mass kg, power W, data Mbps, cost $, sci = science multiplier, node = model node in satellite.glb
const INSTRUMENTS := {
	"img_s": {"name": "M1I_IMG_S", "mass": 180.0, "power": 110.0, "data": 6.0, "cost": 18, "sci": 0.66, "node": "inst_imager"},
	"img_a": {"name": "M1I_IMG_A", "mass": 260.0, "power": 170.0, "data": 12.0, "cost": 32, "sci": 1.0, "node": "inst_imager"},
	"mag_s": {"name": "M1I_MAG_S", "mass": 70.0, "power": 45.0, "data": 1.3, "cost": 10, "sci": 0.66, "node": "inst_mag"},
	"mag_a": {"name": "M1I_MAG_A", "mass": 120.0, "power": 90.0, "data": 2.6, "cost": 20, "sci": 1.0, "node": "inst_mag"},
	"spec_s": {"name": "M1I_SPEC_S", "mass": 120.0, "power": 80.0, "data": 2.5, "cost": 16, "sci": 0.66, "node": "inst_spec"},
	"spec_a": {"name": "M1I_SPEC_A", "mass": 190.0, "power": 130.0, "data": 5.0, "cost": 28, "sci": 1.0, "node": "inst_spec"},
}
const SOLAR := {
	"s": {"name": "M1S_S", "watts": 150.0, "mass": 45.0, "cost": 6, "scale": 0.7},
	"m": {"name": "M1S_M", "watts": 280.0, "mass": 85.0, "cost": 11, "scale": 1.0},
	"l": {"name": "M1S_L", "watts": 450.0, "mass": 140.0, "cost": 18, "scale": 1.3},
}
const BATTERY := {
	"s": {"name": "M1B_S", "wh": 60.0, "mass": 20.0, "cost": 4},
	"m": {"name": "M1B_M", "wh": 140.0, "mass": 45.0, "cost": 8},
	"l": {"name": "M1B_L", "wh": 260.0, "mass": 80.0, "cost": 14},
}
const COMM := {
	"uhf": {"name": "M1C_UHF", "mbps": 0.6, "power": 10.0, "mass": 8.0, "cost": 4, "scale": 0.5},
	"x": {"name": "M1C_X", "mbps": 4.0, "power": 25.0, "mass": 30.0, "cost": 9, "scale": 0.9},
	"ka": {"name": "M1C_KA", "mbps": 20.0, "power": 50.0, "mass": 65.0, "cost": 16, "scale": 1.4},
}

## Mission outcome thresholds (science return 0..1). A rocket reaching orbit is NOT enough: the satellite must work.
const SCI_MIN := 0.50      # below this the science objective failed (launch alone does not count)
const SCI_GOOD := 0.63     # 2 stars
const SCI_FULL := 0.74     # 3 stars (also needs a healthy hull, a reliable rocket and a frugal budget)
const EFF_COST := 0.92     # engineering efficiency: total cost share of the budget for 3 stars
const REL_FULL := 0.86

const LVL_OK := 0
const LVL_WARN := 1
const LVL_FAIL := 2


static func default_design() -> Dictionary:
	return {"goal": "earth", "instrument": "img_s", "solar": "m", "battery": "m", "comm": "x"}


## When the goal changes, keep choices valid.
static func set_goal(d: Dictionary, goal: String) -> void:
	d["goal"] = goal
	var list: Array = GOALS[goal]["instruments"]
	if not list.has(d["instrument"]):
		d["instrument"] = list[0]


# ------------------------------------------------------------- satellite ------
static func sat_stats(d: Dictionary) -> Dictionary:
	var ins: Dictionary = INSTRUMENTS[d["instrument"]]
	var sol: Dictionary = SOLAR[d["solar"]]
	var bat: Dictionary = BATTERY[d["battery"]]
	var com: Dictionary = COMM[d["comm"]]
	var goal: Dictionary = GOALS[d["goal"]]
	var mass := BUS_MASS + float(ins["mass"]) + float(sol["mass"]) + float(bat["mass"]) + float(com["mass"])
	var demand := BUS_POWER + float(ins["power"]) + float(com["power"])
	var gen := float(sol["watts"]) * 0.92                      # end-of-life degradation
	var need_wh := demand * ECLIPSE_HOURS / 0.8                # 80 % depth of discharge
	var produced := float(ins["data"]) * ORBIT_SECONDS * float(goal["duty"])      # Mbit / orbit
	var downlink := float(com["mbps"]) * PASS_SECONDS                              # Mbit / pass
	return {
		"mass": mass, "cost": BUS_COST + int(ins["cost"]) + int(sol["cost"]) + int(bat["cost"]) + int(com["cost"]),
		"demand": demand, "gen": gen, "power_ratio": gen / demand,
		"batt_wh": float(bat["wh"]), "batt_need": need_wh, "batt_ratio": float(bat["wh"]) / need_wh,
		"data_produced": produced, "data_downlink": downlink, "data_ratio": downlink / maxf(produced, 0.001),
		"sci": float(ins["sci"]),
	}


static func _level(ratio: float, ok_at: float, warn_at: float) -> int:
	if ratio >= ok_at:
		return LVL_OK
	if ratio >= warn_at:
		return LVL_WARN
	return LVL_FAIL


## Verification: list of requirement checks. rocket = M1Parts.compute(...) result (may be {}).
static func requirements(d: Dictionary, rocket: Dictionary) -> Array:
	var s := sat_stats(d)
	var goal: Dictionary = GOALS[d["goal"]]
	var out: Array = []
	out.append({"id": "orbit", "key": "REQ_ORBIT", "level": LVL_OK,
		"value": "%d-%d km" % [int(goal["best"][0]), int(goal["best"][1])], "hint": "REQH_ORBIT"})
	out.append({"id": "power", "key": "REQ_POWER", "level": _level(float(s["power_ratio"]), 1.0, 0.8),
		"value": "%d / %d W" % [int(s["gen"]), int(s["demand"])], "hint": "REQH_POWER"})
	out.append({"id": "batt", "key": "REQ_BATT", "level": _level(float(s["batt_ratio"]), 1.0, 0.7),
		"value": "%d / %d Wh" % [int(s["batt_wh"]), int(s["batt_need"])], "hint": "REQH_BATT"})
	out.append({"id": "data", "key": "REQ_DATA", "level": _level(float(s["data_ratio"]), 1.0, 0.5),
		"value": "%d / %d Mbit" % [int(s["data_downlink"]), int(s["data_produced"])], "hint": "REQH_DATA"})
	var best: Array = goal["best"]
	var pred_km := (float(best[0]) + float(best[1])) * 0.5
	var pr := science_result(d, pred_km * 1000.0, pred_km * 1000.0, 100.0)
	var psci := float(pr["science"])
	out.append({"id": "sci", "key": "REQ_SCI", "level": LVL_OK if psci >= SCI_GOOD else (LVL_WARN if psci >= SCI_MIN else LVL_FAIL),
		"value": "%d%%" % int(psci * 100.0), "hint": "REQH_SCI"})
	if not rocket.is_empty():
		var total := int(rocket["cost"])
		var lvl_b := LVL_OK if total <= BUDGET else LVL_FAIL
		out.append({"id": "budget", "key": "REQ_BUDGET", "level": lvl_b,
			"value": "%s / %s" % [Units.money(total), Units.money(BUDGET)], "hint": "REQH_BUDGET"})
		var launch_lvl := LVL_OK
		if not bool(rocket["complete"]) or float(rocket["twr"]) < 1.05:
			launch_lvl = LVL_FAIL
		elif float(rocket["twr"]) < 1.2 or float(rocket["dv"]) < M1Parts.REQUIRED_DV:
			launch_lvl = LVL_WARN
		var dv_lvl := LVL_OK if float(rocket["dv"]) >= M1Parts.REQUIRED_DV else (LVL_WARN if float(rocket["dv"]) >= M1Parts.REQUIRED_DV * 0.92 else LVL_FAIL)
		out.append({"id": "dv", "key": "REQ_DV", "level": dv_lvl,
			"value": "%d / %d %s" % [int(rocket["dv"]), int(M1Parts.REQUIRED_DV), TranslationServer.translate("UNIT_MS")], "hint": "REQH_DV"})
		var g_end := float(rocket["g_end"])
		var g_lvl := LVL_OK if g_end <= FlightModel.G_LIMIT else (LVL_WARN if g_end <= FlightModel.G_LIMIT * 1.5 else LVL_FAIL)
		out.append({"id": "gload", "key": "REQ_GLOAD", "level": g_lvl,
			"value": "%.1f g (%s %.1f g)" % [g_end / 9.81, TranslationServer.translate("REQ_LIMIT"), FlightModel.G_LIMIT / 9.81], "hint": "REQH_GLOAD"})
		var rl := LVL_OK if float(rocket["rel"]) >= 0.88 else (LVL_WARN if float(rocket["rel"]) >= 0.8 else LVL_FAIL)
		out.append({"id": "rel", "key": "REQ_REL", "level": rl, "value": "%d%%" % int(float(rocket["rel"]) * 100.0),
			"hint": "REQH_REL"})
		out.append({"id": "launch", "key": "REQ_LAUNCH", "level": launch_lvl,
			"value": "TWR %.2f | dv %d" % [float(rocket["twr"]), int(rocket["dv"])], "hint": "REQH_LAUNCH"})
	return out


static func worst_level(reqs: Array) -> int:
	var w := LVL_OK
	for r in reqs:
		w = maxi(w, int(r["level"]))
	return w


# --------------------------------------------------------------- science ------
static func window_score(alt_km: float, best: Array, ok: Array) -> float:
	if alt_km >= float(best[0]) and alt_km <= float(best[1]):
		return 1.0
	if alt_km < float(best[0]):
		return clampf(0.3 + 0.7 * (alt_km - float(ok[0])) / maxf(float(best[0]) - float(ok[0]), 1.0), 0.3, 1.0)
	return clampf(0.3 + 0.7 * (float(ok[1]) - alt_km) / maxf(float(ok[1]) - float(best[1]), 1.0), 0.3, 1.0)


## Science return once the satellite is in orbit. ap/pe in metres above the surface.
static func science_result(d: Dictionary, ap_m: float, pe_m: float, hull: float = 100.0) -> Dictionary:
	var s := sat_stats(d)
	var goal: Dictionary = GOALS[d["goal"]]
	var mean_km := (ap_m + pe_m) * 0.5 / 1000.0
	var orbit_q := window_score(mean_km, goal["best"], goal["ok"])
	var power_f := clampf(float(s["power_ratio"]), 0.0, 1.0)
	var batt_f := lerpf(0.4, 1.0, clampf(float(s["batt_ratio"]), 0.0, 1.0))
	var data_f := clampf(float(s["data_ratio"]), 0.0, 1.0)
	var hull_f := lerpf(0.5, 1.0, clampf(hull / 100.0, 0.0, 1.0))      # a damaged payload returns less science
	var science := float(s["sci"]) * orbit_q * power_f * batt_f * data_f * hull_f
	var gbit := float(s["data_produced"]) * float(ORBITS_IN_MISSION) * data_f / 1000.0
	var weakest := "good"
	var wv := 0.92
	for pair in [["power", power_f], ["batt", batt_f], ["data", data_f], ["orbit", orbit_q], ["hull", hull_f]]:
		if float(pair[1]) < wv:
			wv = float(pair[1])
			weakest = str(pair[0])
	return {
		"orbit_q": orbit_q, "power_f": power_f, "batt_f": batt_f, "data_f": data_f,
		"science": science, "hull_f": hull_f, "data_gb": gbit / 8.0, "mean_km": mean_km, "weakest": weakest,
		"sent_ratio": data_f,
	}


## 0 = poor, 1 = partial, 2 = good (drives the "science application" text).
static func science_tier(science: float) -> int:
	if science >= 0.9:
		return 2
	if science >= 0.5:
		return 1
	return 0


## Final judgement of a flight. flight = {orbit_ok, ap, pe, integrity}. rocket = M1Parts.compute result.
## stars: 0 = failed (no orbit OR the science objective was not met), 1 = partial science, 2 = success, 3 = full success.
static func evaluate(d: Dictionary, rocket: Dictionary, flight: Dictionary) -> Dictionary:
	var hull := float(flight.get("integrity", 100.0))
	var sr := science_result(d, float(flight["ap"]), float(flight["pe"]), hull)
	var science := float(sr["science"])
	var stars := 0
	var cause := ""
	if not bool(flight.get("orbit_ok", false)):
		cause = "orbit"
	elif science < SCI_MIN:
		cause = str(sr["weakest"])
		if cause == "good":
			cause = "weak"
	else:
		stars = 1
		if science >= SCI_GOOD:
			stars = 2
		if science >= SCI_FULL and hull >= 80.0 and float(rocket["cost"]) <= EFF_COST * float(BUDGET) and float(rocket["rel"]) >= REL_FULL:
			stars = 3
	return {"stars": stars, "science": science, "cause": cause, "sr": sr}


## MISSION SUCCESS PROXIMITY (0-100 %): how close the flight came to meeting EVERY mandatory requirement. It is NOT the
## scientific result (science return) and NOT campaign progress. Each requirement is scored continuously from the real
## flight outcome (a small miss keeps most of the points, a big miss loses them); passing them all gives exactly 100 %.
## flight = {orbit_ok, ap, pe, integrity, max_alt (m)}.  Returns {percent, reqs[], recs[], critical_failed, all_ok}.
const PROX_WEIGHTS := {"orbit": 20.0, "window": 10.0, "hull": 10.0, "power": 12.0, "batt": 8.0, "data": 15.0, "science": 25.0}
const PROX_HULL_MIN := 60.0
const PROX_RATIO_MIN := 0.75      # power / data link must cover at least this share of the demand
const PROX_BATT_MIN := 0.60       # battery capacity vs the eclipse need
const PROX_WINDOW_MIN := 0.75     # orbit-window quality (1 = inside the best altitude range)
const PROX_CRITICAL_CAP := 89      # a failed critical requirement (no orbit / science objective missed) can never look like a win


static func proximity(d: Dictionary, rocket: Dictionary, flight: Dictionary) -> Dictionary:
	var goal: Dictionary = GOALS[d["goal"]]
	var sat := sat_stats(d)
	var orbit_ok := bool(flight.get("orbit_ok", false))
	var ap := float(flight.get("ap", 0.0))
	var pe := float(flight.get("pe", -1.0e6))
	var hull := float(flight.get("integrity", 100.0))
	var max_alt := float(flight.get("max_alt", 0.0))
	var sr := science_result(d, ap, pe, hull) if orbit_ok else {}
	var reqs: Array = []
	# 1) reach a stable orbit (partial credit for how high / how close to a stable perigee the rocket got)
	var s_orbit := 1.0
	var d_orbit := TranslationServer.translate("MP_D_ORBIT_OK")
	if not orbit_ok:
		var reach := clampf(max_alt / (float(goal["ap_target"]) * 0.9), 0.0, 1.0) * 0.55
		if pe > 0.0 and ap > 0.0:
			reach += 0.40 * clampf(pe / FlightModel.SAFE_PE, 0.0, 1.0)
		s_orbit = clampf(reach, 0.0, 0.95)
		d_orbit = TranslationServer.translate("MP_D_ORBIT_NO") % int(max_alt / 1000.0)
	reqs.append({"id": "orbit", "key": "MP_R_ORBIT", "score": s_orbit, "ok": orbit_ok, "detail": d_orbit})
	# 2) orbit altitude inside the window this scientific goal needs
	var mean_km := (ap + pe) * 0.5 / 1000.0
	var s_win := 0.0
	var d_win := TranslationServer.translate("MP_D_NOT_REACHED")
	if orbit_ok:
		s_win = float(sr["orbit_q"])
		d_win = "%d km (%d-%d km)" % [int(mean_km), int(goal["best"][0]), int(goal["best"][1])]
	reqs.append({"id": "window", "key": "MP_R_WINDOW", "score": clampf(s_win / PROX_WINDOW_MIN, 0.0, 1.0), "ok": orbit_ok and s_win >= PROX_WINDOW_MIN, "detail": d_win})
	# 3) the vehicle / payload survived
	reqs.append({"id": "hull", "key": "MP_R_HULL", "score": clampf(hull / PROX_HULL_MIN, 0.0, 1.0), "ok": hull >= PROX_HULL_MIN,
		"detail": "%d%% (>= %d%%)" % [int(hull), int(PROX_HULL_MIN)]})
	# 4-6) satellite systems: power, battery, data link (ratios of supply to demand)
	for item in [["power", "MP_R_POWER", float(sat["power_ratio"]), PROX_RATIO_MIN], ["batt", "MP_R_BATT", float(sat["batt_ratio"]), PROX_BATT_MIN],
			["data", "MP_R_DATA", float(sat["data_ratio"]), PROX_RATIO_MIN]]:
		var ratio: float = item[2]
		var need: float = item[3]
		var sc := clampf(ratio / need, 0.0, 1.0) if orbit_ok else 0.0
		reqs.append({"id": item[0], "key": item[1], "score": sc, "ok": orbit_ok and ratio >= need,
			"detail": ("%d%% (>= %d%%)" % [int(ratio * 100.0), int(need * 100.0)]) if orbit_ok else TranslationServer.translate("MP_D_NOT_REACHED")})
	# 7) the scientific objective itself (science return reaching the minimum for a successful mission)
	var science := float(sr["science"]) if orbit_ok else 0.0
	reqs.append({"id": "science", "key": "MP_R_SCIENCE", "score": clampf(science / SCI_MIN, 0.0, 1.0), "ok": orbit_ok and science >= SCI_MIN,
		"detail": ("%d%% (>= %d%%)" % [int(science * 100.0), int(SCI_MIN * 100.0)]) if orbit_ok else TranslationServer.translate("MP_D_NOT_REACHED")})
	var total := 0.0
	var wsum := 0.0
	var all_ok := true
	for r in reqs:
		var w: float = PROX_WEIGHTS[r["id"]]
		total += w * float(r["score"])
		wsum += w
		if not bool(r["ok"]):
			all_ok = false
	var percent := int(floor(total / wsum * 100.0 + 0.5))
	var critical_failed: bool = not orbit_ok or science < SCI_MIN
	if all_ok:
		percent = 100
	else:
		percent = mini(percent, 99)
		if critical_failed:
			percent = mini(percent, PROX_CRITICAL_CAP)
	# recommendations: the failed requirements that cost the most points first
	var losses: Array = []
	for r in reqs:
		# a satellite that never reached orbit cannot be judged yet: only the launch itself is worth advice then
		if not orbit_ok and not (str(r["id"]) in ["orbit", "hull"]):
			continue
		if not bool(r["ok"]):
			losses.append([PROX_WEIGHTS[r["id"]] * (1.0 - float(r["score"])), str(r["id"])])
	losses.sort_custom(func(a, b): return a[0] > b[0])
	var recs: Array = []
	for l in losses:
		match str(l[1]):
			"orbit":
				recs.append("MP_REC_ORBIT")
			"window":
				recs.append("TIP_ORBIT_LOW" if mean_km < float(goal["best"][0]) else "TIP_ORBIT_HIGH")
			"hull":
				recs.append("TIP_HULL")
			"power":
				recs.append("TIP_POWER")
			"batt":
				recs.append("TIP_BATT")
			"data":
				recs.append("TIP_DATA")
			"science":
				recs.append("MP_REC_SCIENCE")
		if recs.size() >= 3:
			break
	return {"percent": percent, "reqs": reqs, "recs": recs, "critical_failed": critical_failed, "all_ok": all_ok}
