extends Control
class_name InteractCrosshair

## 屏幕中心的十字准星 + 下面一行小字。
##
## 平时只有一个十字，什么都不显示；需要提示时（看着可交互物体、或菜单里扫到了某一项），
## 在十字**下方**显示一行字 —— 字不在正中心，所以永远不会挡住瞄准点，
## 也不会挡住菜单里的选项。
##
## 谁想改这句话就调 set_hint()。文字没变时什么都不做，所以放在 _physics_process 里
## 每帧调也没关系，不会每帧重播动画。
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
func set_hint(text: String) -> void:
	if text == _hint_text:
		return
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
