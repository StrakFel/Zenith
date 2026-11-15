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
var summary: MissionSummary
var _pitch_vel := 0.0
var stage_panel: StagePanel
var _ign_fx := false
var _stuck_t := 0.0
var fairing_late := false
var auto_warp := true          # time compression: boring parts are skipped unless the player takes over
var _ms_done: Array[int] = []
const MILESTONES := [[600.0, "M1_MS_TOWER"], [12000.0, "M1_MS_SKY"], [45000.0, "M1_MS_THIN"], [100000.0, "M1_MS_SPACE"]]
var _anom_at := -1.0
var _anom_end := -1.0
var anomaly_seen := false
var last_prox: Dictionary = {}   # Mission Success Proximity of the finished flight (read by tests)
var _ap_phase := 0
## Launch profile (Missions 2-5 reuse this scene as their launch segment; empty = Mission 1 with its satellite).
var profile: Dictionary = {}
var profile_id := ""
var payload_lab: PayloadLab
var _handoff_started := false
var auto_flight := true               # the autopilot flies the rocket (default); any control key or M takes over
var guided := true                   # Guided Launch: pitch profile + next-step coach (key H toggles)
var _guide_override_t := 0.0


func _init() -> void:
	mission_id = "m1_launch"
	M1Parts.active_budget = M1Parts.BUDGET
	M1Parts.active_mission = 1
	M1Parts.active_required_dv = M1Parts.REQUIRED_DV


## Called by the subclasses of Missions 2-5 from _init(): configures this launch segment from a LaunchProfile.
func _setup_profile(id: String) -> void:
	profile_id = id
	profile = LaunchProfiles.get_profile(id)
	mission_id = str(profile["mission_id"])
	M1Parts.active_budget = int(profile["budget"])
	M1Parts.active_mission = int(profile["index"])


func _briefing_data() -> Dictionary:
	if not profile.is_empty():
		return {
			"title": str(profile["title"]),
			"objectives": ["%s_OBJ_GOAL" % profile_id.to_upper(), "PRF_OBJ_LAB", "PRF_OBJ_ROCKET", "PRF_OBJ_FLY", "%s_OBJ_OPS" % profile_id.to_upper()],
			"controls": [
				["MOUSE", "M1_CTRL_DRAG"], ["W S", "M1_CTRL_THROTTLE"], ["A D", "M1_CTRL_PITCH"], ["Z X", "M1_CTRL_FULLCUT"],
				["G", "M1_CTRL_STAGE"], ["B", "M1_CTRL_BOOSTERS"], ["F", "M1_CTRL_FAIRING"], ["1 2 3", "M1_CTRL_WARP"],
				["SPACE", "PRF_CTRL_HANDOFF"], ["ESC", "M1_CTRL_PAUSE"]],
		}
	return {
		"title": "M1_TITLE",
		"objectives": ["M1_OBJ_1", "M1_OBJ_2", "M1_OBJ_3", "M1_OBJ_4", "M1_OBJ_5"],
		"controls": [
			["MOUSE", "M1_CTRL_DRAG"],
			["W S", "M1_CTRL_THROTTLE"],
			["A D", "M1_CTRL_PITCH"],
			["T", "M1_CTRL_ASSIST"],
			["H", "M1_CTRL_GUIDE"],
			["F1", "M1_CTRL_HELP"],
			["Z X", "M1_CTRL_FULLCUT"],
			["G", "M1_CTRL_STAGE"],
			["F", "M1_CTRL_FAIRING"],
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
	if not profile.is_empty():
		cam_hint.set_hud_corner(true)      # keep the camera hint clear of the wide lab panel
		payload_lab = PayloadLab.new()
		payload_lab.profile_id = profile_id
		world_layer.add_child(payload_lab)
		payload_lab.design_done.connect(_on_design_done)
		payload_lab.back_requested.connect(func(): Router.go_to(Router.MISSION_SELECT))
		return
	design_view = MissionDesignView.new()
	world_layer.add_child(design_view)
	design_view.design_done.connect(_on_design_done)
	design_view.back_requested.connect(func(): Router.go_to(Router.MISSION_SELECT))
	cam_hint.set_bottom(true, 6.0, true)       # short camera help between the two panels, fades; F1 shows it again


## Step 1-2 finished: the satellite is designed, now design the rocket for it.
func _on_design_done(d: Dictionary) -> void:
	design = d
	sat = M1Design.sat_stats(design) if profile.is_empty() else LaunchProfiles.payload_stats(profile_id, design)
	if payload_lab != null:
		payload_lab.queue_free()
		payload_lab = null
		cam_hint.set_hud_corner(false)
	if design_view != null:
		design_view.queue_free()
		design_view = null
	state = S.ASSEMBLY
	cam_hint.set_bottom(true, 6.0)       # camera help at the bottom, fades after 6 s (F1 shows it again)
	assembly = AssemblyView.new()
	assembly.scene3d = pad_scene
	assembly.payload_mass = float(sat["mass"])
	assembly.sat_cost = int(sat["cost"])
	world_layer.add_child(assembly)
	assembly.launch_requested.connect(_on_review_request)
	assembly.back_requested.connect(_on_assembly_back)
	assembly.missions_requested.connect(func(): Router.go_to(Router.MISSION_SELECT))


## Back from the rocket designer: one step back to the payload / satellite design (which has its own way out to the missions).
func _on_assembly_back() -> void:
	if state != S.ASSEMBLY:
		return
	if assembly != null:
		assembly.queue_free()
		assembly = null
	cam_hint.set_bottom(false)
	state = S.DESIGN
	if profile.is_empty():
		design_view = MissionDesignView.new()
		design_view.design = design.duplicate()
		cam_hint.set_bottom(true, 6.0, true)
		world_layer.add_child(design_view)
		design_view.design_done.connect(_on_design_done)
		design_view.back_requested.connect(func(): Router.go_to(Router.MISSION_SELECT))
	else:
		cam_hint.set_hud_corner(true)
		payload_lab = PayloadLab.new()
		payload_lab.profile_id = profile_id
		payload_lab.design = design.duplicate()
		world_layer.add_child(payload_lab)
		payload_lab.design_done.connect(_on_design_done)
		payload_lab.back_requested.connect(func(): Router.go_to(Router.MISSION_SELECT))


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
	if profile.is_empty():
		review.setup(design, stats)
	else:
		review.setup_reqs(LaunchProfiles.requirements(profile_id, design, stats), M1Parts.can_launch(stats))
	review.back_requested.connect(func():
		review.queue_free()
		assembly.visible = true
		state = S.ASSEMBLY)
	review.launch_approved.connect(func():
		review.queue_free()
		_show_summary())


## Final Mission Summary: everything that was decided, in one place, before the countdown.
func _show_summary() -> void:
	if not profile.is_empty():
		_on_launch(build)
		return
	summary = MissionSummary.new()
	world_layer.add_child(summary)
	summary.setup(design, sat, build, stats)
	summary.back_requested.connect(func():
		summary.queue_free()
		assembly.visible = true
		state = S.ASSEMBLY)
	summary.confirmed.connect(func():
		summary.queue_free()
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
	var az := deg_to_rad(28.0)                        # fixed view: the background must not drift while parts are chosen
	var r := maxf(150.0, h * 2.6)
	# the designer panel covers the right part of the screen: shift the view so the rocket stands in the middle of the free area (left)
	var shift := Vector3.ZERO
	if assembly != null:
		var vs := get_viewport().get_visible_rect().size
		var free_c := (16.0 + (vs.x - 16.0 - AssemblyView.PANEL_W - 14.0)) * 0.5
		var frac := (vs.x * 0.5 - free_c) / vs.x
		var half_w := tan(deg_to_rad(36.0) * 0.5) * (vs.x / vs.y)
		shift = Vector3(cos(az), 0.0, -sin(az)) * r * half_w * 2.0 * frac
	pad_scene.orbit.update(delta, center + Vector3(sin(az) * r, 6.0, cos(az) * r) + shift, center + Vector3(0, -2, 0) + shift, 36.0)


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
	_on_launch({"engine": p[0], "tank": p[1], "nose": p[2], "upper": p[3] if p.size() > 3 else ""})
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
	# reliability decides whether an engine anomaly happens (random event, thrust -45 % for 9 s)
	anomaly_seen = false
	_anom_at = randf_range(15.0, 55.0) if randf() < (1.0 - float(stats["rel"])) * 4.0 else -1.0
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
	flight.scene_design = design if profile.is_empty() else {}
	guided = bool(GameState.settings["guided"])
	auto_flight = bool(GameState.settings["autoflight"])
	_guide_burn = false
	hud.set_autopilot(auto_flight)
	hud.set_guided(guided, _guide_pitch() if guided else NAN)
	_ign_fx = false
	_stuck_t = 0.0
	fairing_late = false
	stage_panel = StagePanel.new()
	hud_layer.add_child(stage_panel)
	stage_panel.setup(model)
	stage_panel.separate_requested.connect(_do_separate)
	stage_panel.boosters_requested.connect(_do_boosters)
	stage_panel.fairing_requested.connect(_do_fairing)
	cam_hint.set_compact(false)
	cam_hint.set_bottom(false)
	cam_hint.set_hud_corner(true)
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
	if stage_panel != null:
		stage_panel.refresh(delta)
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
		if guided and state == S.FLIGHT:
			hud.set_guided(true, _guide_pitch())
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
func _ap_target() -> float:
	if not profile.is_empty():
		return float(profile["ap_target"])
	return float(M1Design.GOALS[design.get("goal", "earth")].get("ap_target", 115000.0))


func _autopilot(delta: float) -> void:
	var h := model.altitude()
	if model.has_boosters and model.b_fuel <= 1.0:
		_do_boosters()
	if model.has_upper and model.stage == 1 and model.fuel <= 1.0:
		_do_separate()
	if model.fairing_on and h >= 95000.0:
		_do_fairing()
	var o := model.orbit()
	var ap := minf(float(o["ap"]), 1.0e9)
	var thr := 1.0 if model.q < 0.8 * FlightModel.Q_LIMIT else 0.55
	if _ap_phase == 0:
		model.pitch = 0.0 if h < 600.0 else deg_to_rad(90.0 * minf(1.0, pow((h - 600.0) / 60000.0, 0.5)))
		if ap >= _ap_target():
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
	var ta_full := model.max_thrust * (model.isp_vac / model.isp_sl if h > 50000.0 else 1.0) / model.mass()
	if ta_full > FlightModel.G_LIMIT * 0.95:
		thr = minf(thr, FlightModel.G_LIMIT * 0.95 / ta_full)      # a competent pilot throttles down near burnout
	model.throttle = thr
	if dev_autopilot:
		warp = 2 if h < 30000.0 else 4
	else:
		_auto_warp()


func _update_flight(delta: float) -> void:
	if dev_autopilot or auto_flight:
		_autopilot(delta)
	else:
		_manual_input(delta)
	_simulate(delta)


func _auto_warp() -> void:
	if not auto_warp:
		return
	var h := model.altitude()
	if model.time < 10.0:
		warp = 1                      # lift-off is shown in real time
	elif h < 30000.0:
		warp = 3
	else:
		warp = 4 if model.throttle > 0.05 else 8


func _manual_input(delta: float) -> void:
	_auto_warp()
	# ---- player input
	var thr_d := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		thr_d += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		thr_d -= 1.0
	model.throttle = clampf(model.throttle + thr_d * 0.7 * delta, 0.0, 1.0)
	if guided:
		# the guide protects against the two classic mistakes: Max-Q and a too violent burnout
		var cap := 1.0
		if model.q > 0.8 * FlightModel.Q_LIMIT:
			cap = 0.55
		var h0 := model.altitude()
		var ta_full := model.max_thrust * (model.isp_vac / model.isp_sl if h0 > 50000.0 else 1.0) / maxf(model.mass(), 1.0)
		if ta_full > FlightModel.G_LIMIT * 0.95:
			cap = minf(cap, FlightModel.G_LIMIT * 0.95 / ta_full)
		model.throttle = minf(model.throttle, cap) if model.throttle > cap else model.throttle
	if Input.is_physical_key_pressed(KEY_Z):
		model.throttle = 1.0
	if Input.is_physical_key_pressed(KEY_X):
		model.throttle = 0.0
	var pitch_d := 0.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		pitch_d += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		pitch_d -= 1.0
	_guide_override_t = maxf(_guide_override_t - delta, 0.0)
	if pitch_d != 0.0:
		_guide_override_t = 2.5               # the player steers: the guide steps aside for a moment
	if guided and pitch_d == 0.0 and _guide_override_t <= 0.0:
		_pitch_vel = 0.0
		model.pitch = move_toward(model.pitch, _guide_pitch(), deg_to_rad(30.0) * delta)
	elif assist and pitch_d == 0.0 and model.speed() > 40.0:
		var target := model.prograde_pitch()
		model.pitch = move_toward(model.pitch, clampf(target, 0.0, PI), deg_to_rad(40.0) * delta)
	else:
		# smoothed pitch: the rate ramps up/down instead of snapping (more precise, less twitchy)
		var sens := float(GameState.settings["sens"])
		_pitch_vel = move_toward(_pitch_vel, pitch_d * deg_to_rad(26.0) * sens, deg_to_rad(110.0) * delta)
		model.pitch = clampf(model.pitch + _pitch_vel * delta, deg_to_rad(-15.0), deg_to_rad(185.0))


## Pitch (rad from vertical) the guide holds: vertical, gravity turn, level coast, circularising burn.
func _guide_pitch() -> float:
	var h := model.altitude()
	var o := model.orbit()
	var ap := minf(float(o["ap"]), 1.0e9)
	if bool(o["bound"]) and ap >= _ap_target() * 0.97:
		_guide_burn = true
	var deg := 0.0
	if _guide_burn:
		deg = 90.0 + clampf(model.vr * 0.25, -10.0, 40.0) if (model.throttle > 0.05 and model.vr < 60.0) else 90.0
	else:
		deg = 0.0 if h < 600.0 else 90.0 * minf(1.0, pow((h - 600.0) / 60000.0, 0.5))
	return deg_to_rad(deg)


var _guide_burn := false


## [translation key, step 1..7] of the guided-launch coach: only the NEXT thing to do, shown when it is relevant.
func _guide_step() -> Array:
	var h := model.altitude()
	var o := model.orbit()
	var ap := minf(float(o["ap"]), 1.0e9)
	var pe := float(o["pe"])
	if model.in_stable_orbit():
		return ["GUIDE_ORBIT", 7]
	if model.has_boosters and model.can_separate_boosters():
		return ["GUIDE_BOOST", 3]
	if model.has_upper and model.stage == 1 and model.can_separate_stage():
		return ["GUIDE_STAGE", 3]
	if model.fairing_on and model.can_jettison_fairing():
		return ["GUIDE_FAIRING", 3]
	if bool(o["bound"]) and ap >= _ap_target() * 0.97 and pe < FlightModel.SAFE_PE:
		if model.throttle > 0.05 and model.vr > 40.0:
			return ["GUIDE_CUT", 4]
		if model.vr > 60.0:
			return ["GUIDE_COAST", 5]
		return ["GUIDE_BURN", 6]
	if h < 600.0:
		return ["GUIDE_LIFTOFF", 1]
	if model.vr < -10.0 and h < 90000.0 and pe < FlightModel.SAFE_PE and ap < _ap_target() * 0.97:
		return ["GUIDE_FALL", 2]
	return ["GUIDE_TURN", 2]


func _simulate(delta: float) -> void:
	# ---- time warp limits (careful in dense air)
	var max_warp := 3 if model.altitude() < 30000.0 else 8
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
	for i in MILESTONES.size():
		if not _ms_done.has(i) and model.altitude() >= float(MILESTONES[i][0]):
			_ms_done.append(i)
			hud.big(tr(str(MILESTONES[i][1])), UIKit.C_ACCENT)
			Sfx.play("beep", -8.0)
	if _anom_at > 0.0 and model.time >= _anom_at:
		_anom_at = -1.0
		_anom_end = model.time + 9.0
		anomaly_seen = true
		model.thrust_scale = 0.55
		_override_hint = "M1_HINT_ANOMALY"
		_override_t = 6.0
		Sfx.play("hit", -6.0)
	if _anom_end > 0.0 and model.time >= _anom_end:
		_anom_end = -1.0
		model.thrust_scale = 1.0
	# ---- end conditions
	if model.integrity <= 0.0:
		_fail("M1_FAIL_DESTROYED", true)
		return
	if model.crashed and model.time > 2.0:
		_fail("M1_FAIL_CRASH", true)
		return
	if model.stage == 2 and model.engine_on and not _ign_fx:
		_ign_fx = true
		flight.ignite_stage2()
		hud.notify(tr("STG_TOAST_IGNITE"), UIKit.C_ACCENT)
		Sfx.play("ignite", -4.0)
	if model.has_upper and model.stage == 1 and model.fuel <= 0.0 and not model.in_stable_orbit():
		_stuck_t += delta
		if _stuck_t > 30.0:
			_fail("STG_FAIL_STUCK", false)
			return
	if model.fuel <= 0.0 and not model.in_stable_orbit() and not (model.has_upper and model.stage == 1) and not (model.has_boosters and model.b_fuel > 0.0):
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
	if event.keycode == KEY_F1:
		return          # F1 is handled by the camera hint itself
	if state == S.FLIGHT and not dev_autopilot and hud != null:
		if event.keycode == KEY_M:
			_set_auto(not auto_flight)
			return
		if auto_flight and event.keycode in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_Z, KEY_X]:
			_set_auto(false)       # the player touches a flight control: manual control, no questions asked
	if event.keycode == KEY_H and (state == S.FLIGHT or state == S.COUNTDOWN) and hud != null:
		guided = not guided
		GameState.set_setting("guided", guided)
		hud.set_guided(guided, _guide_pitch() if guided else NAN)
		return
	# C = free camera (inspect mode) while the rocket is flying; the simulation is frozen
	if event.keycode == KEY_C and (state == S.COUNTDOWN or state == S.FLIGHT or state == S.DEPLOY or state == S.DOWNLINK):
		pad_scene.orbit.toggle_sticky()
		return
	if state != S.FLIGHT:
		return
	match event.keycode:
		KEY_G:
			_do_separate()
		KEY_B:
			_do_boosters()
		KEY_F:
			_do_fairing()
		KEY_T:
			assist = not assist
		KEY_1:
			auto_warp = false
			warp = 1
		KEY_2:
			auto_warp = false
			warp = 2
		KEY_3:
			auto_warp = true      # 3 = automatic time compression
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
	elif model.has_boosters and model.b_fuel <= 0.0:
		hud.set_hint("STG_HINT_BOOST_EMPTY", UIKit.C_BAD)
	elif model.g_load > 0.9 * FlightModel.G_LIMIT:
		hud.set_hint("M1_HINT_GLOAD", UIKit.C_WARN)
	elif auto_flight:
		var gk: Array = _guide_step()
		var map := {"GUIDE_LIFTOFF": "AP_LIFTOFF", "GUIDE_TURN": "AP_TURN", "GUIDE_BOOST": "AP_SEP", "GUIDE_STAGE": "AP_SEP", "GUIDE_FAIRING": "AP_SEP",
			"GUIDE_CUT": "AP_CUT", "GUIDE_COAST": "AP_COAST", "GUIDE_BURN": "AP_BURN", "GUIDE_ORBIT": "AP_ORBIT", "GUIDE_FALL": "AP_TURN"}
		hud.set_hint(tr("AP_NOW") + " " + tr(str(map.get(str(gk[0]), "AP_TURN"))), UIKit.C_GOOD)
	elif guided:
		var g := _guide_step()
		hud.set_hint(tr("GUIDE_STEP") % int(g[1]) + " " + tr(str(g[0])), UIKit.C_ACCENT if int(g[1]) != 7 else UIKit.C_GOOD)
	elif model.has_upper and model.stage == 1 and model.fuel <= 0.0:
		hud.set_hint("STG_HINT_EMPTY", UIKit.C_BAD)
	elif model.has_upper and model.stage == 1 and model.fuel_fraction() < 0.1:
		hud.set_hint("STG_HINT_SEP", UIKit.C_ORANGE)
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
	var b_thr := 0.0
	if model.has_boosters and model.b_fuel > 0.0 and state != S.ENDED:
		b_thr = model.throttle if state != S.COUNTDOWN or _cd >= COUNTDOWN_LEN - 3.0 else 0.0
	flight.update_fx(thr, clampf(rho / 0.9, 0.0, 1.0), drift, b_thr)
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
## STAGE SEPARATION (G / panel button): drops the spent first stage. Consequences are real - see FlightModel.
func _do_separate() -> void:
	if state != S.FLIGHT or inspecting or not model.has_upper or model.stage != 1:
		return
	if not model.can_separate_stage():
		_explain(model.why_not_stage())
		return
	var r := model.separate_stage()
	if not bool(r.get("ok", false)):
		return
	flight.separate_stage()
	Sfx.play("clang", -2.0)
	Sfx.play("whoosh", -6.0)
	hud.notify(tr("STG_TOAST_SEP"), UIKit.C_ORANGE)
	_override_hint = "STG_NOW_COAST"
	_override_t = 3.0
	if float(r["shock"]) > 1.0:
		_override_hint = "STG_SEP_SHOCK"
		_override_t = 5.0
	_ign_fx = false


## Autopilot <-> manual. Handing control back re-synchronises the autopilot with where the flight is now.
func _set_auto(on: bool) -> void:
	if on == auto_flight:
		return
	auto_flight = on
	hud.set_autopilot(on)
	if on:
		var o := model.orbit()
		var ap := minf(float(o["ap"]), 1.0e9)
		_ap_phase = 0 if ap < _ap_target() else (2 if model.vr < 15.0 else 1)
		hud.notify(tr("AP_TOAST_ON"), UIKit.C_GOOD)
	else:
		_pitch_vel = 0.0
		_guide_override_t = 0.0
		hud.notify(tr("AP_TOAST_OFF"), UIKit.C_ORANGE)


## Short toast that says WHY an action is not available yet.
func _explain(why: Array) -> void:
	if str(why[0]) == "":
		return
	Sfx.play("beep", -14.0)
	hud.notify(tr(str(why[0])) % int(why[1]), UIKit.C_WARN)


## BOOSTER SEPARATION (B / panel button): drops the strap-on boosters. Dropping them while they still burn wastes propellant,
## carrying them empty is dead weight, separating near Max-Q shocks the vehicle.
func _do_boosters() -> void:
	if state != S.FLIGHT or inspecting or not model.has_boosters:
		return
	if not model.can_separate_boosters():
		_explain(model.why_not_boosters())
		return
	var r := model.separate_boosters()
	if not bool(r.get("ok", false)):
		return
	flight.separate_boosters()
	Sfx.play("clang", -2.0)
	Sfx.play("whoosh", -6.0)
	hud.notify(tr("STG_TOAST_BOOST"), UIKit.C_ORANGE)
	if float(r["shock"]) > 1.0:
		_override_hint = "STG_SEP_SHOCK"
		_override_t = 5.0


## FAIRING SEPARATION (F / panel button): sheds the nose fairing mass; in dense air the exposed payload is damaged.
func _do_fairing() -> void:
	if state != S.FLIGHT or inspecting or not model.fairing_on:
		return
	if not model.can_jettison_fairing():
		_explain(model.why_not_fairing())
		return
	var r := model.jettison_fairing()
	if not bool(r.get("ok", false)):
		return
	flight.jettison_fairing()
	Sfx.play("clang", -6.0)
	if float(r["damage"]) > 0.0:
		_override_hint = "STG_FAIRING_EARLY"
		_override_t = 5.0
		Sfx.play("hit", -8.0)
	else:
		hud.notify(tr("STG_TOAST_FAIRING"), UIKit.C_ACCENT)


func _try_deploy() -> void:
	if state != S.FLIGHT:
		return
	if not model.in_stable_orbit():
		_override_hint = "M1_DEPLOY_DENIED"
		_override_t = 3.0
		return
	if model.fairing_on:
		fairing_late = true             # still wearing the fairing: its dead mass was carried all the way
		model.jettison_fairing()
	state = S.DEPLOY
	model.throttle = 0.0
	Sfx.loop_stop("rumble")
	Sfx.loop_stop("alarm")
	Sfx.play("whoosh", -4.0)
	hud.set_hint("M1_HINT_DEPLOYING", UIKit.C_ACCENT)
	await flight.deploy_satellite(5.0, design if profile.is_empty() else {})
	if ended:
		return
	if not profile.is_empty():
		_handoff()
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
	if stage_panel != null:
		stage_panel.visible = false
	var fuel_left := model.fuel_fraction()
	var o := model.orbit()
	var ev := M1Design.evaluate(design, stats, {"orbit_ok": true, "ap": float(o["ap"]), "pe": float(o["pe"]), "integrity": model.integrity})
	var sr: Dictionary = ev["sr"]
	var science := float(ev["science"])
	var stars := int(ev["stars"])
	var success := stars > 0
	var stage_pen := int(maxf(model.sep_waste, 0.0) * 400.0) + int(minf(model.dead_mass_time, 20.0) * 5.0) \
		+ (120 if fairing_late else 0) + (150 if model.fairing_early else 0)
	var score := stars * 1000 + int(science * 1500.0) + int(fuel_left * 300.0) + int(model.integrity * 2.0) - stage_pen \
		+ maxi(M1Parts.BUDGET - int(stats["cost"]), 0) * 4
	hud.set_hint("M1_HINT_SUCCESS" if success else "", UIKit.C_GOOD)
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
		["R_STAGING", _staging_text()],
		["R_RELIABILITY", "%d%%%s" % [int(float(stats["rel"]) * 100.0), " (!)" if anomaly_seen else ""]],
		["R_INTEGRITY", "%d%%" % int(model.integrity)],
		["R_COST", "%s / %s" % [Units.money(int(stats["cost"])), Units.money(M1Parts.BUDGET)]],
		["R_SCORE", str(score)],
	]
	# four-segment evaluation
	var launch_r := clampf(model.integrity / 100.0 * 0.6 + (0.4 if model.max_q_seen < 0.9 * FlightModel.Q_LIMIT else 0.2), 0.0, 1.0)
	launch_r *= 1.0 - clampf(maxf(model.sep_waste, 0.0) * 0.5, 0.0, 0.3)
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
		"hull":
			tips.append("TIP_HULL")
	if fuel_left > 0.4:
		tips.append("TIP_FUEL")
	if model.max_q_seen > 0.9 * FlightModel.Q_LIMIT:
		tips.append("TIP_MAXQ")
	if model.has_upper and model.sep_waste > 0.12:
		tips.append("TIP_SEP_EARLY")
	if model.dead_mass_time > 8.0:
		tips.append("TIP_SEP_LATE")
	if model.fairing_early:
		tips.append("TIP_FAIRING_EARLY")
	if fairing_late:
		tips.append("TIP_FAIRING_LATE")
	if not model.has_upper and model.fuel_fraction() < 0.1:
		tips.append("TIP_TRY_UPPER")
	if anomaly_seen:
		tips.append("TIP_REL")
	if success and stars < 3:
		# what separates this result from a full success (the targets are shown, the way to reach them is not)
		if science < M1Design.SCI_FULL:
			tips.append("TIP_3_SCI")
		if model.integrity < 80.0:
			tips.append("TIP_3_HULL")
		if float(stats["rel"]) < M1Design.REL_FULL:
			tips.append("TIP_3_REL")
		if float(stats["cost"]) > M1Design.EFF_COST * float(M1Parts.BUDGET):
			tips.append("TIP_3_COST")
	if tips.is_empty():
		tips.append("TIP_GOOD")
	var extra := {"segments": segments, "science": science, "tips": tips}
	var prox := _proximity_extra(true, success, stars, score)
	if not prox.is_empty():
		extra["proximity"] = prox
	if success:
		extra["user"] = "USER_%s_%d" % [goal_id.to_upper(), M1Design.science_tier(science)]
		extra["science_note"] = "M1_STAR_RULES"
	Sfx.stop_all_loops()
	if success:
		finish(true, stars, score, res, "M1_WIN_REASON", 1.0, extra)
	else:
		finish(false, 0, 0, res, "M1_FAIL_SCI_" + str(ev["cause"]).to_upper(), 1.2, extra)


## Builds the "proximity" block for the result screen from the REAL flight state and stores the personal best.
func _proximity_extra(orbit_ok: bool, success: bool, stars: int, score: int) -> Dictionary:
	if design.is_empty() or stats.is_empty() or not profile.is_empty():
		return {}
	var o := model.orbit()
	var flight := {"orbit_ok": orbit_ok, "ap": minf(float(o["ap"]), 1.0e9), "pe": float(o["pe"]), "integrity": model.integrity,
		"max_alt": _max_alt}
	var prox := M1Design.proximity(design, stats, flight)
	var prev_best := GameState.get_best_prox(mission_id)
	var prev_score := GameState.get_best_score(mission_id)
	var prev_stars := GameState.get_stars(mission_id)
	GameState.record_proximity(mission_id, int(prox["percent"]))
	prox["best"] = maxi(prev_best, int(prox["percent"]))
	prox["new_best"] = int(prox["percent"]) > prev_best and int(prox["percent"]) > 0
	prox["best_stars"] = maxi(prev_stars, stars)
	prox["best_score"] = maxi(prev_score, score)
	last_prox = prox
	return prox


## Launch segment done (Missions 2-5): remember how the launch went and continue with the operations phase.
func _handoff() -> void:
	if _handoff_started:
		return
	_handoff_started = true
	state = S.ENDED
	if stage_panel != null:
		stage_panel.visible = false
	var o := model.orbit()
	var mean_km := (float(o["ap"]) + float(o["pe"])) * 0.5 / 1000.0
	var m_now := model.mass()
	var dv_left := 0.0
	if model.fuel > 0.0 and model.isp_vac > 0.0 and m_now > model.fuel:
		dv_left = model.isp_vac * FlightModel.G0 * log(m_now / (m_now - model.fuel))
	var best: Array = profile["best"]
	var ok: Array = profile["ok"]
	var launch := {
		"hull": model.integrity, "fuel_frac": model.fuel_fraction(), "dv_left": dv_left, "mass_left": m_now,
		"ap": float(o["ap"]), "pe": float(o["pe"]), "mean_km": mean_km, "orbit_q": M1Design.window_score(mean_km, best, ok),
		"rel": float(stats["rel"]), "cost": int(stats["cost"]), "budget": int(profile["budget"]),
		"waste": maxf(model.sep_waste, 0.0), "booster_waste": maxf(model.b_waste, 0.0),
		"fairing_early": model.fairing_early, "fairing_late": fairing_late, "anomaly": anomaly_seen,
		"dead_time": model.dead_mass_time + model.b_dead_time, "max_q": model.max_q_seen / FlightModel.Q_LIMIT,
		"time": model.time,
	}
	GameState.session = {"profile": profile_id, "design": design, "launch": launch, "payload": sat, "stats": stats}
	hud.set_hint("PRF_HINT_HANDOFF", UIKit.C_GOOD)
	hud.notify(tr("PRF_TOAST_ORBIT"), UIKit.C_GOOD)
	Sfx.stop_all_loops()
	await get_tree().create_timer(2.2).timeout
	Router.go_to(str(profile["next"]))


func _staging_text() -> String:
	var parts: Array[String] = []
	if model.b_waste >= 0.0:
		parts.append(tr("R_BST_WASTE") % int(model.b_waste * 100.0))
	if model.has_upper:
		parts.append(tr("R_STG_WASTE") % int(maxf(model.sep_waste, 0.0) * 100.0))
	if model.fairing_early:
		parts.append(tr("R_STG_FAIR_EARLY"))
	elif fairing_late:
		parts.append(tr("R_STG_FAIR_LATE"))
	elif model.fairing_time >= 0.0:
		parts.append(tr("R_STG_FAIR_OK"))
	return ", ".join(parts) if not parts.is_empty() else "-"


func _fail(reason_key: String, boom: bool) -> void:
	if state == S.ENDED:
		return
	state = S.ENDED
	if stage_panel != null:
		stage_panel.visible = false
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
	var fail_extra := {}
	var fprox := _proximity_extra(false, false, 0, 0)
	if not fprox.is_empty():
		fail_extra["proximity"] = fprox
	finish(false, 0, 0, res, reason_key, 1.8, fail_extra)
