class_name ProjectileState
extends RefCounted

var id: String
var source: Dictionary
var position: Vector3
var previous_position: Vector3
var velocity: Vector3
var distance := 0.0
var elapsed := 0.0
var remaining := 0.0
var radius := 0.0
var terminal := false

func _init(event: Dictionary) -> void:
	source = event.duplicate(true) # No weak references to destructible source/target.
	id = "projectile:"+str(event.event_id)
	position = event.position
	previous_position = position
	velocity = event.direction*event.projectile.speed_mps
	remaining = event.projectile.lifetime_seconds
	radius = event.projectile.radius_m

func spawn_event() -> Dictionary:
	return {"projectile_id":id,"source_event_id":source.event_id,"emission_order":source.emission_order,"owner_player_id":source.owner_player_id,"unit_id":source.unit_id,"weapon_instance_id":source.weapon_instance_id,"slot_id":source.slot_id,"ammo_definition_id":source.ammo_definition_id,"time_seconds":source.time_seconds+elapsed,"position":position,"velocity":velocity,"lifetime_seconds":remaining,"radius_m":radius}
