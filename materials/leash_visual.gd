# LeashVisual.gd attached to the MultiMeshInstance3D node (child of Node3D, sibling of RandomWalker)
extends MultiMeshInstance3D

# --- Exports (Paths remain correct for the current hierarchy) ---
@export var dog_point_path: NodePath = "../RandomWalker/WalkerConnectionPoint"
@export var player_point_path: NodePath = "../CharacterBody3D/LeashJoint"
@export_range(0.0, 5.0, 0.1) var slack_depth: float = 0.5 

const MESH_HEIGHT = 0.2
const CURVE_RESOLUTION = 20

# --- Node References ---
@onready var dog_point: Node3D = get_node(dog_point_path)
@onready var player_point: Node3D = get_node(player_point_path)

# 🌟 CORRECTED LINE 17: Path is only up one level, then down.
@onready var camera_node: Camera3D = get_node("../CharacterBody3D/Camera3D")

# Resource to hold the curve data
var slack_curve: Curve3D = Curve3D.new()

func _ready():
	if not is_instance_valid(dog_point) or not is_instance_valid(player_point) or not is_instance_valid(camera_node):
		push_error("Leash Setup Error: Connection points or camera not found. Check paths!")
		process_mode = Node.PROCESS_MODE_DISABLED 
		return
		
	multimesh.instance_count = int(200.0 / MESH_HEIGHT)

func _process(delta):
	if not is_instance_valid(dog_point) or not is_instance_valid(player_point):
		return

	var start_pos: Vector3 = player_point.global_position
	var end_pos: Vector3 = dog_point.global_position

	# --- 1. Populate and Prepare the Curve3D for Slack ---
	slack_curve.clear_points()
	var down_vector: Vector3 = Vector3.DOWN 
	
	# Use four control points for a gentle Bezier curve
	for i in range(4):
		var t = float(i) / 3.0
		var p_straight: Vector3 = start_pos.lerp(end_pos, t)
		
		# Max offset at the middle two points (i=1 and i=2)
		var offset_factor: float = 0.0
		if i == 1 or i == 2:
			offset_factor = 1.0
		
		var p_curved: Vector3 = p_straight + (down_vector * slack_depth * offset_factor)
		slack_curve.add_point(p_curved)
		
	# Use tessellate() to prepare the curve for sampling
	slack_curve.tessellate()
	var baked_length = slack_curve.get_baked_length() 

	# Robustness Check: Only draw if the curve is long enough
	if baked_length < MESH_HEIGHT * 0.5:
		multimesh.instance_count = 0
		return
		
	# --- 2. Sample Points and Place Meshes ---
	var current_length = 0.0
	var instance_idx = 0
	var num_instances = 0
	
	while current_length < baked_length && instance_idx < multimesh.instance_count:
		
		# Get point (origin) and the aligned transform (basis)
		var point: Vector3 = slack_curve.sample_baked(current_length)
		
		# Returns a Transform3D aligned to the tangent and Y-up.
		var instance_transform = slack_curve.sample_baked_with_rotation(current_length)
		
		# Set the origin to the correct point on the curve
		instance_transform.origin = point

		# Rotate the cylinder mesh 90 degrees around X to lay it flat along the tangent (Z-axis).
		var correction_rotation = Basis.from_euler(Vector3(PI/2.0, 0, 0))
		instance_transform.basis = instance_transform.basis * correction_rotation
		
		# Shift the origin by half the mesh height so it is centered on the curve point
		instance_transform.origin += (instance_transform.basis * Vector3(0, 0, -MESH_HEIGHT / 2.0))
		
		multimesh.set_instance_transform(instance_idx, instance_transform)
		
		current_length += MESH_HEIGHT
		instance_idx += 1
		num_instances += 1
		
	multimesh.instance_count = num_instances
