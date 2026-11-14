extends SceneTree
## Localization audit: every "KEY_LIKE" string literal used in the code must exist in
## Strings.all() with a non-empty English and Ukrainian text; reports unused keys too.
##   Godot --headless --path . --script res://Tools/check_strings.gd

func _initialize() -> void:
	var data: Dictionary = Strings.all()
	var re := RegEx.new()
	re.compile("\"([A-Z][A-Z0-9]*_[A-Z0-9_]+)\"")
	var used: Dictionary = {}
	var files: Array[String] = []
	_scan("res://", files)
	for f in files:
		var txt := FileAccess.get_file_as_string(f)
		for m in re.search_all(txt):
			used[m.get_string(1)] = f
	var missing := 0
	for k in used:
		if not data.has(k) and not str(used[k]).contains("strings_") and not str(used[k]).contains("Tools/"):
			print("MISSING: ", k, "   (", used[k], ")")
			missing += 1
	var bad := 0
	for k in data:
		var pair: Array = data[k]
		if pair.size() != 2 or str(pair[0]) == "" or str(pair[1]) == "":
			print("BAD PAIR: ", k)
			bad += 1
	var unused := 0
	for k in data:
		if not used.has(k):
			unused += 1
			print("unused: ", k)
	print("keys=", data.size(), " missing=", missing, " bad=", bad, " unused=", unused)
	quit(0 if missing == 0 and bad == 0 else 1)


func _scan(dir: String, out: Array[String]) -> void:
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d == "addons":
			continue
		_scan(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
