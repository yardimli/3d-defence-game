class_name LevelSerializer
extends RefCounted

# Extracted save logic
static func save_scene(scene_name: String, grid_data: Dictionary, sun_light: DirectionalLight3D, model_scale: float, save_dir: String):
	var level_data_array =[]
	for grid_pos in grid_data:
		var models_on_tile: Array = grid_data[grid_pos]
		for node in models_on_tile:
			if is_instance_valid(node):
				# --- Modified Section ---
				# Get tile_size meta, providing a Vector2i as the default.
				var tile_size = node.get_meta("tile_size", Vector2i(1, 1))
				level_data_array.append({
					"path": node.get_meta("model_path"),
					"pos_x": node.position.x, "pos_y": node.position.y, "pos_z": node.position.z,
					"roty": node.rotation_degrees.y,
					"scale": node.get_meta("model_scale", model_scale),
					"uses_grid_snap": node.get_meta("uses_grid_snap", true),
					"is_road": node.get_meta("is_road", false),
					# Save the integer tile size components.
					"tile_size_x": tile_size.x,
					"tile_size_z": tile_size.y
				})
				# --- End Modified Section ---
				
	var sun_settings_data = {
		"pos_x": sun_light.position.x, "pos_y": sun_light.position.y, "pos_z": sun_light.position.z,
		"rot_x": sun_light.rotation_degrees.x, "rot_y": sun_light.rotation_degrees.y, "rot_z": sun_light.rotation_degrees.z,
		"energy": sun_light.light_energy
	}
	
	var full_save_data = {"level_data": level_data_array, "sun_settings": sun_settings_data}
	var save_path = save_dir.path_join(scene_name + ".json")
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(full_save_data, "\t"))
	file.close()

# Extracted load logic
static func load_scene(scene_name: String, grid_data: Dictionary, placed_models_container: Node3D, sun_light: DirectionalLight3D, default_model_scale: float, tile_x: float, tile_z: float, save_dir: String) -> bool:
	var save_path = save_dir.path_join(scene_name + ".json")
	if not FileAccess.file_exists(save_path): 
		printerr("Save file not found: ", save_path)
		return false
		
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
				var loaded_scale = item.get("scale", default_model_scale)
				instance.scale = Vector3.ONE * loaded_scale
				instance.rotation_degrees.y = item.get("roty", 0.0)
				instance.set_meta("model_path", item["path"])
				instance.set_meta("model_scale", loaded_scale)
				instance.set_meta("uses_grid_snap", item.get("uses_grid_snap", true))
				instance.set_meta("is_road", item.get("is_road", false))
				# --- Modified Section ---
				# Load tile size, explicitly casting to int to create a Vector2i.
				var loaded_tile_size = Vector2i(int(item.get("tile_size_x", 1)), int(item.get("tile_size_z", 1)))
				instance.set_meta("tile_size", loaded_tile_size)
				# --- End Modified Section ---
				GridUtils.configure_shadows(instance)
				placed_models_container.add_child(instance)
				
				var grid_pos = GridUtils.get_grid_pos(instance.position, tile_x, tile_z)
				if not grid_data.has(grid_pos):
					grid_data[grid_pos] = []
				grid_data[grid_pos].append(instance)
	else:
		printerr("Failed to load scene: Invalid save file format.")
		return false
		
	for grid_pos in grid_data:
		grid_data[grid_pos].sort_custom(func(a, b): return a.position.y < b.position.y)
		
	return true
