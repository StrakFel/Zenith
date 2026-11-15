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
	# ---- strap-on boosters (Mission 4+)
	M1Parts.active_mission = 4
	var plain := M1Parts.compute({"nose": "std", "tank": "m", "engine": "kestrel", "upper": "u_s", "booster": ""}, 1700.0, 0)
	var bb := {"nose": "std", "tank": "m", "engine": "kestrel", "upper": "u_s", "booster": "b_s"}
	var sb := M1Parts.compute(bb, 1700.0, 0)
	_check(int(sb["boosters"]) == 2 and float(sb["twr"]) > float(plain["twr"]) + 0.3, "boosters add lift-off thrust (TWR %.2f -> %.2f)" % [float(plain["twr"]), float(sb["twr"])])
	_check(float(sb["dv"]) > float(plain["dv"]) - 200.0 and int(sb["cost"]) > int(plain["cost"]), "boosters cost money and change delta-v (%d -> %d)" % [int(plain["dv"]), int(sb["dv"])])
	var mb := FlightModel.new()
	mb.setup(sb)
	mb.engine_on = true
	mb.throttle = 1.0
	mb.step(0.05)
	_check(mb.b_thrust_now > 0.0 and mb.thrust_now > mb.b_thrust_now, "boosters and core burn together")
	var m_b0 := mb.mass()
	mb.q = 0.9 * FlightModel.Q_LIMIT
	var rb := mb.separate_boosters()
	_check(bool(rb["ok"]) and not mb.has_boosters and mb.mass() < m_b0 - float(sb["b_dry"]) * 0.99, "booster separation drops structure + unused fuel (%d -> %d kg)" % [int(m_b0), int(mb.mass())])
	_check(float(rb["shock"]) > 5.0 and float(rb["waste"]) > 0.9, "separating full boosters near Max-Q wastes propellant and shocks the hull (waste %d%%, hull %d%%)" % [int(float(rb["waste"]) * 100.0), int(mb.integrity)])
	M1Parts.active_mission = 1
	_check(not M1Parts.is_unlocked("booster", "b_s") and M1Parts.is_unlocked("tank", "l"), "boosters are locked in Mission 1, unlocked from Mission 4")
	print("\nRESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
