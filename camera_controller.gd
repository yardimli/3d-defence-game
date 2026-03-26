extends Node3D

# NEW: Enum to manage camera behavior modes
enum Mode { MANUAL, DEMO, FOLLOW }

# --- State ---
var cam_zoom := 10.0
var cam_rot_x := -45.0
var cam_rot_y := 45.0

# NEW: State variables for automated modes
var mode: Mode = Mode.MANUAL
var follow_target: Node3D = null
var demo_timer := 0.0
var demo_transition_speed := 1.0

# MODIFIED: A multiplier to control the overall speed of the demo camera transitions.
# The default value has been lowered to 0.25 for a much slower, smoother experience.
@export var demo_speed_multiplier := 0.25

@onready var camera: Camera3D = %Camera3D

# --- Public API for Level Editor ---

# NEW: Starts the automated demo camera sequence
func start_demo_mode():
	mode = Mode.DEMO
	follow_target = null
	_set_new_demo_target() # Initialize with a random target

# NEW: Starts following a specific Node3D target
func start_follow_mode(target: Node3D):
	if not is_instance_valid(target):
		return
	mode = Mode.FOLLOW
	follow_target = target

# NEW: Resets the camera to manual user control
func stop_automated_modes():
	mode = Mode.MANUAL
	follow_target = null

# --- Godot Lifecycle Methods ---

# Initialization method called by level_editor
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
	# MODIFIED: Use a match statement to handle different camera modes
	match mode:
		Mode.MANUAL:
			_process_manual(delta)
		Mode.DEMO:
			_process_demo(delta)
		Mode.FOLLOW:
			_process_follow(delta)

# --- Mode-specific Process Logic ---

# NEW: Contains the original lerp logic for manual control
func _process_manual(delta):
	rotation_degrees.x = lerp(rotation_degrees.x, cam_rot_x, delta * 15.0)
	rotation_degrees.y = lerp(rotation_degrees.y, cam_rot_y, delta * 15.0)
	if camera:
		camera.position.z = lerp(camera.position.z, cam_zoom, delta * 10.0)

# MODIFIED: Logic for the automated demo camera updated for smoother rotation
func _process_demo(delta):
	demo_timer -= delta
	if demo_timer <= 0:
		_set_new_demo_target()

	var current_speed = demo_transition_speed * demo_speed_multiplier

	# Smoothly move the camera pivot and zoom towards their targets
	if camera:
		camera.position.z = lerp(camera.position.z, cam_zoom, delta * current_speed)
	global_position = global_position.lerp(Vector3.ZERO, delta * current_speed * 0.5) # Gently re-center

	# MODIFIED: Use `lerp_angle` for rotation. This function correctly handles wrapping
	# (e.g., from 350 degrees to 10 degrees) by taking the shortest path,
	# which prevents the camera from spinning wildly.
	rotation_degrees.x = rad_to_deg(lerp_angle(deg_to_rad(rotation_degrees.x), deg_to_rad(cam_rot_x), delta * current_speed))
	rotation_degrees.y = rad_to_deg(lerp_angle(deg_to_rad(rotation_degrees.y), deg_to_rad(cam_rot_y), delta * current_speed))

# NEW: Logic for following a target node
func _process_follow(delta):
	if not is_instance_valid(follow_target):
		# If the target is lost (e.g., deleted), revert to manual mode
		stop_automated_modes()
		return

	# The camera pivot's position should match the target's position
	global_position = global_position.lerp(follow_target.global_position, delta * 10.0)
	
	# Rotation and zoom are still controlled by the user for orbiting
	rotation_degrees.x = lerp(rotation_degrees.x, cam_rot_x, delta * 15.0)
	rotation_degrees.y = lerp(rotation_degrees.y, cam_rot_y, delta * 15.0)
	if camera:
		camera.position.z = lerp(camera.position.z, cam_zoom, delta * 10.0)
		
# --- Helper Methods ---

# NEW: Sets a new random target for the demo camera
func _set_new_demo_target():
	demo_timer = randf_range(4.0, 8.0) # Stay at the target for 4-8 seconds
	demo_transition_speed = randf_range(0.5, 1.5) # Vary the transition speed

	var choice = randi() % 4
	match choice:
		0: # Bird's eye view
			cam_rot_x = randf_range(-89.0, -70.0)
			cam_rot_y = randf_range(0, 360)
			cam_zoom = randf_range(20.0, 40.0)
		1: # Ground level view
			cam_rot_x = randf_range(-25.0, -10.0)
			cam_rot_y = randf_range(0, 360)
			cam_zoom = randf_range(5.0, 15.0)
		2: # Isometric view
			cam_rot_x = randf_range(-50.0, -30.0)
			cam_rot_y = (randi() % 4) * 90.0 + 45.0 # Snap to 45-degree angles
			cam_zoom = randf_range(15.0, 30.0)
		3: # Random zoom-in/out
			cam_zoom = randf_range(4.0, 50.0)
			# Keep current rotation

# Extracted input handling for camera
func handle_input(event: InputEvent) -> bool:
	# MODIFIED: Disable panning input when in an automated mode
	if mode == Mode.DEMO:
		return false # Ignore all camera input in demo mode

	if event is InputEventMouseMotion:
		# MODIFIED: Disable panning when following a car, but allow rotation
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or (Input.is_key_pressed(KEY_SHIFT) and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
			if mode == Mode.FOLLOW:
				return true # Consume input but do nothing
			var right = camera.global_transform.basis.x
			var forward = camera.global_transform.basis.z
			forward.y = 0
			forward = forward.normalized()
			var pan_speed = 0.01 * cam_zoom
			global_position -= (right * event.relative.x + forward * event.relative.y) * pan_speed
			return true
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			# Rotation works in both MANUAL and FOLLOW modes
			cam_rot_y -= event.relative.x * 0.4
			cam_rot_x -= event.relative.y * 0.4
			cam_rot_x = clamp(cam_rot_x, -89.0, -10.0)
			return true
	elif event is InputEventPanGesture:
		# Zoom works in both MANUAL and FOLLOW modes
		cam_zoom += event.delta.y * 0.5
		cam_zoom = clamp(cam_zoom, 2.0, 60.0)
		return true
	elif event is InputEventMouseButton:
		# Zoom works in both MANUAL and FOLLOW modes
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: 
			cam_zoom -= 1.5
			cam_zoom = clamp(cam_zoom, 2.0, 60.0)
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: 
			cam_zoom += 1.5
			cam_zoom = clamp(cam_zoom, 2.0, 60.0)
			return true
	return false
