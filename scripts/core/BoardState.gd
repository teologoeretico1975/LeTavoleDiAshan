# scripts/core/BoardState.gd
#
# Rappresentazione immutabile dello stato di un N-puzzle (3x3 o 4x4).
# Classe pura: extends RefCounted, nessun accesso all'albero di scena.
#
# NOTE PER CHI VIENE DA C#:
#   - "extends RefCounted" = la memoria è gestita con reference counting automatico
#     (come un oggetto normale in C# con GC). Alternativa: "extends Object" che
#     richiede free() manuale. Non usiamo mai "extends Node" nelle classi core.
#   - "class_name" rende la classe globalmente visibile in tutto il progetto,
#     senza bisogno di import/using — equivalente a un tipo pubblico in C#.

class_name BoardState
extends RefCounted


# ---------------------------------------------------------------------------
# Campi
# ---------------------------------------------------------------------------

# Array piatto di N*N interi. 0 = casella vuota (blank).
# Per un 4x4: indice 0 = riga 0 col 0, indice 15 = riga 3 col 3.
# In GDScript "Array[int]" è un array tipizzato — come List<int> in C#,
# ma a dimensione dinamica. La dimensione reale è sempre size*size.
var tiles: Array[int]

# Lato della griglia (3 per il tutorial 3x3, 4 per il gioco principale 4x4).
var size: int

# Indice nell'array dove si trova il blank (0). Tenuto aggiornato per evitare
# di chiamare tiles.find(0) ogni volta che servono le mosse valide.
var blank_index: int


# ---------------------------------------------------------------------------
# Costruttore
# ---------------------------------------------------------------------------

# In GDScript il costruttore si chiama _init() — equivalente del ctor in C#.
# Si invoca con: BoardState.new(my_tiles, 4)
# Il prefisso "p_" sui parametri è una convenzione per distinguerli dai campi.
func _init(p_tiles: Array[int], p_size: int) -> void:
	size = p_size
	# duplicate() crea una copia profonda dell'array — come ToArray() o new List<>(other) in C#.
	# FONDAMENTALE: senza duplicate() tiles e p_tiles punterebbero allo stesso array,
	# rompendo l'immutabilità della classe.
	tiles = p_tiles.duplicate()
	# find() = IndexOf() in C#. Ritorna -1 se non trovato.
	blank_index = tiles.find(0)


# ---------------------------------------------------------------------------
# Metodi statici (factory)
# ---------------------------------------------------------------------------

# Genera lo stato risolto per una griglia di dimensione p_size.
# Stato risolto: [1, 2, 3, ..., N*N-1, 0]
#
# "static func" = metodo statico, si chiama BoardState.solved(4) — come in C#.
# Il tipo di ritorno "-> BoardState" funziona anche per metodi statici.
static func solved(p_size: int) -> BoardState:
	var t: Array[int] = []
	# range(1, n) genera da 1 a n-1 incluso — come Enumerable.Range(1, n-1) in C#.
	for i in range(1, p_size * p_size):
		t.append(i)
	t.append(0)  # il blank va sempre in ultima posizione nello stato risolto
	return BoardState.new(t, p_size)


# ---------------------------------------------------------------------------
# Mosse valide
# ---------------------------------------------------------------------------

# Ritorna gli indici delle tile che possono spostarsi nel blank.
# Nell'N-puzzle si "muovono" le tile adiacenti al blank, non il blank stesso.
# Esempio: se il blank è in posizione 5 di una griglia 4x4, le tile in
# posizione 1 (sopra), 9 (sotto), 4 (sinistra), 6 (destra) sono valide.
func valid_moves() -> Array[int]:
	var moves: Array[int] = []

	# Convertiamo l'indice piatto in coordinate (riga, colonna).
	# "/" in GDScript tra interi fa divisione intera — come in C#.
	var row: int = blank_index / size
	var col: int = blank_index % size

	# Tile sopra: può scendere nel blank. Esiste solo se non siamo nella riga 0.
	if row > 0:
		moves.append(blank_index - size)

	# Tile sotto: può salire nel blank.
	if row < size - 1:
		moves.append(blank_index + size)

	# Tile a sinistra: può spostarsi a destra nel blank.
	if col > 0:
		moves.append(blank_index - 1)

	# Tile a destra: può spostarsi a sinistra nel blank.
	if col < size - 1:
		moves.append(blank_index + 1)

	return moves


# ---------------------------------------------------------------------------
# Applicare una mossa (immutabile)
# ---------------------------------------------------------------------------

# Sposta la tile all'indice tile_index verso il blank e ritorna il NUOVO stato.
# Non modifica questo oggetto — equivalente al pattern "record with { }" in C# 9+.
#
# Parametro: tile_index = indice nell'array della tile da muovere (deve essere
# adiacente al blank, cioè deve essere in valid_moves()).
func apply_move(tile_index: int) -> BoardState:
	# assert() in GDScript = Debug.Assert() in C#: attivo solo in debug build.
	# "%d" % tile_index = String.Format("{0}", tile_index) — sintassi printf.
	assert(tile_index in valid_moves(), "Mossa non valida: tile_index=%d" % tile_index)

	# Creiamo la copia dell'array su cui lavorare.
	var new_tiles: Array[int] = tiles.duplicate()

	# Scambia la tile con il blank.
	new_tiles[blank_index] = new_tiles[tile_index]
	new_tiles[tile_index] = 0

	return BoardState.new(new_tiles, size)


# ---------------------------------------------------------------------------
# Verifica soluzione
# ---------------------------------------------------------------------------

func is_solved() -> bool:
	# "==" su Array in GDScript confronta i valori elemento per elemento,
	# NON i riferimenti — diverso da C# dove == su List<T> confronterebbe
	# i riferimenti. Equivalente a SequenceEqual() in LINQ.
	return tiles == BoardState.solved(size).tiles


# ---------------------------------------------------------------------------
# Clone
# ---------------------------------------------------------------------------

# Ritorna una copia indipendente di questo stato.
# _init() già chiama duplicate() internamente, quindi è sufficiente.
func clone() -> BoardState:
	return BoardState.new(tiles, size)


# ---------------------------------------------------------------------------
# Utilità
# ---------------------------------------------------------------------------

# Ritorna la dimensione totale della griglia (N*N).
func cell_count() -> int:
	return size * size


# Ritorna il valore della tile alle coordinate (row, col).
func get_tile(row: int, col: int) -> int:
	return tiles[row * size + col]


# Converte un indice piatto in coordinate (riga, colonna).
# Ritorna un Dictionary — GDScript non ha tuple, ma Dictionary è leggero.
# Uso: var pos = state.index_to_coords(7)  →  pos.row, pos.col
func index_to_coords(index: int) -> Dictionary:
	return { "row": index / size, "col": index % size }


# ---------------------------------------------------------------------------
# Debug
# ---------------------------------------------------------------------------

# Godot chiama _to_string() quando usi print(oggetto) — equivalente di ToString() in C#.
# Produce una griglia leggibile:
#   1  2  3  4
#   5  6  7  8
#   9 10 11 12
#  13 14 15  _
func _to_string() -> String:
	var result: String = ""
	for i in range(size * size):
		var val: int = tiles[i]
		# Allineamento a 2 caratteri per griglia leggibile.
		if val == 0:
			result += " _"
		elif val < 10:
			result += " %d" % val
		else:
			result += "%d" % val
		# Vai a capo dopo ogni riga.
		# "(i + 1) % size == 0" è vero all'ultimo elemento di ogni riga.
		if (i + 1) % size == 0:
			result += "\n"
	return result
