extends Label
class_name CurrencyLabel

## 邮币：右上角「绿钞玩偶图标 + x 数量」里的那个数字，同时也是全项目的**账本**。
##
## 谁要给钱、收钱、查余额，都调这里的 add_money() / spend() / can_afford()，
## **别自己去改这个 Label 的 text** —— 数字是脚本按 amount 拼出来的，手改下次刷新就被覆盖。
## 花钱成没成功看 spend() 的返回值（true = 扣款成功），UI 上的数字会自动跟着变。
##
## **测试用**：开局想直接有 20 枚，把下面「起始邮币」填成 20 即可 —— 那是"开局给多少"，
## 运行中想看现在有多少，读只读的 amount（或者在游戏里看右上角）。
##
## 数量一变就发 money_changed 信号，以后想加音效、飘字、图标闪烁就接它。
##
## 文字是「prefix + amount」拼出来的；**样式**（字号、描边、颜色）改 Label 自己的那几个
## theme_override_* 属性，那些不受本脚本影响。
##
## 现在整个项目只有水枪升级台会花这笔钱。以后钱要是变复杂了（存档、掉落物、想在好几处
## 同时显示），再把它拆成「钱包（Node）+ 显示（Label）」两个节点；现在合成一个是为了
## 少一层接线 —— 全项目只有这一处认钱，谁想花钱都得来问它。

## 开局给多少邮币。测试用，填多少开局就有多少。
@export var starting_money: int = 0

## 邮币数量每变一次发一次，参数是变化后的总数。
signal money_changed(amount: int)

## 当前数量。**只读**：改它请用 add_money() / spend() / set_money()。
var amount: int = 0:
	set(value):
		amount = maxi(value, 0)   # 兜底：邮币不会变成负数
		_refresh()
		money_changed.emit(amount)

## 数字前面的前缀，默认 "x "，于是显示成「x 0」。
@export var prefix: String = "x ":
	set(value):
		prefix = value
		_refresh()


func _ready() -> void:
	amount = maxi(starting_money, 0)   # 开局发钱；赋值时会把文字刷一遍


## 加钱（传负数就是扣钱，但总数不会低于 0）。以后打怪掉落、完成任务调这个。
func add_money(delta: int) -> void:
	amount += delta


## 花钱：钱够就扣掉并返回 true；不够则一分不扣、返回 false。
## 调用方直接看返回值就知道成没成，不用先问 can_afford()（问了也行）。
func spend(cost: int) -> bool:
	if not can_afford(cost):
		return false
	amount -= cost
	return true


## 买得起吗。价格填负数算"买不起"，免得手滑变成送钱。
func can_afford(cost: int) -> bool:
	return cost >= 0 and amount >= cost


## 直接设成某个数（读档、调试用）。
func set_money(value: int) -> void:
	amount = value


## 把前缀 + 数量写进 Label 的文字；改 amount / prefix 时会自动跑一遍。
func _refresh() -> void:
	text = "%s%d" % [prefix, amount]
