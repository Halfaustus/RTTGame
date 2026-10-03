extends SceneTree

const CONFIG = preload("res://data/prototype_deployment.tres")
const MOVEMENT = preload("res://data/prototype_movement.tres")
const MAP = preload("res://data/prototype_map.tres")
var checks := 0
var failures := 0
var requests: Array[Dictionary] = []
var economy: DeploymentEconomy
var ui: DeploymentUI

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS 0.4B: ", label)
	else:
		failures += 1
		push_error("FAIL 0.4B: " + label)

func key(code: Key, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	return event

func mouse(button: MouseButton, pressed: bool = true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = Vector2(600, 400)
	return event

func respond() -> Dictionary:
	var request: Dictionary = requests.pop_front()
	var result: Dictionary
	match request.action:
		"buy": result = economy.buy_order(1, request.payload.config_id, request.payload.point_id)
		"place": result = economy.place_order(1, request.payload.order_id, request.payload.destination)
		"pickup": result = economy.pickup_order(1, request.payload.order_id)
		"cancel": result = economy.cancel_order(1, request.payload.order_id)
	result.request_id = request.request_id
	ui.apply_state(economy.export_player(1))
	ui.apply_result(result)
	return result

func _run() -> void:
	for field: String in ["sortie_points", "value_points"]:
		for value: Variant in [-5, 3, 40.5, 40.0, NAN, INF, "40", true]:
			var config: DeploymentConfig = CONFIG.duplicate(true)
			config.catalog[0][field] = value
			check(not DeploymentEconomy.new().initialize(config, MOVEMENT, MAP, 60).is_empty(), "reject illegal " + field + ": " + str(value))
	var zero_config: DeploymentConfig = CONFIG.duplicate(true)
	zero_config.catalog[0].sortie_points = 0
	zero_config.catalog[0].value_points = 0
	check(DeploymentEconomy.new().initialize(zero_config, MOVEMENT, MAP, 60).is_empty(), "zero integer scores legal")
	economy = DeploymentEconomy.new()
	check(economy.initialize(CONFIG, MOVEMENT, MAP, 60).is_empty(), "current catalog legal")
	economy.register_player(1, 1, 0)
	economy.register_player(2, 1, 0)
	economy.register_live_unit(4, 1, CONFIG.catalog[0].definition)
	check(economy.upkeep_per_minute("test.rifle") == 7.5, "fractional maintenance quote retained")
	var world = load("res://scenes/maps/test_world.tscn").instantiate()
	root.add_child(world)
	ui = world._deployment_ui
	ui._transport_enabled = false
	ui._ground = func(_position: Vector2): return Vector3(10,0,110)
	ui.request_sent.connect(func(action: String, payload: Dictionary, request_id: int): requests.append({"action":action,"payload":payload,"request_id":request_id}))
	ui.apply_state(economy.export_player(1))
	await process_frame
	check(ui._rows.get_child_count() == 2 and ui._balance.text.contains("1000"), "category purchase interface shows balance and entries")
	world._camera._rotating = true
	ui.buy("test.rifle")
	check(requests.is_empty() and not ui.busy, "rotation blocks purchase confirmation")
	world._camera._rotating = false
	world._attack_move_armed = true
	world._pending_actions.append({"type":"stop"})
	var buy_button: Button = ui._rows.get_child(0)
	var click := mouse(MOUSE_BUTTON_LEFT)
	click.position = buy_button.get_global_rect().get_center()
	root.push_input(click, true)
	click.pressed = false
	root.push_input(click, true)
	ui.buy("test.rifle")
	check(requests.size() == 1 and ui.busy and world._pending_actions.is_empty() and not world._attack_move_armed, "single outstanding buy locks input and clears old gestures")
	var result := respond()
	var id: int = result.order_id
	check(result.ok and ui.held_id == id and economy.export_player(1).balance == 850.0, "purchase holds one card with debit and reservation")
	check(not economy.buy_order(1,"test.rifle","ground.west").ok and not economy.request_order(1,"test.rifle","ground.west",Vector3(10,0,110)).ok, "server blocks repeated buy including legacy bypass")
	check(economy.export_player(2).orders.is_empty() and not economy.place_order(2,id,Vector3(10,0,110)).ok and not economy.cancel_order(2,id).ok, "foreign placement/cancel and account isolation")
	world._handle_world_input(key(KEY_Q))
	world._handle_world_input(key(KEY_F))
	world._handle_world_input(key(KEY_R))
	world._handle_world_input(key(KEY_E, true))
	world._handle_world_input(key(KEY_ESCAPE))
	check(requests.is_empty() and ui.held_id == id and world._pending_actions.is_empty() and not world._fast_move_armed, "held card blocks normal keys; echo/Esc do not cancel card")
	world._handle_world_input(mouse(MOUSE_BUTTON_LEFT))
	world._handle_world_input(mouse(MOUSE_BUTTON_LEFT, false))
	check(requests.size() == 1 and requests[0].action == "place" and world._pending_actions.is_empty(), "deployment left click does not select units or issue movement")
	check(respond().ok and ui.held_id == 0 and economy.export_player(1).orders[0].status == "countdown" and ui._markers.has(id), "placed card displays authoritative countdown")
	check(economy.export_player(1).orders[0].countdown_started and not economy.export_player(1).orders[0].deployment_eligible and economy.export_player(1).timing_implemented, "real countdown without early deployment eligibility")
	ui.pickup(id)
	check(ui.busy and ui.held_id == 0, "pickup waits for server confirmation")
	check(respond().ok and ui.held_id == id and economy.export_player(1).balance == 850.0, "pickup pauses eligibility and retains cost/slot")
	ui.place(Vector3(NAN,0,110))
	check(not respond().ok and not ui.busy and ui.held_id == id and ui._message.text.contains("拒绝"), "refused placement restores held card and input")
	ui.place(Vector3(12,0,112))
	check(respond().ok and economy.export_player(1).orders[0].placement_revision == 2 and economy.export_player(1).orders[0].countdown_seconds == 3.0, "replacement resets full reserved countdown revision")
	ui.pickup(id)
	respond()
	var cancel_click := mouse(MOUSE_BUTTON_RIGHT)
	cancel_click.position = Vector2(30,70)
	root.push_input(cancel_click,true)
	cancel_click.pressed = false
	root.push_input(cancel_click,true)
	check(requests.size() == 1 and requests[0].action == "cancel" and world._pending_actions.is_empty(), "right cancel has no ordinary command passthrough")
	check(respond().ok and ui.held_id == 0 and economy.export_player(1).balance == 1000.0, "cancel refunds and releases held card")
	check(not economy.cancel_order(1,id).refunded and economy.export_player(1).balance == 1000.0, "repeat cancellation does not duplicate refund")
	ui.buy("test.unarmed")
	respond()
	world._handle_world_input(key(KEY_E))
	check(requests.size() == 1 and world._pending_actions.is_empty(), "E cancels held card without stop")
	respond()
	var armour_ids: Array[int] = []
	for index: int in 3:
		var purchase := economy.buy_order(1,"test.armored","ground.west")
		armour_ids.append(purchase.order_id)
		economy.place_order(1,purchase.order_id,Vector3(index * 2,0,110))
	check(economy.card_counts(1,"test.armored") == {"present":1,"pending":3}, "multiple placed cards share cap with present unit")
	check(not economy.buy_order(1,"test.armored","ground.west").ok and not economy.buy_order(1,"test.rifle","ground.west").ok, "server rejects card cap and insufficient balance")
	check(economy.buy_order(2,"test.armored","ground.west").ok, "other account buys independently")
	check(economy.pickup_order(1,armour_ids[0]).ok and not economy.pickup_order(1,armour_ids[1]).ok, "only one picked-up order")
	economy.cancel_order(1,armour_ids[0])
	for index: int in [1,2]: economy.cancel_order(1,armour_ids[index])
	ui.apply_state(economy.export_player(1))
	ui.buy("test.rifle")
	economy._accounts[1].balance = 0.0 # Stale UI simulates a server-side rejection.
	check(not respond().ok and not ui.busy and ui.held_id == 0 and ui.state.balance == 0.0, "server-refused purchase restores authoritative UI")
	economy._accounts[1].balance = 1000.0
	economy._catalog["test.rifle"].sortie_points = 151
	check(not economy.buy_order(1,"test.rifle","ground.west").ok and economy.export_player(1).balance == 1000.0, "server revalidates score without rounding")
	economy._catalog["test.rifle"].sortie_points = 150
	economy._accounts[1].balance = 1000.75
	check(economy.export_player(1).display_points == 1000 and economy.export_player(1).balance == 1000.75, "fractional ledger survives integer purchase scores")
	ui.reset_connection()
	check(ui.state.is_empty() and not ui.busy and ui.held_id == 0, "disconnect resets pending UI")
	_server_checks()
	world.free()
	var evidence := FileAccess.open("res://../tmp/04b/unit-results.json",FileAccess.WRITE)
	evidence.store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("0.4B checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func _server_checks() -> void:
	var model = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(model)
	model._ensure_deployment_ready()
	model.deployment.register_player(1,1,0)
	model._peer_players[42] = 1
	model._pending_deployment_requests.append({"type":"edit","action":"buy","order_id":999,"destination":Vector3.ZERO,"request_id":8,"peer_id":42,"player_id":1})
	model._consume_deployment_requests(PackedInt32Array([42]))
	check(model._replication_queue.size() == 2 and model._replication_queue[0].peer_id == 42 and not model._replication_queue[1].arguments[0].ok, "invalid edit action rejected with owner-only state recovery")
	model._replication_queue.clear()
	model._pending_deployment_requests.append({"type":"buy","config_id":"test.rifle","point_id":"ground.west","request_id":9,"peer_id":42,"player_id":2})
	model._consume_deployment_requests(PackedInt32Array([42]))
	check(model.deployment.export_player(1).balance == 1000.0 and model._replication_queue.is_empty(), "sender/player mapping rechecked before purchase")
	model.free()
