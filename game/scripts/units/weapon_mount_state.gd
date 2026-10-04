class_name WeaponMountState
extends RefCounted

# Orientation/attachment only: deliberately no health, collision or footprint.
var mount_id: String
var kind: int
var hull: WeakRef
var relative_aim_yaw := 0.0
var rotation_speed_degrees := 120.0
var world_yaw: float:
	get:
		var state: UnitState = hull.get_ref() if hull != null else null
		return wrapf(relative_aim_yaw + (state.yaw if state != null else 0.0),-PI,PI)
	set(value):
		var state: UnitState = hull.get_ref() if hull != null else null
		relative_aim_yaw = wrapf(value-(state.yaw if state != null else 0.0),-PI,PI)
var weapon_slots: Array[WeaponSlotDefinition] = []

func relative_yaw(hull_yaw: float) -> float:
	return wrapf(world_yaw-hull_yaw,-PI,PI)

func snapshot(hull_yaw: float) -> Dictionary:
	return {"mount_id":mount_id,"kind":kind,"world_yaw":world_yaw,"relative_yaw":relative_yaw(hull_yaw)}
