extends SceneTree

const MOVEMENT: MovementConfig = preload("res://data/prototype_movement.tres")
const MAP: PrototypeMapDefinition = preload("res://data/prototype_map.tres")
const MOBILE: UnitDefinition = preload("res://data/unit_mobile.tres")
const STATIONARY: UnitDefinition = preload("res://data/unit_stationary.tres")
const UNARMED: UnitDefinition = preload("res://data/unit_unarmed.tres")

var _failures: int = 0
var _presentation_completed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)


func _state(id: int, owner: int, team: int, position: Vector3, definition: UnitDefinition) -> UnitState:
	var state := UnitState.new(id, owner, position)
	state.configure(team, definition)
	return state


func _target_and_visibility() -> void:
	var combat := CombatSimulation.new(MAP)
	var attacker := _state(10, 42, 1, Vector3(10, 0.5, 100), MOBILE)
	var ally := _state(11, 99, 1, Vector3(10, 0.5, 101), MOBILE)
	var high_id := _state(8, 0, 2, Vector3(12, 0.5, 100), UNARMED)
	var low_id := _state(2, 0, 2, Vector3(8, 0.5, 100), UNARMED)
	for state: UnitState in [attacker, ally, high_id, low_id]:
		combat.add_unit(state)
	_check(combat.nearest_enemy(attacker) == low_id, "same-team different-owner ignored; tied distance uses ID")
	high_id.position = Vector3(11, 0.5, 100)
	_check(combat.nearest_enemy(attacker) == high_id, "closer enemy wins over lower ID")
	low_id.health = 0.0
	_check(combat.nearest_enemy(attacker) == high_id, "dead enemy ignored")
	high_id.position.x = 30
	_check(combat.nearest_enemy(attacker) == null, "out of range ignored")
	_check(combat.nearest_enemy(_state(99, 42, 1, attacker.position, UNARMED)) == null, "unarmed cannot target")
	_check(not combat.has_line_of_sight(Vector3(-3, 0.5, 96), Vector3(-3, 0.5, 90)), "wall blocks fire")
	_check(not combat.has_line_of_sight(Vector3(4, 0.5, 90), Vector3(8, 0.5, 90)), "block blocks fire")
	_check(combat.has_line_of_sight(Vector3(4.1, 0.5, 96), Vector3(4.1, 0.5, 93)), "LOS uses actual wall, not inflated navigation wall")
	_check(combat.has_line_of_sight(Vector3(-3, 3, 96), Vector3(-3, 3, 90)), "height respected")
	var movement := MovementSimulation.new(MOVEMENT)
	var blocked := CombatSimulation.new(MAP)
	var behind := _state(1, 42, 1, Vector3(-3, 0.5, 96), MOBILE)
	var enemy := _state(2, 0, 2, Vector3(-3, 0.5, 90), STATIONARY)
	blocked.add_unit(behind)
	blocked.add_unit(enemy)
	_check(blocked.advance(0.1, movement)["shots"].is_empty(), "neither side fires through wall")
	var farther := _state(3, 0, 2, Vector3(-9, 0.5, 96), UNARMED)
	blocked.add_unit(farther)
	_check(blocked.nearest_enemy(behind) == farther, "visible farther enemy wins over blocked nearer enemy")


func _movement_cooldown_and_death() -> void:
	var movement := MovementSimulation.new(MOVEMENT)
	_check(movement.initialize_navigation(), "navigation ready")
	var combat := CombatSimulation.new(MAP)
	var mobile := _state(1, 42, 1, Vector3(10, 0.5, 100), MOBILE)
	var stationary := _state(2, 42, 1, Vector3(12, 0.5, 100), STATIONARY)
	var unarmed := _state(3, 42, 1, Vector3(14, 0.5, 100), UNARMED)
	var enemy := _state(4, 0, 2, Vector3(12, 0.5, 104), STATIONARY)
	for state: UnitState in [mobile, stationary, unarmed, enemy]:
		movement.add_unit(state)
		combat.add_unit(state)
	for id: int in [1, 2, 3]:
		_check(movement.request_move(id, 42, Vector3(14, 0, 106)).is_empty(), "move accepted")
	var original_route := movement.move_paths([1])[0]
	var result := combat.advance(0.1, movement)
	_check(result["shots"].size() == 2, "mobile player and stationary rebel fire; moving stationary and unarmed do not")
	_check(enemy.health == 90.0 and stationary.health == 90.0, "immediate server damage and rebel retaliation")
	_check(movement.move_paths([1])[0] == original_route, "combat neither pursues nor replaces movement")
	_check(combat.advance(0.5, movement)["shots"].is_empty(), "cooldown blocks early shot")
	_check(combat.advance(0.5, movement)["shots"].size() == 2, "cooldown expires independently")
	movement.stop_owner(42)
	result = combat.advance(1.0, movement)
	_check(result["shots"].size() == 3, "stationary weapon fires after stopping; unarmed never fires")
	_check(movement.request_move(4, 0, Vector3(16, 0, 104)).is_empty(), "victim has movement before death")
	enemy.health = 10.0
	result = combat.advance(1.0, movement)
	_check(result["deaths"] == [4] and enemy.health == 0.0, "lethal damage yields one death")
	_check(not combat._units.has(4) and not combat._cooldowns.has(4) and not movement.is_moving(4), "death removes attack cooldown and movement")
	_check(movement.request_move(4, 0, Vector3(16, 0, 104)) == "unknown unit", "dead commands rejected")
	_check(combat.advance(2.0, movement)["shots"].is_empty(), "dead rebel cannot fire; allies do not attack each other")


func _server_snapshot_checks() -> void:
	# Exercise the server tick without transport or client startup.
	var network := root.get_node("NetworkManager")
	_check(network._movement.initialize_navigation(), "server navigation")
	network._initialize_rebels()
	_check(network.live_snapshots().size() == 3, "rebels initialized once")
	var victim: UnitState = network._authoritative_units[1]
	victim.health = 10.0
	var attacker := _state(100, 42, 1, victim.position + Vector3(1, 0, 0), MOBILE)
	network._authoritative_units[100] = attacker
	network._movement.add_unit(attacker)
	network._combat.add_unit(attacker)
	network._pending_positions[1] = victim.position
	network._physics_process(0.1)
	_check(not network._authoritative_units.has(1) and not network._pending_positions.has(1), "server removes death and pending position")
	network._initialize_rebels()
	_check(not network._authoritative_units.has(1), "late join cannot regenerate dead rebels")
	attacker.health = 37.0
	var found := false
	for snapshot: Dictionary in network.live_snapshots():
		_check(snapshot["unit_id"] != 1, "late join omits dead rebel")
		if snapshot["unit_id"] == 100:
			found = snapshot["health"] == 37.0 and snapshot["maximum_health"] == 100.0 and snapshot["team_id"] == 1 and snapshot["owner_peer_id"] == 42
	_check(found, "snapshot retains current health team and owner")
	network.set_physics_process(false)


func _presentation_checks() -> void:
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	world._on_unit_spawn_received(501, 42, Vector3(10, 0.5, 100))
	world._on_unit_combat_state_received(501, 2, 100.0, 37.0)
	var unit: Node3D = world._visual_units[501]
	_check(unit.health == 37.0 and unit.team_id == 2, "client displays received health and team")
	var selection: Dictionary[int, Node3D] = {501: unit}
	world._replace_selection(selection)
	world._move_targets[501] = Vector3(12, 0.5, 100)
	world._route_points[501] = PackedVector3Array([unit.position, Vector3(12, 0.5, 100)])
	world._route_progress[501] = 0
	world._update_unit_path(501)
	world._on_unit_death_received(501)
	_check(world._selected_units.is_empty() and world._movement_paths.is_empty() and world._move_targets.is_empty() and world._route_points.is_empty(), "death immediately clears selection and path")
	var ids: Array[int] = [501]
	var positions: Array[Vector3] = [Vector3(20, 0.5, 100)]
	world._on_unit_positions_received(ids, positions)
	world._on_unit_spawn_received(501, 42, Vector3(10, 0.5, 100))
	world._on_unit_combat_state_received(501, -1, -1.0, 99.0)
	_check(world._visual_units.is_empty(), "late position health and spawn cannot resurrect dead unit")
	world._on_combat_shot_received(Vector3(10, 0.5, 100), Vector3(12, 0.5, 100))
	var shot: Node = world.get_child(world.get_child_count() - 1)
	await create_timer(0.2).timeout
	# queue_free is deferred; timers can expire together in a slow headless frame.
	await process_frame
	_check(not is_instance_valid(shot), "shot visual expires")
	world.queue_free()
	await process_frame
	_presentation_completed = true


func _run() -> void:
	_target_and_visibility()
	_movement_cooldown_and_death()
	_server_snapshot_checks()
	await _presentation_checks()
	_check(_presentation_completed, "presentation checks complete without script errors")
	if _failures == 0:
		print("PASS Prototype 0.2A isolated simulation, server snapshot and presentation checks (no clients launched)")
	quit(0 if _failures == 0 else 1)
