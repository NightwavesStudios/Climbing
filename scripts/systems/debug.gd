extends Node

## Quick diagnostic script - attach to any node in your scene to test

func _ready():
	print("\n" + "=".repeat(50))
	print("DISCIPLINE SYSTEM DIAGNOSTIC")
	print("=".repeat(50))
	
	# Check if scripts exist
	print("\n1. Checking if scripts exist:")
	var scripts_to_check = [
		"res://scripts/systems/rope_system.gd",
		"res://scripts/levels/speed_timer.gd",
		"res://scripts/systems/climbing_discipline.gd"
	]
	
	for script_path in scripts_to_check:
		if ResourceLoader.exists(script_path):
			print("  ✓ Found: " + script_path)
		else:
			print("  ✗ MISSING: " + script_path)
	
	# Check if we can load them
	print("\n2. Checking if scripts can be loaded:")
	
	var rope_script = load("res://scripts/systems/rope_system.gd")
	if rope_script:
		print("  ✓ RopeSystem script loaded")
	else:
		print("  ✗ FAILED to load RopeSystem")
	
	var timer_script = load("res://scripts/levels/speed_timer.gd")
	if timer_script:
		print("  ✓ SpeedTimer script loaded")
	else:
		print("  ✗ FAILED to load SpeedTimer")
	
	var discipline_script = load("res://scripts/systems/climbing_discipline.gd")
	if discipline_script:
		print("  ✓ ClimbingDiscipline script loaded")
	else:
		print("  ✗ FAILED to load ClimbingDiscipline")
	
	# Check main scene structure
	print("\n3. Checking main scene:")
	var main = get_tree().current_scene
	print("  Current scene: " + str(main.name))
	print("  Scene script: " + str(main.get_script()))
	
	# Check for EXISTING rope/timer systems (shouldn't exist!)
	var existing_rope = main.get_node_or_null("RopeSystem")
	if existing_rope:
		print("  ⚠️ WARNING: RopeSystem already exists in scene!")
		print("     This will cause conflicts - REMOVE IT from the scene")
	
	var existing_timer = main.get_node_or_null("SpeedTimer")
	if existing_timer:
		print("  ⚠️ WARNING: SpeedTimer already exists in scene!")
		print("     This will cause conflicts - REMOVE IT from the scene")
	
	# Check for level loader
	var loader = main.get_node_or_null("LevelLoader")
	if loader:
		print("  ✓ LevelLoader found")
		if loader.has_method("get_discipline"):
			print("    ✓ get_discipline() method exists")
		else:
			print("    ✗ get_discipline() method MISSING")
	else:
		print("  ✗ LevelLoader NOT FOUND")
	
	# Check player
	var player = main.get_node_or_null("Character")
	if player:
		print("  ✓ Character found")
		if player.has_method("set_climbing_discipline"):
			print("    ✓ set_climbing_discipline() exists")
		else:
			print("    ✗ set_climbing_discipline() MISSING")
		if player.has_method("set_rope_system"):
			print("    ✓ set_rope_system() exists")
		else:
			print("    ✗ set_rope_system() MISSING")
		if player.has_method("set_speed_timer"):
			print("    ✓ set_speed_timer() exists")
		else:
			print("    ✗ set_speed_timer() MISSING")
	else:
		print("  ✗ Character NOT FOUND")
	
	print("\n" + "=".repeat(50))
	print("DIAGNOSTIC COMPLETE")
	print("=".repeat(50) + "\n")
