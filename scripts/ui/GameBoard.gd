# scripts/ui/GameBoard.gd
#
# Controller della scena GameBoard.tscn.
# Costruisce la griglia di tile proceduralmente in _ready(), gestisce i click
# e delega tutta la logica del puzzle a BoardState (scripts/core/).
#
# NOTE PER CHI VIENE DA C#/WPF:
#   - "extends Control" = questo nodo è un elemento UI, come UserControl in WPF.
#   - Tutto ciò che costruiamo qui in codice si potrebbe fare anche nell'editor
#     visuale di Godot — ma crearlo via codice è più leggibile e versionabile.
#   - Non c'è un file .xaml separato: la struttura dei nodi figli è definita
#     direttamente in _ready(), o nel file .tscn (che è il corrispettivo del .xaml).

class_name GameBoard
extends Control


# ---------------------------------------------------------------------------
# Parametri configurabili dall'editor
# ---------------------------------------------------------------------------

@export var chapter: int = 1
@export var level_id: int = 1


# ---------------------------------------------------------------------------
# Costanti di layout e palette
# ---------------------------------------------------------------------------

const TILE_SIZE: float = 120.0
const TILE_GAP: float = 10.0

# Dimensione griglia: derivata dai dati del livello in _load_level().
var _grid_size: int = 3

# Palette Capitolo I — "La Soglia"
# Color() accetta stringhe esadecimali "rrggbb" o "rrggbbaa" — come Color.FromArgb() in C#.
const COL_BG        := Color("1a1000")  # sfondo scuro quasi-nero con tono caldo
const COL_TILE      := Color("c9a227")  # oro/bronzo per le tile
const COL_TILE_TEXT := Color("1a1000")  # testo scuro sul fondo dorato


# ---------------------------------------------------------------------------
# Stato
# ---------------------------------------------------------------------------

# BoardState è immutabile: ogni mossa produce un nuovo oggetto.
# Teniamo un riferimento all'oggetto corrente — come una variabile puntatore in C#.
var _state: BoardState

# Array di Panel, uno per posizione nella griglia (0..8 per un 3x3).
# INVARIANTE: _tile_nodes[i] è sempre il nodo visivo per la posizione board i.
# Manteniamo questo invariante facendo swap dopo ogni mossa animata.
var _tile_nodes: Array

# Riferimento al container dei tile, usato per il flash di risoluzione.
var _board_container: Control

# Blocca l'input mentre un'animazione è in corso — evita di accodare mosse.
var _is_animating: bool = false


# ---------------------------------------------------------------------------
# Inizializzazione
# ---------------------------------------------------------------------------

func _ready() -> void:
	# PRESET_FULL_RECT = ancora questo nodo ai quattro bordi del genitore,
	# riempiendo tutto lo schermo. Equivalente di Width="*" Height="*" in WPF Grid.
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_setup_background()

	_state = _load_level(chapter, level_id)

	_build_board()
	_refresh_tiles()


# ---------------------------------------------------------------------------
# Caricamento livello da JSON
# ---------------------------------------------------------------------------

# Legge data/levels/chapter_XX.json e ritorna il BoardState del livello richiesto.
# In caso di errore (file mancante, JSON malformato, id non trovato) ritorna un
# fallback hardcoded così il gioco non si blocca mai.
#
# NOTE PER CHI VIENE DA C#:
#   - FileAccess.open() ritorna null se il file non esiste — non lancia eccezioni.
#     In C# useresti try/catch su File.ReadAllText(); qui controlli null ad ogni passo.
#   - JSON.parse_string() ritorna Variant (può essere Dictionary, Array, o null).
#     Devi verificare il tipo con "is" prima di usarlo.
#   - I numeri in un JSON parsato diventano FLOAT in GDScript, non int.
#     Occorre castare esplicitamente con int(v).
func _load_level(p_chapter: int, p_level_id: int) -> BoardState:
	var path := "res://data/levels/chapter_%02d.json" % p_chapter

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("GameBoard: %s non trovato — uso fallback hardcoded." % path)
		return _fallback_state()

	var text  := file.get_as_text()
	file.close()

	# parse_string ritorna null se il testo non è JSON valido.
	var data = JSON.parse_string(text)
	if data == null or not data is Dictionary:
		push_warning("GameBoard: JSON malformato in %s — uso fallback." % path)
		return _fallback_state()

	# data["levels"] è un Array di Dictionary — equivale a List<Dictionary> in C#.
	# .get(key, default) è il null-safe accessor: come dict.GetValueOrDefault() in C#.
	# grid_size viene letto dai metadati del JSON, non hardcoded.
	var json_grid_size: int = int(data.get("grid_size", 3))

	var levels: Array = data.get("levels", [])
	for level_data in levels:
		if int(level_data.get("id", -1)) != p_level_id:
			continue

		var raw: Array = level_data.get("initial_state", [])
		if raw.size() != json_grid_size * json_grid_size:
			push_warning("GameBoard: initial_state ha %d elementi (attesi %d)." \
				% [raw.size(), json_grid_size * json_grid_size])
			return _fallback_state()

		var tiles: Array[int] = []
		for v in raw:
			tiles.append(int(v))

		_grid_size = json_grid_size
		return BoardState.new(tiles, _grid_size)

	push_warning("GameBoard: livello id=%d non trovato in %s." % [p_level_id, path])
	return _fallback_state()


# Stato di emergenza: [1,2,3,4,5,6,7,0,8] — 1 mossa dalla soluzione.
# Usato solo se il JSON non è disponibile o è corrotto.
func _fallback_state() -> BoardState:
	return BoardState.solved(_grid_size).apply_move(7)


func _setup_background() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	# Ancora il ColorRect a tutto il genitore — come Background="..." sul root in WPF.
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


# ---------------------------------------------------------------------------
# Costruzione della griglia
# ---------------------------------------------------------------------------

func _build_board() -> void:
	var board_px: float = _grid_size * TILE_SIZE + (_grid_size - 1) * TILE_GAP

	_board_container = Control.new()
	_board_container.name = "BoardContainer"

	# Centra il container usando anchor = 0.5 + offset negativo di metà dimensione.
	# In Godot 4, anchor definisce il punto di riferimento nel genitore (0=sinistra, 1=destra).
	# offset_left/right/top/bottom sono distanze dal punto di ancoraggio.
	# Equivalente di HorizontalAlignment="Center" VerticalAlignment="Center" in WPF.
	_board_container.anchor_left   = 0.5
	_board_container.anchor_top    = 0.5
	_board_container.anchor_right  = 0.5
	_board_container.anchor_bottom = 0.5
	_board_container.offset_left   = -board_px / 2.0
	_board_container.offset_top    = -board_px / 2.0
	_board_container.offset_right  =  board_px / 2.0
	_board_container.offset_bottom =  board_px / 2.0

	add_child(_board_container)

	_tile_nodes = []
	for i: int in _grid_size * _grid_size:
		var row: int = i / _grid_size
		var col: int = i % _grid_size
		var tile := _make_tile(i)
		# position è relativa al genitore (BoardContainer), partendo da (0,0) in alto a sinistra.
		tile.position = Vector2(col * (TILE_SIZE + TILE_GAP), row * (TILE_SIZE + TILE_GAP))
		_board_container.add_child(tile)
		_tile_nodes.append(tile)


func _make_tile(board_index: int) -> Panel:
	# Panel = contenitore con sfondo stilizzabile — come un Border in WPF.
	var panel := Panel.new()
	panel.name = "Tile%d" % board_index
	panel.size = Vector2(TILE_SIZE, TILE_SIZE)

	# MOUSE_FILTER_STOP = questo nodo consuma gli eventi mouse e non li passa al genitore.
	# Equivalente di IsHitTestVisible="True" + e.Handled=true in WPF.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# StyleBoxFlat = background colorato con angoli arrotondati.
	# In Godot lo stile visivo è separato dal nodo — come ControlTemplate in WPF.
	# add_theme_stylebox_override() applica lo stile solo a questo nodo, non globalmente.
	var style := StyleBoxFlat.new()
	style.bg_color = COL_TILE
	style.corner_radius_top_left     = 10
	style.corner_radius_top_right    = 10
	style.corner_radius_bottom_left  = 10
	style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", style)

	# Label centrata dentro il Panel.
	var label := Label.new()
	label.name = "Label"
	# PRESET_FULL_RECT ancora la Label a tutti e quattro i bordi del Panel genitore.
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 52)
	label.add_theme_color_override("font_color", COL_TILE_TEXT)
	# MOUSE_FILTER_IGNORE = la Label non intercetta eventi mouse; li passa al Panel padre.
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

	# Passa il panel stesso (non l'indice) così _on_tile_input può ricercarne la
	# posizione corrente in _tile_nodes al momento del click — l'indice originale
	# non è affidabile dopo gli swap che avvengono ad ogni mossa.
	panel.gui_input.connect(_on_tile_input.bind(panel))

	return panel


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_tile_input(event: InputEvent, panel: Panel) -> void:
	if _is_animating:
		return

	if not event is InputEventMouseButton:
		return

	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return

	# Ricerca la posizione corrente del panel in _tile_nodes — necessario perché
	# i panel vengono scambiati nell'array dopo ogni mossa: l'indice originale
	# catturato al momento della creazione non è più valido dopo il primo swap.
	_try_move(_tile_nodes.find(panel))


func _try_move(tile_index: int) -> void:
	# "not in" = !list.Contains() in C# — controlla se tile_index NON è tra le mosse valide.
	if tile_index not in _state.valid_moves():
		return

	var blank_index: int = _state.blank_index
	_is_animating = true

	# target_pos: dove il tile si deve spostare (la posizione attuale del blank).
	# Entrambi i nodi sono figli di _board_container, quindi position è nello stesso spazio.
	var target_pos: Vector2 = _tile_nodes[blank_index].position

	# Tween: anima la proprietà "position" del nodo tile da dove è ora a target_pos.
	# create_tween() crea un Tween collegato al ciclo di vita di questo nodo —
	# equivalente di un DispatcherTimer o Storyboard in WPF, ma più semplice.
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUART)  # curva di decelerazione, tipo ease-out cubica
	tween.tween_property(_tile_nodes[tile_index], "position", target_pos, 0.12)

	# tween_callback() esegue una funzione al termine dell'animazione.
	# "func():" è una lambda anonima — come "() => { ... }" in C#.
	tween.tween_callback(func() -> void:
		# Applichiamo la mossa DOPO l'animazione per mantenere la coerenza:
		# durante il tween _state è ancora quello vecchio, così valid_moves() è stabile.
		_state = _state.apply_move(tile_index)

		# Scambia i riferimenti nell'array per mantenere l'invariante:
		# _tile_nodes[i] = nodo visivo per la posizione board i.
		# Dopo la mossa, il tile che era in tile_index è ora in blank_index e viceversa.
		var tmp: Panel = _tile_nodes[tile_index]
		_tile_nodes[tile_index] = _tile_nodes[blank_index]
		_tile_nodes[blank_index] = tmp

		_refresh_tiles()
		_is_animating = false

		if _state.is_solved():
			_play_solve_flash()
	)


# ---------------------------------------------------------------------------
# Aggiornamento visivo
# ---------------------------------------------------------------------------

func _refresh_tiles() -> void:
	for i: int in _grid_size * _grid_size:
		var val: int = _state.tiles[i]
		var panel: Panel = _tile_nodes[i]
		var label: Label = panel.get_node("Label")

		# Riposiziona sempre il panel alla cella di griglia corrispondente a i.
		# Questo è necessario perché il blank panel non viene mai animato dal tween
		# (solo la tile cliccata si muove), quindi senza questa riga rimarrebbe
		# fisicamente nella posizione di partenza e risulterebbe sovrapposto
		# alla tile successiva che lo rimpiazza.
		var row: int = i / _grid_size
		var col: int = i % _grid_size
		panel.position = Vector2(col * (TILE_SIZE + TILE_GAP), row * (TILE_SIZE + TILE_GAP))

		if val == 0:
			# La casella vuota è invisibile — il "buco" nella griglia.
			panel.visible = false
		else:
			panel.visible = true
			label.text = str(val)


# ---------------------------------------------------------------------------
# Animazione di risoluzione
# ---------------------------------------------------------------------------

func _play_solve_flash() -> void:
	# Overlay luminoso dorato che compare e svanisce sopra tutta la board.
	# Creiamo il nodo a runtime e lo distruggiamo al termine — come un AdornerLayer in WPF.
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.85, 0.1, 0.0)  # giallo-oro, alfa iniziale = 0 (invisibile)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE  # non blocca i click sotto
	# Ancora il flash a tutto il BoardContainer (non all'intera schermata).
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_container.add_child(flash)

	# Sequenza: fade in → fade out → rimuovi il nodo.
	# tween_property() su "color:a" anima solo il canale alfa del Color.
	# Il ":" nella stringa della proprietà è sintassi di Godot per accedere a sotto-proprietà
	# — equivalente di animare Canvas.Opacity in WPF.
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.6, 0.18)
	tween.tween_property(flash, "color:a", 0.0, 0.40)
	# queue_free() rimuove il nodo dal albero alla fine del frame — come Dispose() in C#.
	# Passarlo direttamente come Callable funziona perché è un metodo dell'oggetto flash.
	tween.tween_callback(flash.queue_free)
