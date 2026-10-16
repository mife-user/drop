extends Node

## 使用负面道具时实例化放置物。数量由使用次数决定，所以运行时生成。
@export var inventory: HeldItemController
## 唯一允许被负面道具抽水的水池。
@export var pool: WaterSink
## 放置物场景，模型与落点圈均可在该场景内修改。
@export var placed_scene: PackedScene
## 放置后持续秒数。
@export_range(0.1, 600.0, 0.1) var duration: float = 10.0
## 每秒吸水立方米。
@export_range(0.0, 100.0, 0.001) var drain_per_second: float = 0.1
## 放置后每秒自转角度。
@export var spin_speed: float = 180.0

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
	item.duration = duration
	item.drain_per_second = drain_per_second
	item.spin_speed = spin_speed
	add_child(item)
	item.begin_carry()
	# 同帧隐藏水枪；放下后由手持控制器恢复，避免左键同时开火。
	if is_instance_valid(inventory):
		inventory._sync_equipment()
