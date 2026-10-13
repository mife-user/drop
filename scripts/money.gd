extends Label
class_name CurrencyLabel

## 金额：右上角「绿钞玩偶图标 + x 数量」里的那个数字。
##
## **现在没有任何玩法会改它** —— 整个游戏里目前只有检查器能改这个数。
## 想先看看不同位数的效果，直接把 amount 改成 100、9999 就行；
## 以后真正接上经济系统时，调 add_money() / set_money() 即可，UI 结构不用再动。
##
## 文字是「prefix + amount」拼出来的，**别在检查器里直接改 text** —— 下次刷新会被覆盖。
## 想改样式（字号、描边、颜色）改 Label 自己的那几个 theme_override_* 属性，那些不受影响。

## 当前显示的数量。
@export var amount: int = 0:
	set(value):
		amount = value
		_refresh()

## 数字前面的前缀，默认 "x "，于是显示成「x 0」。
@export var prefix: String = "x ":
	set(value):
		prefix = value
		_refresh()


func _ready() -> void:
	_refresh()


## 加钱（可以传负数）。以后接玩法时调这个。
func add_money(delta: int) -> void:
	amount += delta


## 直接设成某个数。
func set_money(value: int) -> void:
	amount = value


## 把前缀 + 数量写进 Label 的文字；改 amount / prefix 时会自动跑一遍。
func _refresh() -> void:
	text = "%s%d" % [prefix, amount]
