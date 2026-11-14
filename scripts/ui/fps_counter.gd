class_name FpsCounter
extends CanvasLayer
## Счётчик кадров в углу экрана: F3 показывает и прячет его, выбор запоминается в настройках.
## Нужен, чтобы проверить частоту кадров на своей видеокарте и подобрать уровень графики.
## Узел создаёт Settings на клиенте с окном.

const THEME_PATH: String = "res://resources/ui/theme.tres"
const LABEL_STYLE: StringName = &"LabelCaption"
const TOGGLE_KEY: Key = KEY_F3
## Поверх всех экранов игры.
const LAYER: int = 100
const MARGIN: float = 12.0
const WIDTH: float = 220.0
const UPDATE_INTERVAL_SEC: float = 0.25
const MSEC_PER_SEC: float = 1000.0
const SHOW_KEY: StringName = &"show_fps"

var _label: Label = null
var _since_update: float = UPDATE_INTERVAL_SEC


func _ready() -> void:
	layer = LAYER
	Settings.changed.connect(_on_settings_changed)
	_set_shown(Settings.show_fps)


func _process(delta: float) -> void:
	_since_update += delta
	if _since_update < UPDATE_INTERVAL_SEC:
		return
	_since_update = 0.0
	_label.text = format(Engine.get_frames_per_second())


## _input, а не опрос действий: это не действие игрока, и работать оно должно в меню тоже.
func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == TOGGLE_KEY:
		Settings.show_fps = not Settings.show_fps
		Settings.save()


## Текст счётчика: кадры в секунду и время кадра.
static func format(frames_per_second: float) -> String:
	if frames_per_second <= 0.0:
		return "— к/с"
	return "%d к/с · %.1f мс" % [roundi(frames_per_second), MSEC_PER_SEC / frames_per_second]


func _set_shown(shown: bool) -> void:
	if shown and _label == null:
		_label = _make_label()
		add_child(_label)
	if _label != null:
		_label.visible = shown
	set_process(shown)


func _make_label() -> Label:
	var label: Label = Label.new()
	# Тему грузим здесь, а не через preload: при первом импорте свежего клона шрифты темы
	# ещё не импортированы, а скрипты автозагрузки уже компилируются.
	label.theme = load(THEME_PATH) as Theme
	label.theme_type_variation = LABEL_STYLE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	label.offset_left = -WIDTH - MARGIN
	label.offset_right = -MARGIN
	label.offset_top = MARGIN
	return label


func _on_settings_changed(key: StringName) -> void:
	if key == SHOW_KEY:
		_set_shown(Settings.show_fps)
