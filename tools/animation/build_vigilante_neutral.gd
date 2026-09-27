extends SceneTree
## Generates the Vigilante "neutral" gameplay stance from the model's real
## skeleton. The GLB's A-pose stays the skeleton rest pose; this is a pose
## layered on top of it (every key is rest * offset).
##
## Run from the project root:
##   godot --headless --path . -s res://tools/animation/build_vigilante_neutral.gd
##
## Writes:
##   res://assets/characters/vigilante/animations/neutral.tres
##   res://assets/characters/vigilante/animations/vigilante_animations.tres
##     (adds/replaces "neutral", keeps every other clip already in it)
##
## The stance is static (one key per track in a short looping clip), so it is
## loop-safe and can sit underneath later animations.
##
## Local bone axes (model faces +Z): +X = character's left, +Z = forward.
## Limbs point down their local -Y, so rotating about -X swings them forward.
## Upper arms rest at +/-41.25 deg about Z (the A-pose); the offsets below bring
## them down to the sides.
##
## Knees: both thighs hang off joint_pelvis. A slight knee bend (thigh forward,
## shin back, foot level again) shortens the legs by a few millimetres, so the
## pelvis is lowered by exactly the measured amount to keep the feet planted.

const MODEL := "res://assets/characters/vigilante/vigilante_player.glb"
const OUT_DIR := "res://assets/characters/vigilante/animations"
const LENGTH := 1.0
## Knee bend in degrees (thigh forward by KNEE, shin back by 2 * KNEE).
const KNEE := 6.0

## bone -> offset from rest, Euler degrees (X, Y, Z) applied in the bone's
## local frame, in X-Y-Z order.
const POSE := {
	# Chest upright with a slight ready lean; head brought back to level.
	&"joint_spine": Vector3(2.0, 0.0, 0.0),
	&"joint_neck": Vector3(-1.0, 0.0, 0.0),
	&"joint_head": Vector3(-1.5, 0.0, 0.0),
	# Arms down at the sides (41.25 -> ~7 deg out), hanging slightly forward.
	&"joint_upperarm.L": Vector3(-3.0, 0.0, -34.0),
	&"joint_upperarm.R": Vector3(-3.0, 0.0, 34.0),
	# Elbows relaxed: 10 deg authored bend -> ~13 deg.
	&"joint_forearm.L": Vector3(-3.0, 0.0, 0.0),
	&"joint_forearm.R": Vector3(-3.0, 0.0, 0.0),
	# Wrists straightened slightly so the hands fall beside the thighs.
	&"joint_hand.L": Vector3(3.0, 0.0, 0.0),
	&"joint_hand.R": Vector3(3.0, 0.0, 0.0),
	# Soft knees: thigh forward, shin back twice as far, foot level again.
	&"joint_thigh.L": Vector3(-KNEE, 0.0, 0.0),
	&"joint_thigh.R": Vector3(-KNEE, 0.0, 0.0),
	&"joint_shin.L": Vector3(2.0 * KNEE, 0.0, 0.0),
	&"joint_shin.R": Vector3(2.0 * KNEE, 0.0, 0.0),
	&"joint_foot.L": Vector3(-KNEE, 0.0, 0.0),
	&"joint_foot.R": Vector3(-KNEE, 0.0, 0.0),
}


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(model)
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skeleton_path := String(model.get_path_to(skeleton))

	# Pose the skeleton to measure how far the feet lift, then drop the pelvis.
	var foot := skeleton.find_bone("joint_foot.L")
	var pelvis := skeleton.find_bone("joint_pelvis")
	var foot_rest := skeleton.get_bone_global_rest(foot).origin
	for bone: StringName in POSE:
		var index := skeleton.find_bone(bone)
		skeleton.set_bone_pose_rotation(index, _pose_rotation(skeleton, index, POSE[bone]))
	var foot_posed := _global_origin(skeleton, foot)
	var pelvis_position := skeleton.get_bone_rest(pelvis).origin - (foot_posed - foot_rest)
	skeleton.set_bone_pose_position(pelvis, pelvis_position)
	var residual := _global_origin(skeleton, foot).distance_to(foot_rest)
	print("pelvis lowered by %.4f m; foot residual %.6f m" % [skeleton.get_bone_rest(pelvis).origin.y - pelvis_position.y, residual])

	var anim := Animation.new()
	anim.resource_name = "neutral"
	anim.length = LENGTH
	anim.loop_mode = Animation.LOOP_LINEAR
	var track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(track, NodePath("%s:joint_pelvis" % skeleton_path))
	anim.position_track_insert_key(track, 0.0, pelvis_position)
	for bone: StringName in POSE:
		var index := skeleton.find_bone(bone)
		track = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath("%s:%s" % [skeleton_path, bone]))
		anim.rotation_track_insert_key(track, 0.0, _pose_rotation(skeleton, index, POSE[bone]))

	var anim_path := OUT_DIR + "/neutral.tres"
	var err := ResourceSaver.save(anim, anim_path)
	print("saved %s: %s (%d tracks, %.1f s, loop, static pose)" % [anim_path, error_string(err), anim.get_track_count(), anim.length])
	_add_to_library(&"neutral", anim_path)
	model.queue_free()
	quit()


static func _pose_rotation(skeleton: Skeleton3D, index: int, euler_deg: Vector3) -> Quaternion:
	var rest := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
	var offset := Quaternion(Vector3.RIGHT, deg_to_rad(euler_deg.x)) \
			* Quaternion(Vector3.UP, deg_to_rad(euler_deg.y)) \
			* Quaternion(Vector3.BACK, deg_to_rad(euler_deg.z))
	return rest * offset


## Global bone origin from the current poses (computed directly, so it does
## not depend on the skeleton's deferred update).
static func _global_origin(skeleton: Skeleton3D, index: int) -> Vector3:
	var t := Transform3D()
	var chain: Array[int] = []
	var b := index
	while b >= 0:
		chain.push_front(b)
		b = skeleton.get_bone_parent(b)
	for i in chain:
		t = t * Transform3D(Basis(skeleton.get_bone_pose_rotation(i)), skeleton.get_bone_pose_position(i))
	return t.origin


## Adds or replaces one clip in the shared library, keeping all others.
static func _add_to_library(clip: StringName, anim_path: String) -> void:
	var lib_path := OUT_DIR + "/vigilante_animations.tres"
	var library: AnimationLibrary
	if ResourceLoader.exists(lib_path):
		library = (load(lib_path) as AnimationLibrary).duplicate()
	else:
		library = AnimationLibrary.new()
	if library.has_animation(clip):
		library.remove_animation(clip)
	library.add_animation(clip, load(anim_path))
	var err := ResourceSaver.save(library, lib_path)
	print("saved %s: %s (%s)" % [lib_path, error_string(err), library.get_animation_list()])
