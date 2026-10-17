extends Node

## 使用负面道具时实例化放置物。数量由使用次数决定，所以运行时生成。
## 持续时间、每秒吸水量和自转速度统一放在道具商店的「负面道具效果」里，这里只负责生成。
@export var inventory: HeldItemController
## 唯一允许被负面道具抽水的水池。
@export var pool: WaterSink
## 放置物场景，模型与落点圈均可在该场景内修改。
@export var placed_scene: PackedScene
## 道具商店；使用时从这里读取负面道具的三项效果参数。
@export var shop: ItemShop

const DEFAULT_DURATION: float = 10.0  # 没接商店时退回的持续秒数
const DEFAULT_DRAIN_PER_SECOND: float = 0.1  # 没接商店时退回的每秒吸水量
const DEFAULT_SPIN_SPEED: float = 180.0  # 没接商店时退回的自转速度

## 只监听使用，购买后不会自动开始放置。
func _ready() -> void:
	if is_instance_valid(inventory):
		inventory.item_used.connect(_on_item_used)

func _on_item_used(id: StringName, _description: String) -> void:
	if id != &"negative" or placed_scene == null:
		return
	var item: NegativePlacedItem = placed_scene.instantiate() as NegativePlacedItem
	if item == null:
		return
	item.name = "负面道具放置物"
	item.pool = pool
	item.duration = shop.negative_duration if is_instance_valid(shop) else DEFAULT_DURATION
	item.drain_per_second = shop.negative_drain_per_second if is_instance_valid(shop) else DEFAULT_DRAIN_PER_SECOND
	item.spin_speed = shop.negative_spin_speed if is_instance_valid(shop) else DEFAULT_SPIN_SPEED
	add_child(item)
	item.begin_carry()
	# 同帧隐藏水枪；放下后由手持控制器恢复，避免左键同时开火。
	if is_instance_valid(inventory):
		inventory._sync_equipment()
