extends SceneTree

const CONFIG = preload("res://data/prototype_movement.tres")
const ARMED = preload("res://data/unit_stationary.tres")
const UNARMED = preload("res://data/unit_unarmed.tres")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	var map := PrototypeMapDefinition.new()
	map.obstacles = []
	var movement := MovementSimulation.new(CONFIG)
	check(movement.initialize_navigation(map), "navigation")
	var combat := CombatSimulation.new(map)
	var a := UnitState.new(10, 42, Vector3(10, 0.5, 100))
	a.configure(1, ARMED)
	a.yaw = PI
	var b := UnitState.new(11, 42, Vector3(12, 0.5, 100))
	b.configure(1, UNARMED)
	var enemy := UnitState.new(20, 0, Vector3(10, 0.5, 104))
	enemy.configure(2, UNARMED)
	var ally := UnitState.new(21, 99, Vector3(10, 0.5, 101))
	ally.configure(1, ARMED)
	for unit: UnitState in [a, b, enemy, ally]:
		movement.add_unit(unit)
		combat.add_unit(unit)
	check(movement.request_move(11, 42, Vector3(12, 0, 110)).is_empty(), "unarmed old order")
	var old := movement.move_paths([11])[0]
	var result := movement.request_group_move([999, 21, 11, 10, 10], 42, Vector3(10, 0, 112), MovementSimulation.MoveMode.ATTACK)
	check(result.unit_ids == [10], "mixed selection ownership weapon and dedup")
	check(movement.move_paths([11])[0] == old, "unarmed preserves order")
	var route := movement.move_paths([10])[0]
	var start := a.position
	movement.update_attack_engagement(combat)
	check(not movement.is_moving(10) and movement._targets.has(10), "engagement parks but retains destination")
	movement.advance(0.25)
	check(a.position == start and movement.move_paths([10])[0] == route, "park preserves exact route")
	check(combat.nearest_enemy(a) == enemy, "same team other owner never enemy")
	check(not combat.advance(0.1, movement).shots.is_empty(), "stationary weapon shoots while parked")
	map.obstacles = [Rect2(9, 102, 2, 0.5)]
	movement.update_attack_engagement(combat)
	check(movement.is_moving(10), "wall blocks attackable target and does not induce pursuit")
	map.obstacles = []
	enemy.position.z = 119
	movement.update_attack_engagement(combat)
	movement.advance(0.25)
	check(a.position.z > start.z and movement._attack_moves.has(10), "out of range resumes existing path")
	enemy.position = a.position + Vector3(0, 0, 2)
	movement.update_attack_engagement(combat)
	check(not movement.is_moving(10), "reentry parks again")
	enemy.health = 1
	combat.advance(2, movement)
	movement.update_attack_engagement(combat)
	check(movement.is_moving(10) and not movement._units.has(20), "death resumes without chase")
	check(not movement.request_move(10, 99, Vector3(10, 0, 110), 2).is_empty(), "foreign sender rejected")
	check(not movement.request_move(10, 42, Vector3(NAN, 0, 110), 2).is_empty(), "invalid target rejected")
	check(not movement.request_move(10, 42, Vector3(10, 0, 110), 99).is_empty(), "invalid command type rejected")
	check(movement.request_move(10, 42, Vector3(10, 0, 110)).is_empty() and not movement._attack_moves.has(10), "basic replaces attack")
	movement.request_move(10, 42, Vector3(10, 0, 112), 2)
	check(movement.request_stop([10], 42) == [10] and not movement._attack_moves.has(10) and not movement._paths.has(10), "stop clears attack path")
	check(movement.request_stop([10], 42) == [10], "repeat stop")
	check(movement.request_move(10, 42, Vector3(10, 0, 112), 1).is_empty(), "fast after stop")
	a.health = 0
	check(not movement.request_move(10, 42, Vector3(10, 0, 112), 2).is_empty(), "dead ignores attack")
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	var key := InputEventKey.new()
	key.keycode = KEY_Q
	key.pressed = true
	check(world._is_attack_move_key(key), "Q recognized")
	key.echo = true
	check(not world._is_attack_move_key(key), "Q repeat ignored")
	key.echo = false
	var field := LineEdit.new()
	world._selection_rectangle.get_parent().add_child(field)
	field.grab_focus()
	check(not world._is_attack_move_key(key), "GUI Q ignored")
	field.release_focus()
	world._toggle_fast_move()
	world._arm_attack_move()
	check(world._attack_move_armed and not world._fast_move_armed and not world._left_pressed, "Q replaces F and cancels selection drag")
	check(world._consume_move_mode() == MovementSimulation.MoveMode.ATTACK, "Q then right click submits attack")
	check(not world._attack_move_armed and not world._movement_mode_hint.visible, "attack submission exits mode")
	check(world._consume_move_mode() == MovementSimulation.MoveMode.BASIC, "subsequent right click is basic")
	world._arm_attack_move()
	world._toggle_fast_move()
	check(world._fast_move_armed and not world._attack_move_armed, "F replaces Q")
	world._arm_attack_move()
	world._cancel_attack_move()
	check(not world._attack_move_armed, "mode cancellation")
	world._on_unit_spawn_received(101, 1, Vector3(10, 0.5, 100))
	var ids: Array[int] = [101]
	var targets: Array[Vector3] = [Vector3(10, 0.5, 112)]
	var paths: Array[PackedVector3Array] = [PackedVector3Array([Vector3(10, 0.5, 100), targets[0]])]
	world._on_unit_move_targets_received(ids, targets)
	world._on_unit_move_paths_received(ids, paths)
	var parked: Array[Vector3] = [Vector3(10, 0.5, 102)]
	world._on_unit_positions_received(ids, parked)
	world._on_unit_positions_received(ids, parked)
	check(world._route_points.has(101), "repeated parked position retains owner route")
	world._on_unit_stops_received(ids, parked)
	check(not world._route_points.has(101), "explicit stop clears presentation")
	world.queue_free()
	await process_frame
	print("Prototype 0.2D isolated checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
