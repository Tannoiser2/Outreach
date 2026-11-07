extends Control
## Menu principale: nuova partita (scenario, giocatori, tabelle e varianti, grafica), partite
## online con codice, caricamento di una partita salvata, regole.

const D = preload("res://scripts/data/od_data.gd")

var main
var scenario := 1
var n_seme := 3
var posti: Array = []
var opz = {"tabelle": "originali", "fato_rivisto": false, "conv_rivista": false, "gilham": false, "limite": 0}
var stile := "originale"
var velocita := 1
var corpo: VBoxContainer
var dettaglio: VBoxContainer
var msg: Label
var on_name: LineEdit
var on_code: LineEdit
var on_start: Button
var load_code: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if main.menu_state.has("scenario"):
		scenario = main.menu_state["scenario"]
		opz = main.menu_state["opz"]
		stile = main.menu_state["stile"]
		n_seme = main.menu_state["n_seme"]
		posti = main.menu_state["posti"]
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right"]:
		m.add_theme_constant_override("margin_" + k, 60)
	for k in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + k, 30)
	add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	m.add_child(h)
	# colonna sinistra: logo e voci
	var sx := VBoxContainer.new()
	sx.custom_minimum_size = Vector2(420, 0)
	sx.add_theme_constant_override("separation", 14)
	h.add_child(sx)
	var logo = UI.titolo("OUTREACH", 92)
	sx.add_child(logo)
	sx.add_child(UI.label("La conquista della Galassia, 3000 d.C.", 24, UI.ORO, "intestazione"))
	sx.add_child(UI.label("Simulations Publications, 1976 - versione digitale", 15, UI.TENUE))
	sx.add_child(UI.sep())
	for voce in [["Nuova partita", _mostra_nuova], ["Gioca online", _mostra_online], ["Carica partita", _mostra_carica], ["Regole e tabelle", func(): main.show_rules()]]:
		var b = UI.bottone(voce[0], voce[1], 24)
		b.custom_minimum_size = Vector2(360, 60)
		sx.add_child(b)
	msg = UI.label("", 16, UI.CIANO)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(400, 0)
	sx.add_child(msg)
	var intro = UI.rich("[i]Il capostipide dei giochi 4X: esplorare la Galassia, entrare in contatto con altre civiltà, scegliere se cooperare o combatterle, colonizzare con le StarGate e far crescere la propria civiltà fino ai segreti del Nucleo.[/i]", 15)
	intro.custom_minimum_size = Vector2(400, 0)
	sx.add_child(intro)
	# colonna destra: pannello delle opzioni
	var pan := PanelContainer.new()
	pan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(pan)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pan.add_child(sc)
	corpo = VBoxContainer.new()
	corpo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	corpo.add_theme_constant_override("separation", 10)
	sc.add_child(corpo)
	if not main.lobby.is_empty():
		_mostra_online()
	else:
		_mostra_nuova()


func _say(t: String) -> void:
	if is_instance_valid(msg):
		msg.text = t


func _pulisci() -> void:
	for c in corpo.get_children():
		c.queue_free()


func _memorizza() -> void:
	main.menu_state = {"scenario": scenario, "opz": opz, "stile": stile, "n_seme": n_seme, "posti": posti}


func _n_lati() -> int:
	var n: int = D.SCENARI[scenario]["giocatori"]
	return n if n > 0 else n_seme


func _nomi_lati() -> Array:
	var out := []
	if scenario == 5:
		for i in n_seme:
			out.append(D.NOMI_SEME[i])
	else:
		for l in D.SCENARI[scenario]["lati"]:
			out.append(l["nome"])
	return out


func _sistema_posti() -> void:
	var n = _n_lati()
	while posti.size() < n:
		posti.append({"name": "", "ai": posti.size() > 0})
	while posti.size() > n:
		posti.pop_back()


# ---------------------------------------------------------------- nuova partita

func _mostra_nuova() -> void:
	_pulisci()
	_sistema_posti()
	corpo.add_child(UI.titolo("Nuova partita", 36))
	corpo.add_child(UI.intestazione("Scenario", 22))
	var hs := HFlowContainer.new()
	for k in D.SCENARI:
		var s: Dictionary = D.SCENARI[k]
		var b := Button.new()
		b.text = "%s %s" % [s["numero"], s["titolo"]]
		b.toggle_mode = true
		b.button_pressed = k == scenario
		b.pressed.connect(func():
			scenario = k
			_memorizza()
			_mostra_nuova())
		hs.add_child(b)
	corpo.add_child(hs)
	var s2: Dictionary = D.SCENARI[scenario]
	var info = UI.rich("[i]%s[/i]\n\n[b]Vittoria.[/b] %s" % [s2["intro"], s2["vittoria"]], 16)
	info.custom_minimum_size = Vector2(800, 0)
	corpo.add_child(info)
	if scenario == 5:
		var r := HBoxContainer.new()
		r.add_child(UI.label("Numero di civiltà: ", 17))
		var sb := SpinBox.new()
		sb.min_value = 1
		sb.max_value = 4
		sb.value = n_seme
		sb.value_changed.connect(func(v):
			n_seme = int(v)
			_memorizza()
			_mostra_nuova())
		r.add_child(sb)
		r.add_child(UI.label("   Limite di turni (0 = nessuno): ", 17))
		var sl := SpinBox.new()
		sl.min_value = 0
		sl.max_value = 200
		sl.value = int(opz.get("limite", 0))
		sl.value_changed.connect(func(v): opz["limite"] = int(v))
		r.add_child(sl)
		corpo.add_child(r)
	corpo.add_child(UI.intestazione("Giocatori", 22))
	var nomi = _nomi_lati()
	for i in _n_lati():
		var r2 := HBoxContainer.new()
		r2.add_theme_constant_override("separation", 10)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(20, 20)
		dot.color = D.TINTE[i]
		r2.add_child(dot)
		var l = UI.label(nomi[i], 18)
		l.custom_minimum_size = Vector2(230, 0)
		r2.add_child(l)
		var ob := OptionButton.new()
		ob.add_item("Persona")
		ob.add_item("Computer")
		ob.selected = 1 if posti[i]["ai"] else 0
		ob.item_selected.connect(func(x): posti[i]["ai"] = x == 1)
		r2.add_child(ob)
		var le := LineEdit.new()
		le.placeholder_text = "nome (facoltativo)"
		le.text = str(posti[i]["name"])
		le.custom_minimum_size = Vector2(220, 0)
		le.text_changed.connect(func(t): posti[i]["name"] = t)
		r2.add_child(le)
		corpo.add_child(r2)
	_opzioni(corpo)
	var go = UI.bottone("Inizia la partita", _inizia, 24)
	go.custom_minimum_size = Vector2(320, 60)
	corpo.add_child(go)


func _opzioni(dove: VBoxContainer) -> void:
	dove.add_child(UI.intestazione("Tabelle e varianti", 22))
	var r := HBoxContainer.new()
	r.add_child(UI.label("Tabelle: ", 17))
	var ob := OptionButton.new()
	var chiavi = ["originali", "skygazer", "v3"]
	for t in ["Originali (1976)", "Dispersione riveduta (SkyGazer)", "Rivedute versione 3 (dispersione, conflitto, conversione)"]:
		ob.add_item(t)
	ob.selected = maxi(0, chiavi.find(str(opz.get("tabelle", "originali"))))
	ob.item_selected.connect(func(x): opz["tabelle"] = chiavi[x])
	r.add_child(ob)
	dove.add_child(r)
	for v in [["fato_rivisto", "Tabella del Fato riveduta"], ["conv_rivista", "Tabella di conversione delle percentuali riveduta"], ["gilham", "Sistema del Fato alternativo (Gilham, Phoenix n. 11): punti civiltà"]]:
		var cb := CheckBox.new()
		cb.text = v[1]
		cb.button_pressed = opz.get(v[0], false)
		cb.toggled.connect(func(x): opz[v[0]] = x)
		dove.add_child(cb)
	var r2 := HBoxContainer.new()
	r2.add_child(UI.label("Grafica: ", 17))
	var og := OptionButton.new()
	og.add_item("Originale (mappa e pedine SPI)")
	og.add_item("Reborn (griglia, galassia e pedine nuove)")
	og.selected = 1 if stile == "reborn" else 0
	og.item_selected.connect(func(x): stile = "reborn" if x == 1 else "originale")
	r2.add_child(og)
	r2.add_child(UI.label("   Animazioni: ", 17))
	var ov := OptionButton.new()
	for t in ["lente", "normali", "veloci"]:
		ov.add_item(t)
	ov.selected = velocita
	ov.item_selected.connect(func(x): velocita = x)
	r2.add_child(ov)
	dove.add_child(r2)


func _config() -> Dictionary:
	_sistema_posti()
	var seats := []
	for p in posti:
		seats.append({"name": str(p["name"]).strip_edges(), "ai": bool(p["ai"]), "level": 1})
	return {"scenario": scenario, "seats": seats, "opzioni": opz.duplicate(), "stile": stile,
		"seed": 1 + randi() % 2000000000, "anim": [0.6, 1.0, 2.0][velocita], "ai_delay": [0.8, 0.4, 0.15][velocita]}


func _inizia() -> void:
	_memorizza()
	main.start_game(_config())


# ---------------------------------------------------------------- caricamento

func _mostra_carica() -> void:
	_pulisci()
	corpo.add_child(UI.titolo("Carica partita", 36))
	corpo.add_child(UI.label("Scrivi il codice di sei lettere che hai ricevuto al salvataggio.", 17))
	load_code = LineEdit.new()
	load_code.max_length = 6
	load_code.custom_minimum_size = Vector2(240, 50)
	load_code.add_theme_font_size_override("font_size", 28)
	corpo.add_child(load_code)
	corpo.add_child(UI.bottone("Carica", _carica, 22))


func _carica() -> void:
	var c = load_code.text.strip_edges().to_upper()
	if c.length() != 6:
		_say("Il codice ha sei lettere.")
		return
	_say("Carico la partita %s..." % c)
	var net: Net = main.get_net()
	var d = await net.load_game(c)
	if d.is_empty() or not d.has("json"):
		_say("Partita %s non trovata.%s" % [c, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	var dati = JSON.parse_string(str(d["json"]))
	if not (dati is Dictionary):
		_say("Salvataggio non leggibile.")
		return
	var cfg: Dictionary = dati["config"]
	cfg["acts"] = str_to_var(str(dati["acts"]))
	cfg["codice"] = c
	cfg["scenario"] = int(cfg["scenario"])
	cfg["seed"] = int(cfg["seed"])
	main.start_game(cfg)


# ---------------------------------------------------------------- online

func _mostra_online() -> void:
	_pulisci()
	_sistema_posti()
	corpo.add_child(UI.titolo("Gioca online", 36))
	corpo.add_child(UI.label("Chi crea la stanza sceglie scenario e regole e gioca il primo lato; gli altri entrano con il codice. I posti vuoti li gioca il computer.", 16, UI.TENUE))
	var r := HBoxContainer.new()
	r.add_child(UI.label("Il tuo nome: ", 18))
	on_name = LineEdit.new()
	on_name.custom_minimum_size = Vector2(260, 0)
	var net: Net = main.get_net()
	on_name.text = str(net.load_session().get("name", ""))
	r.add_child(on_name)
	corpo.add_child(r)
	corpo.add_child(UI.intestazione("Crea una stanza", 22))
	corpo.add_child(UI.label("Scenario: %s %s (si cambia in Nuova partita)" % [D.SCENARI[scenario]["numero"], D.SCENARI[scenario]["titolo"]], 16))
	_opzioni(corpo)
	corpo.add_child(UI.bottone("Crea la stanza", _crea, 20))
	corpo.add_child(UI.sep())
	corpo.add_child(UI.intestazione("Entra in una stanza", 22))
	var r2 := HBoxContainer.new()
	r2.add_child(UI.label("Codice: ", 18))
	on_code = LineEdit.new()
	on_code.max_length = 4
	on_code.custom_minimum_size = Vector2(160, 0)
	r2.add_child(on_code)
	r2.add_child(UI.bottone("Entra", _entra, 20))
	corpo.add_child(r2)
	on_start = UI.bottone("Inizia online", _avvia, 24)
	on_start.visible = main.lobby.get("role", "") == "host"
	corpo.add_child(on_start)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		_attesa(main.lobby["code"])


func _crea() -> void:
	var nm = on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	_memorizza()
	var seats := []
	for i in _n_lati():
		seats.append(i)
	_say("Creo la stanza...")
	var net: Net = main.get_net()
	var code = await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": 0}
	net.remember_room(code, 0)
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_attesa(code)


func _entra() -> void:
	var code = on_code.text.strip_edges().to_upper()
	var nm = on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s..." % code)
	var net: Net = main.get_net()
	var s = await net.join_room(code, nm)
	if s == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if s == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": s}
	net.remember_room(code, s)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s..." % code)
		_avvio(room["game"], true)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_attesa(code)


func _posti_testo(room: Dictionary) -> String:
	var sd = Net._as_dict(room.get("seats", {}))
	var out := []
	var nomi = _nomi_lati()
	for i in nomi.size():
		var k := str(i)
		if sd.has(k) and sd[k] is Dictionary:
			out.append("%s: %s" % [nomi[i], sd[k].get("name", "?")])
		else:
			out.append("%s: libero (computer)" % nomi[i])
	return ", ".join(out)


func _attesa(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room = await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice ai tuoi amici.\nPosti: %s.\nQuando ci sono tutti premi Inizia online." % [code, _posti_testo(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_avvio(room["game"], false)
				return
			_say("Sei nella stanza [ %s ]. Aspetta che chi l'ha creata avvii la partita." % code)
		await get_tree().create_timer(2.0).timeout


func _avvia() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room = await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var sd = Net._as_dict(room.get("seats", {}))
	var cfg = _config()
	for i in cfg["seats"].size():
		var k := str(i)
		if sd.has(k) and sd[k] is Dictionary:
			cfg["seats"][i]["name"] = str(sd[k].get("name", ""))
			cfg["seats"][i]["ai"] = false
		else:
			cfg["seats"][i]["ai"] = true
	var g = {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_avvio(g, false)


func _avvio(g: Dictionary, rientro: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rientro:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	cfg["stile"] = stile
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)
