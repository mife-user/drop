extends Node3D
class_name ItemRainEvent

## 正面道具触发的全地图降雨。水量按有效时间累计，不依赖粒子数量或帧率。
## 固定 GPU 雨滴与高度场碰撞节点写在场景中；雨滴碰到屋顶或地面即消失。
@export var inventory: HeldItemController
## 接收雨水的水池，不影响木碗等其他容器。
@export var pool: WaterSink
## 雨滴表现节点，可在场景中调整密度、范围、速度和材质。
@export var rain: GPUParticles3D
## 每件正面道具增加的降雨时长（秒）。连续使用延长时间，不叠加流量。
@export_range(0.1, 600.0, 0.1) var duration: float = 10.0
## 每秒进入水池的水量（立方米）。
@export_range(0.0, 100.0, 0.001) var water_per_second: float = 0.1

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
	if not is_instance_valid(pool) or duration <= 0.0:
		return
	var was_active: bool = remaining > 0.0
	remaining += duration
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
	if is_instance_valid(pool):
		pool.add_water(maxf(water_per_second, 0.0) * elapsed)
	remaining = maxf(remaining - elapsed, 0.0)
	if remaining <= 0.000001:
		_stop_rain()

func _stop_rain() -> void:
	remaining = 0.0
	if is_instance_valid(rain):
		rain.emitting = false
		rain.hide()
