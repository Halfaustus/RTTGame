extends "res://tests/squad_weapon_channels_test.gd"

# Generated TEST ONLY units; no new configuration fields or formal unit records.
func run() -> void:
	var config := definition(4)
	allocation(config,test_weapon("W_M249"),1,0)
	var rifle := test_weapon("W_M4A1")
	allocation(config,rifle,2,1)
	allocation(config,rifle,3,1)
	allocation(config,test_weapon("W_MP7"),4,1,"secondary")
	var squad := state(config)
	var channels := squad.squad_channels
	var machine := channel(squad,"W_M249")
	var rifles := channel(squad,"W_M4A1")
	var sidearm := channel(squad,"W_MP7")
	var snapshot := channels.profile.duplicate()
	for index: int in 1000: squad.refresh_weapon_operators()
	check(channels.profile == snapshot,"1000 idle calls cause no scans, events or recomputation")
	squad.members[2].health = 4
	check(channels.profile == snapshot,"nonlethal health change does not trigger replacement")
	var before := int(channels.profile.channel_updates)
	squad.members[2].health = 0
	check(channels.profile.events == 1,"death setter emits one authoritative event")
	check(channels.profile.channel_updates == before+1,"ordinary rifle death updates only rifle channel")
	check(machine.node_id == "1" and sidearm.operable_count == 1,"unrelated primary and secondary channels untouched")
	check(rifles.operable_count == 1 and rifles.configured_count == 2,"ordinary casualty changes availability, never fixed N")
	var flow := machine.fire_state
	var cached := int(channels.profile.candidate_builds)
	squad.members[0].health = 0
	check(machine.node_id == "2" and machine.operable_count == 1,"squad weapon legally replaces deceased carrier")
	check(rifles.operable_count == 0 and sidearm.operable_count == 1,"cached slot dependencies update displaced rifle only")
	check(machine.fire_state == flow and channels.profile.candidate_builds == cached,"event preserves timer and never rebuilds candidates")
	check(machine.inventory.A_556_M249 == 0,"death removes carrier stock without recovering it on transfer")
	before = channels.profile.channel_updates
	squad.members[0].health = 5
	check(machine.node_id == "1" and rifles.operable_count == 1,"replenishment restores original station and dependent rifle")
	check(channels.profile.channel_updates == before+2,"revival updates exactly linked machine/rifle channels")
	check(machine.inventory.A_556_M249 == 0 and machine.configured_count == 1,"revival does not create ammo or change N")
	var again := channels.profile.duplicate()
	var aim := aiming(squad)
	# Initialization of aiming is allowed; normal idle combat updates are not events.
	again = channels.profile.duplicate()
	for index: int in 20: aim.advance(1.0/30)
	check(channels.profile == again,"actual aiming updates perform no personnel scan/replacement work")
	var fire := FireSimulation.new()
	for index: int in 20: fire.advance(1.0/30,index,aim)
	check(channels.profile == again,"actual legacy firing updates perform no replacement work")
	var fixed := FireSimulation.new()
	for index: int in 20: fixed.advance_fixed(aim)
	check(channels.profile == again,"fixed firing updates perform no replacement work")
	var heavy_config := definition(2)
	allocation(heavy_config,test_weapon("W_M2"),1,0)
	var heavy := state(heavy_config)
	heavy.members[1].health = 0
	check(channel(heavy,"W_M2").operator_reason == "operators_insufficient","formal two-operator minimum enforced through event")
	heavy.members[1].health = 5
	check(channel(heavy,"W_M2").operable_count == 1,"cached candidate revival restores required crew")
	check(heavy.squad_channels.profile.candidate_builds == 1,"crew changes reuse single cached candidate relation")
	var obsolete := heavy.members[0]
	var obsolete_channels := heavy.squad_channels
	var old_events: int = obsolete_channels.profile.events
	heavy.configure(1,heavy_config)
	obsolete.health = 0
	check(obsolete_channels.profile.events == old_events and channel(heavy,"W_M2").operable_count == 1,"configuration replacement detaches obsolete member events")
	print("DB33 operator events: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
