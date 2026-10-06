extends UnitDefinition

func _init() -> void:
	var generated := GeneratedCombatCatalog.mortar()
	for property: Dictionary in generated.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name != "script":
			set(property.name,generated.get(property.name))
	resource_name = "test_only_db33_active_mortar"
