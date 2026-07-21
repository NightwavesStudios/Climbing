extends Node

func setAchievement(ach):
	var status = Steam.getAchievement(ach)
	if status["achieved"]:
		print("Already unlocked!")
		return
	Steam.setAchievement(ach)
	print("Unlocked Achievement ", ach)
