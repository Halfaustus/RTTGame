extends Node

signal tick_completed(tick: int, records: Array[Dictionary])

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
const MOVEMENT_CONFIG: MovementConfig = preload("res://data/prototype_movement.tres")
const COMBAT_CONFIG: CombatConfig = preload("res://data/prototype_combat.tres")

# Only the dedicated server writes authoritative unit state.
var presentation := PresentationFeed.new()
var timeline := SimulationTimeline.new(Engine.physics_ticks_per_second)
var _replication_queue: Array[Dictionary] = []
var _pending_sessions: Array[Dictionary] = []
var _pending_commands: Array[Dictionary] = []
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
var _rebels_initialized: bool = false
var _player_spawn_index: int = 1


func _ready() -> void:
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
	timeline.append("event", "player_join", {"player_id": player_id, "peer_id": peer_id})
	# Keep current peer ownership for control; the match player ID is archival identity.
	if multiplayer.get_peers().has(peer_id):
		for snapshot: Dictionary in live_snapshots():
			_queue_replication("_receive_unit_snapshot", [snapshot], peer_id)
	for index: int in MOVEMENT_CONFIG.units_per_peer:
		var unit_id := _next_unit_id
		_next_unit_id += 1
		var spawn: Variant = _movement.resolve_spawn_position(MOVEMENT_CONFIG.spawn_position(_player_spawn_index))
		_player_spawn_index += 1
		if spawn == null:
			push_error("No walkable spawn position for unit %d." % unit_id)
			continue
		var state := UnitState.new(unit_id, peer_id, spawn)
		state.owner_player_id = player_id
		state.configure(COMBAT_CONFIG.player_team_id, COMBAT_CONFIG.player_definitions[index % COMBAT_CONFIG.player_definitions.size()])
		_authoritative_units[unit_id] = state
		_movement.add_unit(state)
		_combat.add_unit(state)
		timeline.append("event", "spawn", ReplayFormat.unit_state(state, _movement))
		print("Authoritative unit %d created. Owner peer: %d; match player: %d" % [unit_id, peer_id, player_id])
		if not multiplayer.get_peers().is_empty():
			_queue_replication("_receive_unit_snapshot", [state.snapshot()])


func _initialize_rebels() -> void:
	if _rebels_initialized:
		return
	_rebels_initialized = true
	for requested: Vector3 in COMBAT_CONFIG.rebel_positions:
		var spawn: Variant = _movement.resolve_spawn_position(requested)
		if spawn == null:
			push_error("No walkable rebel spawn.")
			continue
		var state := UnitState.new(_next_unit_id, 0, spawn)
		_next_unit_id += 1
		state.configure(COMBAT_CONFIG.rebel_team_id, COMBAT_CONFIG.rebel_definition)
		_authoritative_units[state.unit_id] = state
		_movement.add_unit(state)
		_combat.add_unit(state)


func live_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for state: UnitState in _authoritative_units.values():
		if state.health > 0.0:
			snapshots.append(state.snapshot())
	return snapshots


@rpc("authority", "call_remote", "reliable")
func _receive_unit_snapshot(state: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	presentation.apply_live_unit(state)


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
		# Remove any older buffered position before broadcasting the current stop position.
		_pending_positions.erase(unit_id)
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
	timeline.begin_tick()
	_consume_sessions(connected_peers)
	timeline.enter_phase("commands")
	_consume_commands(connected_peers)
	timeline.enter_phase("movement")
	var delta := timeline.seconds_per_tick()
	for id: int in _movement.active_command_ids():
		_dirty_units[id] = true
	_movement.update_attack_engagement(_combat)
	var changed := _movement.advance(delta)
	_pending_positions.merge(changed, true)
	for id: int in changed:
		_dirty_units[id] = true
	# A target entered range during this tick: park before applying firing eligibility.
	_movement.update_attack_engagement(_combat)
	timeline.enter_phase("combat")
	var combat_result := _combat.advance(delta, _movement)
	for shot: Dictionary in combat_result["shots"]:
		_dirty_units[shot.target_id] = true
		var recorded_shot := shot.duplicate(true)
		recorded_shot.start = [shot.start.x, shot.start.y, shot.start.z]
		recorded_shot.end = [shot.end.x, shot.end.y, shot.end.z]
		timeline.append("event", "shot", recorded_shot)
		if not multiplayer.get_peers().is_empty():
			_queue_replication("_receive_combat_shot", [shot])
	for id: int in combat_result["deaths"]:
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
	_replication_queue.append({"method": method, "arguments": arguments.duplicate(true), "peer_id": peer_id})


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
