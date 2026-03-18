extends Node3D

# --- Config Variables ---
var models_folder := "res://models"
var tile_x := 2.0
var tile_z := 2.0
var model_scale := 1.0

# --- State ---
var selected_model_path := ""
var selected_model_scale := 1.0
var grid_data := {}
var ghost_instance: Node3D = null
var placement_rotation_y := 0.0
var is_painting := false
var selected_instance: Node3D = null
var is_dragging_instance := false
var last_painted_grid_pos := Vector2.INF
var original_drag_grid_pos := Vector2.INF
var allow_same_asset_stacking := false
# NEW: State variables for tracking the current file and modification status.
var current_scene_name: String = ""
var is_modified := false

# --- Nodes ---
@onready var placed_models_container: Node3D = %PlacedModelsContainer
@onready var cursor: MeshInstance3D = %Cursor
@onready var camera_pivot: Node3D = %CameraPivot
@onready var camera: Camera3D = %Camera3D
@onready var sun_light: DirectionalLight3D = %SunLight
@onready var asset_selector: PanelContainer = %AssetSelector
@onready var sun_settings: Window = %SunSettings
@onready var save_load_manager: Window = %SaveLoadManager
# NEW: Node reference for the "Save As" button.
@onready var btn_save_as: Button = %ButtonSaveAs
@onready var btn_save: Button = %ButtonSave
@onready var btn_load: Button = %ButtonLoad
@onready var btn_rotate: Button = %ButtonRotate
@onready var btn_delete: Button = %ButtonDelete
@onready var btn_sun: Button = %ButtonSun
@onready var btn_settings: Button = %ButtonSettings
@onready var settings_dialog: Window = %SettingsDialog
# NEW: Node references for the properties panel and its toggle button.
@onready var btn_properties: Button = %ButtonProperties
@onready var properties_panel: PanelContainer = %PropertiesPanel
@onready var btn_cycle_selection: Button = %ButtonCycleSelection
# NEW: Node reference for the status label in the bottom-left corner.
@onready var status_label: Label = %StatusLabel

# --- Materials ---
var ghost_material: StandardMaterial3D
var selection_material: StandardMaterial3D

# --- Camera State ---
var cam_zoom := 10.0
var cam_rot_x := -45.0
var cam_rot_y := 45.0

func _ready():
	_load_config()
	_setup_materials()
	_connect_ui_signals()
	
	var mesh = BoxMesh.new()                
	mesh.size = Vector3(tile_x, 0.1, tile_z) 
	cursor.mesh = mesh                      

	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.5, 0.0, 0.5) 
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA 
	cursor.material_override = material	
	
	# NEW: Initialize the status label on startup.
	_update_status_label()

func _process(delta):
	camera_pivot.rotation_degrees.x = lerp(camera_pivot.rotation_degrees.x, cam_rot_x, delta * 15.0)
	camera_pivot.rotation_degrees.y = lerp(camera_pivot.rotation_degrees.y, cam_rot_y, delta * 15.0)
	camera.position.z = lerp(camera.position.z, cam_zoom, delta * 10.0)

# ==========================================
# SETUP & LOADING
# ==========================================
func _load_config():
	var config = ConfigFile.new()
	if config.load("res://config.cfg") == OK:
		models_folder = config.get_value("Settings", "models_folder", "res://models")
		tile_x = float(config.get_value("Settings", "tile_size_x", 2.0))
		tile_z = float(config.get_value("Settings", "tile_size_z", 2.0))
		model_scale = float(config.get_value("Settings", "model_scale", 1.0))
		cam_zoom = float(config.get_value("Camera", "zoom", 10.0))
		cam_rot_x = float(config.get_value("Camera", "rotation_x", -45.0))
		cam_rot_y = float(config.get_value("Camera", "rotation_y", 45.0))
		sun_light.light_energy = float(config.get_value("Sun", "energy", 1.0))
		var sun_rot_x = float(config.get_value("Sun", "rotation_x", -50.0))
		var sun_rot_y = float(config.get_value("Sun", "rotation_y", -30.0))
		sun_light.rotation_degrees = Vector3(sun_rot_x, sun_rot_y, 0)

	if not DirAccess.dir_exists_absolute(models_folder):
		DirAccess.make_dir_absolute(models_folder)

func _setup_materials():
	ghost_material = StandardMaterial3D.new()
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.albedo_color = Color(0.4, 0.8, 1.0, 0.6)
	ghost_material.emission_enabled = true
	ghost_material.emission = Color(0.2, 0.4, 0.8)
	ghost_material.emission_energy_multiplier = 0.5
	
	selection_material = StandardMaterial3D.new()
	selection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_material.albedo_color = Color(1.0, 1.0, 0.0, 0.4)
	selection_material.emission_enabled = true
	selection_material.emission = Color(0.8, 0.8, 0.0)
	selection_material.emission_energy_multiplier = 0.8

func _connect_ui_signals():
	# MODIFIED: The save and save as buttons now connect to new handlers.
	btn_save.pressed.connect(_on_save_button_pressed)
	btn_save_as.pressed.connect(_on_save_as_button_pressed)
	btn_load.pressed.connect(save_load_manager.open)
	btn_rotate.pressed.connect(_rotate_placement)
	btn_delete.pressed.connect(_delete_model_at_cursor)
	btn_sun.pressed.connect(_on_sun_config_pressed)
	btn_settings.pressed.connect(_on_settings_button_pressed)
	settings_dialog.setting_changed.connect(_on_setting_changed)
	# NEW: Connect the signal for preview setting changes.
	settings_dialog.preview_settings_changed.connect(_on_preview_settings_changed)
	
	# NEW: Connect properties panel and cycle selection buttons and signals.
	btn_properties.pressed.connect(properties_panel.toggle_visibility)
	btn_cycle_selection.pressed.connect(_cycle_selection_on_tile)
	properties_panel.position_changed.connect(_on_properties_position_changed)
	properties_panel.scale_changed.connect(_on_properties_scale_changed)
	properties_panel.order_changed.connect(_on_properties_order_changed)
	# NEW: Connect the new signal from the properties panel for toggling grid snap.
	properties_panel.grid_snap_toggled.connect(_on_grid_snap_toggled)
	
	asset_selector.model_selected.connect(_on_model_selected)
	asset_selector.selection_cleared.connect(_deselect_model)
	sun_settings.sun_updated.connect(_on_sun_settings_updated)
	save_load_manager.save_requested.connect(_save_scene)
	save_load_manager.load_requested.connect(_load_scene)

func _on_model_selected(data: Dictionary):
	_deselect_instance()
	selected_model_path = data.get("path", "")
	selected_model_scale = data.get("scale", 1.0)
	_create_ghost(selected_model_path)

func _deselect_model():
	selected_model_path = ""
	if is_instance_valid(ghost_instance):
		ghost_instance.queue_free()
		ghost_instance = null
	_deselect_instance()
	asset_selector.clear_selection()
	print("Selection cleared.")

func _create_ghost(path: String):
	if is_instance_valid(ghost_instance):
		ghost_instance.queue_free()
	var scene = load(path)
	if scene:
		ghost_instance = scene.instantiate()
		cursor.add_child(ghost_instance)
		ghost_instance.scale = Vector3.ONE * selected_model_scale
		ghost_instance.rotation_degrees.y = placement_rotation_y
		_apply_ghost_material(ghost_instance)

func _apply_ghost_material(node: Node):
	if node is MeshInstance3D:
		node.material_overlay = ghost_material
	for child in node.get_children():
		_apply_ghost_material(child)

func _apply_selection_material(node: Node):
	if node is MeshInstance3D:
		node.material_overlay = selection_material
	for child in node.get_children():
		_apply_selection_material(child)

func _clear_material_overlay(node: Node):
	if node is MeshInstance3D:
		node.material_overlay = null
	for child in node.get_children():
		_clear_material_overlay(child)

# ==========================================
# SELECTION & MANIPULATION
# ==========================================
# MODIFIED: Now updates the properties panel on selection.
func _select_instance(instance: Node3D):
	if not is_instance_valid(instance): return
	_deselect_instance()
	if selected_model_path != "":
		selected_model_path = ""
		if is_instance_valid(ghost_instance):
			ghost_instance.queue_free()
			ghost_instance = null
		asset_selector.clear_selection()
	selected_instance = instance
	_apply_selection_material(selected_instance)
	
	# NEW: Update the properties panel with the selected instance's data.
	var grid_pos = _get_grid_pos_for_instance(selected_instance)
	var models_on_tile = grid_data.get(grid_pos, [])
	properties_panel.update_fields(selected_instance, models_on_tile, grid_pos)

# MODIFIED: Now clears and hides the properties panel.
func _deselect_instance():
	if is_instance_valid(selected_instance):
		_clear_material_overlay(selected_instance)
		selected_instance = null
		# NEW: Clear and hide the properties panel when nothing is selected.
		properties_panel.clear_and_hide()

# ==========================================
# PLACEMENT, ROTATION & DELETION
# ==========================================
func _rotate_placement():
	if is_instance_valid(selected_instance):
		_mark_as_modified() # NEW: Track modification.
		selected_instance.rotation_degrees.y = fmod(selected_instance.rotation_degrees.y + 90.0, 360.0)
		return
	placement_rotation_y = fmod(placement_rotation_y + 90.0, 360.0)
	if is_instance_valid(ghost_instance):
		ghost_instance.rotation_degrees.y = placement_rotation_y

# MODIFIED: Recalculates stack Y positions after deletion.
func _delete_model_at_cursor():
	var instance_to_delete = selected_instance
	var grid_pos_to_update = Vector2.INF

	if is_instance_valid(instance_to_delete):
		grid_pos_to_update = _get_grid_pos_for_instance(instance_to_delete)
		_deselect_instance()
		if grid_data.has(grid_pos_to_update):
			var models_on_tile: Array = grid_data[grid_pos_to_update]
			models_on_tile.erase(instance_to_delete)
			if models_on_tile.is_empty():
				grid_data.erase(grid_pos_to_update)
		instance_to_delete.queue_free()
	else:
		var grid_pos = Vector2(cursor.position.x, cursor.position.z)
		if grid_data.has(grid_pos):
			var models_on_tile: Array = grid_data[grid_pos]
			if not models_on_tile.is_empty():
				var model_to_delete = models_on_tile.pop_back()
				if is_instance_valid(model_to_delete):
					grid_pos_to_update = grid_pos
					model_to_delete.queue_free()
				if models_on_tile.is_empty():
					grid_data.erase(grid_pos)
			else:
				grid_data.erase(grid_pos)
	
	# NEW: After deleting, recalculate the Y positions of remaining items in the stack.
	if grid_pos_to_update != Vector2.INF:
		_recalculate_stack_y_positions(grid_pos_to_update)
	_mark_as_modified() # NEW: Track modification.

# ==========================================
# UI CALLBACKS
# ==========================================
func _on_sun_config_pressed():
	var current_settings = {
		"position": sun_light.position,
		"rotation_degrees": sun_light.rotation_degrees,
		"energy": sun_light.light_energy
	}
	sun_settings.open_with_settings(current_settings)

func _on_sun_settings_updated(new_settings: Dictionary):
	sun_light.position = new_settings.get("position", sun_light.position)
	sun_light.rotation_degrees = new_settings.get("rotation_degrees", sun_light.rotation_degrees)
	sun_light.light_energy = new_settings.get("energy", sun_light.light_energy)

# MODIFIED: Now also gets preview settings to populate the dialog.
func _on_settings_button_pressed():
	# Get general editor settings.
	var current_settings = {
		"allow_same_asset_stacking": allow_same_asset_stacking
	}
	# NEW: Get current preview settings from the asset selector.
	var preview_settings = asset_selector.get_current_preview_settings()
	# NEW: Merge the two dictionaries so all data is passed to the dialog.
	current_settings.merge(preview_settings)
	
	settings_dialog.open_with_settings(current_settings)

func _on_setting_changed(setting_name: String, new_value: Variant):
	if setting_name == "allow_same_asset_stacking":
		allow_same_asset_stacking = new_value
		print("Allow same asset stacking set to: ", allow_same_asset_stacking)

# NEW: Handles the new signal from the settings dialog to apply preview overrides.
func _on_preview_settings_changed(settings: Dictionary):
	asset_selector.apply_preview_overrides(settings)

# NEW: Handles the main "Save" button press.
func _on_save_button_pressed():
	# If we don't have a name/path yet, it behaves like "Save As".
	if current_scene_name.is_empty():
		save_load_manager.open()
	else:
		# Otherwise, save directly to the known file.
		_save_scene(current_scene_name)

# NEW: Handles the "Save As" button press, which always opens the dialog.
func _on_save_as_button_pressed():
	save_load_manager.open()

# NEW: Marks the scene as modified and updates the UI label.
func _mark_as_modified():
	if not is_modified:
		is_modified = true
		_update_status_label()

# NEW: Updates the text of the status label in the bottom-left corner.
func _update_status_label():
	var file_text = current_scene_name if not current_scene_name.is_empty() else "Untitled"
	var modified_star = " *" if is_modified else ""
	status_label.text = file_text + modified_star

# ==========================================
# PROPERTIES PANEL HANDLERS
# ==========================================
# NEW: Handles position changes from the properties panel.
func _on_properties_position_changed(new_pos: Vector3):
	if not is_instance_valid(selected_instance): return
	
	var old_grid_pos = _get_grid_pos_for_instance(selected_instance)
	selected_instance.position = new_pos
	# Mark the instance as off-grid so it no longer snaps.
	selected_instance.set_meta("uses_grid_snap", false)
	_update_grid_data_for_moved_instance(selected_instance, old_grid_pos)
	_mark_as_modified() # NEW: Track modification.

# NEW: Handles scale changes from the properties panel.
func _on_properties_scale_changed(new_scale: float):
	if not is_instance_valid(selected_instance): return
	
	selected_instance.scale = Vector3.ONE * new_scale
	selected_instance.set_meta("model_scale", new_scale)
	
	# After scaling, recalculate the stack it's in.
	var grid_pos = _get_grid_pos_for_instance(selected_instance)
	_recalculate_stack_y_positions(grid_pos)
	_mark_as_modified() # NEW: Track modification.

# NEW: Handles re-ordering requests from the properties panel.
func _on_properties_order_changed(direction: int):
	if not is_instance_valid(selected_instance): return
	
	var grid_pos = _get_grid_pos_for_instance(selected_instance)
	var models_on_tile: Array = grid_data.get(grid_pos, [])
	
	if models_on_tile.size() > 1:
		var current_index = models_on_tile.find(selected_instance)
		var new_index = current_index + direction
		
		if new_index >= 0 and new_index < models_on_tile.size():
			models_on_tile.remove_at(current_index)
			models_on_tile.insert(new_index, selected_instance)
			_recalculate_stack_y_positions(grid_pos)
			# Refresh the panel to update button states.
			properties_panel.update_fields(selected_instance, models_on_tile, grid_pos)
	_mark_as_modified() # NEW: Track modification.

# NEW: Handles the toggle for grid snapping from the properties panel.
func _on_grid_snap_toggled(should_snap: bool):
	if not is_instance_valid(selected_instance): return
	
	selected_instance.set_meta("uses_grid_snap", should_snap)
	
	# If we are re-enabling snapping, move the object to the correct grid position.
	if should_snap:
		var grid_pos = _get_grid_pos_for_instance(selected_instance)
		selected_instance.position.x = grid_pos.x
		selected_instance.position.z = grid_pos.y
		
	_mark_as_modified() # NEW: Track modification.

# ==========================================
# INPUT & CAMERA CONTROLS
# ==========================================
func _unhandled_input(event):
	var mouse_pos = get_viewport().get_mouse_position()
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE: _deselect_model()
		if event.keycode == KEY_R: _rotate_placement()
		if event.keycode == KEY_D: _delete_model_at_cursor()
		# NEW: Hotkey to cycle through assets on the same tile.
		if event.keycode == KEY_C: _cycle_selection_on_tile()
		if event.is_match(event): get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		if selected_model_path != "" or is_dragging_instance:
			_update_cursor(mouse_pos)
		if is_painting:
			if selected_model_path != "" and not Input.is_key_pressed(KEY_SHIFT):
				_place_model()
		elif is_dragging_instance and is_instance_valid(selected_instance):
			_drag_selected_instance()
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or (Input.is_key_pressed(KEY_SHIFT) and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
			if asset_selector.get_global_rect().has_point(mouse_pos): return
			var right = camera.global_transform.basis.x
			var forward = camera.global_transform.basis.z
			forward.y = 0; forward = forward.normalized()
			var pan_speed = 0.01 * cam_zoom
			camera_pivot.global_position -= (right * event.relative.x + forward * event.relative.y) * pan_speed
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			if asset_selector.get_global_rect().has_point(mouse_pos): return
			cam_rot_y -= event.relative.x * 0.4
			cam_rot_x -= event.relative.y * 0.4
			cam_rot_x = clamp(cam_rot_x, -89.0, -10.0)
	if event is InputEventPanGesture:
		if asset_selector.get_global_rect().has_point(mouse_pos): return
		cam_zoom += event.delta.y * 0.5
		cam_zoom = clamp(cam_zoom, 2.0, 60.0)
	elif event is InputEventMouseButton:
		# MODIFIED: Added properties_panel to the UI check.
		if asset_selector.get_global_rect().has_point(mouse_pos) or \
		(sun_settings.visible and sun_settings.get_global_rect().has_point(mouse_pos)) or \
		(save_load_manager.visible and save_load_manager.get_global_rect().has_point(mouse_pos)) or \
		(settings_dialog.visible and settings_dialog.get_global_rect().has_point(mouse_pos)) or \
		(properties_panel.visible and properties_panel.get_global_rect().has_point(mouse_pos)):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: cam_zoom -= 1.5
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: cam_zoom += 1.5
		cam_zoom = clamp(cam_zoom, 2.0, 60.0)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if selected_model_path != "" and not event.shift_pressed:
					is_painting = true
					last_painted_grid_pos = Vector2.INF
					_place_model()
				else:
					_update_cursor(mouse_pos)
					var grid_pos = Vector2(cursor.position.x, cursor.position.z)
					if grid_data.has(grid_pos) and not grid_data[grid_pos].is_empty():
						var model_to_select = grid_data[grid_pos].back()
						_select_instance(model_to_select)
						is_dragging_instance = true
						original_drag_grid_pos = _get_grid_pos_for_instance(selected_instance)
					else:
						_deselect_instance()
			else:
				if is_dragging_instance and is_instance_valid(selected_instance):
					_update_grid_data_for_moved_instance(selected_instance, original_drag_grid_pos)
					_mark_as_modified() # NEW: Track modification.
				is_painting = false
				is_dragging_instance = false

func _update_cursor(mouse_pos: Vector2):
	var origin = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	if dir.y >= 0: return
	var t = -origin.y / dir.y
	var intersection = origin + dir * t
	var sn_x = round(intersection.x / tile_x) * tile_x
	var sn_z = round(intersection.z / tile_z) * tile_z
	cursor.position = Vector3(sn_x, 0, sn_z)
	
	if is_instance_valid(ghost_instance) or is_dragging_instance:
		var grid_pos = Vector2(sn_x, sn_z)
		var y_offset = 0.0
		
		if grid_data.has(grid_pos):
			var models_on_tile: Array = grid_data[grid_pos]
			var potential_stack_base = models_on_tile.duplicate()
			
			if is_dragging_instance and is_instance_valid(selected_instance):
				potential_stack_base.erase(selected_instance)

			if not potential_stack_base.is_empty():
				var top_model = potential_stack_base.back()
				var source_model_path = selected_model_path if selected_model_path != "" else selected_instance.get_meta("model_path")
				
				if not allow_same_asset_stacking and top_model.get_meta("model_path") == source_model_path:
					potential_stack_base.pop_back() 
					if not potential_stack_base.is_empty():
						var next_model_down = potential_stack_base.back()
						y_offset = _get_node_top_y(next_model_down)
				else:
					y_offset = _get_node_top_y(top_model)
		
		if is_instance_valid(ghost_instance):
			ghost_instance.position.y = y_offset
		elif is_dragging_instance and is_instance_valid(selected_instance):
			selected_instance.position.y = y_offset

# MODIFIED: Now handles objects that are not snapped to the grid.
func _drag_selected_instance():
	if not is_instance_valid(selected_instance): return
	
	# Raycast to find the ground intersection point.
	var mouse_pos = get_viewport().get_mouse_position()
	var origin = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	if dir.y >= 0: return
	var t = -origin.y / dir.y
	var intersection = origin + dir * t

	# If the instance is set to use grid snapping, snap its position.
	if selected_instance.get_meta("uses_grid_snap", true):
		var sn_x = round(intersection.x / tile_x) * tile_x
		var sn_z = round(intersection.z / tile_z) * tile_z
		selected_instance.position.x = sn_x
		selected_instance.position.z = sn_z
	else: # Otherwise, use the precise intersection point.
		selected_instance.position.x = intersection.x
		selected_instance.position.z = intersection.z

# MODIFIED: Recalculates Y positions on the old stack after a move.
func _update_grid_data_for_moved_instance(instance: Node3D, old_grid_pos: Vector2):
	if not is_instance_valid(instance): return
	
	# Remove instance from its old tile in grid_data.
	if grid_data.has(old_grid_pos):
		var old_tile_models: Array = grid_data[old_grid_pos]
		old_tile_models.erase(instance)
		if old_tile_models.is_empty():
			grid_data.erase(old_grid_pos)
		else:
			# NEW: Recalculate the stack that the instance was moved FROM.
			_recalculate_stack_y_positions(old_grid_pos)
			
	# Add instance to its new tile in grid_data.
	var new_grid_pos = _get_grid_pos_for_instance(instance)
	if not grid_data.has(new_grid_pos):
		grid_data[new_grid_pos] = []
	var new_tile_models: Array = grid_data[new_grid_pos]
	new_tile_models.append(instance)
	# Sort the new tile's array by Y position to maintain correct stacking order.
	new_tile_models.sort_custom(func(a, b): return a.position.y < b.position.y)
	
	# NEW: Refresh the properties panel if the moved instance is still selected.
	if is_instance_valid(selected_instance) and selected_instance == instance:
		properties_panel.update_fields(instance, new_tile_models, new_grid_pos)

# ==========================================
# PLACEMENT & SAVE/LOAD
# ==========================================
# NEW: Cycles through selecting assets on the tile under the cursor.
func _cycle_selection_on_tile():
	var grid_pos = Vector2(cursor.position.x, cursor.position.z)
	var models_on_tile: Array = grid_data.get(grid_pos, [])
	
	if models_on_tile.is_empty():
		_deselect_instance()
		return
		
	var current_selection_index = -1
	if is_instance_valid(selected_instance) and models_on_tile.has(selected_instance):
		current_selection_index = models_on_tile.find(selected_instance)
		
	var next_index = (current_selection_index + 1) % models_on_tile.size()
	_select_instance(models_on_tile[next_index])

# NEW: Helper function to get the representative grid position for an instance.
func _get_grid_pos_for_instance(instance: Node3D) -> Vector2:
	var x = round(instance.position.x / tile_x) * tile_x
	var z = round(instance.position.z / tile_z) * tile_z
	return Vector2(x, z)

# NEW: Recalculates and updates the Y positions for all assets in a stack.
func _recalculate_stack_y_positions(grid_pos: Vector2):
	var models_on_tile: Array = grid_data.get(grid_pos, [])
	if models_on_tile.is_empty(): return
	
	var y_offset = 0.0
	for i in range(models_on_tile.size()):
		var model: Node3D = models_on_tile[i]
		if is_instance_valid(model):
			model.position.y = y_offset
			y_offset = _get_node_top_y(model)

func _configure_shadows_for_node(node: Node):
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in node.get_children():
		_configure_shadows_for_node(child)

func _get_all_meshes(node: Node, meshes: Array):
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_get_all_meshes(child, meshes)

func _get_node_top_y(node: Node3D) -> float:
	var meshes = []
	_get_all_meshes(node, meshes)
	if meshes.is_empty(): return node.global_position.y
	var max_y = -INF
	for mi in meshes:
		var aabb = mi.get_aabb()
		var global_xform = mi.global_transform
		var transformed_aabb = global_xform * aabb
		max_y = max(max_y, transformed_aabb.end.y)
	return max_y

func _place_model():
	var grid_pos = Vector2(cursor.position.x, cursor.position.z)
	if is_painting and grid_pos == last_painted_grid_pos:
		return
	if not grid_data.has(grid_pos):
		grid_data[grid_pos] = []
	
	var models_on_tile: Array = grid_data[grid_pos]
	var y_offset = 0.0
	
	if not models_on_tile.is_empty():
		var top_model = models_on_tile.back()
		if is_instance_valid(top_model):
			if not allow_same_asset_stacking and top_model.get_meta("model_path") == selected_model_path:
				print("Placement blocked: Stacking of the same asset is disabled.")
				return
			y_offset = _get_node_top_y(top_model)

	var scene = load(selected_model_path)
	if scene:
		var instance = scene.instantiate()
		instance.position = Vector3(cursor.position.x, y_offset, cursor.position.z)
		instance.scale = Vector3.ONE * selected_model_scale
		instance.rotation_degrees.y = placement_rotation_y
		instance.set_meta("model_path", selected_model_path)
		instance.set_meta("model_scale", selected_model_scale)
		# NEW: Set meta to indicate the asset should snap to the grid by default.
		instance.set_meta("uses_grid_snap", true)
		_configure_shadows_for_node(instance)
		placed_models_container.add_child(instance)
		models_on_tile.append(instance)
		last_painted_grid_pos = grid_pos
		_mark_as_modified() # NEW: Track modification.

# MODIFIED: Saves the new "uses_grid_snap" meta tag.
func _save_scene(scene_name: String):
	var level_data_array = []
	for grid_pos in grid_data:
		var models_on_tile: Array = grid_data[grid_pos]
		for node in models_on_tile:
			if is_instance_valid(node):
				level_data_array.append({
					"path": node.get_meta("model_path"),
					"pos_x": node.position.x, "pos_y": node.position.y, "pos_z": node.position.z,
					"roty": node.rotation_degrees.y,
					"scale": node.get_meta("model_scale", model_scale),
					# NEW: Save the grid snap preference for the instance.
					"uses_grid_snap": node.get_meta("uses_grid_snap", true)
				})
	var sun_settings_data = {
		"pos_x": sun_light.position.x, "pos_y": sun_light.position.y, "pos_z": sun_light.position.z,
		"rot_x": sun_light.rotation_degrees.x, "rot_y": sun_light.rotation_degrees.y, "rot_z": sun_light.rotation_degrees.z,
		"energy": sun_light.light_energy
	}
	var full_save_data = {"level_data": level_data_array, "sun_settings": sun_settings_data}
	var save_path = save_load_manager.SAVE_DIR.path_join(scene_name + ".json")
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(full_save_data, "\t"))
	file.close()
	
	# NEW: After saving, update the state and UI.
	current_scene_name = scene_name
	is_modified = false
	_update_status_label()

# MODIFIED: Loads the new "uses_grid_snap" meta tag.
func _load_scene(scene_name: String):
	var save_path = save_load_manager.SAVE_DIR.path_join(scene_name + ".json")
	if not FileAccess.file_exists(save_path): 
		printerr("Save file not found: ", save_path)
		return
	var file = FileAccess.open(save_path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	for child in placed_models_container.get_children():
		child.queue_free()
	grid_data.clear()
	if typeof(data) == TYPE_DICTIONARY and data.has("level_data"):
		var level_data_to_load = data["level_data"]
		if data.has("sun_settings"):
			var sun_data = data["sun_settings"]
			sun_light.position = Vector3(sun_data.get("pos_x", 0), sun_data.get("pos_y", 0), sun_data.get("pos_z", 0))
			sun_light.rotation_degrees = Vector3(sun_data.get("rot_x", -50), sun_data.get("rot_y", -30), sun_data.get("rot_z", 0))
			sun_light.light_energy = sun_data.get("energy", 0.1)
		for item in level_data_to_load:
			var scene = load(item["path"])
			if scene:
				var instance = scene.instantiate()
				instance.position = Vector3(item["pos_x"], item["pos_y"], item["pos_z"])
				var loaded_scale = item.get("scale", model_scale)
				instance.scale = Vector3.ONE * loaded_scale
				instance.rotation_degrees.y = item.get("roty", 0.0)
				instance.set_meta("model_path", item["path"])
				instance.set_meta("model_scale", loaded_scale)
				# NEW: Load the grid snap preference for the instance.
				instance.set_meta("uses_grid_snap", item.get("uses_grid_snap", true))
				_configure_shadows_for_node(instance)
				placed_models_container.add_child(instance)
				var grid_pos = _get_grid_pos_for_instance(instance)
				if not grid_data.has(grid_pos):
					grid_data[grid_pos] = []
				grid_data[grid_pos].append(instance)
	else:
		printerr("Failed to load scene: Invalid save file format.")
		return
	for grid_pos in grid_data:
		grid_data[grid_pos].sort_custom(func(a, b): return a.position.y < b.position.y)
		
	# NEW: After loading, update the state and UI.
	current_scene_name = scene_name
	is_modified = false
	_update_status_label()
	_deselect_instance()
	_deselect_model()
	print("Loaded successfully!")
