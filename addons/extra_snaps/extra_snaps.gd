@tool
extends EditorPlugin

var new_config = ConfigFile.new()
const SETTINGS_FILE_PATH = "user://extra_snaps.cfg"
var has_config = false

var undoredo_action: EditorUndoRedoManager = get_undo_redo()

var tool_button: ESMenuButton
var pm: PopupMenu

enum SnapType { SNAP_TO_SURFACE, SNAP_ALONG_NORMAL }
var current_snap_type: SnapType = SnapType.SNAP_TO_SURFACE
var snap_type_labels: Dictionary = {
	SnapType.SNAP_TO_SURFACE: "Snap to Surface",
	SnapType.SNAP_ALONG_NORMAL: "Snap Along Normal",
}
var selected: Node3D = null
var has_moved: bool = false
var move_pressed: bool = false

# https://github.com/godotengine/godot-proposals/issues/2411
const INT32_MAX = 4294967295
# All collisions are enabled by default
var collision_mask: int = INT32_MAX
var DialogConfigureMaskScene = preload("res://addons/extra_snaps/dialog_configure_mask.tscn")
var dialog_configure_mask: Window
const ConfigureDialogToolButtonId = 2

func _enter_tree() -> void:
	# Initialize Configuration File
	var err = new_config.load(SETTINGS_FILE_PATH)
	if err != OK:
		if err == ERR_FILE_NOT_FOUND:
			err = new_config.save(SETTINGS_FILE_PATH)
		if err != OK:
			print("ExtraSnaps: loading config file failed: " + str(err))
	if err == OK:
		has_config = true
	if has_config:
		collision_mask = new_config.get_value("collision_mask", "collision_mask", collision_mask)

	# Setup tool button
	tool_button = preload("res://addons/extra_snaps/es_menu_button.tscn").instantiate()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, tool_button)
	
	# Setup popup menu
	pm = tool_button.get_popup()
	pm.add_radio_check_item(snap_type_labels[SnapType.SNAP_TO_SURFACE], SnapType.SNAP_TO_SURFACE)
	pm.add_radio_check_item(snap_type_labels[SnapType.SNAP_ALONG_NORMAL], SnapType.SNAP_ALONG_NORMAL)
	pm.add_separator()
	pm.add_item("Configure Mask", ConfigureDialogToolButtonId)
	pm.set_item_checked(SnapType.SNAP_TO_SURFACE, true)
	pm.id_pressed.connect(_on_popup_id_pressed)

	# Configure shortcut key
	InputMap.add_action("extra_snaps_move")
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = KEY_W
	ev.ctrl_pressed = true
	ev.command_or_control_autoremap = true
	InputMap.action_add_event("extra_snaps_move", ev)

func _exit_tree() -> void:
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, tool_button)
	tool_button.queue_free()
	dialog_configure_mask.queue_free()

	InputMap.erase_action("extra_snaps_move")

var selected_children: Array[Node] = []
func _handles(object: Object) -> bool:
	if object is Node3D:
		selected = object
		var out: Array[Node] = []
		get_all_children(out, object, [CollisionObject3D, CSGShape3D])
		selected_children = out
		return true

	selected = null
	selected_children = []
	return false

var csg_use_collisions: Array[Dictionary] = []
func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	move_pressed = Input.is_action_pressed("extra_snaps_move")

	if Input.is_action_just_released("extra_snaps_move") and has_moved:
		for csg_data: Dictionary in csg_use_collisions:
			(csg_data['node'] as CSGShape3D).use_collision = csg_data['use_collision']
		
		csg_use_collisions = []

		undoredo_action.add_do_property(selected, "global_position", Vector3(selected.global_position))
		undoredo_action.add_do_property(selected, "global_basis", Basis(selected.global_basis))
		undoredo_action.commit_action()
		has_moved = false

	if move_pressed and selected:
		if event is InputEventMouseMotion:
			return _move_selection(viewport_camera, event)

	return AFTER_GUI_INPUT_PASS

func _close_config() -> void:
	dialog_configure_mask.queue_free()

func save_config():
	if has_config:
		new_config.set_value("collision_mask", "collision_mask", collision_mask)
		new_config.save(SETTINGS_FILE_PATH)

func on_mask_config_confirm(mask: int) -> void:
	dialog_configure_mask.queue_free()
	if mask == collision_mask:
		return
	var old_mask = collision_mask
	collision_mask = mask
	undoredo_action.create_action("ExtraSnaps: Collision Mask Changed")
	undoredo_action.add_do_property(self, "collision_mask", mask)
	undoredo_action.add_undo_property(self, "collision_mask", old_mask)
	undoredo_action.add_do_method(self, "save_config")
	undoredo_action.add_undo_method(self, "save_config")
	undoredo_action.commit_action()
	save_config()

func _on_popup_id_pressed(id: int) -> void:
	if id == ConfigureDialogToolButtonId:
		dialog_configure_mask = DialogConfigureMaskScene.instantiate()
		dialog_configure_mask.connect("on_confirm", on_mask_config_confirm)
		dialog_configure_mask.set("mask", collision_mask)
		dialog_configure_mask.close_requested.connect(_close_config)
		dialog_configure_mask.hide()
		var editor_interface = get_editor_interface()
		var base_control = editor_interface.get_base_control()
		base_control.add_child(dialog_configure_mask)
		dialog_configure_mask.popup_centered()

	if SnapType.values().has(id):
		current_snap_type = id
		for i in SnapType.values():
			pm.set_item_checked(i, i == id)

const RAY_LENGTH: float = 1000.
func _move_selection(viewport_camera: Camera3D, event: InputEventMouseMotion) -> int:
	if !has_moved:
		undoredo_action.create_action("ExtraSnaps: Transform Changed")

		# If the currently selected node is a CSG, store its use_collision status
		# and set it to false throughout the transform.
		if selected is CSGShape3D:
			csg_use_collisions.append({
				"node": selected,
				"use_collision": selected.use_collision
			})
			selected.use_collision = false

		# Also do the same for the children of the selected node.
		for child: Node in selected_children:
			if child is CSGShape3D:
				csg_use_collisions.append({
					"node": child,
					"use_collision": child.use_collision
				})
				child.use_collision = false
		
		undoredo_action.add_undo_property(selected, "global_position", Vector3(selected.global_position))
		undoredo_action.add_undo_property(selected, "global_basis", Basis(selected.global_basis))
		has_moved = true
	
	var from: Vector3 = viewport_camera.project_ray_origin(event.position)
	var to: Vector3 = from + viewport_camera.project_ray_normal(event.position) * RAY_LENGTH
	var space: PhysicsDirectSpaceState3D = viewport_camera.get_world_3d().direct_space_state
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()

	# Exclude selected node and its children if its or CollisionObject3D.
	# (CSG exclusion happens before first movement)
	var exclude_list: Array[RID] = []

	# Exclude the selected node
	if selected is CollisionObject3D:
		exclude_list.append(selected.get_rid())
	
	# Exclude CollisionObject children of the selected node
	for child: Node in selected_children:
		if child is CollisionObject3D: 
			exclude_list.append((child as CollisionObject3D).get_rid())
	
	ray_query.exclude = exclude_list

	ray_query.from = from
	ray_query.to = to
	ray_query.collision_mask = collision_mask
	var result: Dictionary = space.intersect_ray(ray_query)
	
	match current_snap_type:
		SnapType.SNAP_TO_SURFACE:
			if result.has("position"):
				selected.global_position = result.position
			
		SnapType.SNAP_ALONG_NORMAL:
			if result.has("position"):
				selected.global_position = result.position
			if result.has("normal"):
				var g_quat: Quaternion = get_quaternion_from_normal(selected.global_basis, result.normal)
				selected.global_basis = Basis(g_quat)

	return AFTER_GUI_INPUT_STOP

## Returns all the children of [node] recursively. Limit to specific types using [types]. 
func get_all_children(out: Array[Node], node: Node, types: Array[Variant] = []) -> void:
	for child: Node in node.get_children():
		if types.is_empty():
			out.append(child)
		else:
			for type: Variant in types:
				if is_instance_of(child, type):
					out.append(child)
					break
		
		if child.get_child_count() > 0:
			get_all_children(out, child, types)


func get_quaternion_from_normal(old_basis: Basis, new_normal: Vector3) -> Quaternion:
	new_normal = new_normal.normalized()

	var quat : Quaternion = Quaternion(old_basis.y, new_normal).normalized()
	var new_right : Vector3 = quat * old_basis.x
	var new_fwd : Vector3 = quat * old_basis.z

	return Basis(new_right, new_normal, new_fwd).get_rotation_quaternion()