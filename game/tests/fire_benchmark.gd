extends SceneTree

# Same 0.5D layout/120 steps/60 Hz, repeated three times. Explicit authority stubs.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var catalog := Prototype05DCatalog.new()
	for count: int in [8,64,128]:
		for repetition: int in 3:
			var scene := AimingSimulation.new()
			scene.visibility = func(_a,_b): return true
			scene.clear_path = func(_a,_b): return true
			scene.moving = func(_id): return false
			var target := UnitState.new(9999,0,Vector3(0,0,-100))
			target.configure(2,UnitDefinition.new())
			scene.units[9999] = target
			var weapons := 0
			for id: int in count:
				var state := UnitState.new(id+1,42,Vector3(id,0,0))
				state.configure(1,catalog.squad(true) if id%2 == 0 else catalog.weapon_slot_fixture("c"))
				scene.units[state.unit_id] = state
				weapons += state.runtime_weapons.size()
				for instance: RuntimeWeaponInstance in state.runtime_weapons: instance.bind_target(AttackTarget.unit(target))
			var start := Time.get_ticks_usec()
			for frame: int in 120: scene.advance(1.0/60)
			var baseline := (Time.get_ticks_usec()-start)/120.0
			# Explicit valid armor for selection. No target weapons added to measured scale.
			target.definition.protection_kinetic = 6
			target.definition.protection_chemical = 6
			var firing := FireSimulation.new()
			var aim_us := 0
			var fire_us := 0
			var emissions := 0
			var peaks := 0
			for frame: int in 120:
				start = Time.get_ticks_usec()
				scene.advance(1.0/60)
				aim_us += Time.get_ticks_usec()-start
				start = Time.get_ticks_usec()
				emissions += firing.advance(1.0/60,frame,scene).size()
				var elapsed := Time.get_ticks_usec()-start
				fire_us += elapsed
				peaks = maxi(peaks,elapsed)
			start = Time.get_ticks_usec()
			var payload: Array[Dictionary] = []
			for state: UnitState in scene.units.values(): payload.append(state.structure_snapshot())
			var bytes := var_to_bytes(payload).size()
			print("FIRE_BENCH units=%d weapons=%d sample=%d aim_only_ms=%.3f aim_with_fire_ms=%.3f fire_ms=%.3f fire_peak_ms=%.3f updates_tick=%d selections=%d events=%d payload_bytes=%d serialization_ms=%.3f hz=10 path_queries=0" % [count,weapons,repetition,baseline/1000,aim_us/120000.0,fire_us/120000.0,peaks/1000.0,firing.profile.weapon_updates/120,firing.profile.get("selection_queries",0),emissions,bytes,(Time.get_ticks_usec()-start)/1000.0])
	quit()
