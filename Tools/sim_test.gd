extends SceneTree
## Headless balance test: flies every engine/tank combination with a simple
## autopilot (kick + gravity turn, Max-Q throttle limiter) and prints the outcome.
##   Godot --headless --path . --script res://Tools/sim_test.gd

var PROG_H := 60000.0
var PROG_EXP := 0.5


var DEBUG := false


func _initialize() -> void:
	var lines: Array[String] = []
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		DEBUG = true
		var b := {"nose": "std", "tank": args[1], "engine": args[0]}
		var st0 := M1Parts.compute(b)
		print(_fly(st0))
		quit()
		return
	for e in M1Parts.ENGINES:
		for t in M1Parts.TANKS:
			for n in M1Parts.NOSES:
				var build := {"nose": n, "tank": t, "engine": e}
				var st := M1Parts.compute(build)
				var res := _fly(st)
				lines.append("%-8s %-2s %-5s cost %3d twr %.2f dv %5d | %s" % [
					e, t, n, st["cost"], st["twr"], st["dv"], res])
	for l in lines:
		print(l)
	quit()


func _fly(st: Dictionary) -> String:
	var m := FlightModel.new()
	m.setup(st)
	m.engine_on = true
	m.throttle = 1.0
	var dt := 0.05
	var t := 0.0
	var phase := 0
	var orbit_t := -1.0
	while t < 900.0 and not m.crashed:
		var h := m.altitude()
		var o := m.orbit()
		var ap: float = minf(float(o["ap"]), 1.0e9)
		# throttle: obey Max-Q
		var thr := 1.0 if m.q < 0.8 * FlightModel.Q_LIMIT else 0.55
		if phase == 0:
			if h < 600.0:
				m.pitch = 0.0
			else:
				m.pitch = deg_to_rad(90.0 * minf(1.0, pow((h - 600.0) / PROG_H, PROG_EXP)))
			if ap >= 115000.0:
				phase = 1
		if phase == 1:
			thr = 0.0
			m.pitch = deg_to_rad(90.0)
			# start the circularisation burn near apoapsis (vertical speed small)
			if m.vr < 15.0:
				phase = 2
		if phase == 2:
			thr = 1.0
			m.pitch = deg_to_rad(90.0 + clampf(m.vr * 0.25, -10.0, 40.0))
		m.throttle = thr
		if DEBUG and int(t * 20.0) % 400 == 0:
			print("t=%d ph=%d h=%dkm vr=%d vt=%d ap=%dkm pe=%dkm fuel=%d%% pitch=%d" % [
				t, phase, int(h / 1000.0), int(m.vr), int(m.vt), int(ap / 1000.0),
				int(float(o["pe"]) / 1000.0), int(m.fuel_fraction() * 100.0), int(rad_to_deg(m.pitch))])
		if m.in_stable_orbit() and orbit_t < 0.0:
			orbit_t = t
			break
		m.step(dt)
		t += dt
	var o2 := m.orbit()
	if orbit_t > 0.0:
		return "ORBIT t=%ds fuel left %d%% maxQ %dkPa integrity %d" % [
			int(orbit_t), int(m.fuel_fraction() * 100.0), int(m.max_q_seen / 1000.0), int(m.integrity)]
	return "fail t=%ds alt %dkm pe %dkm ap %dkm fuel %d%% maxQ %dkPa" % [
		int(t), int(m.altitude() / 1000.0), int(float(o2["pe"]) / 1000.0), int(minf(float(o2["ap"]), 99999.0) / 1000.0),
		int(m.fuel_fraction() * 100.0), int(m.max_q_seen / 1000.0)]
