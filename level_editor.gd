extends Node3D

# --- Config Variables ---
var models_folder := "res://models"
var tile_x := 2.0
var tile_z := 2.0
var model_scale := 1.0

# --- State ---
var selected_model_path := ""
var grid_data := {} # Stores placed models keyed by Vector2 grid position
var preview_buttons :=[]

# --- Nodes ---
var placed_models_container: Node3D
var cursor: MeshInstance3D
var model_list: VBoxContainer
var camera_pivot: Node3D
var camera: Camera3D

# --- Camera State ---
var cam_zoom := 10.0
var cam_rot_x := -45.0
var cam_rot_y := 45.0

func _ready():
	_load_config()
	_setup_scene_nodes()
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

func _setup_scene_nodes():
	placed_models_container = Node3D.new()
	add_child(placed_models_container)

	# Set up Camera rig
	camera_pivot = Node3D.new()
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera_pivot.add_child(camera)
	
	# Set up Cursor Indicator (Semi-transparent tile)
	cursor = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(tile_x, 0.1, tile_z)
	cursor.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 1, 0, 0.4) # Green transparent
	cursor.mesh.surface_set_material(0, mat)
	add_child(cursor)

func _setup_ui():
	var canvas = CanvasLayer.new()
	add_child(canvas)

	# Top-Left Save/Load buttons
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

	# Right Scrollable Panel
	var panel = PanelContainer.new()
	canvas.add_child(panel) # Add first, position second
	
	# Explicitly pin to the right side, 200px wide, spanning top to bottom
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -200.0
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0

	var scroll = ScrollContainer.new()
	panel.add_child(scroll)

	model_list = VBoxContainer.new()
	model_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(model_list)
	
func _load_models():
	var dir = DirAccess.open(models_folder)
	if dir:
		dir.list_dir_begin()
		var file = dir.get_next()
		while file != "":
			if not dir.current_is_dir() and file.ends_with(".glb"):
				_create_model_preview_button(models_folder + "/" + file)
			file = dir.get_next()

func _create_model_preview_button(path: String):
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(160, 160)
	btn.pressed.connect(_on_model_selected.bind(path, btn))
	
	# Create a 3D SubViewport to preview the GLB file
	var svc = SubViewportContainer.new()
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.add_child(svc)
	
	var vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2(160, 160)
	svc.add_child(vp)
	
	# Setup Preview Camera & Lighting
	var cam = Camera3D.new()
	cam.position = Vector3(2, 2, 2)
	cam.look_at(Vector3.ZERO)
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.2, 0.2, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	cam.environment = env
	vp.add_child(cam)
	
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	vp.add_child(light)

	# Load the GLB into the preview
	var scene = load(path)
	if scene:
		var instance = scene.instantiate()
		instance.scale = Vector3.ONE * model_scale
		vp.add_child(instance)

	model_list.add_child(btn)
	preview_buttons.append({"btn": btn, "path": path})

func _on_model_selected(path: String, selected_btn: Button):
	selected_model_path = path
	# Clear highlights
	for item in preview_buttons:
		item.btn.modulate = Color(1, 1, 1)
	# Highlight selected in green
	selected_btn.modulate = Color(0.4, 1.0, 0.4)

# ==========================================
# INPUT & CAMERA CONTROLS
# ==========================================
func _unhandled_input(event):
	var mouse_pos = get_viewport().get_mouse_position()

	# 1. Update Grid Cursor Position
	if event is InputEventMouseMotion:
		_update_cursor(mouse_pos)

		# Pan (Middle Mouse Button)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			var right = camera.global_transform.basis.x
			var forward = camera.global_transform.basis.z
			forward.y = 0 # Keep pan strictly horizontal
			forward = forward.normalized()
			
			var pan_speed = 0.01 * cam_zoom
			camera_pivot.global_position -= (right * event.relative.x + forward * event.relative.y) * pan_speed
		
		# Tilt / Orbit (Right Mouse Button)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			cam_rot_y -= event.relative.x * 0.4
			cam_rot_x -= event.relative.y * 0.4
			cam_rot_x = clamp(cam_rot_x, -89.0, -10.0)

	# 2. Zoom handling (Standard Wheel + Mac Magic Mouse Pan Gestures)
	if event is InputEventPanGesture: # Mac Magic Mouse / Trackpad zoom
		cam_zoom += event.delta.y * 0.5
		cam_zoom = clamp(cam_zoom, 2.0, 60.0)
		
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_zoom -= 1.5
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_zoom += 1.5
		cam_zoom = clamp(cam_zoom, 2.0, 60.0)

		# 3. Placement (Left Click)
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and selected_model_path != "":
			# Prevent clicking through UI
			if mouse_pos.x < get_viewport().size.x - 180: 
				_place_model()

func _update_cursor(mouse_pos: Vector2):
	var origin = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	if dir.y >= 0: return # Looking above the horizon
	
	# Math intersection with Y=0 plane
	var t = -origin.y / dir.y
	var intersection = origin + dir * t
	
	# Snap to Grid
	var sn_x = round(intersection.x / tile_x) * tile_x
	var sn_z = round(intersection.z / tile_z) * tile_z
	cursor.position = Vector3(sn_x, 0, sn_z)

# ==========================================
# PLACEMENT & SAVE/LOAD
# ==========================================
func _place_model():
	var grid_pos = Vector2(cursor.position.x, cursor.position.z)
	
	# Remove existing model on this tile
	if grid_data.has(grid_pos) and is_instance_valid(grid_data[grid_pos]):
		grid_data[grid_pos].queue_free()

	var scene = load(selected_model_path)
	if scene:
		var instance = scene.instantiate()
		instance.position = cursor.position
		instance.scale = Vector3.ONE * model_scale
		instance.set_meta("model_path", selected_model_path) # Tag for saving
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
				"z": grid_pos.y # Vector2.y is used as Z axis coordinate
			})
	
	var file = FileAccess.open("user://level_save.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(save_array))
	file.close()
	print("Saved to user://level_save.json")

func _load_scene():
	if not FileAccess.file_exists("user://level_save.json"):
		return
		
	var file = FileAccess.open("user://level_save.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	# Clear current board
	for child in placed_models_container.get_children():
		child.queue_free()
	grid_data.clear()

	# Rebuild
	for item in data:
		var scene = load(item["path"])
		if scene:
			var instance = scene.instantiate()
			instance.position = Vector3(item["x"], 0, item["z"])
			instance.scale = Vector3.ONE * model_scale
			instance.set_meta("model_path", item["path"])
			placed_models_container.add_child(instance)
			grid_data[Vector2(item["x"], item["z"])] = instance
	print("Loaded successfully!")
