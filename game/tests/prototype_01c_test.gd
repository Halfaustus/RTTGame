extends SceneTree

const CONFIG: MovementConfig = preload("res://data/prototype_movement.tres")
const FINAL_POSITIONS: Array[Vector3] = [
	Vector3(2.5, 0.5, 100), Vector3(4, 0.5, 100), Vector3(5.5, 0.5, 100)
]

var _network: Node
var _world: Node3D
var _received_target_ids: Array[int] = []
var _simulation_passed: bool = false


func _record_move_targets(unit_ids: Array[int], _positions: Array[Vector3]) -> void:
	_received_target_ids.append_array(unit_ids)


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


func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame


func _button(point: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = pressed
	_world._unhandled_input(event)


func _motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	_world._unhandled_input(event)


func _click(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	_button(point, true, button)
	_button(point, false, button)
	await _settle()


func _drag(start: Vector2, end: Vector2) -> void:
	_button(start, true)
	_motion(end)
	assert(_world._selection_rectangle.visible)
	_button(end, false)
	assert(not _world._selection_rectangle.visible)
	await _settle()


func _arrived() -> bool:
	for index: int in 3:
		if _world._visual_units[index + 1].position.distance_to(FINAL_POSITIONS[index]) > 0.001:
			return false
	return true


func _simulation_checks() -> void:
	var simulation := MovementSimulation.new(CONFIG)
	assert(simulation.initialize_navigation())
	for id: int in [3, 1, 2, 4]:
		simulation.add_unit(UnitState.new(id, 42 if id != 4 else 99, CONFIG.spawn_position(id)))
	var result := simulation.request_group_move([3, 1, 3, 999, 4, 2], 42, Vector3(4, 0, 100), MovementSimulation.MoveMode.BASIC, Vector3.FORWARD)
	assert(result["rejection"].is_empty())
	assert(result["unit_ids"] == [1, 2, 3])
	assert(simulation._targets.size() == 3 and not simulation._targets.has(4))
	for index: int in 3:
		assert(simulation._targets[index + 1] == FINAL_POSITIONS[index])
	var previous := simulation._targets.duplicate()
	assert(not simulation.request_group_move([1, 2], 42, Vector3(NAN, 0, 100))["rejection"].is_empty())
	assert(not simulation.request_group_move([1, 2], 42, Vector3(999, 0, 100))["rejection"].is_empty())
	assert(simulation._targets == previous)
	assert(simulation.request_group_move([4, 999], 42, Vector3(0, 0, 100))["rejection"] == "no owned units")
	# Reordered input must produce identical ID-to-slot assignments.
	simulation.request_group_move([2, 3, 1], 42, Vector3(4, 0, 100), MovementSimulation.MoveMode.BASIC, Vector3.FORWARD)
	assert(simulation._targets == previous)
	for corner: Vector3 in [Vector3(-20, 0, 80), Vector3(60, 0, 120)]:
		assert(simulation.request_group_move([1, 2, 3], 42, corner)["rejection"].is_empty())
		for target: Vector3 in simulation._targets.values():
			assert(target.x >= CONFIG.minimum_xz.x and target.x <= CONFIG.maximum_xz.x)
			assert(target.z >= CONFIG.minimum_xz.y and target.z <= CONFIG.maximum_xz.y)
		assert(simulation._targets[1].distance_to(simulation._targets[2]) >= CONFIG.unit_width + CONFIG.destination_gap)
		assert(simulation._targets[1].distance_to(simulation._targets[3]) >= CONFIG.unit_width + CONFIG.destination_gap)
	# An impossible row must reject atomically without replacing any old targets.
	var tiny := CONFIG.duplicate() as MovementConfig
	tiny.minimum_xz = Vector2(0, 0)
	tiny.maximum_xz = Vector2(0.5, 0.5)
	var tiny_simulation := MovementSimulation.new(tiny)
	assert(tiny_simulation.initialize_navigation())
	for id: int in 3:
		tiny_simulation.add_unit(UnitState.new(id, 42, Vector3.ZERO))
	assert(tiny_simulation.request_group_move([0, 1, 2], 42, Vector3(0.25, 0, 0.25))["rejection"] == "line does not fit prototype bounds")
	assert(not tiny_simulation.has_active_moves())
	for count: int in [1, 2, 5, 8, 16, 48]:
		var line_simulation := MovementSimulation.new(CONFIG)
		assert(line_simulation.initialize_navigation())
		var ids: Array[int] = []
		for index: int in count:
			ids.append(index + 1)
			line_simulation.add_unit(UnitState.new(index + 1, 42, CONFIG.spawn_origin))
		ids.reverse()
		var line_result := line_simulation.request_group_move(ids, 42, Vector3(4, 0, 100), MovementSimulation.MoveMode.BASIC, Vector3.FORWARD)
		assert(line_result["rejection"].is_empty())
		var sorted_ids: Array[int] = line_result["unit_ids"]
		var targets := line_simulation.move_targets(sorted_ids)
		assert(targets.size() == count)
		for index: int in count:
			assert(sorted_ids[index] == index + 1)
			assert(targets[index].z == 100.0)
			assert(targets[index].x >= CONFIG.minimum_xz.x and targets[index].x <= CONFIG.maximum_xz.x)
			if index > 0:
				assert(is_equal_approx(targets[index].x - targets[index - 1].x, CONFIG.unit_width + CONFIG.destination_gap))
	# Validate dashed geometry without a world, viewport, connection, or client.
	var path = load("res://scripts/core/movement_path_visual.gd").new()
	path.update_path(Vector3.ZERO, Vector3(2, 0, 0))
	assert(path.mesh.get_surface_count() == 1)
	var vertices: PackedVector3Array = path.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert(vertices.size() == 18)
	assert(is_equal_approx(vertices[2].x, 0.5))
	assert(is_equal_approx(vertices[6].x, 0.8))
	path.update_path(Vector3.ZERO, Vector3.ZERO)
	assert(path.mesh.get_surface_count() == 0)
	path.free()
	print("PASS simulation: sorted row, duplicates, mixed ownership, invalid targets, boundary shift, atomic rejection")
	_simulation_passed = true


func _selection_checks() -> void:
	var camera := root.get_camera_3d()
	var first: Node3D = _world._visual_units[1]
	var point := camera.unproject_position(first.global_position)
	_button(point, true)
	_motion(point + Vector2(3, 0))
	assert(not _world._selection_rectangle.visible)
	_button(point + Vector2(3, 0), false)
	await _settle()
	assert(_world._selected_units.keys() == [1])
	_button(point, true)
	_motion(point + Vector2(20, 20))
	assert(_world._selection_rectangle.visible)
	_world._cancel_drag()
	assert(not _world._selection_rectangle.visible)
	# Put an owned visual behind the camera: even a broad box must exclude it.
	_world._on_unit_spawn_received(9999, _world.multiplayer.get_unique_id(), camera.global_position + camera.global_basis.z * 10.0)
	await _drag(Vector2(2000, 2000), Vector2(-1000, -1000))
	assert(_world._selected_units.size() == 3)
	assert(not _world._selected_units.has(9999))
	for id: int in range(1, 7):
		assert(_world._visual_units[id].get_node("SelectionIndicator").visible == (id <= 3))
	await _click(camera.unproject_position(_world._visual_units[4].global_position))
	assert(_world._selected_units.size() == 3)
	await _click(point)
	assert(_world._selected_units.keys() == [1])
	await _drag(Vector2(-1000, -1000), Vector2(-900, -900))
	assert(_world._selected_units.is_empty())
	await _drag(Vector2(-1000, -1000), Vector2(2000, 2000))
	assert(_world._selected_units.size() == 3)
	_world._visual_units[9999].queue_free()
	await _settle()
	assert(not _world._visual_units.has(9999))
	print("PASS selection: threshold, reverse box, own-only centers, behind-camera exclusion, click rules, empty box")


func _run() -> void:
	_network = root.get_node("NetworkManager")
	var role := ""
	var port := 17778
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-role="):
			role = argument.get_slice("=", 1)
		if argument.begins_with("--test-port="):
			port = int(argument.get_slice("=", 1))
	if role == "simulation":
		_simulation_checks()
		quit(0 if _simulation_passed else 1)
		return
	if role == "server":
		_simulation_checks()
		if not _simulation_passed:
			quit(1)
			return
		# Keep this movement-only fixture's original player IDs and no combat targets.
		_network._rebels_initialized = true
		assert(_network.start_server(port))
		return
	assert(role in ["driver", "observer", "late"])
	_world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(_world)
	_network.unit_move_targets_received.connect(_record_move_targets)
	assert(_network.connect_to_server("127.0.0.1", port))
	if not await _wait_for(func(): return _world._visual_units.size() >= (9 if role == "late" else 6), "spawn sync"):
		return
	await _settle()
	if role == "driver":
		assert(_world._visual_units[1].owner_peer_id == _world.multiplayer.get_unique_id())
		await _selection_checks()
		var camera := root.get_camera_3d()
		var original: Vector3 = _world._visual_units[1].position
		await _click(camera.unproject_position(Vector3(0, 0, 96)), MOUSE_BUTTON_RIGHT)
		if not await _wait_for(func(): return _world._visual_units[1].position.distance_to(original) > 0.1, "group movement"):
			return
		assert(_world._movement_paths.size() == 3)
		await _click(camera.unproject_position(Vector3(4, 0, 100)), MOUSE_BUTTON_RIGHT)
		# Mixed/duplicated/unordered IDs exercise the real server RPC validator.
		var mixed_ids: Array[int] = [3, 1, 3, 999, 4, 2]
		var own_ids: Array[int] = [1, 2, 3]
		_network.request_moves(mixed_ids, Vector3(4, 0, 100), MovementSimulation.MoveMode.BASIC, Vector3.FORWARD)
		_network.request_moves(own_ids, Vector3(NAN, 0, 100))
		_network.request_moves(own_ids, Vector3(999, 0, 100))
	elif role == "observer":
		await _drag(Vector2(-1000, -1000), Vector2(2000, 2000))
		assert(_world._selected_units.size() == 3 and not _world._selected_units.has(1))
		var foreign_ids: Array[int] = [1, 2, 3, 999]
		_network.request_moves(foreign_ids, Vector3(10, 0, 100))
		# Invalid/foreign IDs do not poison a request for a genuinely owned unit.
		var mixed_ids: Array[int] = [1, 4, 4, 999]
		_network.request_moves(mixed_ids, Vector3(2, 0, 96))
	if not await _wait_for(_arrived, "three replicated final positions"):
		return
	for unit_id: int in _world._move_targets:
		assert(_world._visual_units[unit_id].owner_peer_id == _world.multiplayer.get_unique_id())
	for unit_id: int in _received_target_ids:
		assert(_world._visual_units[unit_id].owner_peer_id == _world.multiplayer.get_unique_id())
	if role == "driver":
		assert(_received_target_ids.has(1) and _received_target_ids.has(2) and _received_target_ids.has(3))
	elif role == "observer":
		assert(not _received_target_ids.has(1) and not _received_target_ids.has(2) and not _received_target_ids.has(3))
	else:
		assert(_received_target_ids.is_empty())
	for unit_id: int in range(1, 4):
		assert(not _world._movement_paths.has(unit_id))
	if role == "observer":
		if not await _wait_for(func(): return _world._visual_units[4].position.distance_to(Vector3(2, 0.5, 96)) < 0.001, "observer owned unit"):
			return
	if role == "driver":
		_world._visual_units[2].queue_free()
		await _settle()
		assert(not _world._selected_units.has(2) and not _world._visual_units.has(2))
		_world._clear_selection()
		assert(_world._selected_units.is_empty())
	print("PASS %s: multi-unit positions and cleanup" % role)
	if role != "late":
		await create_timer(3.0).timeout
	_world.multiplayer.multiplayer_peer.close()
	quit()
