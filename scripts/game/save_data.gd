class_name SaveData
extends RefCounted
## The little the game remembers between sessions (best run times, tips
## already shown), in one ConfigFile under user://. Every read tolerates a
## missing or unreadable file, so a fresh install just starts empty.

## Where it lives (tests point this elsewhere so they never touch a real save).
static var path := "user://vigilante.cfg"


## Best time in seconds for `key` (INF if none yet).
static func best_time(key: StringName) -> float:
	return float(_load().get_value("best_times", String(key), INF))


## Records `seconds` for `key` if it beats the best. True if it did.
static func submit_time(key: StringName, seconds: float) -> bool:
	var cfg := _load()
	if seconds >= float(cfg.get_value("best_times", String(key), INF)):
		return false
	cfg.set_value("best_times", String(key), seconds)
	cfg.save(path)
	return true


static func flag(key: StringName) -> bool:
	return bool(_load().get_value("flags", String(key), false))


static func set_flag(key: StringName, value := true) -> void:
	var cfg := _load()
	cfg.set_value("flags", String(key), value)
	cfg.save(path)


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path) # a missing file just leaves it empty
	return cfg
