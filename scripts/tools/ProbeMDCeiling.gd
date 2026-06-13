# scripts/tools/ProbeMDCeiling.gd
#
# EditorScript di diagnostica: sonda il ceiling MD-increasing su 4x4
# per una serie di valori target, con timeout per evitare attese eccessive.
#
# Come eseguire: apri nell'editor Godot, premi Run (▶) o Ctrl+Shift+X.
# Output: tabella con target MD, tempo impiegato (ms), raggiungibile sì/no.

@tool
extends EditorScript


const GRID_SIZE     := 4
const TIMEOUT_MS    := 30_000  # 30 secondi per target

const PROBE_TARGETS: Array[int] = [55, 60, 65, 70, 75]


func _run() -> void:
	print("=".repeat(50))
	print("Probe MD-increasing ceiling — 4x4")
	print("Timeout per target: %d s" % (TIMEOUT_MS / 1000))
	print("=".repeat(50))
	print("%-10s  %-14s  %s" % ["Target MD", "Tempo", "Raggiungibile"])
	print("-".repeat(50))

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x50524F42  # "PROB" in ASCII

	var goal_pos: Array[Vector2i] = _compute_goal_positions()

	for target: int in PROBE_TARGETS:
		var t0: int = Time.get_ticks_msec()
		var found := _probe(target, goal_pos, rng, t0)
		var elapsed: int = Time.get_ticks_msec() - t0

		if found == null:
			print("%-10d  %-14s  NO (timeout)" % [target, "TROPPO LENTO"])
		else:
			print("%-10d  %-14s  SI" % [target, "%d ms" % elapsed])

	print("=".repeat(50))


# Tenta MD-increasing verso target_md con timeout.
# Ritorna lo stato trovato, oppure null se il timeout scade prima.
func _probe(target_md: int, goal_pos: Array[Vector2i], rng: RandomNumberGenerator, t0: int) -> BoardState:
	while true:
		if Time.get_ticks_msec() - t0 >= TIMEOUT_MS:
			return null

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

	return null  # mai raggiunto, ma GDScript richiede return path completo


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
