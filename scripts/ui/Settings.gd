# scripts/ui/Settings.gd
#
# Schermata impostazioni: volume musica e selezione lingua.
# Accessibile da MainMenu e da GameBoard (pulsante ⚙).
# Al ritorno torna alla scena chiamante tramite GameManager.return_from_settings().

extends Control


const COL_GOLD     := Color("c9a227")
const COL_GOLD_DIM := Color("7a6010")
const COL_DARK     := Color("1a1000")

var _lang_buttons:    Array[Button] = []
var _volume_label:    Label
var _sfx_vol_label:   Label


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	# Contenitore verticale centrato.
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 40)
	vbox.anchor_left   = 0.0; vbox.anchor_right  = 1.0
	vbox.anchor_top    = 0.0; vbox.anchor_bottom = 1.0
	add_child(vbox)

	# Titolo.
	var lbl_title := Label.new()
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 38)
	lbl_title.add_theme_color_override("font_color", COL_GOLD)
	lbl_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_title.text = tr("SETTINGS_TITLE")
	vbox.add_child(lbl_title)

	vbox.add_child(_make_separator())
	_build_audio_section(vbox)
	vbox.add_child(_make_separator())
	_build_sfx_section(vbox)
	vbox.add_child(_make_separator())
	_build_language_section(vbox)
	vbox.add_child(_make_separator())
	_build_back_button(vbox)

	_refresh_lang_buttons()


# ---------------------------------------------------------------------------
# Sezione audio
# ---------------------------------------------------------------------------

func _build_audio_section(p_parent: VBoxContainer) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 16)
	p_parent.add_child(section)

	var lbl := Label.new()
	lbl.text = tr("SETTINGS_MUSIC_VOLUME")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", COL_GOLD)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_child(lbl)

	# Riga: 🔊  ──slider──  "80%"
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	section.add_child(hbox)

	var icon := Label.new()
	icon.text = "🔊"
	icon.add_theme_font_size_override("font_size", 22)
	icon.add_theme_color_override("font_color", COL_GOLD)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	var am: Node = get_node_or_null("/root/AudioManager")
	var init_val: float = (am.get_volume() if am != null else 0.8) * 100.0

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step      = 1.0
	slider.value     = init_val
	slider.custom_minimum_size = Vector2(240, 24)
	slider.add_theme_constant_override("grabber_offset", 0)

	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0.05, 0.03, 0.0, 0.85)
	style_bg.border_color = COL_GOLD
	style_bg.border_width_left = 1; style_bg.border_width_right  = 1
	style_bg.border_width_top  = 1; style_bg.border_width_bottom = 1
	style_bg.corner_radius_top_left    = 4; style_bg.corner_radius_top_right    = 4
	style_bg.corner_radius_bottom_left = 4; style_bg.corner_radius_bottom_right = 4
	style_bg.content_margin_left  = 2; style_bg.content_margin_right  = 2
	style_bg.content_margin_top   = 7; style_bg.content_margin_bottom = 7
	slider.add_theme_stylebox_override("slider", style_bg)

	var style_fill := StyleBoxFlat.new()
	style_fill.bg_color = COL_GOLD
	style_fill.corner_radius_top_left    = 3; style_fill.corner_radius_top_right    = 3
	style_fill.corner_radius_bottom_left = 3; style_fill.corner_radius_bottom_right = 3
	slider.add_theme_stylebox_override("grabber_area", style_fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", style_fill)
	slider.add_theme_icon_override("grabber", _make_grabber_texture())

	hbox.add_child(slider)

	_volume_label = Label.new()
	_volume_label.text = "%d%%" % int(init_val)
	_volume_label.custom_minimum_size = Vector2(48, 0)
	_volume_label.add_theme_font_size_override("font_size", 20)
	_volume_label.add_theme_color_override("font_color", COL_GOLD)
	_volume_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_volume_label)

	slider.value_changed.connect(_on_volume_changed)


func _on_volume_changed(p_value: float) -> void:
	if _volume_label != null:
		_volume_label.text = "%d%%" % int(p_value)
	var am: Node = get_node_or_null("/root/AudioManager")
	if am != null:
		am.set_volume(p_value / 100.0)


# ---------------------------------------------------------------------------
# Sezione SFX
# ---------------------------------------------------------------------------

func _build_sfx_section(p_parent: VBoxContainer) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 16)
	p_parent.add_child(section)

	var lbl := Label.new()
	lbl.text = tr("SETTINGS_SFX_VOLUME")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", COL_GOLD)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_child(lbl)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	section.add_child(hbox)

	var icon := Label.new()
	icon.text = "🔔"
	icon.add_theme_font_size_override("font_size", 22)
	icon.add_theme_color_override("font_color", COL_GOLD)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	var am: Node = get_node_or_null("/root/AudioManager")
	var init_val: float = (am.get_sfx_volume() if am != null else 0.8) * 100.0

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step      = 1.0
	slider.value     = init_val
	slider.custom_minimum_size = Vector2(240, 24)

	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0.05, 0.03, 0.0, 0.85)
	style_bg.border_color = COL_GOLD
	style_bg.border_width_left = 1; style_bg.border_width_right  = 1
	style_bg.border_width_top  = 1; style_bg.border_width_bottom = 1
	style_bg.corner_radius_top_left    = 4; style_bg.corner_radius_top_right    = 4
	style_bg.corner_radius_bottom_left = 4; style_bg.corner_radius_bottom_right = 4
	style_bg.content_margin_left  = 2; style_bg.content_margin_right  = 2
	style_bg.content_margin_top   = 7; style_bg.content_margin_bottom = 7
	slider.add_theme_stylebox_override("slider", style_bg)

	var style_fill := StyleBoxFlat.new()
	style_fill.bg_color = COL_GOLD
	style_fill.corner_radius_top_left    = 3; style_fill.corner_radius_top_right    = 3
	style_fill.corner_radius_bottom_left = 3; style_fill.corner_radius_bottom_right = 3
	slider.add_theme_stylebox_override("grabber_area", style_fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", style_fill)
	slider.add_theme_icon_override("grabber", _make_grabber_texture())

	hbox.add_child(slider)

	_sfx_vol_label = Label.new()
	_sfx_vol_label.text = "%d%%" % int(init_val)
	_sfx_vol_label.custom_minimum_size = Vector2(48, 0)
	_sfx_vol_label.add_theme_font_size_override("font_size", 20)
	_sfx_vol_label.add_theme_color_override("font_color", COL_GOLD)
	_sfx_vol_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_sfx_vol_label)

	slider.value_changed.connect(_on_sfx_volume_changed)


func _on_sfx_volume_changed(p_value: float) -> void:
	if _sfx_vol_label != null:
		_sfx_vol_label.text = "%d%%" % int(p_value)
	var am: Node = get_node_or_null("/root/AudioManager")
	if am != null:
		am.set_sfx_volume(p_value / 100.0)


# ---------------------------------------------------------------------------
# Sezione lingua
# ---------------------------------------------------------------------------

func _build_language_section(p_parent: VBoxContainer) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 16)
	p_parent.add_child(section)

	var lbl := Label.new()
	lbl.text = "Lingua / Language / Idioma"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", COL_GOLD)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_child(lbl)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	section.add_child(hbox)

	for locale: String in ["it", "en", "es"]:
		var btn := Button.new()
		btn.text = locale.to_upper()
		btn.custom_minimum_size = Vector2(80, 48)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(_on_lang_pressed.bind(locale))
		hbox.add_child(btn)
		_lang_buttons.append(btn)


func _on_lang_pressed(p_locale: String) -> void:
	var lm: Node = get_node_or_null("/root/LocalizationManager")
	if lm != null:
		lm.set_language(p_locale)
	_refresh_lang_buttons()


func _refresh_lang_buttons() -> void:
	var active: String = TranslationServer.get_locale()
	var locales: Array = ["it", "en", "es"]
	for i: int in _lang_buttons.size():
		var btn: Button = _lang_buttons[i]
		if locales[i] == active:
			var s := StyleBoxFlat.new()
			s.bg_color = COL_GOLD
			s.corner_radius_top_left    = 8; s.corner_radius_top_right    = 8
			s.corner_radius_bottom_left = 8; s.corner_radius_bottom_right = 8
			btn.add_theme_stylebox_override("normal", s)
			btn.add_theme_color_override("font_color", COL_DARK)
		else:
			var s := StyleBoxFlat.new()
			s.bg_color = Color(0, 0, 0, 0.45)
			s.border_color = COL_GOLD
			s.border_width_left = 1; s.border_width_right  = 1
			s.border_width_top  = 1; s.border_width_bottom = 1
			s.corner_radius_top_left    = 8; s.corner_radius_top_right    = 8
			s.corner_radius_bottom_left = 8; s.corner_radius_bottom_right = 8
			btn.add_theme_stylebox_override("normal", s)
			btn.add_theme_color_override("font_color", COL_GOLD)


# ---------------------------------------------------------------------------
# Pulsante Indietro
# ---------------------------------------------------------------------------

func _build_back_button(p_parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	p_parent.add_child(hbox)

	var btn := Button.new()
	btn.text = tr("SETTINGS_BACK")
	btn.custom_minimum_size = Vector2(200, 56)
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", COL_DARK)

	var s_n := StyleBoxFlat.new()
	s_n.bg_color = COL_GOLD
	s_n.corner_radius_top_left    = 10; s_n.corner_radius_top_right    = 10
	s_n.corner_radius_bottom_left = 10; s_n.corner_radius_bottom_right = 10
	var s_h := StyleBoxFlat.new()
	s_h.bg_color = COL_GOLD.lightened(0.15)
	s_h.corner_radius_top_left    = 10; s_h.corner_radius_top_right    = 10
	s_h.corner_radius_bottom_left = 10; s_h.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal",  s_n)
	btn.add_theme_stylebox_override("hover",   s_h)
	btn.add_theme_stylebox_override("pressed", s_h)
	btn.pressed.connect(_on_back_pressed)
	hbox.add_child(btn)


func _on_back_pressed() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.return_from_settings()


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _make_separator() -> Control:
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 4)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep


func _make_grabber_texture() -> ImageTexture:
	var sz := 18
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var center := Vector2(sz / 2.0, sz / 2.0)
	var radius  := sz / 2.0 - 1.0
	for y in sz:
		for x in sz:
			img.set_pixel(x, y, COL_GOLD if Vector2(x, y).distance_to(center) <= radius else Color(0,0,0,0))
	return ImageTexture.create_from_image(img)
