extends Node

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
var _next_unit_id: int = 1
var _authoritative_units: Dictionary[int, UnitState] = {}
var _movement := MovementSimulation.new(MOVEMENT_CONFIG)
var _pending_positions: Dictionary[int, Vector3] = {}
var _replication_elapsed: float = 0.0
var _combat := CombatSimulation.new(MovementSimulation.MAP_DEFINITION)
var _rebels_initialized: bool = false
var _player_spawn_index: int = 1


func _ready() -> void:
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

	_initialize_rebels()
	set_physics_process(true)
	print("Dedicated server started on port %d." % port)
	return true


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
	if not multiplayer.is_server():
		return

	# Reliable ordered snapshots carry current team/health before subsequent combat events.
	for snapshot: Dictionary in live_snapshots():
		_receive_unit_snapshot.rpc_id(peer_id, snapshot)

	for _index: int in MOVEMENT_CONFIG.units_per_peer:
		var unit_id := _next_unit_id
		_next_unit_id += 1
		var spawn: Variant = _movement.resolve_spawn_position(MOVEMENT_CONFIG.spawn_position(_player_spawn_index))
		_player_spawn_index += 1
		if spawn == null:
			push_error("No walkable spawn position for unit %d." % unit_id)
			continue
		var position: Vector3 = spawn
		var state := UnitState.new(unit_id, peer_id, position)
		state.configure(COMBAT_CONFIG.player_team_id, COMBAT_CONFIG.player_definitions[_index % COMBAT_CONFIG.player_definitions.size()])
		_authoritative_units[unit_id] = state
		_movement.add_unit(state)
		_combat.add_unit(state)
		print("Authoritative unit %d created. Owner peer: %d" % [unit_id, peer_id])
		_receive_unit_snapshot.rpc(state.snapshot())


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
	unit_spawn_received.emit(state["unit_id"], state["owner_peer_id"], state["position"])
	unit_type_received.emit(state["unit_id"], state["unit_type"])
	unit_armament_received.emit(state["unit_id"], state["armed"])
	unit_combat_state_received.emit(state["unit_id"], state["team_id"], state["maximum_health"], state["health"])
	var ids: Array[int] = [state["unit_id"]]
	var yaws: Array[float] = [state["yaw"]]
	unit_orientations_received.emit(ids, yaws)


@rpc("authority", "call_remote", "reliable")
func _receive_combat_shot(shot: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	combat_shot_received.emit(shot["start"], shot["end"])
	var id: int = shot["target_id"]
	# Health updates do not create units.
	unit_combat_state_received.emit(id, -1, -1.0, shot["health"])


@rpc("authority", "call_remote", "reliable")
func _receive_unit_death(unit_id: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	unit_death_received.emit(unit_id)


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
	var result := _apply_stop(unit_ids, sender)
	if result["unit_ids"].is_empty():
		return
	_receive_unit_stops.rpc(result["unit_ids"], result["positions"])
	_receive_unit_orientations.rpc(result["unit_ids"], _unit_yaws(result["unit_ids"]))
	print("Stop accepted: peer %d, units %s" % [sender, result["unit_ids"]])


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
	unit_stops_received.emit(unit_ids, positions)


@rpc("any_peer", "call_remote", "reliable")
func _submit_group_move(unit_ids: Array[int], target_position: Vector3, mode: int = MovementSimulation.MoveMode.BASIC, facing: Vector3 = Vector3.ZERO) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender):
		return
	var result := _movement.request_group_move(unit_ids, sender, target_position, mode, facing)
	if not result["rejection"].is_empty():
		print("Group move rejected: peer %d: %s" % [sender, result["rejection"]])
		return
	print("Group move accepted: peer %d, units %s" % [sender, result["unit_ids"]])
	var accepted_ids: Array[int] = result["unit_ids"]
	_receive_move_targets.rpc_id(sender, accepted_ids, _movement.move_targets(accepted_ids))
	_receive_move_paths.rpc_id(sender, accepted_ids, _movement.move_paths(accepted_ids))
	if not result["failed_ids"].is_empty():
		print("Group move kept old commands for unreachable units: %s" % [result["failed_ids"]])
	set_physics_process(true)


@rpc("any_peer", "call_remote", "reliable")
func _submit_move(unit_id: int, target_position: Vector3, mode: int = MovementSimulation.MoveMode.BASIC) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender):
		return
	var rejection := _movement.request_move(unit_id, sender, target_position, mode)
	if not rejection.is_empty():
		print("Move rejected: peer %d, unit %d: %s" % [sender, unit_id, rejection])
		return
	print("Move accepted: peer %d, unit %d, target %s" % [sender, unit_id, target_position])
	var accepted_ids: Array[int] = [unit_id]
	_receive_move_targets.rpc_id(sender, accepted_ids, _movement.move_targets(accepted_ids))
	_receive_move_paths.rpc_id(sender, accepted_ids, _movement.move_paths(accepted_ids))
	set_physics_process(true)


@rpc("authority", "call_remote", "reliable")
func _receive_move_targets(unit_ids: Array[int], positions: Array[Vector3]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if unit_ids.size() != positions.size():
		return
	unit_move_targets_received.emit(unit_ids, positions)


@rpc("authority", "call_remote", "reliable")
func _receive_move_paths(unit_ids: Array[int], paths: Array[PackedVector3Array]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if unit_ids.size() != paths.size():
		return
	unit_move_paths_received.emit(unit_ids, paths)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_movement.update_attack_engagement(_combat)
	_pending_positions.merge(_movement.advance(delta), true)
	# A target entered range during this tick: park before applying firing eligibility.
	_movement.update_attack_engagement(_combat)
	var combat_result := _combat.advance(delta, _movement)
	if not multiplayer.get_peers().is_empty():
		for shot: Dictionary in combat_result["shots"]:
			_receive_combat_shot.rpc(shot)
	for id: int in combat_result["deaths"]:
		_authoritative_units.erase(id)
		_pending_positions.erase(id)
		if not multiplayer.get_peers().is_empty():
			_receive_unit_death.rpc(id)
	_replication_elapsed += delta
	if _replication_elapsed >= MOVEMENT_CONFIG.replication_interval or not _movement.has_active_moves():
		if not _pending_positions.is_empty() and not multiplayer.get_peers().is_empty():
			var unit_ids: Array[int] = []
			var positions: Array[Vector3] = []
			for unit_id: int in _pending_positions:
				unit_ids.append(unit_id)
				positions.append(_pending_positions[unit_id])
			# Reliable ordered delivery also preserves spawn-before-position ordering.
			_receive_unit_positions.rpc(unit_ids, positions)
			_receive_unit_orientations.rpc(unit_ids, _unit_yaws(unit_ids))
		_pending_positions.clear()
		_replication_elapsed = 0.0


@rpc("authority", "call_remote", "reliable")
func _receive_unit_positions(unit_ids: Array[int], positions: Array[Vector3]) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if unit_ids.size() != positions.size():
		return
	unit_positions_received.emit(unit_ids, positions)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: %d" % peer_id)
	if multiplayer.is_server():
		_movement.stop_owner(peer_id)


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
	unit_orientations_received.emit(unit_ids, yaws)
