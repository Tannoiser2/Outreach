extends Control
## Il regolamento in italiano (assets/regole.md), a tutta larghezza, e le tabelle.

var main


static func md_bb(t: String) -> String:
	var out := []
	for ln in t.split("\n"):
		var l = ln
		if l.begins_with("### "):
			l = "[font_size=20][color=#dcae38][b]%s[/b][/color][/font_size]" % l.substr(4)
		elif l.begins_with("## "):
			l = "\n[font_size=25][color=#f2a83a][b]%s[/b][/color][/font_size]" % l.substr(3)
		elif l.begins_with("# "):
			l = "[font_size=34][color=#f2a83a]%s[/color][/font_size]" % l.substr(2)
		elif l.begins_with("- "):
			l = "  •  " + l.substr(2)
		elif l.begins_with("> "):
			l = "[i][color=#b8b8b0]%s[/color][/i]" % l.substr(2)
		# grassetto e corsivo
		var re := RegEx.new()
		re.compile("\\*\\*(.+?)\\*\\*")
		l = re.sub(l, "[b]$1[/b]", true)
		var re2 := RegEx.new()
		re2.compile("(?<![\\w*])\\*(?!\\s)(.+?)\\*(?!\\w)")
		l = re2.sub(l, "[i]$1[/i]", true)
		out.append(l)
	return "\n".join(out)


static func testo_regole() -> RichTextLabel:
	var f = FileAccess.open("res://assets/regole.md", FileAccess.READ)
	var t = f.get_as_text() if f != null else "Regolamento non trovato."
	var r = UI.rich(md_bb(t), 18)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.custom_minimum_size = Vector2(1200, 0)
	return r


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 40
	p.offset_top = 30
	p.offset_right = -40
	p.offset_bottom = -30
	add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	var h := HBoxContainer.new()
	var t = UI.titolo("Regole di Outreach", 32)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(UI.bottone("Torna al menu", func(): main.show_menu()))
	v.add_child(h)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	var s1 := ScrollContainer.new()
	s1.name = "Regolamento"
	s1.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var r = testo_regole()
	s1.add_child(r)
	tabs.add_child(s1)
	var s2 := ScrollContainer.new()
	s2.name = "Tabelle"
	s2.add_child(preload("res://scripts/ui/tabelle_view.gd").crea(null))
	tabs.add_child(s2)
	var s3 := ScrollContainer.new()
	s3.name = "Plancia"
	var tr := TextureRect.new()
	tr.texture = load("res://assets/misc/plancia.jpg")
	s3.add_child(tr)
	tabs.add_child(s3)
