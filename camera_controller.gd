extends Node3D

# --- State ---
var cam_zoom := 10.0
var cam_rot_x := -45.0
var cam_rot_y := 45.0

@onready var camera: Camera3D = %Camera3D

# NEW: Initialization method called by level_editor
func set_config(zoom: float, rot_x: float, rot_y: float):
	cam_zoom = zoom
	cam_rot_x = rot_x
	cam_rot_y = rot_y
	
	# Apply immediately to avoid initial lerp sweep
	rotation_degrees.x = cam_rot_x
	rotation_degrees.y = cam_rot_y
	if camera:
		camera.position.z = cam_zoom

func _process(delta):
	rotation_degrees.x = lerp(rotation_degrees.x, cam_rot_x, delta * 15.0)
	rotation_degrees.y = lerp(rotation_degrees.y, cam_rot_y, delta * 15.0)
	if camera:
		camera.position.z = lerp(camera.position.z, cam_zoom, delta * 10.0)

# NEW: Extracted input handling for camera
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or (Input.is_key_pressed(KEY_SHIFT) and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
			var right = camera.global_transform.basis.x
			var forward = camera.global_transform.basis.z
			forward.y = 0
			forward = forward.normalized()
			var pan_speed = 0.01 * cam_zoom
			global_position -= (right * event.relative.x + forward * event.relative.y) * pan_speed
			return true
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			cam_rot_y -= event.relative.x * 0.4
			cam_rot_x -= event.relative.y * 0.4
			cam_rot_x = clamp(cam_rot_x, -89.0, -10.0)
			return true
	elif event is InputEventPanGesture:
		cam_zoom += event.delta.y * 0.5
		cam_zoom = clamp(cam_zoom, 2.0, 60.0)
		return true
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: 
			cam_zoom -= 1.5
			cam_zoom = clamp(cam_zoom, 2.0, 60.0)
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: 
			cam_zoom += 1.5
			cam_zoom = clamp(cam_zoom, 2.0, 60.0)
			return true
	return false
