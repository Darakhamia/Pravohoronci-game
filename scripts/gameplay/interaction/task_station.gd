class_name TaskStation
extends Interactable
## Станция задания на карте. Виды заданий и их проверка — в наследниках и в Game.tasks;
## карта сообщает TaskBoard номера всех станций.

## Название задания в списке игрока: «Починить проводку».
@export var title: String = ""
## Где находится станция — показывается рядом с названием: «Реактор».
@export var location: String = ""


## Пользоваться станцией может только тот, у кого это задание ещё не сделано.
func can_interact(player: Player) -> bool:
	return Game.tasks.is_pending(player.peer_id, interact_id)

