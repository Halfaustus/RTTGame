extends Node

signal unit_spawn_received(unit_id: int, owner_peer_id: int, position: Vector3)
signal unit_positions_received(unit_ids: Array[int], positions: Array[Vector3])
signal unit_move_targets_received(unit_ids: Array[int], positions: Array[Vector3])
signal unit_move_paths_received(unit_ids: Array[int], paths: Array[PackedVector3Array])

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 16
const MOVEMENT_CONFIG: MovementConfig = preload("res://data/prototype_movement.tres")

# Only the dedicated server writes authoritative unit state.
var _next_unit_id: int = 1
var _authoritative_units: Dictionary[int, UnitState] = {}
var _movement := MovementSimulation.new(MOVEMENT_CONFIG)
var _pending_positions: Dictionary[int, Vector3] = {}
var _replication_elapsed: float = 0.0


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

	# Catch up the new client before broadcasting its own unit to everyone.
	for existing_unit_id: int in _authoritative_units:
		var state := _authoritative_units[existing_unit_id]
		_receive_unit_spawn.rpc_id(
			peer_id, existing_unit_id, state.owner_peer_id, state.position
		)

	for _index: int in MOVEMENT_CONFIG.units_per_peer:
		var unit_id := _next_unit_id
		_next_unit_id += 1
		var spawn: Variant = _movement.resolve_spawn_position(MOVEMENT_CONFIG.spawn_position(unit_id))
		if spawn == null:
			push_error("No walkable spawn position for unit %d." % unit_id)
			continue
		var position: Vector3 = spawn
		var state := UnitState.new(unit_id, peer_id, position)
		_authoritative_units[unit_id] = state
		_movement.add_unit(state)
		print("Authoritative unit %d created. Owner peer: %d" % [unit_id, peer_id])
		_receive_unit_spawn.rpc(unit_id, peer_id, position)


@rpc("authority", "call_remote", "reliable")
func _receive_unit_spawn(unit_id: int, owner_peer_id: int, position: Vector3) -> void:
	# NetworkManager retains the default server authority (peer 1).
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	unit_spawn_received.emit(unit_id, owner_peer_id, position)


func request_move(unit_id: int, target_position: Vector3) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_submit_move.rpc_id(1, unit_id, target_position)


func request_moves(unit_ids: Array[int], target_position: Vector3) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_submit_group_move.rpc_id(1, unit_ids, target_position)


@rpc("any_peer", "call_remote", "reliable")
func _submit_group_move(unit_ids: Array[int], target_position: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender):
		return
	var result := _movement.request_group_move(unit_ids, sender, target_position)
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
func _submit_move(unit_id: int, target_position: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender):
		return
	var rejection := _movement.request_move(unit_id, sender, target_position)
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
	_pending_positions.merge(_movement.advance(delta), true)
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
		_pending_positions.clear()
		_replication_elapsed = 0.0
	if not _movement.has_active_moves():
		set_physics_process(false)


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
