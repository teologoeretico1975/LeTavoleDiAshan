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
	_test_4x4_worst_case_performance()

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


# Genera uno stato 4x4 applicando n_moves mosse casuali non-inverse dallo stato risolto.
# "Non-inverse" = non annulliamo immediatamente la mossa precedente, così lo scramble
# effettivo è vicino a n_moves (la soluzione ottimale potrebbe essere minore se esistono
# scorciatoie nella griglia, ma resta nell'ordine di grandezza corretto).
# p_seed fisso → risultato riproducibile ad ogni esecuzione.
func _scramble_4x4(n_moves: int, p_seed: int) -> BoardState:
	var state := BoardState.solved(4)
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed

	# prev_blank traccia dove si trovava il blank PRIMA dell'ultima mossa,
	# ovvero l'indice che andremmo a muovere per annullare la mossa appena fatta.
	var prev_blank: int = -1
	for _i in range(n_moves):
		var valid := state.valid_moves()
		# erase() rimuove la prima occorrenza del valore — come List<T>.Remove() in C#.
		# Rimuoviamo la mossa inversa: quella che riporta il blank dove era prima.
		if prev_blank != -1:
			valid.erase(prev_blank)
		prev_blank = state.blank_index
		var chosen: int = valid[rng.randi_range(0, valid.size() - 1)]
		state = state.apply_move(chosen)

	return state


const MAX_NODES: int = 500_000  # soglia di abort per tutti i test di performance


# Esegue solve() con il limite MAX_NODES, stampa manhattan/tempo/nodi/risultato,
# e ritorna true se la ricerca è stata abortita (utile per il riepilogo finale).
func _run_performance_check_ex(state: BoardState) -> bool:
	var solver := PuzzleSolver.new()
	print("  Manhattan iniziale : ", solver.manhattan_distance(state))

	var t_start: int = Time.get_ticks_msec()
	# Passiamo MAX_NODES come limite: se A* supera quella soglia si ferma
	# e result.aborted = true, invece di girare per minuti/ore.
	var result := solver.solve(state, MAX_NODES)
	var elapsed_ms: int = Time.get_ticks_msec() - t_start

	var status: String = " → LIMITE RAGGIUNTO" if result.aborted else " → completato"
	print("  Nodi esplorati     : %d / %d%s" % [result.nodes_explored, MAX_NODES, status])
	print("  Tempo              : %d ms" % elapsed_ms)

	if result.aborted:
		print("  Ottimale           : ABORTITO (oltre %d nodi)" % MAX_NODES)
		print("  → TROPPO LENTO per A* + Manhattan. Vedi riepilogo finale.")
	else:
		print("  Ottimale           : %d mosse" % result.optimal_moves)
		if elapsed_ms < 100:
			print("  → OK: A* praticabile per generazione batch.")
		elif elapsed_ms < 1000:
			print("  → BORDERLINE: accettabile offline, non in real-time.")
		else:
			print("  → LENTO: considerare IDA*.")

	return result.aborted


func _test_4x4_scrambled_performance() -> void:
	print("\n--- 4x4 threshold scan: 30 / 40 / 50 / 60 mosse (limite %d nodi) ---" % MAX_NODES)
	print("Obiettivo: trovare la soglia pratica di A* + Manhattan sul 15-puzzle.")
	print("Seed diversi per evitare che uno stato particolarmente fortunato")
	print("falsifichi la misurazione.")
	print("")

	# Array of [n_moves, seed] — sintassi GDScript per array di array.
	# Equivalente di List<(int, int)> in C#.
	var cases: Array = [
		[30, 1001],
		[40, 2002],
		[50, 3003],
		[60, 4004],
	]

	var any_aborted: bool = false
	for c in cases:
		var n_moves: int = c[0]
		var seed: int    = c[1]
		var state := _scramble_4x4(n_moves, seed)
		print("Scramble ~%d mosse (seed=%d):" % [n_moves, seed])
		var aborted := _run_performance_check_ex(state)
		if aborted:
			any_aborted = true
		print("")

	print("=" .repeat(40))
	if any_aborted:
		print("CONCLUSIONE: A* + Manhattan supera %d nodi su almeno un caso." % MAX_NODES)
		print("Per i livelli oltre la soglia pratica, le opzioni sono:")
		print("")
		print("  1. IDA* (Iterative Deepening A*)")
		print("     Pro: memoria O(d) invece di O(b^d) — non accumula nodi in RAM.")
		print("     Implementazione: loop su soglie f crescenti, DFS dentro ogni soglia.")
		print("     Con Manhattan risolve il 15-puzzle a 80 mosse in ~10-50ms.")
		print("     Contro: riesplora nodi già visti (ma per 15-puzzle è comunque veloce).")
		print("")
		print("  2. Pre-generazione offline dei livelli")
		print("     Calcola optimal_moves una volta sola fuori da Godot (Python/C#),")
		print("     salva il valore nel JSON del livello.")
		print("     A runtime il gioco usa il valore precalcolato: zero overhead.")
		print("     Ideale se i livelli sono fissi (non generati proceduralmente).")
		print("")
		print("  RACCOMANDAZIONE per questo progetto:")
		print("  Capitoli I-IV (livelli prefissati): pre-generazione offline.")
		print("  Hint in-game e Daily Puzzle (real-time): IDA*.")
	else:
		print("CONCLUSIONE: A* + Manhattan rimane entro %d nodi per tutti i casi." % MAX_NODES)
		print("Generazione batch praticabile senza cambiare algoritmo.")
	print("=" .repeat(40))


func _test_4x4_worst_case_performance() -> void:
	# Rimosso: sostituito da _test_4x4_scrambled_performance con threshold scan.
	pass
