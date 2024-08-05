@tool
class_name ESMenuButton extends MenuButton

const common = preload('./common.gd')

var surface_type_pm: PopupMenu
var snap_type_pm: PopupMenu
var pm: PopupMenu
var dialog_configure_mask: Window

var collision_mask: int = common.INT32_MAX

signal configure_mask_window_instantiated(window: Window)
signal new_snap_type_selected(id: common.SnapTypes)
signal new_surface_type_selected(id: common.SurfaceTypes)
signal collision_mask_changed(mask: int)

func _enter_tree() -> void:
	# Setup surface type submenu
	surface_type_pm = PopupMenu.new()
	surface_type_pm.name = "SurfaceTypePM"
	surface_type_pm.add_radio_check_item("Snap with Collision Objects", common.SurfaceTypes.COLLISION_OBJECTS)
	surface_type_pm.add_radio_check_item("Snap with Meshes", common.SurfaceTypes.MESHES)
	surface_type_pm.set_item_checked(common.SurfaceTypes.COLLISION_OBJECTS, true)
	surface_type_pm.id_pressed.connect(_on_surface_type_pm_id_pressed)

	# Setup snap type submenu
	snap_type_pm = PopupMenu.new()
	snap_type_pm.name = "SnapTypePM"
	snap_type_pm.add_radio_check_item("Snap to Surface", common.SnapTypes.SNAP_TO_SURFACE)
	snap_type_pm.add_radio_check_item("Snap Along Normals", common.SnapTypes.SNAP_ALONG_NORMAL)
	snap_type_pm.set_item_checked(common.SnapTypes.SNAP_TO_SURFACE, true)
	snap_type_pm.id_pressed.connect(_on_snap_type_pm_id_pressed)

	# Setup main popup
	pm = get_popup()
	pm.add_child(surface_type_pm)
	pm.add_child(snap_type_pm)
	pm.add_submenu_item("Surface Type", "SurfaceTypePM", common.RootItems.SURFACE_TYPE_SUBMENU)
	pm.add_submenu_item("Snap Type", "SnapTypePM", common.RootItems.SNAP_TYPE_SUBMENU)
	pm.add_item("Configure Collision Mask", common.RootItems.CONFIGURE_MASK)
	pm.id_pressed.connect(_on_main_pm_id_pressed)

func _exit_tree() -> void:
	if dialog_configure_mask:
		dialog_configure_mask.queue_free()

func _on_surface_type_pm_id_pressed(id: int) -> void:
	new_surface_type_selected.emit(id)
	for i: int in common.SurfaceTypes.values():
		surface_type_pm.set_item_checked(i, i == id)

func _on_snap_type_pm_id_pressed(id: int) -> void:
	new_snap_type_selected.emit(id)
	for i: int in common.SnapTypes.values():
		snap_type_pm.set_item_checked(i, i == id)

func _on_main_pm_id_pressed(id: int) -> void:
	match id:
		common.RootItems.CONFIGURE_MASK:
			dialog_configure_mask = common.DIALOG_CONFIGURE_MASK_SCENE.instantiate()
			dialog_configure_mask.connect("on_confirm", _on_mask_config_confirm)
			dialog_configure_mask.set("mask", collision_mask)
			dialog_configure_mask.close_requested.connect(_on_close_config)
			dialog_configure_mask.hide()
			configure_mask_window_instantiated.emit(dialog_configure_mask)
		
func _on_mask_config_confirm(mask: int) -> void:
	collision_mask_changed.emit(mask)
	dialog_configure_mask.queue_free()
	if mask == collision_mask:
		return
	collision_mask = mask

func _on_close_config() -> void:
	dialog_configure_mask.queue_free()