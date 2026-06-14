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

### Non legare callback di nodi a indici di array mutabili

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

---

## Stato avanzamento progetto

### Core e gameplay

| Componente | Stato |
|---|---|
| `BoardState` (core) | ✅ completo, testato |
| `PuzzleSolver` A* (core) | ✅ completo, limite nodi confermato ~30 mosse 4×4 |
| `HintSolver` greedy (core) | ✅ completo, istantaneo su qualsiasi stato |
| `LevelLoader` (Autoload) | ✅ completo — carica `chapter_0X.json` on-demand, cache in memoria; `get_level()` / `get_chapter_info()` / `get_chapter_title()` |
| `SaveManager` (Autoload) | ✅ completo — persistenza `user://save.json`, calcolo stelle, sblocco sequenziale livelli e capitoli; `save_level_result()` / `get_level_progress()` / `is_level_unlocked()` / `get_chapter_progress()` / `is_chapter_unlocked()` |
| `GameManager` (Autoload) | ✅ completo — blackboard per navigazione tra scene (`selected_chapter`, `selected_level`); `goto_game_board()` / `goto_level_select()` / `goto_chapter_select()` |
| `GameBoard.tscn` + script | ✅ completo — griglia cliccabile, tween, HUD (titolo + contatore mosse), calcolo stelle, salvataggio automatico; legge capitolo/livello da `GameManager` con fallback `@export`; pulsante "< Mappa" + ESC per tornare a `LevelSelect` |
| `LevelSelect.tscn` + script | ✅ completo — griglia 4 colonne con stato per livello (bloccato/stelle); legge `LevelLoader` + `SaveManager`; naviga a `GameBoard` al click |
| `ChapterSelect.tscn` + script | ✅ completo — lista verticale 6 capitoli con titolo narrativo, progresso (livelli/stelle), sblocco progressivo; **Main Scene del progetto** |
| `TestAllLevelsPlaythrough` | ✅ 111/111 livelli passati — playthrough 50 mosse per livello, verifica invarianti sync UI/logica |
| `TestSaveManager` | ✅ 9/9 test passati — salvataggio, miglioramento, persistenza su disco, sblocco sequenziale |

### Dati livelli (tutti i 6 capitoli completati)

| File | Stato |
|---|---|
| `chapter_01.json` | ✅ 12 livelli 3×3, optimal 5–16, **titoli evocativi definitivi** |
| `chapter_02.json` | ✅ 20 livelli 4×4, optimal 15–28, titoli placeholder |
| `chapter_03.json` | ✅ 20 livelli 4×4, optimal 28–42, titoli placeholder |
| `chapter_04.json` | ✅ 20 livelli 4×4, optimal 40–52, titoli placeholder |
| `chapter_05.json` | ✅ 19 livelli 4×4, optimal 44–52, titoli placeholder (1 skip MD=52) |
| `chapter_06.json` | ✅ 20 livelli 4×4, optimal 48–52, par_moves×1.2, titoli placeholder |
| `chapters.json` | ✅ titoli narrativi dei 6 capitoli in `data/chapters/` |

Tutti i generatori `GenerateChapter01–06.gd` usano MD-increasing pura con seed fisso.
Ceiling MD-increasing su 4×4: **~51 stabile, 52 borderline** (timeout a 55+).

### Loop di navigazione completo

```
ChapterSelect (Main Scene) → LevelSelect → GameBoard → LevelSelect → ChapterSelect
```

### Non iniziato — prossimi step

| Componente | Priorità | Note |
|---|---|---|
| Overlay Level Complete | **ALTA — bloccante** | per ora solo `print()` + flash; `print()` non è visibile in build esportate; necessario per giocabilità reale fuori dall'editor |
| `MainMenu.tscn` | media | schermata iniziale prima di `ChapterSelect` |
| Sistema hint UI | media | `HintSolver` esiste ma non è collegato a nessuna UI |
| `AudioManager` (Autoload) | bassa | musica e SFX |
| Economia/monete | bassa | `GameManager` ha le variabili previste ma non usate |
| Titoli evocativi Cap II–VI | bassa | placeholder "Livello X-N" — da sessione dedicata alla lore (stile: vedi `chapter_01.json`) |
| Export Android/Windows | — | dipende da overlay Level Complete e MainMenu |
| Daily puzzle | — | generazione deterministica da data |

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
