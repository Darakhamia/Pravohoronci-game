class_name BodyPart
extends RefCounted
## Части тела игрока: по ним считается урон и отлетают конечности.

enum Part { HEAD, TORSO, LEFT_ARM, RIGHT_ARM, LEFT_LEG, RIGHT_LEG }

## Конечности, которые можно потерять.
const LIMBS: Array[Part] = [Part.LEFT_ARM, Part.RIGHT_ARM, Part.LEFT_LEG, Part.RIGHT_LEG]
const ARM_COUNT: int = 2
const LEG_COUNT: int = 2


## Бит части тела в маске потерянных конечностей.
static func bit(part: Part) -> int:
	return 1 << part


static func is_lost(mask: int, part: Part) -> bool:
	return mask & bit(part) != 0


static func lost_arms(mask: int) -> int:
	return int(is_lost(mask, Part.LEFT_ARM)) + int(is_lost(mask, Part.RIGHT_ARM))


static func lost_legs(mask: int) -> int:
	return int(is_lost(mask, Part.LEFT_LEG)) + int(is_lost(mask, Part.RIGHT_LEG))
