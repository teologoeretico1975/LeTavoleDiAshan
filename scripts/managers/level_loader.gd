# scripts/managers/level_loader.gd
#
# Autoload/singleton: carica i JSON dei capitoli e fornisce i dati dei livelli
# a chiunque nel progetto tramite get_level() e get_chapter_info().
#
# COME FUNZIONA UN AUTOLOAD:
#   Godot istanzia questo nodo UNA VOLTA sola all'avvio e lo mantiene vivo per
#   tutta la sessione. È accessibile globalmente con il nome "LevelLoader"
#   (quello scelto in Project Settings → Autoload). Equivalente di una classe
#   statica con stato condiviso in C#, ma legata al ciclo di vita dell'app.
#
# REGISTRAZIONE (da fare una volta nell'editor):
#   Project → Project Settings → Globals → Autoload
#   Path: scripts/managers/level_loader.gd   Name: LevelLoader   → Add
#
# NOTE PER CHI VIENE DA C#:
#   - extends Node (non RefCounted) perché è un nodo dell'albero di scena.
#   - Il campo _cache è un Dictionary<int, Dictionary> — mappa capitolo → dati JSON.
#   - Non c'è un costruttore pubblico: _ready() fa le veci di OnStartup().

extends Node


# ---------------------------------------------------------------------------
# Cache in memoria
# ---------------------------------------------------------------------------

# Dizionario capitolo_numero → dati grezzi del JSON (come Dictionary in C#).
# Evita di rileggere il file ogni volta che viene richiesto un livello.
# Viene popolato on-demand: il capitolo 3 non viene mai caricato se non richiesto.
var _cache: Dictionary = {}

# Cache del file chapters.json: { "1": "Il Risveglio", … }
# Caricata la prima volta che serve, poi tenuta in memoria.
var _chapter_titles: Dictionary = {}


# ---------------------------------------------------------------------------
# API pubblica
# ---------------------------------------------------------------------------

# Ritorna i dati completi di un livello come Dictionary con le chiavi:
#   id, title, initial_state, optimal_moves, par_moves, good_moves, grid_size
# Ritorna null se il capitolo non esiste o l'id non è trovato.
#
# Esempio d'uso:
#   var level = LevelLoader.get_level(1, 3)
#   if level == null: return
#   var state = level["initial_state"]   # Array[int]
func get_level(p_chapter: int, p_level_id: int) -> Dictionary:
	var chapter_data := _load_chapter(p_chapter)
	if chapter_data.is_empty():
		return {}

	var levels: Array = chapter_data.get("levels", [])
	for level_data: Dictionary in levels:
		if int(level_data.get("id", -1)) == p_level_id:
			# Inietta grid_size nei dati del livello così il chiamante non deve
			# prenderlo separatamente dalla radice del JSON.
			var result := level_data.duplicate()
			result["grid_size"] = int(chapter_data.get("grid_size", 3))
			return result

	push_warning("LevelLoader: livello id=%d non trovato nel capitolo %d." \
		% [p_level_id, p_chapter])
	return {}


# Ritorna i metadati del capitolo:
#   chapter, grid_size, level_count
# Ritorna dict vuoto se il capitolo non esiste.
#
# Esempio d'uso:
#   var info = LevelLoader.get_chapter_info(2)
#   print(info["level_count"])   # es. 20
func get_chapter_info(p_chapter: int) -> Dictionary:
	var chapter_data := _load_chapter(p_chapter)
	if chapter_data.is_empty():
		return {}

	return {
		"chapter":     int(chapter_data.get("chapter", p_chapter)),
		"grid_size":   int(chapter_data.get("grid_size", 3)),
		"level_count": (chapter_data.get("levels", []) as Array).size(),
	}


# Ritorna il titolo narrativo di un capitolo (es. "Il Risveglio" per capitolo 1).
# Legge data/chapters/chapters.json la prima volta, poi usa la cache.
# Ritorna "Capitolo N" come fallback se il file non esiste o la chiave manca.
func get_chapter_title(p_chapter: int) -> String:
	if _chapter_titles.is_empty():
		_load_chapter_titles()
	var key := str(p_chapter)
	return _chapter_titles.get(key, "Capitolo %d" % p_chapter)


# ---------------------------------------------------------------------------
# Caricamento e cache
# ---------------------------------------------------------------------------

# Carica il JSON del capitolo se non già in cache, altrimenti ritorna
# il valore cached. Ritorna un Dictionary vuoto in caso di errore.
#
# "on-demand with memoization" — stesso pattern di un lazy-loaded singleton
# o di un ConcurrentDictionary.GetOrAdd() in C#.
func _load_chapter(p_chapter: int) -> Dictionary:
	if _cache.has(p_chapter):
		return _cache[p_chapter]

	var path := "res://data/levels/chapter_%02d.json" % p_chapter

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("LevelLoader: %s non trovato." % path)
		return {}

	var text := file.get_as_text()
	file.close()

	var data = JSON.parse_string(text)
	if data == null or not data is Dictionary:
		push_warning("LevelLoader: JSON malformato in %s." % path)
		return {}

	_cache[p_chapter] = data
	return data


func _load_chapter_titles() -> void:
	const PATH := "res://data/chapters/chapters.json"
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("LevelLoader: %s non trovato." % PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data == null or not data is Dictionary:
		push_warning("LevelLoader: JSON malformato in %s." % PATH)
		return
	_chapter_titles = data
