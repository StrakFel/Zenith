class_name LunarDesign
extends RefCounted
## Mission 2 - Lunar Expedition: design data + trade-off maths.
## Scientific objective -> mission design (site, launcher, lander, rover payload) -> verification ->
## launch -> trans-lunar injection (TLI) planning -> powered descent -> surface science -> data downlink.
##
## HONEST LIMITS: patched-conic style numbers with real Earth/Moon constants for the TLI ellipse, but the
## lunar orbit insertion is a fixed delta-v cost, the descent is a 2-D lander game, the surface day is
## shortened, comms delay is shown but not simulated frame-by-frame. This teaches the trade-offs; it is
## not a GMAT-grade trajectory analysis.

const BUDGET := 230
const MU_EARTH := 3.986004418e14
const R_EARTH := 6_371_000.0
const LEO_ALT := 200_000.0
const MOON_DIST := 384_400_000.0
const MOON_SOI := 66_100_000.0
const G0 := 9.80665
const MOON_G := 1.62
const LOI_DV := 900.0               # lunar orbit insertion + descent prep (fixed cost)
const DESCENT_DV_OK := 300.0        # delta-v the powered descent comfortably needs
const DESCENT_DV_MIN := 200.0
const LANDER_DRY := 650.0           # structure, legs, avionics (kg)
const LANDER_COST := 40
const EXPLORE_HOURS := 2.0          # length of the (shortened) lunar-day science window
const UPLINK_SECONDS := 1200.0      # Earth-visible window used for the downlink
const SAMPLE_SECONDS := 600.0       # instrument time per sample (data volume = rate x this)
const ONE_WAY_DELAY := 1.28         # Earth-Moon light time (s)

const SITES := {
	"mare": {"name": "LUN_SITE_MARE", "desc": "LUN_SITE_MARE_D", "rough": 0.25, "sun": 1.0, "sci": 1.0, "bonus": "cam"},
	"pole": {"name": "LUN_SITE_POLE", "desc": "LUN_SITE_POLE_D", "rough": 0.65, "sun": 0.55, "sci": 1.6, "bonus": "drill"},
	"swirl": {"name": "LUN_SITE_SWIRL", "desc": "LUN_SITE_SWIRL_D", "rough": 0.40, "sun": 0.9, "sci": 1.3, "bonus": "mag"},
}
const LAUNCHERS := {
	"medium": {"name": "LUN_LAUNCH_M", "tli_mass": 3600.0, "cost": 60},
	"heavy": {"name": "LUN_LAUNCH_H", "tli_mass": 5400.0, "cost": 100},
}
const ENGINES := {
	"std": {"name": "LUN_ENG_STD", "isp": 310.0, "thrust": 9000.0, "mass": 90.0, "cost": 14},
	"hp": {"name": "LUN_ENG_HP", "isp": 335.0, "thrust": 13000.0, "mass": 140.0, "cost": 26},
}
## propellant load (kg); tank dry mass = 9 % of it
const TANKS := {
	"s": {"name": "LUN_TANK_S", "prop": 1100.0, "cost": 10},
	"m": {"name": "LUN_TANK_M", "prop": 1700.0, "cost": 15},
	"l": {"name": "LUN_TANK_L", "prop": 2400.0, "cost": 21},
}
const ROVERS := {
	"scout": {"name": "LUN_ROV_SCOUT", "mass": 70.0, "cost": 20, "speed": 3.0},
	"explorer": {"name": "LUN_ROV_EXPL", "mass": 140.0, "cost": 38, "speed": 4.2},
}
const INSTRUMENTS := {
	"cam": {"name": "LUN_INS_CAM", "mass": 18.0, "power": 25.0, "data": 2.0, "sci": 1.0, "cost": 10},
	"drill": {"name": "LUN_INS_DRILL", "mass": 42.0, "power": 70.0, "data": 1.0, "sci": 1.2, "cost": 22},
	"mag": {"name": "LUN_INS_MAG", "mass": 26.0, "power": 30.0, "data": 1.5, "sci": 1.1, "cost": 14},
}
const SOLAR := {
	"s": {"name": "LUN_SOL_S", "watts": 60.0, "mass": 10.0, "cost": 4},
	"m": {"name": "LUN_SOL_M", "watts": 120.0, "mass": 22.0, "cost": 8},
	"l": {"name": "LUN_SOL_L", "watts": 220.0, "mass": 40.0, "cost": 14},
}
const BATTERY := {
	"s": {"name": "LUN_BAT_S", "wh": 150.0, "mass": 12.0, "cost": 5},
	"m": {"name": "LUN_BAT_M", "wh": 400.0, "mass": 30.0, "cost": 11},
	"l": {"name": "LUN_BAT_L", "wh": 900.0, "mass": 65.0, "cost": 20},
}
const COMM := {
	"dte": {"name": "LUN_COM_DTE", "mbps": 0.5, "power": 12.0, "mass": 6.0, "cost": 5},
	"hga": {"name": "LUN_COM_HGA", "mbps": 4.0, "power": 35.0, "mass": 22.0, "cost": 12},
}

const LVL_OK := 0
const LVL_WARN := 1
const LVL_FAIL := 2


static func default_design() -> Dictionary:
	return {"site": "mare", "launcher": "heavy", "engine": "std", "tank": "m", "rover": "scout",
		"instrument": "cam", "solar": "m", "battery": "m", "comm": "hga"}


# ----------------------------------------------------------------- spacecraft ---
static func stats(d: Dictionary) -> Dictionary:
	var site: Dictionary = SITES[d["site"]]
	var lau: Dictionary = LAUNCHERS[d["launcher"]]
	var eng: Dictionary = ENGINES[d["engine"]]
	var tank: Dictionary = TANKS[d["tank"]]
	var rov: Dictionary = ROVERS[d["rover"]]
	var ins: Dictionary = INSTRUMENTS[d["instrument"]]
	var sol: Dictionary = SOLAR[d["solar"]]
	var bat: Dictionary = BATTERY[d["battery"]]
	var com: Dictionary = COMM[d["comm"]]
	var prop := float(tank["prop"])
	var rover_mass := float(rov["mass"]) + float(ins["mass"]) + float(sol["mass"]) + float(bat["mass"]) + float(com["mass"])
	var dry := LANDER_DRY + float(eng["mass"]) + prop * 0.09 + rover_mass
	var m0 := dry + prop
	var isp := float(eng["isp"])
	var dv_total := isp * G0 * log(m0 / dry)
	# lunar orbit insertion burns propellant first
	var m_loi := m0 / exp(LOI_DV / (isp * G0))
	var prop_after_loi := maxf(m_loi - dry, 0.0)
	var dv_descent := isp * G0 * log(m_loi / dry) if prop_after_loi > 0.0 else 0.0
	var twr := float(eng["thrust"]) / (m_loi * MOON_G)
	# rover energy (shortened lunar day)
	var need_w := 12.0 + 55.0 * 0.5 + float(ins["power"]) * 0.4 + float(com["power"]) * 0.2
	var supply_wh := float(sol["watts"]) * float(site["sun"]) * EXPLORE_HOURS + float(bat["wh"])
	var need_wh := need_w * EXPLORE_HOURS
	var data_per_sample := float(ins["data"]) * SAMPLE_SECONDS            # Mbit
	var data_total := data_per_sample * 3.0
	var uplink := float(com["mbps"]) * UPLINK_SECONDS
	var bonus := 1.3 if str(site["bonus"]) == str(d["instrument"]) else 1.0
	return {
		"mass_tli": m0, "tli_cap": float(lau["tli_mass"]), "dry": dry, "prop": prop,
		"dv_total": dv_total, "dv_descent": dv_descent, "twr": twr, "prop_descent": prop_after_loi,
		"mass_descent": m_loi, "power_ratio": supply_wh / need_wh, "supply_wh": supply_wh, "need_wh": need_wh,
		"data_total": data_total, "uplink": uplink, "data_ratio": uplink / maxf(data_total, 0.001),
		"cost": LANDER_COST + int(lau["cost"]) + int(eng["cost"]) + int(tank["cost"]) + int(rov["cost"])
			+ int(ins["cost"]) + int(sol["cost"]) + int(bat["cost"]) + int(com["cost"]),
		"bonus": bonus, "sci_mult": float(site["sci"]) * float(ins["sci"]) * bonus,
		"rover_speed": float(rov["speed"]), "rough": float(site["rough"]), "sun": float(site["sun"]),
		"thrust": float(eng["thrust"]), "isp": isp, "rover_mass": rover_mass,
	}


static func _lvl(ratio: float, ok: float, warn: float) -> int:
	if ratio >= ok:
		return LVL_OK
	if ratio >= warn:
		return LVL_WARN
	return LVL_FAIL


static func requirements(d: Dictionary) -> Array:
	var s := stats(d)
	var site: Dictionary = SITES[d["site"]]
	var out: Array = []
	var mass_lvl := LVL_OK
	if float(s["mass_tli"]) > float(s["tli_cap"]):
		mass_lvl = LVL_FAIL
	elif float(s["mass_tli"]) > float(s["tli_cap"]) * 0.95:
		mass_lvl = LVL_WARN
	out.append({"id": "mass", "key": "LUNREQ_MASS", "level": mass_lvl,
		"value": "%d / %d kg" % [int(s["mass_tli"]), int(s["tli_cap"])], "hint": "LUNREQH_MASS"})
	out.append({"id": "dv", "key": "LUNREQ_DV", "level": _lvl(float(s["dv_descent"]), DESCENT_DV_OK, DESCENT_DV_MIN),
		"value": "%d m/s" % int(s["dv_descent"]), "hint": "LUNREQH_DV"})
	out.append({"id": "twr", "key": "LUNREQ_TWR", "level": _lvl(float(s["twr"]), 1.6, 1.3),
		"value": "%.2f" % float(s["twr"]), "hint": "LUNREQH_TWR"})
	out.append({"id": "power", "key": "LUNREQ_POWER", "level": _lvl(float(s["power_ratio"]), 1.0, 0.8),
		"value": "%d / %d Wh" % [int(s["supply_wh"]), int(s["need_wh"])], "hint": "LUNREQH_POWER"})
	out.append({"id": "data", "key": "LUNREQ_DATA", "level": _lvl(float(s["data_ratio"]), 1.0, 0.5),
		"value": "%d / %d Mbit" % [int(s["uplink"]), int(s["data_total"])], "hint": "LUNREQH_DATA"})
	var syn := LVL_OK if float(s["bonus"]) > 1.0 else LVL_WARN
	out.append({"id": "synergy", "key": "LUNREQ_SYNERGY", "level": syn,
		"value": "x%.1f" % float(s["bonus"]), "hint": "LUNREQH_SYNERGY"})
	var bl := LVL_OK if int(s["cost"]) <= BUDGET else LVL_FAIL
	out.append({"id": "budget", "key": "REQ_BUDGET", "level": bl, "value": "%s / %s" % [Units.money(int(s["cost"])), Units.money(BUDGET)],
		"hint": "REQH_BUDGET"})
	return out


static func worst_level(reqs: Array) -> int:
	var w := LVL_OK
	for r in reqs:
		w = maxi(w, int(r["level"]))
	return w


## The rocket can only be launched if the lander fits the launcher and the budget holds.
static func can_launch(d: Dictionary) -> bool:
	var s := stats(d)
	return float(s["mass_tli"]) <= float(s["tli_cap"]) and int(s["cost"]) <= BUDGET and float(s["prop_descent"]) > 0.0


# --------------------------------------------------------------------- TLI -------
## Apogee (m, from Earth's centre) of the transfer ellipse for a burn of `dv` m/s from 200 km LEO.
static func tli_apogee(dv: float) -> float:
	var r1 := R_EARTH + LEO_ALT
	var v := sqrt(MU_EARTH / r1) + dv
	var inv_a := 2.0 / r1 - v * v / MU_EARTH
	if inv_a <= 0.0:
		return INF
	return 2.0 / inv_a - r1


static func ideal_tli_dv() -> float:
	var r1 := R_EARTH + LEO_ALT
	var a := (r1 + MOON_DIST) * 0.5
	return sqrt(MU_EARTH * (2.0 / r1 - 1.0 / a)) - sqrt(MU_EARTH / r1)


## Miss distance at the Moon's orbit (m).
static func tli_miss(dv: float) -> float:
	var ra := tli_apogee(dv)
	return INF if ra == INF else absf(ra - MOON_DIST)


## 0 = clean intercept, 1 = needs a mid-course correction (costs descent delta-v), 2 = missed the Moon.
static func tli_outcome(dv: float) -> int:
	var miss := tli_miss(dv)
	if miss <= MOON_SOI * 0.35:
		return 0
	if miss <= MOON_SOI * 1.2:
		return 1
	return 2


## delta-v (m/s) spent on the mid-course correction for a given TLI burn.
static func correction_dv(dv: float) -> float:
	var miss := tli_miss(dv)
	if miss <= MOON_SOI * 0.35:
		return 0.0
	return clampf((miss - MOON_SOI * 0.35) / (MOON_SOI * 0.85) * 140.0, 0.0, 140.0)


static func window_text(dv: float) -> String:
	return "%d m/s" % int(dv)
