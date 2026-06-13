# scripts/tools/GenerateChapter05.gd
#
# EditorScript che genera data/levels/chapter_05.json.
# Come eseguire: apri nell'editor Godot, premi Run (▶) o Ctrl+Shift+X.
#
# Strategia: MD-increasing pura (range 44-52 confermato sicuro dal Capitolo IV).
# Nessun fallback A*: tutti i valori nel range sono raggiungibili entro pochi secondi.
# Il ceiling MD-increasing su 4x4 è confermato >52 (probe: 52 ~3s, 55 timeout a 30s).

@tool
extends EditorScript


const GRID_SIZE    := 4
const TOTAL_LEVELS := 20
const MAX_RETRIES  := 50_000

# Range 44-52 = 9 valori distinti → 20 livelli con 2 valori triplicati (48, 50)
# e i restanti 7 raddoppiati.
const TARGETS: Array[int] = [
	44, 44, 45, 45, 46, 46, 47, 47, 48, 48,
	48, 49, 49, 50, 50, 50, 51, 51, 52, 52,
]

const OUTPUT_PATH := "res://data/levels/chapter_05.json"


func _run() -> void:
	print("=".repeat(40))
	print("Generazione Capitolo V — 20 livelli 4x4 (MD-increasing)")
	print("=".repeat(40))

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x41534135  # "ASA5" in ASCII

	var goal_pos: Array[Vector2i] = _compute_goal_positions()
	var unreachable: Array[int]   = []
	var levels: Array             = []
	var level_num: int            = 0

	for i: int in TARGETS.size():
		var target: int = TARGETS[i]
		var t0: int     = Time.get_ticks_msec()

		var state := _try_md_increasing(target, goal_pos, rng)
		var elapsed: int = Time.get_ticks_msec() - t0

		if state == null:
			if target not in unreachable:
				unreachable.append(target)
			print("  [SKIP] MD=%d — irraggiungibile (%d retry, %d ms)" \
				% [target, MAX_RETRIES, elapsed])
			continue

		level_num += 1
		var par_moves:  int = roundi(target * 1.4)
		var good_moves: int = target * 2

		levels.append({
			"id":            level_num,
			"title":         "Livello V-%d" % level_num,
			"initial_state": Array(state.tiles),
			"optimal_moves": target,
			"par_moves":     par_moves,
			"good_moves":    good_moves,
		})

		print("  [%d/%d] optimal=%d  (%d ms)" % [level_num, TOTAL_LEVELS, target, elapsed])

	print("-".repeat(40))
	if unreachable.is_empty():
		print("MD-increasing raggiungibile su tutto il range 44-52.")
	else:
		print("VALORI NON RAGGIUNGIBILI: %s" % str(unreachable))

	if levels.is_empty():
		push_error("Nessun livello generato — JSON non scritto.")
		return

	var data := {
		"chapter":   5,
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


func _try_md_increasing(target_md: int, goal_pos: Array[Vector2i], rng: RandomNumberGenerator) -> BoardState:
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

		var gp: Vector2i     = goal_pos[tile_val - 1]
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
