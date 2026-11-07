extends SceneTree
## Fotografia dello schermo (serve un display: xvfb-run).
## godot --path . -s tests/foto.gd -- file.png [menu|scenario] [stile] [3d] [secondi] [extra]

func _init() -> void:
	var a = OS.get_cmdline_user_args()
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
	if extra == "senzamappa":
		g.opac["3d"]["mappa"] = 0.0
		g._aggiorna_cursori()
		await create_timer(0.5).timeout
	if extra == "vicino":
		g.b3.dist = 14.0
		g.b3.pitch = 0.6
		g.b3._camera()
		await create_timer(0.5).timeout
	if extra == "tocco":
		var b3 = g.b3
		var y0: float = b3.yaw
		var d0: float = b3.dist
		var t1 = InputEventScreenTouch.new(); t1.index = 0; t1.pressed = true; t1.position = Vector2(400, 400)
		var t2 = InputEventScreenTouch.new(); t2.index = 1; t2.pressed = true; t2.position = Vector2(600, 400)
		b3._gui_input(t1); b3._gui_input(t2)
		var dr = InputEventScreenDrag.new(); dr.index = 1; dr.position = Vector2(650, 500)
		b3._gui_input(dr)
		print("tocco 3D: zoom %s, rotazione %s" % ["OK" if b3.dist != d0 else "NO", "OK" if b3.yaw != y0 else "NO"])
		var b2 = g.b2
		var z0: float = b2.zoom
		b2._gui_input(t1); b2._gui_input(t2)
		b2._gui_input(dr)
		print("tocco 2D: zoom %s" % ["OK" if b2.zoom != z0 else "NO"])
	if extra == "fili":
		# balzi di prova per vedere i fili d'argento e le stelle faro
		g.b3.dist = 26.0
		g.b3.pitch = 0.7
		g.b3.target = g.b3.pos(1215)
		g.b3._camera()
		for m in [[1316, 1118, 0, ""], [813, 1212, 1, ""], [1312, 1709, 2, ""], [1018, 920, 3, "d"]]:
			var dati = {"o": m[2], "da": m[0], "a": m[1]}
			if m[3] == "d":
				dati["h"] = 1022
			g.b3.effetto("disperso" if m[3] == "d" else "salto", dati)
			g.b2.effetto("disperso" if m[3] == "d" else "salto", dati)
		for k in 22:
			await process_frame
		print("fili attivi: ", g.b3._fili.size())
	var img = root.get_viewport().get_texture().get_image()
	img.save_png(out)
	print("SALVATO ", out, " ", img.get_size())
	quit()
