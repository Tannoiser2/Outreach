extends RefCounted
## Le tabelle del gioco, in italiano, ricomposte dai dati (quelle in uso sono indicate).

const D = preload("res://scripts/data/od_data.gd")


static func _griglia(titolo: String, intest: Array, righe: Array, nota := "", in_uso := false) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var t = UI.intestazione(titolo + ("   (in uso)" if in_uso else ""), 20)
	if in_uso:
		t.add_theme_color_override("font_color", UI.AMBRA)
	v.add_child(t)
	var g := GridContainer.new()
	g.columns = intest.size()
	g.add_theme_constant_override("h_separation", 2)
	g.add_theme_constant_override("v_separation", 2)
	for x in intest:
		g.add_child(_cella(str(x), true, false))
	var i := 0
	for r in righe:
		for x in r:
			g.add_child(_cella(str(x), false, i % 2 == 0))
		i += 1
	v.add_child(g)
	if nota != "":
		var l = UI.label(nota, 13, UI.TENUE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(700, 0)
		v.add_child(l)
	v.add_child(UI.sep())
	return v


static func _cella(t: String, testa: bool, scura: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.2, 0.1) if testa else (Color(0.13, 0.13, 0.18) if scura else Color(0.09, 0.09, 0.12))
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	var l = UI.label(t if t != "" else "·", 14, UI.ORO if testa else UI.TESTO, "intestazione" if testa else "numeri")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(54, 0)
	p.add_child(l)
	return p


static func _disp(tab: Array) -> Array:
	var out := []
	for i in tab.size():
		var r = [str(i + 1)]
		for c in tab[i]:
			r.append(str(c))
		out.append(r)
	out.append(["10+", "", "", "", "", "", "", "", ""])
	return out


static func _conf(tab: Array) -> Array:
	var out := []
	for i in tab.size():
		var r = [str(i - 2)]
		for c in tab[i]:
			r.append(str(c))
		out.append(r)
	return out


static func _fato(tab: Array, gil := false) -> Array:
	var out := []
	for i in tab.size():
		var r = [str(i + 1)]
		for c in tab[i]:
			r.append(str(c))
		out.append(r)
	return out


static func crea(eng) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var tab: String = str(eng.opz.get("tabelle", "originali")) if eng != null else "originali"
	var gil: bool = eng != null and eng.opz.get("gilham", false)
	var frev: bool = eng != null and eng.opz.get("fato_rivisto", false)
	var crev: bool = eng != null and (eng.opz.get("conv_rivista", false) or tab == "v3")
	var col_disp = ["Dado", "2", "3", "4", "5", "6-8", "9-15", "16-24", "25+"]
	var nota_disp := "Esagoni di spostamento in colonna. «·» = nessuna dispersione; altrimenti distanza di dispersione / percentuale di flotte perdute (per eccesso). Al dado si aggiunge: +1 se nell'esagono d'arrivo c'è una porta amica o alleata, +1 se c'è una stella faro, +1 se la forza comprende esploratrici (+2 se sono tutte esploratrici), +1 per ogni livello di civiltà oltre il primo. Oltre il raggio di sicurezza le perdite raddoppiano. La direzione si tira sul diagramma: 1 su, 2 su a destra, 3 giù a destra, 4 giù, 5 giù a sinistra, 6 su a sinistra."
	v.add_child(_griglia("[5.6] Tabella della dispersione (originale)", col_disp, _disp(D.DISP_ORIGINALE), nota_disp, tab == "originali"))
	v.add_child(_griglia("[5.6] Tabella della dispersione (riveduta da SkyGazer)", col_disp, _disp(D.DISP_SKYGAZER), "", tab == "skygazer"))
	v.add_child(_griglia("[5.6] Tabella della dispersione (riveduta, versione 3)", col_disp, _disp(D.DISP_V3), "", tab == "v3"))
	var esp := []
	for d in range(1, 7):
		var r = [str(d)]
		for c in 6:
			r.append("E" if d <= c + 1 else "")
		esp.append(r)
	v.add_child(_griglia("[6.2] Tabella dell'esplorazione", ["Dado", "1-2", "3-4", "5-6", "7-9", "10-12", "13+"], esp, "Colonna: esploratrici x 2 più le altre flotte nell'esagono. E = esplorazione riuscita.", true))
	var con := []
	for d in range(1, 7):
		var r2 = [str(d)]
		for c in 6:
			r2.append("C" if d <= c else "")
		con.append(r2)
	v.add_child(_griglia("[7.4] Tabella del contatto", ["Dado", "0", "1", "2-4", "5-9", "10-16", "17+"], con, "Indice di contatto in colonna (fra il minimo e il massimo scelti dal giocatore). C = contatto.", true))
	var col_conf = ["Dado", "33-65%", "66-99%", "100-149%", "150-199%", "200-299%", "300-399%", "400%+"]
	var nota_conf := "Capacità vera dell'attaccante divisa per quella del difensore. Al dado +1 per ogni corazzata attaccante, -1 per ogni corazzata in difesa (fra -2 e 9). Risultato: percentuale di perdite dell'attaccante / del difensore. Con l'opzione C contro A si usa la colonna due posti a destra, contro B una."
	v.add_child(_griglia("[9.2] Tabella del conflitto (originale)", col_conf, _conf(D.CONF_ORIGINALE), nota_conf, tab != "v3"))
	v.add_child(_griglia("[9.2] Tabella del conflitto (riveduta, versione 3)", col_conf, _conf(D.CONF_V3), "Nella tabella riveduta la casella 0 / 66-99% è stampata «30/20», evidente refuso per 90/20.", tab == "v3"))
	var rid := []
	for d in range(1, 7):
		var r3 = [str(d)]
		for c in 5:
			r3.append("N" if d <= c + 1 else "")
		rid.append(r3)
	v.add_child(_griglia("[10.3] Tabella della riduzione", ["Dado", "-2..0", "1-2", "3-4", "5-6", "7+"], rid, "Differenza: (corazzate + civiltà dell'attaccante) meno (valore della porta + civiltà del proprietario). N = porta neutralizzata. Sotto -2 nessun effetto.", true))
	var riot := []
	for d in range(1, 7):
		riot.append([str(d)] + D.RIOT[d - 1])
	v.add_child(_griglia("[8.4] Opzioni casuali delle forze autonome", ["Dado", "Prima A", "Prima B", "Prima C", "Nessuna"], riot, "", true))
	var col_f = ["Dado", "0-9", "10-19", "20-29", "30-39", "40-49", "50-59", "60-69", "70-79", "80-89", "90-99", "100+"]
	var nota_f := "Punti sistema in colonna. A-F dissoluzione (10, 30, 50, 70, 80, 90%; E ed F: civiltà -1; B: le dissoluzioni successive si ignorano). G-J comparsa di una forza autonoma. K civiltà +2, L civiltà +1; il numero indica i gettoni saggezza da spendere. 50 risorse = +1 al dado (al massimo 8); 5 risorse = una colonna a sinistra."
	v.add_child(_griglia("[11.4] Tabella del Fato (originale)", col_f, _fato(D.FATO_ORIGINALE), nota_f, not frev and not gil))
	v.add_child(_griglia("[11.4] Tabella del Fato (riveduta)", col_f, _fato(D.FATO_RIVISTO), "", frev and not gil))
	v.add_child(_griglia("Tabella del Fato alternativo (Gilham, Phoenix n. 11)", ["Dado", "0-19", "20-29", "30-39", "40-49", "50-59", "60-69", "70-79", "80-89", "90-99", "100+"], _fato(D.FATO_GILHAM, true), "Solo dissoluzioni; «scende di un livello» diventa «dimezza i punti civiltà». Le forze autonome e la saggezza arrivano dall'esplorazione (risultato 00).", gil))
	var conv := []
	var fasce = ["1-5", "6-10", "11-15", "16-20", "21-25", "26-30", "31-35", "36-40", "41-45", "46-50"]
	for i in 10:
		var r4 = [fasce[i]]
		for x in D.CONV_ORIGINALE[i]:
			r4.append(str(x))
		conv.append(r4)
	v.add_child(_griglia("Tabella di conversione delle percentuali (originale)", ["Flotte", "10%", "15%", "20%", "30%", "40%", "45%", "50%", "60%", "75%", "80%"], conv, "Numero di flotte perdute. Nella tabella riveduta si calcola sempre la percentuale arrotondata per eccesso.", not crev))
	var conv2 := []
	for n in [1, 2, 3, 5, 8, 10, 15, 20, 25, 30, 40, 50]:
		var r5 = [str(n)]
		for p in [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]:
			r5.append(str(D.perdite(n, p, true)))
		conv2.append(r5)
	v.add_child(_griglia("Tabella di conversione delle percentuali (riveduta, estratto)", ["Flotte", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%"], conv2, "", crev))
	var seme := []
	for i in 6:
		seme.append([str(i + 1)] + D.VENTI_SEME[i])
	v.add_child(_griglia("[18.51] Tabella dei Venti Seme", ["Primo dado", "1", "2", "3", "4", "5", "6"], seme, "Risultati (18.52), una porta in ciascun esagono: A 0707, 0706, 0607 (*); B 0510, 0409, 0410 (*); C 0814, 0813, 0714; D 1709, 1708, 1609; E 1110, 1111, 1209, 1210; F 1314, 1313, 1213, 1214; G 1215, 1115, 1116, 1216, 1316; H 1118, 1117, 1017, 1018; I 1816, 1815, 1916; J 1324, 1323, 1423; K 1726, 1625, 1826; L 4903, 4802, 4803 (*); M 3827, 3728 (*). (*) = si piazzano altre stelle faro.", eng != null and eng.scn_id == 5))
	return v
