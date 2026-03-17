extends PanelContainer

# MODIFIED: Emits a dictionary with path and scale info.
signal model_selected(data: Dictionary)
# Emitted when the selection should be cleared (e.g., right-click).
signal selection_cleared

# --- Config ---
var models_folder := "res://models"

# --- State ---
var preview_buttons := []
var selected_button: Button = null
# NEW: ConfigFile objects to hold root and folder-specific settings.
var root_config := ConfigFile.new()
var folder_config: ConfigFile = null

# --- Node-Referenzen ---
@onready var folder_dropdown: OptionButton = %FolderDropdown
@onready var model_list: VBoxContainer = %ModelList

func _ready():
	# NEW: Load the root config file for fallback values.
	root_config.load("res://config.cfg")
	
	# NEW: Programmatically set the font size for the dropdown to ensure it applies.
	folder_dropdown.add_theme_font_size_override("font_size", 24)
	
	# Connect the dropdown's item_selected signal to the folder change handler.
	folder_dropdown.item_selected.connect(_on_folder_selected)
	# Initial population of the asset list.
	_populate_folder_dropdown()

# Scans the models_folder for subdirectories and adds them to the dropdown.
func _populate_folder_dropdown():
	folder_dropdown.clear()
	
	var dir = DirAccess.open(models_folder)
	if not dir:
		print("ERROR: Models folder not found at: ", models_folder)
		return
		
	dir.list_dir_begin()
	var item = dir.get_next()
	var default_folder_index = -1
	var folder_names = []

	while item != "":
		if dir.current_is_dir() and not item.begins_with("."):
			folder_names.append(item)
		item = dir.get_next()
	
	folder_names.sort()
	
	for i in range(folder_names.size()):
		var folder_name = folder_names[i]
		folder_dropdown.add_item(folder_name)
		if folder_name == "default":
			default_folder_index = i
	
	if folder_dropdown.item_count > 0:
		var index_to_select = 0
		if default_folder_index != -1:
			index_to_select = default_folder_index
		
		folder_dropdown.select(index_to_select)
		_on_folder_selected(index_to_select)

# Handles the selection of a new folder from the dropdown.
func _on_folder_selected(index: int):
	var folder_name = folder_dropdown.get_item_text(index)
	var full_path = models_folder.path_join(folder_name)
	
	# NEW: Attempt to load a config file from the selected subfolder.
	var sub_config_path = full_path.path_join("config.cfg")
	var sub_config = ConfigFile.new()
	if sub_config.load(sub_config_path) == OK:
		folder_config = sub_config
	else:
		folder_config = null # Reset if no config is found.
		
	_populate_model_previews(full_path)

# Clears and creates new model preview buttons for the given folder path.
func _populate_model_previews(path: String):
	# Clear existing buttons and data.
	for child in model_list.get_children():
		child.queue_free()
	preview_buttons.clear()
	selected_button = null
	
	var model_paths = []
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file = dir.get_next()
		while file != "":
			if not dir.current_is_dir() and (file.ends_with(".glb") or file.ends_with(".gltf")):
				model_paths.append(path.path_join(file))
			file = dir.get_next()
	
	model_paths.sort()
	
	if model_paths.is_empty():
		var label = Label.new()
		label.text = "No models found in this folder."
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		model_list.add_child(label)
	else:
		for model_path in model_paths:
			_create_model_preview_button(model_path)

# NEW: Helper function to get the correct scale for a model.
# It checks the folder config first, then the root config, then uses the default scale.
func _get_scale_for_model(model_path: String) -> float:
	var model_filename = model_path.get_file()
	
	# 1. Check for per-model scale in the folder's config.cfg
	if folder_config and folder_config.has_section_key("ModelScales", model_filename):
		return folder_config.get_value("ModelScales", model_filename)

	# 2. Check for per-model scale in the root config.cfg
	if root_config and root_config.has_section_key("ModelScales", model_filename):
		return root_config.get_value("ModelScales", model_filename)
		
	# 3. Use the default scale from the folder's config.cfg
	if folder_config and folder_config.has_section_key("Settings", "model_scale"):
		return folder_config.get_value("Settings", "model_scale")

	# 4. Fallback to the default scale from the root config.cfg
	return root_config.get_value("Settings", "model_scale", 1.0)

# NEW: Helper function to get camera settings for the preview.
# It checks the folder config first, then the root config, then uses default values.
func _get_camera_settings() -> Dictionary:
	var default_pos = Vector3(0, 1.0, 2.5)
	var default_look_at = Vector3(0, 0, 0)

	# 1. Check for settings in the folder's config.cfg
	if folder_config and folder_config.has_section("AssetPreviewCamera"):
		return {
			"position": folder_config.get_value("AssetPreviewCamera", "position", default_pos),
			"look_at": folder_config.get_value("AssetPreviewCamera", "look_at", default_look_at)
		}

	# 2. Check for settings in the root config.cfg
	if root_config and root_config.has_section("AssetPreviewCamera"):
		return {
			"position": root_config.get_value("AssetPreviewCamera", "position", default_pos),
			"look_at": root_config.get_value("AssetPreviewCamera", "look_at", default_look_at)
		}

	# 3. Fallback to hardcoded defaults
	return {"position": default_pos, "look_at": default_look_at}

# Creates a single preview button for a given model path.
func _create_model_preview_button(path: String):
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(220, 220)
	
	# MODIFIED: Get the specific scale for this model and bind it to the press signal.
	var scale = _get_scale_for_model(path)
	btn.pressed.connect(_on_model_button_pressed.bind(path, btn, scale))
	
	var scene_name = path.get_file().get_basename()
	var label = Label.new()
	label.text = " " + scene_name
	# MODIFIED: Increase the font size for the model name label.
	label.add_theme_font_size_override("font_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(label)
	
	var svc = SubViewportContainer.new()
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	btn.add_child(svc)
	
	var vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2(220, 220)
	svc.add_child(vp)
	
	# NEW: Get camera settings from config files.
	var cam_settings = _get_camera_settings()
	var cam = Camera3D.new()
	vp.add_child(cam)
	# NEW: Apply settings from config or fallback to defaults.
	cam.position = cam_settings.get("position")
	cam.look_at(cam_settings.get("look_at"))
	
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.2, 0.2, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	cam.environment = env
	
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	vp.add_child(light)

	var scene = load(path)
	if scene:
		var instance = scene.instantiate()
		vp.add_child(instance)
		# Defer fitting to the next frame to ensure nodes are ready.
		get_tree().process_frame.connect(_fit_model_to_preview.bind(instance, cam), CONNECT_ONE_SHOT)

	model_list.add_child(btn)
	preview_buttons.append({"btn": btn, "path": path})

# Scales and positions a model instance to fit nicely within its preview camera.
func _fit_model_to_preview(instance: Node3D, cam: Camera3D):
	var meshes =[]
	_get_mesh_instances(instance, meshes)
	if meshes.is_empty(): return
	
	var bounds = AABB()
	var first = true
	for mi in meshes:
		var mi_aabb = mi.get_aabb()
		var xform = instance.global_transform.affine_inverse() * mi.global_transform
		var transformed_aabb = xform * mi_aabb
		if first:
			bounds = transformed_aabb
			first = false
		else:
			bounds = bounds.merge(transformed_aabb)
			
	var max_size = max(bounds.size.x, max(bounds.size.y, bounds.size.z))
	if max_size > 0.001:
		var fit_scale = 2.0 / max_size
		instance.scale = Vector3.ONE * fit_scale
		instance.position = -bounds.get_center() * fit_scale
		# MODIFIED: The camera's look_at is now controlled by config files,
		# so we no longer force it to look at the model's center here.
		# cam.look_at(instance.position)

# Recursively finds all MeshInstance3D nodes under a given node.
func _get_mesh_instances(node: Node, result: Array):
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_get_mesh_instances(child, result)

# MODIFIED: Handles a model button being pressed, now includes scale.
func _on_model_button_pressed(path: String, btn: Button, scale: float):
	# Deselect if the same button is pressed again.
	if selected_button == btn:
		clear_selection()
		emit_signal("selection_cleared")
	else:
		# Update visuals for selection.
		if is_instance_valid(selected_button):
			selected_button.modulate = Color(1, 1, 1)
		selected_button = btn
		selected_button.modulate = Color(0.4, 1.0, 0.4) # Highlight color
		
		# MODIFIED: Inform the main editor of the selection, including the scale.
		var data = {"path": path, "scale": scale}
		emit_signal("model_selected", data)

# Public method to clear the current selection.
func clear_selection():
	if is_instance_valid(selected_button):
		selected_button.modulate = Color(1, 1, 1)
	selected_button = null
