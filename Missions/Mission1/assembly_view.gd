class_name AssemblyView
extends Control
## Rocket assembly screen: drag parts from the catalogue onto the launch stand
## (or press "Install"), live mass / thrust / delta-v / cost readout.

signal launch_requested(build: Dictionary)

const SLOT_KEYS := {"nose": "M1_SLOT_NOSE", "upper": "M1_SLOT_UPPER", "tank": "M1_SLOT_TANK", "engine": "M1_SLOT_ENGINE"}


# ------------------------------------------------------------------ icon ----
class PartIcon extends Control:
	var slot := ""
	var id := ""

	func _init(s: String = "", i: String = "", min_size: Vector2 = Vector2(64, 84)) -> void:
		slot = s
		id = i
		custom_minimum_size = min_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var p: Dictionary = M1Parts.catalog(slot)[id]
		var pw := RocketDrawer.W if slot != "engine" else maxf(float(p["w"]), 40.0)
		var ph := float(p["h"])
		var sc := minf((size.x - 6.0) / (pw + 20.0), (size.y - 8.0) / ph)
		draw_set_transform(Vector2(size.x * 0.5 - pw * sc * 0.5, size.y * 0.5 - ph * sc * 0.5), 0.0, Vector2(sc, sc))
		var r := Rect2(0, 0, pw if slot != "engine" else float(p["w"]), ph)
		if slot == "engine":
			r.position.x = (pw - r.size.x) * 0.5
		match slot:
			"nose":
				RocketDrawer.draw_nose(self, id, r, 1.0)
			"tank":
				RocketDrawer.draw_tank(self, id, r, 1.0)
			"upper":
				RocketDrawer.draw_tank(self, "s", r, 1.0)
			_:
				RocketDrawer.draw_engine(self, id, r, 1.0)


# ------------------------------------------------------------------ card ----
class PartCard extends PanelContainer:
	signal install(slot: String, id: String)
	var slot := ""
	var id := ""

	func setup(s: String, i: String, installed: bool, current: String = "") -> void:
		slot = s
		id = i
		var p: Dictionary = M1Parts.catalog(slot)[id]
		var sb := UIKit.box(Color(0.045, 0.1, 0.2, 0.92), UIKit.C_ORANGE if installed else UIKit.C_BORDER, 10, 2 if installed else 1, 8)
		add_theme_stylebox_override("panel", sb)
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		var h := UIKit.hbox(10)
		add_child(h)
		var ic := PartIcon.new(slot, id)
		h.add_child(ic)
		var v := UIKit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var name_l := UIKit.label(str(p["name"]), 18, Color.WHITE)
		v.add_child(name_l)
		var d := UIKit.label(str(p["desc"]), 13, UIKit.C_MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 150
		v.add_child(d)
		var stats := UIKit.hbox(12)
		var cur_lines: Array = M1Parts.part_stat_lines(slot, current) if (current != "" and current != id) else []
		var li := 0
		for line in M1Parts.part_stat_lines(slot, id):
			var col := UIKit.vbox(0)
			col.add_child(UIKit.label(str(line[0]), 11, UIKit.C_MUTED))
			var vrow := UIKit.hbox(4)
			vrow.add_child(UIKit.label(str(line[1]), 14, UIKit.C_TEXT))
			if not cur_lines.is_empty():
				# comparison with the part installed now: green = better, red = worse
				var diff: float = float(line[2]) - float(cur_lines[li][2])
				if absf(diff) > 0.0001:
					var better: bool = diff * float(line[3]) > 0.0
					vrow.add_child(UIKit.label("%s%s" % ["+" if diff > 0.0 else "-", _fmt_delta(absf(diff))], 11,
						UIKit.C_GOOD if better else UIKit.C_BAD))
			col.add_child(vrow)
			stats.add_child(col)
			li += 1
		v.add_child(stats)
		var right := UIKit.vbox(4)
		h.add_child(right)
		var cost := UIKit.label("", 18, UIKit.C_WARN, HORIZONTAL_ALIGNMENT_RIGHT)
		cost.text = Units.money(int(p["cost"]))
		right.add_child(cost)
		if current != "" and current != id:
			var dc: int = int(p["cost"]) - int(M1Parts.catalog(slot)[current]["cost"])
			if dc != 0:
				right.add_child(UIKit.label("%s%s" % ["+" if dc > 0 else "-", Units.money(absi(dc))], 12,
					UIKit.C_BAD if dc > 0 else UIKit.C_GOOD, HORIZONTAL_ALIGNMENT_RIGHT))
		var b := UIKit.button("M1_INSTALL", Vector2(84, 34))
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func(): install.emit(slot, id))
		right.add_child(b)

	static func _fmt_delta(v: float) -> String:
		return "%d" % int(round(v)) if v >= 10.0 else "%.2f" % v

	func _get_drag_data(_at: Vector2) -> Variant:
		var prev := PartIcon.new(slot, id, Vector2(86, 110))
		prev.modulate = Color(1, 1, 1, 0.85)
		var holder := Control.new()
		holder.add_child(prev)
		prev.position = -prev.custom_minimum_size * 0.5
		set_drag_preview(holder)
		return {"m1part": true, "slot": slot, "id": id}


# ---------------------------------------------------------------- canvas ----
## Transparent overlay on top of the 3D pad: accepts part drops and draws slot brackets
## / labels by projecting the 3D rocket into screen space.
class PadCanvas extends Control:
	signal part_dropped(slot: String, id: String)
	var build: Dictionary = {}
	var hover_slot := ""
	var scene3d: PadScene3D
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS   # camera drag / wheel go through, drops still work

	func _process(d: float) -> void:
		_t += d
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
			hover_slot = ""

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if data is Dictionary and (data as Dictionary).has("m1part"):
			hover_slot = str((data as Dictionary)["slot"])
			return true
		return false

	func _drop_data(_at: Vector2, data: Variant) -> void:
		hover_slot = ""
		var d: Dictionary = data
		part_dropped.emit(str(d["slot"]), str(d["id"]))

	func _draw() -> void:
		if scene3d == null or not scene3d.is_inside_tree():
			return
		var cam := scene3d.camera
		var rk := scene3d.rocket
		var font := ThemeDB.fallback_font
		var off := -get_global_rect().position
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		for slot in M1Parts.SLOTS:
			if slot == "upper" and str(build.get("upper", "")) == "":
				continue   # optional stage: no bracket while it is not installed
			var span := rk.slot_world_span(slot)
			if cam.is_position_behind(span[0]) or cam.is_position_behind(span[1]):
				continue
			var pb := cam.unproject_position(span[0]) + off
			var pt := cam.unproject_position(span[1]) + off
			var mid := (pb + pt) * 0.5
			var rpx := (cam.unproject_position(span[0] + cam.global_transform.basis.x * 2.0)
				- cam.unproject_position(span[0])).length()
			var filled := str(build.get(slot, "")) != ""
			var col := UIKit.C_GOOD if filled else UIKit.C_ACCENT
			var bx := mid.x - rpx - 26.0
			# bracket
			draw_line(Vector2(bx, pb.y), Vector2(bx, pt.y), Color(col.r, col.g, col.b, 0.85), 2.0, true)
			draw_line(Vector2(bx, pb.y), Vector2(bx + 10, pb.y), Color(col.r, col.g, col.b, 0.85), 2.0, true)
			draw_line(Vector2(bx, pt.y), Vector2(bx + 10, pt.y), Color(col.r, col.g, col.b, 0.85), 2.0, true)
			draw_line(Vector2(bx, mid.y), Vector2(mid.x - rpx - 6.0, mid.y), Color(col.r, col.g, col.b, 0.5), 1.5, true)
			draw_string(font, Vector2(bx - 196.0, mid.y + 6.0), tr(AssemblyView.SLOT_KEYS[slot]),
				HORIZONTAL_ALIGNMENT_RIGHT, 186.0, 17, col)
			if hover_slot == slot:
				var hr := Rect2(Vector2(mid.x - rpx - 12.0, minf(pb.y, pt.y) - 6.0),
					Vector2(rpx * 2.0 + 24.0, absf(pt.y - pb.y) + 12.0))
				draw_rect(hr, Color(1.0, 0.55, 0.15, 0.12 + 0.12 * pulse))
				draw_rect(hr, UIKit.C_ORANGE, false, 3.0)

# ------------------------------------------------------------------ view ----
var build: Dictionary = {"nose": "", "upper": "", "tank": "", "engine": ""}
var scene3d: PadScene3D
var payload_mass := M1Parts.PAYLOAD_MASS
var sat_cost := 0
var _canvas: PadCanvas
var _cards_box: VBoxContainer
var _tab_slot := "engine"
var _tab_buttons: Dictionary = {}
var _slot_rows: Dictionary = {}
var _stat_labels: Dictionary = {}
var _cost_bar: ProgressBar
var _ready_label: Label
var _launch: Button


func _ready() -> void:
	theme = UIKit.get_ui_theme()
	# the full-screen root must NOT swallow the mouse: the free middle area belongs to the 3D camera
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := MarginContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 16)
	add_child(root)
	var cols := UIKit.hbox(14)
	root.add_child(cols)
	cols.add_child(_build_left())
	_canvas = PadCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.scene3d = scene3d
	_canvas.part_dropped.connect(_on_install)
	cols.add_child(_canvas)
	cols.add_child(_build_right())
	_show_tab("engine")
	if scene3d != null:
		scene3d.set_build(build, true)
	_refresh()


func _build_left() -> Control:
	var p := UIKit.panel()
	p.custom_minimum_size = Vector2(330, 0)
	# everything scrolls except the pinned "design review" button, so it is always reachable (small windows, 4 slots)
	var outer := UIKit.vbox(8)
	p.add_child(outer)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(sc)
	var v := UIKit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.add_child(UIKit.label("M1_ASM_TITLE", 26, Color.WHITE))
	v.add_child(UIKit.label("M1_ASM_HINT", 13, UIKit.C_MUTED))
	v.add_child(HSeparator.new())
	for slot in M1Parts.SLOTS:
		var row := UIKit.hbox(6)
		var name_col := UIKit.vbox(0)
		name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_col.add_child(UIKit.label(SLOT_KEYS[slot], 12, UIKit.C_MUTED))
		var val := UIKit.label("M1_EMPTY", 17, UIKit.C_TEXT)
		name_col.add_child(val)
		row.add_child(name_col)
		var rm := UIKit.button("M1_REMOVE", Vector2(86, 32))
		rm.add_theme_font_size_override("font_size", 14)
		rm.pressed.connect(func(): _on_install(slot, ""))
		row.add_child(rm)
		v.add_child(row)
		_slot_rows[slot] = {"label": val, "remove": rm}
	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("M1_STATS", 18, UIKit.C_ACCENT))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 2)
	v.add_child(g)
	for r in [["M1_ST_TOTAL_MASS", "mass"], ["M1_ST_FUEL", "fuel"], ["M1_ST_THRUST", "thrust"],
			["M1_ST_TWR", "twr"], ["M1_ST_DV", "dv"], ["M1_ST_STAGES", "stages"], ["M1_ST_REL", "rel"]]:
		var k := UIKit.label(r[0], 15, UIKit.C_MUTED)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(k)
		var val2 := UIKit.label("-", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		g.add_child(val2)
		_stat_labels[r[1]] = val2
	var cost_row := UIKit.hbox(8)
	cost_row.add_child(UIKit.label("M1_ST_COST", 15, UIKit.C_MUTED))
	_stat_labels["cost"] = UIKit.label("%s / %s" % [Units.money(0), Units.money(M1Parts.BUDGET)], 16, UIKit.C_WARN, HORIZONTAL_ALIGNMENT_RIGHT)
	_stat_labels["cost"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_row.add_child(_stat_labels["cost"])
	v.add_child(cost_row)
	_cost_bar = UIKit.progress_bar(UIKit.C_WARN, Vector2(0, 12))
	v.add_child(_cost_bar)
	v.add_child(HSeparator.new())
	_ready_label = UIKit.label("", 15, UIKit.C_TEXT)
	_ready_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ready_label.custom_minimum_size = Vector2(290, 56)
	v.add_child(_ready_label)
	_launch = UIKit.button("M1_TO_REVIEW", Vector2(0, 58))
	_launch.add_theme_font_size_override("font_size", 22)
	_launch.pressed.connect(func(): launch_requested.emit(build.duplicate()))
	outer.add_child(_launch)
	return p


func _build_right() -> Control:
	var p := UIKit.panel()
	p.custom_minimum_size = Vector2(410, 0)
	var v := UIKit.vbox(8)
	p.add_child(v)
	v.add_child(UIKit.label("M1_CATALOG", 22, Color.WHITE))
	var tabs := UIKit.hbox(6)
	v.add_child(tabs)
	var group := ButtonGroup.new()
	for slot in ["engine", "tank", "upper", "nose"]:
		var b := Button.new()
		b.text = SLOT_KEYS[slot]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_show_tab.bind(slot))
		tabs.add_child(b)
		_tab_buttons[slot] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_cards_box = UIKit.vbox(8)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cards_box)
	return p


func _show_tab(slot: String) -> void:
	_tab_slot = slot
	(_tab_buttons[slot] as Button).button_pressed = true
	for c in _cards_box.get_children():
		c.queue_free()
	var cat := M1Parts.catalog(slot)
	for id in cat:
		var card := PartCard.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cards_box.add_child(card)
		card.setup(slot, id, str(build[slot]) == id, str(build[slot]))
		card.install.connect(_on_install)


func _on_install(slot: String, id: String) -> void:
	build[slot] = id
	_canvas.build = build
	if scene3d != null:
		scene3d.set_build(build, true)
	_show_tab(_tab_slot)
	_refresh()


func _refresh() -> void:
	_canvas.build = build
	var st := M1Parts.compute(build, payload_mass, sat_cost)
	for slot in M1Parts.SLOTS:
		var id := str(build[slot])
		var row: Dictionary = _slot_rows[slot]
		var lab: Label = row["label"]
		lab.text = str(M1Parts.catalog(slot)[id]["name"]) if id != "" else ("M1_NO_UPPER" if slot == "upper" else "M1_EMPTY")
		lab.add_theme_color_override("font_color", UIKit.C_TEXT if id != "" else UIKit.C_MUTED)
		(row["remove"] as Button).disabled = id == ""
	(_stat_labels["stages"] as Label).text = "%d" % int(st["stages"])
	(_stat_labels["rel"] as Label).text = "%d%%" % int(float(st["rel"]) * 100.0)
	(_stat_labels["mass"] as Label).text = Units.kg(float(st["mass_wet"]))
	(_stat_labels["fuel"] as Label).text = Units.kg(float(st["fuel"]))
	(_stat_labels["thrust"] as Label).text = Units.kn(float(st["thrust"]))
	var twr := float(st["twr"])
	var twr_l: Label = _stat_labels["twr"]
	twr_l.text = "%.2f" % twr if bool(st["complete"]) else "-"
	twr_l.add_theme_color_override("font_color", UIKit.C_BAD if twr < 1.15 else (UIKit.C_WARN if twr > 2.6 else UIKit.C_GOOD))
	var dv := float(st["dv"])
	var dv_l: Label = _stat_labels["dv"]
	dv_l.text = Units.ms(dv) if bool(st["complete"]) else "-"
	dv_l.add_theme_color_override("font_color", UIKit.C_GOOD if dv >= M1Parts.REQUIRED_DV else UIKit.C_BAD)
	(_stat_labels["cost"] as Label).text = "%s / %s" % [Units.money(int(st["cost"])), Units.money(M1Parts.BUDGET)]
	(_stat_labels["cost"] as Label).add_theme_color_override("font_color", UIKit.C_BAD if bool(st["over_budget"]) else UIKit.C_WARN)
	_cost_bar.value = float(st["cost"]) / float(M1Parts.BUDGET) * 100.0
	UIKit.set_bar_color(_cost_bar, UIKit.C_BAD if bool(st["over_budget"]) else UIKit.C_WARN)
	var msgs := M1Parts.readiness(st)
	var worst: String = msgs[0]
	var lines: Array[String] = []
	for k in msgs.slice(0, 2):
		lines.append(tr(k))
	_ready_label.text = "\n".join(lines)
	_ready_label.add_theme_color_override("font_color", UIKit.C_GOOD if worst == "M1_RDY_OK" else (UIKit.C_MUTED if worst == "M1_RDY_INCOMPLETE" else UIKit.C_WARN))
	_launch.disabled = not M1Parts.can_launch(st)


