extends Node3D
## "NASA Resources": real NASA links that informed the game, each with a short note on how ZENITH uses it.

const LINKS := [
	["NASA Systems Engineering Handbook", "https://www.nasa.gov/reference/systems-engineering-handbook/", "NR_SE"],
	["NASA Glenn: Rocket Propulsion", "https://www.grc.nasa.gov/www/k-12/airplane/rocket.html", "NR_ROCKET"],
	["NASA Space Place: What Is an Orbit?", "https://spaceplace.nasa.gov/orbits/en/", "NR_ORBIT"],
	["NASA Earth Science", "https://science.nasa.gov/earth/", "NR_EARTH"],
	["NASA Earth Observatory", "https://earthobservatory.nasa.gov/", "NR_EO"],
	["NASA Worldview", "https://worldview.earthdata.nasa.gov/", "NR_WORLDVIEW"],
	["NASA Heliophysics", "https://science.nasa.gov/heliophysics/", "NR_HELIO"],
	["International Space Station", "https://www.nasa.gov/international-space-station/", "NR_ISS"],
	["NASA Small Spacecraft Systems Virtual Institute", "https://www.nasa.gov/smallsat-institute/", "NR_SMALLSAT"],
	["NASA Artemis", "https://www.nasa.gov/humans-in-space/artemis/", "NR_ARTEMIS"],
	["NASA: Earth's Moon", "https://science.nasa.gov/moon/", "NR_MOON"],
	["NASA: Apollo 11", "https://www.nasa.gov/mission/apollo-11/", "NR_APOLLO"],
]


func _ready() -> void:
	var bg := MenuBackdrop3D.new()
	bg.view_name = "settings"
	add_child(bg)
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := Control.new()
	screen.theme = UIKit.get_ui_theme()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(screen)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.add_theme_constant_override("margin_right", 40)
	screen.add_child(margin)
	var p := UIKit.panel()
	margin.add_child(p)
	var outer := UIKit.vbox(8)
	p.add_child(outer)
	outer.add_child(UIKit.label("NR_TITLE", 32, Color.WHITE))
	var intro := UIKit.label("NR_INTRO", 14, UIKit.C_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 600
	outer.add_child(intro)
	outer.add_child(UIKit.label("NR_LOOP", 14, UIKit.C_ORANGE))
	outer.add_child(HSeparator.new())
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(sc)
	var list := UIKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for it in LINKS:
		list.add_child(_row(str(it[0]), str(it[1]), str(it[2])))
	var back := UIKit.button("BTN_BACK", Vector2(200, 46))
	back.pressed.connect(func(): Router.go_to(Router.MAIN_MENU))
	outer.add_child(back)


func _row(title: String, url: String, note_key: String) -> Control:
	var card := UIKit.panel()
	card.add_theme_stylebox_override("panel", UIKit.box(Color(0.05, 0.1, 0.2, 0.8), UIKit.C_BORDER, 8, 1, 8))
	var h := UIKit.hbox(12)
	card.add_child(h)
	var col := UIKit.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	col.add_child(UIKit.label(title, 17, Color.WHITE))
	var n := UIKit.label(note_key, 13, UIKit.C_TEXT)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size.x = 400
	col.add_child(n)
	col.add_child(UIKit.label(url, 11, UIKit.C_ACCENT))
	var open := UIKit.button("NR_OPEN", Vector2(130, 36))
	open.add_theme_font_size_override("font_size", 14)
	open.pressed.connect(func(): OS.shell_open(url))
	h.add_child(open)
	var cp := UIKit.button("NR_COPY", Vector2(120, 36))
	cp.add_theme_font_size_override("font_size", 14)
	cp.pressed.connect(func():
		DisplayServer.clipboard_set(url)
		cp.text = "NR_COPIED")
	h.add_child(cp)
	return card
