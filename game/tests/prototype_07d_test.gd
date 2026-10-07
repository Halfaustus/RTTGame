extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if value: print("PASS 0.7D: ",label)
	else: failures += 1; push_error("FAIL 0.7D: "+label)

func _run() -> void:
	var model = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(model)
	check(model.configure_active_test_map() and model._ensure_deployment_ready(),"actual navigation and definitions ready")
	model._peer_players[42] = 10
	model._peer_players[43] = 11
	for id: int in [9000,9001,9002]:
		var unit := UnitState.new(id,43 if id == 9002 else 42,Vector3(20+(id-9000)*4,0.5,100))
		unit.configure(1,model._weapon_presets[0])
		unit.owner_player_id = 11 if id == 9002 else 10
		model._authoritative_units[id] = unit
		model._movement.add_unit(unit)
		model._combat.add_unit(unit)
	var command := {"type":"move","unit_ids":[9000,9001,9002,9000],"target":Vector3(30,0,100),"mode":0,"facing":Vector3.ZERO,"group":true,"peer_id":42,"player_id":10,"append":false}
	var result: Dictionary = model._submit_task_command(command)
	check(result.unit_ids == [9000,9001] and result.failed_ids.is_empty(),"owned live units accepted once, foreign excluded from results")
	check(not model._task_queue.tasks.has(9002),"foreign queue untouched")
	model._advance_task_queues(PackedInt32Array([42,43]))
	check(model._task_queue.current(9000).started,"server starts current task")
	var first: Vector3 = model._movement._targets[9000]
	command.append = true
	command.target = Vector3(40,0,105)
	result = model._submit_task_command(command)
	check(model._task_queue.tasks[9000].size() == 2 and model._movement._targets[9000] == first,"Shift adds without interrupting active route")
	check(model._task_queue.current(9000).target != model._task_queue.current(9001).target,"formation retains independent slots")
	model._movement._engaging[9000] = true
	model._advance_task_queues(PackedInt32Array([42,43]))
	check(model._task_queue.tasks[9000].size() == 2,"engaging is not arrival")
	model._movement._engaging.erase(9000)
	for step: int in 200:
		if not model._movement._targets.has(9000): break
		model._movement._advance(0.1,9000)
	check(not model._movement._targets.has(9000),"actual isolated authority movement reaches destination")
	model._advance_task_queues(PackedInt32Array([42,43]))
	check(model._task_queue.tasks[9000].size() == 1 and model._task_queue.current(9000).started,"one unit advances independently")
	check(model._task_queue.tasks[9001].size() == 2,"other unit keeps its own head")
	command.append = false
	command.target = Vector3(25,0,95)
	model._submit_task_command(command)
	check(model._task_queue.tasks[9000].size() == 1 and model._task_queue.tasks[9001].size() == 1,"normal command replaces entire supported queue")
	var old: Dictionary = model._task_queue.current(9000).duplicate(true)
	command.mode = MovementSimulation.MoveMode.REVERSE
	result = model._submit_task_command(command)
	check(result.unit_ids.is_empty() and result.has("failed_ids") and model._task_queue.current(9000) == old,"unsupported reverse preserves infantry queue and stable rejection schema")
	command.mode = 0
	command.target = Vector3(NAN,0,0)
	result = model._submit_task_command(command)
	check(not result.rejection.is_empty() and model._task_queue.current(9000) == old,"invalid target never clears task")
	var fire := {"type":"ground_fire","unit_ids":[9000],"target":Vector3(20,0,90),"count":-1,"mode":-1,"facing":Vector3.ZERO,"group":false,"peer_id":42,"player_id":10,"append":false}
	model._submit_task_command(fire)
	model._advance_task_queues(PackedInt32Array([42,43]))
	check(model._task_queue.current(9000).started and model._authoritative_units[9000].runtime_weapons.all(func(w): return w.manual_target and w.forced_emissions_remaining == -1),"G starts persistent authoritative ground target")
	command.target = Vector3(25,0,95)
	command.unit_ids = [9000]
	command.append = true
	model._submit_task_command(command)
	model._advance_task_queues(PackedInt32Array([42,43]))
	check(model._task_queue.tasks[9000].size() == 2 and model._task_queue.current(9000).type == "ground_fire","continuous G blocks following movement")
	var ids: Array[int] = [9000]
	model._apply_stop(ids,42)
	check(not model._task_queue.tasks.has(9000) and not model._movement._targets.has(9000),"E clears queue and current movement/fire")
	check(model._authoritative_units[9000].runtime_weapons.all(func(w): return w.target == null),"E clears persistent weapon target")
	var mortar := UnitState.new(9003,42,Vector3(0,0.5,100))
	mortar.configure(1,preload("res://data/units/db33_active_test_mortar.tres"))
	mortar.owner_player_id = 10
	model._authoritative_units[9003] = mortar
	model._movement.add_unit(mortar)
	model._combat.add_unit(mortar)
	model._aiming.units = model._authoritative_units
	var artillery := {"type":"artillery","unit_ids":[9003],"target":Vector3(0,0,-50),"count":1,"mode":-1,"facing":Vector3.ZERO,"group":false,"peer_id":42,"player_id":10,"append":false}
	result = model._submit_task_command(artillery)
	check(result.unit_ids == [9003] and mortar.runtime_weapons[0].target == null,"T admission validates without starting weapon target")
	model._advance_task_queues(PackedInt32Array([42,43]))
	check(model._task_queue.current(9003).started and not model._artillery.tasks.is_empty(),"T head starts actual artillery task")
	var following := command.duplicate(true)
	following.unit_ids = [9003]
	following.target = Vector3(5,0,100)
	following.append = true
	model._submit_task_command(following)
	for value: Dictionary in model._artillery.tasks.values(): value.finished = true
	var completed_events: Array[Dictionary] = []
	model._artillery.after_emissions(completed_events,model._authoritative_units)
	model._advance_task_queues(PackedInt32Array([42,43]))
	check(model._task_queue.current(9003).type == "move" and model._task_queue.current(9003).started,"authoritative T completion releases next task")
	var mortar_weapon: RuntimeWeaponInstance = mortar.runtime_weapons[0]
	for key: String in mortar_weapon.inventory: mortar_weapon.inventory[key] = 0
	var ammo_id: String = mortar_weapon.definition.ammo_definitions[0].ammo_id
	mortar_weapon.inventory[ammo_id] = mortar_weapon.definition.consumption_per_projectile # TEST ONLY one actual emission stock.
	artillery.count = 3
	model._submit_task_command(artillery)
	model._submit_task_command(following)
	for step: int in 300: model._run_server_tick(PackedInt32Array([42,43]))
	check(mortar_weapon.inventory[ammo_id] == 0 and model._artillery.tasks.has(mortar_weapon.instance_id) and model._artillery.tasks[mortar_weapon.instance_id].remaining == 2,"actual one-shot emission consumes stock but retains remaining finite T budget")
	check(model._task_queue.current(9003).type == "artillery" and model._task_queue.tasks[9003].size() == 2,"depleted finite T task waits and blocks queued move")
	artillery.count = 1
	for key: String in mortar.runtime_weapons[0].inventory: mortar.runtime_weapons[0].inventory[key] = 0
	model._submit_task_command(artillery)
	model._advance_task_queues(PackedInt32Array([42,43]))
	check(not model._task_queue.current(9003).started,"T ammunition shortage waits rather than discards task")
	var waiting: Dictionary = model._task_queue.current(9003).duplicate(true)
	artillery.target = Vector3(0,0,80)
	result = model._submit_task_command(artillery)
	check(result.unit_ids.is_empty() and model._task_queue.current(9003) == waiting,"invalid near T never overwrites existing task")
	model._replication_queue.clear()
	model._task_queue_revision = -1
	model._advance_task_queues(PackedInt32Array([42,43]))
	var projections: Array = model._replication_queue.filter(func(row): return row.method == "_receive_task_queues")
	check(projections.size() == 2,"queue projection separately addressed to each player")
	check(projections[0].arguments[0].all(func(row): return row.unit_id != 9002),"A projection excludes B private queue")
	check(projections[1].arguments[0].all(func(row): return row.unit_id == 9002),"B projection excludes A private queue")
	var projection_count: int = model._replication_queue.size()
	model._queue_replication("_receive_task_queues",[projections[0].arguments[0]])
	check(model._replication_queue.size() == projection_count,"generic broadcast cannot send private queues")
	check(model._replication_arguments_for_peer("_receive_task_queues",[projections[0].arguments[0]],43).is_empty(),"generic peer projection rejects private task payload")
	model._peer_players[42] = 99
	model._advance_task_queues(PackedInt32Array([42,43]))
	check(not model._task_queue.tasks.has(9001),"peer identity reuse retires old task")
	model._peer_players[42] = 10
	command.append = false
	model._submit_task_command(command)
	model._authoritative_units[9000].health = 0
	model._advance_task_queues(PackedInt32Array([42,43]))
	check(not model._task_queue.tasks.has(9000),"death clears authoritative queue")
	model._authoritative_units[9000].health = 10
	model._submit_task_command(command)
	model._task_queue.current(9000).target = Vector3(NAN,0,0) # Isolated invalidated head; not production data.
	model._replication_queue.clear()
	model._advance_task_queues(PackedInt32Array([42,43]))
	check(not model._task_queue.tasks.has(9000),"invalidated head is skipped")
	check(model._replication_queue.any(func(row): return row.method == "_receive_command_notice" and row.peer_id == 42),"invalidated head reports only to original requester")
	var projected: Array[Dictionary] = model._task_queue.projection(9003)
	check(projected.all(func(row): return row.keys().size() == 4 and not row.has("player_id") and not row.has("peer_id")),"task projection strips identities, execution flags and inventories")
	var world = load("res://scenes/maps/db33_active_test_world.tscn").instantiate()
	root.add_child(world)
	world._open_menu()
	var choice: OptionButton = world._menu.find_child("SpawnMoveMode",true,false)
	check(choice != null and choice.get_selected_id() == MovementSimulation.MoveMode.BASIC,"Esc setting keeps default basic movement")
	choice.select(1)
	choice.item_selected.emit(1)
	check(world._deployment_ui.spawn_move_mode == MovementSimulation.MoveMode.FAST,"Esc setting controls deployment preference")
	check(world._camera.input_blocked,"setting retains modal camera interlock")
	world.queue_free()
	if model._projectiles != null: model._projectiles.collision.close()
	model.queue_free()
	await process_frame
	print("0.7D checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
