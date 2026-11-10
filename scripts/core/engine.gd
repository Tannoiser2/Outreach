class_name ODEngine
extends Node
## Motore delle regole di Outreach (SPI, 1976), senza dipendenze dalla grafica.
## Ogni scelta passa da `decide()`: l'IA risponde subito; per le persone viene emesso
## `decision_requested` e si attende `provide_decision()`. Online le scelte viaggiano nel registro
## delle mosse (OnlineSession): con lo stesso seme ogni dispositivo gioca la stessa partita.
##
## Proprietari: 0..3 i giocatori, 10..13 le forze autonome (indice 0..3 nei quattro colori), -1 nessuno.
## Esagoni: interi XXYY (col * 100 + riga).
## Flotte: flotte[esagono][proprietario] = {"r": regolari, "d": corazzate, "e": esploratrici,
##   "m": {r,d,e} già mosse in questo turno, "sag": [gettoni saggezza trasportati]}
## Porte: porte[esagono] = {"o": proprietario (-1 neutralizzata), "sp": valore, "neut": bool,
##   "nata": turno di costruzione, "aum": turno dell'ultimo aumento, "orig": proprietario iniziale}

const D = preload("res://scripts/data/od_data.gd")

signal changed
signal log_added(entry: Dictionary)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(result: Dictionary)
signal fx(kind: String, data: Dictionary)

# ---------------------------------------------------------------- configurazione
var config := {}
var scn_id := 1
var sc: Dictionary
var opz := {}                      # opzioni: tabelle, fato_rivisto, conv_rivista, gilham, limite
var players: Array = []            # [{name, ai, level, fazione, colore, cl, rp, cp, sag: [], vivo, ...}]
var ais: Array = []
var online = null
var ai_delay := 0.4
var anim := 1.0
var headless := false
var abort := false
var rng := RandomNumberGenerator.new()
var preload_acts: Array = []
var pre_i := 0
var rec_acts: Array = []
var replay_lento := false

# ---------------------------------------------------------------- stato
var turn := 0
var phase := ""
var over := false
var result := {}
var log_lines: Array = []
var ordine: Array = []             # ordine dei giocatori nel turno
var porte := {}
var flotte := {}
var pv := {}                       # esagono -> {"c": indice gettone (-1 = valore fisso), "v": valore fisso, "visto": {seat: true}}
var pv_pool: Array = []
var fari := {}                     # esagono -> nome ("" = scoperto in partita)
var contatti := {}                 # esagoni con il segnalino di contatto
var opt := {}                      # "a:b" -> "A" / "B" / "C": opzione di a verso b
var cambio_c := {}                 # seat -> true se nel segmento d'interazione ha spostato qualcosa da o verso C
var attaccati := {}                # "aut:seat" -> true (13.26)
var aut: Array = []                # forze autonome [{presente, attiva, custode, cl, colore, porte_pool, flotte_pool}]
var sag_pool: Array = []           # gettoni saggezza non schierati (9 = "X")
var sag_centro := {}               # esagono del centro -> gettone
var esplorati_turno = {}          # seat -> [esagoni su cui ha tirato]
var x_esplorazione := {}           # seat -> numero di "X" sulla tabella d'esplorazione (non usato nelle tabelle)
var serie := {}                    # contatori per le vittorie (turni consecutivi)
var history: Array = []            # istantanee per il replay
var mosse_turno: Array = []        # spostamenti eseguiti nel turno (per l'animazione)


# ================================================================ avvio

func setup(cfg: Dictionary) -> void:
	config = cfg.duplicate(true)
	scn_id = int(cfg.get("scenario", 1))
	sc = D.SCENARI[scn_id]
	opz = cfg.get("opzioni", {}).duplicate()
	rng.seed = int(cfg.get("seed", 1))
	var seats: Array = cfg.get("seats", [])
	var n = seats.size()
	if int(sc["giocatori"]) > 0:
		n = int(sc["giocatori"])
	players.clear()
	ais.clear()
	for i in n:
		var st: Dictionary = seats[i] if i < seats.size() else {"name": "", "ai": true}
		var p = {"name": str(st.get("name", "")), "ai": bool(st.get("ai", true)), "level": int(st.get("level", 1)),
			"colore": i, "cl": 1, "rp": 0, "cp": 500, "sag": [], "vivo": true, "diss": {}, "immune": false,
			"k_usato": false, "fazione": "", "esplorati": {}, "porte_iniziali": [], "guardiani": false,
			"limite_corazzate": false, "x": false}
		players.append(p)
		var a = preload("res://scripts/core/ai.gd").new()
		a.setup(int(cfg.get("seed", 1)) * 31 + i, p["level"])
		ais.append(a)
	for i in 4:
		aut.append({"presente": false, "attiva": false, "custode": -1, "cl": 1, "porte_pool": [4, 4, 3, 3, 1], "flotte_pool": ["r", "r", "r", "r", "r", "r", "r", "r", "r", "r", "d", "d", "d", "d", "d"], "visti": {}, "dread": {}})
	# gettoni del potenziale e della saggezza
	for i in D.GETTONI_PV.size():
		pv_pool.append(i)
	for i in 10:
		sag_pool.append(i)
	# stelle faro stampate
	for h in D.mappa()["fari"]:
		fari[h] = D.mappa()["fari"][h]
	if scn_id == 5:
		_venti_seme()
	else:
		var lati: Array = sc["lati"]
		for i in players.size():
			var lato: Dictionary = lati[i]
			var p: Dictionary = players[i]
			p["fazione"] = lato["nome"]
			p["rp"] = int(lato["rp"])
			p["cl"] = int(lato["cl"])
			p["guardiani"] = lato.get("guardiani", false)
			p["limite_corazzate"] = lato.get("limite_corazzate", false)
			if p["guardiani"]:
				p["cp"] = 2000
			for g in lato["porte"]:
				var h: int = int(g[0])
				var gv: int = int(g[1])
				var pot: int = int(g[2])
				if gv >= 0:
					porte[h] = {"o": i, "sp": gv, "neut": false, "nata": 0, "aum": 0, "orig": i}
					p["porte_iniziali"].append(h)
				if gv < pot or gv < 0:
					pv[h] = {"c": -1, "v": pot, "visto": {i: true}}
				p["esplorati"][h] = true
				var fl: Dictionary = D.flotte_da_testo(str(g[3]))
				if fl["r"] + fl["d"] + fl["e"] > 0:
					_aggiungi(h, i, fl)
	# saggezza nei tre esagoni centrali
	if usa_saggezza_in_gioco():
		_mescola(sag_pool)
		for h in [3815, 3915, 3916]:
			sag_centro[h] = sag_pool.pop_back()
	_mescola(pv_pool)


func _mescola(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _venti_seme() -> void:
	var usati := {}
	for i in players.size():
		var p: Dictionary = players[i]
		p["fazione"] = D.NOMI_SEME[i]
		p["cl"] = 1
		p["rp"] = 0
	var risultati := []
	while true:
		risultati.clear()
		usati.clear()
		var dup := false
		for i in players.size():
			var r: String = D.VENTI_SEME[rng.randi_range(0, 5)][rng.randi_range(0, 5)]
			if usati.has(r):
				dup = true
			usati[r] = true
			risultati.append(r)
		if not dup:
			break
	for i in players.size():
		var r: String = risultati[i]
		var p: Dictionary = players[i]
		p["seme"] = r
		var hs: Array = D.SEMI[r][0]
		var tot := 0
		for h in hs:
			var c: int = pv_pool.pop_at(rng.randi_range(0, pv_pool.size() - 1))
			var v = D.valore_pv(D.GETTONI_PV[c], h)
			pv_pool.append(c)
			porte[h] = {"o": i, "sp": v, "neut": false, "nata": 0, "aum": 0, "orig": i}
			p["porte_iniziali"].append(h)
			p["esplorati"][h] = true
			tot += v
		p["budget"] = tot * 2
		fari[hs[0]] = fari.get(hs[0], "")
		if D.SEMI[r][1]:
			_scopri_fari(hs[0], i, false)
	var righe := []
	for i in players.size():
		righe.append("%s (%s) nasce in %s" % [players[i]["fazione"], players[i]["seme"], D.nome(D.SEMI[players[i]["seme"]][0][0])])
	log_msg("Venti Seme: " + ", ".join(righe) + ".")


func usa_saggezza_in_gioco() -> bool:
	if ignora("nucleo"):
		return false
	if opz.get("gilham", false):
		return false
	return true


## Regole ignorate dallo scenario (per tutti o per un lato).
func ignora(cosa: String, seat := -1) -> bool:
	var ig: Array = sc.get("ignora", [])
	if cosa in ig:
		return true
	if seat >= 0 and sc.has("ignora_lato"):
		var il: Dictionary = sc["ignora_lato"]
		if il.has(seat) and cosa in il[seat]:
			return true
	if scn_id == 2 and cosa == "nucleo":
		return true
	return false


# ================================================================ registro

func log_msg(t: String, solo := -1, pubblico := "") -> void:
	var e = {"t": t, "solo": solo, "pub": pubblico, "turno": turn}
	log_lines.append(e)
	log_added.emit(e)


func _pace(sec: float) -> void:
	if headless or anim <= 0.0 or abort or not is_inside_tree():
		return
	if online != null and online.catchup:
		return
	if replaying() and not replay_lento:
		return
	await get_tree().create_timer(sec / anim).timeout


func pname(s: int) -> String:
	if s >= 10:
		return "Autonomi %s" % D.COLORI_AUT[s - 10]
	if s < 0 or s >= players.size():
		return "nessuno"
	var p: Dictionary = players[s]
	if p["name"] != "":
		return "%s (%s)" % [p["fazione"], p["name"]]
	return p["fazione"]


func fazione(s: int) -> String:
	if s >= 10:
		return "Autonomi %s" % D.COLORI_AUT[s - 10]
	if s < 0:
		return "nessuno"
	return players[s]["fazione"]


# ================================================================ decisioni

func decide(seat: int, req: Dictionary):
	req["seat"] = seat
	req["turn"] = turn
	if abort:
		return ais[seat].decide(self, seat, req)
	if online != null:
		changed.emit()
		var r0 = await online.decide(self, seat, req)
		rec_acts.append(r0)
		return r0
	if pre_i < preload_acts.size():
		var rp = preload_acts[pre_i]
		pre_i += 1
		rec_acts.append(rp)
		if replay_lento and is_inside_tree():
			changed.emit()
			await get_tree().create_timer(0.25 / maxf(anim, 0.1)).timeout
		return rp
	changed.emit()
	var r = null
	if players[seat]["ai"]:
		if ai_delay > 0.0 and not headless and is_inside_tree():
			await get_tree().create_timer(ai_delay * 0.5).timeout
		r = ais[seat].decide(self, seat, req)
	else:
		decision_requested.emit(req)
		r = await decision_provided
		if r == null:
			r = ais[seat].decide(self, seat, req)
	rec_acts.append(r)
	return r


func replaying() -> bool:
	return pre_i < preload_acts.size()


## Decisioni simultanee: ognuno sceglie senza vedere le scelte altrui.
func decide_all(seats: Array, reqs: Array) -> Array:
	for i in seats.size():
		reqs[i]["seat"] = seats[i]
		reqs[i]["turn"] = turn
	if online != null and not abort:
		var rr: Array = await online.decide_all(self, seats, reqs)
		for r in rr:
			rec_acts.append(r)
		return rr
	var out := []
	for i in seats.size():
		var r = await decide(seats[i], reqs[i])
		out.append(r)
	return out


func provide_decision(r) -> void:
	decision_provided.emit(r)


func humans() -> int:
	var n := 0
	for p in players:
		if not p["ai"]:
			n += 1
	return n


func vivi() -> Array:
	var out := []
	for i in players.size():
		if players[i]["vivo"]:
			out.append(i)
	return out


# ================================================================ consultazione dello stato

func stack(h: int, o: int) -> Dictionary:
	if flotte.has(h) and flotte[h].has(o):
		return flotte[h][o]
	return {}


func n_flotte(h: int, o: int) -> int:
	var s = stack(h, o)
	if s.is_empty():
		return 0
	return int(s["r"]) + int(s["d"]) + int(s["e"])


func liberi(h: int, o: int) -> Dictionary:
	var s = stack(h, o)
	if s.is_empty():
		return {"r": 0, "d": 0, "e": 0}
	var m: Dictionary = s["m"]
	return {"r": int(s["r"]) - int(m["r"]), "d": int(s["d"]) - int(m["d"]), "e": int(s["e"]) - int(m["e"])}


func proprietari(h: int) -> Array:
	var out := []
	if flotte.has(h):
		for o in flotte[h]:
			if n_flotte(h, o) > 0:
				out.append(int(o))
	return out


func _aggiungi(h: int, o: int, fl: Dictionary, mosse := false) -> void:
	if not flotte.has(h):
		flotte[h] = {}
	if not flotte[h].has(o):
		flotte[h][o] = {"r": 0, "d": 0, "e": 0, "m": {"r": 0, "d": 0, "e": 0}, "sag": []}
	var s: Dictionary = flotte[h][o]
	for k in ["r", "d", "e"]:
		s[k] = int(s[k]) + int(fl.get(k, 0))
		if mosse:
			s["m"][k] = int(s["m"][k]) + int(fl.get(k, 0))


## Toglie flotte (prima quelle non mosse se libere=true).
func _togli(h: int, o: int, fl: Dictionary, da_libere := true) -> void:
	var s = stack(h, o)
	if s.is_empty():
		return
	for k in ["r", "d", "e"]:
		var n: int = mini(int(fl.get(k, 0)), int(s[k]))
		s[k] = int(s[k]) - n
		if not da_libere:
			s["m"][k] = maxi(0, int(s["m"][k]) - n)
		s["m"][k] = mini(int(s["m"][k]), int(s[k]))
	_pulisci(h, o)


func _pulisci(h: int, o: int) -> void:
	var s = stack(h, o)
	if s.is_empty():
		return
	if int(s["r"]) + int(s["d"]) + int(s["e"]) <= 0:
		for c in s["sag"]:
			sag_pool.append(c)
			log_msg("Un gettone saggezza trasportato da %s torna fuori dalla mappa." % fazione(o))
		flotte[h].erase(o)
		if flotte[h].is_empty():
			flotte.erase(h)


func porta(h: int) -> Dictionary:
	return porte.get(h, {})


func porte_di(o: int) -> Array:
	var out := []
	for h in porte:
		var g: Dictionary = porte[h]
		if int(g["o"]) == o and not g["neut"]:
			out.append(h)
	out.sort()
	return out


## Punti sistema (somma dei valori delle porte amiche non neutralizzate).
func punti_sistema(s: int) -> int:
	var t := 0
	for h in porte_di(s):
		t += int(porte[h]["sp"])
	return t


func cl(o: int) -> int:
	if o >= 10:
		return int(aut[o - 10]["cl"])
	if opz.get("gilham", false):
		return maxi(0, D.gil_livello(int(players[o]["cp"])))
	return int(players[o]["cl"])


## Raggio di sicurezza (5.15): quadrato del livello di civiltà.
func clr(o: int) -> int:
	if o >= 10:
		return int(aut[o - 10]["cl"]) * int(aut[o - 10]["cl"])
	var p: Dictionary = players[o]
	if opz.get("gilham", false):
		var cp := int(p["cp"])
		if p["x"] and str(sc.get("x_regola", "")) == "5":
			cp *= 2
		return D.gil_raggio(cp)
	var l := int(p["cl"])
	if p["x"] and str(sc.get("x_regola", "")) == "5":
		l += 1
	return l * l


func cl_spostamento(o: int) -> int:
	if o >= 10:
		return int(aut[o - 10]["cl"])
	var l = cl(o)
	if players[o]["x"] and str(sc.get("x_regola", "")) == "5":
		l += 1
	return l


func opzione(a: int, b: int) -> String:
	return str(opt.get("%d:%d" % [a, b], ""))


func alleati(a: int, b: int) -> bool:
	if a == b:
		return true
	return opzione(a, b) == "A" and opzione(b, a) == "A"


## a può usare le porte di b come se fossero alleate (A/A, oppure a = B e b = A).
func usa_porte(a: int, b: int) -> bool:
	if a == b:
		return true
	if b < 0:
		return false
	var mio = opzione(a, b)
	return opzione(b, a) == "A" and (mio == "A" or mio == "B")


func porta_utile(h: int, o: int) -> bool:
	var g = porta(h)
	if g.is_empty() or g["neut"]:
		return false
	return usa_porte(o, int(g["o"]))


func porta_propria(h: int, o: int) -> bool:
	var g = porta(h)
	return not g.is_empty() and not g["neut"] and int(g["o"]) == o


## a può attaccare (o ridurre) b?
func puo_attaccare(a: int, b: int) -> bool:
	if a == b or b < 0:
		return false
	if a >= 10 and b >= 10:
		return false
	var mio = opzione(a, b)
	var suo = opzione(b, a)
	if mio == "" or suo == "":
		return false
	if mio == "C":
		return true
	if mio == "B":
		return suo == "B" or suo == "C"
	return false


## Colonne di vantaggio per chi sceglie C contro A (2) o contro B (1).
func colonne_bonus(a: int, b: int) -> int:
	if opzione(a, b) != "C":
		return 0
	var suo = opzione(b, a)
	if suo == "A":
		return 2
	if suo == "B":
		return 1
	return 0


func obbligatorio(a: int, b: int) -> bool:
	return opzione(a, b) == "C" and opzione(b, a) == "C"


func faro(h: int) -> bool:
	return fari.has(h)


func valore_pv(h: int) -> int:
	var e: Dictionary = pv.get(h, {})
	if e.is_empty():
		return -1
	if int(e["c"]) < 0:
		return int(e["v"])
	return D.valore_pv(D.GETTONI_PV[int(e["c"])], h)


## Il potenziale noto al giocatore (-1 se non lo conosce).
func pv_noto(h: int, s: int) -> int:
	var e: Dictionary = pv.get(h, {})
	if e.is_empty():
		return -1
	if e["visto"].has(s):
		return valore_pv(h)
	return -1


## Potenziale di un esagono in cui c'è una porta (il gettone viene tolto quando la porta lo raggiunge).
func potenziale(h: int) -> int:
	var v = valore_pv(h)
	if v >= 0:
		return v
	var g = porta(h)
	if not g.is_empty():
		return int(g["sp"])
	return 0


func capacita(h: int, o: int) -> int:
	var s = stack(h, o)
	if s.is_empty():
		return 0
	return int(s["r"]) + 2 * int(s["d"])


func vista_porta(h: int, o: int) -> bool:
	# esiste una porta amica o alleata in vista?
	for g in porte:
		if porta_utile(g, o) and (ignora("polvere") or D.vista(h, g)):
			return true
	return false


func esploratori_di(o: int) -> int:
	var t := 0
	for h in flotte:
		var s = stack(h, o)
		if not s.is_empty():
			t += int(s["e"])
	return t


func totale_flotte(o: int) -> Dictionary:
	var t = {"r": 0, "d": 0, "e": 0}
	for h in flotte:
		var s = stack(h, o)
		if not s.is_empty():
			for k in ["r", "d", "e"]:
				t[k] += int(s[k])
	return t


func dado() -> int:
	return rng.randi_range(1, 6)


# ================================================================ partita

func run() -> void:
	log_msg("Scenario %s: %s." % [sc["numero"], sc["titolo"]])
	if sc.get("pre_schieramento", false):
		await _pre_schieramento()
	_controlla_eliminati()
	while not over and not abort:
		turn += 1
		mosse_turno.clear()
		log_msg("— Turno %d —" % turn)
		await _ordine_spostamento()
		if over: break
		await _fase_spostamento()
		if over: break
		await _fase_esplorazione()
		await _segmento_contatto()
		await _segmento_interazione()
		await _segmento_conflitto()
		_controlla_eliminati()
		if over: break
		await _segmento_riduzione()
		_controlla_eliminati()
		if over: break
		await _fase_fato()
		_controlla_eliminati()
		if over: break
		await _fase_risorse()
		_controlla_eliminati()
		_snapshot()
		_vittoria()
		if not over and int(config.get("max_turni", 0)) > 0 and turn >= int(config.get("max_turni", 0)):
			_fine({"winner": -1, "reason": "limite di turni della prova"})
		changed.emit()
	if not over:
		_fine({"winner": -1, "reason": "partita interrotta"})


func _fine(r: Dictionary) -> void:
	if over:
		return
	over = true
	result = r
	phase = "fine"
	log_msg("FINE: " + str(r.get("reason", "")))
	changed.emit()
	game_ended.emit(r)


func _snapshot() -> void:
	var sn = {"turno": turn, "porte": porte.duplicate(true), "flotte": {}, "fari": fari.duplicate(), "contatti": contatti.duplicate()}
	for h in flotte:
		sn["flotte"][h] = {}
		for o in flotte[h]:
			var s: Dictionary = flotte[h][o]
			sn["flotte"][h][o] = {"r": s["r"], "d": s["d"], "e": s["e"]}
	sn["mosse"] = mosse_turno.duplicate(true)
	history.append(sn)


# ================================================================ A. ordine di spostamento

func _ordine_spostamento() -> void:
	phase = "ordine"
	var vv = vivi()
	if vv.is_empty():
		_fine({"winner": -1, "reason": "nessun giocatore rimasto"})
		return
	var candidati = vv.duplicate()
	var primo := -1
	while primo < 0:
		var best := -1
		var tied := []
		for s in candidati:
			var c: Array = D.GETTONI_PV[rng.randi_range(0, D.GETTONI_PV.size() - 1)]
			var tot: int = int(c[0]) + int(c[1]) + int(c[2])
			if tot > best:
				best = tot
				tied = [s]
			elif tot == best:
				tied.append(s)
		if tied.size() == 1:
			primo = tied[0]
		else:
			candidati = tied
	ordine.clear()
	var n = players.size()
	for k in n:
		var s = (primo + k) % n
		if players[s]["vivo"]:
			ordine.append(s)
	if vv.size() > 1:
		log_msg("Ordine di spostamento: " + ", ".join(ordine.map(func(x): return fazione(x))))
	changed.emit()


# ================================================================ B. spostamenti

func _fase_spostamento() -> void:
	for h in flotte:
		for o in flotte[h]:
			flotte[h][o]["m"] = {"r": 0, "d": 0, "e": 0}
	phase = "spostamento"
	for s in ordine:
		if over or not players[s]["vivo"]:
			continue
		await _spostamenti_giocatore(s, false)
	phase = "autonomi"
	await _muovi_autonomi()
	phase = "riserva"
	var rev = ordine.duplicate()
	rev.reverse()
	for s in rev:
		if over or not players[s]["vivo"]:
			continue
		await _spostamenti_giocatore(s, true)


## Forze che possono ancora spostarsi: esagoni con flotte libere.
func forze_libere(s: int) -> Array:
	var out := []
	for h in flotte:
		var l = liberi(h, s)
		if l["r"] + l["d"] + l["e"] > 0:
			out.append(h)
	out.sort()
	return out


func _spostamenti_giocatore(s: int, riserva: bool) -> void:
	var fatti := 0
	var guard := 0
	while not over and guard < 200:
		guard += 1
		if riserva and fatti >= 1:
			return
		var libere = forze_libere(s)
		if libere.is_empty():
			return
		var req = {"type": "mossa", "riserva": riserva, "libere": libere}
		var r = await decide(s, req)
		if r == null or not (r is Dictionary) or r.get("fine", false):
			return
		var ok = await _esegui_mossa(s, r, riserva)
		if ok:
			fatti += 1


## Controlla se uno spostamento è permesso. Restituisce "" se va bene, altrimenti il motivo.
func mossa_valida(s: int, da: int, a: int, fl: Dictionary, riserva := false, prosegue := false) -> String:
	if not D.esiste(a) or da == a:
		return "destinazione non valida"
	var l = liberi(da, s)
	var n := 0
	for k in ["r", "d", "e"]:
		var q := int(fl.get(k, 0))
		if q < 0 or (not prosegue and q > int(l[k])):
			return "flotte non disponibili"
		n += q
	if n <= 0:
		return "nessuna flotta scelta"
	var dist = D.distanza(da, a)
	var raggio = clr(s)
	if riserva and dist > raggio:
		return "lo spostamento di riserva non può superare il raggio di sicurezza (%d)" % raggio
	if dist > raggio and not porta_utile(da, s):
		return "oltre il raggio di sicurezza (%d) si parte solo da una porta amica o alleata" % raggio
	if not ignora("polvere") and dist > 1 and D.attraverso_polvere(da, a):
		if not (porta_utile(da, s) and porta_utile(a, s)):
			return "attraverso la polvere interstellare solo da porta a porta amiche o alleate"
	return ""


## Modificatore del dado di dispersione.
func mod_dispersione(o: int, a: int, fl: Dictionary) -> int:
	var m := 0
	if porta_utile(a, o):
		m += 1
	if faro(a):
		m += 1
	var e := int(fl.get("e", 0))
	var tot = int(fl.get("r", 0)) + int(fl.get("d", 0)) + e
	if e > 0 and e == tot:
		m += 2
	elif e > 0:
		m += 1
	var l = cl_spostamento(o)
	if l > 1:
		m += l - 1
	return m


func tabella_dispersione() -> Array:
	match str(opz.get("tabelle", "originali")):
		"skygazer":
			return D.DISP_SKYGAZER
		"v3":
			return D.DISP_V3
	return D.DISP_ORIGINALE


## Probabilità di dispersione (per l'interfaccia): restituisce i risultati possibili per dado 1..6.
func rischio(o: int, da: int, a: int, fl: Dictionary) -> Dictionary:
	var dist = D.distanza(da, a)
	if dist <= 1:
		return {"dist": dist, "rischio": 0, "mod": 0}
	var m = mod_dispersione(o, a, fl)
	var c = D.col_dispersione(dist)
	var tab = tabella_dispersione()
	var cattivi := 0
	var peggiore := ""
	for d in range(1, 7):
		var r = d + m
		if r <= 9 and str(tab[r - 1][c]) != "":
			cattivi += 1
			if peggiore == "":
				peggiore = str(tab[r - 1][c])
	return {"dist": dist, "rischio": cattivi, "mod": m, "peggiore": peggiore, "oltre": dist > clr(o)}


## Esegue uno spostamento (con eventuali proseguimenti). r = {"da","a","r","d","e","sag"}
func _esegui_mossa(s: int, r: Dictionary, riserva: bool) -> bool:
	var da := int(r.get("da", 0))
	var a := int(r.get("a", 0))
	var fl = {"r": int(r.get("r", 0)), "d": int(r.get("d", 0)), "e": int(r.get("e", 0))}
	var err = mossa_valida(s, da, a, fl, riserva)
	if err != "":
		log_msg("Spostamento rifiutato: " + err, s)
		return false
	# gettoni saggezza: quelli già trasportati vanno con la forza; si può prendere quello del centro
	var carico: Array = []
	var st = stack(da, s)
	if not st.is_empty() and not st["sag"].is_empty():
		var tutte = liberi(da, s)
		if fl["r"] + fl["d"] + fl["e"] >= tutte["r"] + tutte["d"] + tutte["e"] or r.get("sag", 0) > 0:
			carico = st["sag"].duplicate()
			st["sag"].clear()
	if sag_centro.has(da) and int(r.get("sag", 0)) > 0 and usa_saggezza_in_gioco():
		carico.append(sag_centro[da])
		sag_centro.erase(da)
		log_msg("%s prende il gettone saggezza dell'esagono %s." % [fazione(s), D.nome(da)])
		if not sag_pool.is_empty():
			sag_centro[da] = sag_pool.pop_at(rng.randi_range(0, sag_pool.size() - 1))
	_togli(da, s, fl)
	var pos = da
	var dest = a
	var forza = fl
	var primo := true
	while true:
		var esito = await _salto(s, pos, dest, forza, carico)
		if esito["perso"]:
			return true
		pos = int(esito["h"])
		forza = esito["forza"]
		var puo_proseguire: bool = esito["ok"] and not esito["oltre"] and porta_utile(pos, s)
		_atterra(s, pos, forza, carico)
		carico = []
		if not puo_proseguire:
			return true
		var req = {"type": "prosegui", "da": pos, "forza": forza, "riserva": riserva}
		var rr = await decide(s, req)
		if rr == null or not (rr is Dictionary) or rr.get("fine", false) or not rr.has("a"):
			return true
		var nuovo := int(rr["a"])
		var err2 = mossa_valida(s, pos, nuovo, forza, riserva, true)
		if err2 != "":
			log_msg("Proseguimento rifiutato: " + err2, s)
			return true
		# la forza riparte: si toglie dalla pila d'arrivo
		var st2 = stack(pos, s)
		if not st2.is_empty() and not st2["sag"].is_empty():
			carico = st2["sag"].duplicate()
			st2["sag"].clear()
		_togli(pos, s, forza, false)
		dest = nuovo
		primo = false
	return true


## Un singolo salto. Restituisce {"ok": arrivato dove voleva, "perso": forza eliminata, "h", "forza", "oltre"}.
func _salto(o: int, da: int, a: int, forza: Dictionary, carico: Array) -> Dictionary:
	var dist = D.distanza(da, a)
	var raggio = clr(o)
	var oltre = dist > raggio
	var autonomo = o >= 10
	var gil: bool = opz.get("gilham", false) and not autonomo
	var esito = {"ok": true, "perso": false, "h": a, "forza": forza, "oltre": oltre}
	var desc = "%s: %d %s da %s a %s (%d %s)" % [fazione(o), _n(forza), "flotta" if _n(forza) == 1 else "flotte", D.nome(da), D.nome(a), dist, "esagono" if dist == 1 else "esagoni"]
	if dist >= 2:
		var m = mod_dispersione(o, a, forza)
		var d = dado()
		var tot = d + m
		var tab = tabella_dispersione()
		var cella := ""
		if tot <= 9:
			cella = str(tab[tot - 1][D.col_dispersione(dist)])
		if cella != "":
			var parti = cella.split("/")
			var sd := int(parti[0])
			var perc := int(parti[1])
			var n = _n(forza)
			var persi := 0
			if not autonomo:
				persi = D.perdite(n, perc, opz.get("conv_rivista", false))
				if oltre:
					persi = mini(n, persi * 2)
			forza = _perdi(forza, persi, o)
			if gil:
				# variante Gilham: le forze dei giocatori subiscono solo le perdite, senza dispersione
				log_msg(desc + ": dado %d%+d, perdite %d%% (%d flotte)." % [d, m, perc, persi], o, "%s si sposta a %s con perdite." % [fazione(o), D.nome(a)])
				esito["forza"] = forza
				esito["ok"] = false
				if _n(forza) <= 0:
					_perdi_carico(carico, o)
					esito["perso"] = true
					mosse_turno.append({"o": o, "da": da, "a": a, "perso": true})
				else:
					mosse_turno.append({"o": o, "da": da, "a": a})
				return esito
			var dir = dado()
			var finale = D.passo(a, dir, sd)
			esito["ok"] = false
			var motivo := ""
			if _n(forza) <= 0:
				motivo = "tutte le flotte perdute"
			elif not D.esiste(finale):
				motivo = "disperse fuori dalla mappa"
			elif D.nucleo(da) or D.nucleo(a):
				motivo = "dispersione nel Nucleo"
			elif not autonomo and not porta_utile(a, o) and not vista_porta(finale, o):
				motivo = "nessuna porta amica in vista"
			if autonomo and motivo == "nessuna porta amica in vista":
				motivo = ""
			if motivo != "":
				log_msg(desc + ": DISPERSIONE (dado %d%+d), %s." % [d, m, motivo], -1)
				fx.emit("disperso", {"o": o, "da": da, "a": a, "h": finale})
				mosse_turno.append({"o": o, "da": da, "a": a, "perso": true})
				_perdi_carico(carico, o)
				esito["perso"] = true
				return esito
			log_msg(desc + ": dispersione di %d esagoni verso %d (dado %d%+d), perdite %d." % [sd, dir, d, m, persi], o, "%s: dispersione, la forza finisce in %s." % [fazione(o), D.nome(finale)])
			fx.emit("disperso", {"o": o, "da": da, "a": a, "h": finale})
			mosse_turno.append({"o": o, "da": da, "a": finale, "disp": a})
			esito["h"] = finale
			esito["forza"] = forza
			await _pace(0.8)
			return esito
	log_msg(desc + ".", o, "%s si sposta da %s a %s." % [fazione(o), D.nome(da), D.nome(a)])
	fx.emit("salto", {"o": o, "da": da, "a": a})
	mosse_turno.append({"o": o, "da": da, "a": a})
	esito["forza"] = forza
	# scoperta di nuove stelle faro (15.0)
	if not autonomo and not ignora("fari") and not D.nucleo(a):
		var visibile := false
		for f in fari:
			if D.vista(a, f) and D.distanza(a, f) <= 30:
				visibile = true
				break
		if not visibile:
			_scopri_fari(a, o, true)
	await _pace(0.5)
	return esito


func _n(fl: Dictionary) -> int:
	return int(fl.get("r", 0)) + int(fl.get("d", 0)) + int(fl.get("e", 0))


## Toglie n flotte da una forza secondo la preferenza: prima regolari, poi esploratrici, poi corazzate.
func _perdi(fl: Dictionary, n: int, o: int) -> Dictionary:
	var out = fl.duplicate()
	var ordine_perdite = ["r", "e", "d"]
	if o >= 0 and o < 10 and players[o].get("perdite", "") == "esploratrici":
		ordine_perdite = ["e", "r", "d"]
	for k in ordine_perdite:
		var q: int = mini(n, int(out[k]))
		out[k] = int(out[k]) - q
		n -= q
	return out


func _perdi_carico(carico: Array, o: int) -> void:
	for c in carico:
		sag_pool.append(c)
	if not carico.is_empty():
		log_msg("Il gettone saggezza trasportato da %s è perduto e torna fuori dalla mappa." % fazione(o))


func _atterra(o: int, h: int, forza: Dictionary, carico: Array) -> void:
	_aggiungi(h, o, forza, true)
	if carico.is_empty():
		return
	if o < 10 and porta_propria(h, o):
		var p: Dictionary = players[o]
		for c in carico:
			var limite := 3
			if p["x"] and str(sc.get("x_regola", "")) == "5":
				limite = 99
			if c == 9:
				_prendi_x(o)
				if over:
					return
				continue
			if p["sag"].size() >= limite:
				sag_pool.append(c)
				log_msg("%s ha già tre gettoni saggezza: quello nuovo torna fuori dalla mappa." % fazione(o))
			else:
				p["sag"].append(c)
				log_msg("%s porta un gettone saggezza a una porta amica (ora ne controlla %d)." % [fazione(o), p["sag"].size()])
	else:
		var st = stack(h, o)
		if not st.is_empty():
			st["sag"].append_array(carico)


func _prendi_x(o: int) -> void:
	var p: Dictionary = players[o]
	p["x"] = true
	if sc.get("x_perde", false):
		log_msg("%s prende il gettone X: il Nucleo è esploso e l'onda si espande alla velocità della luce. Restano circa quaranta milioni di anni per evacuare la Galassia." % fazione(o))
		_fine({"winner": -1, "reason": "il gettone X: il Nucleo è esploso, partita persa", "perso": o})
		return
	log_msg("%s controlla un gettone saggezza." % fazione(o), -1)
	log_msg("È il gettone X!", o)


## Stelle faro scoperte (15.1): 1d6+2 nuove stelle in esagoni visibili dalla forza.
func _scopri_fari(h: int, o: int, annuncia: bool) -> void:
	var n = dado() + 2
	var cand := []
	var r0 = D.row(h)
	var c0 = D.col(h)
	for c in range(c0 - 8, c0 + 9):
		for rr in range(r0 - 6, r0 + 7):
			var x = D.hx(c, rr)
			if not D.esiste(x) or x == h or fari.has(x) or D.nucleo(x):
				continue
			if D.col(x) == c0 or D.row(x) == r0:
				continue
			var dd = D.distanza(h, x)
			if dd < 2 or dd > 8:
				continue
			if not D.vista(h, x):
				continue
			cand.append(x)
	var messi := []
	while n > 0 and not cand.is_empty():
		var x: int = cand.pop_at(rng.randi_range(0, cand.size() - 1))
		fari[x] = ""
		messi.append(x)
		n -= 1
	if annuncia and not messi.is_empty():
		log_msg("%s scopre %d nuove stelle faro: %s." % [fazione(o), messi.size(), ", ".join(messi.map(func(x): return D.nome(x)))])
		fx.emit("fari", {"h": h, "fari": messi})


# ================================================================ forze autonome: movimento

func _muovi_autonomi() -> void:
	for i in 4:
		var A: Dictionary = aut[i]
		if not A["presente"] or not A["attiva"]:
			continue
		var o = 10 + i
		var mie = porte_di(o)
		var ostili := []
		for s in vivi():
			if opzione(o, s) == "C":
				ostili.append(s)
		var pile := []
		for h in flotte:
			if n_flotte(h, o) > 0:
				pile.append(h)
		if mie.is_empty():
			continue
		if ostili.is_empty():
			# 13.24: tutte le flotte nelle esagoni con porte proprie, concentrandosi dove ci sono giocatori
			for h in pile:
				if porta_propria(h, o):
					continue
				var best = _porta_vicina(h, mie)
				if best > 0:
					var fl: Dictionary = liberi(h, o)
					_togli(h, o, fl)
					var e = await _salto(o, h, best, fl, [])
					if not e["perso"]:
						_aggiungi(int(e["h"]), o, e["forza"], true)
			var occupate := []
			for h in mie:
				for p in proprietari(h):
					if p < 10:
						occupate.append(h)
						break
			if not occupate.is_empty():
				for h in mie:
					if h in occupate:
						continue
					var fl2: Dictionary = liberi(h, o)
					if _n(fl2) > 0:
						var t: int = occupate[rng.randi_range(0, occupate.size() - 1)]
						_togli(h, o, fl2)
						var e2 = await _salto(o, h, t, fl2, [])
						if not e2["perso"]:
							_aggiungi(int(e2["h"]), o, e2["forza"], true)
			continue
		# 13.31: una forza di guardia (tante flotte quante porte), il resto attacca la porta ostile più vicina in vista
		var tot := 0
		for h in pile:
			tot += n_flotte(h, o)
		var guardia = mie.size()
		var eccesso = tot - guardia
		if eccesso <= 0:
			continue
		var bersaglio := -1
		var bd := 999
		var origine := -1
		for h in pile:
			for g in porte:
				var pg: Dictionary = porte[g]
				if pg["neut"] or not (int(pg["o"]) in ostili):
					continue
				if not D.vista(h, g):
					continue
				var dd = D.distanza(h, g)
				if dd < bd:
					bd = dd
					bersaglio = g
					origine = h
		if bersaglio < 0:
			continue
		# raccoglie l'eccesso dalle pile (le flotte in più rispetto a una per porta)
		var forza = {"r": 0, "d": 0, "e": 0}
		var da_prendere = eccesso
		for h in pile:
			if da_prendere <= 0:
				break
			var lib = liberi(h, o)
			var tenere = 1 if porta_propria(h, o) else 0
			var disp = _n(lib) - tenere
			if disp <= 0:
				continue
			var q := mini(disp, da_prendere)
			var preso = {"r": 0, "d": 0, "e": 0}
			for k in ["d", "r"]:
				var x: int = mini(q, int(lib[k]))
				preso[k] = x
				q -= x
			_togli(h, o, preso)
			for k in preso:
				forza[k] += preso[k]
			da_prendere -= _n(preso)
		if _n(forza) <= 0:
			continue
		var e3 = await _salto(o, origine, bersaglio, forza, [])
		if not e3["perso"]:
			_aggiungi(int(e3["h"]), o, e3["forza"], true)


func _porta_vicina(h: int, lista: Array) -> int:
	var best := -1
	var bd := 999
	for g in lista:
		var d = D.distanza(h, g)
		if d < bd:
			bd = d
			best = g
	return best


# ================================================================ C. esplorazione

func esplorabili(s: int) -> Array:
	var out := []
	for h in flotte:
		if n_flotte(h, s) <= 0:
			continue
		if D.nucleo(h):
			continue
		if porte.has(h):
			continue
		if players[s]["esplorati"].has(h) and (not pv.has(h) or pv[h]["visto"].has(s)):
			continue
		out.append(h)
	out.sort()
	return out


func _fase_esplorazione() -> void:
	phase = "esplorazione"
	esplorati_turno.clear()
	for s in ordine:
		if not players[s]["vivo"]:
			continue
		var es = esplorabili(s)
		if es.is_empty():
			continue
		var r = await decide(s, {"type": "esplora", "esagoni": es})
		var scelti: Array = r if r is Array else es
		esplorati_turno[s] = []
		for h0 in scelti:
			var h := int(h0)
			if not (h in es):
				continue
			esplorati_turno[s].append(h)
			var st = stack(h, s)
			var n = 2 * int(st["e"]) + int(st["r"]) + int(st["d"])
			var col = D.col_esplorazione(n)
			var d = dado()
			if d <= col + 1:
				_esplora_riuscita(s, h)
			else:
				log_msg("%s: esplorazione di %s fallita (dado %d)." % [fazione(s), D.nome(h), d], s, "%s tenta di esplorare %s, senza successo." % [fazione(s), D.nome(h)])
		changed.emit()
		await _pace(0.4)


func _esplora_riuscita(s: int, h: int) -> void:
	var p: Dictionary = players[s]
	if not pv.has(h):
		if pv_pool.is_empty():
			pv[h] = {"c": -1, "v": 0, "visto": {}}
		else:
			pv[h] = {"c": pv_pool.pop_back(), "v": 0, "visto": {}}
	pv[h]["visto"][s] = true
	p["esplorati"][h] = true
	var v = valore_pv(h)
	log_msg("%s esplora %s: potenziale %d." % [fazione(s), D.nome(h), v], s, "%s esplora %s." % [fazione(s), D.nome(h)])
	fx.emit("esplora", {"o": s, "h": h})
	if opz.get("gilham", false):
		var pc = rng.randi_range(1, 100)
		if pc < 100:
			var guadagno := int(v * 10 / maxi(1, cl(s)))
			p["cp"] = int(p["cp"]) + guadagno
			if guadagno > 0:
				log_msg("%s guadagna %d punti civiltà dall'esplorazione." % [fazione(s), guadagno], s)
		else:
			var r20 = rng.randi_range(1, 20)
			var ris := "W"
			if r20 <= 4: ris = "G"
			elif r20 <= 7: ris = "H"
			elif r20 <= 9: ris = "I"
			elif r20 == 10: ris = "J"
			log_msg("%s: risultato straordinario dell'esplorazione (%s)." % [fazione(s), ris])
			if ris == "W":
				_gil_saggezza(s, h)
			else:
				esplorati_turno[s] = [h]
				_comparsa_autonomi(s, ris)


func _gil_saggezza(s: int, h: int) -> void:
	var p: Dictionary = players[s]
	var c: int = -1
	if not sag_pool.is_empty():
		c = sag_pool.pop_at(rng.randi_range(0, sag_pool.size() - 1))
		sag_pool.append(c)
	if c == 9 and str(sc.get("x_regola", "")) != "" and not p["x"]:
		p["x"] = true
		log_msg("È il gettone X!", s)
		if sc.get("x_perde", false):
			_fine({"winner": -1, "reason": "il gettone X: il Nucleo è esploso, partita persa", "perso": s})
			return
	var pc = rng.randi_range(1, 100)
	var g := 80
	if pc == 100: g = 10000
	elif pc >= 91: g = 5000
	elif pc >= 76: g = 3000
	elif pc >= 51: g = 2000
	if ignora("nucleo"):
		return
	if p["x"] and str(sc.get("x_regola", "")) == "4":
		g *= 2
	g = g / maxi(1, cl(s))
	p["cp"] = int(p["cp"]) + g
	log_msg("%s scopre un esagono della saggezza: %d punti civiltà." % [fazione(s), g])


# ================================================================ D1. contatto

func gruppi(h: int) -> Array:
	var out = proprietari(h)
	var g = porta(h)
	if not g.is_empty() and not g["neut"] and not (int(g["o"]) in out):
		out.append(int(g["o"]))
	out.sort()
	return out


func _tutti_alleati(gs: Array) -> bool:
	for i in gs.size():
		for j in range(i + 1, gs.size()):
			var a: int = gs[i]
			var b: int = gs[j]
			if a >= 10 and b >= 10:
				continue
			if not alleati(a, b):
				return false
	return true


func _solo_autonomi(gs: Array) -> bool:
	var giocatori := 0
	for g in gs:
		if g < 10:
			giocatori += 1
	return giocatori == 0


## Esagoni in cui serve una prova di contatto.
func casi_contatto() -> Array:
	var out := []
	for h in _esagoni_occupati():
		var gs = gruppi(h)
		if gs.size() < 2 or _solo_autonomi(gs):
			continue
		if _tutti_alleati(gs):
			continue
		if contatti.has(h):
			continue
		out.append(h)
	out.sort()
	return out


func _esagoni_occupati() -> Array:
	var hs := {}
	for h in flotte:
		hs[h] = true
	for h in porte:
		if not porte[h]["neut"]:
			hs[h] = true
	var out = hs.keys()
	out.sort()
	return out


func indice_max(h: int, o: int) -> int:
	var s = stack(h, o)
	var t := 0
	if not s.is_empty():
		t = int(s["e"]) + int(s["r"]) + int(s["d"]) + int(s["e"])
	if porta_propria(h, o):
		t += int(porte[h]["sp"])
	return t


func indice_min(h: int, o: int) -> int:
	if porta_propria(h, o):
		return int(porte[h]["sp"])
	return 0


func _segmento_contatto() -> void:
	phase = "contatto"
	# i segnalini restano dove ci sono ancora parti non alleate
	for h in contatti.keys():
		var gs = gruppi(h)
		if gs.size() < 2 or _tutti_alleati(gs) or _solo_autonomi(gs):
			contatti.erase(h)
	var casi = casi_contatto()
	# 7.25: catena di alleanze A-B, B-C con A e C non alleati: contatto automatico
	for h in casi.duplicate():
		var gs = gruppi(h)
		if gs.size() >= 3:
			var catena := false
			for x in gs:
				for y in gs:
					for z in gs:
						if x != y and y != z and x != z and alleati(x, y) and alleati(y, z) and not alleati(x, z):
							catena = true
			if catena:
				contatti[h] = true
				casi.erase(h)
				log_msg("Contatto automatico in %s (catena di alleanze)." % D.nome(h))
	if casi.is_empty():
		changed.emit()
		return
	# le richieste ai giocatori (simultanee)
	var seats := []
	var reqs := []
	for s in vivi():
		var cs := []
		for h in casi:
			if s in gruppi(h):
				cs.append({"h": h, "min": indice_min(h, s), "max": indice_max(h, s), "altri": gruppi(h).filter(func(x): return x != s)})
		if not cs.is_empty():
			seats.append(s)
			reqs.append({"type": "contatto", "casi": cs})
	var risposte := {}
	if not seats.is_empty():
		var rr: Array = await decide_all(seats, reqs)
		for i in seats.size():
			risposte[seats[i]] = rr[i] if rr[i] is Dictionary else {}
	for h in casi:
		var c := false
		var dettagli := []
		for o in gruppi(h):
			var idx := 0
			if o >= 10:
				var A: Dictionary = aut[o - 10]
				if A["attiva"]:
					idx = indice_max(h, o)
				else:
					idx = n_flotte(h, o) + (3 if porta_propria(h, o) else 0)
			else:
				var rs: Dictionary = risposte.get(o, {})
				idx = clampi(int(rs.get(h, rs.get(str(h), indice_max(h, o)))), indice_min(h, o), indice_max(h, o))
			var d = dado()
			var ok = d <= D.col_contatto(idx)
			dettagli.append("%s indice %d dado %d" % [fazione(o), idx, d])
			if ok:
				c = true
		if c:
			contatti[h] = true
			log_msg("CONTATTO in %s (%s)." % [D.nome(h), "; ".join(dettagli)])
			fx.emit("contatto", {"h": h})
		else:
			log_msg("Nessun contatto in %s." % D.nome(h))
	changed.emit()
	await _pace(0.5)


## Coppie in contatto in questo turno: per ogni giocatore, le parti con cui è in contatto.
func in_contatto(s: int) -> Array:
	var out := {}
	for h in _esagoni_occupati():
		var gs = gruppi(h)
		if not (s in gs):
			continue
		for o in gs:
			if o == s:
				continue
			if contatti.has(h) or alleati(s, o):
				out[o] = true
	var k = out.keys()
	k.sort()
	return k


# ================================================================ D2. interazione

func _segmento_interazione() -> void:
	phase = "interazione"
	cambio_c.clear()
	var seats := []
	var reqs := []
	for s in vivi():
		var parti = in_contatto(s)
		if parti.is_empty():
			continue
		var attuali := {}
		var nuovi := []
		for o in parti:
			attuali[o] = opzione(s, o)
			if attuali[o] == "":
				nuovi.append(o)
		seats.append(s)
		reqs.append({"type": "interazione", "parti": parti, "attuali": attuali, "nuovi": nuovi, "loro": _loro(s, parti)})
	if not seats.is_empty():
		var rr: Array = await decide_all(seats, reqs)
		for i in seats.size():
			var s: int = seats[i]
			var r = rr[i]
			var scelte: Dictionary = r if r is Dictionary else {}
			for o in reqs[i]["parti"]:
				var prima = opzione(s, o)
				var v := str(scelte.get(o, scelte.get(str(o), prima if prima != "" else "B")))
				if not (v in ["A", "B", "C"]):
					v = "B"
				# 18.44: chi ha la X non può scegliere C se l'altro non l'ha scelto per primo
				if v == "C" and players[s]["x"] and str(sc.get("x_regola", "")) == "4" and opzione(o, s) != "C":
					v = "B"
				if (prima == "C") != (v == "C") and prima != "":
					cambio_c[s] = true
				if v == "C" and prima == "":
					cambio_c[s] = true
				opt["%d:%d" % [s, o]] = v
				if prima != v:
					log_msg("%s sceglie %s verso %s." % [fazione(s), v, fazione(o)], s)
	# opzioni delle forze autonome
	for s in vivi():
		for o in in_contatto(s):
			if o < 10:
				continue
			var A: Dictionary = aut[o - 10]
			var k = "%d:%d" % [o, s]
			if A["custode"] < 0:
				A["custode"] = s
				log_msg("%s diventa custode della forza autonoma %s." % [fazione(s), D.COLORI_AUT[o - 10]])
			var prima = opzione(o, s)
			var nuova = prima
			if attaccati.has("%d:%d" % [o, s]):
				nuova = "C"
			elif prima == "":
				nuova = D.RIOT[dado() - 1][3]
			elif cambio_c.has(s):
				nuova = D.RIOT[dado() - 1]["ABC".find(prima)]
			if nuova != prima:
				opt[k] = nuova
				log_msg("La forza autonoma %s sceglie %s verso %s." % [D.COLORI_AUT[o - 10], nuova, fazione(s)])
				if opt.get("%d:%d" % [s, o], "") == "":
					opt["%d:%d" % [s, o]] = "B"
			A["attiva"] = true
			if opz.get("gilham", false) and not A["visti"].has(s):
				A["visti"][s] = true
				var base: int = {1: 100, 2: 800}.get(int(A["cl"]), 100)
				base = int(A.get("cp_val", base))
				var g = base / maxi(1, cl(s))
				players[s]["cp"] = int(players[s]["cp"]) + g
				log_msg("%s guadagna %d punti civiltà dal contatto con gli autonomi." % [fazione(s), g], s)
	attaccati.clear()
	# variante Gilham: trasferimento di punti civiltà fra giocatori in contatto
	if opz.get("gilham", false):
		var fatti := {}
		for s in vivi():
			for o in in_contatto(s):
				if o >= 10 or fatti.has("%d:%d" % [o, s]):
					continue
				fatti["%d:%d" % [s, o]] = true
				_gil_trasferisci(s, o)
				_gil_trasferisci(o, s)
	changed.emit()


func _loro(s: int, parti: Array) -> Dictionary:
	var out := {}
	for o in parti:
		out[o] = opzione(o, s)
	return out


func _gil_trasferisci(donatore: int, ricevente: int) -> void:
	var od = opzione(donatore, ricevente)
	var orr = opzione(ricevente, donatore)
	if od == "" or orr == "" or od == "C":
		return
	var base := 0
	var x = rng.randi_range(1, 10)
	if od == "A":
		base = x * 100 if orr != "C" else x * 10
	else:
		if orr == "A": base = x * 50
		elif orr == "B": base = x * 20
		else: base = x * 10
	var tot := int(base * maxi(1, cl(donatore)) / maxi(1, cl(ricevente)))
	tot = mini(tot, int(players[donatore]["cp"]))
	players[ricevente]["cp"] = int(players[ricevente]["cp"]) + tot
	if tot > 0:
		log_msg("%s riceve %d punti civiltà dal contatto con %s." % [fazione(ricevente), tot, fazione(donatore)], ricevente)


# ================================================================ D3. conflitto

func _segmento_conflitto() -> void:
	phase = "conflitto"
	var hs = contatti.keys()
	hs.sort()
	for h in hs:
		if over:
			return
		await _conflitto_in(h)
	changed.emit()


func bersagli(h: int, o: int) -> Array:
	var out := []
	for t in proprietari(h):
		if t != o and puo_attaccare(o, t):
			out.append(t)
	return out


func _conflitto_in(h: int) -> void:
	var parti = proprietari(h)
	if parti.size() < 2:
		return
	var seats := []
	var reqs := []
	var dich := {}
	for o in parti:
		var bs = bersagli(h, o)
		if bs.is_empty():
			continue
		if o >= 10:
			var ostili = bs.filter(func(t): return opzione(o, t) == "C")
			if not ostili.is_empty():
				dich[o] = capacita(h, o)
			continue
		if not players[o]["vivo"]:
			continue
		var obb := false
		for t in bs:
			if obbligatorio(o, t):
				obb = true
		seats.append(o)
		reqs.append({"type": "attacco", "h": h, "bersagli": bs, "vera": capacita(h, o), "obbligatorio": obb})
	if not seats.is_empty():
		var rr: Array = await decide_all(seats, reqs)
		for i in seats.size():
			var o: int = seats[i]
			var r = rr[i]
			var att: bool = reqs[i]["obbligatorio"]
			var v = capacita(h, o)
			var dv = v
			if r is Dictionary:
				att = att or bool(r.get("attacca", false))
				dv = int(r.get("dich", v))
			if att and v > 0:
				var lo := int(floor(v * 0.5))
				var hi := int(ceil(v * 1.5))
				dich[o] = clampi(dv, lo, hi)
	if dich.is_empty():
		return
	var chi = dich.keys()
	chi.sort_custom(func(a, b): return dich[a] > dich[b] or (dich[a] == dich[b] and _pos(a) < _pos(b)))
	var dett := []
	for o in chi:
		dett.append("%s %d" % [fazione(o), dich[o]])
	log_msg("Conflitto in %s: capacità dichiarate %s." % [D.nome(h), ", ".join(dett)])
	for o in chi:
		if n_flotte(h, o) <= 0 or capacita(h, o) <= 0:
			continue
		var bs = bersagli(h, o)
		if o >= 10:
			bs = bs.filter(func(t): return opzione(o, t) == "C")
		if bs.is_empty():
			continue
		var t: int = bs[0]
		if bs.size() > 1:
			if o >= 10:
				t = bs[rng.randi_range(0, bs.size() - 1)]
			else:
				var r2 = await decide(o, {"type": "bersaglio", "h": h, "bersagli": bs})
				if r2 != null and int(r2) in bs:
					t = int(r2)
		await _attacco(h, o, t)
	await _pace(0.6)


func _pos(o: int) -> int:
	if o >= 10:
		return 100 + o
	var i = ordine.find(o)
	return i if i >= 0 else 50


func tabella_conflitto() -> Array:
	if str(opz.get("tabelle", "originali")) == "v3":
		return D.CONF_V3
	return D.CONF_ORIGINALE


func _attacco(h: int, a: int, d: int) -> void:
	var ca = capacita(h, a)
	var cd = capacita(h, d)
	if cd <= 0:
		cd = 1
	var col := mini(6, D.col_conflitto(ca, cd) + colonne_bonus(a, d))
	var sa = stack(h, a)
	var sd = stack(h, d)
	var dd = dado()
	var mod := int(sa["d"]) - int(sd["d"])
	var tiro := clampi(dd + mod, -2, 9)
	var cella: String = tabella_conflitto()[tiro + 2][col]
	var pp = cella.split("/")
	var pa := int(pp[0])
	var pd := int(pp[1])
	var riv: bool = opz.get("conv_rivista", false) or str(opz.get("tabelle", "")) == "v3"
	var na = n_flotte(h, a)
	var nd = n_flotte(h, d)
	var la = D.perdite(na, pa, riv)
	var ld = D.perdite(nd, pd, riv)
	if obbligatorio(a, d):
		ld = mini(nd, ld * 2)
	var fa = _perdi(_comp(h, a), la, a)
	var fd = _perdi(_comp(h, d), ld, d)
	if d >= 10:
		fd = _perdi_autonomo(_comp(h, d), ld)
	if a >= 10:
		fa = _perdi_autonomo(_comp(h, a), la)
	_imposta(h, a, fa)
	_imposta(h, d, fd)
	log_msg("%s (capacità %d) attacca %s (capacità %d) in %s: colonna %d, dado %d%+d = %d, risultato %s: perdite %d e %d." % [fazione(a), ca, fazione(d), capacita(h, d) if n_flotte(h, d) > 0 else cd, D.nome(h), col + 1, dd, mod, tiro, cella, la, ld])
	fx.emit("attacco", {"h": h, "a": a, "d": d})
	if d >= 10 and a < 10 and opzione(d, a) != "C":
		attaccati["%d:%d" % [d, a]] = true
	if opz.get("gilham", false):
		_gil_combattimento(a, d, ld, fd)
		_gil_combattimento(d, a, la, fa)
	if d >= 10:
		_controlla_autonomo(d - 10)
	if a >= 10:
		_controlla_autonomo(a - 10)
	changed.emit()
	await _pace(0.6)


func _gil_combattimento(vincitore: int, perdente: int, n: int, _f: Dictionary) -> void:
	if vincitore >= 10 or n <= 0:
		return
	var v = n * 3 * maxi(1, cl(perdente)) / maxi(1, cl(vincitore))
	players[vincitore]["cp"] = int(players[vincitore]["cp"]) + v


func _comp(h: int, o: int) -> Dictionary:
	var s = stack(h, o)
	return {"r": int(s.get("r", 0)), "d": int(s.get("d", 0)), "e": int(s.get("e", 0))}


func _imposta(h: int, o: int, fl: Dictionary) -> void:
	var s = stack(h, o)
	if s.is_empty():
		return
	for k in ["r", "d", "e"]:
		s[k] = int(fl[k])
		s["m"][k] = mini(int(s["m"][k]), int(fl[k]))
	_pulisci(h, o)


## Le corazzate autonome si perdono per ultime (9.18).
func _perdi_autonomo(fl: Dictionary, n: int) -> Dictionary:
	var out = fl.duplicate()
	for k in ["r", "e", "d"]:
		var q: int = mini(n, int(out[k]))
		out[k] = int(out[k]) - q
		n -= q
	return out


# ================================================================ D4. riduzione

func _segmento_riduzione() -> void:
	phase = "riduzione"
	var hs = contatti.keys()
	hs.sort()
	for h in hs:
		var g = porta(h)
		if g.is_empty() or g["neut"]:
			continue
		var prop := int(g["o"])
		if n_flotte(h, prop) > 0:
			continue
		var cand := []
		for o in proprietari(h):
			if o == prop or int(stack(h, o)["d"]) <= 0:
				continue
			if not puo_attaccare(o, prop):
				continue
			cand.append(o)
		if cand.is_empty():
			continue
		var tentano := []
		var seats := []
		var reqs := []
		for o in cand:
			if o >= 10:
				if opzione(o, prop) == "C":
					tentano.append(o)
			elif players[o]["vivo"]:
				seats.append(o)
				reqs.append({"type": "riduzione", "h": h, "proprietario": prop})
		if not seats.is_empty():
			var rr: Array = await decide_all(seats, reqs)
			for i in seats.size():
				if (rr[i] is bool and rr[i]) or (rr[i] is Dictionary and rr[i].get("si", false)):
					tentano.append(seats[i])
		tentano.sort_custom(func(a, b): return _cap_rid(h, a) > _cap_rid(h, b))
		for o in tentano:
			if porta(h).is_empty() or porta(h)["neut"]:
				break
			var diff = _cap_rid(h, o) - (int(g["sp"]) + cl(prop))
			var col = D.col_riduzione(diff)
			var dd = dado()
			if col >= 0:
				col = mini(4, col + colonne_bonus(o, prop))
			if col >= 0 and dd <= col + 1:
				_neutralizza(h, "riduzione da parte di " + fazione(o))
				if prop >= 10 and o < 10:
					attaccati["%d:%d" % [prop, o]] = true
				if opz.get("gilham", false) and o < 10:
					players[o]["cp"] = int(players[o]["cp"]) + (10 + 4 * int(g["sp"])) * maxi(1, cl(prop)) / maxi(1, cl(o))
			else:
				log_msg("%s tenta di neutralizzare la porta di %s in %s: differenza %d, dado %d, nessun effetto." % [fazione(o), fazione(prop), D.nome(h), diff, dd])
			await _pace(0.5)
	changed.emit()


func _cap_rid(h: int, o: int) -> int:
	return int(stack(h, o).get("d", 0)) + cl(o)


func _neutralizza(h: int, motivo: String) -> void:
	var g: Dictionary = porte[h]
	var prop := int(g["o"])
	if int(g["sp"]) <= 0:
		porte.erase(h)
		pv[h] = {"c": -1, "v": 0, "visto": {}}
		log_msg("La porta di %s in %s (valore 0) è distrutta (%s)." % [fazione(prop), D.nome(h), motivo])
	else:
		g["neut"] = true
		g["prima"] = prop
		g["o"] = -1
		log_msg("La porta di %s in %s è neutralizzata (%s)." % [fazione(prop), D.nome(h), motivo])
	fx.emit("neutralizza", {"h": h})
	if prop >= 10:
		_controlla_autonomo(prop - 10)


func _controlla_autonomo(i: int) -> void:
	var A: Dictionary = aut[i]
	if not A["presente"]:
		return
	var o = 10 + i
	var ha = not porte_di(o).is_empty()
	for h in flotte:
		if n_flotte(h, o) > 0:
			ha = true
	if not ha:
		A["presente"] = false
		A["attiva"] = false
		log_msg("La forza autonoma %s è eliminata." % D.COLORI_AUT[i])
		for k in opt.keys():
			if str(k).begins_with("%d:" % o) or str(k).ends_with(":%d" % o):
				opt.erase(k)


func _controlla_eliminati() -> void:
	for s in players.size():
		var p: Dictionary = players[s]
		if not p["vivo"]:
			continue
		if porte_di(s).is_empty() or (opz.get("gilham", false) and int(p["cp"]) < 250) or (not opz.get("gilham", false) and int(p["cl"]) < 0):
			p["vivo"] = false
			for h in flotte.keys():
				if flotte.has(h) and flotte[h].has(s):
					flotte[h].erase(s)
					if flotte[h].is_empty():
						flotte.erase(h)
			for h in porte_di(s):
				_neutralizza(h, "eliminazione")
			log_msg("%s è eliminato dalla partita." % fazione(s))
			# 13.22: le forze autonome che avevano interagito solo con lui tornano passive
			for i in 4:
				var A: Dictionary = aut[i]
				if A["attiva"]:
					var ancora := false
					for t in vivi():
						if opzione(10 + i, t) != "":
							ancora = true
					if not ancora:
						A["attiva"] = false
	var vv = vivi()
	if vv.is_empty():
		_fine({"winner": -1, "reason": "tutti i giocatori eliminati"})
	elif vv.size() == 1 and players.size() > 1 and scn_id in [4, 5]:
		_fine({"winner": vv[0], "reason": "%s è l'unico giocatore rimasto" % fazione(vv[0])})


# ================================================================ E. fato

func _fase_fato() -> void:
	phase = "fato"
	for s in ordine:
		if over or not players[s]["vivo"]:
			continue
		await _fato_giocatore(s)
		_controlla_eliminati()


func tabella_fato() -> Array:
	if opz.get("gilham", false):
		return D.FATO_GILHAM
	if opz.get("fato_rivisto", false):
		return D.FATO_RIVISTO
	return D.FATO_ORIGINALE


func _fato_giocatore(s: int) -> void:
	var p: Dictionary = players[s]
	var sp = punti_sistema(s)
	var gil: bool = opz.get("gilham", false)
	var col0 = D.col_fato_gilham(sp) if gil else D.col_fato(sp)
	var req = {"type": "fato", "sp": sp, "rp": int(p["rp"]), "sag": p["sag"].size(), "colonna": col0, "gilham": gil}
	var r = await decide(s, req)
	var piu := 0
	var sx := 0
	var spesi := 0
	if r is Dictionary:
		piu = clampi(int(r.get("piu", 0)), 0, 2)
		sx = maxi(0, int(r.get("sx", 0)))
		spesi = clampi(int(r.get("sag", 0)), 0, p["sag"].size())
	if gil:
		piu = 0
	var costo = piu * 50 + sx * 5
	while costo > int(p["rp"]):
		if sx > 0:
			sx -= 1
		elif piu > 0:
			piu -= 1
		costo = piu * 50 + sx * 5
	p["rp"] = int(p["rp"]) - costo
	# 18.56: chi ha la X non può spendere gettoni saggezza per salire di civiltà
	var x5: bool = p["x"] and str(sc.get("x_regola", "")) == "5"
	if x5:
		spesi = 0
	var sag_val = spesi
	if p["x"] and str(sc.get("x_regola", "")) == "4":
		sag_val += 1
	for i in spesi:
		var c: int = p["sag"].pop_back()
		sag_pool.append(c)
	var col := maxi(0, col0 - sx)
	var d = dado()
	var tiro = d + mini(int(x_esplorazione.get(s, 0)), 6 - d)
	tiro = mini(tiro + piu, 8)
	var tab = tabella_fato()
	tiro = mini(tiro, tab.size())
	var ris: String = tab[tiro - 1][col]
	var testo = "Fato di %s: punti sistema %d, colonna %d, dado %d%s = %d" % [fazione(s), sp, col + 1, d, (" +%d" % piu) if piu > 0 else "", tiro]
	if spesi > 0:
		testo += ", %d gettoni saggezza spesi" % spesi
	if ris == "":
		log_msg(testo + ": nessun effetto.", s, "Fato di %s: nessun effetto." % fazione(s))
		return
	log_msg(testo + ": risultato %s." % ris, s, "Fato di %s: risultato %s." % [fazione(s), ris])
	fx.emit("fato", {"o": s, "r": ris})
	await _applica_fato(s, ris, sag_val)
	await _pace(0.6)


func _applica_fato(s: int, ris: String, sag_val: int) -> void:
	var p: Dictionary = players[s]
	var lettera = ris.substr(0, 1)
	var gil: bool = opz.get("gilham", false)
	if lettera in ["A", "B", "C", "D", "E", "F"]:
		if ignora("fato_AF", s) or ignora("dissoluzione", s):
			log_msg("(risultato ignorato in questo scenario)")
			return
		var ripetibile: bool = p["x"] and scn_id == 5 and players.size() == 1
		if p["immune"]:
			log_msg("%s ignora la dissoluzione (la Fede lo protegge)." % fazione(s))
			return
		if p["diss"].has(lettera) and not ripetibile:
			log_msg("%s ha già subito la dissoluzione %s: nessun effetto." % [fazione(s), lettera])
			return
		p["diss"][lettera] = true
		var perc: int = D.DISSOLUZIONE[lettera]
		log_msg("%s: %s" % [fazione(s), testo_fato(lettera)])
		await _dissoluzione(s, perc)
		if lettera == "B":
			p["immune"] = true
		if D.CALO_CIVILTA.has(lettera):
			if gil:
				p["cp"] = int(p["cp"]) / 2
				log_msg("%s dimezza i suoi punti civiltà (%d)." % [fazione(s), p["cp"]])
			else:
				p["cl"] = int(p["cl"]) - 1
				log_msg("%s scende al livello di civiltà %d." % [fazione(s), p["cl"]])
		return
	if lettera in ["G", "H", "I", "J"]:
		_comparsa_autonomi(s, lettera)
		return
	if lettera == "K":
		if ignora("fato_KL", s) or ignora("fato_K", s):
			log_msg("(risultato ignorato in questo scenario)")
			return
		if sag_val < 2 or p["k_usato"]:
			log_msg("Servivano due gettoni saggezza spesi (una sola volta per giocatore): nessun effetto.")
			return
		p["k_usato"] = true
		p["cl"] = int(p["cl"]) + 2
		log_msg("%s: %s Sale al livello di civiltà %d." % [fazione(s), testo_fato("K"), p["cl"]])
		_dopo_aumento(s)
		return
	if lettera == "L":
		if ignora("fato_KL", s):
			log_msg("(risultato ignorato in questo scenario)")
			return
		if ris == "L1" and sag_val < 1:
			log_msg("Serviva un gettone saggezza speso: nessun effetto.")
			return
		p["cl"] = int(p["cl"]) + 1
		log_msg("%s: %s Sale al livello di civiltà %d." % [fazione(s), testo_fato("L"), p["cl"]])
		_dopo_aumento(s)


func _dopo_aumento(s: int) -> void:
	var p: Dictionary = players[s]
	if p["x"] and str(sc.get("x_regola", "")) == "4":
		# 18.45: la X si considera spesa e torna fuori dalla mappa
		p["x"] = false
		sag_pool.append(9)
		log_msg("%s restituisce il gettone X." % fazione(s))


static func testo_fato(l: String) -> String:
	match l:
		"A":
			return "Dopo anni di crescente separatismo, un settore della civiltà, composto soprattutto da una specie particolarmente insocievole, taglia ogni legame con il corpo principale. Dissoluzione del 10%."
		"B":
			return "Un capo religioso carismatico e fanatico sale alla ribalta nel Sistema Centrale. La sua Fede si diffonde di sistema in sistema; quando il suo erede designato viene ucciso da fanatici avversari, la Fede diventa intollerante. L'espulsione dei dissidenti però rafforza la coesione della civiltà. Dissoluzione del 30%; le dissoluzioni successive si ignorano."
		"C":
			return "Una lunga incapacità delle due specie più importanti di andare d'accordo sfocia in un conflitto breve ma brutale, dopo il quale nasce un vero consenso: dividersi a metà. Dissoluzione del 50%."
		"D":
			return "La scoperta di una droga organica nutriente, leggermente allucinogena e con improvvisi lampi di euforia, crea dipendenza in tre quarti delle popolazioni della Federazione. Gli effetti sulla coesione sono disastrosi. Dissoluzione del 70%."
		"E":
			return "Un lento ma inarrestabile declino colpisce la capacità dell'Autorità Centrale di mantenere il controllo. Una crisi rivela il fallimento del vecchio ordine: la maggior parte delle razze si separa dall'Impero, senza violenza. Dissoluzione dell'80%; la civiltà scende di un livello."
		"F":
			return "Un «regime» autoritario prende il controllo di una vasta regione di spazio. Il risentimento contro le due specie sciovinistiche al potere, una piccola minoranza, cresce fino a una Rivoluzione che porta all'anarchia. Dissoluzione del 90%; la civiltà scende di un livello."
		"G":
			return "Compare una forza autonoma: 2 porte e 5 flotte (livello di civiltà 1)."
		"H":
			return "Compare una forza autonoma: 3 porte e 7 flotte (livello di civiltà 1)."
		"I":
			return "Compare una forza autonoma: 4 porte e 9 flotte (livello di civiltà 1)."
		"J":
			return "Compare una forza autonoma: 5 porte e 12 flotte (livello di civiltà 2)."
		"K":
			return "Usando i dati scientifici di una spedizione al Nucleo, un ricercatore oscuro ed eccentrico che cercava di regolare la velocità della luce scopre per caso un sistema di comunicazione istantanea fra punti infinitamente lontani. La civiltà sale di due livelli."
		"L":
			return "Il libero intreccio delle diverse culture le arricchisce a vicenda e porta a nuovi, entusiasmanti livelli di esperienza senziente. La civiltà sale di un livello."
	return ""


func _dissoluzione(s: int, perc: int) -> void:
	var sp = punti_sistema(s)
	var serve := int(ceil(sp * perc / 100.0))
	if serve <= 0:
		return
	var mie = porte_di(s)
	var r = await decide(s, {"type": "dissoluzione", "serve": serve, "porte": mie, "perc": perc})
	var scelte: Array = []
	var tot := 0
	if r is Array:
		for h0 in r:
			var h := int(h0)
			if h in mie and not (h in scelte):
				scelte.append(h)
				tot += int(porte[h]["sp"])
	if tot < serve:
		# completa da sola con le porte di valore più basso
		var resto = mie.filter(func(x): return not (x in scelte))
		resto.sort_custom(func(a, b): return int(porte[a]["sp"]) < int(porte[b]["sp"]))
		for h in resto:
			if tot >= serve:
				break
			if int(porte[h]["sp"]) <= 0:
				continue
			scelte.append(h)
			tot += int(porte[h]["sp"])
	for h in scelte:
		if porte.has(h) and int(porte[h]["sp"]) > 0:
			_neutralizza(h, "dissoluzione")
	changed.emit()


## Comparsa di una forza autonoma (13.1) attorno a un esagono esplorato nel turno.
func _comparsa_autonomi(s: int, lettera: String) -> void:
	var dati: Array = D.AUTONOMI_FATO[lettera]
	var n_porte: int = dati[0]
	var n_flotte_aut: int = dati[1]
	var livello: int = dati[2]
	var esp: Array = esplorati_turno.get(s, [])
	if esp.is_empty():
		log_msg("%s: la forza autonoma non compare (nessuna esplorazione in questo turno)." % fazione(s))
		return
	var libero := -1
	for i in 4:
		if not aut[i]["presente"]:
			libero = i
			break
	if libero < 0:
		log_msg("Ci sono già quattro forze autonome: il risultato non ha effetto.")
		return
	var cand = esp.duplicate()
	_mescola(cand)
	for h0 in cand:
		var h := int(h0)
		var posti = _posti_autonomi(h, n_porte)
		if posti.size() < n_porte:
			continue
		var A: Dictionary = aut[libero]
		A["presente"] = true
		A["attiva"] = false
		A["custode"] = -1
		A["cl"] = livello
		A["cp_val"] = {"G": 100, "H": 200, "I": 400, "J": 800}[lettera]
		A["visti"] = {}
		var o = 10 + libero
		if pv.has(h):
			var c := int(pv[h]["c"])
			if c >= 0:
				pv_pool.append(c)
			pv.erase(h)
		var vp: Array = A["porte_pool"].duplicate()
		_mescola(vp)
		for i in n_porte:
			var g: int = posti[i]
			var val: int = vp[i % vp.size()]
			porte[g] = {"o": o, "sp": val, "neut": false, "nata": turn, "aum": turn, "orig": o}
		var fp: Array = A["flotte_pool"].duplicate()
		_mescola(fp)
		var per = n_flotte_aut / n_porte
		var extra = n_flotte_aut - per * n_porte
		var idx := 0
		for i in n_porte:
			var q = per + (extra if i == 0 else 0)
			var fl = {"r": 0, "d": 0, "e": 0}
			for k in q:
				fl[fp[idx % fp.size()]] += 1
				idx += 1
			if _n(fl) > 0:
				_aggiungi(posti[i], o, fl)
		log_msg("%s: %s Compare la forza autonoma %s attorno a %s." % [fazione(s), testo_fato(lettera), D.COLORI_AUT[libero], D.nome(h)])
		fx.emit("autonomi", {"h": h, "o": o})
		changed.emit()
		return
	log_msg("%s: non c'è spazio per la forza autonoma, il risultato non ha effetto." % fazione(s))


func _posti_autonomi(h: int, n: int) -> Array:
	var out = [h]
	if porte.has(h):
		return []
	for dir in range(1, 7):
		if out.size() >= n:
			break
		var x = D.passo(h, dir)
		if _idoneo_aut(x, out):
			out.append(x)
	# eccedenza: esagoni adiacenti a una porta già piazzata adiacente all'originale
	var guard := 0
	while out.size() < n and guard < 50:
		guard += 1
		var aggiunto := false
		for base in out.duplicate():
			if base == h:
				continue
			for dir in range(1, 7):
				var x = D.passo(base, dir)
				if _idoneo_aut(x, out):
					out.append(x)
					aggiunto = true
					break
			if out.size() >= n:
				break
		if not aggiunto:
			break
	return out


func _idoneo_aut(x: int, gia: Array) -> bool:
	return D.esiste(x) and not D.nucleo(x) and not porte.has(x) and not pv.has(x) and not (x in gia)


# ================================================================ F. risorse

func _fase_risorse() -> void:
	phase = "risorse"
	for s in ordine:
		if not players[s]["vivo"]:
			continue
		var p: Dictionary = players[s]
		var entrata = punti_sistema(s)
		p["rp"] = int(p["rp"]) + entrata
		var costo = manutenzione(s)
		if costo > int(p["rp"]):
			_taglia_flotte(s, costo - int(p["rp"]))
			costo = manutenzione(s)
		p["rp"] = maxi(0, int(p["rp"]) - costo)
		log_msg("%s: entrate %d, manutenzione %d, risorse %d." % [fazione(s), entrata, costo, p["rp"]], s, "")
	var seats := []
	var reqs := []
	for s in ordine:
		if players[s]["vivo"]:
			seats.append(s)
			reqs.append({"type": "risorse", "rp": int(players[s]["rp"])})
	var rr: Array = await decide_all(seats, reqs)
	for i in seats.size():
		var r = rr[i]
		var azioni: Array = []
		if r is Dictionary:
			azioni = r.get("azioni", [])
		elif r is Array:
			azioni = r
		_applica_risorse(seats[i], azioni)
	# forze autonome ostili: una flotta nuova ogni due porte (13.34)
	for i in 4:
		var A: Dictionary = aut[i]
		if not A["presente"]:
			continue
		var o = 10 + i
		var ostile := false
		for s in vivi():
			if opzione(o, s) == "C":
				ostile = true
		if not ostile:
			continue
		var mie = porte_di(o)
		var nuove = mie.size() / 2
		for k in nuove:
			var h: int = mie[rng.randi_range(0, mie.size() - 1)]
			_aggiungi(h, o, {"r": 1, "d": 0, "e": 0})
		if nuove > 0:
			log_msg("La forza autonoma %s riceve %d flotte nuove." % [D.COLORI_AUT[i], nuove])
	changed.emit()


func manutenzione(s: int) -> int:
	var t := 0
	for h in flotte:
		var st = stack(h, s)
		if st.is_empty():
			continue
		var n := int(st["r"]) + int(st["d"])
		if n > 1:
			t += n - 1
	return t


func _taglia_flotte(s: int, manca: int) -> void:
	var tolte := 0
	var guard := 0
	while manca > 0 and guard < 500:
		guard += 1
		# toglie una regolare (o corazzata) dalla pila più grande
		var best := -1
		var bn := 1
		for h in flotte:
			var st = stack(h, s)
			if st.is_empty():
				continue
			var n := int(st["r"]) + int(st["d"])
			if n > bn:
				bn = n
				best = h
		if best < 0:
			break
		var st2 = stack(best, s)
		if int(st2["r"]) > 0:
			_togli(best, s, {"r": 1}, false)
		else:
			_togli(best, s, {"d": 1}, false)
		manca -= 1
		tolte += 1
	if tolte > 0:
		log_msg("%s non può mantenere tutte le flotte: ne perde %d." % [fazione(s), tolte])


## Azioni possibili nella fase delle risorse (per l'interfaccia e l'IA).
## {"t": "porta", "h"}: crea una porta (2 flotte nell'esagono)
## {"t": "aumenta", "h", "n"}: aumenta la porta di n spendendo n flotte
## {"t": "riattiva", "h"}: de-neutralizza
## {"t": "flotta", "h", "k", "n"}: costruisce n flotte di tipo k
## {"t": "ricerca", "rp"}: (Gilham) converte risorse in punti civiltà
func azione_valida(s: int, a: Dictionary, stato: Dictionary) -> String:
	var p: Dictionary = players[s]
	var t := str(a.get("t", ""))
	var h := int(a.get("h", 0))
	var usate: Dictionary = stato["usate"]
	var rp: int = stato["rp"]
	match t:
		"porta":
			if p["guardiani"]:
				return "i Guardiani non costruiscono porte"
			if D.nucleo(h) or not D.esiste(h):
				return "non si costruiscono porte nel Nucleo"
			if porte.has(h):
				return "c'è già una porta"
			if not p["esplorati"].has(h) or not pv.has(h) or not pv[h]["visto"].has(s):
				return "esagono non esplorato"
			if _flotte_disponibili(h, s, usate) < 2:
				return "servono due flotte nell'esagono"
		"aumenta":
			if p["guardiani"]:
				return "i Guardiani non aumentano le porte"
			var g = porta(h)
			if g.is_empty() or g["neut"] or int(g["o"]) != s:
				return "non è una porta amica"
			if int(g["nata"]) == turn:
				return "una porta nuova si aumenta dal turno dopo"
			var n := int(a.get("n", 1))
			if n <= 0:
				return "quantità non valida"
			if int(g["sp"]) + n > potenziale(h):
				return "oltre il potenziale dell'esagono (%d)" % potenziale(h)
			if _flotte_disponibili(h, s, usate) < n:
				return "flotte insufficienti nell'esagono"
		"riattiva":
			var g2 = porta(h)
			if g2.is_empty() or not g2["neut"]:
				return "non è una porta neutralizzata"
			if p["guardiani"] and int(g2.get("orig", -1)) != s:
				return "i Guardiani riattivano solo le proprie porte iniziali"
			for o in proprietari(h):
				if o != s:
					return "nell'esagono c'è una forza non amica"
			if n_flotte(h, s) <= 0:
				return "serve almeno una flotta amica nell'esagono"
			var spesa := maxi(0, int(g2["sp"]) - cl(s))
			if _flotte_disponibili(h, s, usate) < spesa:
				return "servono %d flotte nell'esagono" % spesa
			if rp < int(g2["sp"]):
				return "servono %d risorse" % int(g2["sp"])
		"flotta":
			var g3 = porta(h)
			if g3.is_empty() or g3["neut"] or int(g3["o"]) != s:
				return "si costruisce solo nelle porte amiche"
			if int(g3["sp"]) <= 0:
				return "la porta deve valere almeno 1"
			if stato["aumentate"].has(h):
				return "non si costruisce dove si è appena aumentata la porta"
			var k := str(a.get("k", "r"))
			var n2 := int(a.get("n", 1))
			if not (k in ["r", "d", "e"]) or n2 <= 0:
				return "tipo non valido"
			if k == "d" and not (D.terreno(h) in ["A", "F"]):
				return "le corazzate si costruiscono solo nell'asse o nella frangia della spirale"
			if k == "e" and D.terreno(h) != "A":
				return "le esploratrici si costruiscono solo nell'asse della spirale"
			var lim := maxi(1, cl(s))
			if int(stato["costruite"].get(h, 0)) + n2 > lim:
				return "al massimo %d flotte per esagono a questo livello di civiltà" % lim
			if rp < D.COSTO[k] * n2:
				return "risorse insufficienti"
			if k == "d" and p["x"] and str(sc.get("x_regola", "")) == "4":
				return "chi ha il gettone X non costruisce corazzate"
			if k == "d" and p["limite_corazzate"]:
				var tot = int(totale_flotte(s)["d"]) + int(stato["corazzate"]) + n2
				if tot > punti_sistema(s) / 10:
					return "al massimo una corazzata ogni dieci punti sistema"
		"ricerca":
			if not opz.get("gilham", false):
				return "solo con il Fato alternativo"
			if int(a.get("rp", 0)) <= 0 or int(a.get("rp", 0)) > rp:
				return "risorse insufficienti"
		_:
			return "azione sconosciuta"
	return ""


func stato_risorse(s: int) -> Dictionary:
	return {"rp": int(players[s]["rp"]), "usate": {}, "aumentate": {}, "costruite": {}, "corazzate": 0}


func _flotte_disponibili(h: int, s: int, usate: Dictionary) -> int:
	return n_flotte(h, s) - int(usate.get(h, 0))


## Applica un'azione allo stato provvisorio (senza toccare la partita): per l'interfaccia.
func simula_azione(s: int, a: Dictionary, stato: Dictionary) -> void:
	var t := str(a.get("t", ""))
	var h := int(a.get("h", 0))
	match t:
		"porta":
			stato["usate"][h] = int(stato["usate"].get(h, 0)) + 2
		"aumenta":
			stato["usate"][h] = int(stato["usate"].get(h, 0)) + int(a.get("n", 1))
			stato["aumentate"][h] = true
		"riattiva":
			var g = porta(h)
			stato["usate"][h] = int(stato["usate"].get(h, 0)) + maxi(0, int(g["sp"]) - cl(s))
			stato["rp"] = int(stato["rp"]) - int(g["sp"])
		"flotta":
			var k := str(a.get("k", "r"))
			var n := int(a.get("n", 1))
			stato["costruite"][h] = int(stato["costruite"].get(h, 0)) + n
			stato["rp"] = int(stato["rp"]) - D.COSTO[k] * n
			if k == "d":
				stato["corazzate"] = int(stato["corazzate"]) + n
		"ricerca":
			stato["rp"] = int(stato["rp"]) - int(a.get("rp", 0))


func _applica_risorse(s: int, azioni: Array) -> void:
	var p: Dictionary = players[s]
	var stato = stato_risorse(s)
	var fatte := []
	for a0 in azioni:
		if not (a0 is Dictionary):
			continue
		var a: Dictionary = a0
		var err = azione_valida(s, a, stato)
		if err != "":
			log_msg("Azione rifiutata (%s): %s." % [str(a.get("t", "")), err], s)
			continue
		var h := int(a.get("h", 0))
		match str(a["t"]):
			"porta":
				_spendi_flotte(h, s, 2)
				porte[h] = {"o": s, "sp": 0, "neut": false, "nata": turn, "aum": 0, "orig": s}
				fatte.append("porta in %s" % D.nome(h))
				# 17.21: un gettone saggezza trasportato da una forza su cui nasce una porta amica passa sotto controllo
				var stg := stack(h, s)
				if not stg.is_empty() and not stg["sag"].is_empty():
					var carico: Array = stg["sag"].duplicate()
					stg["sag"].clear()
					_atterra(s, h, {"r": 0, "d": 0, "e": 0}, carico)
				fx.emit("porta", {"h": h, "o": s})
			"aumenta":
				var n := int(a.get("n", 1))
				_spendi_flotte(h, s, n)
				porte[h]["sp"] = int(porte[h]["sp"]) + n
				porte[h]["aum"] = turn
				if int(porte[h]["sp"]) >= valore_pv(h) and pv.has(h):
					var c := int(pv[h]["c"])
					if c >= 0:
						pv_pool.append(c)
					pv.erase(h)
				fatte.append("porta di %s aumentata" % D.nome(h))
			"riattiva":
				var g: Dictionary = porte[h]
				_spendi_flotte(h, s, maxi(0, int(g["sp"]) - cl(s)))
				p["rp"] = int(p["rp"]) - int(g["sp"])
				g["neut"] = false
				g["o"] = s
				fatte.append("porta di %s riattivata" % D.nome(h))
				fx.emit("porta", {"h": h, "o": s})
			"flotta":
				var k := str(a.get("k", "r"))
				var n2 := int(a.get("n", 1))
				p["rp"] = int(p["rp"]) - D.COSTO[k] * n2
				_aggiungi(h, s, {k: n2})
				fatte.append("%d %s in %s" % [n2, D.NOME_FLOTTE[k] if n2 > 1 else D.NOME_FLOTTA[k], D.nome(h)])
			"ricerca":
				var q := int(a.get("rp", 0))
				p["rp"] = int(p["rp"]) - q
				var g2 = q / maxi(1, cl(s))
				p["cp"] = int(p["cp"]) + g2
				fatte.append("ricerca: %d punti civiltà" % g2)
		simula_azione(s, a, stato)
	if p["guardiani"]:
		p["rp"] = mini(int(p["rp"]), 20)
	if not fatte.is_empty():
		log_msg("%s: %s." % [fazione(s), "; ".join(fatte)], s, "%s costruisce e si organizza." % fazione(s))


func _spendi_flotte(h: int, s: int, n: int) -> void:
	var st = stack(h, s)
	var fl = {"r": 0, "d": 0, "e": 0}
	for k in ["r", "e", "d"]:
		var q: int = mini(n, int(st[k]))
		fl[k] = q
		n -= q
	_togli(h, s, fl, false)


# ================================================================ schieramento iniziale

func _pre_schieramento() -> void:
	phase = "schieramento"
	var seats := []
	var reqs := []
	for s in players.size():
		var p: Dictionary = players[s]
		var budget := int(p.get("budget", p["rp"]))
		seats.append(s)
		reqs.append({"type": "schieramento", "rp": budget})
	var rr: Array = await decide_all(seats, reqs)
	for i in seats.size():
		var s: int = seats[i]
		var p: Dictionary = players[s]
		var budget := int(p.get("budget", p["rp"]))
		var r = rr[i]
		var lista: Array = r.get("azioni", []) if r is Dictionary else (r if r is Array else [])
		var spesi := 0
		var fatte := 0
		for a0 in lista:
			if not (a0 is Dictionary):
				continue
			var h := int(a0.get("h", 0))
			var k := str(a0.get("k", "r"))
			var n := int(a0.get("n", 1))
			if not porta_propria(h, s) or not (k in ["r", "d", "e"]) or n <= 0:
				continue
			if k == "d" and not (D.terreno(h) in ["A", "F"]):
				continue
			if k == "e" and D.terreno(h) != "A":
				continue
			if spesi + D.COSTO[k] * n > budget:
				continue
			spesi += D.COSTO[k] * n
			_aggiungi(h, s, {k: n})
			fatte += n
		if p.has("budget"):
			p["rp"] = 0
			p.erase("budget")
		else:
			p["rp"] = budget - spesi
		log_msg("%s schiera %d flotte." % [fazione(s), fatte])
	changed.emit()


# ================================================================ vittoria

func _vittoria() -> void:
	if over:
		return
	var limite := int(sc["turni"])
	if scn_id == 5:
		limite = int(opz.get("limite", 0))
	match scn_id:
		1:
			if turn >= limite:
				var liv := []
				for s in 2:
					liv.append(_livello_scorpii(s))
				if liv[0] > liv[1]:
					_fine({"winner": 0, "reason": "%s: vittoria %s" % [fazione(0), "sostanziale" if liv[0] == 2 else "marginale"]})
				elif liv[1] > liv[0]:
					_fine({"winner": 1, "reason": "%s: vittoria %s" % [fazione(1), "sostanziale" if liv[1] == 2 else "marginale"]})
				else:
					_fine({"winner": -1, "reason": "nessuno raggiunge una vittoria migliore dell'altro: patta"})
		2:
			for s in [1, 2]:
				if not players[s]["vivo"]:
					serie[s] = 0
					continue
				if _catena_nucleo(s):
					serie[s] = int(serie.get(s, 0)) + 1
					if serie[s] == 1:
						log_msg("%s ha una catena di porte fino al Nucleo!" % fazione(s))
				else:
					serie[s] = 0
				if int(serie.get(s, 0)) >= 5:
					_fine({"winner": s, "reason": "%s mantiene per cinque turni la catena di porte fino al Nucleo" % fazione(s)})
					return
			if turn >= limite:
				_fine({"winner": 0, "reason": "i Guardiani hanno difeso il Nucleo per 50 turni"})
		3:
			if turn >= limite:
				if cl(0) >= 2:
					_fine({"winner": 0, "reason": "la PSL raggiunge il livello di civiltà %d: vittoria" % cl(0)})
				else:
					_fine({"winner": -1, "reason": "la PSL resta al livello di civiltà %d: sconfitta" % cl(0), "perso": 0})
		4:
			var punti = [814, 1118, 1212, 1215, 1314]
			for s in vivi():
				var q := 0
				for h in punti:
					if porta_propria(h, s):
						q += 1
				serie[s] = int(serie.get(s, 0)) + 1 if q >= 4 else 0
				if int(serie.get(s, 0)) >= 5:
					_fine({"winner": s, "reason": "%s tiene quattro esagoni chiave per cinque turni" % fazione(s)})
					return
			for s in vivi():
				var altri := 0
				for t in vivi():
					if t != s:
						altri += cl(t)
				if vivi().size() > 1 and cl(s) > altri:
					_fine({"winner": s, "reason": "%s ha un livello di civiltà superiore a tutti gli altri insieme" % fazione(s)})
					return
			if turn >= limite:
				_fine_punteggio()
		5:
			var vv = vivi()
			if players.size() == 1:
				var s0: int = vv[0] if not vv.is_empty() else 0
				if punti_sistema(s0) >= 100 and _nessuna_porta_ostile(s0):
					serie[s0] = int(serie.get(s0, 0)) + 1
				else:
					serie[s0] = 0
				if int(serie.get(s0, 0)) >= 5:
					_fine({"winner": s0, "reason": "100 punti sistema per cinque turni senza porte non amiche"})
					return
			else:
				for s in vv:
					if _nessuna_porta_ostile(s, true):
						_fine({"winner": s, "reason": "%s: non restano porte non amiche sulla mappa" % fazione(s)})
						return
					if players[s]["x"]:
						continue
					var altri := 0
					for t in vv:
						if t != s:
							altri += cl(t)
					for i in 4:
						if aut[i]["presente"] and not porte_di(10 + i).is_empty():
							altri += int(aut[i]["cl"])
					if cl(s) > altri:
						_fine({"winner": s, "reason": "%s ha un livello di civiltà superiore a tutti gli altri insieme" % fazione(s)})
						return
				var tutti := true
				for s in vv:
					if punti_sistema(s) <= 100:
						tutti = false
				serie["patta"] = int(serie.get("patta", 0)) + 1 if tutti else 0
				if int(serie.get("patta", 0)) >= 10:
					_fine({"winner": -1, "reason": "tutti oltre 100 punti sistema per dieci turni: patta"})
					return
			if limite > 0 and turn >= limite:
				_fine_punteggio()


func _fine_punteggio() -> void:
	var best := -1
	var bv := -1
	var pari := false
	for s in vivi():
		var v = punti_sistema(s) * cl(s)
		if v > bv:
			bv = v
			best = s
			pari = false
		elif v == bv:
			pari = true
	if pari:
		_fine({"winner": -1, "reason": "fine dei turni: parità di punti sistema per livello di civiltà"})
	else:
		_fine({"winner": best, "reason": "fine dei turni: %s ha il punteggio più alto (%d)" % [fazione(best), bv]})


func _livello_scorpii(s: int) -> int:
	for h in players[s]["porte_iniziali"]:
		if not porta_propria(h, s):
			return 0
	if not porta_propria(1816, s):
		return 0
	var altro = 1 - s
	for h in players[altro]["porte_iniziali"]:
		if porta_propria(h, s):
			return 2
	return 1


func _nessuna_porta_ostile(s: int, solo_giocatori := false) -> bool:
	for h in porte:
		var g: Dictionary = porte[h]
		if int(g["o"]) == s:
			continue
		if solo_giocatori and int(g["o"]) >= 10:
			continue
		if g["neut"] and solo_giocatori:
			continue
		return false
	return true


func _catena_nucleo(s: int) -> bool:
	var mie = porte_di(s)
	var inizio: Array = players[s]["porte_iniziali"].filter(func(h): return porta_propria(h, s))
	if inizio.is_empty():
		return false
	var visti := {}
	var coda = inizio.duplicate()
	for h in coda:
		visti[h] = true
	while not coda.is_empty():
		var h: int = coda.pop_back()
		for v in D.vicini(h):
			if D.nucleo(v):
				return true
		for g in mie:
			if not visti.has(g) and D.distanza(h, g) <= 4:
				visti[g] = true
				coda.append(g)
	return false


# ================================================================ salvataggio

func salva() -> Dictionary:
	var c = config.duplicate(true)
	for k in ["acts", "replay", "codice", "online"]:
		c.erase(k)
	return {"config": c, "acts": var_to_str(rec_acts), "turno": turn, "versione": 1}
