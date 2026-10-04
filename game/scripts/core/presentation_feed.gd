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
signal unit_structure_received(state: Dictionary)
signal unit_identity_received(unit_id: int, player_id: int, definition_id: String)
signal unit_member_count_received(unit_id: int, count: int)
var live_structures: Dictionary[int, Dictionary] = {}
signal weapon_fire_received(event: Dictionary)
signal projectile_spawn_received(event: Dictionary)
signal projectile_terminal_received(event: Dictionary)
var live_projectiles: Dictionary = {}
var _projectile_order := 0
var _fire_sequences: Dictionary = {}

func _init() -> void:
	reset_received.connect(_clear_structures)
	unit_death_received.connect(_remove_structure)

func _clear_structures() -> void:
	live_structures.clear()
	_fire_sequences.clear()
	live_projectiles.clear()
	_projectile_order = 0

func apply_projectile_spawn(event: Dictionary) -> void:
	var order := int(event.get("emission_order",0))
	if order <= _projectile_order: return
	_projectile_order = order
	live_projectiles[event.projectile_id] = event.duplicate(true)
	projectile_spawn_received.emit(event.duplicate(true))

func apply_projectile_terminal(event: Dictionary) -> void:
	if not live_projectiles.has(event.projectile_id): return
	live_projectiles.erase(event.projectile_id)
	projectile_terminal_received.emit(event.duplicate(true))

func projectile_position(id: String, authority_time: float) -> Vector3:
	var state: Dictionary = live_projectiles.get(id,{})
	if state.is_empty(): return Vector3.ZERO
	return state.position+state.velocity*clampf(authority_time-state.time_seconds,0,state.lifetime_seconds)

func _remove_structure(id: int) -> void:
	live_structures.erase(id)
	for key: String in _fire_sequences.keys():
		if key.begins_with(str(id)+"/"): _fire_sequences.erase(key)

func apply_fire_event(event: Dictionary) -> void:
	if not event.has("weapon_instance_id") or not event.has("emission_sequence"): return
	var key := str(event.weapon_instance_id)
	var sequence := int(event.emission_sequence)
	if sequence <= int(_fire_sequences.get(key,0)): return
	_fire_sequences[key] = sequence
	weapon_fire_received.emit(event.duplicate(true)) # Presentation only; no ammunition/HP access.

func apply_live_structure(state: Dictionary) -> void:
	live_structures[int(state.unit_id)] = state.duplicate(true)
	unit_structure_received.emit(state.duplicate(true))
	var count := 0
	for member: Dictionary in state.get("members",[]):
		if member.health > 0: count += 1
	unit_member_count_received.emit(int(state.unit_id),count)


func apply_live_unit(state: Dictionary) -> void:
	unit_spawn_received.emit(state.unit_id, state.owner_peer_id, state.position)
	unit_identity_received.emit(state.unit_id,int(state.get("owner_player_id",0)),str(state.get("definition_id","")))
	if state.has("member_count"): unit_member_count_received.emit(state.unit_id,int(state.member_count))
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
