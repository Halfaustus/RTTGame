class_name CombatEventOrder
extends RefCounted

# User-confirmed 0.6A cross-domain tie contract. Exact event timestamps are used;
# this does not alter the existing collision-query tolerance or object ties.
static func before(a: Dictionary,b: Dictionary) -> bool:
	if a.time_seconds != b.time_seconds: return a.time_seconds < b.time_seconds
	if a.unit_id != b.unit_id: return a.unit_id < b.unit_id
	if a.weapon_instance_id != b.weapon_instance_id: return a.weapon_instance_id < b.weapon_instance_id
	if a.source_event_id != b.source_event_id: return a.source_event_id < b.source_event_id
	# Same lifecycle: emission must causally precede its zero-duration terminal.
	return int(a.get("terminal",false)) < int(b.get("terminal",false))
