# RandomWalker.gd
class_name RandomWalker
extends CharacterBody3D

## Movement speed of the character.
@export var speed: float = 3.0
## How fast the character visually turns. Higher is faster.
@export var rotation_speed: float = 5.0
## How sharply the character changes its movement path. Lower values create wider, more circular turns.
@export var turn_agility: float = 3.0
## Gravity applied to the character.
@export var gravity: float = 9.8

## The range of time [min, max] the character will walk in one direction.
@export_group("Walk Settings")
@export var min_walk_time: float = 2.0
@export var max_walk_time: float = 5.0
@export var no_random_break: bool = false

## The range of time [min, max] the character will stay idle.
@export_group("Idle Settings")
@export var min_idle_time: float = 1.0
@export var max_idle_time: float = 4.0

@export_group("Goal Seeking")
## The chance (0.0 to 1.0) that the character will choose a Point of Interest (POI)
## as its target direction instead of a completely random one.
@export var poi_walk_chance: float = 0.5
@export var time_for_target_reconsideration: float = 0.5

# A list of global positions (Vector3) that the character will tend to walk towards.
var points_of_interest: Array[Vector3] = []

# Enum to manage the character's state.
enum State { IDLE, WALK }

var current_state: State = State.IDLE
# The ultimate direction the character wants to go.
var target_direction: Vector3 = Vector3.FORWARD
# The actual direction the character is currently moving. This will smoothly follow the target_direction.
var current_movement_direction: Vector3 = Vector3.FORWARD

@onready var state_timer: Timer = $StateTimer
@onready var dir_timer: Timer = $DirectionTimer

func _ready() -> void:
	state_timer.timeout.connect(_on_state_timer_timeout)
	dir_timer.timeout.connect(_on_dir_timer_timeout)
	dir_timer.wait_time = time_for_target_reconsideration
	dir_timer.autostart = true
	dir_timer.one_shot = false
	dir_timer.start()
	# Set initial direction to something other than zero to avoid issues.
	_pick_random_direction()
	current_movement_direction = target_direction
	# Start the process.
	_on_state_timer_timeout()


func _physics_process(delta: float) -> void:
	# Apply gravity every frame.
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Match the current state to its corresponding logic function.
	match current_state:
		State.IDLE:
			_handle_idle_state()
		State.WALK:
			_handle_walk_state(delta)
			
	move_and_slide()


func _on_state_timer_timeout() -> void:
	if current_state == State.WALK:
		current_state = State.IDLE
		state_timer.wait_time = randf_range(min_idle_time, max_idle_time)
	else:
		current_state = State.WALK
		state_timer.wait_time = randf_range(min_walk_time, max_walk_time)
		_pick_random_direction()
	if !no_random_break:
		state_timer.start()


# Logic for when the character is walking.
func _handle_walk_state(delta: float) -> void:
	# Smoothly interpolate the current movement direction towards the target direction.
	# This creates the curved walking path.
	current_movement_direction = current_movement_direction.slerp(target_direction, turn_agility * delta)
	
	# Set velocity based on the *current* interpolated direction.
	velocity.x = current_movement_direction.x * speed
	velocity.z = current_movement_direction.z * speed
	
	# Smoothly rotate the character's visual model to face its movement direction.
	if current_movement_direction != Vector3.ZERO:
		# Project the movement direction onto the XZ plane for rotation
		var flat_direction = current_movement_direction
		flat_direction.y = 0
		if flat_direction.length_squared() > 0.0:
			var target_basis = Basis.looking_at(flat_direction)
			transform.basis = transform.basis.slerp(target_basis, rotation_speed * delta)


# Logic for when the character is idle.
func _handle_idle_state() -> void:
	# Stop horizontal movement using lerp for a smooth stop.
	velocity.x = lerp(velocity.x, 0.0, 0.1)
	velocity.z = lerp(velocity.z, 0.0, 0.1)

func _on_dir_timer_timeout() -> void:
	_pick_random_direction()
	print("new direction")
	
# Picks a new random destination direction or a Point of Interest.
func _pick_random_direction() -> void:
	# 1. Check if we should try to walk towards a POI
	if not points_of_interest.is_empty() and randf() < poi_walk_chance:
		_pick_point_of_interest()
	# 2. Otherwise, pick a completely random direction (the original logic)
	else:
		var random_angle = randf_range(0, TAU) # TAU is 2 * PI
		target_direction = Vector3(sin(random_angle), 0, cos(random_angle)).normalized()


# Helper function to choose a POI and set it as the target_direction
func _pick_point_of_interest() -> void:
	var current_pos: Vector3 = global_transform.origin
	var total_weight: float = 0.0
	var weights: Array[float] = []

	# 1. Calculate the weight for each point based on inverse distance squared
	for poi in points_of_interest:
		var distance_sq: float = current_pos.distance_squared_to(poi)
		
		# If we are effectively at the POI, skip it by giving it zero weight.
		# This prevents division by zero and "shivering" when at the goal.
		if distance_sq < 1.0:
			weights.append(0.0)
			continue
			
		# The weight is the inverse of the distance squared.
		# This makes closer points have much larger weights.
		var weight: float = 1.0 / distance_sq
		weights.append(weight)
		total_weight += weight

	# Check if we have any valid targets left
	if total_weight == 0.0:
		# All POIs are either too close or the list is empty, revert to random walk.
		_pick_random_direction()
		return

	# 2. Pick a POI using the weighted random selection (Roulette Wheel Selection)
	var random_value: float = randf() * total_weight
	var chosen_index: int = -1
	var weight_sum: float = 0.0

	for i in range(weights.size()):
		weight_sum += weights[i]
		if random_value < weight_sum:
			chosen_index = i
			break

	# This should always succeed if total_weight > 0
	if chosen_index != -1:
		var chosen_poi: Vector3 = points_of_interest[chosen_index]
		
		# 3. Calculate the direction to the chosen POI (as before)
		var direction_to_poi: Vector3 = chosen_poi - current_pos
			
		# Keep the direction only on the XZ plane and normalize it
		direction_to_poi.y = 0
		target_direction = direction_to_poi.normalized()
	else:
		# Fallback in case of a math edge-case, though unlikely
		_pick_random_direction()
