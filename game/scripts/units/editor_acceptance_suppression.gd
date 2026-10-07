extends UnitDefinition
func _init() -> void:
	var unit := EditorAcceptanceCatalog.definition("TEST ONLY suppression shooter")
	if unit == null: return
	for p: Dictionary in unit.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.name != "script": set(p.name,unit.get(p.name))
