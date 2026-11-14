extends SceneTree
## Unit test of the staging physics (no scene needed):  Godot --headless --path . --script res://Tools/stage_test.gd
var _fail := 0

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fail += 1

func _initialize() -> void:
	var b := {"nose": "aero", "tank": "m", "engine": "kestrel", "upper": "u_s"}
	var st := M1Parts.compute(b, 1000.0, 0)
	_check(int(st["stages"]) == 2 and float(st["reserve"]) > 0.0, "compute: two stages, upper-stage propellant counted")
	var single := M1Parts.compute({"nose": "aero", "tank": "m", "engine": "kestrel"}, 1000.0, 0)
	_check(float(st["dv"]) > float(single["dv"]) + 1500.0, "two-stage delta-v is clearly higher (%d vs %d)" % [int(st["dv"]), int(single["dv"])])
	_check(int(st["cost"]) > int(single["cost"]), "upper stage costs money (%d vs %d)" % [int(st["cost"]), int(single["cost"])])
	var m := FlightModel.new()
	m.setup(st)
	var mass0 := m.mass()
	var thrust0 := m.max_thrust
	m.fuel = 0.15 * m.fuel_cap        # separate EARLY: propellant is thrown away
	var r := m.separate_stage()
	_check(bool(r["ok"]) and m.stage == 2, "separate_stage switches to stage 2")
	_check(m.mass() < mass0 - float(st["stage1_dry"]) * 0.99, "mass drops by the stage-1 structure + its unused fuel (%d -> %d)" % [int(mass0), int(m.mass())])
	_check(m.max_thrust != thrust0 and m.fuel == float(st["reserve"]), "thrust / Isp / fuel now describe the upper stage")
	_check(m.sep_waste > 0.1, "wasted propellant is recorded (%.0f%%)" % [m.sep_waste * 100.0])
	_check(not m.engine_on and m.ignite_in > 0.0, "upper engine ignites after a coast delay")
	for i in 60:
		m.step(0.05)
	_check(m.engine_on, "engine lit after the delay")
	# separating at Max-Q hurts
	var m2 := FlightModel.new()
	m2.setup(st)
	m2.q = 0.9 * FlightModel.Q_LIMIT
	var r2 := m2.separate_stage()
	_check(float(r2["shock"]) > 10.0 and m2.integrity < 90.0, "separating near Max-Q damages the vehicle (hull %d%%)" % int(m2.integrity))
	# fairing
	var m3 := FlightModel.new()
	m3.setup(st)
	var mass_f := m3.mass()
	m3.r = FlightModel.R + 30_000.0
	var f1 := m3.jettison_fairing()
	_check(float(f1["damage"]) > 30.0 and m3.fairing_early, "fairing dropped at 30 km damages the payload (hull %d%%)" % int(m3.integrity))
	_check(m3.mass() < mass_f - 300.0 and m3.current_cd() > m3.cd, "fairing mass is shed, payload drag rises")
	var m4 := FlightModel.new()
	m4.setup(st)
	m4.r = FlightModel.R + 100_000.0
	var f2 := m4.jettison_fairing()
	_check(float(f2["damage"]) == 0.0 and m4.integrity == 100.0, "fairing dropped in space is safe")
	print("\nRESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
