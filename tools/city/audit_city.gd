extends SceneTree
## Prints the traversal-network audit of the city (see traversal_audit.gd):
## per district, every elevated walkable surface, how it can be reached from
## the street without wall-runs, and which are unreachable or dead ends.
##
##   godot --headless --path . -s res://tools/city/audit_city.gd [-- --why=<path suffix>]

const Audit := preload("res://tools/city/traversal_audit.gd")


func _initialize() -> void:
	var main: Node = load("res://scenes/main/city_main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _run(main: Node) -> void:
	for i in 3:
		await physics_frame
	var player := main.get_node("Player") as Player
	player.set_physics_process(false) # it only lends its sensor and grapple queries
	await physics_frame
	var audit := Audit.new(main.get_node("CityGreybox"), player.sensor, player.grapple)
	var t := Time.get_ticks_msec()
	audit.run()
	print(audit.report())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--why="):
			print(audit.why(arg.substr(6)))
	print("\n%d unreachable, %d dead ends (%d ms)" % [audit.unreachable().size(), audit.dead_ends().size(), Time.get_ticks_msec() - t])
	for path: String in audit.anchor_sources:
		if audit.anchor_sources[path] <= 0:
			print("anchor usable from nowhere mapped: ", path)
	quit()
