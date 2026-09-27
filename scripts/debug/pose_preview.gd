extends Node3D
## Preview helper for animation comparison scenes: any child AnimationPlayer
## with a "preview_time" metadata entry is frozen at that time of its
## autoplay animation, so several fixed moments can be compared side by side.
## Players without the metadata just play normally.


func _ready() -> void:
	for node in find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		if not player.has_meta(&"preview_time"):
			continue
		player.play(player.autoplay)
		player.seek(float(player.get_meta(&"preview_time")), true)
		player.pause()
