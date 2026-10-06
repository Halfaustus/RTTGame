class_name FiringFrame
extends RefCounted

# Internal shared sampling for one physical interval; no unit configuration.
var time_seconds := 0.0
var weapons: Dictionary = {}
var units: Dictionary = {}
var motion: ProjectileUnitMotion

func begin(at: float,aiming: AimingSimulation) -> void:
	time_seconds = at
	for unit: UnitState in aiming.units.values():
		units[unit.unit_id] = {"start":unit.position,"end":unit.position,"yaw":unit.yaw,"end_yaw":unit.yaw,"moving":aiming.moving.call(unit.unit_id) if aiming.moving.is_valid() else false}
		for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
			weapons[weapon.instance_id] = {"start":weapon.world_position(),"end":weapon.world_position(),"yaw":weapon.world_yaw(),"end_yaw":weapon.world_yaw(),"progress":weapon.aim_progress,"ready":INF,"eligible":aiming.eligibility(weapon) == "eligible"}

func finish(aiming: AimingSimulation,value: ProjectileUnitMotion) -> void:
	motion = value
	for unit: UnitState in aiming.units.values():
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

func pose(weapon: RuntimeWeaponInstance,at: float) -> Dictionary:
	var row: Dictionary = weapons[weapon.instance_id]
	var f := fraction(at)
	var yaw := lerp_angle(float(row.yaw),float(row.end_yaw),f)
	var node := weapon.spatial_node()
	# Aiming turns at its actual bounded angular rate, then holds final yaw.
	if weapon.node_kind != WeaponAllocation.NodeKind.HULL:
		var speed: float = node.rotation_speed_degrees if node is WeaponMountState else weapon.owner_state().definition.member_aim_speed_degrees
		var difference := wrapf(float(row.end_yaw)-float(row.yaw),-PI,PI)
		yaw = float(row.yaw)+clampf(difference,-deg_to_rad(speed)*(at-time_seconds),deg_to_rad(speed)*(at-time_seconds))
	var target := weapon.target.position()
	var velocity := Vector3.ZERO
	var target_yaw := 0.0
	if weapon.target.kind == AttackTarget.Kind.UNIT:
		var target_row: Dictionary = units[weapon.target.unit_id]
		target = target_row.start.lerp(target_row.end,f)
		velocity = (target_row.end-target_row.start)/GravityBallistics.STEP_SECONDS
		target_yaw = lerp_angle(float(target_row.yaw),float(target_row.end_yaw),f)
	var position: Vector3 = row.start.lerp(row.end,f)
	return {"position":position,"yaw":yaw,"target":target,"target_velocity":velocity,"target_yaw":target_yaw,"ready":row.ready,"moving":units[weapon.owner_state().unit_id].moving or row.start != row.end}

func friendly_clear(weapon: RuntimeWeaponInstance,start: Vector3,end: Vector3,at: float) -> bool:
	if weapon.target.kind == AttackTarget.Kind.FORCED_GROUND: return true
	var f := fraction(at)
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
		var center: Vector3 = record.start.lerp(record.end,f)
		var basis: Basis = record.basis.slerp(record.end_basis,f)
		var extents: Vector3 = record.extents.lerp(record.end_extents,f)
		var contact := ProjectileUnitMotion._box(basis.inverse()*(start-center),basis.inverse()*(end-center),extents)
		if contact.is_empty(): continue
		if hit.is_empty() or contact.fraction < hit.fraction or (contact.fraction == hit.fraction and record.object_id < hit.object_id):
			hit = {"fraction":contact.fraction,"object_id":record.object_id,"team_id":record.team_id}
	return hit.is_empty() or hit.team_id != weapon.owner_state().team_id
