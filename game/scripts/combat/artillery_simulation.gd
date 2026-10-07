class_name ArtillerySimulation
extends RefCounted

# Minimal server-authoritative T single-point task. No new unit schema.
var tasks: Dictionary = {}
var data := ConfirmedGameData.new()

func submit(unit: UnitState,point: Vector3,count: int,aiming: AimingSimulation,movement: MovementSimulation,validate_only: bool = false) -> String:
	if not point.is_finite() or count not in [1,3,-1]: return "invalid_artillery_request"
	var ground_error := movement._validate_target(point)
	if not ground_error.is_empty(): return ground_error
	if unit.health <= 0 or not movement.matches_units(aiming.units): return "artillery_owner_invalid"
	var eligible: Array[RuntimeWeaponInstance] = []
	for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
		var row := data.record("Weapons",weapon.definition.definition_id)
		if row.get("Class","") != "迫击炮": continue
		if not weapon.owning_node_valid(): return "artillery_owner_invalid"
		var distance := weapon.world_position().distance_to(point)
		var minimum := data.number(row,"Min_Range_m")
		if not is_finite(minimum) or not is_finite(weapon.definition.range_m): return "artillery_configuration_missing"
		if distance < minimum: return "below_minimum_range"
		if distance > weapon.definition.range_m and unit.definition.hardened_speed <= 0 and unit.definition.unhardened_speed <= 0: return "artillery_cannot_approach"
		var selection := AmmoSelection.ground_selection(weapon)
		if selection.reason != "eligible": return selection.reason
		if not selection.ammo.distance_selected_launch: return "projectile_configuration_missing"
		if distance <= weapon.definition.range_m:
			var solution := GravityBallistics.indirect(DirectBallistics.muzzle(weapon),point)
			if not solution.valid: return solution.reason
		eligible.append(weapon)
	if eligible.is_empty(): return "no_artillery_weapon"
	if validate_only: return ""
	movement.request_stop([unit.unit_id],unit.owner_peer_id)
	cancel(unit)
	for weapon: RuntimeWeaponInstance in eligible:
		weapon.bind_target(AttackTarget.ground(point),true)
		var selection := AmmoSelection.ground_selection(weapon)
		var available := int(weapon.inventory[selection.ammo.ammo_id])/weapon.definition.consumption_per_projectile
		tasks[weapon.instance_id] = {"remaining":available if count < 0 else count,"minimum":data.number(data.record("Weapons",weapon.definition.definition_id),"Min_Range_m"),"ammo":selection.ammo,"weapon":weakref(weapon)}
		if unit.position.distance_to(point) > weapon.definition.range_m:
			var source := weapon.world_position()
			var destination := point+(source-point).normalized()*weapon.definition.range_m-(source-unit.position)
			destination.y = movement._config.ground_height
			var error := movement.request_move(unit.unit_id,unit.owner_peer_id,destination)
			if not error.is_empty(): cancel(unit); return error
	aiming.artillery_tasks = tasks
	return ""

func cancel(unit: UnitState) -> void:
	for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
		if tasks.has(weapon.instance_id):
			tasks.erase(weapon.instance_id)
			weapon.clear_target()

func after_emissions(_events: Array[Dictionary],_units: Dictionary) -> void:
	for key: String in tasks.keys():
		var task: Dictionary = tasks[key]
		var weapon: RuntimeWeaponInstance = task.weapon.get_ref()
		if weapon == null or not weapon.owning_node_valid():
			tasks.erase(key)
			continue
		if not task.get("finished",false): continue
		tasks.erase(key)
		weapon.clear_target()
