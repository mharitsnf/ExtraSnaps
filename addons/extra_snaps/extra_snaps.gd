@tool
extends EditorPlugin

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

func _enter_tree() -> void:
	# Setup tool button
	tool_button = preload("res://addons/extra_snaps/es_menu_button.tscn").instantiate()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, tool_button)
	
	# Setup popup menu
	pm = tool_button.get_popup()
	pm.add_radio_check_item(snap_type_labels[SnapType.SNAP_TO_SURFACE], SnapType.SNAP_TO_SURFACE)
	pm.add_radio_check_item(snap_type_labels[SnapType.SNAP_ALONG_NORMAL], SnapType.SNAP_ALONG_NORMAL)
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

	InputMap.erase_action("extra_snaps_move")

func _handles(object: Object) -> bool:
	if object is Node3D:
		selected = object
		return true

	selected = null
	return false

var csg_use_collision: bool = false
func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	move_pressed = Input.is_action_pressed("extra_snaps_move")

	if Input.is_action_just_released("extra_snaps_move") and has_moved:
		if selected is CSGShape3D:
			selected.use_collision = csg_use_collision
		undoredo_action.add_do_property(selected, "position", Vector3(selected.position))
		undoredo_action.add_do_property(selected, "basis", Basis(selected.basis))
		undoredo_action.commit_action()
		has_moved = false

	if move_pressed and selected:
		if event is InputEventMouseMotion:
			return _move_selection(viewport_camera, event)

	return AFTER_GUI_INPUT_PASS

func _on_popup_id_pressed(id: int) -> void:
	if SnapType.values().has(id):
		current_snap_type = id
		for i in SnapType.values():
			pm.set_item_checked(i, i == id)

const RAY_LENGTH: float = 1000.
func _move_selection(viewport_camera: Camera3D, event: InputEventMouseMotion) -> int:
	if !has_moved:
		undoredo_action.create_action("ExtraSnaps: Transform Changed")
		if selected is CSGShape3D:
			csg_use_collision = selected.use_collision
			selected.use_collision = false
		undoredo_action.add_undo_property(selected, "position", Vector3(selected.position))
		undoredo_action.add_undo_property(selected, "basis", Basis(selected.basis))
		has_moved = true
	
	var from: Vector3 = viewport_camera.project_ray_origin(event.position)
	var to: Vector3 = from + viewport_camera.project_ray_normal(event.position) * RAY_LENGTH
	var space: PhysicsDirectSpaceState3D = viewport_camera.get_world_3d().direct_space_state
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	if selected is PhysicsBody3D:
		ray_query.exclude = [selected]
	if selected is CSGShape3D:
		ray_query.exclude = [selected]
	ray_query.from = from
	ray_query.to = to
	var result: Dictionary = space.intersect_ray(ray_query)
	
	match current_snap_type:
		SnapType.SNAP_TO_SURFACE:
			if result.has("position"):
				selected.position = result.position
			
		SnapType.SNAP_ALONG_NORMAL:
			if result.has("position"):
				selected.position = result.position
			if result.has("normal"):
				selected.quaternion = get_quaternion_from_normal(selected.basis, result.normal)

	return AFTER_GUI_INPUT_STOP

func get_quaternion_from_normal(old_basis: Basis, new_normal: Vector3) -> Quaternion:
	new_normal = new_normal.normalized()

	var quat : Quaternion = Quaternion(old_basis.y, new_normal).normalized()
	var new_right : Vector3 = quat * old_basis.x
	var new_fwd : Vector3 = quat * old_basis.z

	return Basis(new_right, new_normal, new_fwd).get_rotation_quaternion()