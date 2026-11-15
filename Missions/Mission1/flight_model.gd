class_name FlightModel
extends RefCounted
## Simplified 2D launch physics in polar coordinates around a scaled-down Earth
## (radius 1600 km, surface gravity 9.81 m/s^2) so that a single stage can reach orbit.
## State: r (distance from planet centre), theta (downrange angle), vr (vertical speed),
## vt (tangential speed). Pitch is measured from the local vertical (0 = up, 90 deg = horizontal).
## Gravity (1/r^2), centrifugal term, exponential atmosphere + drag, Tsiolkovsky engine
## (mass flow from Isp, Isp rises as the air thins) and a Max-Q structural limit.

const R := 1_600_000.0
const MU := 9.81 * R * R
const SCALE_H := 7000.0
const ATM_TOP := 70_000.0
const SAFE_PE := 80_000.0       # periapsis needed to call it a stable orbit
const Q_LIMIT := 50_000.0       # Pa, structural limit (Max-Q)
const G0 := 9.80665
const G_LIMIT := 65.0           # m/s^2 (about 6.6 g): sustained thrust acceleration above this hurts the payload

# vehicle
var dry_mass := 0.0
var fuel := 0.0
var fuel_cap := 0.0
var max_thrust := 0.0
var isp_sl := 300.0
var isp_vac := 340.0
var cd := 0.4
var area := 10.0

# staging (optional second stage). `fuel` / `fuel_cap` always describe the ACTIVE stage's tank.
var stage := 1
var has_upper := false
var reserve_fuel := 0.0         # upper-stage propellant carried (as dead weight) until separation
var stage1_dry := 0.0           # tank + engine structure that is thrown away at separation
var upper_thrust := 0.0
var upper_isp_sl := 255.0
var upper_isp_vac := 380.0
var fairing_mass := 0.0
var fairing_on := true
# strap-on boosters
var has_boosters := false
var b_fuel := 0.0
var b_fuel_cap := 0.0
var b_dry := 0.0
var b_thrust := 0.0
var b_isp_sl := 240.0
var b_isp_vac := 265.0
var b_waste := -1.0             # fraction of booster propellant thrown away at separation (-1 = not separated)
var b_sep_time := -1.0
var b_thrust_now := 0.0
var b_dead_time := 0.0          # seconds the EMPTY boosters were carried as dead weight
var ignite_in := 0.0            # seconds until the next engine lights after separation
var sep_waste := -1.0           # fraction of stage-1 propellant thrown away unused at separation (-1 = not separated)
var sep_time := -1.0
var fairing_time := -1.0
var fairing_early := false
var dead_mass_time := 0.0       # seconds an EMPTY stage was carried around
const SEP_FUEL_MAX := 0.12       # a stage / booster may be separated once its propellant is below this share
const FAIRING_MIN_ALT := 80_000.0  # the fairing may be jettisoned above this altitude (thin air)
const CD_NO_FAIRING := 0.22     # extra drag of the exposed payload

# state
var r := R
var theta := 0.0
var vr := 0.0
var vt := 0.0
var pitch := 0.0
var throttle := 0.0
var engine_on := false
var thrust_scale := 1.0   # < 1 during an engine anomaly
var on_pad := true
var integrity := 100.0
var crashed := false
var time := 0.0
var max_q_seen := 0.0
# last-step readouts
var q := 0.0
var accel := 0.0
var thrust_now := 0.0
var g_load := 0.0               # thrust acceleration, m/s^2


func setup(stats: Dictionary) -> void:
	dry_mass = float(stats["mass_dry"])
	fuel = float(stats["fuel"])
	fuel_cap = fuel
	max_thrust = float(stats["thrust"])
	isp_sl = float(stats["isp_sl"])
	isp_vac = float(stats["isp_vac"])
	cd = float(stats["cd"])
	stage = 1
	has_boosters = int(stats.get("boosters", 0)) > 0
	if has_boosters:
		b_fuel = float(stats["b_fuel"])
		b_fuel_cap = b_fuel
		b_dry = float(stats["b_dry"])
		b_thrust = float(stats["b_thrust"])
		b_isp_sl = float(stats["b_isp_sl"])
		b_isp_vac = float(stats["b_isp_vac"])
	has_upper = int(stats.get("stages", 1)) == 2
	reserve_fuel = float(stats.get("reserve", 0.0))
	stage1_dry = float(stats.get("stage1_dry", 0.0))
	fairing_mass = float(stats.get("fairing_mass", 0.0))
	fairing_on = true
	if has_upper:
		upper_thrust = float(stats["u_thrust"])
		upper_isp_sl = float(stats["u_isp_sl"])
		upper_isp_vac = float(stats["u_isp_vac"])


func mass() -> float:
	return dry_mass + fuel + reserve_fuel + b_fuel


func altitude() -> float:
	return r - R


func speed() -> float:
	return sqrt(vr * vr + vt * vt)


## Drop the spent first stage: its structure and unused propellant leave, the upper stage becomes active
## (new thrust / Isp / fuel). Returns {"ok", "waste", "shock"}; shock = structural damage from separating in dense air.
func separate_stage() -> Dictionary:
	if stage != 1 or not has_upper:
		return {"ok": false}
	sep_waste = fuel / fuel_cap if fuel_cap > 0.0 else 0.0
	sep_time = time
	var shock := clampf(q / Q_LIMIT - 0.3, 0.0, 1.0) * 40.0      # separating near Max-Q is dangerous
	dry_mass -= stage1_dry
	fuel = reserve_fuel
	fuel_cap = reserve_fuel
	reserve_fuel = 0.0
	max_thrust = upper_thrust
	isp_sl = upper_isp_sl
	isp_vac = upper_isp_vac
	stage = 2
	engine_on = false
	ignite_in = 2.0
	integrity = maxf(integrity - shock, 1.0)
	return {"ok": true, "waste": sep_waste, "shock": shock}


## Jettison the payload fairing: its mass leaves, but the payload is exposed (extra drag; heat/pressure damage in air).
func jettison_fairing() -> Dictionary:
	if not fairing_on:
		return {"ok": false}
	fairing_on = false
	fairing_time = time
	dry_mass -= fairing_mass
	var dmg := 0.0
	var h := altitude()
	if h < 80_000.0:
		dmg = 8.0 + clampf(air_density() / 0.02, 0.0, 1.0) * 55.0
		fairing_early = true
	integrity = maxf(integrity - dmg, 1.0)
	return {"ok": true, "damage": dmg, "early": fairing_early}


## Drop the (usually empty) strap-on boosters. Separating while they still burn throws propellant away; in dense air
## near Max-Q the separation is violent. Returns {"ok", "waste", "shock"}.
func separate_boosters() -> Dictionary:
	if not has_boosters:
		return {"ok": false}
	b_waste = b_fuel / b_fuel_cap if b_fuel_cap > 0.0 else 0.0
	b_sep_time = time
	var shock := clampf(q / Q_LIMIT - 0.35, 0.0, 1.0) * 35.0
	dry_mass -= b_dry
	b_fuel = 0.0
	has_boosters = false
	b_thrust_now = 0.0
	integrity = maxf(integrity - shock, 1.0)
	return {"ok": true, "waste": b_waste, "shock": shock}


## ---- availability rules (used by the UI; the physics above stays unconditional)
func can_separate_stage() -> bool:
	return has_upper and stage == 1 and fuel_fraction() <= SEP_FUEL_MAX


func can_separate_boosters() -> bool:
	return has_boosters and (b_fuel / maxf(b_fuel_cap, 1.0)) <= SEP_FUEL_MAX


func can_jettison_fairing() -> bool:
	return fairing_on and altitude() >= FAIRING_MIN_ALT


## [translation key, argument] explaining why an action is not available yet ("" key = available).
func why_not_stage() -> Array:
	if not has_upper or stage != 1:
		return ["", 0]
	if fuel_fraction() > SEP_FUEL_MAX:
		return ["STG_WHY_STAGE", int(fuel_fraction() * 100.0)]
	return ["", 0]


func why_not_boosters() -> Array:
	if not has_boosters:
		return ["", 0]
	var f := b_fuel / maxf(b_fuel_cap, 1.0)
	if f > SEP_FUEL_MAX:
		return ["STG_WHY_BOOST", int(f * 100.0)]
	return ["", 0]


func why_not_fairing() -> Array:
	if not fairing_on:
		return ["", 0]
	if altitude() < FAIRING_MIN_ALT:
		return ["STG_WHY_FAIRING", int(altitude() / 1000.0)]
	return ["", 0]


func current_cd() -> float:
	return cd + (0.0 if fairing_on else CD_NO_FAIRING)


func air_density() -> float:
	return 1.225 * exp(-altitude() / SCALE_H)


func fuel_fraction() -> float:
	return fuel / fuel_cap if fuel_cap > 0.0 else 0.0


## Prograde direction expressed as pitch from local vertical.
func prograde_pitch() -> float:
	return atan2(vt, vr)


func step(dt: float) -> void:
	if crashed:
		return
	time += dt
	if ignite_in > 0.0:
		ignite_in -= dt
		if ignite_in <= 0.0:
			engine_on = true
	if fuel <= 0.0 and has_upper and stage == 1:
		dead_mass_time += dt
	if has_boosters and b_fuel <= 0.0:
		b_dead_time += dt
	var h := r - R
	var m := mass()
	thrust_now = 0.0
	var mdot := 0.0
	if engine_on and fuel > 0.0 and throttle > 0.0:
		var p := exp(-h / SCALE_H)
		var isp := lerpf(isp_vac, isp_sl, p)
		thrust_now = max_thrust * throttle * (isp / isp_sl) * thrust_scale
		mdot = max_thrust * throttle / (isp_sl * G0)
		fuel = maxf(0.0, fuel - mdot * dt)
	b_thrust_now = 0.0
	if has_boosters and engine_on and b_fuel > 0.0 and throttle > 0.0:
		var pb := exp(-h / SCALE_H)
		var isp_b := lerpf(b_isp_vac, b_isp_sl, pb)
		b_thrust_now = b_thrust * throttle * (isp_b / b_isp_sl) * thrust_scale
		b_fuel = maxf(0.0, b_fuel - b_thrust * throttle / (b_isp_sl * G0) * dt)
		thrust_now += b_thrust_now
	var g := MU / (r * r)
	var v := sqrt(vr * vr + vt * vt)
	q = 0.5 * air_density() * v * v
	var drag := q * current_cd() * area
	var ar := -g + vt * vt / r
	var at := -vr * vt / r
	if v > 0.01:
		ar -= drag / m * vr / v
		at -= drag / m * vt / v
	var ta := thrust_now / m
	g_load = ta
	if ta > G_LIMIT:
		integrity = maxf(0.0, integrity - (ta - G_LIMIT) * 0.12 * dt)
	ar += ta * cos(pitch)
	at += ta * sin(pitch)
	accel = sqrt(ar * ar + at * at) if not on_pad else ta
	if on_pad:
		if ar <= 0.0:
			vr = 0.0
			vt = 0.0
			return
		on_pad = false
	vr += ar * dt
	vt += at * dt
	r += vr * dt
	theta += vt / r * dt
	max_q_seen = maxf(max_q_seen, q)
	if q > Q_LIMIT:
		integrity = maxf(0.0, integrity - (q / Q_LIMIT - 1.0) * 28.0 * dt)
	if r <= R and not on_pad:
		r = R
		var impact := sqrt(vr * vr + vt * vt)
		crashed = true
		vr = 0.0
		vt = 0.0
		if impact < 6.0:
			crashed = true  # a soft touchdown still ends the ascent


func orbit() -> Dictionary:
	var v2 := vr * vr + vt * vt
	var energy := v2 * 0.5 - MU / r
	var hmom := r * vt
	if energy >= 0.0:
		return {"bound": false, "ap": INF, "pe": -R, "ecc": 1.0}
	var a := -MU / (2.0 * energy)
	var e := sqrt(maxf(0.0, 1.0 + 2.0 * energy * hmom * hmom / (MU * MU)))
	return {"bound": true, "ap": a * (1.0 + e) - R, "pe": a * (1.0 - e) - R, "ecc": e}


func in_stable_orbit() -> bool:
	var o := orbit()
	return bool(o["bound"]) and float(o["pe"]) >= SAFE_PE and altitude() >= SAFE_PE
