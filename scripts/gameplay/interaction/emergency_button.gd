class_name EmergencyButton
extends Interactable
## Тревожная кнопка: живой игрок удерживает E и созывает собрание.
## Сколько раз за матч её можно нажать, общая пауза и запрет на время саботажа — в
## Game.meeting.can_press_button(): сервер проверяет про любого игрока, клиент — про своего,
## поэтому подсказка появляется, только когда нажатие сработает.
## На экране клиента колпак над кнопкой откинут, пока свой игрок может её нажать.

## На сколько градусов откидывается колпак, когда кнопка доступна.
@export_range(0.0, 170.0, 1.0) var cover_open_degrees: float = 105.0
## Скорость колпака, градусов в секунду.
@export_range(10.0, 720.0, 1.0) var cover_speed_degrees: float = 240.0

## Колпак модели; null — у модели его нет, тогда кнопка просто не двигается.
@onready var _cover: Node3D = get_node_or_null(^"Model/Cover") as Node3D


func _ready() -> void:
	# Серверу и ботам без окна показывать нечего.
	set_process(_cover != null and not Net.is_server() and DisplayServer.get_name() != "headless")


## Клиент: колпак плавно открывается и закрывается вслед за доступностью кнопки.
func _process(delta: float) -> void:
	var is_open: bool = Game.meeting.can_press_button(Net.local_id())
	var target: float = deg_to_rad(cover_open_degrees) if is_open else 0.0
	_cover.rotation.x = move_toward(_cover.rotation.x, target, deg_to_rad(cover_speed_degrees) * delta)


func can_interact(player: Player) -> bool:
	return player.life == Player.Life.ALIVE and Game.meeting.can_press_button(player.peer_id)


func server_interact(player: Player) -> void:
	Game.meeting.server_call(player.peer_id, Meeting.Reason.BUTTON)
