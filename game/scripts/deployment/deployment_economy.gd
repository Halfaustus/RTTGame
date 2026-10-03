class_name DeploymentEconomy
extends RefCounted

# Server-only accounts, reservations and upkeep. No peer IDs, visuals or replay writes.
signal state_changed(player_id: int)
signal event_emitted(event: Dictionary)

var _config: DeploymentConfig
var _movement: MovementConfig
var _map: PrototypeMapDefinition
var _catalog: Dictionary = {}
var _points: Dictionary = {}
var _accounts: Dictionary = {}
var _orders: Dictionary = {}
var _units: Dictionary = {}
var _next_order_id := 1
var _tick := 0
var _income_ticks := 0
var _event_sequence := 0
var _tick_hz := 60
var _retry_ticks := 15
var _settled_through_tick := 0


func initialize(config: DeploymentConfig, movement: MovementConfig, map: PrototypeMapDefinition, tick_hz: int) -> String:
	if not _accounts.is_empty() or not _orders.is_empty():
		return "cannot reinitialize an active economy"
	if config == null or movement == null or map == null or tick_hz <= 0:
		return "missing deployment configuration"
	if config.map_id != ReplayContent.MAP_ID:
		return "deployment map ID mismatch"
	for value: float in [config.initial_points, config.income_points, config.income_seconds, config.ground_upkeep_fraction_per_minute, config.air_upkeep_fraction_per_minute]:
		if not is_finite(value) or value < 0.0:
			return "invalid economy values"
	if config.income_seconds <= 0.0:
		return "invalid income interval"
	for value: float in [config.spawn_search_radius, config.spawn_search_step, config.waiting_retry_seconds]:
		if not is_finite(value) or value <= 0.0:
			return "invalid deployment search or retry configuration"
	if not is_finite(config.ground_countdown_seconds) or config.ground_countdown_seconds <= 0.0 or not is_finite(config.air_countdown_seconds) or config.air_countdown_seconds <= 0.0:
		return "invalid reserved countdown duration"
	var catalog := {}
	var definitions := {}
	for entry: Dictionary in config.catalog:
		if not _has_keys(entry, ["config_id", "category", "definition", "value_points", "sortie_points", "maximum_present", "width"]):
			return "incomplete catalog entry"
		if not _stable_id(entry.config_id) or catalog.has(entry.config_id) or not entry.definition is UnitDefinition:
			return "invalid or duplicate catalog ID/definition"
		if definitions.has(entry.definition.resource_path) or entry.definition.resource_path.is_empty():
			return "catalog definitions must be unique saved resources"
		if entry.category not in ["infantry", "armored_vehicle"]:
			return "unsupported ground category"
		var expected_type := UnitDefinition.UnitType.ARMORED_VEHICLE if entry.category == "armored_vehicle" else UnitDefinition.UnitType.INFANTRY
		if entry.definition.unit_type != expected_type:
			return "category does not match unit definition"
		for key: String in ["value_points", "sortie_points"]:
			if not valid_score(entry[key]):
				return "scores must be non-negative integers divisible by five"
		for key: String in ["width"]:
			if not _number(entry[key]) or not is_finite(float(entry[key])) or float(entry[key]) < 0.0:
				return "invalid catalog numeric value"
		if entry.width <= 0.0 or not entry.maximum_present is int or entry.maximum_present <= 0:
			return "invalid footprint or card limit"
		catalog[entry.config_id] = entry.duplicate(true)
		definitions[entry.definition.resource_path] = true
	if catalog.is_empty():
		return "empty catalog"
	var points := {}
	for point: Dictionary in config.points:
		if not _has_keys(point, ["point_id", "position", "yaw", "entry_kind", "allowed_factions", "allowed_categories"]):
			return "incomplete deployment point"
		if not _stable_id(point.point_id) or points.has(point.point_id):
			return "invalid or duplicate deployment point ID"
		if not point.position is Vector3 or not point.position.is_finite() or not _inside_bounds(point.position, movement):
			return "invalid deployment position"
		if not is_equal_approx(point.position.y, movement.spawn_origin.y):
			return "deployment point is not at unit ground height"
		if not _number(point.yaw) or not is_finite(float(point.yaw)) or point.entry_kind not in ["ground", "air"]:
			return "invalid deployment orientation or entry kind"
		if not point.allowed_factions is Array or point.allowed_factions.is_empty() or not point.allowed_categories is Array:
			return "invalid deployment restrictions"
		for faction: Variant in point.allowed_factions:
			if not faction is int or faction <= 0:
				return "invalid allowed faction"
		for category: Variant in point.allowed_categories:
			if category not in ["infantry", "armored_vehicle"]:
				return "invalid allowed category"
		points[point.point_id] = point.duplicate(true)
	if points.is_empty():
		return "empty deployment points"
	_config = config.duplicate(true)
	_movement = movement.duplicate(true)
	_map = map.duplicate(true)
	_catalog = catalog
	_points = points
	_income_ticks = maxi(1, ceili(config.income_seconds * tick_hz))
	_tick_hz = tick_hz
	_retry_ticks = maxi(1, ceili(config.waiting_retry_seconds * tick_hz))
	return ""


func is_ready() -> bool:
	return _config != null


func register_player(player_id: int, faction_id: int, tick: int) -> bool:
	if not is_ready() or player_id <= 0 or faction_id <= 0 or tick < _tick or _accounts.has(player_id):
		return false
	_accounts[player_id] = {"faction_id": faction_id, "balance": _config.initial_points, "joined_tick": tick, "income_through_tick": tick,
		"last_settlement_tick": 0, "last_settlement_upkeep": 0.0}
	_emit("account_opened", player_id, {"balance": _config.initial_points})
	return true


func advance_to_tick(tick: int) -> void:
	if not is_ready() or tick < _tick:
		return
	begin_tick(tick)
	while _settled_through_tick + _income_ticks <= tick:
		_settled_through_tick += _income_ticks
		for player_id: int in _accounts:
			var account: Dictionary = _accounts[player_id]
			# Global boundaries, not per-connection timers. Boundary-tick joins start next time.
			if account.joined_tick >= _settled_through_tick:
				continue
			var upkeep := current_upkeep(player_id, _settled_through_tick)
			var before: float = account.balance
			account.balance = maxf(0.0, before + _config.income_points - upkeep)
			account.income_through_tick = _settled_through_tick
			account.last_settlement_tick = _settled_through_tick
			account.last_settlement_upkeep = upkeep
			_emit("settlement", player_id, {"settlement_tick":_settled_through_tick,
				"income":_config.income_points,"upkeep":upkeep,"net_income":_config.income_points-upkeep,
				"balance_before":before,"balance":account.balance})


func begin_tick(tick: int) -> void:
	if tick > _tick:
		_tick = tick
		_event_sequence = 0


func register_live_unit(unit_id: int, player_id: int, definition: UnitDefinition, generated_tick: int = -1) -> bool:
	if unit_id <= 0 or _units.has(unit_id) or not _accounts.has(player_id) or definition == null:
		return false
	for config_id: String in _catalog:
		if _catalog[config_id].definition.resource_path == definition.resource_path:
			_units[unit_id] = _live_registration(player_id, config_id, _tick if generated_tick < 0 else generated_tick)
			state_changed.emit(player_id)
			return true
	return false


func remove_live_unit(unit_id: int) -> void:
	if _units.has(unit_id):
		var player_id: int = _units[unit_id].player_id
		_units.erase(unit_id)
		state_changed.emit(player_id)


func request_order(player_id: int, config_id: String, point_id: String, destination: Vector3, held: bool = false) -> Dictionary:
	if not _accounts.has(player_id):
		return _rejected("unknown player")
	if not _catalog.has(config_id) or not _points.has(point_id):
		return _rejected("unknown configuration or deployment point")
	if not destination.is_finite() or not _inside_bounds(destination, _movement):
		return _rejected("invalid destination")
	var entry: Dictionary = _catalog[config_id]
	var point: Dictionary = _points[point_id]
	var account: Dictionary = _accounts[player_id]
	if held_order_id(player_id) != 0:
		return _rejected("already holding a deployment card")
	if not valid_score(entry.sortie_points) or not valid_score(entry.value_points):
		return _rejected("invalid deployment or value score")
	if point.entry_kind != "ground" or not point.allowed_factions.has(account.faction_id):
		return _rejected("deployment point not permitted")
	if not point.allowed_categories.is_empty() and not point.allowed_categories.has(entry.category):
		return _rejected("unit category not permitted")
	var counts := card_counts(player_id, config_id)
	if counts.present + counts.pending >= entry.maximum_present:
		return _rejected("card limit reached")
	if account.balance < entry.sortie_points:
		return _rejected("insufficient sortie points")
	var id := _next_order_id
	_next_order_id += 1
	account.balance -= entry.sortie_points
	_orders[id] = {"order_id": id, "player_id": player_id, "config_id": config_id, "point_id": point_id,
		"destination": null if held else destination, "status": "held" if held else "pending", "paid_points": float(entry.sortie_points), "accepted_tick": _tick,
		"deployment_eligible": false, "countdown_started": false, "placement_revision": 0,
		"countdown_seconds":_config.ground_countdown_seconds}
	_emit("order_accepted", player_id, _orders[id])
	return {"ok": true, "order_id": id, "status": _orders[id].status}


func buy_order(player_id: int, config_id: String, point_id: String) -> Dictionary:
	if not _points.has(point_id):
		return _rejected("unknown deployment point")
	return request_order(player_id, config_id, point_id, _points[point_id].position, true)


func held_order_id(player_id: int) -> int:
	for order: Dictionary in _orders.values():
		if order.player_id == player_id and order.status == "held":
			return order.order_id
	return 0


func pickup_order(player_id: int, order_id: int) -> Dictionary:
	if not _owned_order(player_id, order_id):
		return _rejected("unknown or unowned order")
	if held_order_id(player_id) != 0:
		return _rejected("already holding a deployment card")
	var order: Dictionary = _orders[order_id]
	if order.status not in ["placed", "countdown", "waiting"]:
		return _rejected("order cannot be picked up")
	order.status = "held"
	order.deployment_eligible = false
	order.countdown_started = false
	order.erase("completion_tick")
	order.erase("next_retry_tick")
	_emit("order_picked_up", player_id, order)
	return {"ok": true, "order_id": order_id, "status": "held"}


func place_order(player_id: int, order_id: int, destination: Vector3, mode: int = MovementSimulation.MoveMode.BASIC) -> Dictionary:
	if not _owned_order(player_id, order_id):
		return _rejected("unknown or unowned order")
	var order: Dictionary = _orders[order_id]
	if order.status != "held":
		return _rejected("order is not held")
	if not destination.is_finite() or not _inside_bounds(destination, _movement):
		return _rejected("invalid destination")
	if mode not in [MovementSimulation.MoveMode.BASIC, MovementSimulation.MoveMode.FAST]:
		return _rejected("invalid deployment movement mode")
	if not is_equal_approx(destination.y, _movement.ground_height):
		return _rejected("destination is not on ground")
	order.destination = destination
	order.status = "countdown"
	order.move_mode = mode
	order.placement_revision += 1
	order.placed_tick = _tick
	order.countdown_seconds = _config.ground_countdown_seconds
	order.countdown_started = true
	order.deployment_eligible = false
	order.completion_tick = _tick + ceili(_config.ground_countdown_seconds * _tick_hz)
	order.next_retry_tick = order.completion_tick
	_emit("order_placed", player_id, order)
	return {"ok": true, "order_id": order_id, "status": "countdown"}


func _owned_order(player_id: int, order_id: int) -> bool:
	return _accounts.has(player_id) and _orders.has(order_id) and _orders[order_id].player_id == player_id


func cancel_order(player_id: int, order_id: int) -> Dictionary:
	if not _accounts.has(player_id) or not _orders.has(order_id) or _orders[order_id].player_id != player_id:
		return _rejected("unknown or unowned order")
	var order: Dictionary = _orders[order_id]
	if order.status == "cancelled":
		return {"ok": true, "order_id": order_id, "refunded": false}
	if order.status not in ["pending", "held", "placed", "countdown", "waiting"]:
		return _rejected("order already generated")
	order.status = "cancelled"
	order.countdown_started = false
	order.deployment_eligible = false
	order.cancelled_tick = _tick
	_accounts[player_id].balance += order.paid_points
	_emit("order_cancelled", player_id, order)
	return {"ok": true, "order_id": order_id, "refunded": true}


func card_counts(player_id: int, config_id: String) -> Dictionary:
	var result := {"present": 0, "pending": 0}
	for unit: Dictionary in _units.values():
		if unit.player_id == player_id and unit.config_id == config_id:
			result.present += 1
	for order: Dictionary in _orders.values():
		if order.player_id == player_id and order.config_id == config_id and order.status in ["pending", "held", "placed", "countdown", "waiting"]:
			result.pending += 1
	return result


func static_spawn_available(config_id: String, point_id: String) -> bool:
	if not _catalog.has(config_id) or not _points.has(point_id) or _points[point_id].entry_kind != "ground":
		return false
	var position: Vector3 = _points[point_id].position
	var clearance: float = _catalog[config_id].width * 0.5 + _movement.obstacle_margin
	var xz := Vector2(position.x, position.z)
	var minimum := _movement.minimum_xz + Vector2.ONE * clearance
	var maximum := _movement.maximum_xz - Vector2.ONE * clearance
	if xz.x < minimum.x or xz.y < minimum.y or xz.x > maximum.x or xz.y > maximum.y:
		return false
	for obstacle: Rect2 in _map.obstacles:
		var blocked := obstacle.grow(clearance)
		if xz.x >= blocked.position.x and xz.y >= blocked.position.y and xz.x <= blocked.end.x and xz.y <= blocked.end.y:
			return false
	return true


# Body sortie cost only; independent value points never contribute.
func upkeep_per_minute(config_id: String) -> float:
	if not _catalog.has(config_id):
		return 0.0
	return _catalog[config_id].sortie_points * _config.ground_upkeep_fraction_per_minute


func _live_registration(player_id: int, config_id: String, generated_tick: int) -> Dictionary:
	return {"player_id":player_id,"config_id":config_id,"generated_tick":generated_tick,
		"sortie_points":_catalog[config_id].sortie_points,
		"upkeep_per_settlement":upkeep_per_minute(config_id) * _income_ticks / float(_tick_hz * 60)}


func current_upkeep(player_id: int, boundary_tick: int = -1) -> float:
	var amount := 0.0
	for unit: Dictionary in _units.values():
		if unit.player_id == player_id and (boundary_tick < 0 or unit.generated_tick < boundary_tick):
			amount += unit.upkeep_per_settlement
	return amount


func export_player(player_id: int) -> Dictionary:
	if not _accounts.has(player_id):
		return {}
	var account: Dictionary = _accounts[player_id]
	var cards := {}
	var catalog: Array[Dictionary] = []
	for config_id: String in _catalog:
		cards[config_id] = card_counts(player_id, config_id)
		var entry: Dictionary = _catalog[config_id]
		catalog.append({"config_id":config_id,"category":entry.category,"value_points":entry.value_points,
			"sortie_points":entry.sortie_points,"maximum_present":entry.maximum_present})
	var points: Array[Dictionary] = []
	for point: Dictionary in _points.values():
		if point.entry_kind == "ground" and point.allowed_factions.has(account.faction_id):
			points.append({"point_id":point.point_id,"allowed_categories":point.allowed_categories.duplicate()})
	var orders: Array[Dictionary] = []
	for order: Dictionary in _orders.values():
		if order.player_id == player_id:
			var exported := order.duplicate(true)
			exported.remaining_seconds = maxf(0.0, (int(order.get("completion_tick", _tick)) - _tick) / float(_tick_hz)) if order.status == "countdown" else 0.0
			orders.append(exported)
	return {"schema_version": 1, "player_id": player_id, "faction_id": account.faction_id, "tick": _tick, "balance": account.balance,
		"display_points": int(account.balance), "income_through_tick": account.income_through_tick,
		"income_per_settlement":_config.income_points,"upkeep_per_settlement":current_upkeep(player_id),
		"net_income_per_settlement":_config.income_points-current_upkeep(player_id),
		"settlement_seconds":_income_ticks/float(_tick_hz),"last_settlement_tick":account.last_settlement_tick,
		"last_settlement_upkeep":account.last_settlement_upkeep,
		"cards": cards, "orders": orders, "catalog":catalog, "points":points,
		"held_order_id":held_order_id(player_id), "timing_implemented":true}


# Called in session after queued deployment requests, before movement/combat.
# The callback must add
# each new unit immediately to the same authoritative occupancy dictionary.
func execute_deployments(units: Dictionary, spawn: Callable) -> void:
	var due: Array[Dictionary] = []
	var new_due := false
	for order: Dictionary in _orders.values():
		if order.status == "countdown" and _tick >= order.completion_tick:
			new_due = true
	for order: Dictionary in _orders.values():
		if order.status == "countdown":
			state_changed.emit(order.player_id)
			if _tick < order.completion_tick:
				continue
		elif order.status != "waiting":
			continue
		# A newly completed order also triggers a priority-ordered batch so an
		# older waiter cannot lose a newly available slot between retry ticks.
		if _tick >= order.next_retry_tick or new_due:
			due.append(order)
	due.sort_custom(func(a: Dictionary, b: Dictionary):
		return a.completion_tick < b.completion_tick if a.completion_tick != b.completion_tick else a.order_id < b.order_id)
	for order: Dictionary in due:
		var entry: Dictionary = _catalog[order.config_id]
		var point: Dictionary = _points[order.point_id]
		var position: Variant = find_spawn_position(entry.width, point.position, units)
		if position == null:
			order.next_retry_tick = _tick + _retry_ticks
			if order.status != "waiting":
				order.status = "waiting"
				order.countdown_started = false
				order.deployment_eligible = true
				_emit("order_waiting", order.player_id, order)
			continue
		var unit_id: int = spawn.call(order.duplicate(true), position, entry, point)
		if unit_id <= 0:
			order.next_retry_tick = _tick + _retry_ticks
			continue
		# Atomic reservation -> live conversion; callback does not register a card.
		_units[unit_id] = _live_registration(order.player_id, order.config_id, _tick)
		order.status = "generated"
		order.countdown_started = false
		order.generated_tick = _tick
		order.unit_id = unit_id
		order.spawn_position = position
		order.deployment_eligible = false
		_emit("order_generated", order.player_id, order)


func find_spawn_position(width: float, center: Vector3, units: Dictionary) -> Variant:
	var candidates: Array[Vector3] = []
	var reach := floori(_config.spawn_search_radius / _config.spawn_search_step)
	for x: int in range(-reach, reach + 1):
		for z: int in range(-reach, reach + 1):
			var position := center + Vector3(x * _config.spawn_search_step, 0, z * _config.spawn_search_step)
			if position.distance_squared_to(center) <= _config.spawn_search_radius * _config.spawn_search_radius + 0.000001:
				candidates.append(position)
	candidates.sort_custom(func(a: Vector3, b: Vector3):
		var da := a.distance_squared_to(center)
		var db := b.distance_squared_to(center)
		if not is_equal_approx(da, db): return da < db
		return a.x < b.x if a.x != b.x else a.z < b.z)
	for position: Vector3 in candidates:
		if not _static_position_available(position, width): continue
		var occupied := false
		for unit: UnitState in units.values():
			if unit.health <= 0: continue
			var other_width := _movement.unit_width
			for entry: Dictionary in _catalog.values():
				if unit.definition == entry.definition:
					other_width = entry.width
					break
			var separation: float = (width + other_width) * 0.5 + _movement.obstacle_margin
			if absf(position.x - unit.position.x) < separation and absf(position.z - unit.position.z) < separation:
				occupied = true
				break
		if not occupied: return position
	return null


func _static_position_available(position: Vector3, width: float) -> bool:
	var clearance := width * 0.5 + _movement.obstacle_margin
	if position.x < _movement.minimum_xz.x + clearance or position.x > _movement.maximum_xz.x - clearance or position.z < _movement.minimum_xz.y + clearance or position.z > _movement.maximum_xz.y - clearance:
		return false
	for obstacle: Rect2 in _map.obstacles:
		var rect := obstacle.abs().grow(clearance)
		if position.x >= rect.position.x and position.x <= rect.end.x and position.z >= rect.position.y and position.z <= rect.end.y:
			return false
	return true


# Server-only export boundary, not a network broadcast or a v1 replay extension.
func export_state() -> Dictionary:
	var players: Array[Dictionary] = []
	for player_id: int in _accounts:
		players.append(export_player(player_id))
	return {"tick": _tick, "next_order_id": _next_order_id, "players": players}


func _emit(kind: String, player_id: int, payload: Dictionary) -> void:
	_event_sequence += 1
	event_emitted.emit({"tick": _tick, "sequence": _event_sequence, "kind": kind, "player_id": player_id, "payload": payload.duplicate(true)})
	state_changed.emit(player_id)


static func _rejected(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _number(value: Variant) -> bool:
	return value is int or value is float

static func valid_score(value: Variant) -> bool:
	return value is int and value >= 0 and value % 5 == 0

static func _has_keys(value: Dictionary, keys: Array) -> bool:
	for key: String in keys:
		if not value.has(key):
			return false
	return true

static func _stable_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-":
			return false
	return true

static func _inside_bounds(position: Vector3, movement: MovementConfig) -> bool:
	return position.x >= movement.minimum_xz.x and position.x <= movement.maximum_xz.x and position.z >= movement.minimum_xz.y and position.z <= movement.maximum_xz.y
