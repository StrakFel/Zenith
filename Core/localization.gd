extends Node
## Autoload "Loc". Builds Translation resources from Strings.all() and registers
## them in TranslationServer. English is the default; the language is changed
## ONLY from the Settings screen (GameState.set_setting("locale", ...)).

const LOCALES: Array[String] = ["en", "uk"]
const LOCALE_NAMES: Dictionary = {"en": "English", "uk": "Українська"}


func _ready() -> void:
	var data := Strings.all()
	for i in LOCALES.size():
		var t := Translation.new()
		t.locale = LOCALES[i]
		for key in data:
			var pair: Array = data[key]
			t.add_message(key, pair[i])
		TranslationServer.add_translation(t)
	TranslationServer.set_locale("en")


func set_locale(locale: String) -> void:
	if not LOCALES.has(locale):
		locale = "en"
	if TranslationServer.get_locale() != locale:
		TranslationServer.set_locale(locale)


func current() -> String:
	var l := TranslationServer.get_locale()
	return "uk" if l.begins_with("uk") else "en"
