extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func key_event(code: Key, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	return event

func mouse_event(button: MouseButton, pressed: bool = true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = Vector2(100, 100)
	return event

func _run() -> void:
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	for code: Key in [KEY_Q, KEY_F, KEY_R]:
		var expected := MovementSimulation.MoveMode.ATTACK if code == KEY_Q else MovementSimulation.MoveMode.FAST
		if code == KEY_R:
			expected = MovementSimulation.MoveMode.REVERSE
		world._handle_world_input(key_event(code))
		world._handle_world_input(key_event(code, true))
		world._handle_world_input(mouse_event(MOUSE_BUTTON_LEFT))
		world._handle_world_input(mouse_event(MOUSE_BUTTON_LEFT, false))
		check(world._pending_actions.size() == 1 and world._pending_actions[0].type == "click", "left click only selects")
		check(world._reverse_move_armed if code == KEY_R else (world._attack_move_armed if code == KEY_Q else world._fast_move_armed), "left click and echo retain pending mode")
		world._pending_actions.clear()
		world._handle_world_input(mouse_event(MOUSE_BUTTON_RIGHT))
		world._handle_world_input(mouse_event(MOUSE_BUTTON_RIGHT, false))
		check(world._pending_actions.size() == 1 and world._pending_actions[0].type == "move" and world._pending_actions[0].mode == expected, "right click confirms pending command")
		check(not world._attack_move_armed and not world._fast_move_armed and not world._reverse_move_armed and not world._movement_mode_hint.visible, "confirmation exits mode")
		world._pending_actions.clear()
		world._handle_world_input(mouse_event(MOUSE_BUTTON_RIGHT))
		world._handle_world_input(mouse_event(MOUSE_BUTTON_RIGHT, false))
		check(world._pending_actions[0].mode == MovementSimulation.MoveMode.BASIC, "no pending command means basic")
		world._pending_actions.clear()
		world._handle_world_input(key_event(code))
		world._handle_world_input(key_event(KEY_ESCAPE))
		check(not world._attack_move_armed and not world._fast_move_armed and not world._reverse_move_armed and world._pending_actions.is_empty(), "Esc cancels without command")
		world._handle_world_input(key_event(code))
		var field := LineEdit.new()
		world._selection_rectangle.get_parent().add_child(field)
		field.grab_focus()
		world._handle_world_input(mouse_event(MOUSE_BUTTON_RIGHT))
		world._handle_world_input(mouse_event(MOUSE_BUTTON_RIGHT, false))
		check(world._pending_actions.is_empty(), "GUI focus blocks command confirmation")
		field.release_focus()
		field.queue_free()
		world._handle_world_input(key_event(KEY_ESCAPE))
	world._handle_world_input(key_event(KEY_A))
	check(not world._attack_move_armed, "old A shortcut inactive")
	for code: Key in [KEY_Q, KEY_F, KEY_R]:
		world._handle_world_input(key_event(KEY_R))
		world._handle_world_input(key_event(code))
		check(world._reverse_move_armed if code == KEY_R else not world._reverse_move_armed, "new command mode replaces reverse mode")
		world._handle_world_input(key_event(KEY_ESCAPE))
	world._pending_actions.clear()
	world._on_unit_spawn_received(101, 1, Vector3(0,0.5,100))
	world._dead_units[102] = true
	world._reset_replicated_units()
	check(world._visual_units.is_empty() and world._dead_units.is_empty(), "new connection discards previous visuals and tombstones")
	world._on_unit_spawn_received(101, 1, Vector3(3,0.5,100))
	world._on_unit_spawn_received(102, 1, Vector3(6,0.5,100))
	await process_frame
	check(world._visual_units.has(101) and world._visual_units.has(102) and world._visual_units[101].position.x == 3, "old deferred removal cannot erase fresh snapshot visuals")
	world.queue_free()
	await process_frame
	print("Command input isolated checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
