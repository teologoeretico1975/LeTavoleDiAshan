# Le Tavole di Ashan

Puzzle game N-puzzle (stile 8-puzzle / 15-puzzle) con ambientazione dark fantasy.
Sviluppato con **Godot 4.6** in **GDScript**, target Android e Windows.

## Gameplay

Il giocatore riordina le tessere numerate di una griglia (3×3 nei primi livelli, 4×4 nei successivi) spostandole nella casella vuota adiacente. Ogni livello ha un numero ottimale di mosse pre-calcolato; le stelle (1–3) vengono assegnate in base all'efficienza.

## Struttura narrativa

6 capitoli, ciascuno con la propria palette e lore:

| # | Titolo | Griglia | Livelli |
|---|--------|---------|---------|
| I | Il Risveglio | 3×3 | 12 |
| II | L'Età dei Costruttori | 4×4 | 20 |
| III | La Prima Crepa | 4×4 | 20 |
| IV | Il Silenzio | 4×4 | 20 |
| V | Ciò Che Dimora | 4×4 | 19 |
| VI | L'Ultimo Archivista | 4×4 | 20 |

## Architettura

```
scenes/
├── ui/          # MainMenu, ChapterSelect, LevelSelect
└── game/        # GameBoard

scripts/
├── core/        # Logica pura (BoardState, PuzzleSolver, HintSolver)
├── managers/    # Autoload: GameManager, LevelLoader, SaveManager
└── ui/          # Controller delle scene

data/
├── levels/      # chapter_01–06.json (111 livelli totali)
└── chapters/    # chapters.json (titoli narrativi)
```

**Principio fondamentale:** `scripts/core/` contiene logica pura (`extends RefCounted`), senza dipendenze da nodi Godot. I controller in `scripts/ui/` e i manager in `scripts/managers/` usano le classi core come strumenti e comunicano tramite segnali.

**Autoload:**
- `GameManager` — navigazione tra scene e passaggio parametri contestuali
- `LevelLoader` — caricamento e cache dei JSON livelli/capitoli
- `SaveManager` — persistenza progresso su `user://save.json`

## Generazione livelli

I livelli sono generati offline con la tecnica **MD-increasing**: partendo dallo stato risolto si applicano K mosse che aumentano la Manhattan distance di 1 ad ogni passo. Questo garantisce `optimal_moves = K` senza eseguire A* a runtime.

- Capitolo I (3×3): optimal 5–16
- Capitoli II–VI (4×4): optimal 15–52

Gli script di generazione sono in `scripts/tools/`.

## Sviluppo

Godot 4.6 — aprire `project.godot` con l'editor Godot.
La scena principale è `scenes/ui/MainMenu.tscn`.

**Loop di navigazione:**
`MainMenu → ChapterSelect → LevelSelect → GameBoard → LevelSelect → ChapterSelect → MainMenu`
