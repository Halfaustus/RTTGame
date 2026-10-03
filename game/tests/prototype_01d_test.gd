extends SceneTree

const CONFIG: MovementConfig = preload("res://data/prototype_movement.tres")
const MAP: PrototypeMapDefinition = preload("res://data/prototype_map.tres")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> bool:
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)
	return condition


func _new_simulation(definition: PrototypeMapDefinition = MAP) -> MovementSimulation:
	var simulation := MovementSimulation.new(CONFIG)
	_check(simulation.initialize_navigation(definition), "synchronous navigation initialization")
	return simulation


func _validate_route(simulation: MovementSimulation, path: PackedVector3Array) -> void:
	_check(path.size() >= 2, "route has start and end")
	for index: int in path.size() - 1:
		_check(simulation._navigation.segment_is_walkable(path[index], path[index + 1]), "entire segment clears inflated obstacles")


func _startup_and_validation() -> void:
	var simulation := MovementSimulation.new(CONFIG)
	var unit := UnitState.new(1, 42, CONFIG.spawn_origin)
	simulation.add_unit(unit)
	_check(not simulation.is_navigation_ready(), "initial navigation state is explicit")
	_check(simulation.request_move(1, 42, Vector3(0, 0, 100)) == "navigation not ready", "not-ready is distinct from unreachable")
	_check(not simulation.has_active_moves(), "not-ready does not mutate moves")
	_check(simulation.initialize_navigation(), "navigation ready without waiting for physics frames")
	_check(simulation.request_move(1, 99, Vector3(0, 0, 90)) == "not owner", "sender ownership")
	_check(simulation.request_move(999, 42, Vector3(0, 0, 90)) == "unknown unit", "unknown ID")
	_check(simulation.request_move(1, 42, Vector3(NAN, 0, 90)) == "non-finite target", "NaN rejection")
	_check(simulation.request_move(1, 42, Vector3(999, 0, 90)) == "target outside prototype bounds", "map bounds rejection")
	_check(simulation.request_move(1, 42, Vector3(0, 3, 90)) == "target is not on the ground", "ground validation")
	_check(not simulation._navigation.is_position_walkable(Vector3(4.3, 0.5, 94)), "unit footprint cannot clip wall edge")
	_check(simulation._navigation.is_position_walkable(Vector3(4.75, 0.5, 94)), "safe clearance beside wall")
	for id: int in range(1, 49):
		var position: Variant = simulation.resolve_spawn_position(CONFIG.spawn_position(id))
		_check(position != null, "walkable spawn fallback for unit %d" % id)
		if position != null:
			_check(simulation._navigation.is_position_walkable(position), "spawn outside static obstacles")
	print("CHECK startup, ownership, invalid targets and spawns")


func _wall_and_movement() -> void:
	var simulation := _new_simulation()
	var unit := UnitState.new(1, 42, CONFIG.spawn_origin)
	simulation.add_unit(unit)
	if not _check(simulation.request_move(1, 42, Vector3(-3, 0, 90)).is_empty(), "wall-crossing request accepted"):
		return
	var ids: Array[int] = [1]
	var route := simulation.move_paths(ids)[0]
	_check(route.size() > 2, "wall requires a detour")
	_validate_route(simulation, route)
	_check(not simulation._navigation.segment_is_walkable(unit.position, Vector3(-3, 0.5, 90)), "straight route is blocked")
	var route_length := 0.0
	for index: int in route.size() - 1:
		route_length += route[index].distance_to(route[index + 1])
	_check(route_length > 10.0, "detour is longer than the blocked straight line")
	for _tick: int in 1000:
		if not simulation.has_active_moves():
			break
		simulation.advance(0.025)
		_check(simulation._navigation.is_position_walkable(unit.position), "movement never places footprint inside wall")
	_check(not simulation.has_active_moves(), "stops at destination")
	_check(unit.position == Vector3(-3, 0.5, 90), "exact reachable destination")
	var arrival := unit.position
	simulation.advance(1.0)
	_check(unit.position == arrival, "no drift after arrival")
	# One large tick must consume distance along all segments rather than cut a corner.
	unit.position = CONFIG.spawn_origin
	simulation.request_move(1, 42, Vector3(-3, 0, 90))
	simulation.advance(route_length / CONFIG.speed + 0.1)
	_check(unit.position == Vector3(-3, 0.5, 90), "large-delta arrival")
	unit.position = CONFIG.spawn_origin
	simulation.request_move(1, 42, Vector3(-3, 0, 90))
	simulation.advance(0.2)
	var current := unit.position
	_check(simulation.request_move(1, 42, Vector3(-6, 0, 102)).is_empty(), "mid-move replacement accepted")
	_check(simulation.move_paths(ids)[0][0] == current, "new path starts at authoritative current position")
	simulation.advance(20.0)
	_check(unit.position == Vector3(-6, 0.5, 102), "new command replaces old path")
	simulation.request_move(1, 42, Vector3(0, 0, 94))
	var nearby := simulation.move_targets(ids)[0]
	_check(nearby.distance_to(Vector3(0, 0.5, 94)) <= CONFIG.target_search_radius, "wall target uses bounded nearby fallback")
	_check(simulation._navigation.is_position_walkable(nearby), "wall target ends on walkable ground")
	_validate_route(simulation, simulation.move_paths(ids)[0])
	simulation.advance(20.0)
	_check(unit.position == nearby, "arrives at wall-target fallback")
	simulation.request_move(1, 42, Vector3(-6, 0, 102))
	var stopped := unit.position
	simulation.stop_owner(42)
	simulation.advance(5.0)
	_check(unit.position == stopped and simulation._paths.is_empty(), "owner disconnect clears paths and stops")
	print("CHECK wall detour, continuous clearance, arrival, redirect, obstacle fallback and disconnect")


func _group_slots() -> void:
	var simulation := _new_simulation()
	for id: int in range(1, 5):
		simulation.add_unit(UnitState.new(id, 42 if id < 4 else 99, CONFIG.spawn_position(id)))
	var result := simulation.request_group_move([3, 1, 3, 4, 999, 2], 42, Vector3(0, 0, 94))
	if not _check(result["rejection"].is_empty(), "wall group accepts reachable fallbacks"):
		return
	_check(result["unit_ids"] == [1, 2, 3], "stable ID order, duplicates and foreign IDs removed")
	var ids: Array[int] = result["unit_ids"]
	var targets := simulation.move_targets(ids)
	for index: int in targets.size():
		_check(simulation._navigation.is_position_walkable(targets[index]), "every slot is walkable")
		_validate_route(simulation, simulation.move_paths(ids)[index])
		for other: int in range(index + 1, targets.size()):
			_check(targets[index].distance_to(targets[other]) >= CONFIG.unit_width + CONFIG.destination_gap - 0.0001, "fallback slots do not stack")
	_check(not simulation._targets.has(4), "foreign unit unchanged")
	for corner: Vector3 in [Vector3(-20, 0, 80), Vector3(60, 0, 120)]:
		var edge := simulation.request_group_move([1, 2, 3], 42, corner)
		_check(edge["unit_ids"] == [1, 2, 3], "edge formation remains reachable")
		for target: Vector3 in simulation.move_targets(ids):
			_check(simulation._navigation.is_position_walkable(target), "edge slots include footprint clearance")
	print("CHECK group walkability, reachability, ownership, non-overlapping fallback and map edges")


func _unreachable_preserves_orders() -> void:
	var divided := PrototypeMapDefinition.new()
	divided.obstacles = [Rect2(CONFIG.minimum_xz.x, 94, CONFIG.maximum_xz.x - CONFIG.minimum_xz.x, 1)]
	var simulation := _new_simulation(divided)
	var first := UnitState.new(1, 42, Vector3(-3, 0.5, 100))
	var second := UnitState.new(2, 42, Vector3(-3, 0.5, 90))
	simulation.add_unit(first)
	simulation.add_unit(second)
	simulation.request_move(1, 42, Vector3(-3, 0, 98))
	simulation.advance(0.1)
	var old_target: Vector3 = simulation._targets[1]
	var old_path: PackedVector3Array = simulation._paths[1].duplicate()
	var old_index: int = simulation._path_indices[1]
	_check(simulation.request_move(1, 42, Vector3(-3, 0, 90)) == "no reachable destination", "disconnected destination rejected")
	_check(simulation._targets[1] == old_target and simulation._paths[1] == old_path, "single failure preserves old target and path")
	var group := simulation.request_group_move([2, 1], 42, Vector3(0, 0, 90))
	_check(group["unit_ids"] == [2] and group["failed_ids"] == [1], "per-unit reachability permits partial acceptance")
	_check(simulation._targets[1] == old_target and simulation._paths[1] == old_path and simulation._path_indices[1] == old_index, "failed group member keeps complete old order")
	simulation.advance(10.0)
	_check(first.position == old_target, "failed member completes its old command")
	_check(second.position == Vector3(0.75, 0.5, 90), "reachable member completes new command")
	print("CHECK disconnected regions and preserved old orders")


func _geometry_check() -> void:
	var geometry = load("res://scripts/maps/test_map_geometry.gd").new()
	root.add_child(geometry)
	_check(geometry.get_child_count() == MAP.obstacles.size() + 1, "map contains ground and shared obstacles")
	for index: int in MAP.obstacles.size():
		var body: StaticBody3D = geometry.get_node("Obstacle_%d" % index)
		var shape: BoxShape3D = body.get_child(0).shape
		_check(shape.size.x == MAP.obstacles[index].size.x and shape.size.z == MAP.obstacles[index].size.y, "physics geometry agrees with navigation data")
	geometry.free()
	var path = load("res://scripts/core/movement_path_visual.gd").new()
	path.update_route(PackedVector3Array([Vector3.ZERO, Vector3(2, 0, 0), Vector3(2, 0, 2)]))
	_check(path.mesh.get_surface_count() == 1, "bent dashed route generates mesh")
	var vertices: PackedVector3Array = path.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(vertices.size() == 36, "dashes cover both route segments")
	path.free()
	# Pure presentation geometry check: no scene readiness, input, or connection.
	var world = load("res://scripts/core/game_world.gd").new()
	world._route_points[1] = PackedVector3Array([Vector3.ZERO, Vector3(2, 0, 0), Vector3(2, 0, 2)])
	world._route_progress[1] = 0
	var remaining: PackedVector3Array = world._remaining_visual_route(1, Vector3(2, 0, 1))
	_check(remaining == PackedVector3Array([Vector3(2, 0, 1), Vector3(2, 0, 2)]), "remaining visual route advances after corner")
	world._clear_unit_path(1)
	_check(world._route_points.is_empty() and world._route_progress.is_empty(), "route references cleared")
	world.free()
	print("CHECK map collision data and dashed polyline geometry")


func _run() -> void:
	if "--server-smoke" in OS.get_cmdline_user_args():
		# Dedicated-server-only check: never connects a client or assumes a server player.
		var network := root.get_node("NetworkManager")
		_check(network.start_server(17779), "headless dedicated server starts")
		_check(network._movement.is_navigation_ready(), "navigation ready when server begins listening")
		_check(network._authoritative_units.is_empty(), "dedicated server has no player units")
		if network.multiplayer.has_multiplayer_peer():
			network.multiplayer.multiplayer_peer.close()
	else:
		_startup_and_validation()
		_wall_and_movement()
		_group_slots()
		_unreachable_preserves_orders()
		_geometry_check()
	if _failures == 0:
		print("PASS Prototype 0.1D checks (no clients launched)")
	quit(0 if _failures == 0 else 1)
