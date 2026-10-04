extends SceneTree

const CONFIG = preload("res://data/prototype_deployment.tres")
const MOVEMENT = preload("res://data/prototype_movement.tres")
const MAP = preload("res://data/prototype_map.tres")
var checks := 0
var failures := 0
var requests: Array[Dictionary] = []
var economy: DeploymentEconomy
var ui: DeploymentUI
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL 0.5C: "+label)
func respond() -> Dictionary:
	var request: Dictionary = requests.pop_front()
	var result: Dictionary
	match request.action:
		"buy": result = economy.buy_order(1,request.payload.config_id,request.payload.point_id)
		"place": result = economy.place_order(1,request.payload.order_id,request.payload.destination)
		"cancel": result = economy.cancel_order(1,request.payload.order_id)
		"pickup": result = economy.pickup_order(1,request.payload.order_id)
	result.request_id = request.request_id
	ui.apply_state(economy.export_player(1))
	ui.apply_result(result)
	return result
func run() -> void:
	economy = DeploymentEconomy.new()
	check(economy.initialize(CONFIG,MOVEMENT,MAP,60).is_empty(),"economy initialization")
	economy.register_player(1,1,0)
	economy.register_player(2,1,0)
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	ui = world._deployment_ui
	ui._transport_enabled = false
	ui.request_sent.connect(func(action: String,payload: Dictionary,id: int): requests.append({"action":action,"payload":payload,"request_id":id}))
	ui.apply_state(economy.export_player(1))
	ui.buy("test.rifle")
	var a: int = respond().order_id
	ui.place(Vector3(10,0,110))
	respond()
	await process_frame
	var button: Button = ui._purchase_buttons["test.rifle"]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = button.get_global_rect().get_center()
	root.push_input(click,true)
	economy.begin_tick(1)
	ui.apply_state(economy.export_player(1))
	await process_frame
	click.pressed = false
	root.push_input(click,true)
	check(requests.size() == 1,"purchase survives countdown snapshot between mouse press and release")
	check(is_instance_valid(button) and button == ui._purchase_buttons["test.rifle"],"purchase button identity remains stable")
	var b: int = respond().order_id
	ui.buy("test.rifle")
	check(requests.is_empty() and ui.held_id == b,"only held card blocks buying")
	ui.place(Vector3(12,0,110))
	respond()
	check(ui._markers.size() == 2 and ui._markers[a] != ui._markers[b],"independent order markers")
	check(economy._orders[a].completion_tick == 180 and economy._orders[b].completion_tick == 181,"independent countdown deadlines")
	check(economy.card_counts(1,"test.rifle") == {"present":0,"pending":2} and economy.export_player(1).balance == 700,"separate costs and reservations")
	check(economy.current_upkeep(1) == 0,"pending orders do not pay upkeep")
	check(economy.export_player(2).orders.is_empty() and not economy.cancel_order(2,a).ok and not economy.pickup_order(2,b).ok,"foreign orders unavailable and unactionable")
	var order_marker := ui._markers[a]
	check(order_marker.is_order and order_marker.style == UnitMarker.STYLE and is_equal_approx(order_marker.modulate.r,order_marker.style.order_brightness),"shared marker style with order darkening")
	check(order_marker.text.is_empty() and order_marker.member_count == -1,"order has no actual unit state or permanent text")
	ui._process(0)
	ui._markers[a].cancel_requested.emit()
	check(requests.size() == 1 and requests[0].payload.order_id == a,"direct right cancellation targets own order")
	respond()
	check(not ui._markers.has(a) and ui._markers.has(b) and economy._orders[b].status == "countdown","cancel A leaves B and marker intact")
	check(economy.export_player(1).balance == 850 and economy.card_counts(1,"test.rifle").pending == 1,"refund and slot isolated")
	check(not economy.cancel_order(1,a).refunded and economy.export_player(1).balance == 850,"repeat cancel no duplicate refund")
	ui.pickup(b)
	respond()
	check(ui.held_id == b and not ui._markers.has(b) and not economy._orders[b].has("completion_tick"),"pickup pauses own countdown and replaces marker with ghost")
	ui._process(0)
	check(ui._ghost.visible and ui._ghost.mouse_filter == Control.MOUSE_FILTER_IGNORE,"held marker cannot swallow placement clicks")
	economy.begin_tick(2)
	ui.place(Vector3(14,0,110))
	respond()
	check(economy._orders[b].completion_tick == 182 and ui._markers.has(b),"replacement restarts full countdown")
	ui.buy("test.unarmed")
	var c: int = respond().order_id
	economy.begin_tick(3)
	ui.place(Vector3(16,0,110))
	respond()
	var occupied: Dictionary[int,UnitState] = {}
	var generated_ids: Array[int] = []
	var spawn := func(order: Dictionary,position: Vector3,entry: Dictionary,_point: Dictionary) -> int:
		var id := 100+generated_ids.size()
		var state := UnitState.new(id,1,position)
		state.owner_player_id = 1
		state.configure(1,entry.definition)
		occupied[id] = state
		generated_ids.append(id)
		return id
	economy.begin_tick(181)
	economy.execute_deployments(occupied,spawn)
	check(generated_ids.is_empty(),"other order completion not premature")
	economy.begin_tick(182)
	economy.execute_deployments(occupied,spawn)
	check(generated_ids.size() == 1 and economy._orders[c].status == "countdown","B generation does not prematurely complete C")
	economy.begin_tick(183)
	economy.execute_deployments(occupied,spawn)
	check(generated_ids.size() == 2 and economy._orders[b].unit_id != economy._orders[c].unit_id,"parallel orders generate distinct units")
	ui.apply_state(economy.export_player(1))
	check(ui._markers.is_empty(),"generated order markers removed")
	check(economy.card_counts(1,"test.rifle") == {"present":1,"pending":0} and economy.card_counts(1,"test.unarmed").present == 1,"reservations atomically become live cards")
	check(is_equal_approx(economy.current_upkeep(1),190*0.05/12),"each spawned unit upkeep registered once")
	economy.advance_to_tick(300)
	check(is_equal_approx(economy.export_player(1).balance,835-190*0.05/12),"combined income and independent upkeep")
	economy.remove_live_unit(economy._orders[b].unit_id)
	check(economy.card_counts(1,"test.rifle").present == 0 and is_equal_approx(economy.current_upkeep(1),40*0.05/12),"remove unit stops upkeep and releases only own card")
	var base: Vector3 = world._ground_at(root.get_visible_rect().size/2)+Vector3.UP*0.5
	for id: int in [201,202,203]:
		world.presentation_source.apply_live_unit({"unit_id":id,"owner_peer_id":1 if id != 203 else 2,"owner_player_id":1 if id != 203 else 2,"position":base+Vector3.RIGHT*(id-201),"unit_type":0,"armed":true,"team_id":1,"maximum_health":40,"health":40,"yaw":0.0,"definition_id":"res://data/unit_stationary.tres","member_count":8})
	world._process(0)
	check(world._unit_markers.size() == 3 and world._unit_markers[201].member_count == 8,"live unit markers and actual member count")
	check(world._unit_markers[201].style == order_marker.style,"orders and units share geometry and glyph configuration")
	check(world._unit_markers[201].modulate == Color.WHITE,"live unit not darkened")
	check(world._unit_markers[201].get_node("LeftStatusSlots").get_child_count() == 0 and world._unit_markers[201].get_node("RightStatusSlots").get_child_count() == 0,"status indicators deferred with empty layout hooks")
	check(world._unit_markers[201].style.color_for(1) != world._unit_markers[203].style.color_for(2),"match player colors distinguish allied ownership")
	var marker: UnitMarker = world._unit_markers[201]
	var original := marker.size
	var screen := marker.position
	world._camera.position.y += 10
	world._process(0)
	check(marker.size == original and marker.scale == Vector2.ONE,"camera zoom does not scale marker")
	world._visual_units[201].position += Vector3.RIGHT*2
	world._process(0)
	check(marker.position != screen,"marker follows replicated model position")
	check(marker.text.is_empty() and not world._visual_units[201].has_node("HealthBar"),"no permanent detailed text or health bar")
	var held_order: Dictionary = economy.buy_order(1,"test.rifle","ground.west")
	ui.apply_state(economy.export_player(1))
	check(marker.mouse_filter == Control.MOUSE_FILTER_IGNORE,"held order bypasses live marker GUI for map placement")
	ui._ground = func(_position: Vector2): return Vector3(1000,0,1000)
	ui._process(0)
	check(ui._ghost.invalid_destination,"out of bounds uses forbidden symbol rather than red order")
	economy.cancel_order(1,held_order.order_id)
	ui.apply_state(economy.export_player(1))
	check(marker.mouse_filter == Control.MOUSE_FILTER_PASS,"ordinary marker restores normal right-command routing")
	world._fast_move_armed = true
	world._choose_marker(false,false,201)
	check(not world._fast_move_armed and world._selected_units.is_empty(),"marker click exits armed targeting without selection passthrough")
	world._choose_marker(false,false,201)
	check(world._selected_units.has(201) and marker.selected,"marker click selection feedback")
	world._choose_marker(true,false,202)
	check(world._selected_units.size() == 2,"shift marker adds selection")
	world._choose_marker(false,false,201)
	check(world._selected_units.size() == 1 and world._selection_collection.size() == 2,"single marker retains original collection")
	world._cycle_marker_selection(false)
	check(world._selected_units.has(202),"Tab cycles unit")
	world._cycle_marker_selection(true)
	check(world._selected_units.size() == 2,"Shift Tab restores collection")
	world._choose_marker(false,true,201)
	check(world._selected_units.size() == 2 and not world._selected_units.has(203),"double click selects visible owned configuration only")
	world._choose_marker(false,false,201)
	world._on_unit_death_received(201)
	check(not world._unit_markers.has(201) and world._selected_units.has(202),"death clears marker and advances current selection")
	world._on_visual_unit_removed(202)
	check(not world._unit_markers.has(202),"legal visual removal clears marker")
	var replaced: UnitMarkerStyle = UnitMarker.STYLE.duplicate(true)
	replaced.symbols["infantry"] = "R"
	check(replaced.symbol_for(0) == "R" and UnitMarker.STYLE.symbol_for(0) == "I","identification mapping is replaceable")
	var texture := GradientTexture2D.new()
	replaced.textures["infantry"] = texture
	check(replaced.texture_for(0) == texture and UnitMarker.STYLE.texture_for(0) == null,"future artwork can replace glyph through resource alone")
	check(marker.style.symbol_for(0,false) != marker.style.symbol_for(1),"test categories remain distinct")
	ui.reset_connection()
	check(ui._markers.is_empty() and ui.held_id == 0,"disconnect clears private client markers")
	world._reset_replicated_units()
	check(world._unit_markers.is_empty(),"session reset clears all live markers")
	server_checks()
	world.free()
	print("0.5C checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func server_checks() -> void:
	var model = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(model)
	model._ensure_deployment_ready()
	model._movement.initialize_navigation()
	model.deployment.register_player(1,1,0)
	model.deployment.register_player(2,1,0)
	model._peer_players[42] = 1
	model._peer_players[99] = 2
	var a: Dictionary = model.deployment.buy_order(1,"test.rifle","ground.west")
	model.deployment.place_order(1,a.order_id,Vector3(10,0,110))
	var b: Dictionary = model.deployment.buy_order(1,"test.rifle","ground.west")
	model.deployment.place_order(1,b.order_id,Vector3(12,0,110))
	var held: Dictionary = model.deployment.buy_order(2,"test.rifle","ground.east")
	check(a.ok and b.ok and held.ok,"production economy multi orders")
	model._pending_deployment_requests.append({"type":"edit","action":"cancel","order_id":held.order_id,"destination":Vector3.ZERO,"request_id":7,"peer_id":42,"player_id":1})
	model._consume_deployment_requests(PackedInt32Array([42,99]))
	check(model._replication_queue.size() == 2 and model._replication_queue[0].peer_id == 42 and model._replication_queue[0].arguments[0].player_id == 1 and not model._replication_queue[1].arguments[0].ok,"foreign cancel rejected and only sender private state returned")
	model._replication_queue.clear()
	for tick: int in 180: model._run_server_tick(PackedInt32Array([42,99]))
	check(model.deployment._orders[a.order_id].status == "generated" and model.deployment._orders[b.order_id].status == "generated","production pipeline multi generation")
	var state: UnitState = model._authoritative_units[model.deployment._orders[a.order_id].unit_id]
	check(state.members.size() == 8 and model._presentation_snapshot(state).member_count == 8,"purchased squad and live marker metadata")
	check(model._presentation_snapshot(state).owner_player_id == 1 and model._presentation_snapshot(state).definition_id == state.definition.resource_path,"public unit identity uses match player not peer")
	check(not state.snapshot().has("member_count"),"new UI metadata excluded from frozen v1 snapshot")
	model._pending_sessions.append({"type":"leave","peer_id":99})
	model._run_server_tick(PackedInt32Array([42]))
	check(model.deployment._orders[held.order_id].status == "cancelled" and model.deployment.export_player(2).balance == 1000,"disconnect cancels unfinished orders and refunds owner")
	check(model.deployment.card_counts(1,"test.rifle").present == 2,"foreign disconnect leaves live units intact")
	model.free()
