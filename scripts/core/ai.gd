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
	var fase := "riserva" if req.get("riserva", false) else "regolari"
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
		var out := fl.duplicate()
		out["da"] = int(m["da"])
		out["a"] = int(m["a"])
		out["sag"] = int(m.get("sag", 0))
		return out
	return {"fine": true}


func _pianifica(eng, s: int, riserva: bool) -> Array:
	var out := []
	var raggio: int = maxi(1, eng.clr(s))
	var mete := {}
	var minacce := _minacce(eng, s)
	var p: Dictionary = eng.players[s]
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
		if riserva:
			continue
		# 2. gettone saggezza nel centro: lo si prende e si torna alla porta più vicina
		if eng.sag_centro.has(h) and eng.usa_saggezza_in_gioco():
			var dest: int = eng._porta_vicina(h, eng.porte_di(s))
			if dest > 0:
				out.append({"da": h, "a": dest, "r": lib["r"], "d": lib["d"], "e": lib["e"], "sag": 1})
				continue
		var st: Dictionary = eng.stack(h, s)
		if not st.is_empty() and not st["sag"].is_empty():
			var dest2: int = eng._porta_vicina(h, eng.porte_di(s))
			if dest2 > 0:
				out.append({"da": h, "a": dest2, "r": lib["r"], "d": lib["d"], "e": lib["e"]})
				continue
		var tenere := {"r": 0, "d": 0, "e": 0}
		# 3. chi sta su un esagono da esplorare resta (se ha esploratrici o è numeroso)
		var pvn: int = eng.pv_noto(h, s)
		var porta: Dictionary = eng.porta(h)
		if porta.is_empty() and not D.nucleo(h):
			if pvn < 0:
				tenere = lib.duplicate()
			elif pvn >= 2:
				# si resta per costruire una porta (servono due flotte)
				var serve := 2
				for k in ["r", "e", "d"]:
					var q: int = mini(serve, int(lib[k]))
					tenere[k] += q
					serve -= q
		elif not porta.is_empty() and eng.porta_propria(h, s):
			# porta propria: si resta per aumentarla fino al potenziale, tenendo le corazzate a difesa
			var manca: int = eng.potenziale(h) - int(porta["sp"])
			for k in ["r", "e"]:
				var q2: int = mini(manca, int(lib[k]))
				tenere[k] += q2
				manca -= q2
			if p["guardiani"]:
				tenere = lib.duplicate()
			tenere["d"] = mini(int(lib["d"]), maxi(int(tenere["d"]), 1 if eng.punti_sistema(s) > 0 else 0))
		var mov = {"r": int(lib["r"]) - int(tenere["r"]), "d": int(lib["d"]) - int(tenere["d"]), "e": int(lib["e"]) - int(tenere["e"])}
		if mov["r"] + mov["d"] + mov["e"] <= 0:
			continue
		var meta := _meta(eng, s, h, mov, raggio, mete)
		if meta > 0:
			mete[meta] = true
			out.append({"da": h, "a": meta, "r": mov["r"], "d": mov["d"], "e": mov["e"]})
	return out


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
	var portata := raggio
	if da_porta:
		portata = maxi(raggio, 3)
	var c0 := D.col(h)
	var r0 := D.row(h)
	for c in range(c0 - portata, c0 + portata + 1):
		for r in range(r0 - portata, r0 + portata + 1):
			var x := D.hx(c, r)
			if x == h or not D.esiste(x) or D.nucleo(x):
				continue
			var dist := D.distanza(h, x)
			if dist > portata:
				continue
			if eng.mossa_valida(s, h, x, fl) != "":
				continue
			var ri: Dictionary = eng.rischio(s, h, x, fl)
			if int(ri["rischio"]) >= 3:
				continue
			var v := 0.0
			var t := D.terreno(x)
			var g: Dictionary = eng.porta(x)
			var nota: int = eng.pv_noto(x, s)
			if not g.is_empty():
				if eng.porta_propria(x, s):
					v += 0.5 if int(g["sp"]) < eng.potenziale(x) else -2.0
				elif g["neut"]:
					v += 3.0 if eng.n_flotte(x, s) == 0 else 0.0
				else:
					v -= 4.0
			elif not p["esplorati"].has(x) or nota < 0:
				v += {"A": 4.0, "F": 3.0, "I": 1.5}.get(t, 0.0)
			elif nota >= 2:
				v += 1.0 + nota * 0.6
			else:
				v -= 1.0
			# vicino alle proprie porte è meglio
			var vicina := 99
			for pg in eng.porte_di(s):
				vicina = mini(vicina, D.distanza(pg, x))
			v -= maxf(0.0, vicina - 2) * 0.7
			v -= dist * 0.4
			v -= int(ri["rischio"]) * 1.5
			if mete.has(x):
				v -= 3.0
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
	var miaf := _forza(eng, s)
	for o in req["parti"]:
		var loro := str(req["loro"].get(o, ""))
		var attuale := str(req["attuali"].get(o, ""))
		var v := "B"
		if o >= 10:
			v = "A" if loro != "C" else "C"
			if loro == "C" and miaf < _forza(eng, o):
				v = "A"
		else:
			var lorof := _forza(eng, o)
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
	var dich := vera
	if rng.randf() < 0.5:
		dich = int(round(vera * rng.randf_range(0.7, 1.3)))
	return {"attacca": att, "dich": dich}


func _bersaglio(eng, s: int, req: Dictionary) -> int:
	var h := int(req["h"])
	var best: int = req["bersagli"][0]
	var bv := 1 << 30
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
	if l in ["A", "B", "C", "D", "E", "F"]:
		if eng.ignora("fato_AF", s) or eng.ignora("dissoluzione", s) or p["immune"] or p["diss"].has(l):
			return 0.0
		var v: float = -float(D.DISSOLUZIONE[l]) / 100.0 * sp * 2.5
		if l in ["E", "F"]:
			v -= 40.0
		if l == "B":
			v += 10.0
		return v
	if l in ["G", "H", "I", "J"]:
		return -3.0
	if l == "K":
		if sag >= 2 and not p["k_usato"] and not eng.ignora("fato_KL", s):
			return 120.0
		return 0.0
	if l == "L":
		if eng.ignora("fato_KL", s):
			return 0.0
		if r == "L1" and sag < 1:
			return 0.0
		return 70.0
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
	var best := {"piu": 0, "sx": 0, "sag": 0}
	var bv := -1e9
	for sagu in range(0, mini(2, sag_disp) + 1):
		var sag_val := sagu + (1 if x4 else 0)
		for piu in range(0, 0 if gil else 3):
			for sx in range(0, col0 + 1):
				var costo := piu * 50 + sx * 5
				if costo > rp:
					continue
				var col := col0 - sx
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
			if v >= 1:
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
		var tieni = 1 if eng.punti_sistema(s) > 6 else 0
		var n := mini(manca, disp - tieni)
		if n > 0:
			prova.call({"t": "aumenta", "h": h, "n": n})
	# 4. costruire flotte
	var riserva = 6 if not eng.opz.get("gilham", false) else 0
	var tot: Dictionary = eng.totale_flotte(s)
	var minacciato := not _minacce(eng, s).is_empty()
	var porte_ok: Array = eng.porte_di(s).filter(func(h): return int(eng.porte[h]["sp"]) > 0)
	porte_ok.sort_custom(func(a, b): return int(eng.porte[a]["sp"]) > int(eng.porte[b]["sp"]))
	var giri := 0
	while int(stato["rp"]) > riserva and giri < 40:
		giri += 1
		var fatto := false
		for h in porte_ok:
			if int(stato["rp"]) <= riserva:
				break
			var tipo := "r"
			var t := D.terreno(h)
			if t == "A" and int(tot["e"]) < 2 + eng.punti_sistema(s) / 15 and not p["guardiani"]:
				tipo = "e"
			elif (t == "A" or t == "F") and (minacciato or p["guardiani"] or (int(tot["d"]) * 4 < int(tot["r"]) and int(stato["rp"]) >= 16)):
				tipo = "d"
			var a := {"t": "flotta", "h": h, "k": tipo, "n": 1}
			if int(stato["rp"]) - D.COSTO[tipo] < riserva - 3:
				a["k"] = "r"
			if prova.call(a):
				fatto = true
				tot[a["k"]] += 1
		if not fatto:
			break
	if eng.opz.get("gilham", false) and int(stato["rp"]) > 20:
		prova.call({"t": "ricerca", "rp": int(stato["rp"]) - 15})
	return out


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
		var t := D.terreno(h)
		var k := "r"
		if t == "A" and esp < 2 and spesi + 5 <= budget:
			k = "e"
			esp += 1
		elif (t == "A" or t == "F") and i % 4 == 0 and spesi + 8 <= budget:
			k = "d"
		spesi += D.COSTO[k]
		out.append({"h": h, "k": k, "n": 1})
	return out
