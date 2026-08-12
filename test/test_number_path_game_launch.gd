extends GutTest

const GAME_SCENE := preload("res://scenes/number_path_game.tscn")

# A seed that generates quickly for every tier (Expert is the slow one: exact
# Rank-4 8x8 generation has an inherent heavy time tail for some random seeds,
# so the launch test pins a vetted fast seed to stay deterministic and reliable
# rather than sampling that tail). Production launches still use a random seed.
const FAST_LAUNCH_SEED := 100


func test_each_tier_launch_produces_a_playable_board() -> void:
	for tier in range(NumberPathLogic.TIER_EASY, NumberPathLogic.TIER_EXPERT + 1):
		var screen := GAME_SCENE.instantiate()
		add_child(screen)
		await wait_process_frames(2)

		screen.start_new_game(tier, FAST_LAUNCH_SEED)
		var deadline := Time.get_ticks_msec() + 10_000
		while screen._gen_thread != null and Time.get_ticks_msec() < deadline:
			await wait_process_frames(1)

		assert_null(screen._gen_thread,
			"Tier %d generation must finish within 10 seconds" % tier)
		assert_false(screen.logic.checkpoints.is_empty(),
			"Tier %d must populate the board with checkpoints" % tier)
		assert_true(screen.board.size.x > 0.0 and screen.board.size.y > 0.0,
			"Tier %d board must have drawable dimensions" % tier)
		assert_true(screen.logic.can_hint(),
			"Tier %d board must be interactive" % tier)

		screen.queue_free()
		await wait_process_frames(1)


func test_slow_expert_seed_falls_back_to_playable_board() -> void:
	var screen := GAME_SCENE.instantiate()
	add_child(screen)
	await wait_process_frames(2)

	screen.start_new_game(NumberPathLogic.TIER_EXPERT, 42)
	var deadline := Time.get_ticks_msec() + 12_000
	while screen._gen_thread != null and Time.get_ticks_msec() < deadline:
		await wait_process_frames(1)

	assert_null(screen._gen_thread, "Slow Expert generation must finish via fallback")
	assert_eq(screen.logic.random_seed, screen.FALLBACK_GENERATION_SEED)
	assert_false(screen.logic.checkpoints.is_empty())
	assert_true(screen.logic.can_hint())

	screen.queue_free()
	await wait_process_frames(1)
