class_name MissionSummary
extends OverlayFrame
## Final "Mission Summary" before the countdown: scientific objective, chosen hardware for every segment
## (Launch / Space / Ground / User), key numbers, budget and a prediction of how well each segment will do.

signal back_requested
signal confirmed


func _col(title_key: String, rows: Array) -> VBoxContainer:
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIKit.label(title_key, 16, UIKit.C_ORANGE))
	for r in rows:
		var row := UIKit.hbox(8)
		var k := UIKit.label(str(r[0]), 13, UIKit.C_MUTED)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(k)
		row.add_child(UIKit.label(str(r[1]), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(row)
	return v


func setup(design: Dictionary, sat: Dictionary, rk: Dictionary, rocket: Dictionary) -> void:
	build(960.0, 0.8)
	header.add_child(UIKit.label("SUM_TITLE", 30, Color.WHITE))
	var goal: Dictionary = M1Design.GOALS[design["goal"]]
	var g := UIKit.label(tr(str(goal["name"])), 20, UIKit.C_ACCENT)
	header.add_child(g)
	var gd := UIKit.label(str(goal["desc"]), 13, UIKit.C_MUTED)
	gd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(gd)
	var cols := UIKit.hbox(22)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var n: Dictionary = M1Parts.NOSES[rk["nose"]]
	var t: Dictionary = M1Parts.TANKS[rk["tank"]]
	var e: Dictionary = M1Parts.ENGINES[rk["engine"]]
	cols.add_child(_col("SEG_LAUNCH", [
		["M1_SLOT_NOSE", tr(str(n["name"]))], ["M1_SLOT_TANK", tr(str(t["name"]))], ["M1_SLOT_ENGINE", tr(str(e["name"]))],
		["M1_ST_STAGES", "%d" % int(rocket["stages"])],
		["M1_ST_TOTAL_MASS", Units.kg(float(rocket["mass_wet"]))],
		["M1_ST_TWR", "%.2f" % float(rocket["twr"])],
		["M1_ST_DV", "%d / %d %s" % [int(rocket["dv"]), int(M1Parts.REQUIRED_DV), tr("UNIT_MS")]],
		["M1_ST_REL", "%d%%" % int(float(rocket["rel"]) * 100.0)],
	]))
	var ins: Dictionary = M1Design.INSTRUMENTS[design["instrument"]]
	var sol: Dictionary = M1Design.SOLAR[design["solar"]]
	var bat: Dictionary = M1Design.BATTERY[design["battery"]]
	var com: Dictionary = M1Design.COMM[design["comm"]]
	cols.add_child(_col("SEG_SPACE", [
		["SUM_INSTR", tr(str(ins["name"]))], ["SUM_SOLAR", tr(str(sol["name"]))], ["SUM_BATT", tr(str(bat["name"]))],
		["LUNREQ_POWER", "%d / %d W" % [int(sat["gen"]), int(sat["demand"])]],
		["REQ_BATT", "%d / %d Wh" % [int(sat["batt_wh"]), int(sat["batt_need"])]],
	]))
	cols.add_child(_col("SEG_GROUND", [
		["SUM_ANT", tr(str(com["name"]))],
		["REQ_DATA", "%d / %d Mbit" % [int(sat["data_downlink"]), int(sat["data_produced"])]],
		["REQ_ORBIT", "%d-%d km" % [int(goal["best"][0]), int(goal["best"][1])]],
		["R_COST", "%s / %s" % [Units.money(int(rocket["cost"])), Units.money(M1Parts.BUDGET)]],
	]))
	body.add_child(HSeparator.new())
	body.add_child(UIKit.label("SUM_PREDICT", 16, UIKit.C_ACCENT))
	var launch_p := clampf(float(rocket["rel"]) * minf(float(rocket["dv"]) / M1Parts.REQUIRED_DV, 1.0), 0.0, 1.0)
	var space_p := (minf(float(sat["power_ratio"]), 1.0) + lerpf(0.4, 1.0, minf(float(sat["batt_ratio"]), 1.0))) * 0.5
	var ground_p := minf(float(sat["data_ratio"]), 1.0)
	var user_p := clampf(float(sat["sci"]) / 1.5 * launch_p * space_p * ground_p * 1.1, 0.0, 1.0)
	for seg in [["SEG_LAUNCH", launch_p], ["SEG_SPACE", space_p], ["SEG_GROUND", ground_p], ["SEG_USER", user_p]]:
		var row := UIKit.hbox(8)
		var nm := UIKit.label(seg[0], 14, UIKit.C_TEXT)
		nm.custom_minimum_size.x = 110
		row.add_child(nm)
		var r: float = seg[1]
		var bar := UIKit.progress_bar(UIKit.C_GOOD if r >= 0.75 else (UIKit.C_WARN if r >= 0.5 else UIKit.C_BAD), Vector2(200, 12))
		bar.value = r * 100.0
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		row.add_child(UIKit.label("%d%%" % int(r * 100.0), 14, Color.WHITE))
		body.add_child(row)
	var note := UIKit.label("SUM_NOTE", 12, UIKit.C_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	var back := UIKit.button("REV_BACK", Vector2(220, 50))
	back.name = "BackButton"
	back.pressed.connect(func(): back_requested.emit())
	footer.add_child(back)
	var go := UIKit.button("SUM_CONFIRM", Vector2(280, 50))
	go.name = "ConfirmButton"
	go.pressed.connect(func(): confirmed.emit())
	footer.add_child(go)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
	request_fit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		back_requested.emit()
		get_viewport().set_input_as_handled()
