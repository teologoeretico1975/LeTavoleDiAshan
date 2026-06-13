# scripts/core/TestHintSolver.gd
#
# Test manuale per HintSolver.
# Come eseguire: apri nell'editor Godot, premi Run (▶) o Ctrl+Shift+X.

@tool
extends EditorScript


func _run() -> void:
	print("=".repeat(40))
	print("TEST HintSolver")
	print("=".repeat(40))

	_test_already_solved()
	_test_one_move_away()
	_test_tiebreak_determinism()
	_test_runtime_performance()

	print("\nTutti i test completati.")


# ---------------------------------------------------------------------------

func _test_already_solved() -> void:
	print("\n--- Stato già risolto: deve ritornare -1 ---")
	var hint := HintSolver.new()

	var s3 := BoardState.solved(3)
	print("3x3 risolto → suggest_move(): ", hint.suggest_move(s3), "  (atteso -1)")

	var s4 := BoardState.solved(4)
	print("4x4 risolto → suggest_move(): ", hint.suggest_move(s4), "  (atteso -1)")


func _test_one_move_away() -> void:
	print("\n--- Stato a 1 mossa dalla soluzione ---")
	print("suggest_move() deve restituire esattamente quella mossa.")

	var hint := HintSolver.new()

	# 3x3: stato risolto [1,2,3,4,5,6,7,8,0], blank in posizione 8.
	# Applichiamo la mossa tile[7] (valore 8) → blank si sposta in 7.
	# L'unica mossa che riduce la Manhattan distance è tornare a tile[7].
	var base_3 := BoardState.solved(3)
	var moved_3 := base_3.apply_move(7)
	print("Stato 3x3 dopo apply_move(7):")
	print(moved_3)
	var suggested_3: int = hint.suggest_move(moved_3)
	print("suggest_move(): ", suggested_3, "  (atteso 7 — riporta allo stato risolto)")
	# Verifica: applicando la mossa suggerita si ottiene lo stato risolto.
	print("Applicando la mossa suggerita si ottiene risolto: ",
		moved_3.apply_move(suggested_3).is_solved())

	# 4x4: blank parte in 15, spostiamo tile[14] → blank in 14.
	# La mossa corretta per tornare al risolto è tile[15]... no:
	# dopo apply_move(14), blank è in 14 e tiles[15] = 15.
	# La mossa che riporta al risolto è quella che sposta tiles[15] (= 15)
	# nel blank (posizione 14) → indice 15.
	var base_4 := BoardState.solved(4)
	var moved_4 := base_4.apply_move(14)
	print("\nStato 4x4 dopo apply_move(14):")
	print(moved_4)
	var suggested_4: int = hint.suggest_move(moved_4)
	print("suggest_move(): ", suggested_4, "  (atteso 15 — riporta allo stato risolto)")
	print("Applicando la mossa suggerita si ottiene risolto: ",
		moved_4.apply_move(suggested_4).is_solved())


func _test_tiebreak_determinism() -> void:
	print("\n--- Determinismo in caso di pareggio ---")
	print("Chiamate multiple sullo stesso stato devono ritornare sempre lo stesso indice.")

	var hint := HintSolver.new()
	# Stato a 2 mosse dalla soluzione: potrebbero esserci mosse con stessa distanza.
	var state := BoardState.solved(4).apply_move(14).apply_move(10)
	print("Stato:")
	print(state)

	var results: Array[int] = []
	for _i in range(5):
		results.append(hint.suggest_move(state))

	# Tutti i valori devono essere uguali.
	var all_equal: bool = true
	for r in results:
		if r != results[0]:
			all_equal = false
	print("5 chiamate → risultati: ", results)
	print("Tutti uguali (deterministici): ", all_equal)


func _test_runtime_performance() -> void:
	print("\n--- Performance su stato scramblato a ~60 mosse (seed=4004) ---")
	print("Deve essere < 1ms — conferma che è praticabile come hint runtime.")

	# Stesso stato usato nel threshold scan di TestPuzzleSolver per confronto diretto.
	var state := _scramble_4x4(60, 4004)
	print("Stato (60 mosse random, seed=4004):")
	print(state)

	var hint := HintSolver.new()

	# Misuriamo su 1000 chiamate consecutive per avere un tempo medio affidabile,
	# dato che una singola chiamata potrebbe essere troppo veloce per get_ticks_msec().
	# Equivalente di BenchmarkDotNet su singola operazione in C#.
	var ITERATIONS: int = 1000
	var t_start: int = Time.get_ticks_msec()
	var last_result: int = -1
	for _i in range(ITERATIONS):
		last_result = hint.suggest_move(state)
	var elapsed_ms: int = Time.get_ticks_msec() - t_start

	print("Mossa suggerita: ", last_result)
	print("Tempo totale (%d iterazioni): %d ms" % [ITERATIONS, elapsed_ms])
	# Divisione in virgola mobile: float() converte l'int — come (float) in C#.
	print("Tempo medio per chiamata: %.3f ms" % (float(elapsed_ms) / ITERATIONS))

	if elapsed_ms < ITERATIONS:  # < 1ms media
		print("→ ISTANTANEO: adatto per hint runtime senza overhead percepibile.")
	else:
		print("→ INATTESO: suggest_move() dovrebbe essere O(k*N²), verificare implementazione.")


# ---------------------------------------------------------------------------
# Helper condiviso (duplicato da TestPuzzleSolver per autonomia del file)
# ---------------------------------------------------------------------------

func _scramble_4x4(n_moves: int, p_seed: int) -> BoardState:
	var state := BoardState.solved(4)
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var prev_blank: int = -1
	for _i in range(n_moves):
		var valid := state.valid_moves()
		if prev_blank != -1:
			valid.erase(prev_blank)
		prev_blank = state.blank_index
		state = state.apply_move(valid[rng.randi_range(0, valid.size() - 1)])
	return state
