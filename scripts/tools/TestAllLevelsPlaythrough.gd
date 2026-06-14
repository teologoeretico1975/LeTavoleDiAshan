# scripts/tools/TestAllLevelsPlaythrough.gd
#
# Test automatico di playthrough su tutti i livelli di tutti i capitoli.
# Istanzia GameBoard (la scena completa, non solo BoardState) e simula 50 mosse
# per ogni livello, verificando dopo ogni mossa che _tile_nodes rimanga
# sincronizzato con BoardState.
#
# COME ESEGUIRE:
#   Apri questo file nell'editor Godot → File → Run (o Ctrl+Shift+X).
#
# PERCHÉ NON USA L'AUTOLOAD:
#   Gli EditorScript girano nel contesto dell'editor, non nel gioco — i singleton
#   Autoload (LevelLoader, GameManager…) non esistono in questo contesto.
#   Creiamo una istanza locale di LevelLoader con .new() e la usiamo direttamente.
#
# PERCHÉ NON USA _ready() NÉ _try_move():
#   - _ready() chiamerebbe LevelLoader come Autoload (non disponibile) e
#     set_anchors_preset() che richiede un Control nel SceneTree.
#   - _try_move() lancia un Tween che non ticka mai senza un frame loop.
#   Usiamo invece setup_for_test() e apply_move_instant() — stessa logica,
#   senza dipendenze dal runtime del gioco.

extends EditorScript


const MOVES_PER_LEVEL: int = 50
const RNG_SEED: int = 42      # seed fisso → risultati riproducibili tra esecuzioni


func _run() -> void:
	# Istanza locale di LevelLoader — non l'Autoload, solo il suo script.
	# Funziona perché get_level() e get_chapter_info() non dipendono da altri Autoload.
	var loader: Node = load("res://scripts/managers/level_loader.gd").new()
	var board_scene: PackedScene = load("res://scenes/game/GameBoard.tscn")

	var total:  int   = 0
	var passed: int   = 0
	var failed: Array = []

	for chapter: int in range(1, 7):
		var info: Dictionary = loader.get_chapter_info(chapter)
		if info.is_empty():
			print("Cap%d: JSON non trovato, skip." % chapter)
			continue

		var level_count: int = info["level_count"]
		print("Capitolo %d — %d livelli, griglia %dx%d" \
			% [chapter, level_count, info["grid_size"], info["grid_size"]])

		for level_id: int in range(1, level_count + 1):
			total += 1

			var level_data: Dictionary = loader.get_level(chapter, level_id)
			if level_data.is_empty():
				failed.append("Cap%d-Lv%d: dati non trovati" % [chapter, level_id])
				continue

			var grid_size: int = int(level_data["grid_size"])
			var raw: Array = level_data["initial_state"]
			var tiles: Array[int] = []
			for v in raw:
				tiles.append(int(v))

			# Istanzia la scena completa — include Panel, Label, _tile_nodes, _board_container.
			# Non aggiungiamo al SceneTree: add_child() sui nodi figli funziona in memoria.
			var board: GameBoard = board_scene.instantiate()
			board.setup_for_test(tiles, grid_size)

			var rng := RandomNumberGenerator.new()
			rng.seed = RNG_SEED

			var level_ok := true
			for move_num: int in range(MOVES_PER_LEVEL):
				var valid: Array = board._state.valid_moves()
				# Sceglie una mossa valida casuale — come rng.Next() % list.Count in C#.
				var chosen: int = valid[rng.randi() % valid.size()]
				board.apply_move_instant(chosen)

				var err: String = _check_invariants(board, grid_size)
				if err != "":
					failed.append("Cap%d-Lv%d mossa %d: %s" % [chapter, level_id, move_num + 1, err])
					level_ok = false
					break   # passa al livello successivo senza bloccare l'intero test

			# free() immediato — nel contesto EditorScript non ci sono frame,
			# quindi queue_free() non verrebbe mai eseguito.
			board.free()

			if level_ok:
				passed += 1

	loader.free()

	# Riepilogo finale
	print("\n=== TestAllLevelsPlaythrough ===")
	print("%d / %d livelli passati." % [passed, total])
	if failed.is_empty():
		print("Tutti OK — nessuna desincronizzazione rilevata.")
	else:
		print("Falliti (%d):" % failed.size())
		for entry: String in failed:
			print("  - " + entry)


# ---------------------------------------------------------------------------
# Verifica delle invarianti dopo ogni mossa
# ---------------------------------------------------------------------------
# Ritorna una stringa di errore (non vuota) se un'invariante è violata,
# oppure "" se tutto è OK.
#
# Le invarianti testano la sincronizzazione tra _tile_nodes (array di Panel)
# e _state (BoardState): il bug storico era che il blank panel rimaneva nella
# posizione fisica originale invece di aggiornarsi. Controllare etichette e
# posizioni dopo ogni mossa copre quella classe di regressioni.

func _check_invariants(board: GameBoard, grid_size: int) -> String:
	var n: int = grid_size * grid_size

	# 1. Numero di nodi corretto
	if board._tile_nodes.size() != n:
		return "_tile_nodes.size()=%d (atteso %d)" % [board._tile_nodes.size(), n]

	# 2. Nessun elemento null
	for i: int in n:
		if board._tile_nodes[i] == null:
			return "_tile_nodes[%d] è null" % i

	# 3. Le posizioni corrispondono alle celle di griglia attese.
	# _refresh_tiles() le ricalcola sempre tutte da zero: se non viene chiamata,
	# o viene chiamata con indici sbagliati, questa invariante fallisce.
	var tile_size: float  = GameBoard.TILE_SIZE
	var tile_gap:  float  = GameBoard.TILE_GAP
	for i: int in n:
		var row: int = i / grid_size
		var col: int = i % grid_size
		var expected := Vector2(col * (tile_size + tile_gap), row * (tile_size + tile_gap))
		var actual: Vector2 = (board._tile_nodes[i] as Panel).position
		if not actual.is_equal_approx(expected):
			return "_tile_nodes[%d] è a %s ma atteso %s" % [i, actual, expected]

	# 4. Nessuna posizione duplicata tra i Panel (nessuna sovrapposizione visiva).
	# Ridondante con l'invariante 3 se le posizioni sono corrette, ma utile come
	# check indipendente nel caso l'invariante 3 avesse un bug nel calcolo atteso.
	var seen_positions: Dictionary = {}
	for i: int in n:
		var pos: Vector2 = (board._tile_nodes[i] as Panel).position
		var key: String  = "%d,%d" % [int(pos.x), int(pos.y)]
		if seen_positions.has(key):
			return "posizione %s occupata da _tile_nodes[%d] e [%d]" \
				% [key, seen_positions[key], i]
		seen_positions[key] = i

	# 5. Le etichette corrispondono ai valori in BoardState.
	# Questa è la sincronizzazione logica fondamentale: il pannello alla posizione i
	# deve mostrare il valore che BoardState dice essere in posizione i.
	for i: int in n:
		var val: int   = board._state.tiles[i]
		var panel: Panel = board._tile_nodes[i] as Panel

		if val == 0:
			if panel.visible:
				return "posizione %d: blank (val=0) ma panel visibile" % i
		else:
			if not panel.visible:
				return "posizione %d: val=%d ma panel invisibile" % [i, val]
			var label: Label = panel.get_node("Label") as Label
			if label.text != str(val):
				return "posizione %d: Label.text='%s' ma _state.tiles[%d]=%d" \
					% [i, label.text, i, val]

	return ""
