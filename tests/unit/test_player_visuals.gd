extends TestCase
## PlayerVisuals и Viewmodel без окна: сервер и боты создают те же сцены, поэтому каждый
## публичный метод обязан работать без рендера, до входа в дерево и с любым мусором на входе.

const VISUALS_SCENE: PackedScene = preload("res://scenes/characters/player_visuals.tscn")
const VIEWMODEL_SCENE: PackedScene = preload("res://scenes/characters/viewmodel.tscn")
const BURST_SCENE: PackedScene = preload("res://scenes/characters/limb_burst.tscn")
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
const BODY_MESHES: PackedStringArray = ["HeadPiece", "VisorGlass", "FacePlate", "TorsoPiece", "PelvisPiece"]
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
const HEAD_CENTER_HEIGHT: float = 1.62
const SHOULDER: Vector2 = Vector2(0.3, 1.42)
const HIP: Vector2 = Vector2(0.11, 0.92)
const FACE_SIZE: float = 0.24
## Бюджет модели: треугольников на персонажа и поверхностей (вызовов отрисовки) на меш.
const MAX_TRIANGLES: int = 27000
const MAX_SURFACES: int = 12
const MATERIAL_DIR: String = "res://resources/materials/characters/"
## Сколько кадров даём позе прицеливания, чтобы она установилась.
const AIM_SETTLE_FRAMES: int = 90
const AIM_TOLERANCE: float = 0.06
## Кулак второй руки лежит вплотную к кулаку с пистолетом.
const SUPPORT_MAX_DISTANCE: float = 0.09
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
	# У рук есть формы кисти: кулак вокруг рукояти и хват пистолета.
	for arm_name: String in ["ArmLeft", "ArmRight"]:
		var arm: MeshInstance3D = visuals.get_node(SKELETON_PATH.path_join(arm_name)) as MeshInstance3D
		for shape: StringName in [PlayerVisuals.HAND_GRIP_SHAPE, PlayerVisuals.HAND_TRIGGER_SHAPE]:
			assert_true(arm.find_blend_shape_by_name(shape) != -1, "форма %s у %s" % [shape, arm_name])
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
	# Перёд модели — -Z: лицевая пластина стоит перед осью шлема. На неё ляжет фото 0.24 x 0.24 м.
	var face_bounds: AABB = face.mesh.get_aabb()
	assert_true(face_bounds.get_center().z < 0.0, "лицо смотрит в -Z")
	assert_true(absf(face_bounds.size.x - FACE_SIZE) < 0.005 and absf(face_bounds.size.y - FACE_SIZE) < 0.005,
			"лицевая пластина 0.24 x 0.24: %s" % face_bounds.size)
	var head: AABB = (visuals.get_node(SKELETON_PATH.path_join("HeadPiece")) as MeshInstance3D).mesh.get_aabb()
	assert_true(absf(head.get_center().y - HEAD_CENTER_HEIGHT) < METRIC_TOLERANCE, "центр шлема: %s" % head.get_center().y)
	var skeleton: Skeleton3D = visuals.get_node(SKELETON_PATH) as Skeleton3D
	for side: float in [-1.0, 1.0]:
		var prefix: String = "Left" if side < 0.0 else "Right"
		var shoulder: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone(prefix + "UpperArm")).origin
		assert_true(Vector2(shoulder.x, shoulder.y).distance_to(Vector2(SHOULDER.x * side, SHOULDER.y)) < METRIC_TOLERANCE,
				"плечо %s: %s" % [prefix, shoulder])
		var hip: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone(prefix + "UpperLeg")).origin
		assert_true(Vector2(hip.x, hip.y).distance_to(Vector2(HIP.x * side, HIP.y)) < METRIC_TOLERANCE,
				"бедро %s: %s" % [prefix, hip])
	visuals.free()


## Материалы модели приходят из общей библиотеки (подмена по имени при импорте), а не из .glb;
## костюм текстурирован и остаётся одним материалом, который красится под игрока.
func test_model_uses_material_library() -> void:
	var visuals: PlayerVisuals = _new_visuals()
	var triangles: int = 0
	for node: Node in visuals.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		assert_true(mesh.get_surface_count() <= MAX_SURFACES, "поверхностей в %s: %d" % [node.name, mesh.get_surface_count()])
		for surface: int in mesh.get_surface_count():
			var material: Material = mesh.surface_get_material(surface)
			assert_true(material != null and material.resource_path.begins_with(MATERIAL_DIR),
					"материал %s/%d из библиотеки: %s" % [node.name, surface, material.resource_path if material != null else "нет"])
			triangles += int(mesh.surface_get_array_index_len(surface) / 3.0)
	assert_true(triangles > 0 and triangles <= MAX_TRIANGLES, "треугольников в модели: %d" % triangles)
	var suit: StandardMaterial3D = PlayerVisuals.make_suit_material(visuals.get_node("Model"))
	assert_eq(suit.resource_name, PlayerVisuals.SUIT_MATERIAL_NAME, "копия материала костюма")
	assert_true(suit.albedo_texture != null and suit.normal_texture != null, "костюм с текстурами")
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


## Нож лежит в кулаке иначе, чем пистолет: клинок выходит со стороны большого пальца.
func test_melee_item_is_turned_in_grip() -> void:
	var visuals: PlayerVisuals = _new_visuals()
	visuals.set_held_item(PISTOL_SCENE)
	var grip: Node = visuals.get_node(RIGHT_GRIP_PATH)
	assert_true((grip.get_child(0) as Node3D).basis.is_equal_approx(Basis.IDENTITY), "пистолет лежит по осям ладони")
	visuals.set_held_item(KNIFE_SCENE)
	var blade: Vector3 = (grip.get_child(0) as Node3D).basis * Vector3.FORWARD
	assert_true(blade.is_equal_approx(Vector3.UP), "клинок идёт вдоль кулака: %s" % blade)
	visuals.free()


## Пистолет держат двумя руками, и ствол смотрит туда же, куда игрок, — на бегу тоже.
func test_aim_follows_look_pitch() -> void:
	var visuals: PlayerVisuals = await _new_visuals_in_tree()
	var skeleton: Skeleton3D = visuals.get_node(SKELETON_PATH) as Skeleton3D
	visuals.set_held_item(PISTOL_SCENE)
	for velocity: Vector3 in [Vector3.ZERO, Vector3(0.0, 0.0, -5.0)]:
		for pitch: float in [0.0, 0.5, -0.6]:
			visuals.set_velocity(velocity)
			visuals.set_look_pitch(pitch)
			for frame: int in AIM_SETTLE_FRAMES:
				visuals._process(FRAME_SEC)
			var right: Transform3D = _grip_in_model(visuals, skeleton, RIGHT_GRIP_PATH, "RightHand")
			var left: Transform3D = _grip_in_model(visuals, skeleton, LEFT_GRIP_PATH, "LeftHand")
			var barrel: Vector3 = right.basis * Vector3.FORWARD
			var expected: Vector3 = Vector3(0.0, sin(pitch), -cos(pitch))
			assert_true(barrel.distance_to(expected) < AIM_TOLERANCE, "ствол по взгляду %.1f: %s" % [pitch, barrel])
			assert_true(right.origin.z < -0.25, "пистолет вынесен вперёд: %s" % right.origin)
			assert_true(left.origin.distance_to(right.origin) < SUPPORT_MAX_DISTANCE,
					"вторая рука на пистолете: %s" % left.origin.distance_to(right.origin))
	# Кисти сжаты по делу: указательный палец на спуске, вторая рука обнимает первую.
	assert_true(_hand_shape(visuals, "ArmRight", PlayerVisuals.HAND_TRIGGER_SHAPE) > 0.95, "палец на спуске")
	assert_true(_hand_shape(visuals, "ArmRight", PlayerVisuals.HAND_GRIP_SHAPE) < 0.05, "правая кисть не в кулаке")
	assert_true(_hand_shape(visuals, "ArmLeft", PlayerVisuals.HAND_GRIP_SHAPE) > 0.95, "вторая кисть обхватывает")
	visuals.set_held_item(KNIFE_SCENE)
	for frame: int in AIM_SETTLE_FRAMES:
		visuals._process(FRAME_SEC)
	assert_true(_hand_shape(visuals, "ArmRight", PlayerVisuals.HAND_GRIP_SHAPE) > 0.95, "нож в кулаке")
	assert_true(_hand_shape(visuals, "ArmLeft", PlayerVisuals.HAND_GRIP_SHAPE) < 0.05, "свободная кисть расслаблена")
	visuals.set_held_item(PISTOL_SCENE)
	# Без второй руки пистолет держат одной: оставшаяся по-прежнему целится.
	visuals.set_limbs_lost(BodyPart.bit(BodyPart.Part.LEFT_ARM), false)
	visuals.set_look_pitch(0.0)
	for frame: int in AIM_SETTLE_FRAMES:
		visuals._process(FRAME_SEC)
	var alone: Vector3 = _grip_in_model(visuals, skeleton, RIGHT_GRIP_PATH, "RightHand").basis * Vector3.FORWARD
	assert_true(alone.distance_to(Vector3.FORWARD) < AIM_TOLERANCE, "ствол вперёд одной рукой: %s" % alone)
	_free_from_tree(visuals)


## Искры из разъёма — отдельная сцена: загружается и удаляется без окна (без него её никто не запускает).
func test_limb_burst_scene() -> void:
	var burst: LimbBurst = BURST_SCENE.instantiate() as LimbBurst
	assert_true(burst != null, "сцена вспышки")
	for path: String in ["Sparks", "Bits", "Vapor"]:
		var particles: GPUParticles3D = burst.get_node_or_null(path) as GPUParticles3D
		assert_true(particles != null and not particles.emitting and particles.one_shot, "частицы %s разовые" % path)
	# Искры ярче единицы: только так их подхватывает свечение кадра.
	var sparks: GPUParticles3D = burst.get_node("Sparks") as GPUParticles3D
	var spark_material: StandardMaterial3D = (sparks.draw_pass_1 as PrimitiveMesh).material as StandardMaterial3D
	assert_true(spark_material != null and spark_material.albedo_color.r > 2.0, "искры светятся в HDR")
	assert_true(burst.get_node_or_null("Floor") is GPUParticlesCollisionBox3D, "пол для искр")
	burst.free()


func test_body_color_is_per_instance() -> void:
	var first: PlayerVisuals = _new_visuals()
	var second: PlayerVisuals = _new_visuals()
	first.set_body_color(Color.RED)
	second.set_body_color(Color.BLUE)
	# Краска костюма — цвет игрока, приглушённый под освещение сцены (PlayerVisuals.suit_paint_color).
	assert_eq(_suit_color(first), PlayerVisuals.suit_paint_color(Color.RED), "цвет первого")
	assert_eq(_suit_color(second), PlayerVisuals.suit_paint_color(Color.BLUE), "цвет второго")
	var paints: Array[Color] = []
	for slot: int in PlayerPalette.COLORS.size():
		var color: Color = PlayerPalette.color(slot)
		first.set_body_color(color)
		var paint: Color = _suit_color(first)
		assert_eq(paint, PlayerVisuals.suit_paint_color(color), "цвет игрока %d" % slot)
		# Краска темнее цвета интерфейса, но оттенок тот же: игрока узнают по цвету.
		assert_true(paint.v < color.v and paint.v > 0.5, "краска %d темнее цвета игрока: %s" % [slot, paint.v])
		assert_true(absf(angle_difference(paint.h * TAU, color.h * TAU)) < 0.12, "оттенок краски %d" % slot)
		for other: Color in paints:
			var gap: Vector3 = Vector3(paint.r - other.r, paint.g - other.g, paint.b - other.b)
			assert_true(gap.length() > 0.15, "краски игроков различимы: %d" % slot)
		paints.append(paint)
	assert_eq(_suit_color(second), PlayerVisuals.suit_paint_color(Color.BLUE), "чужая перекраска не задела")
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
	# Рука — три звена: кисть, предплечье, плечо.
	var links: Dictionary[MeshInstance3D, Array] = {right: [], left: []}
	for link_name: String in ["Forearm", "Upper"]:
		for hand: MeshInstance3D in [right, left]:
			var link: MeshInstance3D = viewmodel.get_node_or_null(
					"Rig/Arms/%s%s" % [link_name, "Right" if hand == right else "Left"]) as MeshInstance3D
			assert_true(link != null and link.mesh != null, "звено %s" % link_name)
			links[hand].append(link)
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
			for link: MeshInstance3D in links[arm]:
				assert_true(link.transform.is_finite(), "звено руки на месте: маска %d" % mask)
				assert_eq(link.visible, arm.visible, "звено скрыто вместе с кистью: маска %d" % mask)
				assert_true(link.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						and link.layers == Viewmodel.VIEW_RENDER_LAYER, "руки без теней и на своём слое")
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
		for node: Node in item.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (node as MeshInstance3D).mesh
			for surface: int in mesh.get_surface_count():
				assert_true(mesh.surface_get_material(surface).resource_path.begins_with(MATERIAL_DIR),
						"материал %s/%d из библиотеки" % [item.name, surface])
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


## Положение ладони в осях модели (узел-вложение обновляется только в дереве с кадрами,
## поэтому считаем от позы кости).
func _grip_in_model(visuals: PlayerVisuals, skeleton: Skeleton3D, grip_path: String, bone: String) -> Transform3D:
	var grip: Node3D = visuals.get_node(grip_path) as Node3D
	return skeleton.get_bone_global_pose(skeleton.find_bone(bone)) * grip.transform


## Вес формы кисти (shape key) у меша руки.
func _hand_shape(visuals: PlayerVisuals, arm_name: String, shape: StringName) -> float:
	var arm: MeshInstance3D = visuals.get_node(SKELETON_PATH.path_join(arm_name)) as MeshInstance3D
	return arm.get_blend_shape_value(arm.find_blend_shape_by_name(shape))


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
