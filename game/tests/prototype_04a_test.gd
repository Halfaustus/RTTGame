extends SceneTree

const CONFIG = preload("res://data/prototype_deployment.tres")
const MOVEMENT = preload("res://data/prototype_movement.tres")
const MAP = preload("res://data/prototype_map.tres")
var failures := 0
var checks := 0
var events: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if value:
		print("PASS 0.4A: ", label)
	else:
		failures += 1
		push_error("FAIL 0.4A: " + label)

func create(config: DeploymentConfig = CONFIG, map: PrototypeMapDefinition = MAP) -> DeploymentEconomy:
	var economy := DeploymentEconomy.new()
	check(economy.initialize(config, MOVEMENT, map, 60).is_empty(), "validated deployment metadata")
	return economy

func buy(economy: DeploymentEconomy, player: int = 1, config: String = "test.armored", point: String = "ground.west") -> Dictionary:
	return economy.request_order(player, config, point, Vector3(10, 0, 110))

func _run() -> void:
	var economy := create()
	economy.event_emitted.connect(func(event: Dictionary): events.append(event))
	check(economy.register_player(1, 1, 0) and economy.register_player(2, 1, 0), "player ID accounts open")
	check(not economy.register_player(1, 2, 0), "duplicate account cannot reset balance or faction")
	economy.register_live_unit(4, 1, CONFIG.catalog[0].definition)
	check(economy.export_player(1).balance == 1000.0, "initial points; test units remain free")
	economy.advance_to_tick(299)
	check(economy.export_player(1).balance == 1000.0, "no early income")
	economy.advance_to_tick(300)
	check(economy.export_player(1).balance == 1023.75, "five-second income and upkeep boundary")
	economy.advance_to_tick(300)
	economy.advance_to_tick(1201)
	check(economy.export_player(1).balance == 1095.0, "catch-up intervals and no duplicate settlement")
	check(economy.register_player(3, 1, 1201), "late account joins at current tick")
	economy.advance_to_tick(1500)
	check(economy.export_player(3).balance == 1025.0, "late player uses global boundary")
	economy.advance_to_tick(1501)
	check(economy.export_player(3).balance == 1025.0, "late player gets income after full interval")
	var order := buy(economy)
	check(order.ok and economy.export_player(1).balance == 818.75, "purchase uses sortie cost, not value")
	var state := economy.export_player(1)
	check(state.orders[0].point_id == "ground.west" and state.orders[0].destination == Vector3(10, 0, 110), "spawn ID separated from destination")
	check(state.cards["test.armored"] == {"present": 1, "pending": 1}, "present plus reservation")
	check(buy(economy).ok and buy(economy).ok and not buy(economy).ok, "card maximum includes free live unit")
	check(buy(economy, 1, "test.rifle").ok, "consume remaining points before insufficient-funds check")
	var before: float = economy.export_player(1).balance
	check(not buy(economy, 1, "test.rifle").ok and economy.export_player(1).balance == before, "insufficient funds atomic rejection")
	check(not economy.cancel_order(2, order.order_id).ok, "foreign cancellation rejected")
	check(economy.cancel_order(1, order.order_id).refunded, "pending cancellation refunds full paid cost")
	var refunded: float = economy.export_player(1).balance
	var event_count := events.size()
	check(not economy.cancel_order(1, order.order_id).refunded and economy.export_player(1).balance == refunded and events.size() == event_count, "repeat cancel neither refund nor event")
	var replacement := buy(economy)
	check(replacement.ok and replacement.order_id > order.order_id, "cancel releases slot and ID never reused")
	economy.remove_live_unit(4)
	check(economy.card_counts(1, "test.armored").present == 0 and buy(economy, 2).ok, "death releases live count; independent limits")
	check(economy.export_player(3).orders.is_empty(), "accounts never expose foreign orders")
	check(not buy(economy, 999).ok and not buy(economy, 1, "invalid").ok and not buy(economy, 1, "test.rifle", "invalid").ok, "unknown identities and IDs rejected")
	check(not economy.request_order(2, "test.rifle", "ground.west", Vector3(NAN, 0, 0)).ok and not economy.request_order(2, "test.rifle", "ground.west", Vector3(999, 0, 100)).ok, "invalid destinations rejected")
	check(not economy.cancel_order(1, -1).ok, "invalid cancellation rejected")
	var fractional := buy(economy, 3, "test.unarmed")
	check(fractional.ok and economy.export_player(3).balance == 985.0 and economy.export_player(3).display_points == 985, "integer purchase score preserved")
	check(economy.upkeep_per_minute("test.armored") == 15.0 and is_equal_approx(economy.upkeep_per_minute("test.rifle"), 7.5), "upkeep still permits fractional quote")
	economy.advance_to_tick(5101)
	check(economy.export_player(3).balance == 1285.0, "one minute income without maintenance charge")
	state = economy.export_player(3)
	state.orders[0].status = "generated"
	state.cards.clear()
	check(economy.export_player(3).orders[0].status == "pending", "export isolation; no actual generation")
	check(economy.static_spawn_available("test.armored", "ground.west"), "static spawn clearance")
	var blocked: PrototypeMapDefinition = MAP.duplicate(true)
	blocked.obstacles.append(Rect2(-12.1, 111.9, 0.2, 0.2))
	var waiting := create(CONFIG, blocked)
	waiting.register_player(1, 1, 0)
	check(not waiting.static_spawn_available("test.armored", "ground.west") and buy(waiting).ok, "blocked valid point reserves pending order; execution/wait deferred")
	var sized: DeploymentConfig = CONFIG.duplicate(true)
	sized.points[0].position = Vector3(-19, 0.5, 112)
	sized.catalog[0].width = 3.0
	var clearance := create(sized)
	check(not clearance.static_spawn_available("test.armored", "ground.west") and clearance.static_spawn_available("test.rifle", "ground.west"), "unit size changes boundary clearance")
	var restricted: DeploymentConfig = CONFIG.duplicate(true)
	restricted.points[0].allowed_factions = [2]
	restricted.points[1].allowed_categories = ["infantry"]
	var restrictions := create(restricted)
	restrictions.register_player(1, 1, 0)
	check(not buy(restrictions).ok and not buy(restrictions, 1, "test.armored", "ground.east").ok and buy(restrictions, 1, "test.rifle", "ground.east").ok, "faction and reserved category permissions")
	for variant: String in ["duplicate_point", "duplicate_config", "map_id", "position", "yaw", "faction", "category", "price", "limit", "height"]:
		var bad: DeploymentConfig = CONFIG.duplicate(true)
		match variant:
			"duplicate_point": bad.points.append(bad.points[0].duplicate(true))
			"duplicate_config": bad.catalog.append(bad.catalog[0].duplicate(true))
			"map_id": bad.map_id = "bad"
			"position": bad.points[0].position = Vector3(INF, 0, 0)
			"yaw": bad.points[0].yaw = NAN
			"faction": bad.points[0].allowed_factions = []
			"category": bad.catalog[0].category = "aircraft"
			"price": bad.catalog[0].sortie_points = -1.0
			"limit": bad.catalog[0].maximum_present = 0
			"height": bad.points[0].position.y = 8.0
		check(not DeploymentEconomy.new().initialize(bad, MOVEMENT, MAP, 60).is_empty(), "configuration rejects " + variant)
	var air: DeploymentConfig = CONFIG.duplicate(true)
	air.points[0].entry_kind = "air"
	var future_air := create(air)
	future_air.register_player(1, 1, 0)
	check(not buy(future_air).ok, "reserved air ingress does not allow ground orders")
	_server_permission_checks()
	var output := FileAccess.open("res://../tmp/04a/unit-results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "state": economy.export_state()}, "", true, true))
	print("0.4A checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func _server_permission_checks() -> void:
	var model = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(model)
	model._ensure_deployment_ready()
	model.deployment.register_player(1, 1, 0)
	model.deployment.register_player(2, 1, 0)
	model._peer_players[42] = 2
	model._pending_deployment_requests.append({"type":"order", "peer_id":42, "player_id":1, "config_id":"test.rifle", "point_id":"ground.west", "destination":Vector3(10,0,110)})
	model._consume_deployment_requests(PackedInt32Array([42]))
	check(model.deployment.export_player(1).balance == 1000.0 and model.deployment.export_player(2).balance == 1000.0, "stale peer mapping cannot spend previous player's points")
	model._pending_deployment_requests.append({"type":"order", "peer_id":42, "player_id":2, "config_id":"test.rifle", "point_id":"ground.west", "destination":Vector3(10,0,110)})
	model._consume_deployment_requests(PackedInt32Array())
	check(model.deployment.export_player(2).orders.is_empty(), "disconnected queued command ignored")
	model.free()
