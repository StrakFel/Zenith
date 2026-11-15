class_name M1Parts
extends RefCounted
## Rocket parts catalogue + design maths (mass, thrust-to-weight, delta-v, cost).

const G0 := 9.80665
const BUDGET := 200
## Budget (points) of the mission that is being designed right now. Missions 2-5 set it from their launch profile.
static var active_budget := 200
static var active_required_dv := 5200.0
const PAYLOAD_MASS := 1000.0  # the satellite (kg)
const REQUIRED_DV := 5200.0   # rough delta-v needed for orbit in this scaled-down world (m/s)

const SLOTS: Array[String] = ["nose", "upper", "tank", "engine", "booster"]
## Campaign progression: the 1-based mission in which a part becomes available (missing = available from Mission 1).
const UNLOCK := {"tank:xl": 2, "upper:u_h": 3, "booster:b_s": 4, "booster:b_l": 4, "engine:titan": 5, "upper:u_t": 5}
static var active_mission := 1
const FAIRING_SHARE := 0.85    # share of the nose mass that is the fairing (dropped when it is jettisoned)

## Optional second stage: its own tank + vacuum engine. thrust is the sea-level equivalent (same convention as ENGINES).
const UPPERS: Dictionary = {
	"u_s": {"rel": 0.96, "name": "M1_UP_S", "desc": "M1_UP_S_D", "dry": 450.0, "fuel": 4200.0, "thrust": 110000.0,
		"isp_sl": 255.0, "isp_vac": 380.0, "cost": 26, "h": 12.0, "w": 40.0},
	"u_m": {"rel": 0.94, "name": "M1_UP_M", "desc": "M1_UP_M_D", "dry": 900.0, "fuel": 9000.0, "thrust": 190000.0,
		"isp_sl": 260.0, "isp_vac": 392.0, "cost": 44, "h": 17.0, "w": 40.0},
	"u_h": {"rel": 0.93, "name": "M1_UP_H", "desc": "M1_UP_H_D", "dry": 1300.0, "fuel": 14000.0, "thrust": 230000.0,
		"isp_sl": 270.0, "isp_vac": 440.0, "cost": 62, "h": 20.0, "w": 40.0},
	"u_t": {"rel": 0.92, "name": "M1_UP_T", "desc": "M1_UP_T_D", "dry": 2200.0, "fuel": 26000.0, "thrust": 320000.0,
		"isp_sl": 275.0, "isp_vac": 450.0, "cost": 95, "h": 26.0, "w": 44.0},
}
## Strap-on boosters (optional, Mission 4+): `count` identical side boosters burn together with the core engine and are dropped when empty.
const BOOSTERS: Dictionary = {
	"b_s": {"rel": 0.95, "name": "M1_BST_S", "desc": "M1_BST_S_D", "count": 2, "dry": 4400.0, "fuel": 36000.0, "thrust": 900000.0,
		"isp_sl": 235.0, "isp_vac": 262.0, "cost": 40, "h": 90.0},
	"b_l": {"rel": 0.93, "name": "M1_BST_L", "desc": "M1_BST_L_D", "count": 4, "dry": 11000.0, "fuel": 90000.0, "thrust": 2400000.0,
		"isp_sl": 240.0, "isp_vac": 268.0, "cost": 88, "h": 110.0},
}

const NOSES: Dictionary = {
	"std": {"rel": 0.99, "name": "M1_NOSE_STD", "desc": "M1_NOSE_STD_D", "mass": 500.0, "cost": 10, "cd": 0.30, "h": 70.0},
	"aero": {"rel": 0.97, "name": "M1_NOSE_AERO", "desc": "M1_NOSE_AERO_D", "mass": 650.0, "cost": 22, "cd": 0.20, "h": 100.0},
}
const TANKS: Dictionary = {
	"s": {"rel": 0.99, "name": "M1_TANK_S", "desc": "M1_TANK_S_D", "dry": 650.0, "fuel": 7000.0, "cost": 12, "h": 70.0},
	"m": {"rel": 0.98, "name": "M1_TANK_M", "desc": "M1_TANK_M_D", "dry": 1500.0, "fuel": 17000.0, "cost": 22, "h": 110.0},
	"l": {"rel": 0.96, "name": "M1_TANK_L", "desc": "M1_TANK_L_D", "dry": 2600.0, "fuel": 32000.0, "cost": 38, "h": 160.0},
	"xl": {"rel": 0.94, "name": "M1_TANK_XL", "desc": "M1_TANK_XL_D", "dry": 5200.0, "fuel": 68000.0, "cost": 66, "h": 230.0},
}
const ENGINES: Dictionary = {
	"spark": {"rel": 0.95, "name": "M1_ENG_SPARK", "desc": "M1_ENG_SPARK_D", "mass": 700.0, "thrust": 180000.0,
		"isp_sl": 290.0, "isp_vac": 330.0, "cost": 15, "h": 38.0, "w": 30.0},
	"kestrel": {"rel": 0.96, "name": "M1_ENG_KESTREL", "desc": "M1_ENG_KESTREL_D", "mass": 1500.0, "thrust": 420000.0,
		"isp_sl": 310.0, "isp_vac": 360.0, "cost": 28, "h": 48.0, "w": 40.0},
	"phoenix": {"rel": 0.92, "name": "M1_ENG_PHOENIX", "desc": "M1_ENG_PHOENIX_D", "mass": 2800.0, "thrust": 800000.0,
		"isp_sl": 330.0, "isp_vac": 380.0, "cost": 50, "h": 60.0, "w": 50.0},
	"titan": {"rel": 0.9, "name": "M1_ENG_TITAN", "desc": "M1_ENG_TITAN_D", "mass": 5200.0, "thrust": 1700000.0,
		"isp_sl": 320.0, "isp_vac": 385.0, "cost": 92, "h": 70.0, "w": 60.0},
}


static func catalog(slot: String) -> Dictionary:
	match slot:
		"nose":
			return NOSES
		"tank":
			return TANKS
		"upper":
			return UPPERS
		"booster":
			return BOOSTERS
		_:
			return ENGINES


## True when the part is available in the mission being designed (progressive unlocks).
static func is_unlocked(slot: String, id: String) -> bool:
	return int(UNLOCK.get("%s:%s" % [slot, id], 1)) <= active_mission


static func unlocked_ids(slot: String) -> Array:
	var out: Array = []
	for id in catalog(slot):
		if is_unlocked(slot, id):
			out.append(id)
	return out


## Returns [[label_key, text, number, direction], ...]; direction +1 = higher is better, -1 = lower is better.
## The number lets the catalogue show how a part compares with the one that is installed now.
static func part_stat_lines(slot: String, id: String) -> Array:
	var p: Dictionary = catalog(slot)[id]
	var rel: Array = ["M1_ST_REL", "%d%%" % int(float(p["rel"]) * 100.0), float(p["rel"]) * 100.0, 1]
	match slot:
		"nose":
			return [["M1_ST_MASS", Units.kg(float(p["mass"])), float(p["mass"]), -1],
				["M1_ST_DRAG", "%.2f" % float(p["cd"]), float(p["cd"]), -1], rel]
		"tank":
			return [["M1_ST_FUEL", Units.kg(float(p["fuel"])), float(p["fuel"]), 1],
				["M1_ST_MASS", Units.kg(float(p["dry"])), float(p["dry"]), -1], rel]
		"booster":
			return [["M1_ST_COUNT", "x%d" % int(p["count"]), float(p["count"]), 1],
				["M1_ST_FUEL", Units.kg(float(p["fuel"])), float(p["fuel"]), 1],
				["M1_ST_THRUST", Units.kn(float(p["thrust"])), float(p["thrust"]) / 1000.0, 1], rel]
		"upper":
			return [["M1_ST_FUEL", Units.kg(float(p["fuel"])), float(p["fuel"]), 1],
				["M1_ST_THRUST", Units.kn(float(p["thrust"])), float(p["thrust"]) / 1000.0, 1],
				["M1_ST_ISP", Units.sec(float(p["isp_vac"])), float(p["isp_vac"]), 1], rel]
		_:
			return [["M1_ST_THRUST", Units.kn(float(p["thrust"])), float(p["thrust"]) / 1000.0, 1],
				["M1_ST_ISP", Units.sec(float(p["isp_vac"])), float(p["isp_vac"]), 1],
				["M1_ST_MASS", Units.kg(float(p["mass"])), float(p["mass"]), -1], rel]


## build = {"nose": id, "tank": id, "engine": id} ("" = empty).
static func compute(build: Dictionary, payload: float = PAYLOAD_MASS, extra_cost: int = 0) -> Dictionary:
	var n := str(build.get("nose", ""))
	var t := str(build.get("tank", ""))
	var e := str(build.get("engine", ""))
	var out: Dictionary = {"complete": false, "cost": 0, "over_budget": false}
	var cost := extra_cost
	var dry := payload
	var fuel := 0.0
	var thrust := 0.0
	var cd := 0.45
	var rel := 1.0
	var isp_sl := 0.0
	var isp_vac := 0.0
	if n != "":
		cost += int(NOSES[n]["cost"])
		dry += float(NOSES[n]["mass"])
		cd = float(NOSES[n]["cd"]) + 0.08
		rel *= float(NOSES[n]["rel"])
	if t != "":
		cost += int(TANKS[t]["cost"])
		dry += float(TANKS[t]["dry"])
		fuel = float(TANKS[t]["fuel"])
		rel *= float(TANKS[t]["rel"])
	if e != "":
		cost += int(ENGINES[e]["cost"])
		dry += float(ENGINES[e]["mass"])
		thrust = float(ENGINES[e]["thrust"])
		isp_sl = float(ENGINES[e]["isp_sl"])
		isp_vac = float(ENGINES[e]["isp_vac"])
		rel *= float(ENGINES[e]["rel"])
	# optional upper stage (jettisoned stage 1 = tank + engine)
	var u := str(build.get("upper", ""))
	var stage1_dry := 0.0
	if t != "":
		stage1_dry += float(TANKS[t]["dry"])
	if e != "":
		stage1_dry += float(ENGINES[e]["mass"])
	var reserve := 0.0
	out["stages"] = 1
	if u != "":
		var up: Dictionary = UPPERS[u]
		cost += int(up["cost"])
		dry += float(up["dry"])
		reserve = float(up["fuel"])
		rel *= float(up["rel"])
		out["stages"] = 2
		out["u_thrust"] = float(up["thrust"])
		out["u_isp_sl"] = float(up["isp_sl"])
		out["u_isp_vac"] = float(up["isp_vac"])
		out["u_dry"] = float(up["dry"])
	out["reserve"] = reserve
	out["stage1_dry"] = stage1_dry
	out["fairing_mass"] = float(NOSES[n]["mass"]) * FAIRING_SHARE if n != "" else 0.0
	# optional strap-on boosters (burn together with the core engine, dropped when empty)
	var bo := str(build.get("booster", ""))
	var b_dry := 0.0
	var b_fuel := 0.0
	var b_thrust := 0.0
	out["boosters"] = 0
	if bo != "":
		var bp: Dictionary = BOOSTERS[bo]
		cost += int(bp["cost"])
		b_dry = float(bp["dry"])
		b_fuel = float(bp["fuel"])
		b_thrust = float(bp["thrust"])
		dry += b_dry
		rel *= float(bp["rel"])
		out["boosters"] = int(bp["count"])
		out["b_isp_sl"] = float(bp["isp_sl"])
		out["b_isp_vac"] = float(bp["isp_vac"])
	out["b_dry"] = b_dry
	out["b_fuel"] = b_fuel
	out["b_thrust"] = b_thrust
	var wet := dry + fuel + reserve + b_fuel
	out["cost"] = cost
	out["over_budget"] = cost > active_budget
	out["mass_dry"] = dry
	out["mass_wet"] = wet
	out["fuel"] = fuel
	out["thrust"] = thrust
	out["thrust_total"] = thrust + b_thrust
	out["cd"] = cd
	out["rel"] = rel
	out["isp_sl"] = isp_sl
	out["isp_vac"] = isp_vac
	out["twr"] = (thrust + b_thrust) / (wet * 9.81) if wet > 0.0 else 0.0
	var dv := isp_vac * G0 * log(wet / (dry + reserve)) if (isp_vac > 0.0 and fuel > 0.0) else 0.0
	var core_used := 0.0
	if bo != "" and fuel > 0.0 and isp_sl > 0.0:
		# phase 0: boosters + core burn together; then the empty boosters are dropped and the core carries on
		var mdot_c := thrust / (isp_sl * G0)
		var mdot_b := b_thrust / (float(out["b_isp_sl"]) * G0)
		var t_b := b_fuel / maxf(mdot_b, 0.001)
		core_used = minf(fuel, mdot_c * t_b)
		var m1 := wet - b_fuel - core_used
		var f_vac := thrust * isp_vac / isp_sl + b_thrust * float(out["b_isp_vac"]) / float(out["b_isp_sl"])
		var isp_eff := f_vac / ((mdot_c + mdot_b) * G0)
		var dv0 := isp_eff * G0 * log(wet / m1)
		var m1p := m1 - b_dry
		var m_after := dry - b_dry + reserve
		dv = dv0 + isp_vac * G0 * log(m1p / m_after)
	if u != "" and fuel > 0.0:
		# two-stage rocket equation: stage 1 burns with the upper stage on top, then stage 1 is dropped
		var m_sep := dry - b_dry + reserve - stage1_dry
		var m_up_dry := m_sep - reserve
		dv += float(out["u_isp_vac"]) * G0 * log(m_sep / maxf(m_up_dry, 1.0))
	out["dv"] = dv
	# acceleration of the LAST stage near burnout (m/s^2, vacuum): the pilot must throttle down above FlightModel.G_LIMIT
	var m_end := dry - b_dry - (stage1_dry if u != "" else 0.0)
	var t_last := thrust * (isp_vac / maxf(isp_sl, 1.0))
	if u != "":
		t_last = float(out["u_thrust"]) * float(out["u_isp_vac"]) / float(out["u_isp_sl"])
	out["g_end"] = t_last / maxf(m_end, 1.0)
	out["complete"] = n != "" and t != "" and e != ""
	return out


## Short advice keys for the readiness panel.
static func readiness(stats: Dictionary) -> Array[String]:
	var msgs: Array[String] = []
	if not bool(stats["complete"]):
		msgs.append("M1_RDY_INCOMPLETE")
		return msgs
	if bool(stats["over_budget"]):
		msgs.append("M1_RDY_BUDGET")
	if float(stats["rel"]) < 0.86:
		msgs.append("M1_RDY_REL")
	if float(stats["twr"]) < 1.15:
		msgs.append("M1_RDY_TWR_LOW")
	elif float(stats["twr"]) > 2.6:
		msgs.append("M1_RDY_TWR_HIGH")
	if float(stats["dv"]) < active_required_dv:
		msgs.append("M1_RDY_DV_LOW")
		if int(stats["stages"]) == 1:
			msgs.append("M1_RDY_TRY_UPPER")
	if msgs.is_empty():
		msgs.append("M1_RDY_OK")
	return msgs


static func can_launch(stats: Dictionary) -> bool:
	return bool(stats["complete"]) and not bool(stats["over_budget"]) and float(stats["twr"]) >= 1.05



