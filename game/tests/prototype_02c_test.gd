extends SceneTree

const CONFIG: MovementConfig = preload("res://data/prototype_movement.tres")
const MAP: PrototypeMapDefinition = preload("res://data/prototype_map.tres")
const VEHICLE: UnitDefinition = preload("res://data/unit_mobile.tres")
const INFANTRY: UnitDefinition = preload("res://data/unit_stationary.tres")
const A := Vector3(-8, 0.5, 102)
const B := Vector3(8, 0.5, 102)

var _failures: int = 0
var _presentation_completed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)


func _simulation(definition: PrototypeMapDefinition, unit_definition: UnitDefinition, position: Vector3) -> MovementSimulation:
	var simulation := MovementSimulation.new(CONFIG)
	_check(simulation.initialize_navigation(definition), "navigation initialized")
	var unit := UnitState.new(1, 42, position)
	unit.configure(1, unit_definition)
	simulation.add_unit(unit)
	return simulation


func _order(simulation: MovementSimulation, target: Vector3, mode: int) -> PackedVector3Array:
	_check(simulation.request_move(1, 42, Vector3(target.x, 0, target.z), mode).is_empty(), "order accepted")
	return simulation.move_paths([1])[0]


func _validate(simulation: MovementSimulation, path: PackedVector3Array) -> void:
	for index: int in path.size() - 1:
		_check(simulation._navigation.segment_is_walkable(path[index], path[index + 1]), "smoothed segment preserves footprint clearance")


func _route_choices() -> void:
	var vehicle := _simulation(MAP, VEHICLE, A)
	var basic := _order(vehicle, B, MovementSimulation.MoveMode.BASIC)
	_check(basic == PackedVector3Array([A, B]), "basic chooses shortest unobstructed straight distance")
	var fast := _order(vehicle, B, MovementSimulation.MoveMode.FAST)
	_validate(vehicle, fast)
	var basic_time := vehicle._navigation.path_cost(basic, true, vehicle._units[1])
	var fast_time := vehicle._navigation.path_cost(fast, true, vehicle._units[1])
	_check(fast.size() > 2 and fast_time < basic_time * 0.8, "fast vehicle uses beneficial road detour after smoothing")
	_check(vehicle._navigation.path_cost(fast, false) > 16.0, "road route is longer in distance")
	print("CHECK vehicle A-B: basic %.3f s / %.3f m; fast %.3f s / %.3f m" % [basic_time, vehicle._navigation.path_cost(basic, false), fast_time, vehicle._navigation.path_cost(fast, false)])
	var elapsed := 0.0
	while vehicle.has_active_moves() and elapsed < 20.0:
		vehicle.advance(0.05)
		elapsed += 0.05
	_check(vehicle._units[1].position == B and elapsed >= fast_time and elapsed < fast_time + 5.0, "road traversal arrives with bounded configured turn overhead")
	var long_map := PrototypeMapDefinition.new()
	long_map.hardened_surfaces = [Rect2(-9, 101, 2, 18), Rect2(-9, 117, 18, 2), Rect2(7, 101, 2, 18)]
	var long_vehicle := _simulation(long_map, VEHICLE, A)
	var long_fast := _order(long_vehicle, B, MovementSimulation.MoveMode.FAST)
	_check(long_fast == basic, "overlong road detour loses to direct route")
	var short_vehicle := _simulation(MAP, VEHICLE, A)
	var short_fast := _order(short_vehicle, Vector3(-4, 0.5, 102), MovementSimulation.MoveMode.FAST)
	_check(short_fast == PackedVector3Array([A, Vector3(-4, 0.5, 102)]), "default-map A-C rejects road detour that is too long for short trip")
	var infantry := _simulation(MAP, INFANTRY, A)
	var infantry_basic := _order(infantry, B, MovementSimulation.MoveMode.BASIC)
	var infantry_fast := _order(infantry, B, MovementSimulation.MoveMode.FAST)
	_check(infantry_basic == basic and infantry_fast == basic, "equal-speed infantry takes same shortest route in both modes")
	_check(infantry._units[1].speed_on(true, 0) == infantry._units[1].speed_on(false, 0), "infantry surfaces have equal speed")


func _speed_and_boundaries() -> void:
	for start: Vector3 in [Vector3(-8, 0.5, 102), Vector3(10, 0.5, 102)]:
		var end := start + Vector3(0, 0, 2)
		var basic := _simulation(MAP, VEHICLE, start)
		var fast := _simulation(MAP, VEHICLE, start)
		basic._units[1].yaw = PI
		fast._units[1].yaw = PI
		_order(basic, end, MovementSimulation.MoveMode.BASIC)
		_order(fast, end, MovementSimulation.MoveMode.FAST)
		basic.advance(0.1)
		fast.advance(0.1)
		var expected := 0.8 if start.x == -8 else 0.3
		_check(absf(basic._units[1].position.distance_to(start) - expected) < 0.00001, "actual speed follows current surface")
		_check(basic._units[1].position == fast._units[1].position, "mode does not boost same-surface speed")
	var crossing := PrototypeMapDefinition.new()
	crossing.hardened_surfaces = [Rect2(2, 100, 4, 4), Rect2(3, 100, 2, 4)]
	for reverse: bool in [false, true]:
		var start := Vector3(8 if reverse else 0, 0.5, 102)
		var end := Vector3(0 if reverse else 8, 0.5, 102)
		var large := _simulation(crossing, VEHICLE, start)
		var small := _simulation(crossing, VEHICLE, start)
		large._units[1].yaw = PI / 2 if reverse else -PI / 2
		small._units[1].yaw = large._units[1].yaw
		_order(large, end, MovementSimulation.MoveMode.BASIC)
		_order(small, end, MovementSimulation.MoveMode.BASIC)
		large.advance(1.5)
		for tick: int in 90:
			small.advance(1.0 / 60.0)
		var expected := Vector3(1 if reverse else 7, 0.5, 102)
		_check(large._units[1].position.distance_to(expected) < 0.0001, "large tick switches speed at entry and exit, including overlapping roads")
		_check(large._units[1].position.distance_to(small._units[1].position) < 0.001, "boundary traversal independent of tick subdivision")
		_check(absf(large._navigation.surface.segment_time(start, end, large._units[1], 4) - (4.0 / 3.0 + 4.0 / 8.0)) < 0.00001, "time cost integrates both surfaces")
	for direction: float in [-1.0, 1.0]:
		var boundary := _simulation(crossing, VEHICLE, Vector3(2, 0.5, 102))
		_order(boundary, Vector3(2 + direction * 2, 0.5, 102), MovementSimulation.MoveMode.BASIC)
		boundary._units[1].yaw = PI / 2 if direction < 0 else -PI / 2
		boundary.advance(0.1)
		var expected := 2.0 + direction * (0.3 if direction < 0 else 0.8)
		_check(absf(boundary._units[1].position.x - expected) < 0.00001, "starting on boundary uses departing surface")


func _orders_and_obstacles() -> void:
	var vehicle := _simulation(MAP, VEHICLE, Vector3(-3, 0.5, 100))
	for mode: int in [MovementSimulation.MoveMode.BASIC, MovementSimulation.MoveMode.FAST]:
		var path := _order(vehicle, Vector3(-3, 0.5, 90), mode)
		_validate(vehicle, path)
		_check(path.size() > 2, "both modes route around wall")
	var old := vehicle.move_paths([1])[0]
	_check(vehicle.request_move(1, 42, Vector3(8, 0, 102), 99) == "invalid movement mode", "server rejects unknown mode")
	_check(vehicle.move_paths([1])[0] == old, "invalid mode preserves previous command")
	_check(vehicle.request_move(1, 99, Vector3(8, 0, 102), MovementSimulation.MoveMode.FAST) == "not owner", "fast ownership enforced")
	var second := UnitState.new(2, 42, Vector3(0, 0.5, 100))
	second.configure(1, INFANTRY)
	vehicle.add_unit(second)
	var foreign := UnitState.new(3, 99, Vector3(3, 0.5, 100))
	foreign.configure(1, VEHICLE)
	vehicle.add_unit(foreign)
	var result := vehicle.request_group_move([999, 3, 2, 1, 1], 42, Vector3(0, 0, 102), MovementSimulation.MoveMode.FAST, Vector3.FORWARD)
	_check(result["unit_ids"] == [1, 2], "heterogeneous fast group independently filters ownership and duplicates")
	_check(vehicle._targets[1].x == -0.75 and vehicle._targets[2].x == 0.75, "stable-ID horizontal row retained")
	for id: int in [1, 2]:
		_validate(vehicle, vehicle.move_paths([id])[0])
	vehicle.advance(0.1)
	var current := vehicle._units[1].position
	_check(vehicle.request_stop([1], 42) == [1], "stop command interface still accepted; no S shortcut")
	vehicle.advance(0.1)
	_check(vehicle._units[1].position == current and not vehicle.is_moving(1), "stopped vehicle stays")
	_order(vehicle, B, MovementSimulation.MoveMode.FAST)
	_check(vehicle.is_moving(1) and vehicle._targets[1] == B, "new fast order replaces old destination after stop")
	var invalid_group := vehicle.request_group_move([1, 2], 42, Vector3(0, 0, 100), -1)
	_check(invalid_group["rejection"] == "invalid movement mode" and vehicle._targets[1] == B, "invalid group mode leaves commands unchanged")
	var isolated := PrototypeMapDefinition.new()
	isolated.obstacles = [Rect2(15, 80, 1, 40)]
	var inaccessible := _simulation(isolated, VEHICLE, Vector3(10, 0.5, 100))
	_order(inaccessible, Vector3(12, 0.5, 100), MovementSimulation.MoveMode.BASIC)
	old = inaccessible.move_paths([1])[0]
	_check(inaccessible.request_move(1, 42, Vector3(20, 0, 100), MovementSimulation.MoveMode.FAST) == "no reachable destination", "fast rejects unreachable region")
	_check(inaccessible.move_paths([1])[0] == old, "unreachable fast preserves old route")


func _presentation() -> void:
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	_check(world._consume_move_mode() == MovementSimulation.MoveMode.BASIC, "default right click is basic")
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	_check(world._is_fast_move_key(key), "F press recognized")
	key.echo = true
	_check(not world._is_fast_move_key(key), "F repeat ignored")
	key.echo = false
	key.pressed = false
	_check(not world._is_fast_move_key(key), "F release ignored")
	key.pressed = true
	key.ctrl_pressed = true
	_check(not world._is_fast_move_key(key), "modified F shortcut ignored")
	key.ctrl_pressed = false
	world._toggle_fast_move()
	_check(world._fast_move_armed and world._movement_mode_hint.visible, "F arms fast mode and shows hint")
	_check(world._consume_move_mode() == MovementSimulation.MoveMode.FAST, "armed right click submits fast")
	_check(not world._fast_move_armed and not world._movement_mode_hint.visible, "right click exits fast mode")
	_check(world._consume_move_mode() == MovementSimulation.MoveMode.BASIC, "subsequent right click is basic")
	world._toggle_fast_move()
	world._toggle_fast_move()
	_check(not world._fast_move_armed, "second F cancels")
	var field := LineEdit.new()
	world._selection_rectangle.get_parent().add_child(field)
	field.grab_focus()
	_check(not world._is_fast_move_key(key), "focused GUI retains F input")
	field.release_focus()
	field.queue_free()
	world._toggle_fast_move()
	world._cancel_fast_move()
	_check(not world._fast_move_armed, "focus/disconnection cancellation resets mode")
	world._on_unit_spawn_received(101, 1, A)
	world._on_unit_type_received(101, UnitDefinition.UnitType.ARMORED_VEHICLE)
	_check(world._visual_units[101].get_node("MeshInstance3D").mesh is BoxMesh, "vehicle has distinct box silhouette")
	world._on_unit_spawn_received(102, 42, B)
	world._on_unit_type_received(102, UnitDefinition.UnitType.INFANTRY)
	_check(world._visual_units[102].get_node("MeshInstance3D").mesh is SphereMesh, "infantry has distinct sphere silhouette")
	var ids: Array[int] = [101, 102]
	var positions: Array[Vector3] = [B, A]
	world._on_unit_move_targets_received(ids, positions)
	var routes: Array[PackedVector3Array] = [PackedVector3Array([A, Vector3(-8, 0.5, 106), Vector3(8, 0.5, 106), B]), PackedVector3Array([B, A])]
	world._on_unit_move_paths_received(ids, routes)
	_check(world._route_points[101] == routes[0] and not world._route_points.has(102), "actual road route shown only to owner")
	world._on_unit_stops_received(ids, positions)
	_check(world._route_points.is_empty(), "stop clears road route")
	var unit := UnitState.new(1, 42, A)
	unit.configure(1, VEHICLE)
	_check(unit.snapshot()["unit_type"] == UnitDefinition.UnitType.ARMORED_VEHICLE, "late-join snapshot carries type")
	world.queue_free()
	await process_frame
	_presentation_completed = true


func _route_cache_checks() -> void:
	var simulation := _simulation(MAP, VEHICLE, A)
	var graph = simulation._navigation._routes
	var point_count: int = graph.get_point_count()
	var fast := _order(simulation, B, MovementSimulation.MoveMode.FAST)
	_check(not graph._edge_costs.is_empty(), "static edge costs cached")
	_check(graph.get_point_count() == point_count, "temporary query endpoints removed")
	var definition := VEHICLE.duplicate() as UnitDefinition
	definition.hardened_speed = definition.unhardened_speed
	simulation._units[1].configure(1, definition)
	var equal_speed := _order(simulation, B, MovementSimulation.MoveMode.FAST)
	_check(equal_speed == PackedVector3Array([A, B]), "changed speed profile does not reuse old road advantage")
	simulation._units[1].configure(1, VEHICLE)
	var restored := _order(simulation, B, MovementSimulation.MoveMode.FAST)
	_check(restored == fast, "restored profile replans correct road route")
	_check(graph.get_point_count() == point_count, "queries do not leak virtual points")
	_check(simulation.initialize_navigation(PrototypeMapDefinition.new()), "navigation reinitialized")
	_check(_order(simulation, B, MovementSimulation.MoveMode.FAST) == PackedVector3Array([A, B]), "map rebuild invalidates cached road costs")


func _run() -> void:
	_route_choices()
	_speed_and_boundaries()
	_orders_and_obstacles()
	_route_cache_checks()
	await _presentation()
	_check(_presentation_completed, "presentation checks complete")
	if _failures == 0:
		print("PASS Prototype 0.2C terrain routing, boundary speed, modes, orders and presentation (no clients launched)")
	quit(0 if _failures == 0 else 1)
