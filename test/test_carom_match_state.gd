extends GutTest

## Unit tests for CaromMatchState — pure match lifecycle logic.
## No scene tree or autoloads required.

const MatchStateScript := preload("res://carom/scripts/carom_match_state.gd")


func _make_state(score_limit: int = 5, difficulty: int = 1) -> CaromMatchState:
	var s: CaromMatchState = MatchStateScript.new()
	s.init_match(difficulty, score_limit)
	return s


# --- Initialisation ---

func test_init_match_sets_scores_to_zero() -> void:
	var s := _make_state()
	assert_eq(s.player_score, 0)
	assert_eq(s.ai_score, 0)


func test_init_match_sets_phase_to_setup() -> void:
	var s := _make_state()
	assert_eq(s.phase, CaromMatchState.Phase.SETUP)


func test_init_match_stores_difficulty_and_limit() -> void:
	var s := _make_state(3, 2)
	assert_eq(s.score_limit, 3)
	assert_eq(s.difficulty, 2)


func test_init_match_resets_rounds_played() -> void:
	var s := _make_state()
	s.on_round_ready()
	s.on_round_ready()
	s.init_match(1, 5)
	assert_eq(s.rounds_played, 0)


# --- Round lifecycle ---

func test_on_round_ready_transitions_to_playing() -> void:
	var s := _make_state()
	assert_eq(s.phase, CaromMatchState.Phase.SETUP)
	s.on_round_ready()
	assert_eq(s.phase, CaromMatchState.Phase.PLAYING)


func test_on_round_ready_increments_rounds_played() -> void:
	var s := _make_state()
	assert_eq(s.rounds_played, 0)
	s.on_round_ready()
	assert_eq(s.rounds_played, 1)
	var _result := s.on_goal_scored("player")
	s.on_round_ready()
	assert_eq(s.rounds_played, 2)


# --- Goal scoring ---

func test_goal_scored_increments_player_score() -> void:
	var s := _make_state()
	s.on_round_ready()
	var result := s.on_goal_scored("player")
	assert_eq(result.scorer, "player")
	assert_eq(s.player_score, 1)
	assert_eq(result.new_score, 1)
	assert_false(result.match_over)
	assert_eq(result.winner, "")


func test_goal_scored_increments_ai_score() -> void:
	var s := _make_state()
	s.on_round_ready()
	var result := s.on_goal_scored("ai")
	assert_eq(result.scorer, "ai")
	assert_eq(s.ai_score, 1)
	assert_eq(result.new_score, 1)
	assert_false(result.match_over)


func test_goal_scored_stays_in_playing_phase() -> void:
	var s := _make_state()
	s.on_round_ready()
	s.on_goal_scored("player")
	assert_eq(s.phase, CaromMatchState.Phase.PLAYING)


# --- Match end ---

func test_match_ends_at_score_limit_for_player() -> void:
	var s := _make_state(3)
	for _i in 2:
		s.on_round_ready()
		s.on_goal_scored("player")
	s.on_round_ready()
	var result := s.on_goal_scored("player")
	assert_true(result.match_over)
	assert_eq(result.winner, "Player")
	assert_eq(s.phase, CaromMatchState.Phase.GAME_OVER)


func test_match_ends_at_score_limit_for_ai() -> void:
	var s := _make_state(3)
	for _i in 2:
		s.on_round_ready()
		s.on_goal_scored("ai")
	s.on_round_ready()
	var result := s.on_goal_scored("ai")
	assert_true(result.match_over)
	assert_eq(result.winner, "AI")
	assert_eq(s.phase, CaromMatchState.Phase.GAME_OVER)


func test_winner_is_player_when_player_reaches_limit() -> void:
	var s := _make_state(5)
	for _i in 5:
		s.on_round_ready()
		s.on_goal_scored("player")
	assert_eq(s.get_winner(), "Player")


func test_winner_is_ai_when_ai_reaches_limit() -> void:
	var s := _make_state(5)
	for _i in 5:
		s.on_round_ready()
		s.on_goal_scored("ai")
	assert_eq(s.get_winner(), "AI")


func test_get_winner_returns_empty_before_limit() -> void:
	var s := _make_state(5)
	s.on_round_ready()
	s.on_goal_scored("player")
	assert_eq(s.get_winner(), "")


# --- Phase transitions ---

func test_phase_transition_setup_to_playing() -> void:
	var s := _make_state()
	assert_eq(s.phase, CaromMatchState.Phase.SETUP)
	s.on_round_ready()
	assert_eq(s.phase, CaromMatchState.Phase.PLAYING)


func test_phase_stays_playing_after_goal() -> void:
	var s := _make_state()
	s.on_round_ready()
	assert_eq(s.phase, CaromMatchState.Phase.PLAYING)
	s.on_goal_scored("ai")
	assert_eq(s.phase, CaromMatchState.Phase.PLAYING)


func test_phase_transition_to_game_over() -> void:
	var s := _make_state(1)
	s.on_round_ready()
	s.on_goal_scored("player")
	assert_eq(s.phase, CaromMatchState.Phase.GAME_OVER)


# --- No scoring after game over ---

func test_no_scoring_after_game_over() -> void:
	var s := _make_state(1)
	s.on_round_ready()
	s.on_goal_scored("player")
	assert_true(s.is_match_over())

	var player_before := s.player_score
	var ai_before := s.ai_score
	s.on_goal_scored("player")
	s.on_goal_scored("ai")
	assert_eq(s.player_score, player_before, "Player score must not change after game over")
	assert_eq(s.ai_score, ai_before, "AI score must not change after game over")


func test_is_match_over_false_during_play() -> void:
	var s := _make_state()
	s.on_round_ready()
	assert_false(s.is_match_over())


func test_is_match_over_true_after_limit_reached() -> void:
	var s := _make_state(1)
	s.on_round_ready()
	s.on_goal_scored("ai")
	assert_true(s.is_match_over())


# --- score_changed signal ---

func test_score_changed_emitted_on_init_match() -> void:
	var s: CaromMatchState = MatchStateScript.new()
	var received: Array = []
	s.score_changed.connect(func(p: int, a: int) -> void:
		received.append([p, a])
	)
	s.init_match(1, 5)
	assert_eq(received.size(), 1)
	assert_eq(received[0], [0, 0])


func test_score_changed_emitted_on_player_goal() -> void:
	var s := _make_state()
	s.on_round_ready()
	var received: Array = []
	s.score_changed.connect(func(p: int, a: int) -> void:
		received.append([p, a])
	)
	s.on_goal_scored("player")
	assert_eq(received.size(), 1)
	assert_eq(received[0], [1, 0])


func test_score_changed_emitted_on_ai_goal() -> void:
	var s := _make_state()
	s.on_round_ready()
	var received: Array = []
	s.score_changed.connect(func(p: int, a: int) -> void:
		received.append([p, a])
	)
	s.on_goal_scored("ai")
	assert_eq(received.size(), 1)
	assert_eq(received[0], [0, 1])


func test_score_changed_not_emitted_when_phase_not_playing() -> void:
	var s: CaromMatchState = MatchStateScript.new()
	s.init_match(1, 5)
	var received: Array = []
	s.score_changed.connect(func(p: int, a: int) -> void:
		received.append([p, a])
	)
	s.on_goal_scored("player")
	assert_eq(received.size(), 0, "score_changed must not emit when phase is not PLAYING")
