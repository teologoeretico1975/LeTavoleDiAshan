# scripts/managers/localization_manager.gd
#
# Autoload che inizializza la lingua al primo frame, prima che qualsiasi scena
# costruisca la propria UI. Deve essere registrato DOPO SaveManager nell'elenco
# Autoload (Project Settings → Autoload) in modo che SaveManager sia già
# disponibile quando questo _ready() viene eseguito.
#
# Logica di selezione lingua:
#   1. Lingua salvata in SaveManager → ha la precedenza (scelta esplicita utente)
#   2. Lingua del sistema operativo, se supportata (it/en/es) → primo avvio
#   3. Fallback "en" → sistema con lingua non supportata

extends Node

const SUPPORTED_LOCALES: Array = ["it", "en", "es"]
const FALLBACK_LOCALE:   String = "en"


func _ready() -> void:
	var saver: Node = get_node_or_null("/root/SaveManager")

	# Se esiste una preferenza salvata, la usiamo direttamente.
	if saver != null:
		var saved: String = saver.get_language()
		# get_language() ritorna "it" come default anche se non esiste una voce
		# esplicita nel file di salvataggio. Distinguiamo i due casi controllando
		# se la chiave è presente nel dato grezzo.
		if saver.has_language_saved():
			TranslationServer.set_locale(saved)
			return

	# Primo avvio (nessuna preferenza salvata): rileva la lingua del sistema.
	var os_lang: String = OS.get_locale_language()
	var locale: String = os_lang if os_lang in SUPPORTED_LOCALES else FALLBACK_LOCALE

	TranslationServer.set_locale(locale)
	if saver != null:
		saver.set_language(locale)


# Cambia la lingua attiva, la applica immediatamente e la persiste.
# Chiamata dai pulsanti IT/EN/ES in MainMenu.
func set_language(p_locale: String) -> void:
	if p_locale not in SUPPORTED_LOCALES:
		push_warning("LocalizationManager: locale '%s' non supportato." % p_locale)
		return
	TranslationServer.set_locale(p_locale)
	var saver: Node = get_node_or_null("/root/SaveManager")
	if saver != null:
		saver.set_language(p_locale)
