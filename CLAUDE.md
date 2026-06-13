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

Per i **Capitoli II–VI (4×4)** questa tecnica potrebbe non coprire i
range di difficoltà previsti oltre ~20 mosse. Le alternative da valutare:
- Continuare con MD-increasing fino al limite pratico (~20 mosse 4×4)
- Random scramble + verifica A* con `max_nodes` per stati moderati
- Pre-generazione offline con script Python/C# per i capitoli V–VI
  (dove `optimal_moves` può avvicinarsi a 40–60, fuori portata di A* GDScript)

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

---

## Stato avanzamento progetto

| Componente | Stato |
|---|---|
| `BoardState` (core) | ✅ completo, testato |
| `PuzzleSolver` A* (core) | ✅ completo, limite nodi confermato ~30 mosse 4×4 |
| `HintSolver` greedy (core) | ✅ completo, istantaneo su qualsiasi stato |
| `GameBoard.tscn` + script | ✅ funzionante: griglia cliccabile, tween, flash risoluzione |
| `data/levels/chapter_01.json` | ✅ 12 livelli 3×3, optimal 5–16, tecnica MD-increasing |
| `GenerateChapter01.gd` | ✅ EditorScript rigenerabile con seed fisso |
| Capitoli II–VI (4×4) | ⬜ prossimo step — vedere nota tecnica sopra |
| LevelSelect, ChapterSelect | ⬜ non iniziato |
| Sistema stelle e mosse | ⬜ non iniziato |
| Autoload (GameManager, ecc.) | ⬜ non iniziato |

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
