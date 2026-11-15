class_name LanderModel
extends RefCounted
## Powered-descent physics of the lunar lander in the vertical x/y plane. Lunar gravity 1.62 m/s^2,
## thrust along the lander's axis, rocket-equation propellant burn, rotation with inertia.
## Fuel and thrust come from the design (LunarDesign.stats) - the player's choices decide whether
## the landing is possible at all.

const G := 1.62
const G0 := 9.80665
const ROT_ACC := 0.55            # rad/s^2 from the RCS
const OMEGA_MAX := 0.9

var pos := Vector2(-380.0, 1300.0)    # x downrange (m), y altitude (m); pad at x = 0
var vel := Vector2(18.0, -30.0)
var angle := 0.0                      # rad, + = nose tilted towards +x
var omega := 0.0
var throttle := 0.0
var fuel := 100.0                     # kg
var dry := 1000.0                     # kg
var thrust_max := 9000.0
var isp := 310.0
var safe_half_width := 40.0           # m around the pad where the ground is flat enough
var time := 0.0
var fuel_used := 0.0

var landed := false
var crashed := false
var outcome := ""                     # "" | "ok" | translation key of the failure reason
var touch_speed := Vector2.ZERO
var touch_angle := 0.0


func setup(s: Dictionary, fuel_kg: float) -> void:
	dry = float(s["dry"])
	fuel = fuel_kg
	thrust_max = float(s["thrust"])
	isp = float(s["isp"])
	safe_half_width = lerpf(70.0, 20.0, float(s["rough"]))


func mass() -> float:
	return dry + fuel


func fuel_fraction(start_fuel: float) -> float:
	return fuel / maxf(start_fuel, 0.001)


func twr() -> float:
	return thrust_max / (mass() * G)


## throttle_in 0..1 (absolute), turn_in -1..1 (rotation command).
func step(dt: float, throttle_in: float, turn_in: float) -> void:
	if landed or crashed:
		return
	time += dt
	throttle = clampf(throttle_in, 0.0, 1.0) if fuel > 0.0 else 0.0
	var t := thrust_max * throttle
	var m := mass()
	var dir := Vector2(sin(angle), cos(angle))
	var acc := dir * (t / m) + Vector2(0.0, -G)
	var burn := t / (isp * G0) * dt
	burn = minf(burn, fuel)
	fuel -= burn
	fuel_used += burn
	omega = clampf(omega + turn_in * ROT_ACC * dt - omega * 0.15 * dt, -OMEGA_MAX, OMEGA_MAX)
	angle += omega * dt
	vel += acc * dt
	pos += vel * dt
	if pos.y <= 0.0:
		pos.y = 0.0
		_touchdown()


func _touchdown() -> void:
	touch_speed = vel
	touch_angle = angle
	var on_pad := absf(pos.x) <= safe_half_width
	if not on_pad:
		crashed = true
		outcome = "LUN_FAIL_TERRAIN"
	elif vel.y < -3.2:
		crashed = true
		outcome = "LUN_FAIL_SPEED"
	elif absf(vel.x) > 1.8:
		crashed = true
		outcome = "LUN_FAIL_DRIFT"
	elif absf(angle) > deg_to_rad(11.0) or absf(omega) > 0.25:
		crashed = true
		outcome = "LUN_FAIL_TILT"
	else:
		landed = true
		outcome = "ok"
	vel = Vector2.ZERO
	omega = 0.0
