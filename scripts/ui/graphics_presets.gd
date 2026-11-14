class_name GraphicsPresets
extends RefCounted
## Уровни качества картинки. Карты и окружение настроены под «Высокое»; остальные уровни
## получаются из него выключением самых дорогих эффектов. Частота кадров на RTX 3060 не
## измерялась (CLAUDE.md, раздел 6): если её не хватает, игрок снижает уровень в главном меню.
## Только чистые функции: об узлах знают лишь то, что им передали. Применяет их GraphicsApplier.

enum Quality { LOW, MEDIUM, HIGH }

const DEFAULT_QUALITY: Quality = Quality.HIGH
## Названия уровней для интерфейса, по порядку Quality.
const NAMES: PackedStringArray = ["Низкая", "Средняя", "Высокая"]
## Значения флага запуска --quality=..., по порядку Quality.
const FLAG: String = "--quality"
const FLAG_VALUES: PackedStringArray = ["low", "medium", "high"]

## На низком уровне отскоков света (SDFGI) нет. Чтобы углы не проваливались в черноту, ровный
## свет окружения поднимается до этой яркости.
const LOW_AMBIENT_ENERGY: float = 0.9
## Настройки проекта, из которых берётся сглаживание высокого уровня.
const MSAA_SETTING: String = "rendering/anti_aliasing/quality/msaa_3d"
const SCREEN_AA_SETTING: String = "rendering/anti_aliasing/quality/screen_space_aa"
const POSITIONAL_SHADOW_SETTING: String = "rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality"
const DIRECTIONAL_SHADOW_SETTING: String = "rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"


## Любое число -> уровень: чужое значение из файла настроек заменяем уровнем по умолчанию.
static func sanitize(value: int) -> Quality:
	if value < 0 or value >= Quality.size():
		return DEFAULT_QUALITY
	return value as Quality


static func quality_name(quality: Quality) -> String:
	return NAMES[quality]


## Следующий уровень по кругу: кнопка в меню перебирает их нажатиями.
static func next(quality: Quality) -> Quality:
	return ((quality + 1) % Quality.size()) as Quality


## Уровень из флага запуска --quality=low|medium|high; -1, если флага нет или значение чужое.
static func from_command_line() -> int:
	return FLAG_VALUES.find(CmdArgs.get_value(FLAG).to_lower())


## Окружение для уровня. Высокий уровень — само авторское окружение; для остальных
## возвращается его изменённая копия, авторский ресурс не трогаем.
static func tune_environment(authored: Environment, quality: Quality) -> Environment:
	if authored == null or quality == Quality.HIGH:
		return authored
	var tuned: Environment = authored.duplicate() as Environment
	# Отражения в экранном пространстве и непрямой свет от соседних поверхностей — украшение.
	tuned.ssr_enabled = false
	tuned.ssil_enabled = false
	if quality == Quality.LOW:
		tuned.sdfgi_enabled = false
		tuned.volumetric_fog_enabled = false
		tuned.ambient_light_energy = maxf(authored.ambient_light_energy, LOW_AMBIENT_ENERGY)
	return tuned


## Сглаживание окна игры: на высоком уровне — как в настройках проекта.
static func get_msaa(quality: Quality) -> Viewport.MSAA:
	match quality:
		Quality.LOW:
			return Viewport.MSAA_DISABLED
		Quality.MEDIUM:
			return Viewport.MSAA_2X
	return ProjectSettings.get_setting(MSAA_SETTING, Viewport.MSAA_DISABLED) as Viewport.MSAA


## Дешёвое сглаживание поверх кадра: без MSAA оно обязательно, иначе мелкие детали рябят.
static func get_screen_space_aa(quality: Quality) -> Viewport.ScreenSpaceAA:
	if quality == Quality.HIGH:
		return ProjectSettings.get_setting(SCREEN_AA_SETTING, Viewport.SCREEN_SPACE_AA_DISABLED) as Viewport.ScreenSpaceAA
	return Viewport.SCREEN_SPACE_AA_FXAA


## Считать ли отскоки света в половинном разрешении.
static func uses_half_resolution_gi(quality: Quality) -> bool:
	return quality != Quality.HIGH


## Качество мягких теней: на низком уровне — самое дешёвое сглаживание края.
static func get_shadow_quality(quality: Quality, setting: String) -> RenderingServer.ShadowQuality:
	if quality == Quality.LOW:
		return RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW
	return ProjectSettings.get_setting(setting, RenderingServer.SHADOW_QUALITY_SOFT_LOW) as RenderingServer.ShadowQuality
