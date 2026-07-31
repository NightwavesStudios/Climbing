extends GPUParticles2D
class_name GrabParticles

## A one-shot particle burst effect that plays when grabbing a hold.
## Automatically queues itself for deletion after the particles finish.

func _ready() -> void:
	finished.connect(_on_finished)

func _on_finished() -> void:
	queue_free()