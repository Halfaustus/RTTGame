class_name ReplayPresentation
extends RefCounted

# A data adapter, not a player: no clock, scene loading, AI, input or networking.
var feed := PresentationFeed.new()
var view_player_id := 0
var _document: Dictionary = {}
var _cursor := {"tick": 0, "sequence": -1}
var _next_record := 0
var _checkpoint_applied := false
var _states: Dictionary[int, Dictionary] = {}


func open(data: Dictionary, player_id: int = 0) -> String:
	var error := ReplayFormat.validate(data)
	if not error.is_empty():
		return error
	if player_id != 0 and not data.header.players.any(func(player: Dictionary): return player.player_id == player_id):
		return "unknown view player"
	_document = data.duplicate(true)
	view_player_id = player_id
	_checkpoint_applied = false
	return ""


func apply_checkpoint(index: int = -1) -> bool:
	if _document.is_empty() or index < -1 or index >= _document.snapshots.size():
		return false
	var checkpoint: Dictionary = _document.initial_state if index == -1 else _document.snapshots[index]
	_cursor = checkpoint.through.duplicate()
	_checkpoint_applied = true
	_next_record = 0
	while _next_record < _document.records.size() and _covered(_document.records[_next_record]):
		_next_record += 1
	feed.reset_received.emit()
	_states.clear()
	for state: Dictionary in checkpoint.units:
		_states[int(state.unit_id)] = state.duplicate(true)
		feed.apply_replay_unit(state)
	return true


func apply_record(record: Dictionary) -> bool:
	if not _checkpoint_applied or not record.has("tick") or not record.has("sequence") or _next_record >= _document.records.size():
		return false
	if record != _document.records[_next_record]:
		return false
	# Commands are audit data. Never resimulate orders or damage on a replay view.
	if record.kind == "event":
		match record.type:
			"spawn", "unit_state":
				_states[int(record.payload.unit_id)] = record.payload.duplicate(true)
				feed.apply_replay_unit(record.payload)
			"shot":
				var shot: Dictionary = record.payload.duplicate(true)
				shot.start = PresentationFeed.vector(shot.start)
				shot.end = PresentationFeed.vector(shot.end)
				if _states.has(int(shot.target_id)):
					_states[int(shot.target_id)].health = shot.health
				feed.apply_shot(shot)
			"death":
				_states.erase(int(record.payload.unit_id))
				feed.unit_death_received.emit(record.payload.unit_id)
	_cursor = {"tick": record.tick, "sequence": record.sequence}
	_next_record += 1
	return true


func cursor() -> Dictionary:
	return _cursor.duplicate()


func apply_through_tick(tick: int) -> bool:
	while _next_record < _document.records.size() and _document.records[_next_record].tick <= tick:
		if not apply_record(_document.records[_next_record]):
			return false
	return true


func applied_record_count() -> int:
	return _next_record


func display_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids := _states.keys()
	ids.sort()
	for id: int in ids:
		result.append(_states[id].duplicate(true))
	return result


func refresh_display() -> void:
	# Same current state only; no cursor changes, old shots or authoritative actions.
	for state: Dictionary in display_states():
		feed.apply_replay_unit(state)


func _covered(record: Dictionary) -> bool:
	return record.tick < _cursor.tick or (record.tick == _cursor.tick and record.sequence <= _cursor.sequence)
