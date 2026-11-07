extends SceneTree
## Fotografia dello schermo (serve un display: xvfb-run).
## godot --path . -s tests/foto.gd -- file.png [menu|scenario] [stile] [3d] [secondi] [extra]

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "/tmp/foto.png"
	var cosa: String = a[1] if a.size() > 1 else "menu"
	var stile: String = a[2] if a.size() > 2 else "originale"
	var tre_d: bool = a.size() > 3 and a[3] == "3d"
	var secs: float = float(a[4]) if a.size() > 4 else 6.0
	var extra: String = a[5] if a.size() > 5 else ""
	root.size = Vector2i(1920, 1080)
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	if cosa == "regole":
		main.show_rules()
	elif cosa != "menu":
		var scn := int(cosa)
		var n: int = ODEngine.D.SCENARI[scn]["giocatori"]
		if n == 0:
			n = 3
		var seats := []
		for i in n:
			seats.append({"name": "", "ai": i != 0 or extra == "ia", "level": 1})
		main.start_game({"scenario": scn, "seats": seats, "stile": stile, "anim": 4.0, "ai_delay": 0.05, "seed": 7, "opzioni": {"tabelle": "originali"}})
		await create_timer(1.0).timeout
		if tre_d:
			main.current._cambia_vista()
	await create_timer(secs).timeout
	var g = main.current
	if extra == "tabelle" and g.has_method("_mostra_tabelle"):
		g._mostra_tabelle()
		await create_timer(1.0).timeout
	if extra == "plancia" and g.has_method("_mostra_plancia"):
		g._mostra_plancia()
		await create_timer(1.0).timeout
	if extra == "mossa" and g.has_method("_on_hex"):
		if g.req.get("type", "") == "mossa":
			var lib: Array = g.req["libere"]
			g._on_hex(lib[0])
			await create_timer(0.5).timeout
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out)
	print("SALVATO ", out, " ", img.get_size())
	quit()
