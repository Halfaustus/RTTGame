class_name FiringFrame
extends RefCounted

# Internal shared sampling for one physical interval; no unit configuration.
var time_seconds := 0.0
var weapons: Dictionary = {}
var units: Dictionary = {}
var motion: ProjectileUnitMotion
var members: Dictionary = {}
var movement: MovementSimulation
var overpenetration_enabled := false

func begin(at: float,aiming: AimingSimulation,capture_members: bool = false) -> void:
	time_seconds = at
	for unit: UnitState in aiming.units.values():
		if capture_members:
			members[unit.unit_id] = {}
			for member: SoldierState in unit.members:
				members[unit.unit_id][member.member_id] = {"start":member.position,"end":member.position,"at":at,"yaw":member.aim_yaw,"end_yaw":member.aim_yaw}
		units[unit.unit_id] = {"start":unit.position,"end":unit.position,"yaw":unit.yaw,"end_yaw":unit.yaw,"at":at,"speed_multiplier":unit.personnel_speed_multiplier,"moving":aiming.moving.call(unit.unit_id) if aiming.moving.is_valid() else false}
		for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
			weapons[weapon.instance_id] = {"start":weapon.world_position(),"end":weapon.world_position(),"yaw":weapon.world_yaw(),"end_yaw":weapon.world_yaw(),"progress":weapon.aim_progress,"ready":INF,"eligible":aiming.eligibility(weapon) == "eligible"}

func finish(aiming: AimingSimulation,value: ProjectileUnitMotion) -> void:
	motion = value
	for unit: UnitState in aiming.units.values():
		if members.has(unit.unit_id):
			for member: SoldierState in unit.members:
				members[unit.unit_id][member.member_id].end = member.position
				members[unit.unit_id][member.member_id].end_yaw = member.aim_yaw
		units[unit.unit_id].end = unit.position
		units[unit.unit_id].end_yaw = unit.yaw
		for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
			var row: Dictionary = weapons[weapon.instance_id]
			row.end = weapon.world_position()
			row.end_yaw = weapon.world_yaw()
			if not row.eligible or not weapon.aim_timer_complete: continue
			var inputs: Dictionary = aiming.inputs.get(unit.unit_id,{})
			var duration := weapon.sampled_aim_seconds*float(inputs.get("aim_time_multiplier",1.0))
			var aim_wait := maxf(0.0,(1.0-float(row.progress))*duration)
			var node := weapon.spatial_node()
			var speed: float = node.rotation_speed_degrees if node is WeaponMountState else unit.definition.member_aim_speed_degrees
			if weapon.node_kind == WeaponAllocation.NodeKind.HULL: speed = unit.definition.turn_speed_degrees
			var angle := maxf(0.0,absf(wrapf(weapon.desired_yaw-float(row.yaw),-PI,PI))-deg_to_rad(Prototype05DCatalog.AIM_TOLERANCE_DEGREES))
			var turn_wait := angle/deg_to_rad(speed) if speed > 0 else (0.0 if angle == 0 else INF)
			row.ready = time_seconds+maxf(aim_wait,turn_wait)

func fraction(at: float) -> float:
	return clampf((at-time_seconds)/GravityBallistics.STEP_SECONDS,0.0,1.0)

func unit_fraction(id: int,at: float) -> float:
	var start: float = units[id].get("at",time_seconds)
	var duration := time_seconds+GravityBallistics.STEP_SECONDS-start
	return clampf((at-start)/duration,0.0,1.0) if duration > 0 else 1.0

func pose(weapon: RuntimeWeaponInstance,at: float) -> Dictionary:
	var row: Dictionary = weapons[weapon.instance_id]
	var f := fraction(at)
	var row_start: float = row.get("at",time_seconds)
	var row_duration: float = time_seconds+GravityBallistics.STEP_SECONDS-row_start
	var weapon_fraction := clampf((at-row_start)/row_duration,0.0,1.0) if row_duration > 0 else 1.0
	var yaw := lerp_angle(float(row.yaw),float(row.end_yaw),weapon_fraction)
	var node := weapon.spatial_node()
	# Aiming turns at its actual bounded angular rate, then holds final yaw.
	if weapon.node_kind != WeaponAllocation.NodeKind.HULL:
		var speed: float = node.rotation_speed_degrees if node is WeaponMountState else weapon.owner_state().definition.member_aim_speed_degrees
		var difference := wrapf(float(row.end_yaw)-float(row.yaw),-PI,PI)
		yaw = float(row.yaw)+clampf(difference,-deg_to_rad(speed)*(at-row_start),deg_to_rad(speed)*(at-row_start))
	var target := weapon.target.position()
	var velocity := Vector3.ZERO
	var target_yaw := 0.0
	if weapon.target.kind == AttackTarget.Kind.UNIT:
		var target_row: Dictionary = units[weapon.target.unit_id]
		var target_fraction := unit_fraction(weapon.target.unit_id,at)
		target = target_row.start.lerp(target_row.end,target_fraction)
		var target_duration: float = time_seconds+GravityBallistics.STEP_SECONDS-float(target_row.get("at",time_seconds))
		velocity = (target_row.end-target_row.start)/target_duration if target_duration > 0 else Vector3.ZERO
		target_yaw = lerp_angle(float(target_row.yaw),float(target_row.end_yaw),target_fraction)
	var position: Vector3 = row.start.lerp(row.end,weapon_fraction)
	return {"position":position,"yaw":yaw,"target":target,"target_velocity":velocity,"target_yaw":target_yaw,"ready":row.ready,"moving":units[weapon.owner_state().unit_id].moving or row.start != row.end,"overpenetration_enabled":overpenetration_enabled}

func friendly_clear(weapon: RuntimeWeaponInstance,start: Vector3,end: Vector3,at: float) -> bool:
	if weapon.target.kind == AttackTarget.Kind.FORCED_GROUND: return true
	# Use the existing spatial index, but freeze candidate poses at emission time.
	if motion == null or not motion.ready: return false
	var hit := {}
	var bounds := AABB(start,Vector3.ZERO).expand(end)
	var candidates := {}
	for cell: Vector3i in ProjectileUnitMotion._covered(bounds):
		for id: Variant in motion.cells.get(cell,[]):
			if int(id) != weapon.owner_state().unit_id: candidates[id] = true
	for id: Variant in candidates:
		var record: Dictionary = motion.records[id]
		var local_fraction := motion.record_fraction(record,at)
		var center: Vector3 = record.start.lerp(record.end,local_fraction)
		var basis: Basis = record.basis.slerp(record.end_basis,local_fraction)
		var extents: Vector3 = record.extents.lerp(record.end_extents,local_fraction)
		var contact := ProjectileUnitMotion._box(basis.inverse()*(start-center),basis.inverse()*(end-center),extents)
		if contact.is_empty(): continue
		if hit.is_empty() or contact.fraction < hit.fraction or (contact.fraction == hit.fraction and record.object_id < hit.object_id):
			hit = {"fraction":contact.fraction,"object_id":record.object_id,"team_id":record.team_id}
	return hit.is_empty() or hit.team_id != weapon.owner_state().team_id

func member_positions(id: int,at: float) -> Dictionary:
	var result := {}
	for member_id: int in members.get(id,{}):
		var row: Dictionary = members[id][member_id]
		var remaining: float = time_seconds+GravityBallistics.STEP_SECONDS-float(row.at)
		var f := clampf((at-float(row.at))/remaining,0.0,1.0) if remaining > 0 else 1.0
		result[member_id] = row.start.lerp(row.end,f)
	return result

func casualty_pose(weapon: RuntimeWeaponInstance,at: float,positions: Dictionary) -> Dictionary:
	if weapon.target == null: return {}
	var owner := weapon.owner_state()
	var node: SoldierState = weapon.spatial_node()
	var yaw: float = members[owner.unit_id][node.member_id].yaw
	var target := weapon.target.position()
	if weapon.target.kind == AttackTarget.Kind.UNIT:
		var target_row: Dictionary = units[weapon.target.unit_id]
		target = target_row.start.lerp(target_row.end,unit_fraction(weapon.target.unit_id,at))
	return {"position":positions[node.member_id]+weapon.slot_state().definition.local_position.rotated(Vector3.UP,yaw),
		"target":target,"moving":units[owner.unit_id].moving,"yaw":yaw}

# Only the damaged unit is replayed from its event pose through the remaining
# existing member-follow rule. Hull path/speed and aim/loading fractions persist.
func refresh_casualty(unit: UnitState,at: float,aiming: AimingSimulation,old_inputs: Dictionary = {},rate_changed: bool = false) -> Dictionary:
	if unit.unit_type() == UnitDefinition.UnitType.ARMORED_VEHICLE:
		return refresh_vehicle(unit,at,aiming,old_inputs)
	var positions := member_positions(unit.unit_id,at)
	var remaining := maxf(0.0,time_seconds+GravityBallistics.STEP_SECONDS-at)
	for member: SoldierState in unit.members:
		member.position = positions[member.member_id]
		var row: Dictionary = members[unit.unit_id][member.member_id]
		var duration: float = time_seconds+GravityBallistics.STEP_SECONDS-float(row.at)
		var f := clampf((at-float(row.at))/duration,0.0,1.0) if duration > 0 else 1.0
		member.aim_yaw = lerp_angle(row.yaw,row.end_yaw,f)
		row.start = member.position
		row.yaw = member.aim_yaw
		row.at = at
	var body: Dictionary = units[unit.unit_id]
	var saved_position := unit.position
	var saved_yaw := unit.yaw
	unit.position = body.start.lerp(body.end,unit_fraction(unit.unit_id,at))
	unit.yaw = lerp_angle(body.yaw,body.end_yaw,unit_fraction(unit.unit_id,at))
	var before := ProjectileUnitMotion.capture({unit.unit_id:unit})
	if unit.health <= 0:
		body.end = unit.position
		body.end_yaw = unit.yaw
		return {"before":{},"after":{}}
	if rate_changed:
		var segment := body.duplicate()
		body.start = unit.position
		body.yaw = unit.yaw
		body.at = at
		if movement != null:
			movement.resample_unit(unit.unit_id,remaining,segment,at)
		else:
			unit.advance_members(remaining)
		body.end = unit.position
		body.end_yaw = unit.yaw
		body.speed_multiplier = unit.personnel_speed_multiplier
	else:
		unit.position = saved_position
		unit.yaw = saved_yaw
		unit.advance_members(remaining)
	for member: SoldierState in unit.members:
		members[unit.unit_id][member.member_id].end = member.position
	var drivers := {}
	for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
		var node := weapon.spatial_node()
		if not node is SoldierState: continue
		var event_pose := casualty_pose(weapon,at,positions)
		if aiming.eligibility(weapon,event_pose) != "eligible": continue
		weapon.desired_direction = event_pose.target-event_pose.position
		if weapon.desired_direction.length_squared() > 0:
			weapon.desired_yaw = atan2(-weapon.desired_direction.x,-weapon.desired_direction.z)
		if not drivers.has(node.member_id) or aiming._preferred(weapon,drivers[node.member_id]): drivers[node.member_id] = weapon
	for driver: RuntimeWeaponInstance in drivers.values():
		var node: SoldierState = driver.spatial_node()
		var speed := deg_to_rad(unit.definition.member_aim_speed_degrees)
		node.aim_yaw += clampf(wrapf(driver.desired_yaw-node.aim_yaw,-PI,PI),-speed*remaining,speed*remaining)
	for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
		var row: Dictionary = weapons[weapon.instance_id]
		var node := weapon.spatial_node()
		if not node is SoldierState: continue
		var old_at: float = row.get("at",time_seconds)
		row.at = at
		row.yaw = members[unit.unit_id][node.member_id].yaw
		row.start = positions[node.member_id]+weapon.slot_state().definition.local_position.rotated(Vector3.UP,row.yaw)
		# Recover this channel's timer at the event; keep its completed fraction.
		var aim_duration: float = weapon.sampled_aim_seconds*float((old_inputs if rate_changed else aiming.inputs.get(unit.unit_id,{})).get("aim_time_multiplier",1.0))
		var progress: float = row.progress
		if row.eligible and aim_duration > 0: progress = minf(1.0,progress+(at-old_at)/aim_duration)
		aim_duration = weapon.sampled_aim_seconds*float(aiming.inputs.get(unit.unit_id,{}).get("aim_time_multiplier",1.0))
		var eligible := aiming.eligibility(weapon,casualty_pose(weapon,at,positions)) == "eligible"
		if eligible and weapon.sampled_aim_seconds < 0:
			weapon.sampled_aim_seconds = aiming.random.randf_range(weapon.definition.aim_min_seconds,weapon.definition.aim_max_seconds)
			aim_duration = weapon.sampled_aim_seconds*float(aiming.inputs.get(unit.unit_id,{}).get("aim_time_multiplier",1.0))
		if eligible:
			weapon.aim_progress = 1.0 if aim_duration == 0 else minf(1.0,progress+remaining/aim_duration)
			weapon.aim_timer_complete = weapon.aim_progress >= 1.0
		var difference := wrapf(weapon.desired_yaw-float(row.yaw),-PI,PI)
		var speed := deg_to_rad(unit.definition.member_aim_speed_degrees)
		row.end = weapon.world_position()
		row.end_yaw = node.aim_yaw
		var angle := maxf(0.0,absf(difference)-deg_to_rad(Prototype05DCatalog.AIM_TOLERANCE_DEGREES))
		var aim_wait := maxf(0.0,(1.0-progress)*aim_duration)
		row.ready = at+maxf(aim_wait,angle/speed) if eligible and speed > 0 else INF
		row.progress = progress
		row.eligible = eligible
	for member: SoldierState in unit.members:
		members[unit.unit_id][member.member_id].end_yaw = member.aim_yaw
	return {"before":before,"after":ProjectileUnitMotion.capture({unit.unit_id:unit})}

func refresh_vehicle(unit: UnitState,at: float,aiming: AimingSimulation,old_inputs: Dictionary) -> Dictionary:
	var remaining := maxf(0.0,time_seconds+GravityBallistics.STEP_SECONDS-at)
	var body: Dictionary = units[unit.unit_id]
	var segment := body.duplicate()
	unit.position = body.start.lerp(body.end,unit_fraction(unit.unit_id,at))
	unit.yaw = lerp_angle(body.yaw,body.end_yaw,unit_fraction(unit.unit_id,at))
	var before := ProjectileUnitMotion.capture({unit.unit_id:unit})
	if unit.health <= 0: return {"before":{},"after":{}}
	var poses := {}
	for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
		if weapon.target != null: poses[weapon.instance_id] = pose(weapon,at)
	body.start = unit.position
	body.yaw = unit.yaw
	body.at = at
	if movement != null: movement.resample_unit(unit.unit_id,remaining,segment,at)
	body.end = unit.position
	body.end_yaw = unit.yaw
	body.speed_multiplier = unit.personnel_speed_multiplier
	for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
		if not poses.has(weapon.instance_id): continue
		var row: Dictionary = weapons[weapon.instance_id]
		var sampled: Dictionary = poses[weapon.instance_id]
		if weapon.spatial_node() is WeaponMountState: weapon.spatial_node().world_yaw = row.end_yaw
		var old_at: float = row.get("at",time_seconds)
		var progress: float = row.progress
		var duration := weapon.sampled_aim_seconds*float(old_inputs.get("aim_time_multiplier",1.0))
		if row.eligible and duration > 0: progress = minf(1.0,progress+(at-old_at)/duration)
		duration = weapon.sampled_aim_seconds*float(aiming.inputs.get(unit.unit_id,{}).get("aim_time_multiplier",1.0))
		var eligible := aiming.eligibility(weapon,sampled) == "eligible"
		if eligible:
			weapon.aim_progress = 1.0 if duration == 0 else minf(1.0,progress+remaining/duration)
			weapon.aim_timer_complete = weapon.aim_progress >= 1.0
		row.progress = progress
		row.at = at
		row.start = sampled.position
		row.yaw = sampled.yaw
		row.end = weapon.world_position()
		row.end_yaw = weapon.world_yaw()
		row.eligible = eligible
		# Rotation remains bounded and independent of module timing. Retain its
		# existing orientation readiness, replacing only the aim-duration debt.
		var node := weapon.spatial_node()
		var speed: float = node.rotation_speed_degrees if node is WeaponMountState else unit.definition.turn_speed_degrees
		var angle := maxf(0.0,absf(wrapf(weapon.desired_yaw-float(row.yaw),-PI,PI))-deg_to_rad(Prototype05DCatalog.AIM_TOLERANCE_DEGREES))
		row.ready = at+maxf(maxf(0.0,(1.0-progress)*duration),angle/deg_to_rad(speed)) if eligible and speed > 0 else INF
	return {"before":before,"after":ProjectileUnitMotion.capture({unit.unit_id:unit})}
