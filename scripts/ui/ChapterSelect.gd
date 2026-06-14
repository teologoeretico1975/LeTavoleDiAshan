# scripts/ui/ChapterSelect.gd
#
# Schermata di selezione capitolo: lista verticale delle 6 epoche narrative.
# Ogni card mostra numero romano, titolo, progresso livelli/stelle e
# icona lucchetto se il capitolo non è ancora raggiunto.
#
# STRUTTURA PROCEDURALE:
#   VBoxContainer (centrato a schermo)
#     └─ per ogni capitolo: Panel (card) con Label titolo + Label progresso
#
# VBoxContainer vs GridContainer: qui abbiamo una lista a colonna singola
# di 6 elementi — VBox è la scelta naturale. Ogni card si estende
# orizzontalmente senza configurare colonne o calcolare larghezze.

extends Control


# ---------------------------------------------------------------------------
# Palette (stessa oro/bronzo — palette per capitolo è polish futuro)
# ---------------------------------------------------------------------------

const COL_BG         := Color("1a1000")
const COL_GOLD       := Color("c9a227")
const COL_GOLD_DIM   := Color("7a6010")
const COL_CARD       := Color("2a1a00")    # sfondo card sbloccata
const COL_CARD_LOCK  := Color("1a1200")    # sfondo card bloccata
const COL_TEXT_DARK  := Color("1a1000")


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

const CARD_HEIGHT:  float = 90.0
const CARD_GAP:     float = 14.0
const CARD_WIDTH:   float = 520.0   # larghezza fissa card, centrata a schermo
const NUM_CHAPTERS: int   = 6

# Numeri romani per i 6 capitoli — array indicizzato da 0 a 5.
const ROMAN: Array = ["I", "II", "III", "IV", "V", "VI"]


# ---------------------------------------------------------------------------
# Inizializzazione
# ---------------------------------------------------------------------------

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	set_anchors_preset(Control.PRESET_FULL_RECT)
	_setup_background()
	_setup_header()
	_build_chapter_list()


func _setup_background() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


func _setup_header() -> void:
	var lbl := Label.new()
	lbl.name = "LabelTitle"
	lbl.text = "Le Tavole di Ashan"
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", COL_GOLD)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.anchor_left   = 0.0
	lbl.anchor_right  = 1.0
	lbl.anchor_top    = 0.0
	lbl.anchor_bottom = 0.0
	lbl.offset_top    = 24.0
	lbl.offset_bottom = 68.0
	add_child(lbl)


# ---------------------------------------------------------------------------
# Lista capitoli
# ---------------------------------------------------------------------------

func _build_chapter_list() -> void:
	var loader: Node = get_node_or_null("/root/LevelLoader")
	var saver:  Node = get_node_or_null("/root/SaveManager")

	# VBoxContainer: dispone i figli dall'alto verso il basso, uno per riga.
	# Ogni add_child() aggiunge la card nella prossima posizione verticale.
	var vbox := VBoxContainer.new()
	vbox.name = "ChapterList"
	vbox.add_theme_constant_override("separation", int(CARD_GAP))

	# Centra il VBox orizzontalmente, posizionato sotto l'header.
	var total_h: float = NUM_CHAPTERS * CARD_HEIGHT + (NUM_CHAPTERS - 1) * CARD_GAP
	vbox.anchor_left  = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top   = 0.0
	vbox.offset_left  = -CARD_WIDTH / 2.0
	vbox.offset_right =  CARD_WIDTH / 2.0
	vbox.offset_top   = 80.0
	vbox.offset_bottom = 80.0 + total_h

	add_child(vbox)

	for ch: int in range(1, NUM_CHAPTERS + 1):
		var title: String = "Capitolo %d" % ch
		if loader != null:
			title = loader.get_chapter_title(ch)

		var is_unlocked: bool = true
		var progress: Dictionary = {
			"completed_levels": 0, "total_levels": 0,
			"total_stars": 0,      "max_stars": 0,
		}
		if saver != null:
			is_unlocked = saver.is_chapter_unlocked(ch)
			progress    = saver.get_chapter_progress(ch)

		var card := _make_chapter_card(ch, title, is_unlocked, progress)
		vbox.add_child(card)


# Costruisce una singola card capitolo come Panel con due Label (titolo + progresso)
# e gestione click via Button trasparente sovrapposto al Panel.
func _make_chapter_card(
		ch: int,
		title: String,
		is_unlocked: bool,
		progress: Dictionary) -> Panel:

	var panel := Panel.new()
	panel.name = "Chapter_%d" % ch
	panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)

	var style := StyleBoxFlat.new()
	style.bg_color = COL_CARD if is_unlocked else COL_CARD_LOCK
	style.corner_radius_top_left     = 12
	style.corner_radius_top_right    = 12
	style.corner_radius_bottom_left  = 12
	style.corner_radius_bottom_right = 12
	# Bordo sottile dorato per le card sbloccate, dimmer per le bloccate.
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.border_color = COL_GOLD if is_unlocked else COL_GOLD_DIM
	panel.add_theme_stylebox_override("panel", style)

	# Label principale: "I — Il Risveglio" oppure "I — 🔒"
	var lbl_title := Label.new()
	lbl_title.name = "LabelTitle"
	lbl_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_unlocked:
		lbl_title.text = "%s — %s" % [ROMAN[ch - 1], title]
		lbl_title.add_theme_color_override("font_color", COL_GOLD)
	else:
		lbl_title.text = "%s — 🔒" % ROMAN[ch - 1]
		lbl_title.add_theme_color_override("font_color", COL_GOLD_DIM)
	lbl_title.add_theme_font_size_override("font_size", 22)
	lbl_title.position = Vector2(20.0, 12.0)
	panel.add_child(lbl_title)

	# Label progresso: "8/20 livelli · 18/60 stelle" (solo per capitoli sbloccati)
	if is_unlocked:
		var lbl_prog := Label.new()
		lbl_prog.name = "LabelProgress"
		lbl_prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cl: int = progress.get("completed_levels", 0)
		var tl: int = progress.get("total_levels", 0)
		var ts: int = progress.get("total_stars", 0)
		var ms: int = progress.get("max_stars", 0)
		lbl_prog.text = "%d/%d livelli  ·  %d/%d stelle" % [cl, tl, ts, ms]
		lbl_prog.add_theme_font_size_override("font_size", 16)
		lbl_prog.add_theme_color_override("font_color", COL_GOLD_DIM)
		lbl_prog.position = Vector2(20.0, 50.0)
		panel.add_child(lbl_prog)

	# Button trasparente sovrapposto — cattura i click sull'intera card.
	# Pattern: Panel gestisce l'aspetto visivo, Button gestisce l'input.
	# Alternativa: usare gui_input sul Panel — ma Button.pressed è più pulito.
	if is_unlocked:
		var btn := Button.new()
		btn.name = "ClickArea"
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		# Rendi il button completamente trasparente: tutti gli stili a bg_color vuoto.
		for state in ["normal", "hover", "pressed", "focus"]:
			var s := StyleBoxFlat.new()
			s.bg_color = Color(0, 0, 0, 0)
			btn.add_theme_stylebox_override(state, s)
		# Hover leggero visibile sovrapposto alla card.
		var s_hover := StyleBoxFlat.new()
		s_hover.bg_color = Color(1.0, 0.85, 0.1, 0.08)
		s_hover.corner_radius_top_left     = 12
		s_hover.corner_radius_top_right    = 12
		s_hover.corner_radius_bottom_left  = 12
		s_hover.corner_radius_bottom_right = 12
		btn.add_theme_stylebox_override("hover", s_hover)
		btn.pressed.connect(_on_chapter_pressed.bind(ch))
		panel.add_child(btn)

	return panel


# ---------------------------------------------------------------------------
# Navigazione
# ---------------------------------------------------------------------------

func _on_chapter_pressed(ch: int) -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.goto_level_select(ch)
