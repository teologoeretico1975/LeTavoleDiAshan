# scripts/ui/MainMenu.gd
#
# Schermata iniziale del gioco. Scope minimo: titolo, tagline, pulsante "Inizia".
# Pulsanti aggiuntivi (Continua, Impostazioni, Daily Puzzle, Credits) verranno
# aggiunti quando le relative funzionalità saranno implementate.

extends Control


const COL_BG   := Color("1a1000")
const COL_GOLD := Color("c9a227")


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

	var lbl_title := Label.new()
	lbl_title.text = "Le Tavole di Ashan"
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 48)
	lbl_title.add_theme_color_override("font_color", COL_GOLD)
	lbl_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lbl_title)

	var lbl_tag := Label.new()
	lbl_tag.text = "Un puzzle dimenticato attende"
	lbl_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_tag.add_theme_font_size_override("font_size", 20)
	lbl_tag.add_theme_color_override("font_color", Color("7a6010"))
	lbl_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lbl_tag)

	# Spacer vuoto per separare visivamente tagline e pulsanti.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(spacer)

	vbox.add_child(_make_btn_row("Inizia", _on_start_pressed))

	# Spacer extra per separare visivamente "Esci" dai pulsanti di navigazione.
	var quit_spacer := Control.new()
	quit_spacer.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(quit_spacer)

	vbox.add_child(_make_btn_row("Esci", _on_quit_pressed))


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
	# Centra il pulsante orizzontalmente dentro il VBox usando un HBox wrapper.
	# VBoxContainer estende i figli a tutta la larghezza — senza wrapper il
	# pulsante occuperebbe l'intera larghezza dello schermo.
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
