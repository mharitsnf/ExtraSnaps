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

var selected_nodes: Array[Node] = []
var object_tris_cache: Array[Dictionary] = []
func _handles(object: Object) -> bool:
	if object is Node3D:
		# Set the newly selected object as selected
		selected = object

		# Add selected nodes to be excluded later
		var out: Array[Node] = []
		get_all_children(out, object, null, [CollisionObject3D, CSGShape3D, MeshInstance3D])
		selected_nodes = out

		selected_nodes.append(selected)
		
		return true

	selected = null
	selected_nodes = []
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

		object_tris_cache = []

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
		for child: Node in selected_nodes:
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
	# Preprocess / setup
	var viewport: SubViewport = viewport_camera.get_viewport()
	
	var edited_scene_root: Node = EditorInterface.get_edited_scene_root()
	if !(edited_scene_root is Node3D):
		push_error("The scene root must be a Node3D node.")
		return
	var scenario: RID = edited_scene_root.get_world_3d().scenario
	
	var event_position_scale: Vector2 = Vector2.ONE / viewport.get_screen_transform().get_scale()
	var screen_position: Vector2 = event.position * event_position_scale

	# Camera and result variable setup
	var from: Vector3 = viewport_camera.project_ray_origin(screen_position)
	var to: Vector3 = viewport_camera.project_ray_normal(screen_position)

	var min_t: float = common.FLOAT64_MAX
	var min_p: Vector3 = Vector3.INF
	var min_n: Vector3

	# Get intersecting meshes, convert them from IDs to nodes
	var object_ids: PackedInt64Array = RenderingServer.instances_cull_ray(from, to * common.SCENARIO_RAY_DISTANCE, scenario)
	var intersected_nodes: Array = Array(object_ids).map(func (id: int) -> Object: return instance_from_id(id))

	# Loop through the intersecting meshes, add them to a global variable (object_tris_cache) if they're not in it already
	for node: Object in intersected_nodes:
		# Exclude the node if it's a child of the selected object
		if selected_nodes.has(node): continue
		
		# Do not process the mesh instance again if it has already been processed
		var node_data: Array[Dictionary] = object_tris_cache.filter(func (data: Dictionary) -> bool: return data.node == node)
		if !node_data.is_empty(): continue

		# Otherwise, create the cache
		# Returned format: { node, aabb, global tris }
		if node is MeshInstance3D: object_tris_cache.append(get_mesh_instance_data(node))
		elif node is CSGShape3D: object_tris_cache.append(get_csg_data(node))

	# Get the intersecting meshes cache
	var intersected_nodes_data = object_tris_cache.filter(func (data: Dictionary) -> bool: return intersected_nodes.has(data.node))

	# Find the closest point
	for data: Dictionary in intersected_nodes_data:
		var time1: float = Time.get_ticks_usec()
		var tris: PackedVector3Array = data['tris']
		for i: int in range(0, tris.size(), 3):
			var v0: Vector3 = tris[i + 0]
			var v1: Vector3 = tris[i + 1]
			var v2: Vector3 = tris[i + 2]
			var res: Variant = Geometry3D.ray_intersects_triangle(from, to, v2, v1, v0)
			if res is Vector3:
				var len: float = from.distance_squared_to(res)
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
	# Preprocess
	var viewport: SubViewport = viewport_camera.get_viewport()
	var event_position_scale: Vector2 = Vector2.ONE / viewport.get_screen_transform().get_scale()
	var screen_position: Vector2 = event.position * event_position_scale

	# Physics snapping
	var from: Vector3 = viewport_camera.project_ray_origin(screen_position)
	var to: Vector3 = from + viewport_camera.project_ray_normal(screen_position) * RAY_LENGTH
	var space: PhysicsDirectSpaceState3D = viewport_camera.get_world_3d().direct_space_state
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()

	# Exclude selected node and its children if its or CollisionObject3D.
	# (CSG exclusion happens before first movement)
	var exclude_list: Array[RID] = []

	# Exclude the selected node
	if selected is CollisionObject3D:
		exclude_list.append(selected.get_rid())
	
	# Exclude CollisionObject children of the selected node
	for child: Node in selected_nodes:
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

## Returns mesh instance data containing the node instance, global aabb, and global tris. Return format: { node, aabb, tris }
func get_mesh_instance_data(node: MeshInstance3D) -> Dictionary:
	var mesh: Mesh = node.mesh
	var aabb: AABB = node.global_transform * node.get_aabb()
	
	if !mesh: return { "node": node, "aabb": aabb, "tris": [] }

	var tris: PackedVector3Array = []
	
	var verts: PackedVector3Array = mesh.get_faces()
	for vert: Vector3 in verts:
		tris.append(node.global_transform * vert)

	return { "node": node, "aabb": aabb, "tris": tris }

## Returns CSG data containing the node instance, global aabb, and global tris. Return format: { node, aabb, tris }
func get_csg_data(node: CSGShape3D) -> Dictionary:
	var meshes: Array = node.get_meshes()
	var aabb: AABB = node.global_transform * node.get_aabb()

	if meshes.is_empty(): return { "node": node, "aabb": aabb, "tris": [] }

	var tris: PackedVector3Array = []

	var verts: PackedVector3Array = (meshes[1] as ArrayMesh).get_faces()
	for vert: Vector3 in verts:
		tris.append(node.global_transform * vert)

	return { "node": node, "aabb": aabb, "tris": tris }

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