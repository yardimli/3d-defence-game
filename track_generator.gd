extends Node3D

# --- Signals ---
# Emitted when the track is rebuilt so cars can snap to new segments
signal track_regenerated

# --- Config ---
@export var lane_offset: float = 0.2
@export var turn_radius: float = 1.0 # Modifier for the curve radius
@export var track_width: float = 0.01

# NEW: Option to disable track visualization entirely.
@export var visualize_tracks: bool = false
# NEW: Option to use alternating colors for debugging track connections.
@export var use_alternating_colors: bool = true
# The two colors to alternate between for debugging.
@export var debug_color_a: Color = Color("#0000AA")
@export var debug_color_b: Color = Color("#F7DC6F")
# Default track color, used when alternating colors are disabled.
@export var default_track_color: Color = Color(0.6, 0.6, 0.6) # Dark grey/black

# NEW: Traffic Light Configuration
@export var traffic_light_green_duration: float = 2.5
@export var traffic_light_all_red_duration: float = 0.5
# NEW: Variable to randomize start times so intersections don't sync perfectly
@export var randomize_intersection_start_times: bool = true

# --- Dependencies ---
var level_editor: Node3D
var grid_data: Dictionary
var tile_x: float = 2.0
var tile_z: float = 2.0

var paths_container: Node3D

# Store all segments to allow cars to find opposite lanes for U-turns
var track_segments: Array[TrackSegment] =[]

# Local segment definitions (at 0 degrees rotation)
var local_segments = {}

# MODIFIED: Traffic Light Materials and State
var mat_green: StandardMaterial3D
var mat_red: StandardMaterial3D
var mat_off: StandardMaterial3D # NEW: Material for the 'off' state of a light.
var intersections: Array[TrafficIntersection] =[]

# MODIFIED: Class to manage a single intersection's traffic lights
class TrafficIntersection extends RefCounted:
	var grid_pos: Vector2
	var phase: int = 0 # Even numbers = Green for a specific entry, Odd numbers = All Red
	var timer: float = 0.0
	
	# NEW: Store entries dynamically to allow one-by-one green lights
	# Each dictionary contains: {"dir": Vector3, "segments": Array[TrackSegment], "visuals": Array[MeshInstance3D]}
	var entries: Array[Dictionary] =[]

# MODIFIED: TrackSegment now holds its own curve, a list of connected next segments, intersection data, and a color for visualization.
class TrackSegment extends RefCounted:
	var start_pos: Vector3
	var start_dir: Vector3
	var end_pos: Vector3
	var end_dir: Vector3
	var type: String
	var curve: Curve3D
	var next_segments: Array[TrackSegment] =[]
	var is_intersection: bool = false
	var grid_pos: Vector2
	var color: Color = Color.BLACK
	var is_colored: bool = false 
	var is_red_light: bool = false # NEW: Flag to tell cars if they must stop before entering

func initialize(editor: Node3D):
	level_editor = editor
	grid_data = editor.grid_data
	tile_x = editor.tile_x
	tile_z = editor.tile_z
	
	paths_container = Node3D.new()
	add_child(paths_container)
	
	# MODIFIED: Initialize all three materials for the traffic lights.
	mat_green = StandardMaterial3D.new()
	mat_green.albedo_color = Color(0, 1, 0)
	mat_green.emission_enabled = true
	mat_green.emission = Color(0, 1, 0)
	
	mat_red = StandardMaterial3D.new()
	mat_red.albedo_color = Color(1, 0, 0)
	mat_red.emission_enabled = true
	mat_red.emission = Color(1, 0, 0)

	# NEW: Material for when a light is off. It's a dark, non-emissive color.
	mat_off = StandardMaterial3D.new()
	mat_off.albedo_color = Color(0.1, 0.1, 0.1)
	mat_off.emission_enabled = false
	
	_init_local_segments()
	
	if level_editor.road_builder:
		level_editor.road_builder.scene_modified.connect(generate_tracks)
		
	generate_tracks()

# MODIFIED: Process loop to manage traffic light timings sequentially for each direction
func _process(delta: float):
	if intersections.is_empty(): return
	
	for inter in intersections:
		inter.timer += delta
		var phase_changed = false
		var num_entries = inter.entries.size()
		
		if num_entries == 0: continue
		
		# Cycle through phases dynamically based on number of entries
		# Phase 0: Entry 0 Green, Phase 1: All Red, Phase 2: Entry 1 Green, Phase 3: All Red, etc.
		var is_green_phase = (inter.phase % 2 == 0)
		
		if is_green_phase:
			if inter.timer >= traffic_light_green_duration:
				inter.phase = (inter.phase + 1) % (num_entries * 2)
				inter.timer = 0.0
				phase_changed = true
		else:
			if inter.timer >= traffic_light_all_red_duration:
				inter.phase = (inter.phase + 1) % (num_entries * 2)
				inter.timer = 0.0
				phase_changed = true
				
		if phase_changed:
			_apply_intersection_phase(inter)

func _init_local_segments():
	var d = lane_offset
	var hx = tile_x / 2.0
	var hz = tile_z / 2.0
	
	# Define connection points at the edges of a tile
	var P_DOWN_IN = Vector3(d, 0, hz)
	var P_DOWN_OUT = Vector3(-d, 0, hz)
	var P_UP_IN = Vector3(-d, 0, -hz)
	var P_UP_OUT = Vector3(d, 0, -hz)
	var P_LEFT_IN = Vector3(-hx, 0, d)
	var P_LEFT_OUT = Vector3(-hx, 0, -d)
	var P_RIGHT_IN = Vector3(hx, 0, -d)
	var P_RIGHT_OUT = Vector3(hx, 0, d)
	
	# Define directions at the edges
	var D_DOWN_IN = Vector3(0, 0, -1)
	var D_DOWN_OUT = Vector3(0, 0, 1)
	var D_UP_IN = Vector3(0, 0, 1)
	var D_UP_OUT = Vector3(0, 0, -1)
	var D_LEFT_IN = Vector3(1, 0, 0)
	var D_LEFT_OUT = Vector3(-1, 0, 0)
	var D_RIGHT_IN = Vector3(-1, 0, 0)
	var D_RIGHT_OUT = Vector3(1, 0, 0)
	
	# Map internal routing for each road type
	local_segments = {
		"straight":[
			{"start": P_LEFT_IN, "start_dir": D_LEFT_IN, "end": P_RIGHT_OUT, "end_dir": D_RIGHT_OUT, "type": "straight"},
			{"start": P_RIGHT_IN, "start_dir": D_RIGHT_IN, "end": P_LEFT_OUT, "end_dir": D_LEFT_OUT, "type": "straight"}
		],
		"corner":[
			{"start": P_DOWN_IN, "start_dir": D_DOWN_IN, "end": P_LEFT_OUT, "end_dir": D_LEFT_OUT, "type": "curve"},
			{"start": P_LEFT_IN, "start_dir": D_LEFT_IN, "end": P_DOWN_OUT, "end_dir": D_DOWN_OUT, "type": "curve"}
		],
		"end":[
			{"start": P_RIGHT_IN, "start_dir": D_RIGHT_IN, "end": P_RIGHT_OUT, "end_dir": D_RIGHT_OUT, "type": "perpendicular"}
		],
		"intersection":[
			{"start": P_LEFT_IN, "start_dir": D_LEFT_IN, "end": P_RIGHT_OUT, "end_dir": D_RIGHT_OUT, "type": "straight"},
			{"start": P_RIGHT_IN, "start_dir": D_RIGHT_IN, "end": P_LEFT_OUT, "end_dir": D_LEFT_OUT, "type": "straight"},
			{"start": P_DOWN_IN, "start_dir": D_DOWN_IN, "end": P_RIGHT_OUT, "end_dir": D_RIGHT_OUT, "type": "curve"},
			{"start": P_RIGHT_IN, "start_dir": D_RIGHT_IN, "end": P_DOWN_OUT, "end_dir": D_DOWN_OUT, "type": "curve"},
			{"start": P_LEFT_IN, "start_dir": D_LEFT_IN, "end": P_DOWN_OUT, "end_dir": D_DOWN_OUT, "type": "curve"},
			{"start": P_DOWN_IN, "start_dir": D_DOWN_IN, "end": P_LEFT_OUT, "end_dir": D_LEFT_OUT, "type": "curve"}
		],
		"crossroad":[
			{"start": P_LEFT_IN, "start_dir": D_LEFT_IN, "end": P_RIGHT_OUT, "end_dir": D_RIGHT_OUT, "type": "straight"},
			{"start": P_RIGHT_IN, "start_dir": D_RIGHT_IN, "end": P_LEFT_OUT, "end_dir": D_LEFT_OUT, "type": "straight"},
			{"start": P_UP_IN, "start_dir": D_UP_IN, "end": P_DOWN_OUT, "end_dir": D_DOWN_OUT, "type": "straight"},
			{"start": P_DOWN_IN, "start_dir": D_DOWN_IN, "end": P_UP_OUT, "end_dir": D_UP_OUT, "type": "straight"},
			
			{"start": P_DOWN_IN, "start_dir": D_DOWN_IN, "end": P_RIGHT_OUT, "end_dir": D_RIGHT_OUT, "type": "curve"},
			{"start": P_RIGHT_IN, "start_dir": D_RIGHT_IN, "end": P_DOWN_OUT, "end_dir": D_DOWN_OUT, "type": "curve"},
			{"start": P_LEFT_IN, "start_dir": D_LEFT_IN, "end": P_DOWN_OUT, "end_dir": D_DOWN_OUT, "type": "curve"},
			{"start": P_DOWN_IN, "start_dir": D_DOWN_IN, "end": P_LEFT_OUT, "end_dir": D_LEFT_OUT, "type": "curve"},
			{"start": P_UP_IN, "start_dir": D_UP_IN, "end": P_LEFT_OUT, "end_dir": D_LEFT_OUT, "type": "curve"},
			{"start": P_LEFT_IN, "start_dir": D_LEFT_IN, "end": P_UP_OUT, "end_dir": D_UP_OUT, "type": "curve"},
			{"start": P_RIGHT_IN, "start_dir": D_RIGHT_IN, "end": P_UP_OUT, "end_dir": D_UP_OUT, "type": "curve"},
			{"start": P_UP_IN, "start_dir": D_UP_IN, "end": P_RIGHT_OUT, "end_dir": D_RIGHT_OUT, "type": "curve"}
		]
	}

func _get_road_type(model_path: String) -> String:
	if "road-end" in model_path: return "end"
	if "road-straight" in model_path: return "straight"
	if "road-bend" in model_path: return "corner"
	if "road-intersection" in model_path: return "intersection"
	if "road-crossroad" in model_path: return "crossroad"
	return ""

# MODIFIED: Generates the track graph, assigns colors for debugging, and sets up traffic lights.
func generate_tracks():
	track_segments.clear()
	for child in paths_container.get_children():
		child.queue_free()
		
	var all_segments: Array[TrackSegment] =[]
	
	# 1. Collect all segments from road tiles in global space
	for grid_pos in grid_data:
		var models = grid_data[grid_pos]
		for model in models:
			if is_instance_valid(model) and model.get_meta("is_road", false):
				var r_type = _get_road_type(model.get_meta("model_path", ""))
				if local_segments.has(r_type):
					var xform = Transform3D()
					xform = xform.rotated(Vector3.UP, deg_to_rad(model.rotation_degrees.y))
					xform.origin = model.position
					
					for l_seg in local_segments[r_type]:
						var g_seg = TrackSegment.new()
						g_seg.start_pos = xform * l_seg["start"]
						g_seg.start_dir = (xform.basis * l_seg["start_dir"]).normalized()
						g_seg.end_pos = xform * l_seg["end"]
						g_seg.end_dir = (xform.basis * l_seg["end_dir"]).normalized()
						g_seg.type = l_seg["type"]
						
						g_seg.is_intersection = (r_type == "intersection" or r_type == "crossroad")
						g_seg.grid_pos = grid_pos
						
						all_segments.append(g_seg)
						
	# 2. Build curves and connect segments into a graph
	for seg in all_segments:
		seg.curve = _build_curve_for_segment(seg)
		
	for seg in all_segments:
		for other_seg in all_segments:
			if seg != other_seg and seg.end_pos.distance_to(other_seg.start_pos) < 0.05:
				seg.next_segments.append(other_seg)
				
	track_segments = all_segments
	
	# NEW: Setup Traffic Lights for Intersections
	intersections.clear()
	var grid_segments = {}
	for seg in all_segments:
		if seg.is_intersection:
			if not grid_segments.has(seg.grid_pos):
				grid_segments[seg.grid_pos] =[]
			grid_segments[seg.grid_pos].append(seg)
			
	for g_pos in grid_segments:
		var segs = grid_segments[g_pos]
		var intersection = TrafficIntersection.new()
		intersection.grid_pos = g_pos
		
		# MODIFIED: Group segments by their incoming direction to allow sequential green lights
		var entries_by_dir = {}
		var processed_starts =[]
		
		for seg in segs:
			var dir_key = seg.start_dir.snapped(Vector3(0.1, 0.1, 0.1))
			if not entries_by_dir.has(dir_key):
				entries_by_dir[dir_key] = {"segments": [], "visuals":[]}
			
			entries_by_dir[dir_key]["segments"].append(seg)
			
			# Create a visual light only once per entry point
			var start_hash = str(snapped(seg.start_pos.x, 0.01)) + "_" + str(snapped(seg.start_pos.z, 0.01))
			if not processed_starts.has(start_hash):
				processed_starts.append(start_hash)
				var light_mesh = _create_traffic_light(seg.start_pos, seg.start_dir)
				entries_by_dir[dir_key]["visuals"].append(light_mesh)
				
		# Add all grouped entries to the intersection
		for dir_key in entries_by_dir:
			intersection.entries.append(entries_by_dir[dir_key])
		
		# NEW: Randomize start phases and timers so they don't all sync up
		if randomize_intersection_start_times:
			var num_entries = intersection.entries.size()
			if num_entries > 0:
				intersection.phase = randi() % (num_entries * 2)
				if intersection.phase % 2 == 0:
					intersection.timer = randf_range(0.0, traffic_light_green_duration)
				else:
					intersection.timer = randf_range(0.0, traffic_light_all_red_duration)
					
		intersections.append(intersection)
		_apply_intersection_phase(intersection) # Initialize the state
	
	# If visualization is turned off, stop here.
	if not visualize_tracks:
		emit_signal("track_regenerated")
		return
		
	if use_alternating_colors:
		for seg in all_segments:
			if not seg.is_colored:
				seg.color = debug_color_a 
				seg.is_colored = true
			var neighbor_color = debug_color_b if seg.color == debug_color_a else debug_color_a
			for next_seg in seg.next_segments:
				if not next_seg.is_colored: 
					next_seg.color = neighbor_color
					next_seg.is_colored = true
	else:
		for seg in all_segments:
			seg.color = default_track_color
			
	# 3. Draw the visual track mesh efficiently using a single SurfaceTool
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true 
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	st.set_material(mat)
	
	for seg in all_segments:
		_add_curve_to_surfacetool(st, seg.curve, seg.color)
		
	var mesh = st.commit()
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	paths_container.add_child(mi)
	
	emit_signal("track_regenerated")

# MODIFIED: Helper to apply the current red/green state to the new, detailed traffic lights.
func _apply_intersection_phase(inter: TrafficIntersection):
	var active_entry_index = -1
	
	# Determine which entry is currently green (if any)
	if inter.phase % 2 == 0:
		active_entry_index = inter.phase / 2
		
	for i in range(inter.entries.size()):
		var entry = inter.entries[i]
		var is_green = (i == active_entry_index)
		
		# Update the state for the track segments (for car logic)
		for seg in entry["segments"]:
			seg.is_red_light = not is_green
			
		# MODIFIED: Update the visual state of the new two-light traffic signals.
		for housing in entry["visuals"]:
			if is_instance_valid(housing):
				# Find the named child nodes for the red and green lights.
				var red_light: MeshInstance3D = housing.get_node_or_null("LightRed")
				var green_light: MeshInstance3D = housing.get_node_or_null("LightGreen")
				
				if red_light and green_light:
					# Apply the correct material based on the light's state.
					if is_green:
						green_light.material_override = mat_green
						red_light.material_override = mat_off
					else: # Light is red
						green_light.material_override = mat_off
						red_light.material_override = mat_red

# MODIFIED: This function now builds a more detailed traffic light and rotates it correctly.
func _create_traffic_light(pos: Vector3, dir: Vector3) -> MeshInstance3D:
	# Create the main pole for the traffic light.
	var pole = Node3D.new() # MODIFIED: Use a generic Node3D as the parent to avoid mesh orientation issues.
	
	var pole_mesh_instance = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = 0.4
	pole_mesh_instance.mesh = cyl
	
	var pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.2, 0.2, 0.2)
	pole_mesh_instance.material_override = pole_mat
	pole.add_child(pole_mesh_instance) # Add mesh as a child of the main Node3D.
	
	# Position the pole to the right of the entry lane.
	var right = dir.cross(Vector3.UP).normalized()
	pole.position = pos + right * 0.25 + Vector3(0, 0.2, 0)
	
	# MODIFIED: Replace look_at with a more robust basis construction to set rotation.
	# The light should face the incoming cars, which is the opposite of the track direction 'dir'.
	pole.transform.basis = Basis.looking_at(-dir)
	
	paths_container.add_child(pole)
	
	# Create the housing/frame for the lights.
	var light_housing = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.08, 0.15, 0.08)
	light_housing.mesh = box
	# MODIFIED: Adjust position to be relative to the new Node3D parent.
	light_housing.position = Vector3(0, 0.2, 0)
	light_housing.material_override = pole_mat # Use the same dark material as the pole.
	pole.add_child(light_housing)

	# NEW: Create two distinct lights (red and green) inside the housing.
	var light_shape = SphereMesh.new()
	light_shape.radius = 0.025
	light_shape.height = 0.05
	
	# Create the red light (top).
	var light_red = MeshInstance3D.new()
	light_red.name = "LightRed" # Assign a unique name to find it later.
	light_red.mesh = light_shape
	# Position it at the top, slightly forward so it's visible from the front.
	light_red.position = Vector3(0, 0.035, -0.04)
	light_housing.add_child(light_red)
	
	# Create the green light (bottom).
	var light_green = MeshInstance3D.new()
	light_green.name = "LightGreen" # Assign a unique name.
	light_green.mesh = light_shape
	# Position it at the bottom, slightly forward.
	light_green.position = Vector3(0, -0.035, -0.04)
	light_housing.add_child(light_green)
	
	# Return the housing, which contains the individual lights as children.
	return light_housing

func _build_curve_for_segment(seg: TrackSegment) -> Curve3D:
	var curve = Curve3D.new()
	
	if seg.type == "straight":
		curve.add_point(seg.start_pos)
		curve.add_point(seg.end_pos)
		
	elif seg.type == "curve":
		var I = Vector3.ZERO
		if abs(seg.start_dir.x) > 0.5:
			I = Vector3(seg.end_pos.x, 0, seg.start_pos.z)
		else:
			I = Vector3(seg.start_pos.x, 0, seg.end_pos.z)
			
		var R = seg.start_pos.distance_to(I)
		var cp_dist = R * 0.5522847 * turn_radius
		
		var out_cp = seg.start_dir * cp_dist
		var in_cp = -seg.end_dir * cp_dist
		
		curve.add_point(seg.start_pos, Vector3.ZERO, out_cp)
		curve.add_point(seg.end_pos, in_cp, Vector3.ZERO)
		
	elif seg.type == "perpendicular":
		var p1 = seg.start_pos
		var p4 = seg.end_pos
		var p2 = p1 + seg.start_dir * (tile_x / 2.0)
		var p3 = p4 - seg.end_dir * (tile_x / 2.0)
		
		curve.add_point(p1)
		curve.add_point(p2)
		curve.add_point(p3)
		curve.add_point(p4)
		
	return curve

func _add_curve_to_surfacetool(st: SurfaceTool, curve: Curve3D, color: Color):
	var points = curve.tessellate(5, 0.1)
	if points.size() < 2: return
	
	var up = Vector3.UP
	for i in range(points.size() - 1):
		var p1 = points[i]
		var p2 = points[i+1]
		var dir = (p2 - p1).normalized()
		if dir == Vector3.ZERO: continue
		var left = dir.cross(up).normalized() * (track_width / 2.0)
		
		var v1 = p1 + left + Vector3(0, 0.05, 0)
		var v2 = p1 - left + Vector3(0, 0.05, 0)
		var v3 = p2 + left + Vector3(0, 0.05, 0)
		var v4 = p2 - left + Vector3(0, 0.05, 0)
		
		st.set_color(color)
		st.set_normal(up)
		st.add_vertex(v1)
		st.set_color(color)
		st.set_normal(up)
		st.add_vertex(v2)
		st.set_color(color)
		st.set_normal(up)
		st.add_vertex(v3)
		
		st.set_color(color)
		st.set_normal(up)
		st.add_vertex(v2)
		st.set_color(color)
		st.set_normal(up)
		st.add_vertex(v4)
		st.set_color(color)
		st.set_normal(up)
		st.add_vertex(v3)
