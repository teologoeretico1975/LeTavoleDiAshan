# scripts/managers/audio_manager.gd
#
# Autoload singleton: gestisce la musica ambientale per capitolo.
#
# Flusso tipico:
#   GameBoard._ready() → AudioManager.fade_to_chapter(chapter)
#   MainMenu._ready() → AudioManager.stop_music()
#
# Il crossfade usa due AudioStreamPlayer: uno per la traccia corrente (fade out)
# e uno per quella nuova (fade in). Al termine del crossfade il player "out"
# viene silenziato e il player "in" diventa quello corrente.

extends Node

const MUSIC_DIR      := "res://assets/audio/music/"
const DEFAULT_VOLUME := 0.8          # 0.0 – 1.0, corrisponde a ~-2 dB
const VOLUME_KEY     := "music_volume"

# Mappa capitolo → nome file OGG (senza directory).
const TRACKS: Dictionary = {
	1: "chapter_01.ogg",
	2: "chapter_02.ogg",
	3: "chapter_03.ogg",
	4: "chapter_04.ogg",
	5: "chapter_05.ogg",
	6: "chapter_06.ogg",
}

# Due player per il crossfade: "A" è quello correntemente audibile.
var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer

# Volume lineare corrente (0.0–1.0) — convertito in dB per i player.
var _volume: float = DEFAULT_VOLUME

# Capitolo in riproduzione (-1 = nessuno).
var _current_chapter: int = -1

# True durante un crossfade — impedisce di accodare più fade contemporanei.
var _fading: bool = false


func _ready() -> void:
	_player_a = AudioStreamPlayer.new()
	_player_a.name = "PlayerA"
	add_child(_player_a)

	_player_b = AudioStreamPlayer.new()
	_player_b.name = "PlayerB"
	add_child(_player_b)

	# Legge il volume salvato da SaveManager se disponibile.
	var saver: Node = get_node_or_null("/root/SaveManager")
	if saver != null and saver.has_volume_saved():
		_volume = saver.get_music_volume()
	_apply_volume_to_player(_player_a, _volume)
	_apply_volume_to_player(_player_b, 0.0)


# ---------------------------------------------------------------------------
# API pubblica
# ---------------------------------------------------------------------------

# Riproduce la traccia del capitolo p_chapter con loop.
# Non fa nulla se la traccia è già quella corrente.
func play_chapter_music(p_chapter: int) -> void:
	if p_chapter == _current_chapter and _player_a.playing:
		return
	var stream := _load_track(p_chapter)
	if stream == null:
		return
	_current_chapter = p_chapter
	_player_a.stream = stream
	_player_a.volume_db = _linear_to_db(_volume)
	_player_a.play()


# Ferma immediatamente la musica.
func stop_music() -> void:
	_current_chapter = -1
	_fading = false
	_player_a.stop()
	_player_b.stop()


# Crossfade dalla traccia corrente alla traccia del capitolo p_chapter.
# Se la traccia è già quella corrente non fa nulla.
# duration: durata totale del crossfade in secondi (fade-out = duration/2, fade-in = duration/2).
func fade_to_chapter(p_chapter: int, duration: float = 1.5) -> void:
	if p_chapter == _current_chapter and _player_a.playing:
		return
	if _fading:
		# Fade già in corso: aggiorniamo subito al nuovo capitolo senza aspettare.
		_player_a.stop()
		_player_b.stop()
		_fading = false
		_current_chapter = -1

	var new_stream := _load_track(p_chapter)
	if new_stream == null:
		return

	_fading = true
	_current_chapter = p_chapter

	# Player B parte silenzioso con la nuova traccia.
	_player_b.stream = new_stream
	_player_b.volume_db = _linear_to_db(0.0)
	_player_b.play()

	var half: float = duration / 2.0

	# Fase 1: fade out di A in half secondi.
	var tween := create_tween()
	tween.tween_method(_set_volume_a, _volume, 0.0, half)

	# Fase 2: fade in di B da 0 a _volume in half secondi.
	tween.tween_method(_set_volume_b, 0.0, _volume, half)

	tween.tween_callback(func() -> void:
		# Swap: A diventa la traccia corrente, B torna silenzioso.
		_player_a.stop()
		_player_a.stream   = _player_b.stream
		_player_a.volume_db = _linear_to_db(_volume)
		_player_a.play()
		# Riposiziona allo stesso punto di B per continuità.
		_player_a.seek(_player_b.get_playback_position())
		_player_b.stop()
		_player_b.volume_db = _linear_to_db(0.0)
		_fading = false
	)


# Imposta il volume master (0.0 = silenzio, 1.0 = massimo).
# Aggiorna immediatamente i player e persiste in SaveManager.
func set_volume(p_linear: float) -> void:
	_volume = clampf(p_linear, 0.0, 1.0)
	if not _fading:
		_apply_volume_to_player(_player_a, _volume)
	var saver: Node = get_node_or_null("/root/SaveManager")
	if saver != null:
		saver.set_music_volume(_volume)


func get_volume() -> float:
	return _volume


# ---------------------------------------------------------------------------
# Metodi interni
# ---------------------------------------------------------------------------

func _load_track(p_chapter: int) -> AudioStream:
	if not TRACKS.has(p_chapter):
		push_warning("AudioManager: nessuna traccia per capitolo %d." % p_chapter)
		return null
	var path: String = MUSIC_DIR + TRACKS[p_chapter]
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: file non trovato: %s" % path)
		return null
	var stream := ResourceLoader.load(path) as AudioStream
	if stream == null:
		push_warning("AudioManager: impossibile caricare %s." % path)
		return null
	# Abilita il loop sull'AudioStreamOggVorbis se disponibile.
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream


func _linear_to_db(p_linear: float) -> float:
	if p_linear <= 0.0:
		return -80.0
	return linear_to_db(p_linear)


func _apply_volume_to_player(p_player: AudioStreamPlayer, p_linear: float) -> void:
	p_player.volume_db = _linear_to_db(p_linear)


# Callback per tween.tween_method — imposta il volume di player A.
func _set_volume_a(p_linear: float) -> void:
	_apply_volume_to_player(_player_a, p_linear)


# Callback per tween.tween_method — imposta il volume di player B.
func _set_volume_b(p_linear: float) -> void:
	_apply_volume_to_player(_player_b, p_linear)
