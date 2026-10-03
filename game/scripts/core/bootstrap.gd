extends Node


func _ready() -> void:
	if "--server" in OS.get_cmdline_user_args():
		_start_server()
	else:
		_start_client()


func _start_server() -> void:
	var success := NetworkManager.start_server()

	if not success:
		push_error("Dedicated server startup failed.")
		get_tree().quit(1)


func _start_client() -> void:
	var success := NetworkManager.connect_to_server()

	if not success:
		push_error("Client startup failed.")
