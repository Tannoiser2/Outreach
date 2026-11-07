class_name UI
extends RefCounted
## Tema grafico: lo spazio nero e l'ambra del logo SPI del 1976, i titoli tondi anni Settanta
## (Righteous), le intestazioni con le grazie delle tabelle originali (Old Standard), testi in
## Space Grotesk e numeri in Share Tech Mono.

const SPAZIO := Color(0.035, 0.04, 0.07)
const PANNELLO := Color(0.07, 0.08, 0.12, 0.94)
const PANNELLO2 := Color(0.1, 0.11, 0.17, 0.96)
const AMBRA := Color(0.95, 0.66, 0.2)
const ORO := Color(0.86, 0.68, 0.22)
const ROSSO := Color(0.88, 0.3, 0.2)
const CIANO := Color(0.36, 0.67, 0.8)
const TESTO := Color(0.9, 0.89, 0.84)
const TENUE := Color(0.62, 0.62, 0.6)
const VERDE := Color(0.45, 0.78, 0.4)

static var _fonts := {}

static func font(nome: String) -> Font:
	if _fonts.has(nome):
		return _fonts[nome]
	var path := ""
	match nome:
		"titolo":
			path = "res://assets/fonts/Righteous-Regular.ttf"
		"intestazione":
			path = "res://assets/fonts/OldStandard-Bold.ttf"
		"serif":
			path = "res://assets/fonts/OldStandard-Regular.ttf"
		"numeri":
			path = "res://assets/fonts/ShareTechMono-Regular.ttf"
		_:
			path = "res://assets/fonts/SpaceGrotesk.ttf"
	var f: Font = load(path)
	if nome == "testo_grassetto":
		var v := FontVariation.new()
		v.base_font = f
		v.variation_opentype = {"wght": 650}
		_fonts[nome] = v
		return v
	_fonts[nome] = f
	return f


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("testo")
	t.default_font_size = 17
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.2)
	sb.border_color = Color(AMBRA, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.2, 0.17, 0.12)
	sbh.border_color = AMBRA
	var sbp := sb.duplicate()
	sbp.bg_color = Color(0.32, 0.22, 0.08)
	var sbd := sb.duplicate()
	sbd.bg_color = Color(0.08, 0.08, 0.1)
	sbd.border_color = Color(0.3, 0.3, 0.3)
	for c in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", c, sb)
		t.set_stylebox("hover", c, sbh)
		t.set_stylebox("pressed", c, sbp)
		t.set_stylebox("disabled", c, sbd)
		t.set_stylebox("focus", c, StyleBoxEmpty.new())
		t.set_color("font_color", c, TESTO)
		t.set_color("font_hover_color", c, AMBRA)
		t.set_color("font_pressed_color", c, Color(1, 0.85, 0.5))
		t.set_color("font_disabled_color", c, Color(0.45, 0.45, 0.45))
	t.set_color("font_color", "Label", TESTO)
	t.set_color("default_color", "RichTextLabel", TESTO)
	var pan := StyleBoxFlat.new()
	pan.bg_color = PANNELLO
	pan.border_color = Color(AMBRA, 0.35)
	pan.set_border_width_all(1)
	pan.set_corner_radius_all(4)
	pan.content_margin_left = 12
	pan.content_margin_right = 12
	pan.content_margin_top = 10
	pan.content_margin_bottom = 10
	t.set_stylebox("panel", "PanelContainer", pan)
	t.set_stylebox("panel", "Panel", pan)
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.05, 0.05, 0.08)
	le.border_color = Color(AMBRA, 0.45)
	le.set_border_width_all(1)
	le.content_margin_left = 8
	le.content_margin_right = 8
	le.content_margin_top = 4
	le.content_margin_bottom = 4
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le)
	t.set_stylebox("normal", "SpinBox", le)
	t.set_color("font_color", "LineEdit", TESTO)
	t.set_font("normal_font", "RichTextLabel", font("testo"))
	t.set_font("bold_font", "RichTextLabel", font("testo_grassetto"))
	t.set_font("italics_font", "RichTextLabel", font("serif"))
	t.set_font("mono_font", "RichTextLabel", font("numeri"))
	var sl := StyleBoxFlat.new()
	sl.bg_color = Color(0.2, 0.2, 0.25)
	sl.content_margin_top = 3
	sl.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", sl)
	var tab := StyleBoxFlat.new()
	tab.bg_color = Color(0.1, 0.1, 0.15)
	tab.content_margin_left = 10
	tab.content_margin_right = 10
	tab.content_margin_top = 4
	tab.content_margin_bottom = 4
	var tabs := tab.duplicate()
	tabs.bg_color = Color(0.25, 0.18, 0.08)
	t.set_stylebox("tab_unselected", "TabBar", tab)
	t.set_stylebox("tab_selected", "TabBar", tabs)
	t.set_stylebox("tab_hovered", "TabBar", tabs)
	t.set_stylebox("tab_unselected", "TabContainer", tab)
	t.set_stylebox("tab_selected", "TabContainer", tabs)
	t.set_stylebox("tab_hovered", "TabContainer", tabs)
	t.set_stylebox("panel", "TabContainer", pan)
	var tt := StyleBoxFlat.new()
	tt.bg_color = Color(0.06, 0.06, 0.09, 0.97)
	tt.border_color = AMBRA
	tt.set_border_width_all(1)
	tt.content_margin_left = 8
	tt.content_margin_right = 8
	tt.content_margin_top = 5
	tt.content_margin_bottom = 5
	t.set_stylebox("panel", "TooltipPanel", tt)
	t.set_color("font_color", "TooltipLabel", TESTO)
	return t


static func label(testo: String, size := 17, col := TESTO, fnt := "testo") -> Label:
	var l := Label.new()
	l.text = testo
	l.add_theme_font_override("font", font(fnt))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


static func titolo(testo: String, size := 30) -> Label:
	return label(testo, size, AMBRA, "titolo")


static func intestazione(testo: String, size := 20) -> Label:
	return label(testo, size, ORO, "intestazione")


static func bottone(testo: String, cb: Callable, size := 17) -> Button:
	var b := Button.new()
	b.text = testo
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	return b


static func rich(bb := "", size := 16) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.add_theme_font_size_override("mono_font_size", size)
	r.text = bb
	return r


static func sep() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 10)
	return s


## Cielo stellato sullo sfondo dei menu.
class Starfield:
	extends Control
	var stelle := []
	var t := 0.0

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g := RandomNumberGenerator.new()
		g.seed = 3000
		for i in 420:
			stelle.append([Vector2(g.randf(), g.randf()), g.randf_range(0.4, 1.9), g.randf(), g.randf_range(0.2, 1.0)])

	func _process(d: float) -> void:
		t += d
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), SPAZIO)
		# una lieve nebulosa a spirale
		var c := size * Vector2(0.72, 0.42)
		for i in 60:
			var a := i * 0.35 + t * 0.01
			var r := 20.0 + i * 9.0
			var p := c + Vector2(cos(a), sin(a) * 0.55) * r
			draw_circle(p, 60.0 + i * 1.5, Color(0.55, 0.32, 0.18, 0.012))
			var p2 := c + Vector2(cos(a + PI), sin(a + PI) * 0.55) * r
			draw_circle(p2, 60.0 + i * 1.5, Color(0.25, 0.35, 0.55, 0.012))
		draw_circle(c, 90.0, Color(0.95, 0.6, 0.3, 0.05))
		for s in stelle:
			var p3: Vector2 = s[0] * size
			var b: float = 0.55 + 0.45 * sin(t * s[3] * 2.0 + s[2] * 10.0)
			draw_circle(p3, s[1], Color(0.95, 0.92, 0.85, b * 0.85))
