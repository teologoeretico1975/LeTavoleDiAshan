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

const SAVE_PATH := "user://save.bin"

# Chiave AES-256 derivata via SHA-256 dalla stringa qui sotto.
# Hardcoded per necessità (è un gioco offline single-player), ma sufficiente
# a rendere il file opaco a qualsiasi editor o tool di analisi.
# Non modificare questa costante dopo il rilascio: i save esistenti diventerebbero
# illeggibili e i giocatori perderebbero il progresso.
const _SAVE_KEY := "Ash4n_T4v0l3_K3y_2026_r7x9z2q_v1"

# Soglie stelle: moves_used <= par_moves → 3★, <= good_moves → 2★, altrimenti 1★.
# (0★ = non completato, non salvato qui — viene gestito da completed:false)
const STARS_3 := "par_moves"
const STARS_2 := "good_moves"

# Chiave radice nel JSON per il saldo monete — separata dalla struttura
# capitolo/livello per semplicità di accesso.
const COINS_KEY      := "__coins__"
const HINTS_USED_KEY := "__hints_used__"
const LANGUAGE_KEY   := "__language__"
const VOLUME_KEY     := "__music_volume__"
const SFX_VOLUME_KEY := "__sfx_volume__"
const DIARIES_KEY    := "__diaries_seen__"
const DAILY_KEY      := "__daily_record__"

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
	_migrate_diaries()
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


# ---------------------------------------------------------------------------
# Volume musica
# ---------------------------------------------------------------------------

func get_music_volume() -> float:
	return float(_data.get(VOLUME_KEY, 0.8))


func has_volume_saved() -> bool:
	return _data.has(VOLUME_KEY)


func set_music_volume(p_linear: float) -> void:
	_data[VOLUME_KEY] = p_linear
	_save_to_disk()


# Volume SFX
# ---------------------------------------------------------------------------

func get_sfx_volume() -> float:
	return float(_data.get(SFX_VOLUME_KEY, 0.8))


func has_sfx_volume_saved() -> bool:
	return _data.has(SFX_VOLUME_KEY)


func set_sfx_volume(p_linear: float) -> void:
	_data[SFX_VOLUME_KEY] = p_linear
	_save_to_disk()


# Azzera tutto il progresso salvato (utile per debug/test).
func reset_all() -> void:
	_data = {}
	_save_to_disk()


# ---------------------------------------------------------------------------
# API diari
# ---------------------------------------------------------------------------

# Ritorna true se il diario del livello è già stato mostrato al giocatore.
# La chiave usata internamente è "chapter_level", es. "1_1".
func is_diary_seen(p_chapter: int, p_level: int) -> bool:
	var key := "%d_%d" % [p_chapter, p_level]
	var seen: Array = _data.get(DIARIES_KEY, [])
	return key in seen


# Segna il diario come visto. Chiama _save_to_disk() per persistenza immediata.
func mark_diary_seen(p_chapter: int, p_level: int) -> void:
	var key := "%d_%d" % [p_chapter, p_level]
	if not _data.has(DIARIES_KEY):
		_data[DIARIES_KEY] = []
	var seen: Array = _data[DIARIES_KEY]
	if key not in seen:
		seen.append(key)
	_save_to_disk()


# ---------------------------------------------------------------------------
# Migrazione diari (eseguita una volta sola al primo avvio post-aggiornamento)
# ---------------------------------------------------------------------------

# Se __diaries_seen__ non esiste ancora nel salvataggio, marca tutti i livelli
# già completati come "diario già visto". Questo evita che i giocatori con
# salvataggi precedenti all'introduzione del sistema diari ricevano popup
# retroattivi su livelli già completati decine di volte.
# L'assenza della chiave DIARIES_KEY è il marker di "non ancora migrato".
func _migrate_diaries() -> void:
	if _data.has(DIARIES_KEY):
		return
	_data[DIARIES_KEY] = []
	for c_key: String in _data:
		if c_key.begins_with("_"):
			continue  # salta __coins__, __hints_used__, ecc.
		var chapter_data = _data[c_key]
		if not chapter_data is Dictionary:
			continue
		for l_key: String in chapter_data:
			var entry = chapter_data[l_key]
			if entry is Dictionary and entry.get("completed", false):
				_data[DIARIES_KEY].append("%s_%s" % [c_key, l_key])
	_save_to_disk()


# ---------------------------------------------------------------------------
# API Daily Puzzle
# ---------------------------------------------------------------------------

# Ritorna il record del Daily Puzzle: { "date": "2026-06-28", "moves": 47, "completed": true }
# o un Dictionary vuoto se non è mai stato completato.
func get_daily_record() -> Dictionary:
	return _data.get(DAILY_KEY, {})


# Salva il completamento del Daily Puzzle per la data specificata.
# Sovrascrive sempre l'eventuale record precedente — teniamo solo il giorno corrente.
func save_daily_record(p_date: String, p_moves: int) -> void:
	_data[DAILY_KEY] = { "date": p_date, "moves": p_moves, "completed": true }
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
		return

	# Prova prima la lettura cifrata (formato corrente).
	var text := _read_encrypted()

	# Fallback plain-text: migrazione da save.json legacy (pre-cifratura).
	# Il percorso plain è controllato solo se quello cifrato fallisce.
	if text.is_empty():
		text = _read_plain_legacy()
		if not text.is_empty():
			# Save trovato in chiaro: re-salva cifrato ed elimina il legacy.
			push_warning("SaveManager: save legacy in chiaro rilevato — migrazione a formato cifrato.")
			_save_to_disk_text(text)
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))

	if text.is_empty():
		return

	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_warning("SaveManager: %s corrotto — progresso azzerato." % SAVE_PATH)
		return

	_data = parsed


# Legge il file cifrato con AES-256. Ritorna stringa vuota in caso di errore
# (file assente, chiave errata, dati corrotti).
func _read_encrypted() -> String:
	var file := FileAccess.open_encrypted_with_pass(SAVE_PATH, FileAccess.READ, _SAVE_KEY)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


# Legge il vecchio save.json in chiaro — usato una sola volta per la migrazione.
func _read_plain_legacy() -> String:
	const LEGACY_PATH := "user://save.json"
	if not FileAccess.file_exists(LEGACY_PATH):
		return ""
	var file := FileAccess.open(LEGACY_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _save_to_disk() -> void:
	_save_to_disk_text(JSON.stringify(_data))


# Scrive p_text cifrato su SAVE_PATH.
func _save_to_disk_text(p_text: String) -> void:
	var file := FileAccess.open_encrypted_with_pass(SAVE_PATH, FileAccess.WRITE, _SAVE_KEY)
	if file == null:
		push_error("SaveManager: impossibile scrivere su %s." % SAVE_PATH)
		return
	file.store_string(p_text)
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
