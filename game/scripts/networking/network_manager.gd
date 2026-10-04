extends Node

signal tick_completed(tick: int, records: Array[Dictionary])
signal deployment_state_received(state: Dictionary)
signal deployment_result_received(result: Dictionary)
signal deployment_event(event: Dictionary)
signal weapon_fire_received(event: Dictionary)
signal projectile_spawn_received(event: Dictionary)
signal projectile_terminal_received(event: Dictionary)

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

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 16
const INTERNAL_STATE_REPLICATION_HZ := 10 # Temporary 0.5B parameter; unchanged.
const MOVEMENT_CONFIG: MovementConfig = preload("res://data/prototype_movement.tres")
const COMBAT_CONFIG: CombatConfig = preload("res://data/prototype_combat.tres")
const DEPLOYMENT_CONFIG: DeploymentConfig = preload("res://data/prototype_deployment.tres")

# Only the dedicated server writes authoritative unit state.
var presentation := PresentationFeed.new()
var timeline := SimulationTimeline.new(Engine.physics_ticks_per_second)
var _replication_queue: Array[Dictionary] = []
var _pending_sessions: Array[Dictionary] = []
var _pending_commands: Array[Dictionary] = []
var _pending_deployment_requests: Array[Dictionary] = []
var _dirty_deployment: Dictionary[int, bool] = {}
var deployment := DeploymentEconomy.new()
var local_deployment_state: Dictionary = {}
var _peer_players: Dictionary[int, int] = {}
var _players: Dictionary[int, Dictionary] = {}
var _next_player_id := 1
var _retired_unit_ids: Array[int] = []
var _dirty_units: Dictionary[int, bool] = {}
var _match_header: Dictionary = {}
var initial_replay_checkpoint: Dictionary = {}
var replay_recorder := ReplayRecorder.new()
var _recording_path := ""
var _snapshot_ticks := 300
var _next_unit_id: int = 1
var _authoritative_units: Dictionary[int, UnitState] = {}
var _movement := MovementSimulation.new(MOVEMENT_CONFIG)
var _pending_positions: Dictionary[int, Vector3] = {}
var _replication_elapsed: float = 0.0
var _combat := CombatSimulation.new(MovementSimulation.MAP_DEFINITION)
var _aiming := AimingSimulation.new()
var _fire := FireSimulation.new()
var _projectiles: ProjectileSimulation
var _previous_ballistic_positions: Dictionary = {}
var legacy_combat_fixture_enabled := false # Explicit historical test opt-in only.
var _weapon_presets: Array[UnitDefinition] = [preload("res://data/05d/assault.tres"),preload("res://data/05d/defense.tres")]
var _rebels_initialized: bool = false
var _player_spawn_index: int = 1


func _ready() -> void:
	presentation.weapon_fire_received.connect(weapon_fire_received.emit)
	presentation.projectile_spawn_received.connect(projectile_spawn_received.emit)
	presentation.projectile_terminal_received.connect(projectile_terminal_received.emit)
	deployment.state_changed.connect(func(player_id: int): _dirty_deployment[player_id] = true)
	deployment.event_emitted.connect(deployment_event.emit)
	presentation.unit_spawn_received.connect(unit_spawn_received.emit)
	presentation.unit_positions_received.connect(unit_positions_received.emit)
	presentation.unit_move_targets_received.connect(unit_move_targets_received.emit)
	presentation.unit_move_paths_received.connect(unit_move_paths_received.emit)
	presentation.unit_combat_state_received.connect(unit_combat_state_received.emit)
	presentation.combat_shot_received.connect(combat_shot_received.emit)
	presentation.unit_death_received.connect(unit_death_received.emit)
	presentation.unit_stops_received.connect(unit_stops_received.emit)
	presentation.unit_armament_received.connect(unit_armament_received.emit)
	presentation.unit_type_received.connect(unit_type_received.emit)
	presentation.unit_orientations_received.connect(unit_orientations_received.emit)
	set_physics_process(false)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func start_server(port: int = DEFAULT_PORT) -> bool:
	if not _ensure_deployment_ready():
		return false
	# Finish the synchronous static grid before accepting connections or commands.
	if not _movement.is_navigation_ready() and not _movement.initialize_navigation():
		push_error("Dedicated server navigation initialization failed.")
		return false
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_CLIENTS)

	if error != OK:
		push_error(
			"Failed to start server on port %d. Error: %s"
			% [port, error]
		)
		return false

	multiplayer.multiplayer_peer = peer

	_ensure_match_header()
	_initialize_rebels()
	initial_replay_checkpoint = capture_replay_checkpoint()
	if not _recording_path.is_empty():
		replay_recorder.start(self, _recording_path, _snapshot_ticks)
	set_physics_process(true)
	print("Dedicated server started on port %d." % port)
	return true


func configure_recording(path: String, snapshot_ticks: int = 300) -> void:
	_recording_path = path
	_snapshot_ticks = snapshot_ticks


func finish_server() -> Dictionary:
	# Consume queued connection/command callbacks once before the final boundary.
	set_physics_process(false)
	if multiplayer.is_server():
		_run_server_tick(multiplayer.get_peers())
		# Ending a match closes all remaining player sessions, even if ENet has not
		# detected a killed client's timeout yet. Record their departure before close.
		if not _peer_players.is_empty():
			var peers := _peer_players.keys()
			peers.sort()
			for id: int in peers:
				_pending_sessions.append({"type": "leave", "peer_id": id, "reason": "match_end"})
			_run_server_tick(PackedInt32Array())
	var result := replay_recorder.finish()
	multiplayer.multiplayer_peer.close()
	return result


func connect_to_server(
	address: String = "127.0.0.1",
	port: int = DEFAULT_PORT
) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)

	if error != OK:
		push_error(
			"Failed to create client connection to %s:%d. Error: %s"
			% [address, port, error]
		)
		return false

	multiplayer.multiplayer_peer = peer

	print("Connecting to server at %s:%d..." % [address, port])
	return true


func _on_connected_to_server() -> void:
	print(
		"Connected to server. Local peer ID: %d"
		% multiplayer.get_unique_id()
	)


func _on_connection_failed() -> void:
	print("Connection to server failed.")


func _on_server_disconnected() -> void:
	print("Disconnected from server.")


func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: %d" % peer_id)
	if multiplayer.is_server():
		_pending_sessions.append({"type": "join", "peer_id": peer_id})


func _apply_peer_join(peer_id: int) -> void:
	if _peer_players.has(peer_id):
		return
	var player_id := _next_player_id
	_next_player_id += 1
	_peer_players[peer_id] = player_id
	_players[player_id] = {"player_id": player_id, "label": "Player %d" % player_id}
	deployment.register_player(player_id, COMBAT_CONFIG.player_team_id, timeline.tick)
	timeline.append("event", "player_join", {"player_id": player_id, "peer_id": peer_id})
	# Keep current peer ownership for control; the match player ID is archival identity.
	if multiplayer.get_peers().has(peer_id):
		for snapshot: Dictionary in live_snapshots():
			_queue_replication("_receive_unit_snapshot", [snapshot], peer_id)
		if _projectiles != null:
			var active_spawns: Array[Dictionary] = []
			for projectile: ProjectileState in _projectiles.active.values(): active_spawns.append(projectile.spawn_event())
			active_spawns.sort_custom(func(a,b): return a.emission_order < b.emission_order)
			if not active_spawns.is_empty(): _queue_replication("_receive_projectile_events",[active_spawns,[]],peer_id)
	for index: int in MOVEMENT_CONFIG.units_per_peer:
		var unit_id := _next_unit_id
		_next_unit_id += 1
		var spawn: Vector3 = MOVEMENT_CONFIG.spawn_position(_player_spawn_index)
		_player_spawn_index += 1
		var state := UnitState.new(unit_id, peer_id, spawn)
		state.owner_player_id = player_id
		state.configure(COMBAT_CONFIG.player_team_id, COMBAT_CONFIG.player_definitions[index % COMBAT_CONFIG.player_definitions.size()] if legacy_combat_fixture_enabled else _weapon_presets[index % _weapon_presets.size()])
		var sized_spawn: Variant = _movement.resolve_spawn_position(state.position, state)
		if sized_spawn == null:
			push_error("No valid unit-sized player spawn.")
			continue
		state.position = sized_spawn
		_authoritative_units[unit_id] = state
		state.generated_tick = timeline.tick
		deployment.register_live_unit(unit_id, player_id, state.definition, state.generated_tick)
		_movement.add_unit(state)
		_combat.add_unit(state)
		timeline.append("event", "spawn", ReplayFormat.unit_state(state, _movement))
		print("Authoritative unit %d created. Owner peer: %d; match player: %d" % [unit_id, peer_id, player_id])
		if not multiplayer.get_peers().is_empty():
			_queue_replication("_receive_unit_snapshot", [_presentation_snapshot(state)])


func _initialize_rebels() -> void:
	if _rebels_initialized:
		return
	_rebels_initialized = true
	for requested: Vector3 in COMBAT_CONFIG.rebel_positions:
		var state := UnitState.new(_next_unit_id, 0, requested)
		_next_unit_id += 1
		state.configure(COMBAT_CONFIG.rebel_team_id, COMBAT_CONFIG.rebel_definition if legacy_combat_fixture_enabled else _weapon_presets[1])
		var sized_spawn: Variant = _movement.resolve_spawn_position(state.position, state)
		if sized_spawn == null:
			push_error("No valid unit-sized rebel spawn.")
			continue
		state.position = sized_spawn
		_authoritative_units[state.unit_id] = state
		_movement.add_unit(state)
		_combat.add_unit(state)


func live_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for state: UnitState in _authoritative_units.values():
		if state.health > 0.0:
			snapshots.append(_presentation_snapshot(state))
	return snapshots


@rpc("authority", "call_remote", "reliable")
func _receive_unit_snapshot(state: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	presentation.apply_live_unit(state)

func _presentation_snapshot(state: UnitState) -> Dictionary:
	var result := state.snapshot()
	result.definition_id = state.definition.resource_path
	var count := 0
	for member: SoldierState in state.members:
		if member.health > 0: count += 1
	result.member_count = count
	return result


@rpc("authority", "call_remote", "reliable")
func _receive_combat_shot(shot: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	presentation.apply_shot(shot)


@rpc("authority", "call_remote", "reliable")
func _receive_unit_death(unit_id: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	presentation.unit_death_received.emit(unit_id)


func request_move(unit_id: int, target_position: Vector3, mode: int = MovementSimulation.MoveMode.BASIC) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_submit_move.rpc_id(1, unit_id, target_position, mode)


func request_moves(unit_ids: Array[int], target_position: Vector3, mode: int = MovementSimulation.MoveMode.BASIC, facing: Vector3 = Vector3.ZERO) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_submit_group_move.rpc_id(1, unit_ids, target_position, mode, facing)


func request_stops(unit_ids: Array[int]) -> void:
	if unit_ids.is_empty() or multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_submit_stop.rpc_id(1, unit_ids)


@rpc("any_peer", "call_remote", "reliable")
func _submit_stop(unit_ids: Array[int]) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender):
		return
	_queue_command({"type": "stop", "unit_ids": unit_ids.duplicate(), "mode": -1, "target": null, "facing": null}, sender)


func _apply_stop(unit_ids: Array[int], sender: int) -> Dictionary:
	var accepted := _movement.request_stop(unit_ids, sender)
	var positions: Array[Vector3] = []
	for unit_id: int in accepted:
		positions.append(_authoritative_units[unit_id].position)
		for instance: RuntimeWeaponInstance in _authoritative_units[unit_id].runtime_weapons: instance.clear_target()
		_movement.attack_facing_requests.erase(unit_id)
		# Remove any older buffered position before broadcasting the current stop position.
		_pending_positions.erase(unit_id)
	for command: Dictionary in _pending_commands:
		if command.peer_id != sender: continue
		command.unit_ids = command.unit_ids.filter(func(id): return not accepted.has(id))
	_pending_commands = _pending_commands.filter(func(command): return not command.unit_ids.is_empty())
	return {"unit_ids": accepted, "positions": positions}


@rpc("authority", "call_remote", "reliable")
func _receive_unit_stops(unit_ids: Array[int], positions: Array[Vector3]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if unit_ids.size() != positions.size():
		return
	presentation.unit_stops_received.emit(unit_ids, positions)


@rpc("any_peer", "call_remote", "reliable")
func _submit_group_move(unit_ids: Array[int], target_position: Vector3, mode: int = MovementSimulation.MoveMode.BASIC, facing: Vector3 = Vector3.ZERO) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender):
		return
	_queue_command({"type": "move", "unit_ids": unit_ids.duplicate(), "mode": mode, "target": target_position, "facing": facing, "group": true}, sender)


@rpc("any_peer", "call_remote", "reliable")
func _submit_move(unit_id: int, target_position: Vector3, mode: int = MovementSimulation.MoveMode.BASIC) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender):
		return
	var ids: Array[int] = [unit_id]
	_queue_command({"type": "move", "unit_ids": ids, "mode": mode, "target": target_position, "facing": Vector3.ZERO, "group": false}, sender)


@rpc("authority", "call_remote", "reliable")
func _receive_move_targets(unit_ids: Array[int], positions: Array[Vector3]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if unit_ids.size() != positions.size():
		return
	presentation.unit_move_targets_received.emit(unit_ids, positions)


@rpc("authority", "call_remote", "reliable")
func _receive_move_paths(unit_ids: Array[int], paths: Array[PackedVector3Array]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if unit_ids.size() != paths.size():
		return
	presentation.unit_move_paths_received.emit(unit_ids, paths)


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	_run_server_tick(multiplayer.get_peers())


func _run_server_tick(connected_peers: PackedInt32Array) -> void:
	# One authoritative fixed step. Network callback arrival never mutates simulation.
	if not _ensure_deployment_ready():
		return
	timeline.begin_tick()
	deployment.begin_tick(timeline.tick)
	_consume_sessions(connected_peers)
	deployment.advance_to_tick(timeline.tick)
	_consume_deployment_requests(connected_peers)
	deployment.execute_deployments(_authoritative_units, _spawn_deployment)
	# Frozen v1 spawn events belong to session. Deployment requests are a
	# separate economic stream, adjudicated here before any spawn or movement.
	timeline.enter_phase("commands")
	_consume_commands(connected_peers)
	timeline.enter_phase("movement")
	var delta := timeline.seconds_per_tick()
	for id: int in _movement.active_command_ids():
		_dirty_units[id] = true
	_aiming.units = _authoritative_units
	# No detection provider exists yet: never equate valid enemy with visible enemy.
	_aiming.visibility = func(owner: UnitState, target: AttackTarget): return target.kind == AttackTarget.Kind.FORCED_GROUND or (target.valid(_authoritative_units) and _authoritative_units[target.unit_id].team_id == owner.team_id)
	_aiming.clear_path = _combat.has_line_of_sight
	_aiming.moving = _movement.is_moving
	_movement.attack_facing_requests = _aiming.hull_requests()
	for state: UnitState in _authoritative_units.values():
		if not _previous_ballistic_positions.has(state.unit_id): _previous_ballistic_positions[state.unit_id] = state.position
	if legacy_combat_fixture_enabled: _movement.update_attack_engagement(_combat)
	var changed := _movement.advance(delta)
	_aiming.target_velocities.clear()
	for state: UnitState in _authoritative_units.values():
		_aiming.target_velocities[state.unit_id] = (state.position-_previous_ballistic_positions[state.unit_id])/delta
		_previous_ballistic_positions[state.unit_id] = state.position
	for id: int in _previous_ballistic_positions.keys():
		if not _authoritative_units.has(id): _previous_ballistic_positions.erase(id)
	_pending_positions.merge(changed, true)
	for id: int in changed:
		_dirty_units[id] = true
	# A target entered range during this tick: park before applying firing eligibility.
	if legacy_combat_fixture_enabled: _movement.update_attack_engagement(_combat)
	timeline.enter_phase("combat")
	_aiming.advance(delta)
	if not legacy_combat_fixture_enabled:
		if _projectiles == null:
			_projectiles = ProjectileSimulation.new()
			_projectiles.bounds = Rect2(MOVEMENT_CONFIG.minimum_xz,MOVEMENT_CONFIG.maximum_xz-MOVEMENT_CONFIG.minimum_xz)
			_projectiles.collision.initialize_map(MovementSimulation.MAP_DEFINITION,MOVEMENT_CONFIG)
		_projectiles.collision.sync_units(_authoritative_units)
		_fire.fire_path_permission = _projectiles.collision.fire_clear
		var terminals := _projectiles.advance(delta,timeline.tick) # Advance older shots before spawning end-of-tick shots.
		for event: Dictionary in terminals: projectile_terminal_received.emit(event.duplicate(true))
		if not terminals.is_empty() and not connected_peers.is_empty(): _queue_replication("_receive_projectile_events",[[],terminals])
		var emissions := _fire.advance(delta,timeline.tick,_aiming)
		var spawns := _projectiles.consume(emissions)
		for event: Dictionary in spawns: projectile_spawn_received.emit(event.duplicate(true))
		if not spawns.is_empty() and not connected_peers.is_empty(): _queue_replication("_receive_projectile_events",[spawns,[]])
		for emission: Dictionary in emissions: weapon_fire_received.emit(emission.duplicate(true))
		if not emissions.is_empty() and not connected_peers.is_empty(): _queue_replication("_receive_weapon_fires",[emissions])
	# New emissions never enter legacy 'shot' (absolute HP result) or frozen v1.
	var combat_result: Dictionary = _combat.advance(delta, _movement) if legacy_combat_fixture_enabled else {"shots":[],"deaths":[]}
	for shot: Dictionary in combat_result["shots"]:
		_dirty_units[shot.target_id] = true
		var recorded_shot := shot.duplicate(true)
		recorded_shot.start = [shot.start.x, shot.start.y, shot.start.z]
		recorded_shot.end = [shot.end.x, shot.end.y, shot.end.z]
		timeline.append("event", "shot", recorded_shot)
		if not multiplayer.get_peers().is_empty():
			_queue_replication("_receive_combat_shot", [shot])
	for id: int in combat_result["deaths"]:
		deployment.remove_live_unit(id)
		_retired_unit_ids.append(id)
		timeline.append("event", "death", {"unit_id": id})
		_authoritative_units.erase(id)
		_pending_positions.erase(id)
		if not multiplayer.get_peers().is_empty():
			_queue_replication("_receive_unit_death", [id])
	timeline.enter_phase("record")
	var dirty_ids := _dirty_units.keys()
	dirty_ids.sort()
	for id: int in dirty_ids:
		if _authoritative_units.has(id):
			timeline.append("event", "unit_state", ReplayFormat.unit_state(_authoritative_units[id], _movement))
	_dirty_units.clear()
	# Future recorder consumes completed state/events here; no whole-match buffer in A.
	tick_completed.emit(timeline.tick, timeline.records.duplicate(true))
	timeline.enter_phase("replication")
	if timeline.tick % maxi(1, timeline.tick_hz / INTERNAL_STATE_REPLICATION_HZ) == 0:
		if not connected_peers.is_empty():
			var structures: Array[Dictionary] = []
			for state: UnitState in _authoritative_units.values(): structures.append(state.structure_snapshot())
			_queue_replication("_receive_unit_structures", [structures])
		for peer_id: int in _peer_players:
			var player_id := _peer_players[peer_id]
			if _dirty_deployment.has(player_id):
				_queue_replication("_receive_deployment_state", [deployment.export_player(player_id)], peer_id)
		_dirty_deployment.clear()
	_replication_elapsed += delta
	if _replication_elapsed >= MOVEMENT_CONFIG.replication_interval or not _movement.has_active_moves():
		if not _pending_positions.is_empty() and not multiplayer.get_peers().is_empty():
			var unit_ids: Array[int] = []
			var positions: Array[Vector3] = []
			for unit_id: int in _pending_positions:
				unit_ids.append(unit_id)
				positions.append(_pending_positions[unit_id])
			# Reliable ordered delivery also preserves spawn-before-position ordering.
			_queue_replication("_receive_unit_positions", [unit_ids, positions])
			_queue_replication("_receive_unit_orientations", [unit_ids, _unit_yaws(unit_ids)])
		_pending_positions.clear()
		_replication_elapsed = 0.0
	_flush_replication()
	timeline.finish_tick()


@rpc("authority", "call_remote", "reliable")
func _receive_unit_structures(states: Array) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	for state: Dictionary in states: presentation.apply_live_structure(state)

@rpc("authority", "call_remote", "reliable")
func _receive_weapon_fires(events: Array) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	for event: Dictionary in events: presentation.apply_fire_event(event)

@rpc("authority", "call_remote", "reliable")
func _receive_projectile_events(spawns: Array, terminals: Array) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	for event: Dictionary in spawns: presentation.apply_projectile_spawn(event)
	for event: Dictionary in terminals: presentation.apply_projectile_terminal(event)


@rpc("authority", "call_remote", "reliable")
func _receive_unit_positions(unit_ids: Array[int], positions: Array[Vector3]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if unit_ids.size() != positions.size():
		return
	presentation.unit_positions_received.emit(unit_ids, positions)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: %d" % peer_id)
	if multiplayer.is_server():
		_pending_sessions.append({"type": "leave", "peer_id": peer_id})


func _unit_yaws(unit_ids: Array[int]) -> Array[float]:
	var yaws: Array[float] = []
	for id: int in unit_ids:
		yaws.append(_authoritative_units[id].yaw)
	return yaws


@rpc("authority", "call_remote", "reliable")
func _receive_unit_orientations(unit_ids: Array[int], yaws: Array[float]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if unit_ids.size() != yaws.size():
		return
	for yaw: float in yaws:
		if not is_finite(yaw):
			return
	presentation.unit_orientations_received.emit(unit_ids, yaws)


func _queue_command(command: Dictionary, sender: int) -> void:
	if not _peer_players.has(sender):
		return
	command.peer_id = sender
	command.player_id = _peer_players[sender]
	_pending_commands.append(command)


func _consume_sessions(connected_peers: PackedInt32Array) -> void:
	var sessions := _pending_sessions
	_pending_sessions = []
	for session: Dictionary in sessions:
		var peer_id: int = session.peer_id
		if session.type == "join":
			if connected_peers.has(peer_id):
				_apply_peer_join(peer_id)
		elif _peer_players.has(peer_id):
			var player_id := _peer_players[peer_id]
			_peer_players.erase(peer_id)
			deployment.cancel_player_orders(player_id)
			_movement.stop_owner(peer_id)
			for unit: UnitState in _authoritative_units.values():
				if unit.owner_player_id == player_id:
					_dirty_units[unit.unit_id] = true
			timeline.append("event", "player_leave", {"player_id": player_id, "peer_id": peer_id,
				"reason": session.get("reason", "transport_disconnect")})


func _consume_commands(connected_peers: PackedInt32Array) -> void:
	var commands := _pending_commands
	_pending_commands = []
	for command: Dictionary in commands:
		var result := {"unit_ids": [], "failed_ids": [], "rejection": "sender disconnected or player changed"}
		if connected_peers.has(command.peer_id) and _peer_players.get(command.peer_id, 0) == command.player_id:
			result = _execute_command(command)
		var requested_ids: Array = []
		for id: int in command.unit_ids:
			requested_ids.append(ReplayFormat.request_integer(id))
		var payload := {"player_id": command.player_id, "peer_id": command.peer_id,
			"unit_ids": requested_ids, "mode": ReplayFormat.request_integer(command.mode), "target": null, "facing": null,
			"accepted_ids": result.unit_ids, "failed_ids": result.failed_ids, "rejection": result.rejection}
		if command.type == "move":
			var target: Vector3 = command.target
			var facing: Vector3 = command.facing
			payload.target = [target.x, target.y, target.z] if target.is_finite() else null
			payload.facing = [facing.x, facing.y, facing.z] if facing.is_finite() else null
			payload.group = command.group
		timeline.append("command", command.type, payload)


func _execute_command(command: Dictionary) -> Dictionary:
	var ids: Array[int] = []
	for id: int in command.unit_ids:
		# A reused ENet peer ID must not grant its new player the old player's units.
		if _authoritative_units.has(id) and _authoritative_units[id].owner_player_id != command.player_id:
			continue
		ids.append(id)
	var sender: int = command.peer_id
	var result := {"unit_ids": [], "failed_ids": [], "rejection": ""}
	if command.type == "stop":
		var stopped := _apply_stop(ids, sender)
		result.unit_ids = stopped.unit_ids
		if result.unit_ids.is_empty():
			result.rejection = "no owned living units"
		elif not multiplayer.get_peers().is_empty():
			_queue_replication("_receive_unit_stops", [stopped.unit_ids, stopped.positions])
			_queue_replication("_receive_unit_orientations", [stopped.unit_ids, _unit_yaws(stopped.unit_ids)])
	elif command.group:
		result = _movement.request_group_move(ids, sender, command.target, command.mode, command.facing)
		if not result.has("failed_ids"):
			result.failed_ids = []
	elif ids.is_empty():
		result.rejection = "no owned units"
	else:
		result.rejection = _movement.request_move(ids[0], sender, command.target, command.mode)
		if result.rejection.is_empty():
			result.unit_ids = ids
	for id: int in result.unit_ids:
		_dirty_units[id] = true
	if not result.unit_ids.is_empty():
		print("%s accepted: peer %d, units %s" % [command.type.capitalize(), sender, result.unit_ids])
		if command.type == "move" and multiplayer.get_peers().has(sender):
			var accepted: Array[int] = []
			accepted.assign(result.unit_ids)
			_queue_replication("_receive_move_targets", [accepted, _movement.move_targets(accepted)], sender)
			_queue_replication("_receive_move_paths", [accepted, _movement.move_paths(accepted)], sender)
	else:
		print("%s rejected: peer %d: %s" % [command.type.capitalize(), sender, result.rejection])
	return result


func _ensure_match_header() -> void:
	if not _match_header.is_empty():
		return
	var crypto := Crypto.new()
	_match_header = ReplayFormat.header(crypto.generate_random_bytes(16).hex_encode(), timeline.tick_hz,
		ReplayContent.MAP_ID, ReplayContent.RULES_ID, crypto.generate_random_bytes(8).hex_encode(), [], ReplayContent.fingerprints())


func replay_header() -> Dictionary:
	_ensure_match_header()
	var result := _match_header.duplicate(true)
	var ids := _players.keys()
	ids.sort()
	for id: int in ids:
		result.players.append(_players[id].duplicate(true))
	return result


func capture_replay_checkpoint() -> Dictionary:
	assert(timeline.phase in ["idle", "record"])
	var units: Array[Dictionary] = []
	var ids := _authoritative_units.keys()
	ids.sort()
	for id: int in ids:
		if _authoritative_units[id].health > 0:
			units.append(ReplayFormat.unit_state(_authoritative_units[id], _movement))
	var retired := _retired_unit_ids.duplicate()
	retired.sort()
	var connected := _peer_players.values()
	connected.sort()
	return {"through": timeline.cursor(), "units": units, "retired_unit_ids": retired,
		"next_unit_id": _next_unit_id, "connected_player_ids": connected}


func _queue_replication(method: String, arguments: Array, peer_id: int = -1) -> void:
	if legacy_combat_fixture_enabled:
		_replication_queue.append({"method": method, "arguments": arguments.duplicate(true), "peer_id": peer_id})
		return
	var recipients: Array = _peer_players.keys() if peer_id == -1 else [peer_id]
	for recipient: int in recipients:
		var permitted := _replication_arguments_for_peer(method,arguments,recipient)
		if not permitted.is_empty():
			_replication_queue.append({"method":method,"arguments":permitted.duplicate(true),"peer_id":recipient})

func _replication_arguments_for_peer(method: String, arguments: Array, peer_id: int) -> Array:
	if not _peer_players.has(peer_id): return []
	# Until a detection provider exists, enemy visibility is not established.
	# Projectile payload projection remains frozen: withhold rather than invent a schema.
	if method in ["_receive_projectile_events","_receive_weapon_fires"]: return []
	if method == "_receive_unit_structures":
		var structures: Array[Dictionary] = []
		for structure: Dictionary in arguments[0]:
			if _authoritative_units.has(structure.unit_id) and _authoritative_units[structure.unit_id].owner_player_id == _peer_players[peer_id]:
				structures.append(structure)
		return [structures] if not structures.is_empty() else []
	if method == "_receive_unit_snapshot":
		return arguments if int(arguments[0].team_id) == COMBAT_CONFIG.player_team_id else []
	if method in ["_receive_unit_positions","_receive_unit_orientations","_receive_unit_stops","_receive_move_targets","_receive_move_paths"]:
		var ids: Array[int] = []
		var values: Array = arguments[1].duplicate()
		values.clear()
		for index: int in arguments[0].size():
			var id: int = arguments[0][index]
			if _authoritative_units.has(id) and _authoritative_units[id].team_id == COMBAT_CONFIG.player_team_id:
				ids.append(id)
				values.append(arguments[1][index])
		return [ids,values] if not ids.is_empty() else []
	if method == "_receive_unit_death":
		return arguments if _authoritative_units.has(arguments[0]) and _authoritative_units[arguments[0]].team_id == COMBAT_CONFIG.player_team_id else []
	return arguments


func _flush_replication() -> void:
	var messages := _replication_queue
	_replication_queue = []
	for message: Dictionary in messages:
		if multiplayer.get_peers().is_empty():
			continue
		if message.peer_id == -1:
			callv("rpc", [StringName(message.method)] + message.arguments)
		elif multiplayer.get_peers().has(message.peer_id):
			callv("rpc_id", [message.peer_id, StringName(message.method)] + message.arguments)


func _ensure_deployment_ready() -> bool:
	if deployment.is_ready():
		return true
	var config: DeploymentConfig = DEPLOYMENT_CONFIG
	if not legacy_combat_fixture_enabled:
		config = DEPLOYMENT_CONFIG.duplicate()
		config.catalog = []
		for entry: Dictionary in DEPLOYMENT_CONFIG.catalog:
			if entry.config_id != "test.rifle": continue
			var active_entry := entry.duplicate()
			active_entry.definition = _weapon_presets[0]
			config.catalog.append(active_entry)
	var error := deployment.initialize(config, MOVEMENT_CONFIG, MovementSimulation.MAP_DEFINITION, timeline.tick_hz)
	if not error.is_empty():
		push_error("Deployment configuration rejected: " + error)
		return false
	return true


# Server-only binding API for the existing command/target layer, never UI identity.
func bind_weapon_target(sender_peer: int, unit_id: int, instance_id: String, target_id: int) -> bool:
	if not multiplayer.is_server(): return false
	if not _authoritative_units.has(unit_id) or not _authoritative_units.has(target_id): return false
	var owner: UnitState = _authoritative_units[unit_id]
	var target: UnitState = _authoritative_units[target_id]
	if owner.owner_peer_id != sender_peer or not _peer_players.has(sender_peer) or owner.owner_player_id != _peer_players[sender_peer] or target.team_id == owner.team_id: return false
	# No production detection provider yet; an enemy ID is not visibility proof.
	if not legacy_combat_fixture_enabled: return false
	for instance: RuntimeWeaponInstance in owner.runtime_weapons:
		if instance.instance_id == instance_id:
			instance.bind_target(AttackTarget.unit(target))
			return true
	return false


func request_deployment(config_id: String, point_id: String, destination: Vector3) -> void:
	if not multiplayer.is_server() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_submit_deployment.rpc_id(1, config_id, point_id, destination)


func request_cancel_deployment(order_id: int) -> void:
	if not multiplayer.is_server() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_submit_cancel_deployment.rpc_id(1, order_id)


func request_buy_deployment(config_id: String, point_id: String, request_id: int) -> void:
	if not multiplayer.is_server() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_submit_buy_deployment.rpc_id(1, config_id, point_id, request_id)


func request_edit_deployment(action: String, order_id: int, destination: Vector3, request_id: int, mode: int = MovementSimulation.MoveMode.BASIC) -> void:
	if not multiplayer.is_server() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_submit_edit_deployment.rpc_id(1, action, order_id, destination, request_id, mode)


@rpc("any_peer", "call_remote", "reliable")
func _submit_buy_deployment(config_id: String, point_id: String, request_id: int) -> void:
	_queue_deployment_request({"type":"buy", "config_id":config_id,"point_id":point_id,"request_id":request_id})


@rpc("any_peer", "call_remote", "reliable")
func _submit_edit_deployment(action: String, order_id: int, destination: Vector3, request_id: int, mode: int = MovementSimulation.MoveMode.BASIC) -> void:
	_queue_deployment_request({"type":"edit","action":action,"order_id":order_id,"destination":destination,"request_id":request_id,"mode":mode})


@rpc("any_peer", "call_remote", "reliable")
func _submit_deployment(config_id: String, point_id: String, destination: Vector3) -> void:
	_queue_deployment_request({"type": "order", "config_id": config_id, "point_id": point_id, "destination": destination})


@rpc("any_peer", "call_remote", "reliable")
func _submit_cancel_deployment(order_id: int) -> void:
	_queue_deployment_request({"type": "cancel", "order_id": order_id})


func _queue_deployment_request(request: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender) or not _peer_players.has(sender):
		return
	request.peer_id = sender
	request.player_id = _peer_players[sender]
	_pending_deployment_requests.append(request)


func _consume_deployment_requests(connected_peers: PackedInt32Array) -> void:
	var requests := _pending_deployment_requests
	_pending_deployment_requests = []
	for request: Dictionary in requests:
		if not connected_peers.has(request.peer_id) or _peer_players.get(request.peer_id, 0) != request.player_id:
			continue
		var result: Dictionary
		if request.type == "order":
			result = deployment.request_order(request.player_id, request.config_id, request.point_id, request.destination)
		elif request.type == "buy":
			result = deployment.buy_order(request.player_id, request.config_id, request.point_id)
		elif request.type == "edit":
			match request.action:
				"pickup": result = deployment.pickup_order(request.player_id, request.order_id)
				"place": result = deployment.place_order(request.player_id, request.order_id, request.destination, request.get("mode", MovementSimulation.MoveMode.BASIC))
				"cancel": result = deployment.cancel_order(request.player_id, request.order_id)
				_: result = {"ok":false,"reason":"invalid deployment action"}
		elif request.type == "cancel":
			result = deployment.cancel_order(request.player_id, request.order_id)
		else:
			result = {"ok":false,"reason":"invalid deployment action"}
		result.request_type = request.type
		result.request_id = request.get("request_id", 0)
		# Always return authoritative state, including on refusal, for UI recovery.
		_queue_replication("_receive_deployment_state", [deployment.export_player(request.player_id)], request.peer_id)
		_queue_replication("_receive_deployment_result", [result], request.peer_id)


@rpc("authority", "call_remote", "reliable")
func _receive_deployment_state(state: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	local_deployment_state = state.duplicate(true)
	deployment_state_received.emit(state.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func _receive_deployment_result(result: Dictionary) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() == 1:
		deployment_result_received.emit(result.duplicate(true))


func _spawn_deployment(order: Dictionary, position: Vector3, entry: Dictionary, point: Dictionary) -> int:
	var peer_id := 0
	for peer: int in _peer_players:
		if _peer_players[peer] == order.player_id:
			peer_id = peer
	var state := UnitState.new(_next_unit_id, peer_id, position)
	_next_unit_id += 1
	state.owner_player_id = order.player_id
	state.configure(deployment.export_player(order.player_id).faction_id, entry.definition)
	state.yaw = point.yaw
	state.generated_tick = timeline.tick
	_authoritative_units[state.unit_id] = state
	_movement.add_unit(state)
	_combat.add_unit(state)
	var movement := _movement.deploy_move(state, order.destination, order.move_mode, entry.width)
	# Existing v1 unit/path state and spawn event suffice; economic/order state is
	# deliberately absent from the frozen replay format.
	timeline.append("event", "spawn", ReplayFormat.unit_state(state, _movement))
	_queue_replication("_receive_unit_snapshot", [_presentation_snapshot(state)])
	var ids: Array[int] = [state.unit_id]
	if peer_id != 0:
		if _movement._targets.has(state.unit_id):
			_queue_replication("_receive_move_targets", [ids, _movement.move_targets(ids)], peer_id)
			_queue_replication("_receive_move_paths", [ids, _movement.move_paths(ids)], peer_id)
		_queue_replication("_receive_deployment_result", [{"ok":true,"request_id":0,"request_type":"generated","order_id":order.order_id,"unit_id":state.unit_id,"generated_tick":timeline.tick,"notice":movement.notice}], peer_id)
	return state.unit_id
