extends OmniLight3D
class_name WaterLevelLight

## 水量灯：灯光亮度跟着某个吸水区的水量走 —— 空着的时候是一点冷色微光，
## 装满的时候变成暖色亮光，装满的那一瞬间再闪一下，当作「成了」的提示。
##
## 它只读 WaterSink 的 amount / capacity，并连一个 filled 信号：不认识木碗，也不认识奶蛋。
## 以后哪个容器需要「满了会亮」（花盆、水缸、消防栓），把那个吸水区拖进 sink 就行。
##
## 注意本节点如果挂在被缩放的父节点下（木碗是 3.965 倍），omni_range 也会跟着放大 3.965 倍，
## 调光照范围时心里要有这个数：改这里的 omni_range 是改「相对木碗的大小」。

## 要跟随的容器；留空则灯光完全不动，保持编辑器里调好的样子。
@export var sink: WaterSink
## 一滴水都没有时的亮度。
@export_range(0.0, 16.0, 0.01) var empty_energy: float = 0.15
## 装满时的亮度。
@export_range(0.0, 16.0, 0.01) var full_energy: float = 2.0
## 空着时的颜色。
@export var empty_color: Color = Color(0.45, 0.62, 0.85)
## 装满时的颜色；中间按水量在两色之间插值。
@export var full_color: Color = Color(1.0, 0.78, 0.42)
## 装满瞬间额外叠多少亮度，再用 flash_time 秒衰减掉；填 0 就是不闪。
@export_range(0.0, 32.0, 0.01) var flash_boost: float = 5.0
## 闪烁的衰减时长（秒）。
@export_range(0.05, 3.0, 0.05) var flash_time: float = 0.8
## 灯光追水量的平滑速度，越大越跟手；填 0 就是每帧直接到位。
@export_range(0.0, 40.0, 0.5) var follow_speed: float = 8.0

var _energy: float = 0.0        # 平滑后的基础亮度，不含闪烁叠加
var _flash_left: float = 0.0    # 闪烁剩余时间（秒）


func _ready() -> void:
	if not is_instance_valid(sink):
		return
	sink.filled.connect(_on_filled)
	# 场景一加载容器里就已经有水（编辑器里预填、或读档）也要立刻显示对，不能只等变化
	_energy = _target_energy()
	light_energy = _energy
	light_color = _target_color()


## 容器第一次装满：开始闪一下。这里只认信号，不管水是谁倒的、之后还剩多少。
func _on_filled() -> void:
	_flash_left = flash_time


func _process(delta: float) -> void:
	if not is_instance_valid(sink):
		return
	var target: float = _target_energy()
	# 指数逼近：水一进来灯就往上涨，骤停时也不会突兀。
	# 木碗一格一格进水（一发水一团），所以这个平滑同时也是「一发一发地亮起来」。
	_energy = target if follow_speed <= 0.0 else lerpf(_energy, target, 1.0 - exp(-follow_speed * delta))
	_flash_left = maxf(0.0, _flash_left - delta)
	light_energy = _energy + flash_boost * (_flash_left / maxf(flash_time, 0.0001))
	light_color = _target_color()


## 当前水量比例（0–1）。
func _ratio() -> float:
	if not is_instance_valid(sink):
		return 0.0
	return clampf(sink.amount / maxf(sink.capacity, 0.0001), 0.0, 1.0)


func _target_energy() -> float:
	return lerpf(empty_energy, full_energy, _ratio())


func _target_color() -> Color:
	return empty_color.lerp(full_color, _ratio())
