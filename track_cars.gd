extends Node3D

# --- Config ---
@export var vehicle_speed: float = 2.0

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

# NEW: Initialize called by level editor
func initialize(editor: Node3D, track_gen: Node3D, cam: Camera3D):
	level_editor = editor
	track_generator = track_gen
	camera = cam
	
	# Listen for track regenerations to snap cars to new segments
	track_generator.track_regenerated.connect(on_track_regenerated)

# NEW: Spawns a car at a random track location
func spawn_car():
	if track_generator.track_segments.is_empty():
		print("No tracks available to spawn a car.")
		return
		
	var seg = track_generator.track_segments.pick_random()
	var progress = randf() * seg.curve.get_baked_length()
	
	var sedan_data = _create_sedan_mesh()
	add_child(sedan_data["root"])
	
	var car_data = {
		"node": sedan_data["root"],
		"wheels": sedan_data["wheels"],
		"segment": seg,
		"progress": progress,
		"base_speed": vehicle_speed * randf_range(0.8, 1.2),
		"current_speed": 0.0,
		"state": "driving", # driving, uturning, dragged
		"wait_time": 0.0,
		"uturn_timer": 0.0,
		"uturn_start_pos": Vector3.ZERO,
		"uturn_start_basis": Basis(),
		"uturn_target_seg": null,
		"uturn_target_offset": 0.0,
		"chosen_next_segment": null # NEW: Pre-selected next path to avoid collisions
	}
	
	active_vehicles.append(car_data)
	_pick_next_segment(car_data) # NEW: Pick the initial next segment avoiding occupied paths

# NEW: Create sedan mesh with collision area for dragging
func _create_sedan_mesh() -> Dictionary:
	var car_root = Node3D.new()
	
	# Randomize car color
	var color = Color(randf_range(0.2, 1.0), randf_range(0.2, 1.0), randf_range(0.2, 1.0))
	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = color
	
	var black_mat = StandardMaterial3D.new()
	black_mat.albedo_color = Color(0.1, 0.1, 0.1)
	
	var glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.7)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	# Lower Body
	var body = MeshInstance3D.new()
	var body_mesh = BoxMesh.new()
	body_mesh.size = Vector3(0.25, 0.1, 0.5)
	body.mesh = body_mesh
	body.material_override = body_mat
	body.position.y = 0.11 # Lifted slightly above wheels
	car_root.add_child(body)
	
	# Cabin (Glass area)
	var cabin = MeshInstance3D.new()
	var cabin_mesh = BoxMesh.new()
	cabin_mesh.size = Vector3(0.2, 0.12, 0.25)
	cabin.mesh = cabin_mesh
	cabin.material_override = glass_mat
	cabin.position = Vector3(0, 0.22, -0.05)
	car_root.add_child(cabin)
	
	# Wheels setup
	var wheels =[]
	var wheel_mesh = CylinderMesh.new()
	wheel_mesh.top_radius = 0.06
	wheel_mesh.bottom_radius = 0.06
	wheel_mesh.height = 0.04
	
	var wheel_positions =[
		Vector3(-0.14, 0.06, -0.15), # FL
		Vector3(0.14, 0.06, -0.15),  # FR
		Vector3(-0.14, 0.06, 0.15),  # RL
		Vector3(0.14, 0.06, 0.15)    # RR
	]
	
	for pos in wheel_positions:
		var pivot = Node3D.new()
		pivot.position = pos
		car_root.add_child(pivot)
		
		var w_mesh = MeshInstance3D.new()
		w_mesh.mesh = wheel_mesh
		w_mesh.material_override = black_mat
		w_mesh.rotation_degrees.z = 90 # Align cylinder to roll on Z axis
		pivot.add_child(w_mesh)
		
		wheels.append(pivot)
		
	# NEW: Add Area3D for mouse picking/dragging
	var area = Area3D.new()
	area.set_meta("is_car", true)
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.6) # Generous hit box
	shape.shape = box
	area.position.y = 0.2
	area.add_child(shape)
	car_root.add_child(area)
		
	return {"root": car_root, "wheels": wheels}

# NEW: Handle drag and drop input
func _unhandled_input(event):
	if not camera: return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Raycast to find car
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
						
						# Lift car slightly while dragging
						car.node.position.y += 0.5
						get_viewport().set_input_as_handled()
						break
		else:
			if dragged_car != null:
				# Drop logic
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
					# Snap to new track
					dragged_car.segment = closest_seg
					dragged_car.progress = best_progress
					dragged_car.state = "driving"
					_pick_next_segment(dragged_car) # NEW: Pick next path after drop
				else:
					# Revert to original position if dropped too far from any track
					dragged_car.node.global_position = drag_original_pos
					dragged_car.segment = drag_original_segment
					dragged_car.progress = drag_original_progress
					dragged_car.state = "driving"
					_pick_next_segment(dragged_car) # NEW: Re-evaluate next path

				dragged_car = null
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and dragged_car != null:
		# Move car along ground plane
		var mouse_pos = event.position
		var origin = camera.project_ray_origin(mouse_pos)
		var dir = camera.project_ray_normal(mouse_pos)
		if dir.y < 0:
			var t = -origin.y / dir.y
			var intersection = origin + dir * t
			# Keep the lifted Y position
			intersection.y = 0.5
			dragged_car.node.global_position = intersection
		get_viewport().set_input_as_handled()

# NEW: Snap cars to tracks if the track is rebuilt
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
			_pick_next_segment(car) # NEW: Pick next path after snapping
		else:
			car.segment = null

# MODIFIED: Process function with advanced traffic logic moved from track_generator
func _process(delta: float):
	for i in range(active_vehicles.size()):
		var car = active_vehicles[i]
		
		# Skip processing if being dragged
		if car.state == "dragged":
			continue
		
		# Handle U-Turn animation state
		if car.state == "uturning":
			car.uturn_timer -= delta
			var t = 1.0 - max(car.uturn_timer, 0.0)
			
			var target_xform = car.uturn_target_seg.curve.sample_baked_with_rotation(car.uturn_target_offset, false, false)
			target_xform.origin.y += 0.05 # Track offset
			
			car.node.global_position = car.uturn_start_pos.lerp(target_xform.origin, t)
			car.node.global_transform.basis = car.uturn_start_basis.slerp(target_xform.basis, t)
			
			# Animate wheels during U-turn
			_animate_wheels(car, delta, 0.0)
			
			if car.uturn_timer <= 0:
				car.segment = car.uturn_target_seg
				car.progress = car.uturn_target_offset
				car.state = "driving"
				car.current_speed = 0.0
				_pick_next_segment(car) # NEW: Pick next path after U-turn completes
			continue

		var seg = car.segment
		if not seg or not seg.curve: continue
		
		var car_pos = car.node.global_position
		var car_fwd = -car.node.global_transform.basis.z.normalized()
		var target_speed = car.base_speed
		
		# NEW: Intersection yielding logic
		var curve_len = seg.curve.get_baked_length()
		var dist_to_end = curve_len - car.progress
		var approaching_new_intersection = false
		var target_intersection_pos = Vector2.INF

		if car.chosen_next_segment and car.chosen_next_segment.is_intersection:
			if not car.segment.is_intersection or car.segment.grid_pos != car.chosen_next_segment.grid_pos:
				approaching_new_intersection = true
				target_intersection_pos = car.chosen_next_segment.grid_pos

		if approaching_new_intersection and dist_to_end < 0.6:
			var should_yield = false
			for j in range(active_vehicles.size()):
				if i == j: continue
				var other = active_vehicles[j]
				if other.state == "dragged" or other.state == "uturning": continue

				# 1. Car already in the target intersection
				if other.segment and other.segment.is_intersection and other.segment.grid_pos == target_intersection_pos:
					should_yield = true
					break

				# 2. Car approaching the same target intersection
				if other.chosen_next_segment and other.chosen_next_segment.is_intersection and other.chosen_next_segment.grid_pos == target_intersection_pos:
					var other_is_approaching = not other.segment.is_intersection or other.segment.grid_pos != target_intersection_pos
					if other_is_approaching:
						# Find out who is closer to the intersection
						var other_dist = 0.0
						if other.segment and other.segment.curve:
							other_dist = other.segment.curve.get_baked_length() - other.progress
						
						if other_dist < dist_to_end - 0.1:
							should_yield = true
							break
						# Tie-breaker to prevent deadlocks when arriving simultaneously
						elif abs(other_dist - dist_to_end) <= 0.1 and j < i:
							should_yield = true
							break

			if should_yield:
				target_speed = 0.0
		
		# Traffic Logic - Check interactions with other cars
		for j in range(active_vehicles.size()):
			if i == j: continue
			var other = active_vehicles[j]
			if other.state == "dragged": continue
			
			var other_pos = other.node.global_position
			var dist = car_pos.distance_to(other_pos)
			
			if dist < 0.8: # Interaction radius
				var dir_to_other = (other_pos - car_pos).normalized()
				var dot_fwd = car_fwd.dot(dir_to_other)
				
				if dot_fwd > 0.6: # Other car is in front of us
					var other_fwd = -other.node.global_transform.basis.z.normalized()
					var dot_facing = car_fwd.dot(other_fwd)
					
					# Calculate lateral distance to ignore cars in opposite lanes
					var right = car.node.global_transform.basis.x.normalized()
					var lateral_dist = abs((other_pos - car_pos).dot(right))
					
					if dot_facing < -0.8: # Head-to-head collision course
						# Only trigger U-turn if they are actually in the same lane (lateral distance is small)
						if lateral_dist < 0.25: 
							if car.state != "uturning" and other.state != "uturning":
								if i > j: # Arbitrary priority based on index
									_start_uturn(car)
								else:
									target_speed = 0.0 # Wait for the other to U-turn
					elif dot_facing > 0.5: # Moving in the same direction
						# Only rear-end if they are in the same lane
						if lateral_dist < 0.25:
							if dist < 0.35:
								target_speed = 0.0 # Stop to avoid rear-ending
							else:
								# Slow down to match speed
								target_speed = min(target_speed, other.current_speed * 0.8)
					else: # Crossing / Intersection (Fallback if yielding logic missed something)
						# Yield to the car with the lower index to prevent deadlocks
						if dist < 0.45 and i > j:
							target_speed = 0.0

		# Smoothly adjust current speed
		car.current_speed = lerp(car.current_speed, target_speed, delta * 4.0)
		
		# Deadlock resolution: if stopped for too long, force a U-turn
		if car.current_speed < 0.1 and target_speed == 0.0:
			car.wait_time += delta
			if car.wait_time > 3.0:
				_start_uturn(car)
		else:
			car.wait_time = 0.0

		# Move car along the curve
		car.progress += car.current_speed * delta
		
		while car.progress > curve_len:
			if curve_len <= 0.001: break
				
			if car.chosen_next_segment != null:
				car.progress -= curve_len
				seg = car.chosen_next_segment
				car.segment = seg
				curve_len = seg.curve.get_baked_length()
				_pick_next_segment(car) # NEW: Pick the next one
			elif seg.next_segments.size() > 0:
				car.progress -= curve_len
				seg = seg.next_segments.pick_random()
				car.segment = seg
				curve_len = seg.curve.get_baked_length()
				_pick_next_segment(car) # NEW: Pick the next one
			else:
				# Dead end reached, automatically U-turn
				car.progress = curve_len
				_start_uturn(car)
				break
		
		if car.state == "driving":
			var transform = seg.curve.sample_baked_with_rotation(car.progress, false, false)
			transform.origin.y += 0.05 # Sit on top of the track
			car.node.global_transform = transform
			
			_animate_wheels(car, delta, car.current_speed)

# NEW: Helper to pick the next segment while avoiding occupied paths
func _pick_next_segment(car: Dictionary):
	if not car.segment or car.segment.next_segments.is_empty():
		car.chosen_next_segment = null
		return

	var valid_segments =[]
	for next_seg in car.segment.next_segments:
		var has_car = false
		for other in active_vehicles:
			if other == car: continue
			if other.state == "dragged": continue
			
			# Check if another car is currently on this segment
			if other.segment == next_seg:
				has_car = true
				break
				
			# Check if another car is targeting this segment and is close to it
			if other.chosen_next_segment == next_seg:
				var other_dist = 0.0
				if other.segment and other.segment.curve:
					other_dist = other.segment.curve.get_baked_length() - other.progress
				if other_dist < 1.0: # Only care if they are relatively close
					has_car = true
					break
					
		if not has_car:
			valid_segments.append(next_seg)

	if valid_segments.size() > 0:
		car.chosen_next_segment = valid_segments.pick_random()
	else:
		# Fallback if all paths are occupied
		car.chosen_next_segment = car.segment.next_segments.pick_random()

# Animates the sedan's wheels (steering and rolling)
func _animate_wheels(car: Dictionary, delta: float, speed: float):
	# Steering logic (Front wheels only)
	var lookahead_offset = min(car.progress + 0.2, car.segment.curve.get_baked_length())
	var lookahead_xform = car.segment.curve.sample_baked_with_rotation(lookahead_offset, false, false)
	var desired_fwd = -lookahead_xform.basis.z
	var right = car.node.global_transform.basis.x
	
	var steer_angle = right.dot(desired_fwd) * 1.2
	steer_angle = clamp(steer_angle, -0.6, 0.6)
	
	# Wheels array:[FL, FR, RL, RR]
	car.wheels[0].rotation.y = steer_angle
	car.wheels[1].rotation.y = steer_angle
	
	# Rolling logic (All wheels)
	var roll_amount = (speed * delta) / 0.06 # 0.06 is the wheel radius
	for w in car.wheels:
		w.rotate_x(-roll_amount)

# Initiates a U-turn by finding the closest segment going in the opposite direction
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
			
			if seg_fwd.dot(car_fwd) < -0.5: # Segment goes in the opposite direction
				if dist < min_dist:
					min_dist = dist
					best_seg = seg
					best_offset = offset
					
	if best_seg:
		car.state = "uturning"
		car.uturn_timer = 1.0 # Takes 1 second to U-turn
		car.uturn_start_pos = car.node.global_position
		car.uturn_start_basis = car.node.global_transform.basis
		car.uturn_target_seg = best_seg
		car.uturn_target_offset = best_offset
		car.wait_time = 0.0
	else:
		# If no opposite lane is found (e.g. single lane dead end), just flip in place
		car.node.rotate_y(PI)
		car.progress = max(0.0, car.progress - 0.1)
		car.wait_time = 0.0
