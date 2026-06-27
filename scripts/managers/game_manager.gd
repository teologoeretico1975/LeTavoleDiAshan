# scripts/managers/game_manager.gd
#
# Autoload/singleton responsabile della navigazione tra scene e del passaggio
# di parametri contestuali tra di esse.
#
# PERCHÉ SERVE:
#   change_scene_to_file() distrugge la scena corrente e crea quella nuova.
#   La scena nuova non esiste ancora al momento della chiamata, quindi non è
#   possibile impostare proprietà su di essa prima che il suo _ready() giri.
#   L'Autoload sopravvive al cambio scena e funge da "blackboard" condiviso:
#   chi parte scrive i parametri qui, chi arriva li legge nel proprio _ready().
#   Equivalente di variabili statiche di Application-scope in WinForms/WPF.
#
# USO TIPICO:
#   # LevelSelect: l'utente clicca il livello 3 del capitolo 2
#   GameManager.goto_game_board(2, 3)
#
#   # GameBoard._ready(): legge i parametri scritti da LevelSelect
#   var ch  = GameManager.selected_chapter   # → 2
#   var lvl = GameManager.selected_level     # → 3

extends Node


# ---------------------------------------------------------------------------
# Parametri contestuali — scritti dal chiamante, letti dalla scena destinazione
# ---------------------------------------------------------------------------

# Capitolo e livello selezionati dall'utente. Valori default (1, 1) garantiscono
# che GameBoard sia sempre inizializzabile anche senza navigazione esplicita.
var selected_chapter: int = 1
var selected_level:   int = 1

# Scena da cui si è entrati in Settings — usata da return_from_settings().
var _settings_return_scene: String = "res://scenes/ui/MainMenu.tscn"


# ---------------------------------------------------------------------------
# Navigazione
# ---------------------------------------------------------------------------

# Imposta il contesto e carica GameBoard.
# Chiamato da LevelSelect quando l'utente tocca un livello sbloccato.
func goto_game_board(p_chapter: int, p_level: int) -> void:
	selected_chapter = p_chapter
	selected_level   = p_level
	get_tree().change_scene_to_file("res://scenes/game/GameBoard.tscn")


# Imposta il capitolo corrente e torna a LevelSelect.
# Chiamato da GameBoard (tasto ESC / pulsante "< Mappa").
func goto_level_select(p_chapter: int) -> void:
	selected_chapter = p_chapter
	get_tree().change_scene_to_file("res://scenes/ui/LevelSelect.tscn")


# Torna alla schermata di selezione capitolo.
# Chiamato da LevelSelect (pulsante "< Capitoli").
func goto_chapter_select() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/ChapterSelect.tscn")


# Torna al menu principale.
# Chiamato da ChapterSelect (pulsante "< Menu").
func goto_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")


# Entra nella schermata Settings ricordando da dove si viene.
func goto_settings(p_return_scene: String = "res://scenes/ui/MainMenu.tscn") -> void:
	_settings_return_scene = p_return_scene
	get_tree().change_scene_to_file("res://scenes/ui/Settings.tscn")


# Torna alla scena chiamante dopo aver chiuso Settings.
func return_from_settings() -> void:
	get_tree().change_scene_to_file(_settings_return_scene)
