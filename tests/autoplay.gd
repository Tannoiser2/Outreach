extends SceneTree
## Partite automatiche IA contro IA in tutti gli scenari.
## Uso: godot --headless --path . -s tests/autoplay.gd -- [scenario] [seme] [opzioni]
## opzioni: originali | skygazer | v3 | gilham | rivisto

func _init() -> void:
	var args = OS.get_cmdline_user_args()
	var scns = [1, 2, 3, 4, 5]
	var seeds = [1, 2]
	var varianti = ["originali", "v3", "gilham"]
	if args.size() >= 1:
		scns = [int(args[0])]
	if args.size() >= 2:
		seeds = [int(args[1])]
	if args.size() >= 3:
		varianti = [args[2]]
	var tot := 0
	var errori := 0
	for s in scns:
		for v in varianti:
			for sd in seeds:
				var e := ODEngine.new()
				e.headless = true
				e.ai_delay = 0.0
				e.anim = 0.0
				var n: int = ODEngine.D.SCENARI[s]["giocatori"]
				if n == 0:
					n = 3 if (sd + varianti.find(v)) % 2 == 1 else 1
				var seats := []
				for i in n:
					seats.append({"name": "IA", "ai": true, "level": 1})
				var opz = {"tabelle": "originali", "limite": 40}
				match v:
					"skygazer", "v3":
						opz["tabelle"] = v
						opz["conv_rivista"] = v == "v3"
					"gilham":
						opz["gilham"] = true
					"rivisto":
						opz["fato_rivisto"] = true
				e.setup({"scenario": s, "seed": sd, "seats": seats, "opzioni": opz, "max_turni": int(OS.get_environment("MAXT")) if OS.get_environment("MAXT") != "" else 30})
				root.add_child(e)
				var t0 = Time.get_ticks_msec()
				await e.run()
				var dt = Time.get_ticks_msec() - t0
				var info := []
				for i in e.players.size():
					var t: Dictionary = e.totale_flotte(i)
					info.append("%s: porte %d sp %d cl %d rp %d flotte %d/%d/%d%s" % [e.fazione(i), e.porte_di(i).size(), e.punti_sistema(i), e.cl(i), e.players[i]["rp"], t["r"], t["d"], t["e"], "" if e.players[i]["vivo"] else " ELIMINATO"])
				var aut := 0
				for a in e.aut:
					if a["presente"]:
						aut += 1
				print("SCN %d %s seme %d: turno %d, vincitore %s (%s) | %s | autonomi %d | %d ms | registro %d" % [s, v, sd, e.turn, str(e.result.get("winner", "?")), e.result.get("reason", ""), " ; ".join(info), aut, dt, e.log_lines.size()])
				if e.turn < 2:
					errori += 1
				if OS.get_environment("DUMP") != "":
					for ln in e.log_lines:
						print("   ", ln["t"])
				tot += 1
				e.queue_free()
	print("FINE ", tot, " partite, anomalie ", errori)
	quit()
