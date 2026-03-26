extends Node3D

# --- Config ---
var terrain_width: int = 100
var terrain_depth: int = 100
var tree_density: float = 0.02 # 2%

var tile_x: float = 2.0
var tile_z: float = 2.0

# Flexible arrays for tiles to easily add more ground/terrain tiles later
var base_tiles =[
	"res://models/default/grass.glb"
]

var decoration_tiles =[
	"res://models/default/grass-trees-tall.glb",
	"res://models/default/grass-trees.glb"
]

var loaded_base_tiles = []
var loaded_deco_tiles =[]

# Container to hold all generated terrain pieces
var terrain_container: Node3D
var level_editor: Node3D # Reference to the main editor for placing trees

func _ready():
	# Preload scenes for faster generation
	for path in base_tiles:
		if ResourceLoader.exists(path):
			loaded_base_tiles.append(load(path))
	for path in decoration_tiles:
		if ResourceLoader.exists(path):
			loaded_deco_tiles.append(load(path))

# --- Public API ---

func initialize(editor_tile_x: float, editor_tile_z: float, editor_ref: Node3D):
	tile_x = editor_tile_x
	tile_z = editor_tile_z
	level_editor = editor_ref
	
	terrain_container = Node3D.new()
	add_child(terrain_container)
	
	generate_terrain()

func set_settings(width: int, depth: int, density: float):
	var changed = false
	if terrain_width != width or terrain_depth != depth or tree_density != density:
		changed = true
		
	terrain_width = width
	terrain_depth = depth
	tree_density = density
	
	if changed:
		generate_terrain()

# --- Internal Logic ---

# Helper to find all mesh instances within a loaded scene
func _get_all_mesh_instances(node: Node, result: Array):
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_get_all_mesh_instances(child, result)

# Generates a single readonly mesh for ground and places trees as normal assets
func generate_terrain():
	# Clear existing terrain mesh
	for child in terrain_container.get_children():
		child.queue_free()
		
	# Clear previously generated trees from the editor so they don't stack on regeneration
	if level_editor:
		for grid_pos in level_editor.grid_data.keys():
			var models = level_editor.grid_data[grid_pos]
			for i in range(models.size() - 1, -1, -1):
				var model = models[i]
				if is_instance_valid(model) and model.get_meta("generated_tree", false):
					models.remove_at(i)
					model.queue_free()
			if models.is_empty():
				level_editor.grid_data.erase(grid_pos)

	if loaded_base_tiles.is_empty():
		return
		
	var base_scene = loaded_base_tiles[0].instantiate()
	add_child(base_scene) # Add to tree temporarily to get valid global transforms
	
	var mesh_instances =[]
	_get_all_mesh_instances(base_scene, mesh_instances)
	
	if mesh_instances.is_empty():
		base_scene.queue_free()
		return
		
	var final_mesh = ArrayMesh.new()
	
	# Pre-calculate random rotations for each tile to ensure consistency across multiple meshes/surfaces
	var tile_rotations =[]
	for i in range(terrain_width * terrain_depth):
		tile_rotations.append((randi() % 4) * (PI / 2.0))
		
	# Build the single readonly mesh
	for mi in mesh_instances:
		var base_mesh = mi.mesh
		if not base_mesh: continue
		
		var local_xform = base_scene.global_transform.affine_inverse() * mi.global_transform
		
		for surf_idx in range(base_mesh.get_surface_count()):
			var st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			
			var mat = mi.material_override
			if not mat:
				mat = base_mesh.surface_get_material(surf_idx)
			if mat:
				st.set_material(mat)
			
			for x in range(terrain_width):
				for z in range(terrain_depth):
					var pos_x = (x - terrain_width / 2.0) * tile_x
					var pos_z = (z - terrain_depth / 2.0) * tile_z
					
					var random_rot = tile_rotations[x * terrain_depth + z]
					var transform = Transform3D()
					transform = transform.rotated(Vector3.UP, random_rot)
					transform.origin = Vector3(pos_x, -0.07, pos_z)
					
					st.append_from(base_mesh, surf_idx, transform * local_xform)
					
			st.commit(final_mesh)
			
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = final_mesh
	terrain_container.add_child(mesh_instance)
	
	base_scene.queue_free()
	
	# Place trees as normal assets
	for x in range(terrain_width):
		for z in range(terrain_depth):
			var pos_x = (x - terrain_width / 2.0) * tile_x
			var pos_z = (z - terrain_depth / 2.0) * tile_z
			
			if randf() < tree_density and loaded_deco_tiles.size() > 0:
				_place_tree_asset(pos_x, pos_z)

# Places a tree as a normal editor asset
func _place_tree_asset(pos_x: float, pos_z: float):
	if not level_editor: return
	
	var tree_idx = randi() % loaded_deco_tiles.size()
	var tree_scene = loaded_deco_tiles[tree_idx]
	var tree_instance = tree_scene.instantiate()
	
	var random_rot = (randi() % 4) * 90.0
	tree_instance.position = Vector3(pos_x, 0, pos_z)
	tree_instance.rotation_degrees.y = random_rot
	
	var model_path = decoration_tiles[tree_idx]
	tree_instance.set_meta("model_path", model_path)
	tree_instance.set_meta("model_scale", 1.0)
	tree_instance.set_meta("uses_grid_snap", true)
	tree_instance.set_meta("generated_tree", true) # Tag to allow cleanup on regenerate
	
	GridUtils.configure_shadows(tree_instance)
	level_editor.placed_models_container.add_child(tree_instance)
	
	var grid_pos = GridUtils.get_grid_pos(tree_instance.position, tile_x, tile_z)
	if not level_editor.grid_data.has(grid_pos):
		level_editor.grid_data[grid_pos] =[]
	level_editor.grid_data[grid_pos].append(tree_instance)
