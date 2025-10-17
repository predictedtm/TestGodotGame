# Player.gd
class_name Player extends CharacterBody3D

@export_group("Player Components")
## FIX: The type 'Inventory' must be available. 
## Ensure Inventory.gd is saved and declared with 'class_name Inventory extends Resource'.
@export var inventory: Inventory 
@onready var camera: Camera3D = $Camera3D 

@export_group("Movement")
@export var speed: float = 5.0
@export var look_sensitivity: float = 0.2 # FIX: Declared look_sensitivity
@export var gravity: float = 9.8

var current_velocity: Vector3 = Vector3.ZERO
var mouse_input: Vector2 = Vector2.ZERO # FIX: Declared mouse_input

func _ready() -> void:
	# Lock the cursor for first-person control
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if inventory == null:
		# Create a default inventory if none is assigned in the Inspector
		inventory = Inventory.new()
		print("⚠️ Player initialized with a default Inventory resource.")

func _input(event: InputEvent) -> void:
	# Handle mouse look input
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		mouse_input = event.relative
	
	# Handle inventory testing/debugging input
	if event.is_action_pressed("debug_add_item"):
		inventory.add_item("Stone", 1)
	if event.is_action_pressed("debug_remove_item"):
		inventory.remove_item("Stone", 1)
	if event.is_action_pressed("debug_print_inventory"):
		inventory.print_inventory()

func _unhandled_input(event: InputEvent) -> void:
	# Toggle mouse lock/free
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		current_velocity.y -= gravity * delta
	
	# Handle mouse look
	_handle_look(delta)
	
	# Handle movement
	_handle_movement()
	
	velocity = current_velocity
	move_and_slide()

func _handle_look(_delta: float) -> void:
	# Horizontal Rotation (Player Body)
	rotation_degrees.y -= mouse_input.x * look_sensitivity
	
	# Vertical Rotation (Camera)
	var camera_rot_x = camera.rotation_degrees.x - mouse_input.y * look_sensitivity
	camera_rot_x = clamp(camera_rot_x, -80.0, 80.0)
	camera.rotation_degrees.x = camera_rot_x
	
	mouse_input = Vector2.ZERO # Reset mouse input

func _handle_movement() -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		# Keep current y velocity (gravity/jump)
		current_velocity.x = direction.x * speed
		current_velocity.z = direction.z * speed
	else:
		# Decelerate when no input
		current_velocity.x = lerp(current_velocity.x, 0.0, 0.1)
		current_velocity.z = lerp(current_velocity.z, 0.0, 0.1)
