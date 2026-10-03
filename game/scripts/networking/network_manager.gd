extends Node

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 16


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func start_server(port: int = DEFAULT_PORT) -> bool:
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


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: %d" % peer_id)
