extends Node

# Quick test - add this as a child of your main scene
# It will test holds after 0.5 seconds

func _ready():
	await get_tree().create_timer(0.5).timeout
	test_holds()


func test_holds():
	print("\n")
	print("=".repeat(50))
	print("HOLD TEST - After 0.5 seconds")
	print("=".repeat(50))
	
	var all_holds = get_tree().get_nodes_in_group("holds")
	print("Total holds: ", all_holds.size())
	
	if all_holds.size() == 0:
		print("❌ NO HOLDS FOUND")
		return
	
	var start_count = 0
	var top_count = 0
	
	for hold in all_holds:
		# Get the HoldType enum
		var hold_script = hold.get_script()
		if not hold_script:
			continue
		
		var HoldType = hold_script.get("HoldType")
		if not HoldType:
			continue
		
		var type_name = HoldType.keys()[hold.hold_type]
		var is_start = hold.is_start_hold()
		var is_top = hold.is_top_out()
		
		print("Hold at ", hold.global_position, ": type=", type_name, ", is_start=", is_start, ", is_top=", is_top)
		
		if is_start:
			start_count += 1
		if is_top:
			top_count += 1
	
	print("\n" + "-".repeat(50))
	print("RESULTS:")
	print("  START holds: ", start_count)
	print("  TOP holds: ", top_count)
	print("-".repeat(50))
	
	if start_count > 0 and top_count > 0:
		print("✅ HOLDS ARE WORKING CORRECTLY!")
	else:
		print("❌ PROBLEM DETECTED!")
		
		# Deep dive
		if start_count == 0:
			print("\n🔍 Checking START holds:")
			for hold in all_holds:
				var hold_script = hold.get_script()
				if not hold_script:
					continue
				var HoldType = hold_script.get("HoldType")
				if not HoldType:
					continue
				
				if hold.hold_type == HoldType.START:
					print("  Found hold with START enum at ", hold.global_position)
					print("    hold.hold_type = ", hold.hold_type)
					print("    HoldType.START = ", HoldType.START)
					print("    hold.hold_type == HoldType.START? ", hold.hold_type == HoldType.START)
					print("    is_start_hold() returns: ", hold.is_start_hold())
					print("    _type_was_set_manually = ", hold.get("_type_was_set_manually"))
	
	print("=".repeat(50))
	print("\n")
