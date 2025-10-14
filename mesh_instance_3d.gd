# terrain_generator.gd
extends MeshInstance3D

# --- Node References ---
var terrain_material: ShaderMaterial
var noise: FastNoiseLite = FastNoiseLite.new()

# --- Terrain & Mesh Properties ---
@export_group("Terrain Geometry")
@export var mesh_size: int = 128
@export var tile_size: float = 1.0
@export var lod_distance: float = 100.0

# --- Noise Parameters (Passed to Shader) ---
@export_group("Noise Parameters")
@export var amplitude: float = 10.0
@export var noise_frequency: float = 0.05
@export var noise_seed: float = 42.0
@export var octaves: float = 4.0
@export var persistence: float = 0.5
@export var lacunarity: float = 2.0

# --- Shader Path ---
const SHADER_PATH = "res://terrain_shader.tres"

func _ready():
	# 1. Initialize FastNoiseLite
	noise.seed = int(noise_seed)
	noise.frequency = noise_frequency
	noise.fractal_octaves = int(octaves)
	noise.fractal_lacunarity = lacunarity
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.noise_type = FastNoiseLite.TYPE_PERLIN

	# 2. Load the material
	var shader_res = load(SHADER_PATH)
	if shader_res is Shader:
		terrain_material = ShaderMaterial.new()
		terrain_material.shader = shader_res
	else:
		push_error("Failed to load Shader at path: " + SHADER_PATH)
		return

	# 3. Generate and assign the mesh
	self.mesh = generate_detailed_mesh(mesh_size, mesh_size, tile_size)
	self.set_surface_override_material(0, terrain_material)

	# 4. Set LOD/Culling properties
	self.material_override = terrain_material
	self.extra_cull_margin = lod_distance 

	# 5. Apply uniforms
	update_shader_uniforms()

func generate_detailed_mesh(width: int, depth: int, tile_size: float) -> ArrayMesh:
	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	
	var vertices: PackedVector3Array = []
	var indices: PackedInt32Array = []
	
	for z in range(depth):
		for x in range(width):
			var n = noise.get_noise_2d(float(x), float(z)) * amplitude
			
			# Base vertex position (no inversion)
			var vertex = Vector3(float(x) * tile_size, n, float(z) * tile_size) 
			vertices.append(vertex)
			
			if x < width - 1 and z < depth - 1:
				var current_index = z * width + x
				var next_x = current_index + 1
				var next_z = current_index + width
				var next_xz = current_index + width + 1
				
				# Standard Winding Order
				indices.append(current_index)
				indices.append(next_z)
				indices.append(next_x) 
				
				indices.append(next_x)
				indices.append(next_z)
				indices.append(next_xz) 

	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_INDEX] = indices

	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_INDEX)

	var tool_mesh = ArrayMesh.new()
	tool_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {})
	
	# Calculate Normals and Tangents
	tool_mesh.surface_generate_normals(0)
	tool_mesh.surface_generate_tangents(0)

	var calculated_normals: PackedVector3Array = tool_mesh.surface_get_arrays(0)[ArrayMesh.ARRAY_NORMAL]
	
	# CRITICAL FIX: Invert the normals to point outwards (up)
	for i in range(calculated_normals.size()):
		calculated_normals[i] = -calculated_normals[i]
		
	arrays[ArrayMesh.ARRAY_NORMAL] = calculated_normals
	arrays[ArrayMesh.ARRAY_TANGENT] = tool_mesh.surface_get_arrays(0)[ArrayMesh.ARRAY_TANGENT]

	array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {})

	return array_mesh

func update_shader_uniforms():
	if terrain_material:
		terrain_material.set_shader_parameter("amplitude", amplitude)
		terrain_material.set_shader_parameter("noise_frequency", noise_frequency)
		terrain_material.set_shader_parameter("noise_seed", noise_seed)
		terrain_material.set_shader_parameter("_octaves", octaves)
		terrain_material.set_shader_parameter("_persistence", persistence)
		terrain_material.set_shader_parameter("_lacunarity", lacunarity)

func _process(delta):
	if Engine.is_editor_hint():
		update_shader_uniforms()
