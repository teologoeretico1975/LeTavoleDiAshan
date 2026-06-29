# scenes/DiaryScreen.gd
#
# Schermata narrativa post-livello: mostra il frammento del diario di Frate Sybelius
# corrispondente al livello appena completato. Il giocatore esce solo premendo
# il pulsante "Continua" — nessun auto-dismiss.
#
# Uso (da GameBoard._try_show_diary):
#   var diary := load("res://scenes/DiaryScreen.tscn").instantiate()
#   diary.chapter_index = chapter
#   diary.level_index   = level_id
#   diary.next_scene    = "res://scenes/ui/LevelSelect.tscn"
#   get_tree().root.add_child(diary)

class_name DiaryScreen
extends CanvasLayer

var chapter_index: int = 0
var level_index:   int = 0
var next_scene:    String = ""

var _root_control:     Control
var _scroll_container: ScrollContainer
var _text_label:       Label
var _btn_continue:     Button
var _navigating:       bool = false

const COL_GOLD     := Color(0.9,  0.78, 0.35)
const COL_TEXT     := Color(0.784, 0.722, 0.604)   # #c8b89a
const COL_MUTED    := Color(0.42, 0.353, 0.243)    # #6b5a3e
const COL_BG       := Color(0.051, 0.039, 0.031)   # #0d0a08
const COL_BTN_TEXT := Color(0.102, 0.063, 0.0)     # testo scuro sul bottone oro


# ---------------------------------------------------------------------------
# Inizializzazione
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()
	_start_sequence()


func _build_ui() -> void:
	var font := ResourceLoader.load(
		"res://assets/fonts/Cinzel_Decorative/CinzelDecorative-Regular.ttf"
	) as Font

	# Root control — pivot del fade, blocca input alla scena sottostante.
	_root_control = Control.new()
	_root_control.name         = "Root"
	_root_control.mouse_filter = Control.MOUSE_FILTER_STOP
	_root_control.modulate     = Color(1.0, 1.0, 1.0, 0.0)
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root_control)

	# Sfondo.
	var bg := ColorRect.new()
	bg.color        = COL_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.add_child(bg)

	# Margini: margin_bottom 100 px per lasciare spazio al pulsante.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   48)
	margin.add_theme_constant_override("margin_right",  48)
	margin.add_theme_constant_override("margin_top",    64)
	margin.add_theme_constant_override("margin_bottom", 100)
	_root_control.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	# Header.
	var header := Label.new()
	header.name                 = "HeaderLabel"
	header.text                 = tr("DIARY_HEADER")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", COL_MUTED)
	if font != null:
		header.add_theme_font_override("font", font)
	vbox.add_child(header)

	# Titolo livello.
	var title_lbl := Label.new()
	title_lbl.name                 = "LevelTitleLabel"
	title_lbl.text                 = tr("LEVEL_%d_%d_TITLE" % [chapter_index, level_index])
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", COL_TEXT)
	if font != null:
		title_lbl.add_theme_font_override("font", font)
	vbox.add_child(title_lbl)

	# Separatore visivo.
	var sep := HSeparator.new()
	sep.modulate = COL_MUTED
	vbox.add_child(sep)

	# Vignetta del capitolo — immagine narrativa tra separatore e testo.
	# Altezza fissa 200px: abbastanza evocativa, non schiaccia il testo su schermi bassi.
	var vignette_path: String = "res://assets/art/vignette_chapter_%d.png" % chapter_index
	if ResourceLoader.exists(vignette_path):
		var vignette_tex := ResourceLoader.load(vignette_path) as Texture2D
		if vignette_tex != null:
			var vignette := TextureRect.new()
			vignette.name         = "VignetteImage"
			vignette.texture      = vignette_tex
			vignette.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			vignette.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
			vignette.custom_minimum_size = Vector2(0, 200)
			vignette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(vignette)

	# ScrollContainer — scrollbar nascosta, scroll orizzontale disabilitato.
	# NOTA: il Label figlio non usa SIZE_EXPAND_FILL perché dentro ScrollContainer
	# causerebbe larghezza indeterminata e il testo non si vedrebbe. La larghezza
	# corretta viene imposta via custom_minimum_size.x in _start_sequence(),
	# dopo che il layout è stabilizzato.
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	_scroll_container.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll_container)

	_text_label = Label.new()
	_text_label.name          = "TextLabel"
	_text_label.text          = tr("LEVEL_%d_%d_DIARY" % [chapter_index, level_index])
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	# SIZE_FILL (non EXPAND_FILL): si adatta alla larghezza del container senza espanderlo.
	_text_label.size_flags_horizontal = Control.SIZE_FILL
	_text_label.add_theme_font_size_override("font_size", 18)
	_text_label.add_theme_color_override("font_color", COL_TEXT)
	if font != null:
		_text_label.add_theme_font_override("font", font)
	_scroll_container.add_child(_text_label)

	# Pulsante "Continua" — ancorato in basso al centro, fuori dal MarginContainer.
	_btn_continue = Button.new()
	_btn_continue.name   = "ContinueButton"
	_btn_continue.text   = tr("DIARY_CONTINUE")
	_btn_continue.anchor_left   = 0.5
	_btn_continue.anchor_right  = 0.5
	_btn_continue.anchor_top    = 1.0
	_btn_continue.anchor_bottom = 1.0
	_btn_continue.offset_left   = -100.0
	_btn_continue.offset_right  =  100.0
	_btn_continue.offset_top    = -64.0
	_btn_continue.offset_bottom = -16.0
	_btn_continue.add_theme_font_size_override("font_size", 20)
	_btn_continue.add_theme_color_override("font_color", COL_BTN_TEXT)
	if font != null:
		_btn_continue.add_theme_font_override("font", font)
	var s_normal := StyleBoxFlat.new()
	s_normal.bg_color = COL_GOLD
	s_normal.corner_radius_top_left     = 8
	s_normal.corner_radius_top_right    = 8
	s_normal.corner_radius_bottom_left  = 8
	s_normal.corner_radius_bottom_right = 8
	var s_hover := StyleBoxFlat.new()
	s_hover.bg_color = COL_GOLD.lightened(0.15)
	s_hover.corner_radius_top_left     = 8
	s_hover.corner_radius_top_right    = 8
	s_hover.corner_radius_bottom_left  = 8
	s_hover.corner_radius_bottom_right = 8
	_btn_continue.add_theme_stylebox_override("normal",  s_normal)
	_btn_continue.add_theme_stylebox_override("hover",   s_hover)
	_btn_continue.add_theme_stylebox_override("pressed", s_hover)
	_btn_continue.pressed.connect(_navigate_away)
	_root_control.add_child(_btn_continue)


# ---------------------------------------------------------------------------
# Sequenza di ingresso + autoscroll
# ---------------------------------------------------------------------------

func _start_sequence() -> void:
	# Stabilizza il layout mentre la schermata è ancora invisibile (modulate.a = 0),
	# così il glitch "rettangolo piccolo" non è mai visibile all'utente.
	await get_tree().process_frame
	await get_tree().process_frame
	_text_label.custom_minimum_size.x = _scroll_container.size.x
	await get_tree().process_frame

	# Fade in solo dopo che il layout è già corretto.
	var tween_in := create_tween()
	tween_in.tween_property(_root_control, "modulate:a", 1.0, 0.4)
	await tween_in.finished

	# Pausa iniziale prima dell'autoscroll.
	await get_tree().create_timer(2.0).timeout

	# Autoscroll proporzionale alla lunghezza del testo (40 px/s — velocità leggibile).
	var content_h:   float = _text_label.size.y
	var visible_h:   float = _scroll_container.size.y
	var scroll_dist: float = maxf(0.0, content_h - visible_h)

	if scroll_dist > 1.0:
		var duration: float = scroll_dist / 40.0
		var tween_scroll := create_tween()
		tween_scroll.tween_property(_scroll_container, "scroll_vertical", int(scroll_dist), duration)
		# Non awaita il tween: l'autoscroll è un effetto, non un gate di uscita.
		# Il giocatore può premere "Continua" in qualsiasi momento.


# ---------------------------------------------------------------------------
# Navigazione — solo via pulsante
# ---------------------------------------------------------------------------

func _navigate_away() -> void:
	if _navigating:
		return
	_navigating = true
	_btn_continue.disabled = true

	# Fade verso il nero anziché verso il trasparente: evita di rivelare
	# la GameBoard sottostante (con overlay stelle) durante la transizione.
	var black := ColorRect.new()
	black.color        = Color(0.0, 0.0, 0.0, 0.0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.add_child(black)

	var tween := create_tween()
	tween.tween_property(black, "color:a", 1.0, 0.4)
	await tween.finished

	queue_free()
	get_tree().change_scene_to_file(next_scene)
