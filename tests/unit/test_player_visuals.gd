extends TestCase
## PlayerVisuals и Viewmodel без окна: сервер и боты создают те же сцены, поэтому каждый
## публичный метод обязан работать без рендера, до входа в дерево и с любым мусором на входе.

const VISUALS_SCENE: PackedScene = preload("res://scenes/characters/player_visuals.tscn")
const VIEWMODEL_SCENE: PackedScene = preload("res://scenes/characters/viewmodel.tscn")
const PISTOL_SCENE: PackedScene = preload("res://assets/models/weapons/pistol.glb")
const KNIFE_SCENE: PackedScene = preload("res://assets/models/weapons/knife.glb")

const SKELETON_PATH: String = "Model/Armature/Skeleton3D"
const RIGHT_GRIP_PATH: String = "Model/Armature/Skeleton3D/RightHandAttachment/Grip"
const LEFT_GRIP_PATH: String = "Model/Armature/Skeleton3D/LeftHandAttachment/Grip"
const LIMB_MESHES: Dictionary[int, String] = {
	BodyPart.Part.LEFT_ARM: "ArmLeft",
	BodyPart.Part.RIGHT_ARM: "ArmRight",
	BodyPart.Part.LEFT_LEG: "LegLeft",
	BodyPart.Part.RIGHT_LEG: "LegRight",
}
const BODY_MESHES: PackedStringArray = ["HeadPiece", "FacePlate", "FaceEyes", "TorsoPiece", "PelvisPiece"]
const BONES: PackedStringArray = [
	"Hips", "Spine", "Chest", "Neck", "Head",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
]
## Все сочетания шести битов BodyPart: четыре конечности плюс голова и торс, которые не теряются.
const MASK_COUNT: int = 64
const ALL_LIMBS: int = 60
## Метрики, на которые опираются хитбоксы (допуск 3 см).
const BODY_HEIGHT: float = 1.8
const METRIC_TOLERANCE: float = 0.03
const FRAME_SEC: float = 1.0 / 60.0
## Сколько кадров анимации прогоняется вручную в каждом состоянии.
const FRAMES_PER_STATE: int = 12


func test_scene_has_expected_nodes() -> void:
	var visuals: PlayerVisuals = _new_visuals()
	assert_true(visuals.get_node_or_null("Model") is Node3D, "узел Model")
	assert_true(visuals.get_node_or_null("NameLabel") is Label3D, "узел NameLabel")
	assert_true(visuals.get_node_or_null("Props") != null, "узел Props")
	assert_true(visuals.get_node_or_null(SKELETON_PATH) is Skeleton3D, "скелет модели")
	var names: PackedStringArray = BODY_MESHES.duplicate()
	names.append_array(LIMB_MESHES.values())
	for mesh_name: String in names:
		var mesh: MeshInstance3D = visuals.get_node_or_null(SKELETON_PATH.path_join(mesh_name)) as MeshInstance3D
		assert_true(mesh != null and mesh.mesh != null, "меш %s" % mesh_name)
	visuals.free()


func test_skeleton_has_exactly_humanoid_bones() -> void:
	var visuals: PlayerVisuals = _new_visuals()
	var skeleton: Skeleton3D = visuals.get_node(SKELETON_PATH) as Skeleton3D
	var found: PackedStringArray = []
	for index: int in skeleton.get_bone_count():
		found.append(skeleton.get_bone_name(index))
	found.sort()
	var expected: PackedStringArray = BONES.duplicate()
	expected.sort()
	assert_eq(found, expected, "имена костей скелета")
	assert_eq(PlayerVisuals.BONE_NAMES, BONES, "порядок костей в PlayerVisuals")
	visuals.free()


func test_model_keeps_hitbox_metrics() -> void:
	var visuals: PlayerVisuals = _new_visuals()
	var bounds: AABB = _mesh_bounds(visuals.get_node("Model"))
	assert_true(absf(bounds.position.y) < METRIC_TOLERANCE, "ступни на нуле: %s" % bounds.position.y)
	assert_true(absf(bounds.end.y - BODY_HEIGHT) < METRIC_TOLERANCE, "рост 1.80 м: %s" % bounds.end.y)
	var face: MeshInstance3D = visuals.get_node(SKELETON_PATH.path_join("FacePlate")) as MeshInstance3D
	assert_eq(face.mesh.surface_get_material(0).resource_name, "FacePlate", "материал лицевой пластины")
	# Перёд модели — -Z: лицевая пластина выступает вперёд.
	assert_true(face.mesh.get_aabb().get_center().z < 0.0, "лицо смотрит в -Z")
	visuals.free()


func test_lost_limbs_are_hidden_and_restored() -> void:
	var visuals: PlayerVisuals = _new_visuals()
	for mask: int in MASK_COUNT:
		visuals.set_limbs_lost(mask, mask % 2 == 0)
		for part: BodyPart.Part in BodyPart.LIMBS:
			var mesh: MeshInstance3D = visuals.get_node(SKELETON_PATH.path_join(LIMB_MESHES[part])) as MeshInstance3D
			assert_eq(mesh.visible, not BodyPart.is_lost(mask, part), "маска %d, %s" % [mask, LIMB_MESHES[part]])
	visuals.set_limbs_lost(0)
	for mesh_name: String in LIMB_MESHES.values():
		assert_true((visuals.get_node(SKELETON_PATH.path_join(mesh_name)) as MeshInstance3D).visible, "%s вернулась" % mesh_name)
	for mesh_name: String in BODY_MESHES:
		assert_true((visuals.get_node(SKELETON_PATH.path_join(mesh_name)) as MeshInstance3D).visible, "%s не прячется" % mesh_name)
	visuals.free()


## Без окна детали не разлетаются, даже если эффект попросили.
func test_no_limb_props_without_display() -> void:
	var visuals: PlayerVisuals = await _new_visuals_in_tree()
	visuals.set_limbs_lost(ALL_LIMBS, true)
	assert_eq(visuals.get_node("Props").get_child_count(), 0, "детали без окна")
	_free_from_tree(visuals)


func test_held_item_follows_free_hand() -> void:
	var visuals: PlayerVisuals = _new_visuals()
	# Ладони создаются при первом обращении к модели.
	visuals.set_held_item(null)
	var right: Node = visuals.get_node(RIGHT_GRIP_PATH)
	var left: Node = visuals.get_node(LEFT_GRIP_PATH)
	assert_eq(right.get_child_count() + left.get_child_count(), 0, "пустые руки")
	visuals.set_held_item(PISTOL_SCENE)
	assert_eq(right.get_child_count(), 1, "предмет в правой руке")
	assert_eq(left.get_child_count(), 0, "левая рука пуста")
	visuals.set_held_item(PISTOL_SCENE)
	assert_eq(right.get_child_count(), 1, "повторный вызов не плодит предметы")
	visuals.set_limbs_lost(BodyPart.bit(BodyPart.Part.RIGHT_ARM), false)
	assert_eq(right.get_child_count(), 0, "без правой руки предмет из неё убран")
	assert_eq(left.get_child_count(), 1, "без правой руки предмет в левой")
	visuals.set_limbs_lost(BodyPart.bit(BodyPart.Part.RIGHT_ARM) | BodyPart.bit(BodyPart.Part.LEFT_ARM), false)
	assert_eq(right.get_child_count() + left.get_child_count(), 0, "без рук предмета нет")
	visuals.set_held_item(KNIFE_SCENE)
	assert_eq(right.get_child_count() + left.get_child_count(), 0, "без рук нож не появляется")
	visuals.set_limbs_lost(0)
	assert_eq(right.get_child_count(), 1, "руки вернулись — нож в правой")
	visuals.set_held_item(null)
	assert_eq(right.get_child_count() + left.get_child_count(), 0, "предмет убран")
	visuals.free()


func test_body_color_is_per_instance() -> void:
	var first: PlayerVisuals = _new_visuals()
	var second: PlayerVisuals = _new_visuals()
	first.set_body_color(Color.RED)
	second.set_body_color(Color.BLUE)
	assert_eq(_suit_color(first), Color.RED, "цвет первого")
	assert_eq(_suit_color(second), Color.BLUE, "цвет второго")
	for slot: int in PlayerPalette.COLORS.size():
		first.set_body_color(PlayerPalette.color(slot))
		assert_eq(_suit_color(first), PlayerPalette.color(slot), "цвет игрока %d" % slot)
	assert_eq(_suit_color(second), Color.BLUE, "чужая перекраска не задела")
	first.free()
	second.free()


func test_name_label_and_visibility_flags() -> void:
	var visuals: PlayerVisuals = _new_visuals()
	var label: Label3D = visuals.get_node("NameLabel") as Label3D
	var model: Node3D = visuals.get_node("Model") as Node3D
	visuals.set_display_name("Тест")
	assert_eq(label.text, "Тест", "ник")
	visuals.set_display_name("")
	assert_eq(label.text, "", "пустой ник")
	for round_index: int in 3:
		visuals.set_dead(true)
		visuals.set_dead(true)
		assert_true(not label.visible, "у мёртвого ник скрыт")
		visuals.set_dead(false)
		assert_true(label.visible, "у живого ник виден")
	visuals.set_first_person(true)
	assert_true(not model.visible and not label.visible, "своё тело и ник скрыты")
	visuals.set_dead(true)
	visuals.set_dead(false)
	assert_true(not label.visible, "ник своего игрока остаётся скрытым")
	visuals.set_first_person(false)
	assert_true(model.visible and label.visible, "чужое тело и ник видны")
	visuals.free()


## Анимацию без окна движок не запускает; здесь её кадры прогоняются вручную во всех
## состояниях, чтобы ошибка в позе не доехала до игрока незамеченной.
func test_animation_keeps_skeleton_finite() -> void:
	var visuals: PlayerVisuals = await _new_visuals_in_tree()
	var skeleton: Skeleton3D = visuals.get_node(SKELETON_PATH) as Skeleton3D
	var velocities: Array[Vector3] = [
		Vector3.ZERO, Vector3(0.0, 0.0, -5.0), Vector3(3.0, 0.0, 3.0), Vector3(0.0, 5.5, -2.0),
		Vector3(0.0, -20.0, 0.0), Vector3(1.0e9, 0.0, 0.0), Vector3(NAN, 0.0, INF),
	]
	var pitches: Array[float] = [0.0, 0.6, -1.5, 100.0, NAN, INF]
	var items: Array[PackedScene] = [null, PISTOL_SCENE, KNIFE_SCENE]
	var step: int = 0
	for mask: int in MASK_COUNT:
		visuals.set_limbs_lost(mask, false)
		visuals.set_held_item(items[step % items.size()])
		visuals.set_velocity(velocities[step % velocities.size()])
		visuals.set_look_pitch(pitches[step % pitches.size()])
		visuals.set_dead(mask % 7 == 3)
		visuals.play_attack()
		for frame: int in FRAMES_PER_STATE:
			visuals._process(FRAME_SEC)
		step += 1
		assert_true(_pose_is_finite(skeleton), "поза конечна: маска %d" % mask)
	visuals.set_limbs_lost(0)
	visuals.set_dead(true)
	visuals._process(10.0)
	assert_true(_pose_is_finite(skeleton), "поза конечна после длинного кадра")
	_free_from_tree(visuals)


func test_viewmodel_api() -> void:
	var viewmodel: Viewmodel = VIEWMODEL_SCENE.instantiate() as Viewmodel
	assert_true(viewmodel != null, "сцена вида от первого лица")
	var right: MeshInstance3D = viewmodel.get_node_or_null("Rig/Arms/ArmRight") as MeshInstance3D
	var left: MeshInstance3D = viewmodel.get_node_or_null("Rig/Arms/ArmLeft") as MeshInstance3D
	assert_true(right != null and left != null, "меши рук")
	viewmodel.set_body_color(PlayerPalette.color(3))
	viewmodel.set_held_item(null)
	viewmodel.play_attack()
	assert_eq(right.get_child_count() + left.get_child_count(), 0, "пустые руки")
	viewmodel.set_held_item(PISTOL_SCENE)
	assert_eq(right.get_child_count(), 1, "предмет в правой руке")
	viewmodel.set_limbs_lost(BodyPart.bit(BodyPart.Part.RIGHT_ARM))
	assert_eq(right.get_child_count(), 0, "правая рука потеряна: предмет убран из неё")
	assert_eq(left.get_child_count(), 1, "правая рука потеряна: предмет в левой")
	assert_true(not right.visible, "потерянная рука не рисуется")
	await _add_to_tree(viewmodel)
	var velocities: Array[Vector3] = [Vector3.ZERO, Vector3(0.0, 5.0, -5.0), Vector3(NAN, INF, 0.0)]
	for mask: int in MASK_COUNT:
		viewmodel.set_limbs_lost(mask)
		viewmodel.set_held_item(KNIFE_SCENE if mask % 3 == 0 else PISTOL_SCENE if mask % 3 == 1 else null)
		viewmodel.set_velocity(velocities[mask % velocities.size()])
		viewmodel.play_attack()
		for frame: int in FRAMES_PER_STATE:
			viewmodel._process(FRAME_SEC)
		for arm: MeshInstance3D in [right, left]:
			assert_true(arm.position.is_finite() and arm.rotation.is_finite(), "рука на месте: маска %d" % mask)
		var arms_lost: int = BodyPart.lost_arms(mask)
		var expected: int = 1 if mask % 3 != 2 and arms_lost < 2 else 0
		assert_eq(right.get_child_count() + left.get_child_count(), expected, "предметов в руках: маска %d" % mask)
		if BodyPart.is_lost(mask, BodyPart.Part.RIGHT_ARM):
			assert_true(not right.visible, "правая рука скрыта: маска %d" % mask)
		if BodyPart.is_lost(mask, BodyPart.Part.LEFT_ARM):
			assert_true(not left.visible, "левая рука скрыта: маска %d" % mask)
	_free_from_tree(viewmodel)


func test_weapon_models() -> void:
	for scene: PackedScene in [PISTOL_SCENE, KNIFE_SCENE]:
		var item: Node3D = scene.instantiate() as Node3D
		assert_true(item != null, "корень модели оружия — Node3D")
		var bounds: AABB = _mesh_bounds(item)
		# Точка хвата — в начале координат, ствол/клинок уходит вперёд, в -Z.
		assert_true(bounds.grow(0.001).has_point(Vector3.ZERO), "хват внутри модели %s" % item.name)
		assert_true(-bounds.position.z > bounds.end.z, "%s смотрит в -Z" % item.name)
		assert_true(bounds.size.z > 0.2 and bounds.size.z < 0.4, "длина %s: %s" % [item.name, bounds.size.z])
		assert_eq(PlayerVisuals.is_melee_item(item), scene == KNIFE_SCENE, "ближний бой: %s" % item.name)
		item.free()


func _new_visuals() -> PlayerVisuals:
	return VISUALS_SCENE.instantiate() as PlayerVisuals


func _new_visuals_in_tree() -> PlayerVisuals:
	var visuals: PlayerVisuals = _new_visuals()
	await _add_to_tree(visuals)
	return visuals


## Тесты стартуют из _ready запускающей сцены: в этот момент корень дерева ещё занят и детей
## не принимает, поэтому сначала пропускаем кадр.
func _add_to_tree(node: Node) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	tree.root.add_child(node)


func _free_from_tree(node: Node) -> void:
	node.get_parent().remove_child(node)
	node.free()


func _suit_color(visuals: PlayerVisuals) -> Color:
	var torso: MeshInstance3D = visuals.get_node(SKELETON_PATH.path_join("TorsoPiece")) as MeshInstance3D
	for surface: int in torso.mesh.get_surface_count():
		if torso.mesh.surface_get_material(surface).resource_name == PlayerVisuals.SUIT_MATERIAL_NAME:
			return (torso.get_surface_override_material(surface) as StandardMaterial3D).albedo_color
	return Color.BLACK


## Общие габариты всех мешей под узлом, в его осях (меши модели лежат без смещений).
func _mesh_bounds(root: Node) -> AABB:
	var bounds: AABB = AABB()
	var first: bool = true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_bounds: AABB = (node as MeshInstance3D).mesh.get_aabb()
		bounds = mesh_bounds if first else bounds.merge(mesh_bounds)
		first = false
	return bounds


func _pose_is_finite(skeleton: Skeleton3D) -> bool:
	for index: int in skeleton.get_bone_count():
		if not skeleton.get_bone_global_pose(index).is_finite():
			return false
	return true
