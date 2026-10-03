extends SceneTree

const CONFIG = preload("res://data/prototype_movement.tres")
const VEHICLE = preload("res://data/unit_mobile.tres")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL 0.2G: " + label)

func _run() -> void:
	var simulation := MovementSimulation.new(CONFIG)
	check(simulation.initialize_navigation(PrototypeMapDefinition.new()), "navigation")
	var a := UnitState.new(1, 42, Vector3(10, 0.5, 100))
	a.configure(1, VEHICLE)
	var b := UnitState.new(2, 42, Vector3(12, 0.5, 100))
	b.configure(1, VEHICLE)
	simulation.add_unit(a)
	simulation.add_unit(b)
	for mode: int in [0, 1, 2, 3]:
		a.position = Vector3(10, 0.5, 100)
		a.yaw = 0
		check(simulation.request_move(1, 42, Vector3(16, 0, 100), mode).is_empty(), "mode accepted")
		simulation.advance(0.25)
		check(a.position == Vector3(10, 0.5, 100) and absf(absf(a.yaw) - PI / 4) < 0.0001, "configured turn before vehicle travel")
		var destination := simulation._targets[1]
		for tick: int in 1000:
			var previous := a.position
			var yaw := a.yaw
			simulation.advance(1.0 / 60)
			check(absf(wrapf(a.yaw - yaw, -PI, PI)) <= PI / 60 + 0.0001, "turn rate bounded")
			var displacement := a.position - previous
			if displacement.length_squared() > 0.0000001:
				var forward := Vector3(-sin(a.yaw), 0, -cos(a.yaw))
				check(displacement.normalized().dot(-forward if mode == 3 else forward) > 0.9999, "no lateral slip")
			if not simulation.has_active_moves():
				break
		check(a.position == destination, "arrival")
		check(absf(wrapf(a.yaw - (PI / 2 if mode == 3 else -PI / 2), -PI, PI)) < 0.0001, "default final facing")
	a.position = Vector3(10, 0.5, 100)
	b.position = Vector3(12, 0.5, 100)
	var result := simulation.request_group_move([2, 1, 1, 999], 42, Vector3(14, 0, 106), 0, Vector3.RIGHT)
	check(result.unit_ids == [1, 2], "stable ID assignment")
	var slots := simulation.move_targets([1, 2])
	check(absf(slots[0].x - slots[1].x) < 0.0001 and absf(slots[1].z - slots[0].z - 1.5) < 0.0001, "row rotated along facing right axis")
	var old := simulation.move_paths([1])[0]
	check(not simulation.request_group_move([1], 42, Vector3(14, 0, 106), 0, Vector3(NAN, 0, 1)).rejection.is_empty(), "invalid facing rejected")
	check(simulation.move_paths([1])[0] == old, "invalid facing retains command")
	for tick: int in 1000:
		simulation.advance(1.0 / 60)
		if not simulation.has_active_moves():
			break
	check(absf(wrapf(a.yaw + PI / 2, -PI, PI)) < 0.0001 and a.position == slots[0], "explicit final facing after arrival")
	simulation.request_move(1, 42, Vector3(a.position.x, 0, a.position.z), 0, Vector3.BACK)
	simulation.advance(0.1)
	var stopped_yaw := a.yaw
	simulation.request_stop([1], 42)
	simulation.advance(5)
	check(a.yaw == stopped_yaw and simulation._final_yaws.is_empty(), "stop cancels final turn and preserves yaw")
	simulation.request_move(1, 42, Vector3(a.position.x, 0, a.position.z))
	simulation.advance(1)
	check(a.yaw == stopped_yaw, "zero distance keeps current yaw")
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.position = Vector2(100, 100)
	press.pressed = true
	world._handle_world_input(press)
	check(world._pending_actions.is_empty(), "press sends no command")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(120, 100)
	world._handle_world_input(motion)
	check(world._right_dragging, "screen pixel threshold")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	world._handle_world_input(escape)
	press.pressed = false
	world._handle_world_input(press)
	check(world._pending_actions.is_empty() and not world._right_pressed, "Esc cancels held right button without submission")
	world.queue_free()
	await process_frame
	print("Prototype 0.2G isolated checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
