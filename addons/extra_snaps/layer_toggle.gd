@tool
class_name ExtraSnapsLayerToggle extends Button

signal on_toggle_mask(value: int, toggled_on: bool)

func _on_toggled(toggled_on:bool) -> void:
	on_toggle_mask.emit(text.to_int()-1, toggled_on)