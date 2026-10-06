class_name SquadWeaponChannels
extends RefCounted

# Physical sources carry ammunition and operator links, never firing timers.
var owner: WeakRef
var sources: Array[Dictionary] = []
var channels: Dictionary = {}
var source_groups: Dictionary = {}
var alive: Dictionary = {}
# Runtime indexes, not unit configuration fields. Built once per configuration.
var candidates: Array[Array] = []
var member_watchers: Dictionary = {}
var occupied: Dictionary = {}
var watchers: Dictionary = {}
var carriers: Dictionary = {}
var pending: Array[int] = []
var queued: Dictionary = {}
var profile := {"events":0,"candidate_builds":0,"candidate_visits":0,"source_updates":0,"channel_updates":0}

func _init(state: UnitState) -> void:
	owner = weakref(state)
	for allocation: WeaponAllocation in state.definition.weapon_allocations:
		if allocation.node_kind != WeaponAllocation.NodeKind.SOLDIER: continue
		var model := allocation.definition.definition_id
		var channel: RuntimeWeaponInstance = channels.get(model)
		var slot_definition := WeaponSlotDefinition.new()
		slot_definition.slot_id = allocation.slot_id
		slot_definition.weapon = allocation.definition
		slot_definition.direction_primary = allocation.direction_primary
		slot_definition.orientation_priority = allocation.orientation_priority
		var slot := WeaponSlotState.new(slot_definition,allocation.node_kind,str(allocation.member_id))
		state.runtime_slots.append(slot)
		state.members[allocation.member_id-1].weapon_slots.append(slot_definition)
		if channel == null:
			channel = RuntimeWeaponInstance.new(state,slot,state.members[allocation.member_id-1])
			channel.instance_id = "%s/squad/%s/%s" % [state.unit_id,state.definition.configuration_source,model]
			channel.configured_count = 0
			channel.squad_channel = weakref(self)
			channels[model] = channel
			source_groups[channel.instance_id] = []
			state.runtime_weapons.append(channel)
		channel.configured_count += 1
		slot.runtime_weapon = channel
		var inventory := allocation.initial_inventory.duplicate(true)
		for id: String in inventory: channel.inventory[id] = channel.inventory.get(id,0)+inventory[id]
		var slots: Array[String] = []
		slots.assign(allocation.occupied_slots if not allocation.occupied_slots.is_empty() else [allocation.slot_id])
		sources.append({"id":"%s/%s" % [allocation.member_id,allocation.slot_id],"member":allocation.member_id,"carrier":allocation.member_id,"channel":channel,"slot":slot,"slots":slots,"inventory":inventory,"priority":allocation.retention_priority,"operators":[]})
	sources.sort_custom(func(a: Dictionary,b: Dictionary): return a.priority < b.priority if a.priority != b.priority else a.id.naturalnocasecmp_to(b.id) < 0)
	for source: Dictionary in sources: source_groups[source.channel.instance_id].append(source)
	for channel: RuntimeWeaponInstance in channels.values(): channel.initialize_first_magazine()
	for member: SoldierState in state.members:
		alive[member.member_id] = member.health > 0
		member_watchers[member.member_id] = {}
		carriers[member.member_id] = {}
	for index: int in sources.size():
		var source := sources[index]
		var ordered: Array[int] = [source.member]
		if source.channel.definition.squad_weapon:
			for member: SoldierState in state.members:
				if member.member_id != source.member: ordered.append(member.member_id)
		candidates.append(ordered)
		profile.candidate_builds += 1
		carriers[source.carrier][index] = true
		_enqueue(index)
	_drain({})
	for member: SoldierState in state.members: member.living_changed.connect(_living_changed)

func refresh() -> void:
	pass # Compatibility entry: health setters already deliver authoritative events.

func detach() -> void:
	var state: UnitState = owner.get_ref()
	if state == null: return
	for member: SoldierState in state.members:
		if member.living_changed.is_connected(_living_changed): member.living_changed.disconnect(_living_changed)

func _enqueue(index: int) -> void:
	if queued.has(index): return
	queued[index] = true
	# Integer priority index, no runtime comparator or configuration sort.
	var at := pending.bsearch(index)
	pending.insert(at,index)

func _living_changed(member_id: int, living: bool) -> void:
	if owner.get_ref() == null: return
	alive[member_id] = living
	profile.events += 1
	var touched := {}
	if not living:
		for index: int in carriers[member_id].keys():
			var source := sources[index]
			for id: String in source.inventory:
				source.channel.inventory[id] = maxi(0,int(source.channel.inventory.get(id,0))-int(source.inventory[id]))
				source.inventory[id] = 0
			touched[source.channel.instance_id] = source.channel
	# Only current operators are affected by death; revival may restore an earlier
	# candidate. Candidate dependencies are cached at configuration time.
	for index: int in member_watchers[member_id].keys():
		var source := sources[index]
		if living or source.operators.has(member_id) or source.member == member_id: _enqueue(index)
	_drain(touched)

func _drain(touched: Dictionary) -> void:
	var state: UnitState = owner.get_ref()
	while not pending.is_empty():
		var index: int = pending.pop_front()
		queued.erase(index)
		var source := sources[index]
		var old: Array = source.operators.duplicate()
		for member_id: int in source.get("watched_members",[]): member_watchers[member_id].erase(index)
		for key: String in source.get("watch_keys",[]): watchers[key].erase(index)
		source.watched_members = []
		source.watch_keys = []
		for member_id: int in old:
			for slot_id: String in source.slots:
				var key := "%s/%s" % [member_id,slot_id]
				if occupied.get(key,-1) == index: occupied.erase(key)
		var selected: Array[int] = []
		var required: int = source.channel.definition.required_operators
		var valid: bool = source.priority >= 0 and state.definition.configuration_source != "unconfigured" and required > 0
		# A missing priority in this model invalidates its operation configuration.
		for peer: Dictionary in source_groups[source.channel.instance_id]:
			if peer.priority < 0: valid = false
		if valid:
			for member_id: int in candidates[index]:
				profile.candidate_visits += 1
				member_watchers[member_id][index] = true
				source.watched_members.append(member_id)
				var free := true
				for slot_id: String in source.slots:
					var key := "%s/%s" % [member_id,slot_id]
					if not watchers.has(key): watchers[key] = {}
					watchers[key][index] = true
					source.watch_keys.append(key)
					if occupied.has(key) and occupied[key] < index: free = false
				if not alive[member_id] or not free: continue
				selected.append(member_id)
				if selected.size() == required: break
		if selected.size() != required or not valid: selected.clear()
		source.operators = selected
		profile.source_updates += 1
		if not selected.is_empty():
			carriers[source.carrier].erase(index)
			source.carrier = selected[0]
			carriers[source.carrier][index] = true
		for member_id: int in selected:
			for slot_id: String in source.slots: occupied["%s/%s" % [member_id,slot_id]] = index
		if old != selected:
			for member_id: int in old + selected:
				for slot_id: String in source.slots:
					for dependent: int in watchers.get("%s/%s" % [member_id,slot_id],{}):
						if dependent > index: _enqueue(dependent)
		touched[source.channel.instance_id] = source.channel
	for channel: RuntimeWeaponInstance in touched.values():
		channel.operable_count = 0
		channel.operator_reason = "operators_insufficient" if channel.definition.required_operators > 0 else "operator_configuration_missing"
		if state.definition.configuration_source == "unconfigured": channel.operator_reason = "source_configuration_missing"
		for source: Dictionary in source_groups[channel.instance_id]:
			if source.priority < 0: channel.operator_reason = "operator_configuration_missing"
			if source.operators.is_empty(): continue
			if channel.operable_count == 0:
				channel.node = weakref(state.members[source.carrier-1])
				channel.node_id = str(source.carrier)
				channel.slot = weakref(source.slot)
			channel.operable_count += 1
		if channel.operable_count > 0: channel.operator_reason = "eligible"
		var stock := 0
		for count: int in channel.inventory.values(): stock += count
		channel.pending_rounds = mini(channel.pending_rounds,stock)
		profile.channel_updates += 1
		var issues := inventory_issues(channel)
		if not issues.is_empty():
			channel.operator_reason = "inventory_accounting_invalid"
			push_error("Squad inventory invariant: "+str(issues))

func consume(channel: RuntimeWeaponInstance, ammo_id: String, count: int) -> void:
	# Stable source order is accounting only; one channel commits one shot.
	for source: Dictionary in source_groups[channel.instance_id]:
		var debit := mini(count,int(source.inventory.get(ammo_id,0)))
		source.inventory[ammo_id] = int(source.inventory.get(ammo_id,0))-debit
		count -= debit
		if count == 0: return
	if count != 0:
		channel.operator_reason = "inventory_accounting_invalid"
		push_error("Source quota cannot cover committed channel debit: "+channel.instance_id)


# Stable-boundary invariant, per channel AND per ammo:
# sum(source.inventory[ammo]) == channel.inventory[ammo].
# Pending/loaded rounds are INCLUDED in that total; in-flight shots have
# already been debited. No third stock authority or per-tick ledger scan.
# During RuntimeWeaponInstance.consume, aggregate debit precedes source debit,
# and caller updates pending after return: use check_pending=false at that
# intermediate boundary. Full checks belong after the complete emission.
func inventory_issues(channel: RuntimeWeaponInstance,check_pending: bool = true) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var path := "channels."+channel.instance_id
	if channels.get(channel.definition.definition_id) != channel or not source_groups.has(channel.instance_id):
		return [{"path":path,"code":"unknown_channel","message":"Channel is not owned by this ledger"}]
	var totals := {}
	for source: Dictionary in source_groups[channel.instance_id]:
		for ammo_id: Variant in source.inventory:
			var count: Variant = source.inventory[ammo_id]
			if not count is int or count < 0:
				issues.append({"path":path+".sources."+source.id+"."+str(ammo_id),"code":"invalid_source_stock","message":"Source quota must be a nonnegative integer"})
				continue
			totals[ammo_id] = totals.get(ammo_id,0)+count
	var keys := totals.keys()
	for ammo_id: Variant in channel.inventory:
		if not keys.has(ammo_id): keys.append(ammo_id)
	var total := 0
	for ammo_id: Variant in keys:
		var count: Variant = channel.inventory.get(ammo_id,0)
		if not count is int or count < 0:
			issues.append({"path":path+".inventory."+str(ammo_id),"code":"invalid_channel_stock","message":"Channel stock must be a nonnegative integer"})
			continue
		total += count
		if count != totals.get(ammo_id,0):
			issues.append({"path":path+".inventory."+str(ammo_id),"code":"inventory_ledger_mismatch","channel_remaining":count,"source_remaining":totals.get(ammo_id,0),"message":"Source quota sum differs from channel total"})
	if check_pending and (channel.pending_rounds < 0 or channel.pending_rounds > mini(maxi(0,channel.pending_capacity()),total)):
		issues.append({"path":path+".pending_rounds","code":"pending_outside_stock","message":"Ready count must stay within capacity and total stock, never added to it"})
	return issues

func all_inventory_issues() -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	for channel: RuntimeWeaponInstance in channels.values(): issues.append_array(inventory_issues(channel))
	return issues
