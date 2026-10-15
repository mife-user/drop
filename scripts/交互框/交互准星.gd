extends Control
class_name InteractCrosshair

## 屏幕中心的十字准星 + 下面一行小字。
##
## 平时只有一个十字，什么都不显示；需要提示时（看着可交互物体、或菜单里扫到了某一项），
## 在十字**下方**显示一行字 —— 字不在正中心，所以永远不会挡住瞄准点，
## 也不会挡住菜单里的选项。
##
## 谁想改这句话就调 set_hint()（第二个参数传 `self`，表示这行字归你）。文字没变时什么都不做，所以放在 _physics_process 里
## 每帧调也没关系，不会每帧重播动画。
##
## **一行字同一时刻只认一个主**：场景里可能摆着好几台交互台座，它们每帧都会来写一次
## （没瞄到目标的那台写空字符串，意思是「擦掉」）。所以调用时要说明「这行字归谁」，
## 不是主人的「擦掉」一律忽略 —— 否则排在场景树后面那台会把正在瞄着的那台的提示每帧抹一次，
## 字就永远显示不出来（两台都显示不出来，因为正序写、反序擦，来回拉锯）。
##
## 这是 HUD，必须挂在 CanvasLayer 下面（挂 3D 根节点上会跟着相机跑、还会被场景挡住）；
## 十字和那行字的位置都在场景里摆，脚本不挪它们。

## 准星组名。交互台没在检查器里显式指定准星时，就按这个组把它捞出来 ——
## 名字要和 scripts/交互框/交互台.gd 里的 GROUP_CROSSHAIR 一致。
const GROUP: StringName = &"interact_crosshair"

## 准星下面那行字。
@export var hint: Label
## 这行字淡入淡出的时长（秒）；填 0 就是硬切。
@export_range(0.0, 1.0, 0.01) var fade_time: float = 0.1

var _hint_text: String = ""
var _owner: Object = null   # 这行字现在归谁；null = 没主，谁都能写、也都能擦
var _tween: Tween


## 登记进「准星」组。放在 _enter_tree 而不是 _ready：所有节点的 _enter_tree 都跑完了
## 才会有第一个 _ready，所以交互台在自己的 _ready 里一定捞得到准星。
func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	# 场景里这行字是亮着的（方便在编辑器里摆位置），运行时先收干净，而且不做动画，
	# 否则开局会在屏幕中间闪一下。
	if is_instance_valid(hint):
		hint.text = ""
		hint.modulate.a = 0.0
		hint.hide()


## 准星下面那行字。传空字符串 = 不显示。
## source = 「这行字归谁」，台座传 self。不传 = 强行写、强行擦（谁都拦不住），留给不认主的调用方用。
func set_hint(text: String, source: Object = null) -> void:
	# 认主这一段必须放在「文字没变就直接返回」**前面**：
	# 两台写着同一句话时，提前返回会让主人换不了手，接着被前一台的「擦掉」抹掉，又开始闪。
	if text.is_empty():
		# 空字符串 = 「擦掉」。别人正用着这行字时不作数 ——
		# 没瞄到目标的台座也在每帧喊擦掉，不拦的话提示根本显示不出来。
		if is_instance_valid(_owner) and source != null and _owner != source:
			return
		_owner = null
	else:
		_owner = source
	if text == _hint_text:
		return   # 主人换了、话没换：认得下来就够了，动画不用重播
	_hint_text = text
	if not is_instance_valid(hint):
		return
	if is_instance_valid(_tween):
		_tween.kill()   # 上一次还没淡完又变了：掐掉重来，否则两个动画会互相拉扯
	if text.is_empty():
		if fade_time <= 0.0:
			_apply(0.0)
			return
		_tween = create_tween()
		_tween.tween_property(hint, "modulate:a", 0.0, fade_time)
		_tween.tween_callback(hint.hide)
		return
	hint.text = text
	hint.show()
	if hint.modulate.a >= 1.0:
		return   # 本来就是亮着的（只是换了句话），不用重播淡入
	if fade_time <= 0.0:
		_apply(1.0)
		return
	_tween = create_tween()
	_tween.tween_property(hint, "modulate:a", 1.0, fade_time)


## 直接跳到位，不播动画。
func _apply(alpha: float) -> void:
	hint.modulate.a = alpha
	hint.visible = alpha > 0.0
