class_name PresentationFeed
extends RefCounted

signal unit_move_modes_received(unit_ids: Array[int], modes: Array[int])

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
signal unit_status_received(state: Dictionary)
signal unit_identity_received(unit_id: int, player_id: int, definition_id: String)
signal unit_member_count_received(unit_id: int, count: int)
var live_structures: Dictionary[int, Dictionary] = {}
var _retired_units: Dictionary = {}
signal weapon_fire_received(event: Dictionary)
signal projectile_spawn_received(event: Dictionary)
signal projectile_terminal_received(event: Dictionary)
var live_projectiles: Dictionary = {}
var projectile_buffers: Dictionary = {}
var interpolation_delay := 0.05 # 1.5 snapshots at 30 Hz; client-adjustable.
const MAX_EXTRAPOLATION_SECONDS := 0.05 # Client clock budget, independent of simulation rate.
const CLOCK_CORRECTION_SECONDS := 0.05
var _projectile_clock_initialized := false
var projectile_authority_time := 0.0
var projectile_display_time := 0.0
var _projectile_terminal_times: Dictionary = {}
var _fire_sequences: Dictionary = {}

func _init() -> void:
	reset_received.connect(_clear_structures)
	unit_death_received.connect(_remove_structure)

func _clear_structures() -> void:
	live_structures.clear()
	_retired_units.clear()
	_fire_sequences.clear()
	live_projectiles.clear()
	projectile_buffers.clear()
	_projectile_terminal_times.clear()
	_projectile_clock_initialized = false
	projectile_authority_time = 0.0
	projectile_display_time = 0.0

func apply_projectile_spawn(event: Dictionary) -> void:
	if not event.get("projectile_id") is String: return
	var id: String = event.projectile_id
	if _projectile_terminal_times.has(id): return
	if live_projectiles.has(id) and float(event.get("time_seconds",0)) <= float(live_projectiles[id].get("time_seconds",0)): return
	live_projectiles[event.projectile_id] = event.duplicate(true)
	if not projectile_buffers.has(id): projectile_buffers[id] = ProjectileSnapshotBuffer.new()
	projectile_buffers[id].push(event)
	projectile_spawn_received.emit(event.duplicate(true))

func apply_projectile_terminal(event: Dictionary) -> void:
	if not event.get("projectile_id") is String: return
	if not live_projectiles.has(event.projectile_id): return
	_projectile_terminal_times[event.projectile_id] = event.get("time_seconds",0.0)
	projectile_terminal_received.emit(event.duplicate(true))
	live_projectiles.erase(event.projectile_id)
	projectile_buffers.erase(event.projectile_id)

func synchronize_projectile_time(value: float) -> void:
	if not is_finite(value) or value < projectile_authority_time: return
	projectile_authority_time = value
	if not _projectile_clock_initialized or live_projectiles.is_empty():
		projectile_display_time = value
		_projectile_clock_initialized = true

func advance_projectile_display(delta: float) -> void:
	if not is_finite(delta) or delta < 0: return
	# Render-rate clock with smooth catch-up and a bounded cosmetic horizon.
	var correction := maxf(0,projectile_authority_time-projectile_display_time)*(1.0-exp(-delta/CLOCK_CORRECTION_SECONDS))
	projectile_display_time = minf(projectile_display_time + delta + correction, projectile_authority_time + maxf(0,interpolation_delay) + MAX_EXTRAPOLATION_SECONDS)

func projectile_visual_state(id: String, delta: float) -> Dictionary:
	if not projectile_buffers.has(id): return {}
	return projectile_buffers[id].render(projectile_display_time-interpolation_delay,delta)

func projectile_position(id: String, authority_time: float) -> Vector3:
	var state: Dictionary = live_projectiles.get(id,{})
	if state.is_empty(): return Vector3.ZERO
	var elapsed := maxf(0,authority_time-float(state.time_seconds))
	if state.has("acceleration"):
		return state.position+state.velocity*elapsed+state.acceleration*(0.5*elapsed*elapsed)
	return state.position+state.velocity*minf(elapsed,float(state.lifetime_seconds)) # Legacy-only event shape.

func projectile_velocity(id: String, authority_time: float) -> Vector3:
	var state: Dictionary = live_projectiles.get(id,{})
	if state.is_empty(): return Vector3.ZERO
	return state.velocity+state.get("acceleration",Vector3.ZERO)*maxf(0,authority_time-float(state.time_seconds))

func _remove_structure(id: int) -> void:
	live_structures.erase(id)
	_retired_units[id] = true
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
	if _retired_units.has(int(state.get("unit_id",0))): return
	live_structures[int(state.unit_id)] = state.duplicate(true)
	unit_structure_received.emit(state.duplicate(true))
	var count := 0
	for member: Dictionary in state.get("members",[]):
		if member.health > 0: count += 1
	unit_member_count_received.emit(int(state.unit_id),count)

func apply_live_status(state: Dictionary) -> void:
	if _retired_units.has(int(state.get("unit_id",0))): return
	unit_status_received.emit(state.duplicate(true))


func apply_live_unit(state: Dictionary) -> void:
	if _retired_units.has(int(state.get("unit_id",0))): return
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
