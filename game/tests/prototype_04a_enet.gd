extends "res://tests/prototype_03b_enet.gd"

# Reuse the real production movement/combat/recording regression, adding private
# deployment RPC checks before it. No purchase UI or authoritative test spawning.
var results: Array[Dictionary] = []
var state_player_ids: Array[int] = []
var economic_events: Array[Dictionary] = []

func _run() -> void:
	var manager := root.get_node("NetworkManager")
	manager.deployment_result_received.connect(func(result: Dictionary): results.append(result.duplicate(true)))
	manager.deployment_state_received.connect(func(state: Dictionary):
		if not state_player_ids.has(state.player_id):
			state_player_ids.append(state.player_id))
	manager.deployment_event.connect(func(event: Dictionary): economic_events.append(event.duplicate(true)))
	await super._run()

func wait_for(condition: Callable, label: String, timeout: float = 30) -> bool:
	var passed := await super.wait_for(condition, label, timeout)
	if passed and label == "two players and original three enemies joined":
		return await _deployment_checks()
	if passed and label in ["driver commands complete", "second client verified death"]:
		var own_player: int = network.local_deployment_state.player_id
		var state: Dictionary = network.local_deployment_state
		if state_player_ids != [own_player] or state.balance < 1000.0 or state.balance > 1000.0 + int(state.income_through_tick / 300) * 25.0 or state.upkeep_per_settlement <= 0.0:
			push_error("FAIL 0.4A income/private synchronization during combat")
			quit(1)
			return false
		write("economy-" + role + "-final", {"pass":true,"state":network.local_deployment_state,"received_player_ids":state_player_ids})
	return passed

func _deployment_checks() -> bool:
	if not await super.wait_for(func(): return not network.local_deployment_state.is_empty(), "private initial account snapshot"):
		return false
	var own_player: int = network.local_deployment_state.player_id
	if role == "observer":
		write("economy-observer-ready", {"player_id":own_player})
		if not await super.wait_for(func(): return not read("economy-order").is_empty(), "driver order accepted"):
			return false
		var foreign := read("economy-order")
		network.request_cancel_deployment(int(foreign.order_id))
		if not await super.wait_for(func(): return results.size() == 1, "foreign cancel response"):
			return false
		if results[0].ok or network.local_deployment_state.balance != 1000.0 or not network.local_deployment_state.orders.is_empty() or state_player_ids != [own_player]:
			push_error("FAIL 0.4A ENet foreign request or private account isolation")
			quit(1)
			return false
		write("economy-observer", {"pass":true, "state":network.local_deployment_state, "received_player_ids":state_player_ids, "foreign_cancel":results[0]})
		return true
	if not await super.wait_for(func(): return not read("economy-observer-ready").is_empty(), "observer account ready"):
		return false
	network.request_deployment("test.unarmed", "ground.west", Vector3(10,0,110))
	if not await super.wait_for(func(): return results.size() == 1 and network.local_deployment_state.orders.size() == 1, "purchase and private snapshot"):
		return false
	var id: int = results[0].order_id
	if not results[0].ok or network.local_deployment_state.balance != 960.0 or network.local_deployment_state.display_points != 960:
		quit(1)
		return false
	write("economy-order", {"order_id":id,"player_id":own_player})
	if not await super.wait_for(func(): return read("economy-observer").get("pass",false), "foreign account remained isolated"):
		return false
	# Same reliable channel preserves request order; refund is performed only once.
	network.request_cancel_deployment(id)
	network.request_cancel_deployment(id)
	network.request_deployment("invalid", "ground.west", Vector3(10,0,110))
	network.request_deployment("test.rifle", "invalid", Vector3(10,0,110))
	network.request_deployment("test.rifle", "ground.west", Vector3(NAN,0,110))
	if not await super.wait_for(func(): return results.size() == 6 and network.local_deployment_state.balance == 1000.0, "refund and malformed requests"):
		return false
	var ok: bool = results[1].refunded and not results[2].refunded and not results[3].ok and not results[4].ok and not results[5].ok and state_player_ids == [own_player]
	for index: int in 4:
		network.request_deployment("test.armored", "ground.west", Vector3(10,0,110))
	network.request_deployment("test.rifle", "ground.west", Vector3(10,0,110))
	if not await super.wait_for(func(): return results.size() == 11 and network.local_deployment_state.cards["test.armored"].pending == 3, "real RPC card limit and insufficient balance"):
		return false
	ok = ok and results[6].ok and results[7].ok and results[8].ok and not results[9].ok and results[9].reason == "card limit reached" and not results[10].ok and results[10].reason == "insufficient sortie points"
	write("economy-limit", {"pass":ok,"state":network.local_deployment_state,"results":results})
	for index: int in [6,7,8]:
		network.request_cancel_deployment(int(results[index].order_id))
	if not await super.wait_for(func(): return results.size() == 14 and network.local_deployment_state.balance == 1000.0, "all pending orders cancelled without spawning"):
		return false
	write("economy-driver", {"pass":ok,"results":results,"state":network.local_deployment_state,"received_player_ids":state_player_ids})
	if not ok:
		quit(1)
	return ok

func _process(delta: float) -> bool:
	var result := super._process(delta)
	if network != null and role == "server":
		write("economy-server", {"state":network.deployment.export_state(),"events":economic_events})
	return result
