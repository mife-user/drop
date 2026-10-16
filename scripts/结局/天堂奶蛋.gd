extends Node3D

## 天堂奶蛋：让挂在本节点下的每只奶蛋在屋里自己随机蹦跶 —— 走完一段就换下一个落点，一直循环。
##
## 主场景里奶蛋是「一只实体 + 一个调度器」的写法（milkegg_encounter.gd），因为那边要管
## 它什么时候出场、什么时候离场、还要躲开泳池和镜头外；**天堂这一屋子不需要那套** ——
## 屋子是封闭的，玩家随时能看见它们，「一直蹦」就够了。
##
## 每只奶蛋用的一律是 milkegg.tscn 现成的 begin_crossing() / crossing_finished 信号，
## 本脚本只负责「挑下一个落点、什么时候挑」，一行都不改奶蛋自己。
## （奶蛋进树时会自己 deactivate() 藏起来，所以**必须有谁来调 begin_crossing**，
## 否则它们永远是隐形的 —— 这就是天堂里一直看不到奶蛋的原因。）
##
## **活动范围直接量地板那个碰撞盒**，不另配尺寸：把「房子/底盘」下的 CollisionShape3D
## 拖进 bounds 即可 —— 以后你把房子改大改小，只要那个碰撞盒跟着改，奶蛋自己就跟对了。
##
## 落点会先往下打一条射线确认踩得到地面，打不到就换一个，所以奶蛋不会跳到半空或掉出去。

## 活动范围：用它的碰撞盒（得是 BoxShape3D）当矩形区域。拖「房子/底盘/实体/CollisionShape3D」过来。
## 留空 = 不挑落点，所有奶蛋原地不动（但还是会现身，可以用来单独看模型）。
@export var bounds: CollisionShape3D
## 落点离区域边缘留多少米，免得奶蛋贴着墙根蹦。
@export_range(0.0, 5.0, 0.1) var margin: float = 1.0
## 每段最远走多远（米）；比这近的落点不要（太近等于原地打转）。
@export_range(1.0, 30.0, 0.5) var leg_distance: float = 6.0
## 每段最短走多远（米）。
@export_range(0.2, 10.0, 0.1) var min_distance: float = 1.5
## 一脚踩到落点之后歇多久再挑下一段（秒），在下面两个数之间随机取 —— 让 8 只不要同步。
@export_range(0.0, 10.0, 0.1) var rest_min: float = 0.4
@export_range(0.0, 10.0, 0.1) var rest_max: float = 2.2
## 挑落点最多试几次；连着挑不到就原地歇一会儿重来。
@export_range(1, 64, 1) var pick_attempts: int = 24
## 用什么碰撞层找地面。默认「世界」（第 1 层），和天堂里那些 StaticBody3D 一致。
@export_flags_3d_physics var ground_mask: int = 1

var _eggs: Array[CharacterBody3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# 子节点的 _ready 先于本节点跑完，所以这时每只奶蛋都已经 deactivate() 过、收好了比例
	for child in get_children():
		var egg := child as CharacterBody3D
		if egg == null:
			continue
		_eggs.append(egg)
		egg.crossing_finished.connect(_on_crossing_finished.bind(egg))
	if _eggs.is_empty():
		push_warning("天堂奶蛋：本节点下一个奶蛋都没有，什么都不会发生。")
		return
	if not is_instance_valid(bounds):
		push_warning("天堂奶蛋：没指定活动范围（bounds），所有奶蛋会从原地出发、原地不动。")
	# 到位第一帧就把它们放出来：从各自现在站的地方挑第一个落点
	for egg: CharacterBody3D in _eggs:
		_send(egg)


## 一段走完（到达了，或者被卡住放弃了）：歇一下再挑下一段。
func _on_crossing_finished(_reached: bool, egg: CharacterBody3D) -> void:
	await get_tree().create_timer(_rng.randf_range(rest_min, rest_max)).timeout
	if is_instance_valid(egg):
		_send(egg)


## 让一只奶蛋从它现在站的地方出发，走向新挑的落点。
func _send(egg: CharacterBody3D) -> void:
	var from: Vector3 = egg.global_position
	egg.begin_crossing(from, _pick_target(from))


## 挑一个能落脚的落点。连着挑不到就返回原地 —— 那一段会立刻判为「到了」，
## 于是歇一下再挑，不会卡死，也不会让奶蛋跑到墙里去。
func _pick_target(from: Vector3) -> Vector3:
	if not is_instance_valid(bounds):
		return from
	for attempt in pick_attempts:
		var ground: Vector3 = _ground_at(_random_in_bounds())
		if not ground.is_finite():
			continue
		var distance: float = from.distance_to(ground)
		if distance < min_distance or distance > leg_distance:
			continue
		return ground
	return from


## 在活动范围（地板碰撞盒）里随机取一个点，高度取盒子顶面。
## 用碰撞盒自己的变换把局部偏移搬到世界坐标 —— 缩放和朝向都自动算进去，
## 你把房子整体转过 90° 也不用回来改这里。
func _random_in_bounds() -> Vector3:
	var box: BoxShape3D = bounds.shape as BoxShape3D
	if box == null:
		return bounds.global_position
	var half: Vector3 = box.size * 0.5
	var local := Vector3(
		_rng.randf_range(-half.x + margin, half.x - margin),
		half.y,
		_rng.randf_range(-half.z + margin, half.z - margin))
	return bounds.global_transform * local


## 从候选点正上方往下打一条射线找地面。打不到、或者打的不是近似水平的面，就返回 INF。
##
## 射线**排除掉全场所有奶蛋**：别的奶蛋正站在那儿的话，会先打到它的圆脑袋上，
## 得到一个悬在半空的「地面」，那样挑出来的落点会一直贴着别人。
func _ground_at(point: Vector3) -> Vector3:
	var box: BoxShape3D = bounds.shape as BoxShape3D
	var reach: float = 4.0
	if box != null:
		reach = maxf(box.size.y * bounds.global_transform.basis.get_scale().y, 1.0)
	var top := Vector3(point.x, point.y + reach, point.z)
	var bottom := Vector3(point.x, point.y - reach, point.z)
	var query := PhysicsRayQueryParameters3D.create(top, bottom, ground_mask, _egg_rids())
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3(INF, INF, INF)
	if (hit.normal as Vector3).y < 0.9:
		return Vector3(INF, INF, INF)   # 斜面和墙面不算地面
	return hit.position


## 全场奶蛋的 RID，给射线当排除名单。
func _egg_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for egg: CharacterBody3D in _eggs:
		if is_instance_valid(egg):
			rids.append(egg.get_rid())
	return rids
