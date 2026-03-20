extends Node

# --- State ---
var world_env: WorldEnvironment
var sky_material: ShaderMaterial

var cloud_density: float = 0.5
var cloud_speed: float = 0.02

func _ready():
	world_env = WorldEnvironment.new()
	add_child(world_env)
	
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	
	# Enable fog to blend the terrain edge smoothly into the skybox horizon
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0025
	env.fog_light_color = Color(0.65, 0.75, 0.85) # Matches sky_horizon_color
	# Prevent the fog from applying to the skybox so the clouds remain visible
	env.fog_sky_affect = 0.0 
	
	# MODIFIED: Decouple ambient lighting from the skybox visuals.
	# This prevents the map from getting brighter when cloud density increases.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 0.75) # A steady, soft sky-blue ambient light
	env.ambient_light_energy = 1.0
	
	var sky = Sky.new()
	sky_material = ShaderMaterial.new()
	
	var shader = Shader.new()
	# Procedural sky shader with moving clouds
	shader.code = """
	shader_type sky;
	
	uniform float cloud_density : hint_range(0.0, 1.0) = 0.5;
	uniform float cloud_speed : hint_range(0.0, 1.0) = 0.02;
	uniform sampler2D noise_tex;
	uniform vec3 sky_top_color : source_color = vec3(0.35, 0.55, 0.85);
	uniform vec3 sky_horizon_color : source_color = vec3(0.65, 0.75, 0.85);
	uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
	
	void sky() {
		vec3 dir = normalize(EYEDIR);
		
		// Base sky gradient
		float t = clamp(dir.y, 0.0, 1.0);
		vec3 sky_color = mix(sky_horizon_color, sky_top_color, t);
		
		// Procedural clouds
		if (dir.y > 0.0) {
			// Project UV based on direction to simulate a flat cloud layer
			vec2 uv = dir.xz / (dir.y + 0.1); 
			uv *= 0.2; // Scale
			uv += TIME * cloud_speed; // Movement
			
			float noise = texture(noise_tex, uv).r;
			// Adjust coverage based on density
			float coverage = smoothstep(1.0 - cloud_density, 1.0, noise);
			
			// Fade clouds near horizon
			coverage *= smoothstep(0.0, 0.2, dir.y);
			
			COLOR = mix(sky_color, cloud_color, coverage);
		} else {
			// Blend the ground color into the horizon color to prevent a harsh gap
			// if the camera angle manages to see past the edge of the terrain mesh.
			COLOR = mix(sky_horizon_color, vec3(0.2, 0.2, 0.2), clamp(-dir.y * 5.0, 0.0, 1.0));
		}
	}
	"""
	sky_material.shader = shader
	
	# Generate a noise texture for the clouds
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02
	
	var noise_tex = NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.seamless = true
	
	sky_material.set_shader_parameter("noise_tex", noise_tex)
	sky_material.set_shader_parameter("cloud_density", cloud_density)
	sky_material.set_shader_parameter("cloud_speed", cloud_speed)
	
	sky.sky_material = sky_material
	env.sky = sky
	world_env.environment = env

# --- Public API ---

func set_cloud_density(density: float):
	cloud_density = density
	if sky_material:
		sky_material.set_shader_parameter("cloud_density", density)

func set_cloud_speed(speed: float):
	cloud_speed = speed
	if sky_material:
		sky_material.set_shader_parameter("cloud_speed", speed)
