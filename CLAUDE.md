# Le Tavole di Ashan — CLAUDE.md

## Progetto

Puzzle game (N-puzzle / 15-puzzle) con lore dark fantasy, target Android e Windows.
Motore: **Godot 4.6**, linguaggio: **GDScript** (non C#).
Sviluppatore: programmatore esperto C#/.NET, principiante Godot.

---

## Struttura cartelle

```
le-tavole-di-ashan/
├── scenes/
│   ├── ui/          # schermate UI pure (MainMenu, ChapterSelect, LevelSelect…)
│   ├── game/        # scene di gameplay (Board, Tile, GameScreen…)
│   └── shared/      # componenti riusabili (StarRating, HintButton, Dialog…)
├── scripts/
│   ├── core/        # logica pura senza nodi Godot (solver A*, generator, validator)
│   ├── managers/    # Autoload/singleton (GameManager, SaveManager, AudioManager…)
│   └── ui/          # controller delle scene in scenes/ui/ e scenes/game/
├── data/
│   ├── levels/      # definizione livelli per capitolo (JSON o Resource .tres)
│   ├── chapters/    # metadati capitoli (palette, titolo, unlock condition)
│   └── config/      # costanti globali, bilanciamento economia, configurazione hint
├── assets/
│   ├── art/         # sprite, texture, sfondi (sottocartelle per capitolo)
│   ├── audio/
│   │   ├── music/   # tracce musicali
│   │   └── sfx/     # effetti sonori
│   ├── fonts/       # .ttf / .otf
│   └── shaders/     # .gdshader
└── addons/          # plugin di terze parti
```

---

## Naming conventions (GDScript)

### File e scene
- Scene: `PascalCase.tscn` → `GameScreen.tscn`, `ChapterSelect.tscn`
- Script: `PascalCase.gd` — stesso nome della scena che controlla, o del concetto → `PuzzleSolver.gd`
- Dati JSON: `snake_case.json` → `chapter_01.json`, `daily_puzzle.json`
- Resource Godot: `snake_case.tres` → `level_001.tres`

### Codice GDScript
- Classi: `PascalCase` (con `class_name`)
- Variabili e funzioni: `snake_case`
- Costanti: `SCREAMING_SNAKE_CASE`
- Segnali: `snake_case`, prefisso participio passato → `level_completed`, `tile_moved`
- Variabili private (convenzione, non enforced): prefisso `_` → `_current_state`

### Nodi nella scena
- Nodi Godot: `PascalCase` → `BoardContainer`, `HintButton`, `StarLabel`

---

## Principio architetturale fondamentale: separare logica pura da nodi Godot

Le classi in `scripts/core/` **non devono mai** fare `extends Node` né accedere
all'albero di scena. Devono essere classi pure (`extends RefCounted` o `extends Object`)
che ricevono dati in input e restituiscono dati in output.

```gdscript
# CORRETTO — scripts/core/puzzle_solver.gd
class_name PuzzleSolver
extends RefCounted

func solve(board: Array) -> int:
    # calcola mosse ottimali con A*, non tocca mai nodi
    ...

# SCORRETTO — mescolare logica e nodo
func solve() -> void:
    var label = $MoveCountLabel   # ← dipendenza dal nodo: da evitare in core/
    label.text = str(_count_moves())
```

I controller in `scripts/ui/` e i manager in `scripts/managers/` usano le classi
core come strumenti, e comunicano con le scene tramite **segnali**.

---

## Decisione architetturale: solver offline vs hint runtime

Due strumenti distinti, con complessità e contesti d'uso opposti:

| | `PuzzleSolver.solve()` | `HintSolver.suggest_move()` |
|---|---|---|
| **Algoritmo** | A* (ricerca esaustiva) | Greedy one-step (Manhattan) |
| **Complessità** | Esponenziale nel caso peggiore | O(k × N²), sempre costante |
| **Tempo 4x4** | Da ms a ore (dipende dalla profondità) | < 0.1 ms in ogni caso |
| **Uso** | Generazione offline dei livelli | Hint in-game, real-time |
| **Ottimale?** | Sì, garantito | No, greedy (buono ma non ottimale) |

**Contesto:** A* + Manhattan sul 15-puzzle supera 500 000 nodi già a ~30–40 mosse
di profondità e non termina in tempi accettabili oltre quella soglia.
`suggest_move()` è istantaneo su qualsiasi stato ed è l'unico approccio
praticabile per hint chiamati a runtime durante la partita.

Per i livelli con `optimal_moves` elevato (Capitoli V–VI), il valore va
pre-calcolato offline con uno script esterno (Python/C#) e salvato nel JSON
del livello — non calcolato a runtime da `PuzzleSolver`.

---

## Pattern: comunicazione tra nodi

Preferire sempre i segnali Godot al posto delle chiamate dirette tra nodi.

```gdscript
# Emettere
signal tile_moved(from_index: int, to_index: int)
emit_signal("tile_moved", 3, 4)

# Ascoltare (in @ready o via editor)
board.tile_moved.connect(_on_tile_moved)
```

I manager Autoload possono essere chiamati direttamente (`GameManager.save()`),
ma i nodi di scena non devono mai chiamarsi a vicenda direttamente — usare segnali.

---

## Autoload (singleton)

Registrati in `Project → Project Settings → Autoload`:

| Nome              | Script                              | Responsabilità                          |
|-------------------|-------------------------------------|-----------------------------------------|
| `GameManager`     | `scripts/managers/game_manager.gd`  | stato globale di gioco, capitoli, monete |
| `SaveManager`     | `scripts/managers/save_manager.gd`  | salvataggio/caricamento su disco        |
| `AudioManager`    | `scripts/managers/audio_manager.gd` | musica e SFX                            |
| `LevelLoader`     | `scripts/managers/level_loader.gd`  | caricamento dati livelli da data/       |

---

## Dati livelli

Ogni livello è definito come risorsa (JSON o `.tres`), mai hardcoded.

Campi minimi di un livello:

```json
{
  "id": "01_001",
  "chapter": 1,
  "grid_size": 3,
  "initial_state": [1, 4, 2, 7, 0, 3, 8, 5, 6],
  "optimal_moves": 12,
  "par_1_star": 20,
  "par_2_star": 16,
  "par_3_star": 12
}
```

`initial_state`: array piatto, `0` rappresenta la casella vuota.
`optimal_moves`: calcolato offline con A* prima di esportare i dati.

### Tecnica MD-increasing per generazione 3×3

Per il Capitolo I (3×3) `optimal_moves` è garantito senza eseguire A*
usando la tecnica **MD-increasing**: si applica una sequenza di K mosse
non-inverse dallo stato risolto scegliendo ad ogni passo una mossa che
aumenta la Manhattan distance di esattamente 1. Se MD(stato) = K e il
percorso ha lunghezza K, allora `optimal_moves = K` per la doppia
disuguaglianza `MD ≤ optimal ≤ path_length`.

Per i **Capitoli II–VI (4×4)** MD-increasing è stata verificata in vivo:
- BFS Python offline: raggiungibile almeno fino a MD=34+
- Capitolo II (15–28): confermato, zero fallback
- Capitolo III (28–42): confermato, ceiling > 42 su 4×4
- Capitolo IV (40–52): confermato, ceiling > 52 su 4×4 (51-52 richiedono ~3s/livello)
- Capitolo V (44–52): 19/20 livelli — MD=52 instabile (1 skip su 2 tentativi, ceiling pratico ~51)
Per i capitoli con target >52 mosse, reverificare con `GenerateChapter0X.gd`:
se compaiono SKIP nel log, il ceiling è stato raggiunto e servono fallback offline.

**Nota implementativa:** il generatore `GenerateChapter02.gd` usa MD-increasing
con retry: un percorso casuale può finire in dead end anche se il target è
raggiungibile, quindi si riparte da zero finché non riesce. Con K≤28 ogni
tentativo è O(K), quindi anche 10 000 retry sono istantanei.

---

## Target di export

| Piattaforma | Preset nome    | Note                                      |
|-------------|----------------|-------------------------------------------|
| Android     | `Android`      | minSdk 24, target orientamento portrait   |
| Windows     | `Windows`      | x86_64, eseguibile standalone             |

Configurare in `Project → Export`. I template di export vanno scaricati separatamente
dall'editor Godot (`Editor → Manage Export Templates`).

---

## Stile e qualità del codice

- Ogni script deve avere `class_name` se è destinato a essere istanziato o riferito altrove.
- Usare type hints ovunque: `var count: int`, `func get_board() -> Array`.
- Niente logica nel `_ready()` oltre all'inizializzazione dei riferimenti a nodi figli.
  La logica di business va in funzioni con nome esplicito chiamate da `_ready()`.
- Preferire `@export` per i parametri configurabili dall'editor invece di costanti hardcoded.
- I commenti spiegano il **perché**, non il cosa. Il codice ben nominato spiega il cosa.

---

## Lezioni architetturali emerse dallo sviluppo

### Non aggiornare UI in modo incrementale da callback asincroni

**Problema riscontrato:** `tween_callback` catturava `blank_index` al momento
del click. Il panel del blank non veniva animato (solo la tile cliccata si muove),
quindi rimaneva fisicamente nella posizione originale. Alla mossa successiva
diventava visibile in quella posizione sbagliata, sovrapposto alla tile successiva.

**Pattern corretto:** dopo ogni cambiamento di stato logico, ri-renderizzare
l'intera UI da zero partendo dallo stato — non fare aggiornamenti incrementali
(es. "sposta solo questo panel"). In `_refresh_tiles()` tutte le `position`
vengono ricalcolate per tutti i panel, non solo per quello animato. Il nodo
appena animato viene riposizionato alla stessa coordinata in cui si trova già
(operazione idempotente), il blank viene correttamente piazzato nella sua nuova
cella. Questo elimina qualsiasi deriva accumulata tra stato logico e stato visivo.

**Regola generale:** le callback asincrone (tween, timer, segnali differiti)
devono **leggere lo stato attuale** al momento dell'esecuzione, non dipendere
da variabili catturate al momento della registrazione.

### TextureRect: expand_mode e minimum size

**Problema riscontrato:** `TextureRect` con `expand_mode = EXPAND_KEEP_SIZE` (default) usa le
dimensioni della texture come `minimum_size` del nodo. Con una texture 521×521 e un tile 120×120,
il minimum size effettivo era 521px — i tile traboccavano dal board_container creando layout caotico.

**Pattern corretto:**
```gdscript
tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # minimum_size = 0, non dipende dalla texture
tile.size = Vector2(TILE_SIZE, TILE_SIZE)
tile.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
```

**Regola generale:** quando si usa `TextureRect` con dimensione fissa (tile, icone, sprite),
impostare sempre `expand_mode = EXPAND_IGNORE_SIZE` per disaccoppiare la dimensione del nodo
da quella della texture.

### Layout figli di Control non-Container: usare il nodo diretto, non un wrapper

**Problema riscontrato:** tile implementato come `Panel` con `TextureRect` e `Label` figli.
`TextureRect` e `Label` con `size` manuale vengono ridimensionati dal layout pass di Godot
dopo l'inserimento nell'albero di scena, perché il Panel non è un Container e non blocca
il layout dei figli. Diverse combinazioni di `size`/`custom_minimum_size`/anchors
non risolvevano il problema — i figli mantenevano dimensioni errate a runtime.

**Pattern corretto:** usare `TextureRect` direttamente come nodo root del tile.
La texture è intrinseca al nodo, non un figlio separato. Il solo figlio è la `Label`.
```gdscript
var tile := TextureRect.new()
tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
tile.stretch_mode = TextureRect.STRETCH_SCALE
tile.size = Vector2(TILE_SIZE, TILE_SIZE)
tile.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
# Label come unico figlio
```

**Regola generale:** se un nodo visivo deve avere una texture come sfondo, preferire
`TextureRect` come root rispetto a `Panel + TextureRect figlio`. Il layout dei figli
in Control non-Container è meno prevedibile di quanto sembri.

### Trasparenza su PNG RGB: usare uno shader canvas_item

**Problema:** il PNG `stonetile256x256.png` è RGB senza canale alpha (color type 2).
Lo sfondo scuro è pixel solidi opachi — non si può rendere trasparente via proprietà del nodo.

**Soluzione:** `ShaderMaterial` con shader `canvas_item` che calcola la luminanza e usa
`smoothstep` per fare alpha fade sui pixel scuri:
```glsl
shader_type canvas_item;
uniform float cutoff : hint_range(0.0, 1.0) = 0.12;
uniform float feather : hint_range(0.0, 0.2) = 0.06;
void fragment() {
    vec4 col = texture(TEXTURE, UV);
    float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    COLOR = vec4(col.rgb, smoothstep(cutoff, cutoff + feather, luma));
}
```
Lo shader è in `assets/shaders/stone_tile.gdshader`.

### Non aggiornare UI in modo incrementale da callback asincroni

**Problema riscontrato:** in `_make_tile(board_index)`, il segnale `gui_input`
veniva connesso con `.bind(board_index)`. Dopo ogni mossa i panel vengono
scambiati in `_tile_nodes`, quindi un panel che era alla posizione `i` si
trova ora alla posizione `j` — ma il suo callback riporta ancora `i`.
La mossa veniva scartata perché `i` non era adiacente al blank.

**Pattern corretto:** passare il riferimento al nodo stesso (`.bind(panel)`)
e cercare la posizione corrente dinamicamente al momento del click:
```gdscript
_try_move(_tile_nodes.find(panel))
```

**Regola generale:** quando i nodi di una lista vengono riordinati, i loro
callback non devono dipendere dall'indice originale — devono ricavarlo
dinamicamente dalla struttura dati aggiornata.

### Label in ScrollContainer: custom_minimum_size dopo layout stabilizzato

**Problema:** `Label` dentro `ScrollContainer` — Godot 4 non propaga la larghezza
del container al figlio, quindi `autowrap_mode` non si attiva e il testo si estende
fuori dallo schermo invisibilmente.

**Pattern corretto:**
```gdscript
label.size_flags_horizontal = Control.SIZE_FILL  # non EXPAND_FILL
# Dopo almeno 3 frame di layout:
label.custom_minimum_size.x = scroll_container.size.x
```
`SIZE_FILL` (non `SIZE_EXPAND_FILL`) evita che il Label espanda il container.
`custom_minimum_size.x` imposta la larghezza effettiva per il wrapping.

**Regola generale:** impostare `custom_minimum_size` solo dopo che il layout è
stabilizzato (≥2 frame dopo `_ready()`). Farlo in `_start_sequence()` con
`await get_tree().process_frame` ripetuto.

### Transizioni tra schermate: fade verso nero, non verso trasparente

**Problema:** fade-out di un CanvasLayer overlay verso `modulate.a = 0` rivela
la scena sottostante (GameBoard con overlay stelle ancora visibile) producendo
un flash indesiderato prima del cambio scena.

**Pattern corretto:** aggiungere un `ColorRect` nero sopra l'overlay e fare
fade-in di quello (da alpha 0 a 1), poi cambiare scena. La nuova scena appare
"da nero" con il suo fade-in — transizione pulita e coerente.

```gdscript
var black := ColorRect.new()
black.color = Color(0, 0, 0, 0)
black.set_anchors_preset(Control.PRESET_FULL_RECT)
parent.add_child(black)
var tween := create_tween()
tween.tween_property(black, "color:a", 1.0, 0.4)
await tween.finished
get_tree().change_scene_to_file(destination)
```

**Regola generale:** il fade-out verso trasparente rivela sempre ciò che c'è sotto.
Quando la scena sottostante non deve essere vista, fare fade verso nero.

### OS.is_debug_build() come gate per codice debug-only

**Pattern:** `OS.is_debug_build()` restituisce `true` nell'editor e negli export
debug, `false` negli export release. Equivalente di `#if DEBUG` in C#.
Usato per il pulsante "Reset save" in MainMenu — non richiede flag di configurazione,
è automatico in base al tipo di build.

### Cifratura save con FileAccess.open_encrypted_with_pass()

**API Godot 4:** `FileAccess.open_encrypted_with_pass(path, mode, key_string)` —
chiave derivata via SHA-256 dalla stringa, cifratura AES-256. Alternativa alla
cifratura custom, integrata nel motore.

**Nota critica:** non modificare mai la chiave (`_SAVE_KEY`) dopo il rilascio —
i save esistenti degli utenti diventerebbero illeggibili senza recovery.

**Migrazione:** aprire encrypted, se fallisce aprire plain text, ri-salvare
encrypted — gli utenti con save legacy li trovano convertiti al prossimo avvio.

---

## Stato avanzamento progetto

### Core e gameplay

| Componente | Stato |
|---|---|
| `BoardState` (core) | ✅ completo, testato |
| `PuzzleSolver` A* (core) | ✅ completo, limite nodi confermato ~30 mosse 4×4 |
| `HintSolver` greedy (core) | ✅ completo, istantaneo su qualsiasi stato |
| `LevelLoader` (Autoload) | ✅ completo — carica `chapter_0X.json` on-demand, cache in memoria; `get_level()` / `get_chapter_info()` / `get_chapter_title()` |
| `SaveManager` (Autoload) | ✅ completo — persistenza `user://save.bin` **cifrato AES-256** (`FileAccess.open_encrypted_with_pass`); stelle, sblocco livelli/capitoli, monete, hint, lingua, volume musica+SFX, diari visti, record daily puzzle; migrazione automatica da `save.json` legacy (con eliminazione del file legacy dopo migrazione) |
| `GameManager` (Autoload) | ✅ completo — blackboard per navigazione tra scene (`selected_chapter`, `selected_level`, `is_daily_mode`); `goto_game_board()` / `goto_level_select()` / `goto_chapter_select()` / `goto_main_menu()` / `goto_settings()` / `return_from_settings()` / `goto_daily_puzzle()` / `return_from_daily()` |
| `DailyPuzzleManager` (Autoload) | ✅ completo — generazione deterministica da data (seed = anno×10000+mese×100+giorno), MD-increasing TARGET_MD=27, `get_today_puzzle()` / `is_completed_today()` / `mark_completed_today()` / `get_today_date_string()` localizzato IT/EN/ES |
| `MainMenu.tscn` + script | ✅ completo — titolo, tagline, pulsanti "Inizia", "Il Puzzle di Oggi", "Impostazioni", "Esci"; **Main Scene del progetto** |
| `ChapterSelect.tscn` + script | ✅ completo — lista verticale 6 capitoli con titolo narrativo, progresso (livelli/stelle), sblocco progressivo; pulsante "< Menu" |
| `LevelSelect.tscn` + script | ✅ completo — griglia 4 colonne con stato per livello (bloccato/stelle); legge `LevelLoader` + `SaveManager`; naviga a `GameBoard` al click |
| `GameBoard.tscn` + script | ✅ completo — griglia cliccabile, tween, HUD completo (titolo, mosse, monete `✦`, pulsante Hint con label dinamica); overlay Level Complete (stelle sequenziali, mosse/par, monete guadagnate, "Avanti"/"Mappa"); flash tile hint (`_flash_tile_hint`); pulsante "< Mappa" + ESC; **modalità Daily** (`_is_daily_mode`): no stelle/monete/DiaryScreen, torna a DailyPuzzleScreen |
| `DailyPuzzleScreen.tscn` + script | ✅ completo — mostra data localizzata, sottotitolo; se non completato: pulsante "Inizia"; se già completato: mosse usate + "Torna domani"; fade-in da nero |
| `DiaryScreen.tscn` + script | ✅ completo — CanvasLayer overlay post-livello; frammenti diario Frate Sybelius localizzati IT/EN/ES; autoscroll 40px/s; pulsante "Continua"; seen-once logic con migrazione save; fade-in/out |
| `TestAllLevelsPlaythrough` | ✅ 111/111 livelli passati — playthrough 50 mosse per livello, verifica invarianti sync UI/logica |
| `TestSaveManager` | ✅ 9/9 test passati — salvataggio, miglioramento, persistenza su disco, sblocco sequenziale |

### Dati livelli (tutti i 6 capitoli completati)

| File | Stato |
|---|---|
| `chapter_01.json` | ✅ 12 livelli 3×3, optimal 5–16, **titoli evocativi definitivi** |
| `chapter_02.json` | ✅ 20 livelli 4×4, optimal 15–28, **titoli evocativi definitivi** |
| `chapter_03.json` | ✅ 20 livelli 4×4, optimal 28–42, **titoli evocativi definitivi** |
| `chapter_04.json` | ✅ 20 livelli 4×4, optimal 40–52, **titoli evocativi definitivi** |
| `chapter_05.json` | ✅ 19 livelli 4×4, optimal 44–52, **titoli evocativi definitivi** (1 skip MD=52) |
| `chapter_06.json` | ✅ 20 livelli 4×4, optimal 48–52, par_moves×1.2, **titoli evocativi definitivi** |
| `chapters.json` | ✅ titoli narrativi dei 6 capitoli in `data/chapters/` |

Tutti i generatori `GenerateChapter01–06.gd` usano MD-increasing pura con seed fisso.
Ceiling MD-increasing su 4×4: **~51 stabile, 52 borderline** (timeout a 55+).

### Loop di navigazione completo

```
MainMenu (Main Scene) → ChapterSelect → LevelSelect → GameBoard → LevelSelect → ChapterSelect → MainMenu
MainMenu → DailyPuzzleScreen → GameBoard (daily mode) → DailyPuzzleScreen
```

### Stato verticale

**Vertical slice completo e giocabile:** 111 livelli (Cap I: 12×3×3, Cap II–VI: 99×4×4), 6 capitoli con titoli lore definitivi, progressione, stelle, monete, hint, pulsante Esci. Loop di navigazione integro dalla Main Scene all'overlay di fine livello. Export Windows e Android funzionanti.

### Completato in sessione (2026-06-21)

| Componente | Note |
|---|---|
| Export Android | Ambiente configurato (JDK 17, NDK r23c, SDK), testato su Samsung Galaxy S21+, portrait bloccato (`orientation=6`) |
| Titoli evocativi Cap II–VI | Tutti i 111 livelli hanno titoli lore definitivi. Cap V: 19 livelli, Cap VI: 20 livelli |
| Pulsante "Esci" MainMenu | `get_tree().quit()`, stesso stile degli altri pulsanti, separatore visivo sopra |

### Completato in sessione (2026-06-27)

| Componente | Note |
|---|---|
| Sfondo atmosferico | `main_menu_bg.jpg` su tutte le schermate; overlay ColorRect per capitolo in GameBoard |
| Localizzazione IT/EN/ES | 137 chiavi CSV, `LocalizationManager` autoload, selezione lingua in Settings |
| `AudioManager` (Autoload) | Musica ambientale per capitolo, crossfade 1.5s, volume persistito |
| `Settings.tscn` + script | Volume musica (slider + %) e lingua; accessibile da MainMenu e GameBoard (⚙) |
| `GameManager` | `goto_settings()` / `return_from_settings()` con scena di ritorno |

### Strategia di monetizzazione

Modello **freemium**:
- **Capitoli I–II gratuiti** (32 livelli) — sufficiente per dimostrare il gameplay e il lore
- **Sblocco completo IAP 0.99€** — capitoli III–VI (79 livelli), acquisto una tantum, nessun consumabile
- **Daily Puzzle gratuito permanente** — leva di retention giornaliera, disponibile a tutti gli utenti anche senza acquisto
- Nessun ads, nessun pay-to-win: il gioco è volutamente premium nel tono, coerente con l'estetica dark fantasy

### Completato in sessione (2026-06-27 — tile art)

| Componente | Note |
|---|---|
| Tile art — struttura | Tile come `TextureRect` root; `expand_mode=EXPAND_IGNORE_SIZE`; `STRETCH_KEEP_ASPECT_COVERED`; `TILE_GAP=3px` |
| Tile art — font | Cinzel Decorative Regular, oro `Color(0.9,0.78,0.35)`, outline nero size 3, shadow offset (2,2) |
| Tile art — texture | `stonetile256x256.png` (521×521 reali, PNG con alpha nativo) — nessuno shader |
| Board background | `TextureRect "BoardBackground"` figlio di `_board_container`: `STRETCH_SCALE`, `BG_PADDING=30px`, `modulate=Color(0.92,0.80,0.45)` (oro desaturato) |
| Tile art — stato | ✅ accettabile per ora — si riprenderà in futuro per ulteriori rifinitura |

### Completato in sessione (2026-06-27 — UI polish)

| Componente | Note |
|---|---|
| Theme globale | `assets/themes/ashan_theme.tres` — Cinzel Decorative Regular + oro `Color(0.85,0.72,0.3)` su Label e Button; applicato a tutte e 5 le scene (.tscn) |
| GameBoard HUD | Refactor da offset manuali a due `HBoxContainer`: Riga 1 `< Mappa · ⚙`, Riga 2 `Titolo · MOVES/monete`; nessun pixel offset hardcoded |
| ChapterSelect scroll | Lista capitoli in `ScrollContainer` (fullscreen sotto header); scrollbar nascosta (`SCROLL_MODE_SHOW_NEVER`); fix capitolo VI tagliato su finestre basse |

### Completato in sessione (2026-06-27 — SFX)

| Componente | Note |
|---|---|
| SFX — file | 5 OGG in `assets/audio/sfx/`: `tile_move`, `tile_invalid`, `hint`, `star`, `level_complete` |
| SFX — AudioManager | Pool 3× `AudioStreamPlayer` round-robin (sovrapposizioni rapide); cache stream; `play_sfx(name)`; `set/get_sfx_volume()` |
| SFX — trigger GameBoard | `tile_move`: inizio tween · `tile_invalid`: tap non valido · `hint`: dopo concessione · `level_complete`: ingresso `_on_puzzle_solved()` · `star`: ogni callback `_reveal_stars()` |
| SFX — volume | Separato dalla musica; chiave `__sfx_volume__` in `SaveManager`; slider 🔔 in Settings con chiave `SETTINGS_SFX_VOLUME` (IT/EN/ES) |

### Completato in sessione (2026-06-28)

| Componente | Note |
|---|---|
| `DiaryScreen` | CanvasLayer overlay post-livello; testo localizzato IT/EN/ES (chiave `LEVEL_C_L_DIARY`); autoscroll 40px/s; pulsante "Continua"; seen-once logic (`SaveManager.is_diary_seen` / `mark_diary_seen`); migrazione automatica save esistenti (`_migrate_diaries`) |
| Cifratura save | `user://save.bin` cifrato AES-256 via `FileAccess.open_encrypted_with_pass`; chiave SHA-256 hardcoded in `_SAVE_KEY`; migrazione automatica da `save.json` plain text al primo avvio |
| Pulsante debug reset | In `MainMenu`, visibile solo se `OS.is_debug_build()` (equivalente `#if DEBUG`); chiama `SaveManager.reset_all()` e ricarica la scena |
| Fix CSV localizzazione | Formato RFC 4180 corretto (outer quoting → per-field quoting); rimosso `;` finale dall'header (era causa del file `translations.es;.translation`); ripristinate OVERLAY_MOVES_PAR, COINS_EARNED, PROGRESS_LABEL, HINT_LABEL_FREE, HUD_MOVES, tutti i LEVEL_X_Y_DIARY; aggiunte DIARY_HEADER, DIARY_CONTINUE |
| Fix Settings back button | Pulsante "Indietro" ancorato in basso al centro (fuori dal VBox) — sempre visibile indipendentemente dall'altezza dello schermo |
| Transizioni schermate | Fade-in da nero (0.35s) all'ingresso di tutte le schermate: MainMenu, ChapterSelect, LevelSelect, GameBoard; DiaryScreen: fade-out verso nero anziché trasparente (evita flash GameBoard) |

### Completato in sessione (2026-06-28 — Daily Puzzle + Security)

| Componente | Note |
|---|---|
| `DailyPuzzleManager` (Autoload) | Generazione deterministica da data, seed = anno×10000+mese×100+giorno; MD-increasing TARGET_MD=27; data localizzata IT/EN/ES |
| `DailyPuzzleScreen.tscn` + script | Schermata dedicata: data odierna, stato completamento, pulsante "Inizia" o riepilogo mosse + "Torna domani" |
| Pulsante MainMenu | "Il Puzzle di Oggi" visibile a tutti (non gated IAP), tra "Inizia" e "Impostazioni" |
| GameBoard modalità Daily | Flag `_is_daily_mode`: no stelle/monete/DiaryScreen; al completamento chiama `DailyPuzzleManager.mark_completed_today()`; torna a DailyPuzzleScreen |
| SaveManager daily record | Chiave `__daily_record__`: `{ date, moves, completed }` — solo il giorno corrente, nessuno storico |
| Fix tampering save | `save.json` legacy eliminato dopo migrazione (`DirAccess.remove_absolute`); tampering di `save.bin` → reset pulito verificato |
| Fix MainMenu layout | Pulsanti 200×56 → 280×62; VBox separation 32 → 16; spacer ridotti — "Esci" sempre visibile, testo non troncato |
| Fix GDScript type inference | Con autoload recuperati come `Node`, usare tipo esplicito (`var x: String =`) invece di `:=` nelle espressioni ternarie |

### Completato in sessione (2026-06-28 — Tile art & Symbol overlay)

| Componente | Note |
|---|---|
| Texture tile aggiornata | `stonetile256x256.png` sostituita con versione bordo naturale marrone, nessun bordo nero |
| Board background pergamena | `board_parchment.png` sostituisce stonetile come sfondo board; `BG_PADDING` 60px per cornice visibile |
| Symbol overlay per capitolo | `TextureRect "SymbolOverlay"` figlio di ogni tile; `AtlasTexture` taglia il simbolo in `grid_size×grid_size` frammenti; ogni tile mostra il frammento del proprio valore; `BLEND_MODE_ADD`, opacità 0.12 |
| Symbol reveal al completamento | `_play_symbol_reveal()`: emerge 0.12→0.6 (1s), pulsa 0.6→0.35→0.6 (1.5s), pausa 0.5s → poi stelline. Flusso: simbolo emerge → stelline → LevelComplete → DiaryScreen |
| Fix `TestAllLevelsPlaythrough` | `Panel` → `TextureRect` dopo refactor tile; 111/111 confermati |

### Open point

_Nessuno._

### Roadmap

#### Pre-lancio

| Priorità | Componente | Note |
|---|---|---|
| 1 | ~~**SFX**~~ | ✅ Completato — 5 trigger, volume separato, slider in Settings |
| 2 | ~~**Daily Puzzle**~~ | ✅ Completato — generazione deterministica, schermata dedicata, free per tutti |
| 3 | ~~**Tile art**~~ | ✅ Completato — texture aggiornata, board pergamena, symbol overlay per capitolo con reveal animato |
| 4 | **IAP** | Sblocco completo 0.99€, gate dopo Capitolo II; Google Play Billing integration |

#### Lancio

| Priorità | Componente | Note |
|---|---|---|
| 5 | **Google Play setup** | Account developer, firma APK release, listing ASO-ottimizzato per search intent |

#### Post-lancio

| Priorità | Componente | Note |
|---|---|---|
| 6 | ~~**Animazioni**~~ | ✅ Transizioni fade-in/out tra schermate completate (2026-06-28) |
| 7 | **MainMenu espanso** | Continua, Nuova Partita, Credits |

---

## Strategia Marketing (zero budget)

> Il Play Store da solo non genera discovery senza momentum esterno: senza
> recensioni iniziali e traffico organico da fonti esterne, un'app nuova
> rimane invisibile. Queste attività sono pre-requisito per la visibilità
> organica e vanno eseguite in parallelo al lancio, non dopo.

| Priorità | Canale | Azione |
|---|---|---|
| 1 | **ASO** | Ottimizzare titolo, descrizione, keyword e screenshot del listing Play Store per search intent reali: `dark puzzle game`, `lovecraftian puzzle`, `puzzle logico atmosferico`. Titolo breve + sottotitolo keyword-ricco. Screenshot con testo overlay in italiano e inglese. |
| 2 | **itch.io** | Pubblicare versione Windows su itch.io come canale parallelo per la comunità indie. Page curata con GIF gameplay, descrizione lore, prezzo pay-what-you-want o free. Genera backlink e prime recensioni da giocatori indie. |
| 3 | **Reddit** | Post mirati al momento del lancio su r/indiegaming, r/AndroidGaming, r/lovecraft, r/puzzlegames. Formato: "Made this solo — dark fantasy puzzle game inspired by Lovecraft". Includere GIF gameplay breve e link diretto. |
| 4 | **TikTok / Instagram Reels** | Video 30s: gameplay con musica ambientale e sfondi atmosferici, formato "ho fatto questo gioco da solo". Mostrare il contrasto visivo e sonoro. Caption con hashtag (#indiegame #puzzlegame #lovecraft #solodev). |
| 5 | **Daily Puzzle shareable** | Aggiungere screenshot condivisibile al completamento del Daily Puzzle (meccanismo Wordle): griglia risolta + stelle + mosse + data. Condivisibile direttamente da gioco. Loop virale gratuito e retention giornaliera. |

---

## Glossario di dominio

| Termine         | Significato                                              |
|-----------------|----------------------------------------------------------|
| `board`         | la griglia di gioco (3×3 o 4×4)                          |
| `tile`          | una singola casella numerata                             |
| `blank`         | la casella vuota (valore 0 nell'array)                   |
| `state`         | configurazione completa della board (array piatto)       |
| `optimal_moves` | soluzione minima calcolata con A*                        |
| `par`           | soglia mosse per ogni livello di stelle                  |
| `chapter`       | uno dei 6 capitoli narrativi, con palette propria        |
| `daily puzzle`  | puzzle giornaliero generato deterministicamente          |
