class_name SoldierState
extends RefCounted

const MAXIMUM_HEALTH := 5.0
var member_id: int
var health := MAXIMUM_HEALTH
var position := Vector3.ZERO
var formation_slot := -1
var hitbox_half_extents := Vector3(0.15,0.4,0.15)
var weapon_slots: Array[WeaponSlotDefinition] = []
var aim_yaw := 0.0

func intersects_hit_segment(start: Vector3, end: Vector3) -> bool:
	if health <= 0.0 or not start.is_finite() or not end.is_finite(): return false
	var a := start - position
	var direction := end - start
	var first := 0.0
	var last := 1.0
	for axis: int in 3:
		if is_zero_approx(direction[axis]):
			if absf(a[axis]) > hitbox_half_extents[axis]: return false
		else:
			var low := (-hitbox_half_extents[axis]-a[axis])/direction[axis]
			var high := (hitbox_half_extents[axis]-a[axis])/direction[axis]
			first = maxf(first,minf(low,high))
			last = minf(last,maxf(low,high))
			if first > last: return false
	return true

func snapshot() -> Dictionary:
	return {"member_id":member_id,"position":position,"health":health,"formation_slot":formation_slot,"aim_yaw":aim_yaw}
