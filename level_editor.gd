extends Node3D

# --- Config Variables ---
var models_folder := "res://models"
var tile_x := 2.0
var tile_z := 2.0
var model_scale := 1.0

# --- State ---
var selected_model_path := ""
var selected_model_scale := 1.0
# Store tile size for placing new assets as an integer vector.
var selected_model_tile_size := Vector2i(1, 1)
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

# State variables for new camera modes
var is_demo_camera_active := false
var is_follow_car_mode_active := false # True when button is pressed, waiting for click
var is_following_car := false # True after a car has been clicked

# Settings State
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
@onready var btn_spawn_car: Button = %ButtonSpawnCar 
@onready var btn_demo_camera: Button = %ButtonDemoCamera
@onready var btn_follow_car: Button = %ButtonFollowCar

# --- Materials ---
var ghost_material: StandardMaterial3D
var selection_material: StandardMaterial3D

# --- Custom Modules ---
var road_builder
var skybox
var terrain_generator
var track_generator
var track_cars

func _ready():
	_load_config()
	_setup_materials()
	
	road_builder = load("res://road_builder.gd").new()
	road_builder.initialize(self, placed_models_container, grid_data)
	
	track_generator = load("res://track_generator.gd").new()
	add_child(track_generator)
	track_generator.initialize(self)
	
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
	# Initialize cursor to the default 1x1 tile size.
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
	
	btn_spawn_car.pressed.connect(_on_spawn_car_button_pressed)
	track_generator.track_regenerated.connect(_update_status_label)

	btn_demo_camera.toggled.connect(_on_demo_camera_toggled)
	btn_follow_car.toggled.connect(_on_follow_car_toggled)

func _on_model_selected(data: Dictionary):
	if is_road_builder_enabled:
		_on_road_builder_toggled()
		
	_deselect_instance()
	selected_model_path = data.get("path", "")
	selected_model_scale = data.get("scale", 1.0)
	# Store the tile size from the asset selector, with a Vector2i default.
	selected_model_tile_size = data.get("tile_size", Vector2i(1, 1))
	_create_ghost(selected_model_path)
	# Update the cursor to reflect the new asset's size immediately.
	_update_cursor(get_viewport().get_mouse_position())

func _deselect_model():
	selected_model_path = ""
	# Reset the tile size to a 1x1 Vector2i when deselecting.
	selected_model_tile_size = Vector2i(1, 1)
	if is_instance_valid(ghost_instance):
		ghost_instance.queue_free()
		ghost_instance = null
	_deselect_instance()
	asset_selector.clear_selection()
	# Update the cursor to reset its size back to 1x1.
	_update_cursor(get_viewport().get_mouse_position())

func _create_ghost(path: String):
	if is_instance_valid(ghost_instance):
		ghost_instance.queue_free()
	var scene = load(path)
	if scene:
		ghost_instance = scene.instantiate()
		cursor.add_child(ghost_instance)
		ghost_instance.scale = Vector3.ONE * selected_model_scale
		ghost_instance.rotation_degrees.y = placement_rotation_y
		# The ghost is a child of the cursor, which is centered.
		# The ghost itself should be at the local origin of the cursor.
		ghost_instance.position = Vector3.ZERO
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
		# Reset placement tile size to a 1x1 Vector2i when selecting an existing instance.
		selected_model_tile_size = Vector2i(1, 1)
		if is_instance_valid(ghost_instance):
			ghost_instance.queue_free()
			ghost_instance = null
		asset_selector.clear_selection()
	selected_instance = instance
	_apply_selection_material(selected_instance)
	
	# --- MODIFIED LINE ---
	# Use the new, robust function to get the correct grid key for the properties panel.
	var grid_pos = _get_grid_key_for_instance(selected_instance)
	var models_on_tile = grid_data.get(grid_pos,[])
	properties_panel.update_fields(selected_instance, models_on_tile, grid_pos)
	
	# --- MODIFIED SECTION ---
	# Update the cursor to match the size and position of the selected instance immediately.
	# This prevents the cursor from jumping on the first drag motion.
	_update_cursor(get_viewport().get_mouse_position())

func _deselect_instance():
	if is_instance_valid(selected_instance):
		_clear_material_overlay(selected_instance)
		selected_instance = null
		properties_panel.clear_and_hide()
		# --- MODIFIED SECTION ---
		# Update the cursor to reset its size and follow the mouse again.
		_update_cursor(get_viewport().get_mouse_position())

# ==========================================
# BOUNDS CHECKING
# ==========================================
func _is_within_terrain_bounds(pos: Vector2) -> bool:
	var min_x = - (terrain_width / 2.0) * tile_x
	var max_x = (terrain_width / 2.0 - 1) * tile_x
	var min_z = - (terrain_depth / 2.0) * tile_z
	var max_z = (terrain_depth / 2.0 - 1) * tile_z
	
	return pos.x >= min_x - 0.01 and pos.x <= max_x + 0.01 and pos.y >= min_z - 0.01 and pos.y <= max_z + 0.01

# --- NEW HELPER FUNCTION ---
# Calculates the correct grid data key for an instance, accounting for multi-tile offsets.
# This is crucial for correctly finding and moving multi-tile assets in the grid_data dictionary.
func _get_grid_key_for_instance(instance: Node3D) -> Vector2:
	if not is_instance_valid(instance):
		return Vector2.INF

	# The asset's tile size is needed to determine the correct grid snapping logic.
	var asset_size: Vector2i = instance.get_meta("tile_size", Vector2i(1, 1))

	# Calculate the offset used for centering.
	# If size is odd (1, 3), offset is 0. Asset is centered on a tile.
	# If size is even (2, 4), offset is half a tile. Asset is centered between tiles.
	var offset_x = (tile_x / 2.0) if asset_size.x % 2 == 0 else 0
	var offset_z = (tile_z / 2.0) if asset_size.y % 2 == 0 else 0

	# To snap the instance's current position to its correct grid center,
	# we apply the same logic as when placing it with the mouse.
	var adjusted_x = instance.position.x - offset_x
	var adjusted_z = instance.position.z - offset_z

	var sn_x = round(adjusted_x / tile_x) * tile_x
	var sn_z = round(adjusted_z / tile_z) * tile_z

	# The final key is the snapped position plus the offset.
	return Vector2(sn_x + offset_x, sn_z + offset_z)

func _get_grid_pos_from_mouse(mouse_pos: Vector2) -> Vector2:
	var origin = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	if dir.y >= 0: return Vector2.INF
	var t = -origin.y / dir.y
	var intersection = origin + dir * t
	
	# Determine the size of the asset currently being handled.
	var asset_size = selected_model_tile_size
	if is_instance_valid(selected_instance):
		# Use a Vector2i as the default for get_meta.
		asset_size = selected_instance.get_meta("tile_size", Vector2i(1, 1))

	# Calculate the offset to center the asset on the grid cells.
	# If size is odd (1, 3, 5), offset is 0.
	# If size is even (2, 4, 6), offset is half a tile, so it centers between tiles.
	var offset_x = (tile_x / 2.0) if asset_size.x % 2 == 0 else 0
	var offset_z = (tile_z / 2.0) if asset_size.y % 2 == 0 else 0
	
	# Apply the offset before rounding to snap the center correctly.
	var adjusted_x = intersection.x - offset_x
	var adjusted_z = intersection.z - offset_z
	
	# Snap to the grid.
	var sn_x = round(adjusted_x / tile_x) * tile_x
	var sn_z = round(adjusted_z / tile_z) * tile_z
	
	# Return the final position, which is the center of the multi-tile area.
	return Vector2(sn_x + offset_x, sn_z + offset_z)

# --- Modified Helper Function ---
# Finds the topmost instance at a given mouse position, accounting for multi-tile assets.
# This is a robust, brute-force check that iterates through all placed assets.
func _get_instance_at_mouse_pos(mouse_pos: Vector2) -> Node3D:
	# 1. Get the 3D world position on the ground plane from the mouse position.
	var origin = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	if dir.y >= 0: return null
	var t = -origin.y / dir.y
	var world_pos_3d = origin + dir * t
	var world_pos_2d = Vector2(world_pos_3d.x, world_pos_3d.z)

	var hits = []

	# 2. Iterate through all grid positions that contain models. This is more robust
	# than a spatial search and is acceptable for a mouse click event.
	for instance_center_pos in grid_data:
		var models_on_tile: Array = grid_data[instance_center_pos]
		if models_on_tile.is_empty(): continue

		# 3. We only need to check the top model at this position for selection.
		var instance: Node3D = models_on_tile.back()
		if not is_instance_valid(instance): continue

		# 4. Calculate the world-space bounding box of the instance.
		var instance_size: Vector2i = instance.get_meta("tile_size", Vector2i(1, 1))
		
		var half_width = (instance_size.x * tile_x) / 2.0
		var half_depth = (instance_size.y * tile_z) / 2.0
		
		var bounds = Rect2(
			instance_center_pos.x - half_width,
			instance_center_pos.y - half_depth,
			instance_size.x * tile_x,
			instance_size.y * tile_z
		)

		# 5. Check if the mouse click's world position is inside this bounding box.
		if bounds.has_point(world_pos_2d):
			# 6. Add the instance to our list of hits.
			hits.append(instance)

	# 7. If there were no hits, return null.
	if hits.is_empty():
		return null
	
	# 8. If there was one hit, return it.
	if hits.size() == 1:
		return hits[0]

	# 9. If there were multiple hits (e.g., overlapping assets), find the one with the highest Y position.
	var topmost_instance = hits[0]
	for i in range(1, hits.size()):
		if hits[i].position.y > topmost_instance.position.y:
			topmost_instance = hits[i]
	
	return topmost_instance
# --- End Modified Helper Function ---

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
		grid_pos_to_update = _get_grid_key_for_instance(instance_to_delete)
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
# MARKER & MISC HELPERS
# ==========================================

# Creates a temporary visual marker above a car when selected for follow mode.
func _create_selection_marker(target: Node3D):
	# Create the marker mesh
	var marker = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.6
	marker.mesh = mesh
	
	# Create a bright, unshaded material that can be faded out
	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 1.0, 0.0, 0.8) # Yellow
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # Make it visible in all lighting
	marker.material_override = material
	
	# Position the marker above the car's origin
	marker.position = Vector3(0, 1.5, 0)
	
	# Add the marker to the car so it moves with it
	target.add_child(marker)
	
	# Create a tween to handle the fade-out and cleanup
	var tween = create_tween()
	# Wait for 2 seconds before starting the fade
	tween.tween_interval(2.0)
	# Animate the alpha component of the material's color to 0 over 1 second
	tween.tween_property(material, "albedo_color:a", 0.0, 1.0)
	# When the tween is finished, call queue_free() on the marker to remove it
	tween.tween_callback(marker.queue_free)

# ==========================================
# UI CALLBACKS
# ==========================================
func _on_spawn_car_button_pressed():
	# First, check if the cursor is visible (i.e., within the terrain bounds).
	if not cursor.visible:
		status_label.text = "Cannot spawn car: Cursor is outside terrain bounds."
		return

	var grid_pos = Vector2(cursor.position.x, cursor.position.z)
	
	# Use the road_builder to verify that the cursor is over a road tile.
	if road_builder.is_road_at(grid_pos):
		# If it's a road, tell the track_cars module to spawn a car at the cursor's 3D position.
		var success = track_cars.spawn_car(cursor.position)
		if success:
			# If spawning was successful, update the status bar to reflect the new car count.
			_update_status_label()
		else:
			# Provide feedback if spawning failed (e.g., another car was too close).
			status_label.text = "Cannot spawn car: Another car is too close."
	else:
		# Provide feedback if the cursor is not on a road.
		status_label.text = "Cannot spawn car: Cursor is not on a road."

func _on_demo_camera_toggled(button_pressed: bool):
	if button_pressed:
		# Turn on demo mode
		is_demo_camera_active = true
		# If follow car mode is active, turn it off
		if btn_follow_car.button_pressed:
			btn_follow_car.button_pressed = false
		
		camera_pivot.start_demo_mode()
		status_label.text = "Demo Camera Active"
	else:
		# Turn off demo mode
		is_demo_camera_active = false
		camera_pivot.stop_automated_modes()
		_update_status_label() # Restore original status label

func _on_follow_car_toggled(button_pressed: bool):
	if button_pressed:
		# Enter mode where we wait for user to click a car
		is_follow_car_mode_active = true
		is_following_car = false # Reset this flag
		# If demo mode is active, turn it off
		if btn_demo_camera.button_pressed:
			btn_demo_camera.button_pressed = false
			
		status_label.text = "Follow Car Mode: Click on a car to follow."
	else:
		# Exit follow car mode completely
		_stop_follow_mode()

func _stop_follow_mode():
	is_follow_car_mode_active = false
	is_following_car = false
	if btn_follow_car.button_pressed:
		btn_follow_car.button_pressed = false # Ensure button state is synced
	camera_pivot.stop_automated_modes()
	_update_status_label()

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
	# Don't update the status if a special camera mode is active
	if is_demo_camera_active or is_follow_car_mode_active or is_following_car:
		return
		
	var file_text = current_scene_name if not current_scene_name.is_empty() else "Untitled"
	var modified_star = " *" if is_modified else ""
	
	var light_count = 0
	# Ensure the track_generator is valid before accessing its properties.
	if is_instance_valid(track_generator):
		light_count = track_generator.intersections.size()
		
	var car_count = 0
	# Ensure the track_cars module is valid.
	if is_instance_valid(track_cars):
		car_count = track_cars.active_vehicles.size()
		
	var stats_text = " | Lights: %d | Cars: %d" % [light_count, car_count]
	
	# Combine the file info with the new stats and set the label's text.
	status_label.text = file_text + modified_star + stats_text

# ==========================================
# PROPERTIES PANEL HANDLERS
# ==========================================
func _on_properties_position_changed(new_pos: Vector3):
	if not is_instance_valid(selected_instance): return
	
	# --- MODIFIED SECTION ---
	# Temporarily update the instance's position to calculate its new grid key
	# for the bounds check, then revert it.
	var old_pos = selected_instance.position
	selected_instance.position = new_pos
	var new_grid_pos = _get_grid_key_for_instance(selected_instance)
	selected_instance.position = old_pos
	# --- END MODIFIED SECTION ---
	
	if not _is_within_terrain_bounds(new_grid_pos):
		var old_grid_pos = _get_grid_key_for_instance(selected_instance)
		properties_panel.update_fields(selected_instance, grid_data.get(old_grid_pos,[]), old_grid_pos)
		return
	
	var old_grid_pos = _get_grid_key_for_instance(selected_instance)
	selected_instance.position = new_pos
	selected_instance.set_meta("uses_grid_snap", false)
	_update_grid_data_for_moved_instance(selected_instance, old_grid_pos)
	_mark_as_modified()

func _on_properties_scale_changed(new_scale: float):
	if not is_instance_valid(selected_instance): return
	
	selected_instance.scale = Vector3.ONE * new_scale
	selected_instance.set_meta("model_scale", new_scale)
	
	# --- MODIFIED LINE ---
	var grid_pos = _get_grid_key_for_instance(selected_instance)
	GridUtils.recalculate_stack_y_positions(grid_pos, grid_data)
	_mark_as_modified()

func _on_properties_order_changed(direction: int):
	if not is_instance_valid(selected_instance): return
	
	# --- MODIFIED LINE ---
	var grid_pos = _get_grid_key_for_instance(selected_instance)
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
		# --- MODIFIED LINE ---
		var grid_pos = _get_grid_key_for_instance(selected_instance)
		selected_instance.position.x = grid_pos.x
		selected_instance.position.z = grid_pos.y
		
	_mark_as_modified()

# ==========================================
# INPUT & CAMERA CONTROLS
# ==========================================

func _handle_right_click_delete(mouse_pos: Vector2) -> bool:
	# Check for valid deletion mode *before* updating the cursor.
	# This prevents the cursor from moving when right-click is used for other actions (like camera rotation).
	var is_asset_selected = not selected_model_path.is_empty()
	if not is_asset_selected and not is_road_builder_enabled:
		return false

	var grid_pos = _get_grid_pos_from_mouse(mouse_pos)
	
	if grid_pos == Vector2.INF or not _is_within_terrain_bounds(grid_pos):
		return false
	
	# The cursor is now updated only when a right-click delete is possible.
	_update_cursor(mouse_pos)

	if not grid_data.has(grid_pos) or grid_data[grid_pos].is_empty():
		return false

	var models_on_tile: Array = grid_data[grid_pos]
	var instance_to_delete: Node3D = null
	var was_road = false

	if is_asset_selected:
		var top_model = models_on_tile.back()
		if is_instance_valid(top_model) and top_model.get_meta("model_path") == selected_model_path:
			instance_to_delete = top_model
			was_road = top_model.get_meta("is_road", false)
		else:
			return false
			
	else: # This block is only reached if is_road_builder_enabled is true due to the check at the top.
		for model in models_on_tile:
			if is_instance_valid(model) and model.get_meta("is_road", false):
				instance_to_delete = model
				was_road = true
				break

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
	if is_demo_camera_active:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			btn_demo_camera.button_pressed = false # This will trigger the toggled signal
		return # Block all other input during demo mode

	var mouse_pos = get_viewport().get_mouse_position()
	
	if asset_selector.get_global_rect().has_point(mouse_pos) or \
	(sun_settings.visible and sun_settings.get_global_rect().has_point(mouse_pos)) or \
	(save_load_manager.visible and save_load_manager.get_global_rect().has_point(mouse_pos)) or \
	(settings_dialog.visible and settings_dialog.get_global_rect().has_point(mouse_pos)) or \
	(properties_panel.visible and properties_panel.get_global_rect().has_point(mouse_pos)):
		return

	if camera_pivot.has_method("handle_input") and camera_pivot.handle_input(event):
		get_viewport().set_input_as_handled()

		if is_following_car:
			return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if is_follow_car_mode_active or is_following_car:
				_stop_follow_mode()
			else:
				_deselect_model() # Original escape functionality
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
				if is_follow_car_mode_active and not is_following_car:
					var space_state = get_world_3d().direct_space_state
					var origin = camera.project_ray_origin(mouse_pos)
					var end = origin + camera.project_ray_normal(mouse_pos) * 1000.0
					var query = PhysicsRayQueryParameters3D.create(origin, end)
					query.collide_with_areas = false
					query.collide_with_bodies = true
					var result = space_state.intersect_ray(query)
					
					if result and result.collider.has_meta("is_car"):
						var car_node = result.collider
						is_following_car = true
						is_follow_car_mode_active = false # We've selected a car, so we're no longer "waiting"
						camera_pivot.start_follow_mode(car_node)
						_create_selection_marker(car_node)
						status_label.text = "Following Car. Use right-mouse to orbit. Press ESC to stop."
						get_viewport().set_input_as_handled()
					else:
						# If user clicks on empty space, do nothing, just wait for a car click
						status_label.text = "No car found at click position. Try again."
					return # Prevent other click logic from running
				
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
					var instance_to_select = _get_instance_at_mouse_pos(mouse_pos)
					
					if is_instance_valid(instance_to_select):
						_select_instance(instance_to_select)
						is_dragging_instance = true
						# --- MODIFIED LINE ---
						# Use the new function to get the correct original grid position.
						# This is the key to fixing the cloning bug on save.
						original_drag_grid_pos = _get_grid_key_for_instance(selected_instance)
					else:
						_deselect_instance()
			else:
				if is_dragging_instance and is_instance_valid(selected_instance):
					_update_grid_data_for_moved_instance(selected_instance, original_drag_grid_pos)
					_mark_as_modified()
				is_painting = false
				is_dragging_instance = false

func _update_cursor(mouse_pos: Vector2):
	var grid_pos: Vector2
	var asset_size: Vector2i

	# --- MODIFIED SECTION ---
	# This logic now handles two distinct modes: manipulating a selected asset
	# or placing a new one.
	if is_instance_valid(selected_instance) and selected_model_path.is_empty():
		# Mode 1: An asset is selected. The cursor should lock to its position and size.
		# When dragging, the instance's position is updated, and this makes the cursor follow.
		grid_pos = _get_grid_key_for_instance(selected_instance)
		asset_size = selected_instance.get_meta("tile_size", Vector2i(1, 1))
	else:
		# Mode 2: Placing a new asset or nothing is selected. The cursor follows the mouse.
		grid_pos = _get_grid_pos_from_mouse(mouse_pos)
		asset_size = selected_model_tile_size # Defaults to 1x1 if nothing is selected.
	# --- END MODIFIED SECTION ---
		
	if grid_pos == Vector2.INF or not _is_within_terrain_bounds(grid_pos):
		cursor.visible = false
		return
		
	cursor.visible = true
	cursor.position = Vector3(grid_pos.x, 0, grid_pos.y)
	
	# Update the cursor's visual size based on the asset being placed or selected.
	if cursor.mesh is BoxMesh:
		var new_size = Vector3(asset_size.x * tile_x, 0.1, asset_size.y * tile_z)
		# Check if size changed to avoid unnecessary mesh updates.
		if not cursor.mesh.size.is_equal_approx(new_size):
			cursor.mesh.size = new_size
	
	if is_instance_valid(ghost_instance) or is_dragging_instance:
		var y_offset = 0.0
		
		# Note: Stacking logic for multi-tile assets is complex.
		# This implementation checks for stacks only at the center point.
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
	
	# Use the new grid position logic for dragging as well.
	if selected_instance.get_meta("uses_grid_snap", true):
		var grid_pos = _get_grid_pos_from_mouse(mouse_pos)
		if _is_within_terrain_bounds(grid_pos):
			selected_instance.position.x = grid_pos.x
			selected_instance.position.z = grid_pos.y
	else:
		# Free-form dragging remains the same.
		var origin = camera.project_ray_origin(mouse_pos)
		var dir = camera.project_ray_normal(mouse_pos)
		if dir.y >= 0: return
		var t = -origin.y / dir.y
		var intersection = origin + dir * t
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
			
	# --- MODIFIED LINE ---
	# Use the new function to calculate the correct new grid position key.
	var new_grid_pos = _get_grid_key_for_instance(instance)
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
# --- Modified Function ---
# Updated to correctly cycle through all assets under the cursor, not just those
# sharing the same center point.
func _cycle_selection_on_tile():
	# Get the cursor's current center position in world space.
	var cursor_world_pos = Vector2(cursor.position.x, cursor.position.z)
	
	var instances_under_cursor = []

	# Brute-force check of all assets to see if their footprint contains the cursor's center.
	for instance_center_pos in grid_data:
		var models_on_tile: Array = grid_data[instance_center_pos]
		for instance in models_on_tile:
			if not is_instance_valid(instance): continue

			var instance_size: Vector2i = instance.get_meta("tile_size", Vector2i(1, 1))
			var half_width = (instance_size.x * tile_x) / 2.0
			var half_depth = (instance_size.y * tile_z) / 2.0
			
			var bounds = Rect2(
				instance_center_pos.x - half_width,
				instance_center_pos.y - half_depth,
				instance_size.x * tile_x,
				instance_size.y * tile_z
			)

			if bounds.has_point(cursor_world_pos):
				instances_under_cursor.append(instance)

	if instances_under_cursor.is_empty():
		_deselect_instance()
		return
		
	# Sort the found instances by their Y position (bottom to top).
	instances_under_cursor.sort_custom(func(a, b): return a.position.y < b.position.y)
		
	var current_selection_index = -1
	if is_instance_valid(selected_instance) and instances_under_cursor.has(selected_instance):
		current_selection_index = instances_under_cursor.find(selected_instance)
		
	# Get the next index, wrapping around.
	var next_index = (current_selection_index + 1) % instances_under_cursor.size()
	_select_instance(instances_under_cursor[next_index])
# --- End Modified Function ---

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

	# For multi-tile assets, we still use the center point as the key for grid_data.
	# Stacking logic will need to be re-evaluated if multi-tile assets can stack.
	# For now, we assume they are placed on the ground or on top of a stack at their center point.
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
		# The instance is placed at the cursor's position, which is already centered.
		instance.position = Vector3(cursor.position.x, y_offset, cursor.position.z)
		instance.scale = Vector3.ONE * selected_model_scale
		instance.rotation_degrees.y = placement_rotation_y
		instance.set_meta("model_path", selected_model_path)
		instance.set_meta("model_scale", selected_model_scale)
		instance.set_meta("uses_grid_snap", true)
		# Save the integer-based tile size to the instance's metadata.
		instance.set_meta("tile_size", selected_model_tile_size)
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
