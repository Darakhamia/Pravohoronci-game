class_name TestSwitch
extends Interactable
## Предмет для сценарных тестов: каждое срабатывание увеличивает общее состояние на единицу.


func server_interact(_player: Player) -> void:
	server_set_state(state + 1)
