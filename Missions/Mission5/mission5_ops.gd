extends "res://Missions/Mission5/moon_mission.gd"
## Mission 5 - Moon & Return, phase 2. The story of the crew:
##   1. trans-lunar burn (planner)            -> 2. lunar orbit insertion with the command ship (burn gauge)
##   3. lander separates and lands (descent)  -> 4. astronauts leave the module, explore, collect samples, come back
##   5. ascent from the Moon and docking with the command ship (rendezvous)
##   6. crew + samples move to the ship, lander is jettisoned -> trans-Earth burn
##   7. service module separation, re-entry, parachutes, splashdown.
## Every stage has an AUTOPILOT (default, flight mode "Automatic") - any control key takes over, M switches it back.
## Chosen parts matter: the ascent stage (delta-v for the Moon ascent, rendezvous RCS and the trans-Earth burn) and the
## capsule heat shield (re-entry heat / g limits), the tank + engine (descent), instrument + site (science).

const ASCENT_NEED := 1700.0         # m/s to reach lunar orbit from the surface (simplified)
const TEI_IDEAL := 1000.0           # m/s trans-Earth injection (simplified)
const TEI_BAND := 80.0              # corridor half-width (m/s)
const TEI_BASE := 850.0             # service-module propellant, m/s
const LOI_BAND := 70.0              # lunar orbit insertion window (m/s)
const BURN_RATE := 260.0            # m/s per second while the engine fires
const ENTRY_CENTER := -6.0          # deg flight-path angle at entry interface
const ENTRY_SHALLOW := -4.8         # shallower than this the capsule skips out of the atmosphere
const ENTRY_G_LIMIT := 9.5
const ENTRY_HEAT_LIMIT := 100.0
const CHUTE_START := 6000.0         # m, capsule altitude when the parachute phase begins
const DROGUE_ALT := 4800.0          # the drogue may be deployed below this altitude
const MAIN_HIGH := 2200.0           # the main chute window (m): deploy between these altitudes
const MAIN_LOW := 800.0
const MAIN_IDEAL := 1500.0

var launch: Dictionary = {}
var lunar: Dictionary = {}
var ret: Dictionary = {}
var auto_flight := true
var os: OrbitStage3D
var dock_world: DockingWorld

var _ret_started := false
var _rs := ""                       # current return-flow stage
var _rs_t := 0.0
var _eva := ""                      # "out" / "in" cut-scenes on the surface
var _eva_t := 0.0
var _homing := false
var _astro: Array[Node3D] = []
var _desc_stage: Node3D
var _seat: Node3D
var _ap_lbl: Label
var _burn_dv := 0.0
var _burn_target := 0.0
var _burn_band := 0.0
var _burn_max := 0.0
var _burn_t := 0.0
var _entry_angle := -4.0
var _alt := 0.0
var _speed := 0.0
var _chute := 0                    # 0 none, 1 drogue, 2 main
var _chute_t := 0.0
var _main_alt := 0.0
var _drogue_alt := 0.0
var _sm := Vector3.ZERO
var _msg_t := 0.0


func _init() -> void:
	super._init()
	mission_id = "m5_moon"
	launch = GameState.session.get("launch", {})
	var d: Dictionary = GameState.session.get("design", LaunchProfiles.default_design("m5"))
	design = LaunchProfiles._as_lunar(d)
	design["capsule"] = d.get("capsule", "light")
	design["ascent"] = d.get("ascent", "s")
	if launch.is_empty():
		launch = {"hull": 100.0, "orbit_q": 1.0, "dv_left": 3300.0, "cost": 300, "budget": 560, "waste": 0.0, "booster_waste": 0.0, "fairing_early": false}


func _briefing_data() -> Dictionary:
	return {
		"title": "M5_TITLE",
		"objectives": ["M5_OPS_1", "M5_OPS_2", "M5_OPS_3", "M5_OPS_4", "M5_OPS_5", "M5_OPS_6"],
		"controls": [["MOUSE", "M1_CTRL_DRAG"], ["M", "M5S_CTRL_AUTO"], ["SPACE", "M5S_CTRL_SPACE"], ["W A S D", "LUN_CTRL_ROVER"],
			["Q E", "M5S_CTRL_DOCK"], ["< >", "M5S_CTRL_ANGLE"], ["C", "CAM_INSPECT_SHORT"], ["ESC", "M1_CTRL_PAUSE"]],
	}


func _build_mission() -> void:
	super._build_mission()
	_ap_lbl = UIKit.label("", 15, UIKit.C_GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	_ap_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_ap_lbl.offset_left = -200
	_ap_lbl.offset_right = 200
	_ap_lbl.offset_top = 6
	_ap_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(_ap_lbl)


func music_mood() -> String:
	return "action" if (state >= S.LAUNCH and state <= S.UPLINK and not ended) else "calm"


func _on_mission_start() -> void:
	st = LunarDesign.stats(design)
	state = S.LAUNCH
	auto_flight = bool(GameState.settings["autoflight"])
	_refresh_ap_label()
	_begin_transfer()
	# the propellant the launch left in the trans-lunar stage limits the burn
	var avail := float(launch["dv_left"])
	_tli_slider.max_value = clampf(avail, TLI_MIN + 1.0, TLI_MAX)
	_tli_slider.min_value = minf(TLI_MIN, _tli_slider.max_value - 1.0)
	_tli_slider.value = clampf(tli_dv, _tli_slider.min_value, _tli_slider.max_value)
	_tli_slider.drag_started.connect(func(): _set_auto(false))     # touching the slider = the player plans the burn
	_set_hint(tr("MOON_TLI_AVAIL") % [int(avail), int(LunarDesign.ideal_tli_dv())], UIKit.C_ACCENT if avail >= LunarDesign.ideal_tli_dv() - 40.0 else UIKit.C_BAD)
	_rs_t = 0.0


func _fail_transfer() -> void:
	if float(launch["dv_left"]) < LunarDesign.ideal_tli_dv() - 70.0:
		state = S.ENDED
		Sfx.play("fail", -6.0)
		var res: Array = [["R_TLI", Units.ms(exec_dv)], ["R_TLI_AVAIL", Units.ms(float(launch["dv_left"]))], ["R_LAUNCH_HULL", "%d%%" % int(launch["hull"])]]
		finish(false, 0, 0, res, "MOON_FAIL_TLI_FUEL", 1.2, {"tips": ["MOON_TIP_TLI_FUEL"]})
		return
	super._fail_transfer()


# ------------------------------------------------------------ autopilot / input --
func _is_auto() -> bool:
	return dev_autopilot or auto_flight


func _set_auto(on: bool) -> void:
	if on == auto_flight or dev_autopilot:
		return
	auto_flight = on
	_refresh_ap_label()
	if on:
		_set_hint(tr("AP_TOAST_ON"), UIKit.C_GOOD)
	else:
		_set_hint(tr("AP_TOAST_OFF"), UIKit.C_ORANGE)


func _refresh_ap_label() -> void:
	if _ap_lbl != null:
		_ap_lbl.text = "HUD_AUTO_ON" if auto_flight else "HUD_AUTO_OFF"
		_ap_lbl.add_theme_color_override("font_color", UIKit.C_GOOD if auto_flight else UIKit.C_ORANGE)


func _takeover_keys() -> Array:
	match _rs:
		"loi", "tei":
			return [KEY_SPACE]
		"dock":
			return [KEY_W, KEY_S, KEY_A, KEY_D, KEY_Q, KEY_E, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
		"entry_set":
			return [KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT]
		"chute":
			return [KEY_SPACE]
	if state == S.DESCENT:
		return [KEY_W, KEY_S, KEY_A, KEY_D, KEY_Z, KEY_X, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
	if state == S.SURFACE:
		return [KEY_W, KEY_S, KEY_A, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_E]
	return []


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and not ended:
		var key := (event as InputEventKey).keycode
		if key == KEY_M:
			_set_auto(not auto_flight)
			return
		if auto_flight and not dev_autopilot and key in _takeover_keys():
			_set_auto(false)
		if _rs == "chute" and key == KEY_SPACE:
			_deploy_chute()
			return
		if _rs == "entry_set" and (key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE):
			_commit_entry()
			return
	super._unhandled_input(event)


func _cur_orbit() -> OrbitCameraController:
	if os != null:
		return os.orbit
	return super._cur_orbit()


# ------------------------------------------------------------------- main loop --
func _process(delta: float) -> void:
	if ended:
		return
	# automatic trans-lunar burn (the plan is shown first; touch the slider to plan it yourself)
	if state == S.TRANSFER and not _coasting and auto_flight and not dev_autopilot and _exec_btn != null and not _exec_btn.disabled:
		_rs_t += delta
		if _rs_t > 2.2:
			_tli_slider.set_value_no_signal(clampf(LunarDesign.ideal_tli_dv(), _tli_slider.min_value, _tli_slider.max_value))
			tli_dv = _tli_slider.value
			planner.set_dv(tli_dv)
			_refresh_tli()
			_execute_burn()
	if _eva != "":
		_update_eva(delta)
	if _rs != "":
		if inspecting:
			if os != null:
				os.orbit.update(delta, os.camera.global_position, os.orbit.focus)
			return
		_update_stage(delta)
		return
	super._process(delta)


# ---------------------------------------------------- 2. lunar orbit insertion ---
func _begin_descent() -> void:
	# the heavy launch + trans-lunar burn are done: capture into lunar orbit before the lander separates
	Sfx.stop_all_loops()
	state = S.UPLINK
	if _tli_panel != null:
		_tli_panel.queue_free()
		_tli_panel = null
	if planner != null:
		planner.visible = false           # the trans-lunar planner (its labels and trajectory) is hidden behind the new scene
	os = OrbitStage3D.new()
	add_child(os)
	os.orbit.engaged_changed.connect(_on_orbit_engaged)
	_start_burn("loi", LunarDesign.LOI_DV, LOI_BAND, 1300.0)
	os.set_moon_altitude(900_000.0)


func _start_burn(id: String, target: float, band: float, fuel_max: float) -> void:
	_rs = id
	_rs_t = 0.0
	_burn_dv = 0.0
	_burn_target = target
	_burn_band = band
	_burn_max = fuel_max
	_burn_t = 0.0
	_hud_table([["M5S_H_BURN_DV", "dv"], ["M5S_H_BURN_TGT", "tgt"], ["M5S_H_BURN_FUEL", "fuel"]], [["M5S_H_BURN_PROG", "prog", UIKit.C_ACCENT]])
	(_vals["tgt"] as Label).text = "%d ± %d %s" % [int(target), int(band), tr("UNIT_MS")]
	_set_hint(tr("M5S_HINT_LOI") if id == "loi" else tr("M5S_HINT_TEI"), UIKit.C_ACCENT)


## Shared hold-SPACE burn: the autopilot burns exactly to the target, the player holds SPACE (release inside the window).
func _update_burn(delta: float) -> bool:
	_burn_t += delta
	var want := false
	if _is_auto():
		want = _burn_t > 1.6 and _burn_dv < _burn_target
	else:
		want = Input.is_physical_key_pressed(KEY_SPACE) and _burn_t > 0.4
	var firing := want and _burn_dv < _burn_max
	if firing:
		_burn_dv = minf(_burn_dv + BURN_RATE * delta, _burn_max)
	os.set_flame(os.csm_flame, 1.0 if firing else 0.0, 12.0)
	if firing:
		Sfx.loop("rumble", -12.0)
	else:
		Sfx.loop_stop("rumble")
	var err := absf(_burn_dv - _burn_target)
	var in_win := err <= _burn_band
	(_vals["dv"] as Label).text = "%d %s" % [int(_burn_dv), tr("UNIT_MS")]
	(_vals["dv"] as Label).add_theme_color_override("font_color", UIKit.C_GOOD if in_win else (UIKit.C_BAD if _burn_dv > _burn_target else Color.WHITE))
	(_vals["fuel"] as Label).text = "%d %s" % [int(maxf(_burn_max - _burn_dv, 0.0)), tr("UNIT_MS")]
	(_bars["prog"] as ProgressBar).value = clampf(_burn_dv / (_burn_target + _burn_band) * 100.0, 0.0, 100.0)
	UIKit.set_bar_color(_bars["prog"], UIKit.C_GOOD if in_win else UIKit.C_ACCENT)
	return firing


# --------------------------------------------------------------- stage machine ---
func _update_stage(delta: float) -> void:
	_rs_t += delta
	match _rs:
		"loi":
			_stage_loi(delta)
		"undock":
			_stage_undock(delta)
		"ascent":
			_stage_ascent(delta)
		"dock":
			_stage_dock(delta)
		"transfer":
			_stage_transfer(delta)
		"jettison":
			_stage_jettison(delta)
		"tei":
			_stage_tei(delta)
		"coast":
			_stage_coast(delta)
		"entry_set":
			_stage_entry_set(delta)
		"sep":
			_stage_sep(delta)
		"entry":
			_stage_entry(delta)
		"chute":
			_stage_chute(delta)
		"splash":
			_stage_splash(delta)


func _orbit_cam(delta: float, dist: float, az_deg: float, el_deg: float, look: Vector3, fov: float = 42.0) -> void:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	os.cam(delta, look + Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * dist, look, fov)


func _stage_loi(delta: float) -> void:
	# the Moon grows while the burn slows the ship down; the camera circles the ship
	var k := clampf(_burn_dv / maxf(_burn_target, 1.0), 0.0, 1.0)
	os.set_moon_altitude(lerpf(900_000.0, 110_000.0, smoothstep(0.0, 1.0, k)))
	os.moon_body.rotation.y += delta * 0.01
	_orbit_cam(delta, 34.0, 25.0 + _rs_t * 4.0, 12.0, Vector3(5.0, 0.0, 0.0))
	var firing := _update_burn(delta)
	if _burn_dv > _burn_target + _burn_band:
		_end_stage_fail("MOON_FAIL_LOI", ["MOON_TIP_LOI"])
		return
	var in_win := absf(_burn_dv - _burn_target) <= _burn_band
	if in_win and not firing and _burn_dv > 0.0 and (_is_auto() or _burn_t > 2.0):
		ret["loi_q"] = clampf(1.0 - absf(_burn_dv - _burn_target) / (_burn_band * 2.0), 0.4, 1.0)
		os.set_flame(os.csm_flame, 0.0)
		Sfx.loop_stop("rumble")
		_set_hint(tr("M5S_LOI_OK"), UIKit.C_GOOD)
		_rs = "undock"
		_rs_t = 0.0
		_clear_hud_panel()


func _stage_undock(delta: float) -> void:
	# the lander separates from the ship and drifts away, then the powered descent starts
	var k := clampf(_rs_t / 4.0, 0.0, 1.0)
	os.lander.position = Vector3(-4.6 - 26.0 * k * k, -1.2 * k, 3.0 * k)
	os.lander.rotation.y = 0.5 * k
	os.set_moon_altitude(110_000.0 - 20_000.0 * k)
	_orbit_cam(delta, 30.0 + 14.0 * k, 70.0, 10.0, Vector3(-6.0 - 12.0 * k, 0.0, 0.0))
	if _rs_t > 0.2 and _msg_t == 0.0:
		_msg_t = 1.0
		_set_hint(tr("M5S_UNDOCK"), UIKit.C_ACCENT)
		Sfx.play("clang", -6.0)
	if _rs_t >= 4.2:
		_msg_t = 0.0
		_rs = ""
		# take the old scenes OUT of the tree right now: only one WorldEnvironment may be active, the Moon scene needs its own
		remove_child(os)
		os.queue_free()
		os = null
		if planner != null:
			remove_child(planner)
		start_fuel *= lerpf(0.94, 1.0, float(ret.get("loi_q", 1.0)))      # a clean orbit insertion saves descent propellant
		super._begin_descent()
		_set_hint(tr("M5S_DESCENT"), UIKit.C_ACCENT)


# --------------------------------------------------------- 4. EVA on the surface ---
func _on_landed() -> void:
	super._on_landed()
	_eva = "out"
	_eva_t = 0.0
	_astro.clear()
	_desc_stage = null
	for i in 2:
		var a := (load("res://Assets/Models/astronaut.glb") as PackedScene).instantiate() as Node3D
		moon.add_child(a)
		OrbitStage3D.fit_height(a, 1.8)
		a.position = lander_view.position + Vector3(1.6, 1.4, 1.9)
		_astro.append(a)
	_set_hint(tr("M5S_EVA_OUT"), UIKit.C_ACCENT)
	if hud_layer != null:
		Sfx.play("beep", -4.0)


func _ground_at(p: Vector2) -> Vector3:
	return Vector3(p.x, moon.ground_y(p.x, p.y), p.y)


func _update_eva(delta: float) -> void:
	_eva_t += delta
	var lander_xz := Vector2(lander_view.position.x, 0.0)
	if _eva == "out":
		var k := clampf(_eva_t / 4.2, 0.0, 1.0)
		var hatch := lander_view.position + Vector3(1.6, 1.4, 1.9)
		for i in _astro.size():
			var kk := clampf(k * 1.4 - 0.25 * i, 0.0, 1.0)
			var target_xz := (r_pos if i == 0 else lander_xz + Vector2(6.0, 5.0))
			var tp := _ground_at(target_xz)
			_astro[i].position = hatch.lerp(tp, smoothstep(0.0, 1.0, kk)) + Vector3(0, absf(sin(kk * 9.0)) * 0.12, 0)
			_astro[i].look_at(_astro[i].position + (tp - hatch).normalized() * Vector3(1, 0, 1) + Vector3(0.001, 0, 0.001), Vector3.UP)
		var p := lander_view.position
		moon.orbit.update(delta, p + Vector3(9.0, 3.5, 14.0), p + Vector3(4.0, 1.5, 1.0), 48.0)
		if k >= 1.0:
			# the first astronaut takes the rover, the second stays at the module and plants the flag
			var seat := _astro[0]
			seat.get_parent().remove_child(seat)
			rover.add_child(seat)
			seat.position = Vector3(0.05, 0.98, 0)       # the astronaut stands on the rover deck (the model origin is at its torso)
			seat.rotation = Vector3.ZERO
			seat.scale = seat.scale / 1.6          # the rover node is scaled 1.6
			_seat = seat
			_astro.remove_at(0)
			_eva = ""
			_set_hint("LUN_SURF_HINT", UIKit.C_TEXT)
	elif _eva == "in":
		var k2 := clampf(_eva_t / 3.4, 0.0, 1.0)
		var hatch2 := lander_view.position + Vector3(1.6, 1.4, 1.9)
		for a in _astro:
			a.position = a.position.lerp(hatch2, clampf(delta * 1.6, 0.0, 1.0))
		var p2 := lander_view.position
		moon.orbit.update(delta, p2 + Vector3(9.0, 3.5, 14.0), p2 + Vector3(4.0, 1.5, 1.0), 48.0)
		if k2 >= 1.0:
			for a in _astro:
				a.visible = false
			_eva = ""
			_homing = false
			super._start_uplink()


func _update_surface(delta: float) -> void:
	if _eva != "":
		return
	if _homing and _battery_dead:
		# no power left: the astronauts walk back on foot
		r_pos = r_pos.move_toward(Vector2(lander_view.position.x + 6.0, 0.0), 2.2 * delta)
		_place_rover()
		_check_home()
		return
	super._update_surface(delta)
	if _homing:
		_check_home()


func _check_home() -> void:
	if not _homing or _eva != "":
		return
	var home := Vector2(lander_view.position.x + 6.0, 0.0)
	if r_pos.distance_to(home) < 7.0 and absf(r_speed) < 1.2:
		_eva = "in"
		_eva_t = 0.0
		# the astronaut on the rover walks to the module together with the one at the flag
		if _seat != null and is_instance_valid(_seat):
			var gp := _seat.global_position
			rover.remove_child(_seat)
			moon.add_child(_seat)
			_seat.global_position = gp
			_seat.scale = _seat.scale * 1.6
			_astro.append(_seat)
			_seat = null
		_set_hint(tr("M5S_EVA_IN"), UIKit.C_ACCENT)
		r_speed = 0.0


func _start_uplink() -> void:
	# all samples collected (or time / power over): first drive back to the module
	if state != S.SURFACE:
		return
	if not _homing and _eva == "":
		_homing = true
		_set_hint(tr("M5S_HOMING"), UIKit.C_ORANGE)
		return


func _rover_autopilot(auto_sample: bool = true) -> Vector2:
	if _homing:
		var home := Vector2(lander_view.position.x + 6.0, 0.0)
		var to := home - r_pos
		var diff := wrapf(atan2(to.y, to.x) - r_head, -PI, PI)
		var drive := 1.0 if to.length() > 9.0 else (0.45 if to.length() > 5.0 else 0.0)
		if absf(diff) > 0.6:
			drive *= 0.3
		return Vector2(drive, clampf(diff * 2.0, -1.0, 1.0))
	return super._rover_autopilot(auto_sample)


# ------------------------------------------------- 5. ascent + docking with the ship ---
func _finish_mission() -> void:
	if r_samples == 0 or _ret_started:
		super._finish_mission()
		return
	_ret_started = true
	state = S.UPLINK
	_clear_hud_panel()
	_set_hint(tr("M5S_ASC_START"), UIKit.C_ACCENT)
	_begin_ascent()


func _asc_dv() -> float:
	return float(LaunchProfiles.MOON_ASCENT[design["ascent"]]["dv"])


func _begin_ascent() -> void:
	_rs = "ascent"
	_rs_t = 0.0
	# the descent stage stays behind: a copy of the lander body remains on the ground
	var base := (load("res://Assets/Models/lander.glb") as PackedScene).instantiate() as Node3D
	moon.add_child(base)
	base.global_transform = lander_view.model_node.global_transform
	_desc_stage = base
	moon.orbit.user_can_engage = false
	Sfx.play("ignite", -4.0)


func _stage_ascent(delta: float) -> void:
	var y0 := _desc_stage.position.y
	var k := clampf(_rs_t / 5.2, 0.0, 1.0)
	var rise := k * k * 700.0
	lander_view.position = Vector3(_desc_stage.position.x, y0 + rise, _desc_stage.position.z)
	lander_view.rotation.z = -0.35 * smoothstep(0.3, 1.0, k)
	lander_view.update_view(1.0 if k < 1.0 else 0.0, rise, y0)
	Sfx.loop("rumble", -14.0)
	var p := lander_view.position
	moon.orbit.update(delta, p + Vector3(14.0 + rise * 0.04, -4.0 + rise * 0.02, 26.0 + rise * 0.08), p, 46.0)
	if _rs_t >= 5.4:
		Sfx.loop_stop("rumble")
		if _asc_dv() < ASCENT_NEED:
			_end_stage_fail("MOON_FAIL_ASCENT", ["MOON_TIP_ASCENT"])
			return
		_begin_dock()


func _begin_dock() -> void:
	remove_child(moon)
	moon.queue_free()
	moon = null
	lander_view = null
	_astro.clear()
	os = OrbitStage3D.new()
	add_child(os)
	os.orbit.engaged_changed.connect(_on_orbit_engaged)
	dock_world = DockingWorld.new()
	dock_world.draw_2d = false
	world_layer.add_child(dock_world)
	dock_world.visible = false
	dock_world.warp = 8                       # time compression for the long approach (drops to x1 inside 100 m)
	dock_world.pos = Vector2(-200.0, 16.0)
	dock_world.vel = Vector2(3.0, -0.09)
	dock_world.angle = 0.3
	# a bigger ascent stage carries more RCS propellant for the rendezvous
	dock_world.fuel = DockingWorld.FUEL_MAX * clampf(0.45 + (_asc_dv() - ASCENT_NEED) / 600.0 * 0.55, 0.45, 1.0)
	dock_world.docked.connect(_on_docked)
	dock_world.docking_failed.connect(_on_dock_failed)
	os.set_moon_altitude(110_000.0)
	os.port_ring.visible = true
	_sm = Vector3.ZERO
	_rs = "dock"
	_rs_t = 0.0
	_hud_table([["M5S_H_RANGE", "range"], ["M5S_H_SPEED", "speed"], ["M5S_H_OFFSET", "lat"], ["M5S_H_ANGLE", "ang"]], [["M5S_H_RCS", "fuel", UIKit.C_ORANGE]])
	_set_hint(tr("M5S_HINT_DOCK"), UIKit.C_ACCENT)


func _dock_autopilot() -> Array:
	var w := dock_world
	var rot := clampf(-(w.angle_error() * 3.0 + w.omega * 4.0), -1.0, 1.0)
	if absf(rot) < 0.05:
		rot = 0.0
	var tip := w.nose_tip()
	var ax := w.axial_distance()
	var vx_t := clampf(ax * 0.16, 0.4, 5.0) if ax > 2.5 else 0.38
	var vy_t := clampf(-tip.y * 0.12, -0.6, 0.6)
	var fwd := clampf((vx_t - w.vel.x) * 4.0, -1.0, 1.0)
	var strafe := clampf((vy_t - w.vel.y) * 5.0, -1.0, 1.0)
	if absf(fwd) < 0.06:
		fwd = 0.0
	if absf(strafe) < 0.06:
		strafe = 0.0
	return [fwd, strafe, rot]


func _stage_dock(delta: float) -> void:
	var w := dock_world
	if not w.finished:
		var fwd := 0.0
		var strafe := 0.0
		var rot := 0.0
		var fine := false
		var kill := false
		if _is_auto():
			var a := _dock_autopilot()
			fwd = a[0]
			strafe = a[1]
			rot = a[2]
			fine = w.axial_distance() < 9.0
		else:
			if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
				fwd += 1.0
			if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
				fwd -= 1.0
			if Input.is_physical_key_pressed(KEY_E):
				strafe += 1.0
			if Input.is_physical_key_pressed(KEY_Q):
				strafe -= 1.0
			if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
				rot += 1.0
			if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
				rot -= 1.0
			fine = Input.is_physical_key_pressed(KEY_SHIFT)
			kill = Input.is_physical_key_pressed(KEY_X)
			var k := 7.0 * delta
			_sm = Vector3(move_toward(_sm.x, fwd, k), move_toward(_sm.y, strafe, k), move_toward(_sm.z, rot * float(GameState.settings["sens"]), k))
			fwd = _sm.x
			strafe = _sm.y
			rot = _sm.z
		w.step(delta, fwd, strafe, rot, fine, kill)
	os.set_chaser(w.pos, w.angle)
	os.set_flame(os.lander_flame, 0.0)
	# camera: between the ascent stage and the ship, closer when near
	var tip := Vector3(w.nose_tip().x, -w.nose_tip().y, 0.0)
	var d := tip.length()
	var focus := Vector3(w.pos.x, -w.pos.y, 0.0).lerp(Vector3(2.0, 0, 0), 0.5)
	_orbit_cam(delta, clampf(d * 0.9 + 22.0, 24.0, 230.0), 18.0 + 6.0 * sin(_rs_t * 0.2), 9.0, focus)
	os.moon_body.rotation.y += delta * 0.008
	if _vals.has("range"):
		var near := d < 40.0
		(_vals["range"] as Label).text = Units.m(w.range_to_port())
		(_vals["speed"] as Label).text = Units.ms(w.vel.x, 2)
		(_vals["speed"] as Label).add_theme_color_override("font_color", Color.WHITE if not near else (UIKit.C_GOOD if w.vel.x <= DockingWorld.TOL_SPEED and w.vel.x > -0.01 else UIKit.C_BAD))
		(_vals["lat"] as Label).text = Units.m(absf(tip.y))
		(_vals["lat"] as Label).add_theme_color_override("font_color", Color.WHITE if not near else (UIKit.C_GOOD if absf(tip.y) <= DockingWorld.TOL_LAT else UIKit.C_BAD))
		(_vals["ang"] as Label).text = "%.1f°" % rad_to_deg(w.angle_error())
		(_vals["ang"] as Label).add_theme_color_override("font_color", Color.WHITE if not near else (UIKit.C_GOOD if absf(w.angle_error()) <= DockingWorld.TOL_ANGLE else UIKit.C_BAD))
		(_bars["fuel"] as ProgressBar).value = w.fuel / DockingWorld.FUEL_MAX * 100.0
	if _rs_t > 100.0 and not w.finished:
		_end_stage_fail("MOON_FAIL_DOCK", ["MOON_TIP_DOCK"])


func _on_docked() -> void:
	ret["dock_q"] = clampf(1.0 - absf(dock_world.contact_speed) / DockingWorld.TOL_SPEED * 0.45 - (1.0 - dock_world.fuel / DockingWorld.FUEL_MAX) * 0.2, 0.4, 1.0)
	Sfx.play("clang", -2.0)
	_set_hint(tr("M5S_DOCKED"), UIKit.C_GOOD)
	os.set_chaser(Vector2(-4.6, 0.0), 0.0)
	os.port_ring.visible = false
	_clear_hud_panel()
	_rs = "transfer"
	_rs_t = 0.0
	dock_world.queue_free()
	dock_world = null
	for a in os.astronauts:
		a.visible = true
	os.crate.visible = true


func _on_dock_failed(_reason: String) -> void:
	Fx3D.burst(os, Vector3(dock_world.nose_tip().x, -dock_world.nose_tip().y, 0), Color(1.0, 0.6, 0.25), 120, 26.0, 2.4, 1.6)
	Sfx.play("hit", 0.0)
	await get_tree().create_timer(1.2).timeout
	_end_stage_fail("MOON_FAIL_DOCK", ["MOON_TIP_DOCK"])


# ------------------------------------------------------ 6. crew transfer + TEI -----
func _stage_transfer(delta: float) -> void:
	# astronauts and the sample container float from the lander hatch to the command-module hatch
	var a := Vector3(-4.6, 0.4, 2.9)
	var b := Vector3(3.0, 0.2, 2.3)
	for i in os.astronauts.size():
		var k := clampf((_rs_t - 0.6 - 1.4 * i) / 3.2, 0.0, 1.0)
		var s := smoothstep(0.0, 1.0, k)
		os.astronauts[i].position = a.lerp(b, s) + Vector3(0, sin(k * PI) * 1.2 + 0.3 * i, 0.4 * sin(k * PI * 2.0))
		os.astronauts[i].rotation = Vector3(0.25 * sin(_rs_t * 1.3 + i), PI * 0.5 + 0.3 * sin(_rs_t + i), 0.15 * sin(_rs_t * 0.9))
		os.astronauts[i].visible = k < 1.0
	var kc := clampf((_rs_t - 3.4) / 2.4, 0.0, 1.0)
	os.crate.position = a.lerp(b, smoothstep(0.0, 1.0, kc)) + Vector3(0, sin(kc * PI) * 0.9 + 0.2, 0.4)
	os.crate.rotation = Vector3(_rs_t * 0.6, _rs_t * 0.4, 0)
	os.crate.visible = kc < 1.0
	_orbit_cam(delta, 22.0, 8.0 + 4.0 * sin(_rs_t * 0.3), 6.0, Vector3(-1.0, 0.0, 1.5), 46.0)
	if _rs_t > 0.4 and _msg_t == 0.0:
		_msg_t = 1.0
		_set_hint(tr("M5S_TRANSFER"), UIKit.C_ACCENT)
	if _rs_t >= 6.4:
		_msg_t = 0.0
		for aa in os.astronauts:
			aa.visible = false
		os.crate.visible = false
		_rs = "jettison"
		_rs_t = 0.0
		_set_hint(tr("M5S_JETTISON"), UIKit.C_ACCENT)


func _stage_jettison(delta: float) -> void:
	var k := clampf(_rs_t / 3.4, 0.0, 1.0)
	os.lander.position = Vector3(-4.6 - 36.0 * k * k, 2.0 * k, -3.0 * k)
	os.lander.rotation = Vector3(0.4 * k, 0.6 * k, 0.9 * k)
	_orbit_cam(delta, 30.0 + 10.0 * k, 60.0, 14.0, Vector3(-4.0 - 12.0 * k, 0.0, 0.0))
	if _rs_t >= 3.6:
		os.lander.visible = false
		_start_burn("tei", TEI_IDEAL, TEI_BAND, TEI_BASE + maxf(_asc_dv() - ASCENT_NEED, 0.0))


func _stage_tei(delta: float) -> void:
	var k := clampf(_burn_dv / TEI_IDEAL, 0.0, 1.0)
	os.set_moon_altitude(110_000.0 + 700_000.0 * k * k)
	os.moon_body.rotation.y += delta * 0.01
	_orbit_cam(delta, 36.0, 200.0 + _rs_t * 3.0, 10.0, Vector3(5.0, 0.0, 0.0))
	var firing := _update_burn(delta)
	if _burn_dv > _burn_target + _burn_band:
		_end_stage_fail("MOON_FAIL_TEI", ["MOON_TIP_TEI"])
		return
	if _burn_dv >= _burn_max - 0.1 and _burn_dv < _burn_target - _burn_band:
		_end_stage_fail("MOON_FAIL_TEI_FUEL", ["MOON_TIP_ASCENT"])
		return
	var in_win := absf(_burn_dv - _burn_target) <= _burn_band
	if in_win and not firing and _burn_dv > 0.0 and (_is_auto() or _burn_t > 2.0):
		ret["tei_dv"] = _burn_dv
		ret["tei_q"] = clampf(1.0 - absf(_burn_dv - _burn_target) / (TEI_BAND * 2.0), 0.0, 1.0)
		os.set_flame(os.csm_flame, 0.0)
		Sfx.loop_stop("rumble")
		_clear_hud_panel()
		_rs = "coast"
		_rs_t = 0.0
		_set_hint(tr("M5S_COAST"), UIKit.C_ACCENT)
		_hud_table([["M5S_H_DIST", "dist"], ["M5S_H_ETA", "eta"]], [])


func _stage_coast(delta: float) -> void:
	var k := clampf(_rs_t / 4.5, 0.0, 1.0)
	os.set_moon_altitude(lerpf(810_000.0, 40_000_000.0, k * k))
	os.stage.place_planet_view(lerpf(2_700_000.0, 2_050_000.0, smoothstep(0.0, 1.0, k)), 13.0, lerpf(500_000.0, 150_000.0, k))
	_orbit_cam(delta, 34.0, 150.0 + _rs_t * 6.0, 8.0, Vector3(5.0, 0.0, 0.0))
	(_vals["dist"] as Label).text = "%d %s" % [int(lerpf(384_400.0, 6_571.0, k)), tr("UNIT_KM")]
	(_vals["eta"] as Label).text = "%d h" % int(lerpf(72.0, 0.0, k))
	if _rs_t >= 4.7:
		_clear_hud_panel()
		_begin_entry_select()


func _begin_entry_select() -> void:
	_rs = "entry_set"
	_rs_t = 0.0
	_entry_angle = -4.0
	_hud_table([["MOON_L_ANGLE", "ang"], ["MOON_L_G", "g"], ["MOON_L_HEAT", "heat"], ["MOON_L_CORR", "corr"]], [])
	_set_hint(tr("M5S_HINT_ENTRY"), UIKit.C_ACCENT)


func _shield() -> float:
	return float(LaunchProfiles.MOON_CAPSULE[design["capsule"]]["shield"])


func _entry_numbers(a: float) -> Dictionary:
	var g := 3.0 + (absf(a) - 3.0) * 1.5
	var heat := 70.0 * pow(absf(a) / 6.0, 2.2) / _shield()
	return {"g": g, "heat": heat}


func _stage_entry_set(delta: float) -> void:
	os.stage.place_planet_view(2_050_000.0, 13.0, 150_000.0)
	_orbit_cam(delta, 30.0, 150.0 + _rs_t * 5.0, 8.0, Vector3(5.0, 0.0, 0.0))
	if _is_auto():
		_entry_angle = move_toward(_entry_angle, ENTRY_CENTER, 2.0 * delta)
		if _rs_t > 2.8:
			_commit_entry()
			return
	else:
		var d := 0.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			d += 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			d -= 1.0
		_entry_angle = clampf(_entry_angle - d * 2.0 * delta, -9.0, -3.0)
	var n := _entry_numbers(_entry_angle)
	var shallow := _entry_angle > ENTRY_SHALLOW
	var good := not shallow and float(n["g"]) <= ENTRY_G_LIMIT and float(n["heat"]) <= ENTRY_HEAT_LIMIT
	(_vals["ang"] as Label).text = "%.1f°" % _entry_angle
	(_vals["g"] as Label).text = "%.1f g (≤ %.1f)" % [float(n["g"]), ENTRY_G_LIMIT]
	(_vals["heat"] as Label).text = "%d%% (≤ %d%%)" % [int(n["heat"]), int(ENTRY_HEAT_LIMIT)]
	(_vals["corr"] as Label).text = tr("MOON_ENT_SKIP") if shallow else (tr("MOON_ENT_OK") if good else tr("MOON_ENT_STEEP"))
	for k in ["ang", "corr"]:
		(_vals[k] as Label).add_theme_color_override("font_color", UIKit.C_GOOD if good else UIKit.C_BAD)
	(_vals["g"] as Label).add_theme_color_override("font_color", UIKit.C_GOOD if float(n["g"]) <= ENTRY_G_LIMIT else UIKit.C_BAD)
	(_vals["heat"] as Label).add_theme_color_override("font_color", UIKit.C_GOOD if float(n["heat"]) <= ENTRY_HEAT_LIMIT else UIKit.C_BAD)


func _commit_entry() -> void:
	if _rs != "entry_set":
		return
	var n := _entry_numbers(_entry_angle)
	ret["angle"] = _entry_angle
	ret["g"] = float(n["g"])
	ret["heat"] = float(n["heat"])
	ret["quality"] = clampf(1.0 - absf(_entry_angle - ENTRY_CENTER) / 1.6, 0.3, 1.0)
	_clear_hud_panel()
	_rs = "sep"
	_rs_t = 0.0
	_set_hint(tr("M5S_SEP"), UIKit.C_ACCENT)
	Sfx.play("clang", -4.0)


func _stage_sep(delta: float) -> void:
	# the service module separates; the command-module capsule is left alone for the entry
	var k := clampf(_rs_t / 3.0, 0.0, 1.0)
	os.service.position = Vector3(0, 7.0 * k * k, 0.8 * k)
	os.service.rotation = Vector3(0.0, 0.0, 0.0)
	os.capsule.rotation = Vector3(0, 0, 0)
	_orbit_cam(delta, 26.0, 40.0, 12.0, Vector3(5.0, 0.0, 0.0))
	if _rs_t >= 3.2:
		os.show_entry()
		os.cap.rotation = Vector3(0, 0, 0)
		_alt = 120_000.0
		_speed = 11_000.0
		_rs = "entry"
		_rs_t = 0.0
		_set_hint(tr("M5S_ENTRY"), UIKit.C_ORANGE)
		_hud_table([["M5S_H_ALT", "alt"], ["M5S_H_VEL", "vel"], ["MOON_L_G", "g"], ["MOON_L_HEAT", "heat"]], [])


func _stage_entry(delta: float) -> void:
	var T := 8.0
	var k := clampf(_rs_t / T, 0.0, 1.0)
	var shallow := float(ret["angle"]) > ENTRY_SHALLOW
	var hot := float(ret["heat"]) > ENTRY_HEAT_LIMIT or float(ret["g"]) > ENTRY_G_LIMIT
	var peak := sin(clampf(k * 1.25, 0.0, 1.0) * PI)
	var heat_n := clampf(float(ret["heat"]) / ENTRY_HEAT_LIMIT, 0.0, 1.6)
	_alt = lerpf(120_000.0, CHUTE_START, pow(k, 0.8))
	_speed = lerpf(11_000.0, 520.0, pow(k, 0.7))
	if shallow and k > 0.5:
		# bounces off the atmosphere: climbs again
		_alt = lerpf(75_000.0, 160_000.0, clampf((k - 0.5) * 3.0, 0.0, 1.0))
		_speed = 9_000.0
		peak *= 0.2
	os.set_altitude(_alt, k * 0.02)
	os.set_flame(os.plasma, clampf(peak * heat_n, 0.0, 1.4), 7.0 + 8.0 * heat_n)
	os.cap.rotation = Vector3(0.12 * sin(_rs_t * 2.1), 0, 0.08 * sin(_rs_t * 1.7))
	var shake := 0.15 * peak
	_orbit_cam(delta, 14.0, 70.0 + 12.0 * k, 4.0, Vector3(0, 0.5, 0) + Vector3(randf_range(-shake, shake), randf_range(-shake, shake), 0), 46.0)
	(_vals["alt"] as Label).text = "%.0f km" % (_alt / 1000.0)
	(_vals["vel"] as Label).text = "%.1f km/s" % (_speed / 1000.0)
	(_vals["g"] as Label).text = "%.1f g" % (float(ret["g"]) * peak)
	(_vals["heat"] as Label).text = "%d%%" % int(float(ret["heat"]) * peak)
	if shallow and k >= 0.9:
		_end_stage_fail("MOON_FAIL_SKIP", ["MOON_TIP_ENTRY"])
		return
	if hot and k >= 0.6:
		Fx3D.burst(os, os.cap.global_position, Color(1.0, 0.7, 0.3), 140, 26.0, 2.4, 1.8)
		os.cap.visible = false
		os.set_flame(os.plasma, 0.0)
		Sfx.play("hit", 2.0)
		await get_tree().create_timer(1.4).timeout
		_end_stage_fail("MOON_FAIL_BURN", ["MOON_TIP_ENTRY_STEEP"])
		return
	if k >= 1.0:
		os.set_flame(os.plasma, 0.0)
		_clear_hud_panel()
		_begin_chute()


# ---------------------------------------------------------- parachutes + splashdown ---
func _begin_chute() -> void:
	_rs = "chute"
	_rs_t = 0.0
	_alt = CHUTE_START
	_speed = 520.0
	_chute = 0
	_chute_t = 0.0
	_drogue_alt = 0.0
	_main_alt = 0.0
	_hud_table([["M5S_H_ALT", "alt"], ["M5S_H_VEL", "vel"], ["M5S_H_CHUTE", "chute"]], [])
	_set_hint(tr("M5S_HINT_CHUTE"), UIKit.C_ACCENT)


func _deploy_chute() -> void:
	if _rs != "chute":
		return
	if _chute == 0:
		if _alt <= DROGUE_ALT:
			_chute = 1
			_chute_t = 0.0
			_drogue_alt = _alt
			os.drogue.visible = true
			os.drogue.scale = Vector3.ONE * 0.2
			Sfx.play("clang", -6.0)
	elif _chute == 1:
		if _alt <= MAIN_HIGH:
			_chute = 2
			_chute_t = 0.0
			_main_alt = _alt
			os.main_chute.visible = true
			os.main_chute.scale = Vector3.ONE * 0.2
			Sfx.play("clang", -3.0)


func _stage_chute(delta: float) -> void:
	_chute_t += delta
	# autopilot: drogue as soon as it is allowed, main at the ideal altitude
	if _is_auto():
		if _chute == 0 and _alt <= DROGUE_ALT - 600.0:
			_deploy_chute()
		elif _chute == 1 and _alt <= MAIN_IDEAL:
			_deploy_chute()
	elif _chute == 0 and _alt < DROGUE_ALT - 1500.0:
		_deploy_chute()                     # emergency drogue (late = less margin)
	var target_v := 480.0
	match _chute:
		1:
			target_v = 300.0
		2:
			target_v = 130.0 if _alt > 220.0 else 55.0
	_speed = lerpf(_speed, target_v, 1.0 - exp(-delta * (1.6 if _chute == 2 else 1.1)))
	_alt = maxf(_alt - _speed * delta, 0.0)
	os.set_altitude(_alt, 0.02)
	# canopies inflate and sway
	if os.drogue.visible:
		os.drogue.scale = Vector3.ONE * lerpf(os.drogue.scale.x, 1.0, 1.0 - exp(-delta * 3.0))
		os.drogue.position = Vector3(0.6 * sin(_rs_t * 1.1), 15.0, 0.4 * cos(_rs_t))
	if os.main_chute.visible:
		os.main_chute.scale = Vector3.ONE * lerpf(os.main_chute.scale.x, 1.0, 1.0 - exp(-delta * 1.4))
		os.main_chute.position = Vector3(1.4 * sin(_rs_t * 0.7), 34.0, 0.9 * cos(_rs_t * 0.6))
		os.drogue.visible = false
	os.cap.rotation = Vector3(0.05 * sin(_rs_t * 1.2), 0, 0.07 * sin(_rs_t * 0.9)) * (1.0 if _chute > 0 else 4.0)
	_orbit_cam(delta, 78.0 if _chute == 2 else (44.0 if _chute == 1 else 24.0), 62.0 + 10.0 * sin(_rs_t * 0.3), 12.0 if _chute > 0 else 6.0, Vector3(0, 20.0 if _chute == 2 else (8.0 if _chute == 1 else 5.0), 0), 46.0)
	(_vals["alt"] as Label).text = "%.0f m" % _alt
	(_vals["vel"] as Label).text = "%d m/s" % int(_speed)
	var ck := "M5S_CHUTE_NONE" if _chute == 0 else ("M5S_CHUTE_DROGUE" if _chute == 1 else "M5S_CHUTE_MAIN")
	(_vals["chute"] as Label).text = tr(ck)
	# prompts
	var prompt := ""
	if _chute == 0 and _alt <= DROGUE_ALT:
		prompt = tr("M5S_PRESS_DROGUE")
	elif _chute == 1 and _alt <= MAIN_HIGH:
		prompt = tr("M5S_PRESS_MAIN") if _alt >= MAIN_LOW else tr("M5S_PRESS_MAIN_NOW")
	if prompt != "":
		_set_hint(prompt, UIKit.C_ORANGE if _alt >= MAIN_LOW or _chute == 0 else UIKit.C_BAD)
	elif _chute == 2 and _chute_t < 0.3:
		_set_hint(tr("M5S_MAIN_OK"), UIKit.C_GOOD)
	elif _chute == 1 and _chute_t < 0.3:
		_set_hint(tr("M5S_DROGUE_OK"), UIKit.C_ACCENT)
	if _chute < 2 and _alt <= MAIN_LOW:
		os.set_altitude(0.0, 0.02)
		Fx3D.burst(os, os.cap.global_position, Color(1.0, 0.7, 0.3), 120, 24.0, 2.0, 1.6)
		os.cap.visible = false
		Sfx.play("hit", 2.0)
		_rs = ""
		await get_tree().create_timer(1.2).timeout
		_end_stage_fail("MOON_FAIL_CHUTE", ["MOON_TIP_CHUTE"])
		return
	if _alt <= 0.5:
		var dq := clampf(1.0 - absf(_main_alt - MAIN_IDEAL) / 900.0, 0.35, 1.0)
		var early := 1.0 if _drogue_alt >= 3200.0 else 0.8
		ret["chute_q"] = dq * early
		_rs = "splash"
		_rs_t = 0.0
		_clear_hud_panel()
		_set_hint(tr("M5S_SPLASH"), UIKit.C_GOOD)
		Fx3D.burst(os, os.cap.global_position + Vector3(0, -1.5, 0), Color(0.85, 0.95, 1.0), 120, 12.0, 2.4, 1.8)
		Sfx.play("beep", -2.0)


func _stage_splash(delta: float) -> void:
	os.set_altitude(0.5 + 0.35 * sin(_rs_t * 1.8), 0.02)
	os.cap.rotation = Vector3(0.1 * sin(_rs_t * 1.4), 0, 0.12 * sin(_rs_t * 1.1))
	os.main_chute.scale.y = lerpf(os.main_chute.scale.y, 0.15, 1.0 - exp(-delta * 1.2))
	os.main_chute.position.y = lerpf(os.main_chute.position.y, 4.0, 1.0 - exp(-delta * 0.8))
	os.main_chute.position.x += delta * 1.2
	_orbit_cam(delta, 40.0 + _rs_t * 2.0, 45.0 + _rs_t * 7.0, 14.0 + _rs_t, Vector3(0, 10.0, 0), 46.0)
	if _rs_t >= 5.2:
		_rs = ""
		ret["ok"] = true
		ret["samples"] = r_samples
		os.queue_free()
		os = null
		super._finish_mission()


## The crew did not make it home: the science was sent by radio, but the mission fails.
func _end_stage_fail(reason: String, tips: Array) -> void:
	_rs = ""
	Sfx.stop_all_loops()
	_clear_hud_panel()
	_end_return(reason, tips)


func _end_return(reason: String, tips: Array) -> void:
	_rs = ""
	ret["ok"] = false
	ret["fail_key"] = reason
	ret["fail_tips"] = tips
	if os != null:
		os.queue_free()
		os = null
	super._finish_mission()


func finish(success: bool, stars: int, score: int, stats: Array, reason_key: String, delay: float = 1.2, extra: Dictionary = {}) -> void:
	if ret.is_empty() or not ret.has("ok"):
		super.finish(success, stars, score, stats, reason_key, delay, extra)
		return
	var tips: Array = extra.get("tips", [])
	var segs: Array = extra.get("segments", [])
	var rating := 0.0
	if bool(ret["ok"]):
		rating = 0.15 * float(ret.get("loi_q", 1.0)) + 0.2 * float(ret.get("dock_q", 1.0)) + 0.2 * float(ret.get("tei_q", 0.0)) \
			+ 0.2 * float(ret.get("quality", 0.0)) + 0.25 * float(ret.get("chute_q", 0.0))
		stats.append(["R_LOI", "%d%%" % int(float(ret.get("loi_q", 1.0)) * 100.0)])
		stats.append(["R_DOCK", "%d%%" % int(float(ret.get("dock_q", 1.0)) * 100.0)])
		stats.append(["R_TEI", Units.ms(float(ret["tei_dv"]))])
		stats.append(["R_ENTRY", "%.1f deg | %.1f g | %d%%" % [float(ret["angle"]), float(ret["g"]), int(ret["heat"])]])
		stats.append(["R_CHUTE", "%d%%" % int(float(ret.get("chute_q", 1.0)) * 100.0)])
		stats.append(["R_SAMPLES_HOME", "%d / 3" % int(ret.get("samples", 0))])
		if rating >= 0.85 and stars < 3 and success:
			stars += 1
		score += int(rating * 800.0) + 120 * int(ret.get("samples", 0))
	else:
		success = false
		stars = 0
		reason_key = str(ret["fail_key"])
		for t in ret.get("fail_tips", []):
			tips.append(t)
		stats.append(["R_TEI", "-"])
	segs = segs.filter(func(r): return r[0] != "SEG_LAUNCH")
	segs.append(["SEG_RETURN", rating])
	segs.insert(0, ["SEG_LAUNCH", _launch_rating()])
	extra["segments"] = segs
	extra["tips"] = tips
	stats = stats.filter(func(r): return r[0] != "R_BUDGET_USED")
	stats.append(["R_BUDGET_USED", "%s / %s" % [Units.money(int(launch["cost"])), Units.money(int(launch["budget"]))]])
	stats.append(["R_LAUNCH_HULL", "%d%%" % int(launch["hull"])])
	super.finish(success, stars, score, stats, reason_key, delay, extra)


func _launch_rating() -> float:
	var l := launch
	var r := float(l["hull"]) / 100.0 * 0.6 + float(l.get("orbit_q", 1.0)) * 0.25 + (0.15 if not bool(l["fairing_early"]) else 0.0)
	r *= 1.0 - clampf(float(l["waste"]) * 0.3 + float(l["booster_waste"]) * 0.2, 0.0, 0.3)
	return clampf(r, 0.0, 1.0)
