# scripts/ui/MainMenu.gd

extends Control


const COL_BG   := Color("1a1000")
const COL_GOLD := Color("c9a227")

# Riferimenti ai nodi di testo localizzabili — aggiornati da _refresh_texts().
var _lbl_title: Label
var _lbl_tag: Label
var _btn_start: Button
var _btn_quit: Button
var _lang_buttons: Array[Button] = []


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

	var am: Node = get_node_or_null("/root/AudioManager")
	if am != null:
		am.stop_music()

	_setup_language_buttons()
	_setup_volume_slider()
	_refresh_texts()
	_refresh_lang_buttons()


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
		_lang_buttons.append(btn)


# Slider volume (0–100%) in basso a destra, sopra i pulsanti lingua.
func _setup_volume_slider() -> void:
	var am: Node = get_node_or_null("/root/AudioManager")
	var init_value: float = (am.get_volume() if am != null else 0.8) * 100.0

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.anchor_left   = 1.0
	hbox.anchor_top    = 1.0
	hbox.anchor_right  = 1.0
	hbox.anchor_bottom = 1.0
	hbox.offset_left   = -252.0
	hbox.offset_top    = -102.0
	hbox.offset_right  = -12.0
	hbox.offset_bottom = -62.0
	add_child(hbox)

	var icon := Label.new()
	icon.text = "🔊"
	icon.add_theme_font_size_override("font_size", 18)
	icon.add_theme_color_override("font_color", COL_GOLD)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	var slider := HSlider.new()
	slider.min_value  = 0.0
	slider.max_value  = 100.0
	slider.step       = 1.0
	slider.value      = init_value
	slider.custom_minimum_size = Vector2(170, 20)
	slider.add_theme_constant_override("grabber_offset", 0)

	# Track background: bordo oro su fondo semitrasparente scuro — ben visibile.
	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0.05, 0.03, 0.0, 0.85)
	style_bg.border_color = COL_GOLD
	style_bg.border_width_left = 1; style_bg.border_width_right  = 1
	style_bg.border_width_top  = 1; style_bg.border_width_bottom = 1
	style_bg.corner_radius_top_left    = 4; style_bg.corner_radius_top_right    = 4
	style_bg.corner_radius_bottom_left = 4; style_bg.corner_radius_bottom_right = 4
	style_bg.content_margin_left  = 2; style_bg.content_margin_right  = 2
	style_bg.content_margin_top   = 6; style_bg.content_margin_bottom = 6
	slider.add_theme_stylebox_override("slider", style_bg)

	# Area riempita: oro pieno.
	var style_fill := StyleBoxFlat.new()
	style_fill.bg_color = COL_GOLD
	style_fill.corner_radius_top_left    = 3; style_fill.corner_radius_top_right    = 3
	style_fill.corner_radius_bottom_left = 3; style_fill.corner_radius_bottom_right = 3
	slider.add_theme_stylebox_override("grabber_area", style_fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", style_fill)

	# Grabber (manopola): cerchio oro visibile.
	slider.add_theme_icon_override("grabber", _make_grabber_texture())

	slider.value_changed.connect(_on_volume_changed)
	hbox.add_child(slider)


# Crea una texture circolare oro per il grabber dello slider.
func _make_grabber_texture() -> ImageTexture:
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius := size / 2.0 - 1.0
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(center)
			if d <= radius:
				img.set_pixel(x, y, COL_GOLD)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _on_volume_changed(p_value: float) -> void:
	var am: Node = get_node_or_null("/root/AudioManager")
	if am != null:
		am.set_volume(p_value / 100.0)


func _on_lang_pressed(locale: String) -> void:
	var lm: Node = get_node_or_null("/root/LocalizationManager")
	if lm != null:
		lm.set_language(locale)
	_refresh_texts()
	_refresh_lang_buttons()


func _refresh_lang_buttons() -> void:
	var active: String = TranslationServer.get_locale()
	var locales: Array = ["it", "en", "es"]
	for i: int in _lang_buttons.size():
		var btn: Button = _lang_buttons[i]
		if locales[i] == active:
			# Attivo: sfondo oro pieno, testo scuro.
			var s := StyleBoxFlat.new()
			s.bg_color = COL_GOLD
			s.corner_radius_top_left    = 6; s.corner_radius_top_right    = 6
			s.corner_radius_bottom_left = 6; s.corner_radius_bottom_right = 6
			btn.add_theme_stylebox_override("normal", s)
			btn.add_theme_color_override("font_color", Color("1a1000"))
		else:
			# Inattivo: semitrasparente con bordo oro.
			var s := StyleBoxFlat.new()
			s.bg_color = Color(0, 0, 0, 0.45)
			s.border_color = COL_GOLD
			s.border_width_left = 1; s.border_width_right  = 1
			s.border_width_top  = 1; s.border_width_bottom = 1
			s.corner_radius_top_left    = 6; s.corner_radius_top_right    = 6
			s.corner_radius_bottom_left = 6; s.corner_radius_bottom_right = 6
			btn.add_theme_stylebox_override("normal", s)
			btn.add_theme_color_override("font_color", COL_GOLD)


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
