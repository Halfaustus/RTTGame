extends "res://tests/prototype_03b_enet.gd"

var deployment_results: Array[Dictionary] = []
var observed_players: Array[int] = []

func _run() -> void:
	var manager := root.get_node("NetworkManager")
	manager.deployment_result_received.connect(func(result: Dictionary): deployment_results.append(result.duplicate(true)))
	manager.deployment_state_received.connect(func(state: Dictionary):
		if not observed_players.has(state.player_id): observed_players.append(state.player_id))
	await super._run()

func wait_for(condition: Callable, label: String, timeout: float = 30) -> bool:
	var passed := await super.wait_for(condition,label,timeout)
	if passed and label == "two players and original three enemies joined":
		return await _deployment_checks()
	return passed

func _deployment_checks() -> bool:
	if not await super.wait_for(func(): return not network.local_deployment_state.is_empty(),"owner economic snapshot"): return false
	var own_player: int = network.local_deployment_state.player_id
	if role == "observer":
		write("deployment-observer-ready",{"player_id":own_player})
		if not await super.wait_for(func(): return not read("deployment-driver").is_empty(),"deployed unit evidence"): return false
		var driver := read("deployment-driver")
		var id: int = driver.unit_id
		if not await super.wait_for(func(): return world._visual_units.has(id) and world._visual_units[id].position.distance_to(Vector3(-12,0.5,115)) < 0.001,"second client same deployed unit and position"): return false
		if observed_players != [own_player] or not network.local_deployment_state.orders.is_empty() or world._route_points.has(id):
			quit(1); return false
		write("deployment-observer",{"pass":true,"unit_id":id,"position":world._visual_units[id].position,"received_players":observed_players,"owner_peer":world._visual_units[id].owner_peer_id})
		return true
	if not await super.wait_for(func(): return not read("deployment-observer-ready").is_empty(),"observer ready"): return false
	network.request_buy_deployment("test.armored","ground.west",1)
	if not await super.wait_for(func(): return deployment_results.size()==1 and network.local_deployment_state.held_order_id != 0,"buy held order"): return false
	var id: int = deployment_results[0].order_id
	network.request_edit_deployment("place",id,Vector3(-12,0,115),2,1)
	if not await super.wait_for(func(): return deployment_results.size()>=2,"place accepted"): return false
	if not await super.wait_for(func(): return deployment_results.size()>=3 and deployment_results[2].request_type=="generated","server generated after countdown"): return false
	var generated: Dictionary = deployment_results[2]
	if not await super.wait_for(func(): return world._visual_units.has(generated.unit_id) and world._visual_units[generated.unit_id].position.distance_to(Vector3(-12,0.5,115))<0.001 and network.local_deployment_state.orders[0].status=="generated","owner reaches fast destination and generated state"): return false
	var row: Dictionary = network.local_deployment_state.orders[0]
	if row.generated_tick-row.placed_tick != 180 or row.unit_id != generated.unit_id or network.local_deployment_state.cards["test.armored"] != {"present":2,"pending":0} or observed_players != [own_player]:
		quit(1); return false
	write("deployment-driver",{"pass":true,"unit_id":generated.unit_id,"row":row,"state":network.local_deployment_state,"position":world._visual_units[generated.unit_id].position})
	if not await super.wait_for(func(): return read("deployment-observer").get("pass",false),"two clients verified generated unit"): return false
	return true
