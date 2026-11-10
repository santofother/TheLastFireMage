class_name VillagerMeshSwap
extends Node3D
## Replaces the meshes on a villager skeleton with another skinned body.
## Owner: blue villager integration. Attach to the root of an instanced red-villager-animations.glb, or call `apply`.
## NET: runs on every peer, visuals only.
##
## Public API:
## - `mesh_scene`: GLB whose skin binds use the red villager's bone names.
## - `apply(skeleton, scene)`: swaps the meshes on an existing skeleton.

# CONTRACT: the skeleton, AnimationPlayer and clips stay the red GLB's. Bodies add meshes only, never clips.

## Character GLB to show instead of the red meshes.
@export var mesh_scene: PackedScene


# WHY: VillagerVisual only looks up the skeleton and player, so it doesn't matter which _ready runs first.
func _ready() -> void:
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or mesh_scene == null:
		push_error("[Game] villager mesh swap needs a Skeleton3D and a mesh_scene")
		return
	apply(skeleton, mesh_scene)


## Removes the skeleton's meshes and moves in the ones from `scene`.
static func apply(skeleton: Skeleton3D, scene: PackedScene) -> void:
	for child: Node in skeleton.get_children():
		if child is MeshInstance3D:
			skeleton.remove_child(child)
			child.free()
	var body := scene.instantiate()
	for source: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh := source as MeshInstance3D
		mesh.get_parent().remove_child(mesh)
		mesh.owner = null
		skeleton.add_child(mesh)
		mesh.skeleton = NodePath("..")
	body.free()
