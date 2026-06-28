# scripts/managers/daily_puzzle_manager.gd
#
# Autoload/singleton: genera e gestisce il puzzle giornaliero.
#
# Il puzzle del giorno è deterministico dalla data: stesso seed → stesso stato
# per tutti i giocatori in tutto il mondo nello stesso giorno.
# Seed = anno * 10000 + mese * 100 + giorno  (es. 20261128)
#
# Difficoltà: MD-increasing con target 27 mosse (buon equilibrio per tutti i cap).
# La stessa logica usata dai generatori GenerateChapter*.gd.

extends Node


const GRID_SIZE := 4
const TARGET_MD := 27


# ---------------------------------------------------------------------------
# API pubblica
# ---------------------------------------------------------------------------

# Seed deterministico per la data odierna.
func get_today_seed() -> int:
	var d := Time.get_date_dict_from_system()
	return int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])


# BoardState del puzzle di oggi. Sempre lo stesso all'interno di una giornata.
func get_today_puzzle() -> BoardState:
	var rng := RandomNumberGenerator.new()
	rng.seed = get_today_seed()
	var goal_pos := _compute_goal_positions()
	return _generate_md_increasing(TARGET_MD, goal_pos, rng)


# True se il giocatore ha già completato il puzzle odierno.
func is_completed_today() -> bool:
	var saver: Node = get_node_or_null("/root/SaveManager")
	if saver == null:
		return false
	var record: Dictionary = saver.get_daily_record()
	if record.is_empty():
		return false
	return record.get("date", "") == _today_string_iso() and record.get("completed", false)


# Segna il puzzle odierno come completato con il numero di mosse usate.
func mark_completed_today(p_moves: int) -> void:
	var saver: Node = get_node_or_null("/root/SaveManager")
	if saver != null:
		saver.save_daily_record(_today_string_iso(), p_moves)


# Recupera le mosse usate oggi (0 se non completato).
func get_today_moves() -> int:
	var saver: Node = get_node_or_null("/root/SaveManager")
	if saver == null:
		return 0
	var record: Dictionary = saver.get_daily_record()
	if record.get("date", "") != _today_string_iso():
		return 0
	return int(record.get("moves", 0))


# Data odierna localizzata, es. "28 Giu 2026" / "Jun 28, 2026" / "28 jun 2026".
func get_today_date_string() -> String:
	var d := Time.get_date_dict_from_system()
	var day   := int(d["day"])
	var month := int(d["month"])
	var year  := int(d["year"])

	var locale: String = "it"
	var saver: Node = get_node_or_null("/root/SaveManager")
	if saver != null:
		locale = saver.get_language()

	const MONTHS_IT: Array[String] = [
		"","Gen","Feb","Mar","Apr","Mag","Giu","Lug","Ago","Set","Ott","Nov","Dic"
	]
	const MONTHS_EN: Array[String] = [
		"","Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"
	]
	const MONTHS_ES: Array[String] = [
		"","ene","feb","mar","abr","may","jun","jul","ago","sep","oct","nov","dic"
	]

	match locale:
		"en":
			return "%s %d, %d" % [MONTHS_EN[month], day, year]
		"es":
			return "%d %s %d" % [day, MONTHS_ES[month], year]
		_:
			return "%d %s %d" % [day, MONTHS_IT[month], year]


# ---------------------------------------------------------------------------
# Generazione MD-increasing (stessa logica dei GenerateChapter*.gd)
# ---------------------------------------------------------------------------

func _generate_md_increasing(target_md: int, goal_pos: Array[Vector2i], rng: RandomNumberGenerator) -> BoardState:
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

	push_error("DailyPuzzleManager: impossibile generare il puzzle per seed=%d" % rng.seed)
	return BoardState.solved(GRID_SIZE).apply_move(3)


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
		var tile_idx: int  = tr * GRID_SIZE + tc
		var tile_val: int  = state.tiles[tile_idx]
		if tile_val == 0:
			continue
		var gp: Vector2i   = goal_pos[tile_val - 1]
		var dist_before: int = abs(tr - gp.x) + abs(tc - gp.y)
		var dist_after:  int = abs(br - gp.x) + abs(bc - gp.y)
		if dist_after == dist_before + 1:
			result.append(tile_idx)

	return result


func _compute_goal_positions() -> Array[Vector2i]:
	var pos: Array[Vector2i] = []
	for i: int in range(GRID_SIZE * GRID_SIZE - 1):
		pos.append(Vector2i(i / GRID_SIZE, i % GRID_SIZE))
	return pos


# ---------------------------------------------------------------------------
# Helper data
# ---------------------------------------------------------------------------

func _today_string_iso() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]
