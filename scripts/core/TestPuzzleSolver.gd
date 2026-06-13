# scripts/core/TestPuzzleSolver.gd
#
# Test manuale per PuzzleSolver.
# Come eseguire: apri nell'editor Godot, premi Run (▶) o Ctrl+Shift+X.

@tool
extends EditorScript


func _run() -> void:
	print("=".repeat(40))
	print("TEST PuzzleSolver")
	print("=".repeat(40))

	_test_already_solved()
	_test_one_move_away()
	_test_solvability()
	_test_real_puzzle_3x3()
	_test_manhattan_heuristic()
	_test_4x4_scrambled_performance()

	print("\nTutti i test completati.")


# ---------------------------------------------------------------------------

func _test_already_solved() -> void:
	print("\n--- Puzzle già risolto ---")
	var solver := PuzzleSolver.new()
	var state := BoardState.solved(4)
	var result := solver.solve(state)

	print("solvable: ", result.solvable,     "  (atteso true)")
	print("optimal_moves: ", result.optimal_moves, "  (atteso 0)")
	print("path.size(): ", result.path.size(),   "  (atteso 1)")


func _test_one_move_away() -> void:
	print("\n--- Puzzle a 1 mossa dalla soluzione (3x3) ---")
	# Stato risolto 3x3, poi applichiamo una mossa → 1 mossa per tornare.
	var state := BoardState.solved(3).apply_move(7)  # tile 8 si sposta nel blank
	print("Stato iniziale:")
	print(state)

	var solver := PuzzleSolver.new()
	var result := solver.solve(state)

	print("solvable: ", result.solvable,        "  (atteso true)")
	print("optimal_moves: ", result.optimal_moves,   "  (atteso 1)")
	print("path.size(): ", result.path.size(),     "  (atteso 2: inizio + fine)")

	# Verifica che il primo stato sia quello iniziale e l'ultimo sia risolto.
	var first_state: BoardState = result.path[0]
	var last_state: BoardState = result.path[-1]  # indice negativo = ultimo
	print("path[0] uguale allo stato iniziale: ", first_state.tiles == state.tiles)
	print("path[-1] è risolto: ", last_state.is_solved())


func _test_solvability() -> void:
	print("\n--- Test solvibilità ---")
	var solver := PuzzleSolver.new()

	# Lo stato risolto è sempre risolvibile (0 inversioni → pari).
	var solved_3 := BoardState.solved(3)
	print("3x3 risolto è solvibile: ", solver.is_solvable(solved_3), "  (atteso true)")

	# Scambiare due tile adiacenti (non il blank) rende il puzzle irrisolvibile.
	# Prendiamo lo stato risolto 3x3 [1,2,3,4,5,6,7,8,0] e scambiamo tile 1 e 2
	# → [2,1,3,4,5,6,7,8,0]: 1 inversione (dispari) → irrisolvibile.
	var tiles_unsolvable: Array[int] = [2, 1, 3, 4, 5, 6, 7, 8, 0]
	var unsolvable := BoardState.new(tiles_unsolvable, 3)
	print("3x3 con 1 inversione è solvibile: ", solver.is_solvable(unsolvable), "  (atteso false)")

	var result := solver.solve(unsolvable)
	print("solve() su irrisolvibile → solvable=false: ", not result.solvable)

	# Stato risolto 4x4 deve essere solvibile.
	var solved_4 := BoardState.solved(4)
	print("4x4 risolto è solvibile: ", solver.is_solvable(solved_4), "  (atteso true)")


func _test_real_puzzle_3x3() -> void:
	print("\n--- Puzzle 3x3 reale (5 mosse ottimali) ---")
	# Costruiamo uno stato a esattamente 5 mosse dalla soluzione applicando 5 mosse
	# in sequenza (senza tornare indietro).
	#   Stato risolto: 1 2 3 / 4 5 6 / 7 8 _
	#   mossa 1: tile 8 → _ (blank va in pos 7)
	#   mossa 2: tile 7 → _ (blank va in pos 6... aspetta, devo controllare gli indici)
	# Usiamo uno stato noto con soluzione documentata.
	# [1,2,3,4,0,5,7,8,6] ha soluzione ottimale di 3 mosse:
	#   pos 5 (val 5) → blank pos 4  →  [1,2,3,4,5,0,7,8,6]
	#   pos 8 (val 6) → blank pos 5  →  [1,2,3,4,5,6,7,8,0]  ← risolto? No, blank deve essere in pos 8
	# Usiamo l'approccio più sicuro: applicare N mosse distinte e verificare il conto.
	var state := BoardState.solved(3)
	# Sequenza di 4 mosse non palindrome (non si torna indietro).
	# Blank parte in 8. Mosse: 7 (blank→7), 6 (blank→6), 3 (blank→3), 4 (blank→4)
	state = state.apply_move(7)  # blank: 8→7
	state = state.apply_move(6)  # blank: 7→6
	state = state.apply_move(3)  # blank: 6→3
	state = state.apply_move(4)  # blank: 3→4

	print("Stato a 4 mosse dal risolto:")
	print(state)

	var solver := PuzzleSolver.new()
	var result := solver.solve(state)

	print("solvable: ", result.solvable)
	print("optimal_moves: ", result.optimal_moves, "  (atteso <= 4)")
	# La soluzione ottimale potrebbe essere <= 4 se esiste una scorciatoia.

	# Stampa il percorso completo.
	print("Percorso soluzione (%d stati):" % result.path.size())
	for i: int in range(result.path.size()):
		var step: BoardState = result.path[i]
		print("Step %d:" % i)
		print(step)


func _test_manhattan_heuristic() -> void:
	print("\n--- Euristico Manhattan ---")
	var solver := PuzzleSolver.new()

	# Nello stato risolto la distanza Manhattan è 0.
	var solved := BoardState.solved(4)
	print("Manhattan dello stato risolto: ", solver.manhattan_distance(solved), "  (atteso 0)")

	# Dopo 1 mossa la distanza Manhattan è 1 (una tile si è allontanata di 1).
	var one_move := solved.apply_move(14)
	print("Manhattan dopo 1 mossa: ", solver.manhattan_distance(one_move), "  (atteso 1)")

	# Dopo 2 mosse non-inverse la distanza Manhattan è 2.
	var two_moves := one_move.apply_move(10)
	print("Manhattan dopo 2 mosse: ", solver.manhattan_distance(two_moves), "  (atteso 2)")


func _test_4x4_scrambled_performance() -> void:
	print("\n--- 4x4 scramblato ~20 mosse: performance A* ---")

	# Generiamo uno stato applicando 20 mosse casuali non-inverse dallo stato risolto.
	# "Non-inverse" = non torniamo immediatamente indietro (evita di annullare la mossa
	# precedente, altrimenti ci ritrovassimo con uno scramble effettivo molto minore).
	# Questo garantisce che lo stato abbia circa 20 mosse di distanza dalla soluzione
	# (la soluzione ottimale potrebbe essere minore se esistono scorciatoie).
	var state := BoardState.solved(4)
	var rng := RandomNumberGenerator.new()
	# seed() fisso → risultato riproducibile ad ogni esecuzione del test.
	# Utile per debug: se il test fallisce puoi riprodurlo esattamente.
	# Equivalente di "new Random(42)" in C#.
	rng.seed = 42

	var last_move: int = -1  # indice dell'ultima mossa applicata (per evitare l'inversa)
	var moves_applied: int = 0
	while moves_applied < 20:
		var valid := state.valid_moves()

		# Rimuoviamo dall'elenco la mossa che annullerebbe quella precedente.
		# Quando muoviamo la tile T nel blank, il blank si sposta dove stava T.
		# La mossa inversa è quella che riporta il blank nella posizione originale,
		# ovvero la mossa verso l'indice dove ora si trova il blank (= last_move).
		# "erase()" rimuove la prima occorrenza del valore — come List<T>.Remove() in C#.
		if last_move != -1:
			valid.erase(state.blank_index)  # dopo la mossa, blank_index è già aggiornato

		# randi_range(min, max) ritorna un intero casuale in [min, max] inclusi.
		# Equivalente di "Random.Next(min, max+1)" in C#.
		var chosen: int = valid[rng.randi_range(0, valid.size() - 1)]
		last_move = state.blank_index  # salviamo dove era il blank prima della mossa
		state = state.apply_move(chosen)
		moves_applied += 1

	print("Stato generato (20 mosse random, seed=42):")
	print(state)
	print("Manhattan distance iniziale: ", PuzzleSolver.new().manhattan_distance(state))

	# --- Misurazione del tempo ---
	# Time.get_ticks_msec() ritorna i millisecondi dall'avvio dell'engine.
	# È la funzione più semplice per misurare elapsed time in GDScript —
	# equivalente di Stopwatch.GetTimestamp() in C#.
	var solver := PuzzleSolver.new()
	var t_start: int = Time.get_ticks_msec()
	var optimal: int = solver.count_optimal_moves(state)
	var t_end: int = Time.get_ticks_msec()
	var elapsed_ms: int = t_end - t_start

	print("Mosse ottimali trovate: ", optimal)
	print("Tempo A*: %d ms" % elapsed_ms)

	# Soglia orientativa: oltre 1000 ms per un singolo puzzle sarebbe problematico
	# per la generazione batch di centinaia di livelli.
	if elapsed_ms < 100:
		print("→ VELOCE: generazione batch dei livelli fattibile senza ottimizzazioni.")
	elif elapsed_ms < 1000:
		print("→ ACCETTABILE: generazione batch fattibile, ma valutare IDA* per puzzle > 25 mosse.")
	else:
		print("→ LENTO: considerare IDA* o pre-calcolo offline dei livelli.")
