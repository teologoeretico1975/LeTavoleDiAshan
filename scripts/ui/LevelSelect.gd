# scripts/ui/LevelSelect.gd
#
# Controller della schermata di selezione livelli per un singolo capitolo.
# Costruisce a runtime una griglia di pulsanti, uno per livello, con stato
# visivo (sbloccato / bloccato / stelle ottenute).
#
# DATI LETTI ALL'AVVIO:
#   LevelLoader.get_chapter_info(chapter)  → metadati capitolo (num_levels)
#   LevelLoader.get_level(chapter, id)     → titolo livello
#   SaveManager.is_level_unlocked(ch, id)  → bool
#   SaveManager.get_level_progress(ch, id) → {"stars": int, "best_moves": int}
#
# NAVIGAZIONE:
#   click su livello sbloccato → GameManager.goto_game_board(chapter, level_id)
#   click su "< Capitoli"     → placeholder (ChapterSelect non ancora implementato)

class_name LevelSelect
extends Control


# ---------------------------------------------------------------------------
# Parametri editor — fallback quando GameManager non è disponibile
# ---------------------------------------------------------------------------

# Capitolo da mostrare. In gioco lo sovrascrive GameManager.selected_chapter.
@export var chapter: int = 1


# ---------------------------------------------------------------------------
# Palette (Capitolo I, oro/bronzo — stessa di GameBoard)
# ---------------------------------------------------------------------------

const COL_BG            := Color("1a1000")
const COL_GOLD          := Color("c9a227")
const COL_GOLD_DIM      := Color("7a6010")   # oro attenuato per testo su tile bloccate
const COL_LOCKED_BG     := Color("2a2000")   # sfondo tile bloccata
const COL_TILE_TEXT     := Color("1a1000")   # testo scuro su tile sbloccata


# ---------------------------------------------------------------------------
# Layout griglia
# ---------------------------------------------------------------------------

# Quante colonne nella griglia dei pulsanti livello.
const GRID_COLS: int     = 4
const BTN_SIZE: float    = 110.0   # lato del pulsante quadrato
const BTN_GAP: float     = 16.0    # spazio tra pulsanti


# ---------------------------------------------------------------------------
# Riferimenti interni
# ---------------------------------------------------------------------------

var _grid: GridContainer   # container che ospita i pulsanti livello


# ---------------------------------------------------------------------------
# Inizializzazione
# ---------------------------------------------------------------------------

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Legge il capitolo da GameManager se disponibile.
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		chapter = gm.selected_chapter

	_setup_background()
	_setup_header()
	_build_level_grid()


# ---------------------------------------------------------------------------
# Sfondo e header
# ---------------------------------------------------------------------------

func _setup_background() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


func _setup_header() -> void:
	# Riga superiore: pulsante "< Capitoli" a sinistra, titolo capitolo centrato.

	var loader: Node = _get_loader()
	var chapter_title: String = "Capitolo %d" % chapter
	if loader != null:
		chapter_title = loader.get_chapter_title(chapter)

	# Label titolo capitolo — centrata in alto.
	var lbl := Label.new()
	lbl.name = "LabelChapterTitle"
	lbl.text = chapter_title
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", COL_GOLD)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Fascia orizzontale in cima — anchor_left=0, anchor_right=1 → larghezza schermo.
	lbl.anchor_left   = 0.0
	lbl.anchor_right  = 1.0
	lbl.anchor_top    = 0.0
	lbl.anchor_bottom = 0.0
	lbl.offset_top    = 20.0
	lbl.offset_bottom = 60.0
	add_child(lbl)

	# Pulsante "< Capitoli" (placeholder — ChapterSelect non ancora implementato).
	var back_btn := Button.new()
	back_btn.name = "BackBtn"
	back_btn.text = "< Capitoli"
	back_btn.add_theme_font_size_override("font_size", 18)
	back_btn.add_theme_color_override("font_color", COL_GOLD)
	var style_n := StyleBoxFlat.new()
	style_n.bg_color = Color(0, 0, 0, 0)
	var style_h := StyleBoxFlat.new()
	style_h.bg_color = Color(1.0, 0.85, 0.1, 0.15)
	back_btn.add_theme_stylebox_override("normal",  style_n)
	back_btn.add_theme_stylebox_override("hover",   style_h)
	back_btn.add_theme_stylebox_override("pressed", style_h)
	back_btn.position = Vector2(16.0, 20.0)
	back_btn.size     = Vector2(140.0, 36.0)
	add_child(back_btn)
	back_btn.pressed.connect(_on_back_to_chapters)


# ---------------------------------------------------------------------------
# Griglia livelli
# ---------------------------------------------------------------------------

# Costruisce il GridContainer e popola un Button per ogni livello del capitolo.
# Tutto avviene in un singolo loop: carico i dati, creo il nodo, configuro,
# aggiungo al container. Nessun aggiornamento incrementale successivo.
func _build_level_grid() -> void:
	var loader: Node = _get_loader()
	var saver:  Node = _get_saver()

	# Numero di livelli dal JSON del capitolo.
	var num_levels: int = 0
	if loader != null:
		var info: Dictionary = loader.get_chapter_info(chapter)
		num_levels = int(info.get("level_count", 0))

	if num_levels == 0:
		push_warning("LevelSelect: nessun livello trovato per capitolo %d." % chapter)
		return

	# GridContainer: container che dispone i figli in N colonne automaticamente.
	# Ogni add_child() aggiunge un elemento nella prossima cella disponibile —
	# non serve calcolare righe e colonne manualmente.
	_grid = GridContainer.new()
	_grid.name    = "LevelGrid"
	_grid.columns = GRID_COLS

	# Larghezza occupata da tutte le colonne + gap tra di esse.
	var grid_w: float = GRID_COLS * BTN_SIZE + (GRID_COLS - 1) * BTN_GAP
	var num_rows: int = int(ceil(float(num_levels) / GRID_COLS))
	var grid_h: float = num_rows * BTN_SIZE + (num_rows - 1) * BTN_GAP

	# Centro orizzontale con margine superiore fisso (sotto l'header).
	_grid.anchor_left  = 0.5
	_grid.anchor_right = 0.5
	_grid.anchor_top   = 0.0
	_grid.offset_left  = -grid_w / 2.0
	_grid.offset_right =  grid_w / 2.0
	_grid.offset_top   = 80.0
	_grid.offset_bottom = 80.0 + grid_h

	# add_theme_constant_override imposta la spaziatura interna del container
	# (equivalente di ItemsPanel.Margin o UniformGrid.ColumnSpacing in WPF).
	_grid.add_theme_constant_override("h_separation", int(BTN_GAP))
	_grid.add_theme_constant_override("v_separation", int(BTN_GAP))

	add_child(_grid)

	# Popola un pulsante per ogni livello.
	for lvl_id: int in range(1, num_levels + 1):
		var is_unlocked: bool = true
		var stars: int        = 0

		if saver != null:
			is_unlocked = saver.is_level_unlocked(chapter, lvl_id)
			var progress = saver.get_level_progress(chapter, lvl_id)
			if progress != null:
				stars = int(progress.get("stars", 0))

		var btn := _make_level_button(lvl_id, is_unlocked, stars)
		_grid.add_child(btn)


# Crea e restituisce un singolo pulsante livello.
# Separato da _build_level_grid() per leggibilità — ogni pulsante ha
# tre stati visivi: completato (oro pieno), sbloccato (oro attenuato), bloccato.
func _make_level_button(lvl_id: int, is_unlocked: bool, stars: int) -> Button:
	var btn := Button.new()
	btn.name         = "Level_%d" % lvl_id
	btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	btn.disabled     = not is_unlocked

	# StyleBoxFlat per i tre stati (normal, hover, disabled).
	# In Godot ogni stato visivo di un Button usa una stylebox distinta.
	var style_base := StyleBoxFlat.new()
	style_base.corner_radius_top_left     = 10
	style_base.corner_radius_top_right    = 10
	style_base.corner_radius_bottom_left  = 10
	style_base.corner_radius_bottom_right = 10

	if not is_unlocked:
		# Bloccato: sfondo scuro, testo simbolo lucchetto.
		var s := style_base.duplicate() as StyleBoxFlat
		s.bg_color = COL_LOCKED_BG
		btn.add_theme_stylebox_override("disabled", s)
		btn.add_theme_color_override("font_disabled_color", COL_GOLD_DIM)
	else:
		# Sbloccato: sfondo oro pieno, hover leggermente più chiaro.
		var s_normal := style_base.duplicate() as StyleBoxFlat
		s_normal.bg_color = COL_GOLD
		var s_hover  := style_base.duplicate() as StyleBoxFlat
		s_hover.bg_color  = COL_GOLD.lightened(0.15)
		btn.add_theme_stylebox_override("normal",  s_normal)
		btn.add_theme_stylebox_override("hover",   s_hover)
		btn.add_theme_stylebox_override("pressed", s_hover)
		btn.add_theme_color_override("font_color", COL_TILE_TEXT)

	# Testo del pulsante: numero livello + stelle ottenute (se completato).
	# Usiamo testo semplice: "3\n★★☆" — nessuna icona, massima compatibilità font.
	var star_text: String = _stars_text(stars) if stars > 0 else ""
	if is_unlocked:
		btn.text = "%d\n%s" % [lvl_id, star_text]
	else:
		btn.text = "🔒"    # lucchetto unicode — fallback se il font non lo ha: "—"

	btn.add_theme_font_size_override("font_size", 22)

	# Collega il segnale solo per pulsanti sbloccati (i disabled non emettono pressed,
	# ma è buona pratica connettere solo chi deve rispondere).
	if is_unlocked:
		btn.pressed.connect(_on_level_pressed.bind(lvl_id))

	return btn


# Restituisce la stringa stelle: "★★★", "★★☆", "★☆☆".
# Unicode stelle piene/vuote — visivamente immediato, nessuna dipendenza da asset.
func _stars_text(stars: int) -> String:
	var full:  String = "★".repeat(stars)
	var empty: String = "☆".repeat(3 - stars)
	return full + empty


# ---------------------------------------------------------------------------
# Handler eventi
# ---------------------------------------------------------------------------

func _on_level_pressed(lvl_id: int) -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.goto_game_board(chapter, lvl_id)
	else:
		# Fallback diretto per testing senza GameManager (raro in produzione).
		push_warning("LevelSelect: GameManager non disponibile, navigazione impossibile.")


func _on_back_to_chapters() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.goto_chapter_select()


# ---------------------------------------------------------------------------
# Accesso agli Autoload (stesso pattern di GameBoard)
# ---------------------------------------------------------------------------

func _get_loader() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/LevelLoader")


func _get_saver() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/SaveManager")
