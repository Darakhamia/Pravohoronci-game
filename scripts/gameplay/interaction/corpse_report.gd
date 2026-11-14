class_name CorpseReport
extends Interactable
## Тело убитого игрока: живой игрок рядом может сообщить о нём и созвать собрание.
## Узел Corpse внутри Player; interact_id — минус peer_id хозяина тела.

@onready var _owner_player: Player = get_parent() as Player


func can_interact(player: Player) -> bool:
	return (_owner_player.life == Player.Life.CORPSE and player != _owner_player
			and player.life == Player.Life.ALIVE)


func server_interact(player: Player) -> void:
	Game.meeting.server_call(player.peer_id, Meeting.Reason.BODY, _owner_player.peer_id)
