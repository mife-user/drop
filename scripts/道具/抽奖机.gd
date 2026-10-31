extends InteractStation
class_name GachaMachine

## 抽奖机：对准之后按 E 直接抽一次，**不弹菜单**（所以这里把 open_menu 接管掉了）。
##
## 奖品和概率还没定，所以这里只放一张「占位表」：
##   prize_ids     —— 奖品 id，后面接进真正的道具系统时换成真实 id
##   prize_weights —— 对应的权重，一一对应，不用凑成 100（内部按总和归一）
## 现在填的是 60 / 30 / 10，三个占位 id，够跑通流程；
## 等定下来，把那两个数组换掉就行，别的代码一行都不用动。
##
## 抽中会发 prize_drawn 信号 —— 真正发奖品的逻辑挂在信号上，
## 不写进这个脚本里，免得以后加十种奖品就把这里塞满。

@export_group("接线")
## 邮币账本。抽一次扣的就是它。
@export var wallet: CurrencyLabel
## 机器上方那行结果文字（Label3D）。
@export var result_label: Label3D

@export_group("抽奖")
## 抽一次多少枚。准星那行提示会自动用这个数，不用手写。
@export_range(1, 999999, 1) var draw_cost: int = 1000
## 手持道具控制器：抽到降雨 / 海绵时交给它。
@export var inventory: HeldItemController

## 奖品表。**id 就是显示名**，同时决定发什么（见 _grant）。
##   "谢谢惠顾"  什么都不发
##   "降雨券"    给一件降雨道具
##   "海绵券"    给一件吸水海绵
##   "邮币 ×N"   直接往账本里加 N 枚（解析字符串里的数字）
## 权重合计 100，方便直接读成百分比。
@export var prize_ids: PackedStringArray = PackedStringArray([
	"谢谢惠顾", "降雨券", "海绵券", "邮币 ×300", "邮币 ×800",
])
## 权重表，和 prize_ids 一一对应。
@export var prize_weights: PackedInt32Array = PackedInt32Array([50, 20, 18, 10, 2])
## 结果文字停留多久（秒）。
@export_range(0.5, 10.0, 0.1) var result_hold: float = 2.5

## 抽中时发出，参数是 prize_ids 里的那一项。
signal prize_drawn(id: String)

var _rng := RandomNumberGenerator.new()
var _result_left: float = 0.0


func _ready() -> void:
	super()   # 基类在 _ready 里收菜单、找玩家和准星、把碰撞体接上
	_rng.randomize()
	# 提示里的价格跟着 draw_cost 走，改价格不用再改一遍场景里的文字
	prompt_text = "按 E 抽奖 · %d 枚" % draw_cost
	if is_instance_valid(result_label):
		result_label.text = ""
	if not is_instance_valid(wallet):
		push_warning("抽奖机（%s）：没接邮币账本，按 E 抽不了。" % name)


## 按 E 就直接抽 —— 不弹菜单、不锁玩家、不动鼠标。
func open_menu() -> void:
	_draw_once()


## 一次抽奖：查钱 → 扣钱 → 掷一次 → 发信号 → 显示结果。
func _draw_once() -> void:
	if not is_instance_valid(wallet):
		return
	if not wallet.can_afford(draw_cost):
		_show("邮币不足，还差 %d 枚" % (draw_cost - wallet.amount))
		return
	if not wallet.spend(draw_cost):
		return
	var id: String = _roll()
	var result: String = _grant(id)
	prize_drawn.emit(id)
	_show(result)


## 发奖。返回要显示的那行字。
## 「谢谢惠顾」什么都不发；两件道具交给手持道具，拿不下（手上已经有东西）就退成邮币，
## 免得玩家花了 1000 抽到一件已经在手上的道具，等于白花。
func _grant(id: String) -> String:
	if id.is_empty() or id == "谢谢惠顾":
		return "谢谢惠顾"
	if id == "降雨券" or id == "海绵券":
		var positive: bool = id == "降雨券"
		if is_instance_valid(inventory) and inventory.can_receive():
			var ok: bool = inventory.receive_item(
				&"positive" if positive else &"negative",
				"下雨" if positive else "吸水")
			if ok:
				return "抽到了：%s" % id
		# 拿不下就退邮币
		if is_instance_valid(wallet):
			wallet.add_money(200)
		return "手上已有道具，折算 200 枚"
	if id.begins_with("邮币"):
		var digits: String = ""
		for c in id:
			if c >= "0" and c <= "9":
				digits += c
		var amount: int = int(digits) if not digits.is_empty() else 0
		if amount > 0 and is_instance_valid(wallet):
			wallet.add_money(amount)
		return "抽到了：%s" % id
	return "谢谢惠顾"


## 按权重掷一个。权重不用凑成 100，内部按总和算；
## 全 0 或表是空的就返回空字符串（不会崩，也不会白扣钱——扣钱在调用处）。 
func _roll() -> String:
	var total: int = 0
	for w: int in prize_weights:
		total += maxi(w, 0)
	if total <= 0 or prize_ids.is_empty():
		return ""
	var pick: int = _rng.randi_range(1, total)
	var acc: int = 0
	for i: int in prize_ids.size():
		var w: int = prize_weights[i] if i < prize_weights.size() else 0
		acc += maxi(w, 0)
		if pick <= acc:
			return prize_ids[i]
	return prize_ids[prize_ids.size() - 1]


func _show(text: String) -> void:
	if is_instance_valid(result_label):
		result_label.text = text
		result_label.modulate.a = 1.0
	_result_left = result_hold


## 结果文字淡出。基类用的是 _physics_process，这里占 _process 不冲突。
func _process(delta: float) -> void:
	if _result_left <= 0.0:
		return
	_result_left -= delta
	if not is_instance_valid(result_label):
		return
	if _result_left <= 0.0:
		result_label.text = ""
	elif _result_left < 0.6:
		result_label.modulate.a = _result_left / 0.6
