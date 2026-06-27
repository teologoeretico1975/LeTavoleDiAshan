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

@tool
# @tool permette a questo script di essere istanziato da altri script @tool (es. EditorScript
# di test). Senza @tool, Godot crea un "placeholder" non funzionale quando uno script tool
# carica questa scena, e tutte le chiamate ai metodi falliscono a runtime.
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
const TILE_GAP: float = 3.0

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

# Dati grezzi del livello dal JSON: title, par_moves, good_moves, ecc.
# Popolato da _load_level() e usato da _setup_hud() e _on_puzzle_solved().
var _level_data: Dictionary = {}

# Contatore mosse dell'utente nella partita corrente.
var _move_count: int = 0

# Array di Control (TextureRect), uno per posizione nella griglia (0..8 per un 3x3).
# INVARIANTE: _tile_nodes[i] è sempre il nodo visivo per la posizione board i.
# Manteniamo questo invariante facendo swap dopo ogni mossa animata.
var _tile_nodes: Array

# Riferimento al container dei tile, usato per il flash di risoluzione.
var _board_container: Control

# ColorRect overlay dal .tscn — colore impostato da _set_chapter_overlay().
var _chapter_overlay: ColorRect

# Label HUD — aggiornate da _setup_hud() e durante il gioco.
var _label_title: Label
var _label_moves: Label
var _label_coins: Label
var _btn_hint: Button

# Blocca l'input mentre un'animazione è in corso — evita di accodare mosse.
var _is_animating: bool = false

# Lock permanente dopo la risoluzione del puzzle — semantica diversa da
# _is_animating (temporaneo). Impostato a true in _on_puzzle_solved() e
# mai resettato: il giocatore non deve poter continuare a muovere le tile.
var _is_solved: bool = false

# Riferimento all'overlay di fine livello — mostrato da _on_puzzle_solved().
var _level_complete_panel: Control
# Riferimento al pulsante "Avanti" — disabilitato se è l'ultimo livello.
var _btn_next: Button


# ---------------------------------------------------------------------------
# Inizializzazione
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Engine.is_editor_hint() è true quando il nodo è nell'editor (preview della scena).
	# In quel contesto LevelLoader non è disponibile e non vogliamo costruire la board.
	# Equivalente di DesignMode in WPF / [DesignerSerializationVisibility] in WinForms.
	if Engine.is_editor_hint():
		return

	# PRESET_FULL_RECT = ancora questo nodo ai quattro bordi del genitore,
	# riempiendo tutto lo schermo. Equivalente di Width="*" Height="*" in WPF Grid.
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Legge capitolo e livello da GameManager se disponibile (navigazione normale),
	# altrimenti usa gli @export della scena (test isolato nell'editor).
	# Pattern: GameManager è il chiamante runtime; @export è il fallback per l'editor.
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		chapter  = gm.selected_chapter
		level_id = gm.selected_level

	_state = _load_level(chapter, level_id)

	_chapter_overlay = get_node_or_null("ChapterOverlay") as ColorRect
	_set_chapter_overlay(chapter)

	var am: Node = get_node_or_null("/root/AudioManager")
	if am != null:
		am.fade_to_chapter(chapter)

	_build_board()
	_refresh_tiles()
	_setup_hud()
	_setup_back_button()
	_setup_hint_button()
	_build_level_complete_panel()


# Inizializza la board direttamente da dati grezzi, senza passare per LevelLoader.
# Usato dai test automatici (EditorScript) dove l'Autoload non è disponibile,
# e da qualsiasi contesto che abbia già i dati del livello pronti.
func setup_for_test(p_tiles: Array[int], p_grid_size: int) -> void:
	_grid_size = p_grid_size
	_state    = BoardState.new(p_tiles, p_grid_size)
	_build_board()
	_refresh_tiles()


# Esegue una mossa senza animazione — stessa logica della tween callback in
# _try_move(), ma sincrona. Usato dai test dove non c'è frame loop.
func apply_move_instant(tile_index: int) -> void:
	if tile_index not in _state.valid_moves():
		return
	var blank_index: int = _state.blank_index
	_state = _state.apply_move(tile_index)
	var tmp: Control = _tile_nodes[tile_index]
	_tile_nodes[tile_index] = _tile_nodes[blank_index]
	_tile_nodes[blank_index] = tmp
	_refresh_tiles()


# ---------------------------------------------------------------------------
# Caricamento livello da JSON (tramite LevelLoader)
# ---------------------------------------------------------------------------

# Chiede i dati del livello a LevelLoader (Autoload) e costruisce il BoardState.
# LevelLoader gestisce parsing, cache e warning — qui gestiamo solo la logica
# di costruzione del BoardState e il fallback visivo.
#
# NOTE PER CHI VIENE DA C#:
#   - Usiamo get_node_or_null("/root/LevelLoader") invece del nome globale diretto.
#     Motivo: gli EditorScript ricompilano i file .gd in contesto editor dove gli
#     Autoload non sono inizializzati come identificatori globali — "LevelLoader"
#     risulterebbe sconosciuto a compile-time e causerebbe un errore di parsing.
#     La ricerca per percorso ("/root/LevelLoader") è una stringa: non viene
#     risolta dal compilatore, quindi funziona in entrambi i contesti.
#   - In game context is_inside_tree() è true e il nodo esiste → funziona normalmente.
#   - In EditorScript context is_inside_tree() è false → _get_loader() ritorna null
#     e _load_level() usa il fallback. Il test usa setup_for_test() e non passa
#     mai per _load_level(), quindi non è un problema.
func _load_level(p_chapter: int, p_level_id: int) -> BoardState:
	var loader: Node = _get_loader()
	if loader == null:
		push_warning("GameBoard: LevelLoader non disponibile — usa setup_for_test() in contesto editor.")
		return _fallback_state()

	var level_data: Dictionary = loader.get_level(p_chapter, p_level_id)

	if level_data.is_empty():
		push_warning("GameBoard: dati non disponibili per capitolo=%d id=%d — uso fallback." \
			% [p_chapter, p_level_id])
		return _fallback_state()

	var json_grid_size: int = int(level_data.get("grid_size", 3))
	var raw: Array = level_data.get("initial_state", [])

	if raw.size() != json_grid_size * json_grid_size:
		push_warning("GameBoard: initial_state ha %d elementi (attesi %d)." \
			% [raw.size(), json_grid_size * json_grid_size])
		return _fallback_state()

	var tiles: Array[int] = []
	for v in raw:
		tiles.append(int(v))

	# Salva i dati completi del livello — usati da _setup_hud() (title) e
	# _on_puzzle_solved() (par_moves, good_moves per il calcolo stelle).
	_level_data  = level_data
	_grid_size   = json_grid_size
	return BoardState.new(tiles, _grid_size)


# Stato di emergenza: [1,2,3,4,5,6,7,0,8] — 1 mossa dalla soluzione.
# Usato solo se il JSON non è disponibile o è corrotto.
func _fallback_state() -> BoardState:
	return BoardState.solved(_grid_size).apply_move(7)


# Recupera il nodo LevelLoader dal percorso assoluto nell'albero di scena.
# Ritorna null se non siamo nel game tree (es. EditorScript, unit test).
# Il percorso stringa evita il riferimento diretto al nome globale dell'Autoload,
# che causa errori di compilazione nei contesti editor dove i singleton non
# sono ancora inizializzati.
func _get_loader() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/LevelLoader")


# Imposta il colore dell'overlay in base al capitolo corrente.
# Il ColorRect "ChapterOverlay" è definito nel .tscn e viene colorato a runtime.
func _set_chapter_overlay(p_chapter: int) -> void:
	if _chapter_overlay == null:
		return
	const COLORS: Array = [
		Color(0.1,  0.05, 0.0,  0.45),  # 1 — amber scuro, caldo e misterioso
		Color(0.0,  0.05, 0.15, 0.50),  # 2 — blu freddo, geometria aliena
		Color(0.08, 0.03, 0.0,  0.50),  # 3 — ambra spenta, degrado
		Color(0.0,  0.0,  0.05, 0.60),  # 4 — quasi nero, silenzio assoluto
		Color(0.0,  0.08, 0.08, 0.50),  # 5 — teal organico, presenza
		Color(0.02, 0.0,  0.08, 0.55),  # 6 — viola cosmico, orrore finale
	]
	var idx: int = clampi(p_chapter - 1, 0, COLORS.size() - 1)
	_chapter_overlay.color = COLORS[idx]


# Costruisce le label HUD (titolo e contatore mosse) sopra la griglia.
# Chiamata DOPO _load_level() perché legge _level_data["title"].
#
# NOTE PER CHI VIENE DA C#/WPF:
#   - anchor_left/right/top/bottom definiscono il punto di riferimento nel genitore
#     (0 = bordo sinistro/superiore, 1 = bordo destro/inferiore).
#   - offset_* sono distanze in pixel dal punto di ancoraggio.
#   - Label titolo: ancorata al bordo superiore-sinistro (anchor = 0,0) con margine.
#   - Label mosse: ancorata al bordo superiore-destro (anchor_left/right = 1) con
#     offset negativi per rientrare dal bordo — equivalente di Right/Top margin in WPF.
func _setup_hud() -> void:
	# Titolo del livello — sottile, in alto a sinistra.
	_label_title = Label.new()
	_label_title.name = "LabelTitle"
	_label_title.text = tr("LEVEL_%d_%d_TITLE" % [chapter, level_id])
	_label_title.add_theme_font_size_override("font_size", 22)
	_label_title.add_theme_color_override("font_color", COL_TILE)
	_label_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Position con anchor default (0,0) = offset in pixel dall'angolo superiore-sinistro.
	_label_title.position = Vector2(20.0, 20.0)
	add_child(_label_title)

	# Contatore mosse — prominente, in alto a destra.
	_label_moves = Label.new()
	_label_moves.name = "LabelMoves"
	_label_moves.text = tr("HUD_MOVES") % 0
	_label_moves.add_theme_font_size_override("font_size", 28)
	_label_moves.add_theme_color_override("font_color", COL_TILE)
	_label_moves.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label_moves.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	# Ancora al bordo destro: anchor_left = anchor_right = 1 → il punto di riferimento
	# è il bordo destro del genitore. offset negativi = rientro verso sinistra.
	_label_moves.anchor_left   = 1.0
	_label_moves.anchor_right  = 1.0
	_label_moves.anchor_top    = 0.0
	_label_moves.anchor_bottom = 0.0
	_label_moves.offset_left   = -200.0
	_label_moves.offset_right  = -20.0
	_label_moves.offset_top    = 20.0
	_label_moves.offset_bottom = 60.0
	add_child(_label_moves)

	# Saldo monete — sotto il contatore mosse, stesso lato destro.
	_label_coins = Label.new()
	_label_coins.name = "LabelCoins"
	_label_coins.add_theme_font_size_override("font_size", 20)
	_label_coins.add_theme_color_override("font_color", COL_TILE)
	_label_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label_coins.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_label_coins.anchor_left   = 1.0
	_label_coins.anchor_right  = 1.0
	_label_coins.anchor_top    = 0.0
	_label_coins.anchor_bottom = 0.0
	_label_coins.offset_left   = -200.0
	_label_coins.offset_right  = -20.0
	_label_coins.offset_top    = 62.0
	_label_coins.offset_bottom = 92.0
	add_child(_label_coins)
	_refresh_coins_label()


# Recupera SaveManager per path — stesso pattern di _get_loader().
func _get_saver() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/SaveManager")


# Aggiorna la label monete leggendo il saldo corrente da SaveManager.
# Chiamata in _setup_hud() e dopo save_level_result().
func _refresh_coins_label() -> void:
	if _label_coins == null:
		return
	var saver: Node = _get_saver()
	var coins: int = saver.get_coins() if saver != null else 0
	_label_coins.text = "✦ %d" % coins


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


func _make_tile(board_index: int) -> Control:
	var tile := TextureRect.new()
	tile.name                = "Tile%d" % board_index
	tile.size                = Vector2(TILE_SIZE, TILE_SIZE)
	tile.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	tile.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tile.mouse_filter        = Control.MOUSE_FILTER_STOP

	var tex := ResourceLoader.load("res://assets/texture/stonetile256x256.png") as Texture2D
	if tex != null:
		tile.texture = tex
	# Nessun ShaderMaterial: il PNG ha alpha nativo, Godot gestisce la trasparenza direttamente.

	# Label numero — Cinzel Decorative oro, centrata sul tile.
	var label := Label.new()
	label.name                 = "Label"
	label.position             = Vector2(0.0, 0.0)
	label.size                 = Vector2(TILE_SIZE, TILE_SIZE)
	label.custom_minimum_size  = Vector2(TILE_SIZE, TILE_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter         = Control.MOUSE_FILTER_IGNORE

	var font := ResourceLoader.load(
		"res://assets/fonts/Cinzel_Decorative/CinzelDecorative-Regular.ttf"
	) as Font
	if font != null:
		label.add_theme_font_override("font", font)

	var font_size: int = 52 if _grid_size == 3 else 36
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color",         Color(0.9,  0.78, 0.35, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0,  0.0,  0.0,  1.0))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_shadow_color",  Color(0.0,  0.0,  0.0,  0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)

	tile.add_child(label)
	tile.gui_input.connect(_on_tile_input.bind(tile))

	return tile


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_tile_input(event: InputEvent, panel: Control) -> void:
	if _is_animating or _is_solved:
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
		var tmp: Control = _tile_nodes[tile_index]
		_tile_nodes[tile_index] = _tile_nodes[blank_index]
		_tile_nodes[blank_index] = tmp

		_refresh_tiles()

		# Aggiorna contatore mosse e label HUD.
		_move_count += 1
		if _label_moves != null:
			_label_moves.text = tr("HUD_MOVES") % _move_count

		_is_animating = false

		if _state.is_solved():
			_on_puzzle_solved()
	)


# ---------------------------------------------------------------------------
# Aggiornamento visivo
# ---------------------------------------------------------------------------

func _refresh_tiles() -> void:
	for i: int in _grid_size * _grid_size:
		var val: int = _state.tiles[i]
		var panel: Control = _tile_nodes[i]
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
# Risoluzione puzzle
# ---------------------------------------------------------------------------

# Chiamata una volta sola quando _state.is_solved() diventa true.
# Ordine: lock input → salva → mostra overlay.
func _on_puzzle_solved() -> void:
	# Lock permanente: nessuna mossa ulteriore accettata.
	_is_solved = true
	_refresh_hint_button()   # disabilita il pulsante hint

	var stars := _compute_stars(_move_count)
	var coins_earned: int = 0

	var saver: Node = _get_saver()
	if saver != null:
		coins_earned = saver.save_level_result(chapter, level_id, _move_count)
		_refresh_coins_label()
	else:
		push_warning("GameBoard: SaveManager non disponibile, risultato non salvato.")

	# Flash visivo breve, poi overlay. Il flash è opzionale ma dà feedback
	# immediato prima che l'overlay appaia (il delay della reveal stelle lo giustifica).
	_play_solve_flash()
	_show_level_complete(stars, coins_earned)


# Calcola le stelle in base alle soglie del livello corrente.
# Stessa logica di SaveManager._compute_stars() — duplicata intenzionalmente
# per non dipendere dall'Autoload solo per ottenere il valore da stampare.
func _compute_stars(p_moves: int) -> int:
	var par:  int = int(_level_data.get("par_moves",  INF))
	var good: int = int(_level_data.get("good_moves", INF))
	if p_moves <= par:
		return 3
	if p_moves <= good:
		return 2
	return 1


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


# ---------------------------------------------------------------------------
# Overlay Level Complete
# ---------------------------------------------------------------------------

# Costruisce il pannello di fine livello e lo aggiunge come ultimo figlio
# (quindi in cima allo stack visivo). Rimane hidden=true fino alla risoluzione.
#
# Struttura nodi:
#   _level_complete_panel (Control, full-rect, MOUSE_FILTER_STOP)
#     ├─ ColorRect  ← sfondo semi-trasparente, blocca visivamente la board
#     └─ Panel      ← card centrata
#          └─ VBoxContainer
#               ├─ Label "Livello completato!"
#               ├─ Label stelle  ← animata da _reveal_stars()
#               ├─ Label "Mosse: X / Par: Y"
#               └─ HBoxContainer
#                    ├─ Button "< Mappa"
#                    └─ Button "Avanti →"
func _build_level_complete_panel() -> void:
	_level_complete_panel = Control.new()
	_level_complete_panel.name = "LevelCompletePanel"
	_level_complete_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# MOUSE_FILTER_STOP: l'overlay assorbe tutti gli eventi mouse.
	# Anche se _is_solved blocca _try_move(), questo impedisce qualsiasi
	# propagazione ai nodi sottostanti — doppia sicurezza.
	_level_complete_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_level_complete_panel.visible = false
	add_child(_level_complete_panel)

	# Sfondo scuro semi-trasparente — oscura la board senza nasconderla.
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_complete_panel.add_child(bg)

	# Card centrale: Panel con angoli arrotondati.
	var card := Panel.new()
	card.name = "Card"
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("1a1000")
	card_style.border_color = COL_TILE
	card_style.border_width_left   = 2
	card_style.border_width_right  = 2
	card_style.border_width_top    = 2
	card_style.border_width_bottom = 2
	card_style.corner_radius_top_left     = 16
	card_style.corner_radius_top_right    = 16
	card_style.corner_radius_bottom_left  = 16
	card_style.corner_radius_bottom_right = 16
	card.add_theme_stylebox_override("panel", card_style)
	# Centra la card: 400×300 px, ancorata al centro dello schermo.
	card.anchor_left   = 0.5
	card.anchor_right  = 0.5
	card.anchor_top    = 0.5
	card.anchor_bottom = 0.5
	card.offset_left   = -200.0
	card.offset_right  =  200.0
	card.offset_top    = -170.0
	card.offset_bottom =  170.0
	_level_complete_panel.add_child(card)

	# VBoxContainer con tutto il contenuto della card.
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 16)
	# Padding interno tramite offset — VBoxContainer non ha padding nativo.
	vbox.offset_left   =  24.0
	vbox.offset_right  = -24.0
	vbox.offset_top    =  24.0
	vbox.offset_bottom = -24.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	# Titolo.
	var lbl_title := Label.new()
	lbl_title.name = "LabelTitle"
	lbl_title.text = tr("LEVEL_COMPLETE_TITLE")
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 26)
	lbl_title.add_theme_color_override("font_color", COL_TILE)
	vbox.add_child(lbl_title)

	# Stelle — testo inizialmente vuoto, rivelato da _reveal_stars().
	var lbl_stars := Label.new()
	lbl_stars.name = "LabelStars"
	lbl_stars.text = ""
	lbl_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_stars.add_theme_font_size_override("font_size", 48)
	lbl_stars.add_theme_color_override("font_color", COL_TILE)
	vbox.add_child(lbl_stars)

	# Mosse / Par.
	var lbl_moves := Label.new()
	lbl_moves.name = "LabelMoves"
	lbl_moves.text = ""   # popolato da _show_level_complete()
	lbl_moves.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_moves.add_theme_font_size_override("font_size", 18)
	lbl_moves.add_theme_color_override("font_color", COL_TILE)
	vbox.add_child(lbl_moves)

	# Monete guadagnate — visibile solo se è un record migliorato.
	var lbl_coins := Label.new()
	lbl_coins.name = "LabelCoins"
	lbl_coins.text = ""
	lbl_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_coins.add_theme_font_size_override("font_size", 18)
	lbl_coins.add_theme_color_override("font_color", COL_TILE)
	lbl_coins.visible = false
	vbox.add_child(lbl_coins)

	# Riga pulsanti.
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(hbox)

	var btn_map := _make_overlay_button(tr("BTN_BACK_MAP"))
	btn_map.pressed.connect(_on_overlay_map_pressed)
	hbox.add_child(btn_map)

	# Salva il riferimento a "Avanti" per poterlo disabilitare se è l'ultimo livello.
	_btn_next = _make_overlay_button(tr("BTN_NEXT"))
	_btn_next.pressed.connect(_on_overlay_next_pressed)
	hbox.add_child(_btn_next)


# Crea un Button con lo stile oro usato nell'overlay.
func _make_overlay_button(p_text: String) -> Button:
	var btn := Button.new()
	btn.text = p_text
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", COL_TILE_TEXT)
	var s_normal := StyleBoxFlat.new()
	s_normal.bg_color = COL_TILE
	s_normal.corner_radius_top_left     = 8
	s_normal.corner_radius_top_right    = 8
	s_normal.corner_radius_bottom_left  = 8
	s_normal.corner_radius_bottom_right = 8
	var s_hover := StyleBoxFlat.new()
	s_hover.bg_color = COL_TILE.lightened(0.15)
	s_hover.corner_radius_top_left     = 8
	s_hover.corner_radius_top_right    = 8
	s_hover.corner_radius_bottom_left  = 8
	s_hover.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal",  s_normal)
	btn.add_theme_stylebox_override("hover",   s_hover)
	btn.add_theme_stylebox_override("pressed", s_hover)
	btn.custom_minimum_size = Vector2(130.0, 44.0)
	return btn


# Rende visibile l'overlay e avvia la rivelazione sequenziale delle stelle.
func _show_level_complete(p_stars: int, p_coins_earned: int) -> void:
	var par: int = int(_level_data.get("par_moves", 0))

	var lbl_moves := _level_complete_panel.get_node("Card/VBox/LabelMoves") as Label
	lbl_moves.text = tr("OVERLAY_MOVES_PAR") % [_move_count, par]

	# Mostra monete guadagnate solo se è un record (coins_earned > 0).
	var lbl_coins := _level_complete_panel.get_node("Card/VBox/LabelCoins") as Label
	if p_coins_earned > 0:
		lbl_coins.text = tr("COINS_EARNED") % p_coins_earned
		lbl_coins.visible = true
	else:
		lbl_coins.visible = false

	_level_complete_panel.visible = true
	_reveal_stars(p_stars)


# Rivela le stelle sequenzialmente: prima mostra le vuote, poi le aggiunge una ad una.
# Usa una serie di tween_callback() concatenati — ogni step aspetta il precedente.
func _reveal_stars(p_stars: int) -> void:
	var lbl := _level_complete_panel.get_node("Card/VBox/LabelStars") as Label
	# Parte da tre stelle vuote.
	lbl.text = "☆☆☆"

	# Sequenza: dopo 0.3s prima stella, poi 0.25s per ciascuna successiva.
	# tween_interval() inserisce una pausa nella sequenza senza bisogno di Timer.
	var tween := create_tween()
	for i: int in p_stars:
		tween.tween_interval(0.3 if i == 0 else 0.25)
		# La lambda cattura `i` — ma qui i non muta tra un callback e l'altro
		# perché ogni iterazione crea una nuova closure con il valore corrente.
		var stars_so_far: int = i + 1
		tween.tween_callback(func() -> void:
			lbl.text = "★".repeat(stars_so_far) + "☆".repeat(3 - stars_so_far)
		)


# ---------------------------------------------------------------------------
# Handler pulsanti overlay
# ---------------------------------------------------------------------------

func _on_overlay_map_pressed() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.goto_level_select(chapter)


func _on_overlay_next_pressed() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return

	# Verifica se esiste un livello successivo nel capitolo corrente.
	var loader: Node = get_node_or_null("/root/LevelLoader")
	var level_count: int = 0
	if loader != null:
		var info: Dictionary = loader.get_chapter_info(chapter)
		level_count = int(info.get("level_count", 0))

	if level_id < level_count:
		gm.goto_game_board(chapter, level_id + 1)
	else:
		# Ultimo livello del capitolo: placeholder fino a schermata dedicata.
		var lbl_title := _level_complete_panel.get_node("Card/VBox/LabelTitle") as Label
		lbl_title.text = tr("CHAPTER_COMPLETE_TITLE")
		_btn_next.disabled = true
		# Torna a LevelSelect dopo un breve delay per far leggere il messaggio.
		await get_tree().create_timer(1.8).timeout
		gm.goto_level_select(chapter)


# ---------------------------------------------------------------------------
# Hint
# ---------------------------------------------------------------------------

# Crea il pulsante Hint in basso a destra, sopra la label monete.
# La label del pulsante è dinamica: mostra hint gratuiti rimanenti o costo.
func _setup_hint_button() -> void:
	_btn_hint = Button.new()
	_btn_hint.name = "BtnHint"

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = COL_TILE
	style_normal.corner_radius_top_left     = 8
	style_normal.corner_radius_top_right    = 8
	style_normal.corner_radius_bottom_left  = 8
	style_normal.corner_radius_bottom_right = 8
	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = COL_TILE.lightened(0.15)
	style_hover.corner_radius_top_left     = 8
	style_hover.corner_radius_top_right    = 8
	style_hover.corner_radius_bottom_left  = 8
	style_hover.corner_radius_bottom_right = 8
	var style_disabled := StyleBoxFlat.new()
	style_disabled.bg_color = Color("3a3000")
	style_disabled.corner_radius_top_left     = 8
	style_disabled.corner_radius_top_right    = 8
	style_disabled.corner_radius_bottom_left  = 8
	style_disabled.corner_radius_bottom_right = 8
	_btn_hint.add_theme_stylebox_override("normal",   style_normal)
	_btn_hint.add_theme_stylebox_override("hover",    style_hover)
	_btn_hint.add_theme_stylebox_override("pressed",  style_hover)
	_btn_hint.add_theme_stylebox_override("disabled", style_disabled)
	_btn_hint.add_theme_color_override("font_color",          COL_TILE_TEXT)
	_btn_hint.add_theme_color_override("font_disabled_color", Color("7a6010"))
	_btn_hint.add_theme_font_size_override("font_size", 17)

	# Posizionato in basso a destra — sotto la label monete.
	_btn_hint.anchor_left   = 1.0
	_btn_hint.anchor_right  = 1.0
	_btn_hint.anchor_top    = 1.0
	_btn_hint.anchor_bottom = 1.0
	_btn_hint.offset_left   = -180.0
	_btn_hint.offset_right  = -20.0
	_btn_hint.offset_top    = -60.0
	_btn_hint.offset_bottom = -20.0

	add_child(_btn_hint)
	_refresh_hint_button()
	_btn_hint.pressed.connect(_on_hint_pressed)


# Aggiorna il testo del pulsante in base allo stato corrente degli hint.
# Chiamata dopo ogni uso di hint e dopo la risoluzione.
func _refresh_hint_button() -> void:
	if _btn_hint == null:
		return

	_btn_hint.disabled = _is_solved

	var saver: Node = _get_saver()
	if saver == null:
		_btn_hint.text = tr("HINT_LABEL_COST")
		return

	var free: int = saver.get_free_hints_remaining()
	if free > 0:
		_btn_hint.text = tr("HINT_LABEL_FREE") % [free, 3]
	else:
		_btn_hint.text = tr("HINT_LABEL_COST")


func _on_hint_pressed() -> void:
	var saver: Node = _get_saver()
	if saver == null:
		return

	var granted: bool = saver.use_hint()

	if not granted:
		# Saldo insufficiente — flash rosso sul pulsante come feedback visivo.
		_flash_hint_button_denied()
		return

	# Aggiorna label monete e pulsante dopo l'uso.
	_refresh_coins_label()
	_refresh_hint_button()

	# Chiedi la mossa suggerita a HintSolver.
	var hint_solver := HintSolver.new()
	var tile_index: int = hint_solver.suggest_move(_state)

	# -1 = puzzle già risolto (non dovrebbe succedere con _is_solved attivo,
	# ma gestiamo il caso per robustezza).
	if tile_index < 0:
		return

	_flash_tile_hint(_tile_nodes[tile_index])


# Flash rosso sul pulsante quando il giocatore non ha abbastanza monete.
# Riusa il pattern tween già consolidato nel progetto.
func _flash_hint_button_denied() -> void:
	var original_style := StyleBoxFlat.new()
	original_style.bg_color = COL_TILE
	original_style.corner_radius_top_left     = 8
	original_style.corner_radius_top_right    = 8
	original_style.corner_radius_bottom_left  = 8
	original_style.corner_radius_bottom_right = 8

	var red_style := StyleBoxFlat.new()
	red_style.bg_color = Color("8b0000")
	red_style.corner_radius_top_left     = 8
	red_style.corner_radius_top_right    = 8
	red_style.corner_radius_bottom_left  = 8
	red_style.corner_radius_bottom_right = 8

	# Non possiamo animare StyleBox direttamente con tween_property —
	# la sostituiamo con un callback manuale: rosso → originale dopo un delay.
	_btn_hint.add_theme_stylebox_override("normal", red_style)
	var tween := create_tween()
	tween.tween_interval(0.35)
	tween.tween_callback(func() -> void:
		_btn_hint.add_theme_stylebox_override("normal", original_style)
	)


# Flash dorato su una singola tile suggerita dall'hint.
# Stesso pattern di _play_solve_flash() ma circoscritto al pannello della tile.
func _flash_tile_hint(p_panel: Control) -> void:
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.85, 0.1, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p_panel.add_child(flash)

	# Fade in → hold → fade out → rimuovi. Più lungo del flash di risoluzione
	# così il giocatore ha il tempo di vedere quale tile muovere.
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.75, 0.15)
	tween.tween_interval(0.35)
	tween.tween_property(flash, "color:a", 0.0,  0.25)
	tween.tween_callback(flash.queue_free)


# ---------------------------------------------------------------------------
# Navigazione di ritorno — PARTE 3
# ---------------------------------------------------------------------------

# Crea un pulsante "< Mappa" in alto a sinistra, sotto il titolo del livello.
# Visibile solo quando GameManager è disponibile (navigazione runtime, non editor).
func _setup_back_button() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		return

	var btn := Button.new()
	btn.name   = "BackButton"
	btn.text   = tr("BTN_BACK_MAP")
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", COL_TILE)

	# Stile flat: nessun bordo, sfondo trasparente — solo testo colorato.
	var style_normal  := StyleBoxFlat.new()
	style_normal.bg_color = Color(0, 0, 0, 0)
	var style_hover   := StyleBoxFlat.new()
	style_hover.bg_color  = Color(1.0, 0.85, 0.1, 0.15)
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover",  style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)

	# Posizionato sotto il titolo del livello (riga HUD sopra la board).
	btn.position = Vector2(20.0, 50.0)
	btn.size     = Vector2(120.0, 32.0)
	add_child(btn)

	btn.pressed.connect(_on_back_pressed)

	# Pulsante ⚙ Settings — angolo in alto a destra, accanto alle mosse.
	var btn_cfg := Button.new()
	btn_cfg.name = "SettingsButton"
	btn_cfg.text = "⚙"
	btn_cfg.add_theme_font_size_override("font_size", 22)
	btn_cfg.add_theme_color_override("font_color", COL_TILE)

	var s_cfg_n := StyleBoxFlat.new()
	s_cfg_n.bg_color = Color(0, 0, 0, 0)
	var s_cfg_h := StyleBoxFlat.new()
	s_cfg_h.bg_color = Color(1.0, 0.85, 0.1, 0.15)
	s_cfg_h.corner_radius_top_left    = 6; s_cfg_h.corner_radius_top_right    = 6
	s_cfg_h.corner_radius_bottom_left = 6; s_cfg_h.corner_radius_bottom_right = 6
	btn_cfg.add_theme_stylebox_override("normal",  s_cfg_n)
	btn_cfg.add_theme_stylebox_override("hover",   s_cfg_h)
	btn_cfg.add_theme_stylebox_override("pressed", s_cfg_h)

	# Ancorato in alto a destra, vicino al contatore mosse.
	btn_cfg.anchor_left   = 1.0; btn_cfg.anchor_right  = 1.0
	btn_cfg.anchor_top    = 0.0; btn_cfg.anchor_bottom = 0.0
	btn_cfg.offset_left   = -52.0; btn_cfg.offset_right  = -12.0
	btn_cfg.offset_top    = 20.0;  btn_cfg.offset_bottom = 52.0
	add_child(btn_cfg)
	btn_cfg.pressed.connect(_on_settings_pressed)


func _on_settings_pressed() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.goto_settings("res://scenes/game/GameBoard.tscn")


func _on_back_pressed() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.goto_level_select(chapter)


# ESC come alternativa touch-free al pulsante — comodo in editor e su desktop.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
