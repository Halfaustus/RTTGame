class_name MovementSimulation
extends RefCounted

enum MoveMode { BASIC, FAST, ATTACK, REVERSE }

const MAP_DEFINITION: PrototypeMapDefinition = preload("res://data/prototype_map.tres")

var _config: MovementConfig
var _units: Dictionary[int, UnitState] = {}
var _targets: Dictionary[int, Vector3] = {}
var _paths: Dictionary[int, PackedVector3Array] = {}
var _path_indices: Dictionary[int, int] = {}
var _attack_moves: Dictionary[int, bool] = {}
var _engaging: Dictionary[int, bool] = {}
var _reverse_moves: Dictionary[int, bool] = {}
var _final_yaws: Dictionary[int, float] = {}
var _move_modes: Dictionary[int, int] = {}
var _navigation := StaticNavigationGrid.new()
var _deployment_navigation: Dictionary = {}
var _blocked_seconds: Dictionary[int, float] = {}
# Temporary retry cadence, not a balance rule.
var dynamic_retry_seconds := 1.0
var _map_definition: PrototypeMapDefinition
var profile: Dictionary = {}
var attack_facing_requests: Dictionary = {}


func navigation_for(state: UnitState, dynamic: bool = true, minimum_width: float = 0.0) -> StaticNavigationGrid:
	var width := maxf(state.movement_radius() * 2.0, minimum_width)
	var navigation := _navigation
	if not is_equal_approx(width, _config.unit_width):
		if not _deployment_navigation.has(width):
			var sized_config: MovementConfig = _config.duplicate(true)
			sized_config.unit_width = width
			var sized := StaticNavigationGrid.new()
			sized.initialize(sized_config, _map_definition)
			_deployment_navigation[width] = sized
		navigation = _deployment_navigation[width]
	var centers: Array[Vector3] = []
	var radii: Array[float] = []
	if dynamic and state.blocks_movement():
		for other: UnitState in _units.values():
			if other.unit_id != state.unit_id and other.blocks_movement():
				centers.append(other.position)
				radii.append(state.movement_radius() + other.movement_radius())
	navigation.profile = profile
	navigation.configure_dynamic(centers,radii)
	return navigation


func translation_clear(state: UnitState, start: Vector3, end: Vector3) -> bool:
	if not profile.is_empty(): profile["swept_checks"] = profile.get("swept_checks",0) + 1
	if not state.blocks_movement(): return true
	var a := Vector2(start.x,start.z)
	var b := Vector2(end.x,end.z)
	for other: UnitState in _units.values():
		if not profile.is_empty(): profile["swept_unit_scans"] = profile.get("swept_unit_scans",0) + 1
		if other.unit_id == state.unit_id or not other.blocks_movement(): continue
		var center := Vector2(other.position.x,other.position.z)
		var nearest := Geometry2D.get_closest_point_to_segment(center,a,b)
		if nearest.distance_to(center) < state.movement_radius() + other.movement_radius() - 0.00001: return false
	return true


func _init(config: MovementConfig) -> void:
	_config = config


func add_unit(state: UnitState) -> void:
	state.initialize_spatial()
	_units[state.unit_id] = state


func initialize_navigation(definition: PrototypeMapDefinition = MAP_DEFINITION) -> bool:
	_map_definition = definition
	_deployment_navigation.clear()
	return _navigation.initialize(_config, definition)


func is_navigation_ready() -> bool:
	return _navigation.is_ready()


func resolve_spawn_position(position: Vector3, state: UnitState = null) -> Variant:
	if state != null: return navigation_for(state).nearest_walkable_position(position)
	_navigation.configure_dynamic([],[])
	return _navigation.nearest_walkable_position(position)


func deploy_move(state: UnitState, destination: Vector3, mode: int, width: float, map: PrototypeMapDefinition = MAP_DEFINITION) -> Dictionary:
	if not _valid_speeds(state): return {"notice":"invalid unit spatial configuration", "target":state.position}
	# The old deployment width remains a conservative lower bound for this entry.
	var navigation := navigation_for(state,true,width)
	var target := Vector3(destination.x, state.position.y, destination.z)
	var path := navigation.deployment_path(state.position, target, mode == MoveMode.FAST, state)
	if path.size() < 2 or path[0].is_equal_approx(path[path.size() - 1]):
		return {"notice":"no usable movement path; remains at spawn", "target":state.position}
	_assign_path(state.unit_id, path, mode)
	_final_yaws[state.unit_id] = _command_yaw(state, path[1] - state.position, mode, Vector3.ZERO)
	return {"notice":"destination adjusted to nearest reachable position" if not path[path.size() - 1].is_equal_approx(target) else "", "target":path[path.size() - 1]}


func _assign_path(unit_id: int, path: PackedVector3Array, mode: int = MoveMode.BASIC) -> void:
	_move_modes[unit_id] = mode
	_attack_moves.erase(unit_id)
	_engaging.erase(unit_id)
	_reverse_moves.erase(unit_id)
	if mode == MoveMode.REVERSE:
		_reverse_moves[unit_id] = true
	if mode == MoveMode.ATTACK:
		_attack_moves[unit_id] = true
	_paths[unit_id] = path
	_path_indices[unit_id] = 1
	_targets[unit_id] = path[path.size() - 1]


func request_move(unit_id: int, sender_peer_id: int, target: Vector3, mode: int = MoveMode.BASIC, facing: Vector3 = Vector3.ZERO) -> String:
	if mode not in [MoveMode.BASIC, MoveMode.FAST, MoveMode.ATTACK, MoveMode.REVERSE]:
		return "invalid movement mode"
	if not _units.has(unit_id):
		return "unknown unit"
	if _units[unit_id].owner_peer_id != sender_peer_id:
		return "not owner"
	if _units[unit_id].health <= 0.0 or (mode == MoveMode.ATTACK and not _units[unit_id].is_armed()):
		return "unit cannot execute command"
	if mode == MoveMode.REVERSE and not _can_reverse(_units[unit_id]):
		return "unit cannot reverse"
	var rejection := _validate_target(target)
	if not facing.is_finite() or not is_zero_approx(facing.y):
		rejection = "invalid facing"
	if not rejection.is_empty():
		return rejection
	if not is_navigation_ready():
		return "navigation not ready"
	var destination := Vector3(target.x, _units[unit_id].position.y, target.z)
	var unit := _units[unit_id]
	if not _valid_speeds(unit):
		return "invalid unit speeds"
	var path := navigation_for(unit).find_path(unit.position, destination, [], 0.0, mode == MoveMode.FAST, unit)
	if path.is_empty():
		return "no reachable destination"
	_assign_path(unit_id, path, mode)
	_final_yaws[unit_id] = _command_yaw(unit, target - unit.position, mode, facing)
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


func request_group_move(unit_ids: Array[int], sender_peer_id: int, target: Vector3, mode: int = MoveMode.BASIC, facing: Vector3 = Vector3.ZERO) -> Dictionary:
	if mode not in [MoveMode.BASIC, MoveMode.FAST, MoveMode.ATTACK, MoveMode.REVERSE]:
		return {"rejection": "invalid movement mode", "unit_ids": []}
	var rejection := _validate_target(target)
	if not facing.is_finite() or not is_zero_approx(facing.y):
		rejection = "invalid facing"
	if not rejection.is_empty():
		return {"rejection": rejection, "unit_ids": []}
	var eligible: Dictionary[int, bool] = {}
	for unit_id: int in unit_ids:
		if _units.has(unit_id) and _units[unit_id].owner_peer_id == sender_peer_id \
			and _units[unit_id].health > 0.0 \
			and (mode != MoveMode.ATTACK or _units[unit_id].is_armed()) \
			and (mode != MoveMode.REVERSE or _can_reverse(_units[unit_id])):
			eligible[unit_id] = true
	var ids: Array[int] = []
	ids.assign(eligible.keys())
	ids.sort()
	if ids.is_empty():
		return {"rejection": "no owned units", "unit_ids": ids}
	var center := Vector3.ZERO
	var selected: Dictionary[int, bool] = {}
	for id: int in unit_ids:
		if _units.has(id) and _units[id].owner_peer_id == sender_peer_id and _units[id].health > 0:
			selected[id] = true
	for id: int in selected:
		center += _units[id].position
	center /= selected.size()
	var final_yaw := _command_yaw(_units[ids[0]], target - center, mode, facing)
	var side := Vector3(cos(final_yaw), 0, -sin(final_yaw))
	var largest_width := _config.unit_width
	for id: int in ids:
		largest_width = maxf(largest_width,_units[id].movement_radius() * 2.0)
	var spacing := largest_width + _config.destination_gap
	var half_width := (ids.size() - 1) * spacing * 0.5
	var clearance := largest_width * 0.5 + _config.obstacle_margin
	var extent_x := absf(side.x) * half_width + clearance
	var extent_z := absf(side.z) * half_width + clearance
	if extent_x * 2 > _config.maximum_xz.x - _config.minimum_xz.x or extent_z * 2 > _config.maximum_xz.y - _config.minimum_xz.y:
		return {"rejection": "line does not fit prototype bounds", "unit_ids": []}
	var destination_center := Vector3(clampf(target.x, _config.minimum_xz.x + extent_x, _config.maximum_xz.x - extent_x), 0, clampf(target.z, _config.minimum_xz.y + extent_z, _config.maximum_xz.y - extent_z))
	if not is_navigation_ready():
		return {"rejection": "navigation not ready", "unit_ids": []}
	var accepted: Array[int] = []
	var failed: Array[int] = []
	var reserved: Array[Vector3] = []
	for index: int in ids.size():
		var unit_id := ids[index]
		var destination := destination_center + side * (-half_width + index * spacing)
		destination.y = _units[unit_id].position.y
		if not _valid_speeds(_units[unit_id]):
			failed.append(unit_id)
			continue
		var path := navigation_for(_units[unit_id]).find_path(_units[unit_id].position, destination, reserved, spacing, mode == MoveMode.FAST, _units[unit_id])
		if path.is_empty():
			failed.append(unit_id)
			continue
		_assign_path(unit_id, path, mode)
		_final_yaws[unit_id] = _units[unit_id].yaw if facing.is_zero_approx() and Vector2(target.x - center.x, target.z - center.z).is_zero_approx() else final_yaw
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
	for id: int in attack_facing_requests:
		if _units.has(id) and not _targets.has(id):
			var previous := _units[id].yaw
			_turn(_units[id],attack_facing_requests[id],delta)
			if previous != _units[id].yaw: changed[id] = _units[id].position
	var ordered := _targets.keys()
	ordered.sort()
	for unit_id: int in ordered:
		if _engaging.has(unit_id):
			continue
		var state := _units[unit_id]
		if _blocked_seconds.has(unit_id):
			_blocked_seconds[unit_id] += delta
			if _blocked_seconds[unit_id] >= dynamic_retry_seconds:
				if not profile.is_empty(): profile["repath_queries"] = profile.get("repath_queries",0) + 1
				_blocked_seconds[unit_id] = 0.0
				var replacement := navigation_for(state).find_path(state.position, _targets[unit_id], [], 0.0, _move_modes[unit_id] == MoveMode.FAST, state)
				if replacement.size() >= 2:
					_paths[unit_id] = replacement
					_path_indices[unit_id] = 1
					_targets[unit_id] = replacement[replacement.size() - 1]
		var time_left := delta
		var path := _paths[unit_id]
		var index := _path_indices[unit_id]
		# Spend time across both route corners and exact surface boundaries.
		while index < path.size() and time_left > 0.0:
			var direction := path[index] - state.position
			if direction.length_squared() <= 0.00000001:
				state.position = path[index]
				index += 1
				continue
			var desired := atan2(-direction.x, -direction.z)
			if _reverse_moves.has(unit_id):
				desired = wrapf(desired + PI, -PI, PI)
			var turn_time := 0.0 if _reverse_moves.has(unit_id) and not state.runtime_weapons.is_empty() else _turn(state, desired, time_left)
			time_left = maxf(0, time_left - turn_time)
			if time_left <= 0:
				break
			var portions := _navigation.surface.split_segment(state.position, path[index])
			for portion_index: int in range(1, portions.size()):
				var end := portions[portion_index]
				var speed := state.speed_on(_navigation.surface.is_hardened((state.position + end) * 0.5), _config.speed)
				if _reverse_moves.has(unit_id):
					speed = state.reverse_speed_on(_navigation.surface.is_hardened((state.position + end) * 0.5))
				var duration := state.position.distance_to(end) / speed
				var next_position := end if duration <= time_left else state.position.move_toward(end, speed * time_left)
				if not translation_clear(state,state.position,next_position):
					if not _blocked_seconds.has(unit_id): _blocked_seconds[unit_id] = 0.0
					time_left = 0.0
					break
				_blocked_seconds.erase(unit_id)
				if duration <= time_left:
					state.position = end
					time_left -= duration
				else:
					state.position = state.position.move_toward(end, speed * time_left)
					time_left = 0.0
					break
			if state.position == path[index]:
				index += 1
				if state.definition != null:
					# Keep a replicated tick's translation aligned with its body yaw.
					time_left = 0.0
					break
		_path_indices[unit_id] = index
		changed[unit_id] = state.position
		if index >= path.size():
			_turn(state, _final_yaws.get(unit_id, state.yaw), time_left)
			if absf(wrapf(_final_yaws.get(unit_id, state.yaw) - state.yaw, -PI, PI)) < 0.00001:
				_clear_move(unit_id)
	for state: UnitState in _units.values():
		state.advance_members(delta)
	return changed


func _clear_move(unit_id: int) -> void:
	_blocked_seconds.erase(unit_id)
	_move_modes.erase(unit_id)
	_final_yaws.erase(unit_id)
	_reverse_moves.erase(unit_id)
	_attack_moves.erase(unit_id)
	_engaging.erase(unit_id)
	_targets.erase(unit_id)
	_paths.erase(unit_id)
	_path_indices.erase(unit_id)


func command_snapshot(unit_id: int) -> Dictionary:
	if not _targets.has(unit_id):
		return {"mode": -1, "target": null, "path": [], "final_yaw": null, "engaging": false}
	var ids: Array[int] = [unit_id]
	var path: Array = []
	for point: Vector3 in move_paths(ids)[0]:
		path.append([point.x, point.y, point.z])
	var target := _targets[unit_id]
	return {"mode": _move_modes[unit_id], "target": [target.x, target.y, target.z],
		"path": path, "final_yaw": _final_yaws[unit_id], "engaging": _engaging.has(unit_id)}


func active_command_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_targets.keys())
	ids.sort()
	return ids


func _valid_speeds(unit: UnitState) -> bool:
	if unit.definition != null and not unit.definition.spatial_valid(): return false
	var paved := unit.speed_on(true, _config.speed)
	var unpaved := unit.speed_on(false, _config.speed)
	var turn_rate := unit.definition.turn_speed_degrees if unit.definition != null else 180.0
	return is_finite(unit.yaw) and is_finite(turn_rate) and turn_rate > 0 and is_finite(paved) and is_finite(unpaved) and paved > 0.0 and unpaved > 0.0


func _can_reverse(unit: UnitState) -> bool:
	if unit.definition == null or unit.unit_type() != UnitDefinition.UnitType.ARMORED_VEHICLE:
		return false
	var definition := unit.definition
	return is_finite(unit.yaw) and is_finite(definition.hardened_reverse_speed) \
		and is_finite(definition.unhardened_reverse_speed) and is_finite(definition.turn_speed_degrees) \
		and definition.hardened_reverse_speed > 0.0 and definition.unhardened_reverse_speed > 0.0 \
		and definition.turn_speed_degrees > 0.0


func has_active_moves() -> bool:
	return not _targets.is_empty()


func is_moving(unit_id: int) -> bool:
	return _targets.has(unit_id) and not _engaging.has(unit_id)


func update_attack_engagement(combat: CombatSimulation) -> void:
	# Freeze only the existing route; target selection never creates a movement order.
	for unit_id: int in _attack_moves:
		if combat.nearest_enemy(_units[unit_id]) != null:
			_engaging[unit_id] = true
		else:
			_engaging.erase(unit_id)


func request_stop(unit_ids: Array[int], sender_peer_id: int) -> Array[int]:
	var accepted: Array[int] = []
	for unit_id: int in unit_ids:
		if not _units.has(unit_id) or _units[unit_id].health <= 0.0:
			continue
		if _units[unit_id].owner_peer_id != sender_peer_id or accepted.has(unit_id):
			continue
		_clear_move(unit_id)
		accepted.append(unit_id)
	accepted.sort()
	return accepted


func remove_unit(unit_id: int) -> void:
	_clear_move(unit_id)
	_units.erase(unit_id)


func stop_owner(owner_peer_id: int) -> void:
	for unit_id: int in _targets.keys():
		if _units[unit_id].owner_peer_id == owner_peer_id:
			_clear_move(unit_id)


func _command_yaw(unit: UnitState, direction: Vector3, mode: int, facing: Vector3) -> float:
	if mode == MoveMode.REVERSE and not unit.runtime_weapons.is_empty(): return unit.yaw
	if not facing.is_zero_approx():
		return atan2(-facing.x, -facing.z)
	direction.y = 0
	if direction.is_zero_approx():
		return unit.yaw
	var yaw := atan2(-direction.x, -direction.z)
	return wrapf(yaw + PI, -PI, PI) if mode == MoveMode.REVERSE else yaw


func _turn(state: UnitState, desired: float, seconds: float) -> float:
	if state.definition == null:
		state.yaw = desired
		return 0.0
	var rate := deg_to_rad(state.definition.turn_speed_degrees if state.definition != null else 180.0)
	var angle := wrapf(desired - state.yaw, -PI, PI)
	var duration := absf(angle) / rate
	state.yaw = wrapf(state.yaw + signf(angle) * minf(absf(angle), rate * seconds), -PI, PI)
	return duration
