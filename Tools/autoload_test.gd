extends SceneTree
## Prints which autoloads exist in the tree (debug aid).

func _initialize() -> void:
	for n in ["Loc", "GameState", "Router", "Sfx"]:
		print(n, " in tree: ", root.has_node(n))
	var s := load("res://Core/sfx.gd")
	print("sfx script loadable: ", s != null)
	quit()
