extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS 0.7C: ", label)
	else:
		failures += 1
		push_error("FAIL 0.7C: " + label)

func _run() -> void:
	var network = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(network)
	network._peer_players[42] = 10
	network._peer_players[43] = 11
	var own := UnitState.new(7,42,Vector3.ZERO)
	own.owner_player_id = 10
	var foreign := UnitState.new(8,43,Vector3.ONE)
	foreign.owner_player_id = 11
	network._authoritative_units[7] = own
	network._authoritative_units[8] = foreign
	var command := {"type":"move","peer_id":42,"player_id":10,"unit_ids":[7,8,999]}
	var failure := {"rejection":"invalid position","unit_ids":[],"failed_ids":[7,8,999]}
	var notice: Dictionary = network._command_notice(command,failure)
	check(notice.unit_ids == [7], "notice excludes foreign and unknown identities")
	check(not notice.has("position") and not notice.has("health") and not notice.has("inventory"), "notice contains no private simulation state")
	network._queue_replication("_receive_command_notice",[notice],42)
	check(network._replication_queue.size() == 1 and network._replication_queue[0].peer_id == 42, "notice targets only requester")
	check(network._replication_queue[0].arguments[0].keys().size() == 3, "wire notice is explicit three-field whitelist")
	check(not network._replication_queue[0].arguments[0].has("_recipient_player_id"), "routing identity not serialized")
	network._queue_replication("_receive_command_notice",[notice])
	check(network._replication_queue.size() == 1, "broadcast notice rejected")
	network._queue_replication("_receive_command_notice",[notice],43)
	check(network._replication_queue.size() == 1, "other player destination rejected")
	var success := {"rejection":"","unit_ids":[7],"failed_ids":[]}
	check(network._command_notice(command,success).is_empty(), "ordinary success has no message")
	network._peer_players[42] = 12
	check(network._command_notice(command,failure).is_empty(), "reused peer rejects old player notice")
	network._queue_replication("_receive_command_notice",[notice],42)
	check(network._replication_queue.size() == 1, "queue checks current player identity")
	network._flush_replication()
	check(network._replication_queue.is_empty(), "delivery safely drops changed player notice")
	network._peer_players.erase(42)
	check(network._command_notice(command,failure).is_empty(), "disconnected sender gets no notice")
	network._peer_players[42] = 10
	command.type = "acceptance_module_probe"
	check(network._command_notice(command,failure).is_empty(), "acceptance diagnostics are not general battlefield messages")
	var deployment := DeploymentUI.new()
	deployment.external_messages = true
	root.add_child(deployment)
	deployment._transport_enabled = false
	deployment._message.hide()
	var texts: Array[String] = []
	deployment.battlefield_notice.connect(func(value): texts.append(value))
	deployment._awaiting_id = 3
	deployment.busy = true
	deployment.apply_result({"request_id":3,"ok":false,"reason":"insufficient_points"})
	check(texts.size() == 1 and texts[0].contains("insufficient_points"), "failed deployment feeds battlefield message")
	check(not deployment.busy and not deployment._message.visible, "message routing keeps original acknowledgement flow and hidden left message")
	deployment._awaiting_id = 4
	deployment.apply_result({"request_id":4,"ok":true})
	check(texts.size() == 1, "normal acknowledgement does not produce success text")
	deployment.apply_result({"request_type":"generated","unit_id":7,"notice":"destination_adjusted"})
	check(texts.size() == 2 and texts[1] == "destination_adjusted", "important generation notice feeds right side")
	deployment.reset_connection()
	check(texts.size() == 3 and texts[2].contains("连接已结束"), "connection status is a battlefield notice")
	deployment.free()
	network.free()
	await process_frame
	print("0.7C checks: %d, failures: %d" % [checks,failures])
	quit(0 if failures == 0 else 1)
