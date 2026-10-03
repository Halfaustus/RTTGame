class_name ReplayFormat
extends RefCounted

const VERSION := 1
const MAX_INTEGER := 9007199254740991
const GAME_VERSION := "0.3C"


static func header(match_id: String, tick_hz: int, map_id: String, rules_id: String, seed: String, players: Array = [], fingerprints: Dictionary = {}) -> Dictionary:
	return {"format": "RTTReplay", "format_version": VERSION, "game_version": GAME_VERSION,
		"match_id": match_id, "tick_hz": tick_hz, "map_id": map_id, "rules_id": rules_id,
		"random_seed": seed, "players": players.duplicate(true), "content_fingerprints": fingerprints.duplicate(true)}


static func document(metadata: Dictionary, initial: Dictionary) -> Dictionary:
	return {"header": metadata.duplicate(true), "initial_state": initial.duplicate(true),
		"records": [], "snapshots": [], "last_tick": 0, "record_count": 0}


static func unit_state(state: UnitState, movement: MovementSimulation) -> Dictionary:
	var result := state.snapshot()
	result.position = [state.position.x, state.position.y, state.position.z]
	result.definition_id = state.definition.resource_path if state.definition != null and not state.definition.resource_path.is_empty() else "runtime/prototype-unit"
	result.command = movement.command_snapshot(state.unit_id)
	return result


static func request_integer(value: int) -> Variant:
	# Rejected int64 input must not make an otherwise valid recording unserializable.
	return value if value >= -MAX_INTEGER and value <= MAX_INTEGER else {"invalid_integer": str(value)}


static func serialize(data: Dictionary) -> Dictionary:
	var error := validate(data)
	return {"error": error, "text": JSON.stringify(data, "\t", true, true) if error.is_empty() else ""}


static func is_json_safe(value: Variant) -> bool:
	return _json_value(value)


static func deserialize(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()], "document": {}}
	if not parser.data is Dictionary:
		return {"error": "replay root must be an object", "document": {}}
	var error := validate(parser.data)
	return {"error": error, "document": parser.data if error.is_empty() else {}}


static func write_file(path: String, data: Dictionary) -> String:
	var encoded := serialize(data)
	if not encoded.error.is_empty():
		return encoded.error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot open replay for writing: %s" % FileAccess.get_open_error()
	file.store_string(encoded.text)
	file.flush()
	var error := file.get_error()
	file.close()
	return "" if error == OK else "replay write failed: %s" % error


static func read_file(path: String) -> Dictionary:
	if path.ends_with(".incomplete") or path.ends_with(".publishing"):
		return {"error": "staging/incomplete recording cannot be loaded as a complete replay", "document": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "cannot open replay for reading: %s" % FileAccess.get_open_error(), "document": {}}
	var text := file.get_as_text()
	var error := file.get_error()
	file.close()
	if error != OK:
		return {"error": "replay read failed: %s" % error, "document": {}}
	return deserialize(text)


static func validate(data: Dictionary) -> String:
	if not _json_value(data):
		return "unsupported/non-finite JSON value or unsafe integer"
	if not _fields(data, ["header", "initial_state", "records", "snapshots", "last_tick", "record_count"]) or not data.header is Dictionary:
		return "missing replay fields"
	var h: Dictionary = data.header
	if not _fields(h, ["format", "format_version", "game_version", "match_id", "tick_hz", "map_id", "rules_id", "random_seed", "players", "content_fingerprints"]):
		return "missing header fields"
	if h.format != "RTTReplay" or not _integer(h.format_version) or h.format_version != VERSION:
		return "unsupported replay format/version"
	for field: String in ["game_version", "match_id", "map_id", "rules_id"]:
		if not _text(h[field]):
			return "invalid header " + field
	if not _integer(h.tick_hz, 1) or h.tick_hz > 1000 or not _hex(h.random_seed, 16) or not h.content_fingerprints is Dictionary:
		return "invalid frequency/seed/fingerprints"
	for key: Variant in h.content_fingerprints:
		if not _text(key) or not _hex(h.content_fingerprints[key], 64):
			return "invalid content fingerprint"
	if not h.players is Array:
		return "invalid player roster"
	var players := {}
	for player: Variant in h.players:
		if not player is Dictionary or not _fields(player, ["player_id", "label"]) or not _integer(player.player_id, 1) or not _text(player.label) or players.has(int(player.player_id)):
			return "invalid/duplicate match player ID"
		players[int(player.player_id)] = true
	if not _integer(data.last_tick) or not data.records is Array or not data.snapshots is Array or not _integer(data.record_count) or data.record_count != data.records.size():
		return "invalid replay extent/count"
	var error := validate_checkpoint(data.initial_state, players)
	if not error.is_empty():
		return "initial: " + error
	if data.initial_state.through.tick != 0 or data.initial_state.through.sequence != -1:
		return "initial state must precede tick 1"
	var live := {}
	var retired := {}
	var connected := {}
	for unit: Dictionary in data.initial_state.units:
		live[int(unit.unit_id)] = unit.duplicate(true)
	for id: Variant in data.initial_state.retired_unit_ids:
		retired[int(id)] = true
	for id: Variant in data.initial_state.connected_player_ids:
		connected[int(id)] = true
	var next_id: int = data.initial_state.next_unit_id
	var states := {0: {"units": live.duplicate(true), "retired": retired.duplicate(), "connected": connected.duplicate(), "next": next_id, "sequence": -1}}
	var tick := 0
	var sequence := -1
	var phase_index := -1
	for record: Variant in data.records:
		if not record is Dictionary or not _fields(record, ["tick", "sequence", "phase", "kind", "type", "payload"]) or not _integer(record.tick, 1) or record.tick > data.last_tick or not _integer(record.sequence) or not record.payload is Dictionary:
			return "invalid record envelope"
		if record.tick < tick:
			return "record ticks out of order"
		if record.tick != tick:
			if tick > 0:
				states[tick] = {"units": live.duplicate(true), "retired": retired.duplicate(), "connected": connected.duplicate(), "next": next_id, "sequence": sequence}
			tick = int(record.tick)
			sequence = -1
			phase_index = -1
		var rank := SimulationTimeline.PHASES.find(record.phase)
		if rank < 0 or rank == 5 or rank < phase_index or record.sequence != sequence + 1:
			return "invalid/gapped sequence or phase order"
		sequence = int(record.sequence)
		phase_index = rank
		var payload: Dictionary = record.payload
		if record.kind == "command":
			error = _command(record, players)
			if error.is_empty():
				for id: Variant in payload.accepted_ids:
					if not live.has(int(id)) or live[int(id)].owner_player_id != payload.player_id or live[int(id)].owner_peer_id != payload.peer_id:
						return "accepted command violates ownership"
		elif record.kind == "event":
			match record.type:
				"player_join", "player_leave":
					if record.phase != "session" or not _fields(payload, ["player_id", "peer_id"]) or not _integer(payload.player_id, 1) or not players.has(int(payload.player_id)) or not _integer(payload.peer_id, 1):
						return "invalid player event"
					var player_id := int(payload.player_id)
					if record.type == "player_join":
						if connected.has(player_id):
							return "duplicate player join"
						connected[player_id] = true
					else:
						if not connected.has(player_id):
							return "leave for disconnected player"
						connected.erase(player_id)
				"spawn":
					if record.phase != "session":
						return "spawn outside session phase"
					error = _unit(payload, players)
					if error.is_empty():
						var id := int(payload.unit_id)
						if id < next_id or live.has(id) or retired.has(id):
							return "unit ID reused/non-monotonic"
						live[id] = payload.duplicate(true)
						next_id = id + 1
				"unit_state":
					if record.phase != "record":
						return "state outside record phase"
					error = _unit(payload, players)
					if error.is_empty():
						var id := int(payload.unit_id)
						if not live.has(id) or retired.has(id):
							return "state cannot create/revive a unit"
						if live[id].health <= 0:
							return "state cannot revive a zero-health unit"
						for field: String in ["owner_player_id", "team_id", "unit_type", "definition_id", "maximum_health", "armed"]:
							if payload[field] != live[id][field]:
								return "unit identity changed"
						live[id] = payload.duplicate(true)
				"shot":
					if record.phase != "combat" or not _fields(payload, ["attacker_id", "target_id", "start", "end", "health"]) or not _integer(payload.attacker_id, 1) or not _integer(payload.target_id, 1) or not live.has(int(payload.attacker_id)) or not live.has(int(payload.target_id)) or not _vector(payload.start) or not _vector(payload.end) or not _number(payload.health):
						return "invalid shot"
					var target: Dictionary = live[int(payload.target_id)]
					var attacker: Dictionary = live[int(payload.attacker_id)]
					if payload.health < 0 or payload.health > target.health or payload.attacker_id == payload.target_id or attacker.health <= 0 or target.health <= 0 or attacker.team_id == target.team_id or not attacker.armed:
						return "invalid absolute shot health"
					target.health = payload.health
				"death":
					if record.phase != "combat" or not _fields(payload, ["unit_id"]) or not _integer(payload.unit_id, 1) or not live.has(int(payload.unit_id)):
						return "invalid/duplicate death"
					var id := int(payload.unit_id)
					if live[id].health != 0:
						return "death without zero-health result"
					live.erase(id)
					retired[id] = true
				"random_result":
					if not _fields(payload, ["key", "result", "context"]) or not _text(payload.key) or not payload.context is Dictionary:
						return "invalid random result"
				_:
					return "unsupported event type"
		else:
			return "unsupported record kind"
		if not error.is_empty():
			return error
	if tick > 0:
		states[tick] = {"units": live.duplicate(true), "retired": retired.duplicate(), "connected": connected.duplicate(), "next": next_id, "sequence": sequence}
	var last_snapshot_tick := 0
	for checkpoint: Variant in data.snapshots:
		error = validate_checkpoint(checkpoint, players)
		if not error.is_empty():
			return "snapshot: " + error
		var at: int = checkpoint.through.tick
		if at <= last_snapshot_tick or at > data.last_tick:
			return "snapshot ticks out of order"
		last_snapshot_tick = at
		var state_tick := 0
		for candidate: int in states:
			if candidate <= at and candidate > state_tick:
				state_tick = candidate
		var expected: Dictionary = states[state_tick]
		var expected_sequence: int = expected.sequence if state_tick == at else -1
		if checkpoint.through.sequence != expected_sequence:
			return "snapshot must include the complete end of its tick"
		var actual_units := {}
		for unit: Dictionary in checkpoint.units:
			actual_units[int(unit.unit_id)] = unit
		if actual_units != expected.units or not _same_ids(checkpoint.retired_unit_ids, _sorted_keys(expected.retired)) or not _same_ids(checkpoint.connected_player_ids, _sorted_keys(expected.connected)) or checkpoint.next_unit_id < expected.next:
			return "snapshot contradicts recorded state/events"
		for record: Dictionary in data.records:
			if record.tick > at and record.type == "spawn" and record.payload.unit_id < checkpoint.next_unit_id:
				return "snapshot allocated ID reused later"
	if data.last_tick > 0 and last_snapshot_tick != data.last_tick:
		return "final tick checkpoint required"
	return ""


static func compatibility(data: Dictionary, map_id: String, rules_id: String, fingerprints: Dictionary) -> String:
	var error := validate(data)
	if not error.is_empty():
		return error
	if data.header.map_id != map_id or data.header.rules_id != rules_id:
		return "map/rules identifier mismatch"
	for key: String in data.header.content_fingerprints:
		if fingerprints.get(key, "") != data.header.content_fingerprints[key]:
			return "content fingerprint mismatch: " + key
	return ""


static func validate_checkpoint(value: Variant, players: Dictionary) -> String:
	if not value is Dictionary or not _fields(value, ["through", "units", "retired_unit_ids", "next_unit_id", "connected_player_ids"]) or not value.through is Dictionary or not _fields(value.through, ["tick", "sequence"]) or not _integer(value.through.tick) or not _integer(value.through.sequence, -1) or not value.units is Array or not value.retired_unit_ids is Array or not _integer(value.next_unit_id, 1) or not value.connected_player_ids is Array:
		return "invalid checkpoint"
	var used := {}
	var previous := 0
	for unit: Variant in value.units:
		var error := _unit(unit, players)
		if not error.is_empty():
			return error
		if unit.unit_id <= previous or unit.unit_id >= value.next_unit_id:
			return "checkpoint IDs not unique/sorted/allocated"
		previous = int(unit.unit_id)
		used[previous] = true
	previous = 0
	for id: Variant in value.retired_unit_ids:
		if not _integer(id, 1) or id <= previous or id >= value.next_unit_id or used.has(int(id)):
			return "invalid retired ID"
		previous = int(id)
	previous = 0
	for id: Variant in value.connected_player_ids:
		if not _integer(id, 1) or id <= previous or not players.has(int(id)):
			return "invalid connected player ID"
		previous = int(id)
	return ""


static func _unit(value: Variant, players: Dictionary) -> String:
	if not value is Dictionary or not _fields(value, ["unit_id", "owner_player_id", "owner_peer_id", "team_id", "position", "yaw", "maximum_health", "health", "unit_type", "armed", "definition_id", "command"]):
		return "missing unit fields"
	if not _integer(value.unit_id, 1) or not _integer(value.owner_player_id) or (value.owner_player_id != 0 and not players.has(int(value.owner_player_id))) or not _integer(value.owner_peer_id) or not _integer(value.team_id) or not _integer(value.unit_type) or int(value.unit_type) not in [0, 1] or not value.armed is bool or not _text(value.definition_id):
		return "invalid unit identity"
	if not _vector(value.position) or not _number(value.yaw) or not _number(value.maximum_health) or not _number(value.health) or value.maximum_health <= 0 or value.health <= 0 or value.health > value.maximum_health:
		return "invalid live unit pose/health"
	var c: Variant = value.command
	if not c is Dictionary or not _fields(c, ["mode", "target", "path", "final_yaw", "engaging"]) or not _integer(c.mode, -1) or int(c.mode) not in [-1, 0, 1, 2, 3] or not c.path is Array or not c.engaging is bool:
		return "invalid movement state"
	if c.mode == -1:
		if c.target != null or c.final_yaw != null or not c.path.is_empty() or c.engaging:
			return "stopped state contains a path/turn"
	else:
		if not _vector(c.target) or not _number(c.final_yaw) or c.path.is_empty() or (c.engaging and c.mode != 2):
			return "incomplete active movement state"
		if (c.mode == 2 and not value.armed) or (c.mode == 3 and value.unit_type != 1):
			return "movement state violates unit capability"
		for point: Variant in c.path:
			if not _vector(point):
				return "invalid path point"
		if c.path[0] != value.position or c.path[-1] != c.target:
			return "remaining path endpoints do not match state"
	return ""


static func _command(record: Dictionary, players: Dictionary) -> String:
	var p: Dictionary = record.payload
	if record.phase != "commands" or record.type not in ["move", "stop"] or not _fields(p, ["player_id", "peer_id", "unit_ids", "mode", "target", "facing", "accepted_ids", "failed_ids", "rejection"]) or not _integer(p.player_id, 1) or not players.has(int(p.player_id)) or not _integer(p.peer_id, 1) or not p.unit_ids is Array or not p.accepted_ids is Array or not p.failed_ids is Array or not (_integer(p.mode, -MAX_INTEGER) or _invalid_integer(p.mode)) or not p.rejection is String:
		return "invalid command record"
	for id: Variant in p.unit_ids:
		if not (_integer(id, -MAX_INTEGER) or _invalid_integer(id)):
			return "invalid requested unit ID"
	var accepted := {}
	for id: Variant in p.accepted_ids:
		if not _integer(id, 1) or not p.unit_ids.has(id) or accepted.has(int(id)):
			return "invalid accepted ID"
		accepted[int(id)] = true
	for id: Variant in p.failed_ids:
		if not _integer(id, 1) or not p.unit_ids.has(id) or accepted.has(int(id)):
			return "invalid failed ID"
	if record.type == "stop":
		if p.mode != -1 or p.target != null or p.facing != null:
			return "stop contains movement input"
	else:
		if not p.accepted_ids.is_empty() and (not _integer(p.mode, -MAX_INTEGER) or int(p.mode) not in [0, 1, 2, 3] or not _vector(p.target) or not _vector(p.facing) or not is_zero_approx(float(p.facing[1]))):
			return "accepted invalid movement input"
		if p.target != null and not _vector(p.target):
			return "invalid command target representation"
		if p.facing != null and not _vector(p.facing):
			return "invalid command facing representation"
	if p.accepted_ids.is_empty() and p.rejection.is_empty():
		return "empty command result lacks rejection"
	return ""


static func _fields(value: Dictionary, names: Array) -> bool:
	for name: String in names:
		if not value.has(name):
			return false
	return true


static func _integer(value: Variant, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(value) and value >= minimum and value <= MAX_INTEGER


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _invalid_integer(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 1 or not value.has("invalid_integer") or not value.invalid_integer is String or not value.invalid_integer.is_valid_int():
		return false
	var number: int = value.invalid_integer.to_int()
	return str(number) == value.invalid_integer and (number < -MAX_INTEGER or number > MAX_INTEGER)


static func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and _number(value[0]) and _number(value[1]) and _number(value[2])


static func _text(value: Variant) -> bool:
	return value is String and not value.is_empty()


static func _hex(value: Variant, length: int) -> bool:
	if not value is String or value.length() != length:
		return false
	for i: int in length:
		if not value.substr(i, 1) in "0123456789abcdef":
			return false
	return true


static func _json_value(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	if value == null or value is bool or value is String:
		return true
	if value is int:
		return value >= -MAX_INTEGER and value <= MAX_INTEGER
	if value is float:
		return is_finite(value)
	if value is Array:
		for entry: Variant in value:
			if not _json_value(entry, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not (key is String or key is StringName) or not _json_value(value[key], depth + 1):
				return false
		return true
	return false


static func _sorted_keys(value: Dictionary) -> Array:
	var ids := value.keys()
	ids.sort()
	return ids


static func _same_ids(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if int(a[i]) != int(b[i]):
			return false
	return true
