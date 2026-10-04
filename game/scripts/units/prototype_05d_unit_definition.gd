extends UnitDefinition

@export var preset: String:
	set(value):
		preset = value
		var catalog := Prototype05DCatalog.shared()
		if value not in ["assault","defense"]:
			member_count = 0 # Invalid resource, not a fallback playable unit.
			push_error("Removed vehicle preset: " + value)
			return
		var source := catalog.squad(value == "assault")
		for field: String in ["resource_name","unit_type","member_count","maximum_health","hardened_speed","unhardened_speed","hardened_reverse_speed","unhardened_reverse_speed","turn_speed_degrees","protection_kinetic","protection_chemical","kinetic_armor_by_face","chemical_armor_by_face","ability_tags","mounts","weapon_allocations"]:
			set(field,source.get(field))
