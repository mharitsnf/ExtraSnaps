@tool
extends EditorPlugin

const common = preload('./common.gd')

var tool_button: ESMenuButton

var new_config = ConfigFile.new()
var has_config = false

var undoredo_action: EditorUndoRedoManager = get_undo_redo()

var current_surface_type: common.SurfaceTypes = common.SurfaceTypes.COLLISION_OBJECTS
var current_snap_type: common.SnapTypes = common.SnapTypes.SNAP_TO_SURFACE

var selected: Node3D = null
var has_moved: bool = false
var move_pressed: bool = false

var collision_mask: int = common.INT32_MAX

# region Lifecycle functions

func _enter_tree() -> void:
	# Initialize Configuration File
	var err = new_config.load(common.SETTINGS_FILE_PATH)
	if err != OK:
		if err == ERR_FILE_NOT_FOUND:
			err = new_config.save(common.SETTINGS_FILE_PATH)
		if err != OK:
			print("ExtraSnaps: loading config file failed: " + str(err))
	if err == OK:
		has_config = true
	if has_config:
		collision_mask = new_config.get_value("collision_mask", "collision_mask", collision_mask)

	# Setup tool button
	tool_button = common.ES_MENU_BUTTON_PSCN.instantiate()
	tool_button.collision_mask = collision_mask
	tool_button.new_surface_type_selected.connect(_on_new_surface_type_selected)
	tool_button.new_snap_type_selected.connect(_on_new_snap_type_selected)
	tool_button.configure_mask_window_instantiated.connect(_on_configure_mask_window_instantiated)
	tool_button.collision_mask_changed.connect(_on_collision_mask_changed)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, tool_button)

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

var selected_children: Array[Node] = []
var visual_instances_data: Array[Dictionary] = []
func _handles(object: Object) -> bool:
	if object is Node3D:
		selected = object
		visual_instances_data = []
		collect_global_tris(object)

		var out: Array[Node] = []
		get_all_children(out, object, null, [CollisionObject3D, CSGShape3D])
		selected_children = out
		return true

	selected = null
	selected_children = []
	visual_instances_data = []
	return false

var csg_use_collisions: Array[Dictionary] = []
func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	move_pressed = Input.is_action_pressed("extra_snaps_move")

	# On complete movement
	if Input.is_action_just_released("extra_snaps_move") and has_moved:
		for csg_data: Dictionary in csg_use_collisions:
			(csg_data['node'] as CSGShape3D).use_collision = csg_data['use_collision']
		
		csg_use_collisions = []

		undoredo_action.add_do_property(selected, "global_transform", Transform3D(selected.global_transform))
		undoredo_action.commit_action()
		has_moved = false

	# During movement
	if move_pressed and selected:
		if event is InputEventMouseMotion:
			return _move_selection(viewport_camera, event)

	return AFTER_GUI_INPUT_PASS

# region ES Menu Button Signal Listener

func _on_configure_mask_window_instantiated(window: Window) -> void:
	var editor_interface = get_editor_interface()
	var base_control = editor_interface.get_base_control()
	base_control.add_child(window)
	window.popup_centered()

func _on_new_surface_type_selected(id: common.SurfaceTypes) -> void:
	current_surface_type = id

func _on_new_snap_type_selected(id: common.SnapTypes) -> void:
	current_snap_type = id

func _on_collision_mask_changed(mask: int) -> void:
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

func save_config():
	if has_config:
		new_config.set_value("collision_mask", "collision_mask", collision_mask)
		new_config.save(common.SETTINGS_FILE_PATH)

# region Movement handling

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
		
		undoredo_action.add_undo_property(selected, "global_transform", Transform3D(selected.global_transform))
		has_moved = true

	match current_surface_type:
		common.SurfaceTypes.COLLISION_OBJECTS: _collision_objects_snapping(viewport_camera, event)
		common.SurfaceTypes.MESHES: _mesh_snapping(viewport_camera, event)

	return AFTER_GUI_INPUT_STOP

func _mesh_snapping(viewport_camera: Camera3D, event: InputEventMouseMotion) -> void:
	# Mesh snapping
	var from: Vector3 = viewport_camera.project_ray_origin(event.position)
	var to: Vector3 = viewport_camera.project_ray_normal(event.position)

	var min_t: float = common.FLOAT64_MAX
	var min_p: Vector3 = Vector3.INF
	var min_n: Vector3

	var data_to_process: Array[Dictionary] = []

	# Check if aabb of visual instance intersects
	for data: Dictionary in visual_instances_data:
		var global_aabb: AABB = data['aabb']
		var res: Variant = global_aabb.intersects_ray(from, to)
		if res is Vector3:
			data_to_process.append(data)

	for data: Dictionary in data_to_process:
		var tris: PackedVector3Array = data['tris']
		for i: int in range(0, tris.size(), 3):
			var v0: Vector3 = tris[i + 0]
			var v1: Vector3 = tris[i + 1]
			var v2: Vector3 = tris[i + 2]
			var res: Variant = Geometry3D.ray_intersects_triangle(from, to, v2, v1, v0)
			if res is Vector3:
				var len: float = from.distance_to(res)
				if len < min_t:
					min_t = len
					min_p = res
					var v0v1: Vector3 = v1 - v0
					var v0v2: Vector3 = v2 - v0
					min_n = v0v2.cross(v0v1)

	if min_t >= common.FLOAT64_MAX: return

	match current_snap_type:
		common.SnapTypes.SNAP_TO_SURFACE:
			selected.global_position = min_p
		common.SnapTypes.SNAP_ALONG_NORMAL:
			selected.global_position = min_p
			var g_quat: Quaternion = get_quaternion_from_normal(selected.global_basis, min_n)
			selected.global_basis = Basis(g_quat)

func _collision_objects_snapping(viewport_camera: Camera3D, event: InputEventMouseMotion) -> void:
	# Physics snapping
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
		common.SnapTypes.SNAP_TO_SURFACE:
			if result.has("position"):
				selected.global_position = result.position
			
		common.SnapTypes.SNAP_ALONG_NORMAL:
			if result.has("position"):
				selected.global_position = result.position
			if result.has("normal"):
				var g_quat: Quaternion = get_quaternion_from_normal(selected.global_basis, result.normal)
				selected.global_basis = Basis(g_quat)

# region Common functions

## Get global triangle of all nodes in the scene, except the [exclude] node and its children.
func collect_global_tris(exclude: Node) -> void:
	var nodes: Array[Node] = []
	get_all_children(nodes, EditorInterface.get_edited_scene_root(), exclude, [MeshInstance3D, CSGShape3D])
	for node: Node in nodes:
		if node is MeshInstance3D:
			var mesh: Mesh = node.mesh
			if !mesh: continue
			
			var aabb: AABB = node.global_transform * node.get_aabb()
			var tris: PackedVector3Array = []
			
			var verts: PackedVector3Array = mesh.get_faces()
			for vert: Vector3 in verts:
				tris.append(node.global_transform * vert)

			visual_instances_data.append({ "node": node, "aabb": aabb, "tris": tris })

		elif node is CSGShape3D:
			var meshes: Array = node.get_meshes()
			if meshes.is_empty(): continue

			var aabb: AABB = node.global_transform * node.get_aabb()
			var tris: PackedVector3Array = []

			var verts: PackedVector3Array = (meshes[1] as ArrayMesh).get_faces()
			for vert: Vector3 in verts:
				tris.append(node.global_transform * vert)

			visual_instances_data.append({ "node": node, "aabb": aabb, "tris": tris })

## Transform local triangle to global triangle.
func _local_tri_to_global_tri(trf: Transform3D, tri: Vector3) -> Vector3:
	return trf * tri

## Returns all the children of [node] recursively. Limit to specific types using [types]. 
func get_all_children(out: Array[Node], node: Node, exclude: Node = null, types: Array[Variant] = []) -> void:
	if node == exclude: return
	for child: Node in node.get_children():
		if child == exclude: continue

		if types.is_empty():
			out.append(child)
		else:
			for type: Variant in types:
				if is_instance_of(child, type):
					out.append(child)
					break
		
		if child.get_child_count() > 0:
			get_all_children(out, child, exclude, types)

func get_quaternion_from_normal(old_basis: Basis, new_normal: Vector3) -> Quaternion:
	new_normal = new_normal.normalized()

	var quat : Quaternion = Quaternion(old_basis.y, new_normal).normalized()
	var new_right : Vector3 = quat * old_basis.x
	var new_fwd : Vector3 = quat * old_basis.z

	return Basis(new_right, new_normal, new_fwd).get_rotation_quaternion()