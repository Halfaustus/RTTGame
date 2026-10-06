class_name AimingSimulation
extends RefCounted

var units: Dictionary[int,UnitState] = {}
var visibility: Callable
var clear_path: Callable
var moving: Callable
var automatic_target_provider: Callable # Optional existing authoritative selector; no global scan here.
var inputs: Dictionary = {}
var profile: Dictionary = {}
var random := RandomNumberGenerator.new()
var target_velocities: Dictionary = {}
var artillery_tasks: Dictionary = {} # Runtime T tasks, not weapon attributes.

func aim_point(weapon: RuntimeWeaponInstance) -> Vector3:
	if weapon.definition.projectile == null: return weapon.target.position()
	var solution := DirectBallistics.lead(DirectBallistics.muzzle(weapon,inputs.get(weapon.owner_state().unit_id,{})),weapon.target.position(),target_velocities.get(weapon.target.unit_id,Vector3.ZERO),weapon.definition.projectile.speed_mps)
	return solution.point if solution.valid else Vector3(NAN,NAN,NAN)

func _init() -> void: random.seed = Prototype05DCatalog.RANDOM_SEED

func eligibility(weapon: RuntimeWeaponInstance,sample: Dictionary = {}) -> String:
	if not weapon.owning_node_valid(): return "owner_invalid"
	if units.get(weapon.owner_state().unit_id) != weapon.owner_state(): return "owner_invalid"
	if weapon.squad_channel != null and weapon.operator_reason != "eligible": return weapon.operator_reason
	if not weapon.enabled: return "disabled"
	if weapon.target == null: return "no_target"
	if not weapon.target.valid(units): return "target_invalid"
	var definition := weapon.definition
	if not is_finite(definition.range_m) or not is_finite(definition.aim_min_seconds) or not is_finite(definition.aim_max_seconds) or definition.range_m < 0 or definition.allowed_target_types.is_empty() or definition.ammo_definitions.is_empty() or definition.consumption_per_projectile <= 0 or definition.aim_min_seconds < 0 or definition.aim_max_seconds < definition.aim_min_seconds or definition.moving_aim_qualification < 0: return "configuration_missing"
	if not visibility.is_valid() or not clear_path.is_valid() or not moving.is_valid(): return "configuration_missing"
	if not visibility.call(weapon.owner_state(),weapon.target): return "not_visible"
	if weapon.target.kind == AttackTarget.Kind.UNIT and weapon.target.state().team_id == weapon.owner_state().team_id: return "friendly_target"
	if weapon.target.kind == AttackTarget.Kind.UNIT and not definition.allowed_target_types.has(weapon.target.target_type()): return "type_not_allowed"
	var origin: Vector3 = sample.get("position",weapon.world_position())
	var target_position: Vector3 = sample.get("target",weapon.target.position())
	if origin.distance_to(target_position) > definition.range_m + Prototype05DCatalog.RANGE_EPSILON_M: return "out_of_range"
	var artillery := artillery_tasks.has(weapon.instance_id)
	if not artillery and not clear_path.call(origin,target_position): return "path_blocked"
	var state: Dictionary = inputs.get(weapon.owner_state().unit_id,{})
	if state.get("sprinting",false): return "sprinting"
	if bool(sample.get("moving",moving.call(weapon.owner_state().unit_id))) and definition.moving_aim_qualification == 0: return "moving_prohibited"
	if state.get("return_fire_locked",false): return "return_fire_locked"
	if state.get("indoors",false):
		if definition.indoor_qualification < 0: return "configuration_missing"
		if definition.indoor_qualification == 0: return "indoor_prohibited"
	if not weapon.has_ammunition(): return "ammunition_insufficient"
	return "eligible"

func _prepare() -> Dictionary:
	var drivers := {}
	for state: UnitState in units.values():
		for weapon: RuntimeWeaponInstance in state.runtime_weapons:
			if weapon.target == null and automatic_target_provider.is_valid():
				var candidate: AttackTarget = automatic_target_provider.call(weapon)
				if candidate != null: weapon.bind_target(candidate,false)
			profile["eligibility_checks"] = profile.get("eligibility_checks",0)+1
			weapon.eligibility_reason = eligibility(weapon)
			weapon.can_attack = weapon.eligibility_reason == "eligible"
			weapon.is_aimed = false
			weapon.orientation_ready = false
			if not weapon.can_attack:
				if weapon.eligibility_reason in ["target_invalid","not_visible"]:
					var reason := weapon.eligibility_reason
					weapon.clear_target()
					weapon.eligibility_reason = reason
				elif weapon.eligibility_reason in ["disabled","sprinting","owner_invalid"]: weapon.reset_aim()
				continue
			var point := aim_point(weapon)
			if not point.is_finite():
				weapon.can_attack = false
				weapon.eligibility_reason = "intercept_unreachable"
				continue
			var origin := weapon.world_position() if weapon.definition.projectile == null else DirectBallistics.muzzle(weapon,inputs.get(state.unit_id,{}))
			weapon.desired_direction = point-origin
			weapon.desired_yaw = weapon.world_yaw() if weapon.desired_direction.length_squared() == 0 else atan2(-weapon.desired_direction.x,-weapon.desired_direction.z)
			var key := "%s/%s/%s" % [state.unit_id,weapon.node_kind,weapon.node_id]
			if not drivers.has(key) or _preferred(weapon,drivers[key]): drivers[key] = weapon
	return drivers

func _preferred(a: RuntimeWeaponInstance, b: RuntimeWeaponInstance) -> bool:
	if a.manual_target != b.manual_target: return a.manual_target
	if not a.manual_target and a.slot_state().definition.orientation_priority != b.slot_state().definition.orientation_priority: return a.slot_state().definition.orientation_priority < b.slot_state().definition.orientation_priority
	if a.slot_state().definition.direction_primary != b.slot_state().definition.direction_primary: return a.slot_state().definition.direction_primary
	return a.instance_id < b.instance_id # Stable technical tie break, not targeting policy.

func hull_requests() -> Dictionary:
	var result := {}
	var selected := {}
	for weapon: RuntimeWeaponInstance in _prepare().values():
		var state := weapon.owner_state()
		if state.unit_type() != UnitDefinition.UnitType.ARMORED_VEHICLE: continue
		if not selected.has(state.unit_id) or _preferred(weapon,selected[state.unit_id]): selected[state.unit_id] = weapon
	for id: int in selected: result[id] = selected[id].desired_yaw
	return result

func advance(delta: float) -> void:
	if delta <= 0 or not is_finite(delta): return
	for weapon: RuntimeWeaponInstance in _prepare().values():
		if weapon.node_kind == WeaponAllocation.NodeKind.HULL: continue # Sole Hull writer is movement.
		var node := weapon.spatial_node()
		var speed: float = node.rotation_speed_degrees if node is WeaponMountState else weapon.owner_state().definition.member_aim_speed_degrees
		var difference := wrapf(weapon.desired_yaw-weapon.world_yaw(),-PI,PI)
		var next := wrapf(weapon.world_yaw()+clampf(difference,-deg_to_rad(speed)*delta,deg_to_rad(speed)*delta),-PI,PI)
		if node is WeaponMountState: node.world_yaw = next
		else: node.aim_yaw = next
		profile["node_rotations"] = profile.get("node_rotations",0)+1
	for state: UnitState in units.values():
		for weapon: RuntimeWeaponInstance in state.runtime_weapons:
			if not weapon.can_attack: continue
			if weapon.sampled_aim_seconds < 0:
				weapon.sampled_aim_seconds = random.randf_range(weapon.definition.aim_min_seconds,weapon.definition.aim_max_seconds)
				profile["aim_samples"] = profile.get("aim_samples",0)+1
			var state_inputs: Dictionary = inputs.get(state.unit_id,{})
			var multiplier: float = state_inputs.get("aim_time_multiplier",1.0)
			if multiplier <= 0 or not is_finite(multiplier):
				weapon.can_attack = false
				weapon.eligibility_reason = "configuration_missing"
				continue
			weapon.aim_progress = 1.0 if weapon.sampled_aim_seconds == 0 else minf(1,weapon.aim_progress+delta/(weapon.sampled_aim_seconds*multiplier))
			weapon.aim_timer_complete = weapon.aim_progress >= 1
			weapon.orientation_ready = absf(wrapf(weapon.desired_yaw-weapon.world_yaw(),-PI,PI)) <= deg_to_rad(Prototype05DCatalog.AIM_TOLERANCE_DEGREES)
			weapon.is_aimed = weapon.can_attack and weapon.aim_timer_complete and weapon.orientation_ready
# No firing, damage, reload or ammunition mutation exists in this system.
