extends SceneTree
## Prints what TranslationServer does after switching locale (debug aid).

func _initialize() -> void:
	print("loaded: ", TranslationServer.get_loaded_locales())
	print("start locale: ", TranslationServer.get_locale(), " -> ", TranslationServer.translate("MENU_PLAY"))
	var gs := root.get_node("GameState")
	print("saved locale setting: ", gs.settings["locale"])
	gs.set_setting("locale", "uk")
	print("after set uk: ", TranslationServer.get_locale(), " -> ", TranslationServer.translate("MENU_PLAY"))
	gs.set_setting("locale", "en")
	print("after set en: ", TranslationServer.get_locale(), " -> ", TranslationServer.translate("MENU_PLAY"))
	quit()
