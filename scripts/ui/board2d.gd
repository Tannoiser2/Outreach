extends Control
## Mappa 2D della Galassia: la mappa SPI originale (o la griglia Reborn) con le pedine.
## Rotella o pizzico per lo zoom, trascinamento per spostarsi, clic per scegliere un esagono.

const D = preload("res://scripts/data/od_data.gd")

signal hex_clicked(h: int)
signal hex_hovered(h: int)

var eng: ODEngine
var vista := -1                    # il giocatore di cui si mostrano le informazioni (-1 = tutto)
var tutto_visibile := false
var tex: Texture2D
var nuv_sotto: Texture2D
var tex_linee: Texture2D
var opac_mappa := 1.0
var opac_griglia := 0.0
var zoom := 0.3
var pan = Vector2.ZERO
var selezionato := -1
var bersagli := {}                 # esagono -> colore di evidenziazione
var hover := -1
var _drag := false
var _drag_from = Vector2.ZERO
var _press = Vector2.ZERO
var _moved := false
var linee: Array = []              # [{da, a, col, t}]
var lampi: Array = []              # [{h, col, t, r}]
var t := 0.0
var mostra_numeri := true
var nuvola := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	ricarica()


func ricarica() -> void:
	tex = Grafica.mappa()
	nuv_sotto = load("res://assets/board/nuvola_sotto.png")
	tex_linee = load("res://assets/board/linee.png")
	queue_redraw()


func adatta() -> void:
	if tex == null or size.x <= 0:
		return
	zoom = minf(size.x / tex.get_width(), size.y / tex.get_height())
	pan = (size - tex.get_size() * zoom) / 2.0
	queue_redraw()


func centra_su(h: int, z := -1.0) -> void:
	if z > 0:
		zoom = z
	var p = Grafica.centro_px(h, tex.get_width())
	pan = size / 2.0 - p * zoom
	queue_redraw()


func px(h: int) -> Vector2:
	return pan + Grafica.centro_px(h, tex.get_width()) * zoom


func rpx() -> float:
	return Grafica.raggio_px(tex.get_width()) * zoom


func hex_at(p: Vector2) -> int:
	var tp = (p - pan) / zoom
	var best := -1
	var bd = 1e9
	var w := float(tex.get_width())
	var r = Grafica.raggio_px(w)
	# stima della colonna e della riga, poi ricerca fra i vicini
	var c0 := 0
	var r0 := 0
	if Grafica.usa_griglia():
		var u = tp / (Grafica.GS * w / 4045.0) - Vector2(Grafica.GMX, Grafica.GMY)
		c0 = int(round(u.x / 1.5)) + 1
		r0 = int(round(u.y / sqrt(3.0))) + 1
	else:
		var g = Grafica.geom()
		var k = w / float(g[4])
		c0 = int(round((tp.x / k - g[0]) / g[2])) + 7
		r0 = int(round((tp.y / k - g[1]) / g[3])) + 1
	for c in range(c0 - 1, c0 + 2):
		for rr in range(r0 - 1, r0 + 2):
			var h = D.hx(c, rr)
			if not D.esiste(h):
				continue
			var d = Grafica.centro_px(h, w).distance_to(tp)
			if d < bd:
				bd = d
				best = h
	if bd > r * 1.05:
		return -1
	return best


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb = ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_drag = true
				_drag_from = mb.position
				_press = mb.position
				_moved = false
			else:
				_drag = false
				if mb.button_index == MOUSE_BUTTON_LEFT and not _moved:
					var h = hex_at(mb.position)
					if h > 0:
						hex_clicked.emit(h)
	elif ev is InputEventMouseMotion:
		var mm = ev as InputEventMouseMotion
		if _drag:
			if mm.position.distance_to(_press) > 6.0:
				_moved = true
			if _moved:
				pan += mm.position - _drag_from
				_drag_from = mm.position
				queue_redraw()
		var h2 = hex_at(mm.position)
		if h2 != hover:
			hover = h2
			hex_hovered.emit(h2)
			queue_redraw()
	elif ev is InputEventMagnifyGesture:
		var mg = ev as InputEventMagnifyGesture
		_zoom_at(mg.position, mg.factor)
	elif ev is InputEventPanGesture:
		var pg = ev as InputEventPanGesture
		pan -= pg.delta * 8.0
		queue_redraw()


func _zoom_at(p: Vector2, f: float) -> void:
	var nz := clampf(zoom * f, 0.08, 2.5)
	var tp = (p - pan) / zoom
	zoom = nz
	pan = p - tp * zoom
	queue_redraw()


func _process(d: float) -> void:
	t += d
	var cambia := false
	for l in linee:
		l["t"] += minf(d, 1.0 / 30.0)
		cambia = true
	linee = linee.filter(func(x): return x["t"] < VOLO + CODA)
	for l in lampi:
		l["t"] -= d
		cambia = true
	lampi = lampi.filter(func(x): return x["t"] > 0)
	if cambia or bersagli.size() > 0 or selezionato > 0:
		queue_redraw()


func effetto(kind: String, data: Dictionary) -> void:
	match kind:
		"salto":
			linee.append({"da": int(data["da"]), "a": int(data["a"]), "col": Grafica.tinta(int(data["o"])), "t": 0.0, "fine": -1})
		"disperso":
			linee.append({"da": int(data["da"]), "a": int(data["a"]), "col": Grafica.tinta(int(data["o"])), "t": 0.0, "fine": int(data.get("h", -1))})
			lampi.append({"h": int(data["h"]), "col": UI.ROSSO, "t": 1.2, "r": 1.0})
		"attacco":
			lampi.append({"h": int(data["h"]), "col": Color(1, 0.4, 0.2), "t": 1.0, "r": 1.3})
		"neutralizza":
			lampi.append({"h": int(data["h"]), "col": Color(0.8, 0.8, 1.0), "t": 1.2, "r": 1.1})
		"contatto":
			lampi.append({"h": int(data["h"]), "col": UI.AMBRA, "t": 1.0, "r": 0.9})
		"esplora":
			lampi.append({"h": int(data["h"]), "col": Color(0.5, 0.9, 1.0), "t": 0.9, "r": 0.8})
		"porta":
			lampi.append({"h": int(data["h"]), "col": Grafica.tinta(int(data["o"])), "t": 1.0, "r": 0.9})
		"autonomi":
			lampi.append({"h": int(data["h"]), "col": Grafica.tinta(int(data["o"])), "t": 1.6, "r": 2.2})
	queue_redraw()


# ---------------------------------------------------------------- disegno

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.04))
	if tex == null:
		return
	var rg = _rect_generati()
	if nuvola and nuv_sotto != null:
		draw_texture_rect(nuv_sotto, rg, false, Color(1, 1, 1, 0.9))
	if opac_mappa > 0.001:
		draw_texture_rect(tex, Rect2(pan, tex.get_size() * zoom), false, Color(1, 1, 1, opac_mappa))
	if opac_griglia > 0.001 and tex_linee != null:
		draw_texture_rect(tex_linee, rg, false, Color(1, 1, 1, opac_griglia))
	if eng == null:
		return
	var r = rpx()
	var font = UI.font("numeri")
	var fs := int(clampf(r * 0.42, 9, 40))
	# evidenziazioni
	for h in bersagli:
		_esagono(px(h), r * 0.92, bersagli[h], 2.5)
	if hover > 0:
		_esagono(px(hover), r * 0.95, Color(1, 1, 1, 0.5), 1.5)
	if selezionato > 0:
		var pulse = 0.6 + 0.4 * sin(t * 5.0)
		_esagono(px(selezionato), r * 0.95, Color(UI.AMBRA, pulse), 4.0)
	# gettoni del potenziale
	for h in eng.pv:
		if eng.porte.has(h):
			continue
		var p = px(h) + Vector2(r * 0.42, -r * 0.42)
		var s = r * 0.42
		draw_rect(Rect2(p - Vector2(s, s) / 2, Vector2(s, s)), Color(0.66, 0.68, 0.64))
		draw_rect(Rect2(p - Vector2(s, s) / 2, Vector2(s, s)), Color(0.2, 0.2, 0.2), false, 1.0)
		var v = eng.valore_pv(h) if tutto_visibile else (eng.pv_noto(h, vista) if vista >= 0 else -1)
		var txt = str(v) if v >= 0 else "?"
		draw_string(font, p + Vector2(-s * 0.5, s * 0.32), txt, HORIZONTAL_ALIGNMENT_CENTER, s, int(s * 0.8), Color(0.1, 0.1, 0.1))
	# stelle faro scoperte
	var tf = Grafica.tex("faro")
	for h in eng.fari:
		if D.faro_stampato(h) != "" and not Grafica.usa_griglia():
			continue
		var p2 = px(h) + Vector2(-r * 0.45, r * 0.4)
		if tf != null:
			draw_texture_rect(tf, Rect2(p2 - Vector2(r, r) * 0.22, Vector2(r, r) * 0.44), false)
	# saggezza nel centro
	var ts = Grafica.tex("saggezza")
	for h in eng.sag_centro:
		var p3 = px(h) + Vector2(r * 0.4, r * 0.35)
		if ts != null:
			draw_texture_rect(ts, Rect2(p3 - Vector2(r, r) * 0.2, Vector2(r, r) * 0.4), false)
	# porte
	for h in eng.porte:
		var g: Dictionary = eng.porte[h]
		var p4 = px(h) + Vector2(-r * 0.25, -r * 0.3)
		var s4 = r * 0.62
		var o := int(g.get("prima", g["o"])) if g["neut"] else int(g["o"])
		var tg = Grafica.tex(Grafica.nome_porta(o))
		var rect := Rect2(p4 - Vector2(s4, s4) / 2, Vector2(s4, s4))
		if tg != null:
			draw_texture_rect(tg, rect, false, Color(0.35, 0.35, 0.35) if g["neut"] else Color.WHITE)
		else:
			draw_rect(rect, Grafica.tinta(o))
		if g["neut"]:
			draw_string(font, rect.position + Vector2(0, s4 * 0.7), "N", HORIZONTAL_ALIGNMENT_CENTER, s4, int(s4 * 0.6), UI.ROSSO)
		elif _vede_porta(o):
			_etichetta(rect.position + Vector2(s4 * 0.7, s4 * 0.05), str(g["sp"]), fs)
	# flotte
	for h in eng.flotte:
		var ps: Array = eng.proprietari(h)
		var i := 0
		for o in ps:
			var p5 = px(h) + Vector2(r * 0.2 + i * r * 0.18, r * 0.05 + i * r * 0.18)
			var s5 = r * 0.6
			var tf2 = Grafica.tex(Grafica.nome_flotta(o))
			var rect2 := Rect2(p5 - Vector2(s5, s5) / 2, Vector2(s5, s5))
			draw_rect(Rect2(rect2.position + Vector2(2, 3), rect2.size), Color(0, 0, 0, 0.5))
			if tf2 != null:
				draw_texture_rect(tf2, rect2, false)
			else:
				draw_rect(rect2, Grafica.tinta(o))
			if _vede_flotte(o):
				var st: Dictionary = eng.stack(h, o)
				var testo = "%d" % (int(st["r"]) + int(st["d"]) + int(st["e"]))
				_etichetta(rect2.position + Vector2(s5 * 0.62, s5 * 0.62), testo, fs)
				if zoom > 0.45:
					var dett = "%dr %dd %de" % [st["r"], st["d"], st["e"]]
					draw_string(font, rect2.position + Vector2(-s5 * 0.2, s5 + fs * 0.9), dett, HORIZONTAL_ALIGNMENT_CENTER, s5 * 1.4, int(fs * 0.7), Color(1, 1, 1, 0.9))
				if not st["sag"].is_empty():
					var tw = Grafica.tex("saggezza")
					if tw != null:
						draw_texture_rect(tw, Rect2(rect2.position + Vector2(-s5 * 0.3, -s5 * 0.3), Vector2(s5, s5) * 0.45), false)
			i += 1
	# segnalini di contatto
	for h in eng.contatti:
		var ps2: Array = eng.proprietari(h).filter(func(x): return x < 10)
		var o2: int = ps2[0] if not ps2.is_empty() else 0
		var tc = Grafica.tex(Grafica.nome_contatto(o2))
		var p6 = px(h) + Vector2(-r * 0.5, r * 0.15)
		var s6 = r * 0.42
		if tc != null:
			draw_texture_rect(tc, Rect2(p6 - Vector2(s6, s6) / 2, Vector2(s6, s6)), false)
		else:
			draw_string(font, p6, "C", HORIZONTAL_ALIGNMENT_CENTER, s6, int(s6), UI.AMBRA)
	# effetti
	for l in linee:
		_disegna_filo(l, r)
	for l in lampi:
		var c2: Color = l["col"]
		var k := float(l["t"])
		c2.a = clampf(k, 0.0, 1.0) * 0.8
		draw_arc(px(int(l["h"])), r * float(l["r"]) * (1.6 - k * 0.5), 0, TAU, 40, c2, 4.0, true)


## Rettangolo a schermo delle immagini generate (nuvole e griglia), allineato alla mappa di fondo.
func _rect_generati() -> Rect2:
	var w := float(tex.get_width())
	var a: Vector2 = Grafica.centro_px(101, w)
	var b: Vector2 = Grafica.centro_px(5129, w)
	var ga = (D.centro(101) + Vector2(Grafica.GMX, Grafica.GMY)) * Grafica.GS
	var gb = (D.centro(5129) + Vector2(Grafica.GMX, Grafica.GMY)) * Grafica.GS
	var k := Vector2((b.x - a.x) / (gb.x - ga.x), (b.y - a.y) / (gb.y - ga.y))
	var o = a - ga * k
	return Rect2(pan + o * zoom, Vector2(4045.0, 2712.0) * k * zoom)


func _vede_porta(o: int) -> bool:
	if tutto_visibile or vista < 0:
		return true
	if o == vista:
		return true
	if o >= 10:
		return int(eng.aut[o - 10]["custode"]) == vista
	return false


func _vede_flotte(o: int) -> bool:
	return _vede_porta(o)


func _etichetta(p: Vector2, testo: String, fs: int) -> void:
	var font = UI.font("numeri")
	var w = font.get_string_size(testo, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6
	draw_rect(Rect2(p - Vector2(2, fs * 0.85), Vector2(w, fs * 1.05)), Color(0, 0, 0, 0.75))
	draw_string(font, p + Vector2(1, 0), testo, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.92, 0.7))


func _esagono(c: Vector2, r: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 7:
		var a := deg_to_rad(60.0 * i)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_polyline(pts, col, w, true)


const VOLO := 1.3
const CODA := 0.9

## Balzo: arco d'argento che si alza sulla mappa, testa luminosa e coda che svanisce.
func _disegna_filo(l: Dictionary, r: float) -> void:
	var a = px(int(l["da"]))
	var b = px(int(l["a"]))
	var punti := PackedVector2Array()
	var n := 40
	var lun = a.distance_to(b)
	var alza := clampf(lun * 0.35, r * 0.8, r * 12.0)
	for i in n + 1:
		var k = float(i) / n
		punti.append(a.lerp(b, k) + Vector2(0, -sin(k * PI) * alza))
	var n_arco = n
	if int(l["fine"]) > 0:
		var f = px(int(l["fine"]))
		for i in range(1, 11):
			var k2 = float(i) / 10
			punti.append(b.lerp(f, k2) + Vector2(0, -sin(k2 * PI) * r * 0.6))
	var tot = punti.size() - 1
	var t3: float = l["t"]
	var testa = clampf(t3 / VOLO, 0.0, 1.0) * tot
	var sv = maxf(0.0, t3 - VOLO) / CODA
	var coda := maxf(0.0, testa - tot * 0.55)
	if sv > 0:
		coda = minf(testa, tot * sv)
	var argento := Color(0.84, 0.88, 0.97).lerp(l["col"], 0.25)
	for i in range(int(coda), int(ceil(testa))):
		var u := clampf((float(i) - coda) / maxf(0.001, testa - coda), 0.0, 1.0)
		var c = argento if i < n_arco else Color(1.0, 0.35, 0.25)
		c.a = u * u * (1.0 - sv)
		draw_line(punti[i], punti[mini(i + 1, tot)], c, 1.0 + 3.0 * u, true)
	if sv < 0.3:
		var hp = punti[clampi(int(round(testa)), 0, tot)]
		draw_circle(hp, r * 0.16, Color(1, 1, 1, 0.35))
		draw_circle(hp, r * 0.08, Color(1, 1, 1, 0.95))
