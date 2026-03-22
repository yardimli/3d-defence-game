extends Node3D

# --- Config ---
@export var vehicle_speed: float = 2.0
@export var vehicle_spacing: float = 1.0

# NEW: Global flag to draw debug bounding boxes for all spawned cars.
# This can be enabled from the Godot Editor's Inspector panel.
@export var draw_debug_bounding_boxes: bool = true

# MODIFIED: Array to configure different vehicle models.
# Each dictionary now includes a "bounding_box_size" to define the collision area.
var vehicle_models = [
	{
		"path": "res://models/car-kit/ambulance.glb",
		"scale": 0.2,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) # MODIFIED: Added specific bounding box size.
	},
	{
		"path": "res://models/car-kit/delivery.glb",
		"scale": 0.2,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) # MODIFIED: Added specific bounding box size.
	},
	{
		"path": "res://models/car-kit/firetruck.glb",
		"scale": 0.2,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) # MODIFIED: Added specific bounding box size.
	},
	{
		"path": "res://models/car-kit/suv.glb",
		"scale": 0.2,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) # MODIFIED: Added specific bounding box size.
	}
]


# --- Dependencies ---
var level_editor: Node3D
var track_generator: Node3D
var camera: Camera3D

# --- State ---
var active_vehicles: Array[Dictionary] =[]

# Drag & Drop State
var dragged_car = null
var drag_original_pos := Vector3.ZERO
var drag_original_segment = null
var drag_original_progress := 0.0

func initialize(editor: Node3D, track_gen: Node3D, cam: Camera3D):
	level_editor = editor
	track_generator = track_gen
	camera = cam
	
	track_generator.track_regenerated.connect(on_track_regenerated)

func spawn_car():
	if track_generator.track_segments.is_empty():
		print("No tracks available to spawn a car.")
		return
		
	var seg = track_generator.track_segments.pick_random()
	var progress = randf() * seg.curve.get_baked_length()
	
	var vehicle_instance_data = _create_vehicle_instance()
	if vehicle_instance_data.is_empty():
		printerr("Failed to create vehicle instance. Check model paths.")
		return
		
	add_child(vehicle_instance_data["root"])
	
	var car_data = {
		"node": vehicle_instance_data["root"],
		"config": vehicle_instance_data["config"],
		"segment": seg,
		"progress": progress,
		"base_speed": vehicle_speed * randf_range(0.8, 1.2),
		"current_speed": 0.0,
		"state": "driving",
		"wait_time": 0.0,
		"uturn_timer": 0.0,
		"uturn_start_pos": Vector3.ZERO,
		"uturn_start_basis": Basis(),
		"uturn_target_seg": null,
		"uturn_target_offset": 0.0,
		"chosen_next_segment": null
	}
	
	active_vehicles.append(car_data)
	_pick_next_segment(car_data)

# MODIFIED: This function now creates a configurable bounding box for collision
# and can also draw a debug visual for it.
func _create_vehicle_instance() -> Dictionary:
	if vehicle_models.is_empty():
		return {}

	var car_config = vehicle_models.pick_random()
	
	var car_scene = load(car_config.path)
	if not car_scene:
		printerr("Failed to load car scene: ", car_config.path)
		return {}
		
	var car_root = car_scene.instantiate()
	car_root.scale = Vector3.ONE * car_config.get("scale", 0.2)
	car_root.rotation_degrees = car_config.get("initial_rotation_degrees", Vector3.ZERO)
	
	# Create the collision area
	var area = Area3D.new()
	area.set_meta("is_car", true)
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	
	# NEW: Use the specific bounding box size from the car's configuration.
	# Fallback to a default size if not specified.
	var bbox_size = car_config.get("bounding_box_size", Vector3(0.4, 0.4, 0.6))
	box.size = bbox_size
	
	shape.shape = box
	area.position.y = bbox_size.y / 2.0 # Center the box vertically
	area.add_child(shape)
	car_root.add_child(area)
	
	# NEW: If the debug flag is on, create a visible mesh for the bounding box.
	if draw_debug_bounding_boxes:
		var debug_mesh_instance = MeshInstance3D.new()
		var debug_mesh = BoxMesh.new()
		debug_mesh.size = bbox_size # Match the collision shape size
		debug_mesh_instance.mesh = debug_mesh
		
		# Create a semi-transparent material for the debug visual
		var debug_material = StandardMaterial3D.new()
		debug_material.albedo_color = Color(1.0, 0.0, 0.0, 0.4) # Red, 40% opaque
		debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		debug_mesh_instance.material_override = debug_material
		
		# Add the visual mesh as a child of the Area3D to align it perfectly.
		area.add_child(debug_mesh_instance)
		
	return {"root": car_root, "config": car_config}

func _unhandled_input(event):
	if not camera: return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var space_state = get_world_3d().direct_space_state
			var mouse_pos = event.position
			var origin = camera.project_ray_origin(mouse_pos)
			var end = origin + camera.project_ray_normal(mouse_pos) * 1000.0
			var query = PhysicsRayQueryParameters3D.create(origin, end)
			query.collide_with_areas = true
			var result = space_state.intersect_ray(query)
			
			if result and result.collider.has_meta("is_car"):
				var car_node = result.collider.get_parent()
				for car in active_vehicles:
					if car.node == car_node:
						dragged_car = car
						drag_original_pos = car.node.global_position
						drag_original_segment = car.segment
						drag_original_progress = car.progress
						car.state = "dragged"
						
						car.node.position.y += 0.5
						get_viewport().set_input_as_handled()
						break
		else:
			if dragged_car != null:
				var closest_seg = null
				var min_dist = INF
				var best_progress = 0.0
				
				for seg in track_generator.track_segments:
					var closest_pt = seg.curve.get_closest_point(dragged_car.node.global_position)
					var dist = closest_pt.distance_to(dragged_car.node.global_position)
					if dist < min_dist:
						min_dist = dist
						closest_seg = seg
						best_progress = seg.curve.get_closest_offset(dragged_car.node.global_position)

				if min_dist < 1.0 and closest_seg != null:
					dragged_car.segment = closest_seg
					dragged_car.progress = best_progress
					dragged_car.state = "driving"
					_pick_next_segment(dragged_car)
				else:
					dragged_car.node.global_position = drag_original_pos
					dragged_car.segment = drag_original_segment
					dragged_car.progress = drag_original_progress
					dragged_car.state = "driving"
					_pick_next_segment(dragged_car)

				dragged_car = null
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and dragged_car != null:
		var mouse_pos = event.position
		var origin = camera.project_ray_origin(mouse_pos)
		var dir = camera.project_ray_normal(mouse_pos)
		if dir.y < 0:
			var t = -origin.y / dir.y
			var intersection = origin + dir * t
			intersection.y = 0.5
			dragged_car.node.global_position = intersection
		get_viewport().set_input_as_handled()

func on_track_regenerated():
	for car in active_vehicles:
		if car.state == "dragged": continue
		
		var min_dist = INF
		var best_seg = null
		var best_progress = 0.0
		
		for seg in track_generator.track_segments:
			var closest_pt = seg.curve.get_closest_point(car.node.global_position)
			var dist = closest_pt.distance_to(car.node.global_position)
			if dist < min_dist:
				min_dist = dist
				best_seg = seg
				best_progress = seg.curve.get_closest_offset(car.node.global_position)

		if best_seg:
			car.segment = best_seg
			car.progress = best_progress
			car.state = "driving"
			_pick_next_segment(car)
		else:
			car.segment = null

# MODIFIED: This function is disabled and will always return false,
# preventing cars from stopping at intersections.
func _should_yield_at_intersection(car: Dictionary) -> bool:
	return false

# MODIFIED: This function now calculates a safe speed based on the distance
# to the car directly in front, preventing collisions.
func _get_speed_for_forward_obstacle(car: Dictionary) -> float:
	var car_in_front = null
	var min_dist = INF

	# --- 1. Find the closest vehicle directly in front ---
	for other_car in active_vehicles:
		if other_car == car:
			continue

		var dist = -1.0

		# Case 1: The other car is on the same segment, ahead of us.
		if other_car.segment == car.segment and other_car.progress > car.progress:
			dist = other_car.progress - car.progress
		
		# Case 2: The other car is on the next chosen segment.
		elif car.chosen_next_segment != null and other_car.segment == car.chosen_next_segment:
			var remaining_dist_on_current_seg = car.segment.curve.get_baked_length() - car.progress
			dist = remaining_dist_on_current_seg + other_car.progress
		
		# If we found a car in front of us and it's closer than the previous one
		if dist >= 0 and dist < min_dist:
			min_dist = dist
			car_in_front = other_car

	# --- 2. If no car is in front, proceed at base speed ---
	if car_in_front == null:
		return car.base_speed

	# --- 3. Calculate a safe speed based on distance ---
	# The minimum safe distance is the length of our car plus the desired spacing.
	# The car's length is its bounding box's Z-axis size.
	var car_length = car.config.get("bounding_box_size", Vector3.ZERO).z
	var safe_distance = car_length + vehicle_spacing
	
	# We define a larger "detection range" to start slowing down smoothly.
	var detection_range = safe_distance * 2.5 # Start slowing down from 2.5x the safe distance

	if min_dist > detection_range:
		# Obstacle is too far away to matter.
		return car.base_speed
	elif min_dist <= safe_distance:
		# We are too close. Match the speed of the car in front to avoid collision.
		return car_in_front.current_speed
	else:
		# We are within the detection range but not yet at the minimum safe distance.
		# We interpolate our speed between our base speed and the obstacle's speed.
		# The closer we get, the more our speed will match the car in front.
		var t = inverse_lerp(safe_distance, detection_range, min_dist)
		return lerp(car_in_front.current_speed, car.base_speed, t)

func _process(delta: float):
	for i in range(active_vehicles.size()):
		var car = active_vehicles[i]
		
		# --- State Handling: Dragged & U-turning ---
		if car.state == "dragged":
			continue
		
		if car.state == "uturning":
			car.uturn_timer -= delta
			var t = 1.0 - max(car.uturn_timer, 0.0)
			
			var config = car.config
			var rotation_degrees = config.get("initial_rotation_degrees", Vector3.ZERO)
			var initial_rotation_radians = Vector3(deg_to_rad(rotation_degrees.x), deg_to_rad(rotation_degrees.y), deg_to_rad(rotation_degrees.z))
			var initial_rotation = Basis.from_euler(initial_rotation_radians)
			var scale = config.get("scale", 0.2)
			
			var target_track_xform = car.uturn_target_seg.curve.sample_baked_with_rotation(car.uturn_target_offset, false, false)
			var target_basis = (target_track_xform.basis * initial_rotation).scaled(Vector3.ONE * scale)
			var target_origin = target_track_xform.origin
			target_origin.y += 0.05
			
			car.node.global_position = car.uturn_start_pos.lerp(target_origin, t)
			car.node.global_transform.basis = car.uturn_start_basis.slerp(target_basis, t)
			
			if car.uturn_timer <= 0:
				car.segment = car.uturn_target_seg
				car.progress = car.uturn_target_offset
				car.state = "driving"
				car.current_speed = 0.0
				_pick_next_segment(car)
			continue

		var seg = car.segment
		if not seg or not seg.curve: continue
		
		# --- Speed Calculation ---
		# MODIFIED: The car's target speed is now determined by checking for obstacles.
		var target_speed = _get_speed_for_forward_obstacle(car)

		# --- Physics Update ---
		# Smoothly adjust the car's current speed towards its target speed.
		car.current_speed = lerp(car.current_speed, target_speed, delta * 4.0)
		car.progress += car.current_speed * delta
		
		# --- Segment Transition Logic ---
		var curve_len = seg.curve.get_baked_length()
		while car.progress > curve_len:
			if curve_len <= 0.001: break
				
			if car.chosen_next_segment != null:
				car.progress -= curve_len
				seg = car.chosen_next_segment
				car.segment = seg
				curve_len = seg.curve.get_baked_length()
				_pick_next_segment(car)
			elif seg.next_segments.size() > 0:
				car.progress -= curve_len
				seg = seg.next_segments.pick_random()
				car.segment = seg
				curve_len = seg.curve.get_baked_length()
				_pick_next_segment(car)
			else:
				# Reached a dead end, force a U-turn.
				car.progress = curve_len
				_start_uturn(car)
				break
		
		# --- Visual Update ---
		if car.state == "driving":
			var track_transform = seg.curve.sample_baked_with_rotation(car.progress, false, false)
			
			var config = car.config
			var rotation_degrees = config.get("initial_rotation_degrees", Vector3.ZERO)
			var initial_rotation_radians = Vector3(deg_to_rad(rotation_degrees.x), deg_to_rad(rotation_degrees.y), deg_to_rad(rotation_degrees.z))
			var initial_rotation = Basis.from_euler(initial_rotation_radians)
			var scale = config.get("scale", 0.2)
			
			var new_basis = (track_transform.basis * initial_rotation).scaled(Vector3.ONE * scale)
			
			var new_origin = track_transform.origin
			new_origin.y += 0.05
			
			car.node.global_transform = Transform3D(new_basis, new_origin)

# MODIFIED: Logic to check for other cars has been removed.
# The car will now pick a random next segment regardless of traffic.
func _pick_next_segment(car: Dictionary):
	if not car.segment or car.segment.next_segments.is_empty():
		car.chosen_next_segment = null
		return

	# Simply pick a random next path without checking if it's occupied.
	car.chosen_next_segment = car.segment.next_segments.pick_random()


func _start_uturn(car: Dictionary):
	var min_dist = INF
	var best_seg = null
	var best_offset = 0.0
	var car_fwd = -car.node.global_transform.basis.z
	
	# Find the nearest valid segment behind the car to turn around onto.
	for seg in track_generator.track_segments:
		var closest_pt = seg.curve.get_closest_point(car.node.global_position)
		var dist = closest_pt.distance_to(car.node.global_position)
		
		if dist < 1.0: # Search within a reasonable radius.
			var offset = seg.curve.get_closest_offset(car.node.global_position)
			var xform = seg.curve.sample_baked_with_rotation(offset, false, false)
			var seg_fwd = -xform.basis.z
			
			# Ensure the target segment is facing the opposite direction.
			if seg_fwd.dot(car_fwd) < -0.5:
				if dist < min_dist:
					min_dist = dist
					best_seg = seg
					best_offset = offset
					
	if best_seg:
		car.state = "uturning"
		car.uturn_timer = 1.0
		car.uturn_start_pos = car.node.global_position
		car.uturn_start_basis = car.node.global_transform.basis
		car.uturn_target_seg = best_seg
		car.uturn_target_offset = best_offset
		car.wait_time = 0.0
	else:
		# Fallback if no suitable U-turn segment is found (should be rare).
		# Immediately rotate and try to reverse a little.
		car.node.rotate_y(PI)
		car.progress = max(0.0, car.progress - 0.1)
		car.wait_time = 0.0
