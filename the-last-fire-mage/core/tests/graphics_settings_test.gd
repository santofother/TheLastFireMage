## Graphics settings checks. Owner: lower-settings. NET: standalone local test.
## Default preset must be the original look; Potato must switch things off; High must restore them.
extends Node

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	var torch := OmniLight3D.new()
	var embers := GPUParticles3D.new()
	add_child(sun)
	add_child(torch)
	add_child(embers)
	GraphicsSettings.apply_preset(0)
	assert(sun.shadow_enabled and torch.visible and embers.amount_ratio == 1.0, "default keeps original look")
	assert(get_tree().root.scaling_3d_scale == 1.0, "default 100% scale")
	GraphicsSettings.apply_preset(3)
	assert(not sun.shadow_enabled and not torch.visible and embers.amount_ratio == 0.0, "potato turns things off")
	assert(get_tree().root.scaling_3d_scale == 0.5, "potato 50% scale")
	var late := OmniLight3D.new()
	add_child(late)
	assert(not late.visible, "lights spawned later obey settings")
	GraphicsSettings.set_value("shadows", 2)
	assert(sun.shadow_enabled and GraphicsSettings.preset == -1, "custom after manual change")
	GraphicsSettings.apply_preset(0)
	assert(torch.visible and late.visible and Engine.max_fps == 0, "default restores everything")
	print("[TEST] GRAPHICS SETTINGS PASSED")
	get_tree().quit()
