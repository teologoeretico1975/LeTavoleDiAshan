# scripts/ui/MainMenu.gd

extends Control


const COL_BG   := Color("1a1000")
const COL_GOLD := Color("c9a227")

# Riferimenti ai nodi di testo localizzabili — aggiornati da _refresh_texts().
var _lbl_title: Label
var _lbl_tag: Label
var _btn_start: Button
var _btn_quit: Button


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 32)
	vbox.anchor_left   = 0.0
	vbox.anchor_right  = 1.0
	vbox.anchor_top    = 0.0
	vbox.anchor_bottom = 1.0
	add_child(vbox)

	_lbl_title = Label.new()
	_lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_title.add_theme_font_size_override("font_size", 48)
	_lbl_title.add_theme_color_override("font_color", COL_GOLD)
	_lbl_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_lbl_title)

	_lbl_tag = Label.new()
	_lbl_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_tag.add_theme_font_size_override("font_size", 20)
	_lbl_tag.add_theme_color_override("font_color", Color("7a6010"))
	_lbl_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_lbl_tag)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(spacer)

	var hbox_start := _make_btn_row("", _on_start_pressed)
	vbox.add_child(hbox_start)
	_btn_start = hbox_start.get_child(0) as Button

	var quit_spacer := Control.new()
	quit_spacer.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(quit_spacer)

	var hbox_quit := _make_btn_row("", _on_quit_pressed)
	vbox.add_child(hbox_quit)
	_btn_quit = hbox_quit.get_child(0) as Button

	_setup_language_buttons()
	_refresh_texts()


# Aggiorna tutti i testi localizzabili. Chiamata al boot e a ogni cambio lingua.
func _refresh_texts() -> void:
	if _lbl_title != null:
		_lbl_title.text = tr("GAME_TITLE")
	if _lbl_tag != null:
		_lbl_tag.text = tr("TAGLINE")
	if _btn_start != null:
		_btn_start.text = tr("BTN_START")
	if _btn_quit != null:
		_btn_quit.text = tr("BTN_QUIT")


# Tre pulsanti compatti IT / EN / ES nell'angolo in basso a destra.
func _setup_language_buttons() -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	# Ancoro all'angolo in basso a destra del viewport.
	hbox.anchor_left   = 1.0
	hbox.anchor_top    = 1.0
	hbox.anchor_right  = 1.0
	hbox.anchor_bottom = 1.0
	hbox.offset_left   = -188.0
	hbox.offset_top    = -52.0
	hbox.offset_right  = -12.0
	hbox.offset_bottom = -12.0
	add_child(hbox)

	for locale: String in ["it", "en", "es"]:
		var btn := Button.new()
		btn.text = locale.to_upper()
		btn.custom_minimum_size = Vector2(52, 36)
		btn.add_theme_font_size_override("font_size", 15)
		btn.add_theme_color_override("font_color", COL_GOLD)

		var s_n := StyleBoxFlat.new()
		s_n.bg_color = Color(0, 0, 0, 0.45)
		s_n.border_color = COL_GOLD
		s_n.border_width_left = 1; s_n.border_width_right  = 1
		s_n.border_width_top  = 1; s_n.border_width_bottom = 1
		s_n.corner_radius_top_left    = 6; s_n.corner_radius_top_right    = 6
		s_n.corner_radius_bottom_left = 6; s_n.corner_radius_bottom_right = 6

		var s_h := StyleBoxFlat.new()
		s_h.bg_color = Color(1.0, 0.85, 0.1, 0.25)
		s_h.corner_radius_top_left    = 6; s_h.corner_radius_top_right    = 6
		s_h.corner_radius_bottom_left = 6; s_h.corner_radius_bottom_right = 6

		btn.add_theme_stylebox_override("normal",  s_n)
		btn.add_theme_stylebox_override("hover",   s_h)
		btn.add_theme_stylebox_override("pressed", s_h)
		btn.pressed.connect(_on_lang_pressed.bind(locale))
		hbox.add_child(btn)


func _on_lang_pressed(locale: String) -> void:
	var lm: Node = get_node_or_null("/root/LocalizationManager")
	if lm != null:
		lm.set_language(locale)
	_refresh_texts()


func _make_btn_row(label: String, callback: Callable) -> HBoxContainer:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", Color("1a1000"))
	btn.custom_minimum_size = Vector2(200, 56)
	var s_normal := StyleBoxFlat.new()
	s_normal.bg_color = COL_GOLD
	s_normal.corner_radius_top_left     = 10
	s_normal.corner_radius_top_right    = 10
	s_normal.corner_radius_bottom_left  = 10
	s_normal.corner_radius_bottom_right = 10
	var s_hover := StyleBoxFlat.new()
	s_hover.bg_color = COL_GOLD.lightened(0.15)
	s_hover.corner_radius_top_left     = 10
	s_hover.corner_radius_top_right    = 10
	s_hover.corner_radius_bottom_left  = 10
	s_hover.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal",  s_normal)
	btn.add_theme_stylebox_override("hover",   s_hover)
	btn.add_theme_stylebox_override("pressed", s_hover)
	btn.pressed.connect(callback)
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(btn)
	return hbox


func _on_start_pressed() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.goto_chapter_select()


func _on_quit_pressed() -> void:
	get_tree().quit()
