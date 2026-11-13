class_name HudTasks
extends PanelContainer
## Общий прогресс экипажа и задания игрока: невыполненные сверху, выполненные тонут вниз.
## Панель одна и для экипажа, и для предателя: она показывает то, что ей передали
## (предателю — задания «для прикрытия»). Скрыта, пока её не включит игра.

const TEXT_PROGRESS: String = "%d/%d"

var _rows: Array[HudTaskRow] = []

@onready var _list: VBoxContainer = %List
@onready var _progress_count: Label = %ProgressCount
@onready var _progress_bar: ProgressBar = %ProgressBar


## titles — названия заданий игрока, done — выполнено ли каждое (по тем же номерам).
## Пустой список оставляет от панели только прогресс экипажа.
func set_tasks(titles: PackedStringArray, done: Array[bool]) -> void:
	while _rows.size() < titles.size():
		var row: HudTaskRow = HudTaskRow.new()
		_list.add_child(row)
		_rows.append(row)
	var order: PackedInt32Array = display_order(titles.size(), done)
	for slot: int in _rows.size():
		var row: HudTaskRow = _rows[slot]
		row.visible = slot < order.size()
		if row.visible:
			var index: int = order[slot]
			row.set_task(titles[index], index < done.size() and done[index])
	_list.visible = not titles.is_empty()


## Названия показанных заданий сверху вниз — как их видит игрок.
func get_shown_titles() -> PackedStringArray:
	var titles: PackedStringArray = []
	for row: HudTaskRow in _rows:
		if row.visible:
			titles.append(row.get_title())
	return titles


## Отметки «выполнено» показанных заданий сверху вниз.
func get_shown_done() -> Array[bool]:
	var done: Array[bool] = []
	for row: HudTaskRow in _rows:
		if row.visible:
			done.append(row.is_done())
	return done


## Порядок показа заданий: сначала невыполненные, потом выполненные; внутри групп — как передали.
## Возвращает номера заданий; у кого в done нет значения, тот считается невыполненным.
static func display_order(count: int, done: Array[bool]) -> PackedInt32Array:
	var order: PackedInt32Array = []
	for wanted: bool in [false, true]:
		for index: int in count:
			if (index < done.size() and done[index]) == wanted:
				order.append(index)
	return order


## Сколько заданий выполнил весь экипаж.
func set_progress(done_count: int, total: int) -> void:
	var safe_total: int = maxi(total, 1)
	var safe_done: int = clampi(done_count, 0, safe_total)
	_progress_count.text = TEXT_PROGRESS % [safe_done, safe_total]
	_progress_bar.max_value = safe_total
	_progress_bar.value = safe_done
