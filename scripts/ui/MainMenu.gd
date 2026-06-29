# scripts/ui/MainMenu.gd

extends Control


const COL_BG   := Color("1a1000")
const COL_GOLD := Color("c9a227")

var _lbl_title: Label
var _lbl_tag:   Label
var _btn_start:    Button
var _btn_daily:    Button
var _btn_settings: Button
var _btn_quit:     Button


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
	vbox.add_theme_constant_override("separation", 16)
	vbox.anchor_left   = 0.0; vbox.anchor_right  = 1.0
	vbox.anchor_top    = 0.0; vbox.anchor_bottom = 1.0
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

	vbox.add_child(_make_spacer(16))

	var hbox_start := _make_btn_row("", _on_start_pressed)
	vbox.add_child(hbox_start)
	_btn_start = hbox_start.get_child(0) as Button

	var hbox_daily := _make_btn_row("", _on_daily_pressed)
	vbox.add_child(hbox_daily)
	_btn_daily = hbox_daily.get_child(0) as Button

	var hbox_settings := _make_btn_row("", _on_settings_pressed)
	vbox.add_child(hbox_settings)
	_btn_settings = hbox_settings.get_child(0) as Button

	vbox.add_child(_make_spacer(8))

	var hbox_quit := _make_btn_row("", _on_quit_pressed)
	vbox.add_child(hbox_quit)
	_btn_quit = hbox_quit.get_child(0) as Button

	var am: Node = get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_menu_music()

	# Pulsante debug — visibile solo nelle build debug (editor + export debug).
	# OS.is_debug_build() è l'equivalente Godot di #if DEBUG in C#:
	# restituisce false negli export release, quindi sparisce in produzione.
	if OS.is_debug_build():
		_build_debug_reset_button()
		_build_debug_unlock_button()

	_refresh_texts()
	_fade_in_from_black()


func _refresh_texts() -> void:
	if _lbl_title    != null: _lbl_title.text    = tr("GAME_TITLE")
	if _lbl_tag      != null: _lbl_tag.text      = tr("TAGLINE")
	if _btn_start    != null: _btn_start.text    = tr("BTN_START")
	if _btn_daily    != null: _btn_daily.text    = tr("DAILY_PUZZLE_TITLE")
	if _btn_settings != null: _btn_settings.text = tr("BTN_SETTINGS")
	if _btn_quit     != null: _btn_quit.text     = tr("BTN_QUIT")


func _make_spacer(p_height: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, p_height)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _make_btn_row(p_label: String, p_callback: Callable) -> HBoxContainer:
	var btn := Button.new()
	btn.text = p_label
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", COL_BG)
	btn.custom_minimum_size = Vector2(280, 62)

	var s_n := StyleBoxFlat.new()
	s_n.bg_color = COL_GOLD
	s_n.corner_radius_top_left     = 10; s_n.corner_radius_top_right    = 10
	s_n.corner_radius_bottom_left  = 10; s_n.corner_radius_bottom_right = 10
	var s_h := StyleBoxFlat.new()
	s_h.bg_color = COL_GOLD.lightened(0.15)
	s_h.corner_radius_top_left     = 10; s_h.corner_radius_top_right    = 10
	s_h.corner_radius_bottom_left  = 10; s_h.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal",  s_n)
	btn.add_theme_stylebox_override("hover",   s_h)
	btn.add_theme_stylebox_override("pressed", s_h)
	btn.pressed.connect(p_callback)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(btn)
	return hbox


func _on_start_pressed() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.goto_chapter_select()


func _on_daily_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/DailyPuzzleScreen.tscn")


func _on_settings_pressed() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.goto_settings("res://scenes/ui/MainMenu.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


# ---------------------------------------------------------------------------
# Transizione ingresso
# ---------------------------------------------------------------------------

func _fade_in_from_black() -> void:
	var black := ColorRect.new()
	black.color        = Color(0.0, 0.0, 0.0, 1.0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var tween := create_tween()
	tween.tween_property(black, "color:a", 0.0, 0.35)
	tween.tween_callback(black.queue_free)


# ---------------------------------------------------------------------------
# Debug only — non raggiungibile nelle build release
# ---------------------------------------------------------------------------

func _build_debug_reset_button() -> void:
	var btn := Button.new()
	btn.text = "[ DEV ] Reset save"
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

	# Sfondo trasparente con bordo rosso tenue — chiaramente "non production".
	var s_n := StyleBoxFlat.new()
	s_n.bg_color    = Color(0.3, 0.0, 0.0, 0.5)
	s_n.border_color = Color(0.8, 0.2, 0.2, 0.8)
	s_n.border_width_left = 1; s_n.border_width_right  = 1
	s_n.border_width_top  = 1; s_n.border_width_bottom = 1
	s_n.corner_radius_top_left     = 6; s_n.corner_radius_top_right    = 6
	s_n.corner_radius_bottom_left  = 6; s_n.corner_radius_bottom_right = 6
	var s_h := s_n.duplicate() as StyleBoxFlat
	s_h.bg_color = Color(0.5, 0.0, 0.0, 0.7)
	btn.add_theme_stylebox_override("normal",  s_n)
	btn.add_theme_stylebox_override("hover",   s_h)
	btn.add_theme_stylebox_override("pressed", s_h)

	# Ancorato in basso a destra — fuori dai percorsi UI normali.
	btn.anchor_left   = 1.0; btn.anchor_right  = 1.0
	btn.anchor_top    = 1.0; btn.anchor_bottom = 1.0
	btn.offset_left   = -190.0; btn.offset_right  = -8.0
	btn.offset_top    = -40.0;  btn.offset_bottom = -8.0

	btn.pressed.connect(_on_debug_reset_pressed)
	add_child(btn)


func _on_debug_reset_pressed() -> void:
	var saver: Node = get_node_or_null("/root/SaveManager")
	if saver != null:
		saver.reset_all()
	get_tree().reload_current_scene()


func _build_debug_unlock_button() -> void:
	var saver: Node = get_node_or_null("/root/SaveManager")
	var is_active: bool = saver != null and saver.is_debug_unlock_active()

	var btn := Button.new()
	btn.name = "DebugUnlockBtn"
	btn.text = "[ DEV ] Unlock OFF" if not is_active else "[ DEV ] Unlock ON"
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color",
		Color(0.4, 1.0, 0.4) if is_active else Color(1.0, 0.85, 0.4))

	var s_n := StyleBoxFlat.new()
	s_n.bg_color    = Color(0.0, 0.2, 0.0, 0.5) if is_active else Color(0.2, 0.15, 0.0, 0.5)
	s_n.border_color = Color(0.2, 0.8, 0.2, 0.8) if is_active else Color(0.8, 0.6, 0.2, 0.8)
	s_n.border_width_left = 1; s_n.border_width_right  = 1
	s_n.border_width_top  = 1; s_n.border_width_bottom = 1
	s_n.corner_radius_top_left     = 6; s_n.corner_radius_top_right    = 6
	s_n.corner_radius_bottom_left  = 6; s_n.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", s_n)

	# Posizionato in basso a destra sopra il pulsante Reset.
	btn.anchor_left   = 1.0; btn.anchor_right  = 1.0
	btn.anchor_top    = 1.0; btn.anchor_bottom = 1.0
	btn.offset_left   = -190.0; btn.offset_right  = -8.0
	btn.offset_top    = -84.0;  btn.offset_bottom = -48.0

	btn.pressed.connect(_on_debug_unlock_pressed)
	add_child(btn)


func _on_debug_unlock_pressed() -> void:
	var saver: Node = get_node_or_null("/root/SaveManager")
	if saver == null:
		return
	if saver.is_debug_unlock_active():
		saver.disable_debug_unlock()
	else:
		saver.enable_debug_unlock()
	# Ricarica per aggiornare lo stato del pulsante e la LevelSelect.
	get_tree().reload_current_scene()
