class_name UnitStatusProjection
extends RefCounted

# Display-only projection. Never expose Q, member IDs, inventory or weapon data.
static func project(structure: Dictionary) -> Dictionary:
	var id: Variant = structure.get("unit_id")
	var personnel: Variant = structure.get("personnel")
	if not id is int or not personnel is Dictionary or personnel.get("state") not in ["calm","panic","disabled","dead"]: return {}
	var result := {"unit_id":id,"personnel_state":personnel.state}
	if structure.has("modules"):
		var modules: Variant = structure.modules
		if not modules is Array or modules.size() != 4: return {}
		for grade: Variant in modules:
			if not grade is int or grade < 0 or grade > 2: return {}
		result.modules = modules.duplicate()
	return result
