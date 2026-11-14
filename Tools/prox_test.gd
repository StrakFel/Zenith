extends SceneTree
## Unit test of Mission Success Proximity (M1Design.proximity). Godot --headless --path . --script res://Tools/prox_test.gd
var _fail := 0

func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fail += 1

func _flight(ap_km: float, pe_km: float, hull: float, orbit_ok := true, max_alt_km := 0.0) -> Dictionary:
	return {"orbit_ok": orbit_ok, "ap": ap_km * 1000.0, "pe": pe_km * 1000.0, "integrity": hull, "max_alt": max_alt_km * 1000.0}

func _initialize() -> void:
	var rocket := {"cost": 100, "rel": 0.9}
	# find designs: one that meets EVERY requirement, one with a small and one with a big deficit
	var perfect := {}
	var small_def := {}
	var big_def := {}
	for g in M1Design.GOALS:
		for i in M1Design.GOALS[g]["instruments"]:
			for so in M1Design.SOLAR:
				for b in M1Design.BATTERY:
					for c in M1Design.COMM:
						var d := {"goal": g, "instrument": i, "solar": so, "battery": b, "comm": c}
						var best: Array = M1Design.GOALS[g]["best"]
						var mid := (float(best[0]) + float(best[1])) * 0.5
						var p := M1Design.proximity(d, rocket, _flight(mid, mid, 100.0))
						if bool(p["all_ok"]) and perfect.is_empty():
							perfect = d
						var sat := M1Design.sat_stats(d)
						if g == "earth":
							if small_def.is_empty() and float(sat["data_ratio"]) >= 0.85 and float(sat["data_ratio"]) < 0.97 and float(sat["power_ratio"]) >= 1.0 and float(sat["batt_ratio"]) >= 1.0:
								small_def = d
							if big_def.is_empty() and float(sat["data_ratio"]) < 0.3 and float(sat["power_ratio"]) >= 1.0 and float(sat["batt_ratio"]) >= 1.0:
								big_def = d
	_check(not perfect.is_empty(), "a design meeting every mandatory requirement exists")
	var g: String = perfect["goal"]
	var best: Array = M1Design.GOALS[g]["best"]
	var mid := (float(best[0]) + float(best[1])) * 0.5
	var p_perfect := M1Design.proximity(perfect, rocket, _flight(mid, mid, 100.0))
	_check(int(p_perfect["percent"]) == 100 and bool(p_perfect["all_ok"]), "all requirements met -> exactly 100%%")
	_check((p_perfect["recs"] as Array).is_empty(), "no recommendations when everything is met")
	# hull
	var h100 := int(M1Design.proximity(perfect, rocket, _flight(mid, mid, 100.0))["percent"])
	var h55 := int(M1Design.proximity(perfect, rocket, _flight(mid, mid, 55.0))["percent"])
	var h20 := int(M1Design.proximity(perfect, rocket, _flight(mid, mid, 20.0))["percent"])
	_check(h100 > h55 and h55 > h20 and h55 < 100, "hull damage lowers it smoothly: 100%% hull=%d%%, 55%%=%d%%, 20%%=%d%%" % [h100, h55, h20])
	# orbit altitude: small miss vs big miss (outside the goal window)
	var lo := float(best[0])
	var o_ok := int(M1Design.proximity(perfect, rocket, _flight(mid, mid, 100.0))["percent"])
	var o_small := int(M1Design.proximity(perfect, rocket, _flight(lo - 6.0, lo - 6.0, 100.0))["percent"])
	var o_big := int(M1Design.proximity(perfect, rocket, _flight(lo + 600.0, lo + 600.0, 100.0))["percent"])
	_check(o_ok > o_small and o_small > o_big, "small altitude error scores higher than a big one: in=%d%% small=%d%% big=%d%%" % [o_ok, o_small, o_big])
	# data link deficit with the real design parameters: same satellite, three antennas (ok / smaller shortage / big shortage)
	var bs: Array = M1Design.GOALS["earth"]["best"]
	var bm := (float(bs[0]) + float(bs[1])) * 0.5
	var pk := M1Design.proximity({"goal": "earth", "instrument": "img_a", "solar": "l", "battery": "l", "comm": "ka"}, rocket, _flight(bm, bm, 100.0))
	var px := M1Design.proximity({"goal": "earth", "instrument": "img_a", "solar": "l", "battery": "l", "comm": "x"}, rocket, _flight(bm, bm, 100.0))
	var pu := M1Design.proximity({"goal": "earth", "instrument": "img_a", "solar": "l", "battery": "l", "comm": "uhf"}, rocket, _flight(bm, bm, 100.0))
	_check(int(pk["percent"]) > int(px["percent"]) and int(px["percent"]) > int(pu["percent"]), "data link: Ka %d%% > X-band %d%% > UHF %d%% (smaller shortage scores higher)" % [int(pk["percent"]), int(px["percent"]), int(pu["percent"])])
	_check((px["recs"] as Array).has("TIP_DATA"), "recommendation points at the data link (%s)" % str(px["recs"]))
	_check(int(px["percent"]) < 100 and not bool(px["all_ok"]), "a missed requirement can never show 100%")
	# no orbit
	var p_no := M1Design.proximity(perfect, rocket, _flight(0.0, -1600.0, 100.0, false, 70.0))
	_check(int(p_no["percent"]) <= M1Design.PROX_CRITICAL_CAP and int(p_no["percent"]) < 60 and bool(p_no["critical_failed"]), "no orbit -> critical failure, low (%d%%), never shown as a win" % int(p_no["percent"]))
	var p_no2 := M1Design.proximity(perfect, rocket, _flight(300.0, 40.0, 100.0, false, 300.0))
	_check(int(p_no2["percent"]) > int(p_no["percent"]) and int(p_no2["percent"]) <= M1Design.PROX_CRITICAL_CAP, "nearly an orbit (%d%%) is closer than a short hop (%d%%) but still capped" % [int(p_no2["percent"]), int(p_no["percent"])])
	_check((p_no["recs"] as Array).has("MP_REC_ORBIT"), "no-orbit result recommends more delta-v / better flight")
	# science objective missed although in orbit: weakest possible satellite
	var weak := {"goal": "earth", "instrument": "img_a", "solar": "s", "battery": "s", "comm": "uhf"}
	var bs2: Array = M1Design.GOALS["earth"]["best"]
	var bm2 := (float(bs2[0]) + float(bs2[1])) * 0.5
	var p_weak := M1Design.proximity(weak, rocket, _flight(bm2, bm2, 100.0))
	_check(bool(p_weak["critical_failed"]) and int(p_weak["percent"]) <= M1Design.PROX_CRITICAL_CAP, "orbit reached but science missed -> capped at %d%% (got %d%%)" % [M1Design.PROX_CRITICAL_CAP, int(p_weak["percent"])])
	_check(not (p_weak["recs"] as Array).is_empty(), "failed requirements produce recommendations (%s)" % str(p_weak["recs"]))
	# consistency with the star rules: every 1+ star outcome needs science >= SCI_MIN, which is a mandatory requirement
	var ok_count := 0
	var total := 0
	for so in M1Design.SOLAR:
		for b in M1Design.BATTERY:
			for c in M1Design.COMM:
				var d2 := {"goal": "space", "instrument": "mag_s", "solar": so, "battery": b, "comm": c}
				var bb: Array = M1Design.GOALS["space"]["best"]
				var m3 := (float(bb[0]) + float(bb[1])) * 0.5
				var ev := M1Design.evaluate(d2, rocket, _flight(m3, m3, 100.0))
				var pr := M1Design.proximity(d2, rocket, _flight(m3, m3, 100.0))
				total += 1
				if int(ev["stars"]) == 0:
					if bool(pr["critical_failed"]) or int(pr["percent"]) < 100:
						ok_count += 1
				else:
					ok_count += 1
	_check(ok_count == total, "100%% proximity never coexists with a failed science mission (%d/%d designs consistent)" % [ok_count, total])
	print("\nRESULT: ", "ALL PASSED" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
