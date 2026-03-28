extends Node3D

# Enum to manage camera behavior modes
enum Mode { MANUAL, DEMO, FOLLOW }

# --- Signals ---
# Emitted when the camera zoom level changes.
signal zoomed(zoom_value: float)

# --- State ---
var cam_zoom := 10.0
var cam_rot_x := -45.0
var cam_rot_y := 45.0

# State variables for automated modes
var mode: Mode = Mode.MANUAL
var follow_target: Node3D = null
var demo_timer := 0.0
var demo_transition_speed := 1.0

@export var demo_speed_multiplier := 0.25

@onready var camera: Camera3D = %Camera3D

# --- Public API for Level Editor ---

# Starts the automated demo camera sequence
func start_demo_mode():
	mode = Mode.DEMO
	follow_target = null
	_set_new_demo_target() # Initialize with a random target

# Starts following a specific Node3D target
func start_follow_mode(target: Node3D):
	if not is_instance_valid(target):
		return
	mode = Mode.FOLLOW
	follow_target = target

# Resets the camera to manual user control
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
	match mode:
		Mode.MANUAL:
			_process_manual(delta)
		Mode.DEMO:
			_process_demo(delta)
		Mode.FOLLOW:
			_process_follow(delta)
	
	# Final check to prevent the camera from going through the ground. This lifts the entire pivot if the camera's final position is too low.
	# A small positive value (0.5) is used as a threshold to avoid clipping.
	var cam_global_y = camera.get_global_transform().origin.y
	if cam_global_y < 0.5:
		global_position.y += 0.5 - cam_global_y

# --- Mode-specific Process Logic ---

# Contains the original lerp logic for manual control
func _process_manual(delta):
	rotation_degrees.x = lerp(rotation_degrees.x, cam_rot_x, delta * 15.0)
	rotation_degrees.y = lerp(rotation_degrees.y, cam_rot_y, delta * 15.0)
	if camera:
		camera.position.z = lerp(camera.position.z, cam_zoom, delta * 10.0)

func _process_demo(delta):
	demo_timer -= delta
	if demo_timer <= 0:
		_set_new_demo_target()

	var current_speed = demo_transition_speed * demo_speed_multiplier

	# Smoothly move the camera pivot and zoom towards their targets
	if camera:
		camera.position.z = lerp(camera.position.z, cam_zoom, delta * current_speed)
	global_position = global_position.lerp(Vector3.ZERO, delta * current_speed * 0.5) # Gently re-center

	# Use `lerp_angle` for rotation. This function correctly handles wrapping
	# (e.g., from 350 degrees to 10 degrees) by taking the shortest path,
	# which prevents the camera from spinning wildly.
	rotation_degrees.x = rad_to_deg(lerp_angle(deg_to_rad(rotation_degrees.x), deg_to_rad(cam_rot_x), delta * current_speed))
	rotation_degrees.y = rad_to_deg(lerp_angle(deg_to_rad(rotation_degrees.y), deg_to_rad(cam_rot_y), delta * current_speed))

# Logic for following a target node
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
			cam_rot_x = randf_range(-15.0, 5.0)
			cam_rot_y = randf_range(0, 360)
			cam_zoom = randf_range(5.0, 15.0)
		2: # Isometric view
			cam_rot_x = randf_range(-50.0, -30.0)
			cam_rot_y = (randi() % 4) * 90.0 + 45.0 # Snap to 45-degree angles
			cam_zoom = randf_range(15.0, 30.0)
		3: # Random zoom-in/out
			cam_zoom = randf_range(4.0, 50.0)
			# Keep current rotation

# Input handling is refactored to cleanly separate gesture-based controls (Magic Mouse, Trackpad)
# from traditional mouse button controls. This fixes the "always rotating" bug and correctly
# implements the requested swipe gestures.
func handle_input(event: InputEvent) -> bool:
	# Disable all camera input when in an automated mode
	if mode == Mode.DEMO:
		return false

	# --- Gesture Handling (for macOS Magic Mouse / Trackpad) ---
	# This block handles swipe gestures for rotation, panning, and zooming.
	if event is InputEventPanGesture:
		var is_shift_pressed = Input.is_key_pressed(KEY_SHIFT)
		var is_control_pressed = Input.is_key_pressed(KEY_CTRL)
		if is_control_pressed:
			# ZOOM: Ctrl + Swipe Up/Down
			cam_zoom += event.delta.y * 0.5
			cam_zoom = clamp(cam_zoom, 2.0, 60.0)
			emit_signal("zoomed", cam_zoom)
			return true
		elif is_shift_pressed:
			# PAN: Shift + Swipe
			if mode == Mode.FOLLOW: return true # Disable pan in follow mode
			
			var right = camera.global_transform.basis.x
			var forward = camera.global_transform.basis.z
			forward.y = 0
			forward = forward.normalized()
			var pan_speed = 0.002 * cam_zoom # Adjusted speed for gestures
			# Pan gestures often feel more natural with inverted directions (like a touchscreen)
			global_position -= (right * event.delta.x - forward * event.delta.y) * pan_speed
			global_position.y = max(global_position.y, 0.0)
			return true
		else:
			print('orbit single-finger')
			# ROTATE (ORBIT): Single-finger Swipe
			# A pan gesture with no modifiers is treated as a rotation/orbit swipe.
			cam_rot_y -= event.delta.x * 0.4
			cam_rot_x -= event.delta.y * 0.4
			cam_rot_x = clamp(cam_rot_x, -89.0, 5.0)
			return true

	# --- Standard Mouse Button Handling (for Windows / Traditional Mice) ---
	# This block handles drag and scroll wheel events.
	if event is InputEventMouseMotion:
		# PAN: Shift + MMB Drag or Spacebar + LMB Drag
		var is_panning = (event.button_mask == MOUSE_BUTTON_MIDDLE and Input.is_key_pressed(KEY_SHIFT)) or \
						 (event.button_mask == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SPACE))
		
		if is_panning:
			if mode == Mode.FOLLOW: return true
			var right = camera.global_transform.basis.x
			var forward = camera.global_transform.basis.z
			forward.y = 0
			forward = forward.normalized()
			var pan_speed = 0.001 * cam_zoom
			global_position -= (right * event.relative.x + forward * event.relative.y) * pan_speed
			global_position.y = max(global_position.y, 0.0)
			return true
			
		# ROTATE (ORBIT): MMB Drag or RMB Drag
		var is_rotating = (event.button_mask == MOUSE_BUTTON_MIDDLE and not Input.is_key_pressed(KEY_SHIFT)) or \
						  (event.button_mask == MOUSE_BUTTON_RIGHT)
						
		if is_rotating:
			print('debug rotating')
			cam_rot_y -= event.relative.x * 0.4
			cam_rot_x -= event.relative.y * 0.4
			cam_rot_x = clamp(cam_rot_x, -89.0, 5.0)
			return true
			
	elif event is InputEventMouseButton:
		# ZOOM: Mouse Wheel Scroll
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_zoom -= 1.5
			cam_zoom = clamp(cam_zoom, 2.0, 60.0)
			emit_signal("zoomed", cam_zoom)
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_zoom += 1.5
			cam_zoom = clamp(cam_zoom, 2.0, 60.0)
			emit_signal("zoomed", cam_zoom)
			return true

	return false
