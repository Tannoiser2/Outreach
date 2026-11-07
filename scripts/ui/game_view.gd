extends Control
## Schermata di gioco: mappa (2D o 3D) a sinistra, pannello a destra con lo stato dei giocatori,
## la decisione da prendere e il registro degli eventi.

const D = preload("res://scripts/data/od_data.gd")
const Board2D = preload("res://scripts/ui/board2d.gd")
const Board3D = preload("res://scripts/ui/board3d.gd")

var main
var config := {}
var eng: ODEngine
var b2: Board2D
var b3: Board3D
var vista3d := false
var vista := 0
var req := {}
var azione: VBoxContainer
var registro: RichTextLabel
var testa: Label
var info: VBoxContainer
var stato_lbl: Label
var tendina: Control
var finestra: PanelContainer
var barra: HBoxContainer
var online = null
var mio_posto := -1
var replay := false
var _ultimo_umano := -1
# stato delle scelte in corso
var sel := -1
var dest := -1
var forza := {"r": 0, "d": 0, "e": 0}
var prendi_sag := false
var spin := {}
var azioni_ris: Array = []
var stato_ris := {}
var hex_ris := -1
var _scelte := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Grafica.stile = str(config.get("stile", "originale"))
	online = config.get("online", null)
	config.erase("online")
	if online != null:
		add_child(online)
		mio_posto = online.seat
	var bg := ColorRect.new()
	bg.color = UI.SPAZIO
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 0)
	add_child(h)
	var area := Control.new()
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.clip_contents = true
	h.add_child(area)
	b2 = Board2D.new()
	b2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.add_child(b2)
	b3 = Board3D.new()
	b3.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b3.visible = false
	area.add_child(b3)
	b2.hex_clicked.connect(_on_hex)
	b3.hex_clicked.connect(_on_hex)
	b2.hex_hovered.connect(_on_hover)
	b3.hex_hovered.connect(_on_hover)
	_barra(area)
	stato_lbl = UI.label("", 15, UI.TESTO)
	stato_lbl.position = Vector2(12, 56)
	stato_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	stato_lbl.add_theme_constant_override("outline_size", 6)
	area.add_child(stato_lbl)
	# pannello laterale
	var lato := PanelContainer.new()
	lato.custom_minimum_size = Vector2(500, 0)
	h.add_child(lato)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	lato.add_child(v)
	testa = UI.titolo("OUTREACH", 26)
	v.add_child(testa)
	info = VBoxContainer.new()
	v.add_child(info)
	v.add_child(UI.sep())
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_stretch_ratio = 1.4
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	azione = VBoxContainer.new()
	azione.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	azione.add_theme_constant_override("separation", 6)
	sc.add_child(azione)
	v.add_child(UI.sep())
	registro = RichTextLabel.new()
	registro.bbcode_enabled = true
	registro.scroll_following = true
	registro.size_flags_vertical = Control.SIZE_EXPAND_FILL
	registro.add_theme_font_size_override("normal_font_size", 14)
	registro.add_theme_font_size_override("bold_font_size", 14)
	v.add_child(registro)
	# il motore
	eng = ODEngine.new()
	eng.ai_delay = float(config.get("ai_delay", 0.4))
	eng.anim = float(config.get("anim", 1.0))
	eng.setup(config)
	if config.has("acts"):
		eng.preload_acts = config["acts"]
	add_child(eng)
	eng.changed.connect(_aggiorna)
	eng.log_added.connect(_on_log)
	eng.decision_requested.connect(_on_decisione)
	eng.game_ended.connect(_on_fine)
	eng.fx.connect(_on_fx)
	b2.eng = eng
	b3.eng = eng
	replay = config.get("replay", false)
	eng.replay_lento = replay
	if replay:
		vista = -1
		b2.tutto_visibile = true
		b3.tutto_visibile = true
	else:
		vista = _primo_umano()
	if online != null:
		eng.online = online
		online.view = self
		vista = mio_posto
		online.setup_done(eng)
	_imposta_vista(vista)
	await get_tree().process_frame
	b2.adatta()
	var mie = eng.porte_di(maxi(0, vista))
	if not mie.is_empty():
		b2.centra_su(mie[0], maxf(b2.zoom * 2.5, 0.22))
		b3.centra_su(mie[0])
	_aggiorna()
	_azione_attesa()
	await eng.run()


func _primo_umano() -> int:
	for i in eng.players.size():
		if not eng.players[i]["ai"]:
			return i
	return -1


func _imposta_vista(s: int) -> void:
	vista = s
	b2.vista = s
	b3.vista = s
	_aggiorna()


# ---------------------------------------------------------------- barra degli strumenti

func _barra(area: Control) -> void:
	barra = HBoxContainer.new()
	barra.position = Vector2(10, 10)
	barra.add_theme_constant_override("separation", 6)
	area.add_child(barra)
	barra.add_child(UI.bottone("3D", _cambia_vista, 15))
	barra.add_child(UI.bottone("Nuvola", _cambia_nuvola, 15))
	barra.add_child(UI.bottone("Grafica", _cambia_grafica, 15))
	barra.add_child(UI.bottone("Plancia", _mostra_plancia, 15))
	barra.add_child(UI.bottone("Tabelle", _mostra_tabelle, 15))
	barra.add_child(UI.bottone("Regole", _mostra_regole, 15))
	barra.add_child(UI.bottone("Salva", _salva, 15))
	barra.add_child(UI.bottone("Menu", _esci, 15))


func _cambia_vista() -> void:
	vista3d = not vista3d
	b2.visible = not vista3d
	b3.visible = vista3d
	(barra.get_child(0) as Button).text = "2D" if vista3d else "3D"
	if vista3d:
		b3.aggiorna()


func _cambia_nuvola() -> void:
	b2.nuvola = not b2.nuvola
	b3.set_nuvola(not b3.nuvola)
	b2.queue_redraw()


func _cambia_grafica() -> void:
	Grafica.stile = "reborn" if Grafica.stile == "originale" else "originale"
	b2.ricarica()
	b2.adatta()
	b3.ricarica()
	_messaggio("Grafica: %s%s" % [Grafica.stile, "" if Grafica.reborn_disponibile() or Grafica.stile == "originale" else " (pedine Reborn non ancora presenti: si usano le originali sulla griglia nuova)"])


func _esci() -> void:
	eng.abort = true
	if online != null:
		online.alive = false
	main.show_menu()


func _messaggio(t: String) -> void:
	registro.append_text("\n[color=#7fb7d0]%s[/color]" % t)


# ---------------------------------------------------------------- aggiornamento

func _aggiorna() -> void:
	if eng == null:
		return
	testa.text = "Turno %d - %s" % [eng.turn, _nome_fase(eng.phase)]
	for c in info.get_children():
		c.queue_free()
	for i in eng.players.size():
		var p: Dictionary = eng.players[i]
		var r := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.color = D.TINTE[i]
		r.add_child(dot)
		var mio := replay or i == vista or vista < 0
		var testo = "%s%s  civiltà %d" % [p["fazione"], "" if p["name"] == "" else " (%s)" % p["name"], eng.cl(i)]
		if mio:
			testo += "  sistema %d  risorse %d" % [eng.punti_sistema(i), p["rp"]]
			if eng.opz.get("gilham", false):
				testo += "  PC %d" % p["cp"]
			if not p["sag"].is_empty() or p["x"]:
				testo += "  saggezza %d%s" % [p["sag"].size(), " +X" if p["x"] else ""]
		else:
			testo += "  porte %d" % eng.porte_di(i).size()
		if not p["vivo"]:
			testo += "  (eliminato)"
		if p["ai"]:
			testo += "  [IA]"
		var l = UI.label(testo, 14, UI.TESTO if p["vivo"] else UI.TENUE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		info.add_child(r)
	var aut_txt := []
	for i in 4:
		if eng.aut[i]["presente"]:
			aut_txt.append("%s%s" % [D.COLORI_AUT[i], " (attiva)" if eng.aut[i]["attiva"] else ""])
	if not aut_txt.is_empty():
		info.add_child(UI.label("Forze autonome: " + ", ".join(aut_txt), 13, UI.TENUE))
	if not eng.ordine.is_empty():
		info.add_child(UI.label("Ordine: " + ", ".join(eng.ordine.map(func(x): return eng.fazione(x))), 13, UI.TENUE))
	b2.queue_redraw()
	if vista3d:
		b3.aggiorna()


func _nome_fase(f: String) -> String:
	return {"ordine": "ordine di spostamento", "spostamento": "spostamenti", "autonomi": "forze autonome",
		"riserva": "spostamenti di riserva", "esplorazione": "esplorazione", "contatto": "contatto",
		"interazione": "interazione", "conflitto": "conflitto", "riduzione": "riduzione", "fato": "fato",
		"risorse": "risorse", "schieramento": "schieramento iniziale", "fine": "partita finita"}.get(f, f)


func _on_log(e: Dictionary) -> void:
	var s := int(e["solo"])
	var t: String = e["t"]
	if s >= 0 and not replay and s != vista and vista >= 0:
		t = str(e["pub"])
		if t == "":
			return
	if t.begins_with("—"):
		registro.append_text("\n[color=#f2a83a][b]%s[/b][/color]" % t)
	elif t.begins_with("FINE"):
		registro.append_text("\n[color=#f2a83a][b]%s[/b][/color]" % t)
	else:
		registro.append_text("\n" + t)


func _on_fx(kind: String, data: Dictionary) -> void:
	b2.effetto(kind, data)
	if vista3d:
		b3.effetto(kind, data)
		b3.aggiorna()


func _on_hover(h: int) -> void:
	if h <= 0:
		stato_lbl.text = ""
		return
	var t = "%s  %s" % [D.nome(h), {"A": "asse della spirale", "F": "frangia della spirale", "I": "spazio interspirale", "N": "Nucleo galattico", "W": "centro del Nucleo"}.get(D.terreno(h), "")]
	var nf := D.faro_stampato(h)
	if nf != "":
		t += "  stella faro: " + nf
	elif eng.fari.has(h):
		t += "  stella faro scoperta"
	var v = eng.pv_noto(h, vista) if vista >= 0 else eng.valore_pv(h)
	if replay:
		v = eng.valore_pv(h)
	if v >= 0:
		t += "  potenziale %d" % v
	var g = eng.porta(h)
	if not g.is_empty():
		if g["neut"]:
			t += "  porta neutralizzata (%s)" % eng.fazione(int(g.get("prima", -1)))
		else:
			t += "  porta di %s" % eng.fazione(int(g["o"]))
	for o in eng.proprietari(h):
		t += "  | " + eng.fazione(o)
		if o == vista or replay or (o >= 10 and int(eng.aut[o - 10]["custode"]) == vista):
			var st = eng.stack(h, o)
			t += " %dr %dd %de" % [st["r"], st["d"], st["e"]]
	if eng.contatti.has(h):
		t += "  [contatto]"
	if sel > 0 and req.get("type", "") in ["mossa", "prosegui"] and h != sel:
		var ri = eng.rischio(int(req["seat"]), sel, h, forza)
		t += "\nDistanza %d, raggio di sicurezza %d" % [ri["dist"], eng.clr(int(req["seat"]))]
		if int(ri["rischio"]) > 0:
			t += ", dispersione possibile con %d risultati su 6 (modificatore %+d)" % [ri["rischio"], ri["mod"]]
	stato_lbl.text = t


# ---------------------------------------------------------------- decisioni

func _azione_attesa(testo := "") -> void:
	for c in azione.get_children():
		c.queue_free()
	if testo == "":
		testo = "Attendere: gioca %s." % ("il computer" if eng.humans() == 0 else "un altro giocatore") if not eng.over else ""
	if testo != "":
		azione.add_child(UI.label(testo, 15, UI.TENUE))
	b2.bersagli = {}
	b2.selezionato = -1
	b3.set_evidenziati({}, -1)


func _on_decisione(r: Dictionary) -> void:
	req = r
	var s := int(r["seat"])
	sel = -1
	dest = -1
	if online == null and eng.humans() > 1 and s != _ultimo_umano:
		_ultimo_umano = s
		_tendina(s)
		return
	_ultimo_umano = s
	if vista != s and not replay:
		_imposta_vista(s)
	_costruisci()


func _tendina(s: int) -> void:
	_imposta_vista(-2)
	for c in azione.get_children():
		c.queue_free()
	tendina = PanelContainer.new()
	tendina.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.02, 0.02, 0.04, 0.97)
	tendina.add_theme_stylebox_override("panel", st)
	add_child(tendina)
	var c := CenterContainer.new()
	tendina.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	c.add_child(v)
	v.add_child(UI.titolo("Tocca a %s" % eng.pname(s), 40))
	v.add_child(UI.label("Passate il dispositivo: le informazioni segrete degli altri sono nascoste.", 18, UI.TENUE))
	v.add_child(UI.bottone("Sono pronto", func():
		tendina.queue_free()
		tendina = null
		_imposta_vista(s)
		_costruisci(), 22))


func _invia(r) -> void:
	req = {}
	_azione_attesa()
	eng.provide_decision(r)


func _costruisci() -> void:
	for c in azione.get_children():
		c.queue_free()
	b2.bersagli = {}
	b2.selezionato = -1
	var tipo := str(req.get("type", ""))
	var s := int(req["seat"])
	azione.add_child(UI.intestazione(eng.fazione(s), 20))
	match tipo:
		"mossa":
			_ui_mossa()
		"prosegui":
			_ui_prosegui()
		"esplora":
			_ui_esplora()
		"contatto":
			_ui_contatto()
		"interazione":
			_ui_interazione()
		"attacco":
			_ui_attacco()
		"bersaglio":
			_ui_bersaglio()
		"riduzione":
			_ui_riduzione()
		"fato":
			_ui_fato()
		"dissoluzione":
			_ui_dissoluzione()
		"risorse", "schieramento":
			_ui_risorse(tipo == "schieramento")
	_evidenzia()


func _evidenzia() -> void:
	b2.selezionato = sel
	b3.set_evidenziati(b2.bersagli, sel)
	b2.queue_redraw()


func _testo(t: String, size := 15, col := UI.TESTO) -> Label:
	var l := UI.label(t, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(440, 0)
	return l


func _on_hex(h: int) -> void:
	var tipo := str(req.get("type", ""))
	match tipo:
		"mossa":
			var lib: Array = req["libere"]
			if h in lib and (sel < 0 or dest < 0 or h == sel):
				sel = h
				dest = -1
				forza = eng.liberi(h, int(req["seat"]))
				prendi_sag = eng.sag_centro.has(h)
				_costruisci()
			elif sel > 0 and h != sel:
				dest = h
				_costruisci()
			elif h in lib:
				sel = h
				dest = -1
				forza = eng.liberi(h, int(req["seat"]))
				_costruisci()
		"prosegui":
			if h != int(req["da"]):
				dest = h
				_costruisci()
		"risorse", "schieramento":
			hex_ris = h
			_costruisci()


# ---------- spostamenti

func _ui_mossa() -> void:
	var s := int(req["seat"])
	var riserva: bool = req.get("riserva", false)
	azione.add_child(_testo("Spostamento %s. Raggio di sicurezza: %d esagoni.%s" % ["di riserva (una sola forza, entro il raggio)" if riserva else "regolare", eng.clr(s), "" if not riserva else ""], 15))
	for h in req["libere"]:
		b2.bersagli[h] = Color(UI.AMBRA, 0.6)
	if sel < 0:
		azione.add_child(_testo("Scegli sulla mappa un esagono con flotte che non si sono ancora spostate (evidenziati), poi la destinazione.", 14, UI.TENUE))
	else:
		sel = sel
		var lib = eng.liberi(sel, s)
		azione.add_child(_testo("Forza in %s:" % D.nome(sel), 15, UI.ORO))
		for k in ["r", "d", "e"]:
			if int(lib[k]) <= 0:
				forza[k] = 0
				continue
			var r := HBoxContainer.new()
			r.add_child(UI.label(D.NOME_FLOTTE[k].capitalize(), 15))
			var sb := SpinBox.new()
			sb.min_value = 0
			sb.max_value = int(lib[k])
			sb.value = int(forza.get(k, lib[k]))
			sb.value_changed.connect(func(v): forza[k] = int(v))
			r.add_child(sb)
			r.add_child(UI.label("su %d" % lib[k], 14, UI.TENUE))
			azione.add_child(r)
		if eng.sag_centro.has(sel) and eng.usa_saggezza_in_gioco():
			var cb := CheckBox.new()
			cb.text = "Prendi il gettone saggezza del centro"
			cb.button_pressed = prendi_sag
			cb.toggled.connect(func(v): prendi_sag = v)
			azione.add_child(cb)
		_mete(s, sel, riserva)
		if dest > 0:
			var err = eng.mossa_valida(s, sel, dest, forza, riserva)
			var ri = eng.rischio(s, sel, dest, forza)
			azione.add_child(_testo("Destinazione %s: distanza %d." % [D.nome(dest), ri["dist"]], 15, UI.ORO))
			if err != "":
				azione.add_child(_testo(err, 14, UI.ROSSO))
			else:
				if int(ri["rischio"]) > 0:
					azione.add_child(_testo("Rischio di dispersione: %d risultati su 6 (modificatore %+d)%s." % [ri["rischio"], ri["mod"], ", perdite raddoppiate perché oltre il raggio" if ri["oltre"] else ""], 14, UI.ROSSO))
				else:
					azione.add_child(_testo("Nessun rischio di dispersione.", 14, UI.VERDE))
				azione.add_child(UI.bottone("Salta", func():
					var out := forza.duplicate()
					out["da"] = sel
					out["a"] = dest
					out["sag"] = 1 if prendi_sag and eng.sag_centro.has(sel) else 0
					_invia(out)))
	azione.add_child(UI.sep())
	azione.add_child(UI.bottone("Fine degli spostamenti" if not riserva else "Nessuno spostamento di riserva", func(): _invia({"fine": true})))


func _mete(s: int, da: int, riserva: bool) -> void:
	var raggio := maxi(1, eng.clr(s))
	var portata = raggio if riserva or not eng.porta_utile(da, s) else maxi(raggio, 8)
	var c0 := D.col(da)
	var r0 := D.row(da)
	for c in range(c0 - portata, c0 + portata + 1):
		for rr in range(r0 - portata, r0 + portata + 1):
			var h := D.hx(c, rr)
			if h == da or not D.esiste(h) or D.distanza(da, h) > portata:
				continue
			if eng.mossa_valida(s, da, h, forza, riserva) != "":
				continue
			var ri = eng.rischio(s, da, h, forza)
			var k := int(ri["rischio"])
			b2.bersagli[h] = Color(0.4, 0.9, 1.0, 0.55) if k == 0 else Color(1.0, 0.75 - k * 0.1, 0.3, 0.55)
	if dest > 0:
		b2.bersagli[dest] = Color(1, 1, 1, 0.95)


func _ui_prosegui() -> void:
	var s := int(req["seat"])
	var da := int(req["da"])
	sel = da
	forza = req["forza"]
	azione.add_child(_testo("La forza è arrivata a una porta amica in %s entro il raggio: può proseguire con un altro salto." % D.nome(da), 15))
	_mete(s, da, req.get("riserva", false))
	if dest > 0:
		var err = eng.mossa_valida(s, da, dest, forza, req.get("riserva", false), true)
		if err != "":
			azione.add_child(_testo(err, 14, UI.ROSSO))
		else:
			var ri = eng.rischio(s, da, dest, forza)
			azione.add_child(_testo("Verso %s: distanza %d, rischio %d su 6." % [D.nome(dest), ri["dist"], ri["rischio"]], 14))
			azione.add_child(UI.bottone("Prosegui", func(): _invia({"a": dest})))
	azione.add_child(UI.bottone("Fermati qui", func(): _invia({"fine": true})))


# ---------- esplorazione

func _ui_esplora() -> void:
	azione.add_child(_testo("Esplorazione: scegli gli esagoni da esplorare (le esploratrici contano doppio).", 15))
	_scelte.clear()
	for h in req["esagoni"]:
		_scelte[h] = true
		b2.bersagli[h] = Color(0.5, 0.9, 1.0, 0.7)
		var st = eng.stack(h, int(req["seat"]))
		var n = 2 * int(st["e"]) + int(st["r"]) + int(st["d"])
		var col := D.col_esplorazione(n)
		var cb := CheckBox.new()
		cb.text = "%s  (%s, flotte corrette %d: riesce con %d o meno)" % [D.nome(h), {"A": "asse", "F": "frangia", "I": "interspirale"}.get(D.terreno(h), ""), n, col + 1]
		cb.button_pressed = true
		cb.toggled.connect(func(v): _scelte[h] = v)
		azione.add_child(cb)
	azione.add_child(UI.bottone("Esplora", func():
		var out := []
		for h in _scelte:
			if _scelte[h]:
				out.append(h)
		_invia(out)))


# ---------- contatto

func _ui_contatto() -> void:
	azione.add_child(_testo("Contatto: per ogni esagono scegli l'indice di contatto. Più è alto, più è probabile accorgersi degli altri (si può cercare o evitare il contatto).", 15))
	_scelte.clear()
	for c in req["casi"]:
		var h := int(c["h"])
		b2.bersagli[h] = Color(UI.AMBRA, 0.8)
		_scelte[h] = int(c["max"])
		var altri: Array = c["altri"]
		azione.add_child(_testo("%s con %s" % [D.nome(h), ", ".join(altri.map(func(x): return eng.fazione(x)))], 15, UI.ORO))
		var r := HBoxContainer.new()
		var sl := HSlider.new()
		sl.min_value = int(c["min"])
		sl.max_value = int(c["max"])
		sl.value = int(c["max"])
		sl.step = 1
		sl.custom_minimum_size = Vector2(260, 24)
		var lab := UI.label("", 15)
		var aggiorna := func(v):
			_scelte[h] = int(v)
			lab.text = "indice %d: contatto con %d o meno" % [int(v), D.col_contatto(int(v))]
		sl.value_changed.connect(aggiorna)
		aggiorna.call(sl.value)
		r.add_child(sl)
		r.add_child(lab)
		azione.add_child(r)
	azione.add_child(UI.bottone("Conferma", func(): _invia(_scelte.duplicate())))


# ---------- interazione

func _ui_interazione() -> void:
	var s := int(req["seat"])
	azione.add_child(_testo("Interazione: scegli l'opzione verso ogni parte con cui sei in contatto. A cooperativa, B neutrale, C ostile. Le scelte sono segrete e simultanee.", 15))
	_scelte.clear()
	for o in req["parti"]:
		var att := str(req["attuali"].get(o, ""))
		_scelte[o] = att if att != "" else "B"
		var loro := str(req["loro"].get(o, ""))
		azione.add_child(_testo("%s%s  (verso di te: %s)" % [eng.fazione(o), "  - primo contatto" if o in req["nuovi"] else "", loro if loro != "" else "non ancora noto"], 15, UI.ORO))
		var r := HBoxContainer.new()
		var gruppo := ButtonGroup.new()
		for k in ["A", "B", "C"]:
			var b := Button.new()
			b.text = {"A": "A cooperativa", "B": "B neutrale", "C": "C ostile"}[k]
			b.toggle_mode = true
			b.button_group = gruppo
			b.button_pressed = _scelte[o] == k
			if k == "C" and eng.players[s]["x"] and str(eng.sc.get("x_regola", "")) == "4" and loro != "C":
				b.disabled = true
				b.tooltip_text = "Chi ha il gettone X non può scegliere C se l'altro non l'ha scelto prima"
			b.pressed.connect(func(): _scelte[o] = k)
			r.add_child(b)
		azione.add_child(r)
	azione.add_child(UI.bottone("Conferma le opzioni", func(): _invia(_scelte.duplicate())))
	azione.add_child(UI.bottone("Mostra la plancia", _mostra_plancia, 14))


# ---------- conflitto

func _ui_attacco() -> void:
	var h := int(req["h"])
	var vera := int(req["vera"])
	b2.bersagli[h] = Color(1, 0.4, 0.2, 0.9)
	sel = h
	azione.add_child(_testo("Conflitto in %s. La tua capacità vera è %d (flotte meno esploratrici più corazzate). Avversari attaccabili: %s." % [D.nome(h), vera, ", ".join(req["bersagli"].map(func(x): return eng.fazione(x)))], 15))
	if req.get("obbligatorio", false):
		azione.add_child(_testo("Ostilità reciproca (C/C): il conflitto è obbligatorio e le perdite del difensore raddoppiano.", 14, UI.ROSSO))
	var att = {"v": true if req.get("obbligatorio", false) else true}
	var cb := CheckBox.new()
	cb.text = "Attacca"
	cb.button_pressed = true
	cb.disabled = req.get("obbligatorio", false)
	cb.toggled.connect(func(v): att["v"] = v)
	azione.add_child(cb)
	var r := HBoxContainer.new()
	r.add_child(UI.label("Capacità dichiarata (chi dichiara di più attacca per primo):", 14))
	azione.add_child(r)
	var sb := SpinBox.new()
	sb.min_value = int(floor(vera * 0.5))
	sb.max_value = int(ceil(vera * 1.5))
	sb.value = vera
	azione.add_child(sb)
	azione.add_child(UI.bottone("Conferma", func(): _invia({"attacca": att["v"], "dich": int(sb.value)})))


func _ui_bersaglio() -> void:
	azione.add_child(_testo("Chi attacchi in %s?" % D.nome(int(req["h"])), 15))
	for o in req["bersagli"]:
		azione.add_child(UI.bottone(eng.fazione(o), func(): _invia(o)))


func _ui_riduzione() -> void:
	var h := int(req["h"])
	b2.bersagli[h] = Color(0.7, 0.8, 1.0, 0.9)
	var s := int(req["seat"])
	var g = eng.porta(h)
	var cap = eng._cap_rid(h, s)
	azione.add_child(_testo("In %s c'è una porta di %s senza difensori. Vuoi tentare di neutralizzarla? Capacità di riduzione %d (corazzate + civiltà); il valore della porta non ti è noto." % [D.nome(h), eng.fazione(int(req["proprietario"])), cap], 15))
	var _u := g
	azione.add_child(UI.bottone("Sì, riduci", func(): _invia(true)))
	azione.add_child(UI.bottone("No", func(): _invia(false)))


# ---------- fato

func _ui_fato() -> void:
	var s := int(req["seat"])
	var rp := int(req["rp"])
	var gil: bool = req.get("gilham", false)
	var col0 := int(req["colonna"])
	var stato := {"piu": 0, "sx": 0, "sag": 0}
	azione.add_child(_testo("Fato: i tuoi punti sistema sono %d (colonna %d). Puoi spendere risorse per spostarti a sinistra (5 ciascuna)%s, e gettoni saggezza (ne hai %d) per gli aumenti di civiltà L1 e K2." % [req["sp"], col0 + 1, "" if gil else " e per aggiungere 1 al dado (50 ciascuno, al massimo 8)", req["sag"]], 15))
	var prev := RichTextLabel.new()
	prev.bbcode_enabled = true
	prev.fit_content = true
	prev.custom_minimum_size = Vector2(440, 0)
	var ricalcola := func():
		var tab = eng.tabella_fato()
		var col := maxi(0, col0 - int(stato["sx"]))
		var txt = "[b]Colonna %d[/b], costo %d risorse:\n" % [col + 1, int(stato["piu"]) * 50 + int(stato["sx"]) * 5]
		for d in range(1, 7):
			var t := mini(d + int(stato["piu"]), mini(8, tab.size()))
			var ris: String = tab[t - 1][col]
			txt += "dado %d: %s\n" % [d, _spiega(ris)]
		prev.text = txt
	var riga := func(nome: String, k: String, mx: int):
		var r := HBoxContainer.new()
		r.add_child(UI.label(nome, 15))
		var sb := SpinBox.new()
		sb.min_value = 0
		sb.max_value = mx
		sb.value_changed.connect(func(v):
			stato[k] = int(v)
			ricalcola.call())
		r.add_child(sb)
		azione.add_child(r)
	riga.call("Colonne a sinistra", "sx", mini(col0, rp / 5))
	if not gil:
		riga.call("+1 al dado", "piu", mini(2, rp / 50))
	if int(req["sag"]) > 0:
		riga.call("Gettoni saggezza da spendere", "sag", mini(2, int(req["sag"])))
	azione.add_child(prev)
	ricalcola.call()
	azione.add_child(UI.bottone("Tira il dado del Fato", func(): _invia(stato.duplicate())))
	var _u := s


func _spiega(r: String) -> String:
	if r == "":
		return "nessun effetto"
	var l = r.substr(0, 1)
	var t = {"A": "dissoluzione 10%", "B": "dissoluzione 30% (poi immunità)", "C": "dissoluzione 50%", "D": "dissoluzione 70%", "E": "dissoluzione 80% e civiltà -1", "F": "dissoluzione 90% e civiltà -1", "G": "forza autonoma (2 porte)", "H": "forza autonoma (3 porte)", "I": "forza autonoma (4 porte)", "J": "forza autonoma (5 porte, civiltà 2)", "K": "civiltà +2", "L": "civiltà +1"}.get(l, r)
	if r.length() > 1:
		t += " (servono %s gettoni saggezza)" % r.substr(1)
	var col = "#e0604a" if l in ["A", "B", "C", "D", "E", "F"] else ("#7fd07f" if l in ["K", "L"] else "#d0c070")
	return "[color=%s]%s %s[/color]" % [col, l, t]


func _ui_dissoluzione() -> void:
	var serve := int(req["serve"])
	azione.add_child(_testo("Dissoluzione del %d%%: scegli porte da neutralizzare per almeno %d punti sistema." % [req["perc"], serve], 15, UI.ROSSO))
	_scelte.clear()
	var tot_lbl := UI.label("", 15)
	var aggiorna := func():
		var t := 0
		for h in _scelte:
			if _scelte[h]:
				t += int(eng.porte[h]["sp"])
		tot_lbl.text = "Scelti %d su %d" % [t, serve]
	for h in req["porte"]:
		_scelte[h] = false
		var cb := CheckBox.new()
		cb.text = "%s (valore %d)" % [D.nome(h), eng.porte[h]["sp"]]
		cb.toggled.connect(func(v):
			_scelte[h] = v
			aggiorna.call())
		azione.add_child(cb)
	azione.add_child(tot_lbl)
	aggiorna.call()
	azione.add_child(UI.bottone("Conferma", func():
		var out := []
		for h in _scelte:
			if _scelte[h]:
				out.append(h)
		_invia(out)))


# ---------- risorse

func _ui_risorse(schieramento: bool) -> void:
	var s := int(req["seat"])
	if stato_ris.is_empty() or stato_ris.get("_turno", -1) != eng.turn or stato_ris.get("_tipo", "") != req["type"]:
		azioni_ris = []
		stato_ris = eng.stato_risorse(s)
		stato_ris["rp"] = int(req["rp"])
		stato_ris["_turno"] = eng.turn
		stato_ris["_tipo"] = req["type"]
	if schieramento:
		azione.add_child(_testo("Schieramento iniziale: hai %d punti risorsa da spendere in flotte nelle tue porte (regolare 3, corazzata 8 nell'asse o nella frangia, esploratrice 5 nell'asse)." % stato_ris["rp"], 15))
	else:
		azione.add_child(_testo("Risorse disponibili: %d. Scegli un esagono sulla mappa per costruire porte, aumentarle, riattivarle o costruire flotte." % stato_ris["rp"], 15))
	for h in eng.porte_di(s):
		b2.bersagli[h] = Color(D.TINTE[s], 0.6)
	if not schieramento:
		for h in eng.flotte:
			if eng.n_flotte(h, s) >= 2 and not eng.porte.has(h) and eng.pv_noto(h, s) >= 0:
				b2.bersagli[h] = Color(0.5, 0.9, 1.0, 0.7)
	if hex_ris > 0:
		sel = hex_ris
		azione.add_child(_testo("Esagono %s:" % D.nome(hex_ris), 15, UI.ORO))
		var possibili := []
		if schieramento:
			for k in ["r", "d", "e"]:
				possibili.append({"t": "flotta", "h": hex_ris, "k": k, "n": 1})
		else:
			possibili = [{"t": "porta", "h": hex_ris}, {"t": "aumenta", "h": hex_ris, "n": 1}, {"t": "riattiva", "h": hex_ris},
				{"t": "flotta", "h": hex_ris, "k": "r", "n": 1}, {"t": "flotta", "h": hex_ris, "k": "d", "n": 1}, {"t": "flotta", "h": hex_ris, "k": "e", "n": 1}]
		var almeno := false
		for a in possibili:
			var err := _valida_ris(s, a, schieramento)
			if err != "":
				continue
			almeno = true
			azione.add_child(UI.bottone(_desc_azione(a), func():
				azioni_ris.append(a)
				_simula_ris(s, a, schieramento)
				_costruisci(), 15))
		if not almeno:
			azione.add_child(_testo("Nessuna azione possibile qui.", 14, UI.TENUE))
	if not azioni_ris.is_empty():
		azione.add_child(UI.sep())
		azione.add_child(_testo("Ordini:", 15, UI.ORO))
		for a in azioni_ris:
			azione.add_child(_testo("- " + _desc_azione(a), 14))
		azione.add_child(UI.bottone("Annulla tutto", func():
			azioni_ris = []
			stato_ris = {}
			_costruisci(), 14))
	if eng.opz.get("gilham", false) and not schieramento and int(stato_ris["rp"]) > 0:
		azione.add_child(UI.bottone("Ricerca: converti tutte le risorse in punti civiltà", func():
			var a = {"t": "ricerca", "rp": int(stato_ris["rp"])}
			azioni_ris.append(a)
			_simula_ris(s, a, false)
			_costruisci(), 14))
	azione.add_child(UI.sep())
	azione.add_child(UI.bottone("Fine", func():
		var out := azioni_ris.duplicate()
		azioni_ris = []
		stato_ris = {}
		hex_ris = -1
		_invia({"azioni": out})))


func _valida_ris(s: int, a: Dictionary, schieramento: bool) -> String:
	if schieramento:
		var h := int(a["h"])
		if not eng.porta_propria(h, s):
			return "x"
		var k := str(a["k"])
		if k == "d" and not (D.terreno(h) in ["A", "F"]):
			return "x"
		if k == "e" and D.terreno(h) != "A":
			return "x"
		if D.COSTO[k] > int(stato_ris["rp"]):
			return "x"
		return ""
	return eng.azione_valida(s, a, stato_ris)


func _simula_ris(s: int, a: Dictionary, schieramento: bool) -> void:
	if schieramento:
		stato_ris["rp"] = int(stato_ris["rp"]) - D.COSTO[str(a["k"])]
	else:
		eng.simula_azione(s, a, stato_ris)


func _desc_azione(a: Dictionary) -> String:
	match str(a["t"]):
		"porta":
			return "Crea una porta in %s (2 flotte)" % D.nome(int(a["h"]))
		"aumenta":
			return "Aumenta la porta di %s di %d (1 flotta per punto)" % [D.nome(int(a["h"])), int(a.get("n", 1))]
		"riattiva":
			return "Riattiva la porta neutralizzata di %s" % D.nome(int(a["h"]))
		"flotta":
			var k := str(a["k"])
			return "Costruisci una %s in %s (%d risorse)" % [D.NOME_FLOTTA[k], D.nome(int(a["h"])), D.COSTO[k]]
		"ricerca":
			return "Ricerca: %d risorse in punti civiltà" % int(a["rp"])
	return str(a)


# ---------------------------------------------------------------- finestre

func _chiudi_finestra() -> void:
	if finestra != null:
		finestra.queue_free()
		finestra = null


func _finestra(titolo: String, largo := 900.0) -> VBoxContainer:
	_chiudi_finestra()
	finestra = PanelContainer.new()
	finestra.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	finestra.offset_left = 60
	finestra.offset_top = 50
	finestra.offset_right = -60
	finestra.offset_bottom = -40
	add_child(finestra)
	var v := VBoxContainer.new()
	finestra.add_child(v)
	var h := HBoxContainer.new()
	var t := UI.titolo(titolo, 28)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(UI.bottone("Chiudi", _chiudi_finestra))
	v.add_child(h)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(largo, 0)
	sc.add_child(c)
	return c


func _mostra_plancia() -> void:
	var s := vista if vista >= 0 else 0
	var c = _finestra("Plancia di %s" % eng.fazione(s))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	c.add_child(h)
	var tav := Control.new()
	var bg: Texture2D = null
	if Grafica.stile == "reborn" and ResourceLoader.exists("res://assets/reborn/plancia.png"):
		bg = load("res://assets/reborn/plancia.png")
	else:
		bg = load("res://assets/misc/plancia.jpg")
	tav.custom_minimum_size = Vector2(600, 780)
	var tr := TextureRect.new()
	tr.texture = bg
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = Vector2(600, 780)
	tav.add_child(tr)
	# i segnalini: colonna = la nostra opzione, riga = la loro (in alto se non è nota)
	var cols := {"A": 102, "B": 292, "C": 484}
	var righe := {"": 160, "A": 410, "B": 552, "C": 694}
	var occ := {}
	for o in _parti_note(s):
		var mia = eng.opzione(s, o)
		if mia == "":
			continue
		var loro = eng.opzione(o, s)
		var key: String = mia + loro
		var n := int(occ.get(key, 0))
		occ[key] = n + 1
		var p := Vector2(cols[mia] - 60 + (n % 3) * 42, righe[loro] - 10 + (n / 3) * 42)
		var g := TextureRect.new()
		g.texture = Grafica.tex(Grafica.nome_porta(o))
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.size = Vector2(40, 40)
		g.position = p
		g.tooltip_text = eng.fazione(o)
		tav.add_child(g)
	h.add_child(tav)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(420, 0)
	h.add_child(v)
	v.add_child(UI.intestazione("Relazioni", 22))
	for o in _parti_note(s):
		var mia2 = eng.opzione(s, o)
		var loro2 = eng.opzione(o, s)
		v.add_child(_testo("%s: noi %s, loro %s. %s" % [eng.fazione(o), mia2 if mia2 != "" else "-", loro2 if loro2 != "" else "-", _effetto_coppia(mia2, loro2)], 15))
	if _parti_note(s).is_empty():
		v.add_child(_testo("Ancora nessun contatto.", 15, UI.TENUE))
	v.add_child(UI.sep())
	var p2: Dictionary = eng.players[s]
	v.add_child(UI.intestazione("Civiltà", 22))
	v.add_child(_testo("Livello di civiltà %d, raggio di sicurezza %d esagoni." % [eng.cl(s), eng.clr(s)], 15))
	v.add_child(_testo("Punti sistema %d, risorse %d, manutenzione %d." % [eng.punti_sistema(s), p2["rp"], eng.manutenzione(s)], 15))
	var t = eng.totale_flotte(s)
	v.add_child(_testo("Flotte: %d regolari, %d corazzate, %d esploratrici." % [t["r"], t["d"], t["e"]], 15))
	v.add_child(_testo("Gettoni saggezza: %d%s." % [p2["sag"].size(), ", più il gettone X" if p2["x"] else ""], 15))
	if not p2["diss"].is_empty():
		v.add_child(_testo("Dissoluzioni già subite: %s%s." % [", ".join(p2["diss"].keys()), " (immune)" if p2["immune"] else ""], 15))
	if eng.opz.get("gilham", false):
		v.add_child(_testo("Punti civiltà: %d." % p2["cp"], 15))
	v.add_child(UI.sep())
	v.add_child(UI.intestazione("Scenario", 22))
	v.add_child(_testo(str(eng.sc["vittoria"]), 14, UI.TENUE))


func _parti_note(s: int) -> Array:
	var out := []
	for k in eng.opt:
		var p: PackedStringArray = str(k).split(":")
		var a := int(p[0])
		var b := int(p[1])
		if a == s and not (b in out):
			out.append(b)
		if b == s and not (a in out):
			out.append(a)
	out.sort()
	return out


func _effetto_coppia(m: String, l: String) -> String:
	match m + l:
		"AA":
			return "Alleanza reciproca: nessun attacco, porte in comune."
		"AB":
			return "Alleanza a senso unico: loro usano le nostre porte, nessun attacco."
		"BA":
			return "Alleanza a senso unico: noi usiamo le loro porte, nessun attacco."
		"AC":
			return "Loro possono attaccarci con due colonne di vantaggio."
		"CA":
			return "Possiamo attaccarli con due colonne di vantaggio."
		"BB":
			return "Nessun effetto speciale: ci si può attaccare."
		"BC":
			return "Loro possono attaccarci con una colonna di vantaggio."
		"CB":
			return "Possiamo attaccarli con una colonna di vantaggio."
		"CC":
			return "Conflitto obbligatorio, perdite del difensore raddoppiate."
	return ""


func _mostra_tabelle() -> void:
	var c := _finestra("Tabelle", 1500)
	c.add_child(preload("res://scripts/ui/tabelle_view.gd").crea(eng))


func _mostra_regole() -> void:
	var c := _finestra("Regole", 1500)
	c.add_child(preload("res://scripts/ui/rules_view.gd").testo_regole())


# ---------------------------------------------------------------- fine e salvataggio

func _on_fine(r: Dictionary) -> void:
	if online != null:
		online.finish()
	var c := _finestra("Fine della partita", 800)
	var w := int(r.get("winner", -1))
	c.add_child(UI.titolo("Vince %s" % eng.pname(w) if w >= 0 else "Nessun vincitore", 38))
	c.add_child(_testo(str(r.get("reason", "")), 20))
	c.add_child(_testo("Turni giocati: %d." % eng.turn, 16, UI.TENUE))
	c.add_child(UI.sep())
	c.add_child(UI.bottone("Rivedi tutta la partita (senza segreti)", _rivedi, 18))
	c.add_child(UI.bottone("Salva su Firebase", _salva, 18))
	c.add_child(UI.bottone("Torna al menu", _esci, 18))
	_azione_attesa("Partita finita.")


func _rivedi() -> void:
	var cfg := eng.config.duplicate(true)
	cfg["acts"] = eng.rec_acts.duplicate(true)
	cfg["replay"] = true
	cfg["anim"] = 2.0
	cfg["ai_delay"] = 0.0
	main.start_game(cfg)


func _salva() -> void:
	var dati = eng.salva()
	var net: Net = main.get_net()
	_messaggio("Salvataggio in corso...")
	var codice = await net.save_game({"json": JSON.stringify(dati), "nome": "%s, turno %d" % [eng.sc["titolo"], eng.turn], "aggiornata": Time.get_unix_time_from_system()}, str(config.get("codice", "")))
	if codice == "":
		_messaggio("Salvataggio non riuscito: %s" % net.last_error)
	else:
		config["codice"] = codice
		_messaggio("Partita salvata con il codice %s (lo si inserisce nel menu, Carica partita)." % codice)
		var c := _finestra("Partita salvata", 600)
		c.add_child(UI.titolo(codice, 60))
		c.add_child(_testo("Per riprendere la partita: menu, Carica partita, e questo codice.", 18))


# ---------------------------------------------------------------- online

func online_status(t: String) -> void:
	_messaggio(t)


func online_waiting(s: int, lento: bool) -> void:
	if s >= 0:
		_azione_attesa("In attesa della scelta di %s%s." % [eng.pname(s), " (lento...)" if lento else ""])


func online_cancel_decision(t: String) -> void:
	_azione_attesa(t)


func online_caught_up() -> void:
	_messaggio("Partita aggiornata.")
