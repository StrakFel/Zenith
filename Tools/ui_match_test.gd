extends SceneTree
## Checks that the numbers the player sees in the designer UI are the numbers the flight physics uses.
##   Godot --headless --path . --script res://Tools/ui_match_test.gd
var _f := 0
var _fail := 0
var _builds := [
	{"engine": "kestrel", "tank": "m", "nose": "std", "upper": "u_s"},
	{"engine": "phoenix", "tank": "l", "nose": "aero", "upper": ""},
	{"engine": "spark", "tank": "s", "nose": "std", "upper": "u_m"},
]
var _bi := 0

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fail += 1

func _initialize() -> void:
	change_scene_to_file("res://Missions/Mission1/mission1.tscn")

func _process(_d: float) -> bool:
	_f += 1
	var m := current_scene
	if m == null or _f < 5:
		return false
	if _f == 5:
		m.dev_skip_briefing()
		m.dev_auto_design()
		return false
	if _f % 4 != 0 or _f < 8:
		return false
	if _bi >= _builds.size():
		print("\nRESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
		quit(_fail)
		return true
	var b: Dictionary = _builds[_bi]
	_bi += 1
	for slot in ["engine", "tank", "upper", "nose"]:
		m.assembly._on_install(slot, b[slot])
	var asm = m.assembly
	var st := M1Parts.compute(asm.build, asm.payload_mass, asm.sat_cost)
	var tag := "%s/%s/%s/%s" % [b["engine"], b["tank"], b["nose"], b["upper"]]
	var labels: Dictionary = asm._stat_labels
	_check((labels["mass"] as Label).text == Units.kg(float(st["mass_wet"])), "UI liftoff mass == compute (%s) [%s]" % [(labels["mass"] as Label).text, tag])
	_check((labels["dv"] as Label).text == Units.ms(float(st["dv"])), "UI delta-v == compute (%s) [%s]" % [(labels["dv"] as Label).text, tag])
	_check((labels["twr"] as Label).text == "%.2f" % float(st["twr"]), "UI thrust/weight == compute (%s) [%s]" % [(labels["twr"] as Label).text, tag])
	_check((labels["cost"] as Label).text.begins_with(Units.money(int(st["cost"]))), "UI cost == compute (%s) [%s]" % [(labels["cost"] as Label).text, tag])
	# the flight physics is set up from the very same numbers
	var fm := FlightModel.new()
	fm.setup(st)
	_check(absf(fm.mass() - float(st["mass_wet"])) < 0.5, "flight model liftoff mass == UI (%d kg)" % int(fm.mass()))
	_check(absf(fm.max_thrust / (fm.mass() * 9.81) - float(st["twr"])) < 0.001, "flight model thrust/weight == UI (%.2f)" % float(st["twr"]))
	_check(absf(fm.fuel + fm.reserve_fuel - float(st["fuel"]) - float(st["reserve"])) < 0.5, "flight model propellant == catalogue values")
	# delta-v seen by the rocket equation in the model (vacuum, no gravity): burn stage 1, drop it, burn stage 2
	var dv := fm.isp_vac * 9.80665 * log(fm.mass() / (fm.mass() - fm.fuel))
	if fm.has_upper:
		var mm := fm.mass() - fm.fuel - fm.stage1_dry
		dv += fm.upper_isp_vac * 9.80665 * log(mm / (mm - fm.reserve_fuel))
	_check(absf(dv - float(st["dv"])) < 1.0, "delta-v from the model's own masses/Isp == UI (%d vs %d)" % [int(dv), int(st["dv"])])
	return false
