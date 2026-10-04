class_name CombatSimulation
extends RefCounted

var _units: Dictionary[int, UnitState] = {}
var _cooldowns: Dictionary[int, float] = {}
var _map: PrototypeMapDefinition


func _init(definition: PrototypeMapDefinition) -> void:
	_map = definition


func add_unit(state: UnitState) -> void:
	_units[state.unit_id] = state


func remove_unit(unit_id: int) -> void:
	_units.erase(unit_id)
	_cooldowns.erase(unit_id)


func has_line_of_sight(start: Vector3, end: Vector3) -> bool:
	# Actual obstacle boxes, without movement clearance inflation.
	for rectangle: Rect2 in _map.obstacles:
		var box := rectangle.abs()
		var low := Vector3(box.position.x, 0.0, box.position.y)
		var high := Vector3(box.end.x, _map.obstacle_height, box.end.y)
		var direction := end - start
		var first := 0.0
		var last := 1.0
		var intersects := true
		for axis: int in 3:
			if is_zero_approx(direction[axis]):
				if start[axis] < low[axis] or start[axis] > high[axis]:
					intersects = false
					break
			else:
				var a := (low[axis] - start[axis]) / direction[axis]
				var b := (high[axis] - start[axis]) / direction[axis]
				first = maxf(first, minf(a, b))
				last = minf(last, maxf(a, b))
				if first > last:
					intersects = false
					break
		if intersects:
			return false
	return true


func nearest_enemy(attacker: UnitState) -> UnitState:
	if attacker.health <= 0.0 or attacker.weapon == null:
		return null
	var best: UnitState = null
	var best_distance := INF
	for candidate: UnitState in _units.values():
		if candidate.health <= 0.0 or candidate.team_id == attacker.team_id:
			continue
		var distance := attacker.position.distance_squared_to(candidate.position)
		if distance > attacker.weapon.range_m * attacker.weapon.range_m:
			continue
		if not has_line_of_sight(attacker.position, candidate.position):
			continue
		if distance < best_distance or (distance == best_distance and (best == null or candidate.unit_id < best.unit_id)):
			best = candidate
			best_distance = distance
	return best


func advance(delta: float, movement: MovementSimulation) -> Dictionary:
	var shots: Array[Dictionary] = []
	var deaths: Array[int] = []
	var ids: Array[int] = []
	ids.assign(_units.keys())
	ids.sort()
	# Immediate damage in stable shooter-ID order; killed units cannot fire later this tick.
	for id: int in ids:
		var attacker := _units[id]
		_cooldowns[id] = maxf(0.0, _cooldowns.get(id, 0.0) - delta)
		var weapon := attacker.weapon
		if not attacker.runtime_weapons.is_empty() or attacker.health <= 0.0 or weapon == null or _cooldowns[id] > 0.0:
			continue
		if movement.is_moving(id) and not weapon.can_fire_while_moving:
			continue
		var target := nearest_enemy(attacker)
		if target == null:
			continue
		_cooldowns[id] = weapon.firing_interval
		target.apply_prototype_damage(weapon.damage)
		shots.append({"attacker_id": id, "target_id": target.unit_id,
			"start": attacker.position, "end": target.position, "health": target.health})
		if target.health <= 0.0:
			deaths.append(target.unit_id)
	for id: int in deaths:
		movement.remove_unit(id)
		remove_unit(id)
	return {"shots": shots, "deaths": deaths}
