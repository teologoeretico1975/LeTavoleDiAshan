# scripts/tools/GenerateChapter02.gd
#
# EditorScript che genera data/levels/chapter_02.json.
# Come eseguire: apri nell'editor Godot, premi Run (▶) o Ctrl+Shift+X.
#
# Strategia: MD-increasing garantita
#   - Parte dallo stato risolto (MD=0).
#   - Applica esattamente K passi, ognuno scelto tra le mosse che aumentano MD di 1.
#   - Garantisce optimal_moves = K per la doppia disuguaglianza MD ≤ optimal ≤ path_length.
#   - Nessuna chiamata A*: ogni livello viene generato in O(K) tempo, istantaneo.
#
# Verifica offline (BFS Python): MD-increasing su 4x4 raggiunge almeno MD=34,
# quindi l'intero range 15-28 è coperto senza fallback.

@tool
extends EditorScript


const GRID_SIZE    := 4
const TOTAL_LEVELS := 20

# 20 valori ordinati: ogni valore compare N volte = N livelli con quel valore.
# Distribuzione: singolo agli estremi, doppio ai valori centrali.
const TARGETS: Array[int] = [
	15, 16, 17, 18, 18, 19, 20, 20, 21, 21,
	22, 22, 23, 23, 24, 24, 25, 26, 27, 28,
]

const OUTPUT_PATH := "res://data/levels/chapter_02.json"


func _run() -> void:
	print("=".repeat(40))
	print("Generazione Capitolo II — 20 livelli 4x4 (MD-increasing)")
	print("=".repeat(40))

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x41534132  # "ASA2" in ASCII — seed fisso per riproducibilità

	# Precalcola le posizioni obiettivo di ogni tile per il calcolo MD.
	var goal_pos: Array[Vector2i] = _compute_goal_positions()

	var levels: Array = []
	for i: int in TARGETS.size():
		var target_md: int = TARGETS[i]
		var state := _generate_md_increasing(target_md, goal_pos, rng)

		var par_moves:  int = roundi(target_md * 1.4)
		var good_moves: int = target_md * 2

		levels.append({
			"id":            i + 1,
			"title":         "Livello II-%d" % (i + 1),
			"initial_state": Array(state.tiles),
			"optimal_moves": target_md,
			"par_moves":     par_moves,
			"good_moves":    good_moves,
		})

		print("  [%d/%d] optimal=%d  stato=%s" \
			% [i + 1, TOTAL_LEVELS, target_md, _short_repr(state)])

	var data := {
		"chapter":   2,
		"grid_size": GRID_SIZE,
		"levels":    levels,
	}

	var json_text: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Impossibile aprire in scrittura: %s" % OUTPUT_PATH)
		return

	file.store_string(json_text)
	file.close()

	print("Scritto: %s  (%d livelli)" % [OUTPUT_PATH, levels.size()])
	print("=".repeat(40))


# ---------------------------------------------------------------------------
# MD-increasing: genera uno stato con Manhattan Distance = target_md
# partendo dallo stato risolto con passi che aumentano MD di 1 ad ogni mossa.
# ---------------------------------------------------------------------------

func _generate_md_increasing(target_md: int, goal_pos: Array[Vector2i], rng: RandomNumberGenerator) -> BoardState:
	# Un percorso casuale può finire in un dead end (nessuna mossa aumenta MD).
	# In quel caso si riparte da zero: ogni tentativo è O(K), quindi retry è istantaneo.
	for _attempt: int in range(10_000):
		var state := BoardState.solved(GRID_SIZE)
		var stuck := false

		for _step: int in range(target_md):
			var moves := _moves_increasing_md(state, goal_pos)
			if moves.is_empty():
				stuck = true
				break
			state = state.apply_move(moves[rng.randi_range(0, moves.size() - 1)])

		if not stuck:
			return state

	push_error("MD-increasing: impossibile raggiungere MD=%d in 10000 tentativi." % target_md)
	return BoardState.solved(GRID_SIZE)


# Ritorna gli indici di mossa (blank_index del tile da spostare) che aumentano MD di 1.
func _moves_increasing_md(state: BoardState, goal_pos: Array[Vector2i]) -> Array[int]:
	var result: Array[int] = []
	var blank: int = state.blank_index
	var br: int    = blank / GRID_SIZE
	var bc: int    = blank % GRID_SIZE

	for delta: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var tr: int = br + delta.x
		var tc: int = bc + delta.y
		if tr < 0 or tr >= GRID_SIZE or tc < 0 or tc >= GRID_SIZE:
			continue

		var tile_idx: int = tr * GRID_SIZE + tc
		var tile_val: int = state.tiles[tile_idx]
		if tile_val == 0:
			continue  # non dovrebbe mai capitare, blank è già noto

		# Distanza corrente del tile dalla sua posizione obiettivo.
		var gp: Vector2i = goal_pos[tile_val - 1]
		var dist_before: int = abs(tr - gp.x) + abs(tc - gp.y)
		# Dopo lo scambio il tile si troverà in (br, bc).
		var dist_after: int = abs(br - gp.x) + abs(bc - gp.y)

		if dist_after == dist_before + 1:
			# Questa mossa sposta il tile lontano dal goal: MD aumenta di 1.
			result.append(tile_idx)

	return result


# ---------------------------------------------------------------------------
# Helper: posizioni obiettivo per ogni tile (tile 1..N*N-1)
# ---------------------------------------------------------------------------

func _compute_goal_positions() -> Array[Vector2i]:
	# goal_pos[i] = posizione (riga, col) che tile (i+1) deve occupare nello stato risolto.
	# Tile 1 → indice 0 → (0,0), Tile 2 → indice 1 → (0,1), ecc.
	var pos: Array[Vector2i] = []
	for i: int in range(GRID_SIZE * GRID_SIZE - 1):
		pos.append(Vector2i(i / GRID_SIZE, i % GRID_SIZE))
	return pos


# ---------------------------------------------------------------------------
# Helper: rappresentazione breve per il log
# ---------------------------------------------------------------------------

func _short_repr(state: BoardState) -> String:
	var parts: PackedStringArray = []
	for v: int in state.tiles:
		parts.append(str(v))
	return "[" + ",".join(parts) + "]"
