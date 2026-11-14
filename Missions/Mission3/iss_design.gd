class_name IssDesign
extends RefCounted
## Mission 3 - ISS Expedition design: which experiment to deliver, which launcher, how much RCS propellant for the
## final approach. Choices change the docking (fuel available, how fragile the cargo is) and the science return.
## Simplified: no orbital phasing here - the launch puts the cargo ship in the ISS orbit near the station.

const BUDGET := 135
const MODULE_MASS := 380.0

const EXPERIMENTS := {
	"crystals": {"name": "ISS_EXP_CRYSTALS", "mass": 120.0, "sci": 1.0, "fragile": 1.0, "cost": 22},
	"cells": {"name": "ISS_EXP_CELLS", "mass": 90.0, "sci": 1.3, "fragile": 1.5, "cost": 30},
	"alloys": {"name": "ISS_EXP_ALLOYS", "mass": 210.0, "sci": 0.9, "fragile": 0.6, "cost": 16},
}
const LAUNCHERS := {
	"small": {"name": "ISS_LAU_S", "cap": 720.0, "cost": 40},
	"medium": {"name": "ISS_LAU_M", "cap": 1100.0, "cost": 72},
}
## rcs: propellant mass, share of the full docking fuel tank that can be used
const RCS := {
	"s": {"name": "ISS_RCS_S", "mass": 40.0, "fuel": 0.5, "cost": 6},
	"m": {"name": "ISS_RCS_M", "mass": 80.0, "fuel": 0.75, "cost": 10},
	"l": {"name": "ISS_RCS_L", "mass": 140.0, "fuel": 1.0, "cost": 16},
}


static func default_design() -> Dictionary:
	return {"experiment": "crystals", "launcher": "medium", "rcs": "m"}


static func stats(d: Dictionary) -> Dictionary:
	var e: Dictionary = EXPERIMENTS[d["experiment"]]
	var l: Dictionary = LAUNCHERS[d["launcher"]]
	var r: Dictionary = RCS[d["rcs"]]
	var mass := MODULE_MASS + float(e["mass"]) + float(r["mass"])
	return {"mass": mass, "cap": float(l["cap"]), "fuel": float(r["fuel"]), "fragile": float(e["fragile"]),
		"sci": float(e["sci"]), "cost": int(e["cost"]) + int(l["cost"]) + int(r["cost"]) + 20}


static func requirements(d: Dictionary) -> Array:
	var s := stats(d)
	var out: Array = []
	var ml := 0
	if float(s["mass"]) > float(s["cap"]):
		ml = 2
	elif float(s["mass"]) > float(s["cap"]) * 0.93:
		ml = 1
	out.append({"id": "mass", "key": "ISSREQ_MASS", "level": ml, "value": "%d / %d kg" % [int(s["mass"]), int(s["cap"])],
		"hint": "ISSREQH_MASS"})
	var fl := 0 if float(s["fuel"]) >= 0.75 else (1 if float(s["fuel"]) >= 0.5 else 2)
	out.append({"id": "fuel", "key": "ISSREQ_FUEL", "level": fl, "value": "%d%%" % int(float(s["fuel"]) * 100.0),
		"hint": "ISSREQH_FUEL"})
	var gl := 0 if float(s["fragile"]) <= 1.0 else 1
	out.append({"id": "fragile", "key": "ISSREQ_FRAGILE", "level": gl, "value": "x%.1f" % float(s["fragile"]),
		"hint": "ISSREQH_FRAGILE"})
	out.append({"id": "budget", "key": "REQ_BUDGET", "level": 0 if int(s["cost"]) <= BUDGET else 2,
		"value": "%s / %s" % [Units.money(int(s["cost"])), Units.money(BUDGET)], "hint": "REQH_BUDGET"})
	return out


static func can_launch(d: Dictionary) -> bool:
	var s := stats(d)
	return float(s["mass"]) <= float(s["cap"]) and int(s["cost"]) <= BUDGET
