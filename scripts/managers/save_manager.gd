# scripts/managers/save_manager.gd
#
# Autoload/singleton: salva e carica il progresso del giocatore su disco.
#
# REGISTRAZIONE (da fare una volta nell'editor):
#   Project → Project Settings → Globals → Autoload
#   Path: scripts/managers/save_manager.gd   Name: SaveManager   → Add
#
# FORMATO DEL FILE DI SALVATAGGIO (user://save.json):
#   {
#     "1": {                    ← chiave = chapter (stringa, JSON vuole stringhe come chiavi)
#       "1": {                  ← chiave = level_id
#         "completed": true,
#         "stars": 3,
#         "best_moves": 7
#       }
#     }
#   }
#
# PERCHÉ user://:
#   res:// punta al pacchetto del gioco (read-only su export).
#   user:// punta alla cartella dati dell'utente sul dispositivo:
#     Windows  → %APPDATA%\Godot\app_userdata\<nome_progetto>\
#     Android  → storage privato dell'app
#   Sopravvive agli aggiornamenti del gioco — come AppData in C#/WPF.
#
# NOTE PER CHI VIENE DA C#:
#   - FileAccess.open(..., WRITE) tronca e riscrive il file intero — come
#     File.WriteAllText() in C#. Non c'è append incrementale.
#   - JSON.stringify() serializza un Variant (Dictionary, Array…) in stringa JSON.
#     È il corrispettivo di JsonSerializer.Serialize() in System.Text.Json.
#   - Le chiavi di un Dictionary JSON sono sempre stringhe: str(chapter) non int.

extends Node


# ---------------------------------------------------------------------------
# Costanti
# ---------------------------------------------------------------------------

const SAVE_PATH := "user://save.json"

# Soglie stelle: moves_used <= par_moves → 3★, <= good_moves → 2★, altrimenti 1★.
# (0★ = non completato, non salvato qui — viene gestito da completed:false)
const STARS_3 := "par_moves"
const STARS_2 := "good_moves"

# Chiave radice nel JSON per il saldo monete — separata dalla struttura
# capitolo/livello per semplicità di accesso.
const COINS_KEY      := "__coins__"
const HINTS_USED_KEY := "__hints_used__"
const LANGUAGE_KEY   := "__language__"

# Monete assegnate per stella al primo raggiungimento di quel record.
const COINS_PER_STAR := 10

# I primi N hint sono gratuiti (contatore persistente su tutto il gioco,
# non per livello — incentiva l'esplorazione senza penalizzare i nuovi giocatori).
const FREE_HINTS_TOTAL := 3

# Costo in monete per ogni hint dopo aver esaurito quelli gratuiti.
const HINT_COST := 20


# ---------------------------------------------------------------------------
# Stato in memoria
# ---------------------------------------------------------------------------

# Struttura: { chapter_str: { level_id_str: { completed, stars, best_moves } } }
# Caricata una volta in _ready(), poi tenuta in sync con il disco ad ogni salvataggio.
var _data: Dictionary = {}


# ---------------------------------------------------------------------------
# Inizializzazione
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load_from_disk()
	# La lingua viene applicata da LocalizationManager (autoload successivo).


# ---------------------------------------------------------------------------
# API pubblica
# ---------------------------------------------------------------------------

# Registra il risultato di una partita completata.
# Calcola le stelle confrontando moves_used con le soglie nel JSON del livello.
# Salva solo se è un miglioramento (più stelle, o stesse stelle con meno mosse).
# Assegna monete solo se le nuove stelle superano il record precedente.
# Scrive su disco immediatamente dopo ogni aggiornamento.
#
# Ritorna le monete assegnate in questa partita (0 se nessun record battuto).
#
# Esempio d'uso:
#   var coins_earned = SaveManager.save_level_result(1, 3, 14)
func save_level_result(p_chapter: int, p_level_id: int, p_moves_used: int) -> int:
	var level_data: Dictionary = _get_level_data_from_loader(p_chapter, p_level_id)
	if level_data.is_empty():
		push_warning("SaveManager: dati non trovati per capitolo=%d id=%d." \
			% [p_chapter, p_level_id])
		return 0

	var stars := _compute_stars(p_moves_used, level_data)
	var prev: Variant = get_level_progress(p_chapter, p_level_id)
	var prev_stars: int = 0 if prev == null else int(prev.get("stars", 0))

	# Non sovrascrivere se il risultato precedente è migliore.
	# "Migliore" = più stelle; a parità di stelle, meno mosse.
	if prev != null:
		var prev_best: int = prev.get("best_moves", INF)
		if prev_stars > stars:
			return 0
		if prev_stars == stars and prev_best <= p_moves_used:
			return 0

	_set_progress(p_chapter, p_level_id, {
		"completed":  true,
		"stars":      stars,
		"best_moves": p_moves_used,
	})

	# Assegna monete solo se il record stelle è migliorato.
	# Formula: nuove_stelle * COINS_PER_STAR (non il delta) — semplicità > precisione.
	var coins_earned: int = 0
	if stars > prev_stars:
		coins_earned = stars * COINS_PER_STAR
		add_coins(coins_earned)

	_save_to_disk()
	return coins_earned


# ---------------------------------------------------------------------------
# API monete
# ---------------------------------------------------------------------------

# Ritorna il saldo monete corrente del giocatore.
func get_coins() -> int:
	return int(_data.get(COINS_KEY, 0))


# Aggiunge monete al saldo. Chiamato internamente da save_level_result
# e potenzialmente da future fonti (daily puzzle, achievement).
func add_coins(p_amount: int) -> void:
	_data[COINS_KEY] = get_coins() + p_amount
	# Nota: _save_to_disk() è chiamato dal chiamante (save_level_result) —
	# non duplichiamo la scrittura qui per evitare doppi flush.


# Sottrae monete se il saldo è sufficiente. Ritorna true se l'operazione
# è riuscita, false se il saldo sarebbe andato sotto zero (nessuna modifica).
# Chiamato quando il giocatore usa un hint o acquista un bonus.
#
# Esempio d'uso:
#   if SaveManager.spend_coins(50):
#       _activate_hint()
func spend_coins(p_amount: int) -> bool:
	var current: int = get_coins()
	if current < p_amount:
		return false
	_data[COINS_KEY] = current - p_amount
	_save_to_disk()
	return true


# Ritorna il progresso salvato per un livello, o null se mai giocato.
# Il Dictionary ha le chiavi: completed (bool), stars (int), best_moves (int).
#
# Esempio d'uso:
#   var prog = SaveManager.get_level_progress(1, 3)
#   if prog == null: print("mai giocato")
#   else: print(prog["stars"], "stelle")
func get_level_progress(p_chapter: int, p_level_id: int) -> Variant:
	var c_key := str(p_chapter)
	var l_key := str(p_level_id)
	if not _data.has(c_key):
		return null
	if not _data[c_key].has(l_key):
		return null
	return _data[c_key][l_key]


# Ritorna true se il livello è accessibile al giocatore.
# Regola: livello 1 di ogni capitolo sempre sbloccato.
#         livello N sbloccato se il livello N-1 dello stesso capitolo è completed.
#
# Esempio d'uso:
#   if SaveManager.is_level_unlocked(2, 5): ...
func is_level_unlocked(p_chapter: int, p_level_id: int) -> bool:
	if p_level_id <= 1:
		return true

	var prev: Variant = get_level_progress(p_chapter, p_level_id - 1)
	if prev == null:
		return false
	return prev.get("completed", false)


# Ritorna il progresso aggregato di un capitolo:
#   completed_levels: quanti livelli hanno completed=true
#   total_levels:     numero totale livelli del capitolo (da LevelLoader)
#   total_stars:      stelle accumulate su tutti i livelli completati
#   max_stars:        total_levels * 3 (massimo ottenibile)
#
# Esempio d'uso:
#   var p = SaveManager.get_chapter_progress(1)
#   label.text = "%d/%d livelli · %d/%d stelle" % [p.completed_levels, p.total_levels, ...]
func get_chapter_progress(p_chapter: int) -> Dictionary:
	var loader: Node = get_node_or_null("/root/LevelLoader")
	var total_levels: int = 0
	if loader != null:
		var info: Dictionary = loader.get_chapter_info(p_chapter)
		total_levels = int(info.get("level_count", 0))

	var completed_levels: int = 0
	var total_stars:      int = 0

	for lvl_id: int in range(1, total_levels + 1):
		var prog: Variant = get_level_progress(p_chapter, lvl_id)
		if prog != null and prog.get("completed", false):
			completed_levels += 1
			total_stars      += int(prog.get("stars", 0))

	return {
		"completed_levels": completed_levels,
		"total_levels":     total_levels,
		"total_stars":      total_stars,
		"max_stars":        total_levels * 3,
	}


# Capitolo 1 sempre sbloccato.
# Capitolo N sbloccato se TUTTI i livelli del capitolo N-1 sono completati.
#
# Esempio d'uso:
#   if SaveManager.is_chapter_unlocked(3): ...
func is_chapter_unlocked(p_chapter: int) -> bool:
	if p_chapter <= 1:
		return true

	var loader: Node = get_node_or_null("/root/LevelLoader")
	if loader == null:
		return false

	var info: Dictionary = loader.get_chapter_info(p_chapter - 1)
	var total: int = int(info.get("level_count", 0))
	if total == 0:
		return false

	for lvl_id: int in range(1, total + 1):
		var prog: Variant = get_level_progress(p_chapter - 1, lvl_id)
		if prog == null or not prog.get("completed", false):
			return false

	return true


# ---------------------------------------------------------------------------
# API hint
# ---------------------------------------------------------------------------

# Ritorna quanti hint gratuiti rimangono (0 se tutti esauriti).
func get_free_hints_remaining() -> int:
	var used: int = int(_data.get(HINTS_USED_KEY, 0))
	return max(0, FREE_HINTS_TOTAL - used)


# True se il prossimo hint è gratuito.
func is_hint_free() -> bool:
	return get_free_hints_remaining() > 0


# Tenta di usare un hint.
# Ordine: prima hint gratuiti, poi monete.
# Ritorna true se l'hint è stato concesso (gratis o pagato),
# false se i gratuiti sono esauriti E le monete sono insufficienti.
# In caso di false non modifica nulla.
func use_hint() -> bool:
	var free_remaining: int = get_free_hints_remaining()

	if free_remaining > 0:
		# Hint gratuito: incrementa solo il contatore, nessun addebito monete.
		_data[HINTS_USED_KEY] = int(_data.get(HINTS_USED_KEY, 0)) + 1
		_save_to_disk()
		return true

	# Hint a pagamento: tenta la sottrazione (spend_coins gestisce il caso saldo < costo).
	if spend_coins(HINT_COST):
		_data[HINTS_USED_KEY] = int(_data.get(HINTS_USED_KEY, 0)) + 1
		# spend_coins() ha già chiamato _save_to_disk() — non duplichiamo.
		return true

	# Saldo insufficiente e nessun gratuito rimasto.
	return false


# ---------------------------------------------------------------------------
# API lingua
# ---------------------------------------------------------------------------

# Ritorna il codice locale salvato (default "it" se mai impostato).
func get_language() -> String:
	return str(_data.get(LANGUAGE_KEY, "it"))


# True se l'utente ha mai scelto una lingua esplicitamente (chiave presente).
func has_language_saved() -> bool:
	return _data.has(LANGUAGE_KEY)


# Persiste la preferenza lingua. La locale viene applicata da LocalizationManager.
func set_language(p_locale: String) -> void:
	_data[LANGUAGE_KEY] = p_locale
	_save_to_disk()


# Azzera tutto il progresso salvato (utile per debug/test).
func reset_all() -> void:
	_data = {}
	_save_to_disk()


# ---------------------------------------------------------------------------
# Calcolo stelle
# ---------------------------------------------------------------------------

func _compute_stars(p_moves: int, p_level_data: Dictionary) -> int:
	var par:  int = int(p_level_data.get("par_moves",  INF))
	var good: int = int(p_level_data.get("good_moves", INF))

	if p_moves <= par:
		return 3
	if p_moves <= good:
		return 2
	return 1


# ---------------------------------------------------------------------------
# Accesso a LevelLoader (stesso pattern di GameBoard: path, non nome globale)
# ---------------------------------------------------------------------------

# Iniettato dai test per bypassare la ricerca nel node tree (non disponibile
# in EditorScript context). A runtime rimane null e si usa la ricerca per path.
# Pattern: dependency injection minimale senza toccare l'API pubblica.
var _test_loader: Node = null


# Cerca LevelLoader per path — evita riferimento al nome globale dell'Autoload
# che causerebbe errori di compilazione in contesti editor (@tool / EditorScript).
func _get_level_data_from_loader(p_chapter: int, p_level_id: int) -> Dictionary:
	var loader: Node = _test_loader if _test_loader != null \
		else get_node_or_null("/root/LevelLoader")
	if loader == null:
		push_warning("SaveManager: LevelLoader non disponibile.")
		return {}
	return loader.get_level(p_chapter, p_level_id)


# ---------------------------------------------------------------------------
# Lettura/scrittura disco
# ---------------------------------------------------------------------------

func _load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		# Prima esecuzione — nessun dato salvato, partiamo da dizionario vuoto.
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: impossibile aprire %s." % SAVE_PATH)
		return

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_warning("SaveManager: %s corrotto — progresso azzerato." % SAVE_PATH)
		return

	_data = parsed


func _save_to_disk() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: impossibile scrivere su %s." % SAVE_PATH)
		return

	# JSON.stringify con indent="\t" produce JSON leggibile — utile per debug.
	# In produzione si potrebbe usare indent="" per risparmiare byte, ma
	# il file di save sarà sempre piccolo (111 livelli × ~50 byte = ~5 KB).
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()


# ---------------------------------------------------------------------------
# Scrittura interna (mantiene la struttura annidata)
# ---------------------------------------------------------------------------

func _set_progress(p_chapter: int, p_level_id: int, p_value: Dictionary) -> void:
	var c_key := str(p_chapter)
	var l_key := str(p_level_id)
	if not _data.has(c_key):
		_data[c_key] = {}
	_data[c_key][l_key] = p_value
