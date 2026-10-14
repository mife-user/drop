extends Node3D
class_name UpgradeStation

## 水枪升级台：这是全场唯一认「升级规则」的地方。
##
## 玩法：人走到跟前、**准星对着它** → 屏幕中心的准星从圆点变成 [E] 键帽 +「升级水枪」；
## 按 E 从它头顶浮出一块面板 → **转动视角把准星扫到想升的那一行**（那一行会亮起来）
## → 再按一次 E 就买下来。Esc 或走远了自动收起面板。
##
## 面板打开时**不冻结玩家**（还能走、还能看），只把水枪暂时关掉 ——
## 因为水枪是按「按住没按住左键」判开火的，不关掉的话玩家看面板时按到左键会顺手滋出一发水。
##
## 三块东西各管各的，改哪块只动哪块：
##   · 这里（升级台）—— 什么时候能交互、买哪一项、多少钱、买完数值变成多少
##   · 升级面板 / 升级行 —— 只负责长什么样；钱和数值都是这里算好喂进去的
##   · 交互准星 —— 屏幕中心那个圆点 / E 键帽，只负责显示
##
## **升级改的是那两个数值本身，不另存一份**：
## 「出水速度」写回水块容器的 muzzle_speed，「水块大小」写回水枪的 blob_size ——
## 全项目只有那两处定义弹道速度和一发水的大小，改完下一发立刻生效。
##
## 注意：水块大小升上去之后，**地上原来那些小的水团不会跟新射出来的合并** ——
## 合并是按边长认的（容差 5%），边长变了就是另一档。这是既有设计，不是这里改坏了。

## 能升哪两项。
enum Upgrade {
	SPEED, ## 出水速度：写回水块容器的 muzzle_speed，射得更远、弧线更平
	SIZE,  ## 水块大小：写回水枪的 blob_size，一发水更大、地上更早攒出大水团
}

## 按哪个键交互；项目设置里没有这个动作时会在这里告警（键还能用，只是不会响应）。
const INTERACT_ACTION: StringName = &"interact"


@export_group("接线")
## 邮币账本（右上角那个数字）。花钱扣的就是它。
@export var wallet: CurrencyLabel
## 水枪发射器：升级「水块大小」改它的 blob_size。
@export var gun: WaterGun
## 水块容器：升级「出水速度」改它的 muzzle_speed。
@export var field: WaterField
## 屏幕中心的准星（HUD 上的那份）。
@export var crosshair: InteractCrosshair
## 悬浮升级面板（本场景里的子节点）。
@export var panel: UpgradePanel
## 自己的碰撞体。准星打到它 = 玩家正对着升级台，才允许交互。
@export var body: CollisionObject3D

@export_group("交互")
## 隔多远还能交互（米）。射程之外不弹提示。
@export_range(0.5, 10.0, 0.1) var interact_distance: float = 3.0
## 交互射线查哪些层。默认「世界(1) + 可交互(5)」：世界层是用来挡视线的 ——
## 隔着墙就不该弹提示，所以打到墙一律当作没瞄准。改层号的话记得这里也跟着改。
@export_flags_3d_physics var ray_mask: int = 17
## 走开多远自动收起面板（米）。面板浮在半空，人走远了还留着很怪。
@export_range(1.0, 20.0, 0.5) var close_distance: float = 4.5

@export_group("升级·出水速度")
## 每升一级加多少（米/秒）。
@export_range(0.5, 20.0, 0.5) var speed_step: float = 2.5
## 上限（米/秒）。到了就不再涨价、也买不了 —— 太快弹道会平得像激光。
@export_range(5.0, 80.0, 0.5) var speed_max: float = 30.0
## 第一级的价格（邮币）。
@export_range(0, 999, 1) var speed_cost: int = 3
## 每买一级，下一级贵多少。
@export_range(0, 999, 1) var speed_cost_step: int = 2

@export_group("升级·水块大小")
## 每升一级加多少（米，水的边长）。
@export_range(0.005, 1.0, 0.005) var size_step: float = 0.03
## 上限（米）。到了就不再涨价、也买不了 —— 太大的水块永远合不到一起、还会糊满屏幕。
@export_range(0.05, 2.0, 0.01) var size_max: float = 0.5
## 第一级的价格（邮币）。
@export_range(0, 999, 1) var size_cost: int = 3
## 每买一级，下一级贵多少。
@export_range(0, 999, 1) var size_cost_step: int = 2

var _speed_level: int = 0      # 速度买过几次（价格按它递增；数值本身存在水块容器上）
var _size_level: int = 0       # 大小买过几次
var _targeting: bool = false   # 准星这会儿是不是正对着升级台
var _selected: int = -1        # 面板开着时，准星扫到的是哪一行（-1 = 没扫到）
var _gun_can_fire_backup: bool = true   # 开面板前水枪的开关状态，关面板要还原


func _ready() -> void:
	if is_instance_valid(wallet):
		wallet.money_changed.connect(_on_money_changed)
	_refresh_panel()
	if not InputMap.has_action(INTERACT_ACTION):
		push_warning("水枪升级：项目设置里没有「%s」这个输入动作，按 E 不会有反应" % INTERACT_ACTION)


func _physics_process(_delta: float) -> void:
	var collider: Object = _aimed_object()
	_targeting = is_instance_valid(body) and collider == body
	if is_instance_valid(panel) and panel.is_open():
		_update_panel(collider)
	else:
		_update_prompt()


## 按 E：面板开着就买下准星扫到的那一行，没开就展开面板。
## 用事件（_unhandled_input）而不是每帧问 Input，是为了「按一下只算一次」——
## 同一次按键不会既开面板又立刻被面板当成确认。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(INTERACT_ACTION):
		return
	get_viewport().set_input_as_handled()
	if is_instance_valid(panel) and panel.is_open():
		if _selected >= 0:
			_buy(_selected)
	elif _targeting:
		_open_panel()


## 面板没开时的每帧更新：正对着就提示「按 E 升级」，否则恢复成普通准星。
func _update_prompt() -> void:
	if not is_instance_valid(crosshair):
		return
	if _targeting:
		crosshair.show_keycap("升级水枪")
	else:
		crosshair.show_dot()


## 面板开着时的每帧更新：算准星扫到哪一行、高亮它、把「按 E 会发生什么」写在准星下面。
func _update_panel(collider: Object) -> void:
	_selected = panel.row_index_of(collider)
	panel.set_selected(_selected)
	if not is_instance_valid(crosshair):
		return
	if _selected >= 0:
		crosshair.show_keycap(_action_hint(_selected))
	else:
		crosshair.show_dot("Esc 关闭")
	if _far_from_player():
		_close_panel()


## 展开面板：喂一遍最新数值，然后接管水枪的开关。
func _open_panel() -> void:
	_refresh_panel()
	panel.open()
	panel.set_selected(-1)
	_selected = -1
	_gun_can_fire_backup = gun.can_fire if is_instance_valid(gun) else true
	if is_instance_valid(gun):
		gun.can_fire = false


## 收起面板：把水枪的开关还原成打开前的样子（别把玩家自己在检查器里关掉的开关又打开）。
func _close_panel() -> void:
	panel.close()
	_selected = -1
	if is_instance_valid(gun):
		gun.can_fire = _gun_can_fire_backup


## 买下第 index 项：先看有没有升到头、再看钱够不够，最后才真扣钱、真改数值。
func _buy(index: int) -> void:
	if not is_instance_valid(wallet) or not is_instance_valid(panel):
		return
	if _is_maxed(index):
		panel.show_message("已经升到头了", false)
		return
	if not wallet.spend(_cost(index)):
		panel.show_message("邮币不足", false)
		return
	_apply_upgrade(index)
	panel.show_message("升级成功", true)
	_refresh_panel()


## 真的把数值改上去。改的是水块容器 / 水枪上那两处唯一的定义，本脚本不另存一份。
func _apply_upgrade(index: int) -> void:
	if index == Upgrade.SPEED:
		field.muzzle_speed = minf(field.muzzle_speed + speed_step, speed_max)
		_speed_level += 1
		return
	gun.blob_size = minf(gun.blob_size + size_step, size_max)
	_size_level += 1


## 把两行选项和邮币数重新算一遍塞进面板。买完、钱变了、刚开局都要跑一次。
func _refresh_panel() -> void:
	if not is_instance_valid(panel):
		return
	panel.update_row(Upgrade.SPEED, _row_text(Upgrade.SPEED), _row_price_text(Upgrade.SPEED), _row_state(Upgrade.SPEED))
	panel.update_row(Upgrade.SIZE, _row_text(Upgrade.SIZE), _row_price_text(Upgrade.SIZE), _row_state(Upgrade.SIZE))
	if is_instance_valid(wallet):
		panel.set_money(wallet.amount)


## 钱一变就刷新 —— 面板正开着的时候（比如别处也花钱），价格的颜色要跟着变。
func _on_money_changed(_amount: int) -> void:
	_refresh_panel()


## 从摄像机正中心朝前打一条射线，返回打到的东西；没打到返回 null。
## 射线上同时挂着「可交互」和「世界」两层：世界层是用来挡视线的（隔墙不给提示）。
## 水块和吸水区在别的层上，所以水从眼前飞过不会把提示打断。
func _aimed_object() -> Object:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return null
	var from: Vector3 = cam.global_position
	var to: Vector3 = from - cam.global_basis.z * interact_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, ray_mask)
	# 面板两行的「选中区」是 Area3D，而射线默认只打刚体 —— 不打开这个开关，
	# 准星永远扫不到选项，表现是"面板能开、但选不中任何一行"。
	query.collide_with_areas = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	return collider


## 玩家是不是已经走远了（面板该收起来了）。
func _far_from_player() -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return false
	return cam.global_position.distance_to(global_position) > close_distance


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


## 一行里左边那句说明：「现在多少 → 买完多少」；到顶了就只写现在多少。
func _row_text(index: int) -> String:
	if index == Upgrade.SPEED:
		if not is_instance_valid(field):
			return "出水速度  ——"
		if _is_maxed(index):
			return "出水速度  %.1f m/s（已满）" % field.muzzle_speed
		return "出水速度  %.1f → %.1f m/s" % [field.muzzle_speed, minf(field.muzzle_speed + speed_step, speed_max)]
	if not is_instance_valid(gun):
		return "水块大小  ——"
	if _is_maxed(index):
		return "水块大小  %.2f m（已满）" % gun.blob_size
	return "水块大小  %.2f → %.2f m" % [gun.blob_size, minf(gun.blob_size + size_step, size_max)]


## 一行里右边的价格。
func _row_price_text(index: int) -> String:
	return "已满级" if _is_maxed(index) else "%d 枚" % _cost(index)


## 这一行现在的状态，决定价格字的颜色。
func _row_state(index: int) -> UpgradeRow.State:
	if _is_maxed(index):
		return UpgradeRow.State.MAX
	if not is_instance_valid(wallet) or not wallet.can_afford(_cost(index)):
		return UpgradeRow.State.POOR
	return UpgradeRow.State.OK


## 准星下面那行字：告诉玩家「现在按 E 会发生什么」。
func _action_hint(index: int) -> String:
	match _row_state(index):
		UpgradeRow.State.MAX:
			return "已满级"
		UpgradeRow.State.POOR:
			return "E 升级 · 邮币不足"
		_:
			return "E 升级 · %d 枚" % _cost(index)
