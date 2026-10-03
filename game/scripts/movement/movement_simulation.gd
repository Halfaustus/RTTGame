class_name MovementSimulation
extends RefCounted

const MAP_DEFINITION: PrototypeMapDefinition = preload("res://data/prototype_map.tres")

var _config: MovementConfig
var _units: Dictionary[int, UnitState] = {}
var _targets: Dictionary[int, Vector3] = {}
var _paths: Dictionary[int, PackedVector3Array] = {}
var _path_indices: Dictionary[int, int] = {}
var _navigation := StaticNavigationGrid.new()


func _init(config: MovementConfig) -> void:
	_config = config


func add_unit(state: UnitState) -> void:
	_units[state.unit_id] = state


func initialize_navigation(definition: PrototypeMapDefinition = MAP_DEFINITION) -> bool:
	return _navigation.initialize(_config, definition)


func is_navigation_ready() -> bool:
	return _navigation.is_ready()


func resolve_spawn_position(position: Vector3) -> Variant:
	return _navigation.nearest_walkable_position(position)


func _assign_path(unit_id: int, path: PackedVector3Array) -> void:
	_paths[unit_id] = path
	_path_indices[unit_id] = 1
	_targets[unit_id] = path[path.size() - 1]


func request_move(unit_id: int, sender_peer_id: int, target: Vector3) -> String:
	if not _units.has(unit_id):
		return "unknown unit"
	if _units[unit_id].owner_peer_id != sender_peer_id:
		return "not owner"
	var rejection := _validate_target(target)
	if not rejection.is_empty():
		return rejection
	if not is_navigation_ready():
		return "navigation not ready"
	var destination := Vector3(target.x, _units[unit_id].position.y, target.z)
	var path := _navigation.find_path(_units[unit_id].position, destination)
	if path.is_empty():
		return "no reachable destination"
	_assign_path(unit_id, path)
	return ""


func _validate_target(target: Vector3) -> String:
	if not target.is_finite():
		return "non-finite target"
	if not is_equal_approx(target.y, _config.ground_height):
		return "target is not on the ground"
	if target.x < _config.minimum_xz.x or target.x > _config.maximum_xz.x \
		or target.z < _config.minimum_xz.y or target.z > _config.maximum_xz.y:
		return "target outside prototype bounds"
	return ""


func request_group_move(unit_ids: Array[int], sender_peer_id: int, target: Vector3) -> Dictionary:
	var rejection := _validate_target(target)
	if not rejection.is_empty():
		return {"rejection": rejection, "unit_ids": []}
	var eligible: Dictionary[int, bool] = {}
	for unit_id: int in unit_ids:
		if _units.has(unit_id) and _units[unit_id].owner_peer_id == sender_peer_id:
			eligible[unit_id] = true
	var ids: Array[int] = []
	ids.assign(eligible.keys())
	ids.sort()
	if ids.is_empty():
		return {"rejection": "no owned units", "unit_ids": ids}
	var spacing := _config.unit_width + _config.destination_gap
	var half_width := (ids.size() - 1) * spacing * 0.5
	var clearance := _config.unit_width * 0.5 + _config.obstacle_margin
	if half_width * 2.0 > _config.maximum_xz.x - _config.minimum_xz.x - clearance * 2.0:
		return {"rejection": "line does not fit prototype bounds", "unit_ids": []}
	# All counts use a single world-X row. Shift it inside the map without stacking slots.
	var center_x := clampf(target.x, _config.minimum_xz.x + clearance + half_width, _config.maximum_xz.x - clearance - half_width)
	var center_z := clampf(target.z, _config.minimum_xz.y + clearance, _config.maximum_xz.y - clearance)
	if not is_navigation_ready():
		return {"rejection": "navigation not ready", "unit_ids": []}
	var accepted: Array[int] = []
	var failed: Array[int] = []
	var reserved: Array[Vector3] = []
	for index: int in ids.size():
		var unit_id := ids[index]
		var destination := Vector3(
			center_x - half_width + index * spacing,
			_units[unit_id].position.y,
			center_z
		)
		var path := _navigation.find_path(_units[unit_id].position, destination, reserved, spacing)
		if path.is_empty():
			failed.append(unit_id)
			continue
		_assign_path(unit_id, path)
		accepted.append(unit_id)
		reserved.append(_targets[unit_id])
	return {"rejection": "no reachable destinations" if accepted.is_empty() else "", "unit_ids": accepted, "failed_ids": failed}


func move_targets(unit_ids: Array[int]) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for unit_id: int in unit_ids:
		positions.append(_targets[unit_id])
	return positions


func move_paths(unit_ids: Array[int]) -> Array[PackedVector3Array]:
	var paths: Array[PackedVector3Array] = []
	for unit_id: int in unit_ids:
		var remaining := PackedVector3Array([_units[unit_id].position])
		remaining.append_array(_paths[unit_id].slice(_path_indices[unit_id]))
		paths.append(remaining)
	return paths


func advance(delta: float) -> Dictionary[int, Vector3]:
	var changed: Dictionary[int, Vector3] = {}
	for unit_id: int in _targets.keys():
		var state := _units[unit_id]
		var distance_left := _config.speed * delta
		var path := _paths[unit_id]
		var index := _path_indices[unit_id]
		# Spend the tick's travel distance along each segment, never across corners.
		while index < path.size() and distance_left > 0.0:
			var segment_distance := state.position.distance_to(path[index])
			if segment_distance <= distance_left:
				state.position = path[index]
				distance_left -= segment_distance
				index += 1
			else:
				state.position = state.position.move_toward(path[index], distance_left)
				distance_left = 0.0
		_path_indices[unit_id] = index
		changed[unit_id] = state.position
		if index >= path.size():
			_clear_move(unit_id)
	return changed


func _clear_move(unit_id: int) -> void:
	_targets.erase(unit_id)
	_paths.erase(unit_id)
	_path_indices.erase(unit_id)


func has_active_moves() -> bool:
	return not _targets.is_empty()


func stop_owner(owner_peer_id: int) -> void:
	for unit_id: int in _targets.keys():
		if _units[unit_id].owner_peer_id == owner_peer_id:
			_clear_move(unit_id)
