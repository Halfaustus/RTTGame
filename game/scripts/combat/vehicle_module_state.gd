class_name VehicleModuleState
extends RefCounted

# Server-only domain state. Random distribution is supplied explicitly by the
# authorized coordinator; this component does not invent a sampling policy.
enum Module { OPTICS, PERSONNEL, LOADING, MOBILITY }
const THRESHOLD := 100.0 # COMBAT_RULES section 10 mechanism constant.
var levels: Array[int] = [0,0,0,0]
var amount := 0.0
var records: Dictionary = {}

func candidates() -> Array[int]:
	var result: Array[int] = []
	for index: int in levels.size():
		if levels[index] < 2: result.append(index)
	return result

static func eligible(ammo: Dictionary,penetration: float,armor: float) -> Dictionary:
	if not ImpactDamageRules.number(ammo.get("module_damage"),0.0): return {"ok":false,"reason":"module_damage_configuration_missing"}
	if not ImpactDamageRules.number(penetration,0.0) or not ImpactDamageRules.number(armor,0.0) or armor <= 0: return {"ok":false,"reason":"module_protection_invalid"}
	if ammo.get("damage_type") not in ["kinetic","chemical"]: return {"ok":false,"reason":"module_damage_type_invalid"}
	var qualifies: bool = penetration >= armor if ammo.damage_type == "kinetic" else penetration >= 0.5*armor
	return {"ok":true,"amount":float(ammo.module_damage) if qualifies else 0.0,"eligible":qualifies and float(ammo.module_damage) > 0}

func prepare(event_id: String,value: float,select: Callable) -> Dictionary:
	if event_id.is_empty() or records.has(event_id): return {"ok":false,"reason":"module_event_duplicate_or_missing"}
	if not InfantrySuppressionState.finite_nonnegative(value): return {"ok":false,"reason":"module_amount_invalid"}
	var next: Array[int] = levels.duplicate()
	var remaining := amount+value
	if not is_finite(remaining): return {"ok":false,"reason":"module_amount_nonfinite"}
	var upgrades: Array[Dictionary] = []
	while remaining >= THRESHOLD:
		var available: Array[int] = []
		for index: int in next.size():
			if next[index] < 2: available.append(index)
		if available.is_empty():
			remaining = 0.0
			break
		if not select.is_valid(): return {"ok":false,"reason":"module_selection_unconfirmed"}
		var chosen: Variant = select.call(available.duplicate())
		if not chosen is int or chosen not in available: return {"ok":false,"reason":"module_selection_invalid"}
		upgrades.append({"module":chosen,"before":next[chosen],"after":next[chosen]+1})
		next[chosen] += 1
		remaining -= THRESHOLD
	if next.all(func(level): return level == 2): remaining = 0.0
	return {"ok":true,"event_id":event_id,"before_levels":levels.duplicate(),"before_amount":amount,"levels":next,"amount":remaining,"upgrades":upgrades}

func commit(plan: Dictionary) -> bool:
	if plan.get("ok") != true or records.has(plan.event_id) or plan.before_levels != levels or plan.before_amount != amount: return false
	levels.assign(plan.levels)
	amount = plan.amount
	records[plan.event_id] = plan.duplicate(true)
	return true

func repair_level_completed(module: int) -> bool:
	# No service/cost/order/timer assumptions: only an actual completed level.
	if module < 0 or module >= levels.size() or levels[module] == 0: return false
	levels[module] -= 1
	amount = 0.0
	return true

static func factor(level: int) -> float:
	return 1.0 if level == 0 else 2.0 if level == 1 else 5.0

func modifiers() -> Dictionary:
	var optics := factor(levels[Module.OPTICS])
	var personnel := factor(levels[Module.PERSONNEL])
	return {"vision":1.0/optics,"movement":1.0/factor(levels[Module.MOBILITY]),
		"aim_time_multiplier":optics*personnel,"spread_multiplier":personnel,
		"personnel_load_multiplier":personnel,"loading_module_multiplier":factor(levels[Module.LOADING])}
