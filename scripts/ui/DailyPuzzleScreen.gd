# scripts/ui/DailyPuzzleScreen.gd
#
# Schermata del puzzle giornaliero. Mostra:
#   - Se già completato oggi: messaggio con mosse usate e "Torna domani"
#   - Se non completato: pulsante "Gioca" che avvia il GameBoard in daily mode

extends Control


const COL_BG   := Color("1a1000")
const COL_GOLD := Color("c9a227")


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.50)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 28)
	vbox.anchor_left   = 0.0; vbox.anchor_right  = 1.0
	vbox.anchor_top    = 0.0; vbox.anchor_bottom = 1.0
	add_child(vbox)

	var dpm: Node = get_node_or_null("/root/DailyPuzzleManager")

	# Titolo
	var lbl_title := Label.new()
	lbl_title.text = tr("DAILY_PUZZLE_TITLE")
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 42)
	lbl_title.add_theme_color_override("font_color", COL_GOLD)
	lbl_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lbl_title)

	# Data
	var date_str: String = dpm.get_today_date_string() if dpm != null else ""
	var lbl_date := Label.new()
	lbl_date.text = date_str
	lbl_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_date.add_theme_font_size_override("font_size", 22)
	lbl_date.add_theme_color_override("font_color", Color("7a6010"))
	lbl_date.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lbl_date)

	# Sottotitolo / stato
	var lbl_sub := Label.new()
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.add_theme_font_size_override("font_size", 20)
	lbl_sub.add_theme_color_override("font_color", COL_GOLD)
	lbl_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lbl_sub)

	vbox.add_child(_make_spacer(16))

	var completed: bool = dpm != null and dpm.is_completed_today()

	if completed:
		var moves: int = dpm.get_today_moves() if dpm != null else 0
		lbl_sub.text = tr("DAILY_PUZZLE_COMPLETED")

		var lbl_moves := Label.new()
		lbl_moves.text = "%s: %d" % [tr("DAILY_PUZZLE_MOVES"), moves]
		lbl_moves.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_moves.add_theme_font_size_override("font_size", 26)
		lbl_moves.add_theme_color_override("font_color", COL_GOLD)
		lbl_moves.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(lbl_moves)

		var lbl_ret := Label.new()
		lbl_ret.text = tr("DAILY_PUZZLE_RETURN")
		lbl_ret.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_ret.add_theme_font_size_override("font_size", 18)
		lbl_ret.add_theme_color_override("font_color", Color("7a6010"))
		lbl_ret.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(lbl_ret)
	else:
		lbl_sub.text = tr("DAILY_PUZZLE_SUBTITLE")

		var hbox := HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(hbox)
		var btn_play := _make_button(tr("BTN_START"), _on_play_pressed)
		hbox.add_child(btn_play)

	vbox.add_child(_make_spacer(24))

	# Pulsante "< Menu"
	var hbox_back := HBoxContainer.new()
	hbox_back.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox_back)
	var btn_back := _make_back_button(tr("BTN_BACK_MENU"), _on_back_pressed)
	hbox_back.add_child(btn_back)

	_fade_in_from_black()


func _on_play_pressed() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.goto_daily_puzzle()


func _on_back_pressed() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.goto_main_menu()


# ---------------------------------------------------------------------------
# Helper costruzione UI
# ---------------------------------------------------------------------------

func _make_spacer(p_height: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, p_height)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _make_button(p_text: String, p_callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = p_text
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", COL_BG)
	btn.custom_minimum_size = Vector2(200, 56)

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
	return btn


func _make_back_button(p_text: String, p_callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = p_text
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", COL_GOLD)
	var s_n := StyleBoxFlat.new()
	s_n.bg_color = Color(0, 0, 0, 0)
	var s_h := StyleBoxFlat.new()
	s_h.bg_color = Color(1.0, 0.85, 0.1, 0.15)
	btn.add_theme_stylebox_override("normal",  s_n)
	btn.add_theme_stylebox_override("hover",   s_h)
	btn.add_theme_stylebox_override("pressed", s_h)
	btn.pressed.connect(p_callback)
	return btn


# ---------------------------------------------------------------------------
# Fade-in
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
