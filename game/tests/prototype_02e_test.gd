extends SceneTree

const CONFIG = preload("res://data/prototype_movement.tres")
const VEHICLE = preload("res://data/unit_mobile.tres")
const INFANTRY = preload("res://data/unit_stationary.tres")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func vehicle(id: int, position: Vector3, owner: int = 42) -> UnitState:
	var unit := UnitState.new(id, owner, position)
	unit.configure(1, VEHICLE)
	return unit

func _run() -> void:
	var map := PrototypeMapDefinition.new()
	map.hardened_surfaces = [Rect2(9, 103, 3, 4)]
	var movement := MovementSimulation.new(CONFIG)
	check(movement.initialize_navigation(map), "navigation")
	var unit := vehicle(1, Vector3(10, 0.5, 100))
	movement.add_unit(unit)
	check(movement.request_move(1, 42, Vector3(10, 0, 110), MovementSimulation.MoveMode.REVERSE).is_empty(), "reverse accepted")
	movement.advance(2.0)
	check(unit.position.is_equal_approx(Vector3(10, 0.5, 103)), "unpaved reverse speed 1.5")
	movement.advance(1.0)
	check(unit.position.is_equal_approx(Vector3(10, 0.5, 107)), "paved reverse speed 4")
	movement.advance(1.0)
	check(is_equal_approx(unit.position.z, 108.5), "surface boundary restores reverse speed")
	check(is_zero_approx(unit.yaw), "tail follows travel +Z")
	unit.position = Vector3(10, 0.5, 100)
	unit.yaw = 0
	movement.request_move(1, 42, Vector3(16, 0, 100), MovementSimulation.MoveMode.REVERSE)
	movement.advance(0.25)
	check(unit.position == Vector3(10, 0.5, 100) and is_equal_approx(unit.yaw, PI / 4), "smooth turn before translation, no sideways slip")
	movement.advance(0.5)
	check(unit.position.is_equal_approx(Vector3(10.375, 0.5, 100)) and is_equal_approx(unit.yaw, PI / 2), "turn consumes time then tail-first travel")
	var before := unit.position
	movement.request_stop([1], 42)
	movement.advance(1)
	check(unit.position == before and not movement._reverse_moves.has(1), "stop clears reverse and preserves yaw")
	var infantry := UnitState.new(2, 42, Vector3(12, 0.5, 100))
	infantry.configure(1, INFANTRY)
	movement.add_unit(infantry)
	movement.request_move(2, 42, Vector3(12, 0, 110))
	var old := movement.move_paths([2])[0]
	var second := vehicle(3, Vector3(14, 0.5, 100))
	var foreign := vehicle(4, Vector3(16, 0.5, 100), 99)
	var dead := vehicle(5, Vector3(18, 0.5, 100))
	dead.health = 0
	for state: UnitState in [second, foreign, dead]:
		movement.add_unit(state)
	var result := movement.request_group_move([999, 1, 2, 3, 3, 4, 5], 42, Vector3(10, 0, 112), MovementSimulation.MoveMode.REVERSE, Vector3.FORWARD)
	check(result.unit_ids == [1, 3], "group eligibility ownership life type and duplicates")
	check(movement.move_paths([2])[0] == old, "infantry preserves old command")
	check(is_equal_approx(movement.move_targets([1, 3])[1].x - movement.move_targets([1, 3])[0].x, CONFIG.unit_width + CONFIG.destination_gap), "horizontal slots")
	for mode: int in [0, 1, 2]:
		movement.request_move(1, 42, Vector3(10, 0, 112), 3)
		check(movement.request_move(1, 42, Vector3(10, 0, 110), mode).is_empty() and not movement._reverse_moves.has(1), "new command replaces reverse")
	check(not movement.request_move(1, 99, Vector3(10, 0, 110), 3).is_empty(), "foreign sender")
	check(not movement.request_move(1, 42, Vector3(NAN, 0, 110), 3).is_empty(), "bad target")
	var invalid := VEHICLE.duplicate() as UnitDefinition
	invalid.unhardened_reverse_speed = 0
	second.configure(1, invalid)
	check(not movement.request_move(3, 42, Vector3(14, 0, 110), 3).is_empty(), "invalid reverse config rejected")
	var blocked_map := PrototypeMapDefinition.new()
	blocked_map.obstacles = [Rect2(19, 80, 2, 40)]
	var blocked := MovementSimulation.new(CONFIG)
	check(blocked.initialize_navigation(blocked_map), "disconnected map")
	var trapped := vehicle(6, Vector3(10, 0.5, 100))
	blocked.add_unit(trapped)
	blocked.request_move(6, 42, Vector3(10, 0, 110), 3)
	var retained := blocked.move_paths([6])[0]
	check(not blocked.request_move(6, 42, Vector3(30, 0, 110), 3).is_empty() and blocked.move_paths([6])[0] == retained, "unreachable preserves old reverse route")
	var fighting := MovementSimulation.new(CONFIG)
	check(fighting.initialize_navigation(map), "combat map")
	var shooter := vehicle(7, Vector3(10, 0.5, 100))
	var enemy := UnitState.new(8, 0, Vector3(10, 0.5, 104))
	enemy.configure(2, preload("res://data/unit_unarmed.tres"))
	var combat := CombatSimulation.new(map)
	for state: UnitState in [shooter, enemy]:
		fighting.add_unit(state)
		combat.add_unit(state)
	fighting.request_move(7, 42, Vector3(10, 0, 110), 3)
	check(not combat.advance(0.1, fighting).shots.is_empty(), "moving-fire weapon can shoot reversing")
	shooter.weapon = shooter.weapon.duplicate() as WeaponDefinition
	shooter.weapon.can_fire_while_moving = false
	check(combat.advance(2, fighting).shots.is_empty(), "stationary-only weapon cannot shoot reversing")
	fighting.request_stop([7], 42)
	check(not combat.advance(2, fighting).shots.is_empty(), "stationary-only weapon shoots after stop")
	var detour := MovementSimulation.new(CONFIG)
	check(detour.initialize_navigation(), "obstacle map")
	var turning := vehicle(10, Vector3(-3, 0.5, 100))
	detour.add_unit(turning)
	check(detour.request_move(10, 42, Vector3(-3, 0, 86), 3).is_empty(), "reverse obstacle route")
	var basic_route := detour.move_paths([10])[0]
	detour.request_move(10, 42, Vector3(-3, 0, 86), 0)
	check(detour.move_paths([10])[0] == basic_route, "reverse uses basic shortest route")
	detour.request_move(10, 42, Vector3(-3, 0, 86), 3)
	for tick: int in 2400:
		var previous := turning.position
		var previous_yaw := turning.yaw
		detour.advance(1.0 / 60)
		check(detour._navigation.segment_is_walkable(previous, turning.position), "continuous obstacle clearance")
		check(absf(wrapf(turning.yaw - previous_yaw, -PI, PI)) <= PI / 60 + 0.0001, "bounded turn rate")
		var displacement := turning.position - previous
		if displacement.length_squared() > 0.0000001:
			check(displacement.normalized().dot(Vector3(sin(turning.yaw), 0, cos(turning.yaw))) > 0.9999, "tail aligned, no lateral travel")
		if not detour.has_active_moves():
			break
	check(turning.position.is_equal_approx(Vector3(-3, 0.5, 86)), "detour arrives")
	var network := root.get_node("NetworkManager")
	network._authoritative_units[10] = turning
	var ids: Array[int] = [10]
	check(network.live_snapshots()[0].yaw == turning.yaw and network._unit_yaws(ids) == [turning.yaw], "late join and replication current yaw")
	network._movement.add_unit(turning)
	check(network._movement.initialize_navigation(), "server stop fixture")
	network._movement.request_move(10, 42, Vector3(-10, 0, 86), 3)
	network._movement.advance(0.1)
	var current_yaw := turning.yaw
	network._pending_positions[10] = Vector3.ZERO
	var stop: Dictionary = network._apply_stop(ids, 42)
	check(stop.unit_ids == ids and not network._pending_positions.has(10) and network._unit_yaws(ids)[0] == current_yaw, "stop replicates final turn orientation and removes old buffered position")
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	world._on_unit_spawn_received(10, 1, turning.position)
	world._on_unit_type_received(10, UnitDefinition.UnitType.ARMORED_VEHICLE)
	var yaws: Array[float] = [turning.yaw]
	world._on_unit_orientations_received(ids, yaws)
	check(is_equal_approx(world._visual_units[10].get_node("MeshInstance3D").rotation.y, turning.yaw), "visual follows authoritative yaw")
	check(world._visual_units[10].get_node("MeshInstance3D/FrontMarker").visible, "vehicle nose marker")
	world._on_unit_death_received(10)
	world._on_unit_orientations_received(ids, yaws)
	check(not world._visual_units.has(10), "late yaw cannot revive death")
	world.queue_free()
	await process_frame
	print("Prototype 0.2E isolated reverse checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
