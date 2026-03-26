extends PanelContainer

# Emits a dictionary with path and scale info.
signal model_selected(data: Dictionary)
# Emitted when the selection should be cleared (e.g., right-click).
signal selection_cleared

# --- Config ---
var models_folder := "res://models"

# --- State ---
var preview_buttons := []
var selected_button: Button = null
# ConfigFile objects to hold root and folder-specific settings.
var root_config := ConfigFile.new()
var folder_config: ConfigFile = null
# Holds the path of the currently viewed folder.
var current_folder_path: String = ""
# Holds temporary override settings from the settings dialog.
var preview_overrides: Dictionary = {}

# --- Node-Referenzen ---
@onready var folder_dropdown: OptionButton = %FolderDropdown
@onready var model_list: VBoxContainer = %ModelList

func _ready():
	# Load the root config file for fallback values.
	root_config.load("res://config.cfg")
	
	# Programmatically set the font size for the dropdown to ensure it applies.
	folder_dropdown.add_theme_font_size_override("font_size", 24)
	
	# Connect the dropdown's item_selected signal to the folder change handler.
	folder_dropdown.item_selected.connect(_on_folder_selected)
	# Initial population of the asset list.
	_populate_folder_dropdown()

# Public method for the level editor to apply temporary settings.
func apply_preview_overrides(settings: Dictionary):
	preview_overrides = settings
	# Refresh the previews with the new override settings.
	if not current_folder_path.is_empty():
		_populate_model_previews(current_folder_path)

# Public method for the level editor to get current settings for the dialog.
func get_current_preview_settings() -> Dictionary:
	var cam_settings = _get_camera_settings()
	var default_scale = root_config.get_value("Settings", "model_scale", 1.0)
	if folder_config and folder_config.has_section_key("Settings", "model_scale"):
		default_scale = folder_config.get_value("Settings", "model_scale")

	# Start with the base settings.
	var settings = {
		"model_scale": default_scale,
		"position": cam_settings.get("position"),
		"look_at": cam_settings.get("look_at")
	}
	
	# If overrides exist, let them take precedence.
	if preview_overrides.has("model_scale"):
		settings["model_scale"] = preview_overrides["model_scale"]
	if preview_overrides.has("position"):
		settings["position"] = preview_overrides["position"]
	if preview_overrides.has("look_at"):
		settings["look_at"] = preview_overrides["look_at"]
		
	return settings

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
	# Clear any temporary overrides when changing folders.
	preview_overrides.clear()
	
	var folder_name = folder_dropdown.get_item_text(index)
	current_folder_path = models_folder.path_join(folder_name)
	
	# Attempt to load a config file from the selected subfolder.
	var sub_config_path = current_folder_path.path_join("config.cfg")
	var sub_config = ConfigFile.new()
	if sub_config.load(sub_config_path) == OK:
		folder_config = sub_config
	else:
		folder_config = null # Reset if no config is found.
		
	_populate_model_previews(current_folder_path)

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

# Helper function to get the correct scale for a model. Checks for an override value first.
func _get_scale_for_model(model_path: String) -> float:
	var model_filename = model_path.get_file()
	
	# 0. Check for a temporary override from the settings dialog.
	if preview_overrides.has("model_scale"):
		return preview_overrides.get("model_scale")
	
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

# Helper function to get camera settings for the preview. Checks for override values first.
func _get_camera_settings() -> Dictionary:
	var default_pos = Vector3(0, 1.0, 2.5)
	var default_look_at = Vector3(0, 0, 0)
	var settings: Dictionary

	# 1. Check for settings in the folder's config.cfg
	if folder_config and folder_config.has_section("AssetPreviewCamera"):
		settings = {
			"position": folder_config.get_value("AssetPreviewCamera", "position", default_pos),
			"look_at": folder_config.get_value("AssetPreviewCamera", "look_at", default_look_at)
		}
	# 2. Check for settings in the root config.cfg
	elif root_config and root_config.has_section("AssetPreviewCamera"):
		settings = {
			"position": root_config.get_value("AssetPreviewCamera", "position", default_pos),
			"look_at": root_config.get_value("AssetPreviewCamera", "look_at", default_look_at)
		}
	# 3. Fallback to hardcoded defaults
	else:
		settings = {"position": default_pos, "look_at": default_look_at}

	# 4. Apply temporary overrides if they exist.
	if preview_overrides.has("position"):
		settings["position"] = preview_overrides["position"]
	if preview_overrides.has("look_at"):
		settings["look_at"] = preview_overrides["look_at"]
		
	return settings

# Creates a single preview button for a given model path.
func _create_model_preview_button(path: String):
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(220, 220)
	
	# Get the specific scale for this model and bind it to the press signal.
	var scale = _get_scale_for_model(path)
	btn.pressed.connect(_on_model_button_pressed.bind(path, btn, scale))
	
	var scene_name = path.get_file().get_basename()
	var label = Label.new()
	label.text = " " + scene_name
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
	
	# Get camera settings from config files.
	var cam_settings = _get_camera_settings()
	var cam = Camera3D.new()
	vp.add_child(cam)
	# Apply settings from config or fallback to defaults.
	cam.position = cam_settings.get("position")
	cam.call_deferred("look_at", cam_settings.get("look_at"))

	
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

	model_list.add_child(btn)
	preview_buttons.append({"btn": btn, "path": path})

# Recursively finds all MeshInstance3D nodes under a given node.
func _get_mesh_instances(node: Node, result: Array):
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_get_mesh_instances(child, result)

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
		
		# Inform the main editor of the selection, including the scale.
		var data = {"path": path, "scale": scale}
		emit_signal("model_selected", data)

# Public method to clear the current selection.
func clear_selection():
	if is_instance_valid(selected_button):
		selected_button.modulate = Color(1, 1, 1)
	selected_button = null
