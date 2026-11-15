class_name LaunchProfiles
extends RefCounted
## Campaign backbone: every mission 2-5 starts with the SAME rocket designer + launch as Mission 1 (the "launch segment"),
## configured by a profile: which payload the player designs, the money available, the target orbit and the scene that
## continues the mission. The launch result is handed over (GameState.session) and changes what the operations phase gives.
##
##   payload lab (what do we deliver?) -> rocket designer -> validation -> launch -> orbit -> hand-off -> operations -> results
##
## Money is in budget points (Units.money shows them as notional millions). Mass in kg.

const ORDER := ["m1", "m2", "m3", "m4", "m5"]

const PROFILES := {
	"m2": {"index": 2, "mission_id": "m2_space_ops", "budget": 190, "ap_target": 150000.0, "best": [100, 220], "ok": [80, 330],
		"next": "res://Missions/Spacewalk/spacewalk.tscn", "title": "M2_TITLE", "lab_title": "OPS_LAB_TITLE", "lab_sub": "OPS_LAB_SUB",
		"base_mass": 520.0, "base_cost": 24},
	"m3": {"index": 3, "mission_id": "m3_iss", "budget": 205, "ap_target": 180000.0, "best": [140, 260], "ok": [80, 380],
		"next": "res://Missions/Mission3/mission3.tscn", "title": "M3_TITLE", "lab_title": "ISS_LAB_TITLE", "lab_sub": "ISS_LAB_SUB",
		"base_mass": 380.0, "base_cost": 20},
	"m4": {"index": 4, "mission_id": "m4_constellation", "budget": 330, "ap_target": 420000.0, "best": [250, 450], "ok": [90, 700],
		"next": "res://Missions/Mission4/mission4_ops.tscn", "title": "M4_TITLE", "lab_title": "CON_LAB_TITLE", "lab_sub": "CON_LAB_SUB",
		"base_mass": 700.0, "base_cost": 24},
	"m5": {"index": 5, "mission_id": "m5_moon", "budget": 560, "ap_target": 200000.0, "best": [150, 320], "ok": [80, 600],
		"next": "res://Missions/Mission5/mission5_ops.tscn", "title": "M5_TITLE", "lab_title": "MOON_LAB_TITLE", "lab_sub": "MOON_LAB_SUB",
		"base_mass": 1500.0, "base_cost": 30},
}

# ---- Mission 2: equipment for the spacewalk (oxygen, thruster gas, suit)
const EVA_O2 := {"s": {"name": "OPS_O2_S", "mass": 60.0, "cost": 6, "k": 0.7}, "m": {"name": "OPS_O2_M", "mass": 100.0, "cost": 10, "k": 1.0},
	"l": {"name": "OPS_O2_L", "mass": 150.0, "cost": 15, "k": 1.4}}
const EVA_N2 := {"s": {"name": "OPS_N2_S", "mass": 40.0, "cost": 5, "k": 0.6}, "m": {"name": "OPS_N2_M", "mass": 70.0, "cost": 9, "k": 1.0},
	"l": {"name": "OPS_N2_L", "mass": 110.0, "cost": 14, "k": 1.5}}
const EVA_SUIT := {"std": {"name": "OPS_SUIT_STD", "mass": 30.0, "cost": 6, "k": 1.0}, "armor": {"name": "OPS_SUIT_ARM", "mass": 80.0, "cost": 14, "k": 1.6}}

# ---- Mission 4: satellite class, count, dispenser
const CON_SAT := {"small": {"name": "CON_SAT_S", "mass": 220.0, "cost": 9, "cap": 1.0}, "medium": {"name": "CON_SAT_M", "mass": 480.0, "cost": 20, "cap": 1.7}}
const CON_COUNT := {"3": {"name": "CON_N3", "n": 3}, "4": {"name": "CON_N4", "n": 4}, "6": {"name": "CON_N6", "n": 6}}
const CON_DISP := {"simple": {"name": "CON_DISP_S", "mass": 120.0, "cost": 6, "tol": 1.0}, "precision": {"name": "CON_DISP_P", "mass": 220.0, "cost": 16, "tol": 1.8}}

# ---- Mission 5: return capsule + ascent stage (the lunar lander itself uses LunarDesign)
const MOON_CAPSULE := {"light": {"name": "MOON_CAP_L", "mass": 900.0, "cost": 28, "shield": 1.0}, "heavy": {"name": "MOON_CAP_H", "mass": 1400.0, "cost": 46, "shield": 1.6}}
const MOON_ASCENT := {"s": {"name": "MOON_ASC_S", "mass": 700.0, "cost": 14, "dv": 1750.0}, "m": {"name": "MOON_ASC_M", "mass": 1100.0, "cost": 24, "dv": 2300.0}}
const MOON_TLI_NEEDED := 3150.0    # delta-v the launcher must still have after reaching the parking orbit (see LunarDesign.ideal_tli_dv)


static func get_profile(id: String) -> Dictionary:
	return PROFILES.get(id, {})


static func default_design(id: String) -> Dictionary:
	match id:
		"m2":
			return {"o2": "m", "n2": "m", "suit": "std"}
		"m3":
			return IssDesign.default_design().duplicate()
		"m4":
			return {"sat": "small", "count": "4", "disp": "simple"}
		_:
			var d := LunarDesign.default_design()
			d["capsule"] = "light"
			d["ascent"] = "s"
			return d


## Option groups shown in the payload lab: [{id, title, options: [{id, name, info, cost}]}]
static func groups(id: String) -> Array:
	var kg := func(v: float) -> String: return Units.kg(v)
	match id:
		"m2":
			return [
				{"id": "o2", "title": "OPS_OPT_O2", "options": _opts(EVA_O2, func(d): return "%s | x%.1f %s" % [kg.call(d["mass"]), d["k"], TranslationServer.translate("OPS_ST_O2")])},
				{"id": "n2", "title": "OPS_OPT_N2", "options": _opts(EVA_N2, func(d): return "%s | x%.1f %s" % [kg.call(d["mass"]), d["k"], TranslationServer.translate("OPS_ST_N2")])},
				{"id": "suit", "title": "OPS_OPT_SUIT", "options": _opts(EVA_SUIT, func(d): return "%s | x%.1f %s" % [kg.call(d["mass"]), d["k"], TranslationServer.translate("OPS_ST_SUIT")])},
			]
		"m3":
			var ex: Array = []
			for k in IssDesign.EXPERIMENTS:
				var e: Dictionary = IssDesign.EXPERIMENTS[k]
				ex.append({"id": k, "name": e["name"], "info": "%s | x%.1f %s | x%.1f %s" % [kg.call(e["mass"]), e["sci"], TranslationServer.translate("LUN_F_SCI"), e["fragile"], TranslationServer.translate("ISS_ST_FRAG")], "cost": int(e["cost"])})
			var rc: Array = []
			for k in IssDesign.RCS:
				var r: Dictionary = IssDesign.RCS[k]
				rc.append({"id": k, "name": r["name"], "info": "%s | %d%%" % [kg.call(r["mass"]), int(float(r["fuel"]) * 100.0)], "cost": int(r["cost"])})
			return [{"id": "experiment", "title": "ISS_OPT_EXP", "options": ex}, {"id": "rcs", "title": "ISS_OPT_RCS", "options": rc}]
		"m4":
			return [
				{"id": "sat", "title": "CON_OPT_SAT", "options": _opts(CON_SAT, func(d): return "%s | x%.1f %s" % [kg.call(d["mass"]), d["cap"], TranslationServer.translate("CON_ST_CAP")])},
				{"id": "count", "title": "CON_OPT_COUNT", "options": _count_opts()},
				{"id": "disp", "title": "CON_OPT_DISP", "options": _opts(CON_DISP, func(d): return "%s | x%.1f %s" % [kg.call(d["mass"]), d["tol"], TranslationServer.translate("CON_ST_TOL")])},
			]
		_:
			var out: Array = []
			for item in [["site", "LUN_STEP_SITE", LunarDesign.SITES], ["rover", "LUN_OPT_ROVER", LunarDesign.ROVERS], ["instrument", "LUN_OPT_INSTR", LunarDesign.INSTRUMENTS],
					["solar", "LUN_OPT_SOLAR", LunarDesign.SOLAR], ["battery", "LUN_OPT_BATT", LunarDesign.BATTERY], ["comm", "LUN_OPT_COMM", LunarDesign.COMM],
					["tank", "LUN_OPT_TANK", LunarDesign.TANKS]]:
				var op: Array = []
				for k in item[2]:
					var d: Dictionary = item[2][k]
					var info := ""
					if d.has("mass"):
						info = Units.kg(float(d["mass"]))
					elif d.has("prop"):
						info = "%s %s" % [Units.kg(float(d["prop"])), TranslationServer.translate("LUN_PROP")]
					elif d.has("watts"):
						info = "%d %s" % [int(d["watts"]), TranslationServer.translate("UNIT_W")]
					elif d.has("rough"):
						info = "%s %.0f%%" % [TranslationServer.translate("LUN_F_ROUGH"), float(d["rough"]) * 100.0]
					op.append({"id": k, "name": d["name"], "info": info, "cost": int(d.get("cost", 0))})
				out.append({"id": item[0], "title": item[1], "options": op})
			out.append({"id": "capsule", "title": "MOON_OPT_CAP", "options": _opts(MOON_CAPSULE, func(d): return "%s | x%.1f %s" % [kg.call(d["mass"]), d["shield"], TranslationServer.translate("MOON_ST_SHIELD")])})
			out.append({"id": "ascent", "title": "MOON_OPT_ASC", "options": _opts(MOON_ASCENT, func(d): return "%s | %d %s" % [kg.call(d["mass"]), int(d["dv"]), TranslationServer.translate("UNIT_MS")])})
			return out


static func _opts(table: Dictionary, info_fn: Callable) -> Array:
	var out: Array = []
	for k in table:
		var d: Dictionary = table[k]
		out.append({"id": k, "name": d["name"], "info": info_fn.call(d), "cost": int(d["cost"])})
	return out


static func _count_opts() -> Array:
	var out: Array = []
	for k in CON_COUNT:
		out.append({"id": k, "name": CON_COUNT[k]["name"], "info": "", "cost": 0})
	return out


## Mass / cost of the payload that the rocket has to lift, plus information lines for the lab.
static func payload_stats(id: String, d: Dictionary) -> Dictionary:
	var pf: Dictionary = PROFILES[id]
	var mass := float(pf["base_mass"])
	var cost := int(pf["base_cost"])
	var lines: Array = []
	match id:
		"m2":
			var o: Dictionary = EVA_O2[d["o2"]]
			var n: Dictionary = EVA_N2[d["n2"]]
			var s: Dictionary = EVA_SUIT[d["suit"]]
			mass += float(o["mass"]) + float(n["mass"]) + float(s["mass"])
			cost += int(o["cost"]) + int(n["cost"]) + int(s["cost"])
			lines = [["OPS_ST_O2", "x%.1f" % float(o["k"])], ["OPS_ST_N2", "x%.1f" % float(n["k"])], ["OPS_ST_SUIT", "x%.1f" % float(s["k"])]]
		"m3":
			var st := IssDesign.stats(d)
			mass = float(st["mass"])
			cost = int(IssDesign.EXPERIMENTS[d["experiment"]]["cost"]) + int(IssDesign.RCS[d["rcs"]]["cost"]) + int(pf["base_cost"])
			lines = [["ISS_ST_FUEL", "%d%%" % int(float(st["fuel"]) * 100.0)], ["ISS_ST_FRAG", "x%.1f" % float(st["fragile"])]]
		"m4":
			var sc: Dictionary = CON_SAT[d["sat"]]
			var n: int = int(CON_COUNT[d["count"]]["n"])
			var dp: Dictionary = CON_DISP[d["disp"]]
			mass += float(sc["mass"]) * n + float(dp["mass"])
			cost += int(sc["cost"]) * n + int(dp["cost"])
			lines = [["CON_ST_N", "%d" % n], ["CON_ST_CAP", "x%.1f" % (float(sc["cap"]) * n / 4.0)], ["CON_ST_TOL", "x%.1f" % float(dp["tol"])]]
		_:
			var ls := LunarDesign.stats(_as_lunar(d))
			var cap: Dictionary = MOON_CAPSULE[d["capsule"]]
			var asc: Dictionary = MOON_ASCENT[d["ascent"]]
			mass = float(ls["mass_tli"]) + float(cap["mass"]) + float(asc["mass"])
			cost = int(ls["cost"]) - int(LunarDesign.LAUNCHERS["medium"]["cost"]) + int(cap["cost"]) + int(asc["cost"]) + int(pf["base_cost"])
			lines = [["LUN_ST_DV", "%d %s" % [int(ls["dv_descent"]), TranslationServer.translate("UNIT_MS")]], ["LUN_ST_POWER", "%d / %d Wh" % [int(ls["supply_wh"]), int(ls["need_wh"])]],
				["LUN_ST_DATA", "%d / %d Mbit" % [int(ls["uplink"]), int(ls["data_total"])]]]
	return {"mass": mass, "cost": cost, "lines": lines}


static func required_dv(id: String) -> float:
	var pf: Dictionary = PROFILES[id]
	return M1Parts.REQUIRED_DV + maxf(float(pf["ap_target"]) / 1000.0 - 130.0, 0.0) * 4.0 + (MOON_TLI_NEEDED if id == "m5" else 0.0)


## Rows for the shared DesignReview window (verification) of a rocket + payload.
static func requirements(id: String, d: Dictionary, rocket: Dictionary) -> Array:
	var pf: Dictionary = PROFILES[id]
	var need := required_dv(id)
	var dv := float(rocket["dv"])
	var out: Array = []
	var lvl_dv := 0 if dv >= need else (1 if dv >= need * 0.93 else 2)
	out.append({"id": "dv", "key": "REQ_DV" if id != "m5" else "REQ_DV_MOON", "level": lvl_dv,
		"value": "%d / %d %s" % [int(dv), int(need), TranslationServer.translate("UNIT_MS")], "hint": "REQH_DV" if id != "m5" else "REQH_DV_MOON"})
	var twr := float(rocket["twr"])
	out.append({"id": "twr", "key": "REQ_TWR_LIFT", "level": 0 if twr >= 1.2 else (1 if twr >= 1.05 else 2), "value": "%.2f" % twr, "hint": "REQH_TWR_LIFT"})
	var g_end := float(rocket["g_end"])
	out.append({"id": "gload", "key": "REQ_GLOAD", "level": 0 if g_end <= FlightModel.G_LIMIT else (1 if g_end <= FlightModel.G_LIMIT * 1.5 else 2),
		"value": "%.1f g (%s %.1f g)" % [g_end / 9.81, TranslationServer.translate("REQ_LIMIT"), FlightModel.G_LIMIT / 9.81], "hint": "REQH_GLOAD"})
	var rel := float(rocket["rel"])
	out.append({"id": "rel", "key": "REQ_REL", "level": 0 if rel >= 0.84 else (1 if rel >= 0.76 else 2), "value": "%d%%" % int(rel * 100.0), "hint": "REQH_REL"})
	var cost := int(rocket["cost"])
	var budget := int(pf["budget"])
	out.append({"id": "budget", "key": "REQ_BUDGET", "level": 0 if cost <= budget else 2,
		"value": "%s / %s" % [Units.money(cost), Units.money(budget)], "hint": "REQH_BUDGET"})
	match id:
		"m2":
			var o: Dictionary = EVA_O2[d["o2"]]
			var n: Dictionary = EVA_N2[d["n2"]]
			out.append({"id": "eva", "key": "OPS_REQ_EVA", "level": 0 if (float(o["k"]) >= 1.0 and float(n["k"]) >= 1.0) else 1,
				"value": "O2 x%.1f / N2 x%.1f" % [float(o["k"]), float(n["k"])], "hint": "OPS_REQH_EVA"})
		"m3":
			var st := IssDesign.stats(d)
			out.append({"id": "fuel", "key": "ISSREQ_FUEL", "level": 0 if float(st["fuel"]) >= 0.75 else (1 if float(st["fuel"]) >= 0.5 else 2),
				"value": "%d%%" % int(float(st["fuel"]) * 100.0), "hint": "ISSREQH_FUEL"})
			out.append({"id": "fragile", "key": "ISSREQ_FRAGILE", "level": 0 if float(st["fragile"]) <= 1.0 else 1,
				"value": "x%.1f" % float(st["fragile"]), "hint": "ISSREQH_FRAGILE"})
		"m4":
			var n: int = int(CON_COUNT[d["count"]]["n"])
			out.append({"id": "boost", "key": "CON_REQ_BOOST", "level": 0 if int(rocket["boosters"]) > 0 or float(rocket["mass_wet"]) < 30000.0 else 1,
				"value": "%d" % int(rocket["boosters"]), "hint": "CON_REQH_BOOST"})
			out.append({"id": "n", "key": "CON_REQ_N", "level": 0 if n >= 4 else 1, "value": "%d" % n, "hint": "CON_REQH_N"})
		"m5":
			var ls := LunarDesign.stats(_as_lunar(d))
			out.append({"id": "ldv", "key": "LUNREQ_DV", "level": 0 if float(ls["dv_descent"]) >= LunarDesign.DESCENT_DV_OK else (1 if float(ls["dv_descent"]) >= LunarDesign.DESCENT_DV_MIN else 2),
				"value": "%d %s" % [int(ls["dv_descent"]), TranslationServer.translate("UNIT_MS")], "hint": "LUNREQH_DV"})
			out.append({"id": "lpow", "key": "LUNREQ_POWER", "level": 0 if float(ls["power_ratio"]) >= 1.0 else (1 if float(ls["power_ratio"]) >= 0.8 else 2),
				"value": "%d / %d Wh" % [int(ls["supply_wh"]), int(ls["need_wh"])], "hint": "LUNREQH_POWER"})
	return out


static func _as_lunar(d: Dictionary) -> Dictionary:
	var ld := d.duplicate()
	ld["launcher"] = "medium"
	if not ld.has("engine"):
		ld["engine"] = "std"
	return ld
