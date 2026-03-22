extends Node3D

# --- Signals ---
# NEW: Emitted when the track is rebuilt so cars can snap to new segments
signal track_regenerated

# --- Config ---
@export var lane_offset: float = 0.2
@export var turn_radius: float = 1.0 # Modifier for the curve radius
@export var track_color: Color = Color(0.6, 0.6, 0.6) # Dark grey/black
@export var track_width: float = 0.01

# --- Dependencies ---
var level_editor: Node3D
var grid_data: Dictionary
var tile_x: float = 2.0
var tile_z: float = 2.0

var paths_container: Node3D

# NEW: Store all segments to allow cars to find opposite lanes for U-turns
var track_segments: Array[TrackSegment] =[]

# Local segment definitions (at 0 degrees rotation)
var local_segments = {}

# MODIFIED: TrackSegment now holds its own curve, a list of connected next segments, and intersection data
class TrackSegment extends RefCounted:
	var start_pos: Vector3
	var start_dir: Vector3
	var end_pos: Vector3
	var end_dir: Vector3
	var type: String
	var curve: Curve3D
	var next_segments: Array[TrackSegment] =[]
	var is_intersection: bool = false # NEW: Flags if this segment is part of an intersection to allow cars to yield
	var grid_pos: Vector2 # NEW: The grid coordinate of this segment to identify which intersection it belongs to

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

# MODIFIED: Generates the track graph and stores all segments globally
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
						
						# NEW: Set intersection metadata for traffic yielding
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
	
	# 3. Draw the visual track mesh efficiently using a single SurfaceTool
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = track_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	st.set_material(mat)
	
	for seg in all_segments:
		_add_curve_to_surfacetool(st, seg.curve)
		
	var mesh = st.commit()
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	paths_container.add_child(mi)
	
	# NEW: Emit signal to notify track_cars.gd to snap vehicles to new track
	emit_signal("track_regenerated")

# NEW: Builds a standalone Curve3D for a single segment
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

# MODIFIED: Appends a curve's visual geometry to a shared SurfaceTool
func _add_curve_to_surfacetool(st: SurfaceTool, curve: Curve3D):
	var points = curve.tessellate(5, 0.1)
	if points.size() < 2: return
	
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
