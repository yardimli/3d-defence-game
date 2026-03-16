extends Node3D

# --- Config Variables ---
var models_folder := "res://models"
var tile_x := 2.0
var tile_z := 2.0
var model_scale := 1.0

# --- State ---
var selected_model_path := ""
var grid_data := {}
var preview_buttons :=[]
var ghost_instance: Node3D = null
var placement_rotation_y := 0.0
var is_painting := false

# --- Nodes ---
var placed_models_container: Node3D
var cursor: MeshInstance3D
var model_list: VBoxContainer
var camera_pivot: Node3D
var camera: Camera3D
var ui_panel: PanelContainer
var sun_light: DirectionalLight3D
var sun_config_dialog: Window
var canvas: CanvasLayer # NEW: Make the CanvasLayer a member variable.
var sun_pos_x_edit: LineEdit
var sun_pos_y_edit: LineEdit
var sun_pos_z_edit: LineEdit
var sun_target_x_edit: LineEdit
var sun_target_y_edit: LineEdit
var sun_target_z_edit: LineEdit


# --- Materials ---
var ghost_material: StandardMaterial3D

# --- Camera State ---
var cam_zoom := 10.0
var cam_rot_x := -45.0
var cam_rot_y := 45.0

func _ready():
	_load_config()
	_setup_materials()
	_setup_scene_nodes()
	_setup_lighting()
	_setup_ui()
	_load_models()

func _process(delta):
	# Smoothly interpolate camera rotation and zoom
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
		tile_x = config.get_value("Settings", "tile_size_x", 2.0)
		tile_z = config.get_value("Settings", "tile_size_z", 2.0)
		model_scale = config.get_value("Settings", "model_scale", 1.0)
	
	if not DirAccess.dir_exists_absolute(models_folder):
		DirAccess.make_dir_absolute(models_folder)

func _setup_lighting():
	sun_light = DirectionalLight3D.new()
	sun_light.name = "SunLight"
	sun_light.shadow_enabled = true
	sun_light.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun_light)

func _setup_materials():
	# Create the transparent "hologram" material for the cursor ghost
	ghost_material = StandardMaterial3D.new()
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.albedo_color = Color(0.4, 0.8, 1.0, 0.6) # Light blue transparent
	ghost_material.emission_enabled = true
	ghost_material.emission = Color(0.2, 0.4, 0.8)
	ghost_material.emission_energy_multiplier = 0.5

func _setup_scene_nodes():
	placed_models_container = Node3D.new()
	add_child(placed_models_container)

	camera_pivot = Node3D.new()
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera_pivot.add_child(camera)
	
	cursor = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(tile_x, 0.1, tile_z)
	cursor.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 1, 0, 0.3)
	cursor.mesh.surface_set_material(0, mat)
	add_child(cursor)

func _setup_ui():
	# MODIFIED: Assign to the member variable instead of a local one.
	canvas = CanvasLayer.new()
	add_child(canvas)

	var top_hbox = HBoxContainer.new()
	top_hbox.position = Vector2(15, 15)
	canvas.add_child(top_hbox)

	var btn_save = Button.new()
	btn_save.text = " Save "
	btn_save.pressed.connect(_save_scene)
	top_hbox.add_child(btn_save)

	var btn_load = Button.new()
	btn_load.text = " Load "
	btn_load.pressed.connect(_load_scene)
	top_hbox.add_child(btn_load)
	
	var btn_rotate = Button.new()
	btn_rotate.text = " Rotate (R) "
	btn_rotate.pressed.connect(_rotate_placement)
	top_hbox.add_child(btn_rotate)

	var btn_delete = Button.new()
	btn_delete.text = " Delete (D) "
	btn_delete.pressed.connect(_delete_model_at_cursor)
	top_hbox.add_child(btn_delete)

	var btn_sun = Button.new()
	btn_sun.text = " Sun "
	btn_sun.pressed.connect(_on_sun_config_pressed)
	top_hbox.add_child(btn_sun)

	ui_panel = PanelContainer.new()
	canvas.add_child(ui_panel)
	
	ui_panel.anchor_left = 1.0
	ui_panel.anchor_right = 1.0
	ui_panel.anchor_top = 0.0
	ui_panel.anchor_bottom = 1.0
	ui_panel.offset_left = -230.0
	ui_panel.offset_right = 0.0
	ui_panel.offset_top = 0.0
	ui_panel.offset_bottom = 0.0

	var scroll = ScrollContainer.new()
	ui_panel.add_child(scroll)

	model_list = VBoxContainer.new()
	model_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(model_list)

	_create_sun_config_dialog()

func _create_sun_config_dialog():
	sun_config_dialog = Window.new()
	sun_config_dialog.title = "Sun Settings"
	sun_config_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_SCREEN_WITH_MOUSE_FOCUS
	sun_config_dialog.size = Vector2i(300, 250)
	sun_config_dialog.visible = false
	# MODIFIED: Add the dialog to the correct parent (the CanvasLayer).
	canvas.add_child(sun_config_dialog)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	sun_config_dialog.add_child(margin)

	var vbox = VBoxContainer.new()
	margin.add_child(vbox)

	var pos_label = Label.new()
	pos_label.text = "Sun Position (X, Y, Z):"
	vbox.add_child(pos_label)
	
	var pos_hbox = HBoxContainer.new()
	vbox.add_child(pos_hbox)
	sun_pos_x_edit = LineEdit.new()
	sun_pos_x_edit.placeholder_text = "X"
	pos_hbox.add_child(sun_pos_x_edit)
	sun_pos_y_edit = LineEdit.new()
	sun_pos_y_edit.placeholder_text = "Y"
	pos_hbox.add_child(sun_pos_y_edit)
	sun_pos_z_edit = LineEdit.new()
	sun_pos_z_edit.placeholder_text = "Z"
	pos_hbox.add_child(sun_pos_z_edit)

	var target_label = Label.new()
	target_label.text = "Look At Target (X, Y, Z):"
	vbox.add_child(target_label)

	var target_hbox = HBoxContainer.new()
	vbox.add_child(target_hbox)
	sun_target_x_edit = LineEdit.new()
	sun_target_x_edit.placeholder_text = "X"
	target_hbox.add_child(sun_target_x_edit)
	sun_target_y_edit = LineEdit.new()
	sun_target_y_edit.placeholder_text = "Y"
	target_hbox.add_child(sun_target_y_edit)
	sun_target_z_edit = LineEdit.new()
	sun_target_z_edit.placeholder_text = "Z"
	target_hbox.add_child(sun_target_z_edit)
	
	sun_pos_x_edit.text = str(sun_light.position.x)
	sun_pos_y_edit.text = str(sun_light.position.y)
	sun_pos_z_edit.text = str(sun_light.position.z)
	sun_target_x_edit.text = "0"
	sun_target_y_edit.text = "0"
	sun_target_z_edit.text = "0"

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var update_btn = Button.new()
	update_btn.text = "Update Sun"
	update_btn.pressed.connect(_on_update_sun_pressed)
	vbox.add_child(update_btn)

func _load_models():
	var model_paths = []
	var dir = DirAccess.open(models_folder)
	if dir:
		dir.list_dir_begin()
		var file = dir.get_next()
		while file != "":
			if not dir.current_is_dir() and file.ends_with(".glb"):
				model_paths.append(models_folder + "/" + file)
			file = dir.get_next()
	
	model_paths.sort()
	
	if model_paths.is_empty():
		print("WARNING: No .glb files found in ", models_folder)
	else:
		for path in model_paths:
			_create_model_preview_button(path)

func _get_glb_scene_name(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	file.seek(12)
	var json_chunk_length = file.get_32()
	var json_chunk_type = file.get_32()
	if json_chunk_type != 0x4E4F534A:
		printerr("Error: First chunk is not JSON for file: ", path)
		return ""
	var json_data_bytes = file.get_buffer(json_chunk_length)
	var json_string = json_data_bytes.get_string_from_utf8()
	var data = JSON.parse_string(json_string)
	if data and typeof(data) == TYPE_DICTIONARY and data.has("scenes"):
		if typeof(data.scenes) == TYPE_ARRAY and not data.scenes.is_empty():
			var first_scene = data.scenes[0]
			if typeof(first_scene) == TYPE_DICTIONARY and first_scene.has("name"):
				return first_scene.name
	return ""

func _create_model_preview_button(path: String):
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(220, 220)
	btn.pressed.connect(_on_model_selected.bind(path, btn))
	
	var scene_name = _get_glb_scene_name(path)
	if not scene_name.is_empty():
		var label = Label.new()
		label.text = " " + scene_name
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
	
	var cam = Camera3D.new()
	vp.add_child(cam)
	cam.position = Vector3(0, 1.0, 2.5)
	cam.look_at(Vector3(0,0,0))
		
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
		get_tree().process_frame.connect(_fit_model_to_preview.bind(instance, cam), CONNECT_ONE_SHOT)

	model_list.add_child(btn)
	preview_buttons.append({"btn": btn, "path": path})

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
		cam.look_at(instance.position)

func _get_mesh_instances(node: Node, result: Array):
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_get_mesh_instances(child, result)

func _on_model_selected(path: String, selected_btn: Button):
	selected_model_path = path
	for item in preview_buttons:
		item.btn.modulate = Color(1, 1, 1)
	selected_btn.modulate = Color(0.4, 1.0, 0.4)
	
	_create_ghost(path)

func _deselect_model():
	selected_model_path = ""

	for item in preview_buttons:
		item.btn.modulate = Color(1, 1, 1)

	if is_instance_valid(ghost_instance):
		ghost_instance.queue_free()
		ghost_instance = null
	print("Selection cleared.")

func _create_ghost(path: String):
	if is_instance_valid(ghost_instance):
		ghost_instance.queue_free()
		
	var scene = load(path)
	if scene:
		ghost_instance = scene.instantiate()
		cursor.add_child(ghost_instance)
		ghost_instance.scale = Vector3.ONE * model_scale
		ghost_instance.rotation_degrees.y = placement_rotation_y
		_apply_ghost_material(ghost_instance)

func _apply_ghost_material(node: Node):
	if node is MeshInstance3D:
		node.material_overlay = ghost_material
	for child in node.get_children():
		_apply_ghost_material(child)

# ==========================================
# PLACEMENT, ROTATION & DELETION
# ==========================================

func _rotate_placement():
	placement_rotation_y = fmod(placement_rotation_y + 90.0, 360.0)
	
	if is_instance_valid(ghost_instance):
		ghost_instance.rotation_degrees.y = placement_rotation_y
	print("Placement rotation set to: ", placement_rotation_y)

func _delete_model_at_cursor():
	var grid_pos = Vector2(cursor.position.x, cursor.position.z)
	
	if grid_data.has(grid_pos):
		var model_to_delete = grid_data[grid_pos]
		
		if is_instance_valid(model_to_delete):
			model_to_delete.queue_free()
			grid_data.erase(grid_pos)
			print("Deleted model at ", grid_pos)
		else:
			grid_data.erase(grid_pos)
	else:
		print("No model to delete at ", grid_pos)

# ==========================================
# SUN CONFIGURATION & UI CALLBACKS
# ==========================================

func _on_sun_config_pressed():
	sun_config_dialog.popup_centered()

func _on_update_sun_pressed():
	var pos_x = sun_pos_x_edit.text.to_float()
	var pos_y = sun_pos_y_edit.text.to_float()
	var pos_z = sun_pos_z_edit.text.to_float()
	var target_x = sun_target_x_edit.text.to_float()
	var target_y = sun_target_y_edit.text.to_float()
	var target_z = sun_target_z_edit.text.to_float()

	var new_pos = Vector3(pos_x, pos_y, pos_z)
	var new_target = Vector3(target_x, target_y, target_z)

	sun_light.position = new_pos
	sun_light.look_at(new_target)

	sun_config_dialog.hide()

# ==========================================
# INPUT & CAMERA CONTROLS
# ==========================================
func _unhandled_input(event):
	var mouse_pos = get_viewport().get_mouse_position()

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_deselect_model()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_R:
			_rotate_placement()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_D:
			_delete_model_at_cursor()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		_update_cursor(mouse_pos)

		if is_painting:
			if selected_model_path != "" and not Input.is_key_pressed(KEY_SHIFT):
				_place_model()

		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or (Input.is_key_pressed(KEY_SHIFT) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
			if ui_panel.get_global_rect().has_point(mouse_pos):
				return
			var right = camera.global_transform.basis.x
			var forward = camera.global_transform.basis.z
			forward.y = 0 
			forward = forward.normalized()
			var pan_speed = 0.01 * cam_zoom
			camera_pivot.global_position -= (right * event.relative.x + forward * event.relative.y) * pan_speed
		
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			if ui_panel.get_global_rect().has_point(mouse_pos):
				return
			cam_rot_y -= event.relative.x * 0.4
			cam_rot_x -= event.relative.y * 0.4
			cam_rot_x = clamp(cam_rot_x, -89.0, -10.0)

	if event is InputEventPanGesture:
		if ui_panel.get_global_rect().has_point(mouse_pos):
			return

		cam_zoom += event.delta.y * 0.5
		cam_zoom = clamp(cam_zoom, 2.0, 60.0)
		
	elif event is InputEventMouseButton:
		if ui_panel.get_global_rect().has_point(mouse_pos) or (sun_config_dialog.visible and sun_config_dialog.get_global_rect().has_point(mouse_pos)):
			return

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_zoom -= 1.5
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_zoom += 1.5
		cam_zoom = clamp(cam_zoom, 2.0, 60.0)

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if selected_model_path != "" and not event.shift_pressed:
					is_painting = true
					_place_model() 
			else:
				is_painting = false

func _update_cursor(mouse_pos: Vector2):
	var origin = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	if dir.y >= 0: return 
	
	var t = -origin.y / dir.y
	var intersection = origin + dir * t
	
	var sn_x = round(intersection.x / tile_x) * tile_x
	var sn_z = round(intersection.z / tile_z) * tile_z
	cursor.position = Vector3(sn_x, 0, sn_z)

# ==========================================
# PLACEMENT & SAVE/LOAD
# ==========================================
func _configure_shadows_for_node(node: Node):
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in node.get_children():
		_configure_shadows_for_node(child)

func _place_model():
	var grid_pos = Vector2(cursor.position.x, cursor.position.z)
	
	if grid_data.has(grid_pos) and is_instance_valid(grid_data[grid_pos]):
		if grid_data[grid_pos].get_meta("model_path") == selected_model_path and \
		abs(grid_data[grid_pos].rotation_degrees.y - placement_rotation_y) < 0.1:
			return
		grid_data[grid_pos].queue_free()

	var scene = load(selected_model_path)
	if scene:
		var instance = scene.instantiate()
		instance.position = cursor.position
		instance.scale = Vector3.ONE * model_scale
		instance.rotation_degrees.y = placement_rotation_y
		instance.set_meta("model_path", selected_model_path)
		_configure_shadows_for_node(instance)
		placed_models_container.add_child(instance)
		grid_data[grid_pos] = instance

func _save_scene():
	var save_array =[]
	for grid_pos in grid_data:
		var node = grid_data[grid_pos]
		if is_instance_valid(node):
			save_array.append({
				"path": node.get_meta("model_path"),
				"x": grid_pos.x,
				"z": grid_pos.y,
				"roty": node.rotation_degrees.y
			})
	var file = FileAccess.open("user://level_save.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(save_array))
	file.close()
	print("Saved to user://level_save.json")

func _load_scene():
	if not FileAccess.file_exists("user://level_save.json"): return
	var file = FileAccess.open("user://level_save.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	for child in placed_models_container.get_children():
		child.queue_free()
	grid_data.clear()

	for item in data:
		var scene = load(item["path"])
		if scene:
			var instance = scene.instantiate()
			instance.position = Vector3(item["x"], 0, item["z"])
			instance.scale = Vector3.ONE * model_scale
			instance.rotation_degrees.y = item.get("roty", 0.0)
			instance.set_meta("model_path", item["path"])
			_configure_shadows_for_node(instance)
			placed_models_container.add_child(instance)
			grid_data[Vector2(item["x"], item["z"])] = instance
	print("Loaded successfully!")
