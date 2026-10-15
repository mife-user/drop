extends Node3D
class_name InteractStation

## 可交互台座：**「看着它 → 提示按 E → 弹出菜单 → 瞄准选 → 左键确认」这整套显示与流程都在这儿**。
## 具体某个物体卖什么、点了之后发生什么，由子类覆盖下面几个函数来定。
##
## 子类至少写这 4 个：
##   row_count()              菜单有几行
##   row_text(index)          第 index 行左边那句
##   row_price_text(index)    第 index 行右边那个价格
##   on_row_activated(index)  左键点了这一行之后干什么
## 想更细还可以覆盖：
##   row_state(index)         能不能选（选不了标红、做完了变灰）
##   panel_footer()           菜单底部那行（比如「邮币 x 3」），默认不显示
##   panel_title()            想让标题跟着状态变时才覆盖；不覆盖就用场景里「标题」上写的字
##   on_menu_opened() / on_menu_closed()   菜单开关时要做的事（比如把自己的武器关掉）
##
## **行就是菜单面板下的「交互选项行」子节点**，从上到下 = 第 0、1、2 行。
## 想加一行：在面板里再实例一个「交互选项行」，子类里多返回一行字，这里一行代码都不用改。
##
## 按 E 打开菜单时会同时做三件事：锁住玩家走动和跳跃、把视角限制在朝面板 ±look_range 度的
## 锥形里（免得一转开就找不到菜单）、把准星下面那行提示清掉（免得挡着选项）。
## **菜单里左键确认**，点右上角的 × 或再按一次 E 关闭 —— 特意不用 Esc：
## 那个键在 player.gd 里是「放开鼠标」，会把光标放出来打断操作。
##
## 「看着它」的判定：从摄像机中心朝前打一条射线，射线同时挂「可交互」层和「世界」层，
## 世界层是用来挡视线的 —— 隔着墙就不弹提示。物体自己要落在「可交互」层上（见 body）。
##
## 想做一个新物体：复制 scenes/交互台.tscn，换个模型，根节点换成你的子类脚本，
## 再把 crosshair / player / panel / body 四根线接上就行。

## —— 通用话术。每个字都能在检查器里改，代码里不存第二份 ——
@export_group("话术")
## 菜单**没开**、准星对着它时，准星下面那行字。
## 菜单开着时准星下面不写任何字（避免挡着选项），只剩下高亮和 × 作反馈。
@export var prompt_text: String = "按 E 交互"
## 选不了（钱不够 / 条件不满足）时那行字，也是子类弹提示时的默认文案。
@export var text_blocked: String = "条件不满足"
## 已经做完了时那行字。
@export var text_done: String = "已经完成"
## 成功时的默认文案。
@export var text_success: String = "操作成功"

@export_group("接线")
## 屏幕中心的准星（HUD 里那份）。
@export var crosshair: InteractCrosshair
## 主人公。菜单打开时要锁住他的移动和视角。
@export var player: Player
## 本物体自己的菜单面板（本场景里的子节点）。
@export var panel: InteractPanel
## 自己的碰撞体：准星打到它 = 玩家正对着这个物体，才允许交互。
@export var body: CollisionObject3D

@export_group("交互")
## 隔多远还能交互（米）。射程之外不弹提示。
@export_range(0.5, 10.0, 0.1) var interact_distance: float = 3.0
## 交互射线查哪些层。默认「世界(1) + 可交互(5)」。
@export_flags_3d_physics var ray_mask: int = 17
## 走开多远自动收起菜单（米）。
@export_range(1.0, 20.0, 0.5) var close_distance: float = 4.5
## 菜单开着时把玩家锁住（不许走、不许跳）。
@export var lock_player: bool = true
## 菜单开着时视角能偏离面板方向多少度（上下左右同一个值）。填 0 = 完全锁死。
@export_range(0.0, 90.0, 1.0) var look_range: float = 35.0

## 按哪个键开菜单。
const INTERACT_ACTION: StringName = &"interact"
## 用哪个动作确认。默认是鼠标左键 —— 和开火绑同一个键是正常的：
## 菜单开着时子类会把武器关掉，不会两边同时触发。
const SELECT_ACTION: StringName = &"select"

var _targeting: bool = false              # 准星这会儿是不是正对着自己
var _hit: int = InteractPanel.HIT_NONE    # 菜单里准星扫到的东西


func _ready() -> void:
	if is_instance_valid(panel):
		panel.close()   # 开机先把菜单收起来（场景里是亮着的，方便你在编辑器里摆）
	refresh_rows()
	if not InputMap.has_action(INTERACT_ACTION):
		push_warning("交互台：项目设置里没有「%s」这个输入动作，按 E 不会有反应" % INTERACT_ACTION)
	if not InputMap.has_action(SELECT_ACTION):
		push_warning("交互台：项目设置里没有「%s」这个输入动作，左键选不了" % SELECT_ACTION)


func _physics_process(_delta: float) -> void:
	var collider: Object = _aimed_object()
	_targeting = is_instance_valid(body) and collider == body
	if is_instance_valid(panel) and panel.is_open():
		_update_menu(collider)
	else:
		_update_prompt()


## E 开关菜单，左键确认。用事件（_unhandled_input）而不是每帧问 Input，是为了「按一下只算一次」。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(INTERACT_ACTION):
		get_viewport().set_input_as_handled()
		if is_instance_valid(panel) and panel.is_open():
			close_menu()
		elif _targeting:
			open_menu()
		return
	if event.is_action_pressed(SELECT_ACTION) and is_instance_valid(panel) and panel.is_open():
		get_viewport().set_input_as_handled()
		_activate(_hit)


## 展开菜单：先把行算好，再开面板、锁玩家。
func open_menu() -> void:
	if not is_instance_valid(panel) or panel.is_open():
		return
	refresh_rows()
	panel.open()
	_hit = InteractPanel.HIT_NONE
	_lock_player()
	on_menu_opened()


## 收起菜单：解锁玩家、还原现场。
func close_menu() -> void:
	if not is_instance_valid(panel) or not panel.is_open():
		return
	panel.close()
	_hit = InteractPanel.HIT_NONE
	_unlock_player()
	on_menu_closed()


## 把所有行重算一遍塞进面板（开菜单、买完、钱变了都要调）。
## 子类只要实现 row_text / row_price_text / row_state，这里自动按行数铺开。
func refresh_rows() -> void:
	if not is_instance_valid(panel):
		return
	var count: int = row_count()
	panel.set_row_count(count)
	var title: String = panel_title()
	if not title.is_empty():
		panel.set_title(title)
	panel.set_footer(panel_footer())
	for index: int in count:
		panel.update_row(index, row_text(index), row_price_text(index), row_state(index))


## 在菜单中间弹一句提示（子类里买完东西时调）。
func show_message(text: String, ok: bool) -> void:
	if is_instance_valid(panel):
		panel.show_message(text, ok)


# —— 下面这些是给子类覆盖的 ——


## 菜单有几行。默认 0 行（等于没东西可卖）。
func row_count() -> int:
	return 0


## 第 index 行左边那句说明。
func row_text(_index: int) -> String:
	return ""


## 第 index 行右边的价格。
func row_price_text(_index: int) -> String:
	return ""


## 第 index 行现在能不能选。
func row_state(_index: int) -> InteractOptionRow.State:
	return InteractOptionRow.State.OK


## 左键点了第 index 行之后干什么（扣钱、改数值、弹提示，都在这儿）。
func on_row_activated(_index: int) -> void:
	pass


## 菜单底部那行字（比如「邮币 x 3」）；返回空字符串就不显示。
func panel_footer() -> String:
	return ""


## 菜单标题。**返回空字符串 = 用场景里「标题」上写的字**，一般不用覆盖；
## 只有想让标题跟着状态变（比如「升级水枪 Lv.3」）时才需要。
func panel_title() -> String:
	return ""


## 菜单刚打开时调一次。
func on_menu_opened() -> void:
	pass


## 菜单收起时调一次。
func on_menu_closed() -> void:
	pass


## 菜单没开时的每帧更新：正对着就提示按 E，否则把提示清掉。
func _update_prompt() -> void:
	if is_instance_valid(crosshair):
		crosshair.set_hint(prompt_text if _targeting else "")


## 菜单开着时的每帧更新：算准星扫到哪一项、高亮它。
## **准星下面不写任何提示文字** —— 菜单里靠「哪一行亮着」和右上角的 × 反馈就够了，
## 再多一行字反而挡着选项。想让玩家看到「左键 升级 · 3 枚」这类字，
## 在这里加一句 crosshair.set_hint(...) 就接回来了。
func _update_menu(collider: Object) -> void:
	_hit = panel.hit_test(collider)
	panel.set_hit(_hit)
	if is_instance_valid(crosshair):
		crosshair.set_hint("")
	if _far_from_player():
		close_menu()


## 左键按下时：扫到 × 就关，扫到某项就让子类去处理，处理完重算一遍行。
func _activate(hit: int) -> void:
	if hit == InteractPanel.HIT_CLOSE:
		close_menu()
		return
	if hit < 0:
		return
	on_row_activated(hit)
	refresh_rows()


## 锁住玩家：不许走、不许跳，视角也只能在面板方向附近转。
func _lock_player() -> void:
	if not is_instance_valid(player):
		return
	if lock_player:
		player.set_move_lock(true)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if is_instance_valid(panel) and cam != null:
		player.lock_look(panel.global_position - cam.global_position, look_range)


## 解锁。
func _unlock_player() -> void:
	if not is_instance_valid(player):
		return
	player.set_move_lock(false)
	player.unlock_look()


## 从摄像机正中心朝前打一条射线，返回打到的东西；没打到返回 null。
## 水块和吸水区在别的层上，所以水从眼前飞过不会把提示打断。
func _aimed_object() -> Object:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return null
	var from: Vector3 = cam.global_position
	var to: Vector3 = from - cam.global_basis.z * interact_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, ray_mask)
	# 菜单的选项和 × 都是 Area3D，而射线默认只打刚体 —— 不打开这个开关，永远选不中
	query.collide_with_areas = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	return collider


## 玩家是不是已经走远了（菜单该收起来了）。
func _far_from_player() -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return false
	return cam.global_position.distance_to(global_position) > close_distance
