# Inventory.gd
class_name Inventory extends Resource

## The maximum number of item slots. (Currently unused in this basic logic)
@export var max_slots: int = 20
## Dictionary to store item data: {item_name: count}
@export var items: Dictionary = {}

## Adds a specified quantity of an item to the inventory.
func add_item(item_name: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false
	
	var current_count = items.get(item_name, 0)
	items[item_name] = current_count + quantity
	print("🎒 Added ", quantity, "x ", item_name, ". Total: ", items[item_name])
	return true

## Removes a specified quantity of an item from the inventory.
func remove_item(item_name: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false

	var current_count = items.get(item_name, 0)
	
	if current_count < quantity:
		print("❌ Cannot remove ", quantity, "x ", item_name, ". Only have ", current_count)
		return false
		
	items[item_name] = current_count - quantity
	
	if items[item_name] <= 0:
		items.erase(item_name) # Remove the key entirely if count hits zero
		
	print("🎒 Removed ", quantity, "x ", item_name, ". Remaining: ", items.get(item_name, 0))
	return true

## Checks if the inventory contains at least the specified quantity of an item.
func has_item(item_name: String, quantity: int = 1) -> bool:
	return items.get(item_name, 0) >= quantity

## Prints the current contents of the inventory to the console for debugging.
func print_inventory() -> void:
	print("--- Inventory Status (Player) ---")
	if items.is_empty():
		print("Inventory is empty.")
		return
	for item_name in items:
		print("- ", item_name, ": ", items[item_name])
	print("---------------------------------")
