extends CharacterBody3D

# --- Movement Parameters ---
@export var speed: float = 3.0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var direction_change_interval: float = 2.0 

# --- AI State ---
var current_direction: Vector3 = Vector3.ZERO
var time_to_next_change: float = 0.0

# 🟢 FIX: Reference the node named 'DogMesh'
@onready var visual_mesh = $DogMesh 


func _ready():
	# Initialize the first random movement
	_set_random_direction()

func _physics_process(delta):
	var velocity = get_velocity()

	# 1. Apply Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. Handle Random Horizontal Movement
	_handle_random_movement(delta)
	
	# Apply the direction to the velocity
	velocity.x = current_direction.x * speed
	velocity.z = current_direction.z * speed
	
	# 3. Rotate the dog to face the direction of movement
	if current_direction.length_squared() > 0.0:
		_rotate_to_direction(current_direction, delta)

	# 4. Final Move
	set_velocity(velocity)
	move_and_slide()

# ----------------------------------------------------------------------
## AI Helper Functions
# ----------------------------------------------------------------------

func _handle_random_movement(delta: float):
	time_to_next_change -= delta

	if time_to_next_change <= 0.0 or is_on_wall():
		_set_random_direction()

func _set_random_direction():
	time_to_next_change = randf_range(direction_change_interval * 0.5, direction_change_interval * 1.5)
	
	var random_angle = randf_range(0.0, PI * 2.0)
	
	current_direction = Vector3(cos(random_angle), 0, sin(random_angle)).normalized()


func _rotate_to_direction(direction: Vector3, delta: float):
	# Determine the angle needed to look in the 'direction'
	var target_transform = visual_mesh.transform.looking_at(
		visual_mesh.global_position + direction, 
		Vector3.UP
	)
	
	# Smoothly rotate the visual mesh towards the target rotation
	visual_mesh.transform = visual_mesh.transform.interpolate_with(
		target_transform, 
		delta * 10.0 # 10.0 is the rotation speed
	)
