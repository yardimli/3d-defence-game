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

func _ready():
	# Preload scenes for faster generation
	for path in base_tiles:
		if ResourceLoader.exists(path):
			loaded_base_tiles.append(load(path))
	for path in decoration_tiles:
		if ResourceLoader.exists(path):
			loaded_deco_tiles.append(load(path))

# --- Public API ---

func initialize(editor_tile_x: float, editor_tile_z: float):
	tile_x = editor_tile_x
	tile_z = editor_tile_z
	
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

func generate_terrain():
	# Clear existing terrain
	for child in terrain_container.get_children():
		child.queue_free()
		
	for x in range(terrain_width):
		for z in range(terrain_depth):
			# Center the terrain grid around (0,0)
			var pos_x = (x - terrain_width / 2.0) * tile_x
			var pos_z = (z - terrain_depth / 2.0) * tile_z
			
			var scene = _choose_tile_scene()
			if scene:
				var instance = scene.instantiate()
				# Place slightly below 0 to avoid z-fighting with placed grid items
				instance.position = Vector3(pos_x, -0.05, pos_z)
				
				# Random rotation (0, 90, 180, 270) for visual variety
				var random_rot = (randi() % 4) * 90.0
				instance.rotation_degrees.y = random_rot
				
				terrain_container.add_child(instance)

func _choose_tile_scene() -> PackedScene:
	# Determine if we should place a decoration (tree) tile based on density %
	if randf() < tree_density and loaded_deco_tiles.size() > 0:
		return loaded_deco_tiles[randi() % loaded_deco_tiles.size()]
	else:
		# Otherwise place a base tile
		if loaded_base_tiles.size() > 0:
			return loaded_base_tiles[randi() % loaded_base_tiles.size()]
		return null
