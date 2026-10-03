extends SceneTree

const CONFIG = preload("res://data/prototype_deployment.tres")
const MOVEMENT = preload("res://data/prototype_movement.tres")
const MAP = preload("res://data/prototype_map.tres")
var failures := 0
var checks := 0
var units := {}
var generated: Array[int] = []
var next_id := 100

func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS 0.4C: ",label)
	else:
		failures += 1
		push_error("FAIL 0.4C: " + label)

func create(config: DeploymentConfig = CONFIG, map: PrototypeMapDefinition = MAP) -> DeploymentEconomy:
	var service := DeploymentEconomy.new()
	check(service.initialize(config,MOVEMENT,map,60).is_empty(),"configuration")
	service.register_player(1,1,0)
	service.register_player(2,1,0)
	return service

func order(service: DeploymentEconomy, config_id: String = "test.rifle", mode: int = 0) -> int:
	var purchase := service.buy_order(1,config_id,"ground.west")
	check(purchase.ok,"purchase")
	check(service.place_order(1,purchase.order_id,Vector3(10,0,110),mode).ok,"place")
	return purchase.order_id

func spawn(row: Dictionary, position: Vector3, entry: Dictionary, point: Dictionary) -> int:
	var state := UnitState.new(next_id,42,position)
	next_id += 1
	state.configure(1,entry.definition)
	state.owner_player_id = row.player_id
	state.yaw = point.yaw
	units[state.unit_id] = state
	generated.append(row.order_id)
	return state.unit_id

func advance(service: DeploymentEconomy, tick: int) -> void:
	service.advance_to_tick(tick)
	service.execute_deployments(units,spawn)

func _run() -> void:
	var service := create()
	var id := order(service)
	advance(service,179)
	check(units.is_empty() and service.export_player(1).orders[0].remaining_seconds > 0,"no spawn before exact 180 ticks")
	advance(service,180)
	check(units.size() == 1 and service._orders[id].generated_tick == 180,"spawn exactly three seconds")
	check(service.card_counts(1,"test.rifle") == {"pending":0,"present":1} and service.export_player(1).balance == 850.0,"atomic reservation conversion without second cost")
	check(not service.cancel_order(1,id).ok and not service.pickup_order(1,id).ok,"generated order cannot refund or pick up")
	advance(service,181)
	check(units.size() == 1,"no repeated generation")
	units.clear(); generated.clear()
	var blocked_config: DeploymentConfig = CONFIG.duplicate(true)
	blocked_config.spawn_search_radius = 0.5
	service = create(blocked_config)
	var blocker := UnitState.new(9,0,Vector3(-12,0.5,112))
	blocker.configure(2,CONFIG.catalog[0].definition)
	units[9] = blocker
	id = order(service)
	advance(service,180)
	check(service._orders[id].status == "waiting" and service.export_player(1).balance == 850.0 and generated.is_empty(),"enemy occupancy waits without fee/refund or closing point")
	blocker.position.x = -8
	advance(service,194)
	check(generated.is_empty(),"fixed retry cadence")
	advance(service,195)
	check(generated == [id] and service._orders[id].generated_tick == 195 and service._orders[id].completion_tick == 180,"free slot generates without another countdown")
	units.clear(); generated.clear()
	service = create(blocked_config)
	units[9] = blocker
	blocker.position = Vector3(-12,0.5,112)
	var old := order(service)
	advance(service,1)
	var later := order(service)
	advance(service,180)
	units.clear()
	advance(service,181)
	check(generated == [old] and service._orders[later].status == "waiting", "older waiter keeps priority when a later countdown completes between retries")
	units.clear(); generated.clear()
	service = create()
	var ids: Array[int] = [order(service),order(service),order(service)]
	advance(service,180)
	check(generated == ids and units.size() == 3,"same tick ID ordering and three generations")
	var positions: Array[Vector3] = []
	for state: UnitState in units.values(): positions.append(state.position)
	check(positions[0] == Vector3(-12,0.5,112) and positions[1] == Vector3(-13.5,0.5,112),"nearest candidate and stable X/Z tie order")
	var separated := true
	for i: int in positions.size():
		for j: int in range(i+1,positions.size()):
			separated = separated and (absf(positions[i].x-positions[j].x)>=1.05 or absf(positions[i].z-positions[j].z)>=1.05)
	check(separated,"successful spawn immediately occupies slot")
	units.clear(); generated.clear()
	var sized_config: DeploymentConfig = blocked_config.duplicate(true)
	sized_config.catalog[0].width = 3.0
	var corridor: PrototypeMapDefinition = MAP.duplicate(true)
	corridor.obstacles.append(Rect2(-16,110,3.25,4))
	corridor.obstacles.append(Rect2(-11.25,110,3.25,4))
	service = create(sized_config,corridor)
	var large := order(service,"test.armored")
	var small := order(service)
	advance(service,180)
	check(service._orders[large].status == "waiting" and generated == [small],"large footprint blocked but later small order proceeds")
	check(service.find_spawn_position(3,Vector3(-12,0.5,112),units) == null,"search never expands outside fixed radius")
	units.clear()
	service._map.obstacles.clear()
	advance(service,195)
	check(generated == [small,large] and service._orders[large].completion_tick == 180,"waiting retains completion priority")
	units.clear(); generated.clear()
	service = create()
	id = order(service)
	advance(service,100)
	check(service.pickup_order(1,id).ok,"pickup countdown")
	advance(service,300)
	check(generated.is_empty() and service._orders[id].status == "held","held pauses deployment eligibility")
	service.place_order(1,id,Vector3(10,0,110),1)
	advance(service,479)
	check(generated.is_empty(),"replacement requires full new countdown")
	advance(service,480)
	check(service._orders[id].generated_tick == 480 and service._orders[id].move_mode == 1,"replacement mode and exact countdown")
	units.clear(); generated.clear()
	service = create(blocked_config)
	units[9] = blocker
	blocker.position = Vector3(-12,0.5,112)
	id = order(service)
	advance(service,180)
	check(service.pickup_order(1,id).ok and service.cancel_order(1,id).refunded,"pickup waiting and refund")
	check(not service.cancel_order(1,id).refunded and service.export_player(1).balance == 1000.0,"repeat cancel no double refund")
	units.clear()
	advance(service,195)
	check(generated.is_empty(),"cancelled waiting order never spawns")
	service = create()
	id = order(service)
	service.advance_to_tick(180)
	service.cancel_order(1,id)
	service.execute_deployments(units,spawn)
	check(generated.is_empty() and service.card_counts(1,"test.rifle").pending == 0,"cancel before execution wins same tick")
	id = order(service)
	check(not service.place_order(2,id,Vector3(1,0,110)).ok and not service.pickup_order(2,id).ok,"player isolation")
	check(not service.place_order(1,id,Vector3(1,0,110),2).ok,"unsupported deployment mode rejected")
	await _navigation_and_server_checks()
	var file := FileAccess.open("res://../tmp/04c/unit-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("0.4C checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func _navigation_and_server_checks() -> void:
	var nav := StaticNavigationGrid.new()
	check(nav.initialize(MOVEMENT,MAP),"navigation")
	var state := UnitState.new(1,42,Vector3(-12,0.5,112))
	state.configure(1,CONFIG.catalog[0].definition)
	var path := nav.deployment_path(state.position,Vector3(0,0.5,94),false,state)
	check(path.size()>1 and nav.is_position_walkable(path[path.size()-1]) and path[path.size()-1] != Vector3(0,0.5,94),"blocked destination nearest reachable fallback")
	var split: PrototypeMapDefinition = MAP.duplicate(true)
	split.obstacles.append(Rect2(-1,80,2,40))
	nav.initialize(MOVEMENT,split)
	path = nav.deployment_path(state.position,Vector3(12,0.5,112),false,state)
	check(path.size()>1 and path[path.size()-1].x < -1.5,"disconnected destination stays in spawn component")
	var pocket: PrototypeMapDefinition = MAP.duplicate(true)
	pocket.obstacles = [Rect2(-20,80,7.4,40),Rect2(-11.4,80,72,40),Rect2(-12.6,80,1.2,31.4),Rect2(-12.6,112.6,1.2,7.4)]
	var movement := MovementSimulation.new(MOVEMENT)
	movement.initialize_navigation(pocket)
	movement.add_unit(state)
	var stopped := movement.deploy_move(state,Vector3(12,0,112),0,1,pocket)
	check(stopped.target == state.position and not stopped.notice.is_empty() and not movement.has_active_moves(),"no reachable path leaves unit at spawn with notice")
	var model = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(model)
	model._ensure_deployment_ready()
	model._movement.initialize_navigation()
	model.deployment.register_player(1,1,0)
	model._peer_players[42] = 1
	var enemy := UnitState.new(900,0,Vector3(-12,0.5,117))
	enemy.configure(2,CONFIG.catalog[1].definition)
	model._authoritative_units[900] = enemy
	model._movement.add_unit(enemy)
	model._combat.add_unit(enemy)
	var id := order(model.deployment,"test.armored",1)
	for tick: int in 180: model._run_server_tick(PackedInt32Array([42]))
	var row: Dictionary = model.deployment._orders[id]
	check(row.status == "generated" and model._authoritative_units[row.unit_id].generated_tick == 180,"production server generates authoritative unit and actual tick")
	check(model._authoritative_units[row.unit_id].health < model._authoritative_units[row.unit_id].maximum_health,"spawned unit takes immediate normal damage without invulnerability")
	check(model._movement.command_snapshot(row.unit_id).mode == 1 and model.timeline.records[0].type == "spawn","production route/mode and unchanged v1 spawn event")
	check(not model.deployment.cancel_order(1,id).ok,"generation before later cancel wins without refund")
	var final_state: Dictionary = model.deployment.export_player(1)
	model.free()
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	var ui: DeploymentUI = world._deployment_ui
	ui._transport_enabled = false
	var display: Dictionary = final_state.duplicate(true)
	display.orders[0].status = "countdown"
	display.orders[0].remaining_seconds = 1.5
	ui.apply_state(display)
	ui._process(10)
	check(ui.state.orders[0].remaining_seconds == 1.5 and ui._markers[id].text.contains("1.5"),"UI displays server time without local countdown completion")
	display.orders[0].status = "waiting"
	ui.apply_state(display)
	ui._process(0)
	check(not ui._markers[id].disabled and ui._markers[id].text.contains("等待"),"waiting marker can be picked up")
	ui.apply_state(final_state)
	check(not ui._markers.has(id),"generated snapshot removes deployment card")
	world.free()
