extends CanvasLayer

## 天堂开场：进到最终场景之后，先把黑幕淡开，再把「恭喜你」「来到了奶蛋天堂」两句依次浮现，
## **等这两句演完（淡走）之后，最后才把「按 Esc 回菜单」那行小提示留在屏幕底部**。
##
## 只管「什么时候叫哪一句」；弹字的动画（淡入、缩放、停留、淡出）全在
## 每个 Label 自己挂的 水量字幕.gd 上，三句各自的字号、颜色、描边在场景里那三份 LabelSettings 上。
## **想加第四句**：在场景里再摆一个 Label、挂上 水量字幕.gd，然后在这里补一段等待和一行 _say()。
##
## 前两句「弹完就淡走」、最后那句「留在屏幕上」，靠的是各自 Label 上 水量字幕.gd 的 stay 勾 ——
## 想换哪句留、哪句走，改那个勾就行，这个脚本一个字都不用改。
## **提示什么时候出**是从第二句 Label 自己的参数上读出来的（见 _wait_for_last_line），
## 所以你在检查器里把第二句的 hold_time 调长，提示会自动跟着往后等，不用回来改代码。
##
## 本节点（CanvasLayer）就是屏幕上这层 UI 的管家，四个子节点各干各的：
## 黑幕只负责「从上一幕的全黑里淡回来」，三个 Label 只负责自己被叫到的时候怎么出场。

## 黑幕（本节点下的 ColorRect）：从上一幕留下的全黑淡回来。留空 = 不淡，进场景就是亮的。
@export var curtain: ColorRect
## 第一句（本节点下的 Label，挂着 水量字幕.gd）。
@export var line_title: WaterCaption
## 第二句。留空 = 只弹第一句。
@export var line_subtitle: WaterCaption
## 最后留在屏幕上的那行小提示（「按 Esc 回菜单」）。
## 它出现得最晚，而且 Label 上的 stay 是勾着的 —— 前两句淡走之后，屏幕上就剩它。
@export var line_hint: WaterCaption
## 前面的字都演完之后，再隔几秒才弹提示。
@export_range(0.0, 10.0, 0.05) var hint_gap: float = 0.6
## 黑幕淡回透明用几秒；填 0 = 黑幕直接消失。
@export_range(0.0, 10.0, 0.05) var fade_in_time: float = 1.2
## 黑幕淡完之后再静一会儿才弹第一句（秒），别让字和淡入撞在一起。
@export_range(0.0, 10.0, 0.1) var start_delay: float = 0.4
## 第一句出现之后隔几秒弹第二句。**要比第一句的淡入时间长一点**，不然两句会叠在一起。
@export_range(0.0, 10.0, 0.05) var line_gap: float = 1.4


func _ready() -> void:
	_fade_from_black()
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout
	_say(line_title)
	if line_gap > 0.0:
		await get_tree().create_timer(line_gap).timeout
	_say(line_subtitle)
	# 等第二句彻底演完（淡入 + 停留 + 淡出）再弹提示，免得两句话叠在一起
	await _wait_for_last_line()
	_say(line_hint)


## 等「第二句演完」所需的时间。**直接从第二句那个 Label 自己的参数上读**，
## 所以在检查器里把它调长调短，提示出现的时机自动跟着走，不用回来改这里。
## 第二句没接（只弹一句）时，就只等 hint_gap。
func _wait_for_last_line() -> void:
	var wait: float = hint_gap
	if is_instance_valid(line_subtitle):
		wait += maxf(line_subtitle.fade_in, 0.0) + maxf(line_subtitle.hold_time, 0.0) + maxf(line_subtitle.fade_out, 0.0)
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout


## 黑幕从全黑淡到透明，淡完顺手藏起来 —— 留着它虽然看不见，但会一直挡着底下的东西。
func _fade_from_black() -> void:
	if not is_instance_valid(curtain):
		return
	if fade_in_time <= 0.0:
		curtain.visible = false
		return
	curtain.visible = true
	curtain.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_property(curtain, "modulate:a", 0.0, fade_in_time)
	tween.finished.connect(_hide_curtain)


func _hide_curtain() -> void:
	if is_instance_valid(curtain):
		curtain.visible = false


## 叫某一句出场。台词本身不在代码里 —— 它就在那个 Label 的 Text 上（编辑器里直接改）。
func _say(line: WaterCaption) -> void:
	if is_instance_valid(line):
		line.show_message()
