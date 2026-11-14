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

# vehicle
var dry_mass := 0.0
var fuel := 0.0
var fuel_cap := 0.0
var max_thrust := 0.0
var isp_sl := 300.0
var isp_vac := 340.0
var cd := 0.4
var area := 10.0

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


func setup(stats: Dictionary) -> void:
	dry_mass = float(stats["mass_dry"])
	fuel = float(stats["fuel"])
	fuel_cap = fuel
	max_thrust = float(stats["thrust"])
	isp_sl = float(stats["isp_sl"])
	isp_vac = float(stats["isp_vac"])
	cd = float(stats["cd"])


func mass() -> float:
	return dry_mass + fuel


func altitude() -> float:
	return r - R


func speed() -> float:
	return sqrt(vr * vr + vt * vt)


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
	var g := MU / (r * r)
	var v := sqrt(vr * vr + vt * vt)
	q = 0.5 * air_density() * v * v
	var drag := q * cd * area
	var ar := -g + vt * vt / r
	var at := -vr * vt / r
	if v > 0.01:
		ar -= drag / m * vr / v
		at -= drag / m * vt / v
	var ta := thrust_now / m
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
