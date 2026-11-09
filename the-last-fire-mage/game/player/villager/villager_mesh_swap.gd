extends Node3D
## Replaces the red villager's meshes with another skinned villager body on the same skeleton.
## Owner: blue villager integration. Attach to the root of an instanced red-villager-animations.glb.
## NET: runs on every peer, visuals only.
##
## Public API:
## - `mesh_scene`: mesh-only GLB whose skin binds use the red villager's bone names.

# CONTRACT: the skeleton, AnimationPlayer and clips stay the red GLB's. Bodies add meshes only, never clips.

## Mesh-only character GLB to show instead of the red meshes.
@export var mesh_scene: PackedScene


# WHY: VillagerVisual only looks up the skeleton and player, so it doesn't matter which _ready runs first.
func _ready() -> void:
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or mesh_scene == null:
		push_error("[Game] villager mesh swap needs a Skeleton3D and a mesh_scene")
		return
	for child: Node in skeleton.get_children():
		if child is MeshInstance3D:
			skeleton.remove_child(child)
			child.free()
	var body := mesh_scene.instantiate()
	for source: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh := source as MeshInstance3D
		mesh.get_parent().remove_child(mesh)
		mesh.owner = null
		skeleton.add_child(mesh)
		mesh.skeleton = NodePath("..")
	body.free()
