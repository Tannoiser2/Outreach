extends SceneTree
## Una partita salvata (configurazione + decisioni) si rigioca identica.

func _gioca(cfg: Dictionary, acts: Array) -> ODEngine:
	var e := ODEngine.new()
	e.headless = true
	e.ai_delay = 0.0
	e.anim = 0.0
	e.setup(cfg)
	e.preload_acts = acts
	root.add_child(e)
	await e.run()
	return e


func _init() -> void:
	var ok := 0
	for scn in [1, 4, 5]:
		var seats := []
		var n: int = ODEngine.D.SCENARI[scn]["giocatori"]
		if n == 0:
			n = 2
		for i in n:
			seats.append({"name": "", "ai": true})
		var cfg := {"scenario": scn, "seed": 11, "seats": seats, "opzioni": {"tabelle": "originali"}, "max_turni": 12}
		var a = await _gioca(cfg, [])
		var dati: Dictionary = a.salva()
		var testo := JSON.stringify(dati)
		var letto = JSON.parse_string(testo)
		var cfg2: Dictionary = letto["config"]
		cfg2["scenario"] = int(cfg2["scenario"])
		cfg2["seed"] = int(cfg2["seed"])
		cfg2["max_turni"] = 12
		var acts = str_to_var(str(letto["acts"]))
		var b = await _gioca(cfg2, acts)
		var sa := "%d %s %s" % [a.turn, str(a.porte.keys()), str(a.punti_sistema(0))]
		var sb := "%d %s %s" % [b.turn, str(b.porte.keys()), str(b.punti_sistema(0))]
		print("scenario %d: originale [%s] ricaricata [%s] %s" % [scn, sa.substr(0, 80), sb.substr(0, 80), "UGUALE" if sa == sb else "DIVERSA"])
		if sa == sb:
			ok += 1
	print("salvataggi identici: %d su 3" % ok)
	quit()
