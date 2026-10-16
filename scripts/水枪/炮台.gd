extends InteractStation
class_name WaterTurretStation

## 炮台商店：**花邮币买一座会自动喷水的炮台，再自己找地方把它放下去。**
##
## 菜单四行（面板里从上到下就是这四行，多出来的行面板会自动藏）：
##
## | 第几行 | 卖什么 |
## |---|---|
## | 0 | 购买炮台 —— 花邮币；买完菜单立刻收起，炮台跟着你走，**左键放下**（见 炮台发射器.gd） |
## | 1 | 发射间隔 —— 秒/发，越小喷得越密 |
## | 2 | 水块大小 —— 一发水多大（边长，米） |
## | 3 | 水量容量 —— 一箱水多少立方米，喷完炮台就没了 |
##
## **升级只影响之后买的炮台**：这一台自己存着一套「出厂规格」（下面 `出厂规格` 那组里的
## 三个数值），买的时候盖到新炮台上 —— 和「水块容器」给每团水盖合并规则是同一个写法。
## 已经摆在场上的炮台不会被回头改，免得出现「买的时候是 A、菜单上写着 B」两个真相。
##
## 同理，**菜单上显示的数字、买完生效的数字、炮台上那个数字是同一份** ——
## 这里改完立刻盖给下一座，不另存一份等级表。`_xxx_level` 那四个计数器只干一件事：算价格
## （见 docs/升级台.md 第二节）。
##
## 携带炮台期间：**玩家自己的水枪会被关掉**（那会儿左键是「放置」，不关就一键两用），
## 全场台座也**不许开菜单**（见 炮台发射器.gd 的 GROUP_BLOCK_INTERACT）。
## 炮台一落地，两样都自动还回来。

## 菜单里四行分别是什么。**顺序 = 面板里从上到下的顺序**，改顺序要连着场景里的行一起改。
enum Upgrade {
	BUY,       ## 购买炮台：花邮币，生成一座新的
	INTERVAL,  ## 发射间隔：秒/发，越小喷得越密（也越快把一箱水喷完）
	SIZE,      ## 水块大小：一发水多大
	CAPACITY,  ## 水量容量：一箱水多少立方米
}

@export_group("接线")
## 邮币账本（右上角那个数字）。花钱扣的就是它。
@export var wallet: CurrencyLabel
## 水块容器：炮台射出去的水也从这儿出生，和水枪共用一套水的规则与初速。
@export var field: WaterField
## 玩家自己的水枪：携带炮台期间把它关掉，炮台落地再还回来。
@export var gun: WaterGun
## 买到的那座炮台（scenes/炮台发射器.tscn）。换炮台造型就换这个场景。
@export var turret_scene: PackedScene

@export_group("出厂规格（下一座炮台按这个配）")
## 发射间隔（秒/发）：**越小喷得越密**，一箱水也越快喷完。
@export_range(0.05, 10.0, 0.05) var fire_interval: float = 1.0
## 一发水的边长（米）。扣水按边长的立方算，所以调大水块 = 每发更费水。
@export_range(0.05, 2.0, 0.01) var blob_size: float = 0.35
## 水箱容量（立方米）。**喷完这一箱，炮台就自己消失** ——
## 按 0.35 米的水块算，10 m³ 大约 233 发；发射间隔 1.0 秒/发 时能喷约 4 分钟。
@export_range(0.1, 100.0, 0.1) var capacity: float = 10.0
## 场上最多同时存在几座炮台。填 0 或负数 = 不限。
## 填 1 时：场上那座还在喷（或者你手上正拿着一座）就不能再买，得等它喷完。
@export var max_turrets: int = 1

@export_group("购买炮台这一行")
## 买一座要多少邮币。
@export_range(0, 9999, 1) var buy_cost: int = 10
## 每买一座，下一座贵多少（填 0 = 一直是上面那个价）。
@export_range(0, 9999, 1) var buy_cost_step: int = 0
## 能买时左边那句。
@export var buy_text: String = "购买炮台"
## 场上已经够多了时左边那句。
@export var buy_full_text: String = "场上已有炮台"
## 场上已经够多时右边写什么（这里没东西可买）。
@export var buy_full_price_text: String = "—"
## 场上已经够多时点了这一行弹的那句提示。
## 「已经升到头了」那句是给三条升级行用的，买炮台这行到顶的原因不一样，所以单独一句。
@export var text_busy: String = "场上已经有炮台了，等它喷完再来"

@export_group("发射间隔这一行")
## 左边那句：两个 %f 依次是「现在多少」和「买完多少」。
@export var interval_text_format: String = "发射间隔  %.2f → %.2f 秒/发"
## 已经升到头时那句（只有一个 %f）。
@export var interval_text_max_format: String = "发射间隔  %.2f 秒/发（已满）"
## 每级减少多少（秒/发）。**这一项是往小里升**，和另外两行相反。
@export_range(0.005, 2.0, 0.005) var interval_step: float = 0.05
## 最快能到多少（秒/发）；到了就不再涨价、也买不了。
@export_range(0.02, 5.0, 0.01) var interval_min: float = 0.2
## 第一级的价格（邮币）。
@export_range(0, 999, 1) var interval_cost: int = 3
## 每买一级，下一级贵多少。
@export_range(0, 999, 1) var interval_cost_step: int = 2

@export_group("水块大小这一行")
## 左边那句：两个 %f 依次是「现在多少」和「买完多少」。
@export var size_text_format: String = "水块大小  %.2f → %.2f m"
## 已经升到头时那句（只有一个 %f）。
@export var size_text_max_format: String = "水块大小  %.2f m（已满）"
## 每级加多少（米，水的边长）。
@export_range(0.005, 1.0, 0.005) var size_step: float = 0.03
## 上限（米）；到了就不再涨价、也买不了。
@export_range(0.05, 2.0, 0.01) var size_max: float = 0.5
## 第一级的价格（邮币）。
@export_range(0, 999, 1) var size_cost: int = 3
## 每买一级，下一级贵多少。
@export_range(0, 999, 1) var size_cost_step: int = 2

@export_group("水量容量这一行")
## 左边那句：两个 %f 依次是「现在多少」和「买完多少」。
@export var cap_text_format: String = "水量容量  %.1f → %.1f m³"
## 已经升到头时那句（只有一个 %f）。
@export var cap_text_max_format: String = "水量容量  %.1f m³（已满）"
## 每级加多少（立方米）。
@export_range(0.1, 50.0, 0.1) var cap_step: float = 5.0
## 上限（立方米）；到了就不再涨价、也买不了。
@export_range(0.5, 100.0, 0.5) var cap_max: float = 30.0
## 第一级的价格（邮币）。
@export_range(0, 999, 1) var cap_cost: int = 5
## 每买一级，下一级贵多少。
@export_range(0, 999, 1) var cap_cost_step: int = 3

@export_group("这一台自己的话术")
## 每一行右边的价格怎么写，%d 是钱数。
@export var price_format: String = "%d 枚"
## 已经到顶（或者场上已经够多了）时右边写什么。
@export var price_max_text: String = "已满级"
## 菜单底部那行怎么写，%d 是当前邮币。留空 = 不显示。
@export var footer_format: String = "邮币 x %d"

var _turrets: Array[WaterTurret] = []   # 这一台卖出去、还活着的炮台（喷完的会被剔掉）
var _made: int = 0                      # 一共造过几座，只用来给节点起名
var _buy_level: int = 0                 # 买过几次（价格按它递增）
var _interval_level: int = 0            # 发射间隔买过几次（数值本身存在 fire_interval 上）
var _size_level: int = 0                # 水块大小买过几次
var _cap_level: int = 0                 # 容量买过几次
var _gun_can_fire_backup: bool = true   # 开菜单前水枪的开关状态，还回去时用
var _gun_muted: bool = false            # 现在是不是「我们把它关掉的」


func _ready() -> void:
	super()   # !!! 基类负责收菜单、把行铺好
	if is_instance_valid(wallet):
		wallet.money_changed.connect(_on_money_changed)
	if turret_scene == null:
		push_warning("炮台商店（%s）：没填「炮台场景」，买不出炮台。" % name)
	if not is_instance_valid(field):
		push_warning("炮台商店（%s）：没接「水块容器」，买出来的炮台射不出水。" % name)
	if not is_instance_valid(wallet):
		push_warning("炮台商店（%s）：没接邮币账本，菜单里全是红字、什么都买不了。" % name)


## 钱一变就重算菜单 —— 比如在别处花了钱，这里的价格颜色要立刻跟着变。
func _on_money_changed(_amount: int) -> void:
	refresh_rows()


## 重算菜单之前先把名单清一遍：炮台喷完是 queue_free 掉的，这儿把失效的引用剔掉，
## 「场上已有炮台」那行才会在它消失后自己变回「购买炮台」。
func refresh_rows() -> void:
	_prune_turrets()
	super()


# —— 四行菜单 ———


## 菜单四行：购买 / 发射间隔 / 水块大小 / 水量容量（顺序和 Upgrade 枚举一致）。
func row_count() -> int:
	return 4


## 左边那句说明。能买的行是「现在多少 → 买完多少」，到顶了就只写现在多少。
func row_text(index: int) -> String:
	match index:
		Upgrade.BUY:
			return buy_text if _can_buy() else buy_full_text
		Upgrade.INTERVAL:
			if _is_maxed(index):
				return interval_text_max_format % fire_interval
			return interval_text_format % [fire_interval, maxf(fire_interval - interval_step, interval_min)]
		Upgrade.SIZE:
			if _is_maxed(index):
				return size_text_max_format % blob_size
			return size_text_format % [blob_size, minf(blob_size + size_step, size_max)]
		_:
			if _is_maxed(index):
				return cap_text_max_format % capacity
			return cap_text_format % [capacity, minf(capacity + cap_step, cap_max)]


## 右边的价格。
func row_price_text(index: int) -> String:
	if index == Upgrade.BUY:
		if not _can_buy():
			return buy_full_price_text
		return price_format % _buy_cost()
	if _is_maxed(index):
		return price_max_text
	return price_format % _cost(index)


## 这一行现在能不能选：到顶/买够了变灰，钱不够标红。
func row_state(index: int) -> InteractOptionRow.State:
	if index == Upgrade.BUY:
		if not _can_buy():
			return InteractOptionRow.State.DONE
	elif _is_maxed(index):
		return InteractOptionRow.State.DONE
	if not is_instance_valid(wallet) or not wallet.can_afford(_cost(index)):
		return InteractOptionRow.State.BLOCK
	return InteractOptionRow.State.OK


## 菜单底部那行「邮币 x N」。
func panel_footer() -> String:
	if not is_instance_valid(wallet) or footer_format.is_empty():
		return ""
	return footer_format % wallet.amount


## 左键点了某一行：先看买不买得了（到顶 / 场上够了）、再看钱够不够，最后才真扣钱。
## 点完基类会自动刷新所有行，这里不用自己 refresh。
func on_row_activated(index: int) -> void:
	if not is_instance_valid(wallet):
		return
	if index == Upgrade.BUY:
		_buy()
		return
	if _is_maxed(index):
		show_message(text_done, false)
		return
	if not wallet.spend(_cost(index)):
		show_message(text_blocked, false)
		return
	_apply_upgrade(index)
	show_message(text_success, true)


# —— 菜单开关时：关掉 / 还回玩家的水枪 ———


## 菜单打开时把水枪关掉：菜单里左键是「确认」，不关掉的话点选项会顺手滋出一发水。
func on_menu_opened() -> void:
	_mute_gun()


## 收起菜单时把水枪还回来 —— **除非还在携带炮台**：
## 那会儿左键是「放置」，水枪得继续关着，等炮台落地（_on_turret_placed）才还。
func on_menu_closed() -> void:
	if _carrying_turret() != null:
		return
	_unmute_gun()


# —— 买东西 ———


## 买一座炮台：扣钱 → 造出来（按出厂规格配好）→ 交到玩家手上 → 收菜单。
## **先 begin_carry 再 close_menu**：这样 on_menu_closed() 看到「还在携带」，就不会
## 把刚关掉的水枪又打开（收菜单和携带都要关水枪，这两件事在基类里正好会打架）。
func _buy() -> void:
	if not _can_buy():
		show_message(text_busy, false)
		return
	if is_instance_valid(wallet) and not wallet.spend(_buy_cost()):
		show_message(text_blocked, false)
		return
	var turret: WaterTurret = _spawn_turret()
	if turret == null:
		if is_instance_valid(wallet):
			wallet.add_money(_buy_cost())   # 造不出来就把钱退回去，别白扣
		show_message(text_blocked, false)
		return
	_buy_level += 1
	turret.begin_carry()
	close_menu()


## 造一座炮台。**先按出厂规格填好再入树** —— 水枪类的 _ready() 会拿 capacity 当满水开局，
## 而入树之后 capacity 就已经不能再改了（改了读数会跟着对不上）。
func _spawn_turret() -> WaterTurret:
	if turret_scene == null:
		push_error("炮台商店：没填 turret_scene，买不出炮台")
		return null
	var turret: WaterTurret = turret_scene.instantiate() as WaterTurret
	if turret == null:
		push_error("炮台商店：turret_scene 的根节点没有继承 WaterTurret，买不出炮台")
		return null
	turret.field = field
	turret.fire_interval = fire_interval
	turret.blob_size = blob_size
	turret.capacity = capacity
	_made += 1
	turret.name = "炮台%d" % _made
	add_child(turret)   # 挂在商店下面：商店在检查器里的位置就是它的出发点，别给商店加缩放
	turret.placed.connect(_on_turret_placed)
	turret.tree_exited.connect(_on_turret_gone)
	_turrets.append(turret)
	return turret


## 炮台落地了：玩家的水枪还回去，菜单上「场上已有炮台」那行跟着变。
func _on_turret_placed() -> void:
	_unmute_gun()
	refresh_rows()


## 炮台没了（水喷完自己消失，或者被玩家看着按 P 拆了）。**这里也是水枪的兜底** ——
## 万一炮台不是正常放下的（被别处删掉），水枪也得还回来，不能让它一直关着。
##
## **但菜单正开着的时候不能还**：那会儿左键是「确认」，还回去就成了「点选项顺手滋出一发水」。
## 等菜单收起时 on_menu_closed() 会还（_gun_muted 还记着，还原的是开菜单前的那个值），
## 所以这里跳过一下不会漏。玩家站在商店里、场上的炮台正好在这会儿喷完水或被拆，就会撞上这条。
func _on_turret_gone() -> void:
	if not (is_instance_valid(panel) and panel.is_open()):
		_unmute_gun()
	refresh_rows()


## 真把出厂规格改上去。改的就是上面那三个变量本身 —— 菜单显示的和买完生效的是同一份。
func _apply_upgrade(index: int) -> void:
	match index:
		Upgrade.INTERVAL:
			fire_interval = maxf(fire_interval - interval_step, interval_min)
			_interval_level += 1
		Upgrade.SIZE:
			blob_size = minf(blob_size + size_step, size_max)
			_size_level += 1
		_:
			capacity = minf(capacity + cap_step, cap_max)
			_cap_level += 1


# —— 自己的小工具 ———


## 现在能不能买：没有一座正拿在手上，而且场上还没到上限。
func _can_buy() -> bool:
	if _carrying_turret() != null:
		return false
	return max_turrets <= 0 or _alive_count() < max_turrets


## 现在拿在手上的那座炮台（没有就返回 null）。
func _carrying_turret() -> WaterTurret:
	for turret: WaterTurret in _turrets:
		if is_instance_valid(turret) and turret.carrying:
			return turret
	return null


## 场上还活着几座（喷完收缩中的也算，它还在那儿）。
func _alive_count() -> int:
	_prune_turrets()
	return _turrets.size()


## 把已经没了的炮台从名单里剔掉。
## **「不在场景树里」也要算没了**：tree_exited 是炮台正在被销毁的那一刻发出来的，
## 那时候节点还没真正 free、is_instance_valid() 仍然返回 true —— 只判这一个的话，
## 菜单上「场上已有炮台」那行会赖着不走，直到下一次刷新才恢复。
func _prune_turrets() -> void:
	for i: int in range(_turrets.size() - 1, -1, -1):
		var turret: WaterTurret = _turrets[i]
		if not is_instance_valid(turret) or not turret.is_inside_tree():
			_turrets.remove_at(i)


## 这一项现在卖多少钱：底价 + 已经买过几次 × 每次涨的价。
func _cost(index: int) -> int:
	match index:
		Upgrade.BUY:
			return _buy_cost()
		Upgrade.INTERVAL:
			return interval_cost + interval_cost_step * _interval_level
		Upgrade.SIZE:
			return size_cost + size_cost_step * _size_level
		_:
			return cap_cost + cap_cost_step * _cap_level


## 这一座炮台现在卖多少钱。
func _buy_cost() -> int:
	return buy_cost + buy_cost_step * _buy_level


## 升到头了吗。**发射间隔是往小里升，所以判的是下限**（见 docs/升级台.md 第二节那 0.0001）。
func _is_maxed(index: int) -> bool:
	match index:
		Upgrade.INTERVAL:
			return fire_interval <= interval_min + 0.0001
		Upgrade.SIZE:
			return blob_size >= size_max - 0.0001
		Upgrade.CAPACITY:
			return capacity >= cap_max - 0.0001
	return false   # 购买那一行没有「升到头」这回事，它满不满看 _can_buy()


## 临时关掉水枪。**开菜单和携带都会走它**，所以用 _gun_muted 挡一道：
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
