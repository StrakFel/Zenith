extends Node
## Run as a scene so autoloads exist: Godot --headless --path . res://Tools/compile_check.tscn
## Loads every script/scene/shader (except addons, GameMenu) and reports failures.

const DIRS := ["Core", "Core3D", "Menus", "Missions", "Tools"]


func _ready() -> void:
	var bad := 0
	var n := 0
	for d in DIRS:
		for p in _collect("res://" + d):
			if p.ends_with("compile_check.gd"):
				continue
			n += 1
			var r = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
			if r == null or (r is GDScript and not (r as GDScript).can_instantiate() and (r as GDScript).get_instance_base_type() == &"" ):
				print("FAIL ", p)
				bad += 1
	print("compile_check: ", n, " files, failures: ", bad)
	get_tree().quit(bad)


func _collect(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".gdshader"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_collect(dir.path_join(sub)))
	return out
