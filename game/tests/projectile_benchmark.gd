extends SceneTree

func _initialize() -> void: run.call_deferred()
func run() -> void:
	var catalog := Prototype05DCatalog.new()
	for count: int in [8,64,128]:
		for sample: int in 3:
			var aiming := AimingSimulation.new()
			aiming.visibility = func(_a,_b): return true # Same explicit 0.5E benchmark authority stubs.
			aiming.clear_path = func(_a,_b): return true
			aiming.moving = func(_id): return false
			var target := UnitState.new(9999,0,Vector3(0,0,-100))
			target.configure(2,UnitDefinition.new())
			aiming.units[9999] = target
			var weapons := 0
			for index: int in count:
				var state := UnitState.new(index+1,42,Vector3(index,0,0))
				state.configure(1,catalog.squad(true) if index%2 == 0 else catalog.weapon_slot_fixture("c"))
				aiming.units[state.unit_id] = state
				weapons += state.runtime_weapons.size()
				for weapon: RuntimeWeaponInstance in state.runtime_weapons: weapon.bind_target(AttackTarget.unit(target))
			var start := Time.get_ticks_usec()
			for frame: int in 120: aiming.advance(1.0/60)
			var aim_only_ms := (Time.get_ticks_usec()-start)/120000.0
			target.definition.protection_kinetic = 6
			target.definition.protection_chemical = 6
			var fire := FireSimulation.new()
			var projectiles := ProjectileSimulation.new()
			# D/E off-map coordinates retained; no invented bounds for this isolated throughput fixture.
			projectiles.collision.sync_units(aiming.units)
			projectiles.collision.box("benchmark_wall","obstacle",Vector3(80,5,0.025),Transform3D(Basis.IDENTITY,Vector3(60,0,-50)))
			fire.fire_path_permission = projectiles.collision.fire_clear # Real friendly checks, not bypassed.
			var totals := {"aim":0,"fire":0,"projectiles":0,"bytes":0,"batches":0,"peak":0}
			var frames := 600 if count == 128 else 120
			for frame: int in frames:
				start = Time.get_ticks_usec()
				aiming.advance(1.0/60)
				totals.aim += Time.get_ticks_usec()-start
				start = Time.get_ticks_usec()
				projectiles.collision.sync_units(aiming.units)
				var terminals := projectiles.advance(1.0/60,frame)
				var projectile_us := Time.get_ticks_usec()-start
				start = Time.get_ticks_usec()
				var shots := fire.advance(1.0/60,frame,aiming)
				totals.fire += Time.get_ticks_usec()-start
				start = Time.get_ticks_usec()
				var spawns := projectiles.consume(shots)
				projectile_us += Time.get_ticks_usec()-start
				totals.projectiles += projectile_us
				totals.peak = maxi(totals.peak,projectile_us)
				if not shots.is_empty(): totals.bytes += var_to_bytes(shots).size()
				if not spawns.is_empty():
					totals.bytes += var_to_bytes(spawns).size()
					totals.batches += 1
				if not terminals.is_empty():
					totals.bytes += var_to_bytes(terminals).size()
					totals.batches += 1
				if frame == 119:
					print("PROJECTILE_SHORT units=%d sample=%d weapons=%d aim_only_ms=%.3f aim_ms=%.3f fire_ms=%.3f projectile_ms=%.3f projectile_peak_ms=%.3f spawns=%d impacts=%d active_peak=%d queries=%d allocations=%d event_bytes=%d batches=%d full_hz=10" % [count,sample,weapons,aim_only_ms,totals.aim/120000.0,totals.fire/120000.0,totals.projectiles/120000.0,totals.peak/1000.0,projectiles.profile.spawned,projectiles.profile.impacts,projectiles.profile.peak_active,projectiles.collision.profile.casts+projectiles.collision.profile.rest_queries,projectiles.collision.profile.query_allocations,totals.bytes,totals.batches])
			if frames > 120:
				print("PROJECTILE_SUSTAINED units=%d sample=%d seconds=10 aim_ms=%.3f fire_ms=%.3f projectile_ms=%.3f cumulative_cpu_ms=%.3f spawns=%d impacts=%d expired=%d active=%d peak=%d failures=%d event_bytes=%d batches_hz=%.1f" % [count,sample,totals.aim/600000.0,totals.fire/600000.0,totals.projectiles/600000.0,(totals.aim+totals.fire+totals.projectiles)/1000.0,projectiles.profile.spawned,projectiles.profile.impacts,projectiles.profile.expired,projectiles.active.size(),projectiles.profile.peak_active,projectiles.profile.failures,totals.bytes,totals.batches/10.0])
			var payload: Array[Dictionary] = []
			for state: UnitState in aiming.units.values(): payload.append(state.structure_snapshot())
			start = Time.get_ticks_usec()
			var bytes := var_to_bytes(payload).size()
			print("PROJECTILE_STRUCTURE units=%d sample=%d bytes=%d encode_ms=%.3f projectiles_in_structure=false" % [count,sample,bytes,(Time.get_ticks_usec()-start)/1000.0])
			projectiles.collision.close()
	quit()
