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
var _from := Vector2.ZERO
var _press := Vector2.ZERO
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
		if c.name.begins_with("Piano") or c.name.begins_with("Nuvola"):
			c.queue_free()
	nuvole.clear()
	_piano()
	aggiorna()


## Posizione nel mondo del centro di un esagono.
func pos(h: int) -> Vector3:
	var p := D.centro(h)
	return Vector3(p.x, 0, p.y)


func _piano() -> void:
	var tex: Texture2D = Grafica.mappa()
	var mi := MeshInstance3D.new()
	mi.name = "Piano"
	var pm := PlaneMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	pm.material = mat
	# la texture va messa in modo che i centri degli esagoni coincidano con D.centro()
	var w := float(tex.get_width())
	var hh := float(tex.get_height())
	var a := Grafica.centro_px(101, w)
	var b := Grafica.centro_px(5101, w)
	var c := Grafica.centro_px(129, w)
	var sx := (D.centro(5101).x - D.centro(101).x) / (b.x - a.x)
	var sz := (D.centro(129).y - D.centro(101).y) / (c.y - a.y)
	pm.size = Vector2(w * sx, hh * sz)
	mi.mesh = pm
	mi.position = Vector3(-a.x * sx + w * sx / 2.0, 0, -a.y * sz + hh * sz / 2.0)
	root3.add_child(mi)
	# la galassia: due strati di nuvola trasparente sopra la griglia
	var gal: Texture2D = load("res://assets/board/galassia.png")
	var neb: Texture2D = load("res://assets/board/nebulosa.png")
	var gw := 4045.0
	var gsx := 1.0 / Grafica.GS
	var size := Vector2(gw * gsx, 2712.0 * gsx)
	var centro := Vector3(-Grafica.GMX + size.x / 2.0, 0, -Grafica.GMY + size.y / 2.0)
	var strati = [[gal, 1.6, 0.5], [gal, 3.2, 0.22], [neb, 5.0, 0.35]]
	var i := 0
	for s in strati:
		var n := MeshInstance3D.new()
		n.name = "Nuvola%d" % i
		var q := PlaneMesh.new()
		q.size = size * (1.0 + i * 0.04)
		var m2 := StandardMaterial3D.new()
		m2.albedo_texture = s[0]
		m2.albedo_color = Color(1, 1, 1, s[2])
		m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m2.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m2.cull_mode = BaseMaterial3D.CULL_DISABLED
		m2.no_depth_test = false
		m2.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		q.material = m2
		n.mesh = q
		n.position = centro + Vector3(0, s[1], 0)
		n.visible = nuvola
		root3.add_child(n)
		nuvole.append(n)
		i += 1


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
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
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
		var a := sin(t * 0.05 + i) * 0.015 * (i + 1)
		n.rotation.y = a
		n.position.y = [1.6, 3.2, 5.0][i] + sin(t * 0.3 + i) * 0.15
	if _sel_mesh != null:
		_sel_mesh.rotation.y += d * 1.5
		_sel_mesh.scale = Vector3.ONE * (1.0 + 0.06 * sin(t * 5.0))
	for c in effetti.get_children():
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
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
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
				var h := _pick(mb.position)
				if h > 0:
					hex_clicked.emit(h)
			_drag = 0
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _drag != 0:
			if mm.position.distance_to(_press) > 6:
				_moved = true
			var dd := mm.position - _from
			_from = mm.position
			if _moved:
				if _drag == MOUSE_BUTTON_RIGHT or (_drag == MOUSE_BUTTON_LEFT and mm.shift_pressed):
					yaw -= dd.x * 0.006
					pitch = clampf(pitch + dd.y * 0.005, 0.25, 1.45)
				else:
					var f := dist * 0.0018
					var fw := Vector3(sin(yaw), 0, cos(yaw))
					var rt := Vector3(cos(yaw), 0, -sin(yaw))
					target -= rt * dd.x * f + fw * dd.y * f
				_camera()
		else:
			var h2 := _pick(mm.position)
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
	var sc := Vector2(vp.size) / size if size.x > 0 else Vector2.ONE
	var q := p * sc
	var o := cam.project_ray_origin(q)
	var dir := cam.project_ray_normal(q)
	if absf(dir.y) < 0.0001:
		return -1
	var k := -o.y / dir.y
	if k < 0:
		return -1
	var w := o + dir * k
	var h := D.da_punto(Vector2(w.x, w.z))
	return h if D.esiste(h) else -1


# ---------------------------------------------------------------- pedine

func _mat_tex(nome: String, scuro := false) -> StandardMaterial3D:
	var k := nome + (":s" if scuro else "") + ":" + Grafica.stile
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
		var p := pos(h) + Vector3(-0.35, 0.02, -0.35)
		var n = _gettone(Grafica.nome_porta(o), p, 0.75, Grafica.tinta(o), g["neut"])
		pedine.add_child(n)
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
				pedine.add_child(_testo(str(g["sp"]), p + Vector3(0.3, 0.5, 0)))
		else:
			pedine.add_child(_testo("N", p + Vector3(0, 0.5, 0), UI.ROSSO))
	# flotte: una pila per proprietario, alta quanto le flotte
	for h in eng.flotte:
		var i := 0
		for o in eng.proprietari(h):
			var st: Dictionary = eng.stack(h, o)
			var tot := int(st["r"]) + int(st["d"]) + int(st["e"])
			var base := pos(h) + Vector3(0.3 + i * 0.25, 0.02, 0.15 + i * 0.25)
			var strati := clampi(tot, 1, 6) if _vede(o) else 1
			for k in strati:
				var n2 := _gettone(Grafica.nome_flotta(o), base + Vector3(0, k * 0.13, 0), 0.7, Grafica.tinta(o))
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
		var f := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		var mf := StandardMaterial3D.new()
		mf.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mf.albedo_color = Color(1, 0.75, 0.55) if D.faro_stampato(h) != "" else Color(0.8, 0.9, 1.0)
		mf.emission_enabled = true
		mf.emission = mf.albedo_color
		mf.emission_energy_multiplier = 3.0
		sm.material = mf
		f.mesh = sm
		f.position = pos(h) + Vector3(-0.5, 0.9, 0.5)
		pedine.add_child(f)
	for h in eng.pv:
		if eng.porte.has(h):
			continue
		var v = eng.valore_pv(h) if tutto_visibile else (eng.pv_noto(h, vista) if vista >= 0 else -1)
		var gp := _gettone("pv", pos(h) + Vector3(0.45, 0.02, -0.45), 0.4, Color(0.6, 0.62, 0.6))
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
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.22
			sm.height = 0.44
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var col = Grafica.tinta(int(data["o"])) if kind == "salto" else UI.ROSSO
			m.albedo_color = col
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = 4.0
			sm.material = m
			s.mesh = sm
			s.set_meta("vita", 1.2)
			s.set_meta("durata", 1.2)
			s.set_meta("da", pos(int(data["da"])) + Vector3(0, 0.5, 0))
			s.set_meta("a", pos(int(data.get("h", data["a"]))) + Vector3(0, 0.5, 0))
			effetti.add_child(s)
		"attacco", "neutralizza", "contatto", "esplora", "porta", "autonomi":
			var col2: Color = {"attacco": Color(1, 0.45, 0.15), "neutralizza": Color(0.7, 0.8, 1.0), "contatto": UI.AMBRA, "esplora": Color(0.5, 0.9, 1.0)}.get(kind, Color(1, 1, 1))
			if data.has("o"):
				col2 = Grafica.tinta(int(data["o"])) if kind in ["porta", "autonomi"] else col2
			var a = _anello(pos(int(data["h"])), col2, 0.4, 0.6)
			a.set_meta("vita", 1.0)
			effetti.add_child(a)
