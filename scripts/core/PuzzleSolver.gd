# scripts/core/PuzzleSolver.gd
#
# Risolve un N-puzzle con l'algoritmo A* e restituisce il numero ottimale di mosse
# e il percorso completo dalla configurazione iniziale alla soluzione.
#
# Classe pura: extends RefCounted, nessun accesso all'albero di scena.
# Dipende solo da BoardState.
#
# NOTE PER CHI VIENE DA C#:
#   - Le inner class in GDScript si dichiarano con "class Nome:" dentro il file.
#     NON hanno accesso automatico ai membri della classe esterna (diverso da C#).
#   - I campi non tipizzati (es. "var parent") accettano qualsiasi tipo — come
#     "object" in C#. Si usa quando il tipo auto-referenziale non è supportato.

class_name PuzzleSolver
extends RefCounted


# ===========================================================================
# INNER CLASS: SolveResult
# Contiene il risultato della ricerca A*. Pubblica: altri script possono usarla
# come "PuzzleSolver.SolveResult" o semplicemente "SolveResult" se importata.
# ===========================================================================

class SolveResult:
	extends RefCounted

	var solvable: bool = false
	var optimal_moves: int = 0
	# Quanti nodi sono stati estratti dal closed set durante la ricerca.
	# Utile per misurare la difficoltà computazionale indipendentemente dall'hardware.
	var nodes_explored: int = 0
	# true se la ricerca è stata interrotta per aver raggiunto max_nodes.
	# In questo caso optimal_moves è -1 e path è vuoto.
	var aborted: bool = false

	# Sequenza di BoardState dall'iniziale al risolto.
	# path[0] = stato iniziale, path[-1] = stato risolto.
	# Indice negativo [-1] accede all'ultimo elemento — sintassi GDScript/Python,
	# non esiste in C# (dove si userebbe path[path.Count - 1]).
	var path: Array = []  # Array of BoardState, non tipizzato per compatibilità


# ===========================================================================
# INNER CLASS: _AStarNode
# Nodo interno dell'albero di ricerca A*. Il prefisso _ indica che è privata.
# ===========================================================================

class _AStarNode:
	extends RefCounted

	var state: BoardState
	var g: int   # costo accumulato: numero di mosse dall'inizio
	var h: int   # valore euristico: stima delle mosse rimanenti (Manhattan)
	# "parent" non è tipizzato come _AStarNode perché GDScript non supporta
	# tipi auto-referenziali nelle inner class. Funziona come "object" in C#.
	var parent   # _AStarNode | null

	func _init(p_state: BoardState, p_g: int, p_h: int, p_parent) -> void:
		state = p_state
		g = p_g
		h = p_h
		parent = p_parent

	# f(n) = g(n) + h(n) — la funzione di costo totale stimato che A* minimizza.
	func f() -> int:
		return g + h


# ===========================================================================
# INNER CLASS: _MinHeap
# Priority queue (min-heap binario) per la open list di A*.
# Un heap binario garantisce insert e pop_min in O(log n).
# GDScript non ha una priority queue built-in (a differenza di C# PriorityQueue<T>).
#
# Struttura: array dove per ogni nodo all'indice i:
#   - figlio sinistro: indice 2*i + 1
#   - figlio destro:   indice 2*i + 2
#   - genitore:        indice (i - 1) / 2
# Il nodo con f() minimo è sempre in _data[0].
# ===========================================================================

class _MinHeap:
	extends RefCounted

	var _data: Array = []  # Array of _AStarNode

	func is_empty() -> bool:
		return _data.is_empty()

	func size() -> int:
		return _data.size()

	# Inserisce un nodo e ripristina la proprietà heap risalendo (sift up).
	func push(node: _AStarNode) -> void:
		_data.append(node)
		_sift_up(_data.size() - 1)

	# Rimuove e ritorna il nodo con f() minimo (sempre in posizione 0).
	func pop_min() -> _AStarNode:
		if _data.size() == 1:
			# pop_back() rimuove e ritorna l'ultimo elemento — come List<T>.RemoveAt(Count-1) in C#.
			return _data.pop_back()
		var min_node: _AStarNode = _data[0]
		# Porta l'ultimo elemento in cima e fai sift down.
		_data[0] = _data.pop_back()
		_sift_down(0)
		return min_node

	# Risale dall'indice i verso la radice finché la proprietà heap è rispettata.
	func _sift_up(i: int) -> void:
		while i > 0:
			var parent_i: int = (i - 1) / 2  # divisione intera in GDScript
			if _data[parent_i].f() <= _data[i].f():
				break
			# Swap — GDScript non ha tuple swap, serve variabile temporanea come in C#.
			var tmp: _AStarNode = _data[parent_i]
			_data[parent_i] = _data[i]
			_data[i] = tmp
			i = parent_i

	# Scende dall'indice i verso le foglie finché la proprietà heap è rispettata.
	func _sift_down(i: int) -> void:
		var n: int = _data.size()
		while true:
			var smallest: int = i
			var left: int = 2 * i + 1
			var right: int = 2 * i + 2
			if left < n and _data[left].f() < _data[smallest].f():
				smallest = left
			if right < n and _data[right].f() < _data[smallest].f():
				smallest = right
			if smallest == i:
				break
			var tmp: _AStarNode = _data[smallest]
			_data[smallest] = _data[i]
			_data[i] = tmp
			i = smallest


# ===========================================================================
# API PUBBLICA
# ===========================================================================

# Risolve il puzzle dato e ritorna un SolveResult.
# Garantisce la soluzione OTTIMALE grazie all'euristico ammissibile (Manhattan).
#
# max_nodes: limite al numero di nodi esplorati. 0 = nessun limite.
# Se il limite viene raggiunto, result.aborted = true e optimal_moves = -1.
# Usare max_nodes per evitare attese infinite su puzzle molto profondi (>30 mosse
# con A* + Manhattan sul 15-puzzle).
func solve(initial: BoardState, max_nodes: int = 0) -> SolveResult:
	var result := SolveResult.new()

	# Controllo solvibilità prima di avviare A* — O(N²), molto più veloce.
	if not is_solvable(initial):
		result.solvable = false
		return result

	result.solvable = true

	# Caso banale: già risolto.
	if initial.is_solved():
		result.optimal_moves = 0
		result.path = [initial]
		return result

	# --- Inizializzazione A* ---
	var open_list := _MinHeap.new()
	# closed_set come Dictionary usato come HashSet: chiave = stringa dello stato,
	# valore = true (non ci interessa il valore, solo la presenza della chiave).
	# Equivalente a HashSet<string> in C#.
	var closed_set: Dictionary = {}

	var start_h: int = _manhattan(initial)
	var start_node := _AStarNode.new(initial, 0, start_h, null)
	open_list.push(start_node)

	# --- Loop principale A* ---
	while not open_list.is_empty():
		var current: _AStarNode = open_list.pop_min()
		var key: String = _state_key(current.state)

		# Se lo stato è già nel closed set, un percorso migliore è già stato trovato.
		# "has()" su Dictionary = ContainsKey() in C#.
		if closed_set.has(key):
			continue
		closed_set[key] = true
		result.nodes_explored += 1

		# Controllo limite nodi: se raggiunto, abortisci senza risultato.
		# max_nodes == 0 significa "nessun limite" — il confronto è saltato.
		if max_nodes > 0 and result.nodes_explored >= max_nodes:
			result.aborted = true
			result.optimal_moves = -1
			return result

		# Soluzione trovata: ricostruiamo il percorso.
		if current.state.is_solved():
			result.optimal_moves = current.g
			result.path = _reconstruct_path(current)
			return result

		# Espandiamo i nodi figli (stati raggiungibili con una mossa).
		for move_index: int in current.state.valid_moves():
			var next_state := current.state.apply_move(move_index)
			var next_key := _state_key(next_state)
			if not closed_set.has(next_key):
				var next_node := _AStarNode.new(
					next_state,
					current.g + 1,
					_manhattan(next_state),
					current
				)
				open_list.push(next_node)

	# Non dovremmo mai arrivare qui se is_solvable() è corretto.
	# Se succede, c'è un bug nella logica di solvibilità.
	push_error("PuzzleSolver: A* esaurita senza trovare soluzione per uno stato solvibile.")
	return result


# Ritorna solo il numero ottimale di mosse, senza il percorso completo.
# max_nodes: passa 0 per nessun limite, altrimenti la ricerca si interrompe
# e ritorna -1 se il limite viene raggiunto.
func count_optimal_moves(initial: BoardState, max_nodes: int = 0) -> int:
	var result := solve(initial, max_nodes)
	if not result.solvable or result.aborted:
		return -1
	return result.optimal_moves


# Ritorna la distanza di Manhattan dello stato — esposta come API pubblica
# perché utile come euristico rapido anche fuori dal solver
# (es. per mostrare un indicatore di difficoltà in tempo reale).
func manhattan_distance(state: BoardState) -> int:
	return _manhattan(state)


# ===========================================================================
# SOLVIBILITÀ
# ===========================================================================

# Verifica se una configurazione è risolvibile PRIMA di avviare A*.
# Metà delle N! permutazioni di un N-puzzle sono irrisolvibili.
#
# Regola (dimostrata matematicamente):
#   - Griglia lato DISPARI (3x3): risolvibile se il numero di inversioni è PARI.
#   - Griglia lato PARI (4x4):   risolvibile se (inversioni + riga_blank_dal_basso) è DISPARI.
#     "riga_blank_dal_basso" = contata dal basso, 1-indexed.
#     (riga 0 dall'alto in una griglia 4x4 → riga 4 dal basso)
#
# Un'inversione è una coppia (i,j) con i<j dove tiles[i] > tiles[j] e nessuno dei due è 0.
func is_solvable(state: BoardState) -> bool:
	var inversions: int = _count_inversions(state)
	if state.size % 2 == 1:
		# Griglia dispari: risolvibile se inversioni pari.
		return inversions % 2 == 0
	else:
		# Griglia pari: considera la riga del blank contata dal basso (1-indexed).
		# blank_index / size = riga 0-indexed dall'alto.
		# size - (blank_index / size) = riga 1-indexed dal basso.
		var blank_row_from_bottom: int = state.size - (state.blank_index / state.size)
		return (inversions + blank_row_from_bottom) % 2 == 1


# ===========================================================================
# METODI PRIVATI
# ===========================================================================

# Euristico Manhattan: somma delle distanze Manhattan di ogni tile dalla sua
# posizione obiettivo. È ammissibile (non sovrastima mai) e consistente,
# proprietà necessarie per garantire ottimalità in A*.
func _manhattan(state: BoardState) -> int:
	var total: int = 0
	for i: int in range(state.size * state.size):
		var val: int = state.tiles[i]
		if val == 0:
			continue  # il blank non contribuisce all'euristico

		# Posizione corrente nell'array piatto → coordinate (riga, colonna).
		var cur_row: int = i / state.size
		var cur_col: int = i % state.size

		# Posizione obiettivo: la tile con valore V deve stare all'indice V-1.
		# Esempio: tile "5" deve stare all'indice 4 → riga 1 col 0 in un 4x4.
		var goal_index: int = val - 1
		var goal_row: int = goal_index / state.size
		var goal_col: int = goal_index % state.size

		# abs() = Math.Abs() in C# — funzione globale in GDScript.
		total += abs(cur_row - goal_row) + abs(cur_col - goal_col)
	return total


# Conta le inversioni nell'array (escludendo il blank).
func _count_inversions(state: BoardState) -> int:
	var count: int = 0
	var n: int = state.size * state.size
	# Doppio ciclo O(N²) — accettabile per N <= 16.
	for i: int in range(n):
		if state.tiles[i] == 0:
			continue
		for j: int in range(i + 1, n):
			if state.tiles[j] == 0:
				continue
			if state.tiles[i] > state.tiles[j]:
				count += 1
	return count


# Converte lo stato in una stringa univoca per il closed_set.
# Equivalente funzionale di GetHashCode() + Equals() per uno stato.
# Esempio per 3x3: "1,2,3,4,5,6,7,8,0"
func _state_key(state: BoardState) -> String:
	# PackedStringArray è un array di stringhe ottimizzato in memoria.
	# join() = String.Join(",", parts) in C#.
	var parts := PackedStringArray()
	for v: int in state.tiles:
		parts.append(str(v))
	return ",".join(parts)


# Ricostruisce il percorso risalendo la catena di nodi parent.
# Il nodo finale ha parent=null, quello iniziale è la radice.
func _reconstruct_path(node: _AStarNode) -> Array:
	var path: Array = []
	var current = node
	while current != null:
		# push_front() inserisce in testa — come List<T>.Insert(0, item) in C#.
		# Usiamo push_front perché risaliamo dall'obiettivo verso l'inizio.
		path.push_front(current.state)
		current = current.parent
	return path
