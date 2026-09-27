extends SceneTree
## Generates the Vigilante "idle" animation on top of the neutral stance.
##
## Run from the project root (after build_vigilante_neutral.gd):
##   godot --headless --path . -s res://tools/animation/build_vigilante_idle.gd
##
## Reads:
##   res://assets/characters/vigilante/animations/neutral.tres  (source of truth)
## Writes:
##   res://assets/characters/vigilante/animations/idle.tres
##   res://assets/characters/vigilante/animations/vigilante_animations.tres
##     (adds/replaces "idle" in the shared AnimationLibrary, keeps other clips)
##
## idle = NEUTRAL STANCE + subtle motion. Every key is neutral_pose * small
## offset, where neutral_pose is read from neutral.tres, so changing the stance
## and regenerating idle keeps the two consistent. The GLB rest (A-pose) is
## only used for bones neutral does not pose, and none of the moving bones
## fall in that group.
##
## Every track in neutral.tres is also carried into idle (legs, pelvis
## height, ...) as a constant key: when a clip plays on its own, bones it does
## not key fall back to the rest pose, so idle must hold the whole stance
## itself to never slip back toward the A-pose.
##
## Motion design (unchanged): slow breathing through the spine, the neck
## counters it so the head stays level, a slight head drift, and the arms and
## hands settle a beat behind the breath. Pelvis and legs do not move, so the
## feet stay planted. All motions complete whole cycles in LENGTH, so the loop
## is seamless.

const MODEL := "res://assets/characters/vigilante/vigilante_player.glb"
const OUT_DIR := "res://assets/characters/vigilante/animations"
const NEUTRAL := OUT_DIR + "/neutral.tres"
const LENGTH := 3.0
const STEP := 0.1

## bone -> [axis, amplitude in degrees, phase in radians] components, applied
## in the bone's local frame on top of its neutral pose.
## Local axes: +X = character's left, +Y = up the bone, +Z = forward.
## Rotation about +X leans forward; about +Z tilts toward the character's right.
const MOTION := {
	&"joint_spine": [[Vector3.RIGHT, -0.9, 0.0], [Vector3.BACK, 0.5, 1.9], [Vector3.UP, 0.35, 0.6]],
	&"joint_neck": [[Vector3.RIGHT, 0.6, 0.0], [Vector3.BACK, -0.3, 1.9]],
	&"joint_head": [[Vector3.RIGHT, 0.5, 2.4], [Vector3.UP, 1.1, 3.6], [Vector3.BACK, 0.25, 0.9]],
	&"joint_upperarm.L": [[Vector3.BACK, 0.9, -0.5], [Vector3.RIGHT, 0.6, 0.8]],
	&"joint_upperarm.R": [[Vector3.BACK, -0.9, -0.5], [Vector3.RIGHT, 0.6, 1.2]],
	&"joint_forearm.L": [[Vector3.RIGHT, -1.2, -0.9]],
	&"joint_forearm.R": [[Vector3.RIGHT, -1.2, -1.1]],
	&"joint_hand.L": [[Vector3.RIGHT, 0.8, -1.3], [Vector3.BACK, 0.5, -1.0]],
	&"joint_hand.R": [[Vector3.RIGHT, 0.8, -1.5], [Vector3.BACK, -0.5, -1.2]],
}


func _initialize() -> void:
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skeleton_path := String(model.get_path_to(skeleton))
	var neutral := load(NEUTRAL) as Animation
	assert(neutral != null, "run build_vigilante_neutral.gd first")

	var anim := Animation.new()
	anim.resource_name = "idle"
	anim.length = LENGTH
	anim.loop_mode = Animation.LOOP_LINEAR
	anim.step = STEP

	# 1) The whole neutral stance, held constant (legs, pelvis height, ...).
	for t in neutral.get_track_count():
		var bone := StringName(neutral.track_get_path(t).get_concatenated_subnames())
		if MOTION.has(bone) and neutral.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			continue # animated below, on top of this same neutral rotation
		var track := anim.add_track(neutral.track_get_type(t))
		anim.track_set_path(track, neutral.track_get_path(t))
		anim.track_insert_key(track, 0.0, neutral.track_get_key_value(t, 0))

	# 2) The moving bones: neutral pose * breathing offset.
	for bone: StringName in MOTION:
		var index := skeleton.find_bone(bone)
		assert(index >= 0, "missing bone %s" % bone)
		var base := _neutral_rotation(neutral, skeleton_path, bone, skeleton.get_bone_rest(index).basis.get_rotation_quaternion())
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath("%s:%s" % [skeleton_path, bone]))
		anim.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		anim.track_set_interpolation_loop_wrap(track, true)
		var keys := int(round(LENGTH / STEP))
		for k in keys: # no key at LENGTH: loop wrap blends the last key into the first
			var t := k * STEP
			anim.rotation_track_insert_key(track, t, base * _offset(MOTION[bone], t))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var anim_path := OUT_DIR + "/idle.tres"
	var err := ResourceSaver.save(anim, anim_path)
	print("saved %s: %s (%d tracks: %d moving on top of neutral, %d held from neutral; %.1f s, loop)" % [
		anim_path, error_string(err), anim.get_track_count(), MOTION.size(), anim.get_track_count() - MOTION.size(), anim.length])

	# Add/replace "idle" in the shared library, keeping any other clips.
	var lib_path := OUT_DIR + "/vigilante_animations.tres"
	var library := AnimationLibrary.new()
	if ResourceLoader.exists(lib_path):
		library = (load(lib_path) as AnimationLibrary).duplicate()
	if library.has_animation(&"idle"):
		library.remove_animation(&"idle")
	library.add_animation(&"idle", load(anim_path))
	err = ResourceSaver.save(library, lib_path)
	print("saved %s: %s (%s)" % [lib_path, error_string(err), library.get_animation_list()])
	model.free()
	quit()


## The bone's rotation in the neutral stance (first key of its rotation
## track), or `fallback` (the rest rotation) if neutral does not pose it.
static func _neutral_rotation(neutral: Animation, skeleton_path: String, bone: StringName, fallback: Quaternion) -> Quaternion:
	var track := neutral.find_track(NodePath("%s:%s" % [skeleton_path, bone]), Animation.TYPE_ROTATION_3D)
	return neutral.track_get_key_value(track, 0) if track >= 0 else fallback


## Small rotation offset for one bone at time t (whole cycles per LENGTH).
static func _offset(components: Array, t: float) -> Quaternion:
	var q := Quaternion.IDENTITY
	var p := TAU * t / LENGTH
	for c in components:
		q = q * Quaternion(c[0], deg_to_rad(c[1]) * sin(p + c[2]))
	return q
