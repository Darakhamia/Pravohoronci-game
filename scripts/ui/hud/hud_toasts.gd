class_name HudToasts
extends VBoxContainer
## Стопка коротких уведомлений вверху по центру: «Готово: ...», «Неверный код», «Потеряна
## левая нога». Новое встаёт снизу, каждое гаснет само. Одинаковый текст не дублируется —
## у показанного уведомления просто начинается новый отсчёт. Мест столько, сколько
## уведомлений лежит в сцене; когда заняты все, новое вытесняет самое старое.

## Сколько секунд уведомление держится на экране.
const SHOW_SEC: float = 3.5

## Уведомления в порядке показа: первое — самое старое.
var _shown: Array[HudToast] = []
var _toasts: Array[HudToast] = []


func _ready() -> void:
	for child: Node in get_children():
		var toast: HudToast = child as HudToast
		if toast != null:
			_toasts.append(toast)
			toast.expired.connect(_on_toast_expired.bind(toast))


## seconds — сколько держать уведомление на экране (по умолчанию SHOW_SEC).
func show_toast(text: String, kind: HudToast.Kind, seconds: float = SHOW_SEC) -> void:
	if text.is_empty() or _toasts.is_empty():
		return
	var toast: HudToast = _find_shown(text)
	if toast == null:
		toast = _take_free()
		_shown.append(toast)
		move_child(toast, -1)
	toast.show_toast(text, kind, seconds)


## Убирает все уведомления сразу (матч закончился, HUD скрыт).
func clear() -> void:
	for toast: HudToast in _toasts:
		toast.hide_toast()
	_shown.clear()


## Тексты показанных уведомлений сверху вниз.
func get_texts() -> PackedStringArray:
	var texts: PackedStringArray = []
	for toast: HudToast in _shown:
		texts.append(toast.get_text())
	return texts


func _find_shown(text: String) -> HudToast:
	for toast: HudToast in _shown:
		if toast.get_text() == text:
			return toast
	return null


## Свободное место; если их нет — самое старое уведомление.
func _take_free() -> HudToast:
	for toast: HudToast in _toasts:
		if not _shown.has(toast):
			return toast
	var oldest: HudToast = _shown.pop_front() as HudToast
	oldest.hide_toast()
	return oldest


func _on_toast_expired(toast: HudToast) -> void:
	_shown.erase(toast)
