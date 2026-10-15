extends InteractStation
class_name ItemShop

## 两种道具共用交互台的菜单与锁人逻辑；这里只处理价格、扣款和购买结果。
## 购买信号只通知领取；具体使用效果连接手持道具的 item_used 信号。
signal item_purchased(item_id: StringName, effect_text: String)

const POSITIVE_ITEM: StringName = &"positive"
const NEGATIVE_ITEM: StringName = &"negative"

@export_group("接线")
## 共用邮币钱包；未绑定时不能购买。
@export var wallet: CurrencyLabel
## 玩家水枪；菜单打开期间停火，关闭后恢复打开前的状态。
@export var gun: WaterGun
## 玩家单格道具控制器；已有道具时禁止再次购买。
@export var inventory: HeldItemController
## 持有位置被占用时的提示。
@export var text_inventory_full: String = "已有道具，请先使用（F）"

@export_group("正面道具")
## 第一项商品的名称，菜单直接读取这里。
@export var positive_name: String = "正面道具"
## 第一项商品的效果说明；当前是占位文字，具体效果通过手持节点的使用信号接入。
@export var positive_effect_text: String = "正面"
## 第一项商品每次购买的价格（邮币），不会随购买次数涨价。
@export_range(0, 9999, 1) var positive_price: int = 10

@export_group("负面道具")
## 第二项商品的名称，菜单直接读取这里。
@export var negative_name: String = "负面道具"
## 第二项商品的效果说明；当前是占位文字，具体效果通过手持节点的使用信号接入。
@export var negative_effect_text: String = "负面"
## 第二项商品每次购买的价格（邮币），不会随购买次数涨价。
@export_range(0, 9999, 1) var negative_price: int = 10

@export_group("购买话术")
## 商品行的文字格式，依次填入名称和效果说明；说明留空时只显示名称。
@export var item_text_format: String = "%s · %s"
## 价格格式，填入这一项的邮币价格。
@export var price_format: String = "%d 枚"
## 菜单底部的余额格式。
@export var footer_format: String = "邮币 x %d"
## 成功购买的提示，依次填入商品名称和效果说明。
@export var purchase_message_format: String = "已购买%s：%s"

var _positive_count: int = 0  # 本次运行累计购买次数；当前持有和消耗由手持控制器负责
var _negative_count: int = 0  # 本次运行买到的负面道具数量
var _gun_muted: bool = false
var _gun_can_fire_backup: bool = true


func _ready() -> void:
	super()
	if is_instance_valid(wallet):
		wallet.money_changed.connect(_on_money_changed)
	if is_instance_valid(inventory):
		inventory.inventory_changed.connect(refresh_rows)


func _on_money_changed(_amount: int) -> void:
	refresh_rows()


func row_count() -> int:
	return 2


func row_text(index: int) -> String:
	var item_name: String = positive_name if index == 0 else negative_name
	var effect: String = positive_effect_text if index == 0 else negative_effect_text
	return item_name if effect.is_empty() else item_text_format % [item_name, effect]


func row_price_text(index: int) -> String:
	return price_format % _price(index)


func row_state(index: int) -> InteractOptionRow.State:
	if index < 0 or index >= row_count() or not is_instance_valid(wallet) or not is_instance_valid(inventory) or not inventory.can_receive():
		return InteractOptionRow.State.BLOCK
	return InteractOptionRow.State.OK if wallet.can_afford(_price(index)) else InteractOptionRow.State.BLOCK


func panel_footer() -> String:
	return footer_format % wallet.amount if is_instance_valid(wallet) and not footer_format.is_empty() else ""


func on_row_activated(index: int) -> void:
	if index < 0 or index >= row_count():
		return
	if not is_instance_valid(inventory) or not inventory.can_receive():
		show_message(text_inventory_full, false)
		return
	if not is_instance_valid(wallet) or not wallet.spend(_price(index)):
		show_message(text_blocked, false)
		return
	var item_id: StringName = POSITIVE_ITEM if index == 0 else NEGATIVE_ITEM
	var item_name: String = positive_name if index == 0 else negative_name
	var effect: String = positive_effect_text if index == 0 else negative_effect_text
	if not inventory.receive_item(item_id, effect):
		wallet.add_money(_price(index))
		return
	if index == 0:
		_positive_count += 1
	else:
		_negative_count += 1
	show_message(purchase_message_format % [item_name, effect], true)
	close_menu()
	item_purchased.emit(item_id, effect)


## 查询本次运行的已购数量；显示文字可以修改，商品标识 positive / negative 保持不变。
func purchased_count(item_id: StringName) -> int:
	if item_id == POSITIVE_ITEM:
		return _positive_count
	if item_id == NEGATIVE_ITEM:
		return _negative_count
	return 0


func _price(index: int) -> int:
	return positive_price if index == 0 else negative_price


func on_menu_opened() -> void:
	if is_instance_valid(gun) and not _gun_muted:
		_gun_can_fire_backup = gun.can_fire
		_gun_muted = true
		gun.can_fire = false


func on_menu_closed() -> void:
	_restore_gun()


func _restore_gun() -> void:
	if _gun_muted and is_instance_valid(gun):
		gun.can_fire = _gun_can_fire_backup
	_gun_muted = false


func _exit_tree() -> void:
	# 台座被删除时也归还移动、视角和水枪控制。
	close_menu()
	_restore_gun()
