extends TestCase
## Каждый скрипт, сцена и ресурс проекта должен загружаться. Импорт и основной сценарий
## компилируют только то, до чего дотягивается главная сцена, а новый скрипт с ошибкой
## или без типов (untyped_declaration — ошибка) иначе доехал бы до main незамеченным.

const ROOT_DIR: String = "res://"
## Сторонний код: к нему правила проекта не относятся.
const SKIPPED_DIRS: PackedStringArray = ["addons"]
const CHECKED_EXTENSIONS: PackedStringArray = ["gd", "tscn", "tres"]


func test_every_script_scene_and_resource_loads() -> void:
	var files: PackedStringArray = _collect(ROOT_DIR)
	assert_true(not files.is_empty(), "в проекте найдены файлы для проверки")
	for path: String in files:
		var resource: Resource = load(path)
		if resource == null:
			assert_true(false, "%s не загружается" % path)
			continue
		var script: GDScript = resource as GDScript
		if script != null:
			assert_true(script.can_instantiate(), "%s не компилируется (ошибка разбора или объявление без типа)" % path)


func _collect(dir_path: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for file: String in DirAccess.get_files_at(dir_path):
		if CHECKED_EXTENSIONS.has(file.get_extension()):
			result.append(dir_path.path_join(file))
	for dir_name: String in DirAccess.get_directories_at(dir_path):
		# Папки с точкой — служебные (.godot, .git).
		if dir_name.begins_with(".") or SKIPPED_DIRS.has(dir_name):
			continue
		result.append_array(_collect(dir_path.path_join(dir_name)))
	return result
