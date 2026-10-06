extends "res://tests/db29_projectile_test.gd"

# Generated local geometry; real ammunition comes from current confirmed DATA.
var ticks: Array[int] = []
func tick() -> bool:
	ticks.append(ticks.size())
	return true
func failed_tick() -> bool: return false

func run() -> void:
	var clock := FixedStepClock.new()
	check(clock.advance(1.0,tick) == 8,"large dt callback budget is eight physical steps")
	check(clock.completed_steps == 8 and absf(clock.pending_seconds-22.0/30.0) < 0.000001,"all unprocessed time retained")
	check(clock.advance(0.0,tick) == 8 and clock.advance(0.0,tick) == 8 and clock.advance(0.0,tick) == 6,"debt drains in sequential steps without dropping")
	check(ticks.size() == 30 and clock.pending_seconds < 0.000001,"one second yields thirty ordered steps")
	check(clock.advance(NAN,tick) == 0 and clock.completed_steps == 30,"invalid dt does not advance")
	check(clock.advance(1.0,failed_tick) == 0 and clock.pending_seconds >= 1.0,"failed step retains debt")
	var sim := DB29ProjectileSimulation.new()
	check(sim.configure_bounds(Rect2(-10,-10,20,20)),"explicit map bounds accepted")
	var events := sim.step([emission("exit",1,0)])
	check(events.size() == 2 and events[1].reason == "battlefield_exit","unhit projectile ends at battlefield boundary")
	check(absf(events[1].time_seconds-10.0/900.0) < 0.000001 and absf(events[1].position.x-10.0) < 0.00001,"exit uses exact within-step time")
	check(sim.active_slots.is_empty() and sim.slots[0].is_empty(),"exit frees slot and cached source/ammo")
	sim.collision.close()
	sim = DB29ProjectileSimulation.new()
	sim.configure_bounds(Rect2(-10,-10,20,20))
	wall(sim,"before_exit",5)
	events = sim.step([emission("hit",1,0)])
	check(events[1].reason == "impact","earlier collision takes precedence over exit")
	sim.collision.close()
	sim = DB29ProjectileSimulation.new()
	sim.configure_bounds(Rect2(-10,-10,20,20))
	wall(sim,"after_exit",15)
	events = sim.step([emission("exit_first",1,0)])
	check(events[1].reason == "battlefield_exit","later wall cannot override prior boundary exit")
	sim.collision.close()
	sim = DB29ProjectileSimulation.new()
	sim.configure_bounds(Rect2(-10,-10,20,20))
	events = sim.step([emission("outside",1,0,Vector3(20,2,0))])
	check(events[1].reason == "battlefield_exit" and events[1].time_seconds == 0,"outside emission spawns then exits immediately")
	sim.collision.close()
	sim = DB29ProjectileSimulation.new()
	sim.configure_bounds(Rect2(-10,-10,20,20))
	var vertical := emission("vertical",1,0)
	vertical.velocity = Vector3(0,900,0)
	sim.step([vertical])
	for i in range(300): sim.step()
	check(sim.active_slots.size() == 1,"no invented height/lifetime cutoff within map bounds")
	check(not sim.configure_bounds(Rect2(-1,-1,2,2)),"bounds cannot change under live projectiles")
	sim.collision.close()
	var before := {"center":Vector3.ZERO,"extents":Vector3(2,0.2,0.2),"basis":Basis(Vector3.UP,-PI/4),"team_id":2,"unit_type":UnitDefinition.UnitType.ARMORED_VEHICLE}
	var after: Dictionary = before.duplicate()
	after.basis = Basis(Vector3.UP,PI/4)
	var motion := ProjectileUnitMotion.new()
	check(motion.configure(0,{2:before},{2:after}),"rotating generated test box configured")
	var h := GravityBallistics.STEP_SECONDS
	check(not motion.sweep(Vector3(1.8,0,0),Vector3(1.8,0,0),0,h,1).is_empty(),"mid-rotation-only contact detected despite endpoint misses")
	check(motion.sweep(Vector3(2.03,0,0),Vector3(2.03,0,0),0,h,1).is_empty(),"point outside swept corner radius and tolerance stays clear")
	check(motion.sweep(Vector3(1.8,0,0),Vector3(1.8,0,0),0,h*0.1,1).is_empty(),"short interval excludes later rotation contact")
	after = before.duplicate()
	before.basis = Basis.IDENTITY
	after.basis = Basis.IDENTITY
	before.extents = Vector3.ONE*0.5
	after.extents = Vector3.ONE
	check(motion.configure(0,{2:before},{2:after}),"changing generated test extents configured")
	var hit := motion.sweep(Vector3(0.75,0,0),Vector3(0.75,0,0),0,h,1)
	check(not hit.is_empty() and absf(hit.fraction-0.5) < 0.003,"growing box contact interpolated within spatial tolerance")
	print("DB33 C projectile design: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
