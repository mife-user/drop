extends InteractStation
class_name FireHydrant

## 消防栓：**一个物体上挂两套动作，靠按 E 的时长分开**。
##
##   点按 E（按一下就松）→ 打开交互台，里面一行「装水速度」升级；
##   长按 E（按住不放）  → 给水枪接水，按装水速度往水箱里灌，灌满自动停。
##
## 分界线是基类的 hold_delay（默认 0.3 秒）。**两套动作都归基类管** ——
## 瞄准判定、准星那行字、E 键归谁、锁玩家，这里一行都不用写。
## 本文件只写两件事：「这一台卖什么」（下面那组 row_* 函数）和「按住时每秒干什么」（on_hold）。
##
## **装水速度存在这一台自己身上**（见下面的 fill_speed）：水枪只认识「水箱里有多少水」，
## 不关心水是怎么进去的，所以不给水枪加一个「注水速度」字段 ——
## 没有第二个消费者，加了只会多一个能配错的地方。
##
## 想再加一台同样的（水塔、水井、洗手池）：**新建继承场景** from
## `scenes/交互模板/交互台.tscn`，把模型拖进「模型」、根节点换成本脚本、
## 勾上「长按」，再填 title_text / prompt_text 和那两个接线就行。
##
## 升级不存档：退出或重开场景，装水速度就回到这里填的初始值（项目里还没有存档系统）。


@export_group("接线")
## 邮币账本（右上角那个数字）。花钱扣的就是它。
@export var wallet: CurrencyLabel
## 要接水的水枪发射器：长按 E 时往它的水箱里灌水。
@export var gun: WaterGun

@export_group("接水")
## 装水速度（立方米/秒）：按住 E 时每秒往水枪水箱里灌多少。
## **它同时就是下面「装水速度」那一行要升级的数值** —— 升级改的就是这一个变量本身，
## 不另存一份，所以买完立刻见效，不用重启场景。
@export_range(0.01, 10.0, 0.01) var fill_speed: float = 0.25

@export_group("装水速度这一行")
## 左边那句：两个 %f 依次是「现在多少」和「买完多少」。
@export var speed_text_format: String = "装水速度  %.2f → %.2f m³/秒"
## 已经升到头时那句（只有一个 %f）。
@export var speed_text_max_format: String = "装水速度  %.2f m³/秒（已满）"
## 每级加多少（立方米/秒）。
@export_range(0.01, 5.0, 0.01) var speed_step: float = 0.05
## 上限（立方米/秒）；到了就不再涨价、也买不了。
@export_range(0.05, 20.0, 0.05) var speed_max: float = 1.0
## 第一级的价格（邮币）。
@export_range(0, 999, 1) var speed_cost: int = 3
## 每买一级，下一级贵多少。
@export_range(0, 999, 1) var speed_cost_step: int = 2

@export_group("接水时的话术")
## 正在灌水时准星下面那句话；后面会自动跟一个百分比（「接水中 37%」）。
@export var filling_text: String = "接水中"
## 水箱已经满了时那句话 —— 不换一句的话，玩家按住看着数字不动会以为卡住了。
@export var text_full: String = "水箱已满"

@export_group("这一台自己的话术")
## 每一行右边的价格怎么写，%d 是钱数。
@export var price_format: String = "%d 枚"
## 已经到顶时右边写什么。
@export var price_max_text: String = "已满级"
## 菜单底部那行怎么写，%d 是当前邮币。留空 = 不显示。
@export var footer_format: String = "邮币 x %d"

var _speed_level: int = 0               # 装水速度买过几次（价格按它递增；速度本身存在 fill_speed 上）
var _gun_can_fire_backup: bool = true   # 我们关掉水枪之前它是什么状态，还回去时用
var _gun_muted: bool = false            # 现在是不是「我们把它关掉的」


func _ready() -> void:
	super()   # !!! 一定要调：基类在 _ready 里收菜单、把行铺好
	if is_instance_valid(wallet):
		wallet.money_changed.connect(_on_money_changed)
	if not hold_enabled:
		push_warning("消防栓（%s）：没勾「长按」，按住 E 只会开菜单、不会接水。" % name)


## 钱一变就重算菜单 —— 比如在别处花了钱，这里的价格颜色要立刻跟着变。
func _on_money_changed(_amount: int) -> void:
	refresh_rows()


# ——— 长按：接水 ———


## 长按生效（按住够 hold_delay 了）：把水枪关掉，免得玩家边接水边滋水（左键就在手边）。
func on_hold_started() -> void:
	_mute_gun()


## 长按结束（松手 / 准星移开）：把水枪还原成按住之前的样子。
func on_hold_stopped() -> void:
	_unmute_gun()


## 长按期间每帧：按装水速度往水箱里灌。
## 灌满之后 fill() 自己会返回 0，这里不用判断「满了没有」。
func on_hold(delta: float) -> void:
	if not is_instance_valid(gun):
		return
	gun.fill(fill_speed * delta)


## 长按期间准星下面那行字：带个百分比，玩家知道还要站多久。
func hold_hint_text() -> String:
	if not is_instance_valid(gun):
		return filling_text
	if gun.is_full():
		return text_full
	return "%s %d%%" % [filling_text, roundi(gun.fill_ratio() * 100.0)]


# ——— 菜单：只有一行「装水速度」（点按 E 打开）———


## 菜单只有一行（面板里多摆的行会自动隐藏，底板也会跟着缩短）。
func row_count() -> int:
	return 1


## 左边那句说明：「现在多少 → 买完多少」；到顶了就只写现在多少。
func row_text(_index: int) -> String:
	if _is_maxed():
		return speed_text_max_format % fill_speed
	return speed_text_format % [fill_speed, minf(fill_speed + speed_step, speed_max)]


## 右边的价格。
func row_price_text(_index: int) -> String:
	return price_max_text if _is_maxed() else price_format % _cost()


## 这一行现在能不能买：到顶了变灰，钱不够标红。
func row_state(_index: int) -> InteractOptionRow.State:
	if _is_maxed():
		return InteractOptionRow.State.DONE
	if not is_instance_valid(wallet) or not wallet.can_afford(_cost()):
		return InteractOptionRow.State.BLOCK
	return InteractOptionRow.State.OK


## 菜单底部那行「邮币 x N」。
func panel_footer() -> String:
	if not is_instance_valid(wallet) or footer_format.is_empty():
		return ""
	return footer_format % wallet.amount


## 左键点了这一行：先看到没到顶、再看钱够不够，最后才真扣钱、真改数值。
## 点完基类会自动刷新所有行，这里不用自己 refresh。
func on_row_activated(_index: int) -> void:
	if not is_instance_valid(wallet):
		return
	if _is_maxed():
		show_message(text_done, false)
		return
	if not wallet.spend(_cost()):
		show_message(text_blocked, false)
		return
	fill_speed = minf(fill_speed + speed_step, speed_max)
	_speed_level += 1
	show_message(text_success, true)


## 打开菜单时把水枪关掉：菜单里左键是「确认」，不关掉的话点选项时会顺手滋出一发水。
func on_menu_opened() -> void:
	_mute_gun()


## 收起菜单时还原成**打开前的值**，别硬写 true —— 玩家可能自己在检查器里关过。
func on_menu_closed() -> void:
	_unmute_gun()


# ——— 自己的小工具 ———


## 装水速度升到头了吗。
func _is_maxed() -> bool:
	return fill_speed >= speed_max - 0.0001


## 这一项现在卖多少钱：底价 + 已经买过几次 × 每次涨的价。
func _cost() -> int:
	return speed_cost + speed_cost_step * _speed_level


## 临时关掉水枪。**接水和开菜单都会走它**，所以用 _gun_muted 挡一道：
## 先关的那一方记下原状态，后一个再来关就是空操作，还原时才不会把状态还错。
func _mute_gun() -> void:
	if not is_instance_valid(gun) or _gun_muted:
		return
	_gun_can_fire_backup = gun.can_fire
	gun.can_fire = false
	_gun_muted = true


## 把水枪还原成我们关掉它之前的样子。
func _unmute_gun() -> void:
	if not is_instance_valid(gun) or not _gun_muted:
		return
	gun.can_fire = _gun_can_fire_backup
	_gun_muted = false
