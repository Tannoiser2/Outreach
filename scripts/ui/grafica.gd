class_name Grafica
extends RefCounted
## Immagini del gioco nelle due grafiche: «originale» (pedine del modulo TTS e mappa SPI) e
## «reborn» (le immagini nuove in assets/reborn/, con lo stesso nome; se una manca si usa l'originale).

const D = preload("res://scripts/data/od_data.gd")

static var stile := "originale"
static var _cache := {}

static func tex(nome: String) -> Texture2D:
	var k = stile + ":" + nome
	if _cache.has(k):
		return _cache[k]
	var t: Texture2D = null
	if stile == "reborn":
		for ext in [".png", ".jpg", ".webp"]:
			var p = "res://assets/reborn/" + nome + ext
			if ResourceLoader.exists(p):
				t = load(p)
				break
	if t == null:
		for ext in [".png", ".jpg"]:
			var p2 = "res://assets/counters/" + nome + ext
			if ResourceLoader.exists(p2):
				t = load(p2)
				break
	_cache[k] = t
	return t


static func reborn_disponibile() -> bool:
	return ResourceLoader.exists("res://assets/reborn/blu_flotta.png") or ResourceLoader.exists("res://assets/reborn/mappa.jpg")


## Nome dell'immagine della flotta / porta di un proprietario.
static func nome_flotta(o: int) -> String:
	if o >= 10:
		return "aut_%s_flotta" % D.COLORI_AUT[o - 10]
	return "%s_flotta" % D.COLORI[o]


static func nome_porta(o: int) -> String:
	if o >= 10:
		return "aut_%s_porta" % D.COLORI_AUT[o - 10]
	return "%s_porta" % D.COLORI[o]


static func nome_contatto(o: int) -> String:
	return "%s_contatto" % D.COLORI[clampi(o, 0, 3)]


static func tinta(o: int) -> Color:
	if o >= 10:
		return D.TINTE_AUT[o - 10]
	if o < 0:
		return Color(0.5, 0.5, 0.5)
	return D.TINTE[o]


## Mappa di fondo: originale (scansione SPI) o reborn (griglia con la galassia).
static func mappa() -> Texture2D:
	var k = stile + ":mappa"
	if _cache.has(k):
		return _cache[k]
	var t: Texture2D = null
	if stile == "reborn":
		if ResourceLoader.exists("res://assets/reborn/mappa.jpg"):
			t = load("res://assets/reborn/mappa.jpg")
		else:
			t = load("res://assets/board/griglia.jpg")
	elif stile == "riveduta":
		t = load("res://assets/board/mappa_riveduta.jpg")
	else:
		t = load("res://assets/board/mappa.jpg")
	_cache[k] = t
	return t


## Geometria della mappa di fondo: [x della colonna 7, y della riga 1, passo colonne, passo righe, larghezza di riferimento].
static func geom() -> Array:
	if stile == "riveduta":
		return [430.0, 56.0, 62.0, 72.5, 3220.0]
	return [OX, OY, OPX, OPY, 10000.0]


static func usa_griglia() -> bool:
	return stile == "reborn" and not ResourceLoader.exists("res://assets/reborn/mappa.jpg")


## Geometria della mappa originale (pixel dell'immagine larga 10000).
const OX := 1343.0
const OY := 153.0
const OPX := 192.2
const OPY := 223.1
## Geometria della griglia generata (unità esagono -> pixel).
const GS := 52.0
const GMX := 1.4
const GMY := 1.4

## Centro di un esagono in pixel della texture di fondo.
static func centro_px(h: int, tex_w: float) -> Vector2:
	var c = D.col(h)
	var r = D.row(h)
	if usa_griglia():
		var p = D.centro(h)
		return Vector2((p.x + GMX) * GS, (p.y + GMY) * GS) * (tex_w / 4045.0)
	var g = geom()
	var k = tex_w / float(g[4])
	var x = g[0] + (c - 7) * g[2]
	var y = g[1] + (r - 1) * g[3] + (0.0 if c % 2 == 1 else g[3] / 2.0)
	return Vector2(x, y) * k


## Raggio di un esagono in pixel della texture.
static func raggio_px(tex_w: float) -> float:
	if usa_griglia():
		return GS * (tex_w / 4045.0)
	var g = geom()
	return g[2] / 1.5 * (tex_w / float(g[4]))
