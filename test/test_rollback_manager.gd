extends GutTest

const RollbackManagerScript := preload("res://carom/scripts/netcode/rollback_manager.gd")


class MockSimWorld extends SimWorld:
	var total: int = 0

	func advance(inputs: Dictionary = {}) -> void:
		total += int(inputs.get("local_input", 0)) * 2
		total += int(inputs.get("remote_input", 0)) * 3
		total += 1

	func get_state() -> Dictionary:
		return {total = total}

	func set_state(state: Dictionary) -> void:
		total = state.get("total", 0)

	func get_body_state() -> Dictionary:
		return get_state()

	func set_body_state(state: Dictionary) -> void:
		set_state(state)


func _make_manager_and_sim() -> Dictionary:
	var sim: MockSimWorld = MockSimWorld.new()
	var manager = RollbackManagerScript.new()
	manager.initialize(sim)
	return {
		sim = sim,
		manager = manager,
	}


func _simulate_total(local_inputs: Array[int], remote_inputs: Array[int]) -> int:
	var total: int = 0
	for i: int in range(local_inputs.size()):
		total += local_inputs[i] * 2 + remote_inputs[i] * 3 + 1
	return total


func test_normal_advance_no_rollback_needed() -> void:
	var ctx: Dictionary = _make_manager_and_sim()
	var manager = ctx.manager
	var sim: MockSimWorld = ctx.sim

	var local_inputs: Array[int] = [0, 1, 0, 1, 0, 1, 0, 1, 0, 1]
	var remote_inputs: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	for i: int in range(10):
		manager.advance_frame(local_inputs[i], remote_inputs[i])

	assert_false(manager.needs_rollback())
	assert_eq(manager.get_current_frame(), 10)
	assert_eq(sim.total, _simulate_total(local_inputs, remote_inputs))
	assert_eq(manager.get_confirmed_frame(), 9)


func test_late_input_rolls_back_and_replays() -> void:
	var ctx: Dictionary = _make_manager_and_sim()
	var manager = ctx.manager
	var sim: MockSimWorld = ctx.sim

	for _i in range(8):
		manager.advance_frame(1, 0)

	manager.receive_remote_input(5, 2)
	assert_true(manager.needs_rollback())

	manager.execute_rollback()
	assert_false(manager.needs_rollback())
	assert_eq(manager.get_current_frame(), 8)

	var expected_local: Array[int] = [1, 1, 1, 1, 1, 1, 1, 1]
	var expected_remote: Array[int] = [0, 0, 0, 0, 0, 2, 2, 2]
	assert_eq(sim.total, _simulate_total(expected_local, expected_remote))


func test_prediction_correct_does_not_trigger_rollback() -> void:
	var ctx: Dictionary = _make_manager_and_sim()
	var manager = ctx.manager

	manager.advance_frame(1, 4)
	manager.advance_frame(1, 4)
	manager.advance_frame(1, 4)

	manager.receive_remote_input(1, 4)
	manager.receive_remote_input(2, 4)

	assert_false(manager.needs_rollback())
	assert_eq(manager.get_current_frame(), 3)


func test_multiple_rollbacks_in_sequence() -> void:
	var ctx: Dictionary = _make_manager_and_sim()
	var manager = ctx.manager
	var sim: MockSimWorld = ctx.sim

	for _i in range(7):
		manager.advance_frame(1, 1)

	manager.receive_remote_input(3, 2)
	assert_true(manager.needs_rollback())
	manager.execute_rollback()
	assert_false(manager.needs_rollback())

	manager.receive_remote_input(6, 3)
	assert_true(manager.needs_rollback())
	manager.execute_rollback()
	assert_false(manager.needs_rollback())

	var expected_local: Array[int] = [1, 1, 1, 1, 1, 1, 1]
	var expected_remote: Array[int] = [1, 1, 1, 2, 2, 2, 3]
	assert_eq(sim.total, _simulate_total(expected_local, expected_remote))


func test_ring_buffer_wraps_without_corruption() -> void:
	var ctx: Dictionary = _make_manager_and_sim()
	var manager = ctx.manager
	var sim: MockSimWorld = ctx.sim

	for _i in range(15):
		manager.advance_frame(1, 1)

	manager.receive_remote_input(2, 9)
	assert_false(manager.needs_rollback())

	manager.receive_remote_input(6, 4)
	assert_true(manager.needs_rollback())
	manager.execute_rollback()
	assert_false(manager.needs_rollback())
	assert_eq(manager.get_current_frame(), 15)

	var expected_local: Array[int] = []
	var expected_remote: Array[int] = []
	for i: int in range(15):
		expected_local.append(1)
		expected_remote.append(4 if i >= 6 else 1)
	assert_eq(sim.total, _simulate_total(expected_local, expected_remote))
