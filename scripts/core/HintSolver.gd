# scripts/core/HintSolver.gd
#
# Suggerisce la prossima mossa per l'hint in-game.
# Strategia: greedy one-step — valuta ogni mossa valida e sceglie quella
# che produce il nuovo stato con la Manhattan distance totale più bassa.
#
# Complessità: O(k * N²) dove k = mosse valide (max 4) e N = lato griglia.
# In pratica: < 0.1ms su qualsiasi stato 4x4. Sempre istantaneo, a differenza
# di PuzzleSolver.solve() che è pensato per la generazione offline dei livelli.
#
# Separato da PuzzleSolver per responsabilità distinte:
#   PuzzleSolver.solve()   → ricerca ottimale (A*), strumento offline
#   HintSolver.suggest_move() → greedy istantaneo, chiamato a runtime durante il gioco

class_name HintSolver
extends RefCounted


# Ritorna l'indice nell'array tiles della tile da muovere verso il blank.
#
# Sceglie tra le mosse valide quella che minimizza la Manhattan distance
# dello stato risultante. In caso di pareggio, sceglie la mossa con
# l'indice più basso (ordine deterministico = comportamento prevedibile e testabile).
#
# Ritorna -1 se lo stato è già risolto (nessuna mossa da suggerire).
func suggest_move(state: BoardState) -> int:
	if state.is_solved():
		return -1

	var best_move: int = -1
	# int.MAX non esiste in GDScript — usiamo una costante grande a sufficienza.
	# Il valore massimo teorico della Manhattan distance per un 4x4 è 6*16 = 96.
	# Equivalente di int.MaxValue come sentinella iniziale in C#.
	var best_distance: int = 999999

	# valid_moves() ritorna sempre le mosse nello stesso ordine (su, giù, sinistra, destra
	# per indice crescente), garantendo il comportamento deterministico in caso di pareggio.
	for move_index: int in state.valid_moves():
		var next_state := state.apply_move(move_index)
		var dist: int = _manhattan(next_state)

		# "<" (stretto) preserva il primo in caso di pareggio, perché aggiorniamo
		# best_move solo se la nuova distanza è strettamente minore.
		if dist < best_distance:
			best_distance = dist
			best_move = move_index

	return best_move


# ---------------------------------------------------------------------------
# Euristico interno
# ---------------------------------------------------------------------------

# Calcola la Manhattan distance totale dello stato.
# Duplicato di PuzzleSolver._manhattan() — intenzionale: HintSolver non dipende
# da PuzzleSolver. Le due classi sono indipendenti e possono evolvere separatamente.
func _manhattan(state: BoardState) -> int:
	var total: int = 0
	for i: int in range(state.size * state.size):
		var val: int = state.tiles[i]
		if val == 0:
			continue
		var cur_row: int = i / state.size
		var cur_col: int = i % state.size
		var goal_index: int = val - 1
		var goal_row: int = goal_index / state.size
		var goal_col: int = goal_index % state.size
		total += abs(cur_row - goal_row) + abs(cur_col - goal_col)
	return total
