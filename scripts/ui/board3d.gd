extends SubViewportContainer
## Vista 3D della Galassia: la griglia di esagoni (o la mappa originale) sul piano, con sopra la
## galassia come una nuvola trasparente a due strati che si muove lentamente; pedine come
## gettoni in rilievo, porte con un anello di luce, stelle faro luminose.
## Trascinare col tasto destro (o con un dito) per ruotare, rotella per lo zoom, trascinare col
## sinistro per spostarsi, clic per scegliere un esagono.

const D = preload("res://scripts/data/od_data.gd")

signal hex_clicked(h: int)
signal hex_hovered(h: int)

var eng: ODEngine
var vista := -1
var tutto_visibile := false
var vp: SubViewport
var root3: Node3D
var cam: Camera3D
var pedine: Node3D
var effetti: Node3D
var nuvole: Array = []
var bersagli := {}
var selezionato := -1
var yaw := 0.0
var pitch := 0.95
var dist := 42.0
var target := Vector3(37, 0, 24)
var _drag := 0
var _from = Vector2.ZERO
var _press = Vector2.ZERO
var _moved := false
var t := 0.0
var nuvola := true
var _sel_mesh: MeshInstance3D
var _evid: Node3D
var _cache_mat := {}
var hover := -1


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.handle_input_locally = false
	add_child(vp)
	root3 = Node3D.new()
	vp.add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.012, 0.025)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.9
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.15
	env.environment = e
	root3.add_child(env)
	var sole := DirectionalLight3D.new()
	sole.rotation_degrees = Vector3(-55, 30, 0)
	sole.light_energy = 0.9
	root3.add_child(sole)
	cam = Camera3D.new()
	cam.fov = 45
	cam.far = 500
	root3.add_child(cam)
	_stelle_fondo()
	_piano()
	pedine = Node3D.new()
	root3.add_child(pedine)
	effetti = Node3D.new()
	root3.add_child(effetti)
	_evid = Node3D.new()
	root3.add_child(_evid)
	_camera()


func ricarica() -> void:
	for c in root3.get_children():
		if c.name.begins_with("Piano") or c.name.begins_with("Nuvola") or c.name.begins_with("Griglia"):
			root3.remove_child(c)
			c.queue_free()
	nuvole.clear()
	_piano()
	aggiorna()


## Posizione nel mondo del centro di un esagono.
func pos(h: int) -> Vector3:
	var p = D.centro(h)
	return Vector3(p.x, 0, p.y)


## Opacità degli strati (0..1), regolate dai cursori della schermata di gioco.
var opac_mappa := 1.0
var opac_griglia := 0.8
var _mat_mappa: StandardMaterial3D
var _mat_linee: StandardMaterial3D
var _quote_nuvole := []
var _nodo_piano: Node3D
var _nodo_griglia: Node3D


## Strati dal basso: nuvola sotto (due veli), mappa (originale, riveduta o Reborn), griglia con
## numeri, polvere e nomi delle stelle, nuvola sopra (due veli più leggeri). Le pedine stanno
## fra la mappa e la nuvola sopra e si vedono attraverso.
func _piano() -> void:
	# --- la mappa di fondo, con la sua geometria
	var tex: Texture2D = null
	if Grafica.stile == "reborn":
		if ResourceLoader.exists("res://assets/reborn/mappa.jpg"):
			tex = load("res://assets/reborn/mappa.jpg")
	else:
		tex = Grafica.mappa()
	if tex != null:
		var mi := MeshInstance3D.new()
		mi.name = "Piano"
		var pm := PlaneMesh.new()
		_mat_mappa = StandardMaterial3D.new()
		_mat_mappa.albedo_texture = tex
		_mat_mappa.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_mappa.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_mappa.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_mat_mappa.render_priority = -1
		_mat_mappa.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		pm.material = _mat_mappa
		var w := float(tex.get_width())
		var hh := float(tex.get_height())
		var a = Grafica.centro_px(101, w)
		var b = Grafica.centro_px(5101, w)
		var c = Grafica.centro_px(129, w)
		var sx = (D.centro(5101).x - D.centro(101).x) / (b.x - a.x)
		var sz = (D.centro(129).y - D.centro(101).y) / (c.y - a.y)
		pm.size = Vector2(w * sx, hh * sz)
		mi.mesh = pm
		mi.position = Vector3(-a.x * sx + w * sx / 2.0, 0, -a.y * sz + hh * sz / 2.0)
		root3.add_child(mi)
		_nodo_piano = mi
	else:
		_mat_mappa = null
		_nodo_piano = null
	# --- gli strati generati (stessa geometria): nuvole e griglia
	var size = Vector2(4045.0, 2712.0) / Grafica.GS
	var centro := Vector3(-Grafica.GMX + size.x / 2.0, 0, -Grafica.GMY + size.y / 2.0)
	var sotto: Texture2D = load("res://assets/board/nuvola_sotto.png")
	var sopra: Texture2D = load("res://assets/board/nuvola_sopra.png")
	var linee: Texture2D = load("res://assets/board/linee.png")
	# [texture, quota, alfa, priorità, nome]
	var strati = [[sotto, -2.6, 0.8, -3, "NuvolaS1"], [sotto, -1.1, 0.75, -2, "NuvolaS2"],
		[linee, 0.03, 1.0, 0, "Griglia"], [sopra, 1.5, 0.3, 1, "NuvolaA1"], [sopra, 3.0, 0.16, 2, "NuvolaA2"]]
	_quote_nuvole.clear()
	for st in strati:
		var n := MeshInstance3D.new()
		n.name = st[4]
		var q := PlaneMesh.new()
		q.size = size * (1.0 + absf(st[1]) * 0.012)
		var m2 := StandardMaterial3D.new()
		m2.albedo_texture = st[0]
		m2.albedo_color = Color(1, 1, 1, st[2])
		m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m2.cull_mode = BaseMaterial3D.CULL_DISABLED
		m2.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m2.render_priority = st[3]
		m2.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		q.material = m2
		n.mesh = q
		n.position = centro + Vector3(0, st[1], 0)
		root3.add_child(n)
		if st[4] == "Griglia":
			_mat_linee = m2
			_nodo_griglia = n
		else:
			n.visible = nuvola
			n.set_meta("alfa", st[2])
			nuvole.append(n)
			_quote_nuvole.append(st[1])
	set_opacita(opac_mappa, opac_griglia)


func set_opacita(mappa: float, griglia: float) -> void:
	opac_mappa = mappa
	opac_griglia = griglia
	if _mat_mappa != null:
		_mat_mappa.albedo_color = Color(1, 1, 1, mappa)
		_mat_mappa.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if mappa >= 0.999 else BaseMaterial3D.TRANSPARENCY_ALPHA
		if _nodo_piano != null:
			_nodo_piano.visible = mappa > 0.001
	if _mat_linee != null:
		_mat_linee.albedo_color = Color(1, 1, 1, griglia)
		if _nodo_griglia != null:
			_nodo_griglia.visible = griglia > 0.001


func _stelle_fondo() -> void:
	var g := RandomNumberGenerator.new()
	g.seed = 76
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	sm.radial_segments = 4
	sm.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	sm.material = mat
	mm.mesh = sm
	mm.instance_count = 700
	for i in 700:
		var d := Vector3(g.randf_range(-1, 1), g.randf_range(-0.2, 1), g.randf_range(-1, 1)).normalized() * g.randf_range(140, 220)
		var tr = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * g.randf_range(0.5, 2.0)), Vector3(37, -30, 24) + d)
		mm.set_instance_transform(i, tr)
		var b = g.randf_range(0.5, 1.0)
		mm.set_instance_color(i, Color(b, b * 0.95, b * 0.85))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	root3.add_child(mi)


func set_nuvola(v: bool) -> void:
	nuvola = v
	for n in nuvole:
		n.visible = v


func _camera() -> void:
	var off = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.position = target + off
	cam.look_at(target, Vector3.UP)


func centra_su(h: int) -> void:
	target = pos(h)
	dist = minf(dist, 22.0)
	_camera()


func _process(d: float) -> void:
	t += d
	# la nuvola respira e ruota lentamente attorno al Nucleo
	for i in nuvole.size():
		var n: MeshInstance3D = nuvole[i]
		var a = sin(t * 0.05 + i) * 0.015 * (i + 1)
		n.rotation.y = a
		n.position.y = float(_quote_nuvole[i]) + sin(t * 0.3 + i) * 0.12
	if _sel_mesh != null:
		_sel_mesh.rotation.y += d * 1.5
		_sel_mesh.scale = Vector3.ONE * (1.0 + 0.06 * sin(t * 5.0))
	_aggiorna_fili(d)
	_pulsa_fari()
	for c in pedine.get_children():
		if c.has_meta("gira"):
			c.rotation.y += d * float(c.get_meta("gira"))
	for c in effetti.get_children():
		if c.has_meta("filo"):
			continue
		if c.has_meta("vita"):
			var v: float = c.get_meta("vita") - d
			c.set_meta("vita", v)
			if c.has_meta("da"):
				var k = 1.0 - v / float(c.get_meta("durata"))
				var a2: Vector3 = c.get_meta("da")
				var b2: Vector3 = c.get_meta("a")
				c.position = a2.lerp(b2, clampf(k, 0, 1)) + Vector3(0, sin(k * PI) * 3.0, 0)
			else:
				c.scale = Vector3.ONE * (1.0 + (1.0 - v) * 2.0)
			if v <= 0:
				c.queue_free()


func _gui_input(ev: InputEvent) -> void:
	if _tocco(ev):
		accept_event()
		return
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		return
	if _tocchi.size() >= 2 and (ev is InputEventMouseMotion or ev is InputEventMouseButton):
		return
	if ev is InputEventMouseButton:
		var mb = ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			dist = maxf(6.0, dist / 1.12)
			_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			dist = minf(110.0, dist * 1.12)
			_camera()
		elif mb.pressed:
			_drag = mb.button_index
			_from = mb.position
			_press = mb.position
			_moved = false
		else:
			if mb.button_index == MOUSE_BUTTON_LEFT and not _moved:
				var h = _pick(mb.position)
				if h > 0:
					hex_clicked.emit(h)
			_drag = 0
	elif ev is InputEventMouseMotion:
		var mm = ev as InputEventMouseMotion
		if _drag != 0:
			if mm.position.distance_to(_press) > 6:
				_moved = true
			var dd = mm.position - _from
			_from = mm.position
			if _moved:
				if _drag == MOUSE_BUTTON_RIGHT or (_drag == MOUSE_BUTTON_LEFT and mm.shift_pressed):
					yaw -= dd.x * 0.006
					pitch = clampf(pitch + dd.y * 0.005, 0.25, 1.45)
				else:
					var f = dist * 0.0018
					var fw := Vector3(sin(yaw), 0, cos(yaw))
					var rt := Vector3(cos(yaw), 0, -sin(yaw))
					target -= rt * dd.x * f + fw * dd.y * f
				_camera()
		else:
			var h2 = _pick(mm.position)
			if h2 != hover:
				hover = h2
				hex_hovered.emit(h2)
	elif ev is InputEventMagnifyGesture:
		dist = clampf(dist / (ev as InputEventMagnifyGesture).factor, 6.0, 110.0)
		_camera()
	elif ev is InputEventPanGesture:
		yaw -= (ev as InputEventPanGesture).delta.x * 0.03
		pitch = clampf(pitch + (ev as InputEventPanGesture).delta.y * 0.02, 0.25, 1.45)
		_camera()


func _pick(p: Vector2) -> int:
	var sc = Vector2(vp.size) / size if size.x > 0 else Vector2.ONE
	var q = p * sc
	var o = cam.project_ray_origin(q)
	var dir = cam.project_ray_normal(q)
	if absf(dir.y) < 0.0001:
		return -1
	var k = -o.y / dir.y
	if k < 0:
		return -1
	var w = o + dir * k
	var h = D.da_punto(Vector2(w.x, w.z))
	return h if D.esiste(h) else -1


# ---------------------------------------------------------------- pedine

func _mat_tex(nome: String, scuro := false) -> StandardMaterial3D:
	var k = nome + (":s" if scuro else "") + ":" + Grafica.stile
	if _cache_mat.has(k):
		return _cache_mat[k]
	var m := StandardMaterial3D.new()
	m.albedo_texture = Grafica.tex(nome)
	if scuro:
		m.albedo_color = Color(0.35, 0.35, 0.35)
	m.roughness = 0.6
	_cache_mat[k] = m
	return m


func _gettone(nome: String, p: Vector3, lato: float, tinta: Color, scuro := false) -> Node3D:
	var n := Node3D.new()
	n.position = p
	var corpo := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(lato, 0.12, lato)
	var mc := StandardMaterial3D.new()
	mc.albedo_color = tinta.darkened(0.45)
	bm.material = mc
	corpo.mesh = bm
	corpo.position.y = 0.06
	n.add_child(corpo)
	var top := MeshInstance3D.new()
	var qm := PlaneMesh.new()
	qm.size = Vector2(lato, lato)
	qm.material = _mat_tex(nome, scuro)
	top.mesh = qm
	top.position.y = 0.125
	n.add_child(top)
	return n


func _testo(t3: String, p: Vector3, col := Color(1, 0.92, 0.7), sz := 48) -> Label3D:
	var l := Label3D.new()
	l.text = t3
	l.font = UI.font("numeri")
	l.font_size = sz
	l.pixel_size = 0.006
	l.modulate = col
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = p
	return l


func aggiorna() -> void:
	if pedine == null or eng == null:
		return
	for c in pedine.get_children():
		c.queue_free()
	# porte
	for h in eng.porte:
		var g: Dictionary = eng.porte[h]
		var o := int(g.get("prima", g["o"])) if g["neut"] else int(g["o"])
		var p = pos(h) + Vector3(-0.35, 0.02, -0.35)
		if usa_modelli and _scena_porta() != null:
			p = pos(h) + Vector3(0, 0.02, 0)
			pedine.add_child(_modello_porta(pos(h), g["neut"]))
		else:
			pedine.add_child(_gettone(Grafica.nome_porta(o), p, 0.75, Grafica.tinta(o), g["neut"]))
		if not g["neut"]:
			var anello := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.62
			tm.outer_radius = 0.7
			var ma := StandardMaterial3D.new()
			ma.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ma.albedo_color = Grafica.tinta(o)
			ma.emission_enabled = true
			ma.emission = Grafica.tinta(o)
			ma.emission_energy_multiplier = 1.5
			tm.material = ma
			anello.mesh = tm
			anello.position = pos(h) + Vector3(0, 0.05, 0)
			pedine.add_child(anello)
			if _vede(o):
				pedine.add_child(_testo(str(g["sp"]), p + Vector3(0.3, 1.0 if usa_modelli else 0.5, 0)))
		else:
			pedine.add_child(_testo("N", p + Vector3(0, 1.0 if usa_modelli else 0.5, 0), UI.ROSSO))
	# flotte: una pila per proprietario, alta quanto le flotte
	for h in eng.flotte:
		var i := 0
		for o in eng.proprietari(h):
			var st: Dictionary = eng.stack(h, o)
			var tot := int(st["r"]) + int(st["d"]) + int(st["e"])
			var base = pos(h) + Vector3(0.3 + i * 0.25, 0.02, 0.15 + i * 0.25)
			var strati = clampi(tot, 1, 6) if _vede(o) else 1
			if usa_modelli and _scena_nave() != null:
				base = pos(h) + Vector3(0.45 - i * 0.42, 0.02, 0.45 + i * 0.12)
				var navi := 1
				if _vede(o):
					navi = 1 if tot <= 2 else (2 if tot <= 7 else 3)
				pedine.add_child(_modello_flotta(base, Grafica.tinta(o), navi))
				if _vede(o):
					pedine.add_child(_testo("%d" % tot, base + Vector3(0.25, 1.0, 0)))
				i += 1
				continue
			for k in strati:
				var n2 = _gettone(Grafica.nome_flotta(o), base + Vector3(0, k * 0.13, 0), 0.7, Grafica.tinta(o))
				pedine.add_child(n2)
			if _vede(o):
				pedine.add_child(_testo("%d" % tot, base + Vector3(0.35, 0.35 + strati * 0.13, 0)))
			i += 1
	# contatto, saggezza, fari
	for h in eng.contatti:
		var ps: Array = eng.proprietari(h).filter(func(x): return x < 10)
		var o2: int = ps[0] if not ps.is_empty() else 0
		pedine.add_child(_gettone(Grafica.nome_contatto(o2), pos(h) + Vector3(-0.45, 0.02, 0.4), 0.5, Grafica.tinta(o2)))
	for h in eng.sag_centro:
		pedine.add_child(_gettone("saggezza", pos(h) + Vector3(0.4, 0.02, 0.4), 0.5, Color(0.3, 0.3, 0.3)))
	for h in eng.fari:
		pedine.add_child(_stella_faro(h))
	for h in eng.pv:
		if eng.porte.has(h):
			continue
		var v = eng.valore_pv(h) if tutto_visibile else (eng.pv_noto(h, vista) if vista >= 0 else -1)
		var gp = _gettone("pv", pos(h) + Vector3(0.45, 0.02, -0.45), 0.4, Color(0.6, 0.62, 0.6))
		pedine.add_child(gp)
		pedine.add_child(_testo(str(v) if v >= 0 else "?", pos(h) + Vector3(0.45, 0.35, -0.45), Color(0.9, 0.9, 0.9), 36))
	_evidenzia()


func _vede(o: int) -> bool:
	if tutto_visibile or vista < 0 or o == vista:
		return true
	if o >= 10:
		return int(eng.aut[o - 10]["custode"]) == vista
	return false


func _evidenzia() -> void:
	for c in _evid.get_children():
		c.queue_free()
	_sel_mesh = null
	for h in bersagli:
		_evid.add_child(_anello(pos(h), bersagli[h], 0.85, 0.95))
	if selezionato > 0:
		_sel_mesh = _anello(pos(selezionato), UI.AMBRA, 0.9, 1.05)
		_evid.add_child(_sel_mesh)


func _anello(p: Vector3, col: Color, r1: float, r2: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r1
	tm.outer_radius = r2
	tm.rings = 6
	tm.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	tm.material = m
	mi.mesh = tm
	mi.position = p + Vector3(0, 0.04, 0)
	return mi


func set_evidenziati(b: Dictionary, sel: int) -> void:
	bersagli = b
	selezionato = sel
	_evidenzia()


func effetto(kind: String, data: Dictionary) -> void:
	match kind:
		"salto", "disperso":
			var da := int(data["da"])
			var a := int(data["a"])
			var fine := int(data.get("h", a))
			var col = Grafica.tinta(int(data["o"])) if int(data["o"]) >= 0 else Color.WHITE
			if kind == "salto":
				_filo(pos(da), pos(a), col, false)
			else:
				# il filo punta alla destinazione voluta, poi si spezza e finisce dove la forza è dispersa
				_filo(pos(da), pos(a), col, true, pos(fine))
		"attacco", "neutralizza", "contatto", "esplora", "porta", "autonomi":
			var col2: Color = {"attacco": Color(1, 0.45, 0.15), "neutralizza": Color(0.7, 0.8, 1.0), "contatto": UI.AMBRA, "esplora": Color(0.5, 0.9, 1.0)}.get(kind, Color(1, 1, 1))
			if data.has("o"):
				col2 = Grafica.tinta(int(data["o"])) if kind in ["porta", "autonomi"] else col2
			var a = _anello(pos(int(data["h"])), col2, 0.4, 0.6)
			a.set_meta("vita", 1.0)
			effetti.add_child(a)


# ---------------------------------------------------------------- balzi: fili d'argento

const DURATA_VOLO := 1.3
const DURATA_CODA := 0.9
var _fili: Array = []
var _mat_filo: StandardMaterial3D


func _materiale_filo() -> StandardMaterial3D:
	if _mat_filo == null:
		_mat_filo = StandardMaterial3D.new()
		_mat_filo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_filo.vertex_color_use_as_albedo = true
		_mat_filo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_filo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat_filo.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_filo.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_mat_filo.render_priority = 3
	return _mat_filo


## Un balzo: una parabola d'argento da a verso b. La testa corre lungo l'arco, la coda svanisce
## mano a mano. Se disperso, alla fine l'arco devia verso l'esagono in cui la forza è finita.
func _filo(a: Vector3, b: Vector3, tinta: Color, disperso := false, fine := Vector3.ZERO) -> void:
	var punti := []
	var lun = a.distance_to(b)
	var alt := clampf(1.2 + lun * 0.28, 1.4, 9.0)
	var n := 48
	for i in n + 1:
		var k = float(i) / n
		punti.append(a.lerp(b, k) + Vector3(0, 0.35 + sin(k * PI) * alt, 0))
	if disperso:
		var c = b + Vector3(0, 0.35, 0)
		var f = fine + Vector3(0, 0.35, 0)
		for i in range(1, 13):
			var k2 = float(i) / 12
			punti.append(c.lerp(f, k2) + Vector3(0, sin(k2 * PI) * 0.8, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.set_meta("filo", true)
	effetti.add_child(mi)
	var testa := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	sm.radial_segments = 8
	sm.rings = 4
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.albedo_color = Color(1, 1, 1)
	mt.emission_enabled = true
	mt.emission = Color(0.95, 0.97, 1.0)
	mt.emission_energy_multiplier = 5.0
	sm.material = mt
	testa.mesh = sm
	testa.set_meta("filo", true)
	effetti.add_child(testa)
	# argento con un riflesso del colore del giocatore (rosso se disperso)
	var argento := Color(0.82, 0.86, 0.95).lerp(tinta, 0.25)
	_fili.append({"mesh": mi, "testa": testa, "punti": punti, "t": 0.0, "col": argento, "disperso": disperso, "n_arco": n})


func _aggiorna_fili(d: float) -> void:
	if _fili.is_empty():
		return
	# con fotogrammi lenti l'animazione rallenta invece di saltare
	d = minf(d, 1.0 / 30.0)
	var vista = cam.global_position
	for f in _fili.duplicate():
		f["t"] = float(f["t"]) + d
		var t3: float = f["t"]
		var punti: Array = f["punti"]
		var tot = punti.size() - 1
		var testa_k := clampf(t3 / DURATA_VOLO, 0.0, 1.0)
		var testa_i = testa_k * tot
		var svanisce = maxf(0.0, t3 - DURATA_VOLO) / DURATA_CODA
		if svanisce >= 1.0:
			f["mesh"].queue_free()
			f["testa"].queue_free()
			_fili.erase(f)
			continue
		# coda: dal punto più vecchio ancora visibile alla testa; si accorcia e sbiadisce
		var lung_coda = tot * 0.55
		var coda_i := maxf(0.0, testa_i - lung_coda + svanisce * lung_coda)
		if svanisce > 0:
			coda_i = minf(testa_i, tot * svanisce)
		var im: ImmediateMesh = f["mesh"].mesh
		im.clear_surfaces()
		var i0 := int(floor(coda_i))
		var i1 := int(ceil(testa_i))
		if i1 - i0 >= 1:
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _materiale_filo())
			for i in range(i0, i1 + 1):
				var p: Vector3 = punti[clampi(i, 0, tot)]
				var q: Vector3 = punti[clampi(i + 1, 0, tot)] if i < tot else punti[tot] + (punti[tot] - punti[tot - 1])
				var tang = (q - p).normalized()
				var verso = (vista - p).normalized()
				var lato = tang.cross(verso).normalized()
				# 0 in coda, 1 in testa
				var u = (float(i) - coda_i) / maxf(0.001, testa_i - coda_i)
				u = clampf(u, 0.0, 1.0)
				var alfa = u * u * (1.0 - svanisce)
				var col: Color = f["col"]
				if f["disperso"] and i > int(f["n_arco"]):
					col = Color(1.0, 0.35, 0.25)
				var largo = 0.03 + 0.07 * u
				im.surface_set_color(Color(col, alfa))
				im.surface_add_vertex(p + lato * largo)
				im.surface_set_color(Color(col, alfa))
				im.surface_add_vertex(p - lato * largo)
			im.surface_end()
		var hp: Vector3 = punti[clampi(int(round(testa_i)), 0, tot)]
		f["testa"].position = hp
		f["testa"].visible = svanisce < 0.3
		f["testa"].scale = Vector3.ONE * (1.0 + 0.25 * sin(t3 * 18.0))


# ---------------------------------------------------------------- stelle faro in 3D

static var _tex_stella: ImageTexture
var _fari_nodi: Array = []


static func _texture_stella() -> ImageTexture:
	if _tex_stella != null:
		return _tex_stella
	var n := 128
	var img = Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c = n / 2.0
	for y in n:
		for x in n:
			var dx = (x - c + 0.5) / c
			var dy = (y - c + 0.5) / c
			var r := sqrt(dx * dx + dy * dy)
			# nucleo, alone e quattro raggi sottili
			var nucleo = exp(-r * r * 60.0)
			var alone = exp(-r * r * 6.0) * 0.45
			var raggi = (exp(-absf(dx) * 40.0) * exp(-absf(dy) * 2.2) + exp(-absf(dy) * 40.0) * exp(-absf(dx) * 2.2)) * 0.8
			var v := clampf(nucleo + alone + raggi, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, v))
	_tex_stella = ImageTexture.create_from_image(img)
	return _tex_stella


func _stella_faro(h: int) -> Node3D:
	var n := Node3D.new()
	var stampata = D.faro_stampato(h) != ""
	var col := Color(1.0, 0.72, 0.5) if stampata else Color(0.7, 0.85, 1.0)
	n.position = pos(h) + Vector3(0, 0.75, 0.25)
	# il corpo: una piccola sfera incandescente
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	var mc := StandardMaterial3D.new()
	mc.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mc.albedo_color = Color(1, 1, 1)
	mc.emission_enabled = true
	mc.emission = col
	mc.emission_energy_multiplier = 6.0
	sm.material = mc
	core.mesh = sm
	n.add_child(core)
	# i raggi: due stelle a croce rivolte alla telecamera, una ruota piano, l'altra pulsa
	for k in 2:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.6, 1.6) if k == 0 else Vector2(1.1, 1.1)
		var mq := StandardMaterial3D.new()
		mq.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mq.albedo_texture = _texture_stella()
		mq.albedo_color = col if k == 0 else Color(1, 1, 1, 0.8)
		mq.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mq.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mq.cull_mode = BaseMaterial3D.CULL_DISABLED
		mq.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mq.render_priority = 4
		qm.material = mq
		q.mesh = qm
		q.set_meta("fase", float((h * 37) % 100) / 100.0 * TAU)
		q.set_meta("tipo", k)
		n.add_child(q)
	_fari_nodi.append(n)
	return n


func _pulsa_fari() -> void:
	var vivi := []
	for n in _fari_nodi:
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		vivi.append(n)
		for q in n.get_children():
			if not q.has_meta("fase"):
				continue
			var fase: float = q.get_meta("fase")
			var ang := 0.0
			var sc := 1.0
			if int(q.get_meta("tipo")) == 0:
				ang = t * 0.35 + fase
				sc = 0.85 + 0.2 * sin(t * 1.7 + fase)
			else:
				ang = -t * 0.6 + fase + PI / 4.0
				sc = 0.6 + 0.45 * pow(0.5 + 0.5 * sin(t * 2.6 + fase), 3.0)
			# rivolta alla telecamera e ruotata attorno alla linea di vista
			var dir: Vector3 = (cam.global_position - n.global_position).normalized()
			var b = Basis.looking_at(-dir, cam.global_transform.basis.y)
			b = b.rotated(dir, ang)
			q.global_transform = Transform3D(b.scaled(Vector3.ONE * sc), n.global_position)
	_fari_nodi = vivi


# ---------------------------------------------------------------- tocco (iPad)
## Un dito trascina (arriva come mouse emulato); due dita: pizzico per lo zoom, girare le dita per ruotare,
## spostarle insieme in su o in giù per inclinare la vista.
var _tocchi := {}
var _t_dist := 0.0
var _t_centro = Vector2.ZERO
var _t_ang := 0.0


func _tocco(ev: InputEvent) -> bool:
	if ev is InputEventScreenTouch:
		var st = ev as InputEventScreenTouch
		if st.pressed:
			_tocchi[st.index] = st.position
		else:
			_tocchi.erase(st.index)
		if _tocchi.size() >= 2:
			_t_init()
		return _tocchi.size() >= 2
	if ev is InputEventScreenDrag:
		var sd = ev as InputEventScreenDrag
		_tocchi[sd.index] = sd.position
		if _tocchi.size() >= 2:
			var k: Array = _tocchi.keys()
			var a: Vector2 = _tocchi[k[0]]
			var b: Vector2 = _tocchi[k[1]]
			var d := maxf(1.0, a.distance_to(b))
			var c = (a + b) / 2.0
			var ang = (b - a).angle()
			_due_dita(d / maxf(1.0, _t_dist), c, c - _t_centro, wrapf(ang - _t_ang, -PI, PI))
			_t_dist = d
			_t_centro = c
			_t_ang = ang
			return true
	return false


func _t_init() -> void:
	var k: Array = _tocchi.keys()
	var a: Vector2 = _tocchi[k[0]]
	var b: Vector2 = _tocchi[k[1]]
	_t_dist = maxf(1.0, a.distance_to(b))
	_t_centro = (a + b) / 2.0
	_t_ang = (b - a).angle()
	_drag = 0
	_moved = true


func _due_dita(fattore: float, _centro: Vector2, sposta: Vector2, rot: float) -> void:
	dist = clampf(dist / fattore, 6.0, 110.0)
	yaw -= rot
	pitch = clampf(pitch + sposta.y * 0.006, 0.25, 1.45)
	_camera()


# ---------------------------------------------------------------- modelli 3D di porte e flotte

## In 3D le porte sono la stazione StarGate e le flotte le Teleship (assets/models); il colore
## del proprietario è nell'anello luminoso alla base. Se i modelli mancano si usano i gettoni.
var usa_modelli := true
static var _sc_porta: PackedScene
static var _sc_nave: PackedScene


static func _scena_porta() -> PackedScene:
	if _sc_porta == null and ResourceLoader.exists("res://assets/models/stargate.glb"):
		_sc_porta = load("res://assets/models/stargate.glb")
	return _sc_porta


static func _scena_nave() -> PackedScene:
	if _sc_nave == null and ResourceLoader.exists("res://assets/models/teleship.glb"):
		_sc_nave = load("res://assets/models/teleship.glb")
	return _sc_nave


func _spegni(n: Node) -> void:
	# porta neutralizzata: il modello diventa scuro e trasparente
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).transparency = 0.6
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.25, 0.25, 0.3, 0.5)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			(c as GeometryInstance3D).material_override = m
		_spegni(c)


func _modello_porta(p: Vector3, neut: bool) -> Node3D:
	var n := Node3D.new()
	n.position = p
	var m: Node3D = _scena_porta().instantiate()
	m.scale = Vector3.ONE * 0.5
	m.position.y = 0.43
	n.add_child(m)
	if neut:
		_spegni(m)
	else:
		n.set_meta("gira", 0.12)
	return n


func _modello_flotta(p: Vector3, tinta: Color, navi: int) -> Node3D:
	var n := Node3D.new()
	n.position = p
	# base colorata del proprietario
	var disco := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.26
	var ma := StandardMaterial3D.new()
	ma.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ma.albedo_color = tinta
	ma.emission_enabled = true
	ma.emission = tinta
	ma.emission_energy_multiplier = 1.8
	tm.material = ma
	disco.mesh = tm
	disco.position.y = 0.03
	n.add_child(disco)
	var posti = [Vector3.ZERO]
	if navi == 2:
		posti = [Vector3(-0.12, 0, 0), Vector3(0.12, 0, 0.05)]
	elif navi >= 3:
		posti = [Vector3(0, 0, -0.12), Vector3(-0.12, 0, 0.08), Vector3(0.12, 0, 0.08)]
	var sc = 0.34 if navi == 1 else 0.26
	for q in posti:
		var nave: Node3D = _scena_nave().instantiate()
		nave.scale = Vector3.ONE * sc
		nave.position = q + Vector3(0, 0.95 * sc + 0.05, 0)
		n.add_child(nave)
	n.set_meta("gira", 0.35)
	return n
