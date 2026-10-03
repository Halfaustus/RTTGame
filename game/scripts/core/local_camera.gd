extends Camera3D

signal rotation_started

@export var config: CameraConfig = preload("res://data/prototype_camera.tres")

var _center: Vector3
var _yaw: float
var _pitch: float
var _distance: float
var _movement_keys: Dictionary[int, bool] = {}
var _middle_held := false
var _alt_held := false
var _rotating := false
var _saved_mouse_mode: Input.MouseMode
var _saved_mouse_position: Vector2
var _enabled := true


func _ready() -> void:
	# No camera or input is needed by the dedicated-server entry.
	_enabled = "--server" not in OS.get_cmdline_user_args() and "--test-role=server" not in OS.get_cmdline_user_args()
	var direction := -global_basis.z
	var hit: Variant = Plane(Vector3.UP, config.ground_height).intersects_ray(global_position, direction)
	_center = hit if hit is Vector3 else global_position + direction * config.minimum_distance
	_center.y = config.ground_height
	_distance = clampf(global_position.distance_to(_center), config.minimum_distance, config.maximum_distance)
	_yaw = global_rotation.y
	_pitch = clampf(-global_rotation.x, deg_to_rad(config.minimum_pitch_degrees), deg_to_rad(config.maximum_pitch_degrees))
	_apply_view()
	get_window().focus_exited.connect(cancel_controls)
	set_process(_enabled)
	set_process_input(_enabled)
	set_process_unhandled_input(_enabled)


func _exit_tree() -> void:
	cancel_controls()


func is_rotating() -> bool:
	return _rotating


func _gui_blocked() -> bool:
	return get_viewport().gui_get_focus_owner() != null or get_viewport().gui_get_hovered_control() != null


func _input(event: InputEvent) -> void:
	# Releases must clean up even when a GUI consumes the event later.
	if event is InputEventKey and not event.pressed:
		_movement_keys.erase(_key_code(event))
		if event.keycode == KEY_ALT:
			_alt_held = false
			_end_rotation_if_released()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		_middle_held = false
		_end_rotation_if_released()


func _unhandled_input(event: InputEvent) -> void:
	_handle_camera_input(event)


func _handle_camera_input(event: InputEvent) -> bool:
	if not _enabled:
		return false
	if _gui_blocked():
		cancel_controls()
		return false
	var handled := false
	if event is InputEventKey:
		var code := _key_code(event)
		if event.keycode == KEY_ALT:
			if not event.echo:
				_alt_held = event.pressed
				if _alt_held:
					_begin_rotation()
				else:
					_end_rotation_if_released()
			handled = true
		elif code in [KEY_W, KEY_A, KEY_S, KEY_D]:
			if not event.pressed:
				_movement_keys.erase(code)
			elif not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and not event.echo:
				_movement_keys[code] = true
			handled = true
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_held = event.pressed
			if _middle_held:
				_begin_rotation()
			else:
				_end_rotation_if_released()
			handled = true
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if event.pressed:
				_zoom((-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0) * event.factor)
			handled = true
	elif event is InputEventMouseMotion and _rotating:
		_rotate_pixels(event.screen_relative)
		handled = true
	if _rotating:
		# Rotation owns mouse/command input until both rotation activators release.
		handled = true
	if handled:
		get_viewport().set_input_as_handled()
	return handled


func _key_code(event: InputEventKey) -> int:
	return event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode


func _begin_rotation() -> void:
	if _rotating:
		return
	_rotating = true
	_saved_mouse_mode = Input.mouse_mode
	_saved_mouse_position = get_viewport().get_mouse_position()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	rotation_started.emit()


func _end_rotation_if_released() -> void:
	if not _middle_held and not _alt_held:
		_end_rotation()


func _end_rotation() -> void:
	if not _rotating:
		return
	_rotating = false
	Input.mouse_mode = _saved_mouse_mode
	if _saved_mouse_mode in [Input.MOUSE_MODE_VISIBLE, Input.MOUSE_MODE_CONFINED] and DisplayServer.get_name() != "headless":
		Input.warp_mouse(_saved_mouse_position)


func cancel_controls() -> void:
	_movement_keys.clear()
	_middle_held = false
	_alt_held = false
	_end_rotation()


func _process(delta: float) -> void:
	if _gui_blocked():
		cancel_controls()
		return
	_advance_pan(delta)


func _advance_pan(delta: float) -> void:
	var axis := Vector2(float(_movement_keys.has(KEY_D)) - float(_movement_keys.has(KEY_A)), float(_movement_keys.has(KEY_S)) - float(_movement_keys.has(KEY_W)))
	if axis.is_zero_approx():
		return
	axis = axis.normalized()
	# Use yaw alone: neither pitch nor zoom changes ground movement speed.
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	var backward := Vector3(sin(_yaw), 0, cos(_yaw))
	_center += (right * axis.x + backward * axis.y) * config.movement_speed * delta
	_apply_view()


func _rotate_pixels(pixels: Vector2) -> void:
	_yaw = wrapf(_yaw - deg_to_rad(pixels.x * config.rotation_degrees_per_pixel), -PI, PI)
	_pitch = clampf(_pitch + deg_to_rad(pixels.y * config.rotation_degrees_per_pixel), deg_to_rad(config.minimum_pitch_degrees), deg_to_rad(config.maximum_pitch_degrees))
	_apply_view()


func _zoom(steps: float) -> void:
	_distance = clampf(_distance + steps * config.zoom_step, config.minimum_distance, config.maximum_distance)
	_apply_view()


func _apply_view() -> void:
	global_rotation = Vector3(-_pitch, _yaw, 0)
	global_position = _center + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
