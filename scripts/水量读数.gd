extends Label3D
class_name WaterSinkReadout

## 水量读数：浮在某个吸水区上方，显示这个容器「装了多少水」。
##
## 通用件，思路和 `水量灯.gd` 完全一样 —— 它不认识水池、也不认识木碗，只读 WaterSink 的
## amount / capacity，并连它的 water_received 信号刷新自己。`吸水区.gd` 一行都不用改。
## 以后哪个容器要显示水量（花盆、水缸、消防栓），把 `水量读数.tscn` 实例一份、
## 把 sink 拖上就行，摆几个都行。
##
## 默认显示**立方米**（「0.005 / 0.025 m³」）而不是百分比：泳池那种大容器里
## 一发水太小（边长 0.17 米的水才 0.0049 m³），按整数百分比要射好几发才跳 1%，
## 看不出在涨；立方米每发都看得见数字动。
## 想要百分比就在检查器里把 display_mode 切成「百分比」。
##
## **父节点的缩放会原样放大这些字**：木碗那条父链带着 3.965 倍缩放，
## 所以木碗上那份实例的 pixel_size 填的是泳池那份的 1/3.965，两边看起来才一样大。
## 觉得字太大/太小，改 pixel_size（改 font_size 也行，两者是乘起来的关系）。
##
## 显示相关的开关都在**节点本身**上（不归脚本管，检查器里直接改）：
## no_depth_test —— 勾上 = 穿墙可见；取消 = 被墙、房子挡住就看不见（默认取消，走正常遮挡）
## billboard —— 文字永远正面朝你（默认开启）；关掉就是固定朝向
## fixed_size —— 勾上后不管离多远，字在屏幕上一样大（适合当任务标记）
##
## 字体：用的是 Godot 自带字体，只有数字、斜杠和 m³ 这些拉丁字符 ——
## 要显示中文得先往项目里加一个中文字体资源。

## 两种显示方式，检查器里切换。
enum DisplayMode {
	CUBIC,   ## 立方米：「0.005 / 0.025 m³」，小容器用它才看得见每发水的变化
	PERCENT, ## 百分比：「20%」
}

## 要读哪个容器。**留空则这个标签完全不动**，保持编辑器里摆好的样子。
@export var sink: WaterSink
## 显示方式。
@export var display_mode: DisplayMode = DisplayMode.CUBIC
## 勾上后按容量自动决定小数位数：容量不到 0.1 立方米用 3 位（木碗，
## 一发水 0.005 才看得见），否则用 2 位（泳池）。
@export var auto_decimals: bool = true
## 取消上面那个勾之后才生效：手动指定小数位数。
@export_range(0, 4) var decimals: int = 2
## 数字后面跟的单位；写成空字符串就是不显示单位。
@export var unit: String = " m³"


func _ready() -> void:
	if not is_instance_valid(sink):
		push_warning("水量读数：没指定吸水区，这个标签不会刷新（保持编辑器里摆好的样子）")
		return
	# 吸水区每收下一团水都会发这个信号（装满之后继续吸水也发），收到就重算一遍文字。
	sink.water_received.connect(_on_water_received)
	# 场景一加载容器里就已经有水（编辑器里预填、或读档）也要立刻显示对，不能只等变化
	_refresh()


## 有水流进来了。参数是这团水的体积，这里用不上 —— 直接读 sink 的当前水量更保险。
func _on_water_received(_volume: float) -> void:
	_refresh()


## 按当前水量重算文字。
func _refresh() -> void:
	if not is_instance_valid(sink):
		return
	if display_mode == DisplayMode.PERCENT:
		text = "%d%%" % roundi(clampf(sink.amount / maxf(sink.capacity, 0.000001), 0.0, 1.0) * 100.0)
		return
	var digits: int = decimals
	if auto_decimals:
		digits = 3 if sink.capacity < 0.1 else 2
	text = "%s / %s%s" % [
		String.num(sink.amount, digits),
		String.num(sink.capacity, digits),
		unit,
	]
