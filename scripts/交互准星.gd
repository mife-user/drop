extends Control
class_name InteractCrosshair

## 屏幕中心的准星：平时是一个小圆点；只要「现在按 E 有用」，圆点就原地变成一个青色键帽 [E]，
## 键帽下面再跟一行说明字（「升级水枪」「E 升级 · 3 枚」这种）。
##
## 这样定规则的好处是准星自己会解释自己：**看到键帽 = 现在按 E 有反应**，
## 平时（圆点）按 E 什么都不会发生，玩家不用猜。
##
## 谁想改准星样子就调 show_keycap() / show_dot() —— 状态和文字都没变时什么都不做，
## 所以放在 _physics_process 里每帧调也没关系，不会每帧重播动画。
##
## 两个状态是二选一：显示键帽时圆点自动藏起来，反之亦然。
## 淡入淡出时长在检查器里调（填 0 = 直接切换）。
##
## 这是 HUD，必须挂在 CanvasLayer 下面；三个元素的位置都在场景里摆，脚本不挪它们。

## 平时那个小圆点。
@export var dot: Control
## 「按 E 有用」时出现的键帽（里面一个 E 字）。
@export var keycap: Control
## 键帽下面那行说明字。文字为空时整行隐藏。
@export var hint: Label
## 圆点和键帽之间切换的淡入淡出时长（秒）；填 0 就是硬切。
@export_range(0.0, 1.0, 0.01) var fade_time: float = 0.1

var _keycap_on: bool = false   # 当前是不是键帽状态
var _hint_text: String = ""    # 当前那行字，用来判断"有没有变化"
var _tween: Tween


func _ready() -> void:
	# 场景里三个元素都是亮着的（方便在编辑器里摆位置），运行时先按"平时"的样子收好，
	# 而且这一步不做动画 —— 否则开局会在屏幕中间闪一下。
	_apply(false, "", false)


## 平时：一个圆点。也可以给一行小字，比如面板开着但没扫到选项时的「Esc 关闭」。
func show_dot(hint_text: String = "") -> void:
	_apply(false, hint_text, true)


## 按 E 有用时：圆点换成键帽，并在下面显示这行字。
func show_keycap(hint_text: String) -> void:
	_apply(true, hint_text, true)


## 切换状态。animated = false 时直接跳到位（_ready 用）。
func _apply(keycap_on: bool, hint_text: String, animated: bool) -> void:
	if animated and keycap_on == _keycap_on and hint_text == _hint_text:
		return
	_keycap_on = keycap_on
	_hint_text = hint_text
	if is_instance_valid(hint) and hint.text != hint_text:
		hint.text = hint_text
	if is_instance_valid(_tween):
		_tween.kill()   # 上一次还没淡完又变了：掐掉重来，否则两个动画会互相拉扯
	var dot_alpha: float = 0.0 if keycap_on else 1.0
	var key_alpha: float = 1.0 if keycap_on else 0.0
	var hint_alpha: float = 0.0 if hint_text.is_empty() else 1.0
	if not animated or fade_time <= 0.0:
		_set_alpha(dot, dot_alpha)
		_set_alpha(keycap, key_alpha)
		_set_alpha(hint, hint_alpha)
		return
	_tween = create_tween().set_parallel(true)
	_fade(dot, dot_alpha)
	_fade(keycap, key_alpha)
	_fade(hint, hint_alpha)


## 淡到某个透明度；淡到 0 的那个等动画放完再整个隐藏，省得它继续参与绘制。
## 用成员 _tween，所以调用前必须已经建好并行补间。
func _fade(node: CanvasItem, target: float) -> void:
	if not is_instance_valid(node):
		return
	if target > 0.0:
		node.show()
	_tween.tween_property(node, "modulate:a", target, fade_time)
	if is_zero_approx(target):
		_tween.tween_callback(node.hide).set_delay(fade_time)


## 直接跳到位，不播动画。
func _set_alpha(node: CanvasItem, alpha: float) -> void:
	if not is_instance_valid(node):
		return
	node.modulate.a = alpha
	node.visible = alpha > 0.0
