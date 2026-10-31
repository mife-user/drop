extends Node3D
class_name ItemRainEvent

## 正面道具触发的全地图降雨。水量按有效时间累计，不依赖粒子数量或帧率。
## 固定 GPU 雨滴与高度场碰撞节点写在场景中；雨滴碰到屋顶或地面即消失。
## 降雨时长和每秒水量统一放在道具商店的「正面道具效果」里，这里只负责执行。
@export var inventory: HeldItemController
## 接收雨水的水池。
@export var pool: WaterSink
## 木碗（奶蛋的碗）。下雨时碗里也会积水 —— 留空则只给水池加（旧行为）。
@export var bowl: WaterSink
## 下多久雨能把碗灌满（秒）。0 = 不给碗加水，回到旧行为。
## **按碗自己的容量算，不按水池的 m³/秒算**：木碗的 capacity 和泳池不在一个量级
## （碗 500、泳池按立方米），套同一个流量的话碗永远是 0。这里只跟容量挂钩，
## 所以以后换更大的容器也不用调。默认 12 秒 ≈ 一场 10 秒的雨能灌到八成多。
@export_range(0.0, 120.0, 0.5) var bowl_fill_seconds: float = 12.0
## 雨滴表现节点，可在场景中调整密度、范围、速度和材质。
@export var rain: GPUParticles3D
## 道具商店；使用时从这里读取降雨时长与每秒水量。
@export var shop: ItemShop

const DEFAULT_DURATION: float = 10.0  # 没接商店时退回的降雨时长
const DEFAULT_WATER_PER_SECOND: float = 0.1  # 没接商店时退回的每秒水量

var remaining: float = 0.0

## 开局不下雨，只监听实际使用信号，购买本身不会触发。
func _ready() -> void:
	if is_instance_valid(inventory):
		inventory.item_used.connect(_on_item_used)
	_stop_rain()

func _on_item_used(item_id: StringName, _description: String) -> void:
	if item_id == &"positive":
		start_rain()

func start_rain() -> void:
	var rain_duration: float = _configured_duration()
	if not is_instance_valid(pool) or rain_duration <= 0.0:
		return
	var was_active: bool = remaining > 0.0
	remaining += rain_duration
	if is_instance_valid(rain):
		rain.show()
		if not was_active:
			rain.restart()
		rain.emitting = true

## 最后一帧只计入剩余秒数，避免超时多加水；水池自身处理容量上限和水面。
func _process(delta: float) -> void:
	if remaining <= 0.0:
		return
	var elapsed: float = minf(maxf(delta, 0.0), remaining)
	var per_second: float = maxf(_configured_water_per_second(), 0.0)
	if is_instance_valid(pool):
		pool.add_water(per_second * elapsed)
	if is_instance_valid(bowl) and bowl_fill_seconds > 0.0:
		bowl.add_water(bowl.capacity / bowl_fill_seconds * elapsed)
	remaining = maxf(remaining - elapsed, 0.0)
	if remaining <= 0.000001:
		_stop_rain()

func _stop_rain() -> void:
	remaining = 0.0
	if is_instance_valid(rain):
		rain.emitting = false
		rain.hide()

## 效果数值存在道具商店上；商店没接时用默认值，保证这个节点单独摆也能用。
func _configured_duration() -> float:
	return shop.positive_rain_duration if is_instance_valid(shop) else DEFAULT_DURATION

func _configured_water_per_second() -> float:
	return shop.positive_rain_water_per_second if is_instance_valid(shop) else DEFAULT_WATER_PER_SECOND
