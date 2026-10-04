extends SceneTree

const CONFIG: MovementConfig = preload("res://data/prototype_movement.tres")

var _failures: int = 0
var _presentation_completed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)


func _simulation_checks() -> void:
	var movement := MovementSimulation.new(CONFIG)
	_check(movement.initialize_navigation(), "navigation ready")
	for id: int in range(1, 5):
		var state := UnitState.new(id, 42 if id <= 3 else 99, Vector3(id * 2, 0.5, 100))
		movement.add_unit(state)
		_check(movement.request_move(id, state.owner_peer_id, Vector3(id * 2, 0, 110)).is_empty(), "move accepted")
	movement.advance(0.25)
	var current := movement._units[1].position
	var foreign_route := movement.move_paths([4])[0]
	var accepted := movement.request_stop([999, 4, 2, 1, 1, -1], 42)
	_check(accepted == [1, 2], "mixed IDs filter independently, deduplicate, and sort")
	_check(not movement._targets.has(1) and not movement._paths.has(1) and not movement._path_indices.has(1), "stop clears target path and progress")
	_check(movement._units[1].position == current, "stop preserves authoritative position")
	_check(movement.move_paths([4])[0] == foreign_route and movement.is_moving(3), "foreign and unselected units keep orders")
	movement.advance(0.5)
	_check(movement._units[1].position == current and movement._units[4].position.z > 101, "stopped unit stays while other units advance")
	_check(movement.request_stop([1, 2], 42) == [1, 2], "repeated stop and stationary stop accepted")
	_check(movement.request_stop([1], 99).is_empty(), "different owner cannot stop same-team unit")
	_check(movement.request_stop([], 42).is_empty(), "empty stop is harmless")
	_check(movement.request_move(1, 42, Vector3(8, 0, 110)).is_empty(), "move after stop accepted")
	movement.advance(0.25)
	_check(movement._units[1].position != current, "movement resumes")
	movement._units[2].health = 0.0
	_check(movement.request_stop([2], 42).is_empty(), "dead unit ignored")
	movement.remove_unit(2)
	_check(movement.request_stop([2, 1], 42) == [1], "removed ID cannot block valid stop")


func _server_checks() -> void:
	var network := root.get_node("NetworkManager")
	_check(network._movement.initialize_navigation(), "server navigation ready")
	for id: int in [101, 102]:
		var state := UnitState.new(id, 42 if id == 101 else 99, Vector3(10, 0.5, 100))
		network._authoritative_units[id] = state
		network._movement.add_unit(state)
		_check(network._movement.request_move(id, state.owner_peer_id, Vector3(10, 0, 110)).is_empty(), "server move accepted")
	network._movement.advance(0.25)
	var position: Vector3 = network._authoritative_units[101].position
	network._pending_positions[101] = Vector3(10, 0.5, 100)
	network._pending_positions[102] = Vector3(10, 0.5, 100)
	var mixed: Array[int] = [102, 999, 101, 101]
	# No remote peer: the RPC entry point must not execute an unauthenticated local call.
	network._submit_stop(mixed)
	_check(network._movement.is_moving(101), "RPC entry rejects unknown sender")
	var result: Dictionary = network._apply_stop(mixed, 42)
	_check(result["unit_ids"] == [101] and result["positions"] == [position], "stop payload carries only accepted ID and current server position")
	_check(not network._pending_positions.has(101) and network._pending_positions.has(102), "only stopped unit's stale buffered position is removed")
	_check(network._movement.is_moving(102), "foreign server unit still moves")
	result = network._apply_stop(mixed, 42)
	_check(result["unit_ids"] == [101] and result["positions"] == [position], "server stop is idempotent")


func _combat_after_stop() -> void:
	var movement := MovementSimulation.new(CONFIG)
	_check(movement.initialize_navigation(), "combat fixture navigation ready")
	var combat := CombatSimulation.new(MovementSimulation.MAP_DEFINITION)
	var attacker := UnitState.new(1, 42, Vector3(10, 0.5, 100))
	attacker.configure(1, load("res://data/unit_stationary.tres"))
	var enemy := UnitState.new(2, 0, Vector3(10, 0.5, 104))
	enemy.configure(2, load("res://data/unit_unarmed.tres"))
	for state: UnitState in [attacker, enemy]:
		movement.add_unit(state)
		combat.add_unit(state)
	_check(movement.request_move(1, 42, Vector3(10, 0, 110)).is_empty(), "stationary weapon moving")
	_check(combat.advance(0.1, movement)["shots"].is_empty(), "stationary weapon cannot fire while moving")
	movement.request_stop([1], 42)
	_check(combat.advance(0.1, movement)["shots"].size() == 1 and enemy.health == 35.0, "stop preserves automatic combat and enables stationary firing")


func _presentation_checks() -> void:
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	_check(world._is_stop_key(key), "E press recognized")
	key.echo = true
	_check(not world._is_stop_key(key), "held-key repeat ignored")
	key.echo = false
	key.pressed = false
	_check(not world._is_stop_key(key), "release ignored")
	key.pressed = true
	key.ctrl_pressed = true
	_check(not world._is_stop_key(key), "GUI shortcut modifier ignored")
	key.ctrl_pressed = false
	var field := LineEdit.new()
	world._selection_rectangle.get_parent().add_child(field)
	field.grab_focus()
	_check(not world._is_stop_key(key), "focused GUI keeps keyboard input")
	field.release_focus()
	field.queue_free()
	# Offline owner 1 is used only for presentation; no clients or connections are created.
	world._on_unit_spawn_received(201, 1, Vector3(10, 0.5, 100))
	world._on_unit_spawn_received(202, 42, Vector3(12, 0.5, 100))
	var own: Node3D = world._visual_units[201]
	var selection: Dictionary[int, Node3D] = {201: own}
	world._replace_selection(selection)
	world._move_targets[201] = Vector3(10, 0.5, 110)
	world._route_points[201] = PackedVector3Array([own.position, Vector3(10, 0.5, 110)])
	world._route_progress[201] = 0
	world._update_unit_path(201)
	var ids: Array[int] = [201, 202, 999]
	var positions: Array[Vector3] = [Vector3(10, 0.5, 102), Vector3(12, 0.5, 102), Vector3.ZERO]
	world._on_unit_stops_received(ids, positions)
	_check(own.position == positions[0] and world._visual_units[202].position == positions[1], "both own and observed units take authoritative stop positions")
	_check(world._movement_paths.is_empty() and world._move_targets.is_empty() and world._route_points.is_empty() and world._route_progress.is_empty(), "owner route completely cleared")
	_check(world._selected_units.has(201), "stop preserves selection")
	world._on_unit_stops_received(ids, positions)
	_check(world._visual_units.size() == 2, "repeated stop and unknown IDs harmless")
	world._on_unit_death_received(201)
	world._on_unit_stops_received(ids, positions)
	_check(not world._visual_units.has(201), "late stop cannot resurrect death")
	world._request_stop_selected()
	_check(world._selected_units.is_empty(), "empty selection stop is harmless")
	world.queue_free()
	await process_frame
	_presentation_completed = true


func _run() -> void:
	_simulation_checks()
	_server_checks()
	_combat_after_stop()
	await _presentation_checks()
	_check(_presentation_completed, "presentation checks completed")
	if _failures == 0:
		print("PASS Prototype 0.2B isolated stop simulation, server payload and presentation/input checks (no clients launched)")
	quit(0 if _failures == 0 else 1)
