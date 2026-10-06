extends SceneTree

var failures := 0
var gui_events := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL 0.2H: " + label)

func key(code: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	return event

func button(code: MouseButton, pressed: bool = true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = code
	event.position = Vector2(400, 300)
	event.pressed = pressed
	return event

func _run() -> void:
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	var camera = world.get_node("Units/Camera3D")
	camera.set_process(false)
	camera.config = camera.config.duplicate()
	var center: Vector3 = camera._center
	var distance: float = camera._distance
	var pitch: float = camera._pitch
	var projection: int = camera.projection
	var fov: float = camera.fov
	check(camera.global_position.distance_to(Vector3(0, 10, 110)) < 0.0001 and center.distance_to(Vector3(0, 0, 100)) < 0.0001, "initial camera view retained")
	var server := root.get_node("NetworkManager")
	var before: Array[Dictionary] = server.live_snapshots()
	for test_pitch: float in [deg_to_rad(20), deg_to_rad(80)]:
		camera._pitch = test_pitch
		camera._yaw = PI / 2
		camera._center = center
		camera._handle_camera_input(key(KEY_W))
		camera._advance_pan(1)
		var full_step: Vector3 = camera._center
		check(full_step.distance_to(center - Vector3(camera.config.movement_speed, 0, 0)) < 0.0001, "pan follows horizontal yaw independent of pitch")
		camera._center = center
		for frame: int in 60:
			camera._advance_pan(1.0 / 60)
		check(camera._center.distance_to(full_step) < 0.001, "pan independent of frame subdivision")
		camera._input(key(KEY_W, false))
		camera._handle_camera_input(key(KEY_D))
		camera._handle_camera_input(key(KEY_W))
		camera._center = center
		camera._advance_pan(1)
		check(absf(camera._center.distance_to(center) - camera.config.movement_speed) < 0.0001 and camera._center.y == center.y, "normalized diagonal ground speed")
		camera.cancel_controls()
	camera._center = center
	camera._yaw = 0
	camera._pitch = pitch
	camera._distance = distance
	camera._rotate_pixels(Vector2(70, 30))
	var whole_yaw: float = camera._yaw
	var whole_pitch: float = camera._pitch
	camera._yaw = 0
	camera._pitch = pitch
	for sample: int in 10:
		camera._rotate_pixels(Vector2(7, 3))
	check(absf(camera._yaw - whole_yaw) < 0.0001 and absf(camera._pitch - whole_pitch) < 0.0001, "pixel rotation independent of event subdivision")
	camera._rotate_pixels(Vector2(0, 10000))
	check(is_equal_approx(camera._pitch, deg_to_rad(80)), "upper pitch limit")
	camera._rotate_pixels(Vector2(0, -10000))
	check(is_equal_approx(camera._pitch, deg_to_rad(20)), "lower pitch limit")
	check((-camera.global_basis.z).dot((camera._center - camera.global_position).normalized()) > 0.9999, "orbit looks at ground center without roll")
	camera._zoom(-1000)
	check(camera._distance == camera.config.minimum_distance, "zoom in clamps")
	camera._zoom(1000)
	check(camera._distance == camera.config.maximum_distance, "zoom out clamps")
	camera._distance = distance
	camera._handle_camera_input(button(MOUSE_BUTTON_WHEEL_UP))
	check(is_equal_approx(camera._distance, distance - camera.config.zoom_step), "wheel up moves closer")
	camera._handle_camera_input(button(MOUSE_BUTTON_WHEEL_DOWN))
	check(is_equal_approx(camera._distance, distance), "wheel down moves farther")
	check(camera.projection == projection and camera.fov == fov, "projection and FOV retained")
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var previous_mode := Input.mouse_mode
	world._handle_world_input(button(MOUSE_BUTTON_RIGHT))
	camera._handle_camera_input(button(MOUSE_BUTTON_MIDDLE))
	check(camera.is_rotating() and not world._right_pressed, "rotation cancels old command drag")
	for event: InputEvent in [button(MOUSE_BUTTON_LEFT), button(MOUSE_BUTTON_LEFT, false), button(MOUSE_BUTTON_RIGHT), button(MOUSE_BUTTON_RIGHT, false), key(KEY_E)]:
		world._handle_world_input(event)
	check(world._pending_actions.is_empty(), "selection and command input suppressed during rotation")
	camera._handle_camera_input(key(KEY_ALT))
	camera._input(button(MOUSE_BUTTON_MIDDLE, false))
	check(camera.is_rotating(), "Alt keeps rotation active after middle release")
	camera._input(key(KEY_ALT, false))
	check(not camera.is_rotating() and Input.mouse_mode == previous_mode, "release restores previous mouse state")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera._handle_camera_input(key(KEY_ALT))
	camera._handle_camera_input(key(KEY_W))
	root.focus_exited.emit()
	check(not camera.is_rotating() and camera._movement_keys.is_empty() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "focus loss clears camera holds and restores cursor")
	var field := LineEdit.new()
	field.position = Vector2(10, 10)
	field.size = Vector2(180, 40)
	world._selection_rectangle.get_parent().add_child(field)
	field.grab_focus()
	check(not camera._handle_camera_input(key(KEY_W)) and not camera._handle_camera_input(button(MOUSE_BUTTON_MIDDLE)), "GUI focus blocks camera initiation")
	camera._movement_keys[KEY_S] = true
	camera._input(key(KEY_S, false))
	check(camera._movement_keys.is_empty(), "GUI-consumed release cannot leave a movement key held")
	field.release_focus()
	field.queue_free()
	await process_frame
	world._pending_actions.clear()
	world._handle_world_input(key(KEY_S))
	world._handle_world_input(key(KEY_A))
	check(world._pending_actions.is_empty() and not world._attack_move_armed, "S and A no longer issue unit commands")
	world._handle_world_input(key(KEY_Q))
	check(world._attack_move_armed, "Q retains attack target semantics")
	world._handle_world_input(key(KEY_ESCAPE))
	check(world._attack_move_armed and world._pending_actions.is_empty(), "DB33 Esc preserves Q interaction")
	world._handle_world_input(key(KEY_E))
	check(not world._attack_move_armed and world._pending_actions.is_empty(), "first E exits interaction without stop")
	world._handle_world_input(key(KEY_E))
	check(world._pending_actions.size() == 1 and world._pending_actions[0].type == "stop", "noninteractive E queues stop")
	world._pending_actions.clear()
	# Anchor a formation center at press time even if the view pans before release.
	camera._center = center
	camera._pitch = pitch
	camera._yaw = 0
	camera._distance = distance
	camera._apply_view()
	var formation_press := button(MOUSE_BUTTON_RIGHT)
	world._handle_world_input(formation_press)
	var pressed_ground: Vector3 = world._right_ground
	camera._movement_keys[KEY_D] = true
	camera._advance_pan(1)
	camera.cancel_controls()
	var formation_motion := InputEventMouseMotion.new()
	formation_motion.position = formation_press.position + Vector2(40, 0)
	world._handle_world_input(formation_motion)
	formation_press.position = formation_motion.position
	formation_press.pressed = false
	world._handle_world_input(formation_press)
	check(world._pending_actions.size() == 1 and world._pending_actions[0].ground == pressed_ground, "formation center anchored before camera movement")
	check(world._pending_actions[0].tip == world._ground_at(formation_motion.position), "formation release direction uses current view")
	world._pending_actions.clear()
	check(server.live_snapshots() == before and not server._movement.has_active_moves(), "camera never changes server simulation")
	# Exercise the real Viewport GUI/unhandled routing without a client connection.
	var panel := Control.new()
	panel.position = Vector2(10, 10)
	panel.size = Vector2(180, 100)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(_event: InputEvent):
		gui_events += 1
		panel.accept_event())
	world._selection_rectangle.get_parent().add_child(panel)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(30, 30)
	root.push_input(motion, true)
	var middle := button(MOUSE_BUTTON_MIDDLE)
	middle.position = Vector2(30, 30)
	root.push_input(middle, true)
	check(gui_events > 0 and not camera.is_rotating(), "GUI mouse routing does not start camera rotation")
	middle.pressed = false
	root.push_input(middle, true)
	panel.queue_free()
	await process_frame
	motion.position = Vector2(400, 300)
	root.push_input(motion, true)
	middle.position = motion.position
	middle.pressed = true
	root.push_input(middle, true)
	check(camera.is_rotating(), "world middle press reaches camera unhandled input")
	motion.screen_relative = Vector2(25, 10)
	var previous_yaw: float = camera._yaw
	root.push_input(motion, true)
	check(camera._yaw != previous_yaw, "mouse motion rotates through real input routing")
	middle.pressed = false
	root.push_input(middle, true)
	check(not camera.is_rotating(), "middle release cleans up via real input routing")
	world.queue_free()
	await process_frame
	print("Prototype 0.2H isolated camera/input checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
