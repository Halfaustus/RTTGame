extends "res://tests/prototype_04c_enet.gd"

var economy_events: Array[Dictionary] = []

func _run() -> void:
	var manager := root.get_node("NetworkManager")
	manager.deployment_event.connect(func(event: Dictionary): economy_events.append(event.duplicate(true)))
	root.tree_exiting.connect(func():
		if role == "server": write("economy-final",{"state":manager.deployment.export_state(),"events":economy_events}))
	await super._run()

func _deployment_checks() -> bool:
	if not await super._deployment_checks(): return false
	var base_fee := 490.0*0.05/12.0
	if role == "observer":
		var foreign := read("deployment-driver")
		var count_before := deployment_results.size()
		network.request_cancel_deployment(int(foreign.row.order_id))
		network.request_buy_deployment("invalid.configuration","ground.west",40)
		if not await super.wait_for(func(): return deployment_results.size()==count_before+2,"foreign cancellation and illegal purchase responses"): return false
		if deployment_results[count_before].ok or deployment_results[count_before+1].ok or not network.local_deployment_state.orders.is_empty():
			quit(1); return false
		if not await super.wait_for(func(): return read("economy-driver").get("pass",false),"economic loop finished",60): return false
		var evidence := read("economy-driver")
		if not await super.wait_for(func(): return deaths.has(int(evidence.unit_id)) and not world._visual_units.has(int(evidence.unit_id)),"deployed unit death replicated"): return false
		if observed_players != [network.local_deployment_state.player_id] or not is_equal_approx(network.local_deployment_state.upkeep_per_settlement,base_fee):
			quit(1); return false
		write("economy-observer",{"pass":true,"state":network.local_deployment_state,"deaths":deaths})
		return true
	var id: int = network.local_deployment_state.orders[0].unit_id
	if not await super.wait_for(func(): return network.local_deployment_state.last_settlement_tick>=300,"first maintenance boundary"): return false
	if not is_equal_approx(network.local_deployment_state.upkeep_per_settlement,base_fee+1.25) or not is_equal_approx(network.local_deployment_state.last_settlement_upkeep,base_fee+1.25):
		quit(1); return false
	write("economy-first-settlement",{"state":network.local_deployment_state})
	var selected: Array[int] = [id]
	network.request_moves(selected,Vector3(3,0,90),0)
	if not await super.wait_for(func(): return deaths.has(id) and not world._visual_units.has(id),"purchased unit dies under normal combat",50): return false
	if not await super.wait_for(func(): return network.local_deployment_state.cards["test.armored"].present==1 and is_equal_approx(network.local_deployment_state.upkeep_per_settlement,base_fee),"death releases upkeep and card"): return false
	var before: float = network.local_deployment_state.balance
	var result_count := deployment_results.size()
	network.request_buy_deployment("test.armored","ground.west",20)
	if not await super.wait_for(func(): return deployment_results.size()>result_count and network.local_deployment_state.held_order_id>0,"repurchase after death"): return false
	var held: int = network.local_deployment_state.held_order_id
	var paid_balance: float = network.local_deployment_state.balance
	result_count = deployment_results.size()
	network.request_buy_deployment("test.armored","ground.west",21)
	if not await super.wait_for(func(): return deployment_results.size()>result_count,"duplicate held purchase rejected"): return false
	if deployment_results[-1].ok or network.local_deployment_state.held_order_id!=held or network.local_deployment_state.balance<paid_balance:
		quit(1); return false
	network.request_cancel_deployment(held)
	if not await super.wait_for(func(): return network.local_deployment_state.held_order_id==0,"repurchase cancellation refund"): return false
	var refunded_balance: float = network.local_deployment_state.balance
	result_count = deployment_results.size()
	network.request_cancel_deployment(held)
	if not await super.wait_for(func(): return deployment_results.size()>result_count,"repeat cancel response"): return false
	if network.local_deployment_state.balance>refunded_balance+25.0 or network.local_deployment_state.cards["test.armored"].pending!=0:
		quit(1); return false
	if network.local_deployment_state.balance<before or observed_players != [network.local_deployment_state.player_id]:
		quit(1); return false
	write("economy-driver",{"pass":true,"unit_id":id,"state":network.local_deployment_state,"balance_before_repurchase":before})
	if not await super.wait_for(func(): return read("economy-observer").get("pass",false),"second client economic isolation and death"): return false
	return true
