extends SceneTree
## Carica ogni script del progetto: un errore di sintassi o di tipo compare qui.
func _init() -> void:
	var n := 0
	for dir in ["res://scripts/core", "res://scripts/data", "res://scripts/ui", "res://scripts/net"]:
		var d = DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".gd"):
				var s = load(dir + "/" + f)
				n += 1
				if s == null:
					print("ERRORE nel caricamento di ", dir, "/", f)
	print("script caricati: ", n)
	quit()
