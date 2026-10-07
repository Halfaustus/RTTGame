class_name ProjectileSettlementInbox
extends RefCounted

# One server-owned inbox per match. Accepting a value is NOT gameplay settlement.
# No callback runs after the whole-step firing batch: a future ordered coordinator
# must own gameplay commits. Entries are retained until explicit match teardown,
# so delayed duplicate delivery cannot silently become a second settlement.
var failure_reason := ""
var _context: Dictionary = {}
var _accepted: Dictionary = {}
var _pending: Array[Dictionary] = []
var _source_orders: Dictionary = {}

func configure(context: Dictionary) -> bool:
	if not values_only(context):
		failure_reason = "settlement_context_invalid"
		return false
	if not _accepted.is_empty() or not _pending.is_empty():
		failure_reason = "settlement_context_in_use"
		return false
	for field: String in ["match_id","map_id","rules_id","data_version","data_sha256"]:
		if not context.get(field) is String or context[field].is_empty():
			failure_reason = "settlement_context_missing:"+field
			return false
	_context = context.duplicate(true)
	failure_reason = ""
	return true

# Validate a whole batch before publishing any entry. Duplicate identity with a
# different value is a conflict, not a silent discard or an automatic repair.
func accept_batch(inputs: Array[Dictionary]) -> bool:
	failure_reason = ""
	if _context.is_empty():
		failure_reason = "settlement_context_missing"
		return false
	var staged := {}
	var staged_sources := {}
	var ordered: Array[Dictionary] = []
	for input: Dictionary in inputs:
		if not _valid(input):
			failure_reason = "settlement_input_invalid"
			return false
		var key: Variant = ProjectileSettlementInput.key(input)
		var source: String = input.source_event_id
		var source_order: int = int(staged_sources.get(source,_source_orders.get(source,input.emission_order)))
		if source_order != input.emission_order:
			failure_reason = "settlement_source_identity_conflict"
			return false
		var existing: Variant = staged.get(key,_accepted.get(key))
		if existing != null:
			if existing != input:
				failure_reason = "settlement_identity_conflict"
				return false
			continue
		var copy := input.duplicate(true)
		staged[key] = copy
		staged_sources[source] = input.emission_order
		ordered.append(copy)
	for input: Dictionary in ordered:
		_accepted[ProjectileSettlementInput.key(input)] = input
		_source_orders[input.source_event_id] = input.emission_order
		var envelope := {"context":_context.duplicate(true),"input":input.duplicate(true)}
		_pending.append(envelope)
	return true

func take_pending() -> Array[Dictionary]:
	var result: Array[Dictionary] = _pending.duplicate(true)
	_pending.clear()
	return result

func accepted_count() -> int:
	return _accepted.size()

func reset() -> void:
	_context.clear()
	_accepted.clear()
	_pending.clear()
	_source_orders.clear()
	failure_reason = ""

static func _valid(input: Dictionary) -> bool:
	if not values_only(input): return false
	if input.has("impact_sequence") and (not input.impact_sequence is int or input.impact_sequence < 0): return false
	if input.has("penetration_loss") and (not _number(input.penetration_loss) or input.penetration_loss < 0): return false
	for field: String in ["projectile_id","source_event_id","weapon_instance_id","ammo_definition_id"]:
		if not input.get(field) is String or input[field].is_empty(): return false
	if input.projectile_id != "projectile:"+input.source_event_id: return false
	for field: String in ["emission_order","slot_generation","source_unit_id"]:
		if not input.get(field) is int or input[field] <= 0: return false
	if not input.get("source_player_id") is int or input.source_player_id < 0: return false
	for field: String in ["time_seconds","distance_m"]:
		if not _number(input.get(field)) or input[field] < 0: return false
	if not _vector(input.get("position")) or not _vector(input.get("velocity")): return false
	if not input.get("ammo_values") is Dictionary or input.ammo_values.get("ammo_id") != input.ammo_definition_id: return false
	if input.get("kind") == "battlefield_exit":
		return input.get("reason") == "battlefield_exit" and not input.has("hit_unit_id")
	if input.get("reason") != "impact" or not _vector(input.get("point")) or not _vector(input.get("normal")): return false
	if not input.get("object_id") is String or input.object_id.is_empty() or not input.get("object_category") is String: return false
	if not input.get("hit_unit_id") is int or not input.get("hit_unit_type") is int: return false
	if input.get("kind") == "unit_impact": return input.hit_unit_id > 0 and input.object_category == "unit"
	return input.get("kind") == "static_impact" and input.hit_unit_id == 0 and input.object_category != "unit"

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and _number(value[0]) and _number(value[1]) and _number(value[2])

static func values_only(value: Variant) -> bool:
	if value == null or value is bool or value is String or value is int: return true
	if value is float: return is_finite(value)
	if value is Array:
		for item: Variant in value:
			if not values_only(item): return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not (key is String or key is StringName) or not values_only(value[key]): return false
		return true
	return false
