class_name Tracer
extends MeshInstance3D
## Клиент: след пули — тонкая светящаяся полоска от ствола до точки попадания, которая
## гаснет за доли секунды и удаляет себя. Создаёт AttackEffects; на сервере и без окна
## трассеров нет.

## Сколько секунд след виден.
const LIFETIME_SEC: float = 0.12
## Короче этого след не рисуем: выстрел в упор.
const MIN_LENGTH: float = 0.3


## Показать след от from до to (мировые координаты) и исчезнуть.
func play(from: Vector3, to: Vector3) -> void:
	if from.distance_to(to) < MIN_LENGTH:
		queue_free()
		return
	global_transform = get_segment_transform(from, to)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, ^"transparency", 1.0, LIFETIME_SEC)
	# Заодно худеет: в рендерах без прозрачности геометрии след всё равно исчезнет плавно.
	tween.tween_property(self, ^"scale:x", 0.0, LIFETIME_SEC)
	tween.tween_property(self, ^"scale:y", 0.0, LIFETIME_SEC)
	tween.chain().tween_callback(queue_free)


## Положение полоски единичной длины (сетка вытянута вдоль своей оси Z): середина
## отрезка, ось Z идёт вдоль него, длина — в масштабе по Z. У отрезка нулевой длины
## направления нет: полоска остаётся единичной в точке from.
static func get_segment_transform(from: Vector3, to: Vector3) -> Transform3D:
	var offset: Vector3 = to - from
	var length: float = offset.length()
	if is_zero_approx(length):
		return Transform3D(Basis.IDENTITY, from)
	var forward: Vector3 = offset / length
	# Для почти вертикального выстрела «верх» берём другой, иначе базис вырождается.
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var axes: Basis = Basis.looking_at(forward, up)
	return Transform3D(axes.scaled_local(Vector3(1.0, 1.0, length)), (from + to) * 0.5)
