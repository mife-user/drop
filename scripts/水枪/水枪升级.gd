extends InteractStation
class_name WaterGunStation

## 水枪升级台：全场唯一认「升级规则」的地方。
##
## **菜单长什么样、怎么瞄、怎么选、怎么关、怎么锁人，全在基类（交互框/交互台.gd）里** ——
## 这个文件只写「这一台卖什么」：三行文字、价格、买完之后数值怎么变。
## 以后要做别的可交互物体（消防栓、贩卖机、门），照这个文件抄一份脚本就行：
## 继承 InteractStation，实现下面那几个 row_* 函数；场景则从
## `scenes/交互模板/交互台.tscn` **新建继承场景**，把模型拖进「模型」节点。
##
## **三行改的都是水枪身上那三个变量本身，不另存一份**：
## 发射频率 → fire_interval，水块大小 → blob_size，水量容量 → capacity。
##
## 两处联动，改的时候心里有数：
## · 水块大小升上去之后，**地上原来那些小的水团不会跟新射出来的合并** ——
##   合并是按边长认的（容差 5%），边长变了就是另一档。这是既有设计，不是这里改坏了。
## · 水块变大 = 每发耗水变多（一发就是边长³），**同一箱水能射的发数会变少** ——
##   所以「水量容量」那一行正好是给它兜底的。

## 菜单里从上到下的三行。**顺序就是枚举顺序**，改顺序改这里 + row_* 里的判断。
enum Upgrade {
	FREQ,     ## 发射频率：改水枪的 fire_interval（隔几秒一发），间隔越短喷得越密
	SIZE,     ## 水块大小：改水枪的 blob_size，一发水更大
	CAPACITY, ## 水量容量：改水枪的 capacity，一箱能装多少立方米
}

@export_group("升级对象")
## 邮币账本（右上角那个数字）。花钱扣的就是它。
@export var wallet: CurrencyLabel
## 水枪发射器。**三行改的都是它身上的数**，所以只接这一根线。
@export var gun: WaterGun

@export_group("发射频率这一行")
## 左边那句：两个 %f 依次是「现在多少」和「买完多少」，单位是「发/秒」。
@export var freq_text_format: String = "发射频率  %.2f → %.2f 发/秒"
## 已经升到头时那句（只有一个 %f）。
@export var freq_text_max_format: String = "发射频率  %.2f 发/秒（已满）"
## 每级少多少秒（发射间隔）。
## **这个步长要对着 fire_interval 的实际值来定**：枪上填 0.12 秒时，0.015 一步是 12%（刚好）；
## 要是把 fire_interval 填成 2.0 秒来测试，同一步长只有 0.75%，买一级几乎看不出来。
@export_range(0.001, 0.5, 0.001) var interval_step: float = 0.015
## 最短间隔（秒）；到了就不再涨价、也买不了。太快就成一条水柱了。
@export_range(0.02, 2.0, 0.01) var interval_min: float = 0.05
## 第一级的价格（邮币）。
@export_range(0, 999, 1) var freq_cost: int = 3
## 每买一级，下一级贵多少。
@export_range(0, 999, 1) var freq_cost_step: int = 2

@export_group("水块大小这一行")
## 左边那句：两个 %f 依次是「现在多少」和「买完多少」，单位是米（水的边长）。
@export var size_text_format: String = "水块大小  %.2f → %.2f m"
## 已经升到头时那句（只有一个 %f）。
@export var size_text_max_format: String = "水块大小  %.2f m（已满）"
## 每级加多少（米，水的边长）。
@export_range(0.005, 1.0, 0.005) var size_step: float = 0.03
## 上限（米）；到了就不再涨价、也买不了。太大的水块永远合不到一起。
@export_range(0.05, 2.0, 0.01) var size_max: float = 0.5
## 第一级的价格（邮币）。
@export_range(0, 999, 1) var size_cost: int = 3
## 每买一级，下一级贵多少。
@export_range(0, 999, 1) var size_cost_step: int = 2

@export_group("水量容量这一行")
## 左边那句：两个 %f 依次是「现在多少」和「买完多少」，单位是立方米。
@export var capacity_text_format: String = "水量容量  %.2f → %.2f m³"
## 已经升到头时那句（只有一个 %f）。
@export var capacity_text_max_format: String = "水量容量  %.2f m³（已满）"
## 水枪的 capacity 填 0（不限制）时那句 —— 无限的箱子没有升容量的意义，这一行会变灰、买不了。
@export var capacity_unlimited_text: String = "水量容量  不限制"
## 上面那种情况下，右边价格那格写什么。
@export var capacity_unlimited_price_text: String = "—"
## 每级加多少（立方米）。
@export_range(0.05, 10.0, 0.05) var capacity_step: float = 0.5
## 上限（立方米）；到了就不再涨价、也买不了。
@export_range(0.05, 100.0, 0.05) var capacity_max: float = 5.0
## 第一级的价格（邮币）。
@export_range(0, 999, 1) var capacity_cost: int = 3
## 每买一级，下一级贵多少。
@export_range(0, 999, 1) var capacity_cost_step: int = 2

@export_group("这一台自己的话术")
## 每一行右边的价格怎么写，%d 是钱数。
@export var price_format: String = "%d 枚"
## 已经到顶时右边写什么。
@export var price_max_text: String = "已满级"
## 菜单底部那行怎么写，%d 是当前邮币。留空 = 不显示。
@export var footer_format: String = "邮币 x %d"

var _freq_level: int = 0       # 频率买过几次（价格按它递增；数值本身在水枪上，不在这儿）
var _size_level: int = 0       # 大小买过几次
var _capacity_level: int = 0   # 容量买过几次
var _gun_can_fire_backup: bool = true   # 开菜单前水枪的开关状态，关菜单要还原


func _ready() -> void:
	super()   # 基类负责收菜单、把行铺好
	if is_instance_valid(wallet):
		wallet.money_changed.connect(_on_money_changed)


## 钱一变就重算菜单 —— 比如在别处花了钱，这里的价格颜色要立刻跟着变。
func _on_money_changed(_amount: int) -> void:
	refresh_rows()


## 菜单打开时把水枪关掉：菜单里左键是「确认」，不关掉的话按左键会顺手滋出一发水。
func on_menu_opened() -> void:
	_gun_can_fire_backup = gun.can_fire if is_instance_valid(gun) else true
	if is_instance_valid(gun):
		gun.can_fire = false


## 收起菜单时把水枪还原成打开前的样子（别把玩家自己在检查器里关掉的开关又打开）。
func on_menu_closed() -> void:
	if is_instance_valid(gun):
		gun.can_fire = _gun_can_fire_backup


## 三行：第 0 行发射频率、第 1 行水块大小、第 2 行水量容量（顺序和 Upgrade 枚举一致）。
## 菜单面板本来就摆着三行，这里说 3 它就显示 3 行、底板自动变高。
func row_count() -> int:
	return 3


## 左边那句说明：「现在多少 → 买完多少」；到顶了就只写现在多少。
func row_text(index: int) -> String:
	if not is_instance_valid(gun):
		return "—"
	match index:
		Upgrade.FREQ:
			if _is_maxed(index):
				return freq_text_max_format % _frequency()
			return freq_text_format % [_frequency(), _frequency_after()]
		Upgrade.SIZE:
			if _is_maxed(index):
				return size_text_max_format % gun.blob_size
			return size_text_format % [gun.blob_size, minf(gun.blob_size + size_step, size_max)]
		_:
			if gun.capacity <= 0.0:
				return capacity_unlimited_text
			if _is_maxed(index):
				return capacity_text_max_format % gun.capacity
			return capacity_text_format % [gun.capacity, minf(gun.capacity + capacity_step, capacity_max)]


## 右边的价格。
func row_price_text(index: int) -> String:
	if index == Upgrade.CAPACITY and is_instance_valid(gun) and gun.capacity <= 0.0:
		return capacity_unlimited_price_text
	return price_max_text if _is_maxed(index) else price_format % _cost(index)


## 这一行现在能不能买：到顶了变灰，钱不够标红。
func row_state(index: int) -> InteractOptionRow.State:
	if _is_maxed(index):
		return InteractOptionRow.State.DONE
	if not is_instance_valid(wallet) or not wallet.can_afford(_cost(index)):
		return InteractOptionRow.State.BLOCK
	return InteractOptionRow.State.OK


## 菜单底部那行「邮币 x N」。
func panel_footer() -> String:
	if not is_instance_valid(wallet) or footer_format.is_empty():
		return ""
	return footer_format % wallet.amount


## 左键点了某一行：先看有没有升到头、再看钱够不够，最后才真扣钱、真改数值。
func on_row_activated(index: int) -> void:
	if not is_instance_valid(wallet) or not is_instance_valid(gun):
		return
	if _is_maxed(index):
		show_message(text_done, false)
		return
	if not wallet.spend(_cost(index)):
		show_message(text_blocked, false)
		return
	_apply_upgrade(index)
	show_message(text_success, true)


## 升到头了吗（也包括「没必要升」的情况：容量填 0 = 不限制，给无限的箱子加容量没意义）。
func _is_maxed(index: int) -> bool:
	if not is_instance_valid(gun):
		return true
	match index:
		Upgrade.FREQ:
			return gun.fire_interval <= interval_min + 0.0001
		Upgrade.SIZE:
			return gun.blob_size >= size_max - 0.001
		_:
			return gun.capacity <= 0.0 or gun.capacity >= capacity_max - 0.001


## 这一项现在卖多少钱：底价 + 已经买过几次 × 每次涨的价。
func _cost(index: int) -> int:
	match index:
		Upgrade.FREQ:
			return freq_cost + freq_cost_step * _freq_level
		Upgrade.SIZE:
			return size_cost + size_cost_step * _size_level
		_:
			return capacity_cost + capacity_cost_step * _capacity_level


## 真把数值改上去。改的都是水枪上那三个变量本身。
func _apply_upgrade(index: int) -> void:
	match index:
		Upgrade.FREQ:
			gun.fire_interval = maxf(gun.fire_interval - interval_step, interval_min)
			_freq_level += 1
		Upgrade.SIZE:
			gun.blob_size = minf(gun.blob_size + size_step, size_max)
			_size_level += 1
		_:
			# 走水枪自己的入口：直接写 capacity 的话，水枪上方那块读数不会跟着刷新
			gun.set_capacity(minf(gun.capacity + capacity_step, capacity_max))
			_capacity_level += 1


## 现在的发射频率（发/秒）。水枪上是「隔几秒一发」，取个倒数。
## 世界属性面板里那个「频率」也是这么算的，两边同一个出处。
func _frequency() -> float:
	return 1.0 / maxf(gun.fire_interval, 0.001)


## 买下这一级之后的发射频率（发/秒）。
func _frequency_after() -> float:
	return 1.0 / maxf(maxf(gun.fire_interval - interval_step, interval_min), 0.001)
