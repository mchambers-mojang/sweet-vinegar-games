class_name CaromMatchState
extends RefCounted

## Pure match lifecycle state — no Node, SceneTree, or autoload dependencies.
## Tracks phase, scores, and produces a GoalResult on each goal event.

enum Phase { SETUP, PLAYING, GAME_OVER }

## Result returned by on_goal_scored().
class GoalResult:
	var scorer: String    ## "player" or "ai"
	var new_score: int    ## Updated score for the scorer
	var match_over: bool  ## True if this goal ends the match
	var winner: String    ## "Player", "AI", or "" if the match is not over

var phase: Phase = Phase.SETUP
var player_score: int = 0
var ai_score: int = 0
var score_limit: int = 5
var difficulty: int = 1  ## Difficulty tier index: 0=Easy, 1=Medium, 2=Hard, 3=Brutal
var rounds_played: int = 0


## Initialise (or reset) the match with the given parameters.
func init_match(p_difficulty: int, p_score_limit: int) -> void:
	difficulty = p_difficulty
	score_limit = p_score_limit
	player_score = 0
	ai_score = 0
	rounds_played = 0
	phase = Phase.SETUP


## Record a goal and advance state.
## Silently ignores the event if the match is not in the PLAYING phase.
## Returns a GoalResult describing what happened.
func on_goal_scored(scorer: String) -> GoalResult:
	var result := GoalResult.new()
	result.scorer = scorer
	result.match_over = false
	result.winner = ""

	if phase != Phase.PLAYING:
		result.new_score = player_score if scorer == "player" else ai_score
		return result

	if scorer == "player":
		player_score += 1
		result.new_score = player_score
	else:
		ai_score += 1
		result.new_score = ai_score

	if player_score >= score_limit or ai_score >= score_limit:
		phase = Phase.GAME_OVER
		result.match_over = true
		result.winner = get_winner()

	return result


## Transition to PLAYING and increment the round counter.
func on_round_ready() -> void:
	rounds_played += 1
	phase = Phase.PLAYING


## Returns "Player", "AI", or "" if neither has reached the score limit yet.
func get_winner() -> String:
	if player_score >= score_limit:
		return "Player"
	if ai_score >= score_limit:
		return "AI"
	return ""


## True once a goal tips the match into GAME_OVER phase.
func is_match_over() -> bool:
	return phase == Phase.GAME_OVER
