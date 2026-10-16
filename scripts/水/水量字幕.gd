extends Label
class_name WaterCaption

## 水量字幕：容器装满的那一瞬间，在屏幕上弹出「恭喜解锁神兽：奶蛋」，停留若干秒后淡出。
## （勾了 stay 的就是弹完不走，一直留在屏幕上 —— 结局那两句用的是这个模式。）
##
## 和「水量灯」（scripts/水量灯.gd）是一对：都只认 WaterSink 的 filled 信号，
## 不认识木碗、也不认识奶蛋。以后别的地方要弹字幕（填满水池、开门、捡到东西），
## 换一下 sink 和 Text 就能用，不用改这个脚本。
##
## 这是 UI，必须挂在 CanvasLayer 下面 —— 否则会跟着 3D 相机跑、还会被场景里的东西挡住。
## 节点平时是隐藏的，只在信号来的时候出现；想手动弹一句就调下面的 show_message()。
##
## 分工：**台词**是这个节点自己的 Text 属性，**样子**（颜色、字号、描边、阴影）是节点上的
## LabelSettings 子资源 —— 两个都在检查器里直接改、编辑器里所见即所得，脚本不另存一份，
## 免得出现「改了一个地方没生效」。本脚本只管「什么时候弹、弹多久、怎么淡出」。

## 触发字幕的容器；留空则永远不弹（可以先这么放着当备用，等哪天接上别的容器）。
@export var sink: WaterSink
## 停留时间（秒）：淡入结束到开始淡出之间隔多久。
@export_range(0.1, 30.0, 0.1) var hold_time: float = 3.0
## 淡入时长（秒）；填 0 就是直接出现。
@export_range(0.0, 3.0, 0.05) var fade_in: float = 0.35
## 淡出时长（秒）；填 0 就是到点直接消失。
@export_range(0.0, 3.0, 0.05) var fade_out: float = 0.8
## 弹出时从多少倍大小缩回原尺寸，1 = 不缩放。略微大一点更有「蹦出来」的感觉。
@export_range(1.0, 2.0, 0.01) var pop_scale: float = 1.08
## 勾上 = 淡入之后**就留在屏幕上不走**（结局、通关那种要一直挂着的字）。
## 不勾（默认）= 老规矩：停留 hold_time 秒后淡出、隐藏。
## 勾上之后 hold_time 和 fade_out 就不起作用了，留着不删是为了随时能勾回来。
@export var stay: bool = false

var _tween: Tween


func _ready() -> void:
	hide()
	if is_instance_valid(sink):
		sink.filled.connect(_on_filled)


## 容器装满：弹字幕。重复触发会从头重新计时，不会叠成两条。
func _on_filled() -> void:
	show_message()


## 弹一次字幕。不传参数就把节点 Text 里那句再放一遍；
## 传了就临时换一句（只影响这一次，不会改掉场景里存的那句）。
## 以后想在别的时机弹字（开门、捡到东西、提示操作），直接调这个函数就行。
func show_message(new_text: String = "") -> void:
	if not new_text.is_empty():
		text = new_text
	if is_instance_valid(_tween):
		_tween.kill()   # 上一条还没放完又被触发：掐掉重来，否则两条动画会互相打架
	visible = true
	modulate.a = 0.0
	pivot_offset = size * 0.5   # 缩放围绕正中间，不然会从左上角涨出来
	scale = Vector2.ONE * pop_scale if pop_scale > 1.0 else Vector2.ONE
	_tween = create_tween()
	if fade_in > 0.0:
		# 淡入和放大同时进行，所以用并行段；结束时要记得关掉并行，否则后面几段也会一起跑
		_tween.set_parallel(true)
		_tween.tween_property(self, "modulate:a", 1.0, fade_in)
		_tween.tween_property(self, "scale", Vector2.ONE, fade_in).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.set_parallel(false)
	else:
		modulate.a = 1.0
		scale = Vector2.ONE
	if stay:
		# 常驻：淡入之后就停在这儿。tween 排到这儿没有下一段了，自己会结束，
		# 所以不用特意去 kill 它 —— 下次 show_message() 会把它掐掉重排。
		return
	_tween.tween_interval(hold_time)
	# tween_property 的时长必须大于 0，所以 fade_out 填 0 时给一个极小值，效果上就是「到点直接消失」
	_tween.tween_property(self, "modulate:a", 0.0, maxf(fade_out, 0.01))
	_tween.tween_callback(hide)
