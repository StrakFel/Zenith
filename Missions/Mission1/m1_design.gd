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

const BUDGET := 170
const BUS_MASS := 480.0
const BUS_POWER := 40.0
const BUS_COST := 20
const PASS_SECONDS := 480.0          # ground-station contact per orbit
const ORBIT_SECONDS := 5400.0        # ~90 min
const ECLIPSE_HOURS := 0.6
const ORBITS_IN_MISSION := 100       # science campaign length (for "data returned")

const GOALS := {
	"earth": {"name": "M1D_GOAL_EARTH", "desc": "M1D_GOAL_EARTH_D", "instruments": ["img_s", "img_a"],
		"best": [90, 140], "ok": [80, 300], "duty": 0.08},
	"space": {"name": "M1D_GOAL_SPACE", "desc": "M1D_GOAL_SPACE_D", "instruments": ["mag_s", "mag_a"],
		"best": [150, 400], "ok": [90, 700], "duty": 0.08},
	"atmo": {"name": "M1D_GOAL_ATMO", "desc": "M1D_GOAL_ATMO_D", "instruments": ["spec_s", "spec_a"],
		"best": [85, 125], "ok": [80, 250], "duty": 0.08},
}
## mass kg, power W, data Mbps, cost $, sci = science multiplier, node = model node in satellite.glb
const INSTRUMENTS := {
	"img_s": {"name": "M1I_IMG_S", "mass": 180.0, "power": 110.0, "data": 6.0, "cost": 18, "sci": 1.0, "node": "inst_imager"},
	"img_a": {"name": "M1I_IMG_A", "mass": 260.0, "power": 170.0, "data": 12.0, "cost": 32, "sci": 1.5, "node": "inst_imager"},
	"mag_s": {"name": "M1I_MAG_S", "mass": 70.0, "power": 45.0, "data": 0.8, "cost": 10, "sci": 1.0, "node": "inst_mag"},
	"mag_a": {"name": "M1I_MAG_A", "mass": 120.0, "power": 80.0, "data": 1.5, "cost": 20, "sci": 1.5, "node": "inst_mag"},
	"spec_s": {"name": "M1I_SPEC_S", "mass": 120.0, "power": 80.0, "data": 2.5, "cost": 16, "sci": 1.0, "node": "inst_spec"},
	"spec_a": {"name": "M1I_SPEC_A", "mass": 190.0, "power": 130.0, "data": 5.0, "cost": 28, "sci": 1.5, "node": "inst_spec"},
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
	if not rocket.is_empty():
		var total := int(rocket["cost"])
		var lvl_b := LVL_OK if total <= BUDGET else LVL_FAIL
		out.append({"id": "budget", "key": "REQ_BUDGET", "level": lvl_b,
			"value": "$%d / $%d" % [total, BUDGET], "hint": "REQH_BUDGET"})
		var launch_lvl := LVL_OK
		if not bool(rocket["complete"]) or float(rocket["twr"]) < 1.05:
			launch_lvl = LVL_FAIL
		elif float(rocket["twr"]) < 1.2 or float(rocket["dv"]) < M1Parts.REQUIRED_DV:
			launch_lvl = LVL_WARN
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
static func science_result(d: Dictionary, ap_m: float, pe_m: float) -> Dictionary:
	var s := sat_stats(d)
	var goal: Dictionary = GOALS[d["goal"]]
	var mean_km := (ap_m + pe_m) * 0.5 / 1000.0
	var orbit_q := window_score(mean_km, goal["best"], goal["ok"])
	var power_f := clampf(float(s["power_ratio"]), 0.0, 1.0)
	var batt_f := lerpf(0.4, 1.0, clampf(float(s["batt_ratio"]), 0.0, 1.0))
	var data_f := clampf(float(s["data_ratio"]), 0.0, 1.0)
	var science := float(s["sci"]) * orbit_q * power_f * batt_f * data_f
	var gbit := float(s["data_produced"]) * float(ORBITS_IN_MISSION) * data_f / 1000.0
	var weakest := "good"
	var wv := 0.92
	for pair in [["power", power_f], ["batt", batt_f], ["data", data_f], ["orbit", orbit_q]]:
		if float(pair[1]) < wv:
			wv = float(pair[1])
			weakest = str(pair[0])
	return {
		"orbit_q": orbit_q, "power_f": power_f, "batt_f": batt_f, "data_f": data_f,
		"science": science, "data_gb": gbit / 8.0, "mean_km": mean_km, "weakest": weakest,
		"sent_ratio": data_f,
	}


## 0 = poor, 1 = partial, 2 = good (drives the "science application" text).
static func science_tier(science: float) -> int:
	if science >= 0.9:
		return 2
	if science >= 0.5:
		return 1
	return 0
