# scripts/tools/GenerateChapter03.gd
#
# EditorScript che genera data/levels/chapter_03.json.
# Come eseguire: apri nell'editor Godot, premi Run (▶) o Ctrl+Shift+X.
#
# Strategia: MD-increasing con rilevamento del ceiling
#   - Stessa tecnica del Capitolo II (MD-increasing + retry).
#   - Per ogni valore target, se tutti i MAX_RETRIES tentativi finiscono in dead end,
#     il valore viene marcato come NON RAGGIUNGIBILE e il livello viene saltato.
#   - L'output riporta esplicitamente i valori non raggiunti: dato importante per
#     pianificare i Capitoli V-VI dove il ceiling MD-increasing potrebbe essere
#     inferiore al range desiderato.
#
# Verifica offline (BFS Python, cap 200k): MD-increasing confermata almeno fino a MD=34.
# Il range 35-42 è territorio inesplorato: questo script lo sonda in vivo.

@tool
extends EditorScript


const GRID_SIZE    := 4
const TOTAL_LEVELS := 20

# Tentativi massimi per ogni singolo valore target prima di dichiararlo irraggiungibile.
# Ogni tentativo è O(K) con K <= 42: anche 50k retry sono istantanei.
const MAX_RETRIES := 50_000

# 20 valori ordinati: ogni valore compare N volte = N livelli con quel valore.
# Range 28-42 = 15 valori distinti → 5 valori raddoppiati per arrivare a 20.
const TARGETS: Array[int] = [
	28, 29, 30, 31, 31, 32, 33, 33, 34, 35,
	35, 36, 37, 37, 38, 39, 39, 40, 41, 42,
]

const OUTPUT_PATH := "res://data/levels/chapter_03.json"


func _run() -> void:
	print("=".repeat(40))
	print("Generazione Capitolo III — 20 livelli 4x4 (MD-increasing)")
	print("=".repeat(40))

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x41534133  # "ASA3" in ASCII — seed fisso per riproducibilità

	var goal_pos: Array[Vector2i] = _compute_goal_positions()

	# Traccia i valori per cui MD-increasing si è dimostrata irraggiungibile.
	var unreachable: Array[int] = []

	var levels: Array = []
	var level_num: int = 0

	for i: int in TARGETS.size():
		var target_md: int = TARGETS[i]

		var result := _try_generate(target_md, goal_pos, rng)

		if result == null:
			# MD-increasing non ha trovato nessun percorso in MAX_RETRIES tentativi.
			if target_md not in unreachable:
				unreachable.append(target_md)
			print("  [SKIP] MD=%d — irraggiungibile via MD-increasing (%d retry esauriti)" \
				% [target_md, MAX_RETRIES])
			continue

		level_num += 1
		var par_moves:  int = roundi(target_md * 1.4)
		var good_moves: int = target_md * 2

		levels.append({
			"id":            level_num,
			"title":         "Livello III-%d" % level_num,
			"initial_state": Array(result.tiles),
			"optimal_moves": target_md,
			"par_moves":     par_moves,
			"good_moves":    good_moves,
		})

		print("  [%d/%d] optimal=%d  stato=%s" \
			% [level_num, TOTAL_LEVELS, target_md, _short_repr(result)])

	# --- Riepilogo ---
	print("-".repeat(40))
	if unreachable.is_empty():
		print("MD-increasing raggiungibile su tutto il range 28-42.")
		print("Ceiling MD-increasing confermato > 42 su 4x4.")
	else:
		print("VALORI NON RAGGIUNGIBILI via MD-increasing: %s" % str(unreachable))
		print("Ceiling MD-increasing 4x4 stimato: < %d" % unreachable.min())
		print("IMPORTANTE per Capitoli V-VI: ricalibrate i range o usate fallback offline.")

	if levels.size() < TOTAL_LEVELS:
		print("Livelli generati: %d/%d (alcuni valori saltati per ceiling)" \
			% [levels.size(), TOTAL_LEVELS])

	if levels.is_empty():
		push_error("Nessun livello generato — JSON non scritto.")
		return

	var data := {
		"chapter":   3,
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
# MD-increasing: tenta MAX_RETRIES percorsi verso target_md.
# Ritorna null se nessun percorso completo è stato trovato (ceiling raggiunto).
# ---------------------------------------------------------------------------

func _try_generate(target_md: int, goal_pos: Array[Vector2i], rng: RandomNumberGenerator) -> BoardState:
	for _attempt: int in range(MAX_RETRIES):
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

	return null


# Ritorna gli indici di mossa che aumentano MD di 1.
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
			continue

		var gp: Vector2i = goal_pos[tile_val - 1]
		var dist_before: int = abs(tr - gp.x) + abs(tc - gp.y)
		var dist_after: int  = abs(br - gp.x) + abs(bc - gp.y)

		if dist_after == dist_before + 1:
			result.append(tile_idx)

	return result


func _compute_goal_positions() -> Array[Vector2i]:
	var pos: Array[Vector2i] = []
	for i: int in range(GRID_SIZE * GRID_SIZE - 1):
		pos.append(Vector2i(i / GRID_SIZE, i % GRID_SIZE))
	return pos


func _short_repr(state: BoardState) -> String:
	var parts: PackedStringArray = []
	for v: int in state.tiles:
		parts.append(str(v))
	return "[" + ",".join(parts) + "]"
