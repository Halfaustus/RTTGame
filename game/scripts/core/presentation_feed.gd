class_name PresentationFeed
extends RefCounted

# This interface carries display results only. It has no transport or simulation.
signal reset_received
signal unit_spawn_received(unit_id: int, owner_peer_id: int, position: Vector3)
signal unit_positions_received(unit_ids: Array[int], positions: Array[Vector3])
signal unit_move_targets_received(unit_ids: Array[int], positions: Array[Vector3])
signal unit_move_paths_received(unit_ids: Array[int], paths: Array[PackedVector3Array])
signal unit_combat_state_received(unit_id: int, team_id: int, maximum_health: float, health: float)
signal combat_shot_received(start: Vector3, end: Vector3)
signal unit_death_received(unit_id: int)
signal unit_stops_received(unit_ids: Array[int], positions: Array[Vector3])
signal unit_armament_received(unit_id: int, armed: bool)
signal unit_type_received(unit_id: int, unit_type: int)
signal unit_orientations_received(unit_ids: Array[int], yaws: Array[float])


func apply_live_unit(state: Dictionary) -> void:
	unit_spawn_received.emit(state.unit_id, state.owner_peer_id, state.position)
	unit_type_received.emit(state.unit_id, state.unit_type)
	unit_armament_received.emit(state.unit_id, state.armed)
	unit_combat_state_received.emit(state.unit_id, state.team_id, state.maximum_health, state.health)
	var ids: Array[int] = [state.unit_id]
	var positions: Array[Vector3] = [state.position]
	var yaws: Array[float] = [state.yaw]
	unit_positions_received.emit(ids, positions)
	unit_orientations_received.emit(ids, yaws)


func apply_shot(shot: Dictionary) -> void:
	combat_shot_received.emit(shot.start, shot.end)
	# This is an absolute server result, never local damage calculation.
	unit_combat_state_received.emit(shot.target_id, -1, -1.0, shot.health)


func apply_replay_unit(state: Dictionary) -> void:
	var native := state.duplicate(true)
	native.position = vector(state.position)
	# In an offline view ownership is a match player ID, never a live ENet peer.
	native.owner_peer_id = int(state.owner_player_id)
	apply_live_unit(native)
	var ids: Array[int] = [state.unit_id]
	var positions: Array[Vector3] = [native.position]
	if state.command.mode == -1:
		unit_stops_received.emit(ids, positions)
	else:
		var targets: Array[Vector3] = [vector(state.command.target)]
		var path := PackedVector3Array()
		for point: Array in state.command.path:
			path.append(vector(point))
		var paths: Array[PackedVector3Array] = [path]
		unit_move_targets_received.emit(ids, targets)
		unit_move_paths_received.emit(ids, paths)


static func vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
