class_name WeaponFireState
extends RefCounted

enum Phase { WAITING, AIMING, READY, INTERVAL, LOADING }
var phase := Phase.WAITING
var can_fire := false
var reason := "no_target"
var interval_remaining := 0.0
var loading := false
var loading_progress := 1.0 # Existing 0.5D initial pending count is ready.
var last_ammo_id := ""
var emission_count := 0
var last_emission_tick := -1

func snapshot() -> Dictionary:
	return {"phase":phase,"can_fire":can_fire,"fire_reason":reason,"interval_remaining":interval_remaining,
		"loading":loading,"loading_progress":loading_progress,"last_ammo_id":last_ammo_id,"emission_count":emission_count}
