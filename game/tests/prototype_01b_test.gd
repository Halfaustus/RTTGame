extends SceneTree

const CONFIG: MovementConfig = preload("res://data/prototype_movement.tres")
const FINAL_TARGET: Vector3 = Vector3(4.0, 0.5, 100.0)

var _world: Node3D
var _network: Node
var _simulation_passed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _wait_for(condition: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL: timeout: " + label)
			quit(1)
			return false
		await process_frame
	return true


func _click(point: Vector2, button: int) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = true
	_world._unhandled_input(event)
	if button == MOUSE_BUTTON_LEFT:
		event = event.duplicate()
		event.pressed = false
		_world._unhandled_input(event)
	await physics_frame
	await physics_frame
	await process_frame


func _simulation_checks() -> void:
	var simulation := MovementSimulation.new(CONFIG)
	assert(simulation.initialize_navigation())
	var unit := UnitState.new(1, 42, CONFIG.spawn_origin)
	simulation.add_unit(unit)
	assert(simulation.request_move(1, 99, Vector3(2, 0, 100)) == "not owner")
	assert(simulation.request_move(999, 42, Vector3(2, 0, 100)) == "unknown unit")
	assert(simulation.request_move(1, 42, Vector3(NAN, 0, 100)) == "non-finite target")
	assert(simulation.request_move(1, 42, Vector3(0, 2, 100)) == "target is not on the ground")
	assert(simulation.request_move(1, 42, Vector3(999, 0, 100)) == "target outside prototype bounds")
	assert(not simulation.has_active_moves())
	assert(simulation.request_move(1, 42, Vector3(2, 0, 100)).is_empty())
	simulation.advance(0.25)
	assert(unit.position.is_equal_approx(CONFIG.spawn_origin + Vector3.RIGHT))
	assert(simulation.request_move(1, 42, Vector3(CONFIG.spawn_origin.x, 0, 100)).is_empty())
	simulation.advance(1.0)
	assert(unit.position == CONFIG.spawn_origin)
	assert(not simulation.has_active_moves())
	simulation.request_move(1, 42, Vector3(5, 0, 100))
	simulation.stop_owner(42)
	simulation.advance(1.0)
	assert(unit.position == CONFIG.spawn_origin)
	print("PASS simulation: rejection, fixed speed, arrival, redirect, owner disconnect")
	_simulation_passed = true


func _run() -> void:
	_network = root.get_node("NetworkManager")
	var role := ""
	var port := 17777
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-role="):
			role = argument.get_slice("=", 1)
		if argument.begins_with("--test-port="):
			port = int(argument.get_slice("=", 1))
	if role in ["server", "simulation"]:
		_simulation_checks()
		if role == "simulation" or not _simulation_passed:
			quit(0 if _simulation_passed else 1)
			return
		# Keep this movement-only fixture's original player IDs and no combat targets.
		_network._rebels_initialized = true
		assert(_network.start_server(port))
		return
	assert(role in ["driver", "observer", "late"])
	_world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(_world)
	assert(_network.connect_to_server("127.0.0.1", port))
	if not await _wait_for(func(): return _world._visual_units.size() >= (9 if role == "late" else 6), "spawn sync"):
		return
	await physics_frame
	await physics_frame
	await process_frame
	var first: Node3D = _world._visual_units[1]
	if role == "driver":
		assert(first.owner_peer_id == _world.multiplayer.get_unique_id())
		var camera := root.get_camera_3d()
		await _click(camera.unproject_position(first.global_position), MOUSE_BUTTON_LEFT)
		assert(_world._selected_units.size() == 1 and _world._selected_units.has(1))
		assert(first.get_node("SelectionIndicator").visible)
		var other: Node3D = _world._visual_units[4]
		await _click(camera.unproject_position(other.global_position), MOUSE_BUTTON_LEFT)
		assert(_world._selected_units.size() == 1 and _world._selected_units.has(1))
		# An RPC request must not move the client's visual immediately.
		var original := first.position
		_world._request_move_at(camera.unproject_position(Vector3(2, 0, 98)))
		assert(first.position == original)
		if not await _wait_for(func(): return first.position.distance_to(original) > 0.1, "server movement"):
			return
		await _click(camera.unproject_position(Vector3(4, 0, 100)), MOUSE_BUTTON_RIGHT)
		_network.request_move(999, Vector3(0, 0, 100))
		_network.request_move(1, Vector3(NAN, 0, 100))
		_network.request_move(1, Vector3(999, 0, 100))
		_network.request_move(1, Vector3(0, 2, 100))
		if not await _wait_for(func(): return first.position.distance_to(FINAL_TARGET) < 0.001, "driver final position"):
			return
		await _click(Vector2(-1000, -1000), MOUSE_BUTTON_LEFT)
		assert(_world._selected_units.is_empty())
		var before := first.position
		await _click(camera.unproject_position(Vector3(0, 0, 100)), MOUSE_BUTTON_RIGHT)
		await create_timer(0.2).timeout
		assert(first.position == before)
	elif role == "observer":
		assert(first.owner_peer_id != _world.multiplayer.get_unique_id())
		_network.request_move(1, Vector3(10, 0, 100))
		if not await _wait_for(func(): return first.position.distance_to(FINAL_TARGET) < 0.001, "observer final position"):
			return
	else:
		assert(first.position.distance_to(FINAL_TARGET) < 0.001)
	var count: int = _world._visual_units.size()
	_world._on_unit_spawn_received(1, first.owner_peer_id, first.position)
	assert(_world._visual_units.size() == count)
	print("PASS %s: unit 1 position %s; owner %d" % [role, first.position, first.owner_peer_id])
	# Keep the first two clients alive while the runner connects the late client.
	if role != "late":
		await create_timer(3.0).timeout
	_world.multiplayer.multiplayer_peer.close()
	quit()
