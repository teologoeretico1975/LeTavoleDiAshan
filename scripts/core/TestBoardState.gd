# scripts/core/TestBoardState.gd
#
# Script di test manuale per BoardState.
#
# COME ESEGUIRLO:
#   1. Apri Godot Editor
#   2. Apri questo file nell'editor degli script (doppio clic nel FileSystem)
#   3. In alto a destra clicca il pulsante "Run" (▶) oppure premi Ctrl+Shift+X
#   4. L'output appare nel pannello "Output" in basso
#
# "extends EditorScript" permette di eseguire codice direttamente nell'editor
# senza creare una scena. Utile per testare classi core pure.
# "@tool" è necessario perché il codice gira nell'editor, non nel gioco.

@tool
extends EditorScript


func _run() -> void:
	print("=" .repeat(40))
	print("TEST BoardState")
	print("=".repeat(40))

	_test_solved_state()
	_test_valid_moves()
	_test_apply_move_immutability()
	_test_3x3()

	print("\nTutti i test completati.")


# ---------------------------------------------------------------------------

func _test_solved_state() -> void:
	print("\n--- Stato risolto 4x4 ---")

	# BoardState.solved() è un metodo statico — nessun .new() necessario.
	var state := BoardState.solved(4)

	# print() chiama automaticamente _to_string() sull'oggetto.
	print(state)

	# In GDScript "==" su bool si può scrivere direttamente nell'if,
	# ma usiamo assert() per rendere evidente l'aspettativa.
	print("is_solved() atteso true: ", state.is_solved())
	print("blank_index atteso 15:   ", state.blank_index)
	print("tiles[0] atteso 1:       ", state.tiles[0])
	print("tiles[15] atteso 0:      ", state.tiles[15])


func _test_valid_moves() -> void:
	print("\n--- Mosse valide dallo stato risolto 4x4 ---")
	print("(blank è in posizione 15 = riga 3, col 3)")

	var state := BoardState.solved(4)
	var moves := state.valid_moves()

	# In uno stato risolto 4x4 il blank è in [3,3].
	# Tile valide: sopra (indice 11) e a sinistra (indice 14).
	# Non ci sono tile sotto né a destra (bordo).
	print("Mosse valide: ", moves)
	print("Attese [11, 14] (sopra e sinistra del blank): ", moves == [11, 14])


func _test_apply_move_immutability() -> void:
	print("\n--- Immutabilità: apply_move ritorna nuovo stato ---")

	var original := BoardState.solved(4)

	# Muoviamo la tile 14 (a sinistra del blank in posizione 15).
	# Dopo la mossa: tile 15 si sposta in pos 14, blank va in pos 15... no:
	# tiles[14]=15 va in blank, tiles[15]=0 diventa 15 → blank si sposta in 14.
	var after_move1 := original.apply_move(14)

	print("Originale (deve essere ancora risolto):")
	print(original)
	print("Dopo mossa tile[14]→blank[15]:")
	print(after_move1)
	print("Originale invariato: ", original.is_solved())
	print("Nuovo stato NON risolto: ", not after_move1.is_solved())
	print("blank_index nuovo: ", after_move1.blank_index, " (atteso 14)")

	# Seconda mossa: muoviamo la tile 10 (sopra il nuovo blank in pos 14).
	var after_move2 := after_move1.apply_move(10)
	print("\nDopo seconda mossa tile[10]→blank[14]:")
	print(after_move2)
	print("blank_index: ", after_move2.blank_index, " (atteso 10)")


func _test_3x3() -> void:
	print("\n--- Test 3x3 (tutorial) ---")

	var state := BoardState.solved(3)
	print(state)
	print("is_solved(): ", state.is_solved())

	var moves := state.valid_moves()
	print("Mosse valide (blank in pos 8 = riga 2 col 2): ", moves)
	print("Attese [5, 7] (sopra e sinistra): ", moves == [5, 7])

	# Muoviamo la tile 7 (a sinistra del blank).
	var after := state.apply_move(7)
	print("\nDopo mossa tile[7]→blank[8]:")
	print(after)

	# Test clone: il clone deve essere uguale ma indipendente.
	var cloned := state.clone()
	print("Clone uguale all'originale: ", cloned.tiles == state.tiles)
