extends MissionBase
## Mission 1 - Rocket Assembly & Launch, structured as the NASA mission-design loop:
##   briefing -> MISSION DESIGN (goal + satellite) -> rocket assembly -> DESIGN REVIEW
##   (verification) -> countdown -> powered flight -> orbit -> deployment -> GROUND downlink ->
##   result (4 segments: Launch / Space / Ground / Users).
## Physics lives in FlightModel, the trade-off maths in M1Design; the 3D presentation lives in
## Core3D (PadScene3D / Rocket3D / FlightDirector3D); HUD + UI stay 2D on top.

enum S { DESIGN, ASSEMBLY, REVIEW, COUNTDOWN, FLIGHT, DEPLOY, DOWNLINK, ENDED }

const STEP := 0.05
const COUNTDOWN_LEN := 6.0

var state: int = S.DESIGN
var design: Dictionary = {}
var sat: Dictionary = {}
var design_view: MissionDesignView
var review: DesignReview
var ground_panel: GroundLinkPanel
var world_layer: CanvasLayer
var hud_layer: CanvasLayer
var assembly: AssemblyView
var pad_scene: PadScene3D
var flight: FlightDirector3D
var hud: FlightHud
var model: FlightModel
var build: Dictionary = {}
var stats: Dictionary = {}
var warp := 1
var assist := false

var _acc := 0.0
var _cd := 0.0
var _last_cd := -1
var _hint_timer := 0.0
var _override_hint := ""
var _override_t := 0.0
var _max_alt := 0.0
var _fuel_out_t := 0.0
var _t_asm := 0.0
var inspecting := false
var cam_hint: CameraHint
var dev_autopilot := false
var _ap_phase := 0


func _init() -> void:
	mission_id = "m1_launch"


func _briefing_data() -> Dictionary:
	return {
		"title": "M1_TITLE",
		"objectives": ["M1_OBJ_1", "M1_OBJ_2", "M1_OBJ_3", "M1_OBJ_4", "M1_OBJ_5"],
		"controls": [
			["MOUSE", "M1_CTRL_DRAG"],
			["W S", "M1_CTRL_THROTTLE"],
			["A D", "M1_CTRL_PITCH"],
			["T", "M1_CTRL_ASSIST"],
			["Z X", "M1_CTRL_FULLCUT"],
			["1 2 3", "M1_CTRL_WARP"],
			["SPACE", "M1_CTRL_DEPLOY"],
			["ESC", "M1_CTRL_PAUSE"],
		],
	}


func _build_mission() -> void:
	pad_scene = PadScene3D.new()
	add_child(pad_scene)
	pad_scene.stage.set_look("dawn")
	world_layer = CanvasLayer.new()
	world_layer.layer = 0
	add_child(world_layer)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	cam_hint = CameraHint.new()
	hud_layer.add_child(cam_hint)
	cam_hint.setup(false, 16.0)
	pad_scene.orbit.engaged_changed.connect(_on_orbit_engaged)


func _on_orbit_engaged(on: bool) -> void:
	var flying := state == S.COUNTDOWN or state == S.FLIGHT or state == S.DEPLOY or state == S.DOWNLINK
	inspecting = on and flying
	cam_hint.set_inspect(inspecting)
	if inspecting:
		Sfx.stop_all_loops()


func _on_mission_start() -> void:
	design_view = MissionDesignView.new()
	world_layer.add_child(design_view)
	design_view.design_done.connect(_on_design_done)


## Step 1-2 finished: the satellite is designed, now design the rocket for it.
func _on_design_done(d: Dictionary) -> void:
	design = d
	sat = M1Design.sat_stats(design)
	if design_view != null:
		design_view.queue_free()
		design_view = null
	state = S.ASSEMBLY
	assembly = AssemblyView.new()
	assembly.scene3d = pad_scene
	assembly.payload_mass = float(sat["mass"])
	assembly.sat_cost = int(sat["cost"])
	world_layer.add_child(assembly)
	assembly.launch_requested.connect(_on_review_request)


## Step 4: verification (design review) before launch.
func _on_review_request(b: Dictionary) -> void:
	if state != S.ASSEMBLY:
		return
	build = b
	stats = M1Parts.compute(build, float(sat["mass"]), int(sat["cost"]))
	state = S.REVIEW
	assembly.visible = false
	review = DesignReview.new()
	world_layer.add_child(review)
	review.setup(design, stats)
	review.back_requested.connect(func():
		review.queue_free()
		assembly.visible = true
		state = S.ASSEMBLY)
	review.launch_approved.connect(func():
		review.queue_free()
		_on_launch(build))


func dev_review() -> void:
	## Test helper: default satellite + a rocket, straight to the design review panel.
	dev_auto_design()
	for step in [["engine", "kestrel"], ["tank", "l"], ["nose", "aero"]]:
		assembly._on_install(step[0], step[1])
	_on_review_request(assembly.build.duplicate())


func dev_auto_design() -> void:
	## Test helper: accept the default satellite design.
	dev_skip_briefing_if_needed()
	_on_design_done(M1Design.default_design())


func dev_skip_briefing_if_needed() -> void:
	if state == S.DESIGN and design_view == null:
		dev_skip_briefing()


## Slow cinematic orbit around the rocket while the player designs it.
func _update_assembly_camera(delta: float) -> void:
	var center := pad_scene.rocket_pivot.global_position
	var h := pad_scene.rocket.total_height()
	var az := deg_to_rad(28.0 + 20.0 * sin(_t_asm * 0.22))
	var r := maxf(125.0, h * 2.3)
	pad_scene.orbit.update(delta, center + Vector3(sin(az) * r, 6.0 + 2.0 * sin(_t_asm * 0.3), cos(az) * r),
		center + Vector3(0, -2, 0), 36.0)


## Developer/test helper: build a rocket and go straight to the launch (skips the countdown).
func dev_quick(spec: String) -> void:
	var p := spec.split("/")
	dev_skip_briefing()
	design = M1Design.default_design()
	sat = M1Design.sat_stats(design)
	if design_view != null:
		design_view.queue_free()
		design_view = null
	state = S.ASSEMBLY
	_on_launch({"engine": p[0], "tank": p[1], "nose": p[2]})
	state = S.FLIGHT
	model.engine_on = true
	model.throttle = 1.0
	flight.liftoff()


func dev_orbit() -> void:
	## Puts the rocket in a circular 150 km orbit (screenshots of the deploy sequence).
	model.r = FlightModel.R + 150000.0
	model.vr = 0.0
	model.vt = sqrt(FlightModel.MU / model.r)
	model.pitch = PI * 0.5
	model.throttle = 0.0
	model.on_pad = false
	model.fuel *= 0.06
	flight.sync()
	flight.skip_intro()


func dev_info() -> void:
	var c := pad_scene.camera
	print("CAM pos=", c.global_position, " fwd=", -c.global_transform.basis.z, " far=", c.far, " fov=", c.fov)
	print("PLANET pivot=", pad_scene.stage.planet_pivot.global_position, " rocket=", pad_scene.rocket_pivot.global_position)
	print("ALT=", model.altitude(), " vt=", model.vt, " vr=", model.vr, " pitch=", model.pitch)


func dev_explode() -> void:
	flight.explode()


func dev_deploy() -> void:
	_try_deploy()


func dev_fly(seconds: String) -> void:
	## Runs the built-in test autopilot for N simulated seconds (visual checks only).
	var n := int(float(seconds) / STEP)
	for i in n:
		var h := model.altitude()
		model.throttle = 1.0 if model.q < 0.8 * FlightModel.Q_LIMIT else 0.55
		model.pitch = 0.0 if h < 600.0 else deg_to_rad(90.0 * minf(1.0, pow((h - 600.0) / 60000.0, 0.5)))
		model.step(STEP)
	flight.sync()
	flight.skip_intro()


# ------------------------------------------------------------------ launch --
func _on_launch(b: Dictionary) -> void:
	if state != S.ASSEMBLY and state != S.REVIEW:
		return
	if design.is_empty():
		design = M1Design.default_design()
		sat = M1Design.sat_stats(design)
	build = b
	stats = M1Parts.compute(build, float(sat["mass"]), int(sat["cost"]))
	if not M1Parts.can_launch(stats):
		return
	model = FlightModel.new()
	model.setup(stats)
	# hand the camera back to the flight director (a free-look from the designer must not leak into flight)
	pad_scene.orbit.disengage()
	if assembly != null:
		assembly.queue_free()
		assembly = null
	flight = FlightDirector3D.new()
	add_child(flight)
	flight.setup(pad_scene, model, build)
	hud = FlightHud.new()
	hud_layer.add_child(hud)
	hud.build()
	cam_hint.set_mission_mode(true, 118.0)
	state = S.COUNTDOWN
	_cd = 0.0
	_last_cd = -1
	hud.set_hint("M1_HINT_COUNTDOWN", UIKit.C_ACCENT)


func _process(delta: float) -> void:
	_t_asm += delta
	if (state == S.DESIGN or state == S.ASSEMBLY or state == S.REVIEW) and pad_scene != null and pad_scene.is_inside_tree():
		_update_assembly_camera(delta)
	pad_scene.orbit.user_can_engage = state == S.DESIGN or state == S.ASSEMBLY or state == S.REVIEW
	if ended or model == null:
		return
	if inspecting:
		# INSPECT MODE: the simulation is frozen, only the camera moves
		if hud != null:
			hud.refresh(model, warp, assist, model.time)
		return
	match state:
		S.COUNTDOWN:
			_update_countdown(delta)
		S.FLIGHT:
			_update_flight(delta)
		S.DEPLOY:
			flight.sync()
	if hud != null:
		hud.refresh(model, warp, assist, model.time)
	_update_fx()


func _update_countdown(delta: float) -> void:
	_cd += delta
	var tleft := COUNTDOWN_LEN - _cd
	var n := int(ceil(tleft))
	if n != _last_cd and n >= 1 and n <= 5:
		_last_cd = n
		hud.big(str(n), UIKit.C_ACCENT)
		Sfx.play("tick")
		if n == 3:
			Sfx.play("ignite", -4.0)
	var ignition := clampf((_cd - (COUNTDOWN_LEN - 3.0)) / 3.0, 0.0, 1.0)
	model.throttle = 0.15 + 0.85 * ignition if _cd > COUNTDOWN_LEN - 3.0 else 0.0
	flight.shake_amp = ignition * 2.2 * _shake_factor()
	flight.set_ignition(ignition)
	if _cd >= COUNTDOWN_LEN:
		state = S.FLIGHT
		model.engine_on = true
		model.throttle = 1.0
		flight.liftoff()
		Sfx.play("go")
		hud.big(tr("M1_LIFTOFF"), UIKit.C_ORANGE)
		hud.set_hint("M1_HINT_LIFTOFF", UIKit.C_TEXT)


func _shake_factor() -> float:
	return 1.0 if bool(GameState.settings["shake"]) else 0.0


## Test autopilot (Tools/e2e_m1.gd): same logic as a competent player.
func _autopilot(delta: float) -> void:
	var h := model.altitude()
	var o := model.orbit()
	var ap := minf(float(o["ap"]), 1.0e9)
	var thr := 1.0 if model.q < 0.8 * FlightModel.Q_LIMIT else 0.55
	if _ap_phase == 0:
		model.pitch = 0.0 if h < 600.0 else deg_to_rad(90.0 * minf(1.0, pow((h - 600.0) / 60000.0, 0.5)))
		if ap >= 115000.0:
			_ap_phase = 1
	if _ap_phase == 1:
		thr = 0.0
		model.pitch = deg_to_rad(90.0)
		if model.vr < 15.0:
			_ap_phase = 2
	if _ap_phase == 2:
		thr = 1.0
		model.pitch = deg_to_rad(90.0 + clampf(model.vr * 0.25, -10.0, 40.0))
	if model.in_stable_orbit():
		thr = 0.0
		_try_deploy()
	model.throttle = thr
	warp = 2 if h < 30000.0 else 4


func _update_flight(delta: float) -> void:
	if dev_autopilot:
		_autopilot(delta)
	else:
		_manual_input(delta)
	_simulate(delta)


func _manual_input(delta: float) -> void:
	# ---- player input
	var thr_d := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		thr_d += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		thr_d -= 1.0
	model.throttle = clampf(model.throttle + thr_d * 0.7 * delta, 0.0, 1.0)
	if Input.is_physical_key_pressed(KEY_Z):
		model.throttle = 1.0
	if Input.is_physical_key_pressed(KEY_X):
		model.throttle = 0.0
	var pitch_d := 0.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		pitch_d += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		pitch_d -= 1.0
	if assist and pitch_d == 0.0 and model.speed() > 40.0:
		var target := model.prograde_pitch()
		model.pitch = move_toward(model.pitch, clampf(target, 0.0, PI), deg_to_rad(40.0) * delta)
	else:
		model.pitch = clampf(model.pitch + pitch_d * deg_to_rad(26.0) * delta, deg_to_rad(-15.0), deg_to_rad(185.0))


func _simulate(delta: float) -> void:
	# ---- time warp limits (careful in dense air)
	var max_warp := 2 if model.altitude() < 30000.0 else 4
	if warp > max_warp:
		warp = max_warp
	# ---- simulate
	_acc += delta * float(warp)
	var steps := 0
	while _acc >= STEP and steps < 24:
		model.step(STEP)
		_acc -= STEP
		steps += 1
		if model.integrity <= 0.0 or model.crashed:
			break
	flight.sync()
	_max_alt = maxf(_max_alt, model.altitude())
	# ---- end conditions
	if model.integrity <= 0.0:
		_fail("M1_FAIL_DESTROYED", true)
		return
	if model.crashed and model.time > 2.0:
		_fail("M1_FAIL_CRASH", true)
		return
	if model.fuel <= 0.0 and not model.in_stable_orbit():
		var o := model.orbit()
		if not bool(o["bound"]) or float(o["pe"]) < FlightModel.SAFE_PE:
			_fuel_out_t += delta
			if _fuel_out_t > 3.0:
				_fail("M1_FAIL_FUEL", false)
				return
	_hint_timer -= delta
	if _hint_timer <= 0.0:
		_hint_timer = 0.2
		_update_hint()
	if _override_t > 0.0:
		_override_t -= delta
	if Input.is_physical_key_pressed(KEY_SPACE):
		_try_deploy()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# C = free camera (inspect mode) while the rocket is flying; the simulation is frozen
	if event.keycode == KEY_C and (state == S.COUNTDOWN or state == S.FLIGHT or state == S.DEPLOY or state == S.DOWNLINK):
		pad_scene.orbit.toggle_sticky()
		return
	if state != S.FLIGHT:
		return
	match event.keycode:
		KEY_T:
			assist = not assist
		KEY_1:
			warp = 1
		KEY_2:
			warp = 2
		KEY_3:
			warp = 4 if model.altitude() >= 30000.0 else 2
		KEY_SPACE:
			_try_deploy()


func _update_hint() -> void:
	if _override_t > 0.0:
		hud.set_hint(_override_hint, UIKit.C_WARN)
		return
	var o := model.orbit()
	var h := model.altitude()
	var ap := minf(float(o["ap"]), 1.0e9)
	var pe := float(o["pe"])
	if model.in_stable_orbit():
		hud.set_hint("M1_HINT_ORBIT", UIKit.C_GOOD)
	elif model.q > 0.85 * FlightModel.Q_LIMIT:
		hud.set_hint("M1_HINT_MAXQ", UIKit.C_BAD)
	elif model.fuel_fraction() < 0.08 and model.fuel > 0.0:
		hud.set_hint("M1_HINT_FUEL", UIKit.C_WARN)
	elif bool(o["bound"]) and ap >= 110000.0 and pe < FlightModel.SAFE_PE:
		if model.vr > 150.0 and model.throttle > 0.05:
			hud.set_hint("M1_HINT_COAST", UIKit.C_WARN)
		elif model.vr > 60.0:
			hud.set_hint("M1_HINT_WAIT", UIKit.C_ACCENT)
		else:
			hud.set_hint("M1_HINT_BURN", UIKit.C_ORANGE)
	elif h < 900.0:
		hud.set_hint("M1_HINT_LIFTOFF", UIKit.C_TEXT)
	elif model.pitch < deg_to_rad(8.0) and h < 12000.0:
		hud.set_hint("M1_HINT_PITCH", UIKit.C_ACCENT)
	else:
		hud.set_hint("M1_HINT_TURN", UIKit.C_TEXT)


func _update_fx() -> void:
	if flight == null or model == null:
		return
	var thr := model.throttle if (model.engine_on and model.fuel > 0.0) or state == S.COUNTDOWN else 0.0
	if state == S.COUNTDOWN and _cd < COUNTDOWN_LEN - 3.0:
		thr = 0.0
	var rho := model.air_density()
	# smoke is left behind the moving rocket: push it opposite to the velocity
	var drift := Vector3(-model.vt, -model.vr * 0.0 - model.vr, 0.0) * 0.5
	if drift.length() > 600.0:
		drift = drift.normalized() * 600.0
	flight.update_fx(thr, clampf(rho / 0.9, 0.0, 1.0), drift)
	# engine rumble follows throttle; it gets thinner in vacuum. Max-Q warning alarm.
	if thr > 0.02 and state != S.ENDED:
		Sfx.loop("rumble", lerpf(-26.0, -4.0, thr) - 10.0 * (1.0 - clampf(rho / 0.9, 0.0, 1.0)), 0.85 + 0.3 * thr)
	else:
		Sfx.loop_stop("rumble")
	if state == S.FLIGHT and model.q > 0.85 * FlightModel.Q_LIMIT:
		Sfx.loop("alarm", -14.0)
	else:
		Sfx.loop_stop("alarm")
	if state == S.FLIGHT:
		var near_ground := clampf(1.0 - model.altitude() / 2500.0, 0.0, 1.0)
		var buffet := 0.0
		if model.q > 0.7 * FlightModel.Q_LIMIT:
			buffet = (model.q / FlightModel.Q_LIMIT - 0.7) * 6.0
		flight.shake_amp = (model.throttle * 2.6 * near_ground + buffet) * _shake_factor()


# ------------------------------------------------------------------ deploy --
func _try_deploy() -> void:
	if state != S.FLIGHT:
		return
	if not model.in_stable_orbit():
		_override_hint = "M1_DEPLOY_DENIED"
		_override_t = 3.0
		return
	state = S.DEPLOY
	model.throttle = 0.0
	Sfx.loop_stop("rumble")
	Sfx.loop_stop("alarm")
	Sfx.play("whoosh", -4.0)
	hud.set_hint("M1_HINT_DEPLOYING", UIKit.C_ACCENT)
	await flight.deploy_satellite(5.0, design)
	if ended:
		return
	await _downlink()
	if ended:
		return
	_succeed()


## GROUND segment: the satellite passes over a station and the data is downloaded. What does not
## fit into the contact window (slow antenna vs fast instrument) is lost.
func _downlink() -> void:
	state = S.DOWNLINK
	var o := model.orbit()
	var sr := M1Design.science_result(design, float(o["ap"]), float(o["pe"]))
	hud.set_hint("M1_HINT_DOWNLINK", UIKit.C_ACCENT)
	ground_panel = GroundLinkPanel.new()
	hud_layer.add_child(ground_panel)
	var total := float(sat["data_produced"])
	ground_panel.setup(total, float(sr["data_f"]), 6.5)
	await ground_panel.finished
	await get_tree().create_timer(0.8).timeout
	ground_panel.queue_free()


func _succeed() -> void:
	state = S.ENDED
	var fuel_left := model.fuel_fraction()
	var o := model.orbit()
	var sr := M1Design.science_result(design, float(o["ap"]), float(o["pe"]))
	var science := float(sr["science"])
	var stars := 1
	if science >= 0.7:
		stars += 1
	if science >= 0.95 and model.integrity >= 80.0:
		stars += 1
	var score := stars * 1000 + int(science * 1500.0) + int(fuel_left * 300.0) + int(model.integrity * 2.0) \
		+ maxi(M1Parts.BUDGET - int(stats["cost"]), 0) * 4
	hud.set_hint("M1_HINT_SUCCESS", UIKit.C_GOOD)
	var goal_id := str(design["goal"])
	var goal: Dictionary = M1Design.GOALS[goal_id]
	var res: Array = [
		["R_GOAL", tr(str(goal["name"]))],
		["R_ORBIT_AP", hud.fmt_dist(float(o["ap"]))],
		["R_ORBIT_PE", hud.fmt_dist(float(o["pe"]))],
		["R_ORBIT_Q", "%d%%" % int(float(sr["orbit_q"]) * 100.0)],
		["R_POWER_F", "%d%%" % int(float(sr["power_f"]) * 100.0)],
		["R_BATT_F", "%d%%" % int(float(sr["batt_f"]) * 100.0)],
		["R_DATA_F", "%d%%" % int(float(sr["data_f"]) * 100.0)],
		["R_DATA_GB", "%.1f GB" % float(sr["data_gb"])],
		["R_FUEL_LEFT", "%d%%" % int(fuel_left * 100.0)],
		["R_INTEGRITY", "%d%%" % int(model.integrity)],
		["R_COST", "$%d / $%d" % [int(stats["cost"]), M1Parts.BUDGET]],
		["R_SCORE", str(score)],
	]
	# four-segment evaluation
	var launch_r := clampf(model.integrity / 100.0 * 0.6 + (0.4 if model.max_q_seen < 0.9 * FlightModel.Q_LIMIT else 0.2), 0.0, 1.0)
	var space_r := (float(sr["orbit_q"]) + float(sr["power_f"]) + float(sr["batt_f"])) / 3.0
	var segments: Array = [["SEG_LAUNCH", launch_r], ["SEG_SPACE", space_r], ["SEG_GROUND", float(sr["data_f"])],
		["SEG_USER", clampf(science, 0.0, 1.0)]]
	var tips: Array = []
	match str(sr["weakest"]):
		"power":
			tips.append("TIP_POWER")
		"batt":
			tips.append("TIP_BATT")
		"data":
			tips.append("TIP_DATA")
		"orbit":
			tips.append("TIP_ORBIT_LOW" if float(sr["mean_km"]) < float(goal["best"][0]) else "TIP_ORBIT_HIGH")
	if fuel_left > 0.4:
		tips.append("TIP_FUEL")
	if model.max_q_seen > 0.9 * FlightModel.Q_LIMIT:
		tips.append("TIP_MAXQ")
	if tips.is_empty():
		tips.append("TIP_GOOD")
	var extra := {"segments": segments, "science": science, "tips": tips,
		"user": "USER_%s_%d" % [goal_id.to_upper(), M1Design.science_tier(science)]}
	Sfx.stop_all_loops()
	finish(true, stars, score, res, "M1_WIN_REASON", 1.0, extra)


func _fail(reason_key: String, boom: bool) -> void:
	if state == S.ENDED:
		return
	state = S.ENDED
	Sfx.stop_all_loops()
	if boom:
		flight.explode()
		Sfx.play("hit", 2.0)
		flight.shake_amp = 12.0 * _shake_factor()
	pad_scene.rocket.set_thrust(0.0, 0.0, Vector3.ZERO)
	hud.set_hint("", UIKit.C_TEXT)
	var res: Array = [
		["R_MAX_ALT", hud.fmt_dist(_max_alt)],
		["R_FUEL_LEFT", "%d%%" % int(model.fuel_fraction() * 100.0)],
		["R_MAXQ", Units.kpa(model.max_q_seen)],
		["R_TIME", "%d:%02d" % [int(model.time) / 60, int(model.time) % 60]],
	]
	finish(false, 0, 0, res, reason_key, 1.8)
