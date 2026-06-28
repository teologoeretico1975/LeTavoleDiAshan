# scenes/DiaryScreen.gd
#
# Schermata narrativa post-livello: mostra il frammento del diario di Frate Sybelius
# corrispondente al livello appena completato, con autoscroll e fade in/out.
#
# Uso (da GameBoard, dopo la risoluzione del puzzle):
#   var diary := load("res://scenes/DiaryScreen.tscn").instantiate()
#   diary.chapter_index = chapter
#   diary.level_index   = level_id
#   diary.next_scene    = "res://scenes/ui/LevelSelect.tscn"
#   get_tree().root.add_child(diary)
#
# La schermata si aggiunge direttamente a root come CanvasLayer, sovrapponendosi
# alla scena corrente (GameBoard). Quando la sequenza termina (o l'utente tocca lo
# schermo), chiama change_scene_to_file(next_scene) e si autodistrugge.

class_name DiaryScreen
extends CanvasLayer

# Parametri iniettati dal chiamante prima di add_child().
var chapter_index: int = 0
var level_index:   int = 0
var next_scene:    String = ""

# Riferimenti ai nodi costruiti in _build_ui().
var _root_control:     Control
var _scroll_container: ScrollContainer
var _text_label:       Label

# Flag anti-rientro: _navigate_away() deve girare una volta sola.
var _navigating: bool = false


# ---------------------------------------------------------------------------
# Inizializzazione
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()
	_start_sequence()


func _build_ui() -> void:
	# Control root: serve come pivot per il fade (modulate alpha).
	# MOUSE_FILTER_STOP cattura tutti i click/touch per il "tap to skip".
	_root_control = Control.new()
	_root_control.name = "Root"
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.modulate   = Color(1.0, 1.0, 1.0, 0.0)
	_root_control.mouse_filter = Control.MOUSE_FILTER_STOP
	_root_control.gui_input.connect(_on_gui_input)
	add_child(_root_control)

	# Sfondo quasi-nero con tono caldo (#0d0a08).
	var bg := ColorRect.new()
	bg.color       = Color(0.051, 0.039, 0.031)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.add_child(bg)

	# Margini laterali 48 px, spazio per SkipLabel in basso.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   48)
	margin.add_theme_constant_override("margin_right",  48)
	margin.add_theme_constant_override("margin_top",    64)
	margin.add_theme_constant_override("margin_bottom", 80)
	_root_control.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	margin.add_child(vbox)

	var font := ResourceLoader.load(
		"res://assets/fonts/Cinzel_Decorative/CinzelDecorative-Regular.ttf"
	) as Font

	# Header: "Dal Diario di Frate Sybelius"
	var header := Label.new()
	header.name                 = "HeaderLabel"
	header.text                 = tr("DIARY_HEADER")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color("#6b5a3e"))
	if font != null:
		header.add_theme_font_override("font", font)
	vbox.add_child(header)

	# Titolo livello.
	var title_lbl := Label.new()
	title_lbl.name                 = "LevelTitleLabel"
	title_lbl.text                 = tr("LEVEL_%d_%d_TITLE" % [chapter_index, level_index])
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color("#c8b89a"))
	if font != null:
		title_lbl.add_theme_font_override("font", font)
	vbox.add_child(title_lbl)

	# ScrollContainer: EXPAND_FILL per occupare tutto lo spazio disponibile;
	# scrollbar nascosta perché l'utente non deve scorrere manualmente.
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_vertical      = Control.SIZE_EXPAND_FILL
	_scroll_container.vertical_scroll_mode     = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll_container.horizontal_scroll_mode   = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll_container)

	# Corpo del diario.
	_text_label = Label.new()
	_text_label.name              = "TextLabel"
	_text_label.text              = tr("LEVEL_%d_%d_DIARY" % [chapter_index, level_index])
	_text_label.autowrap_mode     = TextServer.AUTOWRAP_WORD
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("font_size", 18)
	_text_label.add_theme_color_override("font_color", Color("#c8b89a"))
	if font != null:
		_text_label.add_theme_font_override("font", font)
	_scroll_container.add_child(_text_label)

	# SkipLabel: ancorata al bordo inferiore del root control (fuori dal MarginContainer).
	var skip := Label.new()
	skip.name                 = "SkipLabel"
	skip.text                 = tr("DIARY_TAP_TO_SKIP")
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip.anchor_left          = 0.0
	skip.anchor_right         = 1.0
	skip.anchor_top           = 1.0
	skip.anchor_bottom        = 1.0
	skip.offset_top           = -40.0
	skip.offset_bottom        = -8.0
	skip.add_theme_font_size_override("font_size", 14)
	skip.add_theme_color_override("font_color", Color("#6b5a3e"))
	if font != null:
		skip.add_theme_font_override("font", font)
	_root_control.add_child(skip)


# ---------------------------------------------------------------------------
# Sequenza automatica
# ---------------------------------------------------------------------------

func _start_sequence() -> void:
	# Fade in.
	var tween_in := create_tween()
	tween_in.tween_property(_root_control, "modulate:a", 1.0, 0.4)
	await tween_in.finished

	# Pausa iniziale di lettura.
	await get_tree().create_timer(2.0).timeout

	# Aspetta due frame perché il layout sia stabilizzato prima di leggere le altezze.
	await get_tree().process_frame
	await get_tree().process_frame

	# Autoscroll proporzionale alla lunghezza del testo (50 px/sec).
	var content_h:  float = _text_label.size.y
	var visible_h:  float = _scroll_container.size.y
	var scroll_dist: float = maxf(0.0, content_h - visible_h)

	if scroll_dist > 1.0:
		var duration: float = scroll_dist / 50.0
		var tween_scroll := create_tween()
		tween_scroll.tween_property(_scroll_container, "scroll_vertical", int(scroll_dist), duration)
		await tween_scroll.finished

	# Pausa finale prima di navigare.
	await get_tree().create_timer(1.0).timeout

	_navigate_away()


# ---------------------------------------------------------------------------
# Input — "tocca per continuare"
# ---------------------------------------------------------------------------

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			_navigate_away()
	elif event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_navigate_away()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_navigate_away()


# ---------------------------------------------------------------------------
# Navigazione
# ---------------------------------------------------------------------------

func _navigate_away() -> void:
	if _navigating:
		return
	_navigating = true

	# Fade out, poi cambia scena e rimuovi questo nodo da root.
	var tween := create_tween()
	tween.tween_property(_root_control, "modulate:a", 0.0, 0.4)
	await tween.finished

	queue_free()
	get_tree().change_scene_to_file(next_scene)
