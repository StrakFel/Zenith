extends SceneTree
## Rocket-builder balance analysis. Enumerates EVERY combination (nose x tank x engine x upper stage x satellite design),
## flies a representative set through the real FlightModel with a competent test pilot and judges the result with
## M1Design.evaluate (the same rules the game uses).
##   Godot --headless --path . --script res://Tools/balance_sim.gd [-- csv_path]
## Honest limits: the pilot is a scripted gravity-turn (not an optimiser), the payload mass of each satellite is rounded up
## to a few representative masses per goal (conservative), the outcome ignores random engine anomalies.

const STEP := 0.05
const AP_TARGET_M := {"earth": 135_000.0, "space": 300_000.0, "atmo": 120_000.0}

var _cache: Dictionary = {}
var _flights := 0


func _initialize() -> void:
	var rockets: Array = []
	for n in M1Parts.NOSES:
		for t in M1Parts.TANKS:
			for e in M1Parts.ENGINES:
				for u in ["", "u_s", "u_m"]:
					rockets.append({"nose": n, "tank": t, "engine": e, "upper": u})
	var sats: Array = []
	for g in M1Design.GOALS:
		for i in M1Design.GOALS[g]["instruments"]:
			for so in M1Design.SOLAR:
				for b in M1Design.BATTERY:
					for c in M1Design.COMM:
						sats.append({"goal": g, "instrument": i, "solar": so, "battery": b, "comm": c})
	var total := rockets.size() * sats.size()
	print("rockets=", rockets.size(), " satellites=", sats.size(), " total designs=", total)
	# representative payload masses per goal
	var reps: Dictionary = {}
	for g in M1Design.GOALS:
		var ms: Array = []
		for sd in sats:
			if sd["goal"] == g:
				var m := snappedf(float(M1Design.sat_stats(sd)["mass"]), 1.0)
				if not ms.has(m):
					ms.append(m)
		ms.sort()
		var pick: Array = []
		for q in [0.2, 0.45, 0.7, 1.0]:
			var m2: float = ms[mini(int(ceil(q * ms.size())) - 1, ms.size() - 1)]
			if not pick.has(m2):
				pick.append(m2)
		reps[g] = pick
	var valid := 0
	var counts := [0, 0, 0, 0]
	var fail_causes: Dictionary = {}
	var by_goal: Dictionary = {}
	var examples: Array = []
	var rows := PackedStringArray(["nose,tank,engine,upper,goal,instrument,solar,battery,comm,cost,twr,dv,stars,science,cause"])
	var invalid_cost := 0
	var invalid_twr := 0
	for rk in rockets:
		for sd in sats:
			var ss := M1Design.sat_stats(sd)
			var st := M1Parts.compute(rk, float(ss["mass"]), int(ss["cost"]))
			if not M1Parts.can_launch(st):
				if bool(st["over_budget"]):
					invalid_cost += 1
				else:
					invalid_twr += 1
				continue
			valid += 1
			var rep := 0.0
			for m in reps[sd["goal"]]:
				if float(m) >= float(ss["mass"]) - 0.5:
					rep = float(m)
					break
			var fl := _fly(rk, str(sd["goal"]), rep, float(ss["mass"]), int(ss["cost"]))
			var res := {"stars": 0, "science": 0.0, "cause": "orbit"}
			if bool(fl["orbit_ok"]):
				res = M1Design.evaluate(sd, st, fl)
			var stars := int(res["stars"])
			counts[stars] += 1
			if stars == 0:
				fail_causes[str(res["cause"])] = int(fail_causes.get(str(res["cause"]), 0)) + 1
			var gk := str(sd["goal"])
			if not by_goal.has(gk):
				by_goal[gk] = [0, 0, 0, 0]
			by_goal[gk][stars] += 1
			if stars == 3 and examples.size() < 400:
				examples.append([rk, sd, int(st["cost"]), snappedf(float(res["science"]), 0.01)])
			rows.append("%s,%s,%s,%s,%s,%s,%s,%s,%s,%d,%.2f,%d,%d,%.2f,%s" % [rk["nose"], rk["tank"], rk["engine"], rk["upper"],
				sd["goal"], sd["instrument"], sd["solar"], sd["battery"], sd["comm"], int(st["cost"]), float(st["twr"]),
				int(st["dv"]), stars, float(res["science"]), str(res["cause"])])
	print("flights simulated=", _flights)
	print("invalid (over budget)=", invalid_cost, "  invalid (TWR<1.05)=", invalid_twr, "  VALID builds=", valid, " of ", total)
	for i in [3, 2, 1, 0]:
		print("  %d stars: %d  (%.1f%% of valid)" % [i, counts[i], 100.0 * counts[i] / maxf(valid, 1)])
	print("failure causes: ", fail_causes)
	for g in by_goal:
		var a: Array = by_goal[g]
		var tt: int = a[0] + a[1] + a[2] + a[3]
		print("  goal %s: 3*=%.1f%% 2*=%.1f%% 1*=%.1f%% 0*=%.1f%%" % [g, 100.0 * a[3] / tt, 100.0 * a[2] / tt, 100.0 * a[1] / tt, 100.0 * a[0] / tt])
	# distinct 3-star rockets per goal (several different optimal configurations must exist)
	var best_r: Dictionary = {}
	for ex in examples:
		var key := "%s|%s" % [ex[1]["goal"], "%s/%s/%s/%s" % [ex[0]["nose"], ex[0]["tank"], ex[0]["engine"], ex[0]["upper"]]]
		best_r[key] = true
	var per_goal: Dictionary = {}
	for k in best_r:
		var gk2: String = str(k).split("|")[0]
		per_goal[gk2] = int(per_goal.get(gk2, 0)) + 1
	print("distinct rockets achieving 3 stars per goal: ", per_goal)
	var path := "user://balance.csv"
	var a2 := OS.get_cmdline_user_args()
	if a2.size() > 0:
		path = a2[0]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(rows))
		print("csv: ", ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)
	quit()


func _fly(rk: Dictionary, goal: String, payload: float, actual_mass: float, sat_cost: int) -> Dictionary:
	var key := "%s/%s/%s/%s|%s|%d" % [rk["nose"], rk["tank"], rk["engine"], rk["upper"], goal, int(payload)]
	if _cache.has(key):
		return _cache[key]
	_flights += 1
	var st := M1Parts.compute(rk, payload, sat_cost)
	var m := FlightModel.new()
	m.setup(st)
	var ap_t: float = AP_TARGET_M[goal]
	m.engine_on = true
	m.throttle = 1.0
	var phase := 0
	var res := {"orbit_ok": false, "ap": 0.0, "pe": -1.0e6, "integrity": 0.0, "fuel": 0.0}
	var steps := 0
	while steps < 60000:
		steps += 1
		var h := m.altitude()
		var o := m.orbit()
		var ap := minf(float(o["ap"]), 1.0e9)
		if m.has_upper and m.stage == 1 and m.fuel <= 1.0:
			m.separate_stage()
		if m.fairing_on and h >= 95_000.0:
			m.jettison_fairing()
		var thr := 1.0 if m.q < 0.8 * FlightModel.Q_LIMIT else 0.55
		if phase == 0:
			m.pitch = 0.0 if h < 600.0 else deg_to_rad(90.0 * minf(1.0, pow((h - 600.0) / 60000.0, 0.5)))
			if ap >= ap_t:
				phase = 1
		if phase == 1:
			thr = 0.0
			m.pitch = deg_to_rad(90.0)
			if m.vr < 15.0:
				phase = 2
		if phase == 2:
			thr = 1.0
			m.pitch = deg_to_rad(90.0 + clampf(m.vr * 0.25, -10.0, 40.0))
		# g-limit: a competent pilot throttles down near burnout
		var ta_full := m.max_thrust * (m.isp_vac / m.isp_sl if h > 50000.0 else 1.0) / m.mass()
		if ta_full > FlightModel.G_LIMIT * 0.95:
			thr = minf(thr, FlightModel.G_LIMIT * 0.95 / ta_full)
		m.throttle = thr
		m.step(STEP)
		if m.integrity <= 0.0 or m.crashed:
			break
		if m.in_stable_orbit():
			var o2 := m.orbit()
			res = {"orbit_ok": true, "ap": float(o2["ap"]), "pe": float(o2["pe"]), "integrity": m.integrity, "fuel": m.fuel_fraction()}
			break
		if m.fuel <= 0.0 and not (m.has_upper and m.stage == 1):
			break
		if m.time > 2400.0:
			break
	_cache[key] = res
	return res
