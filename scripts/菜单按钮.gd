extends Button

## 菜单按钮：鼠标悬停或键盘选中时，左侧那条青色竖条从中间"长"出来。
##
## 竖条是按钮自己的子节点（ColorRect），跟按钮的样式盒无关——所以悬停时文字不会左右跳动。
## 文字变亮交给检查器里的 theme_override_colors/font_hover_color、font_focus_color，
## 本脚本只管竖条这一件事。两个按钮共用这个脚本。

## 左侧的青色竖条。scale.y 由本脚本驱动：0 = 收起，1 = 完全长开。
@export var indicator: ColorRect
## 长出 / 收回的时长（秒）。
@export_range(0.02, 0.6, 0.01) var grow_time: float = 0.14


func _ready() -> void:
	# 悬停和键盘聚焦走同一套表现，方向键选中时也有反馈
	mouse_entered.connect(_grow.bind(true))
	mouse_exited.connect(_grow.bind(false))
	focus_entered.connect(_grow.bind(true))
	focus_exited.connect(_grow.bind(false))
	if is_instance_valid(indicator):
		indicator.scale = Vector2(1.0, 0.0)


## 把竖条补间到目标状态；已经到位就直接返回，反复触发（既悬停又聚焦）不会有副作用。
func _grow(active: bool) -> void:
	if not is_instance_valid(indicator):
		return
	var target: Vector2 = Vector2(1.0, 1.0) if active else Vector2(1.0, 0.0)
	if indicator.scale.is_equal_approx(target):
		return
	var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(indicator, "scale", target, grow_time)
