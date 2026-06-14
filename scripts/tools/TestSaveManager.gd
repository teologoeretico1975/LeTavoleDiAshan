@tool
# scripts/tools/TestSaveManager.gd
#
# Verifica che SaveManager salvi, carichi e calcoli stelle correttamente,
# inclusa la persistenza su disco (ricrea il manager e rilegge il file).
#
# COME ESEGUIRE: apri nell'editor → Ctrl+Shift+X
#
# NOTA: scrive e poi cancella user://save.json durante il test.
# Se hai un save reale, verrà temporaneamente sovrascritto e poi ripristinato
# a vuoto da reset_all() alla fine. Per ora siamo in sviluppo — non ci sono
# save reali da proteggere.

extends EditorScript


func _run() -> void:
	var loader: Node = load("res://scripts/managers/level_loader.gd").new()

	var failures: Array = []
	var passed:   int   = 0
	var total:    int   = 0

	# Crea un SaveManager con il loader locale iniettato.
	# _test_loader bypassa get_node_or_null("/root/LevelLoader") che non
	# funziona in EditorScript — stesso problema già risolto in GameBoard.
	var saver: Node = _make_saver(loader)

	# T1 — livello vergine ritorna null
	total += 1
	if saver.get_level_progress(1, 1) != null:
		failures.append("T1: get_level_progress su livello mai giocato dovrebbe essere null")
	else:
		passed += 1

	# T2 — sblocco sequenziale: livello 1 sempre aperto, livello 2 no finché 1 non è completed
	total += 1
	var ok_t2: bool = saver.is_level_unlocked(1, 1) and not saver.is_level_unlocked(1, 2)
	if not ok_t2:
		failures.append("T2: livello 1 deve essere sbloccato, livello 2 no (prima del completamento)")
	else:
		passed += 1

	# T3 — 3 stelle: mosse ≤ par_moves (cap1/lv1: par=7, good=10 → 6 mosse = 3★)
	total += 1
	saver.save_level_result(1, 1, 6)
	var p = saver.get_level_progress(1, 1)
	if p == null or p["stars"] != 3 or p["best_moves"] != 6 or not p["completed"]:
		failures.append("T3: 6 mosse con par=7 → atteso 3★ best=6 completed=true, ottenuto: %s" % str(p))
	else:
		passed += 1

	# T4 — miglioramento sovrascrive (5 mosse < 6, stesse stelle ma best migliore)
	total += 1
	saver.save_level_result(1, 1, 5)
	p = saver.get_level_progress(1, 1)
	if p == null or p["best_moves"] != 5:
		failures.append("T4: 5 mosse dovrebbe aggiornare best_moves da 6 a 5")
	else:
		passed += 1

	# T5 — peggioramento non sovrascrive (20 mosse > 5, risultato peggiore)
	total += 1
	saver.save_level_result(1, 1, 20)
	p = saver.get_level_progress(1, 1)
	if p == null or p["best_moves"] != 5 or p["stars"] != 3:
		failures.append("T5: 20 mosse non dovrebbe sovrascrivere best=5 stars=3")
	else:
		passed += 1

	# T6 — dopo completamento livello 1, livello 2 si sblocca
	total += 1
	if not saver.is_level_unlocked(1, 2):
		failures.append("T6: livello 2 deve essere sbloccato dopo aver completato il livello 1")
	else:
		passed += 1

	# T7 — 2 stelle: par < mosse ≤ good (cap1/lv2: par=8, good=12 → 9 mosse = 2★)
	total += 1
	saver.save_level_result(1, 2, 9)
	p = saver.get_level_progress(1, 2)
	if p == null or p["stars"] != 2:
		failures.append("T7: 9 mosse con par=8 good=12 → atteso 2★, ottenuto: %s" % str(p))
	else:
		passed += 1

	# T8 — 1 stella: mosse > good (cap1/lv3: par=10, good=15 → 20 mosse = 1★)
	total += 1
	saver.save_level_result(1, 3, 20)
	p = saver.get_level_progress(1, 3)
	if p == null or p["stars"] != 1:
		failures.append("T8: 20 mosse con good=15 → atteso 1★, ottenuto: %s" % str(p))
	else:
		passed += 1

	# T9 — persistenza: un secondo SaveManager ricarica gli stessi dati dal file
	total += 1
	var saver2: Node = _make_saver(loader)
	var p2 = saver2.get_level_progress(1, 1)
	if p2 == null or p2["best_moves"] != 5 or p2["stars"] != 3:
		failures.append("T9: dati non persistiti su disco (ottenuto: %s)" % str(p2))
	else:
		passed += 1

	# Pulizia: azzera il save creato dal test per non inquinare lo sviluppo
	saver2.reset_all()

	saver.free()
	saver2.free()
	loader.free()

	print("\n=== TestSaveManager ===")
	print("%d / %d test passati." % [passed, total])
	if failures.is_empty():
		print("Tutti OK.")
	else:
		print("Falliti:")
		for f: String in failures:
			print("  - " + f)


func _make_saver(p_loader: Node) -> Node:
	var saver: Node = load("res://scripts/managers/save_manager.gd").new()
	saver._test_loader = p_loader
	saver._ready()
	return saver
