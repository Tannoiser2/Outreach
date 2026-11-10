extends RefCounted
## Avversario automatico di Outreach. Usa un proprio generatore casuale (mai quello del motore),
## così le partite salvate si rigiocano identiche.

const D = preload("res://scripts/data/od_data.gd")

var rng := RandomNumberGenerator.new()
var level := 1
var piano: Array = []
var piano_turno := -1
var piano_fase := ""


func setup(seed_: int, lvl: int) -> void:
	rng.seed = seed_
	level = lvl


func decide(eng, s: int, req: Dictionary):
	match str(req.get("type", "")):
		"mossa":
			return _mossa(eng, s, req)
		"prosegui":
			return {"fine": true}
		"esplora":
			return req["esagoni"]
		"contatto":
			return _contatto(eng, s, req)
		"interazione":
			return _interazione(eng, s, req)
		"attacco":
			return _attacco(eng, s, req)
		"bersaglio":
			return _bersaglio(eng, s, req)
		"riduzione":
			return true
		"fato":
			return _fato(eng, s, req)
		"dissoluzione":
			return _dissoluzione(eng, s, req)
		"risorse":
			return {"azioni": _risorse(eng, s, int(req["rp"]))}
		"schieramento":
			return {"azioni": _schieramento(eng, s, int(req["rp"]))}
	return null


# ---------------------------------------------------------------- movimento

func _mossa(eng, s: int, req: Dictionary) -> Dictionary:
	var fase = "riserva" if req.get("riserva", false) else "regolari"
	if piano_turno != eng.turn or piano_fase != fase:
		piano_turno = eng.turn
		piano_fase = fase
		piano = _pianifica(eng, s, fase == "riserva")
	while not piano.is_empty():
		var m: Dictionary = piano.pop_front()
		var fl = {"r": int(m["r"]), "d": int(m["d"]), "e": int(m["e"])}
		var lib: Dictionary = eng.liberi(int(m["da"]), s)
		for k in fl:
			fl[k] = mini(int(fl[k]), int(lib[k]))
		if fl["r"] + fl["d"] + fl["e"] <= 0:
			continue
		if eng.mossa_valida(s, int(m["da"]), int(m["a"]), fl, fase == "riserva") != "":
			continue
		var out = fl.duplicate()
		out["da"] = int(m["da"])
		out["a"] = int(m["a"])
		out["sag"] = int(m.get("sag", 0))
		return out
	return {"fine": true}


func _pianifica(eng, s: int, riserva: bool) -> Array:
	var out := []
	var raggio: int = maxi(1, eng.clr(s))
	var mete := {}
	var minacce = _minacce(eng, s)
	var p: Dictionary = eng.players[s]
	var spedizione = _sceglie_spedizione(eng, s) if not riserva else -1
	_verso_chiave.clear()
	for c in [1816, 814, 1118, 1212, 1215, 1314]:
		if _chiave(eng, c):
			_verso_chiave[c] = eng.n_flotte(c, s)
	for h in eng.forze_libere(s):
		var lib: Dictionary = eng.liberi(h, s)
		var n: int = lib["r"] + lib["d"] + lib["e"]
		if n <= 0:
			continue
		# 1. difesa: se una porta propria è minacciata, chi è vicino ci va (anche in riserva)
		var difesa := -1
		for g in minacce:
			if g != h and D.distanza(h, g) <= raggio and not eng.porta_propria(h, s):
				difesa = g
				break
		if difesa > 0:
			out.append({"da": h, "a": difesa, "r": lib["r"], "d": lib["d"], "e": lib["e"]})
			continue
		var st: Dictionary = eng.stack(h, s)
		var porto_sag: bool = not st.is_empty() and not st["sag"].is_empty()
		# 2. gettoni saggezza: chi ne trasporta uno torna a una porta propria a passi senza rischio;
		# chi è in un esagono del centro lo prende uscendo
		if (porto_sag or (eng.sag_centro.has(h) and _vuole_saggezza(eng, s))) and not riserva:
			var casa = _porta_vicina_raggiungibile(eng, s, h)
			if casa > 0:
				var passo = _passo_verso(eng, s, h, lib, casa, false)
				if passo > 0:
					out.append({"da": h, "a": passo, "r": lib["r"], "d": lib["d"], "e": lib["e"], "sag": 1 if eng.sag_centro.has(h) else 0})
				continue
		# 3. la spedizione verso il centro del Nucleo
		if h == spedizione and not riserva:
			var meta_sag = _centro_con_gettone(eng, h)
			if meta_sag > 0:
				var passo2 = _passo_verso(eng, s, h, lib, meta_sag, false)
				if passo2 > 0:
					out.append({"da": h, "a": passo2, "r": lib["r"], "d": lib["d"], "e": lib["e"]})
					_spedizione_h[s] = passo2
					continue
		if riserva:
			continue
		# obiettivo dello scenario ancora senza porta propria: ci vanno, a passi sicuri, esploratrici
		# e corazzate (e regolari finché il gruppo è piccolo)
		var ch = _chiave_vicina(eng, s, h)
		if ch > 0 and int(_verso_chiave.get(ch, 0)) < 6:
			var mc = {"r": 0, "d": int(lib["d"]), "e": int(lib["e"])}
			if int(_verso_chiave.get(ch, 0)) + mc["d"] + mc["e"] < 3:
				mc["r"] = int(lib["r"])
			if mc["r"] + mc["d"] + mc["e"] > 0:
				var passo3 = _passo_verso(eng, s, h, mc, ch, false)
				if passo3 > 0:
					_verso_chiave[ch] = int(_verso_chiave.get(ch, 0)) + mc["r"] + mc["d"] + mc["e"]
					out.append({"da": h, "a": passo3, "r": mc["r"], "d": mc["d"], "e": mc["e"]})
					continue
		var tenere = {"r": 0, "d": 0, "e": 0}
		var pvn: int = eng.pv_noto(h, s)
		var porta: Dictionary = eng.porta(h)
		if _chiave(eng, h) and porta.is_empty():
			# esagono chiave dello scenario: si resta tutti a esplorarlo e a costruirci la porta
			continue
		if porta.is_empty() and not D.nucleo(h):
			if pvn < 0:
				# esagono da esplorare: restano le esploratrici e una flotta (non costano manutenzione)
				tenere["e"] = int(lib["e"])
				if int(lib["e"]) < 2:
					tenere["r"] = mini(int(lib["r"]), 2 - int(lib["e"]))
			elif pvn >= 2:
				# si resta per costruire una porta (servono due flotte)
				var serve := 2
				for k in ["r", "e", "d"]:
					var q: int = mini(serve, int(lib[k]))
					tenere[k] += q
					serve -= q
		elif not porta.is_empty() and eng.porta_propria(h, s):
			# porta propria: si resta solo quanto serve per aumentarla fino al potenziale
			var manca: int = eng.potenziale(h) - int(porta["sp"])
			for k in ["r", "e"]:
				var q2: int = mini(manca, int(lib[k]))
				tenere[k] += q2
				manca -= q2
			if p["guardiani"]:
				tenere = lib.duplicate()
			# una corazzata di guardia nelle porte più ricche
			if int(porta["sp"]) >= 4:
				tenere["d"] = mini(int(lib["d"]), maxi(int(tenere["d"]), 1))
		var mov = {"r": int(lib["r"]) - int(tenere["r"]), "d": int(lib["d"]) - int(tenere["d"]), "e": int(lib["e"]) - int(tenere["e"])}
		if mov["r"] + mov["d"] + mov["e"] <= 0:
			continue
		var meta = _meta(eng, s, h, mov, raggio, mete)
		if meta > 0:
			mete[meta] = true
			out.append({"da": h, "a": meta, "r": mov["r"], "d": mov["d"], "e": mov["e"]})
	return out


# ---------------------------------------------------------------- saggezza: la spedizione al Nucleo

var _spedizione_h := {}            # giocatore -> esagono della forza in spedizione
const CENTRO := [3815, 3915, 3916]


func _vuole_saggezza(eng, s: int) -> bool:
	if not eng.usa_saggezza_in_gioco():
		return false
	var p: Dictionary = eng.players[s]
	if p["guardiani"]:
		return false
	var trasportati := 0
	for h in eng.flotte:
		var st: Dictionary = eng.stack(h, s)
		if not st.is_empty():
			trasportati += st["sag"].size()
	var limite := 3
	# nello scenario 3 la X fa perdere: basta un gettone per sperare in L1
	if eng.sc.get("x_perde", false):
		limite = 1 if int(eng.cl(s)) < 2 else 0
	return p["sag"].size() + trasportati < limite


func _centro_con_gettone(eng, h: int) -> int:
	var best := -1
	var bd := 999
	for c in CENTRO:
		if eng.sag_centro.has(c):
			var d = D.distanza(h, c)
			if d < bd:
				bd = d
				best = c
	return best


## Sceglie (o ritrova) la forza che va a prendere un gettone saggezza al centro del Nucleo.
func _sceglie_spedizione(eng, s: int) -> int:
	if not _vuole_saggezza(eng, s) or eng.sag_centro.is_empty() or eng.turn < 3:
		_spedizione_h.erase(s)
		return -1
	var h0 := int(_spedizione_h.get(s, -1))
	if h0 > 0 and eng.n_flotte(h0, s) > 0 and _n_lib(eng, h0, s) > 0:
		return h0
	# una nuova: la forza libera più vicina al centro, meglio se di sole esploratrici
	var best := -1
	var bv = 1e9
	for h in eng.forze_libere(s):
		var lib: Dictionary = eng.liberi(h, s)
		if int(lib["r"]) + int(lib["d"]) + int(lib["e"]) <= 0:
			continue
		if eng.porta_propria(h, s) and eng.potenziale(h) > int(eng.porte[h]["sp"]):
			continue
		var d = D.distanza(h, 3915)
		var v := float(d)
		if int(lib["e"]) > 0 and int(lib["r"]) + int(lib["d"]) == 0:
			v -= 6.0
		if eng.porta_propria(h, s):
			v -= 2.0
		if v < bv:
			bv = v
			best = h
	if best > 0:
		_spedizione_h[s] = best
	return best


func _n_lib(eng, h: int, s: int) -> int:
	var l: Dictionary = eng.liberi(h, s)
	return int(l["r"]) + int(l["d"]) + int(l["e"])


func _porta_vicina_raggiungibile(eng, s: int, h: int) -> int:
	var best := -1
	var bd := 999
	for g in eng.porte_di(s):
		var d = D.distanza(h, g)
		if d < bd:
			bd = d
			best = g
	return best


## Il passo migliore verso la meta: il salto più lungo senza alcun rischio di dispersione che
## avvicina; fuori dal Nucleo, se nessun salto è sicuro, accetta un rischio di 1 su 6.
func _passo_verso(eng, s: int, h: int, fl: Dictionary, meta: int, riserva: bool) -> int:
	var d0 = D.distanza(h, meta)
	if d0 == 0:
		return -1
	var raggio: int = maxi(1, eng.clr(s))
	var portata = raggio
	if eng.porta_utile(h, s):
		portata = maxi(raggio, 10)
	portata = mini(portata, d0)
	var best := -1
	var bv = 1e9
	for tollera in [0, 1]:
		var c0 = D.col(h)
		var r0 = D.row(h)
		for c in range(c0 - portata, c0 + portata + 1):
			for r in range(r0 - portata, r0 + portata + 1):
				var x = D.hx(c, r)
				if x == h or not D.esiste(x):
					continue
				var dist = D.distanza(h, x)
				if dist > portata:
					continue
				var dm = D.distanza(x, meta)
				if dm >= d0:
					continue
				if eng.mossa_valida(s, h, x, fl, riserva) != "":
					continue
				var ri: Dictionary = eng.rischio(s, h, x, fl)
				var k := int(ri["rischio"])
				if k > tollera:
					continue
				if k > 0 and (D.nucleo(h) or D.nucleo(x) or ri["oltre"]):
					continue
				var v = float(dm) + k * 3.0
				for o in eng.proprietari(x):
					if o != s and (o >= 10 or eng.opzione(o, s) == "C"):
						v += 6.0
				if eng.porta_utile(x, s):
					v -= 1.5
				if v < bv:
					bv = v
					best = x
		if best > 0:
			return best
	return -1


static var _bordo_nucleo: Array = []

## Bonus per gli esagoni che contano per la vittoria dello scenario.
func _obiettivo(eng, s: int, x: int) -> float:
	match int(eng.scn_id):
		1:
			if x == 1816 and not eng.porta_propria(x, s):
				return 4.0
			if x in eng.players[s]["porte_iniziali"] and eng.n_flotte(x, s) == 0:
				return 1.5
			var altro: int = 1 - s
			if x in eng.players[altro]["porte_iniziali"] and int(eng.totale_flotte(s)["d"]) >= 3:
				return 3.0
		2:
			if s > 0:
				if _bordo_nucleo.is_empty():
					for h in D.mappa()["esagoni"]:
						if not D.nucleo(h):
							for v in D.vicini(h):
								if D.nucleo(v):
									_bordo_nucleo.append(h)
									break
				var dmin := 99
				for b in _bordo_nucleo:
					dmin = mini(dmin, D.distanza(b, x))
				return maxf(0.0, 8.0 - dmin) * 0.5
		4:
			if x in [814, 1118, 1212, 1215, 1314] and not eng.porta_propria(x, s):
				return 4.0
	return 0.0


var _verso_chiave := {}


func _chiave_vicina(eng, s: int, h: int) -> int:
	var best := -1
	var bd := 9
	for c in _verso_chiave:
		if eng.porta_propria(c, s) or h == c:
			continue
		var g: Dictionary = eng.porta(c)
		if not g.is_empty() and not g["neut"]:
			# porta altrui: se ne occupa la logica d'attacco, non la corsa all'obiettivo
			continue
		var d = D.distanza(h, c)
		if d < bd:
			bd = d
			best = c
	return best


## Esagoni in cui lo scenario chiede di avere una porta.
func _chiave(eng, h: int) -> bool:
	match int(eng.scn_id):
		1:
			return h == 1816
		4:
			return h in [814, 1118, 1212, 1215, 1314]
	return false


func _minacce(eng, s: int) -> Array:
	var out := []
	for g in eng.porte_di(s):
		for h in eng.flotte:
			for o in eng.proprietari(h):
				if o == s:
					continue
				if eng.opzione(o, s) == "C" and D.distanza(h, g) <= 2 and eng.n_flotte(g, s) < eng.n_flotte(h, o):
					if not (g in out):
						out.append(g)
	return out


func _meta(eng, s: int, h: int, fl: Dictionary, raggio: int, mete: Dictionary) -> int:
	var best := -1
	var bv := -999.0
	var p: Dictionary = eng.players[s]
	var da_porta: bool = eng.porta_utile(h, s)
	var portata := mini(raggio, 4)
	if da_porta:
		portata = maxi(portata, 3)
	var c0 = D.col(h)
	var r0 = D.row(h)
	for c in range(c0 - portata, c0 + portata + 1):
		for r in range(r0 - portata, r0 + portata + 1):
			var x = D.hx(c, r)
			if x == h or not D.esiste(x) or D.nucleo(x):
				continue
			var dist = D.distanza(h, x)
			if dist > portata:
				continue
			if eng.mossa_valida(s, h, x, fl) != "":
				continue
			var ri: Dictionary = eng.rischio(s, h, x, fl)
			if int(ri["rischio"]) >= 3:
				continue
			var v := 0.0
			var t = D.terreno(x)
			var g: Dictionary = eng.porta(x)
			var nota: int = eng.pv_noto(x, s)
			if not g.is_empty():
				if eng.porta_propria(x, s):
					var margine_x: int = eng.potenziale(x) - int(g["sp"]) - eng.n_flotte(x, s)
					v += minf(4.5, margine_x * 1.5) if margine_x > 0 else -2.0
				elif g["neut"]:
					v += 3.0 if eng.n_flotte(x, s) == 0 else 0.0
				else:
					# porta altrui: un gruppo di corazzate abbastanza forte la va ad attaccare
					var o_g := int(g["o"])
					var amico: bool = eng.alleati(s, o_g) or (o_g < 10 and eng.opzione(s, o_g) == "A")
					var difesa_stimata := 0
					for o2 in eng.proprietari(x):
						if o2 != s:
							difesa_stimata += 4
					if not amico and int(fl["d"]) >= 3 and int(fl["d"]) * 2 + int(fl["r"]) >= difesa_stimata * 1.5 + 2 and eng.turn >= 6:
						v += 3.0 + int(g["sp"]) * 0.0 + float(int(fl["d"])) * 0.3
					else:
						v -= 4.0
			elif not p["esplorati"].has(x) or nota < 0:
				v += {"A": 4.0, "F": 3.0, "I": 1.5}.get(t, 0.0)
				if eng.n_flotte(x, s) > 0 and eng.n_flotte(x, s) < 4:
					v += 1.5
			elif nota >= 2:
				v += 1.0 + nota * 0.9 - (1.5 if eng.n_flotte(x, s) >= 2 else 0.0)
			else:
				v -= 1.0
			# vicino alle proprie porte è meglio
			var vicina := 99
			for pg in eng.porte_di(s):
				vicina = mini(vicina, D.distanza(pg, x))
			v -= maxf(0.0, vicina - 2) * 0.7
			v -= dist * 0.4
			v -= int(ri["rischio"]) * 1.5
			if mete.has(x) and nota >= 0:
				v -= 3.0
			v += _obiettivo(eng, s, x)
			# nemici: evitare le pile ostili più forti
			for o in eng.proprietari(x):
				if o != s:
					if eng.opzione(o, s) == "C" or o >= 10:
						v -= 3.0
					else:
						v -= 1.0
			v += rng.randf() * 0.3
			if v > bv:
				bv = v
				best = x
	if bv < 0.5:
		return -1
	return best


# ---------------------------------------------------------------- relazioni

func _forza(eng, o: int) -> int:
	var t := 0
	for h in eng.flotte:
		t += eng.capacita(h, o)
	return t


func _contatto(eng, s: int, req: Dictionary) -> Dictionary:
	var out := {}
	for c in req["casi"]:
		var h := int(c["h"])
		var mia: int = eng.capacita(h, s)
		var altri := 0
		var ostili := false
		for o in c["altri"]:
			altri += eng.n_flotte(h, o) * 2
			if eng.opzione(o, s) == "C":
				ostili = true
		if mia >= altri * 1.5 and mia > 2:
			out[h] = int(c["max"])
		elif ostili:
			out[h] = int(c["min"])
		elif eng.players[s]["guardiani"]:
			out[h] = int(c["max"])
		else:
			out[h] = int(c["min"]) if rng.randf() < 0.6 else int(c["max"])
	return out


func _interazione(eng, s: int, req: Dictionary) -> Dictionary:
	var out := {}
	var p: Dictionary = eng.players[s]
	var miaf = _forza(eng, s)
	for o in req["parti"]:
		var loro := str(req["loro"].get(o, ""))
		var attuale := str(req["attuali"].get(o, ""))
		var v := "B"
		if o >= 10:
			v = "A" if loro != "C" else "C"
			if loro == "C" and miaf < _forza(eng, o):
				v = "A"
		else:
			var lorof = _forza(eng, o)
			if loro == "C":
				v = "C"
			elif p["guardiani"]:
				v = "C"
			elif eng.players[o]["guardiani"]:
				v = "C" if miaf > lorof else "B"
			elif loro == "A":
				v = "A"
			elif miaf > lorof * 2 and level >= 1 and rng.randf() < 0.5:
				v = "C"
			elif attuale != "":
				v = attuale
		if v == "C" and p["x"] and str(eng.sc.get("x_regola", "")) == "4" and loro != "C":
			v = "B"
		out[o] = v
	return out


func _attacco(eng, s: int, req: Dictionary) -> Dictionary:
	var h := int(req["h"])
	var vera := int(req["vera"])
	var best := 0
	for t in req["bersagli"]:
		var stima: int = eng.n_flotte(h, t) * 2 if t < 10 else eng.capacita(h, t)
		if best == 0 or stima < best:
			best = stima
	var att: bool = req.get("obbligatorio", false) or (vera >= best * 1.3 and vera > 0)
	var dich = vera
	if rng.randf() < 0.5:
		dich = int(round(vera * rng.randf_range(0.7, 1.3)))
	return {"attacca": att, "dich": dich}


func _bersaglio(eng, s: int, req: Dictionary) -> int:
	var h := int(req["h"])
	var best: int = req["bersagli"][0]
	var bv = 1 << 30
	for t in req["bersagli"]:
		var v: int = eng.n_flotte(h, t)
		if v < bv:
			bv = v
			best = t
	return best


# ---------------------------------------------------------------- fato

func _valore_lettera(eng, s: int, r: String, sag: int, sp: int) -> float:
	if r == "":
		return 0.0
	var p: Dictionary = eng.players[s]
	var l = r.substr(0, 1)
	# un livello di civiltà vale molto: raddoppia la costruzione per esagono, allarga il raggio,
	# riduce la dispersione; nello scenario 3 è la vittoria
	var livello = 40.0 + sp * 1.2
	if int(eng.scn_id) == 3 and int(eng.cl(s)) < 2:
		livello *= 4.0
	if l in ["A", "B", "C", "D", "E", "F"]:
		if eng.ignora("fato_AF", s) or eng.ignora("dissoluzione", s) or p["immune"] or p["diss"].has(l):
			return 0.0
		var v: float = -float(D.DISSOLUZIONE[l]) / 100.0 * sp * 1.6
		if l in ["E", "F"]:
			v -= livello
		if l == "B":
			# dopo la B tutte le dissoluzioni successive si ignorano: per una civiltà grande è un affare
			var restano := 40
			if int(eng.sc["turni"]) > 0:
				restano = maxi(0, int(eng.sc["turni"]) - int(eng.turn))
			v += 20.0 + sp * 1.0 + restano * 6.0
		return v
	if l in ["G", "H", "I", "J"]:
		return -3.0
	if l == "K":
		if sag >= 2 and not p["k_usato"] and not eng.ignora("fato_KL", s):
			return livello * 2.0
		return 0.0
	if l == "L":
		if eng.ignora("fato_KL", s):
			return 0.0
		if r == "L1" and sag < 1:
			return 0.0
		return livello
	return 0.0


func _fato(eng, s: int, req: Dictionary) -> Dictionary:
	var tab: Array = eng.tabella_fato()
	var rp := int(req["rp"])
	var sp := int(req["sp"])
	var col0 := int(req["colonna"])
	var gil: bool = req.get("gilham", false)
	var sag_disp := int(req["sag"])
	var p: Dictionary = eng.players[s]
	var x4: bool = p["x"] and str(eng.sc.get("x_regola", "")) == "4"
	var best = {"piu": 0, "sx": 0, "sag": 0}
	var bv = -1e9
	for sagu in range(0, mini(2, sag_disp) + 1):
		var sag_val = sagu + (1 if x4 else 0)
		for piu in range(0, 0 if gil else 3):
			for sx in range(0, col0 + 1):
				var costo = piu * 50 + sx * 5
				if costo > rp:
					continue
				var col = col0 - sx
				var ev := 0.0
				for d in range(1, 7):
					var t := mini(d + piu, 8)
					t = mini(t, tab.size())
					ev += _valore_lettera(eng, s, tab[t - 1][col], sag_val, sp)
				ev /= 6.0
				ev -= costo * 0.35
				ev -= sagu * 4.0
				if ev > bv + 0.01:
					bv = ev
					best = {"piu": piu, "sx": sx, "sag": sagu}
	return best


func _dissoluzione(eng, s: int, req: Dictionary) -> Array:
	var serve := int(req["serve"])
	var mie: Array = req["porte"].duplicate()
	mie.sort_custom(func(a, b): return int(eng.porte[a]["sp"]) < int(eng.porte[b]["sp"]))
	var out := []
	var tot := 0
	# prima prova una sola porta che basti, la più piccola possibile
	for h in mie:
		if int(eng.porte[h]["sp"]) >= serve:
			return [h]
	for h in mie:
		if tot >= serve:
			break
		if int(eng.porte[h]["sp"]) <= 0:
			continue
		out.append(h)
		tot += int(eng.porte[h]["sp"])
	return out


# ---------------------------------------------------------------- risorse

func _risorse(eng, s: int, rp: int) -> Array:
	var out := []
	var stato: Dictionary = eng.stato_risorse(s)
	var p: Dictionary = eng.players[s]
	var prova := func(a: Dictionary) -> bool:
		if eng.azione_valida(s, a, stato) == "":
			eng.simula_azione(s, a, stato)
			out.append(a)
			return true
		return false
	# 1. nuove porte dove ci sono due flotte su un esagono esplorato
	var cand := []
	for h in eng.flotte:
		if eng.n_flotte(h, s) >= 2 and not eng.porte.has(h):
			var v: int = eng.pv_noto(h, s)
			var st_s: Dictionary = eng.stack(h, s)
			if _chiave(eng, h) and v >= 0:
				v = 99
			if v >= 2 or (v == 1 and eng.n_flotte(h, s) >= 4) or (v >= 0 and not st_s["sag"].is_empty()):
				cand.append([v, h])
	cand.sort_custom(func(a, b): return a[0] > b[0])
	for c in cand:
		prova.call({"t": "porta", "h": c[1]})
	# 2. riattivare porte neutralizzate
	for h in eng.porte:
		if eng.porte[h]["neut"]:
			prova.call({"t": "riattiva", "h": h})
	# 3. aumentare le porte fino al potenziale
	for h in eng.porte_di(s):
		var manca: int = eng.potenziale(h) - int(eng.porte[h]["sp"])
		if manca <= 0:
			continue
		var disp: int = eng.n_flotte(h, s) - int(stato["usate"].get(h, 0))
		var tieni = 1 if (int(eng.porte[h]["sp"]) >= 4 and _vicini_ostili(eng, s, h)) else 0
		var n := mini(manca, disp - tieni)
		if n > 0:
			prova.call({"t": "aumenta", "h": h, "n": n})
	# 4. costruire flotte. Il motore della crescita: una regolare costa 3 risorse e, spesa per
	# aumentare una porta, dà un punto sistema per sempre. Si costruisce dove la porta ha ancora
	# margine; altrove solo se c'è un posto vicino dove servono (porte da aumentare, esagoni buoni
	# da colonizzare); esploratrici per esplorare (non costano manutenzione); corazzate se serve.
	var riserva: int = _riserva_fato(eng, s)
	var tot: Dictionary = eng.totale_flotte(s)
	var minacciato = not _minacce(eng, s).is_empty()
	var richiesta = _posti_da_riempire(eng, s)
	var porte_ok: Array = eng.porte_di(s).filter(func(h): return int(eng.porte[h]["sp"]) > 0)
	porte_ok.sort_custom(func(a, b): return eng.potenziale(a) - int(eng.porte[a]["sp"]) > eng.potenziale(b) - int(eng.porte[b]["sp"]))
	var giri := 0
	var esploratrici_volute = 2 + eng.punti_sistema(s) / 10
	if _vuole_saggezza(eng, s):
		esploratrici_volute += 2
	while int(stato["rp"]) > riserva and giri < 40:
		giri += 1
		var fatto := false
		for h in porte_ok:
			if int(stato["rp"]) <= riserva:
				break
			var margine: int = eng.potenziale(h) - int(eng.porte[h]["sp"]) - eng.n_flotte(h, s) - int(stato["costruite"].get(h, 0))
			var t = D.terreno(h)
			var tipi = []
			if margine > 0:
				tipi = ["r"]
			elif t == "A" and int(tot["e"]) < esploratrici_volute and not p["guardiani"]:
				tipi = ["e", "r"]
			elif (t == "A" or t == "F") and (minacciato or p["guardiani"] or (int(tot["d"]) * 5 < int(tot["r"]) and eng.punti_sistema(s) >= 20 and int(stato["rp"]) >= 12)):
				tipi = ["d", "r"]
			elif richiesta > 0:
				tipi = ["r"]
			if tipi.is_empty():
				continue
			for tipo in tipi:
				var a = {"t": "flotta", "h": h, "k": tipo, "n": 1}
				if prova.call(a):
					fatto = true
					tot[tipo] += 1
					if margine <= 0 and tipo == "r":
						richiesta -= 1
					break
		if not fatto:
			break
	# 5. risorse in eccesso: esploratrici (esplorano e non costano manutenzione), poi corazzate
	var extra_giri := 0
	while int(stato["rp"]) > riserva + 12 and extra_giri < 30:
		extra_giri += 1
		var fatto2 := false
		for h in porte_ok:
			if int(stato["rp"]) <= riserva + 12:
				break
			var t2 = D.terreno(h)
			var tipo2 := ""
			if t2 == "A" and int(tot["e"]) < esploratrici_volute + 4:
				tipo2 = "e"
			elif t2 == "A" or t2 == "F":
				tipo2 = "d"
			if tipo2 == "":
				continue
			if prova.call({"t": "flotta", "h": h, "k": tipo2, "n": 1}):
				tot[tipo2] += 1
				fatto2 = true
		if not fatto2:
			break
	if eng.opz.get("gilham", false) and int(stato["rp"]) > 20:
		prova.call({"t": "ricerca", "rp": int(stato["rp"]) - 15})
	return out


## Risorse da tenere per il prossimo Fato: quanto serve per spostarsi a sinistra fino a una
## colonna senza dissoluzioni dannose (5 risorse a colonna), con i punti sistema del prossimo turno.
func _riserva_fato(eng, s: int) -> int:
	var p: Dictionary = eng.players[s]
	var tab: Array = eng.tabella_fato()
	var sp: int = eng.punti_sistema(s) + maxi(2, eng.punti_sistema(s) / 6)
	var gil: bool = eng.opz.get("gilham", false)
	var c0: int = D.col_fato_gilham(sp) if gil else D.col_fato(sp)
	var c = c0
	while c > 0:
		var male := false
		for r in range(0, mini(6, tab.size())):
			var l: String = str(tab[r][c]).substr(0, 1)
			if l in ["A", "B", "C", "D", "E", "F"] and not p["immune"] and not p["diss"].has(l) and not eng.ignora("fato_AF", s) and not eng.ignora("dissoluzione", s):
				male = true
		if not male:
			break
		c -= 1
	if c == c0:
		# colonna già sicura (Fede, o dissoluzioni già subite): se in fondo c'è un aumento di
		# civiltà, si tengono le risorse per aggiungere 1 o 2 al dado
		for r in range(5, mini(8, tab.size())):
			var l2: String = str(tab[r][c0]).substr(0, 1)
			if l2 in ["L", "K"] and not eng.ignora("fato_KL", s) and not (l2 == "K" and (eng.ignora("fato_K", s) or p["k_usato"])):
				return 100 if r >= 6 else 50
	return mini(60, 5 * (c0 - c) + 2)


func _vicini_ostili(eng, s: int, g: int) -> bool:
	for h in eng.flotte:
		if D.distanza(h, g) > 3:
			continue
		for o in eng.proprietari(h):
			if o != s and (o >= 10 or eng.opzione(o, s) != "A"):
				return true
	return false


## Quante flotte servono vicino alle porte: punti mancanti delle porte proprie (oltre le flotte
## già presenti) più due per ogni esagono esplorato buono ancora senza porta.
func _posti_da_riempire(eng, s: int) -> int:
	var n := 0
	for g in eng.porte_di(s):
		n += maxi(0, eng.potenziale(g) - int(eng.porte[g]["sp"]) - eng.n_flotte(g, s))
	for h in eng.players[s]["esplorati"]:
		if eng.porte.has(h) or D.nucleo(h):
			continue
		if eng.pv_noto(h, s) >= 2:
			n += maxi(0, 2 - eng.n_flotte(h, s))
	# flotte libere in giro non impegnate
	var sciolte := 0
	for h in eng.flotte:
		if eng.porta_propria(h, s):
			continue
		if eng.pv_noto(h, s) < 0:
			continue
		sciolte += int(eng.stack(h, s).get("r", 0))
	return n - sciolte


func _schieramento(eng, s: int, budget: int) -> Array:
	var out := []
	var mie: Array = eng.porte_di(s)
	if mie.is_empty():
		return out
	var spesi := 0
	var i := 0
	var esp := 0
	var giri := 0
	while spesi + 3 <= budget and giri < 200:
		giri += 1
		var h: int = mie[i % mie.size()]
		i += 1
		var t = D.terreno(h)
		var k := "r"
		if t == "A" and esp < 2 and spesi + 5 <= budget:
			k = "e"
			esp += 1
		elif (t == "A" or t == "F") and i % 4 == 0 and spesi + 8 <= budget:
			k = "d"
		spesi += D.COSTO[k]
		out.append({"h": h, "k": k, "n": 1})
	return out
