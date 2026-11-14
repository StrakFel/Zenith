class_name DesignReview
extends OverlayFrame
## Verification step: every requirement is checked before launch (NASA: verify the design
## against the requirements). Failed items are allowed but lower the science return.

signal back_requested
signal launch_approved


func setup(design: Dictionary, rocket: Dictionary) -> void:
	setup_reqs(M1Design.requirements(design, rocket), M1Parts.can_launch(rocket))


## Generic verification table: reqs = [{id, key, level 0..2, value, hint}], can = launch allowed.
func setup_reqs(reqs: Array, can: bool) -> void:
	build(860.0, 0.72)
	header.add_child(UIKit.label("REV_TITLE", 30, Color.WHITE))
	var sub := UIKit.label("REV_SUB", 14, UIKit.C_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	var cols := [UIKit.C_GOOD, UIKit.C_WARN, UIKit.C_BAD]
	var words := ["LVL_OK", "LVL_WARN", "LVL_FAIL"]
	for r in reqs:
		var lvl: int = r["level"]
		var name_l := UIKit.label(str(r["key"]), 16, Color.WHITE)
		name_l.custom_minimum_size.x = 200
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(name_l)
		var val := UIKit.label(str(r["value"]), 15, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		val.custom_minimum_size.x = 150
		grid.add_child(val)
		var badge := UIKit.label(words[lvl], 15, cols[lvl], HORIZONTAL_ALIGNMENT_CENTER)
		badge.custom_minimum_size.x = 100
		grid.add_child(badge)
		var hint := UIKit.label(str(r["hint"]) if lvl > 0 or r["id"] == "orbit" else "", 12, UIKit.C_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = 170
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(hint)
	var worst := M1Design.worst_level(reqs)
	var verdict := UIKit.label(["REV_RISK_OK", "REV_RISK_WARN", "REV_RISK_FAIL"][worst], 17, cols[worst])
	verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	verdict.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(verdict)
	if not can:
		var blocked := UIKit.label("REV_BLOCKED", 15, UIKit.C_BAD)
		blocked.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(blocked)
	var back := UIKit.button("REV_BACK", Vector2(220, 50))
	back.name = "BackButton"
	back.pressed.connect(func(): back_requested.emit())
	footer.add_child(back)
	var go := UIKit.button("REV_LAUNCH", Vector2(260, 50))
	go.name = "LaunchButton"
	go.disabled = not can
	go.pressed.connect(func(): launch_approved.emit())
	footer.add_child(go)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
	request_fit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		back_requested.emit()
		get_viewport().set_input_as_handled()