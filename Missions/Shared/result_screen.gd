class_name ResultScreen
extends OverlayFrame
## End-of-mission screen: stars, engineering stats and - when the mission provides it - the
## four-segment evaluation (Launch / Space / Ground / Users), science return, how the science
## is used, and recommendations. Long content scrolls; the buttons stay pinned at the bottom.

signal retry_requested
signal next_requested
signal missions_requested


## stats: Array of [label_key, value_text]. reason_key: short explanation key (may be "").
## extra (optional): {"segments": [[seg_key, 0..1], ...], "science": 0..1.5, "user": key,
##                    "tips": [keys], "science_note": key}
func show_result(success: bool, stars: int, stats: Array, reason_key: String, has_next: bool,
		extra: Dictionary = {}) -> void:
	var wide := not extra.is_empty()
	build(980.0 if wide else 640.0, 0.82)
	var title_col: Color = UIKit.C_GOOD if success else UIKit.C_BAD
	header.add_child(UIKit.label("RESULT_SUCCESS" if success else "RESULT_FAIL", 36, title_col, HORIZONTAL_ALIGNMENT_CENTER))
	if reason_key != "":
		var r := UIKit.label(reason_key, 17, UIKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.add_child(r)
	if success:
		var stars_l := UIKit.label("", 42, UIKit.C_ORANGE, HORIZONTAL_ALIGNMENT_CENTER)
		stars_l.text = "★".repeat(stars) + "☆".repeat(3 - stars)
		header.add_child(stars_l)

	var cols := UIKit.hbox(28)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	# ---- left column: numbers
	var left := UIKit.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(grid)
	for s in stats:
		var pair: Array = s
		var k := UIKit.label(str(pair[0]), 16, UIKit.C_MUTED)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(k)
		grid.add_child(UIKit.label(str(pair[1]), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT))
	# ---- right column: segments, science, tips
	if wide:
		var right := UIKit.vbox(8)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(right)
		if extra.has("segments"):
			right.add_child(UIKit.label("RES_SEGMENTS", 17, UIKit.C_ACCENT))
			for seg in extra["segments"]:
				var row := UIKit.hbox(8)
				var nm := UIKit.label(str(seg[0]), 15, UIKit.C_TEXT)
				nm.custom_minimum_size.x = 110
				row.add_child(nm)
				var rating := float(seg[1])
				var bar := UIKit.progress_bar(UIKit.C_GOOD if rating >= 0.75 else (UIKit.C_WARN if rating >= 0.45 else UIKit.C_BAD),
					Vector2(120, 12))
				bar.value = rating * 100.0
				bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(bar)
				row.add_child(UIKit.label("%d%%" % int(rating * 100.0), 14, Color.WHITE))
				right.add_child(row)
		if extra.has("science"):
			var sc := UIKit.hbox(8)
			sc.add_child(UIKit.label("RES_SCIENCE", 17, UIKit.C_ACCENT))
			var scv := UIKit.label("%d%%" % int(float(extra["science"]) * 100.0), 26, UIKit.C_ORANGE, HORIZONTAL_ALIGNMENT_RIGHT)
			scv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sc.add_child(scv)
			right.add_child(sc)
		for key in ["science_note", "user"]:
			if extra.has(key):
				if key == "user":
					right.add_child(UIKit.label("RES_USER", 15, UIKit.C_ACCENT))
				var l := UIKit.label(str(extra[key]), 12 if key == "science_note" else 14, UIKit.C_MUTED if key == "science_note" else UIKit.C_TEXT)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				right.add_child(l)
		if extra.has("tips"):
			right.add_child(UIKit.label("RES_TIPS", 15, UIKit.C_ACCENT))
			for tip in extra["tips"]:
				var t := UIKit.label(str(tip), 13, UIKit.C_WARN)
				t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				right.add_child(t)

	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	var retry := UIKit.button("BTN_RETRY", Vector2(170, 48))
	var miss := UIKit.button("BTN_MISSIONS", Vector2(170, 48))
	retry.name = "RetryButton"
	miss.name = "MissionsButton"
	retry.pressed.connect(func(): retry_requested.emit())
	miss.pressed.connect(func(): missions_requested.emit())
	if success and has_next:
		var nxt := UIKit.button("BTN_NEXT", Vector2(190, 48))
		nxt.name = "NextButton"
		nxt.pressed.connect(func(): next_requested.emit())
		footer.add_child(nxt)
	footer.add_child(retry)
	footer.add_child(miss)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.5)
	Sfx.play("success" if success else "fail", -4.0)
	request_fit()
