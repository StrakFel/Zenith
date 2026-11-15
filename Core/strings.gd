class_name Strings
extends RefCounted
## All translatable texts: KEY -> [English, Українська].
## Keys are used directly as Label/Button text (Godot translates them
## automatically) or via tr("KEY"). Add a new language by appending one more
## entry to every pair and to Loc.LOCALES.

static func all() -> Dictionary:
	var d: Dictionary = {}
	d.merge(StringsCore.DATA)
	d.merge(StringsM1.DATA)
	d.merge(StringsM2.DATA)
	d.merge(StringsM3.DATA)
	d.merge(StringsSci.DATA, true)
	d.merge(StringsCam.DATA, true)
	d.merge(StringsLunar.DATA, true)
	d.merge(StringsCampaign.DATA, true)
	d.merge(StringsNasa.DATA, true)
	return d


