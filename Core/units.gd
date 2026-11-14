class_name Units
extends RefCounted
## Localised unit formatting (kg -> кг, m/s -> м/с ...). Uses TranslationServer so it
## also works from RefCounted/static code.


static func _t(key: String) -> String:
	return TranslationServer.translate(key)


## Budget points are shown as notional millions of dollars (1 point = $5 M).
static func money(points: float) -> String:
	return "$%d %s" % [int(round(points * 5.0)), _t("UNIT_MUSD")]


static func kg(v: float) -> String:
	return "%d %s" % [int(v), _t("UNIT_KG")]


static func kn(newtons: float) -> String:
	return "%d %s" % [int(newtons / 1000.0), _t("UNIT_KN")]


static func sec(v: float) -> String:
	return "%d %s" % [int(v), _t("UNIT_S")]


static func m(v: float) -> String:
	return "%d %s" % [int(v), _t("UNIT_M")]


static func m1(v: float, signed: bool = false) -> String:
	return ("%+.1f %s" if signed else "%.1f %s") % [v, _t("UNIT_M")]


static func ms(v: float, decimals: int = 0, signed: bool = false) -> String:
	var f := "%" + ("+" if signed else "") + "." + str(decimals) + "f %s"
	return f % [v, _t("UNIT_MS")]


static func deg(v: float) -> String:
	return "%+.1f°" % v


static func deg_s(v: float) -> String:
	return "%+.1f %s" % [v, _t("UNIT_DEGS")]


static func kpa(pascal: float) -> String:
	return "%.1f %s" % [pascal / 1000.0, _t("UNIT_KPA")]


static func w(v: float) -> String:
	return "%d %s" % [int(v), _t("UNIT_W")]

