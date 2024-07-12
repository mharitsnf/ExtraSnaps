@tool
extends Window

var mask: int = 0
signal on_confirm(new_mask: int)

func _on_confirm_pressed() -> void:
	on_confirm.emit(mask)

func _ready() -> void:
	var children = get_children()
	while children.size() > 0:
		var child = children.pop_back()
		if child is ExtraSnapsLayerToggle:
			child.connect("on_toggle_mask", on_toggle_mask)
			child.set_pressed_no_signal(mask & (1 << (child.text.to_int()-1)) != 0)
		else:
			children.append_array(child.get_children())

func on_toggle_mask(value: int, toggled_on: bool) -> void:
	var bit = 1 << value
	if toggled_on:
		mask |= bit
	else:
		mask &= ~bit

func _on_close_requested() -> void:
	hide()
