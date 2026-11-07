extends RefCounted
## Dati di Outreach (SPI, 1976): mappa, tabelle (originali e rivedute), scenari, fazioni.
## La mappa (terreno di ogni esagono, stelle faro, lati di polvere interstellare) è stata letta
## dalla mappa originale del modulo TTS e sta in assets/mappa.json.

# ---------------------------------------------------------------- mappa

## Esagono codificato come intero: colonna * 100 + riga (come la numerazione SPI XXYY).
static var _map := {}

static func mappa() -> Dictionary:
	if _map.is_empty():
		var f = FileAccess.open("res://assets/mappa.json", FileAccess.READ)
		var d: Dictionary = JSON.parse_string(f.get_as_text())
		var esa := {}
		for k in d["esagoni"]:
			esa[int(k)] = str(d["esagoni"][k])
		var fari := {}
		for k in d["fari"]:
			fari[int(k)] = str(d["fari"][k])
		var pol := {}
		for e in d["polvere"]:
			var p: PackedStringArray = str(e).split("-")
			var a := int(p[0])
			var b := int(p[1])
			pol[_edge(a, b)] = true
		_map = {"esagoni": esa, "fari": fari, "polvere": pol, "colonne": int(d["colonne"]), "righe": int(d["righe"])}
	return _map


static func _edge(a: int, b: int) -> int:
	return mini(a, b) * 10000 + maxi(a, b)


## Terreno: "A" asse della spirale, "F" frangia, "I" interspirale, "N" nucleo, "W" centro del nucleo.
static func terreno(h: int) -> String:
	return mappa()["esagoni"].get(h, "")


static func esiste(h: int) -> bool:
	return mappa()["esagoni"].has(h)


static func nucleo(h: int) -> bool:
	var t = terreno(h)
	return t == "N" or t == "W"


static func faro_stampato(h: int) -> String:
	return mappa()["fari"].get(h, "")


static func polvere(a: int, b: int) -> bool:
	return mappa()["polvere"].has(_edge(a, b))


static func col(h: int) -> int:
	return h / 100


static func row(h: int) -> int:
	return h % 100


static func hx(c: int, r: int) -> int:
	return c * 100 + r


static func nome(h: int) -> String:
	return "%04d" % h


## Coordinate cubiche (colonne 1, 3, 5... più in alto: le pari sono spostate di mezzo esagono in basso).
static func cubo(h: int) -> Vector3i:
	var q = col(h) - 1
	var r = row(h) - 1
	var x = q
	var z = r - (q - (q & 1)) / 2
	return Vector3i(x, -x - z, z)


static func da_cubo(c: Vector3i) -> int:
	var q = c.x
	var r = c.z + (q - (q & 1)) / 2
	return hx(q + 1, r + 1)


static func distanza(a: int, b: int) -> int:
	var ca = cubo(a)
	var cb = cubo(b)
	return maxi(maxi(absi(ca.x - cb.x), absi(ca.y - cb.y)), absi(ca.z - cb.z))


## Direzioni del diagramma di dispersione: 1 su, 2 su-destra, 3 giù-destra, 4 giù, 5 giù-sinistra, 6 su-sinistra.
const DIR_CUBO := [Vector3i(0, 1, -1), Vector3i(1, 0, -1), Vector3i(1, -1, 0), Vector3i(0, -1, 1), Vector3i(-1, 0, 1), Vector3i(-1, 1, 0)]

static func passo(h: int, dir: int, n := 1) -> int:
	var c = cubo(h) + DIR_CUBO[dir - 1] * n
	return da_cubo(c)


static func vicini(h: int) -> Array:
	var out := []
	for d in 6:
		var v = passo(h, d + 1)
		if esiste(v):
			out.append(v)
	return out


## Centro dell'esagono nel piano (unità: lato dell'esagono = 1).
static func centro(h: int) -> Vector2:
	var c = col(h)
	var r = row(h)
	var y = (r - 1) * sqrt(3.0) + (0.0 if c % 2 == 1 else sqrt(3.0) / 2.0)
	return Vector2((c - 1) * 1.5, y)


static func da_punto(p: Vector2) -> int:
	# punto -> esagono (arrotondamento cubico)
	var q = p.x / 1.5
	var qf := roundf(q)
	# conversione assiale "flat top": q = 2/3 x, r = -1/3 x + sqrt3/3 y
	var aq = (2.0 / 3.0) * p.x
	var ar = (-1.0 / 3.0) * p.x + (sqrt(3.0) / 3.0) * p.y
	var cx = aq
	var cz = ar
	var cy = -cx - cz
	var rx := roundf(cx)
	var ry := roundf(cy)
	var rz := roundf(cz)
	var dx := absf(rx - cx)
	var dy := absf(ry - cy)
	var dz := absf(rz - cz)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	var _u = qf
	# l'origine assiale è il centro dell'esagono 0101; nel sistema di colonne dispari in alto
	# l'asse r assiale corrisponde a z cubico
	return da_cubo(Vector3i(int(rx), int(ry), int(rz)))


## Linea di vista: bloccata se attraversa un lato di polvere interstellare (15.15).
static func vista(a: int, b: int) -> bool:
	if a == b:
		return true
	var pa = centro(a)
	var pb = centro(b)
	var n = int(pa.distance_to(pb) * 6.0) + 2
	var prec = a
	for i in range(1, n + 1):
		var p = pa.lerp(pb, float(i) / n)
		var h = da_punto(p)
		if h != prec:
			if distanza(h, prec) == 1 and polvere(h, prec):
				return false
			prec = h
	return true


## La linea fra due esagoni attraversa la polvere (per lo spostamento, 5.73)?
static func attraverso_polvere(a: int, b: int) -> bool:
	return not vista(a, b)


# ---------------------------------------------------------------- gettoni del potenziale

## I 60 gettoni del potenziale: [asse, frangia, interspirale].
const GETTONI_PV := [
	[1, 1, 0], [5, 4, 1], [3, 2, 4], [2, 2, 1], [2, 3, 0], [2, 3, 3], [4, 5, 1], [4, 5, 0], [3, 2, 0], [3, 5, 1],
	[1, 2, 1], [5, 2, 1], [1, 2, 3], [4, 1, 1], [4, 2, 0], [4, 3, 1], [4, 3, 2], [3, 3, 4], [5, 2, 0], [3, 4, 1],
	[3, 2, 0], [5, 2, 0], [4, 0, 0], [2, 3, 1], [2, 3, 2], [4, 3, 3], [5, 2, 0], [3, 4, 1], [4, 2, 0], [3, 4, 0],
	[4, 4, 0], [0, 5, 2], [4, 1, 2], [5, 3, 3], [3, 3, 3], [3, 1, 4], [3, 5, 0], [4, 4, 0], [5, 2, 2], [4, 2, 0],
	[2, 1, 5], [4, 0, 4], [5, 1, 2], [2, 3, 1], [4, 4, 1], [4, 4, 1], [5, 3, 0], [5, 1, 0], [1, 2, 0], [4, 2, 3],
	[5, 4, 3], [4, 3, 0], [3, 3, 1], [3, 1, 2], [3, 2, 1], [3, 3, 0], [4, 5, 2], [2, 2, 0], [3, 3, 3], [5, 4, 2],
]

static func valore_pv(chit: Array, h: int) -> int:
	match terreno(h):
		"A":
			return int(chit[0])
		"F":
			return int(chit[1])
		_:
			return int(chit[2])


# ---------------------------------------------------------------- tabelle

## Esplorazione (6.2): colonna per flotte corrette 1-2, 3-4, 5-6, 7-9, 10-12, 13+; riuscita se dado <= colonna+1.
static func col_esplorazione(n: int) -> int:
	if n <= 2: return 0
	if n <= 4: return 1
	if n <= 6: return 2
	if n <= 9: return 3
	if n <= 12: return 4
	return 5


## Contatto (7.4): colonne 0, 1, 2-4, 5-9, 10-16, 17+; contatto se dado <= indice di colonna.
static func col_contatto(n: int) -> int:
	if n <= 0: return 0
	if n == 1: return 1
	if n <= 4: return 2
	if n <= 9: return 3
	if n <= 16: return 4
	return 5


## Dispersione (5.6): colonne per esagoni 2, 3, 4, 5, 6-8, 9-15, 16-24, 25+; righe dado 1..9 (10+ nulla).
## Ogni casella: [distanza, perdita %], [] = nessuna dispersione.
static func col_dispersione(d: int) -> int:
	if d <= 2: return 0
	if d <= 5: return d - 2
	if d <= 8: return 4
	if d <= 15: return 5
	if d <= 24: return 6
	return 7

const DISP_ORIGINALE := [
	["1/0", "1/0", "1/0", "1/0", "3/10", "6/20", "10/40", "15/60"],
	["4/15", "3/10", "2/10", "2/10", "4/10", "7/30", "11/50", "16/75"],
	["", "5/20", "3/10", "3/10", "5/15", "8/40", "12/60", "16/75"],
	["", "", "4/15", "4/15", "6/20", "8/40", "12/60", "17/75"],
	["", "", "", "5/20", "7/30", "9/45", "13/60", "17/75"],
	["", "", "", "", "8/30", "10/50", "13/60", "18/80"],
	["", "", "", "", "", "11/50", "14/75", "19/80"],
	["", "", "", "", "", "", "15/80", "19/80"],
	["", "", "", "", "", "", "", "20/80"],
]
const DISP_SKYGAZER := [
	["4/15", "5/20", "4/15", "5/20", "8/30", "11/50", "15/80", "20/80"],
	["1/0", "3/10", "3/10", "4/15", "7/30", "10/50", "14/75", "19/80"],
	["", "1/0", "2/10", "3/10", "6/20", "9/45", "13/60", "19/80"],
	["", "", "1/0", "2/10", "5/15", "8/40", "13/60", "18/80"],
	["", "", "", "1/0", "4/10", "8/40", "12/60", "17/75"],
	["", "", "", "", "3/10", "7/30", "12/60", "17/75"],
	["", "", "", "", "", "6/20", "11/50", "16/75"],
	["", "", "", "", "", "", "10/40", "16/75"],
	["", "", "", "", "", "", "", "15/60"],
]
const DISP_V3 := [
	["4/10", "5/20", "4/20", "5/20", "8/30", "11/50", "15/80", "20/80"],
	["1/0", "3/10", "3/10", "4/20", "7/30", "10/50", "14/70", "19/80"],
	["", "1/0", "2/10", "3/10", "6/20", "9/40", "13/60", "19/80"],
	["", "", "1/0", "2/10", "5/20", "8/40", "13/60", "18/80"],
	["", "", "", "1/0", "4/10", "8/40", "12/60", "17/70"],
	["", "", "", "", "3/10", "7/30", "12/60", "17/70"],
	["", "", "", "", "", "6/20", "11/50", "16/70"],
	["", "", "", "", "", "", "10/40", "16/70"],
	["", "", "", "", "", "", "", "15/60"],
]

## Conflitto (9.2): colonne 33-65%, 66-99, 100-149, 150-199, 200-299, 300-399, 400+; righe dado -2..9.
const CONF_ORIGINALE := [
	["75/15", "60/15", "75/30", "45/30", "30/30", "30/75", "0/100"],
	["75/15", "60/15", "75/30", "45/30", "30/30", "30/75", "0/100"],
	["75/15", "75/30", "75/30", "30/30", "30/60", "30/75", "0/100"],
	["50/10", "50/20", "40/20", "20/20", "20/40", "20/50", "0/100"],
	["50/10", "50/20", "30/20", "30/40", "20/40", "20/50", "0/100"],
	["50/10", "50/20", "40/40", "20/40", "20/50", "20/60", "0/100"],
	["40/10", "40/20", "30/40", "20/40", "20/50", "15/75", "0/100"],
	["40/10", "40/20", "30/40", "20/40", "20/50", "10/80", "0/100"],
	["40/20", "40/40", "20/40", "20/50", "20/60", "0/100", "0/100"],
	["60/40", "75/75", "30/60", "30/75", "30/80", "0/100", "0/100"],
	["60/60", "30/30", "30/75", "30/75", "30/80", "0/100", "0/100"],
	["15/30", "15/30", "30/75", "15/60", "0/100", "0/100", "0/100"],
]
const CONF_V3 := [
	["100/0", "100/10", "90/20", "80/30", "70/40", "60/50", "50/60"],
	["100/0", "90/10", "80/20", "70/30", "60/40", "50/50", "40/60"],
	["100/10", "90/20", "70/30", "60/40", "50/50", "40/60", "30/70"],
	["80/10", "70/20", "60/30", "50/40", "40/50", "30/60", "20/70"],
	["70/10", "60/20", "50/30", "40/40", "30/50", "20/60", "10/70"],
	["60/10", "50/20", "40/30", "30/40", "20/50", "10/60", "0/70"],
	["60/20", "50/30", "40/40", "30/50", "20/60", "10/70", "0/80"],
	["60/20", "50/30", "40/40", "30/50", "20/60", "10/70", "0/80"],
	["50/20", "40/30", "30/40", "20/50", "10/60", "10/70", "0/80"],
	["40/30", "30/40", "20/50", "10/60", "10/70", "0/80", "0/90"],
	["30/40", "20/50", "10/60", "10/70", "0/80", "0/90", "0/100"],
	["20/50", "10/60", "10/70", "0/80", "0/90", "0/100", "0/100"],
]

static func col_conflitto(att: int, dif: int) -> int:
	if dif <= 0:
		return 6
	var p := float(att) * 100.0 / float(dif)
	if p < 66.0: return 0
	if p < 100.0: return 1
	if p < 150.0: return 2
	if p < 200.0: return 3
	if p < 300.0: return 4
	if p < 400.0: return 5
	return 6

## Riduzione (10.3): colonne -2..0, 1-2, 3-4, 5-6, 7+; neutralizzazione se dado <= colonna+1. Sotto -2 nulla.
static func col_riduzione(diff: int) -> int:
	if diff < -2: return -1
	if diff <= 0: return 0
	if diff <= 2: return 1
	if diff <= 4: return 2
	if diff <= 6: return 3
	return 4

## Tabella casuale delle opzioni degli autonomi (8.4): colonne A, B, C, nessuna; righe dado 1..6.
const RIOT := [
	["A", "A", "A", "A"],
	["A", "B", "B", "A"],
	["A", "B", "B", "B"],
	["B", "B", "C", "B"],
	["B", "B", "C", "C"],
	["C", "C", "C", "C"],
]

## Fato (11.4): colonne punti sistema 0-9, 10-19 ... 90-99, 100+; righe dado 1..8.
## "L1" e "K2": servono 1 o 2 gettoni saggezza spesi; "" nessun effetto.
const FATO_ORIGINALE := [
	["", "", "A", "C", "E", "B", "D", "F", "A", "C", "E"],
	["", "", "", "A", "C", "E", "B", "D", "F", "A", "C"],
	["", "", "", "", "A", "C", "E", "B", "D", "F", "A"],
	["", "", "", "G", "H", "A", "C", "E", "B", "D", "F"],
	["", "", "G", "H", "J", "I", "A", "C", "E", "B", "D"],
	["", "", "H", "J", "I", "G", "J", "A", "C", "E", "L"],
	["", "H", "J", "I", "G", "J", "L1", "L1", "L1", "L1", "L1"],
	["H", "G", "I", "K2", "K2", "K2", "K2", "K2", "K2", "K2", "K2"],
]
const FATO_RIVISTO := [
	["", "", "A", "B", "C", "D", "E", "F", "F", "F", "F"],
	["", "", "", "A", "B", "C", "D", "E", "E", "E", "E"],
	["", "", "", "", "A", "B", "C", "D", "D", "D", "D"],
	["", "", "", "J", "J", "A", "B", "C", "C", "C", "C"],
	["", "", "J", "I", "I", "J", "A", "B", "B", "B", "B"],
	["", "", "I", "H", "H", "I", "I", "A", "A", "A", "L"],
	["", "H", "H", "G", "G", "H", "L1", "L1", "L1", "L1", "L1"],
	["H", "G", "G", "K2", "K2", "K2", "K2", "K2", "K2", "K2", "K2"],
]
## Fato alternativo (Gilham, Phoenix n. 11): solo dissoluzioni, colonne 0-19, 20-29 ... 90-99, 100+; dado 1..6.
const FATO_GILHAM := [
	["", "A", "C", "E", "B", "D", "F", "A", "C", "E"],
	["", "", "A", "C", "E", "B", "D", "F", "A", "C"],
	["", "", "", "A", "C", "E", "B", "D", "F", "A"],
	["", "", "", "", "A", "C", "E", "B", "D", "F"],
	["", "", "", "", "", "A", "C", "E", "B", "D"],
	["", "", "", "", "", "", "A", "C", "E", "B"],
]

static func col_fato(sp: int) -> int:
	return clampi(sp / 10, 0, 10)

static func col_fato_gilham(sp: int) -> int:
	if sp < 20:
		return 0
	return clampi(sp / 10 - 1, 1, 9)

## Percentuali della dissoluzione e calo di civiltà (11.2).
const DISSOLUZIONE := {"A": 10, "B": 30, "C": 50, "D": 70, "E": 80, "F": 90}
const CALO_CIVILTA := {"E": 1, "F": 1}
## Comparsa di una forza autonoma: [porte, flotte, livello di civiltà].
const AUTONOMI_FATO := {"G": [2, 5, 1], "H": [3, 7, 1], "I": [4, 9, 1], "J": [5, 12, 2]}

## Tabella di conversione delle percentuali (originale): righe per flotte 1-5, 6-10 ... 46-50;
## colonne 10, 15, 20, 30, 40, 45, 50, 60, 75, 80 %.
const CONV_PERC := [10, 15, 20, 30, 40, 45, 50, 60, 75, 80]
const CONV_ORIGINALE := [
	[1, 1, 1, 1, 1, 1, 1, 2, 3, 3],
	[1, 1, 2, 2, 3, 3, 3, 4, 5, 6],
	[1, 2, 3, 4, 5, 6, 6, 7, 9, 10],
	[2, 3, 3, 5, 7, 8, 9, 10, 12, 13],
	[2, 3, 5, 7, 9, 10, 11, 13, 16, 17],
	[3, 4, 6, 8, 11, 13, 14, 16, 20, 22],
	[3, 5, 7, 9, 13, 15, 17, 19, 24, 27],
	[4, 6, 8, 11, 15, 17, 19, 22, 28, 31],
	[4, 6, 9, 13, 17, 19, 21, 25, 32, 34],
	[5, 7, 10, 15, 19, 21, 24, 28, 36, 38],
]

## Flotte perse: n flotte, perc %. rivista = tabella riveduta (arrotonda per eccesso).
static func perdite(n: int, perc: int, rivista: bool) -> int:
	if n <= 0 or perc <= 0:
		return 0
	if perc >= 100:
		return n
	if rivista or n > 50:
		return mini(n, int(ceil(n * perc / 100.0)))
	var c = CONV_PERC.find(perc)
	if c < 0:
		# percentuale non in tabella: la più vicina per eccesso
		c = CONV_PERC.size() - 1
		for i in CONV_PERC.size():
			if CONV_PERC[i] >= perc:
				c = i
				break
	return mini(n, CONV_ORIGINALE[(n - 1) / 5][c])


## Costi delle flotte (14.23-14.25).
const COSTO := {"r": 3, "d": 8, "e": 5}
const NOME_FLOTTA := {"r": "regolare", "d": "corazzata", "e": "esploratrice"}
const NOME_FLOTTE := {"r": "regolari", "d": "corazzate", "e": "esploratrici"}

## Sistema del Fato alternativo (Gilham): punti civiltà richiesti per livello e raggio.
const GIL_LIVELLI := [250, 500, 1000, 2000, 4000, 8000, 16000, 32000]
const GIL_RAGGIO := [250, 700, 850, 1000, 1200, 1400, 1600, 1800, 2000, 2200, 2500, 2800, 3000, 3300, 3700, 4000, 4400, 4700, 5100, 5500, 6000, 6500, 7000, 7500, 8000]

static func gil_livello(cp: int) -> int:
	if cp < 250:
		return -1
	var l := 0
	for i in range(1, GIL_LIVELLI.size()):
		if cp >= GIL_LIVELLI[i]:
			l = i
	return l

static func gil_raggio(cp: int) -> int:
	var r := 0
	for i in GIL_RAGGIO.size():
		if cp >= GIL_RAGGIO[i]:
			r = i + 1
	if cp > 8000:
		r = 25 + (cp - 8000) / 600
	return r


# ---------------------------------------------------------------- fazioni e colori

const COLORI := ["blu", "giallo", "verde", "rosso"]
const COLORI_AUT := ["grigio", "blu", "verde", "giallo"]
const TINTE := [Color(0.42, 0.68, 0.88), Color(0.96, 0.78, 0.16), Color(0.55, 0.66, 0.26), Color(0.88, 0.2, 0.18)]
const TINTE_AUT := [Color(0.62, 0.62, 0.6), Color(0.3, 0.55, 0.75), Color(0.45, 0.55, 0.25), Color(0.85, 0.7, 0.2)]

## Tabella dei Venti Seme (18.51): riga = primo dado, colonna = secondo.
const VENTI_SEME := [
	["A", "H", "F", "G", "H", "K"],
	["G", "B", "I", "J", "L", "J"],
	["F", "K", "C", "M", "K", "I"],
	["E", "J", "A", "D", "C", "H"],
	["D", "B", "I", "D", "E", "G"],
	["C", "H", "G", "F", "E", "F"],
]
## Risultati (18.52): esagoni delle porte; true = vanno piazzate altre stelle faro.
const SEMI := {
	"A": [[707, 706, 607], true],
	"B": [[510, 409, 410], true],
	"C": [[814, 813, 714], false],
	"D": [[1709, 1708, 1609], false],
	"E": [[1110, 1111, 1209, 1210], false],
	"F": [[1314, 1313, 1213, 1214], false],
	"G": [[1215, 1115, 1116, 1216, 1316], false],
	"H": [[1118, 1117, 1017, 1018], false],
	"I": [[1816, 1815, 1916], false],
	"J": [[1324, 1323, 1423], false],
	"K": [[1726, 1625, 1826], false],
	"L": [[4903, 4802, 4803], true],
	"M": [[3827, 3728], true],
}


# ---------------------------------------------------------------- scenari

## Porte: [esagono, valore porta (-1 = nessuna porta), potenziale, "flotte"]
const SCENARI := {
	1: {
		"titolo": "Conflitto per Scorpii",
		"numero": "18.1",
		"giocatori": 2,
		"turni": 25,
		"intro": "Una civiltà che si estende per migliaia di anni luce e ha ancora fame di espansione finirà per uscire dal proprio braccio a spirale. Per tenere unite colonie sparse nella Galassia, e per svelare le ricchezze del Nucleo, il controllo di certi «crocevia» può diventare decisivo.",
		"vittoria": "Vittoria marginale: conservare tutte le proprie porte iniziali e avere una porta amica nell'esagono 1816 alla fine. Vittoria sostanziale: in più, conquistare e tenere almeno una porta iniziale dell'avversario. Durata: 25 turni.",
		"ignora": ["fari", "polvere", "nucleo", "dissoluzione", "fato_AF", "fato_KL"],
		"lati": [
			{"nome": "Cefeidi", "rp": 3, "cl": 1, "porte": [[1212, 5, 5, "1d"], [1213, 3, 4, "1r"], [1313, 3, 3, "1r"], [1314, 3, 4, "1r"], [1211, -1, 4, ""], [1312, -1, 5, "2e 1r"]]},
			{"nome": "Wezeniani", "rp": 5, "cl": 1, "porte": [[1118, 4, 4, "1r"], [1119, 3, 4, "1r"], [1018, 4, 5, "1r"], [1019, 1, 3, ""], [1117, 1, 4, ""], [918, -1, 2, "4e 1r"], [919, 0, 5, "1r"]]},
		],
	},
	2: {
		"titolo": "La via per il Nucleo",
		"numero": "18.2",
		"giocatori": 3,
		"turni": 50,
		"intro": "Nessuno sulla Terra sa con precisione che cosa si trovi nel Nucleo di stelle antiche e fitte al centro della Galassia. Ma se là c'è davvero qualcosa di prezioso, è probabile che chi lo conosce, o i suoi agenti, lo proteggano.",
		"vittoria": "Centauriani o Perseidi vincono costruendo e mantenendo per cinque turni consecutivi una catena di porte amiche, a non più di quattro esagoni l'una dall'altra, da una delle loro porte iniziali fino a un esagono adiacente al Nucleo Galattico: la partita finisce subito. I Guardiani vincono impedendolo per 50 turni.",
		"ignora_lato": {0: ["dissoluzione", "nucleo", "fato_AF", "fato_KL"], 1: ["nucleo", "fato_K"], 2: ["nucleo", "fato_K"]},
		"lati": [
			{"nome": "Guardiani", "rp": 12, "cl": 3, "guardiani": true, "porte": [[1118, 3, 3, "2d 5r 1e"], [1212, 4, 4, "2d 4r 1e"], [1215, 5, 5, "3d 7r 1e"], [1216, 4, 4, ""], [1314, 5, 5, ""], [1315, 3, 3, ""], [1316, 5, 5, ""], [1416, 0, 1, ""], [1709, 0, 4, ""], [1717, 4, 4, ""], [1815, 4, 4, ""], [1816, 3, 3, "2d 4r 1e"], [1924, 0, 2, ""], [2403, 0, 1, ""]]},
			{"nome": "Centauriani", "rp": 8, "cl": 1, "limite_corazzate": true, "porte": [[1124, 1, 2, ""], [1223, 1, 1, ""], [1224, 1, 2, ""], [1323, 3, 3, "1r"], [1324, 4, 5, "1r"], [1024, -1, 0, "2r 2e"], [1325, -1, 2, ""]]},
			{"nome": "Perseidi", "rp": 6, "cl": 1, "limite_corazzate": true, "porte": [[310, 4, 4, "1d 1r"], [410, 2, 2, "1r"], [510, 3, 3, "2e"], [511, 3, 3, ""], [513, 0, 0, "1d 1r"], [714, 2, 4, "1r"], [813, 2, 5, "2r"], [814, 1, 2, "2r"], [913, 1, 2, "3e 1r"], [713, -1, 0, "1e"]]},
		],
	},
	3: {
		"titolo": "Il Grande Salto della PSL",
		"numero": "18.3",
		"giocatori": 1,
		"turni": 25,
		"intro": "In StarForce, il primo gioco di fantascienza della SPI, la storia dell'umanità arrivava al primo contatto con telestetici non umani e alla nascita della Lega Pan-Senziente. L'intera mappa di quel gioco sta dentro l'esagono 1316. Qui la ritroviamo, discendente lontana e ingrandita diecimila volte, ancora dinamica e in crescita.",
		"vittoria": "Gioco in solitario: si vince portando il livello di civiltà della PSL a «due» alla fine della partita. Chi prende il gettone saggezza «X» scopre che il Nucleo è esploso e perde subito. Durata: 25 turni.",
		"x_perde": true,
		"lati": [
			{"nome": "Lega Pan-Senziente", "rp": 5, "cl": 1, "porte": [[1316, 4, 5, "1e 1r"], [1216, 2, 4, "1r"], [1215, 2, 4, ""]]},
		],
	},
	4: {
		"titolo": "Lotta per Cygnus-Carina",
		"numero": "18.4",
		"giocatori": 4,
		"turni": 50,
		"intro": "Quattro gruppi distinti di telestetici capaci di viaggiare nello spazio nascono vicini, nel braccio a spirale in cui si trova il Sole (esagono 1316).",
		"vittoria": "Si vince: tenendo per cinque turni consecutivi una porta amica in quattro di questi esagoni: 0814, 1118, 1212, 1215, 1314; oppure con un livello di civiltà maggiore della somma di quelli di tutti gli altri giocatori rimasti; oppure restando l'unico giocatore in gioco. Altrimenti, dopo 50 turni, vince chi ha il prodotto più alto fra punti sistema e livello di civiltà.",
		"pre_schieramento": true,
		"x_regola": "4",
		"lati": [
			{"nome": "Aurigani", "rp": 10, "cl": 1, "porte": [[814, 3, 3, ""], [813, 4, 5, ""]]},
			{"nome": "Rigeliani", "rp": 25, "cl": 1, "porte": [[1316, 4, 4, ""], [1216, 3, 5, ""], [1215, 2, 2, ""], [1315, 4, 4, ""]]},
			{"nome": "Wezeni", "rp": 19, "cl": 1, "porte": [[1118, 4, 4, ""], [1018, 3, 3, ""], [1119, 2, 5, ""]]},
			{"nome": "Regnad-Kcin", "rp": 11, "cl": 1, "porte": [[1312, 3, 4, ""], [1411, 2, 2, ""], [1412, 1, 2, ""]]},
		],
	},
	5: {
		"titolo": "La fortuna del sorteggio",
		"numero": "18.5",
		"giocatori": 0,
		"turni": 0,
		"intro": "Non è davvero uno scenario ma la situazione base di Outreach: ogni civiltà nasce dove la portano i Venti Seme, in un punto qualsiasi della Galassia.",
		"vittoria": "Si vince quando non restano porte non amiche sulla mappa, oppure quando il proprio livello di civiltà supera la somma dei livelli di tutti gli altri giocatori e delle forze autonome che hanno porte. Se tutti i giocatori rimasti tengono più di 100 punti sistema per dieci turni consecutivi è patta. In solitario si vince tenendo 100 punti sistema o più per cinque turni consecutivi, senza porte non amiche sulla mappa. Nessun limite di turni (si può fissarne uno nel menu).",
		"venti_seme": true,
		"pre_schieramento": true,
		"x_regola": "5",
		"lati": [],
	},
}

const NOMI_SEME := ["Popolo dei Venti Seme", "Figli della Polvere", "Erranti di Carina", "Telesteti di Orione"]

## "2d 5r 1e" -> {"r": 5, "d": 2, "e": 1}
static func flotte_da_testo(t: String) -> Dictionary:
	var out = {"r": 0, "d": 0, "e": 0}
	for p in t.split(" ", false):
		var k = p.substr(p.length() - 1)
		out[k] = out.get(k, 0) + int(p.substr(0, p.length() - 1))
	return out
