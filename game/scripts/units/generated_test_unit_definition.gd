extends UnitDefinition

# Saved resource identity required by deployment; values are constructed from
# current DATA plus isolated, explicitly authorized development configuration.
func _init() -> void:
	var generated := GeneratedCombatCatalog.squad()
	for property: Dictionary in generated.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name != "script":
			set(property.name,generated.get(property.name))
	resource_name = "test_only_db33_active_generated"
