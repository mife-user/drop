extends HBoxContainer
class_name AttributeRow

## 世界属性面板里的一行：左边是属性名，右边是数值。
##
## **单独做成一个场景，是为了「以后再加属性」**：在 scenes/界面/属性行.tscn 上再实例一份，
## 改掉左格的字、把右格交给面板脚本来刷，就完事了 ——
## 字号、颜色、间距、数值靠右对齐全部是从这份场景继承的，
## 所以新加的行天然和旧的长得一样、也对得齐，不用再对一遍样式。
##
## 左格（属性名）是固定文字，直接在场景里改那个 Label 的 text，脚本不碰它；
## 这里只管右格：set_value() 换数值，文字没变就什么都不做。


## 左格：属性名。一般不用在检查器里改 —— 去场景里改那个 Label 的 text 更直观。
@export var key_label: Label
## 右格：数值。面板脚本只动这一格。
@export var value_label: Label


## 换掉右边的数值。和现在一模一样就直接返回 —— 面板每帧都会叫它一次，省下重绘。
func set_value(text: String) -> void:
	if not is_instance_valid(value_label):
		return
	if value_label.text == text:
		return
	value_label.text = text
