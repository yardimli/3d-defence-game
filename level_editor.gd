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
var current_scene_name: String = ""
var is_modified := false
var is_road_builder_enabled := false

# NEW: Settings State
var cloud_density := 0.5
var cloud_speed := 0.02
var terrain_width := 100
var terrain_depth := 100
var tree_density := 2.0 # percentage

# --- Nodes ---
@onready var placed_models_container: Node3D = %PlacedModelsContainer
@onready var cursor: MeshInstance3D = %Cursor
@onready var camera_pivot: Node3D = %CameraPivot
@onready var camera: Camera3D = %Camera3D
@onready var sun_light: DirectionalLight3D = %SunLight
@onready var asset_selector: PanelContainer = %AssetSelector
@onready var sun_settings: Window = %SunSettings
@onready var save_load_manager: Window = %SaveLoadManager
@onready var btn_save_as: Button = %ButtonSaveAs
@onready var btn_save: Button = %ButtonSave
@onready var btn_load: Button = %ButtonLoad
@onready var btn_rotate: Button = %ButtonRotate
@onready var btn_delete: Button = %ButtonDelete
@onready var btn_sun: Button = %ButtonSun
@onready var btn_settings: Button = %ButtonSettings
@onready var settings_dialog: Window = %SettingsDialog
@onready var btn_properties: Button = %ButtonProperties
@onready var properties_panel: PanelContainer = %PropertiesPanel
@onready var btn_cycle_selection: Button = %ButtonCycleSelection
@onready var status_label: Label = %StatusLabel
@onready var btn_road_builder: Button = %ButtonRoadBuilder
@onready var btn_spawn_car: Button = %ButtonSpawnCar # NEW: Reference to the Spawn Car button

# --- Materials ---
var ghost_material: StandardMaterial3D
var selection_material: StandardMaterial3D

# --- Custom Modules ---
var road_builder
var skybox
var terrain_generator
var track_generator
var track_cars # NEW: Reference to the track cars module

func _ready():
	_load_config()
	_setup_materials()
	
	road_builder = load("res://road_builder.gd").new()
	road_builder.initialize(self, placed_models_container, grid_data)
	
	track_generator = load("res://track_generator.gd").new()
	add_child(track_generator)
	track_generator.initialize(self)
	
	# NEW: Initialize track cars module
	track_cars = load("res://track_cars.gd").new()
	add_child(track_cars)
	track_cars.initialize(self, track_generator, camera)
	
	skybox = load("res://skybox.gd").new()
	add_child(skybox)
	skybox.set_cloud_density(cloud_density)
	skybox.set_cloud_speed(cloud_speed)
	
	terrain_generator = load("res://terrain_generator.gd").new()
	add_child(terrain_generator)
	terrain_generator.set_settings(terrain_width, terrain_depth, tree_density / 100.0)
	terrain_generator.initialize(tile_x, tile_z, self)
	
	_connect_ui_signals()
	
	var mesh = BoxMesh.new()                
	mesh.size = Vector3(tile_x, 0.1, tile_z) 
	cursor.mesh = mesh                      

	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.5, 0.0, 0.5) 
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA 
	cursor.material_override = material	
	
	_update_status_label()

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
		
		if camera_pivot and camera_pivot.has_method("set_config"):
			camera_pivot.set_config(
				float(config.get_value("Camera", "zoom", 10.0)),
				float(config.get_value("Camera", "rotation_x", -45.0)),
				float(config.get_value("Camera", "rotation_y", 45.0))
			)
			
		sun_light.light_energy = float(config.get_value("Sun", "energy", 1.0))
		var sun_rot_x = float(config.get_value("Sun", "rotation_x", -50.0))
		var sun_rot_y = float(config.get_value("Sun", "rotation_y", -30.0))
		sun_light.rotation_degrees = Vector3(sun_rot_x, sun_rot_y, 0)
		
		cloud_density = float(config.get_value("Skybox", "cloud_density", 0.5))
		cloud_speed = float(config.get_value("Skybox", "cloud_speed", 0.02))
		terrain_width = int(config.get_value("Terrain", "width", 100))
		terrain_depth = int(config.get_value("Terrain", "depth", 100))
		tree_density = float(config.get_value("Terrain", "tree_density", 2.0))

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
	btn_save.pressed.connect(_on_save_button_pressed)
	btn_save_as.pressed.connect(_on_save_as_button_pressed)
	btn_load.pressed.connect(save_load_manager.open)
	btn_rotate.pressed.connect(_rotate_placement)
	btn_delete.pressed.connect(_delete_model_at_cursor)
	btn_sun.pressed.connect(_on_sun_config_pressed)
	btn_settings.pressed.connect(_on_settings_button_pressed)
	settings_dialog.setting_changed.connect(_on_setting_changed)
	settings_dialog.preview_settings_changed.connect(_on_preview_settings_changed)
	
	btn_properties.pressed.connect(properties_panel.toggle_visibility)
	btn_cycle_selection.pressed.connect(_cycle_selection_on_tile)
	properties_panel.position_changed.connect(_on_properties_position_changed)
	properties_panel.scale_changed.connect(_on_properties_scale_changed)
	properties_panel.order_changed.connect(_on_properties_order_changed)
	properties_panel.grid_snap_toggled.connect(_on_grid_snap_toggled)
	
	asset_selector.model_selected.connect(_on_model_selected)
	asset_selector.selection_cleared.connect(_deselect_model)
	sun_settings.sun_updated.connect(_on_sun_settings_updated)
	save_load_manager.save_requested.connect(_save_scene)
	save_load_manager.load_requested.connect(_load_scene)
	
	btn_road_builder.pressed.connect(_on_road_builder_toggled)
	road_builder.scene_modified.connect(_mark_as_modified)
	
	# NEW: Connect the Spawn Car button to the track_cars module
	btn_spawn_car.pressed.connect(track_cars.spawn_car)

func _on_model_selected(data: Dictionary):
	if is_road_builder_enabled:
		_on_road_builder_toggled()
		
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
	
	var grid_pos = GridUtils.get_grid_pos(selected_instance.position, tile_x, tile_z)
	var models_on_tile = grid_data.get(grid_pos,[])
	properties_panel.update_fields(selected_instance, models_on_tile, grid_pos)

func _deselect_instance():
	if is_instance_valid(selected_instance):
		_clear_material_overlay(selected_instance)
		selected_instance = null
		properties_panel.clear_and_hide()

# ==========================================
# BOUNDS CHECKING
# ==========================================
func _is_within_terrain_bounds(pos: Vector2) -> bool:
	var min_x = - (terrain_width / 2.0) * tile_x
	var max_x = (terrain_width / 2.0 - 1) * tile_x
	var min_z = - (terrain_depth / 2.0) * tile_z
	var max_z = (terrain_depth / 2.0 - 1) * tile_z
	
	return pos.x >= min_x - 0.01 and pos.x <= max_x + 0.01 and pos.y >= min_z - 0.01 and pos.y <= max_z + 0.01

func _get_grid_pos_from_mouse(mouse_pos: Vector2) -> Vector2:
	var origin = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	if dir.y >= 0: return Vector2.INF
	var t = -origin.y / dir.y
	var intersection = origin + dir * t
	var sn_x = round(intersection.x / tile_x) * tile_x
	var sn_z = round(intersection.z / tile_z) * tile_z
	return Vector2(sn_x, sn_z)

# ==========================================
# PLACEMENT, ROTATION & DELETION
# ==========================================
func _rotate_placement():
	if is_instance_valid(selected_instance):
		if selected_instance.get_meta("is_road", false):
			return
		_mark_as_modified()
		selected_instance.rotation_degrees.y = fmod(selected_instance.rotation_degrees.y + 90.0, 360.0)
		return
	placement_rotation_y = fmod(placement_rotation_y + 90.0, 360.0)
	if is_instance_valid(ghost_instance):
		ghost_instance.rotation_degrees.y = placement_rotation_y

func _delete_model_at_cursor():
	var instance_to_delete = selected_instance
	var grid_pos_to_update = Vector2.INF
	var was_road = false

	if is_instance_valid(instance_to_delete):
		grid_pos_to_update = GridUtils.get_grid_pos(instance_to_delete.position, tile_x, tile_z)
		was_road = instance_to_delete.get_meta("is_road", false)
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
					was_road = model_to_delete.get_meta("is_road", false)
					model_to_delete.queue_free()
				if models_on_tile.is_empty():
					grid_data.erase(grid_pos)
			else:
				grid_data.erase(grid_pos)
	
	if grid_pos_to_update != Vector2.INF:
		if was_road:
			road_builder.on_model_deleted(grid_pos_to_update)
		else:
			GridUtils.recalculate_stack_y_positions(grid_pos_to_update, grid_data)
			
	_mark_as_modified()

# ==========================================
# UI CALLBACKS
# ==========================================
func _on_road_builder_toggled():
	is_road_builder_enabled = not is_road_builder_enabled
	if is_road_builder_enabled:
		_deselect_model()
		btn_road_builder.modulate = Color(0.4, 1.0, 0.4)
	else:
		btn_road_builder.modulate = Color(1, 1, 1)

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

func _on_settings_button_pressed():
	var current_settings = {
		"allow_same_asset_stacking": allow_same_asset_stacking,
		"cloud_density": cloud_density,
		"cloud_speed": cloud_speed,
		"terrain_width": terrain_width,
		"terrain_depth": terrain_depth,
		"tree_density": tree_density
	}
	var preview_settings = asset_selector.get_current_preview_settings()
	current_settings.merge(preview_settings)
	
	settings_dialog.open_with_settings(current_settings)

func _on_setting_changed(setting_name: String, new_value: Variant):
	if setting_name == "allow_same_asset_stacking":
		allow_same_asset_stacking = new_value
	elif setting_name == "cloud_density":
		cloud_density = new_value
		if skybox: skybox.set_cloud_density(cloud_density)
	elif setting_name == "cloud_speed":
		cloud_speed = new_value
		if skybox: skybox.set_cloud_speed(cloud_speed)
	elif setting_name == "terrain_width":
		terrain_width = new_value
		if terrain_generator: terrain_generator.set_settings(terrain_width, terrain_depth, tree_density / 100.0)
	elif setting_name == "terrain_depth":
		terrain_depth = new_value
		if terrain_generator: terrain_generator.set_settings(terrain_width, terrain_depth, tree_density / 100.0)
	elif setting_name == "tree_density":
		tree_density = new_value
		if terrain_generator: terrain_generator.set_settings(terrain_width, terrain_depth, tree_density / 100.0)

func _on_preview_settings_changed(settings: Dictionary):
	asset_selector.apply_preview_overrides(settings)

func _on_save_button_pressed():
	if current_scene_name.is_empty():
		save_load_manager.open()
	else:
		_save_scene(current_scene_name)

func _on_save_as_button_pressed():
	save_load_manager.open()

func _mark_as_modified():
	if not is_modified:
		is_modified = true
		_update_status_label()

func _update_status_label():
	var file_text = current_scene_name if not current_scene_name.is_empty() else "Untitled"
	var modified_star = " *" if is_modified else ""
	status_label.text = file_text + modified_star

# ==========================================
# PROPERTIES PANEL HANDLERS
# ==========================================
func _on_properties_position_changed(new_pos: Vector3):
	if not is_instance_valid(selected_instance): return
	
	var new_grid_pos = GridUtils.get_grid_pos(new_pos, tile_x, tile_z)
	if not _is_within_terrain_bounds(new_grid_pos):
		var old_grid_pos = GridUtils.get_grid_pos(selected_instance.position, tile_x, tile_z)
		properties_panel.update_fields(selected_instance, grid_data.get(old_grid_pos,[]), old_grid_pos)
		return
	
	var old_grid_pos = GridUtils.get_grid_pos(selected_instance.position, tile_x, tile_z)
	selected_instance.position = new_pos
	selected_instance.set_meta("uses_grid_snap", false)
	_update_grid_data_for_moved_instance(selected_instance, old_grid_pos)
	_mark_as_modified()

func _on_properties_scale_changed(new_scale: float):
	if not is_instance_valid(selected_instance): return
	
	selected_instance.scale = Vector3.ONE * new_scale
	selected_instance.set_meta("model_scale", new_scale)
	
	var grid_pos = GridUtils.get_grid_pos(selected_instance.position, tile_x, tile_z)
	GridUtils.recalculate_stack_y_positions(grid_pos, grid_data)
	_mark_as_modified()

func _on_properties_order_changed(direction: int):
	if not is_instance_valid(selected_instance): return
	
	var grid_pos = GridUtils.get_grid_pos(selected_instance.position, tile_x, tile_z)
	var models_on_tile: Array = grid_data.get(grid_pos,[])
	
	if models_on_tile.size() > 1:
		var current_index = models_on_tile.find(selected_instance)
		var new_index = current_index + direction
		
		if new_index >= 0 and new_index < models_on_tile.size():
			models_on_tile.remove_at(current_index)
			models_on_tile.insert(new_index, selected_instance)
			GridUtils.recalculate_stack_y_positions(grid_pos, grid_data)
			properties_panel.update_fields(selected_instance, models_on_tile, grid_pos)
	_mark_as_modified()

func _on_grid_snap_toggled(should_snap: bool):
	if not is_instance_valid(selected_instance): return
	
	selected_instance.set_meta("uses_grid_snap", should_snap)
	
	if should_snap:
		var grid_pos = GridUtils.get_grid_pos(selected_instance.position, tile_x, tile_z)
		selected_instance.position.x = grid_pos.x
		selected_instance.position.z = grid_pos.y
		
	_mark_as_modified()

# ==========================================
# INPUT & CAMERA CONTROLS
# ==========================================

func _handle_right_click_delete(mouse_pos: Vector2) -> bool:
	var grid_pos = _get_grid_pos_from_mouse(mouse_pos)
	
	if grid_pos == Vector2.INF or not _is_within_terrain_bounds(grid_pos):
		return false
		
	_update_cursor(mouse_pos)

	if not grid_data.has(grid_pos) or grid_data[grid_pos].is_empty():
		return false

	var models_on_tile: Array = grid_data[grid_pos]
	var instance_to_delete: Node3D = null
	var was_road = false

	var is_asset_selected = not selected_model_path.is_empty()

	if is_asset_selected:
		var top_model = models_on_tile.back()
		if is_instance_valid(top_model) and top_model.get_meta("model_path") == selected_model_path:
			instance_to_delete = top_model
			was_road = top_model.get_meta("is_road", false)
		else:
			return false
			
	else:
		if is_road_builder_enabled:
			for model in models_on_tile:
				if is_instance_valid(model) and model.get_meta("is_road", false):
					instance_to_delete = model
					was_road = true
					break
		else:
			return false

	if not is_instance_valid(instance_to_delete):
		return false

	if selected_instance == instance_to_delete:
		_deselect_instance()

	models_on_tile.erase(instance_to_delete)
	
	if models_on_tile.is_empty():
		grid_data.erase(grid_pos)
	
	instance_to_delete.queue_free()
	
	if was_road:
		road_builder.on_model_deleted(grid_pos)
	else:
		GridUtils.recalculate_stack_y_positions(grid_pos, grid_data)
		
	_mark_as_modified()
	return true


func _unhandled_input(event):
	var mouse_pos = get_viewport().get_mouse_position()
	
	if asset_selector.get_global_rect().has_point(mouse_pos) or \
	(sun_settings.visible and sun_settings.get_global_rect().has_point(mouse_pos)) or \
	(save_load_manager.visible and save_load_manager.get_global_rect().has_point(mouse_pos)) or \
	(settings_dialog.visible and settings_dialog.get_global_rect().has_point(mouse_pos)) or \
	(properties_panel.visible and properties_panel.get_global_rect().has_point(mouse_pos)):
		return

	if camera_pivot.has_method("handle_input") and camera_pivot.handle_input(event):
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE: _deselect_model()
		if event.keycode == KEY_R: _rotate_placement()
		if event.keycode == KEY_D: _delete_model_at_cursor()
		if event.keycode == KEY_C: _cycle_selection_on_tile()
		if event.is_match(event): get_viewport().set_input_as_handled()
		
	if event is InputEventMouseMotion:
		if selected_model_path != "" or is_dragging_instance or is_road_builder_enabled:
			_update_cursor(mouse_pos)
		if is_painting:
			if is_road_builder_enabled:
				_place_model()
			elif selected_model_path != "" and not Input.is_key_pressed(KEY_SHIFT):
				_place_model()
		elif is_dragging_instance and is_instance_valid(selected_instance):
			_drag_selected_instance()
			
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if _handle_right_click_delete(mouse_pos):
				get_viewport().set_input_as_handled()
				return

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var click_grid_pos = _get_grid_pos_from_mouse(mouse_pos)
				if click_grid_pos == Vector2.INF or not _is_within_terrain_bounds(click_grid_pos):
					_deselect_instance()
					return
					
				if is_road_builder_enabled:
					is_painting = true
					last_painted_grid_pos = Vector2.INF
					_place_model()
				elif selected_model_path != "" and not event.shift_pressed:
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
						original_drag_grid_pos = GridUtils.get_grid_pos(selected_instance.position, tile_x, tile_z)
					else:
						_deselect_instance()
			else:
				if is_dragging_instance and is_instance_valid(selected_instance):
					_update_grid_data_for_moved_instance(selected_instance, original_drag_grid_pos)
					_mark_as_modified()
				is_painting = false
				is_dragging_instance = false

func _update_cursor(mouse_pos: Vector2):
	var grid_pos = _get_grid_pos_from_mouse(mouse_pos)
	if grid_pos == Vector2.INF or not _is_within_terrain_bounds(grid_pos):
		cursor.visible = false
		return
		
	cursor.visible = true
	cursor.position = Vector3(grid_pos.x, 0, grid_pos.y)
	
	if is_instance_valid(ghost_instance) or is_dragging_instance:
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
						y_offset = GridUtils.get_node_top_y(next_model_down)
				else:
					y_offset = GridUtils.get_node_top_y(top_model)
		
		if is_instance_valid(ghost_instance):
			ghost_instance.position.y = y_offset
		elif is_dragging_instance and is_instance_valid(selected_instance):
			selected_instance.position.y = y_offset

func _drag_selected_instance():
	if not is_instance_valid(selected_instance): return
	
	if selected_instance.get_meta("is_road", false):
		is_dragging_instance = false
		return
		
	var mouse_pos = get_viewport().get_mouse_position()
	var origin = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	if dir.y >= 0: return
	var t = -origin.y / dir.y
	var intersection = origin + dir * t

	if selected_instance.get_meta("uses_grid_snap", true):
		var sn_x = round(intersection.x / tile_x) * tile_x
		var sn_z = round(intersection.z / tile_z) * tile_z
		if _is_within_terrain_bounds(Vector2(sn_x, sn_z)):
			selected_instance.position.x = sn_x
			selected_instance.position.z = sn_z
	else:
		if _is_within_terrain_bounds(Vector2(intersection.x, intersection.z)):
			selected_instance.position.x = intersection.x
			selected_instance.position.z = intersection.z

func _update_grid_data_for_moved_instance(instance: Node3D, old_grid_pos: Vector2):
	if not is_instance_valid(instance): return
	
	if grid_data.has(old_grid_pos):
		var old_tile_models: Array = grid_data[old_grid_pos]
		old_tile_models.erase(instance)
		if old_tile_models.is_empty():
			grid_data.erase(old_grid_pos)
		else:
			GridUtils.recalculate_stack_y_positions(old_grid_pos, grid_data)
			
	var new_grid_pos = GridUtils.get_grid_pos(instance.position, tile_x, tile_z)
	if not grid_data.has(new_grid_pos):
		grid_data[new_grid_pos] =[]
	var new_tile_models: Array = grid_data[new_grid_pos]
	new_tile_models.append(instance)
	new_tile_models.sort_custom(func(a, b): return a.position.y < b.position.y)
	
	if is_instance_valid(selected_instance) and selected_instance == instance:
		properties_panel.update_fields(instance, new_tile_models, new_grid_pos)

# ==========================================
# PLACEMENT & SAVE/LOAD
# ==========================================
func _cycle_selection_on_tile():
	var grid_pos = Vector2(cursor.position.x, cursor.position.z)
	var models_on_tile: Array = grid_data.get(grid_pos,[])
	
	if models_on_tile.is_empty():
		_deselect_instance()
		return
		
	var current_selection_index = -1
	if is_instance_valid(selected_instance) and models_on_tile.has(selected_instance):
		current_selection_index = models_on_tile.find(selected_instance)
		
	var next_index = (current_selection_index + 1) % models_on_tile.size()
	_select_instance(models_on_tile[next_index])

func _place_model():
	if not cursor.visible:
		return
		
	var grid_pos = Vector2(cursor.position.x, cursor.position.z)
	if not _is_within_terrain_bounds(grid_pos):
		return
		
	if is_painting and grid_pos == last_painted_grid_pos:
		return

	if is_road_builder_enabled:
		road_builder.place_road(grid_pos)
		last_painted_grid_pos = grid_pos
		return

	if not grid_data.has(grid_pos):
		grid_data[grid_pos] =[]
	
	var models_on_tile: Array = grid_data[grid_pos]
	var y_offset = 0.0
	
	if not models_on_tile.is_empty():
		var top_model = models_on_tile.back()
		if is_instance_valid(top_model):
			if not allow_same_asset_stacking and top_model.get_meta("model_path") == selected_model_path:
				print("Placement blocked: Stacking of the same asset is disabled.")
				return
			y_offset = GridUtils.get_node_top_y(top_model)

	var scene = load(selected_model_path)
	if scene:
		var instance = scene.instantiate()
		instance.position = Vector3(cursor.position.x, y_offset, cursor.position.z)
		instance.scale = Vector3.ONE * selected_model_scale
		instance.rotation_degrees.y = placement_rotation_y
		instance.set_meta("model_path", selected_model_path)
		instance.set_meta("model_scale", selected_model_scale)
		instance.set_meta("uses_grid_snap", true)
		GridUtils.configure_shadows(instance)
		placed_models_container.add_child(instance)
		models_on_tile.append(instance)
		last_painted_grid_pos = grid_pos
		_mark_as_modified()

func _save_scene(scene_name: String):
	LevelSerializer.save_scene(scene_name, grid_data, sun_light, model_scale, save_load_manager.SAVE_DIR)
	current_scene_name = scene_name
	is_modified = false
	_update_status_label()

func _load_scene(scene_name: String):
	var success = LevelSerializer.load_scene(scene_name, grid_data, placed_models_container, sun_light, model_scale, tile_x, tile_z, save_load_manager.SAVE_DIR)
	if success:
		current_scene_name = scene_name
		is_modified = false
		_update_status_label()
		_deselect_instance()
		_deselect_model()
		
		if track_generator:
			track_generator.generate_tracks()
			
		print("Loaded successfully!")
