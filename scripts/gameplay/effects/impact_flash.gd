class_name ImpactFlash
extends MeshInstance3D
## Клиент: вспышка в точке попадания — светящийся шарик, который раздувается, гаснет и
## удаляет себя. Мультяшный «бум» без крови. Создаёт AttackEffects; на сервере и без окна
## вспышек нет.

## Сколько секунд вспышка видна.
const LIFETIME_SEC: float = 0.18
## Во сколько раз шарик вырастает к концу.
const END_SCALE: float = 2.5


## Показать вспышку в точке (мировые координаты) цветом color и исчезнуть.
func play(at: Vector3, color: Color) -> void:
	global_position = at
	# Материал свой у каждой вспышки: цвет зависит от того, во что попали.
	var material: StandardMaterial3D = mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	material.albedo_color = color
	material_override = material
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, ^"scale", Vector3.ONE * END_SCALE, LIFETIME_SEC)
	tween.tween_property(self, ^"transparency", 1.0, LIFETIME_SEC)
	tween.chain().tween_callback(queue_free)
