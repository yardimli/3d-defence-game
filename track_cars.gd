extends Node3D

# --- Config ---
@export var vehicle_speed: float = 2.0
@export var vehicle_spacing: float = 0.75

# NEW: Variable to control how far from the red light the cars should stop
@export var stop_distance_from_light: float = 0.5

# Global flag to draw debug bounding boxes for all spawned cars.
# This can be enabled from the Godot Editor's Inspector panel.
@export var draw_debug_bounding_boxes: bool = false

# Array to configure different vehicle models.
# Each dictionary includes a "bounding_box_size" to define the collision area.
var vehicle_models =[
	{
		"path": "res://models/car-kit/ambulance.glb",
		"scale": 0.15,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) 
	},
	{
		"path": "res://models/car-kit/firetruck.glb",
		"scale": 0.15,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) 
	},
	{
		"path": "res://models/car-kit/suv.glb",
		"scale": 0.15,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) 
	},
	{
		"path": "res://models/car-kit/delivery.glb",
		"scale": 0.15,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) 
	},
	{
		"path": "res://models/car-kit/delivery-flat.glb",
		"scale": 0.15,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) 
	},
	{
		"path": "res://models/car-kit/garbage-truck.glb",
		"scale": 0.15,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) 
	},
	{
		"path": "res://models/car-kit/hatchback-sports.glb",
		"scale": 0.15,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) 
	},
	{
		"path": "res://models/car-kit/police.glb",
		"scale": 0.15,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) 
	},
	{
		"path": "res://models/car-kit/sedan.glb",
		"scale": 0.15,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) 
	},
	{
		"path": "res://models/car-kit/taxi.glb",
		"scale": 0.15,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) 
	},
	{
		"path": "res://models/car-kit/truck-flat.glb",
		"scale": 0.15,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) 
	},
	{
		"path": "res://models/car-kit/truck.glb",
		"scale": 0.15,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) 
	},
	{
		"path": "res://models/car-kit/van.glb",
		"scale": 0.15,
		"initial_rotation_degrees": Vector3(0, 180, 0),
		"bounding_box_size": Vector3(1.2, 2, 3.5) 
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
		"collision_shape": vehicle_instance_data["shape"], # MODIFIED: Store a direct reference to the collision shape
		"config": vehicle_instance_data["config"],
		"segment": seg,
		"progress": progress,
		"base_speed": vehicle_speed * randf_range(0.8, 1.2),
		"current_speed": 0.0,
		"state": "driving",
		"wait_time": 0.0, # Used for pausing after a collision
		"uturn_timer": 0.0,
		"uturn_start_pos": Vector3.ZERO,
		"uturn_start_basis": Basis(),
		"uturn_target_seg": null,
		"uturn_target_offset": 0.0,
		"chosen_next_segment": null
		# MODIFIED: Removed overtake state variables
	}
	
	active_vehicles.append(car_data)
	_pick_next_segment(car_data)

func _create_vehicle_instance() -> Dictionary:
	if vehicle_models.is_empty():
		return {}

	var car_config = vehicle_models.pick_random()
	
	var car_scene = load(car_config.path)
	if not car_scene:
		printerr("Failed to load car scene: ", car_config.path)
		return {}
		
	var physics_body = CharacterBody3D.new()
	physics_body.set_meta("is_car", true)
	
	var car_visual = car_scene.instantiate()
	var scale_factor = car_config.get("scale", 0.2)
	car_visual.scale = Vector3.ONE * scale_factor
	car_visual.rotation_degrees = car_config.get("initial_rotation_degrees", Vector3.ZERO)
	physics_body.add_child(car_visual)
	
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	
	var bbox_size = car_config.get("bounding_box_size", Vector3(0.4, 0.4, 0.6)) * scale_factor
	box.size = bbox_size
	
	shape.shape = box
	shape.position.y = bbox_size.y / 2.0 
	physics_body.add_child(shape)
	
	if draw_debug_bounding_boxes:
		var debug_mesh_instance = MeshInstance3D.new()
		var debug_mesh = BoxMesh.new()
		debug_mesh.size = bbox_size 
		debug_mesh_instance.mesh = debug_mesh
		
		var debug_material = StandardMaterial3D.new()
		debug_material.albedo_color = Color(1.0, 0.0, 0.0, 0.4) 
		debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		debug_mesh_instance.material_override = debug_material
		
		debug_mesh_instance.position.y = bbox_size.y / 2.0
		physics_body.add_child(debug_mesh_instance)
		
	return {"root": physics_body, "config": car_config, "shape": shape} # MODIFIED: Return the collision shape node as well

func _unhandled_input(event):
	if not camera: return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var space_state = get_world_3d().direct_space_state
			var mouse_pos = event.position
			var origin = camera.project_ray_origin(mouse_pos)
			var end = origin + camera.project_ray_normal(mouse_pos) * 1000.0
			var query = PhysicsRayQueryParameters3D.create(origin, end)
			
			query.collide_with_areas = false 
			query.collide_with_bodies = true
			var result = space_state.intersect_ray(query)
			
			if result and result.collider.has_meta("is_car"):
				var car_node = result.collider 
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
					# MODIFIED: Removed overtake state reset
					_pick_next_segment(dragged_car)
				else:
					dragged_car.node.global_position = drag_original_pos
					dragged_car.segment = drag_original_segment
					dragged_car.progress = drag_original_progress
					dragged_car.state = "driving"
					# MODIFIED: Removed overtake state reset
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
			# MODIFIED: Removed overtake state reset
			_pick_next_segment(car)
		else:
			car.segment = null

func _physics_process(delta: float):
	for i in range(active_vehicles.size()):
		var car = active_vehicles[i]
		
		# --- State Handling: Dragged & U-turning ---
		if car.state == "dragged":
			continue
		
		if car.state == "uturning":
			car.uturn_timer -= delta
			var t = 1.0 - max(car.uturn_timer, 0.0)
			
			var target_track_xform = car.uturn_target_seg.curve.sample_baked_with_rotation(car.uturn_target_offset, false, false)
			var target_basis = target_track_xform.basis
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
		
		# --- MODIFIED: Intersection Collision Handling ---
		# When a car is on an intersection segment, disable its collision shape
		# to prevent it from colliding with other cars. Re-enable it otherwise.
		if is_instance_valid(car.collision_shape):
			car.collision_shape.disabled = seg.is_intersection
		# --- END MODIFIED ---

		# MODIFIED: Removed Overtake Logic block from here

		# Handle wait time after collisions.
		if car.wait_time > 0.0:
			car.wait_time -= delta
			car.current_speed = move_toward(car.current_speed, 0.0, delta * 5.0)
		else:
			# MODIFIED: Adaptive Cruise Control (ACC) to maintain vehicle_spacing
			var forward = -car.node.global_transform.basis.z
			var target_speed = car.base_speed
			var car_ahead_detected = false
			
			for other_car in active_vehicles:
				if other_car == car: continue
				if other_car.state == "dragged": continue
				
				var to_other = other_car.node.global_position - car.node.global_position
				var dist = to_other.length()
				
				# Only check cars within a reasonable detection radius
				if dist < vehicle_spacing + 3.0:
					var dir_to_other = to_other / dist
					# Check if the other car is in front (dot product > 0.7 means ~45 degrees)
					if forward.dot(dir_to_other) > 0.7:
						# NEW: Ensure the other car is facing roughly the same direction.
						# This prevents detecting cars in the opposite lane coming towards us.
						var other_forward = -other_car.node.global_transform.basis.z
						if forward.dot(other_forward) > 0.5:
							# Check lateral distance to ensure they are in the same lane/path
							var lateral_dist = abs(car.node.global_transform.basis.x.dot(to_other))
							if lateral_dist < 0.6:
								car_ahead_detected = true
								var gap = dist - vehicle_spacing
								if gap <= 0.0:
									# Too close, force stop to maintain spacing
									target_speed = 0.0
								else:
									# Smoothly reduce speed as gap closes to match the car ahead
									var allowed_speed = gap * 1.5
									target_speed = min(target_speed, other_car.current_speed + allowed_speed)
			
			if car_ahead_detected:
				# Brake or adjust speed to maintain spacing
				car.current_speed = move_toward(car.current_speed, target_speed, delta * 10.0)
			else:
				# Normal acceleration
				car.current_speed = move_toward(car.current_speed, car.base_speed, delta * 5.0)
		
		var step = car.current_speed * delta
		var projected_progress = car.progress + step

		# --- Segment Transition Logic ---
		var curve_len = seg.curve.get_baked_length()
		
		# MODIFIED: Check for red lights and stop before the intersection based on stop_distance_from_light
		var next_seg = car.chosen_next_segment
		if next_seg == null and seg.next_segments.size() > 0:
			next_seg = seg.next_segments.pick_random()
			car.chosen_next_segment = next_seg
			
		if next_seg != null and next_seg.is_red_light:
			var stop_point = max(0.0, curve_len - stop_distance_from_light)
			if projected_progress > stop_point and car.progress < curve_len:
				# MODIFIED: Clamp projected_progress to stop_point, or to current progress if already past it.
				# This prevents creeping forward due to floating point inaccuracies.
				projected_progress = min(projected_progress, max(car.progress, stop_point))
				car.current_speed = 0.0

		while projected_progress > curve_len:
			if curve_len <= 0.001: break
			
			next_seg = car.chosen_next_segment
			if next_seg != null:
				projected_progress -= curve_len
				seg = next_seg
				car.segment = seg
				curve_len = seg.curve.get_baked_length()
				_pick_next_segment(car)
			else:
				# Reached a dead end, force a U-turn.
				projected_progress = curve_len
				_start_uturn(car)
				break
				
		# Handle bouncing backward past the start of the current segment.
		if projected_progress < 0.0:
			projected_progress = 0.0
			car.current_speed = 0.0
		
		# --- Physics Movement & Visual Update ---
		if car.state == "driving":
			var target_transform = seg.curve.sample_baked_with_rotation(projected_progress, false, false)
			var target_origin = target_transform.origin
			target_origin.y += 0.05
			
			# MODIFIED: Removed overtake lateral offset application
			
			var motion = target_origin - car.node.global_position
			var collision = car.node.move_and_collide(motion)
			
			if collision:
				# MODIFIED: Only trigger the crash response if the collision is in front of the car.
				# This prevents the car from stopping when hit from behind or the side on corners.
				var forward = -car.node.global_transform.basis.z
				var hit_normal = collision.get_normal()
				
				# If the dot product is negative, the surface normal is facing the car (frontal crash)
				if forward.dot(hit_normal) < -0.2:
					# MODIFIED: Reverted to original collision fallback, removed overtake behavior
					car.current_speed = -car.base_speed * 0.4
					car.wait_time = randf_range(0.25, 0.75) 
							
			# Sync progress to actual physical position.
			car.progress = seg.curve.get_closest_offset(car.node.global_position)
			
			# Update rotation to align the CharacterBody3D with the track.
			var actual_transform = seg.curve.sample_baked_with_rotation(car.progress, false, false)
			car.node.global_transform.basis = actual_transform.basis

# MODIFIED: This function now checks for cars on upcoming segments before choosing.
func _pick_next_segment(car: Dictionary):
	# If there's no current segment or no available next paths, clear the choice and exit.
	if not car.segment or car.segment.next_segments.is_empty():
		car.chosen_next_segment = null
		return

	var next_options: Array = car.segment.next_segments
	
	# If there's only one path, there's no choice to make.
	if next_options.size() == 1:
		car.chosen_next_segment = next_options[0]
		return
		
	# NEW: Find all segments that are not occupied by a car near the entrance.
	var clear_segments: Array = []
	for potential_seg in next_options:
		var is_occupied = false
		for other_car in active_vehicles:
			# Check if another car is on the potential segment and is close to the start.
			# The threshold (2.0) is roughly a car's length to prevent turning into an occupied space.
			if other_car.segment == potential_seg and other_car.progress < 2.0:
				is_occupied = true
				break # Found a car, no need to check others for this segment.
		
		# If the segment was not occupied, add it to the list of clear choices.
		if not is_occupied:
			clear_segments.append(potential_seg)
			
	# NEW: Prioritize choosing from clear segments.
	if not clear_segments.is_empty():
		# If there are clear paths, pick a random one from them.
		car.chosen_next_segment = clear_segments.pick_random()
	else:
		# MODIFIED: If all paths are occupied, fall back to picking any random path.
		car.chosen_next_segment = next_options.pick_random()


func _start_uturn(car: Dictionary):
	var min_dist = INF
	var best_seg = null
	var best_offset = 0.0
	var car_fwd = -car.node.global_transform.basis.z
	
	for seg in track_generator.track_segments:
		var closest_pt = seg.curve.get_closest_point(car.node.global_position)
		var dist = closest_pt.distance_to(car.node.global_position)
		
		if dist < 1.0: 
			var offset = seg.curve.get_closest_offset(car.node.global_position)
			var xform = seg.curve.sample_baked_with_rotation(offset, false, false)
			var seg_fwd = -xform.basis.z
			
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
		# MODIFIED: Removed overtake state reset
	else:
		car.node.rotate_y(PI)
		car.progress = max(0.0, car.progress - 0.1)
		car.wait_time = 0.0
