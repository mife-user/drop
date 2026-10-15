extends InteractStation
class_name WaterGunStation

## 水枪升级台：全场唯一认「升级规则」的地方。
##
## **菜单长什么样、怎么瞄、怎么选、怎么关、怎么锁人，全在基类（交互台.gd）里** ——
## 这个文件只写「这一台卖什么」：两行文字、价格、买完之后数值怎么变。
## 以后要做别的可交互物体（消防栓、贩卖机、门），照这个文件抄一份就行：
## 继承 InteractStation，实现下面那几个 row_* 函数，场景照 scenes/交互台.tscn 复制。
##
## **升级改的是那两个数值本身，不另存一份**：「出水速度」写回水块容器的 muzzle_speed，
## 「水块大小」写回水枪的 blob_size —— 全项目只有那两处定义弹道速度和一发水的大小。
##
## 注意：水块大小升上去之后，**地上原来那些小的水团不会跟新射出来的合并** ——
## 合并是按边长认的（容差 5%），边长变了就是另一档。这是既有设计，不是这里改坏了。

## 能升哪两项。**顺序就是菜单里从上到下的顺序**：0 = 速度行，1 = 大小行。
enum Upgrade {
	SPEED, ## 出水速度：射得更远、弧线更平
	SIZE,  ## 水块大小：一发水更大、地上更早攒出大水团
}

@export_group("升级对象")
## 邮币账本（右上角那个数字）。花钱扣的就是它。
@export var wallet: CurrencyLabel
## 水枪发射器：升级「水块大小」改它的 blob_size。
@export var gun: WaterGun
## 水块容器：升级「出水速度」改它的 muzzle_speed。
@export var field: WaterField

@export_group("出水速度这一行")
## 左边那句：两个 %f 依次是「现在多少」和「买完多少」。
@export var speed_text_format: String = "出水速度  %.1f → %.1f m/s"
## 已经升到头时那句（只有一个 %f）。
@export var speed_text_max_format: String = "出水速度  %.1f m/s（已满）"
## 每级加多少（米/秒）。
@export_range(0.5, 20.0, 0.5) var speed_step: float = 2.5
## 上限（米/秒）；到了就不再涨价、也买不了。太快弹道会平得像激光。
@export_range(5.0, 80.0, 0.5) var speed_max: float = 30.0
## 第一级的价格（邮币）。
@export_range(0, 999, 1) var speed_cost: int = 3
## 每买一级，下一级贵多少。
@export_range(0, 999, 1) var speed_cost_step: int = 2

@export_group("水块大小这一行")
## 左边那句：两个 %f 依次是「现在多少」和「买完多少」。
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

@export_group("这一台自己的话术")
## 每一行右边的价格怎么写，%d 是钱数。
@export var price_format: String = "%d 枚"
## 已经到顶时右边写什么。
@export var price_max_text: String = "已满级"
## 菜单底部那行怎么写，%d 是当前邮币。留空 = 不显示。
@export var footer_format: String = "邮币 x %d"

var _speed_level: int = 0   # 速度买过几次（价格按它递增；数值本身存在水块容器上，不在这儿）
var _size_level: int = 0    # 大小买过几次
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


func row_count() -> int:
	return 2


## 左边那句说明：「现在多少 → 买完多少」；到顶了就只写现在多少。
func row_text(index: int) -> String:
	if index == Upgrade.SPEED:
		if not is_instance_valid(field):
			return "出水速度  ——"
		if _is_maxed(index):
			return speed_text_max_format % field.muzzle_speed
		return speed_text_format % [field.muzzle_speed, minf(field.muzzle_speed + speed_step, speed_max)]
	if not is_instance_valid(gun):
		return "水块大小  ——"
	if _is_maxed(index):
		return size_text_max_format % gun.blob_size
	return size_text_format % [gun.blob_size, minf(gun.blob_size + size_step, size_max)]


## 右边的价格。
func row_price_text(index: int) -> String:
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
	if not is_instance_valid(wallet):
		return
	if _is_maxed(index):
		show_message(text_done, false)
		return
	if not wallet.spend(_cost(index)):
		show_message(text_blocked, false)
		return
	_apply_upgrade(index)
	show_message(text_success, true)


## 升到头了吗。
func _is_maxed(index: int) -> bool:
	if index == Upgrade.SPEED:
		return not is_instance_valid(field) or field.muzzle_speed >= speed_max - 0.001
	return not is_instance_valid(gun) or gun.blob_size >= size_max - 0.001


## 这一项现在卖多少钱：底价 + 已经买过几次 × 每次涨的价。
func _cost(index: int) -> int:
	if index == Upgrade.SPEED:
		return speed_cost + speed_cost_step * _speed_level
	return size_cost + size_cost_step * _size_level


## 真把数值改上去。改的是水块容器 / 水枪上那两处唯一的定义。
func _apply_upgrade(index: int) -> void:
	if index == Upgrade.SPEED:
		field.muzzle_speed = minf(field.muzzle_speed + speed_step, speed_max)
		_speed_level += 1
		return
	gun.blob_size = minf(gun.blob_size + size_step, size_max)
	_size_level += 1
