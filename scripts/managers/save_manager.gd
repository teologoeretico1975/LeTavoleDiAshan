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


# ---------------------------------------------------------------------------
# API pubblica
# ---------------------------------------------------------------------------

# Registra il risultato di una partita completata.
# Calcola le stelle confrontando moves_used con le soglie nel JSON del livello.
# Salva solo se è un miglioramento (più stelle, o stesse stelle con meno mosse).
# Scrive su disco immediatamente dopo ogni aggiornamento.
#
# Esempio d'uso:
#   SaveManager.save_level_result(1, 3, 14)
func save_level_result(p_chapter: int, p_level_id: int, p_moves_used: int) -> void:
	var level_data: Dictionary = _get_level_data_from_loader(p_chapter, p_level_id)
	if level_data.is_empty():
		push_warning("SaveManager: dati non trovati per capitolo=%d id=%d." \
			% [p_chapter, p_level_id])
		return

	var stars := _compute_stars(p_moves_used, level_data)
	var prev: Variant = get_level_progress(p_chapter, p_level_id)

	# Non sovrascrivere se il risultato precedente è migliore.
	# "Migliore" = più stelle; a parità di stelle, meno mosse.
	if prev != null:
		var prev_stars: int = prev.get("stars", 0)
		var prev_best:  int = prev.get("best_moves", INF)
		if prev_stars > stars:
			return
		if prev_stars == stars and prev_best <= p_moves_used:
			return

	_set_progress(p_chapter, p_level_id, {
		"completed":  true,
		"stars":      stars,
		"best_moves": p_moves_used,
	})
	_save_to_disk()


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
