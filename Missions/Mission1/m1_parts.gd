class_name M1Parts
extends RefCounted
## Rocket parts catalogue + design maths (mass, thrust-to-weight, delta-v, cost).

const G0 := 9.80665
const BUDGET := 170
const PAYLOAD_MASS := 1000.0  # the satellite (kg)
const REQUIRED_DV := 5200.0   # rough delta-v needed for orbit in this scaled-down world (m/s)

const SLOTS: Array[String] = ["nose", "tank", "engine"]

const NOSES: Dictionary = {
	"std": {"rel": 0.99, "name": "M1_NOSE_STD", "desc": "M1_NOSE_STD_D", "mass": 500.0, "cost": 10, "cd": 0.30, "h": 70.0},
	"aero": {"rel": 0.97, "name": "M1_NOSE_AERO", "desc": "M1_NOSE_AERO_D", "mass": 650.0, "cost": 22, "cd": 0.20, "h": 100.0},
}
const TANKS: Dictionary = {
	"s": {"rel": 0.99, "name": "M1_TANK_S", "desc": "M1_TANK_S_D", "dry": 650.0, "fuel": 7000.0, "cost": 12, "h": 70.0},
	"m": {"rel": 0.98, "name": "M1_TANK_M", "desc": "M1_TANK_M_D", "dry": 1500.0, "fuel": 17000.0, "cost": 22, "h": 110.0},
	"l": {"rel": 0.96, "name": "M1_TANK_L", "desc": "M1_TANK_L_D", "dry": 2600.0, "fuel": 32000.0, "cost": 38, "h": 160.0},
}
const ENGINES: Dictionary = {
	"spark": {"rel": 0.95, "name": "M1_ENG_SPARK", "desc": "M1_ENG_SPARK_D", "mass": 700.0, "thrust": 180000.0,
		"isp_sl": 290.0, "isp_vac": 330.0, "cost": 15, "h": 38.0, "w": 30.0},
	"kestrel": {"rel": 0.96, "name": "M1_ENG_KESTREL", "desc": "M1_ENG_KESTREL_D", "mass": 1500.0, "thrust": 420000.0,
		"isp_sl": 310.0, "isp_vac": 360.0, "cost": 28, "h": 48.0, "w": 40.0},
	"phoenix": {"rel": 0.92, "name": "M1_ENG_PHOENIX", "desc": "M1_ENG_PHOENIX_D", "mass": 2800.0, "thrust": 800000.0,
		"isp_sl": 330.0, "isp_vac": 380.0, "cost": 50, "h": 60.0, "w": 50.0},
}


static func catalog(slot: String) -> Dictionary:
	match slot:
		"nose":
			return NOSES
		"tank":
			return TANKS
		_:
			return ENGINES


static func part_stat_lines(slot: String, id: String) -> Array:
	## Returns [[label_key, value_text], ...] for the catalogue card.
	var p: Dictionary = catalog(slot)[id]
	match slot:
		"nose":
			return [["M1_ST_MASS", Units.kg(float(p["mass"]))], ["M1_ST_DRAG", "%.2f" % float(p["cd"])], ["M1_ST_REL", "%d%%" % int(float(p["rel"]) * 100.0)]]
		"tank":
			return [["M1_ST_FUEL", Units.kg(float(p["fuel"]))], ["M1_ST_MASS", Units.kg(float(p["dry"]))], ["M1_ST_REL", "%d%%" % int(float(p["rel"]) * 100.0)]]
		_:
			return [["M1_ST_THRUST", Units.kn(float(p["thrust"]))],
				["M1_ST_ISP", Units.sec(float(p["isp_vac"]))], ["M1_ST_MASS", Units.kg(float(p["mass"]))],
				["M1_ST_REL", "%d%%" % int(float(p["rel"]) * 100.0)]]


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
	var wet := dry + fuel
	out["cost"] = cost
	out["over_budget"] = cost > BUDGET
	out["mass_dry"] = dry
	out["mass_wet"] = wet
	out["fuel"] = fuel
	out["thrust"] = thrust
	out["cd"] = cd
	out["rel"] = rel
	out["isp_sl"] = isp_sl
	out["isp_vac"] = isp_vac
	out["twr"] = thrust / (wet * 9.81) if wet > 0.0 else 0.0
	out["dv"] = isp_vac * G0 * log(wet / dry) if (isp_vac > 0.0 and fuel > 0.0) else 0.0
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
	if float(stats["dv"]) < REQUIRED_DV:
		msgs.append("M1_RDY_DV_LOW")
	if msgs.is_empty():
		msgs.append("M1_RDY_OK")
	return msgs


static func can_launch(stats: Dictionary) -> bool:
	return bool(stats["complete"]) and not bool(stats["over_budget"]) and float(stats["twr"]) >= 1.05



