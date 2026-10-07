class_name BattleControlGroups
extends RefCounted

# Local selection memory only. Never changes ownership or unit tasks.
const DOUBLE_PRESS_SECONDS := 0.35
var groups := {}
var _last_group := -1
var _last_time := -1.0

func save(group: int, selection: Array[int]) -> void:
	groups[group] = selection.duplicate()
	_last_group = -1

func select_group(group: int, current: Array[int], available: Array[int], additive: bool, now: float) -> Dictionary:
	var members: Array[int] = []
	for id: int in groups.get(group, []):
		if available.has(id) and not members.has(id): members.append(id)
	groups[group] = members.duplicate()
	if members.is_empty():
		_last_group = -1
		return {"selection":current.duplicate(), "changed":false, "locate":false}
	var result: Array[int] = []
	if additive: result.assign(current)
	for id: int in members:
		if not result.has(id): result.append(id)
	var locate := not additive and group == _last_group and now >= _last_time and now - _last_time <= DOUBLE_PRESS_SECONDS
	_last_group = group if not additive else -1
	_last_time = now
	return {"selection":result, "changed":true, "locate":locate}

func remove_unit(id: int) -> void:
	for group: int in groups: groups[group].erase(id)

func clear() -> void:
	groups.clear()
	_last_group = -1
	_last_time = -1.0
