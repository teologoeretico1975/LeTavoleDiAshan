# scripts/tools/GenerateChapter04.gd
#
# EditorScript che genera data/levels/chapter_04.json.
# Come eseguire: apri nell'editor Godot, premi Run (▶) o Ctrl+Shift+X.
#
# Strategia duale:
#   1. MD-increasing (istantaneo): tenta MAX_MD_RETRIES percorsi per ogni target.
#      Se riesce → livello generato, metodo loggato come "MD".
#   2. Fallback random+A* (lento): random walk non-inverse + PuzzleSolver.count_optimal_moves().
#      Usato solo se MD-increasing esaurisce i retry (ceiling raggiunto).
#      MAX_NODES_FALLBACK alto (1M) perché è generazione offline una-tantum.
#      Metodo loggato come "A*" con contatore tentativi e tempo ms.
#
# Range 40-52: il ceiling MD-increasing è confermato >42 dal Capitolo III,
# quindi alcuni valori alti potrebbero richiedere il fallback A*.
# Questo script sonda il confine esatto e lo riporta nel log.

@tool
extends EditorScript


const GRID_SIZE          := 4
const TOTAL_LEVELS       := 20
const MAX_MD_RETRIES     := 50_000   # retry MD-increasing per valore target
const MAX_NODES_FALLBACK := 1_000_000  # limite A* per il fallback (offline OK)
const MAX_FALLBACK_ATTEMPTS := 500    # tentativi scramble+A* per valore target

# 20 valori ordinati su range 40-52 (13 valori distinti → 7 raddoppiati).
const TARGETS: Array[int] = [
	40, 41, 41, 42, 43, 43, 44, 45, 45, 46,
	47, 47, 48, 49, 49, 50, 51, 51, 52, 52,
]

const OUTPUT_PATH := "res://data/levels/chapter_04.json"


func _run() -> void:
	print("=".repeat(40))
	print("Generazione Capitolo IV — 20 livelli 4x4 (MD-increasing + fallback A*)")
	print("=".repeat(40))

	var solver   := PuzzleSolver.new()
	var rng      := RandomNumberGenerator.new()
	rng.seed = 0x41534134  # "ASA4" in ASCII

	var goal_pos: Array[Vector2i] = _compute_goal_positions()

	# Statistiche globali per il riepilogo finale.
	var md_count:      int = 0
	var astar_count:   int = 0
	var skip_count:    int = 0
	var first_ceiling: int = -1  # primo valore non raggiungibile via MD-increasing

	var levels: Array = []
	var level_num: int = 0

	for i: int in TARGETS.size():
		var target: int = TARGETS[i]
		var t0: int = Time.get_ticks_msec()

		# --- Tentativo 1: MD-increasing ---
		var md_state := _try_md_increasing(target, goal_pos, rng)
		if md_state != null:
			var elapsed: int = Time.get_ticks_msec() - t0
			level_num += 1
			levels.append(_make_level(level_num, target, md_state))
			print("  [%d/%d] MD  optimal=%d  (%d ms)" % [level_num, TOTAL_LEVELS, target, elapsed])
			md_count += 1
			continue

		# MD-increasing ha fallito: segna il ceiling se è la prima volta.
		if first_ceiling == -1 or target < first_ceiling:
			first_ceiling = target
		print("  [---]     MD=%d ceiling raggiunto — provo fallback A*..." % target)

		# --- Tentativo 2: random scramble + A* ---
		var astar_result := _try_astar_fallback(target, solver, rng)
		var elapsed: int = Time.get_ticks_msec() - t0

		if astar_result == null:
			print("  [SKIP]    MD=%d — fallback A* esaurito (%d tentativi, %d ms)" \
				% [target, MAX_FALLBACK_ATTEMPTS, elapsed])
			skip_count += 1
			continue

		level_num += 1
		levels.append(_make_level(level_num, target, astar_result.state))
		print("  [%d/%d] A*  optimal=%d  (%d tentativi A*, %d ms)" \
			% [level_num, TOTAL_LEVELS, target, astar_result.attempts, elapsed])
		astar_count += 1

	# --- Riepilogo ---
	print("-".repeat(40))
	print("Metodi usati: MD-increasing=%d  A*-fallback=%d  saltati=%d" \
		% [md_count, astar_count, skip_count])

	if first_ceiling == -1:
		print("MD-increasing raggiungibile su tutto il range 40-52.")
		print("Ceiling MD-increasing confermato > 52 su 4x4.")
	else:
		print("Ceiling MD-increasing 4x4: primo fallimento a MD=%d" % first_ceiling)
		if astar_count > 0:
			print("Fallback A* ha coperto i valori mancanti.")
		if skip_count > 0:
			print("ATTENZIONE: %d valori non coperti nemmeno dal fallback A*." % skip_count)
			print("Per Capitoli V-VI: considerare pre-generazione offline Python/C#.")

	if levels.is_empty():
		push_error("Nessun livello generato — JSON non scritto.")
		return

	var data := {
		"chapter":   4,
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
# Metodo 1: MD-increasing
# ---------------------------------------------------------------------------

func _try_md_increasing(target_md: int, goal_pos: Array[Vector2i], rng: RandomNumberGenerator) -> BoardState:
	for _attempt: int in range(MAX_MD_RETRIES):
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

		var gp: Vector2i  = goal_pos[tile_val - 1]
		var dist_before: int = abs(tr - gp.x) + abs(tc - gp.y)
		var dist_after: int  = abs(br - gp.x) + abs(bc - gp.y)

		if dist_after == dist_before + 1:
			result.append(tile_idx)

	return result


# ---------------------------------------------------------------------------
# Metodo 2: random scramble + A*
# ---------------------------------------------------------------------------

class FallbackResult:
	extends RefCounted
	var state:    BoardState
	var attempts: int


func _try_astar_fallback(target: int, solver: PuzzleSolver, rng: RandomNumberGenerator) -> FallbackResult:
	for attempt: int in range(MAX_FALLBACK_ATTEMPTS):
		var n_moves: int = _scramble_length_for(target, rng)
		var state := _scramble(n_moves, rng)

		var opt: int = solver.count_optimal_moves(state, MAX_NODES_FALLBACK)
		if opt == target:
			var r := FallbackResult.new()
			r.state    = state
			r.attempts = attempt + 1
			return r

	return null


func _scramble_length_for(target: int, rng: RandomNumberGenerator) -> int:
	# Per optimal ~40-52, scramble più lungo aumenta la probabilità di centrare il range.
	# Euristico: optimal ≈ scramble * 0.55-0.65 in media sul 4x4.
	if target >= 50:
		return rng.randi_range(90, 140)
	elif target >= 45:
		return rng.randi_range(75, 110)
	else:
		return rng.randi_range(60, 90)


func _scramble(n_moves: int, rng: RandomNumberGenerator) -> BoardState:
	var state := BoardState.solved(GRID_SIZE)
	var prev_blank: int = -1

	for _i: int in range(n_moves):
		var valid := state.valid_moves()
		if prev_blank != -1:
			valid.erase(prev_blank)
		prev_blank = state.blank_index
		state = state.apply_move(valid[rng.randi_range(0, valid.size() - 1)])

	return state


# ---------------------------------------------------------------------------
# Helper comuni
# ---------------------------------------------------------------------------

func _make_level(id: int, optimal: int, state: BoardState) -> Dictionary:
	return {
		"id":            id,
		"title":         "Livello IV-%d" % id,
		"initial_state": Array(state.tiles),
		"optimal_moves": optimal,
		"par_moves":     roundi(optimal * 1.4),
		"good_moves":    optimal * 2,
	}


func _compute_goal_positions() -> Array[Vector2i]:
	var pos: Array[Vector2i] = []
	for i: int in range(GRID_SIZE * GRID_SIZE - 1):
		pos.append(Vector2i(i / GRID_SIZE, i % GRID_SIZE))
	return pos
