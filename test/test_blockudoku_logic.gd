extends GutTest

## Unit tests for BlockudokuLogic — pure game-rules module.
## No autoloads, no scene tree, no side effects required.

const LogicScript := preload("res://scripts/blockudoku/blockudoku_logic.gd")

var logic: BlockudokuLogic


func before_each() -> void:
	logic = BlockudokuLogic.new()
	# Provide 3 single-cell blocks so most tests have a usable set
	var blocks: Array[Array] = [
		[Vector2i(0, 0)],
		[Vector2i(0, 0)],
		[Vector2i(0, 0)],
	]
	logic.deal_blocks(blocks)


# ---------------------------------------------------------------------------
# 1. Valid placement scores correctly (shape.size() points)
# ---------------------------------------------------------------------------

func test_valid_placement_scores_shape_size() -> void:
	var shape_2: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	logic.available_blocks[0] = shape_2
	var result := logic.try_place(0, Vector2i(0, 0))
	assert_true(result.valid, "Two-cell placement should be valid")
	assert_eq(result.cells_placed, 2)
	assert_eq(result.score_delta, 2, "Score delta should equal shape size when no clear")
	assert_eq(logic.score, 2)


func test_single_cell_placement_scores_one() -> void:
	var result := logic.try_place(0, Vector2i(4, 4))
	assert_true(result.valid)
	assert_eq(logic.score, 1)


# ---------------------------------------------------------------------------
# 2. Invalid placement returns valid = false and makes no state change
# ---------------------------------------------------------------------------

func test_invalid_placement_out_of_bounds() -> void:
	var result := logic.try_place(0, Vector2i(8, 8))  # Single cell at valid pos
	assert_true(result.valid)
	logic.board_grid[0] = 0  # Reset manually to re-test
	# Place at a pos where a 3-wide piece would go out of bounds
	var shape_3h: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	logic.available_blocks[1] = shape_3h
	var before_score := logic.score
	var result2 := logic.try_place(1, Vector2i(7, 0))  # 7+2=9 which is out of bounds
	assert_false(result2.valid, "Placement out of bounds should be invalid")
	assert_eq(logic.score, before_score, "Score must not change on invalid placement")
	assert_eq(logic.turns, 1, "Turn count must not change on invalid placement")


func test_invalid_placement_occupied_cell() -> void:
	logic.try_place(0, Vector2i(3, 3))  # Place block at (3,3)
	var before_score := logic.score
	var before_turns := logic.turns
	var result := logic.try_place(1, Vector2i(3, 3))  # Try to place on occupied cell
	assert_false(result.valid)
	assert_eq(logic.score, before_score)
	assert_eq(logic.turns, before_turns)


func test_invalid_block_index() -> void:
	var result := logic.try_place(99, Vector2i(0, 0))
	assert_false(result.valid)
	assert_eq(logic.score, 0)


func test_placed_block_is_invalid_to_place_again() -> void:
	logic.try_place(0, Vector2i(0, 0))
	# Block 0 is now empty in available_blocks
	var result := logic.try_place(0, Vector2i(5, 5))
	assert_false(result.valid, "Already-placed block slot should be invalid")


# ---------------------------------------------------------------------------
# 3. Line clear scores (lines * 18 + cleared_cells)
# ---------------------------------------------------------------------------

func test_line_clear_scoring() -> void:
	# Fill row 0 with 8 cells manually, then place at (8,0) to complete it
	for c in 8:
		logic.board_grid[0 * 9 + c] = 1

	var result := logic.try_place(0, Vector2i(8, 0))
	assert_true(result.valid)
	assert_eq(result.lines_cleared, 1)
	assert_eq(result.boxes_cleared, 0)
	assert_eq(result.total_cells_cleared, 9)
	# Score = 1 (placement) + 1 * 18 + 9 = 28
	assert_eq(result.score_delta, 28)
	assert_eq(logic.score, 28)


# ---------------------------------------------------------------------------
# 4. Box clear scores (boxes * 18 + cleared_cells)
# ---------------------------------------------------------------------------

func test_box_clear_scoring() -> void:
	# Fill top-left 3x3 box except last cell (8th: row=2, col=2)
	for r in 3:
		for c in 3:
			if not (r == 2 and c == 2):
				logic.board_grid[r * 9 + c] = 1

	var result := logic.try_place(0, Vector2i(2, 2))
	assert_true(result.valid)
	assert_eq(result.boxes_cleared, 1)
	assert_eq(result.lines_cleared, 0)
	assert_eq(result.total_cells_cleared, 9)
	# Score = 1 (placement) + 1 * 18 + 9 = 28
	assert_eq(result.score_delta, 28)


# ---------------------------------------------------------------------------
# 5. Combo increments on consecutive clears
# ---------------------------------------------------------------------------

func test_combo_increments_on_consecutive_clears() -> void:
	# First clear — fill row 0 except (8,0)
	for c in 8:
		logic.board_grid[0 * 9 + c] = 1
	logic.try_place(0, Vector2i(8, 0))
	assert_eq(logic.combo_count, 1)

	# Second clear — fill row 1 except (0,1)
	for c in range(1, 9):
		logic.board_grid[1 * 9 + c] = 1
	logic.try_place(1, Vector2i(0, 1))
	assert_eq(logic.combo_count, 2)


# ---------------------------------------------------------------------------
# 6. Combo resets when placement doesn't clear
# ---------------------------------------------------------------------------

func test_combo_resets_on_no_clear() -> void:
	# First clear
	for c in 8:
		logic.board_grid[0 * 9 + c] = 1
	logic.try_place(0, Vector2i(8, 0))
	assert_eq(logic.combo_count, 1)

	# Placement with no clear
	logic.try_place(1, Vector2i(5, 5))
	assert_eq(logic.combo_count, 0)


# ---------------------------------------------------------------------------
# 7. Combo bonus = combo_count * 10 when combo > 1
# ---------------------------------------------------------------------------

func test_combo_bonus_applied_from_second_consecutive_clear() -> void:
	# First clear (no bonus)
	for c in 8:
		logic.board_grid[0 * 9 + c] = 1
	var r1 := logic.try_place(0, Vector2i(8, 0))
	assert_eq(r1.combo_bonus, 0)

	# Second clear (bonus = 2 * 10 = 20)
	for c in range(1, 9):
		logic.board_grid[1 * 9 + c] = 1
	var r2 := logic.try_place(1, Vector2i(0, 1))
	assert_eq(r2.combo, 2)
	assert_eq(r2.combo_bonus, 20)
	# Score delta = 1 (cell) + 1*18 + 9 + 20 = 48
	assert_eq(r2.score_delta, 48)


# ---------------------------------------------------------------------------
# 8. Game over detected when no pieces fit
# ---------------------------------------------------------------------------

func test_game_over_when_no_pieces_fit() -> void:
	# Checkerboard board: cell (r,c) filled iff (r+c)%2==0.
	# No two adjacent horizontal cells are both empty, so placing a single cell
	# here never completes any row/column/box (no unintended clearing).
	for r in 9:
		for c in 9:
			if (r + c) % 2 == 0:
				logic.board_grid[r * 9 + c] = 1

	# Available: index 0 = single cell (will be placed),
	#            index 1 = 2-cell horizontal (cannot fit on checkerboard),
	#            index 2 = empty
	logic.available_blocks[0] = [Vector2i(0, 0)]
	logic.available_blocks[1] = [Vector2i(0, 0), Vector2i(1, 0)]
	logic.available_blocks[2] = []
	# blocks_placed_this_set = 1 so after placing it becomes 2 (< 3, no new deal)
	logic.blocks_placed_this_set = 1

	# (1,0) is empty on the checkerboard ((0+1)%2 == 1)
	var r := logic.try_place(0, Vector2i(1, 0))
	assert_true(r.valid)
	assert_false(r.new_blocks_dealt, "Should not deal new blocks (only placed 2 of 3)")
	# Every adjacent horizontal pair alternates filled/empty → 2-cell horizontal can't fit
	assert_true(r.game_over, "Game should be over when no remaining piece fits")
	assert_true(logic.is_game_over)


# ---------------------------------------------------------------------------
# 9. Game over NOT triggered when rotation allows a fit (rotation_mode=true)
# ---------------------------------------------------------------------------

func test_game_over_not_triggered_when_rotation_allows_fit() -> void:
	logic.rotation_mode = true
	# Sparse board: only 2 isolated cells; no row, col, or box is complete.
	# Placing a single cell here won't trigger any clearing.
	logic.board_grid[0 * 9 + 5] = 1  # (5,0)
	logic.board_grid[1 * 9 + 5] = 1  # (5,1)

	# Index 0: 3-wide H — easily fits on this mostly-empty board.
	# Index 1: single cell to place (triggers game-over check without clearing).
	logic.available_blocks[0] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	logic.available_blocks[1] = [Vector2i(0, 0)]
	logic.available_blocks[2] = []
	logic.blocks_placed_this_set = 1  # becomes 2 after placement (< 3, game-over check runs)

	# (0,0) is empty; placing there fills one cell but never completes any line
	var r := logic.try_place(1, Vector2i(0, 0))
	assert_true(r.valid)
	assert_false(r.new_blocks_dealt)
	# 3-wide H fits easily on the nearly-empty board → game should NOT be over
	assert_false(r.game_over, "Game should NOT be over when a piece can still fit")
	assert_false(logic.is_game_over)


# ---------------------------------------------------------------------------
# 10. Block dealing triggers after 3 placements
# ---------------------------------------------------------------------------

func test_new_blocks_dealt_after_three_placements() -> void:
	var r1 := logic.try_place(0, Vector2i(0, 0))
	assert_false(r1.new_blocks_dealt)
	var r2 := logic.try_place(1, Vector2i(1, 0))
	assert_false(r2.new_blocks_dealt)
	var r3 := logic.try_place(2, Vector2i(2, 0))
	assert_true(r3.new_blocks_dealt, "new_blocks_dealt should be true after placing all 3 blocks")
	assert_eq(logic.blocks_placed_this_set, 3)


func test_deal_blocks_resets_counter() -> void:
	logic.try_place(0, Vector2i(0, 0))
	logic.try_place(1, Vector2i(1, 0))
	logic.try_place(2, Vector2i(2, 0))
	assert_eq(logic.blocks_placed_this_set, 3)

	var new_blocks: Array[Array] = [
		[Vector2i(0, 0)],
		[Vector2i(0, 0)],
		[Vector2i(0, 0)],
	]
	logic.deal_blocks(new_blocks)
	assert_eq(logic.blocks_placed_this_set, 0)
	assert_eq(logic.available_blocks.size(), 3)


# ---------------------------------------------------------------------------
# 11. State serialisation round-trips correctly
# ---------------------------------------------------------------------------

func test_state_roundtrip() -> void:
	# Make some moves
	logic.try_place(0, Vector2i(0, 0))
	logic.try_place(1, Vector2i(3, 3))
	for c in 8:
		logic.board_grid[5 * 9 + c] = 1
	logic.try_place(2, Vector2i(8, 5))  # Complete row 5

	var state: Dictionary = logic.get_state()
	assert_eq(state["score"], logic.score)
	assert_eq(state["turns"], logic.turns)
	assert_eq(state["combo_count"], logic.combo_count)

	# Create a fresh logic and restore
	var fresh := BlockudokuLogic.new()
	fresh.set_state(state)

	assert_eq(fresh.score, logic.score)
	assert_eq(fresh.turns, logic.turns)
	assert_eq(fresh.combo_count, logic.combo_count)
	assert_eq(fresh.blocks_placed_this_set, logic.blocks_placed_this_set)
	assert_eq(fresh.board_grid, logic.board_grid, "board_grid should round-trip")
	assert_eq(fresh.available_blocks.size(), logic.available_blocks.size())


func test_state_roundtrip_board_grid_values() -> void:
	# Place something, then round-trip
	logic.board_grid[0] = 1
	logic.board_grid[40] = 1
	var state: Dictionary = logic.get_state()

	var fresh := BlockudokuLogic.new()
	fresh.set_state(state)

	assert_eq(fresh.board_grid[0], 1)
	assert_eq(fresh.board_grid[40], 1)
	assert_eq(fresh.board_grid[1], 0)


# ---------------------------------------------------------------------------
# Additional: rotation mode affects has_valid_placement check
# ---------------------------------------------------------------------------

func test_rotation_mode_false_does_not_check_rotations() -> void:
	logic.rotation_mode = false
	# Diagonal blocker pattern: for each row r, fill exactly one cell per 3-column window.
	# Window 0-2 → col (r%3); window 3-5 → col 3+(r%3); window 6-8 → col 6+(r%3).
	# Each column gets exactly 3 cells → no full columns (need 9).
	# Each row gets exactly 3 cells → no full rows (need 9).
	# No 3x3 box is complete → no clearing triggered.
	# Key property: any 3 consecutive columns span all 3 residue classes mod 3,
	# so every row's blockers guarantee no 3-wide H can fit anywhere.
	for rr in 9:
		logic.board_grid[rr * 9 + (rr % 3)] = 1         # window 0-2
		logic.board_grid[rr * 9 + 3 + (rr % 3)] = 1     # window 3-5
		logic.board_grid[rr * 9 + 6 + (rr % 3)] = 1     # window 6-8

	# index 0 = 3-wide horizontal (can't fit in any row due to diagonal blockers)
	# index 1 = single cell to place without clearing
	logic.available_blocks[0] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	logic.available_blocks[1] = [Vector2i(0, 0)]
	logic.available_blocks[2] = []
	logic.blocks_placed_this_set = 1  # becomes 2 after placement (< 3, game-over check runs)

	# Row 0 diagonal: fills col 0, col 3, col 6. Col 1 is empty → valid placement.
	# Single cell at (1,0) won't complete any row (4/9), col (4/9), or box (4/9) → no clear.
	var r := logic.try_place(1, Vector2i(1, 0))
	assert_true(r.valid)
	# rotation_mode=false: only tries original orientation of 3-wide H → can't fit → game over
	assert_true(r.game_over, "Without rotation_mode, 3-wide H can't fit when diagonal blockers fill every 3-col window")
