# scripts/tools/GenerateChapter01.gd
#
# EditorScript che genera data/levels/chapter_01.json.
# Come eseguire: apri nell'editor Godot, premi Run (▶) o Ctrl+Shift+X.
#
# Strategia:
#   - Genera stati 3x3 con random walk non-inverse di lunghezze variabili.
#   - Risolve ogni stato con PuzzleSolver (A* senza limite di nodi — 3x3 è veloce).
#   - Raccoglie il primo stato trovato per ogni valore optimal in [5, 16].
#   - Assegna titoli in ordine crescente di optimal_moves e scrive il JSON.
#
# NOTA: il range 5-16 (12 valori) copre esattamente i 12 titoli.
# Il file pre-esistente è stato generato analiticamente; questo script
# sovrascrive con stati trovati via random walk (risultato diverso ad ogni seed).

@tool
extends EditorScript


const GRID_SIZE      := 3
const OPTIMAL_MIN    := 5
const OPTIMAL_MAX    := 16   # 12 valori: 5..16
const MAX_ATTEMPTS   := 5000 # tentativi massimi prima di rinunciare

const TITLES: Array[String] = [
	"La Soglia",
	"Polvere Prima",
	"Il Primo Frammento",
	"Il Sigillo Spezzato",
	"Voci di Pietra",
	"Il Corridoio Sommerso",
	"Frammenti di un Nome",
	"La Lampada Spenta",
	"Ciò Che Rimase",
	"Il Margine del Foglio",
	"Eco Senza Origine",
	"La Prima Tavola",
]

const OUTPUT_PATH := "res://data/levels/chapter_01.json"


func _run() -> void:
	print("=".repeat(40))
	print("Generazione Capitolo I — 12 livelli 3x3")
	print("=".repeat(40))

	var solver := PuzzleSolver.new()
	var rng    := RandomNumberGenerator.new()
	# Seed fisso: ogni esecuzione produce lo stesso JSON.
	# Cambia il seed per esplorare stati alternativi.
	rng.seed = 0x4153414E  # "ASAN" in ASCII

	# found: Dictionary[int, BoardState] — un solo stato per optimal_moves.
	# In GDScript i Dictionary non sono tipizzati — come Dictionary<int, BoardState> in C#.
	var found: Dictionary = {}

	var attempt := 0
	while found.size() < 12 and attempt < MAX_ATTEMPTS:
		attempt += 1

		# Lunghezza dello scramble: varia in base a quanti valori mancano ancora.
		# Per valori alti (>12) serve uno scramble più lungo.
		var n_moves: int = _scramble_length_for(found, rng)
		var state  := _scramble(n_moves, rng)
		var result := solver.solve(state)

		if result.aborted or not result.solvable:
			continue

		var opt: int = result.optimal_moves
		if opt >= OPTIMAL_MIN and opt <= OPTIMAL_MAX and not found.has(opt):
			found[opt] = state
			print("  [%d/%d] optimal=%d trovato (tentativo %d)" \
				% [found.size(), 12, opt, attempt])

	# Ordina per optimal_moves crescente.
	var sorted_optima: Array = found.keys()
	sorted_optima.sort()

	if sorted_optima.size() < 12:
		var missing: Array = []
		for v in range(OPTIMAL_MIN, OPTIMAL_MAX + 1):
			if not found.has(v):
				missing.append(v)
		push_warning("Valori optimal mancanti dopo %d tentativi: %s" \
			% [MAX_ATTEMPTS, str(missing)])
		print("ATTENZIONE: JSON scritto con %d livelli (mancano: %s)" \
			% [sorted_optima.size(), str(missing)])

	var levels: Array = []
	for i in sorted_optima.size():
		var opt:   int        = sorted_optima[i]
		var state: BoardState = found[opt]

		# roundi() = Math.Round() con ritorno int — come (int)Math.Round() in C#.
		var par_moves:  int = roundi(opt * 1.4)
		var good_moves: int = opt * 2

		# Array(state.tiles) converte Array[int] tipizzato in Array non tipizzato,
		# necessario perché JSON.stringify non accetta typed arrays.
		levels.append({
			"id":            i + 1,
			"title":         TITLES[i],
			"initial_state": Array(state.tiles),
			"optimal_moves": opt,
			"par_moves":     par_moves,
			"good_moves":    good_moves,
		})

	var data := {
		"chapter":   1,
		"grid_size": GRID_SIZE,
		"levels":    levels,
	}

	# JSON.stringify(data, "\t") = JsonSerializer.Serialize con indentazione in C#.
	var json_text: String = JSON.stringify(data, "\t")

	# FileAccess.open con WRITE crea il file se non esiste, lo sovrascrive se esiste.
	# Ritorna null se il path non è accessibile (es. directory inesistente).
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Impossibile aprire in scrittura: %s" % OUTPUT_PATH)
		return

	file.store_string(json_text)
	file.close()

	print("Scritto: %s  (%d livelli)" % [OUTPUT_PATH, levels.size()])
	print("=".repeat(40))


# ---------------------------------------------------------------------------
# Helper: lunghezza scramble adattiva
# ---------------------------------------------------------------------------

# Aumenta la lunghezza dello scramble quando i valori alti (>12) non sono ancora trovati.
func _scramble_length_for(found: Dictionary, rng: RandomNumberGenerator) -> int:
	var missing_high := false
	for v in range(13, OPTIMAL_MAX + 1):
		if not found.has(v):
			missing_high = true
			break

	if missing_high:
		# Scramble lungo: più probabile produrre optimal > 12.
		return rng.randi_range(20, 35)
	else:
		# Scramble moderato: copre il range 5-12.
		return rng.randi_range(8, 20)


# ---------------------------------------------------------------------------
# Helper: random walk non-inverse
# ---------------------------------------------------------------------------

func _scramble(n_moves: int, rng: RandomNumberGenerator) -> BoardState:
	var state := BoardState.solved(GRID_SIZE)
	var prev_blank: int = -1

	for _i in range(n_moves):
		var valid := state.valid_moves()
		# Rimuovi la mossa che annullerebbe la precedente (stessa logica dei test).
		if prev_blank != -1:
			valid.erase(prev_blank)
		prev_blank = state.blank_index
		state = state.apply_move(valid[rng.randi_range(0, valid.size() - 1)])

	return state
