extends Camera3D

## Configuration
@export var movement_speed: float = 10.0  # Speed for movement (units per second)
@export var mouse_sensitivity: float = 0.2 # Sensitivity for looking around

## Internal State
var velocity: Vector3 = Vector3.ZERO
var rotation_input: Vector2 = Vector2.ZERO

func _ready():
	# Capture and hide the mouse cursor for a proper 'look' control
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	# Handle mouse movement for rotation
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotation_input.x = -event.relative.y * mouse_sensitivity
		rotation_input.y = -event.relative.x * mouse_sensitivity

func _unhandled_input(event):
	# Toggle mouse capture mode with the Escape key
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta):
	# 1. Apply Mouse Rotation
	_handle_rotation()

	# 2. Calculate Movement Input
	velocity = _get_movement_input()

	# 3. Apply Movement
	if velocity != Vector3.ZERO:
		# Get the camera's local transform basis
		var basis = global_transform.basis
		
		# Move relative to the camera's forward/right direction
		var direction = (
			basis.z * velocity.z + # Forward/Backward (Z-axis)
			basis.x * velocity.x + # Left/Right (X-axis)
			Vector3.UP * velocity.y # Up/Down (Y-axis - world space)
		).normalized() * movement_speed * delta

		global_position += direction
	
	# Optional: Keep the velocity for consistent physics, though here we reset it every frame
	velocity = Vector3.ZERO

## Handles the camera's rotation based on mouse movement
func _handle_rotation():
	# Rotate the camera (pitch - look up/down)
	rotation.x += deg_to_rad(rotation_input.x)
	# Ensure camera doesn't flip over (clamp pitch)
	rotation.x = clamp(rotation.x, deg_to_rad(-90), deg_to_rad(90))

	# Rotate the Camera3D's parent (yaw - look left/right)
	# Since Camera3D doesn't have a parent in this setup, we rotate the camera itself around Y
	rotation.y += deg_to_rad(rotation_input.y)

	# Reset input after use
	rotation_input = Vector2.ZERO

## Gathers input from the keyboard for movement
func _get_movement_input() -> Vector3:
	var input_vector = Vector3.ZERO
	
	# Forward/Backward (Z)
	if Input.is_action_pressed("move_forward"):
		input_vector.z -= 1.0
	if Input.is_action_pressed("move_backward"):
		input_vector.z += 1.0

	# Left/Right (X)
	if Input.is_action_pressed("move_left"):
		input_vector.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_vector.x += 1.0

	# Up/Down (Y - using world up/down)
	if Input.is_action_pressed("move_up"):
		input_vector.y += 1.0
	if Input.is_action_pressed("move_down"):
		input_vector.y -= 1.0
		
	return input_vector.normalized()
