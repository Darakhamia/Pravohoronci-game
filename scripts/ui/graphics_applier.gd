class_name GraphicsApplier
extends Node
## Применяет уровень качества картинки (GraphicsPresets) к окну игры и к окружению каждой
## сцены, где есть WorldEnvironment: к картам матча и к сценам предпросмотра. Узел создаёт
## Settings на клиенте с окном; сервер и запуски без окна обходятся без него.
## Уровень берётся из настроек игрока, а флаг запуска --quality=low|medium|high подменяет его
## на один запуск (в файл настроек не попадает).

## Метка узла WorldEnvironment: окружение, с которым он пришёл из сцены.
const AUTHORED_META: StringName = &"authored_environment"
const QUALITY_KEY: StringName = &"graphics_quality"

## Уровень из флага запуска; -1 — флага нет.
var _forced_quality: int = GraphicsPresets.from_command_line()


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	Settings.changed.connect(_on_settings_changed)
	apply()


## Какой уровень действует сейчас.
func get_quality() -> GraphicsPresets.Quality:
	if _forced_quality >= 0:
		return GraphicsPresets.sanitize(_forced_quality)
	return Settings.graphics_quality


## Применить уровень ко всему, что уже есть в дереве.
func apply() -> void:
	var quality: GraphicsPresets.Quality = get_quality()
	var viewport: Viewport = get_tree().root
	viewport.msaa_3d = GraphicsPresets.get_msaa(quality)
	viewport.screen_space_aa = GraphicsPresets.get_screen_space_aa(quality)
	RenderingServer.gi_set_use_half_resolution(GraphicsPresets.uses_half_resolution_gi(quality))
	RenderingServer.positional_soft_shadow_filter_set_quality(
			GraphicsPresets.get_shadow_quality(quality, GraphicsPresets.POSITIONAL_SHADOW_SETTING))
	RenderingServer.directional_soft_shadow_filter_set_quality(
			GraphicsPresets.get_shadow_quality(quality, GraphicsPresets.DIRECTIONAL_SHADOW_SETTING))
	for node: Node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_tune(node as WorldEnvironment)


func _tune(node: WorldEnvironment) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if not node.has_meta(AUTHORED_META):
		if node.environment == null:
			return
		node.set_meta(AUTHORED_META, node.environment)
	var authored: Environment = node.get_meta(AUTHORED_META) as Environment
	node.environment = GraphicsPresets.tune_environment(authored, get_quality())


func _on_node_added(node: Node) -> void:
	var world_environment: WorldEnvironment = node as WorldEnvironment
	if world_environment != null:
		# Отложенно: узел входит в дерево раньше, чем сцена докладывает о готовности.
		_tune.call_deferred(world_environment)


func _on_settings_changed(key: StringName) -> void:
	if key == QUALITY_KEY:
		apply()
