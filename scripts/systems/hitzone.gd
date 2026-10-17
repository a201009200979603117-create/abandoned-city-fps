extends RefCounted
# 命中部位判定：依擊中點相對於目標腳底的高度（已除以目標縮放）分為頭 / 身 / 腿

const HEAD_HEIGHT: float = 1.45
const LEG_HEIGHT: float = 0.62
const MULT: Dictionary = {"head": 2.0, "body": 1.0, "leg": 0.75}


static func is_living(target: Object) -> bool:
	return target is Node and ((target as Node).is_in_group("enemies") or (target as Node).is_in_group("br_bots"))


static func zone_of(target: Node3D, hit_pos: Vector3) -> String:
	var sc := maxf(target.scale.y, 0.1)
	var h := (hit_pos.y - target.global_position.y) / sc
	if h >= HEAD_HEIGHT:
		return "head"
	if h < LEG_HEIGHT:
		return "leg"
	return "body"


# 狙擊槍爆頭倍率更高
static func multiplier(zone: String, weapon_id: String) -> float:
	var m: float = MULT.get(zone, 1.0)
	if zone == "head" and weapon_id == "sniper":
		m = 3.0
	return m
