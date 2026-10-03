extends Node3D

const UNIT_SCENE: PackedScene = preload("res://scenes/units/unit.tscn")
const MOVEMENT_CONFIG: MovementConfig = preload("res://data/prototype_movement.tres")
const UNIT_PICK_MASK: int = 2
const PICK_DISTANCE: float = 1000.0
const DRAG_THRESHOLD: float = 8.0
const SELECTION_RECTANGLE: Script = preload("res://scripts/core/selection_rectangle.gd")
const MOVEMENT_PATH_VISUAL: Script = preload("res://scripts/core/movement_path_visual.gd")

var _visual_units: Dictionary[int, Node3D] = {}
var _selected_units: Dictionary[int, Node3D] = {}
var _move_targets: Dictionary[int, Vector3] = {}
var _movement_paths: Dictionary[int, MeshInstance3D] = {}
var _route_points: Dictionary[int, PackedVector3Array] = {}
var _route_progress: Dictionary[int, int] = {}
var _pending_actions: Array[Dictionary] = []
var _left_pressed: bool = false
var _box_dragging: bool = false
var _drag_start: Vector2
var _selection_rectangle: Control

@onready var _units: Node3D = $Units


func _ready() -> void:
	NetworkManager.unit_spawn_received.connect(_on_unit_spawn_received)
	NetworkManager.unit_positions_received.connect(_on_unit_positions_received)
	NetworkManager.unit_move_targets_received.connect(_on_unit_move_targets_received)
	NetworkManager.unit_move_paths_received.connect(_on_unit_move_paths_received)
	multiplayer.server_disconnected.connect(_clear_selection)
	multiplayer.server_disconnected.connect(_clear_movement_paths)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_selection_rectangle = SELECTION_RECTANGLE.new()
	overlay.add_child(_selection_rectangle)
	get_window().focus_exited.connect(_cancel_drag)
	set_physics_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if event is InputEventMouseMotion and _left_pressed:
		_update_drag(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_pressed = true
				_box_dragging = false
				_drag_start = event.position
			elif _left_pressed:
				_update_drag(event.position)
				if _box_dragging:
					_queue_action({"type": "box", "rectangle": Rect2(_drag_start, event.position - _drag_start).abs()})
				else:
					_queue_action({"type": "click", "position": event.position})
				_cancel_drag()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not _left_pressed:
			_queue_action({"type": "move", "position": event.position})
			get_viewport().set_input_as_handled()


func _update_drag(position: Vector2) -> void:
	if position.distance_to(_drag_start) > DRAG_THRESHOLD:
		_box_dragging = true
	if _box_dragging:
		_selection_rectangle.show_rectangle(Rect2(_drag_start, position - _drag_start).abs())


func _cancel_drag() -> void:
	_left_pressed = false
	_box_dragging = false
	_selection_rectangle.hide()


func _queue_action(action: Dictionary) -> void:
	_pending_actions.append(action)
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	# Query physics in its tick, and do no per-frame picking when idle.
	for action: Dictionary in _pending_actions:
		match action["type"]:
			"click":
				_select_unit(_pick_unit(action["position"]))
			"box":
				_select_box(action["rectangle"])
			"move":
				_request_move_at(action["position"])
	_pending_actions.clear()
	set_physics_process(false)


func _pick_unit(screen_position: Vector2) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_position)
	var end := origin + camera.project_ray_normal(screen_position) * PICK_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(origin, end, UNIT_PICK_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var unit := (hit["collider"] as Node).get_parent() as Node3D
	if unit == null or not _visual_units.values().has(unit) or unit.is_queued_for_deletion():
		return null
	return unit


func _select_unit(unit: Node3D) -> void:
	# Ownership is read from the server-provided visual metadata, never changed.
	if unit != null and unit.owner_peer_id != multiplayer.get_unique_id():
		return
	var selection: Dictionary[int, Node3D] = {}
	if unit != null:
		selection[unit.unit_id] = unit
	_replace_selection(selection)


func _select_box(rectangle: Rect2) -> void:
	var selection: Dictionary[int, Node3D] = {}
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		for unit_id: int in _visual_units:
			var unit := _visual_units[unit_id]
			if not is_instance_valid(unit) or unit.is_queued_for_deletion():
				continue
			if unit.owner_peer_id != multiplayer.get_unique_id():
				continue
			if camera.is_position_behind(unit.global_position):
				continue
			if rectangle.has_point(camera.unproject_position(unit.global_position)):
				selection[unit_id] = unit
	_replace_selection(selection)


func _replace_selection(selection: Dictionary[int, Node3D]) -> void:
	for unit: Node3D in _selected_units.values():
		if is_instance_valid(unit):
			unit.set_selected(false)
	_selected_units = selection
	for unit: Node3D in _selected_units.values():
		unit.set_selected(true)


func _prune_selection() -> void:
	for unit_id: int in _selected_units.keys():
		var unit := _selected_units[unit_id]
		if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
			_selected_units.erase(unit_id)


func _clear_selection() -> void:
	_pending_actions.clear()
	_cancel_drag()
	set_physics_process(false)
	_select_unit(null)


func _on_unit_spawn_received(unit_id: int, owner_peer_id: int, position: Vector3) -> void:
	if _visual_units.has(unit_id):
		return

	var unit := UNIT_SCENE.instantiate() as Node3D
	unit.name = "Unit_%d" % unit_id
	unit.setup(unit_id, owner_peer_id)
	unit.position = position
	_units.add_child(unit)
	_visual_units[unit_id] = unit
	unit.tree_exiting.connect(_on_visual_unit_removed.bind(unit_id))


func _on_visual_unit_removed(unit_id: int) -> void:
	_clear_unit_path(unit_id)
	if _selected_units.has(unit_id) and is_instance_valid(_selected_units[unit_id]):
		_selected_units[unit_id].set_selected(false)
	_selected_units.erase(unit_id)
	_visual_units.erase(unit_id)


func _request_move_at(screen_position: Vector2) -> void:
	_prune_selection()
	if _selected_units.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var ground := Plane(Vector3.UP, MOVEMENT_CONFIG.ground_height)
	var hit: Variant = ground.intersects_ray(
		camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position)
	)
	if hit is Vector3:
		var unit_ids: Array[int] = []
		for unit_id: int in _selected_units:
			if _selected_units[unit_id].owner_peer_id == multiplayer.get_unique_id():
				unit_ids.append(unit_id)
		if not unit_ids.is_empty():
			NetworkManager.request_moves(unit_ids, hit)


func _on_unit_positions_received(unit_ids: Array[int], positions: Array[Vector3]) -> void:
	for index: int in unit_ids.size():
		if _visual_units.has(unit_ids[index]):
			_visual_units[unit_ids[index]].position = positions[index]
			_update_unit_path(unit_ids[index])


func _on_unit_move_targets_received(unit_ids: Array[int], positions: Array[Vector3]) -> void:
	for index: int in unit_ids.size():
		var unit_id := unit_ids[index]
		if not _visual_units.has(unit_id):
			continue
		if _visual_units[unit_id].owner_peer_id != multiplayer.get_unique_id():
			continue
		_clear_unit_path(unit_id)
		_move_targets[unit_id] = positions[index]


func _on_unit_move_paths_received(unit_ids: Array[int], paths: Array[PackedVector3Array]) -> void:
	for index: int in unit_ids.size():
		var unit_id := unit_ids[index]
		if not _visual_units.has(unit_id) or not _move_targets.has(unit_id):
			continue
		if _visual_units[unit_id].owner_peer_id != multiplayer.get_unique_id() or paths[index].size() < 2:
			continue
		_route_points[unit_id] = paths[index]
		_route_progress[unit_id] = 0
		_update_unit_path(unit_id)


func _update_unit_path(unit_id: int) -> void:
	if not _move_targets.has(unit_id):
		return
	var unit := _visual_units[unit_id]
	var target := _move_targets[unit_id]
	if unit.position.distance_to(target) <= 0.001:
		_clear_unit_path(unit_id)
		return
	if not _route_points.has(unit_id):
		return
	if not _movement_paths.has(unit_id):
		var path := MOVEMENT_PATH_VISUAL.new() as MeshInstance3D
		path.name = "MovementPath_%d" % unit_id
		add_child(path)
		_movement_paths[unit_id] = path
	# The path is presentation only, slightly above the prototype ground plane.
	var remaining := _remaining_visual_route(unit_id, unit.position)
	for index: int in remaining.size():
		var point := remaining[index]
		point.y = MOVEMENT_CONFIG.ground_height + 0.04
		remaining[index] = _units.transform * point
	_movement_paths[unit_id].update_route(remaining)


func _remaining_visual_route(unit_id: int, position: Vector3) -> PackedVector3Array:
	var route := _route_points[unit_id]
	var best := _route_progress[unit_id]
	var distance := INF
	# Find visual progress using replicated positions; this never moves a unit.
	for index: int in range(best, route.size() - 1):
		var closest := Geometry3D.get_closest_point_to_segment(position, route[index], route[index + 1])
		var candidate_distance := position.distance_squared_to(closest)
		if candidate_distance <= distance:
			distance = candidate_distance
			best = index
	_route_progress[unit_id] = best
	var points := PackedVector3Array([position])
	var segment_start := Geometry3D.get_closest_point_to_segment(position, route[best], route[best + 1])
	if segment_start.is_equal_approx(route[best]) and not position.is_equal_approx(route[best]):
		points.append(route[best])
	points.append_array(route.slice(best + 1))
	return points


func _clear_unit_path(unit_id: int) -> void:
	if _movement_paths.has(unit_id):
		_movement_paths[unit_id].hide()
		_movement_paths[unit_id].queue_free()
		_movement_paths.erase(unit_id)
	_move_targets.erase(unit_id)
	_route_points.erase(unit_id)
	_route_progress.erase(unit_id)


func _clear_movement_paths() -> void:
	for unit_id: int in _move_targets.keys():
		_clear_unit_path(unit_id)
