class_name FireSimulation
extends RefCounted

var last_tick := -1
var time_seconds := 0.0
var profile: Dictionary = {}
var emission_order := 0
var random := RandomNumberGenerator.new()
var fire_path_permission: Callable # Production friendly-block query; fixtures can inject explicitly.
var execution_mode := "" # One timing writer per simulation; do not mix legacy/fixed clocks.
const TIME_EPSILON := 0.000000001 # Numerical endpoint tolerance, not gameplay delay.

func _init() -> void: random.seed = Prototype05FConfig.RANDOM_SEED

func advance(delta: float, tick: int, aiming: AimingSimulation) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if execution_mode == "fixed": return events
	if not is_finite(delta) or delta < 0 or tick <= last_tick: return events
	execution_mode = "legacy"
	last_tick = tick
	time_seconds += delta
	for state: UnitState in aiming.units.values():
		var inputs: Dictionary = aiming.inputs.get(state.unit_id,{})
		for weapon: RuntimeWeaponInstance in state.runtime_weapons:
			profile["weapon_updates"] = profile.get("weapon_updates",0)+1
			var fire := weapon.fire_state
			fire.can_fire = false
			fire.phase = WeaponFireState.Phase.WAITING
			if not weapon.owning_node_valid():
				fire.reason = "owner_invalid"
				continue
			fire.interval_remaining = maxf(0,fire.interval_remaining-delta)
			if fire.interval_remaining <= TIME_EPSILON: fire.interval_remaining = 0
			_advance_loading(weapon,delta,inputs)
			fire.reason = aiming.eligibility(weapon) # Same authority/visibility/type/range/path permissions.
			if fire.reason != "eligible": continue
			var origin := weapon.world_position() if weapon.definition.projectile == null else DirectBallistics.muzzle(weapon,inputs)
			var point := aiming.aim_point(weapon)
			if not point.is_finite():
				fire.reason = "intercept_unreachable"
				continue
			var offset := point-origin
			var desired := weapon.world_yaw() if offset.length_squared() == 0 else atan2(-offset.x,-offset.z)
			if not weapon.is_aimed or not weapon.aim_timer_complete or absf(wrapf(desired-weapon.world_yaw(),-PI,PI)) > deg_to_rad(Prototype05DCatalog.AIM_TOLERANCE_DEGREES):
				fire.reason = "not_aimed"
				fire.phase = WeaponFireState.Phase.AIMING
				continue
			if fire.loading:
				fire.reason = "loading"
				fire.phase = WeaponFireState.Phase.LOADING
				continue
			if fire.interval_remaining > 0:
				fire.reason = "interval"
				fire.phase = WeaponFireState.Phase.INTERVAL
				continue
			var definition := weapon.definition
			if definition.capacity <= 0 or not is_finite(definition.preparation_seconds) or definition.preparation_seconds <= 0 or not is_finite(definition.game_projectile_interval) or definition.game_projectile_interval < 0:
				fire.reason = "fire_configuration_missing"
				continue
			if weapon.pending_rounds < definition.consumption_per_projectile:
				fire.reason = "pending_recovery_undefined"
				continue # No new automatic empty-stock recovery mechanic.
			if fire_path_permission.is_valid() and not fire_path_permission.call(weapon,origin,point,inputs):
				fire.reason = "friendly_blocked"
				continue
			if definition.projectile != null and not definition.projectile.valid():
				fire.reason = "projectile_configuration_missing"
				continue
			profile["selection_queries"] = profile.get("selection_queries",0)+1
			var selection := AmmoSelection.select(weapon,aiming.inputs.get(weapon.target.unit_id,{}))
			fire.reason = selection.reason
			if fire.reason != "eligible": continue
			var ammo: AmmoDefinition = selection.ammo
			var count := definition.consumption_per_projectile
			# Build and validate complete event before atomic commit. One event per weapon/tick.
			var event := {"event_id":"%s:%s:%s" % [tick,weapon.instance_id,fire.emission_count+1],"tick":tick,"time_seconds":time_seconds,"emission_sequence":fire.emission_count+1,
				"weapon_instance_id":weapon.instance_id,"unit_id":state.unit_id,"slot_id":weapon.slot_state().definition.slot_id,
				"target_kind":weapon.target.kind,"target_id":weapon.target.unit_id,"target_position":weapon.target.position(),
				"ammo_definition_id":ammo.ammo_id,"consumed":count,"position":origin,"yaw":weapon.world_yaw(),"owner_player_id":state.owner_player_id,"team_id":state.team_id,"emission_order":emission_order+1}
			if not event.position.is_finite() or not event.target_position.is_finite() or not is_finite(event.yaw):
				fire.reason = "spatial_configuration_invalid"
				continue
			if definition.projectile != null:
				var specification := definition.projectile
				var radius := specification.spread_radius_m
				if specification.spread_policy == "radius_at_1000m": radius *= offset.length()/1000.0
				radius *= float(inputs.get("spread_multiplier",1.0))
				if aiming.moving.call(state.unit_id): radius *= specification.moving_spread_multiplier
				if not is_finite(radius) or radius < 0:
					fire.reason = "spread_configuration_invalid"
					continue
				# Actual yaw remains the authoritative muzzle yaw; sampled spread is separate.
				var direction := offset.normalized()
				var pitch := asin(clampf(direction.y,-1,1))
				var actual := Vector3(-sin(event.yaw)*cos(pitch),sin(pitch),-cos(event.yaw)*cos(pitch))
				event.direction = (actual*maxf(offset.length(),0.001)+DirectBallistics.spread_offset(random,radius,actual)).normalized()
				event.projectile = specification.snapshot()
				event.spread_radius_m = radius
				event.ignore_house_id = int(inputs.get("house_id",0))
				event.ignore_target_house_id = int(aiming.inputs.get(weapon.target.unit_id,{}).get("house_id",0))
				event.explosion_radius_m = ammo.explosion_radius_m # Static only; no explosion queries.
				event.ammo_snapshot = {"ammo_id":ammo.ammo_id,"damage_type":ammo.damage_type,"nominal_damage":ammo.nominal_damage,"penetration_upper":ammo.penetration_upper,"anchor_distance_m":ammo.anchor_distance_m,"anchor_penetration":ammo.anchor_penetration,"minimum_penetration":ammo.minimum_penetration,"test_curve":ammo.test_curve,"test_log_shape":ammo.test_log_shape,"explosion_radius_m":ammo.explosion_radius_m,"suppression":ammo.suppression,"module_damage":ammo.module_damage}
			emission_order += 1
			weapon.consume(ammo.ammo_id,count)
			weapon.pending_rounds -= count
			fire.last_ammo_id = ammo.ammo_id
			fire.last_emission_tick = tick
			fire.emission_count += 1
			fire.can_fire = true # Permission at emission, not a promise for a second call.
			fire.phase = WeaponFireState.Phase.READY
			fire.interval_remaining = weapon.shot_interval()
			if definition.preparation_cadence or weapon.pending_rounds < count:
				fire.loading = true
				fire.loading_progress = 0
			events.append(event)
			fire.can_fire = false
			fire.reason = "loading" if fire.loading else "interval"
			fire.phase = WeaponFireState.Phase.LOADING if fire.loading else WeaponFireState.Phase.INTERVAL
	return events

# DB29 prepared, stationary-channel integration. Legacy advance remains an
# isolated compatibility path and cannot mutate a fixed scheduler's state.
func advance_fixed(aiming: AimingSimulation,frame: FiringFrame = null) -> Array[Dictionary]:
	if execution_mode == "legacy": return []
	execution_mode = "fixed"
	return FixedFireScheduler.step(self,aiming,frame)

func _advance_loading(weapon: RuntimeWeaponInstance, delta: float, inputs: Dictionary) -> void:
	var fire := weapon.fire_state
	if not fire.loading: return
	if weapon.squad_channel != null and weapon.operator_reason != "eligible": return
	var module: float = inputs.get("loading_module_multiplier",1.0)
	var personnel: float = 1.0 if weapon.definition.mechanical_loading else inputs.get("personnel_load_multiplier",1.0)
	var duration := weapon.loading_seconds()*module*personnel
	if duration <= 0 or not is_finite(duration): return
	fire.loading_progress = minf(1,fire.loading_progress+delta/duration)
	if fire.loading_progress >= 1.0-TIME_EPSILON:
		fire.loading_progress = 1
		fire.loading = false
		var stock := 0
		for ammo: AmmoDefinition in weapon.definition.ammo_definitions: stock += int(weapon.inventory.get(ammo.ammo_id,0))
		weapon.pending_rounds = mini(weapon.pending_capacity(),stock)
