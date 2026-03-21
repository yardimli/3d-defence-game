extends Node3D

# --- Config ---
@export var lane_offset: float = 0.4
@export var turn_radius: float = 1.0 # Modifier for the curve radius
@export var track_color: Color = Color(0.1, 0.1, 0.1) # Dark grey/black
@export var track_width: float = 0.1

# NEW: Car placeholder settings
@export var tiles_per_sphere: int = 5
@export var sphere_size: float = 0.4
@export var sphere_color: Color = Color(1.0, 0.2, 0.2) # Red
@export var sphere_speed: float = 3.0

# --- Dependencies ---
var level_editor: Node3D
var grid_data: Dictionary
var tile_x: float = 2.0
var tile_z: float = 2.0

var paths_container: Node3D

# NEW: State for moving spheres
var active_path_followers: Array[PathFollow3D] =[]

# Local segment definitions (at 0 degrees rotation)
var local_segments = {}

class TrackSegment extends RefCounted:
	var start_pos: Vector3
	var start_dir: Vector3
	var end_pos: Vector3
	var end_dir: Vector3
	var type: String
	var used: bool = false

func initialize(editor: Node3D):
	level_editor = editor
	grid_data = editor.grid_data
	tile_x = editor.tile_x
	tile_z = editor.tile_z
	
	paths_container = Node3D.new()
	add_child(paths_container)
	
	_init_local_segments()
	
	if level_editor.road_builder:
		level_editor.road_builder.scene_modified.connect(generate_tracks)
		
	generate_tracks()

# NEW: Process function to move the spheres along the tracks
func _process(delta: float):
	for follower in active_path_followers:
		if is_instance_valid(follower):
			follower.progress += sphere_speed * delta

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
			# MODIFIED: Corrected the corner to connect DOWN and LEFT at 0 degrees rotation
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

func generate_tracks():
	# NEW: Clear old followers before regenerating
	active_path_followers.clear()
	
	for child in paths_container.get_children():
		child.queue_free()
		
	var all_segments =[]
	
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
						all_segments.append(g_seg)
						
	# 2. Stitch segments into continuous loops
	var loops =[]
	for seg in all_segments:
		if seg.used: continue
		
		var curve = Curve3D.new()
		var current_seg = seg
		
		_add_segment_to_curve(curve, current_seg, true)
		current_seg.used = true
		
		while true:
			var next_seg = _find_next_segment(current_seg.end_pos, all_segments, seg)
			if next_seg == null or next_seg.used:
				break
				
			_add_segment_to_curve(curve, next_seg, false)
			next_seg.used = true
			current_seg = next_seg
			
		loops.append(curve)
		
	# 3. Draw the loops
	for curve in loops:
		# Add Path3D so cars can follow it later
		var path = Path3D.new()
		path.curve = curve
		paths_container.add_child(path)
		
		# Generate the visual mesh
		_create_mesh_for_curve(curve)
		
		# NEW: Spawn placeholder spheres on the generated path
		_spawn_spheres_on_path(path)

# NEW: Helper function to spawn spheres along a path
func _spawn_spheres_on_path(path: Path3D):
	var curve_length = path.curve.get_baked_length()
	# Estimate number of tiles this curve covers (roughly curve_length / tile_x)
	var estimated_tiles = curve_length / tile_x
	var num_spheres = int(estimated_tiles / tiles_per_sphere)
	
	# Ensure at least one sphere if the track is long enough
	if num_spheres < 1 and curve_length > (tile_x * 2.0):
		num_spheres = 1
		
	if num_spheres <= 0:
		return
		
	var spacing = curve_length / num_spheres
	
	for i in range(num_spheres):
		var follower = PathFollow3D.new()
		follower.loop = true
		follower.progress = i * spacing
		path.add_child(follower)
		
		var mesh_instance = MeshInstance3D.new()
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = sphere_size / 2.0
		sphere_mesh.height = sphere_size
		mesh_instance.mesh = sphere_mesh
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = sphere_color
		mesh_instance.material_override = mat
		
		# Offset slightly up so it sits on the track without clipping
		mesh_instance.position.y = (sphere_size / 2.0) + 0.05
		
		follower.add_child(mesh_instance)
		active_path_followers.append(follower)

func _find_next_segment(pos: Vector3, segments: Array, first_seg: TrackSegment) -> TrackSegment:
	# First try to close the loop seamlessly
	if first_seg != null and first_seg.start_pos.distance_to(pos) < 0.05:
		return first_seg
	# Then look for unused segments
	for seg in segments:
		if not seg.used and seg.start_pos.distance_to(pos) < 0.05:
			return seg
	return null

func _add_segment_to_curve(curve: Curve3D, seg: TrackSegment, is_first: bool):
	if seg.type == "straight":
		if is_first:
			curve.add_point(seg.start_pos)
		else:
			curve.set_point_out(curve.get_point_count() - 1, Vector3.ZERO)
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
		
		if is_first:
			curve.add_point(seg.start_pos, Vector3.ZERO, out_cp)
		else:
			curve.set_point_out(curve.get_point_count() - 1, out_cp)
			
		curve.add_point(seg.end_pos, in_cp, Vector3.ZERO)
		
	elif seg.type == "perpendicular":
		var p1 = seg.start_pos
		var p4 = seg.end_pos
		var p2 = p1 + seg.start_dir * (tile_x / 2.0)
		var p3 = p4 - seg.end_dir * (tile_x / 2.0)
		
		if is_first:
			curve.add_point(p1)
		else:
			curve.set_point_out(curve.get_point_count() - 1, Vector3.ZERO)
			
		curve.add_point(p2)
		curve.add_point(p3)
		curve.add_point(p4)

func _create_mesh_for_curve(curve: Curve3D):
	var points = curve.tessellate(5, 0.1)
	if points.size() < 2: return
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = track_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	st.set_material(mat)
	
	var up = Vector3.UP
	for i in range(points.size() - 1):
		var p1 = points[i]
		var p2 = points[i+1]
		var dir = (p2 - p1).normalized()
		if dir == Vector3.ZERO: continue
		var left = dir.cross(up).normalized() * (track_width / 2.0)
		
		# Offset slightly on Y to prevent Z-fighting with the road
		var v1 = p1 + left + Vector3(0, 0.05, 0)
		var v2 = p1 - left + Vector3(0, 0.05, 0)
		var v3 = p2 + left + Vector3(0, 0.05, 0)
		var v4 = p2 - left + Vector3(0, 0.05, 0)
		
		st.set_normal(up)
		st.add_vertex(v1)
		st.set_normal(up)
		st.add_vertex(v2)
		st.set_normal(up)
		st.add_vertex(v3)
		
		st.set_normal(up)
		st.add_vertex(v2)
		st.set_normal(up)
		st.add_vertex(v4)
		st.set_normal(up)
		st.add_vertex(v3)
		
	var mesh = st.commit()
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	paths_container.add_child(mi)
